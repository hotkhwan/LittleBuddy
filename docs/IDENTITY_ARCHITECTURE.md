# Identity Architecture

## Status and scope

This document defines the production identity architecture for Little Days. It does not assert that the current branch is deployed. Migration `0007_guest_identity.sql` and `cloud/src/routes/identity.ts` implement guest creation, guest tokens, Apple/Google linking, deterministic data migration, guest-aware entitlements, installation records, and purchase identity values. Production migration application, credentials, integration testing, and release approval remain outstanding.

Core play and local lessons remain offline-first. An account is not required before play. Public child audio, real billing, and multiplayer remain disabled.

## Principals and identifiers

| Identifier | Issuer | Purpose | Persistence |
| --- | --- | --- | --- |
| `installation_id` | app, random UUID v4 | installation registration and session binding | secure device storage; may disappear on uninstall |
| `guest_account_id` | backend, UUID | server-owned guest account | backend plus secure device credential |
| `parent_account_id` | backend, UUID | durable family/account owner | backend |
| `child_profile_id` | backend, UUID | parent-owned child data partition | backend |
| provider subject | Apple/Google | proves parent identity | map by provider and subject; raw value should not be used as an account id |

Never derive identity from IMEI, MAC address, serial number, advertising ID, `ANDROID_ID`, `OS.get_unique_id()`, or a device fingerprint. Reinstall may create a new installation and guest; this is acceptable.

## Implemented additive schema

The normalized model is additive to the earlier migrations. The routes must not be advertised as production until the migration is applied and release gates pass.

```sql
guest_accounts(
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK(status IN ('active','linked','suspended','deleted')),
  merged_into TEXT REFERENCES accounts(id),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  linked_at INTEGER
)

identity_providers(
  provider TEXT NOT NULL CHECK(provider IN ('apple','google')),
  provider_subject_hash TEXT NOT NULL,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  PRIMARY KEY(provider, provider_subject_hash)
)

parent_profiles(
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL UNIQUE REFERENCES accounts(id),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)

child_profiles(
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  owner_parent_id TEXT REFERENCES parent_profiles(id),
  nickname TEXT,
  age_band TEXT,
  language TEXT,
  learning_level TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)

installations(
  installation_id TEXT PRIMARY KEY,
  platform TEXT NOT NULL,
  account_id TEXT REFERENCES accounts(id),
  guest_account_id TEXT REFERENCES guest_accounts(id),
  app_version TEXT,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('active','replaced','revoked')),
  CHECK(account_id IS NULL OR guest_account_id IS NULL)
)
```

Provider subjects are stored as HMAC values in `provider_subject_hash` so a database disclosure does not reveal raw federated identifiers. Provider email may be stored only as an optional verified hash/contact attribute; it is never a key.

Migration `0006_production_platform.sql` introduces `accounts`, `parents`, account-linked children, plans, subscriptions, entitlement grants, and AI usage tables. Migration `0007_guest_identity.sql` adds the tables above while bridging through the existing parent repository. Legacy account, device, and entitlement projections remain part of the staged compatibility model.

## Authentication boundaries

- Guest tokens authenticate one active guest account and are bound server-side to the installation registration. Tokens are signed, short-lived, audience/version checked, and refreshable from a securely stored guest credential.
- Parent bearer tokens authenticate a backend account reached through an Apple or Google subject mapping.
- Parent approval tokens remain narrower than bearer tokens and must not authorize provider linking, purchases, export, deletion, or consent changes.
- Every child lookup includes the authenticated account owner in the query. A caller-supplied child ID is never sufficient authorization.
- Linked guests reject further mutation with a conflict/reauth response; their data is reachable only through `merged_into` for audit and idempotent replay.

## Entitlements and trials

`GET /v1/me/entitlements` is the canonical account view for guest, `FREE`, `FAMILY`, `PREMIUM`, `PREMIUM_PLUS`, and `SCHOOL`. A guest can receive only core/local features and the server-policy Standard AI allowance. It can never receive a paid grant or Premium Live trial.

Trial eligibility and consumption are keyed by `parent_account_id`, not installation. A reinstall can lose an unlinked guest but cannot reset a linked parent's trial. AI usage migration preserves consumed quota; it does not create a fresh allowance.

## Security invariants

- Guest creation is idempotent per valid installation/idempotency key, rate-limited, and returns no other account's data.
- Linking requires both a valid guest credential and a freshly verified parent identity. Possession of an installation ID alone is insufficient.
- `(provider, provider_subject)` is unique. A subject already owned by another account cannot silently move.
- Link and merge execute atomically. A second request returns the original result; it cannot duplicate stars, rewards, or quota.
- Paid purchase verification requires a parent account and an account-mapping token that matches it.
- Logs exclude identity tokens, store receipts, provider subjects, child text/audio, installation IDs, and full request URLs.

## Current implementation delta

Implemented in the repository: guest creation/token verification; installation binding and replay checks; Apple/Google JWS verification; HMAC subject mapping; deterministic guest progress/reward/unlock/settings/AI-usage import; parent tokens/approval tokens; parent-owned child access; guest/parent entitlement responses; account purchase identity values; billing verification and notification handlers; development-gated tutor sessions; local lesson fallback.

Still required before production: migration/deployment evidence; stronger concurrency/idempotency validation around linking; projection of imported guest AI usage into canonical quota; strict comparison of store account markers with the authenticated account; native StoreKit/Play/Credential Manager adapters; production credential configuration; and physical-device verification. Social schema exists without routes or UI, by design.
