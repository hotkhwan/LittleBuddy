// Server-side tutor quota. UTC-day window keyed on the approved identity
// (clientId bound to a parent-approval token). Usage is counted from the
// server's own timestamps: session start -> each turn -> end. Each gap is
// capped at `turnCapSeconds` so a client that goes idle or hangs cannot burn
// hours. Allowances are finite for every entitlement; there is no "unlimited".

const DAY_MS = 24 * 3600 * 1000;

/** @param {number} nowMs */
export function utcDayKey(nowMs) {
  return new Date(nowMs).toISOString().slice(0, 10);
}

/** @param {number} nowMs */
export function nextUtcMidnightIso(nowMs) {
  const d = new Date(nowMs);
  const next = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) + DAY_MS;
  return new Date(next).toISOString();
}

/**
 * @param {{store: ReturnType<import('./store.js').createStore>, config: import('./config.js').Config, now: () => number}} deps
 */
export function createQuota({ store, config, now }) {
  /** @param {'free'|'family_club'} entitlement */
  function allowanceFor(entitlement) {
    const seconds = entitlement === 'family_club' ? config.familyClubDailySeconds : config.freeDailySeconds;
    // Defensive: never unlimited, never negative.
    return Math.max(0, Math.min(seconds, 24 * 3600));
  }

  /** @param {'free'|'family_club'} entitlement */
  function turnAllowanceFor(entitlement) {
    return entitlement === 'family_club' ? config.familyClubDailyTurns : config.freeDailyTurns;
  }

  /** @param {string} userKey */
  function record(userKey) {
    const day = utcDayKey(now());
    const existing = store.usage.get(userKey);
    if (existing && existing.dayKey === day) return { turns: 0, ...existing };
    return { dayKey: day, usedSeconds: 0, turns: 0 };
  }

  /**
   * @param {string} userKey
   * @param {'free'|'family_club'} entitlement
   */
  function state(userKey, entitlement) {
    const rec = record(userKey);
    const allowance = allowanceFor(entitlement);
    const used = Math.min(rec.usedSeconds, allowance);
    return {
      entitlement,
      dailyAllowanceSeconds: allowance,
      usedSeconds: round1(used),
      remainingSeconds: round1(Math.max(0, allowance - used)),
      resetAtUtc: nextUtcMidnightIso(now()),
      dailyTurnAllowance: turnAllowanceFor(entitlement),
      usedTurns: rec.turns,
    };
  }

  /**
   * Count one served turn against the day (finding H4: cost is per call, not
   * per second). Returns true when the cap is already reached BEFORE this turn.
   * @param {string} userKey
   * @param {'free'|'family_club'} entitlement
   */
  function turnCapReached(userKey, entitlement) {
    return record(userKey).turns >= turnAllowanceFor(entitlement);
  }

  /** @param {string} userKey */
  function countTurn(userKey) {
    const rec = record(userKey);
    rec.turns += 1;
    store.usage.set(userKey, rec);
    return rec.turns;
  }

  /**
   * Charge elapsed seconds (already capped by the caller or here) to the day.
   * Returns the new state.
   * @param {string} userKey
   * @param {'free'|'family_club'} entitlement
   * @param {number} seconds
   */
  function charge(userKey, entitlement, seconds) {
    const rec = record(userKey);
    const capped = Math.max(0, Math.min(seconds, config.turnCapSeconds));
    rec.usedSeconds = rec.usedSeconds + capped;
    store.usage.set(userKey, rec);
    return state(userKey, entitlement);
  }

  /**
   * Charge elapsed seconds WITHOUT the per-turn cap (realtime sessions, whose
   * bound is the ephemeral token expiry instead). Never charges past the
   * allowance plus `graceSeconds`.
   * @param {string} userKey
   * @param {'free'|'family_club'} entitlement
   * @param {number} seconds
   * @param {number} graceSeconds
   */
  function chargeUncapped(userKey, entitlement, seconds, graceSeconds) {
    const rec = record(userKey);
    const ceiling = allowanceFor(entitlement) + Math.max(0, graceSeconds);
    rec.usedSeconds = Math.min(ceiling, rec.usedSeconds + Math.max(0, seconds));
    store.usage.set(userKey, rec);
    return state(userKey, entitlement);
  }

  /**
   * Seconds to charge for the gap between two server timestamps.
   * @param {number} fromMs
   * @param {number} toMs
   */
  function gapSeconds(fromMs, toMs) {
    const raw = Math.max(0, (toMs - fromMs) / 1000);
    return Math.min(raw, config.turnCapSeconds);
  }

  /**
   * @param {string} userKey
   * @param {'free'|'family_club'} entitlement
   */
  function isExhausted(userKey, entitlement) {
    return state(userKey, entitlement).remainingSeconds <= 0;
  }

  return { allowanceFor, turnAllowanceFor, state, charge, chargeUncapped, gapSeconds, isExhausted, turnCapReached, countTurn };
}

/** @param {number} n */
function round1(n) {
  return Math.round(n * 10) / 10;
}
