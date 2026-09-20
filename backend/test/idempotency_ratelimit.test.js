import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, createSession, turnBody } from './helpers.js';

test('idempotent turns: same key replays the same response without charging twice', async () => {
  const s = await startServer();
  try {
    const { body: { sessionId } } = await createSession(s.api);
    s.clock.advance(20);
    const first = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody(), { 'Idempotency-Key': 'k1' });
    assert.equal(first.status, 200);
    s.clock.advance(20);
    const replay = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody(), { 'Idempotency-Key': 'k1' });
    assert.equal(replay.status, 200);
    assert.equal(replay.headers.get('idempotent-replayed'), 'true');
    assert.deepEqual(replay.body, first.body);
    const ent = await s.api('GET', '/api/v1/tutor/entitlement?clientId=client-a');
    assert.equal(ent.body.quota.usedSeconds, 20, 'replay did not charge quota');
    assert.equal(s.app.usage.sessionTotals(sessionId).turns, 1, 'replay did not record usage');

    const mismatch = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody({ transcript: 'banana' }), { 'Idempotency-Key': 'k1' });
    assert.equal(mismatch.status, 422);
    assert.equal(mismatch.body.error.code, 'idempotency_mismatch');

    const other = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody(), { 'Idempotency-Key': 'k2' });
    assert.equal(other.body.turnIndex, 2);
  } finally {
    await s.close();
  }
});

test('idempotency keys are scoped per session', async () => {
  const s = await startServer();
  try {
    const a = (await createSession(s.api, { clientId: 'a' })).body.sessionId;
    const b = (await createSession(s.api, { clientId: 'b' })).body.sessionId;
    const ra = await s.api('POST', `/api/v1/tutor/sessions/${a}/turns`, turnBody(), { 'Idempotency-Key': 'same' });
    const rb = await s.api('POST', `/api/v1/tutor/sessions/${b}/turns`, turnBody(), { 'Idempotency-Key': 'same' });
    assert.equal(ra.status, 200);
    assert.equal(rb.status, 200);
    assert.equal(rb.headers.get('idempotent-replayed'), null);
  } finally {
    await s.close();
  }
});

test('rate limit per session and per IP', async () => {
  const s = await startServer({ env: { RATE_LIMIT_SESSION_TURNS_PER_MINUTE: '3', RATE_LIMIT_IP_PER_MINUTE: '12' } });
  try {
    const { body: { sessionId } } = await createSession(s.api);
    for (let i = 0; i < 3; i += 1) {
      const r = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
      assert.equal(r.status, 200);
    }
    const blocked = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(blocked.status, 429);
    assert.equal(blocked.body.error.code, 'rate_limited');
    assert.ok(Number(blocked.headers.get('retry-after')) >= 1);

    s.clock.advance(61);
    const afterWindow = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(afterWindow.status, 200, 'window rolled over');

    // IP limit: 12/min total; we have used 1 (session) + 5 (turns) in two windows. Burn the rest.
    let last;
    for (let i = 0; i < 20; i += 1) last = await s.api('GET', '/healthz');
    assert.equal(last.status, 200, 'healthz is not rate limited');
    for (let i = 0; i < 20; i += 1) last = await s.api('GET', '/api/v1/tutor/entitlement?clientId=client-a');
    assert.equal(last.status, 429);
    assert.equal(last.body.error.code, 'rate_limited');
  } finally {
    await s.close();
  }
});
