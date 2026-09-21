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
import { nextUtcMidnightIso, round1, utcDayKey } from '../util/time';

interface QuotaRecord { childId: string; day: string; usedSeconds: number; turns: number }

export interface QuotaKey { childId: string; nowMs: number; entitlement: Entitlement; allowanceSeconds: number; turnAllowance: number }

export class QuotaDO extends DurableObject<Env> {
  private rec: QuotaRecord | null = null;
  private loaded = false;

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
    await this.ctx.storage.deleteAll();
  }
}
