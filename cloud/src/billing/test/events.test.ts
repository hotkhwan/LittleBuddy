import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BILLING_CONFIG } from '../config.ts';
import { eventKey, processPurchaseEvent } from '../events.ts';
import { MemoryBillingRepo } from '../repo.ts';
import { DAY_MS, NOW_MS, tx } from './helpers.ts';

test('events: a verify is applied once; the identical replay returns the stored result and writes nothing new', async () => {
  const repo = new MemoryBillingRepo();
  const first = await processPurchaseEvent(repo, tx(), { nowMs: NOW_MS, subjectId: 'device-a' });
  assert.equal(first.outcome, 'applied');
  assert.deepEqual(first.subjects, ['device-a']);
  assert.equal(first.decision?.status, 'active');
  assert.equal(repo.events.size, 1);
  assert.equal(repo.events.get(eventKey(tx(), 'device-a'))?.payload_hash.length, 64);

  const again = await processPurchaseEvent(repo, tx(), { nowMs: NOW_MS + 1000, subjectId: 'device-a' });
  assert.equal(again.outcome, 'replayed');
  assert.equal(again.httpStatus, 200);
  assert.equal(again.decision?.status, 'active');
  assert.equal(repo.events.size, 1, 'a replay is not a second event');
  assert.equal(repo.entitlements.get('device-a')?.verified_at, Math.floor(NOW_MS / 1000), 'a replay does not touch the row');
});

test('events: the same transaction with a different payload is a 409 conflict and changes nothing', async () => {
  const repo = new MemoryBillingRepo();
  await processPurchaseEvent(repo, tx(), { nowMs: NOW_MS, subjectId: 'device-a' });
  const forged = await processPurchaseEvent(repo, tx({ expiresAtMs: NOW_MS + 300 * DAY_MS }), { nowMs: NOW_MS, subjectId: 'device-a' });
  assert.equal(forged.outcome, 'conflict');
  assert.equal(forged.httpStatus, 409);
  assert.equal(forged.decision, null);
  assert.equal(repo.entitlements.get('device-a')?.period_end, Math.floor((NOW_MS + 29 * DAY_MS) / 1000));
});

test('events: out-of-order notifications do not regress; a later one moves the period forward', async () => {
  const repo = new MemoryBillingRepo();
  await processPurchaseEvent(repo, tx(), { nowMs: NOW_MS, subjectId: 'device-a' });
  // A renewal (newer event, later expiry) arrives.
  const renewal = tx({ transactionId: 'tx-2', expiresAtMs: NOW_MS + 59 * DAY_MS, eventTimeMs: NOW_MS });
  const applied = await processPurchaseEvent(repo, renewal, { nowMs: NOW_MS, subjectId: null });
  assert.equal(applied.outcome, 'applied');
  assert.equal(repo.entitlements.get('device-a')?.period_end, Math.floor((NOW_MS + 59 * DAY_MS) / 1000));
  // Then an OLDER notification (re-delivered) with the shorter expiry: stale.
  const old = tx({ transactionId: 'tx-1:redelivered', eventTimeMs: NOW_MS - 2 * DAY_MS });
  const stale = await processPurchaseEvent(repo, old, { nowMs: NOW_MS, subjectId: null });
  assert.equal(stale.outcome, 'stale');
  assert.equal(repo.entitlements.get('device-a')?.period_end, Math.floor((NOW_MS + 59 * DAY_MS) / 1000), 'the stale event did not shorten the period');
  assert.equal(repo.events.size, 3, 'stale events are still recorded');
});

test('events: a refund revokes even if its event time is older than the last applied renewal', async () => {
  const repo = new MemoryBillingRepo();
  await processPurchaseEvent(repo, tx({ eventTimeMs: NOW_MS }), { nowMs: NOW_MS, subjectId: 'device-a' });
  const refund = tx({ transactionId: 'tx-1:refund', revokedAtMs: NOW_MS - DAY_MS, eventTimeMs: NOW_MS - DAY_MS, source: 'apple_notification' });
  const result = await processPurchaseEvent(repo, refund, { nowMs: NOW_MS, subjectId: null });
  assert.equal(result.outcome, 'applied');
  assert.equal(repo.entitlements.get('device-a')?.status, 'revoked');
});

