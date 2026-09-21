// Aliz AI Tutor routes: sessions, turns, end, quota, realtime token, usage,
// delete history. Thin: the TutorSessionDO owns ordering, clock, quota and
// provider calls; this file authenticates, resolves the child and unwraps.
import { Hono } from 'hono';
import { allowanceFor, type Env } from '../env';
import { requireAuth, type AppContext, type Vars } from '../auth/context';
import { ApiError, errors } from '../errors';
import { hmacHex, uuid } from '../util/crypto';
import { ID_RE, str } from '../util/validate';
import { resolveChild } from '../db/children';
import { upsertDevice } from '../db/devices';
import { hasConsent } from '../db/consent';
import { getEntitlement } from '../db/entitlements';
import { budgetExceeded } from '../db/usage';
import { deleteDeviceHistory } from '../db/retention';
import { LESSONS } from '../tutor/lessons';
import { REALTIME_MAX_EXPIRY_SECONDS, REALTIME_MIN_EXPIRY_SECONDS, buildRealtimeInstructions } from '../tutor/realtime_instructions';
import { CHAT_LESSON_ID, SESSION_MODES, chatAllowed, featureDisabled, loadChatConfig, type SessionMode } from '../tutor/chat_config';
import type { DoResult } from '../do/types';
import type { QuotaState } from '../tutor/types';
import type { TurnOutput } from '../do/tutor_session_do';

export const tutorRoutes = new Hono<{ Bindings: Env; Variables: Vars }>();

/** RPC stubs erase the DoResult union, so the result is re-narrowed at runtime. */
function unwrap<T>(raw: unknown): T {
  const r = raw as DoResult<T>;
  if (r && r.ok) return r.value;
  if (r && !r.ok) throw ApiError.fromWire(r.error);
  throw errors.internal();
}

async function approvalHash(c: AppContext): Promise<string> {
  const auth = requireAuth(c);
  if (!auth.approvalToken) throw errors.notApproved('Tutor time needs a parental-approval token (X-Parent-Approval).');
  return hmacHex(c.env.PARENT_TOKEN_SECRET || '', 'approval', auth.approvalToken);
}

function stub(c: AppContext, sessionId: string) {
  if (!/^[0-9a-f-]{36}$/.test(sessionId)) throw errors.notFound('Session not found.');
  return c.env.TUTOR_SESSION.get(c.env.TUTOR_SESSION.idFromName(sessionId));
}

async function quotaFor(c: AppContext, parentId: string, childId: string): Promise<QuotaState> {
  const config = c.get('config');
  const now = c.get('now');
  const entitlement = await getEntitlement(c.env.DB, parentId, config, now);
  const a = allowanceFor(config, entitlement);
  return c.env.QUOTA.get(c.env.QUOTA.idFromName(childId)).snapshot({ childId, nowMs: now, entitlement, allowanceSeconds: a.seconds, turnAllowance: a.turns });
}

