import { test } from 'node:test';
import assert from 'node:assert/strict';
import { AppleVerifier } from '../apple.ts';
import { decodeJws, verifyJwsWithX5c } from '../crypto/jws.ts';
import { parseCertificate } from '../crypto/x509.ts';
import { base64Decode, sha256Hex } from '../crypto/encoding.ts';
import { CHAIN, DAY_MS, NOW_MS, ROGUE_CHAIN, appleTransactionPayload, clock, fakeFetch, fixtureRootSha256, pem, signWithFixtureLeaf } from './helpers.ts';

const BUNDLE = 'com.littledays.app';

async function verifier(overrides: Partial<ConstructorParameters<typeof AppleVerifier>[0]> = {}, fetchImpl: typeof fetch = fakeFetch([]).fetch) {
  return new AppleVerifier({
    bundleId: BUNDLE,
    issuerId: 'issuer-uuid',
    keyId: 'ABC123DEFG',
    privateKeyPem: pem('leaf.pkcs8.pem'), // any P-256 key works for the client JWT
    environment: 'sandbox',
    trustedRootSha256Hex: await fixtureRootSha256(),
    ...overrides,
  }, { fetch: fetchImpl, now: clock().now });
}

test('x509: the fixture chain parses as leaf(P-256, OID 6.11.1) <- intermediate(CA, OID 6.2.1) <- root(P-384, CA)', () => {
  const [leaf, inter, root] = CHAIN.map((c) => parseCertificate(base64Decode(c)));
  assert.equal(leaf.curve, 'P-256');
  assert.equal(root.curve, 'P-384');
  assert.equal(leaf.isCa, false);
  assert.equal(inter.isCa, true);
  assert.ok(leaf.extensionOids.includes('1.2.840.113635.100.6.11.1'));
  assert.ok(inter.extensionOids.includes('1.2.840.113635.100.6.2.1'));
  assert.ok(leaf.notBeforeMs < NOW_MS && NOW_MS < leaf.notAfterMs);
});

test('jws: a transaction signed by the fixture leaf verifies against the pinned fixture root', async () => {
  const token = await signWithFixtureLeaf(appleTransactionPayload(), { alg: 'ES256' });
  const result = await verifyJwsWithX5c(token, {
    trustedRootSha256Hex: await fixtureRootSha256(),
    requiredLeafOids: ['1.2.840.113635.100.6.11.1'],
    requiredIntermediateOids: ['1.2.840.113635.100.6.2.1'],
  }, NOW_MS);
  assert.equal(result.reason, 'ok');
  assert.equal(result.payload?.productId, 'little_days_family_monthly');
});

