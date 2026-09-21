export interface ProgressRow { child_id: string; lesson_id: string; step_index: number; completed_at: number | null; stars: number; updated_at: number }

export function progressToJson(r: ProgressRow) {
  return { lessonId: r.lesson_id, stepIndex: r.step_index, completedAt: r.completed_at === null ? null : new Date(r.completed_at).toISOString(), stars: r.stars, updatedAt: new Date(r.updated_at).toISOString() };
}

export async function listProgress(db: D1Database, childId: string): Promise<ProgressRow[]> {
  return (await db.prepare('SELECT * FROM learning_progress WHERE child_id = ? ORDER BY updated_at DESC').bind(childId).all<ProgressRow>()).results;
}

export async function upsertProgress(db: D1Database, input: { childId: string; lessonId: string; stepIndex: number; completed: boolean; stars: number; now: number }): Promise<ProgressRow> {
  await db.prepare(`INSERT INTO learning_progress (child_id, lesson_id, step_index, completed_at, stars, updated_at) VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(child_id, lesson_id) DO UPDATE SET
      step_index = MAX(learning_progress.step_index, excluded.step_index),
      completed_at = COALESCE(learning_progress.completed_at, excluded.completed_at),
      stars = MAX(learning_progress.stars, excluded.stars),
      updated_at = excluded.updated_at`)
    .bind(input.childId, input.lessonId, input.stepIndex, input.completed ? input.now : null, input.stars, input.now).run();
  return (await db.prepare('SELECT * FROM learning_progress WHERE child_id = ? AND lesson_id = ?').bind(input.childId, input.lessonId).first<ProgressRow>())!;
}
