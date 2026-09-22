// TutorSessionDO: ONE object per live tutor session. It serialises the
// session's events (turn ordering), owns the server clock for the session
// (start -> turn -> end, each gap capped), runs the idempotency check, calls
// the provider, validates the turn, charges the child's QuotaDO, writes the
// numeric usage rows, and terminates itself on quota, idle timeout, token
// expiry or a parent stop (alarm-driven countdown).
import { DurableObject } from 'cloudflare:workers';
import { ApiError, errors } from '../errors';
import { allowanceFor, loadConfig, type Config, type Entitlement, type Env } from '../env';
import { getEntitlement } from '../db/entitlements';
import { hasConsent } from '../db/consent';
import { budgetExceeded, recordUsage, sessionTotals } from '../db/usage';
import { findIdempotent, storeIdempotent } from '../db/idempotency';
import { insertSession, markSessionEnded, updateSessionProgress } from '../db/sessions';
import { ASSET_ALLOWLIST } from '../tutor/content';
import { LESSONS, resolveLessonContext } from '../tutor/lessons';
import { createMockTurnProvider } from '../tutor/mock_provider';
import { resolveProvider } from '../tutor/provider_registry';
import type { TurnProvider, TurnUsage } from '../tutor/provider_interface';
import { fallbackTurn, validateTurn } from '../tutor/turn_validator';
import type { LessonContext, Outcome, QuotaState, TutorTurn } from '../tutor/types';
// Free chat (T2): mode "chat" sessions keep a rolling context window here in
// the DO (never in D1), gate every reply through gateChatTurn and clear the
// window when the session ends.
import { chatProviderOf, createMockChatProvider, gateChatTurn, toChatTurn, type ChatMessage, type ChatTurn, type ChatTurnProvider } from '../tutor/chat_provider';
import { checkChatText, redirectTurn } from '../tutor/chat_safety';
import { clampResponseWords, type SessionMode } from '../tutor/chat_config';
import { hmacHex, sha256Hex } from '../util/crypto';
import { FixedWindowLimiter } from '../util/rate_limit';
import { ID_RE, MAX_AUDIO_SECONDS, MAX_TRANSCRIPT, isObject, str } from '../util/validate';
import { estimateCostMicro } from '../tutor/cost';
import { ok, type DoResult } from './types';
import type { QuotaKey } from './quota_do';

export interface SessionRecord {
  sessionId: string;
  parentId: string;
  childId: string;
  clientId: string;
  lessonId: string;
  mode: 'turns' | 'realtime';
  providerName: Config['providerName'];
  approvalHash: string;
  devMode: boolean;
  startedAt: number;
  lastEventAt: number;
  turnCount: number;
  secondsUsed: number;
  endedAt: number | null;
  endReason: string | null;
  realtime: { mintedAt: number; expiresAt: number; model: string; mints: number } | null;
  /** "lesson" (default) or "chat" (free conversation, DEV_MODE + FREE_CHAT_ENABLED only). */
  sessionMode?: SessionMode;
  /** Chat sessions only: the config snapshot and the rolling window (cleared on end). */
  chat?: ChatSessionState | null;
}

export interface ChatSessionState {
  contextTurns: number;
  responseMaxWords: number;
  maxOutputTokens: number;
  history: ChatMessage[];
}

export interface StartInput {
  sessionId: string;
  parentId: string;
  childId: string;
  clientId: string;
  lessonId: string;
  providerName: Config['providerName'];
  approvalHash: string;
  devMode: boolean;
  nowMs: number;
  sessionMode?: SessionMode;
  chat?: { contextTurns: number; responseMaxWords: number; maxOutputTokens: number };
}

export interface TurnInputRpc { approvalHash: string; idempotencyKey: string | null; body: unknown; nowMs: number }
export interface TurnOutput { status: number; body: Record<string, unknown>; replayed: boolean }

const OUTCOMES: readonly Outcome[] = ['correct', 'incorrect', 'unclear'];
const MAX_CONTEXT_TEXT = 240;

