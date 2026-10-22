import {
  FEEDBACK_BODY_LIMIT_BYTES,
  classifyDownloadKind,
  createFeedbackRateLimiter,
  feedbackClientKey,
  normalizeClientEvent,
  normalizeEvent,
  normalizeFeedbackSubmission,
  summarizeEvents
} from './site-logic.mjs';

const RELEASE_PREFIX = 'updates';
const LATEST_ZIP = 'dsmn-latest.zip';
const LATEST_DMG = 'dsmn-latest.dmg';
const ANALYTICS_RETENTION_DAYS = 395;
const FEEDBACK_RETENTION_DAYS = 730;
const eventLimiter = createFeedbackRateLimiter({ maxRequests: 120 });
const feedbackLimiter = createFeedbackRateLimiter();

const contentTypes = {
  '.xml': 'application/xml; charset=utf-8',
  '.zip': 'application/zip',
  '.dmg': 'application/x-apple-diskimage'
};

export default {
  fetch(request, env) {
    return handleRequest(request, env);
  }
};

export async function handleRequest(request, env) {
  const url = new URL(request.url);
  const { pathname } = url;

  try {
    if (pathname === '/healthz') return text(200, 'ok');
    if (pathname === '/api/events') return postEvent(request, env);
    if (pathname === '/api/metrics') return getMetrics(request, env);
    if (pathname === '/api/feedback') return feedback(request, env, url);
    if (pathname === '/appcast.xml') return serveRelease(request, env, 'appcast.xml', false);
    if (pathname === '/download') return Response.redirect(new URL(`/download/${LATEST_DMG}`, url), 302);
    if (pathname.startsWith('/download/')) {
      const name = safeReleaseName(pathname.slice('/download/'.length));
      if (!name) return text(400, 'Bad download path.');
      return serveRelease(request, env, name, true);
    }
  } catch (error) {
    console.error(error);
    return text(502, 'Unable to process request.');
  }

  return env.ASSETS.fetch(request);
}

async function postEvent(request, env) {
  if (request.method !== 'POST') return text(405, 'Method not allowed.');

  const nodeReq = nodeRequest(request);
  if (!eventLimiter.allow(feedbackClientKey(nodeReq))) return json(429, { error: 'rate_limited' });

  try {
    const payload = await readJson(request, 4096);
    const event = normalizeClientEvent(payload, nodeReq, undefined);
    if (event) await recordAnalytics(env, event);
    return new Response(null, { status: 204 });
  } catch (error) {
    return text(error.statusCode ?? 400, 'Bad analytics event.');
  }
}

async function getMetrics(request, env) {
  if (!await authorized(request, env.DSMN_METRICS_TOKEN)) return text(401, 'Unauthorized.');

  await pruneAnalytics(env);
  const rows = await env.DB.prepare(`
    select event_name, path, asset, referrer, session_id, metadata, occurred_at
    from analytics_events
  `).all();
  const events = rows.results.map((row) => ({
    eventName: row.event_name,
    path: row.path,
    asset: row.asset,
    referrer: row.referrer,
    sessionId: row.session_id,
    occurredAt: row.occurred_at,
    metadata: parseJson(row.metadata)
  }));

  return json(200, summarizeEvents(events, 'd1'), { 'cache-control': 'no-cache' });
}

