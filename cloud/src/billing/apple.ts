// Apple: App Store Server API v2 signed transactions (JWS with x5c) and App
// Store Server Notifications V2. Verification is local (pinned Apple root,
// Apple OIDs, ES256), the lookup is one injectable `fetch`. Secrets needed
// (see docs/FAMILY_CLUB_BILLING.md): APPLE_ISSUER_ID, APPLE_KEY_ID,
// APPLE_IAP_PRIVATE_KEY_P8 (an In-App Purchase key from App Store Connect),
// APPLE_BUNDLE_ID, APPLE_ENVIRONMENT.
import { BILLING_CONFIG } from './config.ts';
import { importPkcs8, signJws, verifyJwsWithX5c } from './crypto/jws.ts';
import type { NormalizedTransaction } from './types.ts';

export interface AppleConfig {
  bundleId: string;
  issuerId: string;
  keyId: string;
  /** PEM PKCS#8 of the App Store Connect In-App Purchase key. */
  privateKeyPem: string;
  environment: 'production' | 'sandbox';
  /** Lower-case hex SHA-256 of the DER root to trust. Defaults to Apple Root CA - G3. */
  trustedRootSha256Hex?: string;
  /** Test hook: override the OIDs the chain must carry (defaults to Apple's). */
  requiredLeafOids?: string[];
  requiredIntermediateOids?: string[];
}

export interface AppleDeps {
  fetch: typeof fetch;
  now: () => number;
}

/** Fields of JWSTransactionDecodedPayload this module reads. */
export interface AppleTransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number;
  originalPurchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  revocationReason?: number;
  type: string;
  environment: 'Sandbox' | 'Production';
  signedDate: number;
  appAccountToken?: string;
  inAppOwnershipType?: string;
}

export interface AppleRenewalPayload {
  originalTransactionId?: string;
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
  expirationIntent?: number;
  signedDate?: number;
}

/** Notification types that mean the money went back. */
const REVOKING_NOTIFICATIONS = new Set(['REFUND', 'REVOKE']);
/** Notification types after which no fallback grace applies: Apple has finished retrying. */
const NO_GRACE_NOTIFICATIONS = new Set(['EXPIRED', 'GRACE_PERIOD_EXPIRED']);

export class AppleVerifier {
  readonly config: AppleConfig;
  readonly deps: AppleDeps;

  constructor(config: AppleConfig, deps: AppleDeps) {
    this.config = config;
    this.deps = deps;
  }

  private chainPolicy() {
    return {
      trustedRootSha256Hex: this.config.trustedRootSha256Hex ?? BILLING_CONFIG.appleRootCaG3Sha256Hex,
      requiredLeafOids: this.config.requiredLeafOids ?? [BILLING_CONFIG.appleLeafOid],
      requiredIntermediateOids: this.config.requiredIntermediateOids ?? [BILLING_CONFIG.appleIntermediateOid],
    };
  }

  /** Verifies any Apple signed payload (transaction, renewal info, notification). */
  async verifySignedPayload(jws: string): Promise<{ ok: true; payload: Record<string, unknown> } | { ok: false; reason: string }> {
    const result = await verifyJwsWithX5c(jws, this.chainPolicy(), this.deps.now());
    if (!result.ok || !result.payload) return { ok: false, reason: result.reason };
    return { ok: true, payload: result.payload };
  }

  /** A verified signed transaction -> the store-neutral shape. */
  normalizeTransaction(tx: AppleTransactionPayload, renewal: AppleRenewalPayload | null, source: NormalizedTransaction['source'], notificationType?: string): NormalizedTransaction {
    if (tx.bundleId !== this.config.bundleId) throw new Error('apple: bundleId mismatch');
    if (tx.type !== 'Auto-Renewable Subscription') throw new Error(`apple: unsupported transaction type ${tx.type}`);
    const revoked = typeof tx.revocationDate === 'number'
      ? tx.revocationDate
      : notificationType && REVOKING_NOTIFICATIONS.has(notificationType)
        ? tx.signedDate
        : null;
    const autoRenewing = notificationType && NO_GRACE_NOTIFICATIONS.has(notificationType)
      ? false
      : renewal ? renewal.autoRenewStatus === 1 : null;
    return {
      store: 'apple',
      productId: tx.productId,
      transactionId: String(tx.transactionId),
      originalTransactionId: String(tx.originalTransactionId),
      purchaseTimeMs: tx.purchaseDate,
      expiresAtMs: typeof tx.expiresDate === 'number' ? tx.expiresDate : null,
      revokedAtMs: revoked,
      gracePeriodExpiresAtMs: typeof renewal?.gracePeriodExpiresDate === 'number' ? renewal.gracePeriodExpiresDate : null,
      autoRenewing,
      environment: tx.environment === 'Production' ? 'production' : 'sandbox',
      accountToken: tx.appAccountToken ?? null,
      eventTimeMs: tx.signedDate,
      source,
    };
  }

