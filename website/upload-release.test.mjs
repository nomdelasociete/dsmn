import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

test('release upload selects numeric latest artifacts and publishes feed last', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'dsmn-upload-'));
  const uploads = [];
  const server = createServer(async (request, response) => {
    for await (const _ of request) { /* consume the upload */ }
    uploads.push(request.url);
    response.writeHead(200); response.end();
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    for (const name of ['dsmn-0.1.9-9.zip', 'dsmn-0.1.10-10.zip', 'dsmn-0.1.9-9.dmg', 'dsmn-0.1.10-10.dmg', 'appcast.xml']) {
      await writeFile(join(directory, name), 'synthetic release');
    }
    await promisify(execFile)(process.execPath, ['scripts/upload-release.mjs', '--dir', directory], {
      env: {
        PATH: process.env.PATH,
        AWS_ACCESS_KEY_ID: 'synthetic', AWS_SECRET_ACCESS_KEY: 'synthetic',
        AWS_DEFAULT_REGION: 'us-east-1', AWS_S3_BUCKET_NAME: 'test', AWS_S3_URL_STYLE: 'path',
        AWS_ENDPOINT_URL: `http://127.0.0.1:${server.address().port}`
      }
    });
    assert.deepEqual(uploads.map((url) => new URL(url, 'http://localhost').pathname), [
      '/test/updates/dsmn-0.1.10-10.zip', '/test/updates/dsmn-latest.zip',
      '/test/updates/dsmn-0.1.10-10.dmg', '/test/updates/dsmn-latest.dmg', '/test/updates/appcast.xml'
    ]);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
});
