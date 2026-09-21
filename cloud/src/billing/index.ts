// Family Club billing for the Little Days Worker. Mount point: /v1/billing.
//
//   import { billingRoutes } from './billing/index.ts';
//   // inside fetch(request, env, ctx):
//   const handled = await billingRoutes(request, env);
//   if (handled) return handled;
//
// `billingRoutes` returns null for any path outside /v1/billing, so it can sit
// first in the Worker's dispatch. Everything real-store-shaped is behind
// BILLING_PURCHASES_ENABLED="1" (server) and little_days/billing/purchases_enabled
// (app); both are off. NO REAL CHARGE PATH IS ACTIVE.
//
// Secrets and bindings (see docs/FAMILY_CLUB_BILLING.md for the checklist):
//   DB                         D1 binding with schema.sql applied
//   BILLING_PURCHASES_ENABLED  "1" to consult Apple/Google at all (default off)
//   BILLING_DEV_MODE           "1" to accept the Godot mock store's receipts
//   APPLE_BUNDLE_ID, APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_IAP_PRIVATE_KEY_P8, APPLE_ENVIRONMENT
//   APPLE_ROOT_CA_G3_SHA256    optional override of the pinned root fingerprint
//   GOOGLE_PACKAGE_NAME, GOOGLE_SERVICE_ACCOUNT_JSON, GOOGLE_RTDN_TOKEN
import { decisionFromRow, quotaAllowanceFor } from './decision.ts';
import { depsFromEnv, handleBillingRequest, type BillingDeps, type BillingEnv } from './handlers.ts';

export { AppleVerifier } from './apple.ts';
export { BILLING_CONFIG, DAILY_ALLOWANCE_SECONDS, PRICING_PROPOSED, PRODUCTS, PRODUCT_FAMILY_MONTHLY, PRODUCT_FAMILY_YEARLY } from './config.ts';
export { allowanceFor, decideEntitlement, decisionFromRow, quotaAllowanceFor, tierForStatus } from './decision.ts';
export { eventKey, payloadHash, processPurchaseEvent } from './events.ts';
export { GoogleVerifier } from './google.ts';
export { BILLING_MOUNT, depsFromEnv, handleBillingRequest, handleVerify, handleEntitlement, handleAppleNotification, handleGoogleRtdn } from './handlers.ts';
export type { BillingDeps, BillingEnv } from './handlers.ts';
export { D1BillingRepo, MemoryBillingRepo } from './repo.ts';
export type { BillingRepo } from './repo.ts';
export type { EntitlementDecision, EntitlementRow, EntitlementStatus, NormalizedTransaction, ProcessResult, PurchaseEventRow, Store } from './types.ts';

let cachedDeps: { env: BillingEnv; deps: BillingDeps } | null = null;

/** The Worker-facing entry point. Deps are built from env once per isolate. */
export async function billingRoutes(request: Request, env: BillingEnv, deps?: BillingDeps): Promise<Response | null> {
  const resolved = deps ?? resolveDeps(env);
  return handleBillingRequest(request, env, resolved);
}

function resolveDeps(env: BillingEnv): BillingDeps {
  if (cachedDeps && cachedDeps.env === env) return cachedDeps.deps;
  const deps = depsFromEnv(env);
  cachedDeps = { env, deps };
  return deps;
}

/**
 * For the quota module: the daily allowance a subject should get right now,
 * re-evaluated against the clock (so a lapsed subscription drops on time).
 */
export async function allowanceForSubject(deps: BillingDeps, clientId: string): Promise<{ entitlement: 'free' | 'family_club'; dailyAllowanceSeconds: number }> {
  const row = await deps.repo.getEntitlement(clientId);
  return quotaAllowanceFor(decisionFromRow(row, deps.now()));
}
