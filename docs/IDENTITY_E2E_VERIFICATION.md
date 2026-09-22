# Identity End-to-End Verification

Verified 2026-09-22 against merge commit `41393bf` on `feature/ui-meshy-cloud`
(Codex `0f1bc51` merged: guest -> parent identity, migrations 0006/0007,
`cloud/src/routes/identity.ts`, `game/scripts/account/*`).

Evidence sources, all synthetic data, no real store, no charge:

- **LIVE** — HTTPS calls to the dev Worker `https://little-days-api-dev.hotkhwan.workers.dev`
  (`GET /v1/health?db=1` -> `{"devMode":true,"provider":"workers_ai","billingEnabled":false,"db":{"ok":true,"migrations":7}}`;
  `GET /readyz` -> `{"ok":true,"closed":true,"billingEnabled":false,...}`).
- **POOL** — `cloud/test/identity_e2e.test.ts` in the workerd test pool
  (`cd cloud && npm test`: **254 passed** = 246 baseline + 8 new; `npm run typecheck` clean).
- **GODOT** — `game/tests/cases/test_identity_e2e_{first_install,guest_purchase_blocked,link_contract}.gd`
  (`godot --headless --path game --script res://tests/run_tests.gd`), plus the pre-existing
  `test_account_identity`, `test_store_gateway`, `test_entitlement_no_purchase_guard`, `test_billing_flags`.

Nothing was run on a physical device. No file outside the three new test files and this
document was edited.

## State table

