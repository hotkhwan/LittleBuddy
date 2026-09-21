import { test } from 'node:test';
import assert from 'node:assert/strict';
import { AppleVerifier } from '../apple.ts';
import { GoogleVerifier } from '../google.ts';
import { handleBillingRequest, type BillingDeps, type BillingEnv } from '../handlers.ts';
import { billingRoutes } from '../index.ts';
import { MemoryBillingRepo } from '../repo.ts';
import { DAY_MS, NOW_MS, appleTransactionPayload, clock, fakeFetch, fixtureRootSha256, jsonOf, pem, request, rsaPkcs8Pem, signWithFixtureLeaf } from './helpers.ts';

const BUNDLE = 'com.littledays.app';
const PKG = 'com.littledays.app';
const TOKEN = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEF';

async function rig(env: BillingEnv = {}, routes: Parameters<typeof fakeFetch>[0] = []) {
  const repo = new MemoryBillingRepo();
  const c = clock();
  const { fetch: f, calls } = fakeFetch([
    { match: (url) => url === 'https://oauth2.googleapis.com/token', status: 200, body: { access_token: 'ya29.test', expires_in: 3600 } },
    ...routes,
  ]);
  const apple = new AppleVerifier({ bundleId: BUNDLE, issuerId: 'iss', keyId: 'kid', privateKeyPem: pem('leaf.pkcs8.pem'), environment: 'sandbox', trustedRootSha256Hex: await fixtureRootSha256() }, { fetch: f, now: c.now });
  const google = new GoogleVerifier({ packageName: PKG, serviceAccount: { client_email: 'svc@p.iam.gserviceaccount.com', private_key: await rsaPkcs8Pem() }, rtdnToken: 'push-secret' }, { fetch: f, now: c.now });
  const logs: Array<{ route: string; status: number }> = [];
  const deps: BillingDeps = { repo, now: c.now, apple, google, log: (l) => logs.push({ route: l.route, status: l.status }) };
  const call = (req: Request) => handleBillingRequest(req, env, deps);
  return { repo, clock: c, calls, deps, env, call, logs };
}

const mockReceipt = (clientId: string, transactionId = 'mock-txn-1', extra: Record<string, unknown> = {}) => ({
  store: 'mock', productId: 'little_days_family_monthly', transactionId, clientId,
  payload: { mock: true, productId: 'little_days_family_monthly', transactionId, originalTransactionId: 'mock-txn-1', ...extra },
});

test('routes: paths outside /v1/billing are not handled; unknown billing paths are 404', async () => {
  const r = await rig();
  assert.equal(await r.call(request('GET', '/v1/tutor/sessions')), null);
  const res = await r.call(request('GET', '/v1/billing/nope'));
  assert.equal(res?.status, 404);
  assert.equal(r.logs[0].route, 'GET /v1/billing/nope');
});

test('verify: the mock store works only in dev mode and never in a plain deployment', async () => {
  const plain = await rig({});
  const refused = await plain.call(request('POST', '/v1/billing/verify', mockReceipt('device-a')));
  assert.equal(refused?.status, 403);
  assert.equal((await jsonOf(refused!)).code, 'mock_not_allowed');
  assert.equal(plain.repo.entitlements.size, 0);

  const dev = await rig({ BILLING_DEV_MODE: '1' });
  const ok = await dev.call(request('POST', '/v1/billing/verify', mockReceipt('device-a')));
  assert.equal(ok?.status, 200);
  const body = await jsonOf(ok!);
  assert.equal(body.ok, true);
  assert.equal(body.outcome, 'applied');
  const decision = body.decision as Record<string, unknown>;
  assert.equal(decision.entitlementId, 'familyClub');
  assert.equal(decision.status, 'active');
  assert.equal(decision.productId, 'little_days_family_monthly');
  assert.equal(decision.periodEnd, Math.floor((NOW_MS + 30 * DAY_MS) / 1000));
  assert.deepEqual(body.quota, { entitlement: 'family_club', dailyAllowanceSeconds: 1800 });

  // Replay: same answer, no second event.
  const again = await dev.call(request('POST', '/v1/billing/verify', mockReceipt('device-a')));
  assert.equal((await jsonOf(again!)).outcome, 'replayed');
  assert.equal(dev.repo.events.size, 1);
  // Conflict: same transaction, different claim.
  const conflict = await dev.call(request('POST', '/v1/billing/verify', mockReceipt('device-a', 'mock-txn-1', { expiresAtMs: NOW_MS + 400 * DAY_MS })));
  assert.equal(conflict?.status, 409);

  // GET /entitlement re-evaluates against the clock.
  const now = await dev.call(request('GET', '/v1/billing/entitlement?clientId=device-a'));
  assert.equal(((await jsonOf(now!)).decision as Record<string, unknown>).status, 'active');
  dev.clock.advance(31 * DAY_MS);
  const later = await dev.call(request('GET', '/v1/billing/entitlement?clientId=device-a'));
  const lateBody = await jsonOf(later!);
  assert.equal((lateBody.decision as Record<string, unknown>).status, 'expired');
  assert.deepEqual(lateBody.quota, { entitlement: 'free', dailyAllowanceSeconds: 300 });
  const nobody = await dev.call(request('GET', '/v1/billing/entitlement?clientId=never-seen'));
  assert.equal(((await jsonOf(nobody!)).decision as Record<string, unknown>).status, 'none');
});

