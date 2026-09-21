# Family Club billing

**Status: the store abstraction and the backend verification pipeline exist. NO REAL CHARGE PATH IS ACTIVE.**

Family Club is a paid expansion of AI Tutor time (300 s/day free, 1800 s/day with Family Club;
`game/content/tutor/quota_config.json`, `cloud/src/billing/config.ts`). Every existing game
mission, room and character stays free (`docs/FAMILY_CLUB.md`, `free_starter.json`).

| Decision (owner) | Where it is enforced |
| --- | --- |
| Product ids `little_days_family_monthly`, `little_days_family_yearly` | `store_products.gd`, `cloud/src/billing/config.ts` |
| Price hypothesis THB 99 / month, **proposed**, config only | `quota_config.json` `pricingProposed`, `config.ts` `PRICING_PROPOSED` (yearly: `null`, not decided) |
| Real charges DISABLED until owner approval + device QA | app: `little_days/billing/purchases_enabled=false`; server: `BILLING_PURCHASES_ENABLED` unset |
| The backend owns entitlement decisions | `store_entitlement_provider.gd` accepts only `apply_backend_decision()`; `cloud/src/billing/decision.ts` |
| Purchase UI stays behind the parent gate | `purchase_flow.gd` refuses without `parent_gate_open`; no purchase button exists |
| No Stripe checkout in the mobile app | nothing in `game/` references a web checkout; guard test token list |
| No child-directed purchase pressure | `test_entitlement_no_purchase_guard.gd` (copy scan, child-facing dirs, Learn-with-Aliz buttons) |

Guards: `game/tests/cases/test_billing_flags.gd`, `test_store_gateway.gd`,
`test_entitlement_no_purchase_guard.gd` (section 8, "the store layer, disarmed");
`cloud/src/billing/test/*.test.ts`.

---

## 1. Copy that is allowed

The app may print exactly these billing facts to a grown-up, behind the parental gate, and nothing
to a child:

| Copy | Source of truth |
| --- | --- |
| `THB 99 / month (proposed)` | `QuotaConfig.pricing_line()` - the word "proposed" is never dropped |
| `USD 2.99 / month` (proposed) | `parent_settings.gd` `PRICE_MONTHLY_USD` (Agent B) |
| `Billing is not available in this build.` | `BillingFlags.STATUS_TEXT_UNAVAILABLE` |
| `Annual pricing is not decided yet, so there is none to show.` | `parent_settings.gd` |
| Subscription status word: `Free` / `Family Club` (+ optional "until <date>") | `EntitlementService.subscription_status()` |

Forbidden anywhere (tested): "hurry", "limited time", "today only", "unlock", countdowns, "Buddy is
sad/needs/misses", any percentage, any annual number, any price outside Parent Corner and the quota
config, any of "subscribe / payment / buy now / credit card" in a child-facing file.

## 2. Flow

```
 grown-up (past the 3 s parental gate)
   |
   |  PurchaseFlow.begin_purchase(product_id, parent_gate_open = true)
   v
 StoreGateway.purchase()  -- base class: BillingFlags.purchases_enabled() ?
   |                        false (every committed build) -> {status: "disabled"}, NO store call
   |                        true  -> Apple / Google / Mock adapter _start_purchase()
   v
 purchase_updated(receipt)      {store, productId, transactionId, payload}   <- a RECEIPT, not a grant
   |
   |  BillingVerifyClient.verify(receipt)  ->  POST /v1/billing/verify (injected transport)
   v
 backend (cloud/src/billing)
   verify handler: BILLING_PURCHASES_ENABLED? (else 503 billing_disabled, no store API call)
     apple : signed transaction JWS verified locally (pinned Apple Root CA G3, Apple OIDs, ES256)
             or transactionId -> App Store Server API GET /inApps/v1/transactions/{id} -> same JWS check
     google: purchaseToken -> purchases.subscriptionsv2.get (service-account OAuth2) -> state fold
     mock  : BILLING_DEV_MODE only
   -> NormalizedTransaction -> processPurchaseEvent (idempotent, ordered) -> decideEntitlement (pure)
   -> entitlements row(s) upserted -> {ok, decision:{entitlementId, status, periodEnd, verifiedAt, ...}, quota}
   |
   v
 StoreEntitlementProvider.apply_backend_decision(decision, now)   <- the ONLY grant path on the device
   is_active("familyClub") == status in {active, grace} AND periodEnd > now AND now - verifiedAt <= 72 h
   persisted through EntitlementService.to_dict() "providerState"; re-checked against the clock on load
   |
   v
 TutorQuota.entitlement_name() -> "family_club" -> 1800 s/day   (unchanged call site)

 restore(parent_gate_open) : StoreGateway.restore_purchases() -> restore_finished({receipts}) ->
                             one verify per receipt -> same decision path (device B gets the same row set)

 Apple App Store Server Notifications V2 -> POST /v1/billing/apple/notifications (outer + inner JWS verified)
 Google RTDN (Pub/Sub push)              -> POST /v1/billing/google/rtdn (shared token / OIDC, then re-fetch)
   both -> processPurchaseEvent(subject = null) -> every device on that subscription is updated
```

