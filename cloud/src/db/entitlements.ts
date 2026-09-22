// Effective entitlement for a parent: `family_club` while any row for a
// Family Club product is active (or in grace) and not past period_end.
import type { Config, Entitlement, Plan } from '../env';

export interface EntitlementRow { parent_id: string; product_id: string; source: string; status: string; period_end: number | null; raw_receipt_ref: string | null; updated_at: number }

export async function listEntitlements(db: D1Database, parentId: string): Promise<EntitlementRow[]> {
  return (await db.prepare('SELECT * FROM entitlements WHERE parent_id = ? ORDER BY updated_at DESC').bind(parentId).all<EntitlementRow>()).results;
}

export function effectiveEntitlement(rows: EntitlementRow[], config: Config, now: number): { entitlement: Entitlement; activeUntil: string | null; source: string | null } {
  for (const r of rows) {
    if (!config.familyClubProductIds.includes(r.product_id)) continue;
    if (r.status !== 'active' && r.status !== 'grace') continue;
    if (r.period_end !== null && r.period_end <= now) continue;
    return { entitlement: 'family_club', activeUntil: r.period_end === null ? null : new Date(r.period_end).toISOString(), source: r.source };
  }
  return { entitlement: 'free', activeUntil: null, source: null };
}

export async function getEntitlement(db: D1Database, parentId: string, config: Config, now: number): Promise<Entitlement> {
  return effectiveEntitlement(await listEntitlements(db, parentId), config, now).entitlement;
}

export function effectivePlan(rows: EntitlementRow[], config: Config, now: number): { plan: Plan; status: string; expiresAt: string | null; source: string | null } {
  const rank: Record<Plan, number> = { FREE: 0, FAMILY: 1, PREMIUM: 2, PREMIUM_PLUS: 3 };
  let selected: { plan: Plan; status: string; expiresAt: string | null; source: string | null } = { plan: 'FREE', status: 'none', expiresAt: null, source: null };
  for (const row of rows) {
    if (!['active', 'grace'].includes(row.status) || (row.period_end !== null && row.period_end <= now)) continue;
    const mapped = config.storeProductMap[row.product_id]?.plan ?? (config.familyClubProductIds.includes(row.product_id) ? 'FAMILY' : null);
    if (mapped && rank[mapped] > rank[selected.plan]) selected = { plan: mapped, status: row.status, expiresAt: row.period_end === null ? null : new Date(row.period_end).toISOString(), source: row.source };
  }
  return selected;
}

/** Dev grant / revoke (DEV_MODE route) and the write Agent F's billing module will reuse. */
export async function setEntitlement(db: D1Database, input: { parentId: string; productId: string; source: string; status: string; periodEnd: number | null; receiptRef?: string | null; now: number }): Promise<void> {
  await db.prepare(`INSERT INTO entitlements (parent_id, product_id, source, status, period_end, raw_receipt_ref, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(parent_id, product_id, source) DO UPDATE SET status = excluded.status, period_end = excluded.period_end, raw_receipt_ref = excluded.raw_receipt_ref, updated_at = excluded.updated_at`)
    .bind(input.parentId, input.productId, input.source, input.status, input.periodEnd, input.receiptRef ?? null, input.now).run();
}