test('verify: with purchases disabled, a real-store receipt is refused with 503 and NO store API is called', async () => {
  const signed = await signWithFixtureLeaf(appleTransactionPayload(), { alg: 'ES256' });
  const r = await rig({ BILLING_DEV_MODE: '1' }, [{ match: () => true, status: 200, body: {} }]);
  for (const body of [
    { store: 'apple', productId: 'little_days_family_monthly', transactionId: '2000000123456789', clientId: 'device-a', payload: { signedTransaction: signed } },
    { store: 'google', productId: 'little_days_family_monthly', transactionId: 'GPA.1', clientId: 'device-a', payload: { purchaseToken: TOKEN } },
  ]) {
    const res = await r.call(request('POST', '/v1/billing/verify', body));
    assert.equal(res?.status, 503);
    assert.equal((await jsonOf(res!)).code, 'billing_disabled');
  }
  assert.equal(r.calls.length, 0, 'no fetch to Apple or Google happened');
  assert.equal(r.repo.entitlements.size, 0);
  assert.equal(r.repo.events.size, 0);
});

test('verify: request validation -- unknown product, bad client id, bad body, mismatched product', async () => {
  const r = await rig({ BILLING_DEV_MODE: '1' });
  const cases: Array<[unknown, number, string]> = [
    [{ ...mockReceipt('device-a'), productId: 'little_days_gold' }, 400, 'unknown_product'],
    [{ ...mockReceipt('device-a'), clientId: 'x' }, 400, 'bad_request'],
    [{ ...mockReceipt('device-a'), store: 'stripe' }, 400, 'bad_request'],
    [{ ...mockReceipt('device-a'), payload: 'receipt' }, 400, 'bad_request'],
    [{ ...mockReceipt('device-a'), productId: 'little_days_family_yearly' }, 400, 'product_mismatch'],
    ['[]', 400, 'bad_request'],
  ];
  for (const [body, status, code] of cases) {
    const res = await r.call(typeof body === 'string' ? new Request('https://w/v1/billing/verify', { method: 'POST', body }) : request('POST', '/v1/billing/verify', body));
    assert.equal(res?.status, status, JSON.stringify(body));
    assert.equal((await jsonOf(res!)).code, code, JSON.stringify(body));
  }
  const huge = new Request('https://w/v1/billing/verify', { method: 'POST', headers: { 'content-length': String(64 * 1024) }, body: '{}' });
  assert.equal((await r.call(huge))?.status, 413);
  assert.equal(r.repo.events.size, 0);
});

test('verify + notifications: Apple end to end -- two devices restore, a REFUND revokes both, replays are idempotent', async () => {
  const signed = await signWithFixtureLeaf(appleTransactionPayload(), { alg: 'ES256' });
  const r = await rig({ BILLING_PURCHASES_ENABLED: '1' }, [
    { match: (url) => url.endsWith('/inApps/v1/transactions/2000000123456789'), status: 200, body: { signedTransactionInfo: signed } },
  ]);
  // Device A: StoreKit 1 plugin -> transaction id only -> API lookup.
  const a = await r.call(request('POST', '/v1/billing/verify', { store: 'apple', productId: 'little_days_family_monthly', transactionId: '2000000123456789', clientId: 'ipad', payload: { transactionId: '2000000123456789' } }));
  assert.equal(a?.status, 200);
  assert.equal(((await jsonOf(a!)).decision as Record<string, unknown>).status, 'active');
  // Device B: StoreKit 2 -> signed transaction, verified locally (no API call).
  const before = r.calls.length;
  const b = await r.call(request('POST', '/v1/billing/verify', { store: 'apple', productId: 'little_days_family_monthly', transactionId: '2000000123456789', clientId: 'iphone', payload: { signedTransaction: signed } }));
  assert.equal(b?.status, 200);
  assert.equal(r.calls.length, before, 'a signed transaction needs no lookup');
  assert.equal(r.repo.entitlements.get('iphone')?.original_transaction_id, '2000000100000000');

  // Apple sends a REFUND.
  const inner = await signWithFixtureLeaf(appleTransactionPayload({ revocationDate: NOW_MS - 1000, revocationReason: 0 }), { alg: 'ES256' });
  const outer = await signWithFixtureLeaf({ notificationType: 'REFUND', notificationUUID: 'n-1', signedDate: NOW_MS, data: { bundleId: BUNDLE, environment: 'Sandbox', signedTransactionInfo: inner } }, { alg: 'ES256' });
  const n = await r.call(request('POST', '/v1/billing/apple/notifications', { signedPayload: outer }));
  assert.equal(n?.status, 200);
  const nBody = await jsonOf(n!);
  assert.equal(nBody.outcome, 'applied');
  assert.equal(nBody.subjects, 2);
  assert.equal(r.repo.entitlements.get('ipad')?.status, 'revoked');
  assert.equal(r.repo.entitlements.get('iphone')?.status, 'revoked');
  // Re-delivered notification: replayed, still revoked.
  const n2 = await r.call(request('POST', '/v1/billing/apple/notifications', { signedPayload: outer }));
  assert.equal((await jsonOf(n2!)).outcome, 'replayed');
  // Forged notification: 401, nothing changes.
  const forged = await r.call(request('POST', '/v1/billing/apple/notifications', { signedPayload: outer.slice(0, -4) + 'AAAA' }));
  assert.equal(forged?.status, 401);
  // The device asking again gets the revoked truth.
  const after = await r.call(request('GET', '/v1/billing/entitlement?clientId=ipad'));
  assert.equal(((await jsonOf(after!)).decision as Record<string, unknown>).status, 'revoked');
});

