#!/usr/bin/env node
// Little Days -- Aliz Tutor MOCK backend + mock Realtime server.
//
// Zero dependencies (Node 22). Speaks the REST contract in
// docs/ALIZ_TUTOR_CLOUD_CLIENT.md and the Realtime WebSocket event subset the
// game's CloudRealtimeTransport uses, with a SCRIPTED lesson so a headless
// integration run is deterministic. It is NOT a model, calls no provider,
// holds no key, and never logs a transcript or an audio byte: every log line
// carries counts and names only.
//
//   node tools/tutor_mock_server/server.mjs            # 127.0.0.1:8787
//   PORT=8791 node tools/tutor_mock_server/server.mjs
//
// Scenarios are keyed on the childId prefix so one running server covers them:
//   exhausted*  allowance 0             -> 402 quota_exhausted on /sessions
//   deny*       parent not approved     -> 403 not_approved everywhere
//   flaky*      first token mint 503    -> the client reconnects once
//   drop*       socket closed after the first completed reply -> reconnect once
//   banned*     the reply carries a banned word -> the client cancels it
//   noaudio*    transcript deltas only, no audio
//   toolsinline* tool calls inside the spoken response (default: a
//               function-call-only response first, then the spoken one after
//               the client returns the outputs -- the vendor's real shape)
//   rate*       first /sessions answers 429 with retryAfterSeconds 0.2
//
// Env: PORT (8787), HOST (127.0.0.1), MOCK_ALLOWANCE_SECONDS (300),
//      MOCK_WORD_MS (120), MOCK_GRACE_SECONDS (30).

import http from 'node:http';
import crypto from 'node:crypto';

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '127.0.0.1';
const ALLOWANCE = Number(process.env.MOCK_ALLOWANCE_SECONDS || 300);
const WORD_MS = Number(process.env.MOCK_WORD_MS || 120);
const GRACE = Number(process.env.MOCK_GRACE_SECONDS || 30);
const SAMPLE_RATE = 24000;

// -- scripted lesson ---------------------------------------------------------------------
const SCRIPT = [
  { keys: ['cat', 'kitty', 'kitten'], speech: "Great! It's a cat!", card: 'cat', gesture: 'clap', emotion: 'happy' },
  { keys: ['dog', 'puppy', 'doggy'], speech: "Great! It's a dog!", card: 'dog', gesture: 'clap', emotion: 'happy' },
  { keys: ['meow', 'miaow'], speech: "Meow! You're amazing!", card: 'cat', gesture: 'clap', emotion: 'happy' },
  { keys: ['woof', 'bark'], speech: "Woof! You're amazing!", card: 'dog', gesture: 'clap', emotion: 'happy' },
  { keys: ['apple'], speech: 'Yes! A red apple!', card: 'apple_red', gesture: 'clap', emotion: 'happy' },
  { keys: ['banana'], speech: 'Yes! A yellow banana!', card: 'banana_yellow', gesture: 'clap', emotion: 'happy' },
  { keys: ['red'], speech: 'Red! Well done!', card: 'color_red', gesture: 'nod', emotion: 'smile' },
  { keys: ['blue'], speech: 'Blue! Well done!', card: 'color_blue', gesture: 'nod', emotion: 'smile' },
  { keys: ['one'], speech: 'One! Nice!', card: 'number_1', gesture: 'point', emotion: 'happy' },
  { keys: ['two'], speech: 'Two! Nice!', card: 'number_2', gesture: 'point', emotion: 'happy' },
  { keys: ['three'], speech: 'Three! Nice!', card: 'number_3', gesture: 'point', emotion: 'happy' },
];
const RETRY_LINE = { speech: "Let's try together! Can you say it again?", card: '', gesture: 'tilt', emotion: 'encouraging' };
const BANNED_LINE = { speech: 'That was a stupid answer, try again.', card: '', gesture: 'tilt', emotion: 'encouraging' };

