import { describe, expect, it, vi } from 'vitest';
import {
  AppleStoreKitVerifier, CommerceError, CommerceService, GooglePlayVerifier,
  MemoryCommerceRepository, MemoryProductRepository, transition,
  type CommerceRepository, type StoreVerifier, type VerifiedCommerceEvent,
} from '../src/commerce/index.ts';

const NOW = 1_800_000_000_000;
const product = { key: 'premium_monthly', store: 'apple' as const, productId: 'com.littledays.premium.monthly', plan: 'PREMIUM' as const, active: true };

function event(overrides: Partial<VerifiedCommerceEvent> = {}): VerifiedCommerceEvent {
  return {
    store: 'apple', eventId: 'event-1', eventKind: 'purchased', productId: product.productId,
    originalTransactionId: 'original-1', transactionId: 'transaction-1', accountToken: 'account_1234',
    occurredAtMs: NOW - 100, expiresAtMs: NOW + 86_400_000, environment: 'production',
    evidenceHash: 'sha256:abc', ...overrides,
  };
}

function service(options: { event?: VerifiedCommerceEvent; production?: boolean; billing?: boolean; repo?: CommerceRepository } = {}) {
  const verified = options.event ?? event();
  const verifier: StoreVerifier = {
    store: verified.store,
    verifyPurchase: vi.fn(async () => verified),
    verifyNotification: vi.fn(async () => verified),
  };
  const repository = options.repo ?? new MemoryCommerceRepository();
  return {
    repository,
    commerce: new CommerceService({ repository, products: new MemoryProductRepository([
      product,
      { key: 'family_monthly', store: 'google', productId: 'family.monthly', plan: 'FAMILY', active: true },
    ]), verifiers: [verifier], clock: () => NOW, policy: {
      productionEnabled: options.production ?? true,
      billingEnabled: options.billing ?? true,
      allowSandboxCallbacksWhenClosed: true,
    } }),
  };
}

describe('commerce verification boundaries', () => {
  it('normalizes Apple only through its injected signed-payload source', async () => {
    const source = vi.fn(async () => event());
    const verifier = new AppleStoreKitVerifier(source, async () => null);
    await expect(verifier.verifyPurchase({ signedTransaction: 'opaque' })).resolves.toMatchObject({ store: 'apple' });
    expect(source).toHaveBeenCalledOnce();
    await expect(verifier.verifyNotification({ signedPayload: 'test' })).resolves.toBeNull();
  });

  it('rejects a cross-store or malformed verifier result', async () => {
    const apple = new AppleStoreKitVerifier(async () => event({ store: 'google' }), async () => null);
    await expect(apple.verifyPurchase({})).rejects.toMatchObject({ code: 'STORE_MISMATCH' });
    const google = new GooglePlayVerifier(async () => event({ store: 'google', eventId: '' }), async () => null);
    await expect(google.verifyPurchase({})).rejects.toMatchObject({ code: 'INVALID_VERIFIED_EVENT' });
  });

  it('supports Google Play purchase and authenticated-notification adapters without network', async () => {
    const googleEvent = event({ store: 'google', productId: 'family.monthly' });
    const verifier = new GooglePlayVerifier(async () => googleEvent, async () => googleEvent);
    await expect(verifier.verifyPurchase({ purchaseToken: 'opaque' })).resolves.toEqual(googleEvent);
    await expect(verifier.verifyNotification({ message: 'opaque' })).resolves.toEqual(googleEvent);
  });
});

