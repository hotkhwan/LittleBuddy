// Retention (security finding M4): nothing about a child's device is kept
// longer than needed. Sessions, their per-turn usage rows and quota-day rows
// older than RETENTION_DAYS are purged on start and hourly; idempotency rows
// expire after 24 h; a parent can delete a client's learning history on demand.

export const IDEMPOTENCY_TTL_MS = 24 * 3600 * 1000;

/**
 * @param {{store: ReturnType<import('./store.js').createStore>, now: () => number, retentionDays: number}} deps
 */
export function createRetention({ store, now, retentionDays }) {
  const retentionMs = Math.max(1, retentionDays) * 24 * 3600 * 1000;

  /** Delete everything older than the retention window. Returns counts. */
  function purge() {
    const t = now();
    const counts = { sessions: 0, turns: 0, usage: 0, idempotency: 0 };
    /** @type {Set<string>} */
    const deadSessions = new Set();
    for (const [id, s] of store.sessions.entries()) {
      const last = s.endedAt ?? s.lastEventAt ?? s.startedAt ?? 0;
      if (t - last > retentionMs) {
        deadSessions.add(id);
        store.sessions.delete(id);
        counts.sessions += 1;
      }
    }
    for (const [key, turn] of store.turns.entries()) {
      if (deadSessions.has(turn.sessionId) || t - Date.parse(turn.at) > retentionMs) {
        store.turns.delete(key);
        counts.turns += 1;
      }
    }
    for (const [key, rec] of store.usage.entries()) {
      if (t - Date.parse(`${rec.dayKey}T00:00:00Z`) > retentionMs) {
        store.usage.delete(key);
        counts.usage += 1;
      }
    }
    for (const [key, rec] of store.idempotency.entries()) {
      const sessionId = key.split(':')[0];
      if (deadSessions.has(sessionId) || t - (rec.at ?? 0) > IDEMPOTENCY_TTL_MS) {
        store.idempotency.delete(key);
        counts.idempotency += 1;
      }
    }
    return counts;
  }

  /**
   * "Delete learning history" for one client: sessions, their turns and
   * idempotency rows, and quota-day rows. Entitlement and receipts are kept
   * (they are the purchase record, not learning history).
   * @param {string} clientId
   */
  function deleteClient(clientId) {
    const counts = { sessions: 0, turns: 0, usage: 0, idempotency: 0 };
    const sessionIds = new Set();
    for (const [id, s] of store.sessions.entries()) {
      if (s.clientId !== clientId) continue;
      sessionIds.add(id);
      store.sessions.delete(id);
      counts.sessions += 1;
    }
    for (const [key, turn] of store.turns.entries()) {
      if (sessionIds.has(turn.sessionId)) {
        store.turns.delete(key);
        counts.turns += 1;
      }
    }
    for (const [key] of store.idempotency.entries()) {
      if (sessionIds.has(key.split(':')[0])) {
        store.idempotency.delete(key);
        counts.idempotency += 1;
      }
    }
    if (store.usage.delete(clientId)) counts.usage += 1;
    return counts;
  }

  /** Start the hourly job. Returns a stop function. */
  function start(intervalMs = 3600 * 1000) {
    purge();
    const timer = setInterval(purge, intervalMs);
    timer.unref?.();
    return () => clearInterval(timer);
  }

  return { purge, deleteClient, start };
}
