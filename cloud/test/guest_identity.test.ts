import { describe, expect, it } from 'vitest';
import { makeClient, T0, uniqueId } from './helpers';
import { mergeGuest } from '../src/routes/identity';
import { hmacHex } from '../src/util/crypto';

const installId = () => crypto.randomUUID();

describe('guest identity', () => {
  it('creates a server guest, registers an installation and resumes without duplicating it', async () => {
    const c = makeClient({ defaultToken: null });
    const installationId = installId();
    const first = await c.api('POST', '/v1/auth/guest', { installationId, platform: 'ios', appVersion: '1.2.3' });
    expect(first.status).toBe(201);
    expect(first.body).toMatchObject({ installationId, accountType: 'guest' });
    expect(first.body.guestAccountId).not.toBe(installationId);
    expect(first.body.guestToken).toMatch(/^gt1\./);
    const resumed = await c.api('POST', '/v1/auth/guest', { installationId, platform: 'ios', appVersion: '1.2.4' });
    expect(resumed.status).toBe(200);
    expect(resumed.body.guestAccountId).toBe(first.body.guestAccountId);
    const row = await c.env.DB.prepare('SELECT app_version FROM installations WHERE installation_id=?').bind(installationId).first<{ app_version: string }>();
    expect(row?.app_version).toBe('1.2.4');
  });

  it('does not accept hardware-shaped identifiers and detects altered/replayed guest tokens', async () => {
    const c = makeClient({ defaultToken: null });
    expect((await c.api('POST', '/v1/auth/guest', { installationId: 'imei-356938035643809', platform: 'ios' })).status).toBe(400);
    const made = await c.api('POST', '/v1/auth/guest', { installationId: installId(), platform: 'android' });
    const token = `${made.body.guestToken.slice(0, -1)}x`;
    const replay = await c.api('GET', '/v1/me/entitlements', undefined, { authorization: `Bearer ${token}` });
    expect(replay.status).toBe(401);
  });

  it('gives guests only FREE non-purchasable entitlement and blocks subscription identity', async () => {
    const c = makeClient({ defaultToken: null });
    const made = await c.api('POST', '/v1/auth/guest', { installationId: installId(), platform: 'ios' });
    const h = { authorization: `Bearer ${made.body.guestToken}` };
    const ent = await c.api('GET', '/v1/me/entitlements', undefined, h);
    expect(ent.status).toBe(200);
    expect(ent.body).toMatchObject({ accountType: 'guest', plan: 'FREE', paid: false, canPurchase: false, premiumLiveTrial: false });
    expect((await c.api('GET', '/v1/me/purchase-identity', undefined, h)).status).toBe(403);
  });
});

describe('deterministic guest merge', () => {
  it('uses strongest mastery, unions unlocks, deduplicates awards, keeps parent settings, and imports usage once', async () => {
    const c = makeClient({ defaultToken: null });
    const suffix = uniqueId('merge');
    const guestId = `guest-${suffix}`;
    const accountId = `account-${suffix}`;
    const iid = installId();
    await c.env.DB.batch([
      c.env.DB.prepare("INSERT INTO accounts(id,status,created_at,updated_at) VALUES (?,'active',?,?)").bind(accountId, T0, T0),
      c.env.DB.prepare("INSERT INTO guest_accounts(id,status,created_at,updated_at) VALUES (?,'active',?,?)").bind(guestId, T0, T0),
      c.env.DB.prepare("INSERT INTO installations(installation_id,platform,guest_account_id,created_at,last_seen_at,status) VALUES (?,'ios',?,?,?,'active')").bind(iid, guestId, T0, T0),
      c.env.DB.prepare('INSERT INTO guest_learning_progress VALUES (?,?,?,?,?,?,?)').bind(guestId, 'colors', 0.9, T0, T0, 2, T0),
      c.env.DB.prepare('INSERT INTO account_learning_progress VALUES (?,?,?,?,?,?,?)').bind(accountId, 'colors', 0.6, T0 + 1000, null, 5, T0),
      c.env.DB.prepare('INSERT INTO guest_reward_awards VALUES (?,?,?,?)').bind(guestId, 'award-1', 'star', T0),
      c.env.DB.prepare('INSERT INTO account_reward_awards VALUES (?,?,?,?)').bind(accountId, 'award-1', 'star', T0),
      c.env.DB.prepare('INSERT INTO guest_unlocks VALUES (?,?,?)').bind(guestId, 'hat-blue', T0),
      c.env.DB.prepare('INSERT INTO guest_settings VALUES (?,?,?,?)').bind(guestId, 'speechLocale', '"en-GB"', T0),
      c.env.DB.prepare('INSERT INTO account_settings VALUES (?,?,?,?)').bind(accountId, 'speechLocale', '"en-US"', T0),
      c.env.DB.prepare('INSERT INTO guest_ai_usage VALUES (?,?,?,?,?,?)').bind(guestId, '2027-01', 120, 10, 20, T0),
    ]);
    await mergeGuest(c.env.DB, guestId, accountId, iid, T0 + 2000);
    await mergeGuest(c.env.DB, guestId, accountId, iid, T0 + 3000); // idempotent retry
    const progress = await c.env.DB.prepare('SELECT mastery,stars FROM account_learning_progress WHERE account_id=?').bind(accountId).first<{ mastery: number; stars: number }>();
    expect(progress).toEqual({ mastery: 0.9, stars: 5 });
    expect((await c.env.DB.prepare('SELECT COUNT(*) n FROM account_reward_awards WHERE account_id=?').bind(accountId).first<{ n: number }>())?.n).toBe(1);
    expect((await c.env.DB.prepare('SELECT value_json FROM account_settings WHERE account_id=? AND setting_key=\'speechLocale\'').bind(accountId).first<{ value_json: string }>())?.value_json).toBe('"en-US"');
    expect((await c.env.DB.prepare('SELECT COUNT(*) n FROM account_ai_usage_imports WHERE guest_account_id=?').bind(guestId).first<{ n: number }>())?.n).toBe(1);
    expect((await c.env.DB.prepare('SELECT standard_seconds FROM account_ai_usage WHERE account_id=?').bind(accountId).first<{ standard_seconds: number }>())?.standard_seconds).toBe(120);
    const linked = await c.env.DB.prepare('SELECT status,merged_into FROM guest_accounts WHERE id=?').bind(guestId).first();
    expect(linked).toEqual({ status: 'linked', merged_into: accountId });
  });

  it('refuses linking the same guest to a different account', async () => {
    const c = makeClient({ defaultToken: null });
    const guestId = uniqueId('guest'); const accountA = uniqueId('account-a'); const accountB = uniqueId('account-b'); const iid = installId();
    await c.env.DB.batch([
      c.env.DB.prepare("INSERT INTO accounts VALUES (?,'active',?,?,NULL)").bind(accountA, T0, T0),
      c.env.DB.prepare("INSERT INTO accounts VALUES (?,'active',?,?,NULL)").bind(accountB, T0, T0),
      c.env.DB.prepare("INSERT INTO guest_accounts(id,status,merged_into,created_at,updated_at,linked_at) VALUES (?,'linked',?,?,?,?)").bind(guestId, accountA, T0, T0, T0),
    ]);
    await expect(mergeGuest(c.env.DB, guestId, accountB, iid, T0)).rejects.toMatchObject({ status: 409 });
  });
});

