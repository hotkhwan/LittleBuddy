# Little Days cloud backend (Cloudflare Workers)

The production shape of the Aliz AI Tutor backend: **Cloudflare Workers +
D1 + Durable Objects**, TypeScript, Hono. It supersedes the zero-dependency
Node prototype in `backend/` (kept as the reference implementation; its
domain rules, error codes and the shared `TutorTurn` fixtures are carried
over unchanged). Design notes: `docs/CLOUD_BACKEND.md`; API contract:
`docs/ALIZ_TUTOR_API.md`.

**Status: NOT DEPLOYED.** No Cloudflare account token, no `wrangler login`
and no OpenAI key exist on the machine this was built on. Everything below
runs locally (`wrangler dev --local`, the vitest Workers pool).

Owner decisions baked in: app name Little Days; existing game content free;
the AI Tutor needs internet; free AI Tutor 5 min/day (`FREE_DAILY_SECONDS=300`);
Family Club = paid expansion of tutor time (`FAMILY_CLUB_DAILY_SECONDS=1800`);
price hypothesis THB 99/month lives in config (`FAMILY_CLUB_PRICE_*`), never in
clients; real billing stays off (`BILLING_ENABLED=false`) until owner approval +
device QA; minimal child data, never a child's real name.

## Layout

```
cloud/
  wrangler.toml             dev / staging / production (own D1 + DO namespaces each)
  migrations/0001..0004     D1 schema (accounts, entitlements+billing, tutor, progress)
  src/index.ts              Worker entry: fetch + scheduled (daily retention purge); exports the DOs
  src/app.ts                Hono app: clock, IP limit, body cap, parent credential, routes
  src/env.ts                bindings + config parsing (no secret has a default)
  src/errors.ts             {error:{code,message}} shapes, codes = backend/src/errors.js (+3)
  src/auth/                 pt1 / pa1 HMAC tokens, credential middleware
  src/routes/               accounts (parents/children/devices/consent/entitlements/progress), tutor, dev
  src/do/quota_do.ts        QuotaDO: one per child, the daily counter authority
  src/do/tutor_session_do.ts TutorSessionDO: one per live session (ordering, clock, provider, alarm)
  src/db/                   D1 access (parents, children, devices, consent, entitlements, usage, ...)
  src/tutor/                validator (shared fixtures), lesson authority, mock provider,
                            provider_interface.ts (Agent E's contract), registry, cost
  src/tutor/provider/       AGENT E: OpenAI Realtime + turn provider (not present yet)
  src/billing/index.ts      AGENT F: stub router mounted at /v1/billing
  config/prices.json        list prices (copied from backend/config with source + date)
  test/                     vitest, Workers pool, 129 tests, offline
```

## Run locally

```sh
cd cloud
npm install --legacy-peer-deps        # npm 10.9 trips over vitest 4's optional peers without the flag
cp .dev.vars.example .dev.vars        # then set PARENT_TOKEN_SECRET=$(openssl rand -hex 32)
npm run migrate:local                 # wrangler d1 migrations apply little-days-dev --local --env dev
npm run dev                           # wrangler dev --local --env dev  -> http://127.0.0.1:8787
npm test                              # vitest run (Workers pool, no network)
npm run typecheck
```

Point the game at it exactly as for the prototype (`little_days/ai_tutor/backend_url`,
`-- --ai-tutor-cloud`, developer runs only). The Godot clients' paths
(`/api/v1/tutor/...`), the `X-Parent-Approval` header / `parentApprovalToken`
body field and the `dev-parent-approval` literal (DEV_MODE only) all work unchanged.

### Walkthrough (recorded against `wrangler dev --local --env dev`, 2026-09-21)

