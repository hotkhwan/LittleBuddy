// Identity end to end: first install -> guest -> (trial, blocked purchase) ->
// Apple link -> migration -> entitlement -> second installation (restore) ->
// reinstall. Synthetic data only: app-generated UUIDs, a test RSA key that
// serves a fake Apple/Google JWKS, the dev entitlement route. No store is
// called and nothing is charged. Where the implementation diverges from
// docs/IDENTITY_ARCHITECTURE.md the divergence is asserted as it IS today and
// named "GAP" so docs/IDENTITY_E2E_VERIFICATION.md and this file agree.
import { env } from 'cloudflare:test';
import { afterEach, describe, expect, it } from 'vitest';
import { DEV_TOKEN, lessonTurnBody, makeClient, type Client } from './helpers';
import { generateTestKey, jwksDocument, signJws, type TestKey } from './identity_keys';
import { handleVerify, type BillingDeps, type BillingEnv } from '../src/billing/handlers';
import { D1BillingRepo } from '../src/billing/repo';
import type { NormalizedTransaction } from '../src/billing/types';
import type { Env } from '../src/env';

const APPLE_AUD = 'com.joinanny.littledays';
const IDENTITY_ENV = { APPLE_BUNDLE_ID: APPLE_AUD, APPLE_SERVICE_ID: 'com.joinanny.littledays.web', GOOGLE_CLIENT_IDS: 'test-ios.apps.googleusercontent.com' } as Partial<Env>;
const NO_IDENTITY_ENV = { APPLE_BUNDLE_ID: '', APPLE_SERVICE_ID: '', GOOGLE_CLIENT_IDS: '' } as Partial<Env>;
const PII_COLUMN = /name|email|phone|birth|address|nick/i;

// One key for the file: the Apple verifier's JWKS cache is isolate-wide.
const key: TestKey = await generateTestKey('identity-e2e-kid');
const realFetch = globalThis.fetch;
function serveJwks() {
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (url === 'https://appleid.apple.com/auth/keys' || url === 'https://www.googleapis.com/oauth2/v3/certs') return new Response(JSON.stringify(jwksDocument(key)), { headers: { 'content-type': 'application/json' } });
    throw new Error(`identity_e2e: unexpected network call ${url}`);
  }) as typeof fetch;
}
afterEach(() => {
  globalThis.fetch = realFetch;
});

const noToken = { 'x-parent-approval': '' };
const bearer = (token: string) => ({ authorization: `Bearer ${token}`, 'x-parent-approval': '' });
const newInstallationId = () => crypto.randomUUID();

async function appleToken(c: Client, sub: string) {
  const exp = c.clock.now() / 1000 + 600;
  return signJws(key, { iss: 'https://appleid.apple.com', aud: APPLE_AUD, sub, exp, iat: exp - 605, email: 'parent@example.com', email_verified: 'true' });
}

async function count(sql: string, ...binds: unknown[]): Promise<number> {
  return Number((await env.DB.prepare(sql).bind(...binds).first<{ n: number }>())?.n ?? 0);
}

async function columns(table: string): Promise<string[]> {
  const { results } = await env.DB.prepare(`PRAGMA table_info(${table})`).all<{ name: string }>();
  return results.map((r) => r.name);
}

/** The Godot client's first-launch call: InstallationIdentity.load_or_create() -> IdentityApi.create_guest(). */
async function firstInstall(c: Client, installationId = newInstallationId(), platform = 'ios') {
  const r = await c.api('POST', '/v1/auth/guest', { installationId, platform, appVersion: '0.0.0-e2e' }, noToken);
  if (r.status !== 201) throw new Error(`guest create failed: ${r.status} ${JSON.stringify(r.body)}`);
  return { installationId, guestAccountId: r.body.guestAccountId as string, guestToken: r.body.guestToken as string, body: r.body };
}

async function linkApple(c: Client, guestToken: string, sub: string) {
  return c.api('POST', '/v1/auth/link', { provider: 'apple', identityToken: await appleToken(c, sub) }, bearer(guestToken));
}

