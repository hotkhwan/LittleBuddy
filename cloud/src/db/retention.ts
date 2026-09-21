// Retention purge (scheduled cron + DEV_MODE route). Nothing about a child is
// kept longer than RETENTION_DAYS; idempotency rows go after 24 h.
import { IDEMPOTENCY_TTL_MS } from '../util/time';
import { expireTombstones } from './parents';

export interface PurgeCounts { sessions: number; usageEvents: number; dailyQuota: number; idempotency: number }

export async function purgeExpired(db: D1Database, now: number, retentionDays: number): Promise<PurgeCounts> {
  // Deleted parent accounts keep only a (provider, subject_hash) tombstone for
  // 30 days; the nightly purge drops the ones whose window has passed.
  await expireTombstones(db, now);
  const cutoff = now - Math.max(1, retentionDays) * 24 * 3600 * 1000;
  const cutoffDay = new Date(cutoff).toISOString().slice(0, 10);
  const results = await db.batch([
    db.prepare('DELETE FROM api_idempotency WHERE created_at < ?').bind(now - IDEMPOTENCY_TTL_MS),
    db.prepare('DELETE FROM usage_events WHERE created_at < ?').bind(cutoff),
    db.prepare('DELETE FROM daily_quota WHERE day_utc < ?').bind(cutoffDay),
    db.prepare('DELETE FROM tutor_sessions WHERE COALESCE(ended_at, started_at) < ?').bind(cutoff),
  ]);
  const n = (i: number) => Number(results[i]?.meta?.changes ?? 0);
  return { idempotency: n(0), usageEvents: n(1), dailyQuota: n(2), sessions: n(3) };
}

/** "Delete learning history" for one device: its sessions, their usage and idempotency rows. */
export async function deleteDeviceHistory(db: D1Database, deviceId: string, parentId: string): Promise<{ sessions: number; usageEvents: number; idempotency: number }> {
  const ids = (await db.prepare('SELECT s.id FROM tutor_sessions s JOIN child_profiles c ON c.id = s.child_id WHERE s.device_id = ? AND c.parent_id = ?').bind(deviceId, parentId).all<{ id: string }>()).results.map((r) => r.id);
  if (!ids.length) return { sessions: 0, usageEvents: 0, idempotency: 0 };
  let usageEvents = 0;
  let idempotency = 0;
  let sessions = 0;
  for (const id of ids) {
    const r = await db.batch([
      db.prepare('DELETE FROM usage_events WHERE session_id = ?').bind(id),
      db.prepare('DELETE FROM api_idempotency WHERE session_id = ?').bind(id),
      db.prepare('DELETE FROM tutor_sessions WHERE id = ?').bind(id),
    ]);
    usageEvents += Number(r[0]?.meta?.changes ?? 0);
    idempotency += Number(r[1]?.meta?.changes ?? 0);
    sessions += Number(r[2]?.meta?.changes ?? 0);
  }
  return { sessions, usageEvents, idempotency };
}