```
$ curl -s localhost:8787/healthz
{"ok":true,"service":"little-days-cloud","apiVersion":"v1","devMode":true,"provider":"mock","lessons":6,"billingEnabled":false}

$ curl -s -X POST localhost:8787/v1/parents -H 'content-type: application/json' \
    -d '{"provider":"dev","subject":"owner-1","clientId":"ipad-demo"}'
{"parentId":"0dab0e60-...","created":true,"parentToken":"pt1.<...>","expiresAt":"...","devMode":true,"parentApprovalToken":"pa1.<...>"}

$ curl -s -X PUT localhost:8787/v1/consent -H "authorization: Bearer $PT" -H 'content-type: application/json' -d '{"kind":"ai_tutor","granted":true}'
{"parentId":"...","requiredVersion":1,"consent":{"privacy":{...,"granted":false},"ai_tutor":{"version":1,"grantedAt":"...","revokedAt":null,"granted":true},"voice":{...}}}

$ curl -s -X POST localhost:8787/api/v1/tutor/sessions -H 'content-type: application/json' \
    -d "{\"lessonId\":\"colors_red_blue\",\"clientId\":\"ipad-demo\",\"parentApprovalToken\":\"$PA\"}"
{"sessionId":"fd92a937-...","childId":"4eb51f20-...","entitlement":"free","quota":{"entitlement":"free","dailyAllowanceSeconds":300,"usedSeconds":0,"remainingSeconds":300,"resetAtUtc":"2026-09-22T00:00:00.000Z","dailyTurnAllowance":60,"usedTurns":0},"lessonId":"colors_red_blue","lessonKnown":true}

$ curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/turns -H 'content-type: application/json' -H "X-Parent-Approval: $PA" -H 'Idempotency-Key: t1' \
    -d '{"transcript":"red","lessonContext":{"stepId":"s02_red","outcome":"correct","matched":"red"}}'
{"turn":{"speech":"Nice! Yes! Red! What colour is this?","subtitle":"...","emotion":"happy","gesture":"clap","visual":{"type":"flashcard","assetId":"color_red"},"lessonAction":"next_question","nextQuestion":"What colour is this?"},"quota":{...,"usedTurns":1},"endAtBoundary":false,"turnIndex":1,"chargedSeconds":0,"provider":"mock","cached":false,"fallback":null,"contextSource":"server","usage":{"sttSeconds":0,"llmInputTokens":0,"llmOutputTokens":0,"ttsChars":36,"latencyMs":1,"costUsd":0}}

$ # same Idempotency-Key again -> HTTP 200, header idempotent-replayed: true, nothing charged
$ curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/end            # no token
{"error":{"code":"not_approved","message":"A parent needs to approve tutor time first."}}
$ curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/end -H "X-Parent-Approval: $PA"
{"sessionId":"fd92a937-...","endedAt":"2026-09-21T08:08:07.546Z","quota":{...},"usage":{"turns":1,"llmInputTokens":0,"llmOutputTokens":0,"audioSeconds":0,"costUsd":0}}
$ curl -s "localhost:8787/api/v1/tutor/entitlement?clientId=ipad-demo" -H "X-Parent-Approval: $PA"
{"clientId":"ipad-demo","childId":"...","entitlement":"free","quota":{...},"products":["little_days.family_club.monthly","little_days.family_club.yearly"],"priceHint":{"currency":"THB","monthly":99,"status":"proposed"}}
$ curl -s -X POST localhost:8787/v1/tutor/realtime/token -H 'content-type: application/json' -H "X-Parent-Approval: $PA" -d '{"lessonId":"colors_red_blue","clientId":"ipad-demo"}'
{"error":{"code":"provider_unavailable","message":"Realtime tutoring is not configured on this server."}}   # no OPENAI_API_KEY
```

## Routes

All routes live under `/v1` and, for the shipped Godot clients, `/api/v1`.
Every route except health, sign-in and the two store webhooks requires a
parent credential: `Authorization: Bearer pt1.<...>` (parent sign-in) or
`X-Parent-Approval: pa1.<...>` / body `parentApprovalToken` (device approval,
itself parent-signed). Tutor routes need the approval token.

