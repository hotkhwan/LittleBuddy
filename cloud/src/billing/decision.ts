// The PURE entitlement decision, shared by verify, notifications and the quota
// allowance. No I/O, no clock of its own: `nowMs` comes in.
import { BILLING_CONFIG, DAILY_ALLOWANCE_SECONDS, productById, type QuotaTier } from './config.ts';
import type { EntitlementDecision, EntitlementRow, EntitlementStatus, NormalizedTransaction } from './types.ts';

export function allowanceFor(tier: QuotaTier): number {
  return DAILY_ALLOWANCE_SECONDS[tier] ?? DAILY_ALLOWANCE_SECONDS.free;
}

export function tierForStatus(status: EntitlementStatus): QuotaTier {
  return status === 'active' || status === 'grace' ? 'family_club' : 'free';
}

export function grants(status: EntitlementStatus): boolean {
  return status === 'active' || status === 'grace';
}

/**
 * Store facts -> entitlement. Order of the rules matters and is tested:
 *   1. an unknown product grants nothing (`none`);
 *   2. money went back -> `revoked`, terminal;
 *   3. inside the paid period -> `active`;
 *   4. past it but inside a store-declared or fallback grace -> `grace`
 *      (fallback grace only while the store still says it is auto-renewing:
 *      a cancelled subscription simply expires);
 *   5. otherwise `expired`.
 */
export function decideEntitlement(tx: NormalizedTransaction, nowMs: number): EntitlementDecision {
  const product = productById(tx.productId);
  const verifiedAt = Math.floor(nowMs / 1000);
  const base = {
    entitlementId: 'familyClub' as const,
    verifiedAt,
    originalTransactionId: tx.originalTransactionId,
    store: tx.store,
    productId: tx.productId,
  };
  const finish = (status: EntitlementStatus, periodEndMs: number | null, reason: string): EntitlementDecision => {
    const tier = tierForStatus(status);
    return {
      ...base,
      status,
      periodEnd: periodEndMs && periodEndMs > 0 ? Math.floor(periodEndMs / 1000) : 0,
      quotaTier: tier,
      allowanceSeconds: allowanceFor(tier),
      reason,
    };
  };

  if (!product) return finish('none', null, 'unknown_product');
  if (tx.revokedAtMs !== null && tx.revokedAtMs !== undefined) return finish('revoked', tx.revokedAtMs, 'revoked');
  if (tx.expiresAtMs === null || tx.expiresAtMs === undefined) return finish('none', null, 'no_expiry');

  const maxPeriodMs = BILLING_CONFIG.maxPeriodDays * 24 * 3600 * 1000;
  if (tx.expiresAtMs - nowMs > maxPeriodMs) return finish('none', null, 'expiry_out_of_bounds');

  if (nowMs < tx.expiresAtMs) return finish('active', tx.expiresAtMs, 'within_period');

  if (tx.gracePeriodExpiresAtMs !== null && tx.gracePeriodExpiresAtMs !== undefined) {
    if (nowMs < tx.gracePeriodExpiresAtMs) return finish('grace', tx.gracePeriodExpiresAtMs, 'store_grace');
    return finish('expired', tx.expiresAtMs, 'grace_over');
  }
  if (tx.autoRenewing === true) {
    const fallbackEnd = tx.expiresAtMs + BILLING_CONFIG.fallbackGraceSeconds * 1000;
    if (nowMs < fallbackEnd) return finish('grace', fallbackEnd, 'fallback_grace');
  }
  return finish('expired', tx.expiresAtMs, 'period_over');
}

/**
 * Re-evaluates a STORED entitlement row at `nowMs` without a new store event:
 * an active row whose period passed reads as expired; a revoked row stays
 * revoked. This is what `GET /entitlement` and the quota allowance use, so a
 * lapsed subscription drops to the free allowance on time even if no
 * notification ever arrives.
 */
export function decisionFromRow(row: EntitlementRow | null, nowMs: number): EntitlementDecision {
  if (!row) {
    return {
      entitlementId: 'familyClub',
      status: 'none',
      periodEnd: 0,
      verifiedAt: 0,
      originalTransactionId: '',
      store: 'mock',
      productId: '',
      quotaTier: 'free',
      allowanceSeconds: allowanceFor('free'),
      reason: 'no_row',
    };
  }
  const nowS = Math.floor(nowMs / 1000);
  let status: EntitlementStatus = row.status;
  let reason = 'stored';
  if (grants(status) && row.period_end <= nowS) {
    status = 'expired';
    reason = 'stored_period_over';
  }
  const tier = tierForStatus(status);
  return {
    entitlementId: 'familyClub',
    status,
    periodEnd: row.period_end,
    verifiedAt: row.verified_at,
    originalTransactionId: row.original_transaction_id,
    store: row.store as EntitlementDecision['store'],
    productId: row.product_id,
    quotaTier: tier,
    allowanceSeconds: allowanceFor(tier),
    reason,
  };
}

/** The quota block the tutor endpoints can merge into their replies. */
export function quotaAllowanceFor(decision: EntitlementDecision): { entitlement: QuotaTier; dailyAllowanceSeconds: number } {
  return { entitlement: decision.quotaTier, dailyAllowanceSeconds: decision.allowanceSeconds };
}
