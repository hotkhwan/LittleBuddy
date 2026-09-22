# Account Linking

## Contract

`POST /v1/auth/link` converts an authenticated guest into a parent-owned account after server verification of Apple or Google identity. It is a transaction, not a client-side copy operation.

Target request:

```json
{
  "provider": "apple",
  "identityToken": "provider-id-token",
  "nonce": "original-sign-in-nonce"
}
```

The guest bearer token identifies the source. The backend verifies issuer, signature, expiry, audience, nonce when supplied, and provider subject. Apple maps by Apple `sub`; Google maps by Google `sub`. Email is never the account key.

The implemented response returns `parentAccountId`, `parentToken`, `linkedGuestAccountId`, provider, and `mergeStatus`. It never returns a provider subject. The guest token binds the installation.

## Account resolution

1. If `(provider, subject)` has no owner, create a parent account and mapping.
2. If it belongs to an existing active parent account, link/merge into that account (multi-device restore).
3. If it belongs to another account in a state that forbids access, fail closed; never reassign the provider.
4. If the guest is already linked to the same destination, replay the recorded success.
5. If it is linked to a different destination, return conflict without identifying that destination.

Provider verification exists under `cloud/src/auth/identity`; the guest-aware route uses it and writes the normalized provider mapping while bridging the existing parent repository.

## Atomic deterministic merge

Lock or serialize on both source guest and destination account. Record the idempotency key and source/destination pair. Apply all data rules, update the installation, mark the guest `status = 'linked'` and `merged_into = parentAccountId`, then commit. Any failure rolls the entire operation back.

| Domain | Merge rule |
| --- | --- |
| lesson mastery | choose strongest valid evidence; for equal strength choose newest valid evidence; preserve evidence provenance |
| completion/unlocks | set union by stable content ID |
| stars/free rewards | union immutable award IDs; recompute displayed total from unique valid awards; never add aggregate totals |
| progress position | furthest valid curriculum step, subject to prerequisites/content version |
| settings | parent value wins; copy guest value only where parent value is unset |
| child profiles | attach the guest's local/default profile only with an explicit deterministic mapping; never overwrite another child or exceed plan limit silently |
| AI usage | merge usage event IDs and preserve consumed daily/monthly quota; effective consumption is at least the destination usage plus unique guest events, bounded by validated events |
| trial state | parent state wins; guest Standard trial consumption may reduce remaining parent Standard allowance; guest never grants Premium Live eligibility |
| entitlements | paid/school grants remain destination-owned; guest contributes none |

Every award and usage mutation should carry a stable event ID with a unique constraint. Aggregate counters are projections, not merge inputs.

## Ownership and takeover defenses

- Require a live guest credential plus fresh provider proof. `installationId`, guest ID, email, or nickname alone cannot link.
- Verify child ownership on every read/write after linking.
- Do not accept a destination account ID from the client; derive it from the verified provider mapping.
- Rate-limit link attempts by token family, installation, and network risk signals without introducing hardware fingerprinting.
- Rotate/revoke guest session material at commit and issue a new parent session.
- Audit outcome codes and hashed references only; never log identity tokens or raw subjects.

## UX

The child can always choose Play without sign-in. In Parent Area, show the benefit first: “Save progress across devices.” Apple and Google buttons live behind the existing Parent Gate. After linking, return to the intended subscription or restore action. If linking fails, retain all local play data and provide a calm retry; do not show account/security detail to the child.

## Required tests

- Apple and Google link after valid server verification.
- Duplicate provider mapping is idempotent for the owner and rejected for a conflicting owner.
- Same guest linked twice produces one merge.
- Concurrent link requests choose one destination and never split data.
- Rewards are deduplicated; mastery and settings follow the table above.
- AI consumed quota and trial state survive link and reinstall.
- Cross-account child IDs are rejected.
- Multi-device parent sign-in restores the same account and data.