| Method | Path | Credential | Purpose |
| --- | --- | --- | --- |
| GET | `/healthz`, `/v1/health` | none | Liveness (`{ok, apiVersion}`; more in DEV_MODE) |
| POST | `/v1/parents` | none | Sign-in placeholder: `provider: dev` (DEV_MODE) -> `parentToken` (+ `parentApprovalToken` when `clientId` given); `apple`/`google` -> 501 until identity-token verification lands |
| GET | `/v1/parents/me` | any | Who am I |
| POST | `/v1/parents/approval` | bearer | Server half of the parental gate: mint `pa1` bound to `clientId` (+ optional `childId`) |
| GET, POST | `/v1/children` | any | Nickname/avatar/locale/birth-year-bucket profiles (no real name; max 6) |
| GET, POST | `/v1/devices` | any | Register `clientId` + platform + appVersion; a device belongs to one family (409 otherwise) |
| GET, PUT | `/v1/consent` | any / bearer | `privacy`, `ai_tutor`, `voice` with version + grant/revoke timestamps |
| GET | `/v1/entitlements` | any | Effective entitlement, allowances, products with `priceHint` from config, `billing.enabled` |
| GET | `/v1/tutor/quota`, `/v1/tutor/entitlement?clientId=` | any | Today's quota block for the child (Godot alias shape kept) |
| POST | `/v1/tutor/sessions` | approval | Start a session: consent + device + child + budget + quota, then `TutorSessionDO.start` |
| POST | `/v1/tutor/sessions/:id/turns` | approval (same token) | Idempotent, validated `TutorTurn`; server lesson authority |
| POST | `/v1/tutor/sessions/:id/end` | approval (same token) | End; returns quota + numeric usage totals |
| POST | `/v1/tutor/sessions/:id/usage` | approval (same token) | Realtime usage reports (cost accounting only) |
| POST | `/v1/tutor/sessions/:id/stop` | bearer | Parent Corner "stop now" |
| POST | `/v1/tutor/realtime/token` | approval | Ephemeral realtime token; 503 unless `OPENAI_API_KEY` + Agent E's module, consent `voice`, entitlement + quota |
| DELETE | `/v1/tutor/clients/:clientId` | any (bound) | Delete a device's learning history |
| GET, PUT | `/v1/progress` | any | Per-child lesson progress (lesson, step, stars, completedAt) |
| POST | `/v1/billing/apple/notifications`, `/v1/billing/google/rtdn` | signature (Agent F) | Store webhooks; 501 stub |
| POST | `/v1/billing/verify` | any | Receipt verification; 501 stub (Agent F) |
| POST | `/v1/dev/entitlements`, `/v1/dev/parent-approval`, `/v1/dev/retention/purge`; GET `/v1/dev/spend` | any | DEV_MODE only (404 elsewhere) |

Error codes: `bad_request`, `invalid_turn`, `not_approved`, `unknown_lesson`,
`not_found`, `session_ended`, `idempotency_mismatch`, `payload_too_large`,
`quota_exhausted` (`reason` `daily_quota` / `daily_turns` / `monthly_budget`),
`rate_limited` (+ `Retry-After`), `provider_unavailable`, `timeout`,
`not_implemented`, `internal` (all as in `backend/src/errors.js`) plus
`consent_required` (403), `conflict` (409), `method_not_allowed` (405).

## Configuration

Vars live in `wrangler.toml` (repeated per environment because Wrangler does
not inherit `vars`): allowances, caps, retention, budget, rate limits, product
ids, price hint, models. Secrets are never in the file:

| Secret | Purpose | Required |
| --- | --- | --- |
| `PARENT_TOKEN_SECRET` | HMAC key for `pt1`/`pa1` tokens, idempotency hashes, subject hashes | yes (no sessions without it) |
| `OPENAI_API_KEY` | enables Agent E's provider; realtime minting | no (absent -> mock turns, realtime 503) |
| `OPENAI_BASE_URL` | proxy / gateway | no |
| `APPLE_*`, `GOOGLE_*` | Agent F's store verification | not read yet |

DEV_MODE (`env.dev` only) enables: dev sign-in, the literal `dev-parent-approval`
token (a synthetic parent with all consents), `/v1/dev/*`, the `X-Debug-Now`
test clock header and the `TUTOR_PROVIDER=faulty` chaos provider. Never set it
in staging or production.

## Safe deployment

Rules first:

1. **Production is never deployed by automation.** No CI job, script or agent
   runs `wrangler deploy --env production`. The owner runs it by hand after
   staging sign-off and device QA, and only after adding the route in
   `wrangler.toml` (today production has no route and `workers_dev = false`,
   so even a deploy would be unreachable).
2. Each environment has its own D1 database and its own secrets. Never point
   two environments at one database id.
3. `DEV_MODE = "1"` exists only under `[env.dev.vars]`.
4. Secrets go in with `wrangler secret put`; `.dev.vars` never leaves the
   laptop; the `.example` file carries names only.
5. Review `wrangler deploy --dry-run --env <env>` output before a real deploy.

### Credentials on the MacBook (no `wrangler login` needed)