/** Shared by POST /sessions and POST /realtime/token: consent, device, child, budget, quota, DO start. */
async function createSession(c: AppContext) {
  const auth = requireAuth(c);
  const config = c.get('config');
  const now = c.get('now');
  const body = c.get('body');
  // T2: `mode` ("lesson" default | "chat"). Chat is a DEV_MODE + FREE_CHAT_ENABLED
  // feature until the privacy gates pass; anywhere else it is 403 feature_disabled.
  const modeRaw = str(body, 'mode', { max: 16 }) || 'lesson';
  if (!SESSION_MODES.includes(modeRaw as SessionMode)) throw errors.badRequest('mode must be lesson or chat');
  const mode = modeRaw as SessionMode;
  const chatConfig = loadChatConfig(c.env);
  if (mode === 'chat' && !chatAllowed(config, chatConfig)) throw featureDisabled('free_chat');
  const lessonId = mode === 'chat' ? (str(body, 'lessonId', { max: 80, re: ID_RE }) || CHAT_LESSON_ID) : str(body, 'lessonId', { required: true, max: 80, re: ID_RE });
  const clientId = str(body, 'clientId', { required: true, max: 128, re: ID_RE });
  if (!auth.approvalToken || (auth.clientId && auth.clientId !== clientId)) throw errors.notApproved();
  if (mode === 'lesson' && !LESSONS.has(lessonId) && !config.devMode) throw errors.unknownLesson();
  if (!(await hasConsent(c.env.DB, auth.parentId, 'ai_tutor', config.consentVersion))) throw errors.consentRequired('ai_tutor');

  const device = await upsertDevice(c.env.DB, { id: clientId, parentId: auth.parentId, now });
  if (!device) throw errors.conflict('This device is registered to another family.');
  const child = await resolveChild(c.env.DB, auth.parentId, str(body, 'childId', { max: 64 }), auth.childId ?? undefined, now);
  if (!child) throw errors.notFound('Child not found.');
  if (await budgetExceeded(c.env.DB, config.monthlyBudgetUsd, now)) throw errors.quotaExhausted(null, 'monthly_budget');

  const entitlement = await getEntitlement(c.env.DB, auth.parentId, config, now);
  const a = allowanceFor(config, entitlement);
  const q = await c.env.QUOTA.get(c.env.QUOTA.idFromName(child.id)).snapshot({ childId: child.id, nowMs: now, entitlement, allowanceSeconds: a.seconds, turnAllowance: a.turns });
  if (q.remainingSeconds <= 0) throw errors.quotaExhausted(q);
  if (q.usedTurns >= a.turns) throw errors.quotaExhausted(q, 'daily_turns');

  const sessionId = uuid();
  unwrap(await stub(c, sessionId).start({
    sessionId,
    parentId: auth.parentId,
    childId: child.id,
    clientId,
    lessonId,
    providerName: config.providerName,
    approvalHash: await approvalHash(c),
    devMode: config.devMode,
    nowMs: now,
    sessionMode: mode,
    chat: mode === 'chat' ? { contextTurns: chatConfig.contextTurns, responseMaxWords: chatConfig.responseMaxWords, maxOutputTokens: chatConfig.maxOutputTokens } : undefined,
  }));
  return { sessionId, childId: child.id, lessonId, entitlement, quota: q, lessonKnown: LESSONS.has(lessonId), mode, chatConfig };
}

tutorRoutes.post('/tutor/sessions', async (c) => {
  const s = await createSession(c);
  const out: Record<string, unknown> = { sessionId: s.sessionId, childId: s.childId, entitlement: s.entitlement, quota: s.quota, lessonId: s.lessonId, lessonKnown: s.lessonKnown, mode: s.mode };
  if (s.mode === 'chat') out.chat = { responseMaxWords: s.chatConfig.responseMaxWords, contextTurns: s.chatConfig.contextTurns };
  return c.json(out, 201);
});

tutorRoutes.post('/tutor/sessions/:id/turns', async (c) => {
  const r = unwrap<TurnOutput>(await stub(c, c.req.param('id')).turn({
    approvalHash: await approvalHash(c),
    idempotencyKey: (c.req.header('idempotency-key') || '').slice(0, 200) || null,
    body: c.get('body'),
    nowMs: c.get('now'),
  }));
  if (r.replayed) c.header('idempotent-replayed', 'true');
  return c.json(r.body, r.status as 200);
});

tutorRoutes.post('/tutor/sessions/:id/end', async (c) => {
  const r = unwrap<Record<string, unknown>>(await stub(c, c.req.param('id')).end({ approvalHash: await approvalHash(c), reason: str(c.get('body'), 'reason', { max: 40 }) || 'client_end', nowMs: c.get('now') }));
  return c.json(r);
});

tutorRoutes.post('/tutor/sessions/:id/usage', async (c) => {
  const r = unwrap<Record<string, unknown>>(await stub(c, c.req.param('id')).usageReport({ approvalHash: await approvalHash(c), nowMs: c.get('now'), body: c.get('body') }));
  return c.json(r);
});

/** Parent Corner "stop tutor time now" with the parent sign-in. */
tutorRoutes.post('/tutor/sessions/:id/stop', async (c) => {
  const auth = requireAuth(c);
  const r = unwrap<{ ended: boolean }>(await stub(c, c.req.param('id')).parentStop({ parentId: auth.parentId, nowMs: c.get('now') }));
  return c.json({ sessionId: c.req.param('id'), ...r });
});

/** GET /tutor/quota[?childId=] and the prototype's GET /tutor/entitlement?clientId= */
async function quotaReply(c: AppContext) {
  const auth = requireAuth(c);
  const config = c.get('config');
  const now = c.get('now');
  const child = await resolveChild(c.env.DB, auth.parentId, c.req.query('childId') || '', auth.childId ?? undefined, now);
  if (!child) throw errors.notFound('Child not found.');
  const entitlement = await getEntitlement(c.env.DB, auth.parentId, config, now);
  return {
    clientId: c.req.query('clientId') || auth.clientId || null,
    childId: child.id,
    entitlement,
    quota: await quotaFor(c, auth.parentId, child.id),
    products: config.familyClubProductIds,
    priceHint: config.priceHint,
  };
}
tutorRoutes.get('/tutor/quota', async (c) => c.json(await quotaReply(c)));
tutorRoutes.get('/tutor/entitlement', async (c) => c.json(await quotaReply(c)));

