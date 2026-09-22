import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decideEntitlement } from '../decision.ts';
import { decodeJws } from '../crypto/jws.ts';
import { GoogleVerifier, type SubscriptionPurchaseV2 } from '../google.ts';
import { DAY_MS, NOW_MS, clock, fakeFetch, rsaPkcs8Pem } from './helpers.ts';

const PKG = 'com.joinanny.littledays';
const TOKEN = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEF';

function subscription(overrides: Partial<SubscriptionPurchaseV2> = {}, item: Partial<NonNullable<SubscriptionPurchaseV2['lineItems']>[number]> = {}): SubscriptionPurchaseV2 {
  return {
    kind: 'androidpublisher#subscriptionPurchaseV2',
    startTime: new Date(NOW_MS - DAY_MS).toISOString(),
    subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
    latestOrderId: 'GPA.1234-5678-9012-34567',
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
    lineItems: [{ productId: 'little_days_family_monthly', expiryTime: new Date(NOW_MS + 29 * DAY_MS).toISOString(), autoRenewingPlan: { autoRenewEnabled: true }, ...item }],
    ...overrides,
  };
}

async function verifier(routes: Parameters<typeof fakeFetch>[0], rtdnToken = 'push-secret') {
  const key = await rsaPkcs8Pem();
  const { fetch: f, calls } = fakeFetch([
    { match: (url) => url === 'https://oauth2.googleapis.com/token', status: 200, body: { access_token: 'ya29.test', expires_in: 3600 } },
    ...routes,
  ]);
  const v = new GoogleVerifier({ packageName: PKG, serviceAccount: { client_email: 'svc@project.iam.gserviceaccount.com', private_key: key }, rtdnToken }, { fetch: f, now: clock().now });
  return { v, calls };
}

