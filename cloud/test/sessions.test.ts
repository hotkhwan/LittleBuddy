import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { DEV_TOKEN, createSession, devTurnBody, familyClient, lessonTurnBody, makeClient, sessionStub, signInFamily, uniqueId } from './helpers';

describe('session lifecycle', () => {
  it('start -> server-resolved turn -> end, with quota blocks the Godot client understands', async () => {
    const c = makeClient();
    const s = await createSession(c, { clientId: 'ipad-demo' });
    expect(s.status).toBe(201);
    expect(s.body).toMatchObject({ entitlement: 'free', lessonId: 'colors_red_blue', lessonKnown: true, quota: { entitlement: 'free', dailyAllowanceSeconds: 300, usedSeconds: 0, remainingSeconds: 300, resetAtUtc: '2027-01-11T00:00:00.000Z', dailyTurnAllowance: 60, usedTurns: 0 } });
    expect(s.body.childId).toBeTruthy();
    const sid = s.body.sessionId;

    c.clock.advance(12);
    const t = await c.api('POST', `/v1/tutor/sessions/${sid}/turns`, lessonTurnBody(), { 'idempotency-key': 't1' });
    expect(t.status).toBe(200);
    expect(t.body.turn).toMatchObject({ emotion: 'happy', gesture: 'clap', visual: { type: 'flashcard', assetId: 'color_red' }, lessonAction: 'next_question', nextQuestion: 'What colour is this?' });
    // One acknowledgement per praise: the picked opener replaces the lesson
    // line's own ("Yes! Red!" -> "<opener>! Red! <question>").
    expect(t.body.turn.speech).toMatch(/Red!/);
    expect(t.body.turn.speech).not.toMatch(/(Yes|Great|Nice|Super|Well done|Wonderful|Yay)[!.]\s+(Yes|Great|Nice|Super|Well done|Wonderful|Yay)[!.]/i);
    expect(t.body).toMatchObject({ endAtBoundary: false, turnIndex: 1, chargedSeconds: 12, provider: 'mock', cached: false, fallback: null, contextSource: 'server' });
    expect(t.body.quota).toMatchObject({ usedSeconds: 12, remainingSeconds: 288, usedTurns: 1 });
    expect(t.body.usage).toMatchObject({ llmInputTokens: 0, llmOutputTokens: 0, costUsd: 0 });

    c.clock.advance(8);
    const wrong = await c.api('POST', `/v1/tutor/sessions/${sid}/turns`, { transcript: 'green', lessonContext: { stepId: 's03_blue', outcome: 'incorrect' } });
    expect(wrong.body.turn.lessonAction).toBe('give_hint');
    expect(wrong.body.turn.speech).toMatch(/sky and the sea/);

    c.clock.advance(5);
    const e = await c.api('POST', `/v1/tutor/sessions/${sid}/end`, { reason: 'home_button' });
    expect(e.status).toBe(200);
    expect(e.body.quota.usedSeconds).toBe(25);
    expect(e.body.usage).toMatchObject({ turns: 2, costUsd: 0 });
    const row = await env.DB.prepare('SELECT * FROM tutor_sessions WHERE id = ?').bind(sid).first<{ reason: string; turn_count: number; seconds_used: number; ended_at: number }>();
    expect(row).toMatchObject({ reason: 'home_button', turn_count: 2, seconds_used: 25 });
    expect(row?.ended_at).toBe(c.clock.now());
    c.clock.advance(30);
    const e2 = await c.api('POST', `/v1/tutor/sessions/${sid}/end`);
    expect(e2.status).toBe(200);
    expect(e2.body.quota.usedSeconds).toBe(25);
  });

  it('the shipped Godot paths under /api/v1 and the entitlement alias work unchanged (no childId anywhere)', async () => {
    const boot = makeClient({ defaultToken: null });
    const clientId = uniqueId('ipad');
    const fam = await signInFamily(boot, uniqueId('godot'), clientId);
    const c = makeClient({ defaultToken: null, clock: boot.clock });
    const s = await c.api('POST', '/api/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId, parentApprovalToken: fam.approvalToken });
    expect(s.status).toBe(201);
    const t = await c.api('POST', `/api/v1/tutor/sessions/${s.body.sessionId}/turns`, lessonTurnBody(), { 'x-parent-approval': fam.approvalToken, 'idempotency-key': `${s.body.sessionId}-1` });
    expect(t.status).toBe(200);
    const ent = await c.api('GET', `/api/v1/tutor/entitlement?clientId=${clientId}`, undefined, { 'x-parent-approval': fam.approvalToken });
    expect(ent.status).toBe(200);
    expect(ent.body).toMatchObject({ clientId, entitlement: 'free', products: ['little_days.family_club.monthly', 'little_days.family_club.yearly'] });
    expect(ent.body.quota.usedTurns).toBe(1);
    expect(ent.body.childId).toBe(s.body.childId); // the auto-created nickname-only default profile
    const kids = await c.api('GET', '/v1/children', undefined, fam.bearer);
    expect(kids.body.children).toEqual([expect.objectContaining({ nickname: 'Buddy' })]);
    const q = await c.api('GET', '/v1/tutor/quota', undefined, { 'x-parent-approval': fam.approvalToken });
    expect(q.body.quota.dailyAllowanceSeconds).toBe(300);
  });

  it('turns are idempotent: same key replays uncharged, same key + other body is 422', async () => {
    const c = makeClient();
    const s = await createSession(c);
    const sessionId = s.body.sessionId;
    c.clock.advance(10);
    const first = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody(), { 'idempotency-key': 'k1' });
    expect(first.status).toBe(200);
    c.clock.advance(10);
    const replay = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody(), { 'idempotency-key': 'k1' });
    expect(replay.status).toBe(200);
    expect(replay.headers.get('idempotent-replayed')).toBe('true');
    expect(replay.body).toEqual(first.body);
    const q = await c.api('GET', `/v1/tutor/quota?childId=${s.body.childId}`);
    expect(q.body.quota.usedSeconds).toBe(10);
    expect(q.body.quota.usedTurns).toBe(1);
    const mismatch = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody({ transcript: 'blue' }), { 'idempotency-key': 'k1' });
    expect(mismatch.status).toBe(422);
    expect(mismatch.body.error.code).toBe('idempotency_mismatch');
    const rows = await env.DB.prepare('SELECT request_hash, response_json FROM api_idempotency WHERE session_id = ?').bind(sessionId).all<{ request_hash: string; response_json: string }>();
    expect(rows.results).toHaveLength(1);
    expect(rows.results[0].request_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(rows.results[0].response_json).not.toContain('"transcript"');
  });

  it('lesson authority: unknown stepId is invalid_turn, client hint text is ignored, unknown lesson refused outside DEV_MODE', async () => {
    const c = makeClient();
    const { body: { sessionId } } = await createSession(c);
    const bad = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, { transcript: 'x', lessonContext: { stepId: 'not_here', outcome: 'correct' } });
    expect(bad.status).toBe(400);
    expect(bad.body.error.code).toBe('invalid_turn');
    const t = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, { transcript: 'x', lessonContext: { stepId: 's03_blue', outcome: 'incorrect', hint: 'BUY NOW at www.evil.com' } });
    expect(t.status).toBe(200);
    expect(t.body.turn.speech).not.toMatch(/evil/);
    expect(t.body.contextSource).toBe('server');
    expect((await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, { transcript: 'x', lessonContext: { stepId: 's03_blue', outcome: 'maybe' } })).status).toBe(400);
    const { fam, h } = await familyClient('prod-lesson');
    const prod = makeClient({ defaultToken: null, env: { DEV_MODE: '0', PRODUCTION_ENABLED: 'true' } });
    const u = await prod.api('POST', '/v1/tutor/sessions', { lessonId: 'fruits_99', clientId: fam.clientId }, h);
    expect(u.status).toBe(400);
    expect(u.body.error.code).toBe('unknown_lesson');
    const dev = await createSession(c, { lessonId: 'fruits_99' });
    expect(dev.status).toBe(201);
    expect(dev.body.lessonKnown).toBe(false);
    const dt = await c.api('POST', `/v1/tutor/sessions/${dev.body.sessionId}/turns`, devTurnBody());
    expect(dt.status).toBe(200);
    expect(dt.body.contextSource).toBe('client_dev');
  });

  it('session ownership: another approval is 403, unknown session 404, ended session 409', async () => {
    const c = makeClient();
    const clientId = uniqueId('owner');
    const { body: { sessionId } } = await createSession(c, { clientId });
    const fam = await signInFamily(makeClient({ defaultToken: null }), uniqueId('intruder'), clientId);
    const stolen = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody(), { 'x-parent-approval': fam.approvalToken });
    expect(stolen.status).toBe(403);
    expect(stolen.body.error.code).toBe('not_approved');
    const none = await c.api('POST', `/v1/tutor/sessions/${crypto.randomUUID()}/turns`, lessonTurnBody());
    expect(none.status).toBe(404);
    expect(none.body.error.code).toBe('not_found');
    expect((await c.api('POST', '/v1/tutor/sessions/not-a-uuid/end')).status).toBe(404);
    await c.api('POST', `/v1/tutor/sessions/${sessionId}/end`);
    const ended = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
    expect(ended.status).toBe(409);
    expect(ended.body.error.code).toBe('session_ended');
  });

  it('per-session turn rate limit is exact (30/min) and resets with the window', async () => {
    const c = makeClient();
    const { body: { sessionId } } = await createSession(c);
    for (let i = 0; i < 30; i += 1) {
      const r = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
      expect(r.status, `turn ${i + 1}`).toBe(200);
    }
    const r = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
    expect(r.status).toBe(429);
    expect(r.body.error.code).toBe('rate_limited');
    expect(r.headers.get('retry-after')).toBeTruthy();
    c.clock.advance(61);
    expect((await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody())).status).toBe(200);
  });

  it('a faulty provider falls back to the deterministic mock and records the reason', async () => {
    const c = makeClient({ env: { TUTOR_PROVIDER: 'faulty' } });
    const { body: { sessionId } } = await createSession(c);
    const r = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
    expect(r.status).toBe(200);
    expect(r.body.provider).toBe('mock');
    expect(r.body.fallback).toMatch(/^invalid_turn:speech:url/);
    expect(r.body.turn.speech).not.toMatch(/example/);
    expect(r.body.usage.llmInputTokens).toBe(0);
  });
});

