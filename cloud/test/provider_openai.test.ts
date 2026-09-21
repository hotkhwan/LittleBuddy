// The OpenAI turn provider against a FAKE fetch. No key exists on this
// machine or on the dev Worker, so the live path is never exercised here:
// these tests pin the request shape, the mapping of a structured-output reply
// to a TutorTurn candidate, the fallbacks (invalid JSON, refusal, timeout,
// HTTP errors with one retry), the usage numbers and the no-logging rule.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createOpenAIProvider } from '../src/tutor/provider/openai/index';
import { parseTurn } from '../src/tutor/provider/openai/turns';
import { validateTurn } from '../src/tutor/turn_validator';
import { gateChatTurn } from '../src/tutor/chat_provider';
import { ASSET_ALLOWLIST } from '../src/tutor/content';
import { resolveLessonContext, LESSONS } from '../src/tutor/lessons';
import type { ProviderFactoryOptions } from '../src/tutor/provider_interface';

const KEY = 'sk-test-not-a-real-key-000000000000';

interface Call { url: string; init: RequestInit; body: any }

function fakeFetch(handler: (call: Call, n: number) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const impl: typeof fetch = async (input, init) => {
    const call: Call = { url: String(input), init: init ?? {}, body: init?.body ? JSON.parse(String(init.body)) : null };
    calls.push(call);
    return handler(call, calls.length);
  };
  return { impl, calls };
}

function completion(content: unknown, usage: Record<string, unknown> = { prompt_tokens: 120, completion_tokens: 30, prompt_tokens_details: { cached_tokens: 100 } }) {
  return new Response(JSON.stringify({ id: 'chatcmpl-test', choices: [{ index: 0, message: { role: 'assistant', content: typeof content === 'string' ? content : JSON.stringify(content) } }], usage }), { status: 200, headers: { 'content-type': 'application/json' } });
}

function provider(fetchImpl: typeof fetch, extra: Partial<ProviderFactoryOptions> & Record<string, unknown> = {}) {
  return createOpenAIProvider({ apiKey: KEY, model: 'gpt-4o-mini', realtimeModel: 'gpt-realtime-mini', realtimeVoice: 'marin', fetchImpl, ...extra });
}

function lessonCtx() {
  const lesson = LESSONS.get('colors_red_blue')!;
  return resolveLessonContext(lesson, { stepId: 's02_red', outcome: 'correct', matched: 'red', lessonAction: 'next_question' })!;
}

const VALID_LESSON_REPLY = { speech: 'Great! Red! What colour is this?', emotion: 'happy', gesture: 'clap', visual: { type: 'flashcard', assetId: 'color_red' }, lessonAction: 'next_question', nextQuestion: 'What colour is this?' };
const VALID_CHAT_REPLY = { speech: 'Cats eat cat food and drink water. Do you have a pet?', emotion: 'happy', gesture: 'nod', visual: { type: 'flashcard', assetId: 'cat' }, lessonAction: 'none', nextQuestion: '' };

