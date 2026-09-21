# Cloudflare development deployment — 2026-09-21

| Item | Value |
|---|---|
| Cloudflare account | `8d67bfb5b60f8e54544e4aac74a98cc9` (Hotkhwan@hotmail.com's Account, owner of the `joinanny.com` zone); pinned as `account_id` in `cloud/wrangler.toml`. The OAuth login sees two other accounts; neither is used. |
| Auth | owner's `wrangler login` OAuth (no API token requested, none stored by us) |
| Worker | **`little-days-api-dev`** (environment `dev`, `DEV_MODE=1`, workers.dev enabled). Created by this deploy; no other Little Days API Worker existed. |
| Endpoint | `https://little-days-api-dev.hotkhwan.workers.dev` |
| D1 | `little-days-dev` `5c1b5784-be19-4125-9375-82e05b507a34` (created by the owner earlier today, 0 tables) — binding `DB` |
| Migrations | `0001_accounts`, `0002_entitlements_billing`, `0003_tutor`, `0004_progress` applied remotely, all ✅ (`/healthz?db=1` reports `migrations: 4`) |
| Durable Objects | `TUTOR_SESSION` (TutorSessionDO), `QUOTA` (QuotaDO), migration tag v1 (SQLite classes) — exercised by the live session below |
| Secrets | `PARENT_TOKEN_SECRET` generated and uploaded to `dev` only. No `OPENAI_API_KEY`, no store secrets. |
| Cron | `17 3 * * *` retention purge |
| Cloud Tutor | Godot flag `little_days/ai_tutor/cloud_enabled=false` unchanged; realtime token endpoint answers `503 provider_unavailable` |
| Billing | `BILLING_ENABLED=false`; `/v1/billing/verify` answers `503 billing_disabled` |
| R2 | not enabled on the account and not needed |

## Live checks over HTTPS (verbatim, trimmed)
```
GET /healthz            200 {"ok":true,"service":"little-days-cloud","apiVersion":"v1","devMode":true,"provider":"mock","lessons":6,"billingEnabled":false}
GET /healthz?db=1       200 ... "db":{"ok":true,"migrations":4}
GET /v1/children        403 not_approved                      (no credential)
POST /v1/parents        200 dev provider -> parentToken + parentApprovalToken (created:true)
PUT /v1/consent         200 ai_tutor granted
POST /api/v1/tutor/sessions   200 sessionId, entitlement free, quota 300 s / 60 turns
POST .../turns (key qa-t1)    200 validated TutorTurn "Nice! Yes! Red! ..." flashcard color_red
POST .../turns (same key)     200 idempotent-replayed: true
POST .../turns transcript:123 400 bad_request "transcript must be a string"
POST .../turns bogus token    403 not_approved
GET /api/v1/tutor/entitlement 200 usedSeconds 4.1 -> quota accounting live (QuotaDO)
POST /v1/tutor/realtime/token 503 provider_unavailable
POST .../end                  200 endedAt, usedSeconds 5.5
POST .../turns after end      409 session_ended
POST /v1/billing/verify       503 billing_disabled
```

## Domain and routes (inspected, not changed)
- Zone `joinanny.com` is active in this account.
- `api.littledays.joinanny.com/*` exists as a **Workers Route with no script**
  ("Workers are disabled on this route"). No Custom Domain is attached to any
  Worker for that hostname (the account's Workers list holds only
  `littledays-web`, the website, which was not touched).
- `cloud/wrangler.toml` `[env.production]` now names the owner's intended
  Worker `little-days-api` and carries
  `routes = [{ pattern = "api.littledays.joinanny.com/*", zone_name = "joinanny.com" }]`.
  **Production was NOT deployed.** When the owner deploys production by hand
  (`README` "Safe deployment"), that route becomes active with this Worker;
  `littledays.joinanny.com` (website) is unaffected.
- The dev Worker is deliberately NOT attached to the API hostname: it runs
  `DEV_MODE=1` (dev sign-in) and must not be public on the product domain.

## Remaining configuration
1. Production: `npx wrangler d1 create little-days-production` → paste id →
   migrations → new `PARENT_TOKEN_SECRET` → `deploy --dry-run --env production`
   → owner deploys by hand.
2. Staging (optional before production): same with `little-days-staging`.
3. `OPENAI_API_KEY` as a Worker secret only after the privacy gates
   (docs/ALIZ_TUTOR_PRIVACY_REVIEW.md) pass.
4. Apple/Google sign-in verification (Agent B, in progress) and store secrets
   (docs/FAMILY_CLUB_BILLING.md) before any real account or purchase.
5. The OAuth token's listed scopes are user/account read + workers write;
   D1 commands worked. If a future command needs a missing scope, re-run
   `npx wrangler login` (default scopes) — never paste a raw API token.
