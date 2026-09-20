# Aliz Tutor backend (Little Days)

Server side of **Aliz Tutor Mode**: sessions, server-side daily quota,
entitlements, parent approval, turn validation, LLM orchestration and cost
accounting. Node 22, plain ESM JavaScript with JSDoc types, **zero external
dependencies** (`node:http`, `node:crypto`, `node:fs`, `node:test`).

The game never talks to an LLM provider directly and never holds a provider
key. It talks to this service only when `TutorFlags.cloud_enabled()` is true,
which is false in every public build. See `docs/ALIZ_TUTOR_ARCHITECTURE.md`.

## Run

```sh
node backend/src/server.js                 # production shape: no dev routes
DEV_MODE=1 node backend/src/server.js      # local development (dev token + dev routes)
cd backend && npm test                     # node:test, no install step
```

Default bind: `http://127.0.0.1:8787`, which is also `TutorFlags.DEFAULT_BACKEND_URL`.

### Pointing the game at it

The game reads the project setting `little_days/ai_tutor/backend_url`
(`TutorFlags.backend_url()`, default `http://127.0.0.1:8787`). For a device on
the same Wi-Fi set it to your Mac's LAN address, start the server with
`HOST=0.0.0.0`, and run the game with `-- --ai-tutor-cloud` (developer runs
only; the exported setting `little_days/ai_tutor/cloud_enabled` stays false).

## Environment

There is no dotenv loader; the process reads `process.env`. Copy
`backend/.env.example` to `backend/.env` (gitignored) and `set -a; source
backend/.env; set +a` before starting, or export variables inline. **Nothing in
this directory contains a secret and no key may ever be committed.**

| Variable | Default | Meaning |
| --- | --- | --- |
| `PORT` / `HOST` | `8787` / `127.0.0.1` | Listen address. |
| `CORS_ORIGIN` | `*` | `Access-Control-Allow-Origin` for web exports. |
| `DATA_DIR` | `backend/data` | JSON persistence (sessions, usage, entitlements, idempotency keys, receipts, spend, turns). Gitignored. |
| `DEV_MODE` | off | `1` enables the dev parent token, `/api/v1/dev/*` routes and mock billing validation. Never in production. |
| `PARENT_APPROVAL_SECRET` | (none) | HMAC secret for signed parent-approval tokens. Required outside DEV_MODE (no session can be approved without it). |
| `DEV_PARENT_APPROVAL_TOKEN` | `dev-parent-approval` | Literal token accepted in DEV_MODE only. |
| `FREE_DAILY_SECONDS` | `300` | Free allowance per UTC day. |
| `FAMILY_CLUB_DAILY_SECONDS` | `1800` | Family Club allowance per UTC day. Capped at 86400; never unlimited. |
| `TUTOR_TURN_CAP_SECONDS` | `45` | Max seconds charged between two server events (start/turn/end). A hung client cannot burn hours. |
| `TUTOR_PROVIDER` | `mock` (`openai` if a key is set) | Conversation provider. |
| `OPENAI_API_KEY` | (none) | Enables the OpenAI adapter. Server only. Not present on this machine; tests use a fake fetch. |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | For proxies / gateways. |
| `TUTOR_MODEL` | `gpt-4o-mini` | Small model by default. Must exist in `config/prices.json` for cost estimates. |
| `OPENAI_EXTRA_HEADERS` | `{}` | JSON object of extra request headers (data-retention / project hooks). |
| `PROVIDER_TIMEOUT_MS` | `6000` | Provider call timeout; on expiry the deterministic mock answers instead. |
| `HANDLER_TIMEOUT_MS` | `10000` | Whole-request timeout -> `504 timeout`. |
| `MAX_BODY_BYTES` | `32768` | Request size limit -> `413`. |
| `MONTHLY_BUDGET_USD` | (none) | When the estimated spend for the UTC month reaches this, sessions and turns get `429 quota_exhausted` with `reason: "monthly_budget"`. |
| `STT_MODE` / `STT_MODEL` | `device` / `gpt-4o-mini-transcribe` | Cost model only: `device` costs reported audio seconds at 0. |
| `TTS_MODE` / `TTS_MODEL` | `device` / `tts-1` | Cost model only: `device` costs synthesized characters at 0. |
| `TURN_CACHE_TTL_SECONDS` | `86400` | Cache for identical `(lessonId, stepId, outcome, hasHint)` instructional turns from a real provider. `0` disables. |
| `RATE_LIMIT_IP_PER_MINUTE` | `120` | Per client IP (all API routes; `/healthz` exempt). |
| `RATE_LIMIT_SESSION_TURNS_PER_MINUTE` | `30` | Per session. |
| `TUTOR_ALLOWLIST_PATH` | `game/content/tutor/assets_allowlist.json` | Shared asset allowlist; the contract list is built in as fallback when the file is absent (`/healthz` reports `allowlistSource`). |

