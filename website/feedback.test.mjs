import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createFeedbackRateLimiter, normalizeFeedbackSubmission } from './feedback.mjs';

const request = {
  headers: {
    'user-agent': 'node-test'
  }
};

test('normalizes a valid feedback submission', () => {
  const feedback = normalizeFeedbackSubmission(
    {
      category: 'bug',
      email: 'jb@example.com',
      message: 'The helper status stayed stale after installing.',
      appVersion: '0.1.4',
      buildNumber: '5',
      osVersion: 'macOS 15.5',
      diagnostics: {
        helper: 'enabled',
        ignoredObject: { nested: true },
        long: 'x'.repeat(600)
      }
    },
    request,
    '9a1a9b4e-4af6-4d53-b8b2-d8b6c9e4f1e2'
  );

  assert.equal(feedback.category, 'bug');
  assert.equal(feedback.email, 'jb@example.com');
  assert.equal(feedback.appVersion, '0.1.4');
  assert.equal(feedback.buildNumber, '5');
  assert.equal(feedback.osVersion, 'macOS 15.5');
  assert.equal(feedback.userAgent, 'node-test');
  assert.equal(feedback.sessionId, '9a1a9b4e-4af6-4d53-b8b2-d8b6c9e4f1e2');
  assert.equal(feedback.diagnostics.helper, 'enabled');
  assert.equal(feedback.diagnostics.ignoredObject, undefined);
  assert.equal(feedback.diagnostics.long.length, 500);
});

test('falls back to other for unknown categories', () => {
  const feedback = normalizeFeedbackSubmission(
    { category: 'sales', message: 'Please add a status export.' },
    request
  );

  assert.equal(feedback.category, 'other');
});

test('rejects short messages and invalid emails', () => {
  assert.throws(
    () => normalizeFeedbackSubmission({ message: 'hey' }, request),
    /too short/
  );

  assert.throws(
    () => normalizeFeedbackSubmission({ message: 'This is a real bug report.', email: 'not-an-email' }, request),
    /Invalid feedback email/
  );
});

test('rate limiter allows bounded bursts per key', () => {
  let timestamp = 1000;
  const limiter = createFeedbackRateLimiter({
    maxRequests: 2,
    now: () => timestamp,
    windowMs: 100
  });

  assert.equal(limiter.allow('client-a'), true);
  assert.equal(limiter.allow('client-a'), true);
  assert.equal(limiter.allow('client-a'), false);
  assert.equal(limiter.allow('client-b'), true);

  timestamp += 101;
  assert.equal(limiter.allow('client-a'), true);
});
