import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { createSession, familyClient, makeClient, sessionStub, uniqueId } from './helpers';
import { createMockTurnProvider } from '../src/tutor/mock_provider';
import type { RealtimeMintInput, TutorProvider } from '../src/tutor/provider_interface';
import { openAiFactoryWired } from '../src/tutor/provider_registry';

/** What Agent E's module will return, shaped per provider_interface.ts. */
function fakeProvider(opts: { fail?: boolean } = {}) {
  const mints: RealtimeMintInput[] = [];
  const provider: TutorProvider = {
    name: 'fake-openai',
    turns: createMockTurnProvider(),
    realtime: {
      name: 'fake-openai-realtime',
      model: 'gpt-realtime-mini',
      async mint(input) {
        mints.push(input);
        if (opts.fail) throw Object.assign(new Error('http 500'), { status: 500 });
        const expiresAt = new Date(Date.parse('2027-01-10T10:00:00.000Z') + input.expiresSeconds * 1000).toISOString();
        return {
          value: 'ek_test_not_real_1234567890',
          expiresAt,
          model: 'gpt-realtime-mini',
          turnDetection: input.turnDetection,
          wsUrl: 'wss://api.openai.com/v1/realtime?model=gpt-realtime-mini',
          subprotocols: ['realtime', 'openai-insecure-api-key.ek_test_not_real_1234567890'],
          sessionUpdate: { type: 'session.update', session: { type: 'realtime', instructions: input.instructions } },
        };
      },
    },
  };
  return { provider, mints };
}

