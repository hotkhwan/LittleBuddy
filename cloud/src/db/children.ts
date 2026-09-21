import { uuid } from '../util/crypto';

export interface ChildRow { id: string; parent_id: string; nickname: string; avatar_id: string | null; birth_year_bucket: string | null; locale: string; created_at: number; updated_at: number }

export const DEFAULT_NICKNAME = 'Buddy';

export function childToJson(c: ChildRow) {
  return { childId: c.id, nickname: c.nickname, avatarId: c.avatar_id, birthYearBucket: c.birth_year_bucket, locale: c.locale, createdAt: new Date(c.created_at).toISOString() };
}

export async function listChildren(db: D1Database, parentId: string): Promise<ChildRow[]> {
  return (await db.prepare('SELECT * FROM child_profiles WHERE parent_id = ? ORDER BY created_at ASC').bind(parentId).all<ChildRow>()).results;
}

export async function getChild(db: D1Database, parentId: string, childId: string): Promise<ChildRow | null> {
  return (await db.prepare('SELECT * FROM child_profiles WHERE id = ? AND parent_id = ?').bind(childId, parentId).first<ChildRow>()) ?? null;
}

export async function createChild(db: D1Database, input: { parentId: string; nickname: string; avatarId?: string; birthYearBucket?: string; locale?: string; now: number }): Promise<ChildRow> {
  const id = uuid();
  await db.prepare('INSERT INTO child_profiles (id, parent_id, nickname, avatar_id, birth_year_bucket, locale, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
    .bind(id, input.parentId, input.nickname, input.avatarId ?? null, input.birthYearBucket ?? null, input.locale || 'en-US', input.now, input.now).run();
  return (await getChild(db, input.parentId, id))!;
}

/**
 * The child a tutor call is about: an explicit childId (must belong to the
 * parent), else the token's child, else the parent's first profile, else a
 * nickname-only default so the current Godot client (which knows nothing
 * about profiles) works unchanged.
 */
export async function resolveChild(db: D1Database, parentId: string, explicitId: string, tokenChildId: string | undefined, now: number): Promise<ChildRow | null> {
  if (explicitId) return getChild(db, parentId, explicitId);
  if (tokenChildId) {
    const c = await getChild(db, parentId, tokenChildId);
    if (c) return c;
  }
  const all = await listChildren(db, parentId);
  if (all.length) return all[0];
  return createChild(db, { parentId, nickname: DEFAULT_NICKNAME, now });
}
