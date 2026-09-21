# Aliz Tutor backend API (v1)

Two implementations share this contract:

- **Cloudflare Worker** (`cloud/`, the product shape, NOT DEPLOYED yet) — section 1.
- **Node prototype** (`backend/`, the reference implementation) — section 2, kept verbatim.

The prototype's routes, bodies, quota block, TutorTurn rules and error codes
are the base; the Worker serves all of them under both `/v1` and `/api/v1`
(the shipped Godot clients use the latter) and adds the account layer below.

---

# 1. Worker contract (`cloud/`)

Source: `cloud/src/routes/*.ts`, `cloud/src/do/*.ts`. Design: `docs/CLOUD_BACKEND.md`.
Run locally: `cd cloud && npm run dev` (see `cloud/README.md`).

## 1.1 Credentials

| Header | Token | Who | Where accepted |
| --- | --- | --- | --- |
| `Authorization: Bearer pt1.<...>` | parent sign-in (30 d) | Parent Corner | every account route; `PUT /consent`, `POST /parents/approval` and `POST /tutor/sessions/:id/stop` require it |
| `X-Parent-Approval: pa1.<...>` or body `parentApprovalToken` | parental approval bound to `clientId` (+ optional `childId`) | the game | every route; REQUIRED on tutor routes, re-verified on each session call (same token that created the session) |
| literal `dev-parent-approval` | DEV_MODE only | dev runs | as above, maps to the synthetic parent `dev-parent` |

`pa1` keeps the prototype's format (`pa1.<base64url JSON>.<hex HMAC-SHA256>`,
claims `sub` = clientId, `iat`, `exp`) plus `pid` (parent) and optional `cid`
(child). Missing/invalid/expired/mis-bound credential: `403 not_approved`.

