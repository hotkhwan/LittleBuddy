// Google Play: purchases.subscriptionsv2.get is the source of truth for a
// purchase token; RTDN (Pub/Sub push) only tells us WHEN to look again. The
// device's purchase token is never believed on its own. Secrets needed (see
// docs/FAMILY_CLUB_BILLING.md): GOOGLE_PACKAGE_NAME,
// GOOGLE_SERVICE_ACCOUNT_JSON (client_email, private_key, token_uri; the
// account needs "View financial data" + "Manage orders and subscriptions" in
// Play Console), GOOGLE_RTDN_TOKEN (shared secret in the push URL) and/or
// GOOGLE_RTDN_AUDIENCE for OIDC push authentication.
import { BILLING_CONFIG } from './config.ts';
import { base64Decode, fromUtf8, timingSafeEqualStrings } from './crypto/encoding.ts';
import { importPkcs8, signJws } from './crypto/jws.ts';
import type { NormalizedTransaction } from './types.ts';

export interface GoogleConfig {
  packageName: string;
  serviceAccount: { client_email: string; private_key: string; token_uri?: string };
  /** Shared secret expected as `?token=` on the RTDN push URL. */
  rtdnToken?: string;
}

export interface GoogleDeps {
  fetch: typeof fetch;
  now: () => number;
  /** Optional: verify a Pub/Sub OIDC bearer (aud/iss/exp). Injected; not implemented here. */
  verifyPushBearer?: (bearer: string) => Promise<boolean>;
}

/** The parts of a SubscriptionPurchaseV2 this module reads. */
export interface SubscriptionPurchaseV2 {
  kind?: string;
  startTime?: string;
  subscriptionState?: string;
  latestOrderId?: string;
  linkedPurchaseToken?: string;
  acknowledgementState?: string;
  testPurchase?: unknown;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  lineItems?: Array<{
    productId?: string;
    expiryTime?: string;
    autoRenewingPlan?: { autoRenewEnabled?: boolean };
    prepaidPlan?: unknown;
  }>;
}

/** RTDN subscriptionNotification.notificationType values. */
export const GOOGLE_NOTIFICATION = Object.freeze({
  1: 'SUBSCRIPTION_RECOVERED', 2: 'SUBSCRIPTION_RENEWED', 3: 'SUBSCRIPTION_CANCELED', 4: 'SUBSCRIPTION_PURCHASED',
  5: 'SUBSCRIPTION_ON_HOLD', 6: 'SUBSCRIPTION_IN_GRACE_PERIOD', 7: 'SUBSCRIPTION_RESTARTED',
  8: 'SUBSCRIPTION_PRICE_CHANGE_CONFIRMED', 9: 'SUBSCRIPTION_DEFERRED', 10: 'SUBSCRIPTION_PAUSED',
  11: 'SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED', 12: 'SUBSCRIPTION_REVOKED', 13: 'SUBSCRIPTION_EXPIRED',
  20: 'SUBSCRIPTION_PENDING_PURCHASE_CANCELED',
} as Record<number, string>);

export interface RtdnMessage {
  packageName: string;
  eventTimeMs: number;
  messageId: string;
  subscription: { purchaseToken: string; subscriptionId: string; notificationType: number; name: string } | null;
  voided: { purchaseToken: string; orderId: string; productType: number; refundType: number } | null;
  test: boolean;
}

export class GoogleVerifier {
  readonly config: GoogleConfig;
  readonly deps: GoogleDeps;
  private cachedToken: { value: string; expiresAtMs: number } | null = null;

  constructor(config: GoogleConfig, deps: GoogleDeps) {
    this.config = config;
    this.deps = deps;
  }

  /** The verify path for a device receipt: token -> subscriptionsv2 -> normalized. */
  async verifyDevicePayload(payload: { purchaseToken?: unknown; packageName?: unknown }): Promise<NormalizedTransaction> {
    const token = typeof payload.purchaseToken === 'string' ? payload.purchaseToken : '';
    if (!/^[A-Za-z0-9._-]{16,512}$/.test(token)) throw new Error('google: purchaseToken required');
    if (typeof payload.packageName === 'string' && payload.packageName !== this.config.packageName) throw new Error('google: packageName mismatch');
    const sub = await this.getSubscriptionV2(token);
    return this.normalize(sub, token, 'verify', this.deps.now());
  }