// Realtime: mint an ephemeral client secret bound to a quota session. Only
// with a configured provider (OPENAI_API_KEY + Agent E's module); otherwise
// 503 provider_unavailable, DEV_MODE included.
tutorRoutes.post('/tutor/realtime/token', async (c) => {
  const auth = requireAuth(c);
  const config = c.get('config');
  const now = c.get('now');
  const provider = c.get('provider');
  const body = c.get('body');
  if (!provider.realtime) throw errors.providerUnavailable('Realtime tutoring is not configured on this server.');
  if ((str(body, 'mode', { max: 16 }) || 'lesson') !== 'lesson') throw errors.badRequest('realtime sessions are lesson sessions; free chat runs on the turns path');
  if (!(await hasConsent(c.env.DB, auth.parentId, 'voice', config.consentVersion))) throw errors.consentRequired('voice');

  let sessionId: string;
  let lessonId: string;
  let q: QuotaState;
  const existingId = str(body, 'sessionId', { max: 64 });
  if (existingId) {
    const pre = unwrap<{ quota: QuotaState; lessonId: string; childId: string; parentId: string }>(await stub(c, existingId).realtimePrecheck({ approvalHash: await approvalHash(c), nowMs: now }));
    sessionId = existingId;
    lessonId = pre.lessonId;
    q = pre.quota;
  } else {
    const s = await createSession(c);
    sessionId = s.sessionId;
    lessonId = s.lessonId;
    q = s.quota;
  }
  const lesson = LESSONS.get(lessonId) ?? null;
  const expiresSeconds = Math.max(REALTIME_MIN_EXPIRY_SECONDS, Math.min(REALTIME_MAX_EXPIRY_SECONDS, Math.floor(q.remainingSeconds + config.realtimeGraceSeconds)));
  const instructions = buildRealtimeInstructions(lesson ?? { lessonId, title: lessonId, steps: [] });
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), config.providerTimeoutMs);
  let minted;
  try {
    minted = await provider.realtime.mint({ lesson, instructions, expiresSeconds, turnDetection: config.realtimeTurnDetection, voice: config.realtimeVoice, signal: ac.signal });
  } catch (err) {
    console.log(`[tutor] realtime mint failed: ${(err as { status?: number })?.status ?? 'error'}`);
    throw errors.providerUnavailable('Realtime tutoring is not available right now.');
  } finally {
    clearTimeout(timer);
  }
  const expiresAtMs = Date.parse(minted.expiresAt);
  if (!Number.isFinite(expiresAtMs) || !minted.value) throw errors.providerUnavailable('Realtime tutoring is not available right now.');
  const quota = unwrap<QuotaState>(await stub(c, sessionId).attachRealtime({ approvalHash: await approvalHash(c), nowMs: now, expiresAt: expiresAtMs, model: minted.model }));

  // Both shapes: the game's CloudRealtimeTransport (clientSecret/wsUrl/subprotocols/sessionUpdate)
  // and the prototype's (token/realtime/quota).
  return c.json({
    sessionId,
    quotaSessionId: sessionId,
    clientSecret: { value: minted.value, expiresAt: Math.floor(expiresAtMs / 1000) },
    token: { value: minted.value, expiresAt: minted.expiresAt },
    expiresInSeconds: Math.max(0, Math.floor((expiresAtMs - now) / 1000)),
    wsUrl: minted.wsUrl,
    subprotocols: minted.subprotocols ?? [],
    headers: minted.headers ?? [],
    sessionUpdate: minted.sessionUpdate ?? null,
    realtime: { model: minted.model, turnDetection: minted.turnDetection, mock: false, transport: 'websocket', note: 'Send only this ephemeral value to the provider; it expires with your quota.' },
    quota,
    lessonKnown: Boolean(lesson),
  }, 201);
});

// "Delete learning history" for a device (parent credential for that device).
tutorRoutes.delete('/tutor/clients/:clientId', async (c) => {
  const auth = requireAuth(c);
  const clientId = c.req.param('clientId');
  if (!ID_RE.test(clientId)) throw errors.badRequest('clientId has an invalid format');
  if (auth.clientId && auth.clientId !== clientId) throw errors.notApproved();
  const deleted = await deleteDeviceHistory(c.env.DB, clientId, auth.parentId);
  return c.json({ clientId, deleted });
});
