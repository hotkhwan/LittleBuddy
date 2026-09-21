// Test-only signing: a generated RSA key pair, a fake JWKS document and a
// compact-JWS signer, so the Apple / Google verifiers run offline.
import { bytesToB64url } from '../src/auth/identity';

export interface TestKey { kid: string; privateKey: CryptoKey; jwk: JsonWebKey & { kid: string; alg: string; use: string } }

export async function generateTestKey(kid: string): Promise<TestKey> {
  const pair = (await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify'])) as CryptoKeyPair;
  const pub = (await crypto.subtle.exportKey('jwk', pair.publicKey)) as JsonWebKey;
  return { kid, privateKey: pair.privateKey, jwk: { kty: 'RSA', n: pub.n, e: pub.e, kid, alg: 'RS256', use: 'sig' } };
}

export function jwksDocument(...keys: TestKey[]) {
  return { keys: keys.map((k) => k.jwk) };
}

/** A fetch that serves `doc` for any URL and counts calls; `status` overrides the answer. */
export function fakeJwksFetch(doc: unknown, opts: { status?: number } = {}) {
  const state = { calls: 0 };
  const fetchImpl: typeof fetch = async () => {
    state.calls += 1;
    return new Response(JSON.stringify(doc), { status: opts.status ?? 200, headers: { 'content-type': 'application/json' } });
  };
  return { fetchImpl, state };
}

export async function signJws(key: TestKey, payload: Record<string, unknown>, header: Record<string, unknown> = {}): Promise<string> {
  const enc = new TextEncoder();
  const h = bytesToB64url(enc.encode(JSON.stringify({ alg: 'RS256', kid: key.kid, typ: 'JWT', ...header })));
  const p = bytesToB64url(enc.encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key.privateKey, enc.encode(`${h}.${p}`));
  return `${h}.${p}.${bytesToB64url(sig)}`;
}

export const HEX64 = /^[0-9a-f]{64}$/;
