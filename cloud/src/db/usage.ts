// usage_events: numbers only. Also the monthly budget guard.
import { utcMonthStartMs } from '../util/time';
import { uuid } from '../util/crypto';

export type UsageKind = 'turn' | 'realtime_mint' | 'realtime_usage';

export async function recordUsage(db: D1Database, input: { sessionId: string; kind: UsageKind; tokensIn: number; tokensOut: number; audioSeconds: number; costUsdMicro: number; now: number }): Promise<string> {
  const id = uuid();
  await db.prepare('INSERT INTO usage_events (id, session_id, kind, tokens_in, tokens_out, audio_seconds, cost_usd_micro, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
    .bind(id, input.sessionId, input.kind, clampInt(input.tokensIn), clampInt(input.tokensOut), clampNum(input.audioSeconds, 7200), clampInt(input.costUsdMicro), input.now).run();
  return id;
}

export async function monthlySpendMicro(db: D1Database, now: number): Promise<{ spentUsdMicro: number; events: number; monthStart: string }> {
  const start = utcMonthStartMs(now);
  const row = await db.prepare('SELECT COALESCE(SUM(cost_usd_micro), 0) AS spent, COUNT(*) AS n FROM usage_events WHERE created_at >= ?').bind(start).first<{ spent: number; n: number }>();
  return { spentUsdMicro: Number(row?.spent ?? 0), events: Number(row?.n ?? 0), monthStart: new Date(start).toISOString() };
}

export async function budgetExceeded(db: D1Database, monthlyBudgetUsd: number, now: number): Promise<boolean> {
  const { spentUsdMicro } = await monthlySpendMicro(db, now);
  return spentUsdMicro >= Math.round(monthlyBudgetUsd * 1e6);
}

export async function sessionTotals(db: D1Database, sessionId: string): Promise<{ turns: number; llmInputTokens: number; llmOutputTokens: number; audioSeconds: number; costUsd: number }> {
  const row = await db.prepare(`SELECT COUNT(*) AS n, COALESCE(SUM(tokens_in), 0) AS tin, COALESCE(SUM(tokens_out), 0) AS tout, COALESCE(SUM(audio_seconds), 0) AS audio, COALESCE(SUM(cost_usd_micro), 0) AS cost
    FROM usage_events WHERE session_id = ?`).bind(sessionId).first<{ n: number; tin: number; tout: number; audio: number; cost: number }>();
  return { turns: Number(row?.n ?? 0), llmInputTokens: Number(row?.tin ?? 0), llmOutputTokens: Number(row?.tout ?? 0), audioSeconds: Number(row?.audio ?? 0), costUsd: Number(row?.cost ?? 0) / 1e6 };
}

function clampInt(v: number): number {
  return Math.max(0, Math.min(2 ** 40, Math.round(Number(v) || 0)));
}
function clampNum(v: number, max: number): number {
  return Math.max(0, Math.min(max, Number(v) || 0));
}