function scriptFor(text, scenario) {
  if (scenario.banned) return BANNED_LINE;
  const said = ` ${String(text).toLowerCase().replace(/[^a-z ]/g, ' ')} `;
  for (const entry of SCRIPT) if (entry.keys.some((k) => said.includes(` ${k} `))) return entry;
  return RETRY_LINE;
}

// -- state -----------------------------------------------------------------------------------
const sessions = new Map(); // sessionId -> session
const quota = new Map();    // childId -> {used}
const tokens = new Map();   // token -> sessionId
const scenarioState = new Map(); // childId -> {tokenFailed, rateLimited}
let counter = 0;

function scenarioOf(childId) {
  const id = String(childId || '');
  const has = (p) => id.startsWith(p);
  return {
    exhausted: has('exhausted'), deny: has('deny'), flaky: has('flaky'), drop: has('drop'),
    banned: has('banned'), noaudio: has('noaudio'), toolsInline: has('toolsinline'), rate: has('rate'),
  };
}
function allowanceFor(childId) { return scenarioOf(childId).exhausted ? 0 : ALLOWANCE; }
function usedFor(childId) { return quota.get(childId)?.used ?? 0; }
function charge(childId, seconds) {
  const cur = quota.get(childId) ?? { used: 0 };
  cur.used = Math.min(allowanceFor(childId) + GRACE, cur.used + Math.max(0, seconds));
  quota.set(childId, cur);
}
function resetAtUtc() { const d = new Date(); d.setUTCHours(24, 0, 0, 0); return d.toISOString(); }
function quotaBlock(childId) {
  const allowanceSeconds = allowanceFor(childId);
  const usedSeconds = Math.round(usedFor(childId) * 10) / 10;
  return { allowanceSeconds, usedSeconds, remainingSeconds: Math.max(0, allowanceSeconds - usedSeconds), resetAtUtc: resetAtUtc() };
}
function settle(session, now = Date.now()) {
  if (!session.realtimeStartedAt || session.endedAt) return;
  const until = Math.min(now, session.expiresAtMs);
  const seconds = (until - session.lastChargedAt) / 1000;
  if (seconds > 0) charge(session.childId, seconds);
  session.lastChargedAt = Math.max(session.lastChargedAt, until);
}

function log(line) { console.log(`[mock-tutor ${new Date().toISOString()}] ${line}`); }

