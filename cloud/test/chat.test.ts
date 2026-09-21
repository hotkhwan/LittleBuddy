// Free chat (T2): mode "chat" sessions end to end inside the Worker. No key
// anywhere, so the mock chat provider answers; the OpenAI path through the
// Durable Object is driven with a fake fetch via the registry's test seam.
import { env } from 'cloudflare:test';
import { afterEach, describe, expect, it } from 'vitest';
import { DEV_TOKEN, createSession, familyClient, makeClient, sessionStub, uniqueId, type Client } from './helpers';
import { setProviderTestSeam } from '../src/tutor/provider_registry';
import { CHAT_DEFAULT_WORDS, loadChatConfig, clampResponseWords } from '../src/tutor/chat_config';
import { capWords, checkChatText, countWords, redirectTurn } from '../src/tutor/chat_safety';
import { createMockChatProvider, gateChatTurn } from '../src/tutor/chat_provider';
import { validateTurn } from '../src/tutor/turn_validator';
import { ASSET_ALLOWLIST } from '../src/tutor/content';
import type { Env } from '../src/env';

const CHAT_ENV: Partial<Env> & Record<string, string> = { FREE_CHAT_ENABLED: '1' } as never;

async function chatSession(c: Client, extra: Record<string, unknown> = {}) {
  const kid = await c.api('POST', '/v1/children', { nickname: 'Test Kid' }, { 'x-parent-approval': DEV_TOKEN });
  return c.api('POST', '/v1/tutor/sessions', { mode: 'chat', clientId: uniqueId('chat'), childId: kid.body.childId, ...extra });
}

function turn(c: Client, sid: string, transcript: string, extra: Record<string, unknown> = {}, headers: Record<string, string> = {}) {
  return c.api('POST', `/v1/tutor/sessions/${sid}/turns`, { transcript, ...extra }, headers);
}

