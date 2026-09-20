// Realtime: ephemeral client-secret minting + usage reports. No real network:
// the OpenAI fetch is always injected.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, createSession, DEV_TOKEN, FIXTURE_LESSONS_DIR } from './helpers.js';
import { createRealtimeTokenMinter, buildRealtimeInstructions, REALTIME_MAX_EXPIRY_SECONDS } from '../src/providers/openai_realtime.js';
import { loadLessons } from '../src/lessons.js';
import { estimateTurnCost, loadPrices } from '../src/usage.js';
import { loadConfig } from '../src/config.js';

const lesson = loadLessons(FIXTURE_LESSONS_DIR).lessons.get('colors_red_blue');

/** Fake OpenAI client_secrets endpoint recording requests. */
function fakeOpenAI(nowSeconds = 1_800_000_000) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    const seconds = JSON.parse(init.body).expires_after.seconds;
    return { ok: true, status: 200, async json() { return { value: 'ek_test_not_real_1234567890', expires_at: nowSeconds + seconds, session: { id: 'sess_fake', object: 'realtime.session' } }; } };
  };
  return { calls, fetchImpl };
}

test('minter: request shape follows the client_secrets contract, key stays server-side', async () => {
  const { calls, fetchImpl } = fakeOpenAI();
  const m = createRealtimeTokenMinter({ apiKey: 'test-key-not-real', fetchImpl, model: 'gpt-realtime-mini', voice: 'marin', extraHeaders: { authorization: 'Bearer attacker', 'x-project': 'p' } });
  const out = await m.mint({ instructions: buildRealtimeInstructions(lesson), expiresSeconds: 330, turnDetection: 'semantic_vad' });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://api.openai.com/v1/realtime/client_secrets');
  assert.equal(calls[0].init.method, 'POST');
  assert.equal(calls[0].init.headers.authorization, 'Bearer test-key-not-real');
  assert.equal(calls[0].init.headers['x-project'], 'p');
  const b = calls[0].body;
  assert.deepEqual(b.expires_after, { anchor: 'created_at', seconds: 330 });
  assert.equal(b.session.type, 'realtime');
  assert.equal(b.session.model, 'gpt-realtime-mini');
  assert.deepEqual(b.session.output_modalities, ['audio']);
  assert.equal(b.session.tool_choice, 'none');
  assert.deepEqual(b.session.tools, []);
  assert.equal(b.session.max_output_tokens, 400);
  assert.deepEqual(b.session.audio.input.turn_detection, { type: 'semantic_vad', eagerness: 'low', create_response: true, interrupt_response: true });
  assert.deepEqual(b.session.audio.input.transcription, { model: 'gpt-4o-mini-transcribe', language: 'en' });
  assert.deepEqual(b.session.audio.input.noise_reduction, { type: 'near_field' });
  assert.equal(b.session.audio.output.voice, 'marin');
  assert.match(b.session.instructions, /aged 3 to 6/);
  assert.match(b.session.instructions, /Never ask the child personal questions/);
  assert.match(b.session.instructions, /What colour is this\?/, 'lesson steps come from the server lesson file');
  assert.doesNotMatch(b.session.instructions, /client|session id|device/i);
  assert.equal(out.value, 'ek_test_not_real_1234567890');
  assert.equal(out.expiresAt, new Date((1_800_000_000 + 330) * 1000).toISOString());
  assert.equal(out.turnDetection, 'semantic_vad');
});

test('minter: server_vad variant, expiry clamped to 10..7200, errors throw', async () => {
  const { calls, fetchImpl } = fakeOpenAI();
  const m = createRealtimeTokenMinter({ apiKey: 'k', fetchImpl });
  await m.mint({ instructions: 'x', expiresSeconds: 999_999, turnDetection: 'server_vad' });
  assert.equal(calls[0].body.expires_after.seconds, REALTIME_MAX_EXPIRY_SECONDS);
  assert.equal(calls[0].body.session.audio.input.turn_detection.type, 'server_vad');
  assert.equal(calls[0].body.session.audio.input.turn_detection.interrupt_response, true);
  await m.mint({ instructions: 'x', expiresSeconds: 1 });
  assert.equal(calls[1].body.expires_after.seconds, 10);
  const bad = createRealtimeTokenMinter({ apiKey: 'k', fetchImpl: async () => ({ ok: false, status: 429, async json() { return {}; } }) });
  await assert.rejects(bad.mint({ instructions: 'x', expiresSeconds: 60 }), /http 429/);
  const empty = createRealtimeTokenMinter({ apiKey: 'k', fetchImpl: async () => ({ ok: true, status: 200, async json() { return {}; } }) });
  await assert.rejects(empty.mint({ instructions: 'x', expiresSeconds: 60 }), /no value/);
  assert.throws(() => createRealtimeTokenMinter({ apiKey: '' }), /OPENAI_API_KEY/);
});