// -- HTTP -------------------------------------------------------------------------------------
function send(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(text) });
  res.end(text);
}
function fail(res, status, code, extra = {}) { send(res, status, { error: code, ...extra }); }
function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); } catch { resolve(null); }
    });
  });
}
function authOf(req) {
  const auth = String(req.headers.authorization || '');
  const parentToken = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  return { parentToken, approval: String(req.headers['x-parent-approval'] || '').trim(), deviceId: String(req.headers['x-device-id'] || '').trim() };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const path = url.pathname;
  if (req.method === 'GET' && path === '/healthz') return send(res, 200, { ok: true, mock: true });
  if (req.headers.upgrade) return; // handled by 'upgrade'

  const body = req.method === 'GET' ? {} : await readBody(req);
  if (body === null) return fail(res, 400, 'bad_request');
  const auth = authOf(req);
  if (!auth.parentToken || !auth.approval || !auth.deviceId) {
    log(`403 ${req.method} ${path} (missing parent token, approval or device id)`);
    return fail(res, 403, 'not_approved');
  }

  if (req.method === 'GET' && path === '/v1/tutor/quota') {
    const childId = url.searchParams.get('childId') || '';
    if (scenarioOf(childId).deny) return fail(res, 403, 'not_approved');
    for (const s of sessions.values()) if (s.childId === childId) settle(s);
    log(`GET quota child=${childId.slice(0, 12)} used=${usedFor(childId).toFixed(1)}`);
    return send(res, 200, quotaBlock(childId));
  }

  if (req.method === 'POST' && path === '/v1/tutor/sessions') {
    const childId = String(body.childId || '');
    const scenario = scenarioOf(childId);
    if (!childId || !body.lessonId) return fail(res, 400, 'bad_request');
    if (scenario.deny) return fail(res, 403, 'not_approved');
    const st = scenarioState.get(childId) ?? {};
    if (scenario.rate && !st.rateLimited) { st.rateLimited = true; scenarioState.set(childId, st); return fail(res, 429, 'rate_limited', { retryAfterSeconds: 0.2 }); }
    if (usedFor(childId) >= allowanceFor(childId)) { log(`402 sessions child=${childId.slice(0, 12)}`); return fail(res, 402, 'quota_exhausted', { quota: quotaBlock(childId) }); }
    counter += 1;
    const session = { sessionId: `mock-s-${counter}-${crypto.randomBytes(3).toString('hex')}`, childId, lessonId: String(body.lessonId), mode: body.mode === 'turns' ? 'turns' : 'realtime',
      parentToken: auth.parentToken, createdAt: Date.now(), realtimeStartedAt: 0, lastChargedAt: 0, expiresAtMs: 0, endedAt: 0, responses: 0, turns: 0, socket: null, scenario };
    sessions.set(session.sessionId, session);
    log(`201 sessions ${session.sessionId} lesson=${session.lessonId} mode=${session.mode} scenario=${Object.entries(scenario).filter(([, v]) => v).map(([k]) => k).join(',') || 'default'}`);
    return send(res, 201, { sessionId: session.sessionId, quota: quotaBlock(childId), entitlement: 'free' });
  }

  if (req.method === 'POST' && path === '/v1/tutor/realtime/token') {
    const session = sessions.get(String(body.sessionId || ''));
    if (!session || session.endedAt) return fail(res, 410, 'session_ended');
    if (session.parentToken !== auth.parentToken) return fail(res, 403, 'not_approved');
    const st = scenarioState.get(session.childId) ?? {};
    if (session.scenario.flaky && !st.tokenFailed) { st.tokenFailed = true; scenarioState.set(session.childId, st); log(`503 token ${session.sessionId} (flaky scenario, once)`); return fail(res, 503, 'provider_unavailable'); }
    settle(session);
    const remaining = allowanceFor(session.childId) - usedFor(session.childId);
    if (remaining <= 0) { log(`402 token ${session.sessionId}`); return fail(res, 402, 'quota_exhausted', { quota: quotaBlock(session.childId) }); }
    const token = `mock-rt-${crypto.randomBytes(12).toString('hex')}`;
    const seconds = Math.max(10, Math.min(600, Math.floor(remaining + GRACE)));
    const now = Date.now();
    session.expiresAtMs = now + seconds * 1000;
    if (!session.realtimeStartedAt) { session.realtimeStartedAt = now; session.lastChargedAt = now; }
    tokens.set(token, session.sessionId);
    log(`200 token ${session.sessionId} expires_in=${seconds}s`);
    return send(res, 200, {
      token, expiresAt: new Date(session.expiresAtMs).toISOString(), model: 'mock-realtime',
      url: `ws://${HOST}:${PORT}/v1/realtime?model=mock-realtime`,
      subprotocols: ['realtime', `mock-token.${token}`],
      sessionUpdate: { type: 'session.update', session: { type: 'realtime', output_modalities: ['audio'], instructions: 'mock lesson' } },
    });
  }

  const turnMatch = path.match(/^\/v1\/tutor\/sessions\/([^/]+)\/turns$/);
  if (req.method === 'POST' && turnMatch) {
    const session = sessions.get(turnMatch[1]);
    if (!session || session.endedAt) return fail(res, 410, 'session_ended');
    if (session.parentToken !== auth.parentToken) return fail(res, 403, 'not_approved');
    if (usedFor(session.childId) >= allowanceFor(session.childId)) return fail(res, 402, 'quota_exhausted', { quota: quotaBlock(session.childId) });
    session.turns += 1;
    charge(session.childId, 10);
    const line = scriptFor(body.transcript || '', session.scenario);
    log(`200 turn ${session.sessionId} #${session.turns} phase=${body.phase || '?'} transcript_chars=${String(body.transcript || '').length}`);
    return send(res, 200, {
      turn: { speech: line.speech, subtitle: line.speech, emotion: line.emotion, gesture: line.gesture,
        visual: line.card ? { type: 'flashcard', assetId: line.card } : { type: 'none' }, lessonAction: line.card ? 'next_question' : 'retry' },
      quota: quotaBlock(session.childId), endAtBoundary: usedFor(session.childId) >= allowanceFor(session.childId), turnIndex: session.turns,
    });
  }

  const endMatch = path.match(/^\/v1\/tutor\/sessions\/([^/]+)\/end$/);
  if (req.method === 'POST' && endMatch) {
    const session = sessions.get(endMatch[1]);
    if (!session) return fail(res, 410, 'session_ended');
    if (session.parentToken !== auth.parentToken) return fail(res, 403, 'not_approved');
    if (!session.endedAt) {
      settle(session);
      session.endedAt = Date.now();
      if (session.socket) { try { wsClose(session.socket, 1000, 'session ended'); } catch { /* closed */ } }
    }
    const usage = body.usage || {};
    log(`200 end ${session.sessionId} reason=${body.reason || '?'} secondsUsed=${Number(body.secondsUsed || 0).toFixed(1)} tokensIn=${usage.tokensIn ?? 0} tokensOut=${usage.tokensOut ?? 0} audioSeconds=${usage.audioSeconds ?? 0} responses=${session.responses}`);
    return send(res, 200, { ok: true, quota: quotaBlock(session.childId), endedAt: new Date(session.endedAt).toISOString() });
  }

  fail(res, 404, 'not_found');
});

