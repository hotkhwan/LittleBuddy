import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, createSession, turnBody, makeClock, tempDir } from './helpers.js';
import { utcDayKey, nextUtcMidnightIso } from '../src/quota.js';

test('free quota exhausts at exactly 300 s, survives a server restart, and is not reset by a new session', async () => {
  const dataDir = tempDir();
  const clock = makeClock();
  let s = await startServer({ dataDir, clock });
  let sessionId;
  try {
    ({ body: { sessionId } } = await createSession(s.api));
    // 5 turns x 30 s = 150 s
    for (let i = 1; i <= 5; i += 1) {
      clock.advance(30);
      const r = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
      assert.equal(r.status, 200);
      assert.equal(r.body.quota.usedSeconds, 30 * i);
      assert.equal(r.body.endAtBoundary, false);
    }
  } finally {
    await s.close();
  }

  // Restart the process-equivalent: new app, same DATA_DIR, same clock.
  s = await startServer({ dataDir, clock });
  try {
    const ent = await s.api('GET', '/api/v1/tutor/entitlement?clientId=client-a');
    assert.equal(ent.body.quota.usedSeconds, 150, 'usage persisted across restart');

    // Continue the SAME session (sessions persist too): 4 more turns -> 270 s.
    for (let i = 6; i <= 9; i += 1) {
      clock.advance(30);
      const r = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
      assert.equal(r.status, 200, JSON.stringify(r.body));
      assert.equal(r.body.quota.usedSeconds, 30 * i);
      assert.equal(r.body.endAtBoundary, false);
    }
    // 10th turn lands exactly on 300 s: served, but flagged as the boundary.
    clock.advance(30);
    const boundary = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(boundary.status, 200);
    assert.equal(boundary.body.quota.usedSeconds, 300);
    assert.equal(boundary.body.quota.remainingSeconds, 0);
    assert.equal(boundary.body.endAtBoundary, true);

    // 11th turn: refused with quota_exhausted and the reset time.
    clock.advance(5);
    const refused = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(refused.status, 429);
    assert.equal(refused.body.error.code, 'quota_exhausted');
    assert.equal(refused.body.error.quota.resetAtUtc, '2026-09-21T00:00:00.000Z');

    // A brand-new session for the same client does not reset anything.
    const again = await createSession(s.api);
    assert.equal(again.status, 429);
    assert.equal(again.body.error.code, 'quota_exhausted');

    // A new clientId with the OLD client's signed token is not approved (no reset trick).
    const token = s.app.approval.mint('client-a');
    const trick = await createSession(s.api, { clientId: 'client-a-fresh', token });
    assert.equal(trick.status, 403);
    assert.equal(trick.body.error.code, 'not_approved');

    // Next UTC day: the window resets.
    clock.t = Date.UTC(2026, 8, 21, 0, 0, 1);
    const fresh = await createSession(s.api);
    assert.equal(fresh.status, 201);
    assert.equal(fresh.body.quota.usedSeconds, 0);
    assert.equal(fresh.body.quota.resetAtUtc, '2026-09-22T00:00:00.000Z');
  } finally {
    await s.close();
  }
});

test('per-turn cap stops a stuck client from burning hours', async () => {
  const s = await startServer({ env: { TUTOR_TURN_CAP_SECONDS: '45' } });
  try {
    const { body: { sessionId } } = await createSession(s.api);
    s.clock.advance(3600); // client "hung" for an hour
    const r = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(r.status, 200);
    assert.equal(r.body.chargedSeconds, 45);
    assert.equal(r.body.quota.usedSeconds, 45);
    s.clock.advance(7200);
    const end = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/end`);
    assert.equal(end.body.quota.usedSeconds, 90);
  } finally {
    await s.close();
  }
});

test('family_club allowance is configurable and never unlimited', async () => {
  const s = await startServer({ env: { FAMILY_CLUB_DAILY_SECONDS: '900' } });
  try {
    const grant = await s.api('POST', '/api/v1/dev/entitlement', { clientId: 'fam', entitlement: 'family_club' });
    assert.equal(grant.status, 200);
    assert.equal(grant.body.quota.dailyAllowanceSeconds, 900);
    const c = await createSession(s.api, { clientId: 'fam' });
    assert.equal(c.body.entitlement, 'family_club');
    assert.equal(c.body.quota.remainingSeconds, 900);
    assert.equal(s.app.quota.allowanceFor('family_club'), 900);
    assert.ok(s.app.quota.allowanceFor('family_club') <= 24 * 3600);
  } finally {
    await s.close();
  }
  const huge = await startServer({ env: { FAMILY_CLUB_DAILY_SECONDS: '999999999' } });
  try {
    assert.equal(huge.app.quota.allowanceFor('family_club'), 24 * 3600, 'capped at one day');
  } finally {
    await huge.close();
  }
});

test('UTC day helpers', () => {
  assert.equal(utcDayKey(Date.UTC(2026, 8, 20, 23, 59, 59)), '2026-09-20');
  assert.equal(utcDayKey(Date.UTC(2026, 8, 21, 0, 0, 0)), '2026-09-21');
  assert.equal(nextUtcMidnightIso(Date.UTC(2026, 8, 20, 23, 59, 59)), '2026-09-21T00:00:00.000Z');
  assert.equal(nextUtcMidnightIso(Date.UTC(2026, 11, 31, 12)), '2027-01-01T00:00:00.000Z');
});
