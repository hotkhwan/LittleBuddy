import { describe, expect, it } from 'vitest';
import { AppleIdentityVerifier, DevIdentityVerifier, GoogleIdentityVerifier, IdentityError, JwksClient, createIdentityVerifiers, hashEmail, hashSubject } from '../src/auth/identity';
import { HEX64, fakeJwksFetch, generateTestKey, jwksDocument, signJws } from './identity_keys';

const NOW = Date.UTC(2027, 0, 10, 10, 0, 0);
const SECRET = 'test-only-parent-token-secret-not-for-deployment';
const hasher = (email: string) => hashEmail(SECRET, email);

const keyA = await generateTestKey('kid-a');
const keyB = await generateTestKey('kid-b');
const rogue = await generateTestKey('kid-a'); // same kid, different key: a forged signature

async function failure(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return 'ok';
  } catch (e) {
    if (e instanceof IdentityError) return e.reason;
    throw e;
  }
}

describe('AppleIdentityVerifier', () => {
  const claims = (over: Record<string, unknown> = {}) => ({ iss: 'https://appleid.apple.com', aud: 'com.joinanny.littledays', sub: '001234.abcdef.5678', exp: NOW / 1000 + 600, iat: NOW / 1000 - 5, email: 'Parent@Example.com', email_verified: 'true', ...over });
  const make = (fetchImpl: typeof fetch, audiences = ['com.joinanny.littledays', 'com.joinanny.littledays.web']) =>
    new AppleIdentityVerifier({ audiences, hashEmail: hasher, now: () => NOW, jwks: new JwksClient({ url: 'https://appleid.apple.com/auth/keys', fetchImpl }) });

  it('accepts a valid identity token and hashes the verified e-mail', async () => {
    const { fetchImpl, state } = fakeJwksFetch(jwksDocument(keyA, keyB));
    const v = make(fetchImpl);
    const id = await v.verify(await signJws(keyA, claims()));
    expect(id).toMatchObject({ provider: 'apple', subject: '001234.abcdef.5678', emailVerified: true });
    expect(id.emailHash).toMatch(HEX64);
    expect(id.emailHash).toBe(await hashEmail(SECRET, 'parent@example.com')); // case-insensitive
    await v.verify(await signJws(keyB, claims()));
    expect(state.calls).toBe(1); // JWKS cached
  });

  it('accepts the web Services ID audience and an aud array', async () => {
    const v = make(fakeJwksFetch(jwksDocument(keyA)).fetchImpl);
    await expect(v.verify(await signJws(keyA, claims({ aud: 'com.joinanny.littledays.web' })))).resolves.toBeTruthy();
    await expect(v.verify(await signJws(keyA, claims({ aud: ['other', 'com.joinanny.littledays'] })))).resolves.toBeTruthy();
  });

  it('rejects wrong aud, expired, wrong iss, unknown kid, forged signature and non-RS256', async () => {
    const v = make(fakeJwksFetch(jwksDocument(keyA)).fetchImpl);
    expect(await failure(v.verify(await signJws(keyA, claims({ aud: 'com.someone.else' }))))).toBe('wrong_audience');
    expect(await failure(v.verify(await signJws(keyA, claims({ exp: NOW / 1000 - 120 }))))).toBe('expired');
    expect(await failure(v.verify(await signJws(keyA, claims({ iss: 'https://accounts.google.com' }))))).toBe('wrong_issuer');
    expect(await failure(v.verify(await signJws(keyB, claims())))).toBe('unknown_key');
    expect(await failure(v.verify(await signJws(rogue, claims())))).toBe('bad_signature');
    expect(await failure(v.verify(await signJws(keyA, claims(), { alg: 'HS256' })))).toBe('unsupported_alg');
    expect(await failure(v.verify(await signJws(keyA, claims(), { alg: 'none' })))).toBe('unsupported_alg');
    expect(await failure(v.verify('not.a.jwt'))).toBe('malformed');
    expect(await failure(v.verify(''))).toBe('malformed');
    expect(await failure(v.verify(await signJws(keyA, claims({ sub: undefined }))))).toBe('malformed');
  });

  it('checks the nonce only when the caller sends one', async () => {
    const v = make(fakeJwksFetch(jwksDocument(keyA)).fetchImpl);
    const token = await signJws(keyA, claims({ nonce: 'n-1' }));
    await expect(v.verify(token, { nonce: 'n-1' })).resolves.toBeTruthy();
    expect(await failure(v.verify(token, { nonce: 'n-2' }))).toBe('wrong_nonce');
    await expect(v.verify(token)).resolves.toBeTruthy();
  });

  it('an unverified or missing e-mail yields no hash; Apple private relay still counts when verified', async () => {
    const v = make(fakeJwksFetch(jwksDocument(keyA)).fetchImpl);
    expect((await v.verify(await signJws(keyA, claims({ email_verified: 'false' })))).emailHash).toBeUndefined();
    expect((await v.verify(await signJws(keyA, claims({ email: undefined, email_verified: undefined })))).emailVerified).toBe(false);
    expect((await v.verify(await signJws(keyA, claims({ email: 'abc123@privaterelay.appleid.com', is_private_email: 'true' })))).emailHash).toMatch(HEX64);
  });

  it('refetches the JWKS once for an unknown kid after the min interval (key rotation)', async () => {
    let doc = jwksDocument(keyA);
    let calls = 0;
    const fetchImpl: typeof fetch = async () => {
      calls += 1;
      return new Response(JSON.stringify(doc));
    };
    let t = NOW;
    const v = new AppleIdentityVerifier({ audiences: ['com.joinanny.littledays'], hashEmail: hasher, now: () => t, jwks: new JwksClient({ url: 'https://appleid.apple.com/auth/keys', fetchImpl }) });
    await v.verify(await signJws(keyA, claims()));
    expect(calls).toBe(1);
    doc = jwksDocument(keyA, keyB);
    expect(await failure(v.verify(await signJws(keyB, claims())))).toBe('unknown_key'); // within the min interval: no hammering
    expect(calls).toBe(1);
    t += 61_000;
    await expect(v.verify(await signJws(keyB, claims({ exp: t / 1000 + 600 })))).resolves.toBeTruthy();
    expect(calls).toBe(2);
  });

  it('reports the provider as unavailable when the JWKS cannot be fetched, and not_configured without audiences', async () => {
    expect(await failure(make(fakeJwksFetch({}, { status: 500 }).fetchImpl).verify(await signJws(keyA, claims())))).toBe('jwks_unavailable');
    const down: typeof fetch = async () => {
      throw new TypeError('network down');
    };
    expect(await failure(make(down).verify(await signJws(keyA, claims())))).toBe('jwks_unavailable');
    expect(await failure(make(fakeJwksFetch(jwksDocument(keyA)).fetchImpl, ['', '  ']).verify(await signJws(keyA, claims())))).toBe('not_configured');
  });
});

