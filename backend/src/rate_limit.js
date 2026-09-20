// Fixed-window rate limiter, in memory (per process). Keys: "ip:<addr>" and
// "session:<id>". Cheap and predictable; good enough for a single instance.

/**
 * @param {{now: () => number, windowMs?: number}} deps
 */
export function createRateLimiter({ now, windowMs = 60_000 }) {
  /** @type {Map<string, {windowStart: number, count: number}>} */
  const buckets = new Map();

  /**
   * @param {string} key
   * @param {number} limit
   * @returns {{allowed: boolean, remaining: number, retryAfterSeconds: number}}
   */
  function hit(key, limit) {
    const t = now();
    let b = buckets.get(key);
    if (!b || t - b.windowStart >= windowMs) {
      b = { windowStart: t, count: 0 };
      buckets.set(key, b);
    }
    b.count += 1;
    const allowed = b.count <= limit;
    const retryAfterSeconds = Math.max(1, Math.ceil((b.windowStart + windowMs - t) / 1000));
    if (buckets.size > 10_000) sweep(t);
    return { allowed, remaining: Math.max(0, limit - b.count), retryAfterSeconds };
  }

  /** @param {number} t */
  function sweep(t) {
    for (const [k, b] of buckets) if (t - b.windowStart >= windowMs) buckets.delete(k);
  }

  return { hit, reset: () => buckets.clear() };
}
