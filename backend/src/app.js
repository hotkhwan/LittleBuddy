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
import { fallbackTurn, loadAssetAllowlist, validateTurn } from './turn_validator.js';
import { createMockProvider } from './providers/mock_provider.js';
import { createOpenAIProvider } from './providers/openai_provider.js';
import { ApiError, errors } from './errors.js';

export const API_VERSION = 'v1';
export const OUTCOMES = Object.freeze(['correct', 'incorrect', 'unclear']);
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
  const quota = createQuota({ store, config, now });
  const entitlements = createEntitlements({ store, config, now });
  const approval = createParentalApproval({ config, now });
  const limiter = createRateLimiter({ now });
  const usage = createUsage({ store, config, now });
  const cache = createTurnCache({ now, ttlSeconds: config.turnCacheTtlSeconds, maxEntries: config.turnCacheMaxEntries });
  const mock = createMockProvider({ allowlist: allowlist.ids });

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

  function requireBudget() {
    if (usage.budgetExceeded()) throw errors.quotaExhausted(null, 'monthly_budget');
  }

  /** @param {any} body */
  function parseLessonContext(body) {
    const lc = body?.lessonContext;
    if (!lc || typeof lc !== 'object' || Array.isArray(lc)) throw errors.invalidTurn('lessonContext is required');
    const outcome = lc.outcome;
    if (!OUTCOMES.includes(outcome)) throw errors.invalidTurn('lessonContext.outcome must be correct, incorrect or unclear');
    const stepId = str(lc, 'stepId', { required: true, max: 80, re: ID_RE });
    const expected = lc.expectedAnswers === undefined ? [] : lc.expectedAnswers;
    if (!Array.isArray(expected) || expected.length > 20 || expected.some((e) => typeof e !== 'string' || e.length > 80)) {
      throw errors.invalidTurn('lessonContext.expectedAnswers must be a short array of strings');
    }
    /** @type {import('./types.js').LessonContext} */
    const ctx = {
      stepId,
      outcome,
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

  /** @param {any} body */
  function bodyHash(body) {
    return crypto.createHash('sha256').update(JSON.stringify(body ?? null)).digest('hex');
  }

  // ----------------------------------------------------------------- routes
  router.add('GET', '/healthz', () => ({
    status: 200,
    body: { ok: true, service: 'little-days-tutor-backend', apiVersion: API_VERSION, provider: providerNote, devMode: config.devMode, allowlistSource: allowlist.source, uptimeSeconds: Math.round((now() - startedAt) / 1000) },
  }));

  router.add('POST', `/api/${API_VERSION}/tutor/sessions`, (ctx) => {
    limitIp(ctx.ip);
    const lessonId = str(ctx.body, 'lessonId', { required: true, max: 80, re: ID_RE });
    const clientId = str(ctx.body, 'clientId', { required: true, max: 128, re: ID_RE });
    const token = ctx.body?.parentApprovalToken;
    const ok = approval.verify(token, clientId);
    if (!ok.ok) throw errors.notApproved();

    const entitlement = entitlements.get(clientId);
    requireBudget();
    const q = quota.state(clientId, entitlement);
    if (q.remainingSeconds <= 0) throw errors.quotaExhausted(q);

    const t = now();
    const session = {
      sessionId: crypto.randomUUID(),
      clientId,
      lessonId,
      entitlement,
      approvedVia: ok.dev ? 'dev_token' : 'signed_token',
      startedAt: t,
      lastEventAt: t,
      turnCount: 0,
      endedAt: null,
      endReason: null,
    };
    store.sessions.set(session.sessionId, session);
    return { status: 201, body: { sessionId: session.sessionId, entitlement, quota: q, lessonId } };
  });

  router.add('POST', `/api/${API_VERSION}/tutor/sessions/{id}/turns`, async (ctx) => {
    limitIp(ctx.ip);
    const session = requireSession(ctx.params.id);
    const sr = limiter.hit(`session:${session.sessionId}`, config.sessionTurnsPerMinute);
    if (!sr.allowed) throw errors.rateLimited(sr.retryAfterSeconds);
    if (session.endedAt) throw errors.sessionEnded();

    const idemKey = ctx.headers['idempotency-key'];
    const idemId = idemKey ? `${session.sessionId}:${idemKey}` : null;
    const hash = bodyHash(ctx.body);
    if (idemId) {
      const prior = store.idempotency.get(idemId);
      if (prior) {
        if (prior.hash !== hash) throw errors.idempotencyMismatch();
        return { status: prior.status, body: prior.body, headers: { 'idempotent-replayed': 'true' } };
      }
    }

    const transcript = str(ctx.body, 'transcript', { max: MAX_TRANSCRIPT });
    const lessonContext = parseLessonContext(ctx.body);
    const audioSeconds = Math.max(0, Math.min(MAX_AUDIO_SECONDS, Number(ctx.body?.audioSeconds) || 0));

    requireBudget();
    const entitlement = entitlements.get(session.clientId);
    const t0 = now();
    const before = quota.state(session.clientId, entitlement);
    if (before.remainingSeconds <= 0) {
      endSession(session, 'quota_exhausted', t0, 0);
      throw errors.quotaExhausted(before);
    }
    const charged = quota.gapSeconds(session.lastEventAt, t0);
    const q = quota.charge(session.clientId, entitlement, charged);
    const endAtBoundary = q.remainingSeconds <= 0;

    const produced = await produceTurn({ transcript, lessonId: session.lessonId, lessonContext, signal: ctx.signal });
    const latencyMs = now() - t0;

    session.turnCount += 1;
    session.lastEventAt = now();
    store.sessions.set(session.sessionId, session);

    const usageEntry = usage.recordTurn(session.sessionId, session.turnCount, {
      sttSeconds: audioSeconds,
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
      quota: q,
      endAtBoundary,
      turnIndex: session.turnCount,
      chargedSeconds: Math.round(charged * 10) / 10,
      provider: produced.provider,
      cached: produced.cached,
      fallback: produced.fallback,
      usage: { sttSeconds: usageEntry.sttSeconds, llmInputTokens: usageEntry.llmInputTokens, llmOutputTokens: usageEntry.llmOutputTokens, ttsChars: usageEntry.ttsChars, latencyMs: usageEntry.latencyMs, costUsd: usageEntry.costUsd },
    };
    if (idemId) store.idempotency.set(idemId, { hash, status: 200, body, at: now() });
    return { status: 200, body };
  });

  /** @param {any} session @param {string} reason @param {number} t @param {number} [chargedOverride] */
  function endSession(session, reason, t, chargedOverride) {
    if (session.endedAt) return quota.state(session.clientId, entitlements.get(session.clientId));
    const entitlement = entitlements.get(session.clientId);
    const charged = chargedOverride ?? quota.gapSeconds(session.lastEventAt, t);
    const q = quota.charge(session.clientId, entitlement, charged);
    session.endedAt = t;
    session.lastEventAt = t;
    session.endReason = reason;
    store.sessions.set(session.sessionId, session);
    return q;
  }

  router.add('POST', `/api/${API_VERSION}/tutor/sessions/{id}/end`, (ctx) => {
    limitIp(ctx.ip);
    const session = requireSession(ctx.params.id);
    const q = endSession(session, str(ctx.body, 'reason', { max: 40 }) || 'client_end', now());
    return { status: 200, body: { sessionId: session.sessionId, endedAt: new Date(session.endedAt).toISOString(), quota: q, usage: usage.sessionTotals(session.sessionId) } };
  });

  router.add('GET', `/api/${API_VERSION}/tutor/entitlement`, (ctx) => {
    limitIp(ctx.ip);
    const clientId = ctx.url.searchParams.get('clientId') || '';
    if (!ID_RE.test(clientId)) throw errors.badRequest('clientId query parameter is required');
    const entitlement = entitlements.get(clientId);
    return { status: 200, body: { clientId, entitlement, quota: quota.state(clientId, entitlement), products: FAMILY_CLUB_PRODUCT_IDS } };
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
    router.add('GET', `/api/${API_VERSION}/dev/spend`, () => ({ status: 200, body: { ...usage.monthlySpend(), monthlyBudgetUsd: config.monthlyBudgetUsd, cache: cache.stats() } }));
  }

  /**
   * Dispatch one request context. Never throws: errors become JSON bodies.
   * @param {import('./types.js').RequestContext} ctx
   * @returns {Promise<import('./types.js').Response>}
   */
  async function dispatch(ctx) {
    try {
      const m = router.match(ctx.method, ctx.url.pathname);
      if (!m) throw errors.notFound();
      if ('allowed' in m) return { status: 405, body: { error: { code: 'method_not_allowed', message: `Use ${m.allowed.join(', ')}` } }, headers: { allow: m.allowed.join(', ') } };
      return await m.handler({ ...ctx, params: m.params });
    } catch (err) {
      if (err instanceof ApiError) {
        const headers = err.code === 'rate_limited' ? { 'retry-after': String(err.extra.retryAfterSeconds ?? 1) } : {};
        return { status: err.status, body: err.toBody(), headers };
      }
      if (ctx.signal.aborted) return { status: 499, body: { error: { code: 'client_cancelled', message: 'Request cancelled.' } } };
      log(`unhandled error: ${err?.stack ?? err}`);
      return { status: 500, body: errors.internal().toBody() };
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
    allowlist,
    provider: primary,
    providerNote,
    dispatch,
    close: () => store.flushAll(),
  };
}
