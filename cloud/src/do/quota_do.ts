// QuotaDO: ONE object per child, the authority for "how many seconds and
// turns did this child use today (UTC)". Chosen over a D1 read-modify-write
// because D1 has no interactive transactions: two devices (or two retries)
// charging the same child at the same moment would race past the allowance,
// and the "last turn lands exactly on 300 s" rule needs check-and-charge to
// be one step. A Durable Object executes one request at a time, its storage
// is transactional, and it is the natural place for a child's counter to
// live no matter how many Worker isolates or sessions touch it. The D1
// table daily_quota is a reporting mirror (dashboards, retention, deletion),
// written after every change.
import { DurableObject } from 'cloudflare:workers';
import type { Entitlement, Env } from '../env';
import type { QuotaState } from '../tutor/types';
import { nextUtcMidnightIso, nextUtcMonthIso, round1, utcDayKey, utcMonthKey } from '../util/time';

interface QuotaRecord { childId: string; day: string; usedSeconds: number; turns: number }

interface LiveQuotaRecord {
  accountId: string;
  month: string;
  usedSeconds: number;
  reservations: Record<string, number>;
}

export interface LiveQuotaKey {
  accountId: string;
  nowMs: number;
  allowanceSeconds: number;
  sessionMaxSeconds: number;
}

export interface LiveQuotaState {
  allowanceSeconds: number;
  usedSeconds: number;
  reservedSeconds: number;
  remainingSeconds: number;
  resetAt: string;
}

export interface QuotaKey { childId: string; nowMs: number; entitlement: Entitlement; allowanceSeconds: number; turnAllowance: number }

export class QuotaDO extends DurableObject<Env> {
  private rec: QuotaRecord | null = null;
  private loaded = false;
  private live: LiveQuotaRecord | null = null;
  private liveLoaded = false;

  private async load(childId: string, nowMs: number): Promise<QuotaRecord> {
    if (!this.loaded) {
      this.rec = (await this.ctx.storage.get<QuotaRecord>('rec')) ?? null;
      this.loaded = true;
    }
    const day = utcDayKey(nowMs);
    if (!this.rec || this.rec.day !== day || this.rec.childId !== childId) {
      this.rec = { childId, day, usedSeconds: 0, turns: 0 };
      await this.ctx.storage.put('rec', this.rec);
    }
    return this.rec;
  }

  private async loadLive(key: LiveQuotaKey): Promise<LiveQuotaRecord> {
    if (!this.liveLoaded) {
      this.live = (await this.ctx.storage.get<LiveQuotaRecord>('live')) ?? null;
      this.liveLoaded = true;
    }
    const month = utcMonthKey(key.nowMs);
    if (!this.live || this.live.accountId !== key.accountId || this.live.month !== month) {
      this.live = { accountId: key.accountId, month, usedSeconds: 0, reservations: {} };
      await this.ctx.storage.put('live', this.live);
    }
    return this.live;
  }

  private liveState(rec: LiveQuotaRecord, key: LiveQuotaKey): LiveQuotaState {
    const allowance = Math.max(0, Math.floor(key.allowanceSeconds));
    const reserved = Object.values(rec.reservations).reduce((sum, value) => sum + value, 0);
    return {
      allowanceSeconds: allowance,
      usedSeconds: Math.min(rec.usedSeconds, allowance),
      reservedSeconds: reserved,
      remainingSeconds: Math.max(0, allowance - rec.usedSeconds - reserved),
      resetAt: nextUtcMonthIso(key.nowMs),
    };
  }

  async liveSnapshot(key: LiveQuotaKey): Promise<LiveQuotaState> {
    return this.liveState(await this.loadLive(key), key);
  }

  /** Reserves pooled monthly Live time before credentials are minted. */
  async reserveLive(key: LiveQuotaKey, sessionId: string, requestedSeconds: number): Promise<LiveQuotaState> {
    const rec = await this.loadLive(key);
    if (!rec.reservations[sessionId]) {
      const state = this.liveState(rec, key);
      const request = Math.max(0, Math.min(Math.floor(requestedSeconds), Math.floor(key.sessionMaxSeconds)));
      if (request <= 0 || request > state.remainingSeconds) return state;
      rec.reservations[sessionId] = request;
      await this.ctx.storage.put('live', rec);
    }
    return this.liveState(rec, key);
  }