## 1.2 Routes (prefix `/v1` or `/api/v1`)

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/healthz`, `/v1/health` | no credential |
| POST | `/v1/parents` | no credential. `{provider:"dev", subject, clientId?}` (DEV_MODE) -> `201 {parentId, created, parentToken, expiresAt, parentApprovalToken?}`; `apple`/`google` -> `501 not_implemented` until identity tokens are verified |
| GET | `/v1/parents/me` | `{parentId, provider, consentVersion, createdAt, via}` |
| POST | `/v1/parents/approval` | bearer. `{clientId, childId?, ttlSeconds?}` -> `201 {parentApprovalToken, expiresAt}` (server half of the parental gate) |
| GET / POST | `/v1/children` | `{nickname (<=24, no contact details), avatarId?, birthYearBucket? ("2020-2021"), locale?}` -> `201 {childId, ...}`; max 6 |
| GET / POST | `/v1/devices` | `{clientId, platform: ios|android|macos|unknown, appVersion?}` -> `201`; `409 conflict` when the device belongs to another family |
| GET / PUT | `/v1/consent` | PUT (bearer) `{kind: privacy|ai_tutor|voice, version?, granted}`; GET -> `{requiredVersion, consent:{kind:{version, grantedAt, revokedAt, granted}}}` |
| GET | `/v1/entitlements` | `{entitlement, activeUntil, source, allowances, products:[{productId, priceHint:{currency, monthly, status}}], billing:{enabled}, records}` — price hint is config |
| GET | `/v1/tutor/quota`, `/v1/tutor/entitlement?clientId=` | `{clientId, childId, entitlement, quota, products, priceHint}` (prototype alias shape kept) |
| POST | `/v1/tutor/sessions` | as prototype + optional `childId`; response adds `childId`. Needs consent `ai_tutor` (`403 consent_required {kind}`) |
| POST | `/v1/tutor/sessions/:id/turns` | as prototype (idempotent, `X-Parent-Approval` = creating token) |
| POST | `/v1/tutor/sessions/:id/end` | as prototype; `usage` = `{turns, llmInputTokens, llmOutputTokens, audioSeconds, costUsd}` |
| POST | `/v1/tutor/sessions/:id/usage` | realtime usage reports, as prototype |
| POST | `/v1/tutor/sessions/:id/stop` | bearer; Parent Corner stop -> `{sessionId, ended}` |
| POST | `/v1/tutor/realtime/token` | `503 provider_unavailable` unless `OPENAI_API_KEY` + provider module (Agent E) + consent `voice`; otherwise `201` with BOTH shapes: `{sessionId, quotaSessionId, clientSecret:{value, expiresAt(unix s)}, token:{value, expiresAt(ISO)}, expiresInSeconds, wsUrl, subprotocols, headers, sessionUpdate, realtime:{model, turnDetection, mock:false}, quota, lessonKnown}` (what `cloud_realtime_transport.gd` reads + the prototype fields) |
| DELETE | `/v1/tutor/clients/:clientId` | `{clientId, deleted:{sessions, usageEvents, idempotency}}` |
| GET / PUT | `/v1/progress` | PUT `{childId?, lessonId, stepIndex, stars, completed?}` (monotonic upsert); GET `?childId=` -> `{childId, progress:[...]}` |
| POST | `/v1/billing/apple/notifications`, `/v1/billing/google/rtdn`, `/v1/billing/verify` | Agent F; `501` stubs. Webhooks need no parent token |
| POST / GET | `/v1/dev/entitlements`, `/v1/dev/parent-approval`, `/v1/dev/retention/purge`, `/v1/dev/spend` | DEV_MODE only |

Header `X-Debug-Now: <unix ms>` sets the server clock in DEV_MODE only (tests).

## 1.3 Differences from the prototype the client may notice

- `childId` appears in session and quota replies. The Godot client may ignore
  it; a session without `childId` uses the family's first (auto-created,
  nickname-only) profile.
- New error code `consent_required` (403): treat like `not_approved` (back to
  the parent gate) — `backend_response.gd` already maps unknown 403s that way.
- New error code `conflict` (409) on device registration.
- Realtime never returns a mock token; without a provider it is `503`.
- Quota is per child, not per `clientId`: two devices approved for the same
  child share one daily allowance.

---

# 2. Prototype (`backend/`) reference

Base URL: `TutorFlags.backend_url()` (default `http://127.0.0.1:8787`).
All bodies are JSON with camelCase keys. All errors are
`{"error":{"code":"...","message":"...", ...}}`. Source: `backend/src/app.js`.
Run locally: `DEV_MODE=1 node backend/src/server.js` (see `backend/README.md`).

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/healthz` | Liveness + which provider/allowlist is active. Not rate limited. |
| `POST` | `/api/v1/tutor/sessions` | Start a lesson session (needs parent approval). |
| `POST` | `/api/v1/tutor/sessions/{id}/turns` | One conversational turn. Needs the session's parent token. Supports `Idempotency-Key`. |
| `POST` | `/api/v1/tutor/sessions/{id}/end` | End the session; returns usage totals. Needs the session's parent token. Idempotent. |
| `GET` | `/api/v1/tutor/entitlement?clientId=` | Current entitlement + quota for a client. |
| `POST` | `/api/v1/tutor/realtime/token` | Mint an ephemeral OpenAI Realtime client secret bound to a quota session (needs parent token + open quota). Mock token in DEV_MODE without a key; `503` without a key otherwise. |
| `POST` | `/api/v1/tutor/sessions/{id}/usage` | Realtime only: report provider usage events (tokens, audio seconds) for cost accounting. Not a quota authority. |
| `DELETE` | `/api/v1/tutor/clients/{clientId}` | "Delete learning history": removes that client's sessions, per-turn usage, quota-day rows and idempotency rows. Needs a valid parent token for that clientId. |
| `POST` | `/api/v1/tutor/billing/validate` | Server-side receipt validation (mock in DEV_MODE; Google Play / Apple are `501` TODOs). |
| `POST` | `/api/v1/dev/entitlement` | DEV_MODE only: grant/revoke `free` / `family_club`. |
| `POST` | `/api/v1/dev/billing/mock-purchase` | DEV_MODE only: mint a fake receipt for `billing/validate`. |
| `POST` | `/api/v1/dev/parent-approval` | DEV_MODE only: mint a signed parent-approval token for a clientId. |
| `GET` | `/api/v1/dev/spend` | DEV_MODE only: month-to-date estimated spend, budget, cache stats, loaded lesson ids. |
| `POST` | `/api/v1/dev/retention/purge` | DEV_MODE only: run the retention purge now; returns counts. |

Outside DEV_MODE the `/api/v1/dev/*` routes do not exist (`404`).

Common headers: `content-type: application/json`; `X-Parent-Approval: <token>`
on every session-scoped route (`/turns`, `/end`, `DELETE /clients/{clientId}`);
the token may alternatively be sent as `parentApprovalToken` in the body.
CORS headers are emitted only for origins listed in `CORS_ORIGINS` (default:
none; the Godot client needs none). Request bodies over 32 KB get `413`.
Whole-request timeout is 10 s (`504 timeout`). Access logs record method,
route pattern, status and latency only (never URLs, ids, headers or bodies).

### Session ownership
A session is bound to the exact parent-approval token that created it. Calls
to `/turns` and `/end` must present that same token (header or body); it must
still verify (unexpired, bound to the session's clientId). Anything else is
`403 not_approved`, so a leaked session id alone cannot be used.

## Schemas

### Quota
```json
{"entitlement":"free","dailyAllowanceSeconds":300,"usedSeconds":120.5,"remainingSeconds":179.5,"resetAtUtc":"2026-09-21T00:00:00.000Z",
 "dailyTurnAllowance":60,"usedTurns":7}
```
`free` = 300 s and 60 turns per UTC day; `family_club` = `FAMILY_CLUB_DAILY_SECONDS` (default 1800) and `FAMILY_CLUB_DAILY_TURNS` (default 360). Seconds are measured from server timestamps (each gap capped at 45 s) and charged after a turn is served; turns are counted per provider call. Never unlimited. A server-wide monthly budget (`MONTHLY_BUDGET_USD`, default 25, always on) sits above both.

### TutorTurn (validated server side; identical rules on the client)
```json
{"speech":"Great! Apple! What color is the banana?",
 "subtitle":"Great! Apple! What color is the banana?",
 "emotion":"happy","gesture":"clap",
 "visual":{"type":"flashcard","assetId":"apple_red"},
 "lessonAction":"next_question","nextQuestion":"What color is the banana?"}
```
- `emotion` in `neutral | listening | thinking | happy | encouraging | smile`
- `gesture` in `none | nod | tilt | point | clap | wave`
- `visual.type` in `none | flashcard | model`; `assetId` must be in `game/content/tutor/assets_allowlist.json` (required unless type is `none`)
- `lessonAction` in `next_question | retry | give_hint | complete | end_session`
- `speech` <= 160 chars, `subtitle` <= 160 (defaults to `speech`), `nextQuestion` <= 120; ASCII printable only; no URLs, no digit runs over 20, no banned words.
- Anything invalid becomes the safe fallback turn
  `{"speech":"Let's try together!","emotion":"encouraging","gesture":"tilt","visual":{"type":"none"},"lessonAction":"retry"}`.

### LessonContext (sent by the game from its LessonEngine)
```json
{"stepId":"s02_red","outcome":"correct","matched":"red","lessonAction":"next_question"}
```
`stepId` and `outcome` (`correct | incorrect | unclear`) are required. **The
server is the authority for lesson text**: it loads the same lesson files the
game ships (`LESSONS_DIR`, default `game/content/tutor/lessons/`) and resolves
`stepId` itself to obtain `expectedAnswers`, `hint`, the next question, the
visual asset and the lesson lines. From the client it honours only `stepId`,
`outcome`, `matched` (kept only if it is one of the step's expected answers)
and `lessonAction` (plausibility-checked against the outcome and step). Any
`hint` / `nextQuestionText` / `expectedAnswers` / `visualAssetId` the client
sends are ignored for known lessons. An unknown `stepId` is `400 invalid_turn`.
Unknown `lessonId`s are `400 unknown_lesson` at session creation, except in
DEV_MODE where the client-supplied fields are used as a fallback (the response
then says `contextSource: "client_dev"`).

## `POST /api/v1/tutor/sessions`
Request:
```json
{"lessonId":"fruits_1","parentApprovalToken":"pa1.<payload>.<sig>","clientId":"ipad-demo"}
```
Response `201`:
```json
{"sessionId":"3d3b93a9-...","entitlement":"free","lessonId":"fruits_1","quota":{...}}
```
Response also carries `lessonKnown` (false only in DEV_MODE for an unknown lesson).
Errors: `403 not_approved` (missing/invalid/expired token or token bound to another clientId), `400 unknown_lesson`, `429 quota_exhausted` (`reason` `daily_quota`, `daily_turns` or `monthly_budget`), `429 rate_limited`, `400 bad_request`.

`parentApprovalToken`: minted by the server for a clientId after the game's
parental gate (`POST /api/v1/dev/parent-approval` in DEV_MODE; a production
consent endpoint is a follow-up). In DEV_MODE the literal `dev-parent-approval`
is also accepted.

## `POST /api/v1/tutor/sessions/{id}/turns`
Headers: `X-Parent-Approval: <the token that created the session>` (required);
`Idempotency-Key: <client-generated unique string>` (recommended; retries with
the same key within 24 h replay the same response and are not charged; the
same key with a different body gives `422 idempotency_mismatch`; the server
stores only a salted HMAC of the key and body, never the transcript).

Request:
```json
{"transcript":"red","audioSeconds":3.2,"lessonContext":{"stepId":"s02_red","outcome":"correct","matched":"red"}}
```
`transcript` <= 500 chars (may be empty for `unclear`). `audioSeconds` is optional, clamped to 30, recorded as `clientReportedAudioSeconds` for information only; it is never costed (no server-side STT runs today).

Response `200`:
```json
{"turn":{...TutorTurn...},
 "quota":{...},
 "endAtBoundary":false,
 "turnIndex":1,
 "chargedSeconds":12,
 "provider":"mock",
 "cached":false,
 "fallback":null,
 "contextSource":"server",
 "usage":{"sttSeconds":0,"llmInputTokens":0,"llmOutputTokens":0,"ttsChars":43,"latencyMs":2,"costUsd":0}}
```
- `endAtBoundary: true` means this turn used the last of today's seconds or turns (or the lesson asked to `end_session`); the game finishes the current beat and shows the break screen (the next turn would be `429 quota_exhausted`).
- `fallback` is `null`, or a reason such as `provider_timeout`, `provider_error:503`, `invalid_turn:speech:url` when the real provider failed and the deterministic mock answered instead. The turn is always valid.
- `chargedSeconds` is the server-measured gap since the previous event, capped by `TUTOR_TURN_CAP_SECONDS`.

Errors: `403 not_approved` (wrong/missing/expired token for this session), `400 invalid_turn` (bad `lessonContext` or unknown `stepId`), `400 bad_request`, `404 not_found`, `409 session_ended`, `422 idempotency_mismatch`, `429 quota_exhausted`, `429 rate_limited`, `503 provider_unavailable`, `504 timeout`.

## `POST /api/v1/tutor/sessions/{id}/end`
Header `X-Parent-Approval` required (the session's token). Body optional: `{"reason":"home_button"}`. Response `200`:
```json
{"sessionId":"...","endedAt":"2026-09-20T15:19:21.676Z","quota":{...},
 "usage":{"turns":2,"sttSeconds":0,"llmInputTokens":0,"llmOutputTokens":0,"cachedInputTokens":0,"ttsChars":90,"latencyMs":3,"cachedTurns":0,"costUsd":0}}
```
Calling it twice is safe; the second call charges nothing.

## `GET /api/v1/tutor/entitlement?clientId=ipad-demo`
```json
{"clientId":"ipad-demo","entitlement":"free","quota":{...},"products":["little_days.family_club.monthly","little_days.family_club.yearly"]}
```

## `POST /api/v1/tutor/realtime/token`
Header `X-Parent-Approval` (or body `parentApprovalToken`). Body either
`{"lessonId":"colors_red_blue","clientId":"ipad-demo"}` (creates and binds a new
quota session, same checks as `POST /sessions`) or `{"sessionId":"..."}` (links
an existing open session you own). Response `201`:
```json
{"sessionId":"...",
 "token":{"value":"ek_...","expiresAt":"2026-09-20T10:05:30.000Z"},
 "realtime":{"model":"gpt-realtime-mini","turnDetection":"semantic_vad","mock":false,"transport":"websocket_or_webrtc","note":"..."},
 "quota":{...,"usedTurns":1},
 "lessonKnown":true}
```
- The server calls OpenAI `POST /v1/realtime/client_secrets` (reference fetched
  2026-09-20: https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets/methods/create)
  with `expires_after: {anchor:"created_at", seconds}` where
  `seconds = min(remainingSeconds + 30, 7200)` (API range 10-7200, default 600),
  and a `session` of `type: "realtime"`, `model` (`REALTIME_MODEL`, default
  `gpt-realtime-mini`), server-built `instructions` from the lesson file,
  `output_modalities: ["audio"]`, `max_output_tokens: 400`, `tool_choice: "none"`,
  `audio.input.noise_reduction {type:"near_field"}`,
  `audio.input.transcription {model, language:"en"}`,
  `audio.input.turn_detection` = `{type:"semantic_vad", eagerness:"low", create_response:true, interrupt_response:true}`
  or, with `REALTIME_TURN_DETECTION=server_vad`,
  `{type:"server_vad", threshold:0.6, prefix_padding_ms:300, silence_duration_ms:700, create_response:true, interrupt_response:true}`,
  and `audio.output {voice, speed:0.9}`. The response's `value` (`ek_...`) and
  `expires_at` are returned; **the permanent key never leaves the server**.
- The token's expiry is the hard bound on the conversation: it is at most the
  remaining daily allowance plus 30 s of grace, so even a client that never
  reports usage cannot exceed the quota by more than the grace.
- A mint counts as one turn toward the daily turn cap.
- DEV_MODE without `OPENAI_API_KEY`: `{"token":{"value":"dev-realtime-token",...},"realtime":{"mock":true}}`.
- Without a key outside DEV_MODE: `503 provider_unavailable`. Provider failure: `503`.
- Other errors as for `POST /sessions` (`403 not_approved`, `400 unknown_lesson`, `429 quota_exhausted`, `409 session_ended`).

Connecting from the game (not implemented client-side; see
`docs/ALIZ_TUTOR_REALTIME_EVALUATION.md`): `wss://api.openai.com/v1/realtime?model=<model>`
with the ephemeral value as `Authorization: Bearer ek_...` (or the subprotocols
`realtime`, `openai-insecure-api-key.<ek_...>`), PCM16 24 kHz base64 audio via
`input_audio_buffer.append`.

## `POST /api/v1/tutor/sessions/{id}/usage`
Realtime sessions only. Header `X-Parent-Approval` (the session's token). Body is
a summary of the provider's server events (e.g. each `response.done` ->
`response.usage`) relayed by the client:
```json
{"responses":3,"inputAudioTokens":600,"cachedInputAudioTokens":0,"outputAudioTokens":1200,
 "inputTextTokens":900,"cachedInputTextTokens":800,"outputTextTokens":120,
 "inputAudioSeconds":20,"outputAudioSeconds":30}
```
Response `200`:
```json
{"sessionId":"...","recorded":{"turnIndex":1,"costUsd":0.03,"priceMissing":[]},"quota":{...},"endAtBoundary":false,"tokenExpiresAt":"..."}
```
- Feeds **cost accounting only** (`config/prices.json` realtime prices). It is
  never the quota authority: seconds are charged from the server clock between
  server events, bounded by the token expiry (not by the 45 s per-turn cap,
  because a realtime session may have no turns), and each report counts as one
  turn toward the daily turn cap. A body containing `usedSeconds`,
  `remainingSeconds` or `quota` is rejected with `400 bad_request`.
- Numbers are clamped (tokens <= 5,000,000, seconds <= 7200). `400 bad_request`
  for a non-realtime session, `409 session_ended`, `429 quota_exhausted`
  (`daily_turns`) when the cap is reached.

## `DELETE /api/v1/tutor/clients/{clientId}`
Header `X-Parent-Approval` with a valid token for that `clientId`. Response `200`:
```json
{"clientId":"ipad-demo","deleted":{"sessions":3,"turns":27,"usage":1,"idempotency":27}}
```
Entitlement and receipts (the purchase record) are kept. Independently of this,
the server purges sessions, per-turn rows and quota-day rows older than
`RETENTION_DAYS` (default 30) on start and hourly, and idempotency rows after 24 h.

## `POST /api/v1/tutor/billing/validate`
```json
{"clientId":"ipad-demo","platform":"mock|google_play|apple","receipt":{...}}
```
`200 {"clientId","entitlement":"family_club","expiresAt","receiptId","quota"}`.
The client never declares an entitlement; it forwards the store receipt and the
server decides. `mock` works only in DEV_MODE; `google_play` and `apple` return
`501 not_implemented` until wired (TODOs in `backend/src/entitlement.js`).

## Error codes (what the game should map)

| HTTP | code | Game behaviour |
| --- | --- | --- |
| 429 | `quota_exhausted` | Break screen: "Great job today! Come back tomorrow." Body carries `quota.resetAtUtc`; `reason` is `daily_quota`, `daily_turns` or `monthly_budget`. |
| 403 | `not_approved` | Return to the parental gate (also returned when a session is used with a token other than the one that created it). |
| 400 | `unknown_lesson` | The server does not ship this lesson: use the scripted tutor. |
| 503 | `provider_unavailable` | Fall back to the local scripted tutor (also: realtime not configured on this server). |
| 429 | `rate_limited` | Wait `retryAfterSeconds` (also `Retry-After` header), keep listening state. |
| 400 | `invalid_turn` | Client bug: the lessonContext was malformed. Use the scripted turn. |
| 409 | `session_ended` | Start a new session. |
| 422 | `idempotency_mismatch` | Client bug: new key per distinct turn. |
| 404 | `not_found` | Session unknown (server restarted with a different DATA_DIR): start a new session. |
| 504 | `timeout` | Treat like `provider_unavailable`. |
| 413 / 400 | `payload_too_large` / `bad_request` | Client bug. |

## curl walkthrough (DEV_MODE)

```sh
DEV_MODE=1 node backend/src/server.js &

curl -s localhost:8787/healthz

SID=$(curl -s -X POST localhost:8787/api/v1/tutor/sessions -H 'content-type: application/json' \
  -d '{"lessonId":"colors_red_blue","clientId":"ipad-demo","parentApprovalToken":"dev-parent-approval"}' \
  | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).sessionId')

# every session-scoped call carries the same parent token
T='X-Parent-Approval: dev-parent-approval'

curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/turns \
  -H 'content-type: application/json' -H "$T" -H 'Idempotency-Key: t1' \
  -d '{"transcript":"red","lessonContext":{"stepId":"s02_red","outcome":"correct","matched":"red"}}'

curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/turns \
  -H 'content-type: application/json' -H "$T" \
  -d '{"transcript":"green","lessonContext":{"stepId":"s03_blue","outcome":"incorrect"}}'

curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/end -H "$T"

# parent deletes this device's learning history
curl -s -X DELETE localhost:8787/api/v1/tutor/clients/ipad-demo -H "$T"

curl -s 'localhost:8787/api/v1/tutor/entitlement?clientId=ipad-demo'

# Family Club via mock billing: mint a receipt, then let the server validate it
R=$(curl -s -X POST localhost:8787/api/v1/dev/billing/mock-purchase -H 'content-type: application/json' \
  -d '{"clientId":"ipad-demo","productId":"little_days.family_club.monthly"}')
node -e 'const r=JSON.parse(process.argv[1]);process.stdout.write(JSON.stringify({clientId:"ipad-demo",platform:"mock",receipt:r.receipt}))' "$R" \
  | curl -s -X POST localhost:8787/api/v1/tutor/billing/validate -H 'content-type: application/json' -d @-

# Signed parent token (what production will use instead of the dev literal)
curl -s -X POST localhost:8787/api/v1/dev/parent-approval -H 'content-type: application/json' -d '{"clientId":"ipad-demo"}'
```
The full recorded output of this walkthrough is in `backend/README.md`.
