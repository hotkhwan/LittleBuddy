// Sign-in verification: the boundary between a store identity token (Sign in
// with Apple / Google ID token) and the parent account. A verifier answers
// "who is this, according to the provider" and nothing else; the account
// layer decides what to store (HMAC hashes only, never the raw subject or
// e-mail; see cloud/src/routes/accounts.ts and migrations/0001_accounts.sql).
export type IdentityProvider = 'apple' | 'google' | 'dev';

export interface VerifiedIdentity {
  provider: IdentityProvider;
  /** The provider's stable user id (Apple `sub`, Google `sub`, dev: the literal subject). Never persisted raw. */
  subject: string;
  /** HMAC of the lower-cased e-mail when the provider marked it verified; otherwise absent. */
  emailHash?: string;
  emailVerified: boolean;
}

export type IdentityFailure =
  | 'malformed'
  | 'unsupported_alg'
  | 'unknown_key'
  | 'bad_signature'
  | 'expired'
  | 'not_yet_valid'
  | 'wrong_issuer'
  | 'wrong_audience'
  | 'wrong_nonce'
  | 'jwks_unavailable'
  | 'provider_disabled'
  | 'not_configured';

export class IdentityError extends Error {
  constructor(readonly reason: IdentityFailure, message?: string) {
    super(message ?? reason);
  }
}

export interface VerifyOptions {
  /** Apple / Google: the nonce the client generated for this sign-in, when it used one. */
  nonce?: string;
}

export interface IdentityVerifier {
  readonly provider: IdentityProvider;
  /** `credential` is the provider's identity token (a compact JWS) or, for the dev provider, the literal subject. */
  verify(credential: string, options?: VerifyOptions): Promise<VerifiedIdentity>;
}