describe('GoogleIdentityVerifier', () => {
  const claims = (over: Record<string, unknown> = {}) => ({ iss: 'https://accounts.google.com', aud: '1234-ios.apps.googleusercontent.com', sub: '10769150350006150715113082367', exp: NOW / 1000 + 600, iat: NOW / 1000 - 5, email: 'parent@gmail.com', email_verified: true, ...over });
  const make = (fetchImpl: typeof fetch, clientIds = ['1234-ios.apps.googleusercontent.com', '1234-web.apps.googleusercontent.com']) =>
    new GoogleIdentityVerifier({ clientIds, hashEmail: hasher, now: () => NOW, jwks: new JwksClient({ url: 'https://www.googleapis.com/oauth2/v3/certs', fetchImpl }) });

  it('accepts a valid ID token from either issuer form and any configured client id', async () => {
    const v = make(fakeJwksFetch(jwksDocument(keyA)).fetchImpl);
    const id = await v.verify(await signJws(keyA, claims()));
    expect(id).toMatchObject({ provider: 'google', subject: '10769150350006150715113082367', emailVerified: true });
    expect(id.emailHash).toMatch(HEX64);
    await expect(v.verify(await signJws(keyA, claims({ iss: 'accounts.google.com', aud: '1234-web.apps.googleusercontent.com' })))).resolves.toBeTruthy();
  });

  it('rejects wrong aud, expired, wrong iss, unknown kid, forged signature; boolean email_verified false yields no hash', async () => {
    const v = make(fakeJwksFetch(jwksDocument(keyA)).fetchImpl);
    expect(await failure(v.verify(await signJws(keyA, claims({ aud: '9999.apps.googleusercontent.com' }))))).toBe('wrong_audience');
    expect(await failure(v.verify(await signJws(keyA, claims({ exp: NOW / 1000 - 3600 }))))).toBe('expired');
    expect(await failure(v.verify(await signJws(keyA, claims({ iss: 'https://appleid.apple.com' }))))).toBe('wrong_issuer');
    expect(await failure(v.verify(await signJws(keyB, claims())))).toBe('unknown_key');
    expect(await failure(v.verify(await signJws(rogue, claims())))).toBe('bad_signature');
    expect((await v.verify(await signJws(keyA, claims({ email_verified: false })))).emailHash).toBeUndefined();
    expect(await failure(make(fakeJwksFetch(jwksDocument(keyA)).fetchImpl, []).verify(await signJws(keyA, claims())))).toBe('not_configured');
  });
});

describe('DevIdentityVerifier', () => {
  it('is deterministic in DEV_MODE and refused outside it', async () => {
    const dev = new DevIdentityVerifier(true);
    expect(await dev.verify('qa-parent-1')).toEqual({ provider: 'dev', subject: 'qa-parent-1', emailVerified: false });
    expect(await failure(dev.verify('bad subject!'))).toBe('malformed');
    expect(await failure(new DevIdentityVerifier(false).verify('qa-parent-1'))).toBe('provider_disabled');
  });
});

describe('createIdentityVerifiers + hashes', () => {
  it('reads APPLE_BUNDLE_ID / APPLE_SERVICE_ID / GOOGLE_CLIENT_IDS and never yields a raw value', async () => {
    const v = createIdentityVerifiers({ devMode: false }, { PARENT_TOKEN_SECRET: SECRET, APPLE_BUNDLE_ID: 'com.joinanny.littledays', APPLE_SERVICE_ID: 'com.joinanny.littledays.web', GOOGLE_CLIENT_IDS: 'a.apps.googleusercontent.com, b.apps.googleusercontent.com' });
    expect(v.apple.configured).toBe(true);
    expect(v.google.configured).toBe(true);
    expect(await failure(v.dev.verify('x'))).toBe('provider_disabled');
    const unconfigured = createIdentityVerifiers({ devMode: true }, { PARENT_TOKEN_SECRET: SECRET });
    expect(unconfigured.apple.configured).toBe(false);
    expect(unconfigured.google.configured).toBe(false);
    const h1 = await hashSubject(SECRET, 'apple', '001234.abcdef');
    expect(h1).toMatch(HEX64);
    expect(h1).not.toBe(await hashSubject(SECRET, 'google', '001234.abcdef')); // provider-separated
    expect(h1).not.toBe(await hashSubject('another-secret-value-1234567890', 'apple', '001234.abcdef'));
    expect(h1).not.toContain('001234');
  });
});
