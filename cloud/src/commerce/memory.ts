import type { CommerceRepository, CommerceStore, ProcessedEvent, ProductMappingRepository, StoreProductMapping, SubscriptionSnapshot } from './types.ts';

/** Test/dev adapters. Production D1 implementations must preserve the same atomic contract. */
export class MemoryProductRepository implements ProductMappingRepository {
  constructor(private readonly products: ReadonlyArray<StoreProductMapping>) {}
  async findActiveByStoreProduct(store: CommerceStore, productId: string): Promise<StoreProductMapping | null> {
    return this.products.find((p) => p.active && p.store === store && p.productId === productId) ?? null;
  }
}

export class MemoryCommerceRepository implements CommerceRepository {
  private readonly events = new Map<string, ProcessedEvent>();
  private readonly subscriptions = new Map<string, SubscriptionSnapshot>();
  async getProcessedEvent(store: CommerceStore, eventId: string): Promise<ProcessedEvent | null> {
    return this.events.get(`${store}:${eventId}`) ?? null;
  }
  async getSubscription(store: CommerceStore, originalTransactionId: string): Promise<SubscriptionSnapshot | null> {
    return this.subscriptions.get(`${store}:${originalTransactionId}`) ?? null;
  }
  async applyEvent(event: ProcessedEvent, snapshot: SubscriptionSnapshot): Promise<'applied' | 'duplicate'> {
    const eventKey = `${event.store}:${event.eventId}`;
    if (this.events.has(eventKey)) return 'duplicate';
    this.events.set(eventKey, Object.freeze({ ...event }));
    this.subscriptions.set(`${snapshot.store}:${snapshot.originalTransactionId}`, Object.freeze({ ...snapshot }));
    return 'applied';
  }
}
