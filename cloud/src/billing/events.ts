// Purchase-event processing: idempotency, ordering, and the entitlement upsert.
//
//   * Every store event is recorded once under an event key (`eventKey`). A
//     replay with the same payload hash returns the stored result; the same
//     key with a DIFFERENT payload is a 409 conflict and changes nothing.
//   * Events are applied in store order (`eventTimeMs`) per subscription: a
//     late-arriving older event is recorded as `stale` and does not regress
//     the entitlement. A revocation always applies -- money going back is terminal.
//   * One subscription (original_transaction_id) may back several subjects
//     (devices) up to `maxSubjectsPerSubscription`; a store notification (no
//     subject) updates every subject on that subscription.
import { BILLING_CONFIG, productById } from './config.ts';
import { canonicalJson, sha256Hex, utf8 } from './crypto/encoding.ts';
import { decideEntitlement } from './decision.ts';
import type { BillingRepo } from './repo.ts';
import type { EntitlementDecision, EntitlementRow, NormalizedTransaction, ProcessResult, PurchaseEventRow } from './types.ts';

/**
 * The idempotency key. A device verify is keyed per (store, transaction,
 * subject) so a second device restoring the same transaction is a new event
 * that links a new subject, while the same device retrying is a replay. Store
 * notifications carry their own unique ids inside `transactionId`.
 */
export function eventKey(tx: NormalizedTransaction, subjectId: string | null): string {
  return subjectId === null ? `${tx.store}:${tx.transactionId}` : `verify:${tx.store}:${tx.transactionId}:${subjectId}`;
}

/** Hash of the facts that matter; excludes wall-clock noise like fetch time for notifications. */
export async function payloadHash(tx: NormalizedTransaction, subjectId: string | null): Promise<string> {
  const facts = {
    store: tx.store,
    productId: tx.productId,
    transactionId: tx.transactionId,
    originalTransactionId: tx.originalTransactionId,
    expiresAtMs: tx.expiresAtMs,
    revokedAtMs: tx.revokedAtMs,
    gracePeriodExpiresAtMs: tx.gracePeriodExpiresAtMs,
    subjectId,
  };
  return sha256Hex(utf8(canonicalJson(facts)));
}

export interface ProcessOptions {
  nowMs: number;
  /** The clientId presenting a receipt; null for a store notification. */
  subjectId: string | null;
}

