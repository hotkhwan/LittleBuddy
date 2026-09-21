#!/usr/bin/env node
// Little Days -- Aliz Tutor MOCK backend + mock Realtime server.
//
// Zero dependencies (Node 22). Speaks the deployed Worker's REST contract
// (docs/ALIZ_TUTOR_API.md §1, reconciled 2026-09-21 in
// docs/ALIZ_TUTOR_CLOUD_CLIENT.md) and the Realtime WebSocket event subset the
// game's CloudRealtimeTransport uses, with a SCRIPTED lesson so a headless
// integration run is deterministic. It is NOT a model, calls no provider,
// holds no key, and never logs a transcript or an audio byte: every log line
// carries counts and names only.
//
//   node tools/tutor_mock_server/server.mjs            # 127.0.0.1:8787
//   PORT=8791 node tools/tutor_mock_server/server.mjs
//
// Worker shapes mirrored here:
//   POST /v1/parents {provider:"dev", subject, clientId}  -> parentToken (pt1.*) + parentApprovalToken (pa1.*)
//   PUT  /v1/consent {kind, granted}                       parent sign-in header only
//   tutor routes: X-Parent-Approval ONLY (a request that also carries the
//     parent sign-in header is refused 403 not_approved, exactly like the
//     Worker); the DEV literal `dev-parent-approval` is accepted
//   GET  /v1/tutor/entitlement?clientId= | /v1/tutor/quota
//   POST /v1/tutor/sessions {lessonId, clientId}           -> 201 {sessionId, childId, entitlement, quota, lessonId, lessonKnown}
//   POST /v1/tutor/realtime/token {sessionId}              -> 201 both token shapes | 503 provider_unavailable (norealtime*)
//   POST /v1/tutor/sessions/:id/turns {transcript, lessonContext} + Idempotency-Key -> TutorTurn reply; replay -> idempotent-replayed: true; same key other body -> 422
//   POST /v1/tutor/sessions/:id/end {reason (<= 40)}       -> {sessionId, endedAt, quota, usage}; idempotent
//   errors: {error:{code, message, ...}}; quota_exhausted is 429 (quota inside error), session_ended is 409
//   X-Debug-Now: <unix ms> moves the server clock (DEV_MODE semantics)
//   /api/v1/... is served as well as /v1/...
//
// Scenarios are keyed on the clientId prefix so one running server covers them:
//   exhausted*   allowance 0                -> 429 quota_exhausted on /sessions
//   deny*        parent not approved        -> 403 not_approved everywhere
//   norealtime*  token endpoint 503         -> the client runs the turns path (the deployed Worker's shape)
//   shortday*    allowance 25 s             -> the third 10 s turn lands on endAtBoundary
//   drop*        socket closed after the first completed reply -> reconnect once
//   banned*      the reply carries a banned word -> the client cancels it
//   noaudio*     transcript deltas only, no audio
//   toolsinline* tool calls inside the spoken response (default: a
//                function-call-only response first, then the spoken one after
//                the client returns the outputs -- the vendor's real shape)
//   rate*        first /sessions answers 429 rate_limited with retryAfterSeconds 0.2
//
// Env: PORT (8787), HOST (127.0.0.1), MOCK_ALLOWANCE_SECONDS (300),
//      MOCK_TURN_SECONDS (10, the floor charged per REST turn so quota moves in
//      a fast test; the Worker charges the capped wall-clock gap instead),
//      MOCK_WORD_MS (120), MOCK_GRACE_SECONDS (30).

