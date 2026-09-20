# Aliz Tutor Mode: architecture (client, backend, provider)

Status: backend implemented in `backend/` (Node 22, zero dependencies), tested,
not deployed. The cloud path is dark in every public build
(`little_days/ai_tutor/cloud_enabled = false`).

## Diagram

```
 iPad / phone (Godot)                    |  Backend (backend/src, Node 22)          |  Provider
 ---------------------------------------  |  ---------------------------------------- |  ------------------
 LessonEngine (deterministic, local)      |                                          |
   |  step, outcome, hint, next question  |                                          |
   v                                      |                                          |
 ConversationProvider                     |                                          |
   Scripted (always) ----> TutorTurn      |                                          |
   Backend  (flag-gated)                  |                                          |
     | POST /sessions {lessonId,          |  parental_approval.verify(token,clientId)|
     |   clientId, parentApprovalToken}   |  entitlement.get(clientId)               |
     |                                    |  quota.state(clientId)  -> 201/403/429   |
     | POST /sessions/{id}/turns          |  rate_limit(ip, session)                 |
     |   {transcript, lessonContext}      |  idempotency(sessionId+key)              |
     |   Idempotency-Key                  |  quota.charge(gap, capped)               |
     |                                    |  turn_cache(lessonId,stepId,outcome)     |
     |                                    |  provider.generateTurn -----------------> OpenAI chat.completions
     |                                    |     6 s timeout / AbortController        |   (strict JSON schema,
     |                                    |     on failure: mock_provider            |    store:false, key on
     |                                    |  turn_validator -> valid TutorTurn       |    server only)
     |                                    |  usage.recordTurn + cost + budget guard  |
     | <-- {turn, quota, endAtBoundary}   |  store (JSON files in DATA_DIR)          |
     | POST /sessions/{id}/end            |                                          |
 TutorTurn validator (client, same rules) |                                          |
 SpeechSynthesis -> TutorFace (lip sync)  |                                          |
 SpeechRecognition (on device)            |                                          |
```

Speech recognition and synthesis run on the device today. The backend carries
`audioSeconds` and `ttsChars` in usage so the cost model already covers a
future cloud STT/TTS hop, but no audio is ever uploaded.

## Trust boundaries

1. **Child <-> game.** The game owns the parental gate. Nothing the child does
   can reach the network while `cloud_enabled()` is false; the scripted tutor
   gives a complete 5-minute lesson offline.
2. **Game <-> backend.** The game is an untrusted client. It may claim nothing:
   - It cannot set its entitlement. It forwards a store receipt and the server
     validates it (`POST /billing/validate`; mock platform only in DEV_MODE).
   - It cannot set its quota. Usage is measured from server timestamps
     (start/turn/end), each gap capped at `TUTOR_TURN_CAP_SECONDS` so a hung
     client cannot burn hours; the UTC-day window and `resetAtUtc` come from
     the server.
   - It cannot start a session without a parent-approval token bound to its
     `clientId` (HMAC with `PARENT_APPROVAL_SECRET`, expiry, constant-time
     compare). Dev literal token only in DEV_MODE. The session is bound to that
     exact token (salted HMAC stored on the session); `/turns` and `/end`
     re-verify it on every call, so a leaked session id is useless and an
     expired approval stops a live session.
   - It cannot put words in Aliz's mouth: the server loads the lesson files
     and resolves `stepId` itself; the client's hint/question/answers are
     ignored for known lessons and unknown lessons are refused outside
     DEV_MODE. The transcript is the only free text from the device.
   - Provider calls are capped per client per day (60 free / 360 Family Club)
     independently of the seconds quota, and a server-wide monthly budget
     (default USD 25) is always on.
   - Every turn is validated on the server before it leaves, and again on the
     client with the same rules and the same fixture file.
   - Input is bounded: 32 KB bodies, 500-char transcripts, allowlisted asset
     ids, id regexes, rate limits per IP and per session.
3. **Backend <-> provider.** Only the backend holds `OPENAI_API_KEY`. The
   prompt contains the lesson context and this turn's transcript; no name,
   age, clientId, sessionId, device or location. `store: false` is sent;
   `OPENAI_EXTRA_HEADERS` is the hook for any headers a data-processing
   agreement (e.g. Zero Data Retention scoping) requires. A strict JSON schema
   constrains the shape; the validator constrains the content.

## Where secrets live

| Secret | Location | Never |
| --- | --- | --- |
| `OPENAI_API_KEY` | server environment only | in the game, in git, in logs |
| `PARENT_APPROVAL_SECRET` | server environment only | in the game |
| Store credentials (Play service account, App Store key) | server environment when wired | in the game |

