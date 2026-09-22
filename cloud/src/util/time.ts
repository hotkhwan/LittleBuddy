const DAY_MS = 24 * 3600 * 1000;

export function utcDayKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}

export function utcMonthStartMs(nowMs: number): number {
  const d = new Date(nowMs);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1);
}

export function utcMonthKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 7);
}

export function nextUtcMonthIso(nowMs: number): string {
  const d = new Date(nowMs);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1)).toISOString();
}

export function nextUtcMidnightIso(nowMs: number): string {
  const d = new Date(nowMs);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) + DAY_MS).toISOString();
}

export function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

export const IDEMPOTENCY_TTL_MS = 24 * 3600 * 1000;
