// Fixed-window limiter in isolate memory. Honest limit: a Worker runs in many
// isolates, so the per-IP cap is per isolate (still bounds a single abusive
// connection). The per-session cap lives inside TutorSessionDO, which IS a
// single place per session, so that one is exact.
export interface Bucket { windowStart: number; count: number }

export class FixedWindowLimiter {
  private readonly buckets = new Map<string, Bucket>();
  constructor(private readonly windowMs = 60_000) {}

  hit(key: string, limit: number, now: number): { allowed: boolean; retryAfterSeconds: number } {
    let b = this.buckets.get(key);
    if (!b || now - b.windowStart >= this.windowMs) {
      b = { windowStart: now, count: 0 };
      this.buckets.set(key, b);
    }
    b.count += 1;
    if (this.buckets.size > 10_000) this.sweep(now);
    return { allowed: b.count <= limit, retryAfterSeconds: Math.max(1, Math.ceil((b.windowStart + this.windowMs - now) / 1000)) };
  }

  private sweep(now: number): void {
    for (const [k, b] of this.buckets) if (now - b.windowStart >= this.windowMs) this.buckets.delete(k);
  }

  reset(): void {
    this.buckets.clear();
  }
}
