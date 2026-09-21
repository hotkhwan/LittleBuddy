import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { makeClient, signInFamily } from './helpers';

describe('children', () => {
  it('creates nickname-only profiles and lists them', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'kids');
    const r = await c.api('POST', '/v1/children', { nickname: 'Bunny', avatarId: 'bear_01', birthYearBucket: '2020-2021', locale: 'th-TH' }, fam.bearer);
    expect(r.status).toBe(201);
    expect(r.body).toMatchObject({ nickname: 'Bunny', avatarId: 'bear_01', birthYearBucket: '2020-2021', locale: 'th-TH' });
    const list = await c.api('GET', '/v1/children', undefined, fam.bearer);
    expect(list.body.children).toHaveLength(1);
    const cols = (await env.DB.prepare('PRAGMA table_info(child_profiles)').all<{ name: string }>()).results.map((x) => x.name);
    expect(cols).not.toContain('name');
    expect(cols).not.toContain('birth_date');
  });

  it('rejects contact details, over-long nicknames, bad buckets and more than 6 profiles', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'kids-limits');
    expect((await c.api('POST', '/v1/children', { nickname: 'me@example.com' }, fam.bearer)).status).toBe(400);
    expect((await c.api('POST', '/v1/children', { nickname: 'x'.repeat(25) }, fam.bearer)).status).toBe(400);
    expect((await c.api('POST', '/v1/children', { nickname: 'Bud', birthYearBucket: '2020-05-01' }, fam.bearer)).status).toBe(400);
    for (let i = 0; i < 6; i += 1) expect((await c.api('POST', '/v1/children', { nickname: `Kid ${i}` }, fam.bearer)).status).toBe(201);
    expect((await c.api('POST', '/v1/children', { nickname: 'Seventh' }, fam.bearer)).status).toBe(400);
  });

  it('a device approval token can read children but not another family\'s', async () => {
    const c = makeClient({ defaultToken: null });
    const a = await signInFamily(c, 'fam-a');
    const b = await signInFamily(c, 'fam-b');
    await c.api('POST', '/v1/children', { nickname: 'A1' }, a.bearer);
    const viaA = await c.api('GET', '/v1/children', undefined, { 'x-parent-approval': a.approvalToken });
    const viaB = await c.api('GET', '/v1/children', undefined, { 'x-parent-approval': b.approvalToken });
    expect(viaA.body.children).toHaveLength(1);
    expect(viaB.body.children).toHaveLength(0);
  });
});

describe('devices', () => {
  it('registers a device (platform, appVersion only) and refuses a device claimed by another family', async () => {
    const c = makeClient({ defaultToken: null });
    const a = await signInFamily(c, 'dev-a', 'ipad-shared');
    const b = await signInFamily(c, 'dev-b', 'ipad-shared');
    const r = await c.api('POST', '/v1/devices', { clientId: 'ipad-shared', platform: 'ios', appVersion: '0.9.3' }, a.bearer);
    expect(r.status).toBe(201);
    expect(r.body).toMatchObject({ deviceId: 'ipad-shared', platform: 'ios', appVersion: '0.9.3' });
    const conflict = await c.api('POST', '/v1/devices', { clientId: 'ipad-shared', platform: 'ios' }, b.bearer);
    expect(conflict.status).toBe(409);
    expect(conflict.body.error.code).toBe('conflict');
    expect((await c.api('POST', '/v1/devices', { clientId: 'x', platform: 'windows' }, a.bearer)).status).toBe(400);
    const list = await c.api('GET', '/v1/devices', undefined, a.bearer);
    expect(list.body.devices.map((d: { deviceId: string }) => d.deviceId)).toEqual(['ipad-shared']);
    const cols = (await env.DB.prepare('PRAGMA table_info(devices)').all<{ name: string }>()).results.map((x) => x.name);
    expect(cols).not.toContain('push_token');
  });
});

