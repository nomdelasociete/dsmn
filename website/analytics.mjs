import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import pg from 'pg';
import { createHash, timingSafeEqual } from 'node:crypto';
import { createMaintenance, createSerialQueue, PRUNE_INTERVAL_MS } from './maintenance.mjs';
import { classifyDownloadKind, normalizeClientEvent, normalizeEvent, summarizeEvents } from './site-logic.mjs';

export { classifyDownloadKind, normalizeClientEvent };

const { Pool } = pg;

const MAX_BODY_BYTES = 4096;
const ANALYTICS_RETENTION_DAYS = parseRetentionDays(process.env.DSMN_ANALYTICS_RETENTION_DAYS, 395);

export function createAnalytics() {
  const databaseUrl = process.env.DATABASE_URL;
  const filePath = process.env.DSMN_ANALYTICS_FILE ?? join(process.cwd(), '.analytics', 'events.jsonl');
  const storage = databaseUrl ? 'postgres' : 'file';
  const pool = databaseUrl ? new Pool({ connectionString: databaseUrl }) : null;
  const fileQueue = createSerialQueue();
  const ensureDatabase = createMaintenance(setupDatabase);
  const pruneDatabaseOnce = createMaintenance(pruneDatabase, { intervalMs: PRUNE_INTERVAL_MS });
  const pruneFileOnce = createMaintenance(pruneFile, { intervalMs: PRUNE_INTERVAL_MS });

  async function setupDatabase() {
    if (!pool) return;
    await pool.query(`
      create table if not exists analytics_events (
        id bigserial primary key,
        occurred_at timestamptz not null default now(),
        event_name text not null,
        path text,
        asset text,
        referrer text,
        session_id text,
        metadata jsonb not null default '{}'::jsonb
      );

      create index if not exists analytics_events_occurred_at_idx
        on analytics_events (occurred_at desc);

      create index if not exists analytics_events_event_name_idx
        on analytics_events (event_name);
    `);
  }

  async function record(input) {
    const event = normalizeEvent(input);
    if (!event?.eventName) return;

    try {
      if (pool) {
        await ensureDatabase();
        await pruneDatabaseOnce();
        await pool.query(
          `
            insert into analytics_events
              (event_name, path, asset, referrer, session_id, metadata)
            values
              ($1, $2, $3, $4, $5, $6::jsonb)
          `,
          [
            event.eventName,
            event.path ?? null,
            event.asset ?? null,
            event.referrer ?? null,
            event.sessionId ?? null,
            JSON.stringify(event.metadata ?? {})
          ]
        );
        return;
      }

      await fileQueue(async () => {
        await pruneFileOnce();
        await mkdir(dirname(filePath), { recursive: true });
        await appendFile(filePath, `${JSON.stringify({ ...event, occurredAt: new Date().toISOString() })}\n`);
      });
    } catch (error) {
      console.error('analytics record failed', error);
    }
  }

  async function metrics() {
    if (pool) {
      await ensureDatabase();
      await pruneDatabaseOnce();
      return databaseMetrics(pool);
    }

    return fileQueue(async () => {
      await pruneFileOnce();
      return fileMetrics(filePath);
    });
  }

  async function pruneDatabase() {
    if (!pool) return;
    await pool.query(
      `delete from analytics_events where occurred_at < now() - ($1::int * interval '1 day')`,
      [ANALYTICS_RETENTION_DAYS]
    );
  }

  async function pruneFile() {
    if (storage !== 'file') return;
    await pruneJsonlFile(filePath, 'occurredAt', ANALYTICS_RETENTION_DAYS);
  }

  function session() {
    return { id: undefined };
  }

  return {
    authorizeMetrics: authorizeMetricsRequest,
    metrics,
    record,
    session,
    storage
  };
}

export async function readJsonBody(request, maxBodyBytes = MAX_BODY_BYTES) {
  const chunks = [];
  let bytes = 0;

  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > maxBodyBytes) {
      const error = new Error('Request body too large.');
      error.statusCode = 413;
      throw error;
    }
    chunks.push(Buffer.from(chunk));
  }

  if (bytes === 0) return {};

  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    const error = new Error('Invalid JSON.');
    error.statusCode = 400;
    throw error;
  }
}