Failure rule, both sides: a failed or missing verify **changes nothing**. It never grants and never
revokes; only a parsed decision does. A store callback alone grants nothing (tested).

## 3. Gate rules

1. `little_days/billing/purchases_enabled` is committed `false`. `StoreGateway.purchase()` is not
   overridable and returns `disabled` before any adapter code runs. `test_billing_flags.gd` reads the
   committed `project.godot` and `export_presets.cfg`, not the running settings.
2. No store plugin ships. `AppleStoreGateway` (`InAppStore` singleton, godot-ios-plugins `inappstore`,
   Godot 4.x branch) and `GooglePlayGateway` (`GodotGooglePlayBilling` singleton,
   godot-google-play-billing v2/v3 for Godot 4, Play Billing Library 6-7) report `store_unavailable`
   when `Engine.has_singleton()` is false, which is every current build. Exact plugin builds are to be
   pinned at activation (checklist below).
3. `PurchaseFlow.begin_purchase()` / `restore()` refuse unless the caller passes `parent_gate_open = true`.
   Only the grown-up screen behind the 3-second hold may own a gateway or a flow; the guard test fails
   if any child-facing file or any `.tscn` references `scripts/entitlement/store/`.
4. The device never validates. `StoreEntitlementProvider` has no method that takes a receipt; the
   backend's decision is sanitised field by field (known entitlement, known status, known product,
   product -> entitlement consistent) and a bad shape grants nothing.
5. The offline cache is bounded: `periodEnd` and a 72-hour `verifiedAt` window
   (`BillingFlags.OFFLINE_CACHE_SECONDS`). A hand-edited save cannot extend either (tested).
6. Server side, real stores are consulted only when `BILLING_PURCHASES_ENABLED="1"`. Notifications
   (refunds) are honoured regardless, so switching verification off never leaves a refunded family entitled.
7. No purchase button, price sheet or "restore" button ships. Agent B's Parent Corner keeps printing
   the proposed prices as information and `Billing is not available in this build.`

## 4. Backend contract

`POST /v1/billing/verify`
```json
{"store":"apple|google|mock","productId":"little_days_family_monthly","transactionId":"...","payload":{...},"clientId":"<per-install id>"}
```
`payload`: apple `{signedTransaction}` (StoreKit 2) or `{transactionId}` (StoreKit 1 plugin; the server
looks it up); google `{purchaseToken, packageName}`; mock `{mock:true, productId, transactionId, originalTransactionId}`.

`200 {"ok":true,"outcome":"applied|replayed|stale","decision":{"entitlementId":"familyClub","status":"active|grace|expired|revoked|none","periodEnd":<unix s>,"verifiedAt":<unix s>,"originalTransactionId":"...","store":"...","productId":"...","quotaTier":"family_club|free","allowanceSeconds":1800,"reason":"..."},"quota":{"entitlement":"family_club","dailyAllowanceSeconds":1800}}`

| status | code | meaning |
| --- | --- | --- |
| 400 | `unknown_product`, `product_mismatch`, `receipt_rejected`, `bad_request` | the caller's receipt |
| 403 | `mock_not_allowed` | mock store outside `BILLING_DEV_MODE` |
| 409 | `conflict` | same transaction, different payload; or too many devices on one subscription (6) |
| 503 | `billing_disabled`, `store_not_configured`, `store_unavailable` | the server's side; the client keeps what it had |

`GET /v1/billing/entitlement?clientId=` re-evaluates the stored row against the clock (a lapsed
subscription reads `expired` on time even if no notification arrived).

