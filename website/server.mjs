import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { basename, extname, join, normalize } from 'node:path';
import { Readable, pipeline } from 'node:stream';
import { GetObjectCommand, HeadObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { classifyDownloadKind, createAnalytics, normalizeClientEvent, readJsonBody } from './analytics.mjs';
import { createFeedbackStore, createFeedbackRateLimiter, feedbackClientKey, FEEDBACK_BODY_LIMIT_BYTES } from './feedback.mjs';

const root = join(process.cwd(), 'dist');
const port = Number(process.env.PORT ?? 3000);
const localReleaseDir = process.env.DSMN_RELEASE_DIR ?? join(root, 'updates');
const releasePrefix = normalizeReleasePrefix(process.env.DSMN_RELEASE_PREFIX ?? 'updates');
const latestArchiveName = process.env.DSMN_LATEST_ARCHIVE_NAME ?? 'dsmn-latest.zip';
const latestDmgName = process.env.DSMN_LATEST_DMG_NAME ?? 'dsmn-latest.dmg';
const fallbackLatestUrl = process.env.DSMN_LATEST_DOWNLOAD_URL ?? process.env.DSMN_DOWNLOAD_URL ?? '';
const bucketName = process.env.AWS_S3_BUCKET_NAME ?? process.env.S3_BUCKET ?? process.env.BUCKET_NAME ?? '';
const endpoint = process.env.AWS_ENDPOINT_URL ?? process.env.S3_ENDPOINT ?? undefined;
const region = process.env.AWS_DEFAULT_REGION ?? process.env.AWS_REGION ?? 'auto';
const forcePathStyle = process.env.AWS_S3_URL_STYLE === 'path';
const analytics = createAnalytics();
const feedbackStore = createFeedbackStore();
const eventLimiter = createFeedbackRateLimiter({ maxRequests: 120 });

const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.xml': 'application/xml; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.zip': 'application/zip',
  '.dmg': 'application/x-apple-diskimage'
};

let cachedS3Client;

function normalizeReleasePrefix(value) {
  return value.replace(/^\/+|\/+$/g, '');
}

function s3Client() {
  if (!bucketName) return null;
  if (!cachedS3Client) {
    cachedS3Client = new S3Client({
      endpoint,
      forcePathStyle,
      region
    });
  }

  return cachedS3Client;
}

function requestPath(url) {
  try {
    return decodeURIComponent(new URL(url, 'http://localhost').pathname);
  } catch {
    return null;
  }
}

function resolveStaticPath(pathname) {
  if (pathname === '/') return join(root, 'index.html');
  if (pathname === '/legal') return join(root, 'legal.html');
  if (pathname === '/favicon.ico') return join(root, 'favicon.png');

  const safePath = normalize(pathname).replace(/^([/\\.])+/, '');
  const candidate = join(root, safePath);

  if (existsSync(candidate) && statSync(candidate).isFile()) return candidate;
  if (existsSync(candidate) && statSync(candidate).isDirectory()) {
    const index = join(candidate, 'index.html');
    if (existsSync(index)) return index;
  }

  return null;
}

function staticCacheControl(filePath) {
  if (filePath.endsWith('index.html')) return 'no-cache';
  if (filePath.endsWith('404.html')) return 'no-cache';

  const fileName = basename(filePath);
  if (/-[A-Za-z0-9_-]{8,}\.(?:css|js|mjs|map)$/i.test(fileName)) {
    return 'public, max-age=31536000, immutable';
  }

  return 'public, max-age=0, must-revalidate';
}

function shouldServeNotFoundPage(request, pathname) {
  if (pathname.startsWith('/api/') || pathname.startsWith('/download/')) return false;

  const extension = extname(pathname);
  if (extension && extension !== '.html') return false;

  const accept = request.headers.accept ?? '';
  return !accept || accept.includes('text/html') || accept.includes('*/*');
}

function safeReleaseName(value) {
  const name = basename(value);
  if (name !== value || !/^[A-Za-z0-9._-]+$/.test(name)) return null;
  return name;
}

function releaseKey(name) {
  return releasePrefix ? `${releasePrefix}/${name}` : name;
}

function releaseCacheControl(name) {
  if (name === 'appcast.xml') return 'no-cache';
  if (name === latestArchiveName || name === latestDmgName) return 'public, max-age=300';
  return 'public, max-age=31536000, immutable';
}