## Layout

```
backend/
  src/server.js            HTTP: JSON, CORS, body limit, timeout, cancellation
  src/app.js               routes -> domain modules; provider fallback; cache
  src/router.js            tiny {param} matcher
  src/store.js             in-memory + JSON files under DATA_DIR
  src/quota.js             UTC-day allowance, per-turn cap, resetAtUtc
  src/entitlement.js       free | family_club; dev grant; mock billing + validation stub
  src/parental_approval.js HMAC tokens bound to clientId; dev token in DEV_MODE
  src/rate_limit.js        fixed-window per IP / per session
  src/turn_validator.js    contract rules + safe fallback turn
  src/turn_cache.js        response cache for instructional turns
  src/usage.js             per-turn/session accounting, cost estimate, monthly budget
  src/providers/mock_provider.js    deterministic; full lesson offline
  src/providers/openai_provider.js  strict JSON schema, store:false, fake-fetch tested
  config/prices.json       OpenAI list prices with source URL + fetch date
  test/                    node:test suites + test/fixtures/turn_fixtures.json
  data/                    runtime files (gitignored)
```

## Identity and quota (honest limits)

Quota is keyed on `clientId`, and a session is only created when the request
carries a parent-approval token **bound to that clientId** (HMAC-signed with
`PARENT_APPROVAL_SECRET`; in DEV_MODE the literal dev token is also accepted).
A new session, a restart of the server, or a re-used token with a different
`clientId` never resets the day's usage. What this does *not* prevent: a
device without an account can be reinstalled, obtain a new `clientId`, and a
parent can pass the gate again for it. Cross-device identity needs accounts,
which are out of scope for the MVP.

Usage is measured from the server's own clock: session start -> each turn ->
end, each gap capped at `TUTOR_TURN_CAP_SECONDS`. The turn that lands on the
allowance is still served with `endAtBoundary: true`; the next one is
`429 quota_exhausted` with `resetAtUtc` (next UTC midnight).

## Happy path in DEV_MODE (real transcript, 2026-09-20)

Server started with `DEV_MODE=1 PORT=8787 DATA_DIR=<tmp> node src/server.js`.