| State | Client (Godot) | Wire | Worker records / answers | Verdict |
| --- | --- | --- | --- | --- |
| **First install** | `InstallationIdentity.load_or_create()` mints a UUID v4 with `Crypto.generate_random_bytes(16)`; `user://installation.json` holds exactly `{"installationId","version":1}`. No `OS.get_unique_id`, model name, IP/MAC, IDFA/IDFV or ANDROID_ID is read (GODOT scans executable lines). Reinstall (file gone) mints a new id. | `POST /v1/auth/guest` body `{installationId, platform, appVersion}` — nothing else (GODOT pins `IdentityApi.request_shape`). | LIVE 201: `{"guestAccountId":"1cab8220-…","installationId":"6f188783-…","guestToken":"gt1.…","accountType":"guest"}`. Rows: `installations(platform='ios', account_id=NULL, guest_account_id=<gid>, app_version, status='active')`, `guest_accounts(status='active', merged_into=NULL)`. POOL: `PRAGMA table_info` on `installations`, `guest_accounts`, `guest_learning_progress`, `guest_settings`, `guest_ai_usage` has **no** column matching `name/email/phone/birth/address/nick` — a child name or e-mail cannot be stored. Relaunch with the same id -> LIVE 200, same `guestAccountId`, still one row. Hardware-shaped / non-UUID ids -> 400. | PASS (server). **GAP G1** on the client: the Worker answers `guestToken`, `LittleDaysAccountState.apply_guest_response()` reads `sessionToken`/`token`, so the live reply is rejected (returns `false`). Nothing in the game calls the account layer yet, so nothing is broken in play. |
| **Guest** | `AccountCredentialStore` writes only `{accountId, accountType, sessionToken, expiresAt}` through `FileAccess.open_encrypted_with_pass`; an `identityToken`, `email`, `childName`, `installationId` handed to it are dropped and the file bytes contain no plaintext token (GODOT). `subscription_action(true)` -> `{"allowed":false,"action":"link_account"}`; `ParentAccountUx.view().showInChildUi == false`. | `GET /v1/me/entitlements` with `Authorization: Bearer gt1.…` | LIVE 200: `{"accountType":"guest","plan":"FREE","paid":false,"canPurchase":false,"features":["core_game","local_lessons","standard_ai_trial"],"premiumLiveTrial":false}`. Guest token claims: `{"gid","iid","iat","exp"}` (30-day TTL, `PARENT_TOKEN_TTL_SECONDS`). A tampered token -> 401 `invalid_guest_session`. gt1 on `/v1/parents/me` -> 403; pt1 on `/v1/auth/link` -> 401. | PASS |
| **Local learning, no account** | `little_days/services/backend_url=""` and `ai_tutor/backend_url=""` in `project.godot`; `IdentityApi.create_guest()` returns `false` and sends nothing when no URL is configured. GODOT scan: no file under `res://scripts` or `res://scenes` (outside `scripts/account/`) references `InstallationIdentity`, `IdentityApi`, `LittleDaysAccountState`, `AccountCredentialStore` or `ParentAccountUx`. | none | none | PASS — the whole offline suite is the evidence (see "Offline suite" below). |
| **AI trial as a guest** | The shipped tutor client sends `X-Parent-Approval: dev-parent-approval` in DEV_MODE (`use_dev_token()`); it never sends the guest token. | `POST /v1/tutor/sessions` | With `gt1` as bearer -> LIVE 403 `not_approved` ("The parent sign-in has expired"); as `X-Parent-Approval` -> 403 `not_approved`. With the DEV literal and the guest installation id as `clientId` (own child `E2E Guest Trial` under `dev-parent`): LIVE 201 `quota:{"entitlement":"free","dailyAllowanceSeconds":300,"usedSeconds":0,"remainingSeconds":300,"dailyTurnAllowance":60}`; `POST …/end` with `x-debug-now` +20 s -> `"usedSeconds":20,"remainingSeconds":280`; `GET /v1/tutor/quota` confirms 20/300. POOL: turn at +12 s -> `usedSeconds 12`, end at +20 s -> `20`. | Allowance 300 s and charging: PASS. **GAP G2**: the guest identity (`gt1`) cannot open a tutor session — `authMiddleware` accepts only `pt1`/`pa1`/the DEV literal — so `standard_ai_trial` in the guest entitlement is not reachable with the guest credential, and the trial is charged to the approving parent's child quota (QUOTA DO), never to `guest_ai_usage` (POOL asserts 0 rows). The link-time usage import therefore has nothing to carry. |
| **Purchase blocked (guest)** | `BillingFlags.purchases_enabled()` is `false` (committed). `StoreGatewayFactory.for_platform("iOS"/"Android"/"macOS"/"Windows"/"Linux").purchase(little_days_family_monthly)` -> `{"status":"disabled"}` on every platform; `PurchaseFlow.begin_purchase(product, true)` -> `{"outcome":"disabled"}`, gate closed -> `gate_closed`; zero requests reach the transport; iOS/Android `restore_purchases()` -> `unavailable` (no plugin). Replaying the five recorded Worker refusals through `BillingVerifyClient._on_reply` yields `verify_failed` (`backend_unavailable` for 5xx, `rejected` with the API code for 4xx) and `StoreEntitlementProvider` stays on Free Starter every time (GODOT). | `POST /v1/billing/verify` `{store, productId, transactionId, payload, clientId=<installationId>}` | LIVE: gt1 only -> 403 `not_approved` (auth middleware; billing is not auth-exempt). DEV approval + `store=apple`/`google` -> 503 `{"ok":false,"code":"billing_disabled"}` (server switch `BILLING_PURCHASES_ENABLED` unset, before any store call). `store=mock` -> 403 `mock_not_allowed` (`BILLING_DEV_MODE` unset on dev). POOL: `handleVerify` with `BILLING_PURCHASES_ENABLED=1` and a stub Apple verifier vouching for the receipt, guest installation as `clientId` -> 403 `parent_account_required` (`handlers.ts:126-127`). `GET /v1/me/purchase-identity` with gt1 -> LIVE 403 `parent_account_required`. | PASS |
| **Link (guest -> parent)** | `IdentityApi.link_account(session_token, provider, identity_token)` -> `POST /v1/auth/link`, bearer = guest token, body exactly `{provider, identityToken}`. `provider_link_request()` refuses `dev`, `facebook`, `""`, `APPLE`, an empty token, and a client with no session (GODOT). | `POST /v1/auth/link` `Authorization: Bearer gt1.…` `{provider:"apple"|"google", identityToken, nonce?}` | POOL (synthetic Apple JWS signed by a test RSA key, fake JWKS served for `appleid.apple.com/auth/keys`, `APPLE_BUNDLE_ID=com.joinanny.littledays`): 200 `{parentAccountId, linkedGuestAccountId, parentToken:"pt1.…", provider:"apple", mergeStatus:"complete"}`; reply contains no raw subject. Rows: `guest_accounts.status='linked', merged_into=<account>`, `installations.account_id=<account>, guest_account_id=NULL`, `identity_providers` 1 row, `parent_profiles` 1 row, `parent_accounts(provider='apple', subject_hash=HMAC hex, email_hash=HMAC hex)` — no raw subject or e-mail in any row. LIVE: providers unconfigured -> 501 (see "No fabricated sign-in"); `provider:"dev"` -> 400 `provider must be apple or google`, so the link **cannot be exercised on the live dev API** without real Apple/Google credentials. | PASS in POOL; not reachable LIVE by design. **GAP G3**: the Worker answers `parentToken`, `apply_link_response()` reads `sessionToken`/`token` -> rejected on the client (GODOT characterises). |
| **Migrate** | n/a | same call | POOL seeds two `guest_learning_progress` rows, 1 award, 1 unlock, 1 setting, `guest_ai_usage(2027-01, 90 s)`. After link: `account_learning_progress` 2 rows (`colors_red_blue` mastery 0.8 stars 3), `account_reward_awards` 1, `account_unlocks` 1, `account_settings` 1, `account_ai_usage.standard_seconds=90`, `account_ai_usage_imports` 1. Replaying the link with the spent guest token -> 401 `guest_token_replay`; every count unchanged (no duplicated stars/usage). `POST /v1/auth/guest` for the linked installation -> 409. `mergeGuest()` itself is idempotent (Codex's `guest_identity.test.ts`). | PASS. Note: the doc says a second link request "returns the original result"; the route answers 401/409 instead (see G4). Note also that the migrated tables (`account_learning_progress`, …) are not the tables the game's `PUT /v1/progress` writes (`progress` by `child_id`); the merged rows are not yet read by any route. |
| **Entitlement after link** | `subscription_action(true)` for a linked parent -> `{"allowed":true,"action":"continue_purchase"}`; `ParentAccountUx.view().providers == []`. | `POST /v1/dev/entitlements {entitlement:"family_club",days:30}` (DEV_MODE, parent bearer) then `GET /v1/me/entitlements` | LIVE (dev sign-in `provider:"dev"`, synthetic subject): before grant `{"accountType":"parent","plan":"FREE","paid":false,"canPurchase":true,"child_profile_limit":1,"standard_daily_seconds":300,…}`; grant -> `{"entitlement":"family_club","productId":"little_days.family_club.monthly","source":"dev"}`; after -> `{"plan":"FAMILY","paid":true,"features":["core_game","local_lessons","standard_ai","basic_progress"],"child_profile_limit":3,"standard_daily_seconds":3600,"subscription_status":"active","expires_at":"2026-10-22T09:33:09.836Z"}`; `GET /v1/parents/me/subscription` -> `entitlement:"family_club", managedBy:"dev"`. `GET /v1/me/purchase-identity` -> `{"apple":{"appAccountToken":"<uuid>"},"google":{"obfuscatedAccountId":"<hmac hex>"},"containsPii":false}`, identical on repeat. POOL: same after an Apple link. The mock-store path is off on dev (`BILLING_DEV_MODE` unset). | PASS |
| **Restore (second installation)** | A restored parent session on another installation reads `is_linked() == true` through `AccountCredentialStore` (GODOT). | second `POST /v1/auth/guest` + `POST /v1/auth/link` with the same Apple subject | POOL: device B (android) gets its own guest, links to the same subject -> same `parentAccountId`; `/v1/me/entitlements` -> `FAMILY`, same `expires_at`; `/v1/me/purchase-identity` byte-identical. Counts: `identity_providers` 1, `parent_accounts` 1, `accounts` 1, `parent_profiles` 1, `account_learning_progress` 1 (device A's row, not duplicated), `installations(account_id, active)` 2, `guest_accounts(linked, merged_into)` 2, active `entitlements` 1. LIVE (dev provider): second sign-in same subject -> `created:false`, same `parentId`; `/v1/me/entitlements` FAMILY on device 2; tutor quota for a shared child from device 1 and device 2 -> `"entitlement":"family_club","dailyAllowanceSeconds":1800` on both. | PASS |
| **Reinstall** | `InstallationIdentity` file gone -> new UUID (GODOT). | new `POST /v1/auth/guest`, then link | POOL: new installation id, new guest; link with the same subject -> same account, `FAMILY`; `installations(active)` 3, progress rows still 1, identity mapping still 1; the old installation row is untouched (`status='active'`, `account_id` set). | PASS (documented behaviour: a reinstall is a new guest until linked; an unlinked guest's data is lost with the install). |
| **No fabricated sign-in** | No Sign in with Apple / Credential Manager adapter exists (GODOT scans `scripts`, `scenes`, `ios`, `android`, `addons` for `ASAuthorization*`, `AuthenticationServices`, `CredentialManager`, `GetGoogleIdOption`, `GoogleIdTokenCredential`, `GIDSignIn`: none). | `POST /v1/parents {provider:"apple"|"google", identityToken}` | LIVE 501 `{"error":{"code":"not_implemented","message":"Apple sign-in is not configured on this server (APPLE_BUNDLE_ID / APPLE_SERVICE_ID)."}}` and `…Google sign-in is not configured on this server (GOOGLE_CLIENT_IDS).`. `POST /v1/auth/link` unconfigured -> 501 with `{"code":"not_approved","reason":"not_configured"}`. POOL: configured but wrong `aud` -> 403 `not_approved`/`wrong_audience`, no parent row created. | PASS |

## Route contract as observed

| Route | Auth | Request | Response |
| --- | --- | --- | --- |
| `POST /v1/auth/guest` | none | `{installationId: UUID v1-8, platform: ios\|android\|macos\|windows\|linux\|web\|unknown, appVersion?}` | 201 (new) / 200 (resume) `{guestAccountId, installationId, guestToken: "gt1.<b64url{gid,iid,iat,exp}>.<hmac>", accountType:"guest"}`; 400 bad id/platform; 409 if the installation is already linked or its guest is not active. |
| `GET /v1/me/entitlements` | `Bearer gt1` or `Bearer pt1` | — | guest: `{accountType:"guest", plan:"FREE", paid:false, canPurchase:false, features:[core_game, local_lessons, standard_ai_trial], premiumLiveTrial:false}`; parent: `{accountType:"parent", plan, paid, canPurchase:true, features, child_profile_limit, standard_daily_seconds, live_monthly_seconds, live_used_seconds, live_remaining_seconds, subscription_status, expires_at, school_entitlements}`; 401 `invalid_guest_session` for a bad/stale guest token. |
| `POST /v1/auth/link` | `Bearer gt1` (installation must still own the guest) | `{provider:"apple"\|"google", identityToken, nonce?}` | 200 `{parentAccountId, linkedGuestAccountId, parentToken:"pt1.…", provider, mergeStatus:"complete"}`; 400 other provider; 401 `invalid_guest_session` / `guest_token_replay`; 409 guest already linked or subject on a deleted account; 501/503 provider not configured/unavailable (code `not_approved`/`provider_unavailable`); 403 token rejected. |
| `GET /v1/me/purchase-identity` | `Bearer pt1` only | — | 200 `{apple:{appAccountToken: UUID}, google:{obfuscatedAccountId: HMAC hex}, containsPii:false}` (stable per account); 403 `parent_account_required` otherwise. |
| `POST /v1/parents` | none | `{provider:"dev", subject, clientId?}` (DEV_MODE) or `{provider:"apple"\|"google", identityToken, nonce?, clientId?}` | 201 `{parentId, provider, created, parentToken, expiresAt, emailVerified, devMode, parentApprovalToken?}`; 501 `not_implemented` when the provider audiences are unset. |
| `POST /v1/dev/entitlements` | parent credential, DEV_MODE only | `{entitlement:"free"\|"family_club", productId?, days?}` | 200 `{parentId, entitlement, productId, source:"dev"}` |
| `POST /v1/billing/verify` | parent credential (auth middleware) | `{store, productId, transactionId, payload, clientId}` | 503 `billing_disabled` (apple/google, switch off), 403 `mock_not_allowed` (mock, `BILLING_DEV_MODE` unset), 403 `parent_account_required` (guest installation, only reachable once a store vouches), 409 `purchase_account_mismatch`. |

Client-side (`game/scripts/account`): `installation.json` = `{installationId, version}`; encrypted
session = `{accountId, accountType, sessionToken, expiresAt}`; `IdentityApi` paths
`/v1/auth/guest`, `/v1/auth/link`, `/v1/me/entitlements`; the session header is a first-party
`Authorization: Bearer <token>`.

## Offline suite

`godot --headless --path game --script res://tests/run_tests.gd` (autoloads detached, no network,
no backend URL), 2026-09-22: **186 cases, 1 failure** — the single failure is the pre-existing,
unrelated `android_platform_guards` ("Android release metadata must be versionCode 2 / versionName
0.1.1 or newer": `game/tests/cases/test_android_platform_guards.gd:104` string-matches
`version/code=2` while `game/export_presets.cfg:98` already reads `version/code=3`). Every identity
and store case passed: `[PASS] identity_e2e_first_install`, `[PASS] identity_e2e_guest_purchase_blocked`,
`[PASS] identity_e2e_link_contract`, `[PASS] account_identity`, `[PASS] store_gateway`,
`[PASS] entitlement_no_purchase_guard`, `[PASS] billing_flags`, `[PASS] entitlement_service`,
`[PASS] entitlement_free_starter`. The account layer is not referenced by any gameplay script or scene, so the whole
suite (feeding, rooms, lessons, save/load, parent gate, entitlement guards) is the evidence that a
guest with no account plays the local game.

## Gaps and bugs (not fixed here)

- **G1 / G3 — client/Worker token key mismatch.** `game/scripts/account/account_state.gd:21`
  (`apply_guest_response` reads `sessionToken`/`token`; Worker sends `guestToken`) and
  `account_state.gd:32` (`apply_link_response`; Worker sends `parentToken`). Both live replies are
  rejected today. Characterised by `test_identity_e2e_first_install.gd` and
  `test_identity_e2e_link_contract.gd` (they print `GAP` and will fail with `GAP CLOSED` once the
  client accepts the Worker keys, at which point delete those assertions).
- **G2 — guest AI trial not reachable with the guest credential.** `cloud/src/auth/middleware.ts:34-57`
  accepts `pt1`/`pa1`/the DEV literal only; `cloud/src/routes/tutor.ts:52` (`createSession`) needs an
  approval token. `standard_ai_trial` in the guest entitlement is therefore aspirational, and usage
  is charged to a parent child quota, never to `guest_ai_usage` (nothing writes that table).
- **G4 — link replay semantics differ from the doc.** `docs/IDENTITY_ARCHITECTURE.md` ("A second
  request returns the original result"); `cloud/src/routes/identity.ts:24` answers 401
  `guest_token_replay` after the installation moved to the account, and `identity.ts:56` answers 409
  when the guest row is `linked`. Idempotent in effect (no duplication), not in shape.
- **G5 — error code on `/v1/auth/link` when a provider is unconfigured.** `cloud/src/routes/identity.ts:68`
  maps 501 to code `not_approved`; `POST /v1/parents` maps the same condition to `not_implemented`
  (`accounts.ts:66`). Clients keying on the code see two names for one condition.
- **G6 — the account layer is not wired into the game.** No scene or autoload calls
  `InstallationIdentity`/`IdentityApi`/`AccountCredentialStore`; the first-install -> guest call never
  happens in a running build (which also means a device today creates no server row).
- **G7 — no native sign-in adapters.** `parent_account_ux.gd` lists "Sign in with Apple" and
  "Sign in with Google" but nothing produces an `identityToken`: there is no
  `ASAuthorizationController` bridge in `game/ios/` and no Credential Manager
  (`GetGoogleIdOption`/`GoogleIdTokenCredential`) code in `game/android/`. `identity_api.gd` also has
  no `nonce` handling, which Sign in with Apple expects for replay protection.
- **Pre-existing (recorded, not Codex's):** `cloud/src/billing/test/handlers.test.ts` "Apple end to
  end" and "Google end to end" fail (`expected 200, actual 503`) because the memory-repo rig has no
  `env.DB`/`installations` table for the new owner check (`handlers.ts:124`). Separately,
  `GET /v1/billing/entitlement?clientId=…` answers **500 `internal_error`** on the live dev API:
  `cloud/src/billing/repo.ts:80` selects `entitlements.subject_id`, but no migration applies
  `cloud/src/billing/schema.sql`; the D1 `entitlements` table (migration 0002) is keyed by
  `parent_id, product_id, source`. The billing module also uses product ids
  `little_days_family_monthly` (matching the Godot `store_products.gd`) while the Worker's
  `FAMILY_CLUB_PRODUCT_IDS` are `little_days.family_club.monthly`; a verified store purchase would
  not become a Worker entitlement until those are reconciled.
- Two entitlement views disagree on the Family allowance: `/v1/me/entitlements` reports
  `standard_daily_seconds: 3600` (plan policy) while `/v1/tutor/quota` grants `1800`
  (`FAMILY_CLUB_DAILY_SECONDS`). Policy question, not a security issue.

## Remaining native sign-in work

1. **iOS — Sign in with Apple.** Add an `ASAuthorizationAppleIDProvider` request (scopes: none
   required; e-mail is optional and only hashed server-side) to the iOS plugin, pass a SHA-256 nonce,
   return `identityToken` (JWS) to GDScript; enable the capability on the App ID; set
   `APPLE_BUNDLE_ID` (and `APPLE_SERVICE_ID` only for a web flow) on the Worker.
2. **Android — Credential Manager.** `GetGoogleIdOption` with the Web client id as
   `serverClientId`, nonce set, return `GoogleIdTokenCredential.idToken`; set `GOOGLE_CLIENT_IDS`
   (Android + Web client ids) on the Worker.
3. **Client glue.** Wire `InstallationIdentity` -> `IdentityApi.create_guest()` on first launch and
   `link_account()` behind the parental gate; accept `guestToken`/`parentToken` in
   `LittleDaysAccountState` (G1/G3); persist through `AccountCredentialStore` (Keychain/Keystore
   replacement noted in that file); send `nonce` on link.
4. **Server.** Decide whether guests may open tutor sessions with `gt1` (G2) or whether the trial
   stays behind a parent approval; align the link replay contract (G4) and error code (G5);
   reconcile the billing schema/product ids before any store test.
5. **Device QA** (not done here): first install, Apple/Google link on a real device, reinstall,
   second device restore, all with sandbox/test accounts.


## Update (lead, same day)
Gap 1 (client token field names) is closed in `account_state.gd`: `apply_guest_response` reads `guestToken` and `apply_link_response` reads `parentToken` (older shapes still accepted); the two characterising cases now assert acceptance. The Android guard test's versionCode pin is monotonic (>= 2); the post-merge RC is versionCode 3.
