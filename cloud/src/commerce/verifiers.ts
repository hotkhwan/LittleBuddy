import { CommerceError, type CommerceStore, type StoreVerifier, type VerifiedCommerceEvent } from './types.ts';

export type VerificationSource<T> = (input: T) => Promise<VerifiedCommerceEvent | null>;

/**
 * Provider-neutral boundary around StoreKit verification. Production injects a
 * JWS/App Store Server API implementation; tests inject a deterministic fake.
 */
export class AppleStoreKitVerifier<P = unknown, N = unknown> implements StoreVerifier<P, N> {
  readonly store = 'apple' as const;
  constructor(private readonly purchaseSource: VerificationSource<P>, private readonly notificationSource: VerificationSource<N>) {}
  async verifyPurchase(input: P): Promise<VerifiedCommerceEvent> {
    return requireVerified('apple', await this.purchaseSource(input));
  }
  async verifyNotification(input: N): Promise<VerifiedCommerceEvent | null> {
    const event = await this.notificationSource(input);
    return event === null ? null : requireVerified('apple', event);
  }
}

/** Production injects Android Publisher API + authenticated RTDN verification. */
export class GooglePlayVerifier<P = unknown, N = unknown> implements StoreVerifier<P, N> {
  readonly store = 'google' as const;
  constructor(private readonly purchaseSource: VerificationSource<P>, private readonly notificationSource: VerificationSource<N>) {}
  async verifyPurchase(input: P): Promise<VerifiedCommerceEvent> {
    return requireVerified('google', await this.purchaseSource(input));
  }
  async verifyNotification(input: N): Promise<VerifiedCommerceEvent | null> {
    const event = await this.notificationSource(input);
    return event === null ? null : requireVerified('google', event);
  }
}

function requireVerified(store: CommerceStore, event: VerifiedCommerceEvent | null): VerifiedCommerceEvent {
  if (!event) throw new CommerceError('STORE_VERIFICATION_FAILED', 401);
  if (event.store !== store) throw new CommerceError('STORE_MISMATCH', 400);
  if (!event.eventId || !event.transactionId || !event.originalTransactionId || !event.productId || !event.evidenceHash) {
    throw new CommerceError('INVALID_VERIFIED_EVENT', 400);
  }
  if (!Number.isFinite(event.occurredAtMs) || event.occurredAtMs <= 0) throw new CommerceError('INVALID_EVENT_TIME', 400);
  return Object.freeze({ ...event });
}
