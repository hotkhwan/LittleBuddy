import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, createSession, turnBody } from './helpers.js';
import { createMockProvider } from '../src/providers/mock_provider.js';
import { validateTurn, DEFAULT_ASSET_ALLOWLIST } from '../src/turn_validator.js';

/** A provider that never answers until aborted. */
function hangingProvider() {
  let calls = 0;
  return {
    name: 'hanging',
    calls: () => calls,
    generateTurn({ signal }) {
      calls += 1;
      return new Promise((_, reject) => {
        signal.addEventListener('abort', () => reject(signal.reason ?? new Error('aborted')), { once: true });
      });
    },
  };
}

/** A provider that returns a fixed turn and counts calls. */
function fixedProvider(turn, usage = { llmInputTokens: 300, llmOutputTokens: 40 }) {
  let calls = 0;
  return { name: 'fixed', calls: () => calls, async generateTurn() { calls += 1; return { turn: structuredClone(turn), usage }; } };
}

test('provider timeout -> deterministic mock fallback turn, request still succeeds', async () => {
  const provider = hangingProvider();
  const s = await startServer({ provider, env: { PROVIDER_TIMEOUT_MS: '60' } });
  try {
    const { body: { sessionId } } = await createSession(s.api);
    const started = Date.now();
    const r = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(r.status, 200);
    assert.ok(Date.now() - started < 2000);
    assert.equal(r.body.provider, 'mock');
    assert.equal(r.body.fallback, 'provider_timeout');
    assert.equal(r.body.turn.lessonAction, 'next_question');
    assert.equal(validateTurn(r.body.turn).ok, true);
    assert.equal(provider.calls(), 1);
  } finally {
    await s.close();
  }
});

test('provider error -> mock fallback; provider returning an invalid turn -> mock fallback', async () => {
  const boom = { name: 'boom', async generateTurn() { const e = new Error('http 500'); e.status = 500; throw e; } };
  let s = await startServer({ provider: boom });
  try {
    const { body: { sessionId } } = await createSession(s.api);
    const r = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(r.status, 200);
    assert.equal(r.body.fallback, 'provider_error:500');
    assert.equal(r.body.provider, 'mock');
  } finally {
    await s.close();
  }
  const naughty = fixedProvider({ speech: 'Visit www.example.com now!', emotion: 'happy', gesture: 'clap', visual: { type: 'none' }, lessonAction: 'next_question' });
  s = await startServer({ provider: naughty });
  try {
    const { body: { sessionId } } = await createSession(s.api);
    const r = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(r.status, 200);
    assert.match(r.body.fallback, /^invalid_turn:speech:url/);
    assert.equal(r.body.provider, 'mock');
    assert.doesNotMatch(r.body.turn.speech, /example\.com/);
  } finally {
    await s.close();
  }
});

test('response cache serves identical (lessonId, stepId, outcome) turns without a provider call', async () => {
  const provider = fixedProvider({ speech: 'Great! Apple! What color is the banana?', emotion: 'happy', gesture: 'clap', visual: { type: 'flashcard', assetId: 'apple_red' }, lessonAction: 'next_question', nextQuestion: 'What color is the banana?' });
  const s = await startServer({ provider });
  try {
    const a = (await createSession(s.api, { clientId: 'a' })).body.sessionId;
    const b = (await createSession(s.api, { clientId: 'b' })).body.sessionId;
    const r1 = await s.api('POST', `/api/v1/tutor/sessions/${a}/turns`, turnBody());
    assert.equal(r1.body.cached, false);
    assert.equal(r1.body.usage.llmInputTokens, 300);
    const r2 = await s.api('POST', `/api/v1/tutor/sessions/${b}/turns`, turnBody({ transcript: 'an apple please' }));
    assert.equal(r2.body.cached, true);
    assert.equal(r2.body.usage.llmInputTokens, 0);
    assert.deepEqual(r2.body.turn, r1.body.turn);
    assert.equal(provider.calls(), 1);
    // A different outcome is a different instructional beat.
    const r3 = await s.api('POST', `/api/v1/tutor/sessions/${b}/turns`, turnBody({ lessonContext: { stepId: 's1', outcome: 'incorrect', hint: 'It is red.' } }));
    assert.equal(r3.body.cached, false);
    assert.equal(provider.calls(), 2);
    // TTL expiry
    s.clock.advance(s.config.turnCacheTtlSeconds + 1);
    const r4 = await s.api('POST', `/api/v1/tutor/sessions/${a}/turns`, turnBody());
    assert.equal(r4.body.cached, false);
    assert.equal(provider.calls(), 3);
  } finally {
    await s.close();
  }
});

