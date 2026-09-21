// Sign in with Apple: the identity token the app (ASAuthorization) or the web
// flow (Sign in with Apple JS, Services ID) hands us. Apple's rules
// (developer.apple.com "Verifying a user"): verify the JWS with Apple's public
// keys, iss = https://appleid.apple.com, aud = your client id (bundle id for
// native, Services ID for web), exp in the future, nonce when one was sent.
import { JwksClient, truthyClaim, verifyJws } from './jwks';
import { IdentityError, type IdentityVerifier, type VerifiedIdentity, type VerifyOptions } from './types';

export const APPLE_ISSUER = 'https://appleid.apple.com';
export const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';

export interface AppleVerifierOptions {
  /** Accepted `aud` values: APPLE_BUNDLE_ID (native app) and APPLE_SERVICE_ID (web, littledays.joinanny.com). */
  audiences: readonly string[];
  hashEmail: (email: string) => Promise<string>;
  now?: () => number;
  fetchImpl?: typeof fetch;
  jwks?: JwksClient;
}

export class AppleIdentityVerifier implements IdentityVerifier {
  readonly provider = 'apple' as const;
  private readonly jwks: JwksClient;
  private readonly audiences: string[];

  constructor(private readonly options: AppleVerifierOptions) {
    this.audiences = options.audiences.map((a) => a.trim()).filter(Boolean);
    this.jwks = options.jwks ?? new JwksClient({ url: APPLE_JWKS_URL, fetchImpl: options.fetchImpl });
  }

  get configured(): boolean {
    return this.audiences.length > 0;
  }

  async verify(credential: string, options: VerifyOptions = {}): Promise<VerifiedIdentity> {
    if (!this.configured) throw new IdentityError('not_configured', 'Apple sign-in is not configured on this server (APPLE_BUNDLE_ID / APPLE_SERVICE_ID).');
    const nowMs = (this.options.now ?? Date.now)();
    const claims = await verifyJws({ token: credential, jwks: this.jwks, issuers: [APPLE_ISSUER], audiences: this.audiences, nowMs, nonce: options.nonce });
    const emailVerified = truthyClaim(claims.email_verified) && typeof claims.email === 'string' && claims.email.length > 0;
    const out: VerifiedIdentity = { provider: 'apple', subject: claims.sub, emailVerified };
    if (emailVerified) out.emailHash = await this.options.hashEmail(claims.email as string);
    return out;
  }
}
