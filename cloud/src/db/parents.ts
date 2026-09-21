import { DEV_PARENT_ID } from '../env';
import { uuid } from '../util/crypto';

export interface ParentRow { id: string; provider: string; subject_hash: string; email_hash: string | null; consent_version: number; created_at: number; updated_at: number }

export async function findParentBySubject(db: D1Database, provider: string, subjectHash: string): Promise<ParentRow | null> {
  return (await db.prepare('SELECT * FROM parent_accounts WHERE provider = ? AND subject_hash = ?').bind(provider, subjectHash).first<ParentRow>()) ?? null;
}

export async function getParent(db: D1Database, id: string): Promise<ParentRow | null> {
  return (await db.prepare('SELECT * FROM parent_accounts WHERE id = ?').bind(id).first<ParentRow>()) ?? null;
}

export async function upsertParent(db: D1Database, input: { provider: string; subjectHash: string; emailHash?: string | null; now: number; id?: string }): Promise<{ parent: ParentRow; created: boolean }> {
  const existing = await findParentBySubject(db, input.provider, input.subjectHash);
  if (existing) {
    await db.prepare('UPDATE parent_accounts SET updated_at = ? WHERE id = ?').bind(input.now, existing.id).run();
    return { parent: existing, created: false };
  }
  const id = input.id ?? uuid();
  await db.prepare('INSERT INTO parent_accounts (id, provider, subject_hash, email_hash, consent_version, created_at, updated_at) VALUES (?, ?, ?, ?, 0, ?, ?)')
    .bind(id, input.provider, input.subjectHash, input.emailHash ?? null, input.now, input.now).run();
  return { parent: (await getParent(db, id))!, created: true };
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