  /**
   * The verify path for a device receipt. StoreKit 2 devices send the signed
   * transaction JWS; the StoreKit 1 iOS plugin sends only a transaction id,
   * which is looked up with the App Store Server API (which answers with a
   * signed transaction, verified the same way). Either way Apple's signature
   * is what is believed, never the device.
   */
  async verifyDevicePayload(payload: { signedTransaction?: unknown; transactionId?: unknown }): Promise<NormalizedTransaction> {
    let signed: string | null = typeof payload.signedTransaction === 'string' ? payload.signedTransaction : null;
    let renewal: AppleRenewalPayload | null = null;
    if (!signed) {
      const transactionId = typeof payload.transactionId === 'string' ? payload.transactionId : '';
      if (!/^[0-9]{1,32}$/.test(transactionId)) throw new Error('apple: transactionId required');
      const info = await this.lookupTransaction(transactionId);
      signed = info.signedTransactionInfo;
      renewal = info.renewal;
    }
    const verified = await this.verifySignedPayload(signed);
    if (!verified.ok) throw new Error(`apple: ${verified.reason}`);
    const tx = verified.payload as unknown as AppleTransactionPayload;
    if (this.config.environment === 'production' && tx.environment !== 'Production') throw new Error('apple: sandbox transaction in production');
    return this.normalizeTransaction(tx, renewal, 'verify');
  }

  /** GET /inApps/v1/transactions/{transactionId}, authenticated with a client JWT. */
  async lookupTransaction(transactionId: string): Promise<{ signedTransactionInfo: string; renewal: AppleRenewalPayload | null }> {
    const token = await this.clientJwt();
    const base = BILLING_CONFIG.appleApiBase[this.config.environment];
    const response = await this.deps.fetch(`${base}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, {
      method: 'GET',
      headers: { authorization: `Bearer ${token}`, accept: 'application/json' },
    });
    if (response.status === 404) throw new Error('apple: transaction not found');
    if (response.status === 401) throw new Error('apple: api credentials rejected');
    if (!response.ok) throw new Error(`apple: api ${response.status}`);
    const body = (await response.json()) as { signedTransactionInfo?: unknown };
    if (typeof body.signedTransactionInfo !== 'string') throw new Error('apple: api reply lacks signedTransactionInfo');
    return { signedTransactionInfo: body.signedTransactionInfo, renewal: null };
  }

  /** The App Store Server API bearer: ES256, 20-minute JWT keyed by the IAP key. */
  async clientJwt(): Promise<string> {
    const key = await importPkcs8(this.config.privateKeyPem, 'ES256');
    const nowS = Math.floor(this.deps.now() / 1000);
    return signJws(
      { kid: this.config.keyId, typ: 'JWT' },
      { iss: this.config.issuerId, iat: nowS, exp: nowS + 20 * 60, aud: 'appstoreconnect-v1', bid: this.config.bundleId },
      key,
      'ES256',
    );
  }

  /**
   * App Store Server Notifications V2: `{signedPayload}`. The outer JWS is
   * verified, then the inner signedTransactionInfo / signedRenewalInfo, each
   * against the same pinned chain policy. Returns the normalized transaction
   * plus the notification type so the caller can log it.
   */
  async parseNotification(body: unknown): Promise<{ notificationType: string; subtype: string | null; notificationUUID: string; transaction: NormalizedTransaction | null }> {
    const signedPayload = (body as { signedPayload?: unknown } | null)?.signedPayload;
    if (typeof signedPayload !== 'string') throw new Error('apple: signedPayload required');
    const outer = await this.verifySignedPayload(signedPayload);
    if (!outer.ok) throw new Error(`apple: notification ${outer.reason}`);
    const decoded = outer.payload as {
      notificationType?: string; subtype?: string; notificationUUID?: string;
      data?: { bundleId?: string; environment?: string; signedTransactionInfo?: string; signedRenewalInfo?: string };
    };
    const notificationType = String(decoded.notificationType ?? '');
    const notificationUUID = String(decoded.notificationUUID ?? '');
    if (!notificationType || !notificationUUID) throw new Error('apple: notification lacks type/uuid');
    const data = decoded.data ?? {};
    if (data.bundleId && data.bundleId !== this.config.bundleId) throw new Error('apple: notification bundleId mismatch');
    if (notificationType === 'TEST') return { notificationType, subtype: decoded.subtype ?? null, notificationUUID, transaction: null };
    if (typeof data.signedTransactionInfo !== 'string') throw new Error('apple: notification lacks signedTransactionInfo');

    const txVerified = await this.verifySignedPayload(data.signedTransactionInfo);
    if (!txVerified.ok) throw new Error(`apple: transaction ${txVerified.reason}`);
    let renewal: AppleRenewalPayload | null = null;
    if (typeof data.signedRenewalInfo === 'string') {
      const renewalVerified = await this.verifySignedPayload(data.signedRenewalInfo);
      if (!renewalVerified.ok) throw new Error(`apple: renewal ${renewalVerified.reason}`);
      renewal = renewalVerified.payload as AppleRenewalPayload;
    }
    const tx = this.normalizeTransaction(txVerified.payload as unknown as AppleTransactionPayload, renewal, 'apple_notification', notificationType);
    // A notification's ordering key is the notification's signedDate, which is
    // later than the transaction's own signedDate for re-sent transactions.
    const outerSigned = (outer.payload as { signedDate?: number }).signedDate;
    if (typeof outerSigned === 'number' && outerSigned > tx.eventTimeMs) tx.eventTimeMs = outerSigned;
    // Notifications about the same transaction (e.g. DID_CHANGE_RENEWAL_STATUS
    // after SUBSCRIBED) must not collide on transaction_id: key by the UUID.
    tx.transactionId = `${tx.transactionId}:${notificationUUID}`;
    return { notificationType, subtype: decoded.subtype ?? null, notificationUUID, transaction: tx };
  }
}