Idempotency: `purchase_events.transaction_id` is the event key (`verify:<store>:<txn>:<clientId>`
for device verifies, `<store>:<txn>[:<notificationId>]` for store events). Same key + same
`payload_hash` -> the stored result is replayed; same key + different hash -> 409. Ordering:
per subscription, an event older than the last applied one is recorded as `stale` and does not
regress the row; a revocation always applies. Schema: `cloud/src/billing/schema.sql` (to reconcile
with Agent D's D1 migration; column names are the integration point).

Quota integration: `allowanceForSubject(deps, clientId)` / `decisionFromRow()` give the tutor quota
the daily allowance from one place (`config.ts` `DAILY_ALLOWANCE_SECONDS`).

Tests: `cd cloud/src/billing && npm test` (Node 22, `node:test`, type stripping, zero dependencies;
a vitest config was not added because the worktree has no `cloud/package.json` yet and no network
to install dev dependencies - the tests are plain `node:test` and port to vitest by swapping the import).

## 5. Activation checklist (nothing below has been done)

**Owner**
- [ ] Approve the price (currently a THB 99 / month hypothesis; annual undecided) and the two product ids.
- [ ] Approve turning on real charges, in writing, after device QA below.

**App Store Connect**
- [ ] Create a subscription group "Family Club" with auto-renewable products
      `little_days_family_monthly` and `little_days_family_yearly`; set territory pricing (THB first).
- [ ] Generate an **In-App Purchase key** (Users and Access > Integrations > In-App Purchase):
      note Issuer ID, Key ID, download the `.p8` once.
- [ ] Configure App Store Server Notifications V2 (production + sandbox) to
      `https://<worker>/v1/billing/apple/notifications`.
- [ ] Sandbox tester accounts for QA; enable Billing Grace Period if wanted (the server honours
      `gracePeriodExpiresDate`).
- [ ] Confirm the pinned root fingerprint (`APPLE_ROOT_CA_G3_SHA256`) against apple.com/certificateauthority.

**Play Console**
- [ ] Create subscriptions `little_days_family_monthly` / `little_days_family_yearly` with base plans.
- [ ] Service account with "View financial data" and "Manage orders and subscriptions"; download its JSON key.
- [ ] Real-time developer notifications: Pub/Sub topic + push subscription to
      `https://<worker>/v1/billing/google/rtdn?token=<GOOGLE_RTDN_TOKEN>` (or OIDC push auth and
      inject `verifyPushBearer`).
- [ ] License testers for QA.

**Worker secrets / env** (`wrangler secret put`)
- [ ] `DB` D1 binding with `schema.sql` applied
- [ ] `APPLE_BUNDLE_ID`, `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_IAP_PRIVATE_KEY_P8`, `APPLE_ENVIRONMENT` (`sandbox` for QA)
- [ ] `GOOGLE_PACKAGE_NAME`, `GOOGLE_SERVICE_ACCOUNT_JSON`, `GOOGLE_RTDN_TOKEN`
- [ ] `BILLING_DEV_MODE` unset in production; `BILLING_PURCHASES_ENABLED` **unset until the last step**

**Game**
- [ ] Add the iOS `inappstore` plugin (godot-ios-plugins, Godot 4.x) to the iOS export and the
      `GodotGooglePlayBilling` plugin (godot-google-play-billing, Godot 4) to the Android export;
      pin the versions here.
- [ ] Wire `BillingVerifyClient` to a transport over the flag-gated tutor cloud client
      (`cloud_quota_client.gd` is the only script allowed to hold an `HTTPRequest`; add one
      `post_billing_verify()` method there).
- [ ] Agent B: a gated Family Club panel section that owns `PurchaseFlow` (buy / restore buttons appear
      only when `EntitlementService.describe().purchasingAvailable` is true) - still behind the gate,
      still with the no-pressure copy rules.
- [ ] Flip `little_days/billing/purchases_enabled=true` **only in the build under QA**; update
      `test_billing_flags.gd` / the guard when the owner signs off (they will go red on purpose).

**Device QA (sandbox / license testers)** before any production switch
- [ ] iPad + iPhone: buy on one, restore on the other, both show Family Club; the allowance is 1800 s.
- [ ] Refund in sandbox -> both devices drop to Free after the notification.
- [ ] Expiry (sandbox accelerated renewals) -> Free on time; grace period behaves.
- [ ] Airplane mode: Family Club persists < 72 h, then Free; reconnect restores it.
- [ ] Child never sees a price, a button or a lock; the gate is still 3 s.
- [ ] Android: same on two devices; Play acknowledges within 3 days (server does it).

Only after every box is ticked: `BILLING_PURCHASES_ENABLED="1"` on the Worker, then the app setting
in a release build. Until then: **no real charge path is active.**