describe('POST /v1/tutor/realtime/token', () => {
  it('is 503 provider_unavailable without OPENAI_API_KEY, DEV_MODE included', async () => {
    const c = makeClient();
    const clientId = uniqueId('rt');
    const r = await c.api('POST', '/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId });
    expect(r.status).toBe(503);
    expect(r.body.error.code).toBe('provider_unavailable');
    expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM tutor_sessions WHERE device_id = ?').bind(clientId).first<{ n: number }>())?.n).toBe(0);
  });

  it('is still 503 when a key is present: the wired OpenAI module serves turns only (realtime stays null)', async () => {
    expect(openAiFactoryWired()).toBe(true);
    const c = makeClient({ env: { OPENAI_API_KEY: 'sk-test-not-real' } });
    const r = await c.api('POST', '/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: uniqueId('rt') });
    expect(r.status).toBe(503);
  });

  it('with a provider: mints a token bound to a new quota session in the shape the CloudRealtimeTransport expects', async () => {
    const { provider, mints } = fakeProvider();
    const { c, fam } = await familyClient('rt-mint', { app: { provider } });
    const r = await c.api('POST', '/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: fam.clientId, parentApprovalToken: fam.approvalToken });
    expect(r.status).toBe(201);
    expect(r.body.clientSecret).toEqual({ value: 'ek_test_not_real_1234567890', expiresAt: Math.floor(c.clock.now() / 1000) + 330 });
    expect(r.body.token.value).toBe('ek_test_not_real_1234567890');
    expect(r.body.wsUrl).toMatch(/^wss:\/\//);
    expect(r.body.subprotocols).toEqual(['realtime', 'openai-insecure-api-key.ek_test_not_real_1234567890']);
    expect(r.body.sessionUpdate.type).toBe('session.update');
    expect(r.body.expiresInSeconds).toBe(330);
    expect(r.body.quotaSessionId).toBe(r.body.sessionId);
    expect(r.body.realtime).toMatchObject({ model: 'gpt-realtime-mini', turnDetection: 'semantic_vad', mock: false });
    expect(r.body.quota.usedTurns).toBe(1);
    expect(r.body.lessonKnown).toBe(true);
    expect(mints[0].expiresSeconds).toBe(330); // remaining 300 + 30 grace
    expect(mints[0].instructions).toMatch(/What colour is this\?/);
    expect(mints[0].instructions).not.toMatch(new RegExp(`${fam.clientId}|session id`, 'i'));
    const row = await env.DB.prepare('SELECT mode FROM tutor_sessions WHERE id = ?').bind(r.body.sessionId).first<{ mode: string }>();
    expect(row?.mode).toBe('realtime');
  });

  it('requires voice consent on top of ai_tutor consent', async () => {
    const { provider } = fakeProvider();
    const boot = makeClient({ defaultToken: null, app: { provider } });
    const clientId = uniqueId('nv');
    const r0 = await boot.api('POST', '/v1/parents', { provider: 'dev', subject: uniqueId('novoice'), clientId });
    const bearer = { authorization: `Bearer ${r0.body.parentToken}`, 'x-parent-approval': '' };
    await boot.api('PUT', '/v1/consent', { kind: 'ai_tutor', granted: true }, bearer);
    const r = await boot.api('POST', '/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId }, { 'x-parent-approval': r0.body.parentApprovalToken });
    expect(r.status).toBe(403);
    expect(r.body.error).toMatchObject({ code: 'consent_required', kind: 'voice' });
  });

  it('links an existing open session, charges the realtime clock uncapped, and expires with the token', async () => {
    const { provider } = fakeProvider();
    const { c, fam } = await familyClient('rt-link', { app: { provider } });
    const s = await createSession(c, { fresh: false, token: fam.approvalToken, clientId: fam.clientId });
    const sessionId = s.body.sessionId;
    const r = await c.api('POST', '/v1/tutor/realtime/token', { sessionId });
    expect(r.status).toBe(201);
    expect(r.body.sessionId).toBe(sessionId);
    c.clock.advance(100);
    const q = await c.api('GET', '/v1/tutor/quota');
    expect(q.body.quota.usedSeconds).toBe(0); // settled lazily on the session's next event
    const u = await c.api('POST', `/v1/tutor/sessions/${sessionId}/usage`, { responses: 2, inputAudioTokens: 600, outputAudioTokens: 1200, inputTextTokens: 900, outputTextTokens: 120, inputAudioSeconds: 20, outputAudioSeconds: 30 });
    expect(u.status).toBe(200);
    expect(u.body.quota.usedSeconds).toBe(100); // not capped at 45: bounded by the token instead
    expect(u.body.recorded.costUsd).toBeGreaterThan(0);
    expect(u.body.recorded.priceMissing).toEqual([]);
    const ev = await env.DB.prepare("SELECT tokens_in, tokens_out, audio_seconds, cost_usd_micro FROM usage_events WHERE session_id = ? AND kind = 'realtime_usage'").bind(sessionId).first<{ tokens_in: number; tokens_out: number; audio_seconds: number; cost_usd_micro: number }>();
    expect(ev).toMatchObject({ tokens_in: 1500, tokens_out: 1320, audio_seconds: 50 });
    expect(ev?.cost_usd_micro).toBeGreaterThan(0);
    const rejected = await c.api('POST', `/v1/tutor/sessions/${sessionId}/usage`, { usedSeconds: 1 });
    expect(rejected.status).toBe(400);
    const tick = await sessionStub(sessionId).tick(c.clock.now() + 400_000);
    expect(tick).toEqual({ ended: true, reason: 'token_expired' });
    const after = await c.api('GET', '/v1/tutor/quota');
    expect(after.body.quota.usedSeconds).toBe(300); // charged to the token expiry, never past allowance + grace; the view caps at the allowance
  });

  it('a provider failure is 503 and leaves the session unbound (no mint counted)', async () => {
    const { provider } = fakeProvider({ fail: true });
    const { c, fam } = await familyClient('rt-fail', { app: { provider } });
    const s = await createSession(c, { fresh: false, token: fam.approvalToken, clientId: fam.clientId });
    expect(s.status).toBe(201);
    const r = await c.api('POST', '/v1/tutor/realtime/token', { sessionId: s.body.sessionId });
    expect(r.status).toBe(503);
    expect((await sessionStub(s.body.sessionId).info())?.realtime).toBeNull();
    const q = await c.api('GET', '/v1/tutor/quota');
    expect(q.body.quota.usedTurns).toBe(0);
  });

  it('turns are refused on a realtime session and usage reports on a turn session', async () => {
    const { provider } = fakeProvider();
    const { c, fam } = await familyClient('rt-mix', { app: { provider } });
    const s = await createSession(c, { fresh: false, token: fam.approvalToken, clientId: fam.clientId });
    expect(s.status).toBe(201);
    expect((await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/usage`, { responses: 1 })).status).toBe(400);
    expect((await c.api('POST', '/v1/tutor/realtime/token', { sessionId: s.body.sessionId })).status).toBe(201);
    const t = await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/turns`, { transcript: 'red', lessonContext: { stepId: 's02_red', outcome: 'correct' } });
    expect(t.status).toBe(400);
  });
});