// -- WebSocket (RFC 6455, server side, text frames) ----------------------------------------------
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

function wsSend(socket, obj) {
  if (socket.destroyed) return false;
  const payload = Buffer.from(JSON.stringify(obj), 'utf8');
  const len = payload.length;
  let header;
  if (len < 126) header = Buffer.from([0x81, len]);
  else if (len < 65536) { header = Buffer.alloc(4); header[0] = 0x81; header[1] = 126; header.writeUInt16BE(len, 2); }
  else { header = Buffer.alloc(10); header[0] = 0x81; header[1] = 127; header.writeBigUInt64BE(BigInt(len), 2); }
  socket.write(Buffer.concat([header, payload]));
  return true;
}
function wsClose(socket, code = 1000, reason = '') {
  const body = Buffer.concat([Buffer.from([code >> 8, code & 0xff]), Buffer.from(reason, 'utf8')]);
  socket.write(Buffer.concat([Buffer.from([0x88, body.length]), body]));
  setTimeout(() => socket.destroy(), 50);
}
function wsPong(socket, payload) { socket.write(Buffer.concat([Buffer.from([0x8a, payload.length]), payload])); }

// Parses complete frames out of `state.buffer`; returns [{opcode, payload}].
function wsFrames(state) {
  const out = [];
  for (;;) {
    const b = state.buffer;
    if (b.length < 2) break;
    const fin = (b[0] & 0x80) !== 0;
    const opcode = b[0] & 0x0f;
    const masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7f;
    let offset = 2;
    if (len === 126) { if (b.length < 4) break; len = b.readUInt16BE(2); offset = 4; }
    else if (len === 127) { if (b.length < 10) break; len = Number(b.readBigUInt64BE(2)); offset = 10; }
    const maskLen = masked ? 4 : 0;
    if (b.length < offset + maskLen + len) break;
    let payload = b.subarray(offset + maskLen, offset + maskLen + len);
    if (masked) {
      const mask = b.subarray(offset, offset + 4);
      const un = Buffer.alloc(len);
      for (let i = 0; i < len; i++) un[i] = payload[i] ^ mask[i % 4];
      payload = un;
    }
    state.buffer = b.subarray(offset + maskLen + len);
    if (!fin && opcode !== 0) { state.fragment = { opcode, parts: [payload] }; continue; }
    if (opcode === 0 && state.fragment) { state.fragment.parts.push(payload); if (fin) { out.push({ opcode: state.fragment.opcode, payload: Buffer.concat(state.fragment.parts) }); state.fragment = null; } continue; }
    out.push({ opcode, payload });
  }
  return out;
}

