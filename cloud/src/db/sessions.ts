export interface SessionRow { id: string; child_id: string; device_id: string | null; lesson_id: string; mode: string; provider: string; started_at: number; ended_at: number | null; reason: string | null; seconds_used: number; turn_count: number }

export async function insertSession(db: D1Database, s: { id: string; childId: string; deviceId: string | null; lessonId: string; mode: 'turns' | 'realtime'; provider: string; startedAt: number }): Promise<void> {
  await db.prepare('INSERT INTO tutor_sessions (id, child_id, device_id, lesson_id, mode, provider, started_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .bind(s.id, s.childId, s.deviceId, s.lessonId, s.mode, s.provider, s.startedAt).run();
}

export async function updateSessionProgress(db: D1Database, id: string, secondsUsed: number, turnCount: number, mode?: 'turns' | 'realtime'): Promise<void> {
  await db.prepare('UPDATE tutor_sessions SET seconds_used = ?, turn_count = ?, mode = COALESCE(?, mode) WHERE id = ?').bind(secondsUsed, turnCount, mode ?? null, id).run();
}

export async function markSessionEnded(db: D1Database, id: string, endedAt: number, reason: string, secondsUsed: number, turnCount: number): Promise<void> {
  await db.prepare('UPDATE tutor_sessions SET ended_at = ?, reason = ?, seconds_used = ?, turn_count = ? WHERE id = ? AND ended_at IS NULL').bind(endedAt, reason, secondsUsed, turnCount, id).run();
}

export async function getSession(db: D1Database, id: string): Promise<SessionRow | null> {
  return (await db.prepare('SELECT * FROM tutor_sessions WHERE id = ?').bind(id).first<SessionRow>()) ?? null;
}
