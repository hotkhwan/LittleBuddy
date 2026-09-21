# Little Days cloud backend (Cloudflare Workers) — design notes

Owner: Agent D. Date: 2026-09-21. Code: `cloud/` (branch `wt6/cloud`).
Status: **built and tested locally; NOT DEPLOYED — no Cloudflare credentials
on this machine.** Contract: `docs/ALIZ_TUTOR_API.md`. Runbook and safe
deployment: `cloud/README.md`.

## Why a Worker, and what it keeps from the prototype

`backend/` (Node 22, zero dependencies) proved the domain rules: sessions,
server-side UTC daily quota, entitlements, parental approval bound to
sessions, idempotent validated turns, rate limits, retention, usage and a
monthly budget guard. The Worker keeps every one of those rules and the same
error codes, and adds what a real product needs and a single Node process
could not give: accounts (parents, children, devices, consent), a durable
per-child counter that survives many isolates and many devices, store-driven
entitlements (Agent F), and a provider module boundary (Agent E).

| Concern | Prototype (`backend/`) | Worker (`cloud/`) |
| --- | --- | --- |
| Identity | `clientId` + HMAC approval token | parent account (`pt1` bearer) + approval token (`pa1`, same format, now parent-signed) + child profile |
| Quota authority | in-memory map + JSON files | `QuotaDO` per child (transactional storage), mirrored to D1 `daily_quota` |
| Session state | JSON files | `TutorSessionDO` per session (ordering, clock, idempotency, alarm) + D1 `tutor_sessions` |
| Entitlement | dev grant / mock receipt | D1 `entitlements` written by dev grant today, by Agent F's billing module later |
| Consent | none | D1 `consent_status` (privacy / ai_tutor / voice, versioned); tutor routes require `ai_tutor`, realtime also `voice` |
| Retention | hourly timer | cron trigger `17 3 * * *` + DEV route |
| Provider | in-tree OpenAI adapter | `provider_interface.ts` + mock; OpenAI module is Agent E's |

## Architecture

```
 Godot client                         Worker (Hono)                          Durable Objects            D1
 ------------                         -------------                          ---------------            --
 POST /api/v1/tutor/sessions  ----->  clock (X-Debug-Now dev only)
   clientId, lessonId,                per-IP limiter, 32 KB body cap
   X-Parent-Approval: pa1.*           credential -> {parentId, clientId}
                                      consent(ai_tutor)? device upsert
                                      child resolve, budget, entitlement
                                      QUOTA(child).snapshot() -------------> QuotaDO(child)
                                      TUTOR_SESSION(id).start() -----------> TutorSessionDO(id) ------> tutor_sessions
 POST .../turns  Idempotency-Key ---> TUTOR_SESSION(id).turn() ------------> serialize; owner check
                                                                             rate limit; idempotency --> api_idempotency
                                                                             consent + budget + quota
                                                                             lesson authority (bundled)
                                                                             provider (mock | E) w/ 6 s timeout
                                                                             validateTurn -> fallback
                                                                             QuotaDO.charge/countTurn --> daily_quota
                                                                             usage row ----------------> usage_events
                                                                             alarm(idle | token expiry)
 POST .../end  ---------------------> TUTOR_SESSION(id).end()
 POST /realtime/token  -------------> provider.realtime.mint()  (503 unless key + E + voice consent)
                                      TUTOR_SESSION(id).attachRealtime()
```

Domain code (`src/tutor/**`, `src/auth/tokens.ts`, `src/util/**`) is pure
TypeScript with no Cloudflare types; the Worker and the DOs are thin.

## Durable Objects: what and why