server.on('upgrade', (req, socket) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const key = req.headers['sec-websocket-key'];
  const protocols = String(req.headers['sec-websocket-protocol'] || '').split(',').map((s) => s.trim()).filter(Boolean);
  let token = protocols.find((p) => p.startsWith('mock-token.'))?.slice('mock-token.'.length) || '';
  if (!token) { const auth = String(req.headers.authorization || ''); if (auth.startsWith('Bearer ')) token = auth.slice(7).trim(); }
  const sessionId = tokens.get(token);
  const session = sessionId ? sessions.get(sessionId) : null;
  if (url.pathname !== '/v1/realtime' || !key || !session || session.endedAt || Date.now() > session.expiresAtMs) {
    log(`ws refused path=${url.pathname} token_known=${Boolean(session)}`);
    socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
    socket.destroy();
    return;
  }
  const accept = crypto.createHash('sha1').update(key + WS_GUID).digest('base64');
  const headers = ['HTTP/1.1 101 Switching Protocols', 'Upgrade: websocket', 'Connection: Upgrade', `Sec-WebSocket-Accept: ${accept}`];
  if (protocols.includes('realtime')) headers.push('Sec-WebSocket-Protocol: realtime');
  socket.write(headers.join('\r\n') + '\r\n\r\n');
  socket.setNoDelay(true);
  session.socket = socket;
  const state = { buffer: Buffer.alloc(0), fragment: null, session, socket, responding: null, audioBytes: 0, speechStarted: false, serial: 0, items: 0 };
  log(`ws open ${session.sessionId}`);
  wsSend(socket, { type: 'session.created', event_id: nextId(state), session: { id: `rt-${session.sessionId}`, type: 'realtime' } });
  socket.on('data', (chunk) => {
    state.buffer = Buffer.concat([state.buffer, chunk]);
    for (const frame of wsFrames(state)) {
      if (frame.opcode === 0x8) { wsClose(socket, 1000, 'bye'); return; }
      if (frame.opcode === 0x9) { wsPong(socket, frame.payload); continue; }
      if (frame.opcode !== 0x1) continue;
      let event;
      try { event = JSON.parse(frame.payload.toString('utf8')); } catch { continue; }
      handleClientEvent(state, event);
    }
  });
  socket.on('close', () => { if (session.socket === socket) session.socket = null; if (state.responding) state.responding.cancelled = true; log(`ws closed ${session.sessionId}`); });
  socket.on('error', () => {});
});

function nextId(state) { state.serial += 1; return `mock_ev_${state.serial}`; }