import http from 'node:http';
import crypto from 'node:crypto';

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '127.0.0.1';
const ALLOWANCE = Number(process.env.MOCK_ALLOWANCE_SECONDS || 300);
const TURN_FLOOR = Number(process.env.MOCK_TURN_SECONDS || 10);
const TURN_CAP = 45;
const TURN_ALLOWANCE = 60;
const WORD_MS = Number(process.env.MOCK_WORD_MS || 120);
const GRACE = Number(process.env.MOCK_GRACE_SECONDS || 30);
const SAMPLE_RATE = 24000;
const MAX_END_REASON = 40;
const DEV_APPROVAL_LITERAL = 'dev-parent-approval';
const DEV_PARENT_ID = 'dev-parent';
const OUTCOMES = new Set(['correct', 'incorrect', 'unclear']);
const ID_RE = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;

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
const sessions = new Map();      // sessionId -> session
const quota = new Map();         // childId (= parentId here) -> {used, turns}
const tokens = new Map();        // realtime token value -> sessionId
const parents = new Map();       // parentId -> {consent:Set}
const scenarioState = new Map(); // clientId -> {rateLimited}
const idempotency = new Map();   // sessionId\nkey -> {bodyHash, body}
let counter = 0;

parents.set(DEV_PARENT_ID, { consent: new Set(['privacy', 'ai_tutor', 'voice']) });

function scenarioOf(clientId) {
  const id = String(clientId || '');
  const has = (p) => id.startsWith(p);
  return {
    exhausted: has('exhausted'), deny: has('deny'), norealtime: has('norealtime'), shortday: has('shortday'), drop: has('drop'),
    banned: has('banned'), noaudio: has('noaudio'), toolsInline: has('toolsinline'), rate: has('rate'),
  };
}
function allowanceFor(scenario) { return scenario.exhausted ? 0 : scenario.shortday ? 25 : ALLOWANCE; }
function usedFor(childId) { return quota.get(childId)?.used ?? 0; }
function turnsFor(childId) { return quota.get(childId)?.turns ?? 0; }
function charge(childId, seconds, ceiling) {
  const cur = quota.get(childId) ?? { used: 0, turns: 0 };
  cur.used = Math.min(ceiling, cur.used + Math.max(0, seconds));
  quota.set(childId, cur);
}
function countTurn(childId) {
  const cur = quota.get(childId) ?? { used: 0, turns: 0 };
  cur.turns += 1;
  quota.set(childId, cur);
}
function resetAtUtc(now) { const d = new Date(now); d.setUTCHours(24, 0, 0, 0); return d.toISOString(); }
function quotaBlock(childId, scenario, now) {
  const dailyAllowanceSeconds = allowanceFor(scenario);
  const usedSeconds = Math.round(Math.min(usedFor(childId), dailyAllowanceSeconds) * 10) / 10;
  return {
    entitlement: 'free', dailyAllowanceSeconds, usedSeconds,
    remainingSeconds: Math.max(0, Math.round((dailyAllowanceSeconds - usedSeconds) * 10) / 10),
    resetAtUtc: resetAtUtc(now), dailyTurnAllowance: TURN_ALLOWANCE, usedTurns: turnsFor(childId),
  };
}
function settle(session, now = Date.now()) {
  if (!session.realtimeStartedAt || session.endedAt) return;
  const until = Math.min(now, session.expiresAtMs);
  const seconds = (until - session.lastChargedAt) / 1000;
  if (seconds > 0) charge(session.childId, seconds, allowanceFor(session.scenario) + GRACE);
  session.lastChargedAt = Math.max(session.lastChargedAt, until);
}
function endSession(session, reason, now) {
  if (session.endedAt) return;
  settle(session, now);
  session.endedAt = now;
  session.endReason = reason;
  if (session.socket) { try { wsClose(session.socket, 1000, 'session ended'); } catch { /* closed */ } }
}

function log(line) { console.log(`[mock-tutor ${new Date().toISOString()}] ${line}`); }