function pipeBody(body, response) {
  if (!body) {
    response.end();
    return;
  }

  if (typeof body.pipe === 'function') {
    pipeline(body, response, () => {});
    return;
  }

  if (body instanceof ReadableStream) {
    pipeline(Readable.fromWeb(body), response, () => {});
    return;
  }

  pipeline(Readable.from(body), response, () => {});
}

async function serveLocalRelease(request, response, name, download, extraHeaders = {}) {
  const filePath = join(localReleaseDir, name);
  if (!existsSync(filePath) || !statSync(filePath).isFile()) return false;

  const stats = statSync(filePath);
  const headers = {
    'cache-control': releaseCacheControl(name),
    'content-length': stats.size,
    'content-type': contentTypes[extname(filePath)] ?? 'application/octet-stream',
    ...extraHeaders
  };

  if (download) headers['content-disposition'] = `attachment; filename="${name}"`;
  response.writeHead(200, headers);

  if (request.method === 'HEAD') {
    response.end();
    return true;
  }

  pipeBody(createReadStream(filePath), response);
  return true;
}

async function serveBucketRelease(request, response, name, download, extraHeaders = {}) {
  const client = s3Client();
  if (!client) return false;

  const key = releaseKey(name);

  try {
    if (request.method === 'HEAD') {
      const object = await client.send(new HeadObjectCommand({ Bucket: bucketName, Key: key }));
      const headers = {
        'cache-control': object.CacheControl ?? releaseCacheControl(name),
        'content-length': object.ContentLength ?? 0,
        'content-type': object.ContentType ?? contentTypes[extname(name)] ?? 'application/octet-stream',
        ...extraHeaders
      };
      if (object.ETag) headers.etag = object.ETag;
      if (download) headers['content-disposition'] = `attachment; filename="${name}"`;
      response.writeHead(200, headers);
      response.end();
      return true;
    }

    const object = await client.send(new GetObjectCommand({ Bucket: bucketName, Key: key }));
    const headers = {
      'cache-control': object.CacheControl ?? releaseCacheControl(name),
      'content-length': object.ContentLength ?? 0,
      'content-type': object.ContentType ?? contentTypes[extname(name)] ?? 'application/octet-stream',
      ...extraHeaders
    };
    if (object.ETag) headers.etag = object.ETag;
    if (download) headers['content-disposition'] = `attachment; filename="${name}"`;
    response.writeHead(200, headers);
    pipeBody(object.Body, response);
    return true;
  } catch (error) {
    if (error?.name === 'NoSuchKey' || error?.$metadata?.httpStatusCode === 404) return false;
    throw error;
  }
}

async function serveRelease(request, response, name, options = {}) {
  if (!['GET', 'HEAD'].includes(request.method ?? 'GET')) {
    response.writeHead(405, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Method not allowed.');
    return;
  }

  if ((name === latestArchiveName || name === latestDmgName) && fallbackLatestUrl) {
    response.writeHead(302, { location: fallbackLatestUrl });
    response.end();
    return;
  }

  const eventSession = options.download ? analytics.session(request) : { id: undefined };
  const analyticsHeaders = eventSession.setCookie ? { 'set-cookie': eventSession.setCookie } : {};

  const servedFromBucket = await serveBucketRelease(request, response, name, options.download, analyticsHeaders);
  if (servedFromBucket) {
    await trackReleaseRequest(request, name, options, eventSession.id);
    return;
  }

  const servedFromDisk = await serveLocalRelease(request, response, name, options.download, analyticsHeaders);
  if (servedFromDisk) {
    await trackReleaseRequest(request, name, options, eventSession.id);
    return;
  }

  response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
  response.end(`Release asset not found: ${name}`);
}

async function trackReleaseRequest(request, name, options, sessionId) {
  if (name === 'appcast.xml') {
    await analytics.record({
      eventName: 'appcast_request',
      path: '/appcast.xml',
      asset: name,
      metadata: { method: request.method ?? 'GET' }
    });
    return;
  }

  if (!options.download || request.method !== 'GET') return;

  await analytics.record({
    eventName: 'download',
    path: `/download/${name}`,
    asset: name,
    referrer: request.headers.referer,
    sessionId,
    metadata: {
      downloadKind: classifyDownloadKind(name),
      latest: name === latestArchiveName || name === latestDmgName,
      latestArchive: name === latestArchiveName,
      latestDmg: name === latestDmgName
    }
  });
}

function writeJson(response, statusCode, payload, headers = {}) {
  response.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    ...headers
  });
  response.end(JSON.stringify(payload));
}

