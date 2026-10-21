import { createReadStream } from 'node:fs';
import { readdir, stat } from 'node:fs/promises';
import { basename, extname, join, resolve } from 'node:path';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';

const args = parseArgs(process.argv.slice(2));
const releaseDir = resolve(args.dir ?? process.env.DSMN_RELEASE_DIR ?? 'dist/updates');
const prefix = normalizePrefix(args.prefix ?? process.env.DSMN_RELEASE_PREFIX ?? 'updates');
const latestName = args.latest ?? process.env.DSMN_LATEST_ARCHIVE_NAME ?? 'dsmn-latest.zip';
const latestDmgName = args.latestDmg ?? process.env.DSMN_LATEST_DMG_NAME ?? 'dsmn-latest.dmg';
const bucketName = process.env.AWS_S3_BUCKET_NAME ?? process.env.S3_BUCKET ?? process.env.BUCKET_NAME;
const endpoint = process.env.AWS_ENDPOINT_URL ?? process.env.S3_ENDPOINT;
const region = process.env.AWS_DEFAULT_REGION ?? process.env.AWS_REGION ?? 'auto';
const forcePathStyle = process.env.AWS_S3_URL_STYLE === 'path';

if (!bucketName) {
  fail('AWS_S3_BUCKET_NAME, S3_BUCKET, or BUCKET_NAME is required.');
}

const archivePath = resolve(args.zip ?? await findArchive(releaseDir));
const dmgPath = resolve(args.dmg ?? await findDmg(releaseDir));
const appcastPath = resolve(args.appcast ?? join(releaseDir, 'appcast.xml'));

await assertFile(appcastPath);
await assertFile(archivePath);
await assertFile(dmgPath);

const client = new S3Client({
  endpoint,
  forcePathStyle,
  region
});

await uploadFile(client, archivePath, basename(archivePath), {
  contentType: 'application/zip',
  cacheControl: 'public, max-age=31536000, immutable'
});
await uploadFile(client, archivePath, latestName, {
  contentType: 'application/zip',
  cacheControl: 'public, max-age=300'
});
await uploadFile(client, dmgPath, basename(dmgPath), {
  contentType: 'application/x-apple-diskimage',
  cacheControl: 'public, max-age=31536000, immutable'
});
await uploadFile(client, dmgPath, latestDmgName, {
  contentType: 'application/x-apple-diskimage',
  cacheControl: 'public, max-age=300'
});

// Publish the feed only after every referenced artifact is available.
await uploadFile(client, appcastPath, 'appcast.xml', {
  contentType: 'application/xml; charset=utf-8',
  cacheControl: 'no-cache'
});

console.log(`Uploaded appcast, ${basename(archivePath)}, and ${basename(dmgPath)} to s3://${bucketName}/${prefix || ''}`);

function parseArgs(values) {
  const parsed = {};

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith('--')) continue;

    const key = value.slice(2);
    const next = values[index + 1];
    if (!next || next.startsWith('--')) {
      parsed[key] = true;
      continue;
    }

    parsed[key] = next;
    index += 1;
  }

  return parsed;
}

function normalizePrefix(value) {
  return value.replace(/^\/+|\/+$/g, '');
}

function objectKey(name) {
  return prefix ? `${prefix}/${name}` : name;
}

async function assertFile(path) {
  const stats = await stat(path).catch(() => null);
  if (!stats?.isFile()) fail(`file not found: ${path}`);
}

async function findArchive(directory) {
  const entries = await readdir(directory).catch(() => []);
  const archives = entries
    .filter((entry) => extname(entry) === '.zip' && entry !== latestName)
    .sort((a, b) => a.localeCompare(b, 'en', { numeric: true }));

  if (archives.length === 0) {
    fail(`no .zip archive found in ${directory}; pass --zip /path/to/archive.zip`);
  }

  return join(directory, archives.at(-1));
}

async function findDmg(directory) {
  const entries = await readdir(directory).catch(() => []);
  const dmgs = entries
    .filter((entry) => extname(entry) === '.dmg' && entry !== latestDmgName)
    .sort((a, b) => a.localeCompare(b, 'en', { numeric: true }));

  if (dmgs.length === 0) {
    fail(`no .dmg archive found in ${directory}; pass --dmg /path/to/archive.dmg`);
  }

  return join(directory, dmgs.at(-1));
}

async function uploadFile(client, path, name, { contentType, cacheControl }) {
  await client.send(new PutObjectCommand({
    Bucket: bucketName,
    Key: objectKey(name),
    Body: createReadStream(path),
    ContentType: contentType,
    CacheControl: cacheControl
  }));

  console.log(`uploaded ${objectKey(name)}`);
}

function fail(message) {
  console.error(message);
  process.exit(2);
}
