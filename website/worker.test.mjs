import assert from 'node:assert/strict';
import { test } from 'node:test';
import { handleRequest } from './worker.mjs';

function database() {
  const feedback = [];
  return {
    prepare(sql) {
      const statement = {
        params: [],
        bind(...params) {
          statement.params = params;
          return statement;
        },
        async run() {
          if (sql.includes('insert into feedback_messages')) {
            feedback.push(statement.params);
            return { meta: { last_row_id: feedback.length } };
          }
          return { meta: {} };
        },
        async all() {
          return { results: [] };
        }
      };
      return statement;
    }
  };
}

function env() {
  return {
    DB: database(),
    DSMN_METRICS_TOKEN: 'synthetic-test-token',
    RELEASES: {
      async head() { return null; },
      async get() { return null; }
    },
    ASSETS: { async fetch() { return new Response('asset', { status: 200 }); } }
  };
}

test('health check answers ok', async () => {
  const response = await handleRequest(new Request('https://dsmn.test/healthz'), env());
  assert.equal(response.status, 200);
  assert.equal(await response.text(), 'ok');
});

test('metrics require the bearer token', async () => {
  const denied = await handleRequest(new Request('https://dsmn.test/api/metrics'), env());
  assert.equal(denied.status, 401);

  const allowed = await handleRequest(new Request('https://dsmn.test/api/metrics', {
    headers: { authorization: 'Bearer synthetic-test-token' }
  }), env());
  assert.equal(allowed.status, 200);
  const body = await allowed.json();
  assert.equal(body.storage, 'd1');
  assert.equal(body.totals.page_views, 0);
});

test('short feedback is rejected', async () => {
  const response = await handleRequest(new Request('https://dsmn.test/api/feedback', {
    method: 'POST',
    headers: { 'cf-connecting-ip': '192.0.2.10' },
    body: JSON.stringify({ message: 'no' })
  }), env());
  assert.equal(response.status, 422);
  assert.deepEqual(await response.json(), { ok: false, error: 'invalid_feedback' });
});

test('feedback storage failure is unavailable', async () => {
  const failing = env();
  failing.DB.prepare = () => ({
    bind() { return this; },
    async run() { throw new Error('d1 down'); },
    async all() { return { results: [] }; }
  });
  const response = await handleRequest(new Request('https://dsmn.test/api/feedback', {
    method: 'POST',
    headers: { 'cf-connecting-ip': '192.0.2.12' },
    body: JSON.stringify({ category: 'bug', message: 'Helper stayed stale after install.' })
  }), failing);
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { ok: false, error: 'unavailable' });
});

test('oversized feedback is rejected before it is stored', async () => {
  const response = await handleRequest(new Request('https://dsmn.test/api/feedback', {
    method: 'POST',
    headers: { 'cf-connecting-ip': '192.0.2.13' },
    body: 'x'.repeat(8193)
  }), env());
  assert.equal(response.status, 413);
});

test('metrics storage failure is a bad gateway', async () => {
  const failing = env();
  failing.DB.prepare = () => ({
    bind() { return this; },
    async run() { throw new Error('d1 down'); },
    async all() { throw new Error('d1 down'); }
  });
  const response = await handleRequest(new Request('https://dsmn.test/api/metrics', {
    headers: { authorization: 'Bearer synthetic-test-token' }
  }), failing);
  assert.equal(response.status, 502);
  assert.equal(await response.text(), 'Unable to process request.');
});

test('valid feedback is stored', async () => {
  const response = await handleRequest(new Request('https://dsmn.test/api/feedback', {
    method: 'POST',
    headers: { 'cf-connecting-ip': '192.0.2.11' },
    body: JSON.stringify({ category: 'bug', message: 'Helper stayed stale after install.' })
  }), env());
  assert.equal(response.status, 201);
  assert.equal((await response.json()).ok, true);
});

test('download names cannot escape the release prefix', async () => {
  const response = await handleRequest(new Request('https://dsmn.test/download/bad%20name'), env());
  assert.equal(response.status, 400);
});

test('missing release is a 404', async () => {
  const response = await handleRequest(new Request('https://dsmn.test/download/dsmn-latest.dmg'), env());
  assert.equal(response.status, 404);
});
