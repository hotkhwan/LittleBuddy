import { DEV_PARENT_ID } from '../env';
import { uuid } from '../util/crypto';

export interface ParentRow {
  id: string;
  provider: string;
  subject_hash: string;
  email_hash: string | null;
  consent_version: number;
  created_at: number;
  updated_at: number;
  /** Set by DELETE /v1/parents/me; the row is then a tombstone, not an account. */
  deleted_at: number | null;
  tombstone_until: number | null;
}

export const TOMBSTONE_DAYS = 30;
export const TOMBSTONE_MS = TOMBSTONE_DAYS * 24 * 3600 * 1000;

export async function findParentBySubject(db: D1Database, provider: string, subjectHash: string): Promise<ParentRow | null> {
  return (await db.prepare('SELECT * FROM parent_accounts WHERE provider = ? AND subject_hash = ?').bind(provider, subjectHash).first<ParentRow>()) ?? null;
}

export async function getParent(db: D1Database, id: string): Promise<ParentRow | null> {
  return (await db.prepare('SELECT * FROM parent_accounts WHERE id = ?').bind(id).first<ParentRow>()) ?? null;
}

export function isTombstone(p: ParentRow | null | undefined): boolean {
  return Boolean(p && p.deleted_at !== null);
}

export type UpsertOutcome = { parent: ParentRow; created: boolean; tombstoned?: undefined } | { parent?: undefined; created?: undefined; tombstoned: ParentRow };

/**
 * Finds the parent for (provider, subject_hash) or creates one. A tombstone
 * inside its window is returned as `tombstoned` (the caller answers 409);
 * an expired tombstone for this very pair is cleared first, so it can never
 * be revived with its old id: the returning parent gets a new account.
 */
export async function upsertParent(db: D1Database, input: { provider: string; subjectHash: string; emailHash?: string | null; now: number; id?: string }): Promise<UpsertOutcome> {
  await expireTombstones(db, input.now, { provider: input.provider, subjectHash: input.subjectHash });
  const existing = await findParentBySubject(db, input.provider, input.subjectHash);
  if (existing && isTombstone(existing)) return { tombstoned: existing };
  if (existing) {
    // A provider that sends the e-mail only on first sign-in (Apple) never clears a stored hash.
    await db.prepare('UPDATE parent_accounts SET email_hash = COALESCE(?, email_hash), updated_at = ? WHERE id = ?').bind(input.emailHash ?? null, input.now, existing.id).run();
    return { parent: (await getParent(db, existing.id))!, created: false };
  }
  const id = input.id ?? uuid();
  await db.prepare('INSERT INTO parent_accounts (id, provider, subject_hash, email_hash, consent_version, created_at, updated_at) VALUES (?, ?, ?, ?, 0, ?, ?)')
    .bind(id, input.provider, input.subjectHash, input.emailHash ?? null, input.now, input.now).run();
  return { parent: (await getParent(db, id))!, created: true };
}

/**
 * Tombstones past their window: drop those with nothing left to audit,
 * anonymise the rest (they anchor revoked entitlement rows, so the pair
 * becomes 'deleted:<id>'). Sign-in calls it for its own (provider,
 * subject_hash); the retention purge should call it without `only` so the
 * hash of a parent who never returns does not outlive the window either.
 */
export async function expireTombstones(db: D1Database, now: number, only?: { provider: string; subjectHash: string }): Promise<{ deleted: number; anonymised: number }> {
  const scope = only ? ' AND provider = ? AND subject_hash = ?' : '';
  const scopeBinds = only ? [only.provider, only.subjectHash] : [];
  const r = await db.batch([
    db.prepare(`DELETE FROM parent_accounts WHERE deleted_at IS NOT NULL AND tombstone_until IS NOT NULL AND tombstone_until <= ? AND NOT EXISTS (SELECT 1 FROM entitlements e WHERE e.parent_id = parent_accounts.id)${scope}`).bind(now, ...scopeBinds),
    db.prepare(`UPDATE parent_accounts SET subject_hash = 'deleted:' || id, email_hash = NULL, tombstone_until = NULL, updated_at = ? WHERE deleted_at IS NOT NULL AND tombstone_until IS NOT NULL AND tombstone_until <= ?${scope}`).bind(now, now, ...scopeBinds),
  ]);
  return { deleted: Number(r[0]?.meta?.changes ?? 0), anonymised: Number(r[1]?.meta?.changes ?? 0) };
}

/** The synthetic DEV_MODE parent behind the literal dev approval token; all consents granted. */
export async function ensureDevParent(db: D1Database, now: number, consentVersion: number): Promise<ParentRow> {
  const existing = await getParent(db, DEV_PARENT_ID);
  if (existing) return existing;
  await db.batch([
    db.prepare('INSERT OR IGNORE INTO parent_accounts (id, provider, subject_hash, email_hash, consent_version, created_at, updated_at) VALUES (?, ?, ?, NULL, ?, ?, ?)').bind(DEV_PARENT_ID, 'dev', 'dev-literal', consentVersion, now, now),
    ...['privacy', 'ai_tutor', 'voice'].map((kind) => db.prepare('INSERT OR IGNORE INTO consent_status (parent_id, kind, version, granted_at, revoked_at, updated_at) VALUES (?, ?, ?, ?, NULL, ?)').bind(DEV_PARENT_ID, kind, consentVersion, now, now)),
  ]);
  return (await getParent(db, DEV_PARENT_ID))!;
}