export async function processPurchaseEvent(repo: BillingRepo, tx: NormalizedTransaction, options: ProcessOptions): Promise<ProcessResult> {
  const { nowMs, subjectId } = options;
  const key = eventKey(tx, subjectId);
  const hash = await payloadHash(tx, subjectId);

  // -- idempotency --------------------------------------------------------------
  const existing = await repo.getEvent(key);
  if (existing) {
    if (existing.payload_hash === hash) {
      const stored = JSON.parse(existing.result_json) as ProcessResult;
      return { ...stored, outcome: 'replayed', reason: `replay_of_${stored.outcome}`, httpStatus: stored.httpStatus === 409 ? 409 : 200 };
    }
    return { outcome: 'conflict', decision: null, subjects: [], reason: 'same_transaction_different_payload', httpStatus: 409 };
  }

  // -- validation --------------------------------------------------------------------
  const rejected = (reason: string, status = 400): ProcessResult => ({ outcome: 'rejected', decision: null, subjects: [], reason, httpStatus: status });
  if (!productById(tx.productId)) return await record(repo, key, hash, tx, subjectId, nowMs, rejected('unknown_product'));
  if (tx.eventTimeMs - nowMs > BILLING_CONFIG.maxFutureSkewMs) return await record(repo, key, hash, tx, subjectId, nowMs, rejected('event_time_in_future'));
  if (!tx.originalTransactionId) return await record(repo, key, hash, tx, subjectId, nowMs, rejected('missing_original_transaction_id'));

  const decision = decideEntitlement(tx, nowMs);
  const isRevocation = decision.status === 'revoked';

  // -- who is affected ------------------------------------------------------------------
  const linked = await repo.listEntitlementsBySubscription(tx.originalTransactionId);
  const subjects = new Set(linked.map((r) => r.subject_id));
  if (subjectId !== null) {
    if (!subjects.has(subjectId) && subjects.size >= BILLING_CONFIG.maxSubjectsPerSubscription) {
      return await record(repo, key, hash, tx, subjectId, nowMs, rejected('too_many_subjects_for_subscription', 409));
    }
    subjects.add(subjectId);
  }
  if (subjects.size === 0) {
    // A notification for a subscription nobody has presented yet: record it so a
    // later verify sees the event history, but there is no row to update.
    return await record(repo, key, hash, tx, subjectId, nowMs, { outcome: 'applied', decision, subjects: [], reason: 'no_subject_yet', httpStatus: 200 });
  }

  // -- ordering + upsert ----------------------------------------------------------------
  const written: string[] = [];
  let staleFor = 0;
  for (const subject of subjects) {
    const current = linked.find((r) => r.subject_id === subject) ?? (await repo.getEntitlement(subject));
    if (current && current.original_transaction_id === tx.originalTransactionId && !isRevocation && tx.eventTimeMs < current.last_event_time_ms) {
      staleFor += 1;
      continue;
    }
    if (current && current.original_transaction_id !== tx.originalTransactionId && current.status !== 'expired' && current.status !== 'none' && current.status !== 'revoked'
        && current.period_end > Math.floor(nowMs / 1000) && !(decision.status === 'active' || decision.status === 'grace')) {
      // A subject already covered by a live subscription is not downgraded by a
      // dead one presented later (e.g. restoring an old, expired receipt).
      staleFor += 1;
      continue;
    }
    await repo.upsertEntitlement(rowFor(subject, decision, tx, nowMs));
    written.push(subject);
  }

  // Google upgrade/downgrade: the replaced token's rows lapse.
  if (tx.supersedesOriginalTransactionId && (decision.status === 'active' || decision.status === 'grace')) {
    for (const old of await repo.listEntitlementsBySubscription(tx.supersedesOriginalTransactionId)) {
      if (!subjects.has(old.subject_id)) {
        await repo.upsertEntitlement({ ...old, status: 'expired', period_end: Math.floor(nowMs / 1000), last_event_time_ms: tx.eventTimeMs, updated_at: Math.floor(nowMs / 1000) });
      }
    }
  }

  const result: ProcessResult = written.length > 0
    ? { outcome: 'applied', decision, subjects: written, reason: decision.reason, httpStatus: 200 }
    : { outcome: 'stale', decision, subjects: [], reason: staleFor > 0 ? 'older_than_applied_event' : 'nothing_to_write', httpStatus: 200 };
  return await record(repo, key, hash, tx, subjectId, nowMs, result);
}

function rowFor(subject: string, decision: EntitlementDecision, tx: NormalizedTransaction, nowMs: number): EntitlementRow {
  const nowS = Math.floor(nowMs / 1000);
  return {
    subject_id: subject,
    entitlement_id: decision.entitlementId,
    status: decision.status,
    period_end: decision.periodEnd,
    verified_at: nowS,
    original_transaction_id: tx.originalTransactionId,
    store: tx.store,
    product_id: tx.productId,
    last_event_time_ms: tx.eventTimeMs,
    updated_at: nowS,
  };
}

async function record(repo: BillingRepo, key: string, hash: string, tx: NormalizedTransaction, subjectId: string | null, nowMs: number, result: ProcessResult): Promise<ProcessResult> {
  const row: PurchaseEventRow = {
    transaction_id: key,
    store: tx.store,
    original_transaction_id: tx.originalTransactionId,
    product_id: tx.productId,
    subject_id: subjectId,
    payload_hash: hash,
    event_time_ms: tx.eventTimeMs,
    source: tx.source,
    result_json: JSON.stringify(result),
    processed_at: Math.floor(nowMs / 1000),
  };
  const inserted = await repo.insertEvent(row);
  if (!inserted) {
    // Lost a race with an identical event: replay whatever won.
    const winner = await repo.getEvent(key);
    if (winner && winner.payload_hash === hash) {
      const stored = JSON.parse(winner.result_json) as ProcessResult;
      return { ...stored, outcome: 'replayed', reason: `replay_of_${stored.outcome}` };
    }
    return { outcome: 'conflict', decision: null, subjects: [], reason: 'same_transaction_different_payload', httpStatus: 409 };
  }
  return result;
}
