export const CONSENT_KINDS = ['privacy', 'ai_tutor', 'voice'] as const;
export type ConsentKind = (typeof CONSENT_KINDS)[number];

export interface ConsentRow { parent_id: string; kind: string; version: number; granted_at: number | null; revoked_at: number | null; updated_at: number }

export async function listConsent(db: D1Database, parentId: string): Promise<ConsentRow[]> {
  return (await db.prepare('SELECT * FROM consent_status WHERE parent_id = ?').bind(parentId).all<ConsentRow>()).results;
}

export function isGranted(row: ConsentRow | undefined, requiredVersion: number): boolean {
  return Boolean(row && row.granted_at !== null && row.revoked_at === null && row.version >= requiredVersion);
}

export async function hasConsent(db: D1Database, parentId: string, kind: ConsentKind, requiredVersion: number): Promise<boolean> {
  const row = await db.prepare('SELECT * FROM consent_status WHERE parent_id = ? AND kind = ?').bind(parentId, kind).first<ConsentRow>();
  return isGranted(row ?? undefined, requiredVersion);
}

export async function setConsent(db: D1Database, input: { parentId: string; kind: ConsentKind; version: number; granted: boolean; now: number }): Promise<void> {
  if (input.granted) {
    await db.prepare(`INSERT INTO consent_status (parent_id, kind, version, granted_at, revoked_at, updated_at) VALUES (?, ?, ?, ?, NULL, ?)
      ON CONFLICT(parent_id, kind) DO UPDATE SET version = excluded.version, granted_at = excluded.granted_at, revoked_at = NULL, updated_at = excluded.updated_at`)
      .bind(input.parentId, input.kind, input.version, input.now, input.now).run();
  } else {
    await db.prepare(`INSERT INTO consent_status (parent_id, kind, version, granted_at, revoked_at, updated_at) VALUES (?, ?, ?, NULL, ?, ?)
      ON CONFLICT(parent_id, kind) DO UPDATE SET version = excluded.version, revoked_at = excluded.revoked_at, updated_at = excluded.updated_at`)
      .bind(input.parentId, input.kind, input.version, input.now, input.now).run();
  }
  if (input.kind === 'privacy' && input.granted) {
    await db.prepare('UPDATE parent_accounts SET consent_version = MAX(consent_version, ?), updated_at = ? WHERE id = ?').bind(input.version, input.now, input.parentId).run();
  }
}

export function consentToJson(rows: ConsentRow[], requiredVersion: number) {
  const out: Record<string, { version: number; grantedAt: string | null; revokedAt: string | null; granted: boolean }> = {};
  for (const kind of CONSENT_KINDS) {
    const row = rows.find((r) => r.kind === kind);
    out[kind] = {
      version: row?.version ?? 0,
      grantedAt: row?.granted_at ? new Date(row.granted_at).toISOString() : null,
      revokedAt: row?.revoked_at ? new Date(row.revoked_at).toISOString() : null,
      granted: isGranted(row, requiredVersion),
    };
  }
  return out;
}