test('jws: tampering with the payload, a rogue chain, a missing OID, a wrong root, or a stale date all fail closed', async () => {
  const policy = { trustedRootSha256Hex: await fixtureRootSha256(), requiredLeafOids: ['1.2.840.113635.100.6.11.1'], requiredIntermediateOids: ['1.2.840.113635.100.6.2.1'] };
  const good = await signWithFixtureLeaf(appleTransactionPayload(), { alg: 'ES256' });

  // Payload swapped for a longer subscription, signature kept.
  const [h, , s] = good.split('.');
  const forgedPayload = Buffer.from(JSON.stringify(appleTransactionPayload({ expiresDate: NOW_MS + 300 * DAY_MS }))).toString('base64url');
  const forged = await verifyJwsWithX5c(`${h}.${forgedPayload}.${s}`, policy, NOW_MS);
  assert.equal(forged.ok, false);
  assert.equal(forged.reason, 'bad_signature');

  // Signed by a leaf that carries the right OID but chains to somebody else's root.
  const rogue = await signWithFixtureLeaf(appleTransactionPayload(), { alg: 'ES256' }, 'rogue_leaf.pkcs8.pem', ROGUE_CHAIN);
  assert.equal((await verifyJwsWithX5c(rogue, policy, NOW_MS)).reason, 'untrusted_root');

  // Pin the rogue root instead: the chain is now "trusted" but still fails policy
  // (its root is not marked CA, and there is no intermediate carrying Apple's OID).
  const rogueRootSha = await sha256Hex(base64Decode(ROGUE_CHAIN[1]));
  const noIntermediate = await verifyJwsWithX5c(rogue, { ...policy, trustedRootSha256Hex: rogueRootSha }, NOW_MS);
  assert.equal(noIntermediate.ok, false);
  assert.match(noIntermediate.reason, /is_not_a_ca|intermediate_missing_oid_1\.2\.840\.113635\.100\.6\.2\.1/);

  // A policy demanding an OID the leaf lacks.
  const missing = await verifyJwsWithX5c(good, { ...policy, requiredLeafOids: ['1.2.840.113635.100.6.99.9'] }, NOW_MS);
  assert.equal(missing.reason, 'leaf_missing_oid_1.2.840.113635.100.6.99.9');

  // The production pin (Apple's real root) rejects the fixture chain.
  const wrongRoot = await verifyJwsWithX5c(good, { ...policy, trustedRootSha256Hex: '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179' }, NOW_MS);
  assert.equal(wrongRoot.reason, 'untrusted_root');

  // A signedDate before the certificates existed.
  const ancient = await signWithFixtureLeaf(appleTransactionPayload({ signedDate: Date.UTC(2001, 0, 1) }), { alg: 'ES256' });
  assert.match((await verifyJwsWithX5c(ancient, policy, NOW_MS)).reason, /not_valid_at_effective_time/);

  // Wrong algorithm / no chain.
  assert.equal((await verifyJwsWithX5c(good.replace(h, Buffer.from(JSON.stringify({ alg: 'HS256', x5c: CHAIN })).toString('base64url')), policy, NOW_MS)).reason, 'unsupported_alg');
  assert.equal((await verifyJwsWithX5c('not.a.jws', policy, NOW_MS)).ok, false);
});

test('apple: a StoreKit 2 signed transaction from the device is verified locally and normalized', async () => {
  const v = await verifier();
  const signed = await signWithFixtureLeaf(appleTransactionPayload(), { alg: 'ES256' });
  const tx = await v.verifyDevicePayload({ signedTransaction: signed });
  assert.equal(tx.store, 'apple');
  assert.equal(tx.productId, 'little_days_family_monthly');
  assert.equal(tx.transactionId, '2000000123456789');
  assert.equal(tx.originalTransactionId, '2000000100000000');
  assert.equal(tx.expiresAtMs, NOW_MS + 29 * DAY_MS);
  assert.equal(tx.revokedAtMs, null);
  assert.equal(tx.environment, 'sandbox');
  assert.equal(tx.eventTimeMs, NOW_MS - 3600_000);
});

test('apple: a StoreKit 1 transaction id is looked up with the App Store Server API using an ES256 client JWT', async () => {
  const signed = await signWithFixtureLeaf(appleTransactionPayload(), { alg: 'ES256' });
  const { fetch: f, calls } = fakeFetch([
    { match: (url) => url.endsWith('/inApps/v1/transactions/2000000123456789'), status: 200, body: { signedTransactionInfo: signed } },
  ]);
  const v = await verifier({}, f);
  const tx = await v.verifyDevicePayload({ transactionId: '2000000123456789' });
  assert.equal(tx.transactionId, '2000000123456789');
  assert.equal(calls.length, 1);
  assert.ok(calls[0].url.startsWith('https://api.storekit-sandbox.itunes.apple.com/'), 'sandbox host in sandbox config');
  const auth = String((calls[0].init?.headers as Record<string, string>).authorization);
  assert.ok(auth.startsWith('Bearer '));
  const jwt = decodeJws(auth.slice(7));
  assert.equal(jwt.header.alg, 'ES256');
  assert.equal(jwt.header.kid, 'ABC123DEFG');
  assert.equal(jwt.payload.iss, 'issuer-uuid');
  assert.equal(jwt.payload.aud, 'appstoreconnect-v1');
  assert.equal(jwt.payload.bid, BUNDLE);

  // The API answering with a transaction for another app is rejected.
  const other = await signWithFixtureLeaf(appleTransactionPayload({ bundleId: 'com.other.app' }), { alg: 'ES256' });
  const v2 = await verifier({}, fakeFetch([{ match: () => true, status: 200, body: { signedTransactionInfo: other } }]).fetch);
  await assert.rejects(v2.verifyDevicePayload({ transactionId: '1' }), /bundleId mismatch/);
  // And a malformed id never reaches the network.
  const { fetch: f3, calls: calls3 } = fakeFetch([]);
  await assert.rejects((await verifier({}, f3)).verifyDevicePayload({ transactionId: 'DROP TABLE' }), /transactionId required/);
  assert.equal(calls3.length, 0);
});

