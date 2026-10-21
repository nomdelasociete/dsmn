import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { classifyDownloadKind, createAnalytics } from './analytics.mjs';

test('analytics sessions do not set visitor cookies', () => {
  const analytics = createAnalytics();
  const session = analytics.session({
    headers: {
      cookie: 'dsmn_sid=9a1a9b4e-4af6-4d53-b8b2-d8b6c9e4f1e2'
    }
  });

  assert.equal(session.id, undefined);
  assert.equal(session.setCookie, undefined);
});

test('classifies release downloads by asset', () => {
  assert.equal(classifyDownloadKind('dsmn-latest.dmg'), 'site_dmg');
  assert.equal(classifyDownloadKind('dsmn-0.1.10-11.dmg'), 'site_dmg');
  assert.equal(classifyDownloadKind('dsmn-0.1.10-11.zip'), 'sparkle_update_zip');
  assert.equal(classifyDownloadKind('dsmn-latest.zip'), 'direct_zip');
  assert.equal(classifyDownloadKind('notes.txt'), 'unknown');
});

test('analytics metrics split site and update downloads', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'dsmn-analytics-'));
  const filePath = join(directory, 'events.jsonl');
  const previousFile = process.env.DSMN_ANALYTICS_FILE;
  const previousDatabase = process.env.DATABASE_URL;
  const now = new Date().toISOString();

  const events = [
    { eventName: 'page_view', path: '/', occurredAt: now },
    { eventName: 'download_click', path: '/download/dsmn-latest.dmg', asset: 'dsmn-latest.dmg', occurredAt: now },
    { eventName: 'download', path: '/download/dsmn-latest.dmg', asset: 'dsmn-latest.dmg', occurredAt: now },
    { eventName: 'download', path: '/download/dsmn-0.1.10-11.zip', asset: 'dsmn-0.1.10-11.zip', occurredAt: now },
    { eventName: 'download', path: '/download/dsmn-latest.zip', asset: 'dsmn-latest.zip', occurredAt: now },
    { eventName: 'download', path: '/download/custom.bin', asset: 'custom.bin', metadata: { downloadKind: 'unknown' }, occurredAt: now },
    { eventName: 'appcast_request', path: '/appcast.xml', asset: 'appcast.xml', occurredAt: now }
  ];

  try {
    process.env.DSMN_ANALYTICS_FILE = filePath;
    delete process.env.DATABASE_URL;

    await writeFile(filePath, `${events.map((event) => JSON.stringify(event)).join('\n')}\n`);

    const metrics = await createAnalytics().metrics();

    assert.equal(metrics.totals.downloads, 4);
    assert.equal(metrics.totals.site_downloads, 1);
    assert.equal(metrics.totals.update_downloads, 1);
    assert.equal(metrics.totals.direct_downloads, 1);
    assert.equal(metrics.totals.unknown_downloads, 1);
    assert.equal(metrics.totals.download_clicks, 1);
    assert.equal(metrics.totals.appcast_requests, 1);
    assert.equal(metrics.last24h.site_downloads, 1);
    assert.equal(metrics.byDay[0].update_downloads, 1);
    assert.deepEqual(metrics.topDownloads[0], {
      asset: 'dsmn-latest.dmg',
      downloadKind: 'site_dmg',
      downloads: 1
    });
  } finally {
    if (previousFile === undefined) {
      delete process.env.DSMN_ANALYTICS_FILE;
    } else {
      process.env.DSMN_ANALYTICS_FILE = previousFile;
    }

    if (previousDatabase === undefined) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = previousDatabase;
    }

    await rm(directory, { force: true, recursive: true });
  }
});
