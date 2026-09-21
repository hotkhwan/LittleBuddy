// Parent accounts: sign-in verification wired into POST /v1/parents, hashed
// storage, export, deletion cascade + tombstone, child deletion.
import { env } from 'cloudflare:test';
import { afterEach, describe, expect, it } from 'vitest';
import { makeClient, signInFamily, uniqueId, type Client, type Family } from './helpers';
import { HEX64, generateTestKey, jwksDocument, signJws, type TestKey } from './identity_keys';
import { hashEmail, hashSubject } from '../src/auth/identity';
import { expireTombstones } from '../src/db/parents';
import type { Env } from '../src/env';

const SECRET = 'test-only-parent-token-secret-not-for-deployment';
const APPLE_AUD = 'com.joinanny.littledays';
const GOOGLE_AUD = 'test-ios.apps.googleusercontent.com';
const IDENTITY_ENV = { APPLE_BUNDLE_ID: APPLE_AUD, APPLE_SERVICE_ID: 'com.joinanny.littledays.web', GOOGLE_CLIENT_IDS: `${GOOGLE_AUD},test-web.apps.googleusercontent.com` } as Partial<Env>;
const NO_IDENTITY_ENV = { APPLE_BUNDLE_ID: '', APPLE_SERVICE_ID: '', GOOGLE_CLIENT_IDS: '' } as Partial<Env>;

// One key pair for the whole file: the route uses the isolate-wide JWKS cache.
const key: TestKey = await generateTestKey('route-kid');
const realFetch = globalThis.fetch;
let jwksCalls = 0;
function serveJwks() {
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    jwksCalls += 1;
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (url === 'https://appleid.apple.com/auth/keys' || url === 'https://www.googleapis.com/oauth2/v3/certs') return new Response(JSON.stringify(jwksDocument(key)), { headers: { 'content-type': 'application/json' } });
    throw new Error(`unexpected fetch ${url}`);
  }) as typeof fetch;
}
afterEach(() => {
  globalThis.fetch = realFetch;
});

const noToken = { 'x-parent-approval': '' };
const bearerOf = (token: string) => ({ authorization: `Bearer ${token}`, 'x-parent-approval': '' });

async function appleToken(c: Client, over: Record<string, unknown> = {}) {
  const exp = c.clock.now() / 1000 + 600;
  return signJws(key, { iss: 'https://appleid.apple.com', aud: APPLE_AUD, sub: over.sub ?? uniqueId('apple-sub'), exp, iat: exp - 605, email: 'parent@example.com', email_verified: 'true', ...over });
}

async function googleToken(c: Client, over: Record<string, unknown> = {}) {
  const exp = c.clock.now() / 1000 + 600;
  return signJws(key, { iss: 'https://accounts.google.com', aud: GOOGLE_AUD, sub: over.sub ?? uniqueId('google-sub'), exp, iat: exp - 605, email: 'parent@gmail.com', email_verified: true, ...over });
}

async function parentRow(parentId: string) {
  return env.DB.prepare('SELECT * FROM parent_accounts WHERE id = ?').bind(parentId).first<{ id: string; provider: string; subject_hash: string; email_hash: string | null; deleted_at: number | null; tombstone_until: number | null; consent_version: number }>();
}

async function count(sql: string, ...binds: unknown[]) {
  return Number((await env.DB.prepare(sql).bind(...binds).first<{ n: number }>())?.n ?? 0);
}