Store a **scoped API token** and the account id in the macOS keychain once
(the token needs Workers Scripts:Edit, D1:Edit, Account Settings:Read and
Workers Routes:Edit on the `joinanny.com` zone; never a Global API Key):

```sh
security add-generic-password -s CLOUDFLARE_API_TOKEN -a littledays -w '<token>'
security add-generic-password -s CLOUDFLARE_ACCOUNT_ID -a littledays -w '<account id>'
source tools/cf_keychain.sh          # exports both, prints only lengths
```

Then the first dev deployment is one script, preflight first:

```sh
LD_DEV_WORKER_NAME=<the Worker the owner created> tools/cf_deploy_dev.sh          # dry run
LD_DEV_WORKER_NAME=<the Worker the owner created> tools/cf_deploy_dev.sh --apply  # create dev D1, migrate, deploy dev, curl /healthz?db=1
```

`GET /healthz?db=1` proves the D1 binding and reports the number of applied
migrations (numbers only). The custom domain `api.littledays.joinanny.com`
belongs to production and is NOT attached by this script.

One-time per environment (owner, with `wrangler login`):

```sh
cd cloud

# dev
npx wrangler d1 create little-days-dev
#   -> paste the database_id into [[env.dev.d1_databases]] (replace REPLACE_WITH_DEV_DATABASE_ID)
npx wrangler d1 migrations apply little-days-dev --env dev --remote
npx wrangler secret put PARENT_TOKEN_SECRET --env dev          # openssl rand -hex 32
npx wrangler secret put OPENAI_API_KEY --env dev               # optional; only when Agent E's module is wired
npx wrangler deploy --dry-run --env dev && npx wrangler deploy --env dev
curl -s https://little-days-cloud-dev.<account>.workers.dev/healthz

# staging (same steps, staging names; DEV_MODE stays "0")
npx wrangler d1 create little-days-staging
npx wrangler d1 migrations apply little-days-staging --env staging --remote
npx wrangler secret put PARENT_TOKEN_SECRET --env staging
npx wrangler deploy --dry-run --env staging && npx wrangler deploy --env staging

# production: BY HAND ONLY, after staging sign-off + device QA + owner approval
#   1. add `routes = [{ pattern = "api.<owner-domain>/*", zone_name = "<owner-domain>" }]` under [env.production]
#   2. npx wrangler d1 create little-days-production ; paste id ; migrations apply --env production --remote
#   3. npx wrangler secret put PARENT_TOKEN_SECRET --env production (a NEW secret, never reused from dev/staging)
#   4. npx wrangler deploy --dry-run --env production ; read it ; npx wrangler deploy --env production
```

New migrations: add `migrations/000N_<name>.sql`, run the tests (they apply
every file), then `wrangler d1 migrations apply <db> --env <env> --remote`
dev -> staging -> production in that order. Migrations are additive; never
edit an applied file.

Logging: the Worker logs `method routePattern status ms` only (never URLs, ids,
headers, bodies). If Workers Logs / observability is enabled on the account,
Cloudflare's invocation logs will also include request URLs; those contain
opaque session UUIDs and `clientId`s but no child data. Transcripts and audio
never reach the Worker's logs or its database.

## R2

Not used, deliberately: nothing in this service is a file. No audio is ever
uploaded, receipts are hashed not stored, exports do not exist. Add a bucket
only when a real file workload appears.

## What Agents E and F implement

- **Agent E** (`cloud/src/tutor/provider/**`): a `ProviderFactory` per
  `src/tutor/provider_interface.ts` returning `{ name, turns, realtime }`;
  `turns.generateTurn()` returns a RAW candidate (the DO validates it and
  falls back to the mock), `realtime.mint()` returns the ephemeral secret +
  `wsUrl` + `subprotocols` + `sessionUpdate`. Wire it by replacing the one
  marked `null` in `src/tutor/provider_registry.ts`. Instructions are built
  server side (`src/tutor/realtime_instructions.ts`); never add client text.
- **Agent F** (`cloud/src/billing/**`): the three routes in
  `src/billing/index.ts`; write entitlements through
  `src/db/entitlements.ts setEntitlement()` and record every store event in
  `purchase_events` (`transaction_id UNIQUE` makes replays no-ops). The two
  webhooks are already exempt from the parent credential
  (`src/auth/middleware.ts isAuthExempt`) and must authenticate by signature.
  Keep `BILLING_ENABLED` honoured.
