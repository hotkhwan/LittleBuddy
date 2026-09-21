// Compact JWS (RS256) verification against a provider's JWKS document, with
// injectable fetch + clock so tests use a generated key pair and a fake JWKS.
// Only what Apple and Google identity tokens need: RS256, `kid` lookup,
// iss / aud / exp / nbf / nonce claims. No other algorithm is accepted
// (`alg: none` and HMAC algorithms are refused before any key is touched).
import { IdentityError, type IdentityFailure } from './types';

export interface JwtClaims {
  iss?: unknown;
  sub?: unknown;
  aud?: unknown;
  exp?: unknown;
  iat?: unknown;
  nbf?: unknown;
  nonce?: unknown;
  email?: unknown;
  email_verified?: unknown;
  [claim: string]: unknown;
}

export interface JwksClientOptions {
  url: string;
  fetchImpl?: typeof fetch;
  /** Cache lifetime of a JWKS document (ms). Apple and Google rotate rarely. */
  ttlMs?: number;
  /** Minimum gap between two fetches triggered by an unknown `kid` (ms), so a flood of bad tokens cannot hammer the provider. */
  minRefetchMs?: number;
}

/** workers-types' JsonWebKey lacks the JWKS envelope fields. */
export type Jwk = JsonWebKey & { kid?: string; alg?: string; use?: string };

interface Cached { keys: Map<string, Jwk>; fetchedAt: number }

/** Late-bound global fetch: tests may replace `globalThis.fetch`. */
const defaultFetch: typeof fetch = (input, init) => globalThis.fetch(input, init);

export class JwksClient {
  private cache: Cached | null = null;
  private inflight: Promise<Cached> | null = null;
  private readonly ttlMs: number;
  private readonly minRefetchMs: number;
  private readonly fetchImpl: typeof fetch;

  constructor(private readonly options: JwksClientOptions) {
    this.ttlMs = options.ttlMs ?? 6 * 3600 * 1000;
    this.minRefetchMs = options.minRefetchMs ?? 60 * 1000;
    this.fetchImpl = options.fetchImpl ?? defaultFetch;
  }

  get url(): string {
    return this.options.url;
  }

  /** The JWK for `kid`, refreshing the document once when the kid is unknown (key rotation). */
  async key(kid: string, nowMs: number): Promise<Jwk> {
    let doc = this.cache && nowMs - this.cache.fetchedAt < this.ttlMs ? this.cache : await this.load(nowMs);
    let jwk = doc.keys.get(kid);
    if (!jwk && nowMs - doc.fetchedAt >= this.minRefetchMs) {
      doc = await this.load(nowMs);
      jwk = doc.keys.get(kid);
    }
    if (!jwk) throw new IdentityError('unknown_key', 'The identity token was signed with an unknown key.');
    return jwk;
  }

  private load(nowMs: number): Promise<Cached> {
    if (!this.inflight) {
      this.inflight = this.fetchDoc(nowMs).finally(() => {
        this.inflight = null;
      });
    }
    return this.inflight;
  }

  private async fetchDoc(nowMs: number): Promise<Cached> {
    let res: Response;
    try {
      res = await this.fetchImpl(this.options.url, { method: 'GET', headers: { accept: 'application/json' } });
    } catch {
      throw new IdentityError('jwks_unavailable', 'The sign-in provider could not be reached.');
    }
    if (!res.ok) throw new IdentityError('jwks_unavailable', 'The sign-in provider could not be reached.');
    let body: unknown;
    try {
      body = await res.json();
    } catch {
      throw new IdentityError('jwks_unavailable', 'The sign-in provider answered with an unreadable key set.');
    }
    const keys = new Map<string, Jwk>();
    const list = (body as { keys?: unknown } | null)?.keys;
    if (Array.isArray(list)) {
      for (const k of list) {
        const jwk = k as Jwk | null;
        if (jwk && typeof jwk === 'object' && typeof jwk.kid === 'string' && jwk.kty === 'RSA') keys.set(jwk.kid, jwk);
      }
    }
    const cached = { keys, fetchedAt: nowMs };
    this.cache = cached;
    return cached;
  }
}

