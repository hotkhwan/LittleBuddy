import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BILLING_CONFIG, DAILY_ALLOWANCE_SECONDS, PRICING_PROPOSED, PRODUCTS } from '../config.ts';
import { allowanceFor, decideEntitlement, decisionFromRow, quotaAllowanceFor } from '../decision.ts';
import { DAY_MS, NOW_MS, tx } from './helpers.ts';

test('config: two products, both familyClub; allowances match the game quota config; price is proposed only', () => {
  assert.deepEqual(PRODUCTS.map((p) => p.productId), ['little_days_family_monthly', 'little_days_family_yearly']);
  assert.ok(PRODUCTS.every((p) => p.entitlementId === 'familyClub'));
  assert.equal(DAILY_ALLOWANCE_SECONDS.free, 300);
  assert.equal(DAILY_ALLOWANCE_SECONDS.family_club, 1800);
  assert.equal(allowanceFor('family_club'), 1800);
  assert.equal(allowanceFor('free'), 300);
  assert.equal(PRICING_PROPOSED.status, 'proposed');
  assert.equal(PRICING_PROPOSED.currency, 'THB');
  assert.equal(PRICING_PROPOSED.monthly, 99);
  assert.equal(PRICING_PROPOSED.yearly, null, 'no annual price may be invented');
});

test('decision: inside the period is active with the family_club allowance', () => {
  const d = decideEntitlement(tx(), NOW_MS);
  assert.equal(d.status, 'active');
  assert.equal(d.periodEnd, Math.floor((NOW_MS + 29 * DAY_MS) / 1000));
  assert.equal(d.quotaTier, 'family_club');
  assert.equal(d.allowanceSeconds, 1800);
  assert.deepEqual(quotaAllowanceFor(d), { entitlement: 'family_club', dailyAllowanceSeconds: 1800 });
});

test('decision: unknown product grants nothing even with a valid period', () => {
  const d = decideEntitlement(tx({ productId: 'little_days_gold' }), NOW_MS);
  assert.equal(d.status, 'none');
  assert.equal(d.allowanceSeconds, 300);
});

test('decision: revocation wins over everything', () => {
  const d = decideEntitlement(tx({ revokedAtMs: NOW_MS - 1000 }), NOW_MS);
  assert.equal(d.status, 'revoked');
  assert.equal(d.quotaTier, 'free');
});

test('decision: past the period -> store grace, then fallback grace only while auto-renewing, then expired', () => {
  const expired = NOW_MS - DAY_MS;
  const withStoreGrace = decideEntitlement(tx({ expiresAtMs: expired, gracePeriodExpiresAtMs: NOW_MS + 5 * DAY_MS }), NOW_MS);
  assert.equal(withStoreGrace.status, 'grace');
  assert.equal(withStoreGrace.periodEnd, Math.floor((NOW_MS + 5 * DAY_MS) / 1000));

  const graceOver = decideEntitlement(tx({ expiresAtMs: expired, gracePeriodExpiresAtMs: NOW_MS - 1000 }), NOW_MS);
  assert.equal(graceOver.status, 'expired');

  const fallback = decideEntitlement(tx({ expiresAtMs: expired, autoRenewing: true }), NOW_MS);
  assert.equal(fallback.status, 'grace');
  assert.equal(fallback.reason, 'fallback_grace');
  assert.equal(fallback.periodEnd, Math.floor((expired + BILLING_CONFIG.fallbackGraceSeconds * 1000) / 1000));

  const cancelled = decideEntitlement(tx({ expiresAtMs: expired, autoRenewing: false }), NOW_MS);
  assert.equal(cancelled.status, 'expired');

  const longGone = decideEntitlement(tx({ expiresAtMs: NOW_MS - 30 * DAY_MS, autoRenewing: true }), NOW_MS);
  assert.equal(longGone.status, 'expired');
});

test('decision: no expiry or an absurd expiry is not a subscription we sell', () => {
  assert.equal(decideEntitlement(tx({ expiresAtMs: null }), NOW_MS).status, 'none');
  assert.equal(decideEntitlement(tx({ expiresAtMs: NOW_MS + 5 * 365 * DAY_MS }), NOW_MS).status, 'none');
});

test('decisionFromRow: a stored active row reads expired once its period passes; revoked stays revoked', () => {
  const row = {
    subject_id: 'a', entitlement_id: 'familyClub', status: 'active' as const, period_end: Math.floor(NOW_MS / 1000) + 60,
    verified_at: Math.floor(NOW_MS / 1000), original_transaction_id: 'orig-1', store: 'apple', product_id: 'little_days_family_monthly',
    last_event_time_ms: NOW_MS, updated_at: Math.floor(NOW_MS / 1000),
  };
  assert.equal(decisionFromRow(row, NOW_MS).status, 'active');
  assert.equal(decisionFromRow(row, NOW_MS + 61_000).status, 'expired');
  assert.equal(decisionFromRow(row, NOW_MS + 61_000).allowanceSeconds, 300);
  assert.equal(decisionFromRow({ ...row, status: 'revoked' }, NOW_MS).status, 'revoked');
  assert.equal(decisionFromRow(null, NOW_MS).status, 'none');
});
