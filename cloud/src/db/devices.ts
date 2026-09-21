export interface DeviceRow { id: string; parent_id: string; platform: string; app_version: string | null; created_at: number; last_seen_at: number }

export const PLATFORMS = ['ios', 'android', 'macos', 'unknown'] as const;

export async function getDevice(db: D1Database, id: string): Promise<DeviceRow | null> {
  return (await db.prepare('SELECT * FROM devices WHERE id = ?').bind(id).first<DeviceRow>()) ?? null;
}

/** Registers or refreshes a device. Returns null when the clientId belongs to another parent. */
export async function upsertDevice(db: D1Database, input: { id: string; parentId: string; platform?: string; appVersion?: string; now: number }): Promise<DeviceRow | null> {
  const existing = await getDevice(db, input.id);
  if (existing && existing.parent_id !== input.parentId) return null;
  if (existing) {
    await db.prepare('UPDATE devices SET platform = COALESCE(?, platform), app_version = COALESCE(?, app_version), last_seen_at = ? WHERE id = ?')
      .bind(input.platform ?? null, input.appVersion ?? null, input.now, input.id).run();
  } else {
    await db.prepare('INSERT INTO devices (id, parent_id, platform, app_version, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(input.id, input.parentId, input.platform ?? 'unknown', input.appVersion ?? null, input.now, input.now).run();
  }
  return getDevice(db, input.id);
}

export async function listDevices(db: D1Database, parentId: string): Promise<DeviceRow[]> {
  return (await db.prepare('SELECT * FROM devices WHERE parent_id = ? ORDER BY created_at ASC').bind(parentId).all<DeviceRow>()).results;
}
