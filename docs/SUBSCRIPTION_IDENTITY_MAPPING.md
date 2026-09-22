# Subscription Identity Mapping

## Non-negotiable rule

A guest cannot purchase. Family, Premium, and Premium+ actions first pass the Parent Gate and complete account linking. The server rejects purchase verification unless the authenticated principal is a parent account and the store account marker maps to that same account.

Real billing remains disabled in committed settings and must not be enabled by this work. The repository has a billing hard switch, receipt verification handlers, Apple/Google notification ingestion, a development mock flow, and parent-only `GET /v1/me/purchase-identity`. Its legacy billing endpoint still maps decisions to `clientId`; parent-account ownership and strict marker matching are required before production sales.

## Apple / StoreKit 2

Create a stable random UUID `appAccountToken` for each Little Days parent account. Store the mapping server-side; the mobile app receives only the UUID needed for StoreKit. Reuse it for all that account's purchases and restores; never derive it from email or provider subject.

The app includes `appAccountToken` in the StoreKit purchase option. The backend verifies the signed transaction and requires its returned `appAccountToken` to map to the authenticated `parentAccountId`. A missing/mismatched value is quarantined or rejected; it must not grant entitlement. Persist hashed transaction/original-transaction references and process App Store Server Notifications idempotently.

Required configuration and access:

- Apple Developer team and explicit App ID/bundle ID with Sign in with Apple and In-App Purchase capabilities.
- App Store Connect subscription products/groups, agreements, tax, and banking setup.
- App Store Server API issuer ID, key ID, `.p8` private key, environment, and notification URL.
- Sign in with Apple bundle ID; Services ID only if a web flow is used.
- Xcode signing team/provisioning and an App Store Connect sandbox tester or StoreKit test configuration.

Repository variable names are not fully uniform: identity reads `APPLE_BUNDLE_ID`/`APPLE_SERVICE_ID`; billing currently expects `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, and an IAP private-key secret. Reconcile `.dev.vars.example`, `Env`, and billing names before deployment; never commit credentials.

## Google Play Billing

Android uses Credential Manager Sign in with Google. The backend verifies the Google ID token and maps `sub`, not email, to the parent account.

Before launching a Billing purchase, set:

```text
setObfuscatedAccountId(HMAC-SHA256(serverSecret, parentAccountId))
setObfuscatedProfileId(HMAC-SHA256(serverSecret, childProfileId))  // optional
```

Use a versioned, URL-safe encoding within Play's length rules. Neither field may contain email, name, or other PII. The current endpoint uses HMAC-SHA-256 with the server secret, so enumerable account IDs cannot be guessed offline. The backend independently computes the expected value and compares it to the verified Play purchase. A mismatch does not grant entitlement.

Required configuration and access:

- Google Cloud OAuth client IDs accepted by the backend (`GOOGLE_CLIENT_IDS`), including the Android client configuration needed by Credential Manager.
- Android package name `com.joinanny.littledays`, SHA-256 signing certificate fingerprints, and a configured Play Console app.
- Play subscription/base plans/offers and license tester accounts.
- Google Play Developer API service account with least privilege, linked to Play Console.
- Real-time developer notification Pub/Sub topic/push authentication.
- A signed build installed through an internal test track for realistic Billing tests.

The billing module and example configuration use `GOOGLE_PACKAGE_NAME=com.joinanny.littledays`, `GOOGLE_SERVICE_ACCOUNT_JSON`, and `GOOGLE_RTDN_TOKEN`. Real credentials remain server-side and billing remains disabled.

## Backend purchase sequence

1. Authenticate parent; reject guest before any store call.
2. Resolve the server-owned account marker and allowed product/plan.
3. Client starts the platform purchase with that marker.
4. Client sends the signed transaction/purchase token; never an asserted entitlement.
5. Backend verifies with Apple/Google, product, environment/package/bundle, state, expiry, and account marker.
6. In one idempotent transaction, store the event and project subscription/entitlement to `parentAccountId`.
7. `GET /v1/me/entitlements` returns backend state. Store callbacks can renew, grace, revoke, or expire it.

Product IDs map server-side to only `FAMILY`, `PREMIUM`, or `PREMIUM_PLUS`. `FREE` is policy, `SCHOOL` comes from licensing, and guest is a principal type—not a paid plan.

## Trial and restore rules

Premium Live trial state is stored against `parentAccountId` with immutable eligibility/consumption events. Uninstall, new installation, or another device cannot reset it. Restore signs into the parent account, revalidates store history, and reconstructs entitlement; it does not trust a local cache beyond the existing bounded offline grace policy.

## Required negative tests

- Guest purchase start and receipt verification are denied.
- Apple `appAccountToken` and Google obfuscated account mismatches grant nothing.
- Receipt replay is idempotent; cross-account replay conflicts.
- Product/package/bundle/environment mismatch is rejected.
- Refund/revocation removes or downgrades entitlement even while sales are disabled.
- Reinstall and multi-device restore preserve trial consumption and subscription ownership.

Physical-device QA is mandatory for Apple authorization, StoreKit sandbox, Android Credential Manager, Play Billing/internal track, secure credential persistence, uninstall/reinstall semantics, and restore behavior. Simulator/editor mocks are necessary but not sufficient.