describe('consent', () => {
  it('starts empty, PUT grants per kind, revoke clears, GET reflects the required version', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'consent', 'd', []);
    let r = await c.api('GET', '/v1/consent', undefined, fam.bearer);
    expect(r.body.requiredVersion).toBe(1);
    expect(r.body.consent.ai_tutor.granted).toBe(false);
    r = await c.api('PUT', '/v1/consent', { kind: 'ai_tutor', version: 1, granted: true }, fam.bearer);
    expect(r.status).toBe(200);
    expect(r.body.consent.ai_tutor).toMatchObject({ granted: true, version: 1, revokedAt: null });
    r = await c.api('PUT', '/v1/consent', { kind: 'ai_tutor', granted: false }, fam.bearer);
    expect(r.body.consent.ai_tutor.granted).toBe(false);
    expect(r.body.consent.ai_tutor.revokedAt).not.toBeNull();
    expect((await c.api('PUT', '/v1/consent', { kind: 'marketing', granted: true }, fam.bearer)).status).toBe(400);
  });

  it('consent changes need the parent sign-in, not a device approval', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'consent-bearer');
    const r = await c.api('PUT', '/v1/consent', { kind: 'voice', granted: false }, { 'x-parent-approval': fam.approvalToken });
    expect(r.status).toBe(403);
    expect((await c.api('GET', '/v1/consent', undefined, { 'x-parent-approval': fam.approvalToken })).status).toBe(200);
  });

  it('a parent who has not granted ai_tutor consent gets 403 consent_required at session start', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'no-consent', 'dev-nc', ['privacy']);
    const r = await c.api('POST', '/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId: 'dev-nc' }, { 'x-parent-approval': fam.approvalToken });
    expect(r.status).toBe(403);
    expect(r.body.error.code).toBe('consent_required');
    expect(r.body.error.kind).toBe('ai_tutor');
  });
});

describe('entitlements', () => {
  it('reports free by default with the configured price hint and billing disabled', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'ent');
    const r = await c.api('GET', '/v1/entitlements', undefined, fam.bearer);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ entitlement: 'free', activeUntil: null, billing: { enabled: false } });
    expect(r.body.products[0]).toEqual({ productId: 'little_days.family_club.monthly', priceHint: { currency: 'THB', monthly: 99, status: 'proposed' } });
    expect(r.body.allowances).toEqual({ free: { dailySeconds: 300, dailyTurns: 60 }, family_club: { dailySeconds: 1800, dailyTurns: 360 } });
  });

  it('price hint comes from config, not code', async () => {
    const c = makeClient({ defaultToken: null, env: { FAMILY_CLUB_PRICE_MONTHLY: '129', FAMILY_CLUB_PRICE_STATUS: 'approved' } });
    const fam = await signInFamily(c, 'ent-cfg');
    const r = await c.api('GET', '/v1/entitlements', undefined, fam.bearer);
    expect(r.body.products[0].priceHint).toEqual({ currency: 'THB', monthly: 129, status: 'approved' });
  });

  it('a dev grant switches to family_club until period_end, then falls back to free', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'ent-grant');
    const g = await c.api('POST', '/v1/dev/entitlements', { entitlement: 'family_club', days: 2 }, fam.bearer);
    expect(g.status).toBe(200);
    let r = await c.api('GET', '/v1/entitlements', undefined, fam.bearer);
    expect(r.body.entitlement).toBe('family_club');
    expect(r.body.source).toBe('dev');
    c.clock.advance(3 * 86_400);
    r = await c.api('GET', '/v1/entitlements', undefined, fam.bearer);
    expect(r.body.entitlement).toBe('free');
  });
});

describe('progress', () => {
  it('PUT upserts monotonically and GET lists per child', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'prog');
    const kid = await c.api('POST', '/v1/children', { nickname: 'Pip' }, fam.bearer);
    const childId = kid.body.childId;
    let r = await c.api('PUT', '/v1/progress', { childId, lessonId: 'colors_red_blue', stepIndex: 2, stars: 1 }, fam.bearer);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ childId, lessonId: 'colors_red_blue', stepIndex: 2, stars: 1, completedAt: null });
    r = await c.api('PUT', '/v1/progress', { childId, lessonId: 'colors_red_blue', stepIndex: 1, stars: 0, completed: true }, fam.bearer);
    expect(r.body.stepIndex).toBe(2);
    expect(r.body.stars).toBe(1);
    expect(r.body.completedAt).not.toBeNull();
    const list = await c.api('GET', `/v1/progress?childId=${childId}`, undefined, fam.bearer);
    expect(list.body.progress).toHaveLength(1);
    expect((await c.api('PUT', '/v1/progress', { childId, lessonId: 'not_a_lesson' }, { ...fam.bearer })).status).toBe(200); // DEV_MODE accepts unknown lessons
    const prod = makeClient({ defaultToken: null, env: { DEV_MODE: '0' } });
    expect((await prod.api('PUT', '/v1/progress', { childId, lessonId: 'not_a_lesson' }, fam.bearer)).status).toBe(400);
  });

  it('a child of another family is 404', async () => {
    const c = makeClient({ defaultToken: null });
    const a = await signInFamily(c, 'prog-a');
    const b = await signInFamily(c, 'prog-b');
    const kid = await c.api('POST', '/v1/children', { nickname: 'Pip' }, a.bearer);
    const r = await c.api('GET', `/v1/progress?childId=${kid.body.childId}`, undefined, b.bearer);
    expect(r.status).toBe(404);
  });
});
