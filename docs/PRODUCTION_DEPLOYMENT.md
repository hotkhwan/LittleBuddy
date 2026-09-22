# Production Deployment

## Closed deployment sequence

1. Inspect Cloudflare account `8d67bfb5b60f8e54544e4aac74a98cc9`, existing Workers/routes, and D1 list using Wrangler OAuth.
2. Create `little-days-prod` only if it does not exist. Copy the returned ID into the production D1 binding; never invent it.
3. Configure unique production secrets and confirm development/staging values are not reused.
4. Apply migrations 0001–0006 to the newly created database; capture output and run foreign-key/schema checks.
5. Deploy `little-days-api` with `PRODUCTION_ENABLED=false`, `BILLING_ENABLED=false`, `LIVE_CHILD_AUDIO_ENABLED=false`, and mock providers.
6. Confirm `/healthz` and `/readyz`. Public tutor, real billing, and school redemption must remain denied.
7. Inspect `api.littledays.joinanny.com`; attach only to `little-days-api`. Do not modify the `littledays.joinanny.com` website Worker.

No deployment was performed in this sprint. The first package lookup was blocked by DNS, and the locally installed Wrangler then confirmed that the saved OAuth token is expired and cannot refresh non-interactively. The production D1 ID therefore could not be verified.

## Recovery

D1 backup availability must be confirmed in the actual Cloudflare plan before launch. Recovery rehearsal: restore/copy to a separate D1 database, apply missing forward migrations, reconcile purchases from immutable verified store events, reconstruct entitlement grants, restore contract license rows, and compare audit totals before binding traffic. Migration rollback is forward-fix or database restore; destructive down migrations are prohibited in production.

Do not claim backups exist until the dashboard/API confirms retention and a restore drill succeeds.
