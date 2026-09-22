# Production Readiness

Verdict: **closed production deployed; not ready to open**. Infrastructure is deployed behind mandatory disabled feature gates, but store, provider, legal, security, and operational gates remain.

## Completed

- Additive migration 0006; all migrations apply to a fresh SQLite database with 36 tables and clean foreign-key check.
- Consumer plan policy, normalized entitlement response, child-profile limits, generic content grants, monthly usage, provider budgets, and closed-mode flags.
- Apple/Google neutral commerce lifecycle with idempotency, ownership, stale-event, refund/revoke/restore behavior.
- School license domain with tier/seat/device/pool enforcement and concurrency tests.
- Monthly pooled Live reservation/finalization in Durable Objects.
- Request IDs, structured errors/logging, `/healthz`, `/readyz`, consent/privacy/audit schema.
- 31 pure commerce/licensing tests passing; full Cloud TypeScript type-check passing.
- Production D1 created in APAC and migrations 0001–0006 applied with foreign keys enabled.
- Production Worker deployed with a unique signing secret, mock providers, and `PRODUCTION_ENABLED=false`, `BILLING_ENABLED=false`, `LIVE_CHILD_AUDIO_ENABLED=false`.
- `api.littledays.joinanny.com` attached as a Cloudflare Custom Domain without changing the website Worker.

## Failed or blocked gates

- Full Worker integration tests still require an environment where workerd may bind its local loopback listener; the isolated commerce/licensing suite and production synthetic probes are green.
- Full Worker suite: workerd attempted a loopback listener forbidden by this sandbox (`EPERM`), so the integration matrix is not green here.
- Store credentials/products and webhook trust chains are absent; billing stays disabled.
- Gemini credentials/privacy approval are absent; child Live audio stays disabled.
- School service still needs its production D1/DO repository and routes wired before activation can open.
- OpenAI/DeepSeek/Gemini Cloud provider adapters must be wired to the Worker registry and contract-tested in staging; mock is the configured safe default.
- Distributed account/plan endpoint rate limiting, production CORS decision, data-recovery drill, external security review, and legal privacy approval remain.
- Apple and Google products, server credentials, notifications, sandbox/license testers, and physical-device purchase/restore/refund/expiry tests remain owner work.
- Product IDs are inconsistent between the newer billing implementation (`little_days_family_monthly/yearly`) and the account/API configuration (`little_days.family_club.monthly/yearly`); reconcile this before configuring store products or enabling billing.
- Stripe is intentionally unsupported in the mobile billing scope. No Stripe credential is required unless a later owner-approved web-billing scope is added.

## Launch gates

All unit, Worker integration, migration-on-copy, authorization isolation, quota race, store sandbox notification, restore, health/readiness, and security checks must pass in staging and closed production. Owner approval is separately required to enable billing, publish store products, or allow public child Live audio.
