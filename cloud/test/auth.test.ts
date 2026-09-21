import { describe, expect, it } from 'vitest';
import { DEV_TOKEN, T0, createSession, makeClient, signInFamily } from './helpers';
import { TokenService } from '../src/auth/tokens';

const SECRET = 'test-only-parent-token-secret-not-for-deployment';

describe('health', () => {
  it('GET /healthz needs no token and reports the dev shape in DEV_MODE', async () => {
    const c = makeClient({ defaultToken: null });
    const r = await c.api('GET', '/healthz');
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ ok: true, service: 'little-days-cloud', apiVersion: 'v1', devMode: true, provider: 'mock', lessons: 6, billingEnabled: false });
  });

  it('GET /healthz?db=1 proves the D1 binding and counts applied migrations', async () => {
    const c = makeClient({ defaultToken: null });
    const r = await c.api('GET', '/healthz?db=1');
    expect(r.status).toBe(200);
    expect(r.body.db.ok).toBe(true);
    expect(r.body.db.migrations).toBeGreaterThanOrEqual(4);
  });

  it('GET /v1/health outside DEV_MODE is the minimal shape', async () => {
    const c = makeClient({ defaultToken: null, env: { DEV_MODE: '0' } });
    const r = await c.api('GET', '/v1/health');
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ ok: true, apiVersion: 'v1' });
  });
});

const PROTECTED: Array<[string, string, unknown]> = [
  ['GET', '/v1/parents/me', undefined],
  ['POST', '/v1/parents/approval', { clientId: 'x' }],
  ['GET', '/v1/children', undefined],
  ['POST', '/v1/children', { nickname: 'Bud' }],
  ['GET', '/v1/devices', undefined],
  ['POST', '/v1/devices', { clientId: 'x' }],
  ['GET', '/v1/consent', undefined],
  ['PUT', '/v1/consent', { kind: 'privacy', granted: true }],
  ['GET', '/v1/entitlements', undefined],
  ['GET', '/v1/tutor/quota', undefined],
  ['GET', '/v1/tutor/entitlement?clientId=x', undefined],
  ['POST', '/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId: 'x' }],
  ['POST', '/v1/tutor/sessions/00000000-0000-0000-0000-000000000000/turns', {}],
  ['POST', '/v1/tutor/sessions/00000000-0000-0000-0000-000000000000/end', {}],
  ['POST', '/v1/tutor/realtime/token', { lessonId: 'colors_red_blue', clientId: 'x' }],
  ['GET', '/v1/progress', undefined],
  ['PUT', '/v1/progress', { lessonId: 'colors_red_blue' }],
  ['DELETE', '/v1/tutor/clients/x', undefined],
  ['POST', '/v1/billing/verify', {}],
  ['POST', '/v1/dev/entitlements', { entitlement: 'free' }],
];

describe('parent credential required', () => {
  it.each(PROTECTED)('%s %s -> 403 not_approved without a token', async (method, path, body) => {
    const c = makeClient({ defaultToken: null });
    const r = await c.api(method, path, body);
    expect(r.status).toBe(403);
    expect(r.body.error.code).toBe('not_approved');
  });

  it('malformed, wrong-prefix and tampered tokens are refused', async () => {
    const c = makeClient({ defaultToken: null });
    for (const t of ['nope', 'pa1.x', 'pt1.abc.def', 'pa1.e30.0000']) {
      const r = await c.api('GET', '/v1/children', undefined, { 'x-parent-approval': t });
      expect(r.status, t).toBe(403);
    }
    const fam = await signInFamily(c, 'tamper');
    const tampered = fam.approvalToken.slice(0, -2) + (fam.approvalToken.endsWith('a') ? 'bb' : 'aa');
    expect((await c.api('GET', '/v1/children', undefined, { 'x-parent-approval': tampered })).status).toBe(403);
  });

  it('an expired approval token is refused and an expired bearer too', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'expiry');
    expect((await c.api('GET', '/v1/children', undefined, { 'x-parent-approval': fam.approvalToken })).status).toBe(200);
    c.clock.advance(31 * 24 * 3600);
    const r = await c.api('GET', '/v1/children', undefined, { 'x-parent-approval': fam.approvalToken });
    expect(r.status).toBe(403);
    const b = await c.api('GET', '/v1/parents/me', undefined, fam.bearer);
    expect(b.status).toBe(403);
  });

  it('an approval token bound to another clientId cannot start a session (no quota-reset trick)', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'bind', 'device-1');
    const r = await createSession(c, { clientId: 'device-2', token: fam.approvalToken });
    expect(r.status).toBe(403);
    expect(r.body.error.code).toBe('not_approved');
    const ok = await createSession(c, { clientId: 'device-1', token: fam.approvalToken });
    expect(ok.status).toBe(201);
  });

  it('the token may travel in the body as parentApprovalToken (Godot cloud_quota_client.gd)', async () => {
    const c = makeClient({ defaultToken: null });
    const r = await c.api('POST', '/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId: 'ipad-demo', parentApprovalToken: DEV_TOKEN });
    expect(r.status).toBe(201);
  });

  it('the dev literal token is refused outside DEV_MODE', async () => {
    const c = makeClient({ env: { DEV_MODE: '0' } });
    const r = await c.api('GET', '/v1/children');
    expect(r.status).toBe(403);
  });

  it('bearer parent tokens work on account routes and identify the parent', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'bearer');
    const r = await c.api('GET', '/v1/parents/me', undefined, fam.bearer);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ parentId: fam.parentId, provider: 'dev', via: 'bearer' });
  });

  it('a bearer alone cannot start tutor time: tutor routes need the approval token', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'bearer-only');
    const r = await c.api('POST', '/v1/tutor/sessions', { lessonId: 'colors_red_blue', clientId: fam.clientId }, fam.bearer);
    expect(r.status).toBe(403);
    expect(r.body.error.code).toBe('not_approved');
  });
});