**`QuotaDO` — one per child.** The daily counter needs check-and-charge to be
one step ("the turn that lands on 300 s is served, the next is refused") across
any number of isolates, sessions and devices. D1 has no interactive
transactions, so a Worker-side read-modify-write on `daily_quota` would race.
A Durable Object executes one request at a time with transactional storage,
and a child is the natural key (two devices in one family share the child's
five minutes). D1 `daily_quota` is a reporting mirror written after every
change; dashboards, retention and deletion read it, the DO is the truth.
Alternative considered: `UPDATE daily_quota SET seconds_used = seconds_used + ?`
is atomic on its own but cannot combine "is there anything left?" with the
charge, and the turn cap + turn count would need a second statement. Rejected.

**`TutorSessionDO` — one per live session.** Serialises turns (a promise
chain, so one provider call at a time per session), owns the session clock
(start -> turn -> end, each gap capped at 45 s), runs idempotency (D1 rows
keyed by `HMAC(secret, sessionId + Idempotency-Key)`), calls the provider
with a timeout and falls back to the mock, charges `QuotaDO`, writes the
numeric usage rows, and terminates itself: an alarm fires at
`lastEventAt + SESSION_IDLE_SECONDS` (or the realtime token expiry) and ends
the session with reason `idle` / `token_expired` / `quota_exhausted`. A clock
behind the last event is ignored so a skewed alarm can never end a live
lesson. `parentStop` (Parent Corner) and consent revocation end it too.

Both DOs use the SQLite-backed storage class (`new_sqlite_classes`).

## Credentials

- `pt1.<b64url json>.<hex hmac>`: parent bearer, claims `{pid, iat, exp}`,
  30-day TTL, issued by `POST /v1/parents` after sign-in verification (see
  "Parent accounts" below). Every account route also checks that the parent
  row still exists and is not a deletion tombstone (403 `not_approved`
  otherwise), so a bearer outlives `DELETE /v1/parents/me` only as a string.
- `pa1.<b64url json>.<hex hmac>`: parental approval, claims
  `{sub: clientId, pid, cid?, iat, exp}`. Same wire format as the prototype
  (`backend/src/parental_approval.js`), which is why `cloud_quota_client.gd`,
  `backend_conversation_provider.gd` and `cloud_realtime_transport.gd` need
  no change: they already send it as `X-Parent-Approval` / `parentApprovalToken`.
- A session is bound to `HMAC(secret, approvalToken)`; every session call
  must present the same token (403 `not_approved` otherwise).
- DEV_MODE only: the literal `dev-parent-approval` maps to the synthetic
  parent `dev-parent` with all consents granted.

## Parent accounts (sign-in, ownership, privacy controls)

Code: `cloud/src/auth/identity/**` (verifiers), `cloud/src/routes/accounts.ts`
(routes), `cloud/src/db/parents.ts` + `cloud/src/db/accounts_privacy.ts`
(rows), `cloud/migrations/0005_account_privacy.sql`. Portal contract with
examples: `docs/PARENT_PORTAL_API.md`.

**Sign-in verification.** `POST /v1/parents {provider, identityToken |
subject, clientId?, nonce?}` picks an `IdentityVerifier`
(`verify(credential) -> {provider, subject, emailHash?, emailVerified}`):

| Provider | Credential | Checks |
| --- | --- | --- |
| `apple` | Sign in with Apple identity token (compact JWS) | RS256 against Apple's JWKS (`https://appleid.apple.com/auth/keys`), `iss` = `https://appleid.apple.com`, `aud` in {`APPLE_BUNDLE_ID` (app), `APPLE_SERVICE_ID` (web)}, `exp` (60 s leeway), `nonce` when the client sends one |
| `google` | Google ID token | RS256 against `https://www.googleapis.com/oauth2/v3/certs`, `iss` in {`accounts.google.com`, `https://accounts.google.com`}, `aud` in `GOOGLE_CLIENT_IDS` (comma list), `exp`, `nonce` optional |
| `dev` | literal `subject` | DEV_MODE only; refused (501) everywhere else |