createServer(async (request, response) => {
  if (!existsSync(root)) {
    response.writeHead(503, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Run `npm run build` before `npm start`.');
    return;
  }

  const pathname = requestPath(request.url ?? '/');

  if (pathname === null) {
    response.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Bad request.');
    return;
  }

  try {
    if (pathname === '/healthz') {
      response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('ok');
      return;
    }

    if (pathname === '/api/events') {
      if (request.method !== 'POST') {
        response.writeHead(405, { 'content-type': 'text/plain; charset=utf-8' });
        response.end('Method not allowed.');
        return;
      }

      if (!eventLimiter.allow(feedbackClientKey(request))) {
        writeJson(response, 429, { error: 'rate_limited' });
        return;
      }

      const eventSession = analytics.session(request);
      const responseHeaders = eventSession.setCookie ? { 'set-cookie': eventSession.setCookie } : {};

      try {
        const payload = await readJsonBody(request);
        const event = normalizeClientEvent(payload, request, eventSession.id);
        if (event) await analytics.record(event);
        response.writeHead(204, responseHeaders);
        response.end();
      } catch (error) {
        response.writeHead(error.statusCode ?? 400, {
          'content-type': 'text/plain; charset=utf-8',
          ...responseHeaders
        });
        response.end('Bad analytics event.');
      }
      return;
    }

    if (pathname === '/api/metrics') {
      if (!analytics.authorizeMetrics(request.headers)) {
        response.writeHead(401, { 'content-type': 'text/plain; charset=utf-8' });
        response.end('Unauthorized.');
        return;
      }

      const metrics = await analytics.metrics();
      writeJson(response, 200, metrics, { 'cache-control': 'no-cache' });
      return;
    }

    if (pathname === '/api/feedback') {
      if (request.method === 'GET') {
        if (!analytics.authorizeMetrics(request.headers)) {
          response.writeHead(401, { 'content-type': 'text/plain; charset=utf-8' });
          response.end('Unauthorized.');
          return;
        }

        const limit = new URL(request.url ?? '/', 'http://localhost').searchParams.get('limit');
        const messages = await feedbackStore.listRecent(limit);
        writeJson(response, 200, messages, { 'cache-control': 'no-cache' });
        return;
      }

      if (request.method !== 'POST') {
        response.writeHead(405, { 'content-type': 'text/plain; charset=utf-8' });
        response.end('Method not allowed.');
        return;
      }

      const eventSession = analytics.session(request);
      const responseHeaders = eventSession.setCookie ? { 'set-cookie': eventSession.setCookie } : {};

      try {
        const payload = await readJsonBody(request, FEEDBACK_BODY_LIMIT_BYTES);
        const result = await feedbackStore.submit(payload, request, eventSession.id);
        writeJson(response, 201, { ok: true, id: result.id }, responseHeaders);
      } catch (error) {
        writeJson(
          response,
          error.statusCode ?? 400,
          { ok: false, error: error.statusCode === 429 ? 'rate_limited' : 'invalid_feedback' },
          responseHeaders
        );
      }
      return;
    }

    if (pathname === '/appcast.xml') {
      await serveRelease(request, response, 'appcast.xml');
      return;
    }

    if (pathname === '/download') {
      response.writeHead(302, { location: `/download/${latestDmgName}` });
      response.end();
      return;
    }

    if (pathname.startsWith('/download/')) {
      const name = safeReleaseName(pathname.slice('/download/'.length));
      if (!name) {
        response.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' });
        response.end('Bad download path.');
        return;
      }

      await serveRelease(request, response, name, { download: true });
      return;
    }
  } catch (error) {
    console.error(error);
    response.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Unable to process request.');
    return;
  }

  const filePath = resolveStaticPath(pathname);
  if (!filePath || !existsSync(filePath) || !statSync(filePath).isFile()) {
    const notFoundPath = join(root, '404.html');
    if (shouldServeNotFoundPage(request, pathname) && existsSync(notFoundPath) && statSync(notFoundPath).isFile()) {
      response.writeHead(404, {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-cache'
      });
      pipeBody(createReadStream(notFoundPath), response);
      return;
    }

    response.writeHead(404, {
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'no-cache'
    });
    response.end('Not found.');
    return;
  }

  const type = contentTypes[extname(filePath)] ?? 'application/octet-stream';

  response.writeHead(200, {
    'content-type': type,
    'cache-control': staticCacheControl(filePath)
  });
  pipeBody(createReadStream(filePath), response);
}).listen(port, '0.0.0.0', () => {
  console.log(`dsmn website listening on :${port}`);
});
