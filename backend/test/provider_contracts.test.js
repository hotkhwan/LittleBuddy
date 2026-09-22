import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { sessionMetadata, usageRecord } from '../src/providers/tutor_contract.js';
import { createProviderChain } from '../src/providers/provider_chain.js';
import { createDeepSeekProvider } from '../src/providers/deepseek_provider.js';
import { createGeminiLiveProvider } from '../src/providers/gemini_live_provider.js';
import { startServer, createSession } from './helpers.js';

test('provider-neutral metadata exposes only safe fields for all modes', () => {
  const standard = sessionMetadata({ mode: 'standard_chat', quotaRemaining: 900 });
  assert.deepEqual(Object.keys(standard), ['tier', 'mode', 'capabilities', 'quota_remaining', 'audio_mode']);
  assert.equal(standard.audio_mode, 'device');
  const premium = sessionMetadata({ tier: 'premium', mode: 'premium_live', quotaRemaining: 1800 });
  assert.equal(premium.audio_mode, 'streaming');
  assert.ok(premium.capabilities.includes('barge_in'));
  assert.throws(() => sessionMetadata({ mode: 'provider_secret_mode' }), /invalid tutor mode/);
});

test('config keeps quotas and model names configurable with requested defaults', () => {
  const defaults = loadConfig({});
  assert.equal(defaults.model, 'gpt-5.6-luna');
  assert.equal(defaults.deepseekModel, 'deepseek-flash');
  assert.equal(defaults.geminiLiveModel, 'gemini-3.8-live');
  assert.equal(defaults.premiumLiveDailySeconds, 1800);
  assert.equal(loadConfig({ PREMIUM_LIVE_DAILY_SECONDS: '900' }).premiumLiveDailySeconds, 900);
  assert.equal(loadConfig({ PREMIUM_LIVE_DAILY_SECONDS: '3600' }).premiumLiveDailySeconds, 3600);
});

test('provider chain switches on failure and records the selected provider', async () => {
  const failing = { name: 'gemini-live:test', async generateTurn() { throw new Error('disconnect'); } };
  const standard = { name: 'openai:gpt-5.6-luna', async generateTurn() { return { turn: { speech: 'Hello' }, usage: {} }; } };
  const chain = createProviderChain([failing, standard]);
  const result = await chain.generateTurn({});
  assert.equal(result.selectedProvider, standard.name);
  assert.deepEqual(result.providerFailures, [{ provider: failing.name, reason: 'disconnect' }]);
});

test('DeepSeek fake-fetch request and response obey the turn contract', async () => {
  let request;
  const provider = createDeepSeekProvider({ apiKey: 'server-test-key', fetchImpl: async (url, init) => {
    request = { url, init, body: JSON.parse(init.body) };
    return { ok: true, async json() { return { choices: [{ message: { content: JSON.stringify({ speech: 'Great!', subtitle: 'Great!', emotion: 'happy', gesture: 'clap', visual: { type: 'none', assetId: null }, lessonAction: 'complete', nextQuestion: null }) } }], usage: { prompt_tokens: 12, completion_tokens: 4, prompt_cache_hit_tokens: 2 } }; } };
  } });
  const result = await provider.generateTurn({ transcript: 'milk', lessonId: 'l', lessonContext: { stepId: 's', outcome: 'correct' } });
  assert.equal(request.url, 'https://api.deepseek.com/chat/completions');
  assert.equal(request.body.model, 'deepseek-flash');
  assert.equal(request.init.headers.authorization, 'Bearer server-test-key');
  assert.equal(result.turn.speech, 'Great!');
  assert.deepEqual(result.usage, { llmInputTokens: 12, llmOutputTokens: 4, cachedInputTokens: 2 });
});

test('Gemini Live supports barge-in, interruption, metering and graceful fallback on disconnect', async () => {
  const transports = [];
  const events = [];
  const provider = createGeminiLiveProvider({ apiKey: 'server-test-key', maxReconnects: 0, transportFactory: async () => {
    const transport = { sent: [], send(value) { this.sent.push(value); }, close() { this.onclose?.(); } };
    transports.push(transport); return transport;
  } });
  const session = provider.createSession({ quotaRemainingSeconds: 30, onEvent: (event) => events.push(event) });
  await session.connect();
  session.sendAudio(new Uint8Array([1]), 2.5);
  assert.equal(session.interrupt(), true);
  transports[0].onmessage({ data: { type: 'audio', durationSeconds: 1.25 } });
  transports[0].onclose();
  assert.equal(session.state, 'closed');
  assert.equal(events.at(-1).fallbackMode, 'standard_chat');
  assert.deepEqual(transports[0].sent.map((item) => item.type), ['audio', 'interrupt']);
  assert.deepEqual(usageRecord(session.usage()), session.usage());
  assert.equal(session.usage().audio_input_seconds, 2.5);
  assert.equal(session.usage().audio_output_seconds, 1.25);
});

test('session creation validates mode and returns sanitized tutor metadata', async () => {
  const server = await startServer();
  try {
    const created = await server.api('POST', '/api/v1/tutor/sessions', { lessonId: 'fruits_1', clientId: 'mode-client', parentApprovalToken: 'dev-parent-approval', mode: 'standard_chat' });
    assert.equal(created.status, 201);
    assert.equal(created.body.tutor.mode, 'standard_chat');
    assert.deepEqual(Object.keys(created.body.tutor), ['tier', 'mode', 'capabilities', 'quota_remaining', 'audio_mode']);
    const invalid = await server.api('POST', '/api/v1/tutor/sessions', { lessonId: 'fruits_1', clientId: 'bad-mode', parentApprovalToken: 'dev-parent-approval', mode: 'raw_provider' });
    assert.equal(invalid.status, 400);
  } finally { await server.close(); }
});