`alg` other than RS256 (including `none`) is refused before any key is
touched; an unknown `kid` refetches the JWKS once (key rotation) but never
more than once a minute; a JWKS outage is 503 `provider_unavailable`, an
unconfigured provider 501 `not_implemented`, a bad token 403 `not_approved`
with `reason` (`wrong_audience`, `expired`, `wrong_issuer`, `unknown_key`,
`bad_signature`, `wrong_nonce`), a malformed one 400. Fetch and clock are
injectable; the tests sign with a generated RSA key and a fake JWKS.

**What is stored.** The parent is found or created by `(provider,
subject_hash)` where `subject_hash = HMAC(PARENT_TOKEN_SECRET, "subject",
"<provider>\n<subject>")` and `email_hash = HMAC(PARENT_TOKEN_SECRET,
"email", lower(email))` only when the provider marked the e-mail verified
(Apple sends it on the first authorization only, so an existing row keeps
its hash). The raw subject and e-mail never reach a row or a log; tests
assert the columns are 64-hex.

**Ownership.** A parent owns: child profiles (nickname, avatar id, optional
birth-year bucket, locale; never a legal name; max 6; `GET/POST /v1/children`,
`GET/PATCH/DELETE /v1/children/:id`), devices, consent (`privacy`,
`ai_tutor`, `voice`, versioned), learning progress (keyed by child), and a
read-only view of the entitlement rows the billing module writes
(`GET /v1/entitlements` for the app, `GET /v1/parents/me/subscription` for
the portal). `GET /v1/parents/me` adds `hasEmailHash`, `childCount`,
`maxChildren`, `tutorEntitlement`.

**Privacy controls** (parent bearer only; a device approval token gets 403):

- `GET /v1/parents/me/export`: JSON (`little-days-family-export/1`) of every
  row of the family: parent (ids, versions, `hasEmailHash`), children with
  progress / tutor sessions / daily quota numbers, devices, consent,
  entitlements, purchase events. Ids and numbers only; the hashes are not
  exported and there are no transcripts anywhere to export.
- `DELETE /v1/children/:id`: the child and everything keyed by it (progress,
  sessions, their usage + idempotency rows, `daily_quota`) and its `QuotaDO`.
- `DELETE /v1/parents/me`: children (as above), devices, consent,
  `purchase_events.parent_id -> NULL` (kept, unlinked), entitlements set to
  `revoked` with `revoked_reason = 'account_deleted'` (kept for refund / tax
  audit), and the parent row turned into a **tombstone**: `email_hash` NULL,
  `consent_version` 0, `deleted_at`, `tombstone_until = +30 days`, the
  `(provider, subject_hash)` pair retained. Within the window the same store
  identity signing in again gets 409 `conflict` `{reason: "account_deleted",
  availableAt}` (the app shows "account deleted" instead of silently
  re-creating it). At the first sign-in after the window the pair's tombstone
  is dropped (no entitlement rows) or anonymised (`subject_hash =
  'deleted:<id>'`) and a brand-new account is created with no old data.
  `expireTombstones(db, now)` without a scope is the sweep the retention
  purge should call so tombstones of parents who never return expire too
  (one line in `purgeExpired`; not wired by the accounts agent).

Vars: `APPLE_BUNDLE_ID`, `APPLE_SERVICE_ID`, `GOOGLE_CLIENT_IDS` (names in
`cloud/.dev.vars.example`; plain `[vars]` or secrets per environment). Before
real Apple / Google sign-in can be switched on: the App ID's bundle id and a
Services ID (with `littledays.joinanny.com` as a return domain) from the
Apple developer account; the iOS and web OAuth client ids from the Google
Cloud project; the game client must send the identity token in
`identityToken` (and the `nonce` it generated, if any); and the portal site
must run the web flows. The Worker needs outbound HTTPS to the two JWKS
endpoints only.

## Data minimisation (what the tables hold)

- `parent_accounts`: provider + `subject_hash` (HMAC), optional `email_hash`,
  plus `deleted_at` / `tombstone_until` after deletion. No e-mail, no name.
