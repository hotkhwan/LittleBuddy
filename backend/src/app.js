// Application wiring: routes -> domain modules. No HTTP details here beyond
// the RequestContext/Response shapes, so tests can drive it in-process or
// over a real socket.
import crypto from 'node:crypto';
import { createRouter } from './router.js';
import { createStore } from './store.js';
import { createQuota } from './quota.js';
import { createEntitlements, ENTITLEMENTS, FAMILY_CLUB_PRODUCT_IDS } from './entitlement.js';
import { createParentalApproval } from './parental_approval.js';
import { createRateLimiter } from './rate_limit.js';
import { createUsage } from './usage.js';
import { createTurnCache } from './turn_cache.js';
import { createRetention, IDEMPOTENCY_TTL_MS } from './retention.js';
import { loadLessons, resolveLessonContext } from './lessons.js';
import { fallbackTurn, loadAssetAllowlist, validateTurn } from './turn_validator.js';
import { createMockProvider } from './providers/mock_provider.js';
import { createOpenAIProvider } from './providers/openai_provider.js';
import { createRealtimeTokenMinter, buildRealtimeInstructions, REALTIME_MAX_EXPIRY_SECONDS, REALTIME_MIN_EXPIRY_SECONDS } from './providers/openai_realtime.js';
import { ApiError, errors } from './errors.js';

export const API_VERSION = 'v1';
export const OUTCOMES = Object.freeze(['correct', 'incorrect', 'unclear']);
export const PARENT_TOKEN_HEADER = 'x-parent-approval';
const ID_RE = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;
const MAX_TRANSCRIPT = 500;
const MAX_CONTEXT_TEXT = 240;
const MAX_AUDIO_SECONDS = 30;

/**
 * @param {{config: import('./config.js').Config, now?: () => number, fetchImpl?: typeof fetch, provider?: import('./types.js').ConversationProvider, persist?: boolean, log?: (msg: string) => void}} opts
 */
