import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createOpenAIProvider, TUTOR_TURN_SCHEMA, SYSTEM_PROMPT, buildUserMessage, asciiNormalize } from '../src/providers/openai_provider.js';
import { validateTurn } from '../src/turn_validator.js';

const completion = (content, usage = { prompt_tokens: 321, completion_tokens: 42, prompt_tokens_details: { cached_tokens: 200 } }) => ({
  ok: true,
  status: 200,
  async json() { return { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify(content) } }], usage }; },
});

test('openai provider: request shape (never a real network call)', async () => {
  /** @type {any[]} */
  const calls = [];
  const fakeFetch = async (url, init) => {
    calls.push({ url, init });
    return completion({ speech: 'Great! Apple! What color is the banana?', subtitle: null, emotion: 'happy', gesture: 'clap', visual: { type: 'flashcard', assetId: 'apple_red' }, lessonAction: 'next_question', nextQuestion: 'What color is the banana?' });
  };
  const p = createOpenAIProvider({ apiKey: 'test-key-not-real', model: 'gpt-4o-mini', fetchImpl: fakeFetch, extraHeaders: { 'x-data-retention': 'zdr', authorization: 'Bearer attacker' } });
  const ac = new AbortController();
  const result = await p.generateTurn({
    transcript: 'apple',
    lessonId: 'fruits_1',
    lessonContext: { stepId: 's1', outcome: 'correct', expectedAnswers: ['apple'], nextQuestionText: 'What color is the banana?', visualAssetId: 'apple_red' },
    signal: ac.signal,
  });

  assert.equal(calls.length, 1);
  const { url, init } = calls[0];
  assert.equal(url, 'https://api.openai.com/v1/chat/completions');
  assert.equal(init.method, 'POST');
  assert.equal(init.headers.authorization, 'Bearer test-key-not-real');
  assert.equal(init.headers['content-type'], 'application/json');
  assert.equal(init.headers['x-data-retention'], 'zdr', 'extra header hook is applied');
  assert.equal(init.headers.authorization, 'Bearer test-key-not-real', 'extra headers cannot override authorization');
  assert.equal(init.signal, ac.signal, 'abort signal is passed to fetch');

  const body = JSON.parse(init.body);
  assert.equal(body.model, 'gpt-4o-mini');
  assert.equal(body.store, false, 'asks the provider not to retain the completion');
  assert.ok(body.max_tokens <= 200);
  assert.equal(body.response_format.type, 'json_schema');
  assert.equal(body.response_format.json_schema.strict, true);
  assert.deepEqual(body.response_format.json_schema, TUTOR_TURN_SCHEMA);
  assert.equal(body.messages[0].role, 'system');
  assert.equal(body.messages[0].content, SYSTEM_PROMPT);
  assert.match(SYSTEM_PROMPT, /160 characters/);
  assert.match(SYSTEM_PROMPT, /3 to 6/);
  assert.match(SYSTEM_PROMPT, /Never ask the child personal questions/);
  assert.equal(body.messages[1].role, 'user');
  assert.match(body.messages[1].content, /childSaid: apple/);
  assert.doesNotMatch(body.messages[1].content, /client|session|name|age|device/i, 'no PII fields in the prompt');

  assert.equal(result.usage.llmInputTokens, 321);
  assert.equal(result.usage.llmOutputTokens, 42);
  assert.equal(result.usage.cachedInputTokens, 200);
  const v = validateTurn(result.turn);
  assert.equal(v.ok, true, v.reasons.join(','));
  assert.equal(v.turn.subtitle, v.turn.speech, 'null subtitle defaults to speech');
});

test('openai provider: schema mirrors TutorTurn enums and is strict', () => {
  const s = TUTOR_TURN_SCHEMA.schema;
  assert.equal(s.additionalProperties, false);
  assert.deepEqual(s.required.sort(), ['emotion', 'gesture', 'lessonAction', 'nextQuestion', 'speech', 'subtitle', 'visual'].sort());
  assert.deepEqual(s.properties.emotion.enum, ['neutral', 'listening', 'thinking', 'happy', 'encouraging', 'smile']);
  assert.deepEqual(s.properties.gesture.enum, ['none', 'nod', 'tilt', 'point', 'clap', 'wave', 'thumbsUp', 'celebrate', 'listening', 'thinking', 'encourage']);
  assert.deepEqual(s.properties.visual.properties.type.enum, ['none', 'flashcard', 'model']);
  assert.deepEqual(s.properties.lessonAction.enum, ['next_question', 'retry', 'give_hint', 'complete', 'end_session', 'switch_lesson', 'jump_step']);
  assert.equal(s.properties.visual.additionalProperties, false);
});

test('openai provider: curly quotes and emoji are normalised before validation', async () => {
  const fakeFetch = async () => completion({ speech: '“Great!” Let’s go 🍎', subtitle: null, emotion: 'happy', gesture: 'clap', visual: { type: 'none', assetId: null }, lessonAction: 'retry', nextQuestion: null });
  const p = createOpenAIProvider({ apiKey: 'k', fetchImpl: fakeFetch });
  const r = await p.generateTurn({ transcript: '', lessonId: 'l', lessonContext: { stepId: 's', outcome: 'unclear' } });
  assert.equal(r.turn.speech, '"Great!" Let\'s go');
  assert.equal(r.turn.nextQuestion, undefined);
  assert.deepEqual(r.turn.visual, { type: 'none', assetId: undefined });
  assert.equal(validateTurn(r.turn).ok, true);
  assert.equal(asciiNormalize('a – b…'), 'a - b...');
});

test('openai provider: HTTP errors, refusals and bad JSON throw (caller falls back)', async () => {
  const p500 = createOpenAIProvider({ apiKey: 'k', fetchImpl: async () => ({ ok: false, status: 503, async json() { return {}; } }) });
  await assert.rejects(p500.generateTurn({ transcript: '', lessonId: 'l', lessonContext: { stepId: 's', outcome: 'correct' } }), /openai http 503/);
  const refusal = createOpenAIProvider({ apiKey: 'k', fetchImpl: async () => ({ ok: true, status: 200, async json() { return { choices: [{ message: { refusal: 'no' } }] }; } }) });
  await assert.rejects(refusal.generateTurn({ transcript: '', lessonId: 'l', lessonContext: { stepId: 's', outcome: 'correct' } }), /no usable completion/);
  const bad = createOpenAIProvider({ apiKey: 'k', fetchImpl: async () => ({ ok: true, status: 200, async json() { return { choices: [{ message: { content: 'not json' } }] }; } }) });
  await assert.rejects(bad.generateTurn({ transcript: '', lessonId: 'l', lessonContext: { stepId: 's', outcome: 'correct' } }), /non-JSON/);
  assert.throws(() => createOpenAIProvider({ apiKey: '' }), /OPENAI_API_KEY/);
});

test('openai provider: user message contains only lesson context and transcript', () => {
  const msg = buildUserMessage({ transcript: 'x'.repeat(500), lessonId: 'l1', lessonContext: { stepId: 's1', outcome: 'correct', expectedAnswers: ['a', 'b'], hint: 'h', nextQuestionText: 'n', visualAssetId: 'cat' } });
  const lines = msg.split('\n').map((l) => l.split(':')[0]);
  assert.deepEqual(lines, ['lessonId', 'stepId', 'outcome', 'expectedAnswers', 'hint', 'nextQuestionText', 'visualAssetId', 'childSaid']);
  assert.ok(msg.length < 400, 'transcript is truncated to 200 chars');
});