describe('daily quota', () => {
  it('free quota exhausts at exactly 300 s: 10th turn is the boundary, 11th and a new session are 429, next UTC day resets', async () => {
    const c = makeClient();
    const clientId = uniqueId('q');
    const s = await createSession(c, { clientId });
    const { sessionId, childId } = s.body;
    for (let i = 1; i <= 9; i += 1) {
      c.clock.advance(30);
      const r = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
      expect(r.status, `turn ${i}`).toBe(200);
      expect(r.body.quota.usedSeconds).toBe(30 * i);
      expect(r.body.endAtBoundary).toBe(false);
    }
    c.clock.advance(30);
    const boundary = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
    expect(boundary.status).toBe(200);
    expect(boundary.body.quota).toMatchObject({ usedSeconds: 300, remainingSeconds: 0 });
    expect(boundary.body.endAtBoundary).toBe(true);

    c.clock.advance(5);
    const refused = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
    expect(refused.status).toBe(429);
    expect(refused.body.error.code).toBe('quota_exhausted');
    expect(refused.body.error.reason).toBe('daily_quota');
    expect(refused.body.error.quota.resetAtUtc).toBe('2027-01-11T00:00:00.000Z');
    const row = await env.DB.prepare('SELECT reason FROM tutor_sessions WHERE id = ?').bind(sessionId).first<{ reason: string }>();
    expect(row?.reason).toBe('quota_exhausted');

    const again = await createSession(c, { clientId, childId });
    expect(again.status).toBe(429);
    const mirror = await env.DB.prepare("SELECT seconds_used, turns_used, allowance_seconds FROM daily_quota WHERE child_id = ? AND day_utc = '2027-01-10'").bind(childId).first();
    expect(mirror).toEqual({ seconds_used: 300, turns_used: 10, allowance_seconds: 300 });

    c.clock.t = Date.UTC(2027, 0, 11, 0, 0, 1);
    const fresh = await createSession(c, { clientId, childId });
    expect(fresh.status).toBe(201);
    expect(fresh.body.quota.usedSeconds).toBe(0);
    expect(fresh.body.quota.resetAtUtc).toBe('2027-01-12T00:00:00.000Z');
  });

  it('the per-turn cap stops a hung client from burning hours', async () => {
    const c = makeClient();
    const { body: { sessionId } } = await createSession(c);
    c.clock.advance(3600);
    const r = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
    expect(r.status).toBe(200);
    expect(r.body.chargedSeconds).toBe(45);
    expect(r.body.quota.usedSeconds).toBe(45);
  });

  it('Family Club raises the allowance to 1800 s mid-day and the quota block says so', async () => {
    const { c, fam } = await familyClient('club');
    const s = await createSession(c, { fresh: false, token: fam.approvalToken, clientId: fam.clientId });
    expect(s.status).toBe(201);
    const sid = s.body.sessionId;
    for (let i = 0; i < 10; i += 1) {
      c.clock.advance(30);
      expect((await c.api('POST', `/v1/tutor/sessions/${sid}/turns`, lessonTurnBody())).status).toBe(200);
    }
    c.clock.advance(30);
    expect((await c.api('POST', `/v1/tutor/sessions/${sid}/turns`, lessonTurnBody())).status).toBe(429);
    const grant = await c.api('POST', '/v1/dev/entitlements', { entitlement: 'family_club' }, fam.bearer);
    expect(grant.status).toBe(200);
    const s2 = await createSession(c, { fresh: false, token: fam.approvalToken, clientId: fam.clientId });
    expect(s2.status).toBe(201);
    expect(s2.body.entitlement).toBe('family_club');
    expect(s2.body.quota).toMatchObject({ entitlement: 'family_club', dailyAllowanceSeconds: 1800, usedSeconds: 300, remainingSeconds: 1500, dailyTurnAllowance: 360 });
    c.clock.advance(30);
    const t = await c.api('POST', `/v1/tutor/sessions/${s2.body.sessionId}/turns`, lessonTurnBody());
    expect(t.status).toBe(200);
    expect(t.body.quota.usedSeconds).toBe(330);
  });

  it('the daily turn cap is independent of seconds (Worker-side start check)', async () => {
    const c = makeClient({ env: { FREE_DAILY_TURNS: '2' } });
    const s = await createSession(c);
    expect((await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/turns`, lessonTurnBody())).status).toBe(200);
    expect((await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/turns`, lessonTurnBody())).status).toBe(200);
    const s2 = await createSession(c, { childId: s.body.childId });
    expect(s2.status).toBe(429);
    expect(s2.body.error.reason).toBe('daily_turns');
  });

  it('the monthly budget guard closes sessions and turns for everyone with reason monthly_budget', async () => {
    const c = makeClient();
    const { body: { sessionId } } = await createSession(c);
    const id = uniqueId('budget');
    await env.DB.prepare("INSERT INTO usage_events (id, session_id, kind, tokens_in, tokens_out, audio_seconds, cost_usd_micro, created_at) VALUES (?, 'other', 'turn', 0, 0, 0, 25000000, ?)").bind(id, c.clock.now()).run();
    try {
      const t = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
      expect(t.status).toBe(429);
      expect(t.body.error.reason).toBe('monthly_budget');
      const s = await createSession(c);
      expect(s.status).toBe(429);
      expect(s.body.error.reason).toBe('monthly_budget');
      const spend = await c.api('GET', '/v1/dev/spend');
      expect(spend.body.spentUsd).toBeGreaterThanOrEqual(25);
      expect(spend.body.monthlyBudgetUsd).toBe(25);
    } finally {
      await env.DB.prepare('DELETE FROM usage_events WHERE id = ?').bind(id).run();
    }
    expect((await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody())).status).toBe(200);
  });
});