describe('POST /v1/parents with apple / google identity tokens', () => {
  it('apple: verifies the token, creates the parent once (idempotent on subject) and stores only hashes', async () => {
    serveJwks();
    const c = makeClient({ defaultToken: null, env: IDENTITY_ENV });
    const sub = uniqueId('apple-sub');
    const first = await c.api('POST', '/v1/parents', { provider: 'apple', identityToken: await appleToken(c, { sub }), clientId: 'ipad-1' }, noToken);
    expect(first.status).toBe(201);
    expect(first.body).toMatchObject({ provider: 'apple', created: true, emailVerified: true });
    expect(first.body.parentToken).toMatch(/^pt1\./);
    expect(first.body.parentApprovalToken).toMatch(/^pa1\./);
    // Apple only sends the e-mail on the first authorization; the second token has none.
    const again = await c.api('POST', '/v1/parents', { provider: 'apple', identityToken: await appleToken(c, { sub, email: undefined, email_verified: undefined }) }, noToken);
    expect(again.status).toBe(201);
    expect(again.body.parentId).toBe(first.body.parentId);
    expect(again.body.created).toBe(false);
    const row = (await parentRow(first.body.parentId))!;
    expect(row.provider).toBe('apple');
    expect(row.subject_hash).toMatch(HEX64);
    expect(row.subject_hash).toBe(await hashSubject(SECRET, 'apple', sub));
    expect(row.email_hash).toMatch(HEX64);
    expect(row.email_hash).toBe(await hashEmail(SECRET, 'parent@example.com'));
    const cols = (await env.DB.prepare('PRAGMA table_info(parent_accounts)').all<{ name: string }>()).results.map((x) => x.name);
    expect(cols).not.toContain('email');
    expect(cols).not.toContain('subject');
    const me = await c.api('GET', '/v1/parents/me', undefined, bearerOf(first.body.parentToken));
    expect(me.body).toMatchObject({ parentId: first.body.parentId, provider: 'apple', hasEmailHash: true, childCount: 0, maxChildren: 6, tutorEntitlement: 'free' });
  });

  it('google: same contract; apple and google subjects never collide', async () => {
    serveJwks();
    const c = makeClient({ defaultToken: null, env: IDENTITY_ENV });
    const sub = uniqueId('shared-sub');
    const g = await c.api('POST', '/v1/parents', { provider: 'google', identityToken: await googleToken(c, { sub }) }, noToken);
    expect(g.status).toBe(201);
    expect(g.body).toMatchObject({ provider: 'google', created: true, emailVerified: true });
    const a = await c.api('POST', '/v1/parents', { provider: 'apple', identityToken: await appleToken(c, { sub }) }, noToken);
    expect(a.status).toBe(201);
    expect(a.body.parentId).not.toBe(g.body.parentId);
    const row = (await parentRow(g.body.parentId))!;
    expect(row.subject_hash).toMatch(HEX64);
    expect(row.email_hash).toMatch(HEX64);
  });

  it('rejects a wrong audience, an expired token, a bad token shape, and reports 501 when unconfigured', async () => {
    serveJwks();
    const c = makeClient({ defaultToken: null, env: IDENTITY_ENV });
    let r = await c.api('POST', '/v1/parents', { provider: 'apple', identityToken: await appleToken(c, { aud: 'com.other.app' }) }, noToken);
    expect(r.status).toBe(403);
    expect(r.body.error).toMatchObject({ code: 'not_approved', reason: 'wrong_audience' });
    r = await c.api('POST', '/v1/parents', { provider: 'google', identityToken: await googleToken(c, { exp: c.clock.now() / 1000 - 3600 }) }, noToken);
    expect(r.body.error).toMatchObject({ code: 'not_approved', reason: 'expired' });
    r = await c.api('POST', '/v1/parents', { provider: 'apple', identityToken: 'garbage' }, noToken);
    expect(r.status).toBe(400);
    r = await c.api('POST', '/v1/parents', { provider: 'apple' }, noToken);
    expect(r.status).toBe(400);
    expect(await count('SELECT COUNT(*) AS n FROM parent_accounts WHERE provider = ? AND subject_hash = ?', 'apple', await hashSubject(SECRET, 'apple', 'never-created'))).toBe(0);
    const unconfigured = makeClient({ defaultToken: null, env: NO_IDENTITY_ENV });
    r = await unconfigured.api('POST', '/v1/parents', { provider: 'apple', identityToken: await appleToken(c) }, noToken);
    expect(r.status).toBe(501);
    r = await unconfigured.api('POST', '/v1/parents', { provider: 'google', identityToken: await googleToken(c) }, noToken);
    expect(r.status).toBe(501);
    expect((await c.api('POST', '/v1/parents', { provider: 'facebook', identityToken: 'x' }, noToken)).status).toBe(400);
  });

  it('dev sign-in: same subject -> same parent, hashed row, refused outside DEV_MODE', async () => {
    const c = makeClient({ defaultToken: null });
    const subject = uniqueId('dev-idem');
    const a = await c.api('POST', '/v1/parents', { provider: 'dev', subject }, noToken);
    const b = await c.api('POST', '/v1/parents', { provider: 'dev', subject }, noToken);
    expect(a.status).toBe(201);
    expect(b.body.parentId).toBe(a.body.parentId);
    expect(b.body.created).toBe(false);
    const row = (await parentRow(a.body.parentId))!;
    expect(row.subject_hash).toMatch(HEX64);
    expect(row.subject_hash).not.toContain(subject);
    expect(row.email_hash).toBeNull();
    const prod = makeClient({ defaultToken: null, env: { DEV_MODE: '0' } });
    const r = await prod.api('POST', '/v1/parents', { provider: 'dev', subject }, noToken);
    expect(r.status).toBe(501);
  });
});