async function feedback(request, env, url) {
  if (request.method === 'GET') {
    if (!await authorized(request, env.DSMN_METRICS_TOKEN)) return text(401, 'Unauthorized.');

    const limit = Math.min(Math.max(Number(url.searchParams.get('limit')) || 50, 1), 100);
    await pruneFeedback(env);
    const rows = await env.DB.prepare(`
      select id, created_at, category, message, email, app_version, build_number,
             os_version, diagnostics, user_agent, session_id
      from feedback_messages
      order by created_at desc
      limit ?
    `).bind(limit).all();

    return json(200, {
      generatedAt: new Date().toISOString(),
      storage: 'd1',
      messages: rows.results.map((row) => ({
        id: row.id,
        createdAt: row.created_at,
        category: row.category,
        message: row.message,
        email: row.email,
        appVersion: row.app_version,
        buildNumber: row.build_number,
        osVersion: row.os_version,
        diagnostics: parseJson(row.diagnostics),
        userAgent: row.user_agent,
        sessionId: row.session_id
      }))
    }, { 'cache-control': 'no-cache' });
  }

  if (request.method !== 'POST') return text(405, 'Method not allowed.');

  const nodeReq = nodeRequest(request);
  try {
    if (!feedbackLimiter.allow(feedbackClientKey(nodeReq))) {
      return json(429, { ok: false, error: 'rate_limited' });
    }

    const payload = await readJson(request, FEEDBACK_BODY_LIMIT_BYTES);
    const submission = normalizeFeedbackSubmission(payload, nodeReq, undefined);
    await pruneFeedback(env);
    const result = await env.DB.prepare(`
      insert into feedback_messages
        (created_at, category, message, email, app_version, build_number, os_version, diagnostics, user_agent, session_id)
      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      new Date().toISOString(),
      submission.category,
      submission.message,
      submission.email ?? null,
      submission.appVersion ?? null,
      submission.buildNumber ?? null,
      submission.osVersion ?? null,
      JSON.stringify(submission.diagnostics),
      submission.userAgent ?? null,
      submission.sessionId ?? null
    ).run();

    return json(201, { ok: true, id: result.meta.last_row_id });
  } catch (error) {
    const statusCode = error.statusCode ?? 400;
    return json(statusCode, { ok: false, error: statusCode === 429 ? 'rate_limited' : 'invalid_feedback' });
  }
}

async function serveRelease(request, env, name, download) {
  if (!['GET', 'HEAD'].includes(request.method)) return text(405, 'Method not allowed.');

  const key = `${RELEASE_PREFIX}/${name}`;
  const object = request.method === 'HEAD'
    ? await env.RELEASES.head(key)
    : await env.RELEASES.get(key);
  if (!object) return text(404, `Release asset not found: ${name}`);

  const extension = name.slice(name.lastIndexOf('.'));
  const headers = new Headers();
  headers.set('cache-control', object.httpMetadata?.cacheControl || releaseCacheControl(name));
  headers.set('content-type', object.httpMetadata?.contentType || contentTypes[extension] || 'application/octet-stream');
  if (object.size != null) headers.set('content-length', String(object.size));
  if (object.httpEtag) headers.set('etag', object.httpEtag);
  if (download) headers.set('content-disposition', `attachment; filename="${name}"`);

  await trackRelease(request, env, name, download);
  return new Response(request.method === 'HEAD' ? null : object.body, { status: 200, headers });
}

async function trackRelease(request, env, name, download) {
  if (name === 'appcast.xml') {
    await recordAnalytics(env, normalizeEvent({
      eventName: 'appcast_request',
      path: '/appcast.xml',
      asset: name,
      metadata: { method: request.method }
    }));
    return;
  }

  if (!download || request.method !== 'GET') return;

  await recordAnalytics(env, normalizeEvent({
    eventName: 'download',
    path: `/download/${name}`,
    asset: name,
    referrer: request.headers.get('referer') ?? undefined,
    metadata: {
      downloadKind: classifyDownloadKind(name),
      latest: name === LATEST_ZIP || name === LATEST_DMG,
      latestArchive: name === LATEST_ZIP,
      latestDmg: name === LATEST_DMG
    }
  }));
}

async function recordAnalytics(env, event) {
  if (!event?.eventName) return;

  try {
    await pruneAnalytics(env);
    await env.DB.prepare(`
      insert into analytics_events
        (occurred_at, event_name, path, asset, referrer, session_id, metadata)
      values (?, ?, ?, ?, ?, ?, ?)
    `).bind(
      new Date().toISOString(),
      event.eventName,
      event.path ?? null,
      event.asset ?? null,
      event.referrer ?? null,
      event.sessionId ?? null,
      JSON.stringify(event.metadata ?? {})
    ).run();
  } catch (error) {
    console.error('analytics record failed', error);
  }
}

async function pruneAnalytics(env) {
  const cutoff = new Date(Date.now() - ANALYTICS_RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString();
  await env.DB.prepare('delete from analytics_events where occurred_at < ?').bind(cutoff).run();
}

async function pruneFeedback(env) {
  const cutoff = new Date(Date.now() - FEEDBACK_RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString();
  await env.DB.prepare('delete from feedback_messages where created_at < ?').bind(cutoff).run();
}

function nodeRequest(request) {
  return {
    headers: {
      'x-real-ip': request.headers.get('cf-connecting-ip') ?? undefined,
      'user-agent': request.headers.get('user-agent') ?? undefined,
      referer: request.headers.get('referer') ?? undefined
    }
  };
}

async function readJson(request, maxBytes) {
  const bytes = await request.arrayBuffer();
  if (bytes.byteLength > maxBytes) {
    const error = new Error('Request body too large.');
    error.statusCode = 413;
    throw error;
  }
  if (bytes.byteLength === 0) return {};

  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    const error = new Error('Invalid JSON.');
    error.statusCode = 400;
    throw error;
  }
}

async function authorized(request, token) {
  if (!token) return false;
  const header = request.headers.get('authorization') ?? '';
  const bearer = header.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : '';
  if (!bearer) return false;

  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(bearer)),
    crypto.subtle.digest('SHA-256', encoder.encode(token))
  ]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let index = 0; index < a.length; index += 1) diff |= a[index] ^ b[index];
  return diff === 0;
}

function safeReleaseName(value) {
  const name = value.split('/').pop();
  if (name !== value || !/^[A-Za-z0-9._-]+$/.test(name)) return null;
  return name;
}

function releaseCacheControl(name) {
  if (name === 'appcast.xml') return 'no-cache';
  if (name === LATEST_ZIP || name === LATEST_DMG) return 'public, max-age=300';
  return 'public, max-age=31536000, immutable';
}

function parseJson(value) {
  if (value && typeof value === 'object') return value;
  if (typeof value !== 'string' || !value) return {};
  try {
    return JSON.parse(value);
  } catch {
    return {};
  }
}

function text(status, body) {
  return new Response(body, { status, headers: { 'content-type': 'text/plain; charset=utf-8' } });
}

function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers }
  });
}
