export const FEEDBACK_BODY_LIMIT_BYTES = 8192;

const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const RATE_LIMIT_MAX_REQUESTS = 5;
const allowedCategories = new Set(['bug', 'idea', 'question', 'other']);
const allowedClientEvents = new Set(['page_view', 'download_click']);
const downloadKinds = new Set(['site_dmg', 'sparkle_update_zip', 'direct_zip', 'unknown']);

export function normalizeClientEvent(payload, request, sessionId) {
  const eventName = clean(payload?.event ?? payload?.eventName, 64);
  if (!allowedClientEvents.has(eventName)) return null;

  return normalizeEvent({
    eventName,
    path: cleanPath(payload?.path),
    asset: clean(payload?.asset, 200),
    referrer: clean(payload?.referrer ?? headerValue(request, 'referer'), 500),
    sessionId,
    metadata: safeMetadata(payload?.metadata)
  });
}

export function normalizeEvent(input) {
  const eventName = clean(input?.eventName ?? input?.event, 64);
  if (!eventName) return null;

  return {
    eventName,
    path: cleanPath(input?.path),
    asset: clean(input?.asset, 200),
    referrer: clean(input?.referrer, 500),
    sessionId: isSessionId(input?.sessionId) ? input.sessionId : undefined,
    metadata: safeMetadata(input?.metadata)
  };
}

export function classifyDownloadKind(asset) {
  const name = clean(asset, 200) ?? '';
  if (name.endsWith('.dmg')) return 'site_dmg';
  if (/^dsmn-\d+(?:\.\d+){1,2}-\d+\.zip$/i.test(name)) return 'sparkle_update_zip';
  if (name.endsWith('.zip')) return 'direct_zip';
  return 'unknown';
}

export function summarizeEvents(events, storage) {
  const since = Date.now() - 24 * 60 * 60 * 1000;
  const last24h = events.filter((event) => Date.parse(event.occurredAt ?? '') >= since);
  const byDay = new Map();
  const topDownloads = new Map();

  for (const event of events) {
    const timestamp = Date.parse(event.occurredAt ?? '');
    if (Number.isFinite(timestamp)) {
      const date = new Date(timestamp).toISOString().slice(0, 10);
      const bucket = byDay.get(date) ?? [];
      bucket.push(event);
      byDay.set(date, bucket);
    }

    if (event.eventName === 'download') {
      const asset = event.asset ?? 'unknown';
      const downloadKind = downloadKindForEvent(event);
      const key = JSON.stringify([asset, downloadKind]);
      topDownloads.set(key, (topDownloads.get(key) ?? 0) + 1);
    }
  }

  return {
    generatedAt: new Date().toISOString(),
    storage,
    totals: summarizeBucket(events),
    last24h: summarizeBucket(last24h),
    byDay: [...byDay.entries()]
      .sort(([left], [right]) => right.localeCompare(left))
      .slice(0, 30)
      .map(([date, bucket]) => ({ date, ...summarizeBucket(bucket) })),
    topDownloads: [...topDownloads.entries()]
      .sort((left, right) => right[1] - left[1])
      .slice(0, 10)
      .map(([key, downloads]) => {
        const [asset, downloadKind] = JSON.parse(key);
        return { asset, downloadKind, downloads };
      })
  };
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
    userAgent: clean(headerValue(request, 'user-agent'), 500),
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
  // Only x-real-ip selects a rate-limit bucket. The Worker copies
  // cf-connecting-ip into that header. Other forwarding headers can be spoofed.
  const clientIp = firstHeaderValue(headerValue(request, 'x-real-ip') ?? headers['x-real-ip']);
  return clientIp ?? request?.socket?.remoteAddress ?? 'unknown';
}

function headerValue(request, name) {
  const headers = request?.headers;
  if (!headers) return undefined;
  if (typeof headers.get === 'function') return headers.get(name) ?? undefined;
  return headers[name];
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

function cleanPath(value) {
  const path = clean(value, 300);
  if (!path) return undefined;
  if (path.startsWith('/')) return path;

  try {
    const parsed = new URL(path);
    return `${parsed.pathname}${parsed.search}`.slice(0, 300);
  } catch {
    return undefined;
  }
}

function safeMetadata(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};

  return Object.fromEntries(
    Object.entries(value)
      .slice(0, 20)
      .flatMap(([key, entry]) => {
        const safeKey = clean(key, 60);
        if (!safeKey) return [];
        if (typeof entry === 'string') return [[safeKey, entry.slice(0, 200)]];
        if (typeof entry === 'boolean') return [[safeKey, entry]];
        if (typeof entry === 'number' && Number.isFinite(entry)) return [[safeKey, entry]];
        return [];
      })
  );
}

function downloadKindForEvent(event) {
  const explicitKind = clean(event?.metadata?.downloadKind, 64);
  if (downloadKinds.has(explicitKind)) return explicitKind;
  return classifyDownloadKind(event?.asset);
}

function summarizeBucket(events) {
  const downloadEvents = events.filter((event) => event.eventName === 'download');

  return {
    page_views: countEvents(events, 'page_view'),
    visits: new Set(events.filter((event) => event.eventName === 'page_view').map((event) => event.sessionId).filter(Boolean)).size,
    downloads: downloadEvents.length,
    site_downloads: countDownloadKind(downloadEvents, 'site_dmg'),
    update_downloads: countDownloadKind(downloadEvents, 'sparkle_update_zip'),
    direct_downloads: countDownloadKind(downloadEvents, 'direct_zip'),
    unknown_downloads: countDownloadKind(downloadEvents, 'unknown'),
    download_clicks: countEvents(events, 'download_click'),
    appcast_requests: countEvents(events, 'appcast_request')
  };
}

function countEvents(events, eventName) {
  return events.filter((event) => event.eventName === eventName).length;
}

function countDownloadKind(events, downloadKind) {
  return events.filter((event) => downloadKindForEvent(event) === downloadKind).length;
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