async function seedFamily(c: Client, fam: Family) {
  const k1 = await c.api('POST', '/v1/children', { nickname: 'Pip', avatarId: 'bear_01', birthYearBucket: '2020-2021' }, fam.bearer);
  const k2 = await c.api('POST', '/v1/children', { nickname: 'Bo' }, fam.bearer);
  expect(k1.status).toBe(201);
  expect(k2.status).toBe(201);
  const dev = await c.api('POST', '/v1/devices', { clientId: fam.clientId, platform: 'ios', appVersion: '1.0.0' }, fam.bearer);
  expect(dev.status).toBe(201);
  expect((await c.api('PUT', '/v1/progress', { childId: k1.body.childId, lessonId: 'colors_red_blue', stepIndex: 3, stars: 2 }, fam.bearer)).status).toBe(200);
  const s = await c.api('POST', '/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId: fam.clientId, childId: k1.body.childId }, { 'x-parent-approval': fam.approvalToken });
  expect(s.status).toBe(201);
  const turn = await c.api('POST', `/v1/tutor/sessions/${s.body.sessionId}/turns`, { transcript: 'red', lessonContext: { stepId: 's02_red', outcome: 'correct', matched: 'red' } }, { 'x-parent-approval': fam.approvalToken, 'idempotency-key': uniqueId('idem') });
  expect(turn.status).toBe(200);
  expect((await c.api('POST', '/v1/dev/entitlements', { entitlement: 'family_club', days: 30 }, fam.bearer)).status).toBe(200);
  await env.DB.prepare('INSERT INTO purchase_events (id, store, transaction_id, product_id, parent_id, status, payload_hash, processed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
    .bind(uniqueId('evt'), 'dev', uniqueId('txn'), 'little_days.family_club.monthly', fam.parentId, 'applied', 'deadbeef', c.clock.now()).run();
  return { child1: k1.body.childId as string, child2: k2.body.childId as string, sessionId: s.body.sessionId as string };
}

describe('GET /v1/parents/me/export', () => {
  it('returns every family row as ids and numbers, no hashes, no transcripts, bearer only', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, uniqueId('export'));
    const seeded = await seedFamily(c, fam);
    const r = await c.api('GET', '/v1/parents/me/export', undefined, fam.bearer);
    expect(r.status).toBe(200);
    expect(r.headers.get('content-disposition')).toContain('attachment');
    const body = r.body;
    expect(body.format).toBe('little-days-family-export/1');
    expect(body.parent).toEqual({ parentId: fam.parentId, provider: 'dev', consentVersion: 1, hasEmailHash: false, createdAt: expect.any(String), updatedAt: expect.any(String) });
    expect(body.children).toHaveLength(2);
    const pip = body.children.find((k: { childId: string }) => k.childId === seeded.child1);
    expect(pip).toMatchObject({ nickname: 'Pip', avatarId: 'bear_01', birthYearBucket: '2020-2021' });
    expect(pip.progress).toEqual([expect.objectContaining({ lessonId: 'colors_red_blue', stepIndex: 3, stars: 2 })]);
    expect(pip.tutorSessions).toHaveLength(1);
    expect(pip.tutorSessions[0]).toMatchObject({ sessionId: seeded.sessionId, lessonId: 'colors_red_blue', turnCount: 1 });
    expect(pip.dailyQuota.length).toBeGreaterThanOrEqual(1);
    expect(body.devices).toEqual([expect.objectContaining({ deviceId: fam.clientId, platform: 'ios', appVersion: '1.0.0' })]);
    expect(body.consent.ai_tutor.granted).toBe(true);
    expect(body.entitlements).toEqual([expect.objectContaining({ productId: 'little_days.family_club.monthly', source: 'dev', status: 'active', revokedReason: null })]);
    expect(body.purchaseEvents).toHaveLength(1);
    const text = JSON.stringify(body);
    expect(text).not.toContain('subject_hash');
    expect(text).not.toContain('email_hash');
    expect(text).not.toMatch(/transcript/i);
    expect(text).not.toMatch(/[0-9a-f]{64}/);
    // a device approval cannot export the family
    expect((await c.api('GET', '/v1/parents/me/export', undefined, { 'x-parent-approval': fam.approvalToken })).status).toBe(403);
  });
});