function authorizeMetricsRequest(headers) {
  const expectedToken = process.env.DSMN_METRICS_TOKEN;
  if (!expectedToken) return false;

  const authorization = headers.authorization ?? '';
  const bearer = authorization.startsWith('Bearer ') ? authorization.slice('Bearer '.length).trim() : '';

  if (!bearer) return false;
  const digest = (value) => createHash('sha256').update(value).digest();
  return timingSafeEqual(digest(bearer), digest(expectedToken));
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

async function databaseMetrics(pool) {
  const [totals, last24h, byDay, topDownloads] = await Promise.all([
    pool.query(summaryQuery()),
    pool.query(`${summaryQuery()} where occurred_at >= now() - interval '24 hours'`),
    pool.query(`
      select
        to_char(date_trunc('day', occurred_at), 'YYYY-MM-DD') as date,
        ${summaryColumns()}
      from analytics_events
      where occurred_at >= now() - interval '30 days'
      group by 1
      order by 1 desc
    `),
    pool.query(`
      select
        coalesce(asset, 'unknown') as asset,
        ${downloadKindSql()} as download_kind,
        count(*)::int as downloads
      from analytics_events
      where event_name = 'download'
      group by 1, 2
      order by downloads desc
      limit 10
    `)
  ]);

  return {
    generatedAt: new Date().toISOString(),
    storage: 'postgres',
    totals: normalizeSummary(totals.rows[0]),
    last24h: normalizeSummary(last24h.rows[0]),
    byDay: byDay.rows.map((row) => ({ date: row.date, ...normalizeSummary(row) })),
    topDownloads: topDownloads.rows.map((row) => ({
      asset: row.asset,
      downloadKind: row.download_kind,
      downloads: Number(row.downloads ?? 0)
    }))
  };
}

async function fileMetrics(filePath) {
  const contents = await readFile(filePath, 'utf8').catch((error) => {
    if (error.code === 'ENOENT') return '';
    throw error;
  });
  const events = contents
    .split('\n')
    .filter(Boolean)
    .flatMap((line) => {
      try {
        return [JSON.parse(line)];
      } catch {
        return [];
      }
    });

  return summarizeEvents(events, 'file');
}

function summaryQuery() {
  return `
    select ${summaryColumns()}
    from analytics_events
  `;
}

function summaryColumns() {
  const downloadKind = downloadKindSql();
  return `
    count(*) filter (where event_name = 'page_view')::int as page_views,
    count(distinct session_id) filter (where event_name = 'page_view' and session_id is not null)::int as visits,
    count(*) filter (where event_name = 'download')::int as downloads,
    count(*) filter (where event_name = 'download' and ${downloadKind} = 'site_dmg')::int as site_downloads,
    count(*) filter (where event_name = 'download' and ${downloadKind} = 'sparkle_update_zip')::int as update_downloads,
    count(*) filter (where event_name = 'download' and ${downloadKind} = 'direct_zip')::int as direct_downloads,
    count(*) filter (where event_name = 'download' and ${downloadKind} = 'unknown')::int as unknown_downloads,
    count(*) filter (where event_name = 'download_click')::int as download_clicks,
    count(*) filter (where event_name = 'appcast_request')::int as appcast_requests
  `;
}

function downloadKindSql() {
  return `
    case
      when metadata->>'downloadKind' in ('site_dmg', 'sparkle_update_zip', 'direct_zip', 'unknown')
        then metadata->>'downloadKind'
      when asset like '%.dmg'
        then 'site_dmg'
      when asset ~* '^dsmn-[0-9]+(\\.[0-9]+){1,2}-[0-9]+\\.zip$'
        then 'sparkle_update_zip'
      when asset like '%.zip'
        then 'direct_zip'
      else 'unknown'
    end
  `;
}

function normalizeSummary(row = {}) {
  return {
    page_views: Number(row.page_views ?? 0),
    visits: Number(row.visits ?? 0),
    downloads: Number(row.downloads ?? 0),
    site_downloads: Number(row.site_downloads ?? 0),
    update_downloads: Number(row.update_downloads ?? 0),
    direct_downloads: Number(row.direct_downloads ?? 0),
    unknown_downloads: Number(row.unknown_downloads ?? 0),
    download_clicks: Number(row.download_clicks ?? 0),
    appcast_requests: Number(row.appcast_requests ?? 0)
  };
}

