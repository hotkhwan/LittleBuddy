import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, createSession, turnBody, DEV_TOKEN } from './helpers.js';

test('session lifecycle: create -> turns -> end, with validated turns and quota', async () => {
  const s = await startServer();
  try {
    const h = await s.api('GET', '/healthz');
    assert.equal(h.status, 200);
    assert.equal(h.body.ok, true);

    const created = await createSession(s.api);
    assert.equal(created.status, 201);
    assert.equal(created.body.entitlement, 'free');
    assert.deepEqual(Object.keys(created.body.quota).sort(), ['dailyAllowanceSeconds', 'dailyTurnAllowance', 'entitlement', 'remainingSeconds', 'resetAtUtc', 'usedSeconds', 'usedTurns']);
    assert.equal(created.body.quota.dailyAllowanceSeconds, 300);
    assert.equal(created.body.quota.resetAtUtc, '2026-09-21T00:00:00.000Z');
    const id = created.body.sessionId;

    s.clock.advance(12);
    const t1 = await s.api('POST', `/api/v1/tutor/sessions/${id}/turns`, turnBody());
    assert.equal(t1.status, 200);
    assert.equal(t1.body.turn.lessonAction, 'next_question');
    assert.equal(t1.body.turn.visual.assetId, 'apple_red');
    assert.equal(t1.body.turn.nextQuestion, 'What color is the banana?');
    assert.ok(t1.body.turn.speech.length <= 160);
    assert.equal(t1.body.endAtBoundary, false);
    assert.equal(t1.body.quota.usedSeconds, 12);
    assert.equal(t1.body.chargedSeconds, 12);

    s.clock.advance(10);
    const t2 = await s.api('POST', `/api/v1/tutor/sessions/${id}/turns`, turnBody({ transcript: 'blue', lessonContext: { stepId: 's2', outcome: 'incorrect', expectedAnswers: ['yellow'], hint: 'It is the color of the sun.' } }));
    assert.equal(t2.status, 200);
    assert.equal(t2.body.turn.lessonAction, 'give_hint');
    assert.match(t2.body.turn.speech, /color of the sun/);
    assert.equal(t2.body.quota.usedSeconds, 22);

    s.clock.advance(5);
    const end = await s.api('POST', `/api/v1/tutor/sessions/${id}/end`);
    assert.equal(end.status, 200);
    assert.equal(end.body.quota.usedSeconds, 27);
    assert.equal(end.body.usage.turns, 2);
    assert.equal(end.body.usage.ttsChars, t1.body.turn.speech.length + t2.body.turn.speech.length);

    const again = await s.api('POST', `/api/v1/tutor/sessions/${id}/end`);
    assert.equal(again.status, 200);
    assert.equal(again.body.quota.usedSeconds, 27, 'ending twice does not double charge');

    const after = await s.api('POST', `/api/v1/tutor/sessions/${id}/turns`, turnBody());
    assert.equal(after.status, 409);
    assert.equal(after.body.error.code, 'session_ended');
  } finally {
    await s.close();
  }
});

test('session creation requires parent approval', async () => {
  const s = await startServer();
  try {
    const bad = await createSession(s.api, { token: 'nope' });
    assert.equal(bad.status, 403);
    assert.equal(bad.body.error.code, 'not_approved');
    const missing = await s.api('POST', '/api/v1/tutor/sessions', { lessonId: 'fruits_1', clientId: 'client-a' }, { 'x-parent-approval': '' });
    assert.equal(missing.status, 403);

    const minted = await s.api('POST', '/api/v1/dev/parent-approval', { clientId: 'client-b' });
    assert.equal(minted.status, 200);
    const ok = await createSession(s.api, { clientId: 'client-b', token: minted.body.parentApprovalToken });
    assert.equal(ok.status, 201);
    const other = await createSession(s.api, { clientId: 'client-c', token: minted.body.parentApprovalToken });
    assert.equal(other.status, 403, 'a token bound to client-b does not approve client-c');
  } finally {
    await s.close();
  }
});

test('dev token is refused outside DEV_MODE; signed tokens still work', async () => {
  const s = await startServer({ env: { DEV_MODE: '0' } });
  try {
    const bad = await createSession(s.api, { token: DEV_TOKEN, lessonId: 'colors_red_blue' });
    assert.equal(bad.status, 403);
    const dev = await s.api('POST', '/api/v1/dev/parent-approval', { clientId: 'x' });
    assert.equal(dev.status, 404, 'dev routes are absent outside DEV_MODE');
    const token = s.app.approval.mint('client-z');
    const ok = await createSession(s.api, { clientId: 'client-z', token, lessonId: 'colors_red_blue' });
    assert.equal(ok.status, 201);
    const unknown = await createSession(s.api, { clientId: 'client-z', token, lessonId: 'fruits_1' });
    assert.equal(unknown.status, 400, 'unknown lessons are refused outside DEV_MODE');
    assert.equal(unknown.body.error.code, 'unknown_lesson');
  } finally {
    await s.close();
  }
});

test('turn request validation returns invalid_turn / bad_request codes', async () => {
  const s = await startServer();
  try {
    const { body: { sessionId } } = await createSession(s.api);
    const noCtx = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, { transcript: 'apple' });
    assert.equal(noCtx.status, 400);
    assert.equal(noCtx.body.error.code, 'invalid_turn');
    const badOutcome = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody({ lessonContext: { stepId: 's1', outcome: 'wrong' } }));
    assert.equal(badOutcome.body.error.code, 'invalid_turn');
    const notJson = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, '{not json');
    assert.equal(notJson.status, 400);
    assert.equal(notJson.body.error.code, 'bad_request');
    const missing = await s.api('POST', '/api/v1/tutor/sessions/does-not-exist/turns', turnBody());
    assert.equal(missing.status, 404);
    const big = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody({ transcript: 'x'.repeat(40_000) }));
    assert.equal(big.status, 413);
    const unknownAsset = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody({ lessonContext: { stepId: 's1', outcome: 'correct', visualAssetId: 'dragon' } }));
    assert.equal(unknownAsset.status, 200);
    assert.deepEqual(unknownAsset.body.turn.visual, { type: 'none' }, 'unknown asset id is dropped, never echoed');
  } finally {
    await s.close();
  }
});

test('CORS preflight and unknown routes', async () => {
  const s = await startServer();
  try {
    const res = await fetch(`${s.base}/api/v1/tutor/sessions`, { method: 'OPTIONS' });
    assert.equal(res.status, 204);
    assert.equal(res.headers.get('access-control-allow-origin'), null, 'no CORS headers without an allowlist');
    const nf = await s.api('GET', '/nope');
    assert.equal(nf.status, 404);
    const wrongMethod = await s.api('GET', '/api/v1/tutor/sessions');
    assert.equal(wrongMethod.status, 405);
  } finally {
    await s.close();
  }
});