export interface VerifyJwsInput {
  token: string;
  jwks: JwksClient;
  issuers: readonly string[];
  audiences: readonly string[];
  nowMs: number;
  nonce?: string;
  /** Clock skew tolerance for exp / nbf (seconds). */
  leewaySeconds?: number;
}

const MAX_TOKEN_CHARS = 8192;

/** Verifies signature and standard claims; returns the payload. Throws IdentityError. */
export async function verifyJws(input: VerifyJwsInput): Promise<JwtClaims & { sub: string }> {
  const { token } = input;
  if (typeof token !== 'string' || !token || token.length > MAX_TOKEN_CHARS) throw new IdentityError('malformed');
  const parts = token.split('.');
  if (parts.length !== 3) throw new IdentityError('malformed');
  const [h, p, s] = parts;
  const header = parseJson(h);
  if (!header || header.alg !== 'RS256') throw new IdentityError(header && typeof header.alg === 'string' && header.alg !== 'RS256' ? 'unsupported_alg' : 'malformed');
  if (typeof header.kid !== 'string' || !header.kid) throw new IdentityError('malformed');
  const payload = parseJson(p);
  if (!payload) throw new IdentityError('malformed');

  const jwk = await input.jwks.key(header.kid, input.nowMs);
  if (jwk.alg !== undefined && jwk.alg !== 'RS256') throw new IdentityError('unsupported_alg');
  if (jwk.use !== undefined && jwk.use !== 'sig') throw new IdentityError('unknown_key');
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey('jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true }, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  } catch {
    throw new IdentityError('unknown_key', 'The provider key could not be imported.');
  }
  const sig = b64urlToBytes(s);
  if (!sig) throw new IdentityError('malformed');
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, sig, new TextEncoder().encode(`${h}.${p}`));
  if (!ok) throw new IdentityError('bad_signature');

  const leeway = input.leewaySeconds ?? 60;
  const nowSec = input.nowMs / 1000;
  if (typeof payload.exp !== 'number' || !Number.isFinite(payload.exp)) throw new IdentityError('malformed', 'exp is missing');
  if (payload.exp + leeway <= nowSec) throw new IdentityError('expired');
  if (typeof payload.nbf === 'number' && payload.nbf - leeway > nowSec) throw new IdentityError('not_yet_valid');
  if (typeof payload.iss !== 'string' || !input.issuers.includes(payload.iss)) throw new IdentityError('wrong_issuer');
  const aud = payload.aud;
  const audList = typeof aud === 'string' ? [aud] : Array.isArray(aud) ? aud.filter((a): a is string => typeof a === 'string') : [];
  if (!audList.some((a) => input.audiences.includes(a))) throw new IdentityError('wrong_audience');
  if (typeof payload.sub !== 'string' || !payload.sub || payload.sub.length > 255) throw new IdentityError('malformed', 'sub is missing');
  if (input.nonce !== undefined && payload.nonce !== input.nonce) throw new IdentityError('wrong_nonce');
  return payload as JwtClaims & { sub: string };
}

/** Providers differ: Apple sends "true"/"false" strings, Google booleans. */
export function truthyClaim(v: unknown): boolean {
  return v === true || v === 'true';
}

export function failureStatus(reason: IdentityFailure): 400 | 403 | 501 | 503 {
  switch (reason) {
    case 'malformed':
    case 'unsupported_alg':
      return 400;
    case 'jwks_unavailable':
      return 503;
    case 'not_configured':
    case 'provider_disabled':
      return 501;
    default:
      return 403;
  }
}

function parseJson(b64: string): Record<string, unknown> | null {
  const bytes = b64urlToBytes(b64);
  if (!bytes) return null;
  try {
    const v: unknown = JSON.parse(new TextDecoder().decode(bytes));
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

export function b64urlToBytes(text: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) return null;
  try {
    const padded = text.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (text.length % 4)) % 4);
    const bin = atob(padded);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

export function bytesToB64url(bytes: Uint8Array | ArrayBuffer): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = '';
  for (const b of view) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