describe('identity e2e: first install -> guest', () => {
  it('registers an installation and a guest account that hold no personal data, idempotently', async () => {
    const c = makeClient({ defaultToken: null });
    const g = await firstInstall(c);
    expect(Object.keys(g.body).sort()).toEqual(['accountType', 'guestAccountId', 'guestToken', 'installationId']);
    expect(g.body.accountType).toBe('guest');
    expect(g.guestToken).toMatch(/^gt1\./);
    expect(g.guestAccountId).not.toBe(g.installationId);

    const install = await env.DB.prepare('SELECT platform,account_id,guest_account_id,app_version,status FROM installations WHERE installation_id=?').bind(g.installationId).first();
    expect(install).toEqual({ platform: 'ios', account_id: null, guest_account_id: g.guestAccountId, app_version: '0.0.0-e2e', status: 'active' });
    const guest = await env.DB.prepare('SELECT status,merged_into,linked_at FROM guest_accounts WHERE id=?').bind(g.guestAccountId).first();
    expect(guest).toEqual({ status: 'active', merged_into: null, linked_at: null });

    // The guest tables cannot hold a child name or an e-mail: there is no column for one.
    for (const table of ['installations', 'guest_accounts', 'guest_learning_progress', 'guest_settings', 'guest_ai_usage']) {
      const cols = await columns(table);
      expect(cols.length).toBeGreaterThan(0);
      expect(cols.filter((name) => PII_COLUMN.test(name))).toEqual([]);
    }

    // Relaunch: same installation id -> 200, same guest, still one row each.
    const again = await c.api('POST', '/v1/auth/guest', { installationId: g.installationId, platform: 'ios', appVersion: '0.0.1-e2e' }, noToken);
    expect(again.status).toBe(200);
    expect(again.body.guestAccountId).toBe(g.guestAccountId);
    expect(await count('SELECT COUNT(*) n FROM installations WHERE installation_id=?', g.installationId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM installations WHERE guest_account_id=?', g.guestAccountId)).toBe(1);

    // What a guest is entitled to: FREE, not purchasable.
    const ent = await c.api('GET', '/v1/me/entitlements', undefined, bearer(g.guestToken));
    expect(ent.status).toBe(200);
    expect(ent.body).toEqual({ accountType: 'guest', plan: 'FREE', paid: false, canPurchase: false, features: ['core_game', 'local_lessons', 'standard_ai_trial'], premiumLiveTrial: false });
  });

  it('rejects hardware-shaped, malformed and foreign-platform installation ids', async () => {
    const c = makeClient({ defaultToken: null });
    expect((await c.api('POST', '/v1/auth/guest', { installationId: '356938035643809', platform: 'ios' }, noToken)).status).toBe(400);
    expect((await c.api('POST', '/v1/auth/guest', { installationId: 'not-a-uuid', platform: 'ios' }, noToken)).status).toBe(400);
    expect((await c.api('POST', '/v1/auth/guest', { installationId: newInstallationId(), platform: 'tv' }, noToken)).status).toBe(400);
    expect((await c.api('POST', '/v1/auth/guest', {}, noToken)).status).toBe(400);
  });
});

describe('identity e2e: guest capabilities', () => {
  it('GAP: the guest token opens no tutor session; the DEV literal does, with the 300 s free allowance charged per child', async () => {
    const c = makeClient({ defaultToken: null });
    const g = await firstInstall(c);
    // Every tutor route needs a parent credential (pa1 / pt1 / DEV literal); gt1 is not one.
    const asBearer = await c.api('POST', '/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId: g.installationId }, bearer(g.guestToken));
    expect(asBearer.status).toBe(403);
    expect(asBearer.body.error.code).toBe('not_approved');
    const asApproval = await c.api('POST', '/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId: g.installationId }, { 'x-parent-approval': g.guestToken });
    expect(asApproval.status).toBe(403);

    // The DEV_MODE literal the Godot client sends today (use_dev_token()).
    const dev = { 'x-parent-approval': DEV_TOKEN };
    const kid = await c.api('POST', '/v1/children', { nickname: 'E2E Trial Kid', clientId: g.installationId }, dev);
    expect(kid.status).toBe(201);
    const s = await c.api('POST', '/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId: g.installationId, childId: kid.body.childId }, dev);
    expect(s.status).toBe(201);
    expect(s.body.quota).toMatchObject({ entitlement: 'free', dailyAllowanceSeconds: 300, usedSeconds: 0, remainingSeconds: 300 });
    c.clock.advance(12);
    const turn = await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/turns`, lessonTurnBody(), dev);
    expect(turn.status).toBe(200);
    expect(turn.body.quota).toMatchObject({ usedSeconds: 12, remainingSeconds: 288, usedTurns: 1 });
    c.clock.advance(8);
    const end = await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/end`, { reason: 'e2e' }, dev);
    expect(end.body.quota).toMatchObject({ usedSeconds: 20, remainingSeconds: 280 });
    // GAP: that trial is accounted to the dev parent's child quota, never to the guest row,
    // so the link-time usage import (guest_ai_usage -> account_ai_usage) has nothing to carry.
    expect(await count('SELECT COUNT(*) n FROM guest_ai_usage WHERE guest_account_id=?', g.guestAccountId)).toBe(0);
  });

  it('blocks a paid purchase for a guest at every layer', async () => {
    const c = makeClient({ defaultToken: null });
    const g = await firstInstall(c);
    const receipt = (store: string, payload: Record<string, unknown>) => ({ store, productId: 'little_days_family_monthly', transactionId: `e2e-${store}-1`, payload, clientId: g.installationId });

    // No parent credential at all -> the auth middleware stops it.
    const bare = await c.api('POST', '/v1/billing/verify', receipt('apple', { transactionId: 'x' }), bearer(g.guestToken));
    expect(bare.status).toBe(403);
    expect(bare.body.error.code).toBe('not_approved');

    // With a credential but purchases switched off server side: 503 billing_disabled before any store is consulted.
    const dev = { 'x-parent-approval': DEV_TOKEN };
    const apple = await c.api('POST', '/v1/billing/verify', receipt('apple', { transactionId: 'x' }), dev);
    expect(apple.status).toBe(503);
    expect(apple.body.code).toBe('billing_disabled');
    const google = await c.api('POST', '/v1/billing/verify', receipt('google', { purchaseToken: 'x' }), dev);
    expect(google.status).toBe(503);
    expect(google.body.code).toBe('billing_disabled');
    const mock = await c.api('POST', '/v1/billing/verify', receipt('mock', { mock: true, productId: 'little_days_family_monthly' }), dev);
    expect(mock.status).toBe(403);
    expect(mock.body.code).toBe('mock_not_allowed');

    // Even with purchases enabled and a store that vouches for the receipt, a guest installation is refused.
    const tx: NormalizedTransaction = { store: 'apple', productId: 'little_days_family_monthly', transactionId: 'e2e-apple-2', originalTransactionId: 'e2e-apple-orig', purchaseTimeMs: c.clock.now(), expiresAtMs: c.clock.now() + 86_400_000, revokedAtMs: null, gracePeriodExpiresAtMs: null, autoRenewing: true, environment: 'sandbox', accountToken: 'not-this-account', eventTimeMs: c.clock.now(), source: 'verify' };
    const billingEnv: BillingEnv = { DB: env.DB as unknown as BillingEnv['DB'], BILLING_PURCHASES_ENABLED: '1' };
    const deps: BillingDeps = { repo: new D1BillingRepo(env.DB as never), now: () => c.clock.now(), apple: { verifyDevicePayload: async () => tx } as unknown as BillingDeps['apple'], google: null };
    const direct = await handleVerify(new Request('https://cloud.test/v1/billing/verify', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(receipt('apple', { transactionId: 'e2e-apple-2' })) }), billingEnv, deps).catch((e) => e);
    expect(direct).toMatchObject({ status: 403, code: 'parent_account_required' });

    // And the purchase identity a store would be asked to carry is not issued to a guest.
    const pid = await c.api('GET', '/v1/me/purchase-identity', undefined, bearer(g.guestToken));
    expect(pid.status).toBe(403);
    expect(pid.body.error.code).toBe('parent_account_required');
  });
});

describe('identity e2e: guest -> parent link', () => {
  it('links with an Apple identity token, migrates progress once, and refuses a replay or a second parent', async () => {
    serveJwks();
    const c = makeClient({ defaultToken: null, env: IDENTITY_ENV });
    const g = await firstInstall(c);
    const T = c.clock.now();
    await env.DB.batch([
      env.DB.prepare('INSERT INTO guest_learning_progress VALUES (?,?,?,?,?,?,?)').bind(g.guestAccountId, 'colors_red_blue', 0.8, T, T, 3, T),
      env.DB.prepare('INSERT INTO guest_learning_progress VALUES (?,?,?,?,?,?,?)').bind(g.guestAccountId, 'animals_farm', 0.4, T, null, 1, T),
      env.DB.prepare('INSERT INTO guest_reward_awards VALUES (?,?,?,?)').bind(g.guestAccountId, 'award-e2e-1', 'star', T),
      env.DB.prepare('INSERT INTO guest_unlocks VALUES (?,?,?)').bind(g.guestAccountId, 'hat-e2e', T),
      env.DB.prepare('INSERT INTO guest_settings VALUES (?,?,?,?)').bind(g.guestAccountId, 'thaiHints', 'true', T),
      env.DB.prepare('INSERT INTO guest_ai_usage VALUES (?,?,?,?,?,?)').bind(g.guestAccountId, '2027-01', 90, 5, 9, T),
    ]);

    const sub = `apple-sub-${g.installationId}`;
    const link = await linkApple(c, g.guestToken, sub);
    expect(link.status).toBe(200);
    expect(Object.keys(link.body).sort()).toEqual(['linkedGuestAccountId', 'mergeStatus', 'parentAccountId', 'parentToken', 'provider']);
    expect(link.body).toMatchObject({ linkedGuestAccountId: g.guestAccountId, provider: 'apple', mergeStatus: 'complete' });
    expect(link.body.parentToken).toMatch(/^pt1\./);
    const accountId = link.body.parentAccountId as string;
    expect(JSON.stringify(link.body)).not.toContain(sub);

    // Server state after the merge.
    expect(await env.DB.prepare('SELECT status,merged_into FROM guest_accounts WHERE id=?').bind(g.guestAccountId).first()).toEqual({ status: 'linked', merged_into: accountId });
    expect(await env.DB.prepare('SELECT account_id,guest_account_id,status FROM installations WHERE installation_id=?').bind(g.installationId).first()).toEqual({ account_id: accountId, guest_account_id: null, status: 'active' });
    expect(await count('SELECT COUNT(*) n FROM account_learning_progress WHERE account_id=?', accountId)).toBe(2);
    expect(await env.DB.prepare("SELECT mastery,stars FROM account_learning_progress WHERE account_id=? AND lesson_id='colors_red_blue'").bind(accountId).first()).toEqual({ mastery: 0.8, stars: 3 });
    expect(await count('SELECT COUNT(*) n FROM account_reward_awards WHERE account_id=?', accountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM account_unlocks WHERE account_id=?', accountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM account_settings WHERE account_id=?', accountId)).toBe(1);
    expect(await env.DB.prepare('SELECT standard_seconds FROM account_ai_usage WHERE account_id=?').bind(accountId).first()).toEqual({ standard_seconds: 90 });
    expect(await count('SELECT COUNT(*) n FROM account_ai_usage_imports WHERE guest_account_id=?', g.guestAccountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM identity_providers WHERE account_id=?', accountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM parent_profiles WHERE account_id=?', accountId)).toBe(1);
    // Only hashes: the raw subject and e-mail never land in a row.
    const parentRow = await env.DB.prepare('SELECT provider,subject_hash,email_hash FROM parent_accounts WHERE id=?').bind(accountId).first<{ provider: string; subject_hash: string; email_hash: string }>();
    expect(parentRow?.provider).toBe('apple');
    expect(parentRow?.subject_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(parentRow?.email_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(parentRow)).not.toMatch(/parent@example\.com|apple-sub-/);

    // The parent token is a real account credential; the guest token is finished.
    const ent = await c.api('GET', '/v1/me/entitlements', undefined, bearer(link.body.parentToken));
    expect(ent.body).toMatchObject({ accountType: 'parent', plan: 'FREE', paid: false, canPurchase: true });
    const stale = await c.api('GET', '/v1/me/entitlements', undefined, bearer(g.guestToken));
    expect(stale.status).toBe(401);

    // Replay of the link with the spent guest token: no second merge, no duplicated rows.
    // GAP: the doc promises "a second request returns the original result"; the route answers 401 guest_token_replay.
    const replay = await linkApple(c, g.guestToken, sub);
    expect(replay.status).toBe(401);
    expect(replay.body.error.code).toBe('guest_token_replay');
    expect(await count('SELECT COUNT(*) n FROM account_learning_progress WHERE account_id=?', accountId)).toBe(2);
    expect(await count('SELECT COUNT(*) n FROM account_reward_awards WHERE account_id=?', accountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM account_ai_usage_imports WHERE guest_account_id=?', g.guestAccountId)).toBe(1);
    expect(await env.DB.prepare('SELECT standard_seconds FROM account_ai_usage WHERE account_id=?').bind(accountId).first()).toEqual({ standard_seconds: 90 });

    // The linked installation cannot go back to being a guest.
    const regress = await c.api('POST', '/v1/auth/guest', { installationId: g.installationId, platform: 'ios' }, noToken);
    expect(regress.status).toBe(409);

    // A parent token is not a guest credential for /auth/link.
    const wrongToken = await c.api('POST', '/v1/auth/link', { provider: 'apple', identityToken: await appleToken(c, sub) }, bearer(link.body.parentToken));
    expect(wrongToken.status).toBe(401);
  });

  it('entitlement follows the account: a dev grant, a second installation linked to the same Apple subject, and a reinstall all see FAMILY without duplicating rows', async () => {
    serveJwks();
    const c = makeClient({ defaultToken: null, env: IDENTITY_ENV });
    const sub = `apple-sub-restore-${crypto.randomUUID()}`;

    // Device A: first install, some guest progress, link.
    const a = await firstInstall(c);
    await env.DB.prepare('INSERT INTO guest_learning_progress VALUES (?,?,?,?,?,?,?)').bind(a.guestAccountId, 'colors_red_blue', 0.5, c.clock.now(), null, 2, c.clock.now()).run();
    const linkA = await linkApple(c, a.guestToken, sub);
    expect(linkA.status).toBe(200);
    const accountId = linkA.body.parentAccountId as string;
    const parentA = bearer(linkA.body.parentToken);

    // Entitlement: FREE -> FAMILY through the DEV_MODE grant (the mock store is off on this server).
    expect((await c.api('GET', '/v1/me/entitlements', undefined, parentA)).body.plan).toBe('FREE');
    const grant = await c.api('POST', '/v1/dev/entitlements', { entitlement: 'family_club', days: 30 }, parentA);
    expect(grant.status).toBe(200);
    expect(grant.body).toMatchObject({ parentId: accountId, entitlement: 'family_club', source: 'dev' });
    const entA = await c.api('GET', '/v1/me/entitlements', undefined, parentA);
    expect(entA.body).toMatchObject({ accountType: 'parent', plan: 'FAMILY', paid: true, subscription_status: 'active' });
    const idA = await c.api('GET', '/v1/me/purchase-identity', undefined, parentA);
    expect(idA.status).toBe(200);
    expect(idA.body.apple.appAccountToken).toMatch(/^[0-9a-f-]{36}$/);
    expect(idA.body.containsPii).toBe(false);

    // Device B: a second installation starts as its own guest and links to the same Apple subject.
    const b = await firstInstall(c, newInstallationId(), 'android');
    expect(b.guestAccountId).not.toBe(a.guestAccountId);
    const linkB = await linkApple(c, b.guestToken, sub);
    expect(linkB.status).toBe(200);
    expect(linkB.body.parentAccountId).toBe(accountId);
    const parentB = bearer(linkB.body.parentToken);
    const entB = await c.api('GET', '/v1/me/entitlements', undefined, parentB);
    expect(entB.body).toMatchObject({ plan: 'FAMILY', paid: true, expires_at: entA.body.expires_at });
    expect((await c.api('GET', '/v1/me/purchase-identity', undefined, parentB)).body).toEqual(idA.body);

    // Restore did not duplicate anything: one identity mapping, one parent, one progress row, two installations.
    expect(await count('SELECT COUNT(*) n FROM identity_providers WHERE account_id=?', accountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM parent_accounts WHERE id=?', accountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM accounts WHERE id=?', accountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM parent_profiles WHERE account_id=?', accountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM account_learning_progress WHERE account_id=?', accountId)).toBe(1);
    expect(await count("SELECT COUNT(*) n FROM installations WHERE account_id=? AND status='active'", accountId)).toBe(2);
    expect(await count("SELECT COUNT(*) n FROM guest_accounts WHERE merged_into=? AND status='linked'", accountId)).toBe(2);
    expect(await count("SELECT COUNT(*) n FROM entitlements WHERE parent_id=? AND status='active'", accountId)).toBe(1);

    // Reinstall on device A: the secure store is gone, so a NEW installation id and a new guest; linking again lands on the same account.
    const a2 = await firstInstall(c);
    expect(a2.installationId).not.toBe(a.installationId);
    const linkA2 = await linkApple(c, a2.guestToken, sub);
    expect(linkA2.status).toBe(200);
    expect(linkA2.body.parentAccountId).toBe(accountId);
    expect((await c.api('GET', '/v1/me/entitlements', undefined, bearer(linkA2.body.parentToken))).body.plan).toBe('FAMILY');
    expect(await count("SELECT COUNT(*) n FROM installations WHERE account_id=? AND status='active'", accountId)).toBe(3);
    expect(await count('SELECT COUNT(*) n FROM account_learning_progress WHERE account_id=?', accountId)).toBe(1);
    expect(await count('SELECT COUNT(*) n FROM identity_providers WHERE account_id=?', accountId)).toBe(1);
    // The old installation row is untouched (a reinstall is not a revoke).
    expect(await env.DB.prepare('SELECT account_id,status FROM installations WHERE installation_id=?').bind(a.installationId).first()).toEqual({ account_id: accountId, status: 'active' });
  });

  it('a guest whose Apple subject already belongs to another linked family joins that family; a linked guest cannot be re-linked elsewhere', async () => {
    serveJwks();
    const c = makeClient({ defaultToken: null, env: IDENTITY_ENV });
    const sub = `apple-sub-family-${crypto.randomUUID()}`;
    const first = await firstInstall(c);
    const linkFirst = await linkApple(c, first.guestToken, sub);
    expect(linkFirst.status).toBe(200);
    const second = await firstInstall(c);
    const linkSecond = await linkApple(c, second.guestToken, sub);
    expect(linkSecond.status).toBe(200);
    expect(linkSecond.body.parentAccountId).toBe(linkFirst.body.parentAccountId);
    // A different subject with the already-linked guest token: no silent move of data.
    const move = await linkApple(c, second.guestToken, `${sub}-other`);
    expect(move.status).toBe(401);
    expect(await env.DB.prepare('SELECT merged_into FROM guest_accounts WHERE id=?').bind(second.guestAccountId).first()).toEqual({ merged_into: linkFirst.body.parentAccountId });
  });
});

describe('identity e2e: no fabricated Apple / Google sign-in', () => {
  it('answers 501 for apple/google sign-in and link until the audiences are configured; a wrong audience is 403', async () => {
    serveJwks();
    const unconfigured = makeClient({ defaultToken: null, env: NO_IDENTITY_ENV });
    const g = await firstInstall(unconfigured);
    const token = await appleToken(unconfigured, `apple-sub-unconfigured-${g.installationId}`);

    const apple = await unconfigured.api('POST', '/v1/parents', { provider: 'apple', identityToken: token }, noToken);
    expect(apple.status).toBe(501);
    expect(apple.body.error.code).toBe('not_implemented');
    expect(apple.body.error.message).toMatch(/APPLE_BUNDLE_ID/);
    const google = await unconfigured.api('POST', '/v1/parents', { provider: 'google', identityToken: token }, noToken);
    expect(google.status).toBe(501);
    expect(google.body.error.code).toBe('not_implemented');
    expect(google.body.error.message).toMatch(/GOOGLE_CLIENT_IDS/);

    // The link route reports the same condition as 501 but labels it `not_approved` (GAP: code mismatch, identity.ts).
    const link = await unconfigured.api('POST', '/v1/auth/link', { provider: 'apple', identityToken: token }, bearer(g.guestToken));
    expect(link.status).toBe(501);
    expect(link.body.error).toMatchObject({ code: 'not_approved', reason: 'not_configured' });
    expect(await env.DB.prepare('SELECT status FROM guest_accounts WHERE id=?').bind(g.guestAccountId).first()).toEqual({ status: 'active' });

    // There is no dev provider for linking: a guest cannot be linked on the dev server without a real token.
    const dev = await unconfigured.api('POST', '/v1/auth/link', { provider: 'dev', identityToken: 'x' }, bearer(g.guestToken));
    expect(dev.status).toBe(400);

    // Configured, but the token was minted for another app: refused, nothing created.
    const configured = makeClient({ defaultToken: null, env: IDENTITY_ENV });
    const appleParentsBefore = await count("SELECT COUNT(*) n FROM parent_accounts WHERE provider='apple'");
    const foreign = await signJws(key, { iss: 'https://appleid.apple.com', aud: 'com.other.app', sub: 'apple-foreign', exp: configured.clock.now() / 1000 + 600, iat: configured.clock.now() / 1000 - 5 });
    const rejected = await configured.api('POST', '/v1/parents', { provider: 'apple', identityToken: foreign }, noToken);
    expect(rejected.status).toBe(403);
    expect(rejected.body.error).toMatchObject({ code: 'not_approved', reason: 'wrong_audience' });
    expect(await count("SELECT COUNT(*) n FROM parent_accounts WHERE provider='apple'")).toBe(appleParentsBefore);
  });
});