function handleClientEvent(state, event) {
  const type = String(event.type || '');
  const { socket, session } = state;
  switch (type) {
    case 'session.update':
      wsSend(socket, { type: 'session.updated', event_id: nextId(state), session: { id: `rt-${session.sessionId}`, type: 'realtime' } });
      break;
    case 'conversation.item.create': {
      const item = event.item || {};
      if (item.type === 'message') {
        const text = (item.content || []).map((c) => c.text || '').join(' ');
        state.pendingText = text;
        log(`item.create message chars=${text.length} ${session.sessionId}`);
        wsSend(socket, { type: 'conversation.item.created', event_id: nextId(state), item: { id: `item_u_${++state.items}`, type: 'message', role: 'user' } });
      } else if (item.type === 'function_call_output') {
        state.toolOutputs = (state.toolOutputs || 0) + 1;
        log(`item.create function_call_output ${session.sessionId}`);
        wsSend(socket, { type: 'conversation.item.created', event_id: nextId(state), item: { id: `item_o_${++state.items}`, type: 'function_call_output' } });
      }
      break;
    }
    case 'response.create':
      if (state.responding) { wsSend(socket, { type: 'error', event_id: nextId(state), error: { type: 'invalid_request_error', code: 'conversation_already_has_active_response', message: 'busy' } }); break; }
      startResponse(state, state.pendingText || '', Boolean(state.toolOutputs));
      state.toolOutputs = 0;
      break;
    case 'response.cancel':
      if (state.responding) { state.responding.cancelled = true; log(`response.cancel ${session.sessionId}`); }
      break;
    case 'conversation.item.truncate':
      log(`item.truncate ${session.sessionId} audio_end_ms=${Number(event.audio_end_ms || 0)}`);
      wsSend(socket, { type: 'conversation.item.truncated', event_id: nextId(state), item_id: event.item_id, content_index: 0, audio_end_ms: event.audio_end_ms });
      break;
    case 'input_audio_buffer.append': {
      const bytes = Buffer.from(String(event.audio || ''), 'base64').length;
      state.audioBytes += bytes;
      if (!state.speechStarted && state.audioBytes >= SAMPLE_RATE * 2 * 1) {
        state.speechStarted = true;
        wsSend(socket, { type: 'input_audio_buffer.speech_started', event_id: nextId(state), audio_start_ms: 0, item_id: `item_a_${state.items + 1}` });
      }
      if (state.speechStarted && state.audioBytes >= SAMPLE_RATE * 2 * 2 && !state.responding) {
        const total = state.audioBytes;
        state.audioBytes = 0; state.speechStarted = false;
        const itemId = `item_a_${++state.items}`;
        log(`server vad: ${total} audio bytes -> committed ${session.sessionId}`);
        wsSend(socket, { type: 'input_audio_buffer.speech_stopped', event_id: nextId(state), audio_end_ms: Math.round(total / 48), item_id: itemId });
        wsSend(socket, { type: 'input_audio_buffer.committed', event_id: nextId(state), item_id: itemId });
        const transcript = process.env.MOCK_AUDIO_TRANSCRIPT || 'cat';
        wsSend(socket, { type: 'conversation.item.input_audio_transcription.completed', event_id: nextId(state), item_id: itemId, content_index: 0, transcript });
        startResponse(state, transcript, false);
      }
      break;
    }
    default:
      break;
  }
}