export function createApp({ config, now = () => Date.now(), fetchImpl, provider, persist = true, log = () => {} }) {
  const store = createStore({ dataDir: config.dataDir, persist });
  const allowlist = loadAssetAllowlist(config.allowlistPath);
  const lessonSet = loadLessons(config.lessonsDir);
  for (const e of lessonSet.errors) log(`lessons: ${e}`);
  const quota = createQuota({ store, config, now });
  const entitlements = createEntitlements({ store, config, now });
  const approval = createParentalApproval({ config, now });
  const limiter = createRateLimiter({ now });
  const usage = createUsage({ store, config, now });
  const cache = createTurnCache({ now, ttlSeconds: config.turnCacheTtlSeconds, maxEntries: config.turnCacheMaxEntries });
  const retention = createRetention({ store, now, retentionDays: config.retentionDays });
  const mock = createMockProvider({ allowlist: allowlist.ids });

  // Per-server random salt (persisted in DATA_DIR, never in code) for hashing
  // idempotency bodies and binding sessions to their approval token (M3, H3).
  let salt = store.meta.get('salt');
  if (typeof salt !== 'string' || salt.length < 32) {
    salt = crypto.randomBytes(32).toString('hex');
    store.meta.set('salt', salt);
  }
  /** @param {string} purpose @param {string} value */
  const hmac = (purpose, value) => crypto.createHmac('sha256', salt).update(`${purpose}\n${value}`).digest('hex');

  /** @type {import('./types.js').ConversationProvider} */
  let primary = provider ?? mock;
  let providerNote = provider ? provider.name : 'mock';
  if (!provider && config.provider === 'openai') {
    if (config.openaiApiKey) {
      primary = createOpenAIProvider({ apiKey: config.openaiApiKey, model: config.model, baseUrl: config.openaiBaseUrl, fetchImpl, extraHeaders: config.openaiExtraHeaders });
      providerNote = primary.name;
    } else {
      providerNote = 'mock (TUTOR_PROVIDER=openai requested but OPENAI_API_KEY is not set)';
      log(`provider: ${providerNote}`);
    }
  }

  // Realtime ephemeral-token minter: only with a server-side key. Tests inject fetchImpl.
  const realtimeMinter = config.openaiApiKey
    ? createRealtimeTokenMinter({ apiKey: config.openaiApiKey, model: config.realtimeModel, baseUrl: config.openaiBaseUrl, fetchImpl, voice: config.realtimeVoice, transcriptionModel: config.sttModel, extraHeaders: config.openaiExtraHeaders })
    : null;

  const router = createRouter();
  const startedAt = now();

  // ---------------------------------------------------------------- helpers
  /** @param {string} ip */
  function limitIp(ip) {
    const r = limiter.hit(`ip:${ip}`, config.ipPerMinute);
    if (!r.allowed) throw errors.rateLimited(r.retryAfterSeconds);
  }

  /** @param {any} body @param {string} field @param {{required?: boolean, max?: number, re?: RegExp}} [o] */
  function str(body, field, o = {}) {
    const v = body?.[field];
    if (v === undefined || v === null || v === '') {
      if (o.required) throw errors.badRequest(`${field} is required`);
      return '';
    }
    if (typeof v !== 'string') throw errors.badRequest(`${field} must be a string`);
    if (o.max && v.length > o.max) throw errors.badRequest(`${field} is too long (max ${o.max})`);
    if (o.re && !o.re.test(v)) throw errors.badRequest(`${field} has an invalid format`);
    return v;
  }

  /** @param {string} sessionId */
  function requireSession(sessionId) {
    const s = store.sessions.get(sessionId);
    if (!s) throw errors.notFound('Session not found.');
    return s;
  }

  /** The parent token travels in the X-Parent-Approval header or the body. */
  function tokenFrom(ctx) {
    const h = ctx.headers[PARENT_TOKEN_HEADER];
    if (typeof h === 'string' && h) return h;
    const b = ctx.body?.parentApprovalToken;
    return typeof b === 'string' ? b : '';
  }

  /**
   * H3/M6: a session accepts calls only with the very token that created it,
   * which must still verify (not expired) for the session's clientId.
   * @param {import('./types.js').RequestContext} ctx
   * @param {any} session
   */
  function requireOwner(ctx, session) {
    const token = tokenFrom(ctx);
    const ok = token && approval.verify(token, session.clientId).ok && hmac('approval', token) === session.approvalHash;
    if (!ok) throw errors.notApproved('This session belongs to another approval.');
  }

  function requireBudget() {
    if (usage.budgetExceeded()) throw errors.quotaExhausted(null, 'monthly_budget');
  }

  /**
   * Client-supplied context, used ONLY in DEV_MODE for lessons the server does
   * not know (finding M2). Text fields are bounded and asset ids allowlisted.
   * @param {any} lc
   */
  function devClientContext(lc) {
    const expected = lc.expectedAnswers === undefined ? [] : lc.expectedAnswers;
    if (!Array.isArray(expected) || expected.length > 20 || expected.some((e) => typeof e !== 'string' || e.length > 80)) {
      throw errors.invalidTurn('lessonContext.expectedAnswers must be a short array of strings');
    }
    /** @type {import('./types.js').LessonContext} */
    const ctx = {
      stepId: lc.stepId,
      outcome: lc.outcome,
      expectedAnswers: expected,
      hint: str(lc, 'hint', { max: MAX_CONTEXT_TEXT }),
      nextQuestionText: str(lc, 'nextQuestionText', { max: MAX_CONTEXT_TEXT }),
      visualAssetId: str(lc, 'visualAssetId', { max: 64 }),
      matched: str(lc, 'matched', { max: 80 }),
      lessonAction: str(lc, 'lessonAction', { max: 32 }),
    };
    if (ctx.visualAssetId && !allowlist.ids.includes(ctx.visualAssetId)) ctx.visualAssetId = '';
    return ctx;
  }

  /**
   * Resolve the trusted lesson context for a turn. The server's lesson files
   * are the authority; the client contributes stepId, outcome, matched and a
   * plausibility-checked lessonAction only.
   * @param {any} body
   * @param {string} lessonId
   * @returns {{lessonContext: import('./types.js').LessonContext, source: 'server'|'client_dev'}}
   */
  function resolveContext(body, lessonId) {
    const lc = body?.lessonContext;
    if (!lc || typeof lc !== 'object' || Array.isArray(lc)) throw errors.invalidTurn('lessonContext is required');
    if (!OUTCOMES.includes(lc.outcome)) throw errors.invalidTurn('lessonContext.outcome must be correct, incorrect or unclear');
    const stepId = str(lc, 'stepId', { required: true, max: 80, re: ID_RE });
    const lesson = lessonSet.lessons.get(lessonId);
    if (lesson) {
      const resolved = resolveLessonContext(lesson, { stepId, outcome: lc.outcome, matched: str(lc, 'matched', { max: 80 }), lessonAction: str(lc, 'lessonAction', { max: 32 }) });
      if (!resolved) throw errors.invalidTurn('lessonContext.stepId is not a step of this lesson');
      if (resolved.visualAssetId && !allowlist.ids.includes(resolved.visualAssetId)) resolved.visualAssetId = '';
      return { lessonContext: resolved, source: 'server' };
    }
    if (!config.devMode) throw errors.unknownLesson();
    return { lessonContext: devClientContext(lc), source: 'client_dev' };
  }

  /**
   * Call the primary provider with a timeout and cancellation; fall back to
   * the deterministic mock on any failure. Always returns a VALID turn.
   * @param {{transcript: string, lessonId: string, lessonContext: import('./types.js').LessonContext, signal: AbortSignal}} input
   */
  async function produceTurn(input) {
    const cacheable = primary !== mock && config.turnCacheTtlSeconds > 0;
    const cacheKey = cache.key({ lessonId: input.lessonId, stepId: input.lessonContext.stepId, outcome: input.lessonContext.outcome, hint: input.lessonContext.hint });
    if (cacheable) {
      const hit = cache.get(cacheKey);
      if (hit) return { turn: hit, usage: { llmInputTokens: 0, llmOutputTokens: 0 }, provider: primary.name, cached: true, fallback: null };
    }

    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(new Error('provider_timeout')), config.providerTimeoutMs);
    const onAbort = () => ac.abort(new Error('client_cancelled'));
    input.signal.addEventListener('abort', onAbort, { once: true });
    let fallback = null;
    let result;
    try {
      result = await primary.generateTurn({ ...input, signal: ac.signal });
      const v = validateTurn(result.turn, { allowlist: allowlist.ids });
      if (!v.ok) {
        fallback = `invalid_turn:${v.reasons.slice(0, 3).join(',')}`;
        log(`provider ${primary.name} produced an invalid turn: ${v.reasons.join(',')}`);
        result = null;
      } else {
        result = { ...result, turn: v.turn };
        if (cacheable) cache.set(cacheKey, v.turn);
      }
    } catch (err) {
      result = null;
      fallback = ac.signal.aborted ? String(ac.signal.reason?.message ?? 'aborted') : `provider_error:${err?.status ?? err?.message ?? 'unknown'}`;
      if (fallback === 'client_cancelled') throw err;
      log(`provider ${primary.name} failed: ${fallback}`);
    } finally {
      clearTimeout(timer);
      input.signal.removeEventListener('abort', onAbort);
    }

    if (result) return { ...result, provider: primary.name, cached: false, fallback: null };

    if (primary === mock) throw errors.providerUnavailable();
    const m = await mock.generateTurn(input);
    const mv = validateTurn(m.turn, { allowlist: allowlist.ids });
    return { turn: mv.ok ? mv.turn : fallbackTurn(), usage: m.usage, provider: 'mock', cached: false, fallback };
  }

  /** Salted HMAC of the canonical body: not reversible by dictionary (M3). */
  function bodyHash(body) {
    return hmac('idempotency', JSON.stringify(body ?? null));
  }

  /** @param {any} session @param {string} reason @param {number} t @param {number} [chargedOverride] */
  function endSession(session, reason, t, chargedOverride) {
    if (session.endedAt) return quota.state(session.clientId, entitlements.get(session.clientId));
    const entitlement = entitlements.get(session.clientId);
    if (session.realtime) settleRealtime(session, t);
    const charged = session.realtime ? 0 : (chargedOverride ?? quota.gapSeconds(session.lastEventAt, t));
    const q = quota.charge(session.clientId, entitlement, charged);
    session.endedAt = t;
    session.lastEventAt = t;
    session.endReason = reason;
    store.sessions.set(session.sessionId, session);
    return q;
  }

  // ----------------------------------------------------------------- routes
  router.add('GET', '/healthz', () => ({
    status: 200,
    body: config.devMode
      ? { ok: true, service: 'little-days-tutor-backend', apiVersion: API_VERSION, provider: providerNote, devMode: true, allowlistSource: allowlist.source, lessons: lessonSet.lessons.size, uptimeSeconds: Math.round((now() - startedAt) / 1000) }
      : { ok: true, apiVersion: API_VERSION },
  }));

  /**
   * Realtime sessions are not turn-based: the client streams audio to the
   * provider directly with an ephemeral token. The server still owns the
   * clock: elapsed time since the last server event is charged, bounded by
   * the token's expiry (which was set to remaining quota + grace), NOT by the
   * per-turn cap, because there may be no turns at all. Runs on every server
   * event for the session and for all of a client's open realtime sessions
   * whenever that client touches the quota again.
   * @param {any} session @param {number} t
   */
  function settleRealtime(session, t) {
    if (!session.realtime || session.endedAt) return 0;
    const until = Math.min(t, Date.parse(session.realtime.expiresAt));
    const seconds = Math.max(0, (until - session.lastEventAt) / 1000);
    if (seconds > 0) quota.chargeUncapped(session.clientId, entitlements.get(session.clientId), seconds, config.realtimeGraceSeconds);
    session.lastEventAt = Math.max(session.lastEventAt, until);
    store.sessions.set(session.sessionId, session);
    return seconds;
  }

  /** Settle every open realtime session of a client before reading its quota. */
  function settleClient(clientId, t) {
    for (const s of store.sessions.values()) if (s.clientId === clientId && s.realtime && !s.endedAt) settleRealtime(s, t);
  }

  /**
   * Shared session creation for /sessions and /realtime/token.
   * @param {import('./types.js').RequestContext} ctx
   */
  function createSessionRecord(ctx) {
    const lessonId = str(ctx.body, 'lessonId', { required: true, max: 80, re: ID_RE });
    const clientId = str(ctx.body, 'clientId', { required: true, max: 128, re: ID_RE });
    const token = tokenFrom(ctx);
    const ok = approval.verify(token, clientId);
    if (!ok.ok) throw errors.notApproved();
    if (!lessonSet.lessons.has(lessonId) && !config.devMode) throw errors.unknownLesson();

    const t = now();
    settleClient(clientId, t);
    const entitlement = entitlements.get(clientId);
    requireBudget();
    const q = quota.state(clientId, entitlement);
    if (q.remainingSeconds <= 0) throw errors.quotaExhausted(q);
    if (quota.turnCapReached(clientId, entitlement)) throw errors.quotaExhausted(q, 'daily_turns');

    const session = {
      sessionId: crypto.randomUUID(),
      clientId,
      lessonId,
      entitlement,
      approvedVia: ok.dev ? 'dev_token' : 'signed_token',
      approvalHash: hmac('approval', token),
      startedAt: t,
      lastEventAt: t,
      turnCount: 0,
      endedAt: null,
      endReason: null,
    };
    store.sessions.set(session.sessionId, session);
    return { session, quota: q, entitlement };
  }

  router.add('POST', `/api/${API_VERSION}/tutor/sessions`, (ctx) => {
    limitIp(ctx.ip);
    const { session, quota: q, entitlement } = createSessionRecord(ctx);
    return { status: 201, body: { sessionId: session.sessionId, entitlement, quota: q, lessonId: session.lessonId, lessonKnown: lessonSet.lessons.has(session.lessonId) } };
  });

  // Realtime: mint an ephemeral client secret bound to a quota session. The
  // game never sees OPENAI_API_KEY. Expiry = min(remaining + grace, 7200 s),
  // so the token itself ends the conversation when the allowance runs out
  // even if the client never reports usage.
  router.add('POST', `/api/${API_VERSION}/tutor/realtime/token`, async (ctx) => {
    limitIp(ctx.ip);
    if (!realtimeMinter && !config.devMode) throw errors.providerUnavailable('Realtime tutoring is not configured on this server.');
    let session;
    let q;
    const existingId = str(ctx.body, 'sessionId', { max: 64 });
    if (existingId) {
      session = requireSession(existingId);
      requireOwner(ctx, session);
      if (session.endedAt) throw errors.sessionEnded();
      settleRealtime(session, now());
      requireBudget();
      q = quota.state(session.clientId, entitlements.get(session.clientId));
      if (q.remainingSeconds <= 0) throw errors.quotaExhausted(q);
      if (quota.turnCapReached(session.clientId, session.entitlement)) throw errors.quotaExhausted(q, 'daily_turns');
    } else {
      ({ session, quota: q } = createSessionRecord(ctx));
    }
    const lesson = lessonSet.lessons.get(session.lessonId);
    const expiresSeconds = Math.max(REALTIME_MIN_EXPIRY_SECONDS, Math.min(REALTIME_MAX_EXPIRY_SECONDS, Math.floor(q.remainingSeconds + config.realtimeGraceSeconds)));
    const t = now();
    let minted;
    if (realtimeMinter) {
      const instructions = lesson ? buildRealtimeInstructions(lesson) : buildRealtimeInstructions({ lessonId: session.lessonId, title: session.lessonId, steps: [] });
      try {
        minted = await realtimeMinter.mint({ instructions, expiresSeconds, turnDetection: config.realtimeTurnDetection, signal: ctx.signal });
      } catch (err) {
        log(`realtime mint failed: ${err?.status ?? err?.message ?? 'unknown'}`);
        throw errors.providerUnavailable('Realtime tutoring is not available right now.');
      }
    } else {
      minted = { value: 'dev-realtime-token', expiresAt: new Date(t + expiresSeconds * 1000).toISOString(), model: 'mock', turnDetection: config.realtimeTurnDetection };
    }
    // A mint is a provider call: count it toward the daily turn cap.
    const usedTurns = quota.countTurn(session.clientId);
    session.realtime = { mintedAt: t, expiresAt: minted.expiresAt, model: minted.model, mints: (session.realtime?.mints ?? 0) + 1 };
    session.lastEventAt = t;
    store.sessions.set(session.sessionId, session);
    return {
      status: 201,
      body: {
        sessionId: session.sessionId,
        token: { value: minted.value, expiresAt: minted.expiresAt },
        realtime: { model: minted.model, turnDetection: minted.turnDetection, mock: !realtimeMinter, transport: 'websocket_or_webrtc', note: 'Send only this ephemeral value to OpenAI; it expires with your quota.' },
        quota: { ...quota.state(session.clientId, entitlements.get(session.clientId)), usedTurns },
        lessonKnown: Boolean(lesson),
      },
    };
  });

  // Realtime usage reports: summaries of the provider's server events
  // (response.done -> response.usage) relayed by the client. They feed COST
  // accounting only. They are NOT the quota authority: seconds come from the
  // server clock (settleRealtime), and each report counts as one turn toward
  // the daily turn cap. Any client-supplied "usedSeconds"/"remainingSeconds"
  // is ignored.
  router.add('POST', `/api/${API_VERSION}/tutor/sessions/{id}/usage`, (ctx) => {
    limitIp(ctx.ip);
    const session = requireSession(ctx.params.id);
    requireOwner(ctx, session);
    if (session.endedAt) throw errors.sessionEnded();
    if (!session.realtime) throw errors.badRequest('usage reports are only accepted for realtime sessions');
    const sr = limiter.hit(`session:${session.sessionId}`, config.sessionTurnsPerMinute);
    if (!sr.allowed) throw errors.rateLimited(sr.retryAfterSeconds);
    const b = ctx.body ?? {};
    if (b.usedSeconds !== undefined || b.remainingSeconds !== undefined || b.quota !== undefined) {
      throw errors.badRequest('client timers are not accepted as quota authority; report provider usage events only');
    }
    const entitlement = entitlements.get(session.clientId);
    if (quota.turnCapReached(session.clientId, entitlement)) {
      endSession(session, 'daily_turns', now());
      throw errors.quotaExhausted(quota.state(session.clientId, entitlement), 'daily_turns');
    }
    const t = now();
    settleRealtime(session, t);
    const usedTurns = quota.countTurn(session.clientId);
    session.turnCount += 1;
    session.lastEventAt = Math.max(session.lastEventAt, t);
    store.sessions.set(session.sessionId, session);
    const clampTok = (v) => Math.max(0, Math.min(5_000_000, Math.round(Number(v) || 0)));
    const clampSec = (v) => Math.max(0, Math.min(7200, Number(v) || 0));
    const realtime = {
      realtimeAudioInputTokens: clampTok(b.inputAudioTokens),
      realtimeCachedAudioInputTokens: clampTok(b.cachedInputAudioTokens),
      realtimeAudioOutputTokens: clampTok(b.outputAudioTokens),
      realtimeTextInputTokens: clampTok(b.inputTextTokens),
      realtimeCachedTextInputTokens: clampTok(b.cachedInputTextTokens),
      realtimeTextOutputTokens: clampTok(b.outputTextTokens),
      reportedInputAudioSeconds: clampSec(b.inputAudioSeconds),
      reportedOutputAudioSeconds: clampSec(b.outputAudioSeconds),
      responses: clampTok(b.responses),
    };
    const entry = usage.recordTurn(session.sessionId, session.turnCount, { provider: `openai-realtime:${session.realtime.model}`, latencyMs: 0, realtime });
    const q = quota.state(session.clientId, entitlement);
    const endAtBoundary = q.remainingSeconds <= 0 || usedTurns >= quota.turnAllowanceFor(entitlement) || Date.parse(session.realtime.expiresAt) <= t;
    return { status: 200, body: { sessionId: session.sessionId, recorded: { turnIndex: session.turnCount, costUsd: entry.costUsd, priceMissing: entry.priceMissing }, quota: { ...q, usedTurns }, endAtBoundary, tokenExpiresAt: session.realtime.expiresAt } };
  });

  router.add('POST', `/api/${API_VERSION}/tutor/sessions/{id}/turns`, async (ctx) => {
    limitIp(ctx.ip);
    const session = requireSession(ctx.params.id);
    requireOwner(ctx, session);
    const sr = limiter.hit(`session:${session.sessionId}`, config.sessionTurnsPerMinute);
    if (!sr.allowed) throw errors.rateLimited(sr.retryAfterSeconds);
    if (session.endedAt) throw errors.sessionEnded();

    const idemKey = ctx.headers['idempotency-key'];
    const idemId = idemKey ? `${session.sessionId}:${hmac('idempotency-key', idemKey).slice(0, 32)}` : null;
    const hash = bodyHash(ctx.body);
    if (idemId) {
      const prior = store.idempotency.get(idemId);
      if (prior && now() - prior.at <= IDEMPOTENCY_TTL_MS) {
        if (prior.hash !== hash) throw errors.idempotencyMismatch();
        return { status: prior.status, body: prior.body, headers: { 'idempotent-replayed': 'true' } };
      }
    }

    const transcript = str(ctx.body, 'transcript', { max: MAX_TRANSCRIPT });
    const { lessonContext, source } = resolveContext(ctx.body, session.lessonId);
    const clientReportedAudioSeconds = Math.max(0, Math.min(MAX_AUDIO_SECONDS, Number(ctx.body?.audioSeconds) || 0));

    requireBudget();
    const entitlement = entitlements.get(session.clientId);
    const t0 = now();
    const before = quota.state(session.clientId, entitlement);
    if (before.remainingSeconds <= 0) {
      endSession(session, 'quota_exhausted', t0, 0);
      throw errors.quotaExhausted(before);
    }
    if (quota.turnCapReached(session.clientId, entitlement)) {
      endSession(session, 'daily_turns', t0);
      throw errors.quotaExhausted(before, 'daily_turns');
    }
    const gap = quota.gapSeconds(session.lastEventAt, t0);

    // Provider first; quota is charged only once a turn is actually served
    // (a client that disconnects mid-call is not charged). A provider timeout
    // still yields a served (fallback) turn and is charged.
    const produced = await produceTurn({ transcript, lessonId: session.lessonId, lessonContext, signal: ctx.signal });
    const latencyMs = now() - t0;

    const q = quota.charge(session.clientId, entitlement, gap);
    const usedTurns = quota.countTurn(session.clientId);
    const endAtBoundary = q.remainingSeconds <= 0 || usedTurns >= quota.turnAllowanceFor(entitlement) || lessonContext.lessonAction === 'end_session';
    session.turnCount += 1;
    session.lastEventAt = now();
    store.sessions.set(session.sessionId, session);

    const usageEntry = usage.recordTurn(session.sessionId, session.turnCount, {
      sttSeconds: 0, // no server-side STT today; client-reported audio is never costed (L4)
      clientReportedAudioSeconds,
      llmInputTokens: produced.usage.llmInputTokens,
      llmOutputTokens: produced.usage.llmOutputTokens,
      cachedInputTokens: produced.usage.cachedInputTokens,
      ttsChars: produced.turn.speech.length,
      latencyMs,
      cached: produced.cached,
      provider: produced.provider,
    });

    const body = {
      turn: produced.turn,
      quota: { ...q, usedTurns },
      endAtBoundary,
      turnIndex: session.turnCount,
      chargedSeconds: Math.round(gap * 10) / 10,
      provider: produced.provider,
      cached: produced.cached,
      fallback: produced.fallback,
      contextSource: source,
      usage: { sttSeconds: usageEntry.sttSeconds, llmInputTokens: usageEntry.llmInputTokens, llmOutputTokens: usageEntry.llmOutputTokens, ttsChars: usageEntry.ttsChars, latencyMs: usageEntry.latencyMs, costUsd: usageEntry.costUsd },
    };
    if (idemId) store.idempotency.set(idemId, { hash, status: 200, body, at: now() });
    return { status: 200, body };
  });

  router.add('POST', `/api/${API_VERSION}/tutor/sessions/{id}/end`, (ctx) => {
    limitIp(ctx.ip);
    const session = requireSession(ctx.params.id);
    requireOwner(ctx, session);
    const q = endSession(session, str(ctx.body, 'reason', { max: 40 }) || 'client_end', now());
    return { status: 200, body: { sessionId: session.sessionId, endedAt: new Date(session.endedAt).toISOString(), quota: q, usage: usage.sessionTotals(session.sessionId) } };
  });

  router.add('GET', `/api/${API_VERSION}/tutor/entitlement`, (ctx) => {
    limitIp(ctx.ip);
    const clientId = ctx.url.searchParams.get('clientId') || '';
    if (!ID_RE.test(clientId)) throw errors.badRequest('clientId query parameter is required');
    settleClient(clientId, now());
    const entitlement = entitlements.get(clientId);
    return { status: 200, body: { clientId, entitlement, quota: quota.state(clientId, entitlement), products: FAMILY_CLUB_PRODUCT_IDS } };
  });

  // M4: "Delete learning history" for a client. Requires a valid parent token
  // for that clientId (header or body).
  router.add('DELETE', `/api/${API_VERSION}/tutor/clients/{clientId}`, (ctx) => {
    limitIp(ctx.ip);
    const clientId = ctx.params.clientId;
    if (!ID_RE.test(clientId)) throw errors.badRequest('clientId has an invalid format');
    if (!approval.verify(tokenFrom(ctx), clientId).ok) throw errors.notApproved();
    const deleted = retention.deleteClient(clientId);
    return { status: 200, body: { clientId, deleted } };
  });

  router.add('POST', `/api/${API_VERSION}/tutor/billing/validate`, (ctx) => {
    limitIp(ctx.ip);
    const clientId = str(ctx.body, 'clientId', { required: true, max: 128, re: ID_RE });
    const platform = str(ctx.body, 'platform', { required: true, max: 20 });
    const result = entitlements.validateReceipt({ clientId, platform, receipt: ctx.body?.receipt });
    return { status: 200, body: { clientId, ...result, quota: quota.state(clientId, result.entitlement) } };
  });

  // ------------------------------------------------------------ dev routes
  if (config.devMode) {
    router.add('POST', `/api/${API_VERSION}/dev/entitlement`, (ctx) => {
      const clientId = str(ctx.body, 'clientId', { required: true, max: 128, re: ID_RE });
      const entitlement = str(ctx.body, 'entitlement', { required: true, max: 20 });
      if (!ENTITLEMENTS.includes(entitlement)) throw errors.badRequest('entitlement must be free or family_club');
      const rec = entitlements.devSet(clientId, entitlement);
      return { status: 200, body: { clientId, entitlement: rec.entitlement, source: rec.source, quota: quota.state(clientId, rec.entitlement) } };
    });
    router.add('POST', `/api/${API_VERSION}/dev/billing/mock-purchase`, (ctx) => {
      const clientId = str(ctx.body, 'clientId', { required: true, max: 128, re: ID_RE });
      const productId = str(ctx.body, 'productId', { max: 80 }) || FAMILY_CLUB_PRODUCT_IDS[0];
      return { status: 200, body: { clientId, ...entitlements.mockPurchase(clientId, productId), next: `POST /api/${API_VERSION}/tutor/billing/validate with {clientId, platform, receipt}` } };
    });
    router.add('POST', `/api/${API_VERSION}/dev/parent-approval`, (ctx) => {
      const clientId = str(ctx.body, 'clientId', { required: true, max: 128, re: ID_RE });
      const token = approval.mint(clientId);
      return { status: 200, body: { clientId, parentApprovalToken: token, devToken: config.devParentApprovalToken } };
    });
    router.add('GET', `/api/${API_VERSION}/dev/spend`, () => ({ status: 200, body: { ...usage.monthlySpend(), monthlyBudgetUsd: config.monthlyBudgetUsd, cache: cache.stats(), lessons: [...lessonSet.lessons.keys()] } }));
    router.add('POST', `/api/${API_VERSION}/dev/retention/purge`, () => ({ status: 200, body: retention.purge() }));
  }

  /**
   * Dispatch one request context. Never throws: errors become JSON bodies.
   * The returned `route` is the pattern (no ids, no query) for access logs (M1).
   * @param {import('./types.js').RequestContext} ctx
   * @returns {Promise<import('./types.js').Response & {route: string}>}
   */
  async function dispatch(ctx) {
    let route = 'unmatched';
    try {
      const m = router.match(ctx.method, ctx.url.pathname);
      if (!m) throw errors.notFound();
      if ('allowed' in m) return { status: 405, body: { error: { code: 'method_not_allowed', message: `Use ${m.allowed.join(', ')}` } }, headers: { allow: m.allowed.join(', ') }, route };
      route = m.pattern;
      const res = await m.handler({ ...ctx, params: m.params });
      return { ...res, route };
    } catch (err) {
      if (err instanceof ApiError) {
        const headers = err.code === 'rate_limited' ? { 'retry-after': String(err.extra.retryAfterSeconds ?? 1) } : {};
        return { status: err.status, body: err.toBody(), headers, route };
      }
      if (ctx.signal.aborted) return { status: 499, body: { error: { code: 'client_cancelled', message: 'Request cancelled.' } }, route };
      log(`unhandled error on ${route}: ${err?.stack ?? err}`);
      return { status: 500, body: errors.internal().toBody(), route };
    }
  }

  return {
    config,
    store,
    quota,
    entitlements,
    approval,
    usage,
    cache,
    retention,
    lessons: lessonSet,
    allowlist,
    provider: primary,
    providerNote,
    dispatch,
    close: () => store.flushAll(),
  };
}