describe('DELETE /v1/parents/me', () => {
  it('cascades, marks entitlements revoked, unlinks purchases, tombstones for 30 days, then allows a fresh account', async () => {
    const c = makeClient({ defaultToken: null });
    const subject = uniqueId('delete-me');
    const fam = await signInFamily(c, subject);
    const seeded = await seedFamily(c, fam);
    // approval tokens cannot delete the account
    expect((await c.api('DELETE', '/v1/parents/me', undefined, { 'x-parent-approval': fam.approvalToken })).status).toBe(403);

    const del = await c.api('DELETE', '/v1/parents/me', undefined, fam.bearer);
    expect(del.status).toBe(200);
    expect(del.body).toMatchObject({ deleted: true, parentId: fam.parentId, counts: { children: 2, devices: 1, consent: 3, sessions: 1, progress: 1, entitlementsRevoked: 1, purchaseEventsUnlinked: 1 } });
    expect(del.body.counts.usageEvents).toBeGreaterThanOrEqual(1);
    expect(del.body.counts.idempotency).toBeGreaterThanOrEqual(1);
    expect(new Date(del.body.tombstoneUntil).getTime() - c.clock.now()).toBe(30 * 86_400_000);

    for (const [table, col, id] of [['child_profiles', 'parent_id', fam.parentId], ['devices', 'parent_id', fam.parentId], ['consent_status', 'parent_id', fam.parentId], ['tutor_sessions', 'child_id', seeded.child1], ['learning_progress', 'child_id', seeded.child1], ['daily_quota', 'child_id', seeded.child1], ['usage_events', 'session_id', seeded.sessionId], ['api_idempotency', 'session_id', seeded.sessionId]] as const) {
      expect(await count(`SELECT COUNT(*) AS n FROM ${table} WHERE ${col} = ?`, id), table).toBe(0);
    }
    const ent = await env.DB.prepare('SELECT status, revoked_reason FROM entitlements WHERE parent_id = ?').bind(fam.parentId).all<{ status: string; revoked_reason: string }>();
    expect(ent.results).toEqual([{ status: 'revoked', revoked_reason: 'account_deleted' }]);
    expect(await count('SELECT COUNT(*) AS n FROM purchase_events WHERE parent_id = ?', fam.parentId)).toBe(0);
    expect(await count("SELECT COUNT(*) AS n FROM purchase_events WHERE parent_id IS NULL AND store = 'dev'")).toBeGreaterThanOrEqual(1);

    const row = (await parentRow(fam.parentId))!;
    expect(row.deleted_at).toBe(c.clock.now());
    expect(row.email_hash).toBeNull();
    expect(row.consent_version).toBe(0);
    expect(row.subject_hash).toBe(await hashSubject(SECRET, 'dev', subject)); // the tombstone keeps the pair

    // the old credentials are dead
    expect((await c.api('GET', '/v1/parents/me', undefined, fam.bearer)).status).toBe(403);
    expect((await c.api('POST', '/v1/children', { nickname: 'Ghost' }, fam.bearer)).status).toBe(403);
    expect((await c.api('GET', '/v1/children', undefined, { 'x-parent-approval': fam.approvalToken })).status).toBe(403);
    expect((await c.api('DELETE', '/v1/parents/me', undefined, fam.bearer)).status).toBe(403);
    // the quota counter is gone
    const quota = await env.QUOTA.get(env.QUOTA.idFromName(seeded.child1)).snapshot({ childId: seeded.child1, nowMs: c.clock.now(), entitlement: 'free', allowanceSeconds: 300, turnAllowance: 60 });
    expect(quota.usedSeconds).toBe(0);
    expect(quota.usedTurns).toBe(0);
    // it may have re-mirrored an empty day; that mirror row is harmless but must not exist for a deleted child either
    expect(await count('SELECT COUNT(*) AS n FROM daily_quota WHERE child_id = ?', seeded.child1)).toBe(0);

    // re-sign-in inside the window: 409 with availableAt
    const blocked = await c.api('POST', '/v1/parents', { provider: 'dev', subject }, noToken);
    expect(blocked.status).toBe(409);
    expect(blocked.body.error).toMatchObject({ code: 'conflict', reason: 'account_deleted', availableAt: del.body.tombstoneUntil });
    c.clock.advance(29 * 86_400);
    expect((await c.api('POST', '/v1/parents', { provider: 'dev', subject }, noToken)).status).toBe(409);

    // after the window: a brand-new parent with nothing attached; the tombstone is anonymised (it anchors the revoked entitlement)
    c.clock.advance(2 * 86_400);
    const fresh = await c.api('POST', '/v1/parents', { provider: 'dev', subject }, noToken);
    expect(fresh.status).toBe(201);
    expect(fresh.body.created).toBe(true);
    expect(fresh.body.parentId).not.toBe(fam.parentId);
    const freshBearer = bearerOf(fresh.body.parentToken);
    expect((await c.api('GET', '/v1/children', undefined, freshBearer)).body.children).toEqual([]);
    expect((await c.api('GET', '/v1/entitlements', undefined, freshBearer)).body.entitlement).toBe('free');
    const old = (await parentRow(fam.parentId))!;
    expect(old.subject_hash).toBe(`deleted:${fam.parentId}`);
    expect(old.tombstone_until).toBeNull();
    expect(await count('SELECT COUNT(*) AS n FROM entitlements WHERE parent_id = ?', fam.parentId)).toBe(1);
  });

  it('a tombstone with no entitlement rows is dropped entirely once the window passes (own sign-in, or the retention sweep)', async () => {
    const c = makeClient({ defaultToken: null });
    const subject = uniqueId('delete-plain');
    const fam = await signInFamily(c, subject);
    expect((await c.api('DELETE', '/v1/parents/me', undefined, fam.bearer)).status).toBe(200);
    expect((await parentRow(fam.parentId))?.deleted_at).not.toBeNull();
    // another parent's sign-in never touches it, even after the window (the sweep is per subject at sign-in) ...
    c.clock.advance(31 * 86_400);
    expect((await c.api('POST', '/v1/parents', { provider: 'dev', subject: uniqueId('someone-else') }, noToken)).status).toBe(201);
    expect((await parentRow(fam.parentId))?.deleted_at).not.toBeNull();
    // ... the retention sweep (no scope) drops it, and so would the same subject's own sign-in
    const swept = await expireTombstones(env.DB, c.clock.now());
    expect(swept.deleted).toBeGreaterThanOrEqual(1);
    expect(await parentRow(fam.parentId)).toBeNull();
    const fresh = await c.api('POST', '/v1/parents', { provider: 'dev', subject }, noToken);
    expect(fresh.status).toBe(201);
    expect(fresh.body.parentId).not.toBe(fam.parentId);
  });
});