test('events: expiry -- an EXPIRED notification drops the family to free; the stored row also lapses on its own', async () => {
  const repo = new MemoryBillingRepo();
  await processPurchaseEvent(repo, tx(), { nowMs: NOW_MS, subjectId: 'device-a' });
  const later = NOW_MS + 40 * DAY_MS;
  const expired = tx({ transactionId: 'tx-1:expired', expiresAtMs: NOW_MS + 29 * DAY_MS, autoRenewing: false, eventTimeMs: later, source: 'apple_notification' });
  const result = await processPurchaseEvent(repo, expired, { nowMs: later, subjectId: null });
  assert.equal(result.decision?.status, 'expired');
  assert.equal(repo.entitlements.get('device-a')?.status, 'expired');
});

test('events: restore -- two devices under one store account share one subscription and one decision', async () => {
  const repo = new MemoryBillingRepo();
  const a = await processPurchaseEvent(repo, tx(), { nowMs: NOW_MS, subjectId: 'ipad' });
  const b = await processPurchaseEvent(repo, tx(), { nowMs: NOW_MS + 60_000, subjectId: 'iphone' });
  assert.equal(a.outcome, 'applied');
  assert.equal(b.outcome, 'applied', 'the same transaction from a second device is a new event, not a conflict');
  assert.deepEqual([...repo.entitlements.keys()].sort(), ['ipad', 'iphone']);
  assert.equal(repo.entitlements.get('iphone')?.original_transaction_id, 'orig-1');
  // A refund notification (no subject) revokes BOTH.
  const refund = tx({ transactionId: 'tx-1:refund', revokedAtMs: NOW_MS + DAY_MS, eventTimeMs: NOW_MS + DAY_MS, source: 'apple_notification' });
  const revoked = await processPurchaseEvent(repo, refund, { nowMs: NOW_MS + DAY_MS, subjectId: null });
  assert.deepEqual(revoked.subjects.sort(), ['ipad', 'iphone']);
  assert.equal(repo.entitlements.get('ipad')?.status, 'revoked');
  assert.equal(repo.entitlements.get('iphone')?.status, 'revoked');
});

test('events: a subscription cannot be spread over more devices than the cap', async () => {
  const repo = new MemoryBillingRepo();
  for (let i = 0; i < BILLING_CONFIG.maxSubjectsPerSubscription; i++) {
    const r = await processPurchaseEvent(repo, tx(), { nowMs: NOW_MS, subjectId: `device-${i}` });
    assert.equal(r.outcome, 'applied');
  }
  const extra = await processPurchaseEvent(repo, tx(), { nowMs: NOW_MS, subjectId: 'device-extra' });
  assert.equal(extra.outcome, 'rejected');
  assert.equal(extra.httpStatus, 409);
  assert.equal(repo.entitlements.has('device-extra'), false);
});

test('events: a notification for a subscription nobody presented yet is recorded but grants nobody', async () => {
  const repo = new MemoryBillingRepo();
  const r = await processPurchaseEvent(repo, tx({ source: 'apple_notification' }), { nowMs: NOW_MS, subjectId: null });
  assert.equal(r.outcome, 'applied');
  assert.deepEqual(r.subjects, []);
  assert.equal(repo.entitlements.size, 0);
});

test('events: an expired receipt restored later does not downgrade a device already covered by a live subscription', async () => {
  const repo = new MemoryBillingRepo();
  await processPurchaseEvent(repo, tx({ originalTransactionId: 'orig-new', transactionId: 'tx-new' }), { nowMs: NOW_MS, subjectId: 'ipad' });
  const dead = tx({ originalTransactionId: 'orig-old', transactionId: 'tx-old', expiresAtMs: NOW_MS - 100 * DAY_MS, autoRenewing: false, eventTimeMs: NOW_MS - 130 * DAY_MS });
  const r = await processPurchaseEvent(repo, dead, { nowMs: NOW_MS, subjectId: 'ipad' });
  assert.equal(r.outcome, 'stale');
  assert.equal(repo.entitlements.get('ipad')?.status, 'active');
  assert.equal(repo.entitlements.get('ipad')?.original_transaction_id, 'orig-new');
});

test('events: junk is rejected and recorded, never applied', async () => {
  const repo = new MemoryBillingRepo();
  const unknown = await processPurchaseEvent(repo, tx({ productId: 'little_days_gold' }), { nowMs: NOW_MS, subjectId: 'a' });
  assert.equal(unknown.outcome, 'rejected');
  const future = await processPurchaseEvent(repo, tx({ transactionId: 'tx-f', eventTimeMs: NOW_MS + DAY_MS }), { nowMs: NOW_MS, subjectId: 'a' });
  assert.equal(future.reason, 'event_time_in_future');
  assert.equal(repo.entitlements.size, 0);
});