  /** Finalization is idempotent and charges no more than the reserved amount. */
  async finalizeLive(key: LiveQuotaKey, sessionId: string, actualSeconds: number): Promise<LiveQuotaState> {
    const rec = await this.loadLive(key);
    const reserved = rec.reservations[sessionId];
    if (reserved === undefined) return this.liveState(rec, key);
    rec.usedSeconds += Math.max(0, Math.min(Math.floor(actualSeconds), reserved));
    delete rec.reservations[sessionId];
    await this.ctx.storage.put('live', rec);
    await this.env.DB.prepare(`INSERT INTO ai_usage_monthly
      (account_id, usage_month, live_used_seconds, live_allowance_seconds, reset_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(account_id, usage_month) DO UPDATE SET
        live_used_seconds = excluded.live_used_seconds,
        live_allowance_seconds = excluded.live_allowance_seconds,
        reset_at = excluded.reset_at,
        updated_at = excluded.updated_at`)
      .bind(rec.accountId, rec.month, rec.usedSeconds, Math.max(0, Math.floor(key.allowanceSeconds)), Date.parse(nextUtcMonthIso(key.nowMs)), key.nowMs).run();
    return this.liveState(rec, key);
  }

  private state(rec: QuotaRecord, key: QuotaKey): QuotaState {
    const allowance = Math.max(0, Math.min(key.allowanceSeconds, 86_400));
    const used = Math.min(rec.usedSeconds, allowance);
    return {
      entitlement: key.entitlement,
      dailyAllowanceSeconds: allowance,
      usedSeconds: round1(used),
      remainingSeconds: round1(Math.max(0, allowance - used)),
      resetAtUtc: nextUtcMidnightIso(key.nowMs),
      dailyTurnAllowance: key.turnAllowance,
      usedTurns: rec.turns,
    };
  }

  private async persist(rec: QuotaRecord, key: QuotaKey): Promise<void> {
    await this.ctx.storage.put('rec', rec);
    await this.env.DB.prepare(`INSERT INTO daily_quota (child_id, day_utc, seconds_used, turns_used, allowance_seconds, updated_at) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(child_id, day_utc) DO UPDATE SET seconds_used = excluded.seconds_used, turns_used = excluded.turns_used, allowance_seconds = excluded.allowance_seconds, updated_at = excluded.updated_at`)
      .bind(rec.childId, rec.day, rec.usedSeconds, rec.turns, key.allowanceSeconds, key.nowMs).run();
  }

  async snapshot(key: QuotaKey): Promise<QuotaState> {
    return this.state(await this.load(key.childId, key.nowMs), key);
  }

  /** Charge `seconds`, capped at `capSeconds` (the per-turn cap). */
  async charge(key: QuotaKey, seconds: number, capSeconds: number): Promise<QuotaState> {
    const rec = await this.load(key.childId, key.nowMs);
    rec.usedSeconds += Math.max(0, Math.min(seconds, capSeconds));
    await this.persist(rec, key);
    return this.state(rec, key);
  }

  /** Realtime: no per-turn cap (bounded by the token expiry) but never past allowance + grace. */
  async chargeUncapped(key: QuotaKey, seconds: number, graceSeconds: number): Promise<QuotaState> {
    const rec = await this.load(key.childId, key.nowMs);
    const ceiling = Math.max(0, Math.min(key.allowanceSeconds, 86_400)) + Math.max(0, graceSeconds);
    rec.usedSeconds = Math.min(ceiling, rec.usedSeconds + Math.max(0, seconds));
    await this.persist(rec, key);
    return this.state(rec, key);
  }

  async countTurn(key: QuotaKey): Promise<QuotaState> {
    const rec = await this.load(key.childId, key.nowMs);
    rec.turns += 1;
    await this.persist(rec, key);
    return this.state(rec, key);
  }

  async reset(): Promise<void> {
    this.rec = null;
    this.loaded = true;
    this.live = null;
    this.liveLoaded = true;
    await this.ctx.storage.deleteAll();
  }
}
