// Entitlements: `free` | `family_club`. The server is the only authority: a
// client never claims an entitlement, it presents a receipt and the server
// validates it (mock platform in DEV_MODE; Google Play / Apple: TODO below).
import crypto from 'node:crypto';
import { errors } from './errors.js';

export const ENTITLEMENTS = Object.freeze(['free', 'family_club']);
export const FAMILY_CLUB_PRODUCT_IDS = Object.freeze(['little_days.family_club.monthly', 'little_days.family_club.yearly']);

/**
 * @param {{store: ReturnType<import('./store.js').createStore>, config: import('./config.js').Config, now: () => number}} deps
 */
export function createEntitlements({ store, config, now }) {
  // Separate key from the parent-approval HMAC (finding L1): HKDF with its own info label.
  const mockSecret = crypto.hkdfSync('sha256', config.parentApprovalSecret || 'dev-only-mock-billing-secret', 'little-days', 'mock-billing', 32);

  /** @param {string} clientId @returns {'free'|'family_club'} */
  function get(clientId) {
    const rec = store.entitlements.get(clientId);
    if (!rec) return 'free';
    if (rec.expiresAt && Date.parse(rec.expiresAt) <= now()) return 'free';
    return ENTITLEMENTS.includes(rec.entitlement) ? rec.entitlement : 'free';
  }

  /**
   * @param {string} clientId
   * @param {'free'|'family_club'} entitlement
   * @param {{source: string, expiresAt?: string | null, receiptId?: string}} meta
   */
  function set(clientId, entitlement, meta) {
    if (!ENTITLEMENTS.includes(entitlement)) throw errors.badRequest('entitlement must be free or family_club');
    const rec = { clientId, entitlement, source: meta.source, receiptId: meta.receiptId ?? null, expiresAt: meta.expiresAt ?? null, updatedAt: new Date(now()).toISOString() };
    store.entitlements.set(clientId, rec);
    return rec;
  }

  /**
   * DEV_MODE only: grant/revoke for testing. Route layer enforces the mode.
   * @param {string} clientId
   * @param {'free'|'family_club'} entitlement
   */
  function devSet(clientId, entitlement) {
    return set(clientId, entitlement, { source: 'dev' });
  }

  /**
   * DEV_MODE only: mint a fake receipt that the validation stub accepts.
   * Shape loosely mirrors a store receipt so the client code path is real.
   * @param {string} clientId
   * @param {string} productId
   */
  function mockPurchase(clientId, productId) {
    if (!FAMILY_CLUB_PRODUCT_IDS.includes(productId)) throw errors.badRequest(`unknown productId; expected one of ${FAMILY_CLUB_PRODUCT_IDS.join(', ')}`);
    const receiptId = crypto.randomUUID();
    const purchasedAt = new Date(now()).toISOString();
    const expiresAt = new Date(now() + (productId.endsWith('yearly') ? 365 : 30) * 24 * 3600 * 1000).toISOString();
    const payload = { receiptId, clientId, productId, purchasedAt, expiresAt, platform: 'mock' };
    const signature = sign(payload);
    return { platform: 'mock', receipt: { ...payload, signature } };
  }

  /**
   * Server-side receipt validation. The client sends the platform receipt; the
   * server decides. Never trust a client-declared entitlement.
   * @param {{clientId: string, platform: string, receipt: any}} input
   */
  function validateReceipt({ clientId, platform, receipt }) {
    if (platform === 'mock') {
      if (!config.devMode) throw errors.notImplemented('mock billing is only available in DEV_MODE');
      if (!receipt || typeof receipt !== 'object') throw errors.badRequest('receipt required');
      const { signature, ...payload } = receipt;
      if (payload.clientId !== clientId) throw errors.badRequest('receipt does not belong to this clientId');
      if (!signature || !safeEqual(signature, sign(payload))) throw errors.badRequest('receipt signature invalid');
      if (store.receipts.has(payload.receiptId)) {
        // Replay of an already-consumed receipt is fine (restore purchase) as long as it is the same client.
        const prior = store.receipts.get(payload.receiptId);
        if (prior.clientId !== clientId) throw errors.badRequest('receipt already used by another client');
      }
      store.receipts.set(payload.receiptId, { clientId, platform, productId: payload.productId, validatedAt: new Date(now()).toISOString() });
      const rec = set(clientId, 'family_club', { source: 'mock_receipt', expiresAt: payload.expiresAt, receiptId: payload.receiptId });
      return { entitlement: rec.entitlement, expiresAt: rec.expiresAt, receiptId: payload.receiptId };
    }
    if (platform === 'google_play') {
      // TODO(billing): verify with the Google Play Developer API
      //   purchases.subscriptionsv2.get(packageName, token) using a service
      //   account; check subscriptionState == ACTIVE, the productId is in
      //   FAMILY_CLUB_PRODUCT_IDS, and acknowledge the purchase. Persist
      //   purchaseToken -> clientId in store.receipts to stop token sharing.
      throw errors.notImplemented('Google Play receipt validation is not wired yet');
    }
    if (platform === 'apple') {
      // TODO(billing): verify with the App Store Server API (JWS transaction
      //   info, or /verifyReceipt for legacy receipts) using the App Store
      //   Connect key; check the productId, expiresDate and revocationDate.
      //   Persist originalTransactionId -> clientId in store.receipts.
      throw errors.notImplemented('Apple IAP receipt validation is not wired yet');
    }
    throw errors.badRequest('platform must be mock, google_play or apple');
  }

  /** @param {object} payload */
  function sign(payload) {
    const canonical = JSON.stringify(payload, Object.keys(payload).sort());
    return crypto.createHmac('sha256', mockSecret).update(canonical).digest('hex');
  }

  return { get, set, devSet, mockPurchase, validateReceipt };
}

/** @param {string} a @param {string} b */
function safeEqual(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
}