test('verify + rtdn: Google end to end -- verify acknowledges after granting; an EXPIRED RTDN downgrades; unauthenticated pushes are 401', async () => {
  let state = 'SUBSCRIPTION_STATE_ACTIVE';
  let expiry = new Date(NOW_MS + 29 * DAY_MS).toISOString();
  const acks: string[] = [];
  const r = await rig({ BILLING_PURCHASES_ENABLED: '1' }, [
    { match: (url, init) => url.endsWith(':acknowledge') && init?.method === 'POST', status: 200, body: {} },
    { match: (url) => url.includes(`/subscriptionsv2/tokens/${TOKEN}`), status: 200, body: { get kind() { return 'androidpublisher#subscriptionPurchaseV2'; }, get subscriptionState() { return state; }, latestOrderId: 'GPA.1', startTime: new Date(NOW_MS - DAY_MS).toISOString(), acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING', get lineItems() { return [{ productId: 'little_days_family_monthly', expiryTime: expiry, autoRenewingPlan: { autoRenewEnabled: true } }]; } } },
  ]);
  const v = await r.call(request('POST', '/v1/billing/verify', { store: 'google', productId: 'little_days_family_monthly', transactionId: 'GPA.1', clientId: 'pixel', payload: { purchaseToken: TOKEN, packageName: PKG } }));
  assert.equal(v?.status, 200);
  assert.equal(((await jsonOf(v!)).decision as Record<string, unknown>).status, 'active');
  const ackCalls = r.calls.filter((c) => c.url.endsWith(':acknowledge'));
  assert.equal(ackCalls.length, 1, 'acknowledged once, after the grant');
  acks.push(ackCalls[0].url);
  assert.ok(acks[0].includes(`/purchases/subscriptions/little_days_family_monthly/tokens/${TOKEN}:acknowledge`));

  // Replay of the verify: no second acknowledge.
  await r.call(request('POST', '/v1/billing/verify', { store: 'google', productId: 'little_days_family_monthly', transactionId: 'GPA.1', clientId: 'pixel', payload: { purchaseToken: TOKEN, packageName: PKG } }));
  assert.equal(r.calls.filter((c) => c.url.endsWith(':acknowledge')).length, 1);

  // Play says it expired.
  state = 'SUBSCRIPTION_STATE_EXPIRED';
  expiry = new Date(NOW_MS - 1000).toISOString();
  const data = Buffer.from(JSON.stringify({ version: '1.0', packageName: PKG, eventTimeMillis: String(NOW_MS + 1000), subscriptionNotification: { version: '1.0', notificationType: 13, purchaseToken: TOKEN, subscriptionId: 'little_days_family_monthly' } })).toString('base64');
  const push = (path: string) => request('POST', path, { message: { data, messageId: 'm-1' }, subscription: 's' });
  assert.equal((await r.call(push('/v1/billing/google/rtdn')))?.status, 401);
  assert.equal((await r.call(push('/v1/billing/google/rtdn?token=nope')))?.status, 401);
  assert.equal(r.repo.entitlements.get('pixel')?.status, 'active', 'unauthenticated pushes change nothing');
  r.clock.advance(2000);
  const ok = await r.call(push('/v1/billing/google/rtdn?token=push-secret'));
  assert.equal(ok?.status, 200);
  assert.equal((await jsonOf(ok!)).notificationType, 'SUBSCRIPTION_EXPIRED');
  assert.equal(r.repo.entitlements.get('pixel')?.status, 'expired');
  // Redelivery: replayed; still 200 so Pub/Sub stops.
  assert.equal((await jsonOf((await r.call(push('/v1/billing/google/rtdn?token=push-secret')))!)).outcome, 'replayed');
});

test('index: billingRoutes accepts injected deps and refuses to build real deps without a DB binding', async () => {
  const r = await rig({ BILLING_DEV_MODE: '1' });
  const res = await billingRoutes(request('POST', '/v1/billing/verify', mockReceipt('device-z')), r.env, r.deps);
  assert.equal(res?.status, 200);
  await assert.rejects(billingRoutes(request('GET', '/v1/billing/entitlement?clientId=device-z'), {}), /DB binding missing/);
});
