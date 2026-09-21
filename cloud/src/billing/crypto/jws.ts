// JWS compact serialisation: decode, verify ES256 with a given key or an x5c
// chain, and sign (for the App Store Server API client JWT and the Google
// service-account assertion). WebCrypto only.
import { base64Decode, base64UrlDecode, base64UrlEncode, fromUtf8, pemToDer, sha256Hex, utf8 } from './encoding.ts';
import { importSpki, verifyChain, type ChainPolicy, type ParsedCertificate } from './x509.ts';

export interface DecodedJws {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
  signingInput: Uint8Array;
  signature: Uint8Array;
}

export function decodeJws(token: string): DecodedJws {
  if (typeof token !== 'string') throw new Error('jws: not a string');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('jws: expected three segments');
  const [h, p, s] = parts;
  const header = JSON.parse(fromUtf8(base64UrlDecode(h)));
  const payload = JSON.parse(fromUtf8(base64UrlDecode(p)));
  if (!header || typeof header !== 'object' || !payload || typeof payload !== 'object') throw new Error('jws: malformed segments');
  return { header, payload, signingInput: utf8(`${h}.${p}`), signature: base64UrlDecode(s) };
}

export async function verifyEs256(decoded: DecodedJws, key: CryptoKey, hash: 'SHA-256' | 'SHA-384' = 'SHA-256'): Promise<boolean> {
  return crypto.subtle.verify({ name: 'ECDSA', hash }, key, decoded.signature as BufferSource, decoded.signingInput as BufferSource);
}

export interface X5cVerifyResult {
  ok: boolean;
  reason: string;
  payload: Record<string, unknown> | null;
  leaf: ParsedCertificate | null;
}

/**
 * Apple-style: the signer's certificate chain rides in the header (`x5c`).
 * Chain first (pinned root, OIDs, validity at `effectiveTimeMs`), then the
 * signature with the leaf's key. Nothing is trusted from the payload until
 * both pass.
 */
export async function verifyJwsWithX5c(token: string, policy: Omit<ChainPolicy, 'effectiveTimeMs'> & { effectiveTimeMs?: number }, nowMs: number): Promise<X5cVerifyResult> {
  let decoded: DecodedJws;
  try {
    decoded = decodeJws(token);
  } catch (error) {
    return { ok: false, reason: `malformed_jws: ${(error as Error).message}`, payload: null, leaf: null };
  }
  if (decoded.header.alg !== 'ES256') return { ok: false, reason: 'unsupported_alg', payload: null, leaf: null };
  const x5c = decoded.header.x5c;
  if (!Array.isArray(x5c) || !x5c.every((c) => typeof c === 'string')) return { ok: false, reason: 'missing_x5c', payload: null, leaf: null };

  // Apple: validate the chain at the payload's signedDate (falls back to now).
  const signedDate = typeof decoded.payload.signedDate === 'number' ? decoded.payload.signedDate : nowMs;
  const effectiveTimeMs = policy.effectiveTimeMs ?? signedDate;
  const chain = await verifyChain(x5c as string[], { ...policy, effectiveTimeMs }, sha256Hex, base64Decode);
  if (!chain.ok || !chain.leaf) return { ok: false, reason: chain.reason, payload: null, leaf: null };
  if (chain.leaf.curve !== 'P-256') return { ok: false, reason: 'leaf_key_not_p256', payload: null, leaf: null };

  const key = await importSpki(chain.leaf.spki, 'P-256');
  const valid = await verifyEs256(decoded, key);
  if (!valid) return { ok: false, reason: 'bad_signature', payload: null, leaf: null };
  return { ok: true, reason: 'ok', payload: decoded.payload, leaf: chain.leaf };
}

// -- signing (client JWTs) -----------------------------------------------------

export type SignAlg = 'ES256' | 'RS256';

export async function importPkcs8(pem: string, alg: SignAlg): Promise<CryptoKey> {
  const der = pemToDer(pem);
  const params = alg === 'ES256'
    ? ({ name: 'ECDSA', namedCurve: 'P-256' } as never)
    : ({ name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' } as never);
  return crypto.subtle.importKey('pkcs8', der as BufferSource, params, false, ['sign']);
}

/** Compact JWS/JWT with the given header and payload. */
export async function signJws(header: Record<string, unknown>, payload: Record<string, unknown>, key: CryptoKey, alg: SignAlg): Promise<string> {
  const h = base64UrlEncode(utf8(JSON.stringify({ ...header, alg })));
  const p = base64UrlEncode(utf8(JSON.stringify(payload)));
  const input = utf8(`${h}.${p}`);
  const params = alg === 'ES256' ? { name: 'ECDSA', hash: 'SHA-256' } : { name: 'RSASSA-PKCS1-v1_5' };
  const sig = new Uint8Array(await crypto.subtle.sign(params, key, input as BufferSource));
  return `${h}.${p}.${base64UrlEncode(sig)}`;
}
