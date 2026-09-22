import {
  CommerceError, type CommerceRepository, type ProductMappingRepository, type StoreVerifier,
  type SubscriptionSnapshot, type SubscriptionStatus, type VerifiedCommerceEvent,
} from './types.ts';

export interface CommercePolicy {
  productionEnabled: boolean;
  billingEnabled: boolean;
  allowSandboxCallbacksWhenClosed: boolean;
}

export interface CommerceServiceDeps {
  repository: CommerceRepository;
  products: ProductMappingRepository;
  verifiers: ReadonlyArray<StoreVerifier>;
  clock: () => number;
  policy: CommercePolicy;
}

export interface CommerceResult {
  outcome: 'applied' | 'replayed' | 'stale' | 'ignored';
  subscription: SubscriptionSnapshot | null;
}

export class CommerceService {
  private readonly verifiers: Map<string, StoreVerifier>;
  constructor(private readonly deps: CommerceServiceDeps) {
    this.verifiers = new Map(deps.verifiers.map((v) => [v.store, v]));
  }

  async verifyPurchase(store: 'apple' | 'google', accountId: string, input: unknown): Promise<CommerceResult> {
    this.assertAccount(accountId);
    this.assertBillingOpen();
    const verifier = this.verifier(store);
    return this.process(accountId, await verifier.verifyPurchase(input));
  }

  async receiveNotification(store: 'apple' | 'google', accountId: string, input: unknown): Promise<CommerceResult> {
    this.assertAccount(accountId);
    const verifier = this.verifier(store);
    const event = await verifier.verifyNotification(input);
    if (!event) return { outcome: 'ignored', subscription: null };
    if (!this.deps.policy.productionEnabled && !(this.deps.policy.allowSandboxCallbacksWhenClosed && event.environment === 'sandbox')) {
      throw new CommerceError('PRODUCTION_CLOSED', 503);
    }
    return this.process(accountId, event);
  }

  private async process(accountId: string, event: VerifiedCommerceEvent): Promise<CommerceResult> {
    const priorEvent = await this.deps.repository.getProcessedEvent(event.store, event.eventId);
    if (priorEvent) {
      if (priorEvent.evidenceHash !== event.evidenceHash) throw new CommerceError('EVENT_REPLAY_CONFLICT', 409);
      return { outcome: 'replayed', subscription: await this.deps.repository.getSubscription(event.store, event.originalTransactionId) };
    }
    const product = await this.deps.products.findActiveByStoreProduct(event.store, event.productId);
    if (!product) throw new CommerceError('UNKNOWN_STORE_PRODUCT', 422);
    const previous = await this.deps.repository.getSubscription(event.store, event.originalTransactionId);
    if (previous && event.occurredAtMs < previous.lastEventAtMs) return { outcome: 'stale', subscription: previous };
    if (previous && previous.accountId !== accountId) throw new CommerceError('PURCHASE_OWNED_BY_ANOTHER_ACCOUNT', 409);

    const now = this.deps.clock();
    const status = transition(previous?.status, event.eventKind, event.expiresAtMs, now);
    const snapshot: SubscriptionSnapshot = {
      accountId, store: event.store, originalTransactionId: event.originalTransactionId,
      productKey: product.key, plan: product.plan, status,
      currentPeriodEndMs: event.expiresAtMs,
      autoRenewing: status === 'active' || status === 'grace',
      lastEventAtMs: event.occurredAtMs, updatedAtMs: now,
    };
    const applied = await this.deps.repository.applyEvent(
      { store: event.store, eventId: event.eventId, evidenceHash: event.evidenceHash, processedAtMs: now }, snapshot,
    );
    if (applied === 'duplicate') {
      const concurrent = await this.deps.repository.getProcessedEvent(event.store, event.eventId);
      if (concurrent?.evidenceHash !== event.evidenceHash) throw new CommerceError('EVENT_REPLAY_CONFLICT', 409);
      return { outcome: 'replayed', subscription: await this.deps.repository.getSubscription(event.store, event.originalTransactionId) };
    }
    return { outcome: 'applied', subscription: snapshot };
  }

  private verifier(store: string): StoreVerifier {
    const verifier = this.verifiers.get(store);
    if (!verifier) throw new CommerceError('STORE_NOT_CONFIGURED', 503);
    return verifier;
  }
  private assertBillingOpen(): void {
    if (!this.deps.policy.productionEnabled || !this.deps.policy.billingEnabled) throw new CommerceError('BILLING_DISABLED', 503);
  }
  private assertAccount(accountId: string): void {
    if (!/^[A-Za-z0-9_-]{8,128}$/.test(accountId)) throw new CommerceError('INVALID_ACCOUNT', 400);
  }
}

export function transition(
  previous: SubscriptionStatus | undefined,
  event: VerifiedCommerceEvent['eventKind'],
  expiresAtMs: number | null,
  nowMs: number,
): SubscriptionStatus {
  if (event === 'refunded') return 'refunded';
  if (event === 'revoked') return 'revoked';
  if (event === 'expired') return 'expired';
  if (event === 'cancelled') return expiresAtMs !== null && expiresAtMs > nowMs ? 'cancelled' : 'expired';
  if (event === 'purchased' || event === 'renewed' || event === 'restored') {
    return expiresAtMs === null || expiresAtMs <= nowMs ? 'expired' : 'active';
  }
  return previous ?? 'pending';
}