describe('free chat: the gate', () => {
  it('is OFF by default: DEV_MODE without FREE_CHAT_ENABLED answers 403 feature_disabled and opens no session', async () => {
    // The dev environment now sets FREE_CHAT_ENABLED=1 (wrangler.toml); the
    // default is exercised with the flag explicitly absent.
    const c = makeClient({ env: { FREE_CHAT_ENABLED: '' } as never });
    const clientId = uniqueId('nochat');
    const r = await c.api('POST', '/v1/tutor/sessions', { mode: 'chat', clientId });
    expect(r.status).toBe(403);
    expect(r.body.error).toMatchObject({ code: 'feature_disabled', feature: 'free_chat' });
    expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM tutor_sessions WHERE device_id = ?').bind(clientId).first<{ n: number }>())?.n).toBe(0);
  });

  it('production-shaped env refuses chat with 403 feature_disabled even with the flag on', async () => {
    const { fam, h } = await familyClient('prod-chat');
    const prod = makeClient({ defaultToken: null, env: { DEV_MODE: '0', FREE_CHAT_ENABLED: 'true' } as never });
    const r = await prod.api('POST', '/v1/tutor/sessions', { mode: 'chat', clientId: fam.clientId }, h);
    expect(r.status).toBe(403);
    expect(r.body.error.code).toBe('feature_disabled');
    const lesson = await prod.api('POST', '/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId: fam.clientId }, h);
    expect(lesson.status).toBe(201);
    expect(lesson.body.mode).toBe('lesson');
  });

  it('rejects an unknown mode, and the realtime token route never opens a chat session', async () => {
    const c = makeClient({ env: CHAT_ENV });
    const bad = await c.api('POST', '/v1/tutor/sessions', { mode: 'party', lessonId: 'colors_red_blue', clientId: uniqueId('m') });
    expect(bad.status).toBe(400);
    const rt = await c.api('POST', '/v1/tutor/realtime/token', { mode: 'chat', clientId: uniqueId('rtc') });
    expect([400, 503]).toContain(rt.status); // 503 without a provider (no key), 400 with one
  });

  it('config: defaults in code (off, K=6, 25 words, 160 tokens) and bounded overrides', () => {
    const d = loadChatConfig({} as never);
    expect(d).toEqual({ enabled: false, contextTurns: 6, responseMaxWords: CHAT_DEFAULT_WORDS, maxOutputTokens: 160 });
    const o = loadChatConfig({ FREE_CHAT_ENABLED: 'true', CHAT_CONTEXT_TURNS: '99', CHAT_RESPONSE_MAX_WORDS: '3', CHAT_MAX_OUTPUT_TOKENS: 'abc' } as never);
    expect(o).toEqual({ enabled: true, contextTurns: 12, responseMaxWords: 8, maxOutputTokens: 160 });
    expect(clampResponseWords(12, 25)).toBe(12);
    expect(clampResponseWords(1000, 25)).toBe(40);
    expect(clampResponseWords('nope', 25)).toBe(25);
  });
});

describe('free chat: sessions and turns (mock provider, no key)', () => {
  it('opens a chat session, answers with a gated TutorTurn (lessonAction none), charges quota, keeps numbers only in D1', async () => {
    const c = makeClient({ env: CHAT_ENV });
    const s = await chatSession(c);
    expect(s.status).toBe(201);
    expect(s.body).toMatchObject({ mode: 'chat', lessonId: 'free_chat', lessonKnown: false, chat: { responseMaxWords: 25, contextTurns: 6 } });
    const sid = s.body.sessionId;
    c.clock.advance(7);
    const t = await turn(c, sid, 'what do cats eat', {}, { 'idempotency-key': 'c1' });
    expect(t.status).toBe(200);
    expect(t.body).toMatchObject({ mode: 'chat', contextSource: 'chat', provider: 'mock', fallback: null, turnIndex: 1, chargedSeconds: 7, chat: { responseMaxWords: 25, historyTurns: 1, redirected: null } });
    expect(t.body.turn).toMatchObject({ speech: 'Cats eat cat food and drink water.', emotion: 'happy', visual: { type: 'flashcard', assetId: 'cat' }, lessonAction: 'none' });
    expect(t.body.turn.nextQuestion).toBeUndefined();
    // the validator accepts everything but the chat-only action
    expect(validateTurn({ ...t.body.turn, lessonAction: 'retry' }, { allowlist: ASSET_ALLOWLIST.ids }).ok).toBe(true);
    expect(t.body.quota).toMatchObject({ usedSeconds: 7, usedTurns: 1 });
    // idempotent replay, uncharged
    c.clock.advance(5);
    const again = await turn(c, sid, 'what do cats eat', {}, { 'idempotency-key': 'c1' });
    expect(again.headers.get('idempotent-replayed')).toBe('true');
    expect(again.body).toEqual(t.body);
    const row = await env.DB.prepare('SELECT lesson_id, mode, turn_count FROM tutor_sessions WHERE id = ?').bind(sid).first<{ lesson_id: string; mode: string; turn_count: number }>();
    expect(row).toEqual({ lesson_id: 'free_chat', mode: 'turns', turn_count: 1 });
    const usage = await env.DB.prepare('SELECT kind, tokens_in, tokens_out FROM usage_events WHERE session_id = ?').bind(sid).all<{ kind: string }>();
    expect(usage.results).toEqual([{ kind: 'turn', tokens_in: 0, tokens_out: 0 }]);
    const idem = await env.DB.prepare('SELECT response_json FROM api_idempotency WHERE session_id = ?').bind(sid).first<{ response_json: string }>();
    expect(idem?.response_json).not.toContain('what do cats eat');
  });

  it('keeps a rolling context window in the DO: a follow-up without a topic is answered about the last topic; the window is capped at K and cleared on end', async () => {
    const c = makeClient({ env: { ...CHAT_ENV, CHAT_CONTEXT_TURNS: '2' } as never });
    const s = await chatSession(c);
    const sid = s.body.sessionId;
    expect(s.body.chat.contextTurns).toBe(2);
    const a = await turn(c, sid, 'tell me about dogs');
    expect(a.body.turn.speech).toMatch(/dog|puppies|puppy/i);
    const b = await turn(c, sid, 'and why?');
    expect(b.body.turn.speech).toMatch(/^About dogs\?/);
    expect(b.body.chat.historyTurns).toBe(2);
    const info = await sessionStub(sid).info();
    expect(info?.sessionMode).toBe('chat');
    expect(info?.chat?.history.map((m) => m.role)).toEqual(['child', 'tutor', 'child', 'tutor']);
    await turn(c, sid, 'apples please');
    const info2 = await sessionStub(sid).info();
    expect(info2?.chat?.history).toHaveLength(4); // K=2 exchanges
    expect(info2?.chat?.history[0].text).toBe('and why?');
    const e = await c.api('POST', `/v1/tutor/sessions/${sid}/end`, { reason: 'return_to_lesson' });
    expect(e.status).toBe(200);
    expect((await sessionStub(sid).info())?.chat?.history).toEqual([]);
    const row = await env.DB.prepare('SELECT reason FROM tutor_sessions WHERE id = ?').bind(sid).first<{ reason: string }>();
    expect(row?.reason).toBe('return_to_lesson');
  });

  it('enforces the word cap: the session default, a per-turn responseMaxWords inside the band, and the band itself', async () => {
    const c = makeClient({ env: { ...CHAT_ENV, CHAT_RESPONSE_MAX_WORDS: '10' } as never });
    const s = await chatSession(c);
    const sid = s.body.sessionId;
    const a = await turn(c, sid, 'sing a song');
    expect(countWords(a.body.turn.speech)).toBeLessThanOrEqual(10);
    expect(a.body.chat.responseMaxWords).toBe(10);
    const b = await turn(c, sid, 'sing a song again', { responseMaxWords: 8 });
    expect(countWords(b.body.turn.speech)).toBeLessThanOrEqual(8);
    expect(b.body.chat.responseMaxWords).toBe(8);
    const huge = await turn(c, sid, 'sing more', { responseMaxWords: 500 });
    expect(huge.body.chat.responseMaxWords).toBe(40);
    // the gate itself: a wordy but safe candidate is shortened, not rejected
    const wordy = { speech: 'Cats are soft and warm and they like to sleep in the sun all day long and then they play at night.', emotion: 'happy', gesture: 'nod', visual: { type: 'none' }, lessonAction: 'none' };
    const g = gateChatTurn(wordy, { responseMaxWords: 12, allowlist: ASSET_ALLOWLIST.ids });
    expect(g.ok).toBe(true);
    expect(g.capped).toBe(true);
    expect(countWords(g.turn.speech)).toBeLessThanOrEqual(12);
    expect(g.turn.speech.endsWith('.')).toBe(true);
    expect(capWords('Cats are nice. They nap a lot in the sun every day.', 8)).toEqual({ text: 'Cats are nice.', capped: true });
    expect(capWords('One. Two three four five six seven.', 4)).toEqual({ text: 'One. Two three four.', capped: true }); // a boundary too early is not used
    expect(capWords('Short and sweet.', 25)).toEqual({ text: 'Short and sweet.', capped: false });
  });

  it('redirects a flagged CHILD topic without asking any provider, and a flagged REPLY from the provider', async () => {
    const c = makeClient({ env: CHAT_ENV });
    const s = await chatSession(c);
    const sid = s.body.sessionId;
    const r = await turn(c, sid, 'what is your phone number and where do you live');
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ provider: 'safety', fallback: 'redirect:child:personal_data', chat: { redirected: 'personal_data' } });
    expect(r.body.turn.speech).toBe("Let's keep that private! Tell me your favorite animal instead.");
    expect(r.body.turn.lessonAction).toBe('none');
    expect(r.body.quota.usedTurns).toBe(1); // charged like any turn
    const v = await turn(c, sid, 'do you have a gun');
    expect(v.body.chat.redirected).toBe('violence');
    const g = gateChatTurn({ speech: 'Sure, I will kill the monster for you!', emotion: 'happy', gesture: 'nod', visual: { type: 'none' }, lessonAction: 'none' }, { responseMaxWords: 25 });
    expect(g.ok).toBe(false);
    expect(g.reasons[0]).toMatch(/banned_word|redirect/);
    expect(g.turn.speech).not.toMatch(/kill/);
    const g2 = gateChatTurn({ speech: 'Come to my house and we can play!', emotion: 'happy', gesture: 'nod', visual: { type: 'none' }, lessonAction: 'none' }, { responseMaxWords: 25 });
    expect(g2).toMatchObject({ ok: false, redirected: 'contact' });
    // every redirect line is itself a valid turn and does not trip its own rules
    for (const cat of ['personal_data', 'contact', 'adult', 'violence', 'substances', 'scary', 'money', 'self_harm', 'unsafe_acts', 'links', null] as const) {
      const t = redirectTurn(cat);
      expect(validateTurn(t).ok, String(cat)).toBe(true);
      expect(checkChatText(t.speech).flagged, String(cat)).toBe(false);
    }
    expect(checkChatText('what color is the sky').flagged).toBe(false);
    expect(checkChatText('my class starts at nine').flagged).toBe(false);
  });

  it('a chat turn needs a transcript; a lesson session still needs lessonContext; the mock chat says the unsure line for the unknown', async () => {
    const c = makeClient({ env: CHAT_ENV });
    const s = await chatSession(c);
    const empty = await turn(c, s.body.sessionId, '   ');
    expect(empty.status).toBe(400);
    expect(empty.body.error.code).toBe('invalid_turn');
    const unknown = await turn(c, s.body.sessionId, 'zorp blex quux');
    expect(unknown.body.turn.speech).toMatch(/^I'm not sure, let's find out together!/);
    expect(unknown.body.turn.emotion).toBe('thinking');
    const lesson = await createSession(c);
    const noCtx = await turn(c, lesson.body.sessionId, 'red');
    expect(noCtx.status).toBe(400);
    const lessonInfo = await sessionStub(lesson.body.sessionId).info();
    expect(lessonInfo?.sessionMode).toBe('lesson');
    expect(lessonInfo?.chat).toBeNull();
    const mock = createMockChatProvider();
    const m = await mock.generateChatTurn({ transcript: '', history: [], responseMaxWords: 25, signal: new AbortController().signal });
    expect((m.turn as { speech: string }).speech).toBe('I am listening! Tell me anything.');
  });

  it('a primary provider without generateChatTurn (the DEV_MODE faulty chaos provider) is never asked: the mock chat answers directly', async () => {
    const c = makeClient({ env: { ...CHAT_ENV, TUTOR_PROVIDER: 'faulty' } as never });
    const s = await chatSession(c);
    const r = await turn(c, s.body.sessionId, 'do you like bananas');
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ provider: 'mock', fallback: null, usage: { llmInputTokens: 0, llmOutputTokens: 0 } });
    expect(r.body.turn.speech).toMatch(/banana/i);
    expect(r.body.turn.speech).not.toMatch(/example\.com/);
  });

  it('the daily allowance is charged by the server clock and ends a chat session exactly like a lesson', async () => {
    const c = makeClient({ env: CHAT_ENV });
    const s = await chatSession(c);
    const sid = s.body.sessionId;
    let boundaryAt = 0;
    for (let i = 1; i <= 8 && !boundaryAt; i += 1) {
      c.clock.advance(45); // each gap is capped at TUTOR_TURN_CAP_SECONDS; 300 s free allowance
      const r = await turn(c, sid, i % 2 ? 'hello' : 'and cats?');
      expect(r.status).toBe(200);
      expect(r.body.quota.usedSeconds).toBe(Math.min(300, 45 * i));
      if (r.body.endAtBoundary) boundaryAt = i;
    }
    expect(boundaryAt).toBe(7);
    const after = await turn(c, sid, 'one more');
    expect(after.status).toBe(429);
    expect(after.body.error).toMatchObject({ code: 'quota_exhausted', reason: 'daily_quota' });
    expect((await sessionStub(sid).info())?.endReason).toBe('quota_exhausted');
    expect((await sessionStub(sid).info())?.chat?.history).toEqual([]);
  });
});

