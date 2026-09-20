# Aliz Tutor backend API (v1)

Base URL: `TutorFlags.backend_url()` (default `http://127.0.0.1:8787`).
All bodies are JSON with camelCase keys. All errors are
`{"error":{"code":"...","message":"...", ...}}`. Source: `backend/src/app.js`.
Run locally: `DEV_MODE=1 node backend/src/server.js` (see `backend/README.md`).

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/healthz` | Liveness + which provider/allowlist is active. Not rate limited. |
| `POST` | `/api/v1/tutor/sessions` | Start a lesson session (needs parent approval). |
| `POST` | `/api/v1/tutor/sessions/{id}/turns` | One conversational turn. Supports `Idempotency-Key`. |
| `POST` | `/api/v1/tutor/sessions/{id}/end` | End the session; returns usage totals. Idempotent. |
| `GET` | `/api/v1/tutor/entitlement?clientId=` | Current entitlement + quota for a client. |
| `POST` | `/api/v1/tutor/billing/validate` | Server-side receipt validation (mock in DEV_MODE; Google Play / Apple are `501` TODOs). |
| `POST` | `/api/v1/dev/entitlement` | DEV_MODE only: grant/revoke `free` / `family_club`. |
| `POST` | `/api/v1/dev/billing/mock-purchase` | DEV_MODE only: mint a fake receipt for `billing/validate`. |
| `POST` | `/api/v1/dev/parent-approval` | DEV_MODE only: mint a signed parent-approval token for a clientId. |
| `GET` | `/api/v1/dev/spend` | DEV_MODE only: month-to-date estimated spend, budget, cache stats. |

Outside DEV_MODE the `/api/v1/dev/*` routes do not exist (`404`).

Common headers: `content-type: application/json`; CORS preflight (`OPTIONS`)
answers `204` with `access-control-allow-headers: content-type, idempotency-key`.
Request bodies over 32 KB get `413`. Whole-request timeout is 10 s (`504 timeout`).

## Schemas

### Quota
```json
{"entitlement":"free","dailyAllowanceSeconds":300,"usedSeconds":120.5,"remainingSeconds":179.5,"resetAtUtc":"2026-09-21T00:00:00.000Z"}
```
`free` = 300 s per UTC day; `family_club` = `FAMILY_CLUB_DAILY_SECONDS` (default 1800). Never unlimited.

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
{"stepId":"s1","outcome":"correct","expectedAnswers":["apple"],"hint":"It is red.",
 "nextQuestionText":"What color is the banana?","visualAssetId":"apple_red",
 "matched":"apple","lessonAction":"next_question"}
```
`stepId` and `outcome` (`correct | incorrect | unclear`) are required. Unknown `visualAssetId`s are dropped, never echoed.

## `POST /api/v1/tutor/sessions`
Request:
```json
{"lessonId":"fruits_1","parentApprovalToken":"pa1.<payload>.<sig>","clientId":"ipad-demo"}
```
Response `201`:
```json
{"sessionId":"3d3b93a9-...","entitlement":"free","lessonId":"fruits_1","quota":{...}}
```
Errors: `403 not_approved` (missing/invalid/expired token or token bound to another clientId), `429 quota_exhausted`, `429 rate_limited`, `400 bad_request`.

`parentApprovalToken`: minted by the server for a clientId after the game's
parental gate (`POST /api/v1/dev/parent-approval` in DEV_MODE; a production
consent endpoint is a follow-up). In DEV_MODE the literal `dev-parent-approval`
is also accepted.

## `POST /api/v1/tutor/sessions/{id}/turns`
Headers: `Idempotency-Key: <client-generated unique string>` (recommended; retries with the same key replay the same response and are not charged; the same key with a different body gives `422 idempotency_mismatch`).

Request:
```json
{"transcript":"apple","audioSeconds":3.2,"lessonContext":{...}}
```
`transcript` <= 500 chars (may be empty for `unclear`). `audioSeconds` is optional, clamped to 30, used only for usage/cost reporting.

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
 "usage":{"sttSeconds":3.2,"llmInputTokens":0,"llmOutputTokens":0,"ttsChars":43,"latencyMs":2,"costUsd":0}}
```
- `endAtBoundary: true` means this turn used the last of today's allowance; the game finishes the current beat and shows the break screen (the next turn would be `429 quota_exhausted`).
- `fallback` is `null`, or a reason such as `provider_timeout`, `provider_error:503`, `invalid_turn:speech:url` when the real provider failed and the deterministic mock answered instead. The turn is always valid.
- `chargedSeconds` is the server-measured gap since the previous event, capped by `TUTOR_TURN_CAP_SECONDS`.

Errors: `400 invalid_turn` (bad `lessonContext`), `400 bad_request`, `404 not_found`, `409 session_ended`, `422 idempotency_mismatch`, `429 quota_exhausted`, `429 rate_limited`, `503 provider_unavailable`, `504 timeout`.

## `POST /api/v1/tutor/sessions/{id}/end`
Body optional: `{"reason":"home_button"}`. Response `200`:
```json
{"sessionId":"...","endedAt":"2026-09-20T15:19:21.676Z","quota":{...},
 "usage":{"turns":2,"sttSeconds":0,"llmInputTokens":0,"llmOutputTokens":0,"cachedInputTokens":0,"ttsChars":90,"latencyMs":3,"cachedTurns":0,"costUsd":0}}
```
Calling it twice is safe; the second call charges nothing.

## `GET /api/v1/tutor/entitlement?clientId=ipad-demo`
```json
{"clientId":"ipad-demo","entitlement":"free","quota":{...},"products":["little_days.family_club.monthly","little_days.family_club.yearly"]}
```

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
| 429 | `quota_exhausted` | Break screen: "Great job today! Come back tomorrow." Body carries `quota.resetAtUtc`; `reason` is `daily_quota` or `monthly_budget`. |
| 403 | `not_approved` | Return to the parental gate. |
| 503 | `provider_unavailable` | Fall back to the local scripted tutor. |
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
  -d '{"lessonId":"fruits_1","clientId":"ipad-demo","parentApprovalToken":"dev-parent-approval"}' \
  | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).sessionId')

curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/turns \
  -H 'content-type: application/json' -H 'Idempotency-Key: t1' \
  -d '{"transcript":"apple","lessonContext":{"stepId":"s1","outcome":"correct","expectedAnswers":["apple"],"nextQuestionText":"What color is the banana?","visualAssetId":"apple_red"}}'

curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/turns \
  -H 'content-type: application/json' \
  -d '{"transcript":"red","lessonContext":{"stepId":"s2","outcome":"incorrect","expectedAnswers":["yellow"],"hint":"It is the color of the sun.","visualAssetId":"banana_yellow"}}'

curl -s -X POST localhost:8787/api/v1/tutor/sessions/$SID/end

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
