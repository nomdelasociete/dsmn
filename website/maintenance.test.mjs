import assert from 'node:assert/strict';
import test from 'node:test';
import { createMaintenance, createSerialQueue } from './maintenance.mjs';

test('maintenance shares work, retries failure, and reruns after its interval', async () => {
  let now = 0;
  let calls = 0;
  const run = createMaintenance(async () => {
    calls++;
    if (calls === 1) throw new Error('database unavailable');
  }, { intervalMs: 100, now: () => now });
  const first = run();
  assert.equal(run(), first);
  await assert.rejects(first, /unavailable/);
  await run();
  await run();
  assert.equal(calls, 2);
  now = 100;
  await Promise.all([run(), run()]);
  assert.equal(calls, 3);
});

test('file queue serializes operations and continues after a failed write', async () => {
  const queue = createSerialQueue();
  const order = [];
  const first = queue(async () => { order.push('prune'); throw new Error('write failed'); });
  const second = queue(async () => { order.push('append'); });
  await assert.rejects(first, /failed/);
  await second;
  assert.deepEqual(order, ['prune', 'append']);
});