describe('free chat: the OpenAI provider through the Durable Object (fake fetch, no real key)', () => {
  afterEach(() => setProviderTestSeam(null));

  function seam(handler: (body: any, n: number) => Response) {
    const calls: any[] = [];
    setProviderTestSeam({
      apiKey: 'sk-test-not-a-real-key',
      fetchImpl: (async (_input: RequestInfo | URL, init?: RequestInit) => {
        const body = JSON.parse(String(init?.body));
        calls.push(body);
        return handler(body, calls.length);
      }) as typeof fetch,
    });
    return calls;
  }
  const reply = (turn: unknown, usage = { prompt_tokens: 200, completion_tokens: 25 }) => new Response(JSON.stringify({ choices: [{ message: { role: 'assistant', content: JSON.stringify(turn) } }], usage }), { status: 200 });

  it('a valid model reply becomes the served turn with usage and cost recorded; the window travels as prior messages', async () => {
    const calls = seam((_b, n) => reply(n === 1
      ? { speech: 'Dogs eat dog food. They love to run!', emotion: 'happy', gesture: 'nod', visual: { type: 'flashcard', assetId: 'dog' }, lessonAction: 'none', nextQuestion: '' }
      : { speech: 'Puppies drink milk, then eat soft food.', emotion: 'smile', gesture: 'point', visual: { type: 'none', assetId: '' }, lessonAction: 'none', nextQuestion: '' }));
    const c = makeClient({ env: CHAT_ENV });
    const s = await chatSession(c);
    const sid = s.body.sessionId;
    const a = await turn(c, sid, 'what do dogs eat');
    expect(a.status).toBe(200);
    expect(a.body).toMatchObject({ provider: 'openai:gpt-4o-mini', fallback: null, usage: { llmInputTokens: 200, llmOutputTokens: 25 } });
    expect(a.body.usage.costUsd).toBeGreaterThan(0);
    expect(a.body.turn).toEqual({ speech: 'Dogs eat dog food. They love to run!', subtitle: 'Dogs eat dog food. They love to run!', emotion: 'happy', gesture: 'nod', visual: { type: 'flashcard', assetId: 'dog' }, lessonAction: 'none' });
    const b = await turn(c, sid, 'and puppies?');
    expect(b.body.turn.speech).toBe('Puppies drink milk, then eat soft food.');
    expect(calls[1].messages.map((m: { role: string }) => m.role)).toEqual(['system', 'user', 'assistant', 'user']);
    expect(calls[1].messages[1].content).toBe('what do dogs eat');
    expect(calls[1].messages[2].content).toBe('Dogs eat dog food. They love to run!');
    const usage = await env.DB.prepare('SELECT tokens_in, tokens_out, cost_usd_micro FROM usage_events WHERE session_id = ? ORDER BY created_at').bind(sid).all<{ tokens_in: number; tokens_out: number; cost_usd_micro: number }>();
    expect(usage.results.map((r) => r.tokens_in)).toEqual([200, 200]);
    expect(usage.results[0].cost_usd_micro).toBeGreaterThan(0);
  });

  it('invalid model JSON -> mock fallback; a flagged model reply -> scripted redirect; a banned word -> mock; a 503 -> mock fallback', async () => {
    let mode: 'invalid' | 'flagged' | 'banned' | 'hang' = 'invalid';
    seam(() => {
      if (mode === 'invalid') return new Response(JSON.stringify({ choices: [{ message: { role: 'assistant', content: 'not json' } }], usage: { prompt_tokens: 9, completion_tokens: 1 } }), { status: 200 });
      if (mode === 'flagged') return reply({ speech: 'Come to my house and we can play!', emotion: 'happy', gesture: 'nod', visual: { type: 'none', assetId: '' }, lessonAction: 'none', nextQuestion: '' });
      if (mode === 'banned') return reply({ speech: 'Tell me where do you live and I will visit!', emotion: 'happy', gesture: 'nod', visual: { type: 'none', assetId: '' }, lessonAction: 'none', nextQuestion: '' });
      return new Response('{}', { status: 503 });
    });
    const c = makeClient({ env: { ...CHAT_ENV, PROVIDER_TIMEOUT_MS: '500' } as never });
    const s = await chatSession(c);
    const sid = s.body.sessionId;
    const a = await turn(c, sid, 'what about cats');
    expect(a.body).toMatchObject({ provider: 'mock', fallback: 'invalid_turn:turn:not_object', usage: { llmInputTokens: 9 } });
    expect(a.body.turn.speech).toMatch(/cat|kitten/i);
    mode = 'flagged';
    const b = await turn(c, sid, 'where are you');
    expect(b.body).toMatchObject({ provider: 'safety', fallback: 'redirect:reply:contact', chat: { redirected: 'contact' } });
    expect(b.body.turn.speech).toBe('Aliz only plays here with you. What do you like to play?');
    mode = 'banned';
    const bb = await turn(c, sid, 'where are you now');
    expect(bb.body).toMatchObject({ provider: 'mock', fallback: 'invalid_turn:speech:banned_word,subtitle:banned_word' });
    expect(bb.body.turn.speech).not.toMatch(/live|visit/);
    mode = 'hang';
    const d = await turn(c, sid, 'apples?');
    expect(d.body.provider).toBe('mock');
    expect(d.body.fallback).toMatch(/^provider_error:503|provider_timeout/);
    expect(d.body.turn.speech).toMatch(/apple/i);
  });
});
