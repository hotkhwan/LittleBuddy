// Google Sign-In ID token (iOS SDK / web GIS). Google's rules
// (developers.google.com/identity "Verify the Google ID token on your server
// side"): RS256 signed with a key from the JWKS endpoint, iss is
// accounts.google.com or https://accounts.google.com, aud is one of your
// OAuth client ids, exp in the future.
import { JwksClient, truthyClaim, verifyJws } from './jwks';
import { IdentityError, type IdentityVerifier, type VerifiedIdentity, type VerifyOptions } from './types';

export const GOOGLE_ISSUERS = ['accounts.google.com', 'https://accounts.google.com'] as const;
export const GOOGLE_JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

export interface GoogleVerifierOptions {
  /** Accepted `aud` values: GOOGLE_CLIENT_IDS (iOS client id, web client id, ...). */
  clientIds: readonly string[];
  hashEmail: (email: string) => Promise<string>;
  now?: () => number;
  fetchImpl?: typeof fetch;
  jwks?: JwksClient;
}

export class GoogleIdentityVerifier implements IdentityVerifier {
  readonly provider = 'google' as const;
  private readonly jwks: JwksClient;
  private readonly clientIds: string[];

  constructor(private readonly options: GoogleVerifierOptions) {
    this.clientIds = options.clientIds.map((a) => a.trim()).filter(Boolean);
    this.jwks = options.jwks ?? new JwksClient({ url: GOOGLE_JWKS_URL, fetchImpl: options.fetchImpl });
  }

  get configured(): boolean {
    return this.clientIds.length > 0;
  }

  async verify(credential: string, options: VerifyOptions = {}): Promise<VerifiedIdentity> {
    if (!this.configured) throw new IdentityError('not_configured', 'Google sign-in is not configured on this server (GOOGLE_CLIENT_IDS).');
    const nowMs = (this.options.now ?? Date.now)();
    const claims = await verifyJws({ token: credential, jwks: this.jwks, issuers: GOOGLE_ISSUERS, audiences: this.clientIds, nowMs, nonce: options.nonce });
    const emailVerified = truthyClaim(claims.email_verified) && typeof claims.email === 'string' && claims.email.length > 0;
    const out: VerifiedIdentity = { provider: 'google', subject: claims.sub, emailVerified };
    if (emailVerified) out.emailHash = await this.options.hashEmail(claims.email as string);
    return out;
  }
}