describe('children: delete, edit, cap', () => {
  it('DELETE /v1/children/:id removes the child and everything keyed by it; the slot frees up under the cap of 6', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, uniqueId('kid-del'));
    const seeded = await seedFamily(c, fam);
    for (let i = 0; i < 4; i += 1) expect((await c.api('POST', '/v1/children', { nickname: `Kid ${i}` }, fam.bearer)).status).toBe(201);
    expect((await c.api('POST', '/v1/children', { nickname: 'Seventh' }, fam.bearer)).status).toBe(400);
    expect((await c.api('DELETE', `/v1/children/${seeded.child1}`, undefined, { 'x-parent-approval': fam.approvalToken })).status).toBe(403);
    const r = await c.api('DELETE', `/v1/children/${seeded.child1}`, undefined, fam.bearer);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ deleted: true, childId: seeded.child1, counts: { sessions: 1, progress: 1 } });
    expect(await count('SELECT COUNT(*) AS n FROM tutor_sessions WHERE child_id = ?', seeded.child1)).toBe(0);
    expect(await count('SELECT COUNT(*) AS n FROM learning_progress WHERE child_id = ?', seeded.child1)).toBe(0);
    expect(await count('SELECT COUNT(*) AS n FROM usage_events WHERE session_id = ?', seeded.sessionId)).toBe(0);
    expect(await count('SELECT COUNT(*) AS n FROM child_profiles WHERE id = ?', seeded.child2)).toBe(1);
    expect((await c.api('DELETE', `/v1/children/${seeded.child1}`, undefined, fam.bearer)).status).toBe(404);
    expect((await c.api('POST', '/v1/children', { nickname: 'Seventh' }, fam.bearer)).status).toBe(201);
    expect((await c.api('POST', '/v1/children', { nickname: 'Eighth' }, fam.bearer)).status).toBe(400);
    // another family cannot delete it
    const other = await signInFamily(c, uniqueId('kid-del-other'));
    expect((await c.api('DELETE', `/v1/children/${seeded.child2}`, undefined, other.bearer)).status).toBe(404);
  });

  it('PATCH /v1/children/:id edits nickname / avatar / bucket with the same rules; GET reads one', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, uniqueId('kid-edit'));
    const kid = await c.api('POST', '/v1/children', { nickname: 'Pip', birthYearBucket: '2020-2021' }, fam.bearer);
    const id = kid.body.childId;
    let r = await c.api('PATCH', `/v1/children/${id}`, { nickname: 'Pippa', avatarId: 'cat_02' }, fam.bearer);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ childId: id, nickname: 'Pippa', avatarId: 'cat_02', birthYearBucket: '2020-2021' });
    r = await c.api('PATCH', `/v1/children/${id}`, { birthYearBucket: null }, fam.bearer);
    expect(r.body.birthYearBucket).toBeNull();
    expect((await c.api('PATCH', `/v1/children/${id}`, { nickname: 'me@example.com' }, fam.bearer)).status).toBe(400);
    expect((await c.api('PATCH', `/v1/children/${id}`, { nickname: 'X' }, { 'x-parent-approval': fam.approvalToken })).status).toBe(403);
    expect((await c.api('GET', `/v1/children/${id}`, undefined, { 'x-parent-approval': fam.approvalToken })).body.nickname).toBe('Pippa');
    expect((await c.api('GET', `/v1/children/${id}`, undefined, (await signInFamily(c, uniqueId('kid-edit-other'))).bearer)).status).toBe(404);
  });
});

describe('GET /v1/parents/me/subscription', () => {
  it('is a read-only view of the entitlement rows', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, uniqueId('sub'));
    let r = await c.api('GET', '/v1/parents/me/subscription', undefined, fam.bearer);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ entitlement: 'free', status: 'none', activeUntil: null, managedBy: null, productId: null, billing: { enabled: false }, records: [] });
    await c.api('POST', '/v1/dev/entitlements', { entitlement: 'family_club', days: 10 }, fam.bearer);
    r = await c.api('GET', '/v1/parents/me/subscription', undefined, fam.bearer);
    expect(r.body).toMatchObject({ entitlement: 'family_club', status: 'active', managedBy: 'dev', productId: 'little_days.family_club.monthly' });
    expect(r.body.activeUntil).not.toBeNull();
    c.clock.advance(11 * 86_400);
    r = await c.api('GET', '/v1/parents/me/subscription', undefined, fam.bearer);
    expect(r.body).toMatchObject({ entitlement: 'free', status: 'inactive', managedBy: null });
  });
});
