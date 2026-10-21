import { randomUUID } from 'node:crypto';
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import pg from 'pg';
import { createMaintenance, createSerialQueue, PRUNE_INTERVAL_MS } from './maintenance.mjs';

const { Pool } = pg;

export const FEEDBACK_BODY_LIMIT_BYTES = 8192;

const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const RATE_LIMIT_MAX_REQUESTS = 5;
const FEEDBACK_RETENTION_DAYS = parseRetentionDays(process.env.DSMN_FEEDBACK_RETENTION_DAYS, 730);
const allowedCategories = new Set(['bug', 'idea', 'question', 'other']);

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

export function normalizeFeedbackSubmission(payload, request, sessionId) {
  const category = clean(payload?.category, 32) ?? 'other';
  const message = clean(payload?.message, 4000);
  const email = clean(payload?.email, 254);
  const appVersion = clean(payload?.appVersion, 40);
  const buildNumber = clean(payload?.buildNumber, 40);
  const osVersion = clean(payload?.osVersion, 120);

  if (!message || message.length < 5) {
    const error = new Error('Feedback message is too short.');
    error.statusCode = 422;
    throw error;
  }

  if (email && !isEmail(email)) {
    const error = new Error('Invalid feedback email.');
    error.statusCode = 422;
    throw error;
  }

  return {
    category: allowedCategories.has(category) ? category : 'other',
    message,
    email,
    appVersion,
    buildNumber,
    osVersion,
    diagnostics: safeDiagnostics(payload?.diagnostics),
    userAgent: clean(request?.headers?.['user-agent'], 500),
    sessionId: isSessionId(sessionId) ? sessionId : undefined
  };
}

export function createFeedbackRateLimiter({
  maxRequests = RATE_LIMIT_MAX_REQUESTS,
  windowMs = RATE_LIMIT_WINDOW_MS,
  now = () => Date.now()
} = {}) {
  const buckets = new Map();

  function allow(key) {
    const safeKey = key || 'unknown';
    const timestamp = now();
    const bucket = buckets.get(safeKey) ?? [];
    const active = bucket.filter((entry) => timestamp - entry < windowMs);

    if (active.length >= maxRequests) {
      buckets.set(safeKey, active);
      return false;
    }

    active.push(timestamp);
    buckets.set(safeKey, active);

    if (buckets.size > 1000) {
      for (const [bucketKey, entries] of buckets) {
        const remaining = entries.filter((entry) => timestamp - entry < windowMs);
        if (remaining.length) buckets.set(bucketKey, remaining);
        else buckets.delete(bucketKey);
      }
    }

    return true;
  }

  return { allow };
}

export function feedbackClientKey(request) {
  const headers = request?.headers ?? {};
  // Railway's public ingress supplies X-Real-IP. Other forwarding headers can
  // contain client-controlled values and must not select rate-limit buckets.
  const railwayIp = firstHeaderValue(headers['x-real-ip']);
  return railwayIp ?? request?.socket?.remoteAddress ?? 'unknown';
}

function firstHeaderValue(value) {
  if (Array.isArray(value)) return firstHeaderValue(value[0]);
  if (typeof value !== 'string') return undefined;
  return value.split(',')[0]?.trim() || undefined;
}

function clean(value, maxLength) {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  return trimmed.slice(0, maxLength);
}

function isEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function isSessionId(value) {
  return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function safeDiagnostics(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};

  return Object.fromEntries(
    Object.entries(value)
      .slice(0, 20)
      .flatMap(([key, entry]) => {
        const safeKey = clean(key, 60);
        if (!safeKey) return [];
        if (typeof entry === 'string') return [[safeKey, entry.slice(0, 500)]];
        if (typeof entry === 'boolean') return [[safeKey, entry]];
        if (typeof entry === 'number' && Number.isFinite(entry)) return [[safeKey, entry]];
        return [];
      })
  );
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