test('POST /realtime/token: DEV_MODE without a key returns a mock token bound to a new quota session', async () => {
  const s = await startServer();
  try {
    const noApproval = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'kid' }, { 'x-parent-approval': '' });
    assert.equal(noApproval.status, 403);
    const r = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'kid' });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(r.body.token.value, 'dev-realtime-token');
    assert.equal(r.body.realtime.mock, true);
    assert.ok(r.body.sessionId);
    // free: 300 s remaining + 30 s grace
    assert.equal(Date.parse(r.body.token.expiresAt), s.clock.t + 330 * 1000);
    assert.equal(r.body.quota.usedTurns, 1, 'a mint counts as one provider call');
    assert.ok(s.app.store.sessions.get(r.body.sessionId).realtime);
    // linking an existing session
    const again = await s.api('POST', '/api/v1/tutor/realtime/token', { sessionId: r.body.sessionId });
    assert.equal(again.status, 201);
    assert.equal(again.body.sessionId, r.body.sessionId);
    const otherToken = await s.api('POST', '/api/v1/tutor/realtime/token', { sessionId: r.body.sessionId }, { 'x-parent-approval': s.app.approval.mint('kid') });
    assert.equal(otherToken.status, 403, 'session ownership applies');
  } finally {
    await s.close();
  }
});

test('POST /realtime/token: without a key outside DEV_MODE -> 503 provider_unavailable', async () => {
  const s = await startServer({ env: { DEV_MODE: '0' } });
  try {
    const token = s.app.approval.mint('kid');
    const r = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'kid' }, { 'x-parent-approval': token });
    assert.equal(r.status, 503);
    assert.equal(r.body.error.code, 'provider_unavailable');
  } finally {
    await s.close();
  }
});

