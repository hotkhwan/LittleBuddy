// Response cache for instructional turns. Key: (lessonId, stepId, outcome,
// hasHint). The reply to "correct on step 3 of lesson X" is the same teaching
// beat for every child, so one provider call can serve everyone. Transcripts
// are never part of the key and never stored here.

/**
 * @param {{now: () => number, ttlSeconds: number, maxEntries: number}} opts
 */
export function createTurnCache({ now, ttlSeconds, maxEntries }) {
  /** @type {Map<string, {turn: any, expiresAt: number}>} */
  const map = new Map();
  let hits = 0;
  let misses = 0;

  /**
   * @param {{lessonId: string, stepId: string, outcome: string, hint?: string}} ctx
   */
  function key(ctx) {
    return `${ctx.lessonId}|${ctx.stepId}|${ctx.outcome}|${ctx.hint ? 'h' : '-'}`;
  }

  /** @param {string} k */
  function get(k) {
    const e = map.get(k);
    if (!e) {
      misses += 1;
      return null;
    }
    if (e.expiresAt <= now()) {
      map.delete(k);
      misses += 1;
      return null;
    }
    hits += 1;
    return structuredClone(e.turn);
  }

  /** @param {string} k @param {any} turn */
  function set(k, turn) {
    if (ttlSeconds <= 0) return;
    if (map.size >= maxEntries) {
      const oldest = map.keys().next().value;
      if (oldest !== undefined) map.delete(oldest);
    }
    map.set(k, { turn: structuredClone(turn), expiresAt: now() + ttlSeconds * 1000 });
  }

  return { key, get, set, stats: () => ({ hits, misses, size: map.size }), clear: () => map.clear() };
}