test('mock provider runs a full lesson deterministically and every turn validates', async () => {
  const mock = createMockProvider({ allowlist: DEFAULT_ASSET_ALLOWLIST });
  const steps = [
    { stepId: 's1', outcome: 'correct', expectedAnswers: ['apple'], nextQuestionText: 'What color is the banana?', visualAssetId: 'apple_red' },
    { stepId: 's2', outcome: 'incorrect', expectedAnswers: ['yellow'], hint: 'It is the color of the sun.', visualAssetId: 'banana_yellow' },
    { stepId: 's2', outcome: 'incorrect', expectedAnswers: ['yellow'], visualAssetId: 'banana_yellow' },
    { stepId: 's2', outcome: 'unclear', expectedAnswers: ['yellow'], lessonAction: 'next_question', nextQuestionText: 'Can you find the cat?', visualAssetId: 'banana_yellow' },
    { stepId: 's3', outcome: 'unclear', expectedAnswers: ['cat'], visualAssetId: 'cat' },
    { stepId: 's3', outcome: 'correct', expectedAnswers: ['cat'], visualAssetId: 'cat' },
  ];
  const expectedActions = ['next_question', 'give_hint', 'retry', 'next_question', 'retry', 'complete'];
  const seen = [];
  for (const [i, lessonContext] of steps.entries()) {
    const a = await mock.generateTurn({ transcript: 'x', lessonId: 'fruits_1', lessonContext });
    const b = await mock.generateTurn({ transcript: 'x', lessonId: 'fruits_1', lessonContext });
    assert.deepEqual(a, b, 'deterministic');
    const v = validateTurn(a.turn, { allowlist: DEFAULT_ASSET_ALLOWLIST });
    assert.equal(v.ok, true, `${lessonContext.stepId}: ${v.reasons.join(',')}`);
    assert.equal(v.turn.lessonAction, expectedActions[i], `step ${i}`);
    seen.push(v.turn.speech);
  }
  assert.match(seen[0], /banana/);
  assert.match(seen[1], /color of the sun/);
  assert.match(seen[5], /Great job today/);
  // Long inputs are clipped to the contract lengths.
  const long = await mock.generateTurn({ transcript: '', lessonId: 'l', lessonContext: { stepId: 's', outcome: 'correct', expectedAnswers: ['a'], nextQuestionText: 'word '.repeat(80) } });
  assert.ok(long.turn.speech.length <= 160);
  assert.ok(long.turn.nextQuestion.length <= 120);
  assert.equal(validateTurn(long.turn).ok, true);
});

test('mock provider never emits an asset outside the allowlist', async () => {
  const mock = createMockProvider({ allowlist: ['cat'] });
  const r = await mock.generateTurn({ transcript: '', lessonId: 'l', lessonContext: { stepId: 's', outcome: 'correct', visualAssetId: 'dragon' } });
  assert.deepEqual(r.turn.visual, { type: 'none' });
});

test('client cancellation propagates to the provider via AbortSignal', async () => {
  let providerSignal;
  const slow = {
    name: 'slow',
    generateTurn({ signal }) {
      providerSignal = signal;
      return new Promise((_, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    },
  };
  const s = await startServer({ provider: slow, env: { PROVIDER_TIMEOUT_MS: '5000' } });
  try {
    const { body: { sessionId } } = await createSession(s.api);
    const ac = new AbortController();
    const p = fetch(`${s.base}/api/v1/tutor/sessions/${sessionId}/turns`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(turnBody()), signal: ac.signal });
    await new Promise((r) => setTimeout(r, 50));
    assert.ok(providerSignal && !providerSignal.aborted, 'provider is running');
    ac.abort();
    await assert.rejects(p);
    await new Promise((r) => setTimeout(r, 50));
    assert.equal(providerSignal.aborted, true, 'provider call was cancelled');
    assert.equal(String(providerSignal.reason?.message), 'client_cancelled');
    assert.equal(s.app.usage.sessionTotals(sessionId).turns, 0, 'nothing recorded for a cancelled turn');
  } finally {
    await s.close();
  }
});

test('handler timeout returns 504 and aborts the in-flight work', async () => {
  const s = await startServer({ provider: hangingProvider(), env: { HANDLER_TIMEOUT_MS: '80', PROVIDER_TIMEOUT_MS: '5000' } });
  try {
    const { body: { sessionId } } = await createSession(s.api);
    const r = await s.api('POST', `/api/v1/tutor/sessions/${sessionId}/turns`, turnBody());
    assert.equal(r.status, 504);
    assert.equal(r.body.error.code, 'timeout');
  } finally {
    await s.close();
  }
});