test('POST /realtime/token: with a key, mints via OpenAI with expiry = remaining + 30 s; the game never sees the key', async () => {
  const { calls, fetchImpl } = fakeOpenAI(Math.floor(Date.UTC(2026, 8, 20, 10) / 1000));
  const s = await startServer({ env: { OPENAI_API_KEY: 'test-key-not-real', TUTOR_PROVIDER: 'mock', FAMILY_CLUB_DAILY_SECONDS: '1800' }, fetchImpl });
  try {
    await s.api('POST', '/api/v1/dev/entitlement', { clientId: 'fam', entitlement: 'family_club' });
    // burn 100 s on a normal session first
    const { body: { sessionId } } = await createSession(s.api, { clientId: 'fam', lessonId: 'colors_red_blue' });
    s.clock.advance(40);
    await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, { transcript: 'red', lessonContext: { stepId: 's02_red', outcome: 'correct' } });
    await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/end`);
    const r = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'fam' });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(calls.length, 1);
    assert.equal(calls[0].body.expires_after.seconds, 1800 - 40 + 30);
    assert.equal(r.body.token.value, 'ek_test_not_real_1234567890');
    assert.equal(r.body.realtime.mock, false);
    assert.equal(r.body.realtime.model, 'gpt-realtime-mini');
    assert.doesNotMatch(JSON.stringify(r.body), /test-key-not-real/, 'permanent key never in a response');
    // provider failure -> 503
    const failing = await startServer({ env: { OPENAI_API_KEY: 'test-key-not-real', TUTOR_PROVIDER: 'mock' }, fetchImpl: async () => ({ ok: false, status: 500, async json() { return {}; } }) });
    try {
      const f = await failing.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'x' });
      assert.equal(f.status, 503);
      assert.equal(f.body.error.code, 'provider_unavailable');
    } finally {
      await failing.close();
    }
  } finally {
    await s.close();
  }
});

test('POST /realtime/token: refused when quota or turn cap is exhausted or budget spent', async () => {
  const s = await startServer({ env: { FREE_DAILY_TURNS: '1' } });
  try {
    const first = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'kid' });
    assert.equal(first.status, 201);
    const second = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'kid' });
    assert.equal(second.status, 429);
    assert.equal(second.body.error.reason, 'daily_turns');
  } finally {
    await s.close();
  }
});

test('realtime quota: the server clock is the authority, bounded by the token expiry, not by client reports', async () => {
  const s = await startServer();
  try {
    const r = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'kid' });
    const id = r.body.sessionId;
    // 60 s of streaming, then a usage report: charged 60 s (not capped at the 45 s per-turn cap)
    s.clock.advance(60);
    const u1 = await s.api('POST', `/api/v1/tutor/sessions/${id}/usage`, { inputAudioTokens: 600, outputAudioTokens: 1200, inputAudioSeconds: 20, outputAudioSeconds: 30, responses: 3 });
    assert.equal(u1.status, 200, JSON.stringify(u1.body));
    assert.equal(u1.body.quota.usedSeconds, 60);
    assert.equal(u1.body.quota.usedTurns, 2, 'mint + report');
    assert.ok(u1.body.recorded.costUsd > 0);
    // client timers are rejected as authority
    const cheat = await s.api('POST', `/api/v1/tutor/sessions/${id}/usage`, { usedSeconds: 1 });
    assert.equal(cheat.status, 400);
    // silence for 10 minutes: charged only up to the token expiry (300 + 30 s), never more
    s.clock.advance(600);
    const ent = await s.api('GET', '/api/v1/tutor/entitlement?clientId=kid');
    assert.equal(ent.body.quota.usedSeconds, 300, 'clamped to the allowance (grace covers the token tail only)');
    assert.equal(ent.body.quota.remainingSeconds, 0);
    const late = await s.api('POST', `/api/v1/tutor/sessions/${id}/usage`, { inputAudioTokens: 10 });
    assert.equal(late.status, 200);
    assert.equal(late.body.endAtBoundary, true);
    const more = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'kid' });
    assert.equal(more.status, 429, 'no new token once the day is used up');
    const end = await s.api('POST', `/api/v1/tutor/sessions/${id}/end`);
    assert.equal(end.status, 200);
    assert.equal(end.body.usage.turns, 2);
    // a fresh clientId cannot piggy-back: needs its own approval (dev token in DEV_MODE approves any client, so use a signed token)
    const trick = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'kid-2' }, { 'x-parent-approval': s.app.approval.mint('kid') });
    assert.equal(trick.status, 403);
  } finally {
    await s.close();
  }
});

test('realtime usage: only realtime sessions accept reports; fields clamped; cost uses realtime prices', async () => {
  const s = await startServer();
  try {
    const { body: { sessionId } } = await createSession(s.api, { lessonId: 'colors_red_blue' });
    const notRt = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/usage`, { inputAudioTokens: 1 });
    assert.equal(notRt.status, 400);
    const r = await s.api('POST', '/api/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'kid' });
    const u = await s.api('POST', `/api/v1/tutor/sessions/${r.body.sessionId}/usage`, { inputAudioTokens: 1_000_000, outputAudioTokens: -5, inputAudioSeconds: 99999 });
    assert.equal(u.status, 200);
    assert.equal(u.body.recorded.costUsd, 10, '1M audio input tokens at gpt-realtime-mini list price');
    const row = s.app.store.turns.values().find((t) => t.sessionId === r.body.sessionId);
    assert.equal(row.realtime.realtimeAudioOutputTokens, 0);
    assert.equal(row.realtime.reportedInputAudioSeconds, 7200);
    assert.equal(row.provider, 'openai-realtime:mock');
  } finally {
    await s.close();
  }
});

test('realtime cost arithmetic and prices.json entries', () => {
  const prices = loadPrices(loadConfig({}).pricesPath);
  assert.equal(prices.realtime.audioTokensPerMinute, null, 'tokens-per-minute is not on the pricing page; left null');
  assert.equal(prices.realtime['gpt-realtime-mini'].audioInputPer1MTokens, 10);
  assert.equal(prices.realtime['gpt-realtime-mini'].audioOutputPer1MTokens, 20);
  assert.equal(prices.realtime['gpt-realtime'].audioInputPer1MTokens, 32);
  assert.equal(prices.realtime['gpt-realtime'].audioOutputPer1MTokens, 64);
  const p = { prices, model: 'gpt-4o-mini', sttMode: 'device', ttsMode: 'device', realtimeModel: 'gpt-realtime-mini' };
  const r = estimateTurnCost({ realtimeAudioInputTokens: 3000, realtimeCachedAudioInputTokens: 1000, realtimeAudioOutputTokens: 6000, realtimeTextInputTokens: 2000, realtimeTextOutputTokens: 100 }, p);
  // in: 2000*10/1e6=0.02 + cached 1000*0.30/1e6=0.0003 ; out: 6000*20/1e6=0.12 ; text in 2000*0.60/1e6=0.0012 ; text out 100*2.40/1e6=0.00024
  assert.equal(r.breakdown.realtime, 0.14174);
  assert.equal(r.costUsd, 0.14174);
  const missing = estimateTurnCost({ realtimeAudioInputTokens: 1 }, { ...p, realtimeModel: 'gpt-4o-realtime-preview' });
  assert.deepEqual(missing.priceMissing, ['realtime:gpt-4o-realtime-preview']);
});