describe('TutorSessionDO countdown', () => {
  it('ends an idle session after SESSION_IDLE_SECONDS and charges the capped gap', async () => {
    const c = makeClient();
    const { body: { sessionId } } = await createSession(c);
    c.clock.advance(10);
    await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
    const stub = sessionStub(sessionId);
    expect(await stub.tick(c.clock.now() + 60_000)).toEqual({ ended: false, reason: null });
    expect(await stub.tick(c.clock.now() + 121_000)).toEqual({ ended: true, reason: 'idle' });
    const info = await stub.info();
    expect(info?.endReason).toBe('idle');
    expect(info?.secondsUsed).toBe(55); // 10 s turn gap + 45 s capped idle gap
    c.clock.advance(200);
    const after = await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody());
    expect(after.status).toBe(409);
  });

  it('a skewed clock behind the last event never ends a live session', async () => {
    const c = makeClient();
    const s = await createSession(c);
    expect(s.status).toBe(201);
    const stub = sessionStub(s.body.sessionId);
    expect(await stub.tick(c.clock.now() - 10_000_000)).toEqual({ ended: false, reason: null });
    expect((await stub.info())?.endedAt).toBeNull();
  });

  it('a parent can stop tutor time from Parent Corner with the sign-in', async () => {
    const { c, fam } = await familyClient('stopper');
    const s = await createSession(c, { fresh: false, token: fam.approvalToken, clientId: fam.clientId });
    expect(s.status).toBe(201);
    const other = await signInFamily(makeClient({ defaultToken: null }), uniqueId('not-stopper'));
    expect((await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/stop`, {}, other.bearer)).status).toBe(403);
    const r = await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/stop`, {}, fam.bearer);
    expect(r.status).toBe(200);
    expect(r.body.ended).toBe(true);
    expect((await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/turns`, lessonTurnBody())).status).toBe(409);
  });

  it('revoking ai_tutor consent ends the live session on the next turn', async () => {
    const { c, fam } = await familyClient('revoker');
    const s = await createSession(c, { fresh: false, token: fam.approvalToken, clientId: fam.clientId });
    expect(s.status).toBe(201);
    await c.api('PUT', '/v1/consent', { kind: 'ai_tutor', granted: false }, fam.bearer);
    const t = await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/turns`, lessonTurnBody());
    expect(t.status).toBe(403);
    expect(t.body.error.code).toBe('consent_required');
    expect((await sessionStub(s.body.sessionId).info())?.endReason).toBe('consent_revoked');
  });
});

describe('delete learning history', () => {
  it('removes a device\'s sessions, usage and idempotency rows but not the purchase record', async () => {
    const c = makeClient();
    const clientId = uniqueId('del');
    const { body: { sessionId } } = await createSession(c, { clientId });
    await c.api('POST', `/v1/tutor/sessions/${sessionId}/turns`, lessonTurnBody(), { 'idempotency-key': 'd1' });
    await c.api('POST', `/v1/tutor/sessions/${sessionId}/end`);
    const r = await c.api('DELETE', `/v1/tutor/clients/${clientId}`);
    expect(r.status).toBe(200);
    expect(r.body.deleted).toEqual({ sessions: 1, usageEvents: 1, idempotency: 1 });
    expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM tutor_sessions WHERE id = ?').bind(sessionId).first<{ n: number }>())?.n).toBe(0);
    const other = await c.api('DELETE', '/v1/tutor/clients/someone-else');
    expect(other.body.deleted.sessions).toBe(0);
  });
});