test('apple: production config refuses a sandbox transaction', async () => {
  const v = await verifier({ environment: 'production' });
  const signed = await signWithFixtureLeaf(appleTransactionPayload(), { alg: 'ES256' });
  await assert.rejects(v.verifyDevicePayload({ signedTransaction: signed }), /sandbox transaction in production/);
});

test('apple: App Store Server Notifications V2 -- outer and inner JWS verified; REFUND becomes a revocation; TEST is ignored', async () => {
  const v = await verifier();
  const inner = await signWithFixtureLeaf(appleTransactionPayload({ revocationDate: NOW_MS - 60_000, revocationReason: 0 }), { alg: 'ES256' });
  const renewal = await signWithFixtureLeaf({ originalTransactionId: '2000000100000000', autoRenewStatus: 0, signedDate: NOW_MS - 30_000 }, { alg: 'ES256' });
  const outer = await signWithFixtureLeaf({
    notificationType: 'REFUND', notificationUUID: 'uuid-1', signedDate: NOW_MS - 10_000, version: '2.0',
    data: { bundleId: BUNDLE, environment: 'Sandbox', signedTransactionInfo: inner, signedRenewalInfo: renewal },
  }, { alg: 'ES256' });
  const parsed = await v.parseNotification({ signedPayload: outer });
  assert.equal(parsed.notificationType, 'REFUND');
  assert.equal(parsed.transaction?.revokedAtMs, NOW_MS - 60_000);
  assert.equal(parsed.transaction?.transactionId, '2000000123456789:uuid-1');
  assert.equal(parsed.transaction?.eventTimeMs, NOW_MS - 10_000, 'ordered by the notification signedDate');
  assert.equal(parsed.transaction?.autoRenewing, false);

  const testOuter = await signWithFixtureLeaf({ notificationType: 'TEST', notificationUUID: 'uuid-t', signedDate: NOW_MS, data: { bundleId: BUNDLE } }, { alg: 'ES256' });
  assert.equal((await v.parseNotification({ signedPayload: testOuter })).transaction, null);

  // An inner transaction signed by the rogue chain inside a valid outer envelope is rejected.
  const rogueInner = await signWithFixtureLeaf(appleTransactionPayload(), { alg: 'ES256' }, 'rogue_leaf.pkcs8.pem', ROGUE_CHAIN);
  const mixed = await signWithFixtureLeaf({ notificationType: 'DID_RENEW', notificationUUID: 'uuid-2', signedDate: NOW_MS, data: { bundleId: BUNDLE, signedTransactionInfo: rogueInner } }, { alg: 'ES256' });
  await assert.rejects(v.parseNotification({ signedPayload: mixed }), /untrusted_root/);
  await assert.rejects(v.parseNotification({ signedPayload: 'garbage' }), /malformed_jws/);
  await assert.rejects(v.parseNotification({}), /signedPayload required/);
});

test('apple: EXPIRED / GRACE_PERIOD_EXPIRED disable the fallback grace; DID_FAIL_TO_RENEW with a grace date keeps it', async () => {
  const v = await verifier();
  const payload = appleTransactionPayload({ expiresDate: NOW_MS - DAY_MS });
  const expired = v.normalizeTransaction(payload as never, { autoRenewStatus: 1 }, 'apple_notification', 'EXPIRED');
  assert.equal(expired.autoRenewing, false);
  const graced = v.normalizeTransaction(payload as never, { autoRenewStatus: 1, gracePeriodExpiresDate: NOW_MS + 10 * DAY_MS }, 'apple_notification', 'DID_FAIL_TO_RENEW');
  assert.equal(graced.gracePeriodExpiresAtMs, NOW_MS + 10 * DAY_MS);
  assert.throws(() => v.normalizeTransaction({ ...payload, type: 'Consumable' } as never, null, 'verify'), /unsupported transaction type/);
});
