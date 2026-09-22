# Production Subscriptions

Store product IDs map to internal `FAMILY`, `PREMIUM`, and `PREMIUM_PLUS` plans through backend configuration/data. Prices and regional presentation remain owned by Apple and Google and are not authoritative in the client.

The commerce domain normalizes Apple StoreKit and Google Play results into purchase, renewal, cancellation, expiration, refund, revocation, and restore events. Verification is injected behind store-specific interfaces. Event IDs are idempotent, replaying a different payload is rejected, stale events cannot overwrite newer state, and a transaction cannot move between accounts.

`GET /v1/me/entitlements` is the normalized client contract. The backend, never a client `isPremium` flag, owns plan, features, profile limit, Standard allowance, pooled Live usage/remaining time, status, expiration, school grants, and content packs.

Real charging remains disabled. Required launch inputs are Apple bundle/product configuration and App Store Server credentials/notification verification, plus Google package/product configuration, service-account access, and RTDN verification. Sandbox callback tests may run while production is closed. Store product mappings are currently `{}` rather than invented.

Commerce tests cover mapping, ownership isolation, duplicate/replayed events, stale delivery, purchase, renewal, cancel, expire, refund, revoke, restore, and closed-mode gates.

