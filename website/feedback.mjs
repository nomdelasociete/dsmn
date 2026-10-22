import { randomUUID } from 'node:crypto';
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import pg from 'pg';
import { createMaintenance, createSerialQueue, PRUNE_INTERVAL_MS } from './maintenance.mjs';
import {
  FEEDBACK_BODY_LIMIT_BYTES,
  createFeedbackRateLimiter,
  feedbackClientKey,
  normalizeFeedbackSubmission
} from './site-logic.mjs';

export { FEEDBACK_BODY_LIMIT_BYTES, createFeedbackRateLimiter, feedbackClientKey, normalizeFeedbackSubmission };

const { Pool } = pg;

const FEEDBACK_RETENTION_DAYS = parseRetentionDays(process.env.DSMN_FEEDBACK_RETENTION_DAYS, 730);

export function createFeedbackStore() {
  const databaseUrl = process.env.DATABASE_URL;
  const filePath = process.env.DSMN_FEEDBACK_FILE ?? join(process.cwd(), '.feedback', 'messages.jsonl');
  const pool = databaseUrl ? new Pool({ connectionString: databaseUrl }) : null;
  const rateLimiter = createFeedbackRateLimiter();
  const fileQueue = createSerialQueue();
  const ensureDatabase = createMaintenance(setupDatabase);
  const pruneDatabaseOnce = createMaintenance(pruneDatabase, { intervalMs: PRUNE_INTERVAL_MS });
  const pruneFileOnce = createMaintenance(pruneFile, { intervalMs: PRUNE_INTERVAL_MS });

  async function setupDatabase() {
    if (!pool) return;
    await pool.query(`
      create table if not exists feedback_messages (
        id bigserial primary key,
        created_at timestamptz not null default now(),
        category text not null,
        message text not null,
        email text,
        app_version text,
        build_number text,
        os_version text,
        diagnostics jsonb not null default '{}'::jsonb,
        user_agent text,
        session_id text
      );

      create index if not exists feedback_messages_created_at_idx
        on feedback_messages (created_at desc);

      create index if not exists feedback_messages_category_idx
        on feedback_messages (category);
    `);
  }

  async function submit(payload, request, sessionId) {
    const clientKey = feedbackClientKey(request);
    if (!rateLimiter.allow(clientKey)) {
      const error = new Error('Too many feedback submissions.');
      error.statusCode = 429;
      throw error;
    }

    const feedback = normalizeFeedbackSubmission(payload, request, sessionId);

    if (pool) {
      await ensureDatabase();
      await pruneDatabaseOnce();
      const result = await pool.query(
        `
          insert into feedback_messages
            (category, message, email, app_version, build_number, os_version, diagnostics, user_agent, session_id)
          values
            ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9)
          returning id, created_at
        `,
        [
          feedback.category,
          feedback.message,
          feedback.email ?? null,
          feedback.appVersion ?? null,
          feedback.buildNumber ?? null,
          feedback.osVersion ?? null,
          JSON.stringify(feedback.diagnostics),
          feedback.userAgent ?? null,
          feedback.sessionId ?? null
        ]
      );

      return {
        id: result.rows[0]?.id,
        createdAt: result.rows[0]?.created_at
      };
    }

    return fileQueue(async () => {
      await pruneFileOnce();
      await mkdir(dirname(filePath), { recursive: true });
      const fallbackRecord = {
        ...feedback,
        id: randomUUID(),
        createdAt: new Date().toISOString()
      };
      await appendFile(filePath, `${JSON.stringify(fallbackRecord)}\n`);
      return { id: fallbackRecord.id, createdAt: fallbackRecord.createdAt };
    });
  }

  async function listRecent(limit = 50) {
    const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);

    if (pool) {
      await ensureDatabase();
      await pruneDatabaseOnce();
      const result = await pool.query(
        `
          select
            id,
            created_at,
            category,
            message,
            email,
            app_version,
            build_number,
            os_version,
            diagnostics,
            user_agent,
            session_id
          from feedback_messages
          order by created_at desc
          limit $1
        `,
        [safeLimit]
      );

      return {
        generatedAt: new Date().toISOString(),
        storage: 'postgres',
        messages: result.rows.map((row) => ({
          id: row.id,
          createdAt: row.created_at,
          category: row.category,
          message: row.message,
          email: row.email,
          appVersion: row.app_version,
          buildNumber: row.build_number,
          osVersion: row.os_version,
          diagnostics: row.diagnostics ?? {},
          userAgent: row.user_agent,
          sessionId: row.session_id
        }))
      };
    }

    return fileQueue(async () => {
      await pruneFileOnce();
      const contents = await readFile(filePath, 'utf8').catch((error) => {
        if (error.code === 'ENOENT') return '';
        throw error;
      });
      const messages = contents
        .split('\n')
        .filter(Boolean)
        .flatMap((line) => {
          try {
            return [JSON.parse(line)];
          } catch {
            return [];
          }
        })
        .slice(-safeLimit)
        .reverse();

      return {
        generatedAt: new Date().toISOString(),
        storage: 'file',
        messages
      };
    });
  }

  return {
    listRecent,
    submit
  };

  async function pruneDatabase() {
    if (!pool) return;
    await pool.query(
      `delete from feedback_messages where created_at < now() - ($1::int * interval '1 day')`,
      [FEEDBACK_RETENTION_DAYS]
    );
  }

  async function pruneFile() {
    if (pool) return;
    await pruneJsonlFile(filePath, 'createdAt', FEEDBACK_RETENTION_DAYS);
  }
}

function parseRetentionDays(value, fallback) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return fallback;
  return parsed;
}

async function pruneJsonlFile(filePath, timestampField, retentionDays) {
  const contents = await readFile(filePath, 'utf8').catch((error) => {
    if (error.code === 'ENOENT') return '';
    throw error;
  });
  if (!contents) return;

  const cutoff = Date.now() - retentionDays * 24 * 60 * 60 * 1000;
  const lines = contents.split('\n').filter(Boolean);
  const retained = lines.filter((line) => {
    try {
      const timestamp = Date.parse(JSON.parse(line)?.[timestampField] ?? '');
      return !Number.isFinite(timestamp) || timestamp >= cutoff;
    } catch {
      return false;
    }
  });

  if (retained.length === lines.length) return;
  await writeFile(filePath, retained.length ? `${retained.join('\n')}\n` : '');
}
