# Guest Account Flow

## Child-facing outcome

The first screen continues directly to play. Account creation is silent, asynchronous, and never blocks the local game. If networking fails, local lessons and local progress continue; registration is retried later.

## First launch

1. Generate a cryptographically random UUID v4 `installation_id` in the app. Store it in platform-secure app storage; do not derive it from hardware.
2. Load an existing guest credential when present.
3. If none exists, call `POST /v1/auth/guest` with `installationId`, `platform`, and `appVersion`. The installation UUID is the current creation idempotency key.
4. The backend creates or reuses the installation registration, creates a backend UUID guest account when needed, and returns `guestAccountId` and a short-lived guest token.
5. Persist the credential securely and upload eligible local progress opportunistically. Never delay play while waiting.

Implemented request/response shape:

```json
POST /v1/auth/guest
{
  "installationId": "uuid-v4",
  "platform": "ios",
  "appVersion": "1.0.0"
}

201
{
  "guestAccountId": "backend-uuid",
  "guestToken": "signed-token",
  "installationId": "uuid-v4",
  "accountType": "guest"
}
```

Credential responses should be forced to `Cache-Control: no-store` before production. A repeated request for the same active installation returns the same guest relationship and a newly minted session token, not a second account.

## Relaunch and reinstall

On relaunch, load the `installation_id` and guest credential, refresh if necessary, and continue. If the secure data survives but local saves do not, the backend guest can restore synchronized guest data. If uninstall removes both, generate a new installation and guest. Do not attempt recovery via fingerprinting.

Offline progress created before guest registration needs stable client-generated event/award IDs so later upload is idempotent. The server rejects cross-account reuse of an ID.

## Guest capabilities

A guest may use core play, bundled local lessons, and limited Standard AI only when server policy allows it. `GET /v1/me/entitlements` must return a guest-safe feature set and never a paid tier. Premium Live trial requires a linked parent.

When a guest chooses Family, Premium, or Premium+, the app opens the Parent Gate and explains: “Save progress across devices” followed by “Sign in with Apple” and “Sign in with Google.” No store sheet opens before successful linking.

## Installation registration

The target `installations` row stores only `installation_id`, platform, account or guest association, app version, timestamps, and status. Update `last_seen_at` on authenticated activity with write coalescing. On link, atomically replace `guest_account_id` with `account_id`; do not retain both as active owners.

## Failure behavior

| Failure | Client behavior | Server behavior |
| --- | --- | --- |
| offline/timeout | use local lesson; retry with same idempotency key | no partial account |
| expired guest token | refresh once, otherwise preserve local play | rotate credential; revoke replayed refresh token |
| token replay from another installation | do not expose account data | deny, record security event, optionally revoke token family |
| linked guest token | prompt parent sign-in if cloud restore is needed | return linked/conflict with no destination account details |
| corrupt local credential | start locally and register a new guest | never match by device fingerprint |

## Acceptance tests

- First registration creates one installation and one guest.
- Repeating creation is idempotent and guest relaunch restores identity.
- Reinstall without secure state creates a new guest and does not inherit the old trial.
- Guest progress uploads without duplicate awards.
- Guest cannot start billing or Premium Live trial.
- A captured token cannot be used to take over or relink the guest.