export class TutorSessionDO extends DurableObject<Env> {
  private rec: SessionRecord | null = null;
  private loaded = false;
  private queue: Promise<unknown> = Promise.resolve();
  private readonly limiter = new FixedWindowLimiter();
  private readonly config: Config;
  private readonly mock: TurnProvider;
  private readonly mockChat: ChatTurnProvider;
  private primary: TurnProvider | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.config = loadConfig(env);
    this.mock = createMockTurnProvider({ allowlist: ASSET_ALLOWLIST.ids });
    this.mockChat = createMockChatProvider({ allowlist: ASSET_ALLOWLIST.ids });
  }

  // ---------------------------------------------------------------- plumbing
  private serialize<T>(fn: () => Promise<T>): Promise<T> {
    const run = this.queue.then(fn, fn);
    this.queue = run.catch(() => undefined);
    return run;
  }

  private async load(): Promise<SessionRecord | null> {
    if (!this.loaded) {
      this.rec = (await this.ctx.storage.get<SessionRecord>('rec')) ?? null;
      this.loaded = true;
    }
    return this.rec;
  }

  private async save(): Promise<void> {
    if (this.rec) await this.ctx.storage.put('rec', this.rec);
  }

  private wrap<T>(fn: () => Promise<T>): Promise<DoResult<T>> {
    return this.serialize(async () => {
      try {
        return ok(await fn());
      } catch (err) {
        if (err instanceof ApiError) return { ok: false, error: err.toWire() };
        console.log(`[tutor-session] unhandled: ${err instanceof Error ? err.message : 'error'}`);
        return { ok: false, error: errors.internal().toWire() };
      }
    });
  }

  private quotaStub() {
    const rec = this.rec!;
    return this.env.QUOTA.get(this.env.QUOTA.idFromName(rec.childId));
  }

  private async quotaKey(nowMs: number): Promise<QuotaKey & { entitlement: Entitlement }> {
    const rec = this.rec!;
    const entitlement = await getEntitlement(this.env.DB, rec.parentId, this.config, nowMs);
    const a = allowanceFor(this.config, entitlement);
    return { childId: rec.childId, nowMs, entitlement, allowanceSeconds: a.seconds, turnAllowance: a.turns };
  }

  private provider(): TurnProvider {
    if (!this.primary) {
      const rec = this.rec!;
      const cfg = { ...this.config, providerName: rec.providerName };
      // Both providers: Workers AI through the `AI` binding (Codex), OpenAI
      // through the key with the chat extras (Claude). The registry picks by
      // `providerName`; the mock serves when neither is configured.
      this.primary = resolveProvider(cfg, this.env.OPENAI_API_KEY, undefined, {
        ai: this.env.AI,
        baseUrl: this.env.OPENAI_BASE_URL,
        maxOutputTokens: rec.chat?.maxOutputTokens,
      }).turns;
    }
    return this.primary;
  }

  private gapSeconds(fromMs: number, toMs: number): number {
    return Math.min(Math.max(0, (toMs - fromMs) / 1000), this.config.turnCapSeconds);
  }

  private async scheduleAlarm(): Promise<void> {
    const rec = this.rec!;
    if (rec.endedAt) {
      await this.ctx.storage.deleteAlarm();
      return;
    }
    const idleAt = rec.lastEventAt + this.config.sessionIdleSeconds * 1000;
    const at = rec.realtime ? Math.min(rec.realtime.expiresAt, Math.max(idleAt, rec.realtime.expiresAt)) : idleAt;
    await this.ctx.storage.setAlarm(at);
  }

  /** Charge the realtime clock between the last event and min(now, token expiry). */
  private async settleRealtime(nowMs: number, key: QuotaKey): Promise<void> {
    const rec = this.rec!;
    if (!rec.realtime || rec.endedAt) return;
    const until = Math.min(nowMs, rec.realtime.expiresAt);
    const seconds = Math.max(0, (until - rec.lastEventAt) / 1000);
    if (seconds > 0) {
      await this.quotaStub().chargeUncapped(key, seconds, this.config.realtimeGraceSeconds);
      rec.secondsUsed += seconds;
    }
    rec.lastEventAt = Math.max(rec.lastEventAt, until);
  }

  private async endInternal(reason: string, nowMs: number, key: QuotaKey, chargedOverride?: number): Promise<QuotaState> {
    const rec = this.rec!;
    if (rec.endedAt) return this.quotaStub().snapshot(key);
    let q: QuotaState;
    if (rec.realtime) {
      await this.settleRealtime(nowMs, key);
      q = await this.quotaStub().snapshot(key);
    } else {
      const charged = chargedOverride ?? this.gapSeconds(rec.lastEventAt, nowMs);
      q = await this.quotaStub().charge(key, charged, this.config.turnCapSeconds);
      rec.secondsUsed += charged;
    }
    rec.endedAt = nowMs;
    rec.lastEventAt = nowMs;
    rec.endReason = reason;
    if (rec.chat) rec.chat.history = [];  // the child's words never outlive the session
    await this.save();
    await markSessionEnded(this.env.DB, rec.sessionId, nowMs, reason, rec.secondsUsed, rec.turnCount);
    await this.ctx.storage.deleteAlarm();
    return q;
  }

  private requireOwner(approvalHash: string): SessionRecord {
    const rec = this.rec;
    if (!rec) throw errors.notFound('Session not found.');
    if (!approvalHash || approvalHash !== rec.approvalHash) throw errors.notApproved('This session belongs to another approval.');
    return rec;
  }

  // ------------------------------------------------------------------- RPC
  async start(input: StartInput): Promise<DoResult<{ sessionId: string }>> {
    return this.wrap(async () => {
      if (await this.load()) throw errors.conflict('Session already exists.');
      this.rec = {
        sessionId: input.sessionId,
        parentId: input.parentId,
        childId: input.childId,
        clientId: input.clientId,
        lessonId: input.lessonId,
        mode: 'turns',
        providerName: input.providerName,
        approvalHash: input.approvalHash,
        devMode: input.devMode,
        startedAt: input.nowMs,
        lastEventAt: input.nowMs,
        turnCount: 0,
        secondsUsed: 0,
        endedAt: null,
        endReason: null,
        realtime: null,
        sessionMode: input.sessionMode === 'chat' ? 'chat' : 'lesson',
        chat: input.sessionMode === 'chat' && input.chat ? { ...input.chat, history: [] } : null,
      };
      await this.save();
      await insertSession(this.env.DB, { id: input.sessionId, childId: input.childId, deviceId: input.clientId, lessonId: input.lessonId, mode: 'turns', provider: this.provider().name, startedAt: input.nowMs });
      await this.scheduleAlarm();
      return { sessionId: input.sessionId };
    });
  }

  async info(): Promise<SessionRecord | null> {
    const rec = await this.load();
    return rec ? { ...rec } : null;
  }

  async turn(input: TurnInputRpc): Promise<DoResult<TurnOutput>> {
    return this.wrap(async () => {
      await this.load();
      const rec = this.requireOwner(input.approvalHash);
      const sr = this.limiter.hit('turns', this.config.sessionTurnsPerMinute, input.nowMs);
      if (!sr.allowed) throw errors.rateLimited(sr.retryAfterSeconds);
      if (rec.endedAt) throw errors.sessionEnded();
      if (rec.realtime) throw errors.badRequest('this is a realtime session; report usage instead of turns');

      const secret = this.env.PARENT_TOKEN_SECRET || '';
      const idemId = input.idempotencyKey ? await hmacHex(secret, 'idempotency-key', `${rec.sessionId}\n${input.idempotencyKey}`) : null;
      const bodyHash = await hmacHex(secret, 'idempotency-body', JSON.stringify(input.body ?? null));
      if (idemId) {
        const prior = await findIdempotent(this.env.DB, idemId, input.nowMs);
        if (prior) {
          if (prior.request_hash !== bodyHash) throw errors.idempotencyMismatch();
          return { status: prior.status, body: JSON.parse(prior.response_json) as Record<string, unknown>, replayed: true };
        }
      }

      const transcript = str(input.body, 'transcript', { max: MAX_TRANSCRIPT });
      const isChat = rec.sessionMode === 'chat' && Boolean(rec.chat);
      let lessonContext: LessonContext | null = null;
      let source: 'server' | 'client_dev' | 'chat' = 'chat';
      if (isChat) {
        if (!transcript.trim()) throw errors.invalidTurn('transcript is required in chat mode');
      } else {
        const resolved = this.resolveContext(input.body, rec.lessonId);
        lessonContext = resolved.lessonContext;
        source = resolved.source;
      }
      const audioSeconds = Math.max(0, Math.min(MAX_AUDIO_SECONDS, Number((input.body as Record<string, unknown>)?.audioSeconds) || 0));

      if (!(await hasConsent(this.env.DB, rec.parentId, 'ai_tutor', this.config.consentVersion))) {
        await this.endInternal('consent_revoked', input.nowMs, await this.quotaKey(input.nowMs), 0);
        throw errors.consentRequired('ai_tutor');
      }
      if (await budgetExceeded(this.env.DB, this.config.monthlyBudgetUsd, input.nowMs)) throw errors.quotaExhausted(null, 'monthly_budget');

      const key = await this.quotaKey(input.nowMs);
      const before = await this.quotaStub().snapshot(key);
      if (before.remainingSeconds <= 0) {
        await this.endInternal('quota_exhausted', input.nowMs, key, 0);
        throw errors.quotaExhausted(before);
      }
      if (before.usedTurns >= key.turnAllowance) {
        await this.endInternal('daily_turns', input.nowMs, key);
        throw errors.quotaExhausted(before, 'daily_turns');
      }
      const gap = this.gapSeconds(rec.lastEventAt, input.nowMs);

      const responseMaxWords = isChat ? clampResponseWords((input.body as Record<string, unknown>)?.responseMaxWords, rec.chat!.responseMaxWords) : 0;
      const produced = isChat
        ? await this.produceChatTurn({ transcript, responseMaxWords })
        : await this.produceTurn({ transcript, lessonId: rec.lessonId, lessonContext: lessonContext! });

      const charged = await this.quotaStub().charge(key, gap, this.config.turnCapSeconds);
      const q = await this.quotaStub().countTurn(key);
      const endAtBoundary = q.remainingSeconds <= 0 || q.usedTurns >= key.turnAllowance || lessonContext?.lessonAction === 'end_session';
      rec.turnCount += 1;
      rec.secondsUsed += Math.max(0, Math.min(gap, this.config.turnCapSeconds));
      rec.lastEventAt = input.nowMs;
      await this.save();

      const cost = estimateCostMicro({ llmInputTokens: produced.usage.llmInputTokens, llmOutputTokens: produced.usage.llmOutputTokens, cachedInputTokens: produced.usage.cachedInputTokens }, { model: this.config.model, realtimeModel: this.config.realtimeModel });
      await recordUsage(this.env.DB, { sessionId: rec.sessionId, kind: 'turn', tokensIn: produced.usage.llmInputTokens, tokensOut: produced.usage.llmOutputTokens, audioSeconds, costUsdMicro: cost.costUsdMicro, now: input.nowMs });
      await updateSessionProgress(this.env.DB, rec.sessionId, rec.secondsUsed, rec.turnCount);

      const body: Record<string, unknown> = {
        turn: produced.turn,
        quota: { ...charged, usedTurns: q.usedTurns },
        endAtBoundary,
        turnIndex: rec.turnCount,
        chargedSeconds: Math.round(gap * 10) / 10,
        provider: produced.provider,
        cached: false,
        fallback: produced.fallback,
        contextSource: source,
        usage: { sttSeconds: 0, llmInputTokens: produced.usage.llmInputTokens, llmOutputTokens: produced.usage.llmOutputTokens, ttsChars: produced.turn.speech.length, latencyMs: produced.latencyMs, costUsd: cost.costUsdMicro / 1e6 },
      };
      if (isChat) {
        body.mode = 'chat';
        body.chat = { responseMaxWords, historyTurns: Math.floor(rec.chat!.history.length / 2), redirected: produced.redirected ?? null, capped: Boolean(produced.capped) };
      }
      if (idemId) {
        const json = JSON.stringify(body);
        await storeIdempotent(this.env.DB, { key: idemId, sessionId: rec.sessionId, requestHash: bodyHash, responseHash: await sha256Hex(json), status: 200, responseJson: json, now: input.nowMs });
      }
      if (endAtBoundary && lessonContext?.lessonAction === 'end_session') await this.endInternal('lesson_end', input.nowMs, key, 0);
      else await this.scheduleAlarm();
      return { status: 200, body, replayed: false };
    });
  }

  async end(input: { approvalHash: string; reason: string; nowMs: number }): Promise<DoResult<{ sessionId: string; endedAt: string; quota: QuotaState; usage: Awaited<ReturnType<typeof sessionTotals>> }>> {
    return this.wrap(async () => {
      await this.load();
      const rec = this.requireOwner(input.approvalHash);
      const key = await this.quotaKey(input.nowMs);
      const quota = await this.endInternal(input.reason || 'client_end', input.nowMs, key);
      return { sessionId: rec.sessionId, endedAt: new Date(rec.endedAt!).toISOString(), quota, usage: await sessionTotals(this.env.DB, rec.sessionId) };
    });
  }

  /** Parent Corner "stop now" / retention: ends without the approval token (the route checks the parent). */
  async parentStop(input: { parentId: string; nowMs: number }): Promise<DoResult<{ ended: boolean }>> {
    return this.wrap(async () => {
      const rec = await this.load();
      if (!rec) throw errors.notFound('Session not found.');
      if (rec.parentId !== input.parentId) throw errors.notApproved();
      if (rec.endedAt) return { ended: false };
      await this.endInternal('parent_stop', input.nowMs, await this.quotaKey(input.nowMs));
      return { ended: true };
    });
  }

  /** Pre-check for the realtime route: owner, open, quota; settles any running realtime clock. */
  async realtimePrecheck(input: { approvalHash: string; nowMs: number }): Promise<DoResult<{ quota: QuotaState; lessonId: string; childId: string; parentId: string }>> {
    return this.wrap(async () => {
      await this.load();
      const rec = this.requireOwner(input.approvalHash);
      if (rec.endedAt) throw errors.sessionEnded();
      const key = await this.quotaKey(input.nowMs);
      await this.settleRealtime(input.nowMs, key);
      await this.save();
      if (await budgetExceeded(this.env.DB, this.config.monthlyBudgetUsd, input.nowMs)) throw errors.quotaExhausted(null, 'monthly_budget');
      const q = await this.quotaStub().snapshot(key);
      if (q.remainingSeconds <= 0) throw errors.quotaExhausted(q);
      if (q.usedTurns >= key.turnAllowance) throw errors.quotaExhausted(q, 'daily_turns');
      return { quota: q, lessonId: rec.lessonId, childId: rec.childId, parentId: rec.parentId };
    });
  }

  /** After the Worker minted an ephemeral token: bind it to the session and count the mint as a provider call. */
  async attachRealtime(input: { approvalHash: string; nowMs: number; expiresAt: number; model: string }): Promise<DoResult<QuotaState>> {
    return this.wrap(async () => {
      await this.load();
      const rec = this.requireOwner(input.approvalHash);
      if (rec.endedAt) throw errors.sessionEnded();
      const key = await this.quotaKey(input.nowMs);
      await this.settleRealtime(input.nowMs, key);
      rec.realtime = { mintedAt: input.nowMs, expiresAt: input.expiresAt, model: input.model, mints: (rec.realtime?.mints ?? 0) + 1 };
      rec.mode = 'realtime';
      rec.lastEventAt = input.nowMs;
      const q = await this.quotaStub().countTurn(key);
      await this.save();
      await recordUsage(this.env.DB, { sessionId: rec.sessionId, kind: 'realtime_mint', tokensIn: 0, tokensOut: 0, audioSeconds: 0, costUsdMicro: 0, now: input.nowMs });
      await updateSessionProgress(this.env.DB, rec.sessionId, rec.secondsUsed, rec.turnCount, 'realtime');
      await this.scheduleAlarm();
      return q;
    });
  }

  /** Realtime usage reports: cost accounting only, never the quota authority. */
  async usageReport(input: { approvalHash: string; nowMs: number; body: unknown }): Promise<DoResult<Record<string, unknown>>> {
    return this.wrap(async () => {
      await this.load();
      const rec = this.requireOwner(input.approvalHash);
      if (rec.endedAt) throw errors.sessionEnded();
      if (!rec.realtime) throw errors.badRequest('usage reports are only accepted for realtime sessions');
      const sr = this.limiter.hit('turns', this.config.sessionTurnsPerMinute, input.nowMs);
      if (!sr.allowed) throw errors.rateLimited(sr.retryAfterSeconds);
      const b = isObject(input.body) ? input.body : {};
      if (b.usedSeconds !== undefined || b.remainingSeconds !== undefined || b.quota !== undefined) {
        throw errors.badRequest('client timers are not accepted as quota authority; report provider usage events only');
      }
      const key = await this.quotaKey(input.nowMs);
      const before = await this.quotaStub().snapshot(key);
      if (before.usedTurns >= key.turnAllowance) {
        await this.endInternal('daily_turns', input.nowMs, key);
        throw errors.quotaExhausted(before, 'daily_turns');
      }
      await this.settleRealtime(input.nowMs, key);
      const q = await this.quotaStub().countTurn(key);
      rec.turnCount += 1;
      rec.lastEventAt = Math.max(rec.lastEventAt, input.nowMs);
      await this.save();
      const tok = (v: unknown) => Math.max(0, Math.min(5_000_000, Math.round(Number(v) || 0)));
      const sec = (v: unknown) => Math.max(0, Math.min(7200, Number(v) || 0));
      const cost = estimateCostMicro({
        realtimeAudioInputTokens: tok(b.inputAudioTokens), realtimeCachedAudioInputTokens: tok(b.cachedInputAudioTokens), realtimeAudioOutputTokens: tok(b.outputAudioTokens),
        realtimeTextInputTokens: tok(b.inputTextTokens), realtimeCachedTextInputTokens: tok(b.cachedInputTextTokens), realtimeTextOutputTokens: tok(b.outputTextTokens),
      }, { model: this.config.model, realtimeModel: rec.realtime.model });
      await recordUsage(this.env.DB, { sessionId: rec.sessionId, kind: 'realtime_usage', tokensIn: tok(b.inputAudioTokens) + tok(b.inputTextTokens), tokensOut: tok(b.outputAudioTokens) + tok(b.outputTextTokens), audioSeconds: sec(b.inputAudioSeconds) + sec(b.outputAudioSeconds), costUsdMicro: cost.costUsdMicro, now: input.nowMs });
      await updateSessionProgress(this.env.DB, rec.sessionId, rec.secondsUsed, rec.turnCount);
      const endAtBoundary = q.remainingSeconds <= 0 || q.usedTurns >= key.turnAllowance || rec.realtime.expiresAt <= input.nowMs;
      await this.scheduleAlarm();
      return { sessionId: rec.sessionId, recorded: { turnIndex: rec.turnCount, costUsd: cost.costUsdMicro / 1e6, priceMissing: cost.priceMissing }, quota: q, endAtBoundary, tokenExpiresAt: new Date(rec.realtime.expiresAt).toISOString() };
    });
  }

  /**
   * The countdown. Ends the session when the token expired, the child went
   * idle, or the day's allowance is gone. Called by the alarm with the real
   * clock and by tests with an explicit one; a clock behind the last event
   * is ignored (never lets a skewed alarm end a live lesson early).
   */
  async tick(nowMs: number): Promise<{ ended: boolean; reason: string | null }> {
    return this.serialize(async () => {
      const rec = await this.load();
      if (!rec || rec.endedAt) return { ended: false, reason: rec?.endReason ?? null };
      if (nowMs < rec.lastEventAt) {
        await this.scheduleAlarm();
        return { ended: false, reason: null };
      }
      const key = await this.quotaKey(nowMs);
      if (rec.realtime && nowMs >= rec.realtime.expiresAt) {
        await this.endInternal('token_expired', nowMs, key);
        return { ended: true, reason: 'token_expired' };
      }
      if (nowMs - rec.lastEventAt >= this.config.sessionIdleSeconds * 1000) {
        await this.endInternal('idle', nowMs, key);
        return { ended: true, reason: 'idle' };
      }
      if (rec.realtime) await this.settleRealtime(nowMs, key);
      const q = await this.quotaStub().snapshot(key);
      if (q.remainingSeconds <= 0) {
        await this.endInternal('quota_exhausted', nowMs, key, 0);
        return { ended: true, reason: 'quota_exhausted' };
      }
      await this.save();
      await this.scheduleAlarm();
      return { ended: false, reason: null };
    });
  }

  async alarm(): Promise<void> {
    await this.tick(Date.now());
  }

  // ---------------------------------------------------------------- helpers
  private resolveContext(body: unknown, lessonId: string): { lessonContext: LessonContext; source: 'server' | 'client_dev' } {
    const lc = (body as Record<string, unknown> | null | undefined)?.lessonContext;
    if (!isObject(lc)) throw errors.invalidTurn('lessonContext is required');
    if (!OUTCOMES.includes(lc.outcome as Outcome)) throw errors.invalidTurn('lessonContext.outcome must be correct, incorrect or unclear');
    const stepId = str(lc, 'stepId', { required: true, max: 80, re: ID_RE });
    const lesson = LESSONS.get(lessonId);
    if (lesson) {
      const resolved = resolveLessonContext(lesson, { stepId, outcome: lc.outcome as Outcome, matched: str(lc, 'matched', { max: 80 }), lessonAction: str(lc, 'lessonAction', { max: 32 }) });
      if (!resolved) throw errors.invalidTurn('lessonContext.stepId is not a step of this lesson');
      if (resolved.visualAssetId && !ASSET_ALLOWLIST.ids.includes(resolved.visualAssetId)) resolved.visualAssetId = '';
      return { lessonContext: resolved, source: 'server' };
    }
    if (!this.rec?.devMode) throw errors.unknownLesson();
    const expected = lc.expectedAnswers === undefined ? [] : lc.expectedAnswers;
    if (!Array.isArray(expected) || expected.length > 20 || expected.some((e) => typeof e !== 'string' || e.length > 80)) {
      throw errors.invalidTurn('lessonContext.expectedAnswers must be a short array of strings');
    }
    const ctx: LessonContext = {
      stepId,
      outcome: lc.outcome as Outcome,
      expectedAnswers: expected as string[],
      hint: str(lc, 'hint', { max: MAX_CONTEXT_TEXT }),
      nextQuestionText: str(lc, 'nextQuestionText', { max: MAX_CONTEXT_TEXT }),
      visualAssetId: str(lc, 'visualAssetId', { max: 64 }),
      matched: str(lc, 'matched', { max: 80 }),
      lessonAction: str(lc, 'lessonAction', { max: 32 }),
    };
    if (ctx.visualAssetId && !ASSET_ALLOWLIST.ids.includes(ctx.visualAssetId)) ctx.visualAssetId = '';
    return { lessonContext: ctx, source: 'client_dev' };
  }

  /** Provider with timeout; on any failure the deterministic mock answers. Always a VALID turn. */
  private async produceTurn(input: { transcript: string; lessonId: string; lessonContext: LessonContext }): Promise<ProducedTurn> {
    const primary = this.provider();
    const t0 = Date.now();
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(new Error('provider_timeout')), this.config.providerTimeoutMs);
    let fallback: string | null = null;
    let result: { turn: TutorTurn; usage: TurnUsage } | null = null;
    try {
      const r = await primary.generateTurn({ ...input, signal: ac.signal });
      const v = validateTurn(r.turn, { allowlist: ASSET_ALLOWLIST.ids });
      if (!v.ok) {
        fallback = `invalid_turn:${v.reasons.slice(0, 3).join(',')}`;
        console.log(`[tutor-session] provider ${primary.name} produced an invalid turn: ${v.reasons.join(',')}`);
      } else result = { turn: v.turn, usage: r.usage };
    } catch (err) {
      fallback = ac.signal.aborted ? String((ac.signal.reason as Error | undefined)?.message ?? 'aborted') : `provider_error:${(err as { status?: number })?.status ?? (err instanceof Error ? err.message : 'unknown')}`;
      console.log(`[tutor-session] provider ${primary.name} failed: ${fallback}`);
    } finally {
      clearTimeout(timer);
    }
    const latencyMs = Date.now() - t0;
    if (result) return { ...result, provider: primary.name, fallback: null, latencyMs };
    if (primary === this.mock || primary.name === 'mock') throw errors.providerUnavailable();
    const m = await this.mock.generateTurn({ ...input, signal: new AbortController().signal });
    const mv = validateTurn(m.turn, { allowlist: ASSET_ALLOWLIST.ids });
    return { turn: mv.ok ? mv.turn : fallbackTurn(), usage: m.usage, provider: 'mock', fallback, latencyMs };
  }

  /**
   * Free chat. The child's words are checked against the redirect list before
   * any model sees them; the reply (from the OpenAI provider when a key is
   * set, else the mock) goes through gateChatTurn; any failure or invalid
   * reply is answered by the deterministic mock chat, gated the same way. The
   * rolling window keeps the last K exchanges in DO storage only. Nothing
   * here logs a transcript or a reply.
   */
  private async produceChatTurn(input: { transcript: string; responseMaxWords: number }): Promise<ProducedTurn> {
    const rec = this.rec!;
    const chat = rec.chat!;
    const t0 = Date.now();
    const allowlist = ASSET_ALLOWLIST.ids;
    const remember = async (reply: ChatTurn) => {
      chat.history.push({ role: 'child', text: input.transcript }, { role: 'tutor', text: reply.speech });
      const keep = Math.max(0, chat.contextTurns) * 2;
      if (chat.history.length > keep) chat.history = chat.history.slice(chat.history.length - keep);
    };
    const childCheck = checkChatText(input.transcript);
    if (childCheck.flagged) {
      const turn = toChatTurn(redirectTurn(childCheck.category));
      await remember(turn);
      return { turn, usage: { llmInputTokens: 0, llmOutputTokens: 0 }, provider: 'safety', fallback: `redirect:child:${childCheck.category}`, latencyMs: Date.now() - t0, redirected: childCheck.category, capped: false };
    }
    const primaryTurns = this.provider();
    const primary = chatProviderOf(primaryTurns) ?? this.mockChat;
    const window = chat.history.slice(-Math.max(0, chat.contextTurns) * 2);
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(new Error('provider_timeout')), this.config.providerTimeoutMs);
    let fallback: string | null = null;
    let usage: TurnUsage = { llmInputTokens: 0, llmOutputTokens: 0 };
    let gated: ReturnType<typeof gateChatTurn> | null = null;
    try {
      const r = await primary.generateChatTurn({ transcript: input.transcript, history: window, responseMaxWords: input.responseMaxWords, signal: ac.signal });
      usage = r.usage;
      const g = gateChatTurn(r.turn, { responseMaxWords: input.responseMaxWords, allowlist });
      if (g.ok || g.redirected) gated = g;
      else {
        fallback = `invalid_turn:${g.reasons.slice(0, 3).join(',')}`;
        console.log(`[tutor-session] chat provider ${primary.name} produced an invalid turn: ${g.reasons.join(',')}`);
      }
    } catch (err) {
      fallback = ac.signal.aborted ? String((ac.signal.reason as Error | undefined)?.message ?? 'aborted') : `provider_error:${(err as { status?: number })?.status ?? (err instanceof Error ? err.message : 'unknown')}`;
      console.log(`[tutor-session] chat provider ${primary.name} failed: ${fallback}`);
    } finally {
      clearTimeout(timer);
    }
    let provider = primary.name;
    if (!gated) {
      provider = 'mock';
      const m = await this.mockChat.generateChatTurn({ transcript: input.transcript, history: window, responseMaxWords: input.responseMaxWords, signal: new AbortController().signal });
      gated = gateChatTurn(m.turn, { responseMaxWords: input.responseMaxWords, allowlist });
      if (!gated.ok && !gated.redirected) gated = { ...gated, turn: toChatTurn(redirectTurn(null)) };
    } else if (gated.redirected) {
      provider = 'safety';
      fallback = `redirect:reply:${gated.redirected}`;
    }
    await remember(gated.turn);
    return { turn: gated.turn, usage, provider, fallback, latencyMs: Date.now() - t0, redirected: gated.redirected, capped: gated.capped };
  }
}

interface ProducedTurn {
  turn: TutorTurn | ChatTurn;
  usage: TurnUsage;
  provider: string;
  fallback: string | null;
  latencyMs: number;
  redirected?: string | null;
  capped?: boolean;
}