describe('commerce processing', () => {
  it('maps a store product to an internal plan and applies a verified purchase', async () => {
    const { commerce } = service();
    const result = await commerce.verifyPurchase('apple', 'parent_1234', {});
    expect(result).toMatchObject({ outcome: 'applied', subscription: { plan: 'PREMIUM', status: 'active', productKey: 'premium_monthly' } });
  });

  it('makes duplicate delivery idempotent and rejects same-id changed evidence', async () => {
    const { commerce, repository } = service();
    await commerce.verifyPurchase('apple', 'parent_1234', {});
    await expect(commerce.verifyPurchase('apple', 'parent_1234', {})).resolves.toMatchObject({ outcome: 'replayed' });
    const conflict = service({ event: event({ evidenceHash: 'sha256:changed' }), repo: repository });
    await expect(conflict.commerce.verifyPurchase('apple', 'parent_1234', {})).rejects.toMatchObject({ code: 'EVENT_REPLAY_CONFLICT', httpStatus: 409 });
  });

  it('does not let an older event overwrite current subscription state', async () => {
    const { commerce, repository } = service({ event: event({ eventKind: 'renewed', occurredAtMs: NOW }) });
    await commerce.verifyPurchase('apple', 'parent_1234', {});
    const old = service({ event: event({ eventId: 'old', eventKind: 'revoked', occurredAtMs: NOW - 1 }), repo: repository });
    await expect(old.commerce.verifyPurchase('apple', 'parent_1234', {})).resolves.toMatchObject({ outcome: 'stale', subscription: { status: 'active' } });
  });

  it('prevents purchase ownership transfer between accounts', async () => {
    const { commerce, repository } = service();
    await commerce.verifyPurchase('apple', 'parent_1234', {});
    const later = service({ event: event({ eventId: 'event-2', eventKind: 'renewed', occurredAtMs: NOW }), repo: repository });
    await expect(later.commerce.verifyPurchase('apple', 'parent_5678', {})).rejects.toMatchObject({ code: 'PURCHASE_OWNED_BY_ANOTHER_ACCOUNT' });
  });

  it('rejects unknown or inactive products', async () => {
    const { commerce } = service({ event: event({ productId: 'forged.product' }) });
    await expect(commerce.verifyPurchase('apple', 'parent_1234', {})).rejects.toMatchObject({ code: 'UNKNOWN_STORE_PRODUCT' });
  });

  it('keeps purchase/restore closed until both production and billing gates open', async () => {
    await expect(service({ production: false }).commerce.verifyPurchase('apple', 'parent_1234', {})).rejects.toMatchObject({ code: 'BILLING_DISABLED' });
    await expect(service({ billing: false }).commerce.verifyPurchase('apple', 'parent_1234', {})).rejects.toMatchObject({ code: 'BILLING_DISABLED' });
  });

  it('allows only sandbox callbacks in closed production test mode', async () => {
    await expect(service({ production: false }).commerce.receiveNotification('apple', 'parent_1234', {})).rejects.toMatchObject({ code: 'PRODUCTION_CLOSED' });
    const sandbox = service({ production: false, event: event({ environment: 'sandbox' }) });
    await expect(sandbox.commerce.receiveNotification('apple', 'parent_1234', {})).resolves.toMatchObject({ outcome: 'applied' });
  });
});

describe('subscription lifecycle', () => {
  it.each([
    ['purchased', NOW + 1, 'active'], ['renewed', NOW + 1, 'active'], ['restored', NOW + 1, 'active'],
    ['cancelled', NOW + 1, 'cancelled'], ['cancelled', NOW - 1, 'expired'], ['expired', NOW + 1, 'expired'],
    ['refunded', NOW + 1, 'refunded'], ['revoked', NOW + 1, 'revoked'],
  ] as const)('%s produces %s', (kind, expiry, expected) => {
    expect(transition('active', kind, expiry, NOW)).toBe(expected);
  });

  it('processes renewal, cancellation, refund, revocation, expiration and restore in event order', async () => {
    const repo = new MemoryCommerceRepository();
    const kinds = ['renewed', 'cancelled', 'refunded', 'revoked', 'expired', 'restored'] as const;
    const expected = ['active', 'cancelled', 'refunded', 'revoked', 'expired', 'active'];
    for (let i = 0; i < kinds.length; i++) {
      const current = service({ repo, event: event({ eventId: `e-${i}`, eventKind: kinds[i], occurredAtMs: NOW + i, expiresAtMs: NOW + 1000 }) });
      const result = await current.commerce.verifyPurchase('apple', 'parent_1234', {});
      expect(result.subscription?.status).toBe(expected[i]);
    }
  });
});

describe('concurrent duplicate contract', () => {
  it('treats an atomic-repository duplicate as replay and checks its digest', async () => {
    const base = new MemoryCommerceRepository();
    const raceRepo: CommerceRepository = {
      getProcessedEvent: vi.fn()
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce({ store: 'apple', eventId: 'event-1', evidenceHash: 'sha256:abc', processedAtMs: NOW }),
      getSubscription: (...args) => base.getSubscription(...args),
      applyEvent: async () => 'duplicate',
    };
    await expect(service({ repo: raceRepo }).commerce.verifyPurchase('apple', 'parent_1234', {})).resolves.toMatchObject({ outcome: 'replayed' });
  });
});
