// Wiring: provider name -> verifier, built from config + env per request
// (cheap objects; the JWKS documents are cached per isolate below), plus the
// two hashes the account layer stores instead of the raw values.
import type { Config } from '../../env';
import { hmacHex } from '../../util/crypto';
import { AppleIdentityVerifier } from './apple';
import { DevIdentityVerifier } from './dev';
import { GoogleIdentityVerifier } from './google';
import { JwksClient } from './jwks';
import { APPLE_JWKS_URL } from './apple';
import { GOOGLE_JWKS_URL } from './google';
import type { IdentityProvider, IdentityVerifier } from './types';

export * from './types';
export { AppleIdentityVerifier, APPLE_ISSUER, APPLE_JWKS_URL } from './apple';
export { GoogleIdentityVerifier, GOOGLE_ISSUERS, GOOGLE_JWKS_URL } from './google';
export { DevIdentityVerifier } from './dev';
export { JwksClient, verifyJws, failureStatus, bytesToB64url, b64urlToBytes } from './jwks';

/** The vars the identity layer reads. Names only in .dev.vars.example; values via `wrangler secret put` / [vars]. */
export interface IdentityEnv {
  DEV_MODE?: string;
  PARENT_TOKEN_SECRET?: string;
  APPLE_BUNDLE_ID?: string;
  APPLE_SERVICE_ID?: string;
  GOOGLE_CLIENT_IDS?: string;
}

export const IDENTITY_PROVIDERS: readonly IdentityProvider[] = ['apple', 'google', 'dev'];

export function isIdentityProvider(v: unknown): v is IdentityProvider {
  return typeof v === 'string' && (IDENTITY_PROVIDERS as readonly string[]).includes(v);
}

/**
 * HMAC(PARENT_TOKEN_SECRET, "subject", "<provider>\n<subject>"): what
 * parent_accounts.subject_hash holds. Same derivation the dev sign-in has used
 * since migration 0001, so existing dev rows keep matching.
 */
export function hashSubject(secret: string, provider: IdentityProvider, subject: string): Promise<string> {
  return hmacHex(secret, 'subject', `${provider}\n${subject}`);
}

/** HMAC(PARENT_TOKEN_SECRET, "email", lower-cased trimmed e-mail): parent_accounts.email_hash. */
export function hashEmail(secret: string, email: string): Promise<string> {
  return hmacHex(secret, 'email', email.trim().toLowerCase());
}

export function splitList(v: string | undefined): string[] {
  return (v || '').split(',').map((s) => s.trim()).filter(Boolean);
}

// One JWKS cache per provider per isolate (Apple and Google rotate keys rarely).
const sharedJwks = { apple: new JwksClient({ url: APPLE_JWKS_URL }), google: new JwksClient({ url: GOOGLE_JWKS_URL }) };

export interface IdentityVerifiers { apple: AppleIdentityVerifier; google: GoogleIdentityVerifier; dev: DevIdentityVerifier }

export function createIdentityVerifiers(config: Pick<Config, 'devMode'>, env: IdentityEnv, opts: { now?: () => number; fetchImpl?: typeof fetch } = {}): IdentityVerifiers {
  const secret = env.PARENT_TOKEN_SECRET || '';
  const emailHasher = (email: string) => hashEmail(secret, email);
  const jwksFor = (provider: 'apple' | 'google', url: string) => (opts.fetchImpl ? new JwksClient({ url, fetchImpl: opts.fetchImpl }) : sharedJwks[provider]);
  return {
    apple: new AppleIdentityVerifier({ audiences: [env.APPLE_BUNDLE_ID || '', env.APPLE_SERVICE_ID || ''], hashEmail: emailHasher, now: opts.now, jwks: jwksFor('apple', APPLE_JWKS_URL) }),
    google: new GoogleIdentityVerifier({ clientIds: splitList(env.GOOGLE_CLIENT_IDS), hashEmail: emailHasher, now: opts.now, jwks: jwksFor('google', GOOGLE_JWKS_URL) }),
    dev: new DevIdentityVerifier(config.devMode),
  };
}

export function verifierFor(verifiers: IdentityVerifiers, provider: IdentityProvider): IdentityVerifier {
  return verifiers[provider];
}
