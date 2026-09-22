# Production Deployment

## Closed deployment sequence

1. Inspect Cloudflare account `8d67bfb5b60f8e54544e4aac74a98cc9`, existing Workers/routes, and D1 list using Wrangler OAuth.
2. Create `little-days-prod` only if it does not exist. Copy the returned ID into the production D1 binding; never invent it.
3. Configure unique production secrets and confirm development/staging values are not reused.
4. Apply migrations 0001–0006 to the newly created database; capture output and run foreign-key/schema checks.
5. Deploy `little-days-api` with `PRODUCTION_ENABLED=false`, `BILLING_ENABLED=false`, `LIVE_CHILD_AUDIO_ENABLED=false`, and mock providers.
6. Confirm `/healthz` and `/readyz`. Public tutor, real billing, and school redemption must remain denied.
7. Inspect `api.littledays.joinanny.com`; attach only to `little-days-api`. Do not modify the `littledays.joinanny.com` website Worker.

## 2026-09-22 deployment record

- Wrangler OAuth was verified for account `8d67bfb5b60f8e54544e4aac74a98cc9`.
- D1 `little-days-prod` was created in APAC with ID `88f3043d-d7a8-47b3-b315-33c4cf077f63`.
- Migrations 0001–0006 applied successfully; `PRAGMA foreign_keys` returned `1` and all six rows are present in `d1_migrations`.
- A unique production `PARENT_TOKEN_SECRET` was generated directly into Cloudflare Secrets (not persisted locally).
- Worker `little-days-api` was deployed with production, billing, and live-child-audio gates all disabled and both AI providers set to `mock`.
- `api.littledays.joinanny.com` is enabled as a Custom Domain for `little-days-api`. The obsolete exact-host route with no script was removed; the website Worker and `littledays.joinanny.com` were not changed.
- Cloudflare public DNS resolves the hostname. At the end of the deployment window the new edge certificate was still provisioning, so HTTPS health and synthetic probes must be repeated after TLS activation.

## Recovery

D1 backup availability must be confirmed in the actual Cloudflare plan before launch. Recovery rehearsal: restore/copy to a separate D1 database, apply missing forward migrations, reconcile purchases from immutable verified store events, reconstruct entitlement grants, restore contract license rows, and compare audit totals before binding traffic. Migration rollback is forward-fix or database restore; destructive down migrations are prohibited in production.

Do not claim backups exist until the dashboard/API confirms retention and a restore drill succeeds.