describe('subscription-safe parent identity', () => {
  it('returns a stable Apple UUID and keyed Google marker across devices without PII', async () => {
    const c = makeClient({ defaultToken: null });
    const accountId = uniqueId('parent-account');
    await c.env.DB.prepare("INSERT INTO accounts(id,status,created_at,updated_at) VALUES (?,'active',?,?)").bind(accountId, T0, T0).run();
    // TokenService is the production implementation; no test-only auth bypass.
    const { TokenService } = await import('../src/auth/tokens');
    const parentToken = await new TokenService('test-only-parent-token-secret-not-for-deployment', true).mintParent(accountId, T0, 3600);
    const h = { authorization: `Bearer ${parentToken}` };
    const one = await c.api('GET', '/v1/me/purchase-identity', undefined, h);
    const two = await c.api('GET', '/v1/me/purchase-identity', undefined, h);
    expect(one.status).toBe(200);
    expect(one.body).toEqual(two.body);
    expect(one.body.apple.appAccountToken).toMatch(/^[0-9a-f-]{36}$/i);
    expect(one.body.google.obfuscatedAccountId).toBe(await hmacHex('test-only-parent-token-secret-not-for-deployment', 'google-obfuscated-account-id', accountId));
    expect(JSON.stringify(one.body)).not.toContain(accountId);
  });

  it('stores premium trial state on the parent account, independent of installations', async () => {
    const c = makeClient({ defaultToken: null });
    const accountId = uniqueId('trial-account');
    const i1 = installId(); const i2 = installId();
    await c.env.DB.batch([
      c.env.DB.prepare("INSERT INTO accounts(id,status,created_at,updated_at) VALUES (?,'active',?,?)").bind(accountId, T0, T0),
      c.env.DB.prepare("INSERT INTO account_trials(account_id,trial_key,status,started_at,expires_at,updated_at) VALUES (?,'premium_live','active',?,?,?)").bind(accountId, T0, T0 + 86400000, T0),
      c.env.DB.prepare("INSERT INTO installations(installation_id,platform,account_id,created_at,last_seen_at,status) VALUES (?,'ios',?,?,?,'active')").bind(i1, accountId, T0, T0),
      c.env.DB.prepare("INSERT INTO installations(installation_id,platform,account_id,created_at,last_seen_at,status) VALUES (?,'ios',?,?,?,'active')").bind(i2, accountId, T0, T0),
    ]);
    await c.env.DB.prepare('DELETE FROM installations WHERE installation_id=?').bind(i1).run(); // uninstall
    const trial = await c.env.DB.prepare("SELECT status,expires_at FROM account_trials WHERE account_id=? AND trial_key='premium_live'").bind(accountId).first();
    expect(trial).toEqual({ status: 'active', expires_at: T0 + 86400000 });
    expect((await c.env.DB.prepare('SELECT account_id FROM installations WHERE installation_id=?').bind(i2).first<{ account_id: string }>())?.account_id).toBe(accountId);
  });
});