- `child_profiles`: nickname (24 chars, no `@`/URLs), avatar id, locale,
  optional `birth_year_bucket` ("2020-2021"). **No real name, no birth date.**
- `devices`: the app's pseudonymous `clientId`, platform, app version. No
  push token, no model, no OS build.
- `tutor_sessions`, `daily_quota`, `usage_events`: ids and numbers only.
  `usage_events` has exactly three TEXT columns (`id`, `kind`, `session_id`);
  a test asserts it.
- `api_idempotency`: salted HMAC of the request body (transcript not
  recoverable) and the validated reply (no transcript).
- Transcripts and audio are never written anywhere; logs carry
  `method routePattern status ms`.

Retention: `tutor_sessions`, `usage_events`, `daily_quota` after
`RETENTION_DAYS` (30); `api_idempotency` after 24 h; run by the cron trigger
and `POST /v1/dev/retention/purge`. `DELETE /v1/tutor/clients/:clientId`
deletes a device's learning history on demand; `DELETE /v1/children/:id` and
`DELETE /v1/parents/me` delete a child or the whole family (see "Parent
accounts"). Entitlement rows survive account deletion as `revoked` /
`account_deleted` (audit), linked to an anonymised tombstone.

## Security controls

Parent credential on every route except health, sign-in and the two store
webhooks (signature-authenticated by Agent F); per-IP fixed window (per
isolate — an honest limit, exact per-session limit lives in the DO); 32 KB
body cap; JSON only; id regexes; bounded strings; transcript <= 500 chars;
CORS never emitted; secrets only via `wrangler secret`; `DEV_MODE` only in
`env.dev`; production has no route.

## Tests

`cd cloud && npm test` -> **8 files, 129 tests, all passing, offline**
(vitest 4 + `@cloudflare/vitest-pool-workers` 0.22 running D1, both DOs and
alarms inside workerd). Coverage: migrations apply + indexes + uniqueness +
cascades; the 39 shared `turn_fixtures.json` cases (parity with the client
and the prototype); every route's happy path and its auth failures; token
format parity; quota exhaustion at exactly 300 s with boundary/refusal/new
session/next day; per-turn cap; Family Club raising the allowance to 1800 s;
daily turn cap; monthly budget; idempotent replay + 422 mismatch; lesson
authority; session ownership; per-session and per-IP rate limits; idle and
token-expiry countdown; parent stop; consent revocation; delete history;
realtime 503 without a key (and with a key but no provider module), the
transport response shape with an injected provider, voice consent, uncapped
realtime charging, usage reports, provider failure; retention purge and the
scheduled handler; billing stubs.

Storage is shared across tests in this pool version (no `isolatedStorage`),
so every test owns its identities (fresh family or fresh child).

## Deployment status and commands

NOT DEPLOYED. Commands, per environment, are in `cloud/README.md` "Safe
deployment"; the short form: `wrangler d1 create` -> paste id ->
`wrangler d1 migrations apply --remote` -> `wrangler secret put
PARENT_TOKEN_SECRET` -> `wrangler deploy --dry-run` -> `wrangler deploy`,
dev then staging, both manual; production only by the owner after adding a
route, never by automation.

## Open items

- Apple / Google sign-in: verifiers are in place; switching them on needs
  `APPLE_BUNDLE_ID` / `APPLE_SERVICE_ID` / `GOOGLE_CLIENT_IDS` per environment
  (see "Parent accounts") and the clients sending `identityToken`.
- Wire `expireTombstones(db, now)` into the retention purge (`purgeExpired`).
- Agent E: provider module + registry wiring; Agent F: billing.
- The Godot clients still call the prototype's `/api/v1/...` paths and send
  no `Authorization`; that works, but once accounts exist in the app the
  client should mint `pa1` via `POST /v1/parents/approval` instead of the dev
  literal (the dev literal is DEV_MODE only).
- `compatibility_date` is pinned to 2026-08-01 by the test pool's workerd;
  bump with the pool.