// Streams one scripted reply. `afterTools` = the client returned tool outputs,
// so this is the spoken half of a two-response turn.
function startResponse(state, text, afterTools) {
  const { socket, session } = state;
  const line = scriptFor(text, session.scenario);
  const responseId = `resp_${++state.items}`;
  const run = { cancelled: false, id: responseId };
  state.responding = run;
  const words = line.speech.split(' ');
  const inline = session.scenario.toolsInline;
  const toolsFirst = !inline && !afterTools && Boolean(line.card);
  const outputs = [];
  const say = (obj) => wsSend(socket, { event_id: nextId(state), response_id: responseId, ...obj });
  say({ type: 'response.created', response: { id: responseId, status: 'in_progress' } });
  session.responses += 1;

  const finish = (status) => {
    if (state.responding !== run) return;
    state.responding = null;
    const usage = { total_tokens: 0, input_tokens: 40 + text.length, output_tokens: 8 * words.length,
      input_token_details: { text_tokens: 40 + text.length, audio_tokens: 0, cached_tokens: 0 },
      output_token_details: { text_tokens: words.length, audio_tokens: 7 * words.length } };
    usage.total_tokens = usage.input_tokens + usage.output_tokens;
    say({ type: 'response.done', response: { id: responseId, status, output: outputs, usage } });
    log(`response.done ${session.sessionId} status=${status} words=${status === 'completed' ? words.length : 'n/a'}`);
    if (status === 'completed' && !toolsFirst && session.scenario.drop && !state.dropped) {
      state.dropped = true;
      setTimeout(() => { log(`drop scenario: closing socket ${session.sessionId}`); wsClose(socket, 1011, 'mock drop'); }, 80);
    }
  };

  const steps = [];
  const pushTool = (name, args) => {
    const itemId = `item_fc_${++state.items}`;
    const callId = `call_${state.items}`;
    outputs.push({ id: itemId, type: 'function_call', name, call_id: callId, arguments: JSON.stringify(args) });
    steps.push(() => say({ type: 'response.output_item.added', output_index: outputs.length - 1, item: { id: itemId, type: 'function_call', name, call_id: callId } }));
    steps.push(() => say({ type: 'response.function_call_arguments.delta', item_id: itemId, call_id: callId, delta: JSON.stringify(args) }));
    steps.push(() => say({ type: 'response.function_call_arguments.done', item_id: itemId, call_id: callId, name, arguments: JSON.stringify(args) }));
    steps.push(() => say({ type: 'response.output_item.done', item: { id: itemId, type: 'function_call', name, call_id: callId, arguments: JSON.stringify(args) } }));
  };
  if (line.card && (inline || toolsFirst)) {
    pushTool('show_card', { assetId: line.card });
    pushTool('gesture', { name: line.gesture });
  }
  if (!toolsFirst) {
    const itemId = `item_m_${++state.items}`;
    outputs.push({ id: itemId, type: 'message', role: 'assistant' });
    steps.push(() => say({ type: 'response.output_item.added', output_index: outputs.length - 1, item: { id: itemId, type: 'message', role: 'assistant' } }));
    steps.push(() => say({ type: 'response.content_part.added', item_id: itemId, content_index: 0, part: { type: 'output_audio' } }));
    words.forEach((word, i) => {
      steps.push(() => say({ type: 'response.output_audio_transcript.delta', item_id: itemId, content_index: 0, delta: (i ? ' ' : '') + word }));
      if (!session.scenario.noaudio) steps.push(() => say({ type: 'response.output_audio.delta', item_id: itemId, content_index: 0, delta: toneChunk(i, word.length) }));
    });
    steps.push(() => say({ type: 'response.output_audio.done', item_id: itemId, content_index: 0 }));
    steps.push(() => say({ type: 'response.output_audio_transcript.done', item_id: itemId, content_index: 0, transcript: line.speech }));
    steps.push(() => say({ type: 'response.output_item.done', item: { id: itemId, type: 'message', role: 'assistant' } }));
  }
  let index = 0;
  const tick = () => {
    if (state.responding !== run || socket.destroyed) return;
    if (run.cancelled) { finish('cancelled'); return; }
    if (index >= steps.length) { finish('completed'); return; }
    steps[index++]();
    setTimeout(tick, toolsFirst ? 5 : WORD_MS / 3);
  };
  setTimeout(tick, 20);
}

// 100 ms of a soft tone per word (raised-cosine envelope), PCM16 mono 24 kHz, base64.
function toneChunk(index, length) {
  const frames = SAMPLE_RATE / 10;
  const buf = Buffer.alloc(frames * 2);
  const freq = 220 + 30 * (index % 4) + 5 * (length % 5);
  for (let i = 0; i < frames; i++) {
    const env = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / frames);
    const sample = Math.round(0.3 * 32767 * env * Math.sin((2 * Math.PI * freq * i) / SAMPLE_RATE));
    buf.writeInt16LE(sample, i * 2);
  }
  return buf.toString('base64');
}

server.listen(PORT, HOST, () => log(`listening on http://${HOST}:${PORT} (allowance ${ALLOWANCE}s, word ${WORD_MS}ms); no provider, no key, no transcript logging`));
