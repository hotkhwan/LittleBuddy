import { IDEMPOTENCY_TTL_MS } from '../util/time';

export interface IdemRow { key: string; session_id: string; request_hash: string; response_hash: string; status: number; response_json: string; created_at: number }

export async function findIdempotent(db: D1Database, key: string, now: number): Promise<IdemRow | null> {
  const row = await db.prepare('SELECT * FROM api_idempotency WHERE key = ?').bind(key).first<IdemRow>();
  if (!row) return null;
  if (now - row.created_at > IDEMPOTENCY_TTL_MS) return null;
  return row;
}

export async function storeIdempotent(db: D1Database, row: { key: string; sessionId: string; requestHash: string; responseHash: string; status: number; responseJson: string; now: number }): Promise<void> {
  await db.prepare('INSERT OR REPLACE INTO api_idempotency (key, session_id, request_hash, response_hash, status, response_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .bind(row.key, row.sessionId, row.requestHash, row.responseHash, row.status, row.responseJson, row.now).run();
}