```
$ curl -s localhost:8787/healthz
{"ok":true,"service":"little-days-tutor-backend","apiVersion":"v1","provider":"mock","devMode":true,"allowlistSource":"default","uptimeSeconds":1}

$ curl -s -X POST localhost:8787/api/v1/tutor/sessions -H "content-type: application/json" \
    -d '{"lessonId":"fruits_1","clientId":"ipad-demo","parentApprovalToken":"dev-parent-approval"}'
{"sessionId":"3d3b93a9-9b1c-4be1-af31-0ff0b3be532d","entitlement":"free","quota":{"entitlement":"free","dailyAllowanceSeconds":300,"usedSeconds":0,"remainingSeconds":300,"resetAtUtc":"2026-09-21T00:00:00.000Z"},"lessonId":"fruits_1"}

$ curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/turns -H "content-type: application/json" -H "Idempotency-Key: t1" \
    -d '{"transcript":"apple","lessonContext":{"stepId":"s1","outcome":"correct","expectedAnswers":["apple"],"nextQuestionText":"What color is the banana?","visualAssetId":"apple_red"}}'
{"turn":{"speech":"Well done! Apple! What color is the banana?","subtitle":"Well done! Apple! What color is the banana?","emotion":"happy","gesture":"clap","visual":{"type":"flashcard","assetId":"apple_red"},"lessonAction":"next_question","nextQuestion":"What color is the banana?"},"quota":{"entitlement":"free","dailyAllowanceSeconds":300,"usedSeconds":0,"remainingSeconds":300,"resetAtUtc":"2026-09-21T00:00:00.000Z"},"endAtBoundary":false,"turnIndex":1,"chargedSeconds":0,"provider":"mock","cached":false,"fallback":null,"usage":{"sttSeconds":0,"llmInputTokens":0,"llmOutputTokens":0,"ttsChars":43,"latencyMs":2,"costUsd":0}}

$ # same Idempotency-Key again -> replayed, not charged
$ curl -s -i -X POST ... -H "Idempotency-Key: t1" ... | grep -i idempotent
idempotent-replayed: true

$ curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/turns -H "content-type: application/json" \
    -d '{"transcript":"red","lessonContext":{"stepId":"s2","outcome":"incorrect","expectedAnswers":["yellow"],"hint":"It is the color of the sun.","visualAssetId":"banana_yellow"}}'
{"turn":{"speech":"Let's try together! It is the color of the sun.","subtitle":"Let's try together! It is the color of the sun.","emotion":"encouraging","gesture":"point","visual":{"type":"flashcard","assetId":"banana_yellow"},"lessonAction":"give_hint"},"quota":{"entitlement":"free","dailyAllowanceSeconds":300,"usedSeconds":0.1,"remainingSeconds":299.9,"resetAtUtc":"2026-09-21T00:00:00.000Z"},"endAtBoundary":false,"turnIndex":2,"chargedSeconds":0,"provider":"mock","cached":false,"fallback":null,"usage":{"sttSeconds":0,"llmInputTokens":0,"llmOutputTokens":0,"ttsChars":47,"latencyMs":1,"costUsd":0}}

$ curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/end
{"sessionId":"3d3b93a9-9b1c-4be1-af31-0ff0b3be532d","endedAt":"2026-09-20T15:19:21.676Z","quota":{"entitlement":"free","dailyAllowanceSeconds":300,"usedSeconds":0.1,"remainingSeconds":299.9,"resetAtUtc":"2026-09-21T00:00:00.000Z"},"usage":{"turns":2,"sttSeconds":0,"llmInputTokens":0,"llmOutputTokens":0,"cachedInputTokens":0,"ttsChars":90,"latencyMs":3,"cachedTurns":0,"costUsd":0}}

$ curl -s "localhost:8787/api/v1/tutor/entitlement?clientId=ipad-demo"
{"clientId":"ipad-demo","entitlement":"free","quota":{"entitlement":"free","dailyAllowanceSeconds":300,"usedSeconds":0.1,"remainingSeconds":299.9,"resetAtUtc":"2026-09-21T00:00:00.000Z"},"products":["little_days.family_club.monthly","little_days.family_club.yearly"]}

$ # without a parent-approval token
$ curl -s -X POST localhost:8787/api/v1/tutor/sessions -H "content-type: application/json" -d '{"lessonId":"fruits_1","clientId":"ipad-demo","parentApprovalToken":"nope"}'
{"error":{"code":"not_approved","message":"A parent needs to approve tutor time first."}}

$ curl -s -X POST localhost:8787/api/v1/dev/billing/mock-purchase -H "content-type: application/json" -d '{"clientId":"ipad-demo","productId":"little_days.family_club.monthly"}'
{"clientId":"ipad-demo","platform":"mock","receipt":{"receiptId":"78295ccf-5c27-466f-b0b8-8fb4abcc6690","clientId":"ipad-demo","productId":"little_days.family_club.monthly","purchasedAt":"2026-09-20T15:19:21.701Z","expiresAt":"2026-10-20T15:19:21.701Z","platform":"mock","signature":"a985189883f4128d6715a30e82f469e60ac40e87a3fa505665cb5ec58f31191b"},"next":"POST /api/v1/tutor/billing/validate with {clientId, platform, receipt}"}

$ # the client forwards the receipt; the SERVER validates it and grants family_club
$ curl -s -X POST localhost:8787/api/v1/tutor/billing/validate -H "content-type: application/json" -d '{"clientId":"ipad-demo","platform":"mock","receipt":<receipt from above>}'
{"clientId":"ipad-demo","entitlement":"family_club","expiresAt":"2026-10-20T15:19:21.701Z","receiptId":"78295ccf-5c27-466f-b0b8-8fb4abcc6690","quota":{"entitlement":"family_club","dailyAllowanceSeconds":1800,"usedSeconds":0.1,"remainingSeconds":1799.9,"resetAtUtc":"2026-09-21T00:00:00.000Z"}}
```

## Tests

`npm test` runs 60 tests (session lifecycle, quota exhaustion at exactly 300 s
across a restart, no-reset tricks, idempotent turns, rate limits, validator
truth table + fixtures, provider timeout/error/invalid -> fallback, client
cancellation, handler timeout, OpenAI request shape with a fake fetch, budget
guard, cost arithmetic, entitlement/billing, store persistence). The suite
also runs `game/content/tutor/turn_fixtures.json` when that shared file exists.

## Non-goals here

No accounts, no real store billing (stubs with TODOs), no TTS/STT proxying yet
(cost model has the hooks), single-process rate limiting and cache.
