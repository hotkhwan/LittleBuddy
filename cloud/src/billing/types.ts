import type { EntitlementId, QuotaTier } from './config.ts';

export type Store = 'apple' | 'google' | 'mock';
export const STORES: ReadonlyArray<Store> = Object.freeze(['apple', 'google', 'mock']);

export type EntitlementStatus = 'active' | 'grace' | 'expired' | 'revoked' | 'none';

export type EventSource = 'verify' | 'apple_notification' | 'google_rtdn' | 'mock';

/**
 * A store event with the store-specific shape removed. Everything the decision
 * needs, nothing it does not. Times are unix MILLISECONDS (store-native).
 */
export interface NormalizedTransaction {
  store: Store;
  productId: string;
  /** Unique per store event: Apple transactionId, Google latestOrderId. */
  transactionId: string;
  /** The subscription's identity across renewals: Apple originalTransactionId, Google purchaseToken. */
  originalTransactionId: string;
  purchaseTimeMs: number;
  expiresAtMs: number | null;
  /** Set when the store says the money went back (refund / revoke / voided). */
  revokedAtMs: number | null;
  /** Explicit grace end from the store, when it gave one. */
  gracePeriodExpiresAtMs: number | null;
  autoRenewing: boolean | null;
  environment: 'production' | 'sandbox' | 'mock';
  /** Apple appAccountToken / Google obfuscatedExternalAccountId, if the app set one. */
  accountToken: string | null;
  /** Ordering key: Apple signedDate, Google eventTimeMillis / API fetch time. */
  eventTimeMs: number;
  source: EventSource;
  /** Google only: the token this purchase replaced (upgrade/downgrade/resubscribe). */
  supersedesOriginalTransactionId?: string | null;
}

export interface EntitlementDecision {
  entitlementId: EntitlementId;
  status: EntitlementStatus;
  /** Unix SECONDS: when the current period (or grace) ends. 0 when none. */
  periodEnd: number;
  /** Unix SECONDS: when the backend last confirmed this with the store. */
  verifiedAt: number;
  originalTransactionId: string;
  store: Store;
  productId: string;
  /** What the quota layer should allow per UTC day for this decision. */
  quotaTier: QuotaTier;
  allowanceSeconds: number;
  reason: string;
}

export interface PurchaseEventRow {
  transaction_id: string;
  store: string;
  original_transaction_id: string;
  product_id: string;
  subject_id: string | null;
  payload_hash: string;
  event_time_ms: number;
  source: string;
  result_json: string;
  processed_at: number;
}

export interface EntitlementRow {
  subject_id: string;
  entitlement_id: string;
  status: EntitlementStatus;
  period_end: number;
  verified_at: number;
  original_transaction_id: string;
  store: string;
  product_id: string;
  last_event_time_ms: number;
  updated_at: number;
}

export interface ProcessResult {
  outcome: 'applied' | 'replayed' | 'stale' | 'conflict' | 'rejected';
  decision: EntitlementDecision | null;
  /** Subjects whose entitlement row was written. */
  subjects: string[];
  reason: string;
  httpStatus: number;
}

export class BillingError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string, message?: string) {
    super(message ?? code);
    this.status = status;
    this.code = code;
  }
}
