import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { estimateTurnCost, loadPrices, utcMonthKey } from '../src/usage.js';
import { loadConfig } from '../src/config.js';
import { startServer, createSession, turnBody } from './helpers.js';

const prices = loadPrices(loadConfig({}).pricesPath);

test('prices.json cites its source and has the fields the estimator reads', () => {
  assert.match(prices._source.url, /^https:\/\/developers\.openai\.com\/api\/docs\/pricing/);
  assert.match(prices._source.fetchedOn, /^\d{4}-\d{2}-\d{2}$/);
  assert.equal(typeof prices.llm['gpt-4o-mini'].inputPer1MTokens, 'number');
  assert.equal(typeof prices.llm['gpt-4o-mini'].outputPer1MTokens, 'number');
  assert.equal(typeof prices.stt['gpt-4o-mini-transcribe'].perMinute, 'number');
  assert.equal(typeof prices.tts['tts-1'].per1MChars, 'number');
  assert.equal(prices.tts['gpt-4o-mini-tts'].per1MChars, null, 'unknown prices stay null, never invented');
});

test('cost arithmetic per turn (cloud STT + LLM + cloud TTS)', () => {
  const p = { prices, model: 'gpt-4o-mini', sttModel: 'gpt-4o-mini-transcribe', ttsModel: 'tts-1', sttMode: 'cloud', ttsMode: 'cloud' };
  const r = estimateTurnCost({ sttSeconds: 6, llmInputTokens: 600, llmOutputTokens: 60, ttsChars: 100 }, p);
  // stt: 6/60 * 0.003 = 0.0003 ; in: 600/1e6*0.15 = 0.00009 ; out: 60/1e6*0.60 = 0.000036 ; tts: 100/1e6*15 = 0.0015
  assert.equal(r.breakdown.stt, 0.0003);
  assert.equal(r.breakdown.llmInput, 0.00009);
  assert.equal(r.breakdown.llmOutput, 0.000036);
  assert.equal(r.breakdown.tts, 0.0015);
  assert.equal(r.costUsd, 0.001926);
  assert.deepEqual(r.priceMissing, []);
});

test('cost arithmetic honours cached input tokens and device-side STT/TTS', () => {
  const p = { prices, model: 'gpt-4o-mini', sttModel: 'gpt-4o-mini-transcribe', ttsModel: 'tts-1', sttMode: 'device', ttsMode: 'device' };
  const r = estimateTurnCost({ sttSeconds: 6, llmInputTokens: 600, cachedInputTokens: 400, llmOutputTokens: 60, ttsChars: 100 }, p);
  // fresh 200 * 0.15/1e6 = 0.00003 ; cached 400 * 0.075/1e6 = 0.00003 ; out 0.000036 ; stt/tts on device = 0
  assert.equal(r.breakdown.llmInput, 0.00006);
  assert.equal(r.breakdown.stt, 0);
  assert.equal(r.breakdown.tts, 0);
  assert.equal(r.costUsd, 0.000096);
});

test('cost arithmetic reports missing prices instead of inventing them', () => {
  const p = { prices, model: 'gpt-9-ultra', sttModel: 'nope', ttsModel: 'gpt-4o-mini-tts', sttMode: 'cloud', ttsMode: 'cloud' };
  const r = estimateTurnCost({ sttSeconds: 6, llmInputTokens: 10, llmOutputTokens: 1, ttsChars: 10 }, p);
  assert.equal(r.costUsd, 0);
  assert.deepEqual(r.priceMissing, ['llm:gpt-9-ultra', 'stt:nope', 'tts:gpt-4o-mini-tts']);
  const zero = estimateTurnCost({}, p);
  assert.deepEqual(zero.priceMissing, [], 'no usage, nothing missing');
});

test('monthly budget guard returns 429 quota_exhausted with reason monthly_budget, persists spend', async () => {
  // Provider "costs" 1,000,000 input tokens per turn at $0.15/M = $0.15/turn. Budget $0.20 -> 2nd turn allowed (0.15 < 0.20), 3rd refused.
  const pricey = { name: 'pricey', async generateTurn() { return { turn: { speech: 'Nice!', emotion: 'happy', gesture: 'nod', visual: { type: 'none' }, lessonAction: 'retry' }, usage: { llmInputTokens: 1_000_000, llmOutputTokens: 0 } }; } };
  const s = await startServer({ provider: pricey, env: { MONTHLY_BUDGET_USD: '0.20', TURN_CACHE_TTL_SECONDS: '0' } });
  try {
    const { body: { sessionId } } = await createSession(s.api);
    const r1 = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(r1.status, 200);
    assert.equal(r1.body.usage.costUsd, 0.15);
    const r2 = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(r2.status, 200);
    const r3 = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(r3.status, 429);
    assert.equal(r3.body.error.code, 'quota_exhausted');
    assert.equal(r3.body.error.reason, 'monthly_budget');
    assert.match(r3.body.error.message, /Come back tomorrow/);
    const newSession = await createSession(s.api, { clientId: 'someone-else' });
    assert.equal(newSession.status, 429, 'budget applies to everyone');
    const spend = await s.api('GET', '/api/v1/dev/spend');
    assert.equal(spend.body.spentUsd, 0.3);
    assert.equal(spend.body.monthKey, utcMonthKey(s.clock.t));
    const onDisk = JSON.parse(fs.readFileSync(`${s.dataDir}/spend.json`, 'utf8'));
    assert.equal(onDisk[utcMonthKey(s.clock.t)].spentUsd, 0.3, 'spend ledger persisted');
    // Next month: budget window resets.
    s.clock.t = Date.UTC(2026, 9, 1, 0, 0, 1);
    const oct = await createSession(s.api, { clientId: 'someone-else' });
    assert.equal(oct.status, 201);
  } finally {
    await s.close();
  }
});

test('per-turn usage is recorded with every field and session totals add up', async () => {
  const s = await startServer();
  try {
    const { body: { sessionId } } = await createSession(s.api);
    await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody({ audioSeconds: 4.5 }));
    await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody({ audioSeconds: 999 }));
    const entries = s.app.store.turns.values().filter((t) => t.sessionId === sessionId);
    assert.equal(entries.length, 2);
    for (const e of entries) {
      for (const f of ['sttSeconds', 'llmInputTokens', 'llmOutputTokens', 'ttsChars', 'latencyMs', 'costUsd']) assert.equal(typeof e[f], 'number', f);
      assert.equal(e.provider, 'mock');
    }
    assert.equal(entries[0].sttSeconds, 4.5);
    assert.equal(entries[1].sttSeconds, 30, 'client-reported audio seconds are clamped');
    const totals = s.app.usage.sessionTotals(sessionId);
    assert.equal(totals.turns, 2);
    assert.equal(totals.sttSeconds, 34.5);
    assert.equal(totals.ttsChars, entries[0].ttsChars + entries[1].ttsChars);
  } finally {
    await s.close();
  }
});
