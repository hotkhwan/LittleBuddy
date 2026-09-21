// Parent privacy controls: the family export (ids and numbers only; there
// are no transcripts anywhere to export) and the two deletions (a child, the
// whole account). Deleting the account leaves a 30-day tombstone (see
// migrations/0005_account_privacy.sql and parents.ts).
import { TOMBSTONE_MS, type ParentRow } from './parents';
import { childToJson, type ChildRow } from './children';
import { consentToJson, type ConsentRow } from './consent';
import { type DeviceRow } from './devices';
import { type EntitlementRow } from './entitlements';
import { progressToJson, type ProgressRow } from './progress';
import { type SessionRow } from './sessions';

export const EXPORT_FORMAT = 'little-days-family-export/1';

interface QuotaRow { child_id: string; day_utc: string; seconds_used: number; turns_used: number; allowance_seconds: number; updated_at: number }
interface PurchaseRow { id: string; store: string; transaction_id: string; product_id: string; status: string; processed_at: number }

const iso = (ms: number | null | undefined) => (ms === null || ms === undefined ? null : new Date(ms).toISOString());

export async function exportFamily(db: D1Database, parent: ParentRow, consentVersion: number, now: number) {
  const children = (await db.prepare('SELECT * FROM child_profiles WHERE parent_id = ? ORDER BY created_at ASC').bind(parent.id).all<ChildRow>()).results;
  const devices = (await db.prepare('SELECT * FROM devices WHERE parent_id = ? ORDER BY created_at ASC').bind(parent.id).all<DeviceRow>()).results;
  const consent = (await db.prepare('SELECT * FROM consent_status WHERE parent_id = ?').bind(parent.id).all<ConsentRow>()).results;
  const entitlements = (await db.prepare('SELECT * FROM entitlements WHERE parent_id = ? ORDER BY updated_at DESC').bind(parent.id).all<EntitlementRow & { revoked_reason: string | null }>()).results;
  const purchases = (await db.prepare('SELECT id, store, transaction_id, product_id, status, processed_at FROM purchase_events WHERE parent_id = ? ORDER BY processed_at ASC').bind(parent.id).all<PurchaseRow>()).results;
  const kids = [];
  for (const child of children) {
    const progress = (await db.prepare('SELECT * FROM learning_progress WHERE child_id = ? ORDER BY updated_at DESC').bind(child.id).all<ProgressRow>()).results;
    const sessions = (await db.prepare('SELECT * FROM tutor_sessions WHERE child_id = ? ORDER BY started_at ASC').bind(child.id).all<SessionRow>()).results;
    const quota = (await db.prepare('SELECT * FROM daily_quota WHERE child_id = ? ORDER BY day_utc ASC').bind(child.id).all<QuotaRow>()).results;
    kids.push({
      ...childToJson(child),
      updatedAt: iso(child.updated_at),
      progress: progress.map(progressToJson),
      tutorSessions: sessions.map((s) => ({ sessionId: s.id, deviceId: s.device_id, lessonId: s.lesson_id, mode: s.mode, startedAt: iso(s.started_at), endedAt: iso(s.ended_at), reason: s.reason, secondsUsed: s.seconds_used, turnCount: s.turn_count })),
      dailyQuota: quota.map((q) => ({ day: q.day_utc, secondsUsed: q.seconds_used, turnsUsed: q.turns_used, allowanceSeconds: q.allowance_seconds })),
    });
  }
  return {
    format: EXPORT_FORMAT,
    exportedAt: new Date(now).toISOString(),
    notes: ['Ids and numbers only. Little Days stores no conversation text, no audio, no e-mail and no real names; the sign-in subject and e-mail columns hold keyed hashes and are not exported.'],
    parent: { parentId: parent.id, provider: parent.provider, consentVersion: parent.consent_version, hasEmailHash: parent.email_hash !== null, createdAt: iso(parent.created_at), updatedAt: iso(parent.updated_at) },
    children: kids,
    devices: devices.map((d) => ({ deviceId: d.id, platform: d.platform, appVersion: d.app_version, createdAt: iso(d.created_at), lastSeenAt: iso(d.last_seen_at) })),
    consent: consentToJson(consent, consentVersion),
    entitlements: entitlements.map((e) => ({ productId: e.product_id, source: e.source, status: e.status, revokedReason: e.revoked_reason ?? null, periodEnd: iso(e.period_end), updatedAt: iso(e.updated_at) })),
    purchaseEvents: purchases.map((p) => ({ store: p.store, transactionId: p.transaction_id, productId: p.product_id, status: p.status, processedAt: iso(p.processed_at) })),
  };
}

export interface ChildDeleteCounts { sessions: number; usageEvents: number; idempotency: number; progress: number; dailyQuota: number }