  async getSubscriptionV2(purchaseToken: string): Promise<SubscriptionPurchaseV2> {
    const accessToken = await this.accessToken();
    const url = `${BILLING_CONFIG.googleApiBase}/applications/${encodeURIComponent(this.config.packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
    const response = await this.deps.fetch(url, { method: 'GET', headers: { authorization: `Bearer ${accessToken}`, accept: 'application/json' } });
    if (response.status === 404 || response.status === 410) throw new Error('google: purchase token unknown');
    if (response.status === 401 || response.status === 403) throw new Error('google: api credentials rejected');
    if (!response.ok) throw new Error(`google: api ${response.status}`);
    return (await response.json()) as SubscriptionPurchaseV2;
  }

  /**
   * Play refunds an unacknowledged subscription after 3 days. The backend
   * acknowledges AFTER it has verified and granted -- never the device.
   * purchases.subscriptions.acknowledge (v1 path, still the documented way).
   */
  async acknowledge(productId: string, purchaseToken: string): Promise<boolean> {
    const accessToken = await this.accessToken();
    const url = `${BILLING_CONFIG.googleApiBase}/applications/${encodeURIComponent(this.config.packageName)}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
    const response = await this.deps.fetch(url, { method: 'POST', headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' }, body: '{}' });
    return response.ok;
  }

  normalize(sub: SubscriptionPurchaseV2, purchaseToken: string, source: NormalizedTransaction['source'], eventTimeMs: number, voided = false): NormalizedTransaction {
    const item = sub.lineItems?.[0];
    if (!item?.productId) throw new Error('google: subscription has no line item');
    const expiresAtMs = item.expiryTime ? Date.parse(item.expiryTime) : null;
    const state = sub.subscriptionState ?? 'SUBSCRIPTION_STATE_UNSPECIFIED';
    const purchaseTimeMs = sub.startTime ? Date.parse(sub.startTime) : eventTimeMs;

    // Play's states, folded onto the decision's inputs. Grace: Play extends
    // expiryTime to the end of the grace period, so we pass it as the grace end.
    let effectiveExpiry = expiresAtMs;
    let grace: number | null = null;
    let revokedAtMs: number | null = null;
    let autoRenewing: boolean | null = item.autoRenewingPlan ? item.autoRenewingPlan.autoRenewEnabled === true : null;
    switch (state) {
      case 'SUBSCRIPTION_STATE_ACTIVE':
      case 'SUBSCRIPTION_STATE_CANCELED':
        break;
      case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD':
        grace = expiresAtMs;
        effectiveExpiry = Math.min(expiresAtMs ?? eventTimeMs, eventTimeMs); // past the paid period; grace carries access
        break;
      case 'SUBSCRIPTION_STATE_ON_HOLD':
      case 'SUBSCRIPTION_STATE_PAUSED':
      case 'SUBSCRIPTION_STATE_EXPIRED':
        // Access is not granted during hold/pause; treat the period as over now,
        // and no fallback grace: Play's own grace period has already run out.
        effectiveExpiry = Math.min(expiresAtMs ?? eventTimeMs, eventTimeMs);
        autoRenewing = false;
        break;
      case 'SUBSCRIPTION_STATE_PENDING':
      case 'SUBSCRIPTION_STATE_UNSPECIFIED':
      default:
        effectiveExpiry = null;
        break;
    }
    if (voided) revokedAtMs = eventTimeMs;

    return {
      store: 'google',
      productId: item.productId,
      transactionId: sub.latestOrderId ? String(sub.latestOrderId) : `${purchaseToken.slice(0, 24)}:${eventTimeMs}`,
      originalTransactionId: purchaseToken,
      purchaseTimeMs,
      expiresAtMs: effectiveExpiry,
      revokedAtMs,
      gracePeriodExpiresAtMs: grace,
      autoRenewing,
      environment: sub.testPurchase ? 'sandbox' : 'production',
      accountToken: sub.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
      eventTimeMs,
      source,
      supersedesOriginalTransactionId: sub.linkedPurchaseToken ?? null,
    };
  }

  // -- RTDN (Pub/Sub push) ------------------------------------------------------

  /** Is this push request from our Pub/Sub subscription? Shared token and/or OIDC. */
  async authenticatePush(url: URL, authorizationHeader: string | null): Promise<boolean> {
    if (this.config.rtdnToken) {
      const provided = url.searchParams.get('token') ?? '';
      if (provided && timingSafeEqualStrings(provided, this.config.rtdnToken)) return true;
    }
    if (this.deps.verifyPushBearer && authorizationHeader?.startsWith('Bearer ')) {
      return this.deps.verifyPushBearer(authorizationHeader.slice('Bearer '.length));
    }
    return false;
  }

  parseRtdn(body: unknown): RtdnMessage {
    const message = (body as { message?: { data?: unknown; messageId?: unknown } } | null)?.message;
    if (!message || typeof message.data !== 'string') throw new Error('google: pubsub message.data required');
    const decoded = JSON.parse(fromUtf8(base64Decode(message.data))) as {
      version?: string; packageName?: string; eventTimeMillis?: string | number;
      subscriptionNotification?: { version?: string; notificationType?: number; purchaseToken?: string; subscriptionId?: string };
      voidedPurchaseNotification?: { purchaseToken?: string; orderId?: string; productType?: number; refundType?: number };
      testNotification?: unknown;
    };
    if (decoded.packageName !== this.config.packageName) throw new Error('google: rtdn packageName mismatch');
    const eventTimeMs = Number(decoded.eventTimeMillis ?? this.deps.now());
    const s = decoded.subscriptionNotification;
    const v = decoded.voidedPurchaseNotification;
    return {
      packageName: decoded.packageName,
      eventTimeMs: Number.isFinite(eventTimeMs) ? eventTimeMs : this.deps.now(),
      messageId: String(message.messageId ?? ''),
      subscription: s && typeof s.purchaseToken === 'string'
        ? { purchaseToken: s.purchaseToken, subscriptionId: String(s.subscriptionId ?? ''), notificationType: Number(s.notificationType ?? 0), name: GOOGLE_NOTIFICATION[Number(s.notificationType ?? 0)] ?? 'UNKNOWN' }
        : null,
      voided: v && typeof v.purchaseToken === 'string'
        ? { purchaseToken: v.purchaseToken, orderId: String(v.orderId ?? ''), productType: Number(v.productType ?? 0), refundType: Number(v.refundType ?? 0) }
        : null,
      test: decoded.testNotification !== undefined,
    };
  }

  /** RTDN -> a fresh look at the token -> normalized (revoked for voided purchases). */
  async transactionForRtdn(rtdn: RtdnMessage): Promise<NormalizedTransaction | null> {
    if (rtdn.test) return null;
    if (rtdn.voided) {
      const sub = await this.getSubscriptionV2(rtdn.voided.purchaseToken);
      const tx = this.normalize(sub, rtdn.voided.purchaseToken, 'google_rtdn', rtdn.eventTimeMs, true);
      tx.transactionId = `${rtdn.voided.orderId || tx.transactionId}:voided`;
      return tx;
    }
    if (rtdn.subscription) {
      const sub = await this.getSubscriptionV2(rtdn.subscription.purchaseToken);
      const revoked = rtdn.subscription.notificationType === 12; // SUBSCRIPTION_REVOKED
      const tx = this.normalize(sub, rtdn.subscription.purchaseToken, 'google_rtdn', rtdn.eventTimeMs, revoked);
      // Several notifications can share latestOrderId (e.g. CANCELED after RENEWED):
      // key the event by the message so each is recorded once, in order.
      tx.transactionId = `${tx.transactionId}:${rtdn.subscription.notificationType}:${rtdn.messageId || rtdn.eventTimeMs}`;
      return tx;
    }
    return null;
  }

  // -- OAuth2 service account ---------------------------------------------------------

  async accessToken(): Promise<string> {
    const nowMs = this.deps.now();
    if (this.cachedToken && this.cachedToken.expiresAtMs - 60_000 > nowMs) return this.cachedToken.value;
    const tokenUri = this.config.serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token';
    const key = await importPkcs8(this.config.serviceAccount.private_key, 'RS256');
    const nowS = Math.floor(nowMs / 1000);
    const assertion = await signJws(
      { typ: 'JWT' },
      { iss: this.config.serviceAccount.client_email, scope: BILLING_CONFIG.googleScope, aud: tokenUri, iat: nowS, exp: nowS + 3600 },
      key,
      'RS256',
    );
    const form = new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion });
    const response = await this.deps.fetch(tokenUri, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: form.toString() });
    if (!response.ok) throw new Error(`google: token endpoint ${response.status}`);
    const body = (await response.json()) as { access_token?: string; expires_in?: number };
    if (!body.access_token) throw new Error('google: token endpoint returned no access_token');
    this.cachedToken = { value: body.access_token, expiresAtMs: nowMs + (body.expires_in ?? 3600) * 1000 };
    return body.access_token;
  }
}
