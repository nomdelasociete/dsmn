import assert from 'node:assert/strict';
import test from 'node:test';
import { createAnalytics } from './analytics.mjs';

test('admin authorization requires a nonempty matching bearer token', () => {
  const previous = process.env.DSMN_METRICS_TOKEN;
  try {
    process.env.DSMN_METRICS_TOKEN = 'synthetic-test-token';
    const { authorizeMetrics } = createAnalytics();
    assert.equal(authorizeMetrics({}), false);
    assert.equal(authorizeMetrics({ authorization: 'Bearer ' }), false);
    assert.equal(authorizeMetrics({ authorization: 'Bearer wrong' }), false);
    assert.equal(authorizeMetrics({ authorization: 'Bearer synthetic-test-token' }), true);
    delete process.env.DSMN_METRICS_TOKEN;
    assert.equal(authorizeMetrics({ authorization: 'Bearer synthetic-test-token' }), false);
  } finally {
    if (previous === undefined) delete process.env.DSMN_METRICS_TOKEN;
    else process.env.DSMN_METRICS_TOKEN = previous;
  }
});