/** One child: sessions' usage + idempotency rows first (no FK), then the row (cascades sessions, daily_quota, progress). */
export async function deleteChild(db: D1Database, parentId: string, childId: string): Promise<ChildDeleteCounts | null> {
  const child = await db.prepare('SELECT id FROM child_profiles WHERE id = ? AND parent_id = ?').bind(childId, parentId).first<{ id: string }>();
  if (!child) return null;
  const counts = await countChildRows(db, childId);
  await db.batch([
    db.prepare('DELETE FROM usage_events WHERE session_id IN (SELECT id FROM tutor_sessions WHERE child_id = ?)').bind(childId),
    db.prepare('DELETE FROM api_idempotency WHERE session_id IN (SELECT id FROM tutor_sessions WHERE child_id = ?)').bind(childId),
    db.prepare('DELETE FROM child_profiles WHERE id = ? AND parent_id = ?').bind(childId, parentId),
  ]);
  return counts;
}

async function countChildRows(db: D1Database, childId: string): Promise<ChildDeleteCounts> {
  const n = async (sql: string) => Number((await db.prepare(sql).bind(childId).first<{ n: number }>())?.n ?? 0);
  return {
    sessions: await n('SELECT COUNT(*) AS n FROM tutor_sessions WHERE child_id = ?'),
    usageEvents: await n('SELECT COUNT(*) AS n FROM usage_events WHERE session_id IN (SELECT id FROM tutor_sessions WHERE child_id = ?)'),
    idempotency: await n('SELECT COUNT(*) AS n FROM api_idempotency WHERE session_id IN (SELECT id FROM tutor_sessions WHERE child_id = ?)'),
    progress: await n('SELECT COUNT(*) AS n FROM learning_progress WHERE child_id = ?'),
    dailyQuota: await n('SELECT COUNT(*) AS n FROM daily_quota WHERE child_id = ?'),
  };
}

export interface AccountDeleteResult {
  childIds: string[];
  counts: { children: number; devices: number; consent: number; sessions: number; usageEvents: number; idempotency: number; progress: number; dailyQuota: number; entitlementsRevoked: number; purchaseEventsUnlinked: number };
  tombstoneUntil: number;
}

/**
 * The whole family. Everything about children and devices goes; entitlements
 * stay as `revoked` / `account_deleted` (audit), purchase_events lose their
 * parent link, the parent row becomes a 30-day tombstone.
 */
export async function deleteParentAccount(db: D1Database, parentId: string, now: number): Promise<AccountDeleteResult> {
  const childIds = (await db.prepare('SELECT id FROM child_profiles WHERE parent_id = ?').bind(parentId).all<{ id: string }>()).results.map((r) => r.id);
  const totals = { sessions: 0, usageEvents: 0, idempotency: 0, progress: 0, dailyQuota: 0 };
  for (const id of childIds) {
    const c = await countChildRows(db, id);
    totals.sessions += c.sessions;
    totals.usageEvents += c.usageEvents;
    totals.idempotency += c.idempotency;
    totals.progress += c.progress;
    totals.dailyQuota += c.dailyQuota;
  }
  const tombstoneUntil = now + TOMBSTONE_MS;
  const r = await db.batch([
    db.prepare('DELETE FROM usage_events WHERE session_id IN (SELECT s.id FROM tutor_sessions s JOIN child_profiles c ON c.id = s.child_id WHERE c.parent_id = ?)').bind(parentId),
    db.prepare('DELETE FROM api_idempotency WHERE session_id IN (SELECT s.id FROM tutor_sessions s JOIN child_profiles c ON c.id = s.child_id WHERE c.parent_id = ?)').bind(parentId),
    db.prepare('DELETE FROM child_profiles WHERE parent_id = ?').bind(parentId),
    db.prepare('DELETE FROM devices WHERE parent_id = ?').bind(parentId),
    db.prepare('DELETE FROM consent_status WHERE parent_id = ?').bind(parentId),
    db.prepare("UPDATE entitlements SET status = 'revoked', revoked_reason = 'account_deleted', updated_at = ? WHERE parent_id = ?").bind(now, parentId),
    db.prepare('UPDATE purchase_events SET parent_id = NULL WHERE parent_id = ?').bind(parentId),
    db.prepare('UPDATE parent_accounts SET email_hash = NULL, consent_version = 0, deleted_at = ?, tombstone_until = ?, updated_at = ? WHERE id = ?').bind(now, tombstoneUntil, now, parentId),
  ]);
  // D1's meta.changes on the child delete includes cascaded rows, so children are counted from the id list.
  const n = (i: number) => Number(r[i]?.meta?.changes ?? 0);
  return {
    childIds,
    counts: { children: childIds.length, devices: n(3), consent: n(4), entitlementsRevoked: n(5), purchaseEventsUnlinked: n(6), ...totals },
    tombstoneUntil,
  };
}
