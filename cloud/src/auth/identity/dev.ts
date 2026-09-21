// DEV_MODE only: `{provider: "dev", subject: "<any id>"}` signs in
// deterministically so QA and the tests can create families without a store
// account. Refused everywhere else, before anything is looked at.
import { IdentityError, type IdentityVerifier, type VerifiedIdentity } from './types';

const SUBJECT_RE = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;

export class DevIdentityVerifier implements IdentityVerifier {
  readonly provider = 'dev' as const;

  constructor(private readonly devMode: boolean) {}

  async verify(credential: string): Promise<VerifiedIdentity> {
    if (!this.devMode) throw new IdentityError('provider_disabled', 'dev sign-in is disabled outside DEV_MODE');
    if (typeof credential !== 'string' || !SUBJECT_RE.test(credential)) throw new IdentityError('malformed', 'subject has an invalid format');
    return { provider: 'dev', subject: credential, emailVerified: false };
  }
}