test('google: a purchase token is looked up with subscriptionsv2 using a service-account RS256 assertion', async () => {
  const { v, calls } = await verifier([
    { match: (url) => url.includes(`/purchases/subscriptionsv2/tokens/${TOKEN}`), status: 200, body: subscription() },
  ]);
  const tx = await v.verifyDevicePayload({ purchaseToken: TOKEN, packageName: PKG });
  assert.equal(tx.store, 'google');
  assert.equal(tx.productId, 'little_days_family_monthly');
  assert.equal(tx.transactionId, 'GPA.1234-5678-9012-34567');
  assert.equal(tx.originalTransactionId, TOKEN);
  assert.equal(tx.expiresAtMs, NOW_MS + 29 * DAY_MS);
  assert.equal(decideEntitlement(tx, NOW_MS).status, 'active');

  assert.equal(calls.length, 2);
  const tokenCall = calls[0];
  const form = new URLSearchParams(String(tokenCall.init?.body));
  assert.equal(form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
  const assertion = decodeJws(form.get('assertion') ?? '');
  assert.equal(assertion.header.alg, 'RS256');
  assert.equal(assertion.payload.iss, 'svc@project.iam.gserviceaccount.com');
  assert.equal(assertion.payload.scope, 'https://www.googleapis.com/auth/androidpublisher');
  assert.ok(calls[1].url.startsWith(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PKG}/`));
  assert.equal((calls[1].init?.headers as Record<string, string>).authorization, 'Bearer ya29.test');

  // The token is cached for the next call.
  await v.verifyDevicePayload({ purchaseToken: TOKEN });
  assert.equal(calls.length, 3);
});

test('google: a malformed token or a foreign package never reaches the network; unknown tokens are rejected', async () => {
  const { v, calls } = await verifier([{ match: (url) => url.includes('/tokens/'), status: 404, body: {} }]);
  await assert.rejects(v.verifyDevicePayload({ purchaseToken: 'short' }), /purchaseToken required/);
  await assert.rejects(v.verifyDevicePayload({ purchaseToken: TOKEN, packageName: 'com.other' }), /packageName mismatch/);
  assert.equal(calls.length, 0);
  await assert.rejects(v.verifyDevicePayload({ purchaseToken: TOKEN }), /purchase token unknown/);
});

test('google: subscription states fold onto the decision correctly', async () => {
  const { v } = await verifier([]);
  const at = (state: string, extra: Partial<SubscriptionPurchaseV2> = {}, item = {}) => decideEntitlement(v.normalize(subscription({ subscriptionState: state, ...extra }, item), TOKEN, 'verify', NOW_MS), NOW_MS);
  assert.equal(at('SUBSCRIPTION_STATE_ACTIVE').status, 'active');
  assert.equal(at('SUBSCRIPTION_STATE_CANCELED', {}, { autoRenewingPlan: { autoRenewEnabled: false } }).status, 'active', 'cancelled keeps access until expiry');
  const grace = at('SUBSCRIPTION_STATE_IN_GRACE_PERIOD', {}, { expiryTime: new Date(NOW_MS + 5 * DAY_MS).toISOString() });
  assert.equal(grace.status, 'grace');
  assert.equal(grace.periodEnd, Math.floor((NOW_MS + 5 * DAY_MS) / 1000));
  assert.equal(at('SUBSCRIPTION_STATE_ON_HOLD').status, 'expired', 'on hold: no access, no fallback grace');
  assert.equal(at('SUBSCRIPTION_STATE_PAUSED').status, 'expired');
  assert.equal(at('SUBSCRIPTION_STATE_EXPIRED', {}, { expiryTime: new Date(NOW_MS - DAY_MS).toISOString() }).status, 'expired');
  assert.equal(at('SUBSCRIPTION_STATE_PENDING').status, 'none');
  assert.throws(() => v.normalize({ lineItems: [] }, TOKEN, 'verify', NOW_MS), /no line item/);
  const superseding = v.normalize(subscription({ linkedPurchaseToken: 'old-token-0123456789abcdef' }), TOKEN, 'verify', NOW_MS);
  assert.equal(superseding.supersedesOriginalTransactionId, 'old-token-0123456789abcdef');
});

test('google: RTDN push -- authenticated by the shared token, decoded from Pub/Sub, re-fetched from the API', async () => {
  const { v, calls } = await verifier([
    { match: (url) => url.includes(`/tokens/${TOKEN}`), status: 200, body: subscription({ subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED' }, { expiryTime: new Date(NOW_MS - 3600_000).toISOString() }) },
  ]);
  assert.equal(await v.authenticatePush(new URL('https://w/v1/billing/google/rtdn?token=push-secret'), null), true);
  assert.equal(await v.authenticatePush(new URL('https://w/v1/billing/google/rtdn?token=wrong'), null), false);
  assert.equal(await v.authenticatePush(new URL('https://w/v1/billing/google/rtdn'), 'Bearer x'), false, 'no OIDC verifier injected -> not trusted');

  const data = Buffer.from(JSON.stringify({ version: '1.0', packageName: PKG, eventTimeMillis: String(NOW_MS - 5000), subscriptionNotification: { version: '1.0', notificationType: 13, purchaseToken: TOKEN, subscriptionId: 'little_days_family_monthly' } })).toString('base64');
  const rtdn = v.parseRtdn({ message: { data, messageId: 'm-1', publishTime: new Date(NOW_MS).toISOString() }, subscription: 'projects/p/subscriptions/s' });
  assert.equal(rtdn.subscription?.name, 'SUBSCRIPTION_EXPIRED');
  assert.equal(rtdn.eventTimeMs, NOW_MS - 5000);
  const tx = await v.transactionForRtdn(rtdn);
  assert.equal(tx?.transactionId, 'GPA.1234-5678-9012-34567:13:m-1');
  assert.equal(decideEntitlement(tx!, NOW_MS).status, 'expired');
  assert.equal(calls.filter((c) => c.url.includes('/tokens/')).length, 1);

  // Test notifications and foreign packages.
  const testData = Buffer.from(JSON.stringify({ version: '1.0', packageName: PKG, eventTimeMillis: NOW_MS, testNotification: { version: '1.0' } })).toString('base64');
  assert.equal((await v.transactionForRtdn(v.parseRtdn({ message: { data: testData, messageId: 't' } }))), null);
  const foreign = Buffer.from(JSON.stringify({ packageName: 'com.other', subscriptionNotification: { notificationType: 4, purchaseToken: TOKEN } })).toString('base64');
  assert.throws(() => v.parseRtdn({ message: { data: foreign } }), /packageName mismatch/);

  // Voided purchase -> revoked.
  const voided = Buffer.from(JSON.stringify({ packageName: PKG, eventTimeMillis: NOW_MS, voidedPurchaseNotification: { purchaseToken: TOKEN, orderId: 'GPA.1234-5678-9012-34567', productType: 1, refundType: 1 } })).toString('base64');
  const voidedTx = await v.transactionForRtdn(v.parseRtdn({ message: { data: voided, messageId: 'v' } }));
  assert.equal(voidedTx?.revokedAtMs, NOW_MS);
  assert.equal(decideEntitlement(voidedTx!, NOW_MS).status, 'revoked');
});