`backend/.env.example` lists names only. `backend/data/` and `backend/.env`
are gitignored. This machine has no `OPENAI_API_KEY`; tests exercise the
OpenAI adapter with an injected fake `fetch`.

## What the flag gates

`TutorFlags.cloud_enabled()` gates the `BackendConversationProvider`, any
backend TTS bytes, and any transcript leaving the device. When it is false the
`ScriptedConversationProvider` builds turns from `LessonEngine` output only.
When true, the backend is still the authority for quota and entitlement, and
the scripted provider remains the fallback for `provider_unavailable`,
`timeout`, and network errors.

## Privacy controls in the backend

- Access logs: method, route pattern (`/api/v1/tutor/sessions/{id}/turns`),
  status, latency. Never the URL, query string, ids, headers or bodies.
- Idempotency rows: salted HMAC (per-server random salt in `DATA_DIR/meta.json`)
  of key and body, 24 h TTL. Transcripts are never persisted anywhere.
- Retention: sessions, per-turn usage rows and quota-day rows older than
  `RETENTION_DAYS` (30) are purged on start and hourly;
  `DELETE /api/v1/tutor/clients/{clientId}` (parent token) implements
  "Delete learning history" server-side. Entitlement/receipts are kept as the
  purchase record.
- No end-user identifier (`user` / `safety_identifier`) is sent to the
  provider: a hashed clientId would still be a persistent identifier of a
  child's device disclosed to a third party. Abuse tracing stays server-side
  (per-client caps, per-session rate limits).
- `X-Forwarded-For` is honoured only with `TRUST_PROXY=1` (last hop); CORS
  headers only for `CORS_ORIGINS`; `/healthz` is `{ok, apiVersion}` outside
  DEV_MODE.

## Realtime option (server side only, not used by the client)

`POST /api/v1/tutor/realtime/token` mints an OpenAI ephemeral client secret
bound to a quota session; its expiry is `remaining quota + 30 s`, so the token
itself ends the conversation. Audio would then flow device <-> OpenAI directly
(the backend never sees it); `POST /sessions/{id}/usage` collects provider
usage events for cost only, while seconds are charged from the server clock
bounded by the token expiry. See `docs/ALIZ_TUTOR_REALTIME_EVALUATION.md` for
why this is not the V1 path.

## Persistence

`backend/src/store.js`: one JSON file per collection under `DATA_DIR`
(`sessions`, `usage`, `entitlements`, `idempotency`, `receipts`, `spend`,
`turns`). Writes are atomic (`tmp` + `rename`). A corrupt file is quarantined
as `*.corrupt-<ts>` and that collection restarts empty (safe defaults). Quota,
sessions and the month's spend therefore survive a process restart, which the
test suite proves by restarting the app on the same directory mid-lesson.

## Failure modes and what the child sees

| Failure | Server behaviour | Child sees |
| --- | --- | --- |
| Provider slow (> `PROVIDER_TIMEOUT_MS`, 6 s) | Abort provider, answer with the deterministic mock turn; `fallback: "provider_timeout"` | A normal, slightly generic Aliz line; lesson continues |
| Provider HTTP error / refusal / bad JSON | Same fallback (`provider_error:<status>`) | Same |
| Provider returns unsafe or malformed content | Validator rejects; mock answers (`invalid_turn:<reason>`) | Same; unsafe text never reaches the device |
| Whole request > 10 s | `504 timeout`, in-flight provider call aborted | Game falls back to the scripted turn |
| Client disconnects mid-turn | Provider call aborted via AbortController; quota is charged only after a turn is served, so nothing is charged or recorded | Nothing |
| Daily allowance reached | Last turn served with `endAtBoundary: true`; next is `429 quota_exhausted` + `resetAtUtc` | Break screen: "Great job today! Come back tomorrow." |
| Monthly budget reached | `429 quota_exhausted`, `reason: monthly_budget` for everyone | Same break screen |
| No parent approval | `403 not_approved` | Parental gate |
| Too many requests | `429 rate_limited` + `Retry-After` | Brief wait |
| Server down / unreachable | n/a | Scripted tutor (flag path already handles `provider_failed`) |
| Server restarted with another `DATA_DIR` | `404 not_found` for old sessions | Game starts a new session |

## Identity (honest limits)

Quota identity = `clientId` + parent-approval token bound to that `clientId`.
Not a reset vector: new sessions, server restarts, replayed tokens under a new
`clientId`. Reset vector we accept for the MVP: reinstalling the app yields a
new `clientId` and a parent can pass the gate again. Accounts would close it and
are out of scope.

## Out of scope for this pass

Accounts, real store billing (stubbed with TODOs), cloud STT/TTS proxying,
multi-instance rate limiting/cache (in-memory per process), TLS termination
(put a reverse proxy in front), log shipping (logs carry method/path/status/ms
only, never transcripts).