describe('createOpenAIProvider', () => {
  afterEach(() => vi.restoreAllMocks());

  it('is a TutorProvider for the turns path only: realtime stays null so the token route keeps answering 503', () => {
    const p = provider(fakeFetch(() => completion(VALID_LESSON_REPLY)).impl);
    expect(p.name).toBe('openai:gpt-4o-mini');
    expect(p.realtime).toBeNull();
    expect(typeof p.turns.generateTurn).toBe('function');
    expect(typeof (p.turns as unknown as { generateChatTurn: unknown }).generateChatTurn).toBe('function');
  });

  it('lesson turn: posts Chat Completions with a strict TutorTurn schema, the key only in the header, low temperature, bounded tokens; maps the reply to a valid TutorTurn with usage', async () => {
    const f = fakeFetch(() => completion(VALID_LESSON_REPLY));
    const p = provider(f.impl, { maxOutputTokens: 120 });
    const r = await p.turns.generateTurn({ transcript: 'red', lessonId: 'colors_red_blue', lessonContext: lessonCtx(), signal: new AbortController().signal });
    expect(f.calls).toHaveLength(1);
    const call = f.calls[0];
    expect(call.url).toBe('https://api.openai.com/v1/chat/completions');
    expect((call.init.headers as Record<string, string>).authorization).toBe(`Bearer ${KEY}`);
    expect(JSON.stringify(call.body)).not.toContain(KEY);
    expect(call.body).toMatchObject({ model: 'gpt-4o-mini', temperature: 0.3, max_tokens: 120 });
    expect(call.body.response_format.type).toBe('json_schema');
    expect(call.body.response_format.json_schema.strict).toBe(true);
    const schema = call.body.response_format.json_schema.schema;
    expect(schema.additionalProperties).toBe(false);
    expect(schema.properties.lessonAction.enum).toContain('next_question');
    expect(schema.properties.lessonAction.enum).not.toContain('none');
    expect(schema.properties.visual.properties.assetId.enum).toEqual(['', ...ASSET_ALLOWLIST.ids]);
    expect(call.body.messages[0].role).toBe('system');
    expect(call.body.messages[0].content).toMatch(/outcome = correct/);
    expect(call.body.messages[0].content).toMatch(/Never ask for or repeat personal information/);
    expect(call.body.messages[1]).toEqual({ role: 'user', content: 'The child said (transcript, may be empty or misheard): "red"' });
    const v = validateTurn(r.turn, { allowlist: ASSET_ALLOWLIST.ids });
    expect(v.ok, v.reasons.join(',')).toBe(true);
    expect(v.turn).toMatchObject({ speech: 'Great! Red! What colour is this?', subtitle: 'Great! Red! What colour is this?', emotion: 'happy', gesture: 'clap', visual: { type: 'flashcard', assetId: 'color_red' }, lessonAction: 'next_question', nextQuestion: 'What colour is this?' });
    expect(r.usage).toEqual({ llmInputTokens: 120, llmOutputTokens: 30, cachedInputTokens: 100 });
  });

  it('chat turn: free-chat persona with the word cap, the rolling window as prior messages, lessonAction pinned to "none"; the gate accepts the reply', async () => {
    const f = fakeFetch(() => completion(VALID_CHAT_REPLY, { prompt_tokens: 80, completion_tokens: 20 }));
    const p = provider(f.impl);
    const chat = p.turns as unknown as { generateChatTurn: (i: unknown) => Promise<{ turn: unknown; usage: unknown }> };
    const r = await chat.generateChatTurn({ transcript: 'what do cats eat', history: [{ role: 'child', text: 'hello' }, { role: 'tutor', text: 'Hello! What do you want to talk about?' }], responseMaxWords: 18, signal: new AbortController().signal });
    const call = f.calls[0];
    expect(call.body.messages.map((m: { role: string }) => m.role)).toEqual(['system', 'user', 'assistant', 'user']);
    expect(call.body.messages[0].content).toMatch(/at most 18 words/);
    expect(call.body.messages[0].content).toMatch(/kind, playful English teacher for a child aged 3 to 6/);
    expect(call.body.messages[0].content).toMatch(/I'm not sure, let's find out together!/);
    expect(call.body.messages[0].content).toMatch(/no name, age, home, address, school/);
    expect(call.body.messages[3]).toEqual({ role: 'user', content: 'what do cats eat' });
    expect(call.body.response_format.json_schema.schema.properties.lessonAction.enum).toEqual(['none']);
    const g = gateChatTurn(r.turn, { responseMaxWords: 18, allowlist: ASSET_ALLOWLIST.ids });
    expect(g.ok, g.reasons.join(',')).toBe(true);
    expect(g.turn).toEqual({ speech: 'Cats eat cat food and drink water. Do you have a pet?', subtitle: 'Cats eat cat food and drink water. Do you have a pet?', emotion: 'happy', gesture: 'nod', visual: { type: 'flashcard', assetId: 'cat' }, lessonAction: 'none' });
    expect(r.usage).toEqual({ llmInputTokens: 80, llmOutputTokens: 20 });
  });

  it('invalid JSON, a refusal or an empty message -> turn null (the validator then falls back); usage is still recorded', async () => {
    const f = fakeFetch((_c, n) => {
      if (n === 1) return completion('{"speech": "oops', { prompt_tokens: 5, completion_tokens: 1 });
      if (n === 2) return new Response(JSON.stringify({ choices: [{ message: { role: 'assistant', content: null, refusal: 'I cannot help with that.' } }], usage: { prompt_tokens: 7, completion_tokens: 2 } }), { status: 200 });
      return new Response(JSON.stringify({ choices: [], usage: {} }), { status: 200 });
    });
    const p = provider(f.impl);
    const input = { transcript: 'x', lessonId: 'colors_red_blue', lessonContext: lessonCtx(), signal: new AbortController().signal };
    const a = await p.turns.generateTurn(input);
    expect(a.turn).toBeNull();
    expect(a.usage).toEqual({ llmInputTokens: 5, llmOutputTokens: 1 });
    expect(validateTurn(a.turn).ok).toBe(false);
    const b = await p.turns.generateTurn(input);
    expect(b.turn).toBeNull();
    expect(b.usage).toEqual({ llmInputTokens: 7, llmOutputTokens: 2 });
    const c = await p.turns.generateTurn(input);
    expect(c.turn).toBeNull();
    expect(c.usage).toEqual({ llmInputTokens: 0, llmOutputTokens: 0 });
    expect(parseTurn('[1,2]')).toBeNull();
    expect(parseTurn('"text"')).toBeNull();
  });

  it('a 5xx / 429 is retried once, then thrown with its status; a 4xx is not retried', async () => {
    const f = fakeFetch((_c, n) => (n === 1 ? new Response('{"error":{"message":"overloaded"}}', { status: 503 }) : completion(VALID_LESSON_REPLY)));
    const p = provider(f.impl);
    const input = { transcript: 'red', lessonId: 'colors_red_blue', lessonContext: lessonCtx(), signal: new AbortController().signal };
    const r = await p.turns.generateTurn(input);
    expect(f.calls).toHaveLength(2);
    expect(validateTurn(r.turn).ok).toBe(true);

    const g = fakeFetch(() => new Response('{}', { status: 500 }));
    await expect(provider(g.impl).turns.generateTurn(input)).rejects.toMatchObject({ status: 500 });
    expect(g.calls).toHaveLength(2);

    const h = fakeFetch(() => new Response('{"error":{"message":"bad key"}}', { status: 401 }));
    await expect(provider(h.impl).turns.generateTurn(input)).rejects.toMatchObject({ status: 401 });
    expect(h.calls).toHaveLength(1);
  });

  it('a slow vendor times out per attempt (one retry) and the caller\'s abort signal stops everything', async () => {
    vi.useFakeTimers();
    try {
      const hang = fakeFetch((c) => new Promise<Response>((_resolve, reject) => { c.init.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError'))); }));
      const p = provider(hang.impl, { attemptTimeoutMs: 50 });
      const input = { transcript: 'red', lessonId: 'colors_red_blue', lessonContext: lessonCtx(), signal: new AbortController().signal };
      const pending = p.turns.generateTurn(input);
      const assertion = expect(pending).rejects.toMatchObject({ status: 504 });
      await vi.advanceTimersByTimeAsync(60);
      await vi.advanceTimersByTimeAsync(60);
      await assertion;
      expect(hang.calls).toHaveLength(2);

      const outer = new AbortController();
      const hang2 = fakeFetch((c) => new Promise<Response>((_resolve, reject) => { c.init.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError'))); }));
      const p2 = provider(hang2.impl, { attemptTimeoutMs: 5000 });
      const pending2 = p2.turns.generateTurn({ ...input, signal: outer.signal });
      const assertion2 = expect(pending2).rejects.toThrow(/provider_timeout/);
      outer.abort(new Error('provider_timeout'));
      await vi.advanceTimersByTimeAsync(1);
      await assertion2;
      expect(hang2.calls).toHaveLength(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('never logs a prompt, a transcript, a reply or the key', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined);
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const err = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const f = fakeFetch((_c, n) => (n === 1 ? new Response('{"error":"x"}', { status: 503 }) : completion(VALID_LESSON_REPLY)));
    await provider(f.impl).turns.generateTurn({ transcript: 'SECRET-TRANSCRIPT-MARKER', lessonId: 'colors_red_blue', lessonContext: lessonCtx(), signal: new AbortController().signal });
    const lines = [...log.mock.calls, ...warn.mock.calls, ...err.mock.calls].map((c) => c.map(String).join(' ')).join('\n');
    expect(lines).not.toContain('SECRET-TRANSCRIPT-MARKER');
    expect(lines).not.toContain(KEY);
    expect(lines).not.toContain('Great! Red!');
  });

  it('honours OPENAI_BASE_URL-style overrides and extra headers', async () => {
    const f = fakeFetch(() => completion(VALID_LESSON_REPLY));
    const p = provider(f.impl, { baseUrl: 'https://gateway.example.test/openai/v1/', extraHeaders: { 'x-route': 'test' } });
    await p.turns.generateTurn({ transcript: 'red', lessonId: 'colors_red_blue', lessonContext: lessonCtx(), signal: new AbortController().signal });
    expect(f.calls[0].url).toBe('https://gateway.example.test/openai/v1/chat/completions');
    expect((f.calls[0].init.headers as Record<string, string>)['x-route']).toBe('test');
  });
});
