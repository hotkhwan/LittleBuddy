// Storage behind the billing module: an interface, an in-memory implementation
// for tests, and a D1 implementation against `schema.sql`. Agent D's D1 tables
// are `entitlements` and `purchase_events` (transaction_id UNIQUE, payload_hash,
// processed_at); the column set here is the module's expectation and is the
// integration point to reconcile.
import type { EntitlementRow, PurchaseEventRow } from './types.ts';

export interface BillingRepo {
  getEvent(transactionId: string): Promise<PurchaseEventRow | null>;
  /** Inserts unless transaction_id exists. Returns whether a row was written. */
  insertEvent(row: PurchaseEventRow): Promise<boolean>;
  getEntitlement(subjectId: string): Promise<EntitlementRow | null>;
  listEntitlementsBySubscription(originalTransactionId: string): Promise<EntitlementRow[]>;
  upsertEntitlement(row: EntitlementRow): Promise<void>;
}

export class MemoryBillingRepo implements BillingRepo {
  readonly events = new Map<string, PurchaseEventRow>();
  readonly entitlements = new Map<string, EntitlementRow>();

  async getEvent(transactionId: string): Promise<PurchaseEventRow | null> {
    return this.events.get(transactionId) ?? null;
  }

  async insertEvent(row: PurchaseEventRow): Promise<boolean> {
    if (this.events.has(row.transaction_id)) return false;
    this.events.set(row.transaction_id, { ...row });
    return true;
  }

  async getEntitlement(subjectId: string): Promise<EntitlementRow | null> {
    const row = this.entitlements.get(subjectId);
    return row ? { ...row } : null;
  }

  async listEntitlementsBySubscription(originalTransactionId: string): Promise<EntitlementRow[]> {
    return [...this.entitlements.values()].filter((r) => r.original_transaction_id === originalTransactionId).map((r) => ({ ...r }));
  }

  async upsertEntitlement(row: EntitlementRow): Promise<void> {
    this.entitlements.set(row.subject_id, { ...row });
  }
}

// -- D1 ---------------------------------------------------------------------------

/** The slice of the D1 binding this module uses (typed locally: no workers-types dependency). */
export interface D1Like {
  prepare(sql: string): D1StatementLike;
}
export interface D1StatementLike {
  bind(...values: unknown[]): D1StatementLike;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<{ results: T[] }>;
  run(): Promise<{ success: boolean; meta: { changes?: number } }>;
}

export class D1BillingRepo implements BillingRepo {
  private readonly db: D1Like;
  constructor(db: D1Like) {
    this.db = db;
  }

  async getEvent(transactionId: string): Promise<PurchaseEventRow | null> {
    return this.db.prepare('SELECT * FROM purchase_events WHERE transaction_id = ?1').bind(transactionId).first<PurchaseEventRow>();
  }

  async insertEvent(row: PurchaseEventRow): Promise<boolean> {
    const result = await this.db
      .prepare(
        'INSERT INTO purchase_events (transaction_id, store, original_transaction_id, product_id, subject_id, payload_hash, event_time_ms, source, result_json, processed_at) '
        + 'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) ON CONFLICT(transaction_id) DO NOTHING',
      )
      .bind(row.transaction_id, row.store, row.original_transaction_id, row.product_id, row.subject_id, row.payload_hash, row.event_time_ms, row.source, row.result_json, row.processed_at)
      .run();
    return (result.meta.changes ?? 0) > 0;
  }

  async getEntitlement(subjectId: string): Promise<EntitlementRow | null> {
    return this.db.prepare('SELECT * FROM entitlements WHERE subject_id = ?1').bind(subjectId).first<EntitlementRow>();
  }

  async listEntitlementsBySubscription(originalTransactionId: string): Promise<EntitlementRow[]> {
    const { results } = await this.db.prepare('SELECT * FROM entitlements WHERE original_transaction_id = ?1').bind(originalTransactionId).all<EntitlementRow>();
    return results;
  }

  async upsertEntitlement(row: EntitlementRow): Promise<void> {
    await this.db
      .prepare(
        'INSERT INTO entitlements (subject_id, entitlement_id, status, period_end, verified_at, original_transaction_id, store, product_id, last_event_time_ms, updated_at) '
        + 'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) ON CONFLICT(subject_id) DO UPDATE SET '
        + 'entitlement_id = excluded.entitlement_id, status = excluded.status, period_end = excluded.period_end, verified_at = excluded.verified_at, '
        + 'original_transaction_id = excluded.original_transaction_id, store = excluded.store, product_id = excluded.product_id, '
        + 'last_event_time_ms = excluded.last_event_time_ms, updated_at = excluded.updated_at',
      )
      .bind(row.subject_id, row.entitlement_id, row.status, row.period_end, row.verified_at, row.original_transaction_id, row.store, row.product_id, row.last_event_time_ms, row.updated_at)
      .run();
  }
}
