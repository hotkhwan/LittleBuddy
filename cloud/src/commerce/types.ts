export type CommerceStore = 'apple' | 'google';
export type InternalPlan = 'FREE' | 'FAMILY' | 'PREMIUM' | 'PREMIUM_PLUS';
export type SubscriptionStatus =
  | 'pending' | 'active' | 'grace' | 'cancelled' | 'expired' | 'refunded' | 'revoked';

export interface StoreProductMapping {
  key: string;
  store: CommerceStore;
  productId: string;
  plan: Exclude<InternalPlan, 'FREE'>;
  active: boolean;
}

export type CommerceEventKind =
  | 'purchased' | 'renewed' | 'cancelled' | 'expired' | 'refunded' | 'revoked' | 'restored';

/** Store signatures/tokens have already been verified before this object exists. */
export interface VerifiedCommerceEvent {
  store: CommerceStore;
  eventId: string;
  eventKind: CommerceEventKind;
  productId: string;
  originalTransactionId: string;
  transactionId: string;
  accountToken: string | null;
  occurredAtMs: number;
  expiresAtMs: number | null;
  environment: 'sandbox' | 'production';
  /** A stable digest of the signed notification or purchase token, never its raw value. */
  evidenceHash: string;
}

export interface SubscriptionSnapshot {
  accountId: string;
  store: CommerceStore;
  originalTransactionId: string;
  productKey: string;
  plan: Exclude<InternalPlan, 'FREE'>;
  status: SubscriptionStatus;
  currentPeriodEndMs: number | null;
  autoRenewing: boolean;
  lastEventAtMs: number;
  updatedAtMs: number;
}

export interface ProcessedEvent {
  store: CommerceStore;
  eventId: string;
  evidenceHash: string;
  processedAtMs: number;
}

export interface ProductMappingRepository {
  findActiveByStoreProduct(store: CommerceStore, productId: string): Promise<StoreProductMapping | null>;
}

export interface CommerceRepository {
  getProcessedEvent(store: CommerceStore, eventId: string): Promise<ProcessedEvent | null>;
  getSubscription(store: CommerceStore, originalTransactionId: string): Promise<SubscriptionSnapshot | null>;
  /** Must atomically persist the event marker and snapshot (unique store+eventId). */
  applyEvent(event: ProcessedEvent, snapshot: SubscriptionSnapshot): Promise<'applied' | 'duplicate'>;
}

export interface StoreVerifier<TPurchase = unknown, TNotification = unknown> {
  readonly store: CommerceStore;
  verifyPurchase(input: TPurchase): Promise<VerifiedCommerceEvent>;
  verifyNotification(input: TNotification): Promise<VerifiedCommerceEvent | null>;
}

export class CommerceError extends Error {
  constructor(readonly code: string, readonly httpStatus: number, message = code) {
    super(message);
  }
}