// -- HTTP -------------------------------------------------------------------------------------
function send(res, status, body, extraHeaders = {}) {
  const text = JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(text), ...extraHeaders });
  res.end(text);
}
function fail(res, status, code, message = code, extra = {}) {
  const headers = code === 'rate_limited' ? { 'retry-after': String(extra.retryAfterSeconds ?? 1) } : {};
  send(res, status, { error: { code, message, ...extra } }, headers);
}
function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); } catch { resolve(null); }
    });
  });
}
function nowOf(req) {
  const debug = Number(req.headers['x-debug-now']);
  return Number.isFinite(debug) && debug > 0 ? debug : Date.now();
}
// Credential, Worker rules: a parent sign-in header wins (and carries no
// approval); else the approval token from the header or the body.
function authOf(req, body) {
  const raw = String(req.headers.authorization || '');
  if (/^bearer\s+/i.test(raw)) {
    const pt = raw.replace(/^bearer\s+/i, '').trim();
    const m = pt.match(/^pt1\.mock\.(.+)$/);
    if (!m || !parents.has(m[1])) return { error: 'expired_sign_in' };
    return { parentId: m[1], clientId: null, approval: null, via: 'bearer' };
  }
  const approval = String(req.headers['x-parent-approval'] || body?.parentApprovalToken || '').trim();
  if (!approval) return { error: 'missing' };
  if (approval === DEV_APPROVAL_LITERAL) return { parentId: DEV_PARENT_ID, clientId: typeof body?.clientId === 'string' ? body.clientId : null, approval, via: 'dev_literal' };
  const m = approval.match(/^pa1\.mock\.([^.]+)\.(.+)$/);
  if (!m || !parents.has(m[2])) return { error: 'malformed' };
  if (typeof body?.clientId === 'string' && body.clientId && body.clientId !== m[1]) return { error: 'wrong_client' };
  return { parentId: m[2], clientId: m[1], approval, via: 'approval' };
}
function bodyHashOf(body) { return crypto.createHash('sha256').update(JSON.stringify(body ?? null)).digest('hex'); }

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const path = url.pathname.replace(/^\/api(?=\/v1\/)/, '');
  const now = nowOf(req);
  if (req.method === 'GET' && (path === '/healthz' || path === '/v1/health')) {
    return send(res, 200, { ok: true, mock: true, service: 'little-days-cloud', apiVersion: 'v1', devMode: true, provider: 'mock' });
  }
  if (req.headers.upgrade) return; // handled by 'upgrade'

  const body = req.method === 'GET' ? {} : await readBody(req);
  if (body === null) return fail(res, 400, 'bad_request', 'Body must be valid JSON.');

  // -- DEV sign-in (no credential) --------------------------------------------------------
  if (req.method === 'POST' && path === '/v1/parents') {
    if (body.provider !== 'dev') return fail(res, body.provider === 'apple' || body.provider === 'google' ? 501 : 400, body.provider === 'apple' || body.provider === 'google' ? 'not_implemented' : 'bad_request');
    const subject = String(body.subject || '');
    const clientId = String(body.clientId || '');
    if (!subject || !ID_RE.test(subject)) return fail(res, 400, 'bad_request', 'subject is required');
    if (clientId && !ID_RE.test(clientId)) return fail(res, 400, 'bad_request', 'clientId has an invalid format');
    const parentId = `p-${crypto.createHash('sha256').update(subject).digest('hex').slice(0, 12)}`;
    const created = !parents.has(parentId);
    if (created) parents.set(parentId, { consent: new Set() });
    const out = { parentId, created, parentToken: `pt1.mock.${parentId}`, expiresAt: new Date(now + 30 * 86400 * 1000).toISOString(), devMode: true };
    if (clientId) out.parentApprovalToken = `pa1.mock.${clientId}.${parentId}`;
    log(`201 parents created=${created} scenario=${Object.entries(scenarioOf(clientId)).filter(([, v]) => v).map(([k]) => k).join(',') || 'default'}`);
    return send(res, 201, out);
  }

  const auth = authOf(req, body);
  if (auth.error) {
    log(`403 ${req.method} ${path} (${auth.error})`);
    return fail(res, 403, 'not_approved', auth.error === 'expired_sign_in' ? 'The parent sign-in has expired. Please sign in again.' : 'A parent needs to approve tutor time first.');
  }
  const parent = parents.get(auth.parentId);

  // -- consent (parent sign-in only) -------------------------------------------------------
  if (req.method === 'PUT' && path === '/v1/consent') {
    if (auth.via !== 'bearer') return fail(res, 403, 'not_approved', 'Consent changes need the parent sign-in, not a device approval.');
    const kind = String(body.kind || '');
    if (!['privacy', 'ai_tutor', 'voice'].includes(kind)) return fail(res, 400, 'bad_request', 'kind must be one of privacy, ai_tutor, voice');
    if (body.granted === false) parent.consent.delete(kind); else parent.consent.add(kind);
    log(`200 consent ${kind} granted=${body.granted !== false}`);
    const consent = {};
    for (const k of ['privacy', 'ai_tutor', 'voice']) consent[k] = { version: parent.consent.has(k) ? 1 : 0, granted: parent.consent.has(k) };
    return send(res, 200, { parentId: auth.parentId, requiredVersion: 1, consent });
  }

  // -- tutor routes need the approval (the Worker's approvalHash rule) ------------------------
  if (!auth.approval) {
    log(`403 ${req.method} ${path} (sign-in header on a tutor route)`);
    return fail(res, 403, 'not_approved', 'Tutor time needs a parental-approval token (X-Parent-Approval).');
  }
  const clientId = auth.clientId || String(url.searchParams.get('clientId') || body.clientId || '');
  const scenario = scenarioOf(clientId);
  const childId = auth.parentId;
  if (scenario.deny) return fail(res, 403, 'not_approved');

  if (req.method === 'GET' && (path === '/v1/tutor/entitlement' || path === '/v1/tutor/quota')) {
    for (const s of sessions.values()) if (s.childId === childId) settle(s, now);
    log(`200 entitlement used=${usedFor(childId).toFixed(1)} turns=${turnsFor(childId)}`);
    return send(res, 200, { clientId: clientId || null, childId, entitlement: 'free', quota: quotaBlock(childId, scenario, now), products: ['little_days.family_club.monthly', 'little_days.family_club.yearly'] });
  }

  if (req.method === 'POST' && path === '/v1/tutor/sessions') {
    const lessonId = String(body.lessonId || '');
    if (!lessonId || !clientId) return fail(res, 400, 'bad_request', 'lessonId and clientId are required');
    if (!parent.consent.has('ai_tutor')) return fail(res, 403, 'consent_required', 'A parent needs to give consent in Parent Corner first.', { kind: 'ai_tutor' });
    const st = scenarioState.get(clientId) ?? {};
    if (scenario.rate && !st.rateLimited) { st.rateLimited = true; scenarioState.set(clientId, st); return fail(res, 429, 'rate_limited', 'Too many requests. Please wait a moment.', { retryAfterSeconds: 0.2 }); }
    const q = quotaBlock(childId, scenario, now);
    if (q.remainingSeconds <= 0) { log(`429 sessions quota_exhausted`); return fail(res, 429, 'quota_exhausted', 'Great job today! Come back tomorrow for more Little Days!', { reason: 'daily_quota', quota: q }); }
    if (q.usedTurns >= TURN_ALLOWANCE) return fail(res, 429, 'quota_exhausted', 'Aliz needs a little rest.', { reason: 'daily_turns', quota: q });
    counter += 1;
    const session = {
      sessionId: crypto.randomUUID(), childId, clientId, lessonId, approval: auth.approval, mode: 'turns', scenario,
      createdAt: now, lastEventAt: now, realtimeStartedAt: 0, lastChargedAt: 0, expiresAtMs: 0, endedAt: 0, endReason: null,
      responses: 0, turns: 0, socket: null,
    };
    sessions.set(session.sessionId, session);
    log(`201 sessions ${session.sessionId} lesson=${lessonId} scenario=${Object.entries(scenario).filter(([, v]) => v).map(([k]) => k).join(',') || 'default'}`);
    return send(res, 201, { sessionId: session.sessionId, childId, entitlement: 'free', quota: q, lessonId, lessonKnown: true });
  }

  if (req.method === 'POST' && path === '/v1/tutor/realtime/token') {
    if (scenario.norealtime) { log(`503 token (norealtime scenario)`); return fail(res, 503, 'provider_unavailable', 'Realtime tutoring is not configured on this server.'); }
    const session = sessions.get(String(body.sessionId || ''));
    if (!session) return fail(res, 404, 'not_found', 'Session not found.');
    if (session.approval !== auth.approval) return fail(res, 403, 'not_approved', 'This session belongs to another approval.');
    if (session.endedAt) return fail(res, 409, 'session_ended', 'This lesson session has already ended.');
    settle(session, now);
    const q = quotaBlock(childId, scenario, now);
    if (q.remainingSeconds <= 0) { log(`429 token quota_exhausted`); return fail(res, 429, 'quota_exhausted', 'Great job today!', { reason: 'daily_quota', quota: q }); }
    const value = `mock-rt-${crypto.randomBytes(12).toString('hex')}`;
    const seconds = Math.max(10, Math.min(600, Math.floor(q.remainingSeconds + GRACE)));
    session.expiresAtMs = now + seconds * 1000;
    session.mode = 'realtime';
    if (!session.realtimeStartedAt) { session.realtimeStartedAt = now; session.lastChargedAt = now; }
    countTurn(childId);
    tokens.set(value, session.sessionId);
    log(`201 token ${session.sessionId} expires_in=${seconds}s`);
    return send(res, 201, {
      sessionId: session.sessionId, quotaSessionId: session.sessionId,
      clientSecret: { value, expiresAt: Math.floor(session.expiresAtMs / 1000) },
      token: { value, expiresAt: new Date(session.expiresAtMs).toISOString() },
      expiresInSeconds: seconds,
      wsUrl: `ws://${HOST}:${PORT}/v1/realtime?model=mock-realtime`,
      subprotocols: ['realtime', `mock-token.${value}`],
      headers: [],
      sessionUpdate: { type: 'session.update', session: { type: 'realtime', output_modalities: ['audio'], instructions: 'mock lesson' } },
      realtime: { model: 'mock-realtime', turnDetection: 'semantic_vad', mock: true, transport: 'websocket' },
      quota: quotaBlock(childId, scenario, now), lessonKnown: true,
    });
  }

  const turnMatch = path.match(/^\/v1\/tutor\/sessions\/([^/]+)\/turns$/);
  if (req.method === 'POST' && turnMatch) {
    const session = sessions.get(turnMatch[1]);
    if (!session) return fail(res, 404, 'not_found', 'Session not found.');
    if (session.approval !== auth.approval) return fail(res, 403, 'not_approved', 'This session belongs to another approval.');
    if (session.endedAt) return fail(res, 409, 'session_ended', 'This lesson session has already ended.');
    if (session.realtimeStartedAt) return fail(res, 400, 'bad_request', 'this is a realtime session; report usage instead of turns');
    const key = String(req.headers['idempotency-key'] || '').slice(0, 200);
    const idemId = key ? `${session.sessionId}\n${key}` : null;
    const hash = bodyHashOf(body);
    if (idemId && idempotency.has(idemId)) {
      const prior = idempotency.get(idemId);
      if (prior.bodyHash !== hash) return fail(res, 422, 'idempotency_mismatch', 'Idempotency-Key was reused with a different request.');
      log(`200 turn ${session.sessionId} replayed`);
      return send(res, 200, prior.body, { 'idempotent-replayed': 'true' });
    }
    if (typeof body.transcript !== 'string' && body.transcript !== undefined) return fail(res, 400, 'bad_request', 'transcript must be a string');
    const lc = body.lessonContext;
    if (!lc || typeof lc !== 'object' || Array.isArray(lc)) return fail(res, 400, 'invalid_turn', 'lessonContext is required');
    if (!OUTCOMES.has(lc.outcome)) return fail(res, 400, 'invalid_turn', 'lessonContext.outcome must be correct, incorrect or unclear');
    if (typeof lc.stepId !== 'string' || !lc.stepId) return fail(res, 400, 'invalid_turn', 'lessonContext.stepId is required');
    const before = quotaBlock(childId, scenario, now);
    if (before.remainingSeconds <= 0) { endSession(session, 'quota_exhausted', now); return fail(res, 429, 'quota_exhausted', 'Great job today!', { reason: 'daily_quota', quota: before }); }
    if (before.usedTurns >= TURN_ALLOWANCE) { endSession(session, 'daily_turns', now); return fail(res, 429, 'quota_exhausted', 'Aliz needs a little rest.', { reason: 'daily_turns', quota: before }); }
    const gap = Math.min(Math.max(0, (now - session.lastEventAt) / 1000), TURN_CAP);
    const chargedSeconds = Math.max(gap, TURN_FLOOR);
    const line = scriptFor(body.transcript || '', session.scenario);
    charge(childId, chargedSeconds, allowanceFor(scenario) + GRACE);
    countTurn(childId);
    session.turns += 1;
    session.lastEventAt = now;
    const q = quotaBlock(childId, scenario, now);
    const endAtBoundary = q.remainingSeconds <= 0 || q.usedTurns >= TURN_ALLOWANCE || lc.lessonAction === 'end_session';
    const reply = {
      turn: { speech: line.speech, subtitle: line.speech, emotion: line.emotion, gesture: line.gesture,
        visual: line.card ? { type: 'flashcard', assetId: line.card } : { type: 'none' }, lessonAction: line.card ? 'next_question' : 'retry' },
      quota: q, endAtBoundary, turnIndex: session.turns, chargedSeconds: Math.round(chargedSeconds * 10) / 10,
      provider: 'mock', cached: false, fallback: null, contextSource: 'server',
      usage: { sttSeconds: 0, llmInputTokens: 0, llmOutputTokens: 0, ttsChars: line.speech.length, latencyMs: 1, costUsd: 0 },
    };
    if (idemId) idempotency.set(idemId, { bodyHash: hash, body: reply });
    log(`200 turn ${session.sessionId} #${session.turns} outcome=${lc.outcome} transcript_chars=${String(body.transcript || '').length} charged=${chargedSeconds} boundary=${endAtBoundary}`);
    return send(res, 200, reply);
  }

  const endMatch = path.match(/^\/v1\/tutor\/sessions\/([^/]+)\/end$/);
  if (req.method === 'POST' && endMatch) {
    const session = sessions.get(endMatch[1]);
    if (!session) return fail(res, 404, 'not_found', 'Session not found.');
    if (session.approval !== auth.approval) return fail(res, 403, 'not_approved', 'This session belongs to another approval.');
    const reason = body.reason === undefined ? 'client_end' : String(body.reason);
    if (reason.length > MAX_END_REASON) return fail(res, 400, 'bad_request', `reason is too long (max ${MAX_END_REASON})`);
    const wasOpen = !session.endedAt;
    if (wasOpen) {
      if (!session.realtimeStartedAt) charge(childId, Math.min(Math.max(0, (now - session.lastEventAt) / 1000), TURN_CAP), allowanceFor(scenario) + GRACE);
      endSession(session, reason, now);
    }
    log(`200 end ${session.sessionId} reason=${reason} first=${wasOpen} turns=${session.turns} responses=${session.responses}`);
    return send(res, 200, {
      sessionId: session.sessionId, endedAt: new Date(session.endedAt).toISOString(), quota: quotaBlock(childId, scenario, now),
      usage: { turns: session.turns, llmInputTokens: 0, llmOutputTokens: 0, audioSeconds: 0, costUsd: 0 },
    });
  }

  fail(res, 404, 'not_found', 'Not found.');
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
  if (!token) { const auth = String(req.headers.authorization || ''); if (/^bearer\s+/i.test(auth)) token = auth.replace(/^bearer\s+/i, '').trim(); }
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

server.listen(PORT, HOST, () => log(`listening on http://${HOST}:${PORT} (allowance ${ALLOWANCE}s, turn floor ${TURN_FLOOR}s, word ${WORD_MS}ms); no provider, no key, no transcript logging`));