describe('sign-in placeholder', () => {
  it('dev sign-in returns a parent token and an approval token bound to the clientId', async () => {
    const c = makeClient({ defaultToken: null });
    const r = await c.api('POST', '/v1/parents', { provider: 'dev', subject: 'owner-1', clientId: 'ipad-1' });
    expect(r.status).toBe(201);
    expect(r.body.parentToken).toMatch(/^pt1\./);
    expect(r.body.parentApprovalToken).toMatch(/^pa1\./);
    expect(r.body.created).toBe(true);
    const again = await c.api('POST', '/v1/parents', { provider: 'dev', subject: 'owner-1' });
    expect(again.body.parentId).toBe(r.body.parentId);
    expect(again.body.created).toBe(false);
    expect(again.body.parentApprovalToken).toBeUndefined();
  });

  it('apple / google identity tokens are 501 until wired; unknown providers 400', async () => {
    const c = makeClient({ defaultToken: null });
    expect((await c.api('POST', '/v1/parents', { provider: 'apple', identityToken: 'x' })).status).toBe(501);
    expect((await c.api('POST', '/v1/parents', { provider: 'google', identityToken: 'x' })).status).toBe(501);
    expect((await c.api('POST', '/v1/parents', { provider: 'facebook' })).status).toBe(400);
  });

  it('dev sign-in is 501 outside DEV_MODE and 503 without PARENT_TOKEN_SECRET', async () => {
    const prod = makeClient({ defaultToken: null, env: { DEV_MODE: '0' } });
    expect((await prod.api('POST', '/v1/parents', { provider: 'dev', subject: 'x' })).status).toBe(501);
    const noSecret = makeClient({ defaultToken: null, env: { PARENT_TOKEN_SECRET: '' } });
    const r = await noSecret.api('POST', '/v1/parents', { provider: 'dev', subject: 'x' });
    expect(r.status).toBe(503);
    expect(r.body.error.code).toBe('provider_unavailable');
  });

  it('the pa1 token keeps the prototype format (prefix.base64url-json.hex-hmac with sub/iat/exp)', async () => {
    const tokens = new TokenService(SECRET, false);
    const tok = await tokens.mintApproval({ clientId: 'ipad-demo', parentId: 'p1', childId: 'c1' }, T0, 3600);
    const [prefix, body, sig] = tok.split('.');
    expect(prefix).toBe('pa1');
    expect(sig).toMatch(/^[0-9a-f]{64}$/);
    const claims = JSON.parse(atob(body.replace(/-/g, '+').replace(/_/g, '/')));
    expect(claims).toMatchObject({ sub: 'ipad-demo', pid: 'p1', cid: 'c1', iat: Math.floor(T0 / 1000), exp: Math.floor(T0 / 1000) + 3600 });
    expect((await tokens.verifyApproval(tok, T0 + 1000, 'ipad-demo')).ok).toBe(true);
    expect((await tokens.verifyApproval(tok, T0 + 1000, 'other')).ok).toBe(false);
    expect((await tokens.verifyApproval(tok, T0 + 3601 * 1000, 'ipad-demo')).ok).toBe(false);
    expect((await tokens.verifyApproval('dev-parent-approval', T0, 'x')).ok).toBe(false);
  });
});

describe('request hygiene', () => {
  it('bodies over the cap are 413 and non-JSON bodies are 400', async () => {
    const c = makeClient();
    const big = JSON.stringify({ transcript: 'a'.repeat(40_000) });
    const r = await c.api('POST', '/v1/tutor/sessions', big);
    expect(r.status).toBe(413);
    expect(r.body.error.code).toBe('payload_too_large');
    const bad = await c.api('POST', '/v1/tutor/sessions', '{not json');
    expect(bad.status).toBe(400);
    expect(bad.body.error.code).toBe('bad_request');
  });

  it('unknown routes are 404 not_found JSON and dev routes vanish outside DEV_MODE', async () => {
    const c = makeClient();
    const r = await c.api('GET', '/v1/nope');
    expect(r.status).toBe(404);
    expect(r.body.error.code).toBe('not_found');
    const prod = makeClient({ defaultToken: null, env: { DEV_MODE: '0' } });
    const fam = await signInFamily(makeClient({ defaultToken: null }), 'prod-dev-routes');
    const d = await prod.api('GET', '/v1/dev/spend', undefined, fam.bearer);
    expect(d.status).toBe(404);
  });

  it('per-IP rate limit answers 429 rate_limited with Retry-After', async () => {
    const c = makeClient({ env: { RATE_LIMIT_IP_PER_MINUTE: '3' }, ip: '203.0.113.9' });
    for (let i = 0; i < 3; i += 1) expect((await c.api('GET', '/v1/children')).status).toBe(200);
    const r = await c.api('GET', '/v1/children');
    expect(r.status).toBe(429);
    expect(r.body.error.code).toBe('rate_limited');
    expect(Number(r.headers.get('retry-after'))).toBeGreaterThan(0);
    c.clock.advance(61);
    expect((await c.api('GET', '/v1/children')).status).toBe(200);
  });

  it('CORS headers are never emitted (native clients only)', async () => {
    const c = makeClient({ defaultToken: null });
    const r = await c.api('GET', '/healthz', undefined, { origin: 'https://evil.example' });
    expect(r.headers.get('access-control-allow-origin')).toBeNull();
  });
});
