# Aliz Tutor — free conversation (development-safe path)

Owner: Agent T2, branch `wt8/chat`, 2026-09-22. Status: **development / QA
only.** Nothing in this document changes what a public build can do: the cloud
flag stays `false` in `project.godot`, the Worker refuses chat outside
`DEV_MODE`, and no OpenAI key exists on the dev Worker or on any developer
machine. Read `docs/ALIZ_TUTOR_PRIVACY_REVIEW.md` first; this path is behind
every gate that document closes.

## 1. What it is

A child can ask Aliz simple questions ("what do cats eat?", "and dogs?") and
get a short, child-appropriate spoken answer with follow-up context, next to
the scripted lesson. The lesson and the chat are two **modes** of the same
classroom; the chat never forks the presentation: every reply reaches the
scene through the same `turn_ready` the lesson provider uses.

```
child speaks -> on-device STT -> tutor_scene._request_turn(transcript)
                                       |  (one-line hook, §5)
                                       v
                          FreeChatController.intercept_turn()
                                       |  CloudTutorApi.submit_chat_turn()
                                       v
   Cloudflare dev Worker  POST /v1/tutor/sessions/:id/turns  (mode "chat" session)
     child-text safety regex -> [OpenAI Chat Completions, structured output]
     -> chat gate (shared validator -> safety regex -> word cap) -> TutorTurn
                                       |
                                       v
             bound provider .turn_ready  ->  tutor_scene._speak_turn()  (face, card,
             subtitle, local voice, then listening again)
```

Without `OPENAI_API_KEY` on the Worker the deterministic **mock chat provider**
answers (topic facts with follow-up memory, the unsure line, a greeting). The
whole path is therefore exercisable offline against
`tools/tutor_mock_server/server.mjs`, which speaks the same shape.

## 2. Files

| Layer | File | Role |
| --- | --- | --- |
| Worker | `cloud/src/tutor/provider/openai/{index,turns,client,prompts,schema}.ts` | `ProviderFactory` for the turns path: Chat Completions, strict TutorTurn JSON schema, server-built prompts, temperature 0.3, bounded `max_tokens`, per-attempt timeout + one retry, usage numbers, injectable fetch. `realtime` stays `null`. |
| Worker | `cloud/src/tutor/provider_registry.ts` | Wires the factory. Instantiated only when `OPENAI_API_KEY` is set; otherwise the mock. `setProviderTestSeam()` is a test-only hook for the Durable Object path. |
| Worker | `cloud/src/tutor/chat_config.ts` | `FREE_CHAT_ENABLED` (default `"false"` in code), `CHAT_CONTEXT_TURNS` (K, default 6, max 12), `CHAT_RESPONSE_MAX_WORDS` (default 25, band 8..40), `CHAT_MAX_OUTPUT_TOKENS` (default 160). `chatAllowed()` = `DEV_MODE && enabled`. `403 feature_disabled`. |
| Worker | `cloud/src/tutor/chat_safety.ts` | Regex redirect list (child text AND reply), scripted redirect turns, word cap, unsure line. No external call. |
| Worker | `cloud/src/tutor/chat_provider.ts` | `ChatTurnProvider` (duck-typed extension of `TurnProvider`), the chat gate `gateChatTurn()`, the mock chat provider. |
| Worker | `cloud/src/routes/tutor.ts` | `mode: "lesson" \| "chat"` on `POST /v1/tutor/sessions` (the only change). Realtime token route refuses `mode: "chat"`. |
| Worker | `cloud/src/do/tutor_session_do.ts` | Chat sessions: `sessionMode`, rolling window in DO storage, `produceChatTurn()`, window cleared on end. Lesson path untouched. |
| Mock | `tools/tutor_mock_server/server.mjs` | `chat` scenario (any client), `chatoff*` scenario (403 `feature_disabled`). |
| Game | `game/scripts/tutor/cloud/cloud_tutor_api.gd` | `create_session(lesson_id, mode)`, `submit_chat_turn()`, `session_body()`, `chat_turn_body()`, `CODE_FEATURE_DISABLED`. Still the only file with a network class. |
| Game | `game/scripts/tutor/cloud/free_chat_controller.gd` | The mode switch and the transcript route. No network class. |
| Tests | `cloud/test/provider_openai.test.ts`, `cloud/test/chat.test.ts`, `game/tests/cases/test_tutor_free_chat.gd`, `game/tests/cases/test_tutor_cloud_integration.gd` (chat + chatoff), fixture `game/tests/fixtures/tutor_chat_exchange.json` | see §7 |

## 3. Wire contract (additions to `docs/ALIZ_TUTOR_API.md` §1)

`POST /v1/tutor/sessions`
- body `{mode: "chat", clientId}` (`lessonId` optional, ignored; the session is
  recorded under `free_chat`). `mode` omitted or `"lesson"` = the existing
  contract, byte for byte.
- `201 {..., mode: "chat", lessonId: "free_chat", lessonKnown: false, chat: {responseMaxWords, contextTurns}}`
- `403 feature_disabled {feature: "free_chat"}` unless the Worker runs in
  `DEV_MODE` **and** `FREE_CHAT_ENABLED` is `"1"`/`"true"`. Production-shaped
  env (`DEV_MODE=0`) always refuses, whatever the flag says (tested).
- `400 bad_request` for any other `mode`.

`POST /v1/tutor/sessions/:id/turns` on a chat session
- body `{transcript (1..500 chars, required), responseMaxWords? (clamped 8..40)}`; no `lessonContext`.
- `200` = the lesson reply shape plus `mode: "chat"`, `contextSource: "chat"`,
  `chat: {responseMaxWords, historyTurns, redirected, capped}`. `turn.lessonAction`
  is always `"none"`, `nextQuestion` never present. `provider` is
  `openai:<model>`, `mock` or `safety`; `fallback` is `null`,
  `redirect:child:<category>`, `redirect:reply:<category>`,
  `invalid_turn:<reasons>`, `provider_timeout` or `provider_error:<status>`.
- Idempotency, quota charging (`chargedSeconds`, `usedTurns`, `endAtBoundary`),
  rate limits, consent, budget and session ownership: identical to a lesson turn.
- `400 invalid_turn` for an empty transcript.

`POST /v1/tutor/realtime/token` with `mode: "chat"`: `400 bad_request` (chat
runs on the turns path only). Without a key it is still `503 provider_unavailable`.

## 4. Safety rules (server side, every reply)

1. **Child text first.** `checkChatText(transcript)` runs before any provider is
   asked. A hit (categories: `personal_data`, `contact`, `adult`, `violence`,
   `substances`, `scary`, `self_harm`, `unsafe_acts`, `money`, `links`) answers
   with the scripted redirect for that category (`provider: "safety"`), the
   turn is still charged, and the model never sees the words.
2. **Persona.** Server-built system prompt: Aliz, kind playful teacher for a
   3–6 year old; ≤ N words; simple English; the unsure line
   `"I'm not sure, let's find out together!"`; gentle redirect for unsafe /
   adult / personal-data topics back to play or the lesson; never asks for the
   child's name, address, school, age, family, location; never mentions the
   internet, links, prices, apps, or being an AI. The transcript is the only
   free text and travels quoted as data.
3. **Structured output.** Strict JSON schema = TutorTurn with `lessonAction`
   pinned to `["none"]` and `visual.assetId` limited to the approved allowlist
   (or `""`). Anything else parses to `null` → mock fallback.
4. **The chat gate** (`gateChatTurn`): word cap (normalisation, clean sentence
   end) → the **shared TutorTurn validator** (ASCII, ≤ 160 chars, no URL, no
   digit runs, banned words, enums, allowlisted asset) → the same regex list on
   the reply. Invalid → mock answer (gated again); flagged → scripted redirect
   (`provider: "safety"`, `fallback: redirect:reply:<category>`).
5. **Never a dead end.** Provider timeout / 5xx / invalid JSON → the mock chat
   answers. Every redirect line is itself a valid turn and does not trip its own
   rules (tested).
6. **Client side, again.** The controller maps `none` → `retry` and runs
   `tutor_turn.gd` `coerce()` before presenting; the scene coerces once more.

## 5. Godot integration (what the lead wires)

Everything is constructed from the bridge the classroom already builds while
`TutorFlags.cloud_enabled()` is true; nothing under `scripts/tutor/cloud/` is
loaded when the flag is off, so a public build is unchanged.

The **one line** required for routing, in `tutor_scene._request_turn(transcript, phase)`
before `_provider.call("submit_turn", ...)`:

```gdscript
if _cloud_bridge != null and _cloud_bridge.has_meta("freeChat") and bool(_cloud_bridge.get_meta("freeChat").call("intercept_turn", transcript, phase)): return
```

It is a no-op with no controller attached or in lesson mode. The entry point
(a dev/QA button, a debug key) is:

```gdscript
var chat: RefCounted = load("res://scripts/tutor/cloud/free_chat_controller.gd").attach_to_bridge(_cloud_bridge)  # idempotent
chat.enter_free_chat()      # -> chat session, greeting through turn_ready, then listening
chat.return_to_lesson()     # -> /end, "Okay! Back to our lesson!" with jump_step (re-asks the current step)
chat.set_response_max_words(20)   # 0 = server default (25); band 8..40
```

Signals for a HUD: `mode_changed(mode)`, `chat_ready(info)`,
`chat_turn(turn, meta)` (`meta` = provider/fallback/redirected/capped/words,
never the transcript), `chat_unavailable(code)`, `chat_ended(reason)`. Call
`on_scene_exiting()` from the scene's exit (or let the lesson session's end
cover it: the Worker ends idle sessions after 120 s).

Behaviour inside the scene: the reply is spoken by `_speak_turn()` and, being
`retry`, the scene listens again on the same step. Silence (`timeout` /
`together` phases) is answered locally; the third silence returns to the
lesson. `feature_disabled`, quota exhaustion or a dead session return to the
lesson with a kind line and `jump_step` (the scene re-opens the current step;
the engine has not moved).

Known coupling (accepted for dev): the controller shares the lesson session's
serial REST queue and `completed` signal; it only consumes the kinds it is
awaiting and refuses to start while the lesson session is mid-handshake. The
lesson session's own idle timer keeps running during a chat; the
`CloudTutorProvider` restarts it on the next lesson turn.

## 6. Configuration

Worker env (plain vars; names only in `cloud/.dev.vars.example`; **not** added
to `wrangler.toml`, the lead sets them on dev when QA starts):

| Var | Default | Bounds |
| --- | --- | --- |
| `FREE_CHAT_ENABLED` | `false` | honoured in `DEV_MODE` only |
| `CHAT_CONTEXT_TURNS` | `6` exchanges | 0..12 |
| `CHAT_RESPONSE_MAX_WORDS` | `25` | 8..40 (a turn may lower/raise inside the band) |
| `CHAT_MAX_OUTPUT_TOKENS` | `160` | 40..400 |
| `OPENAI_API_KEY` | absent | Worker Secret only (`wrangler secret put`), never in Godot |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | optional gateway |
| `TUTOR_MODEL`, `PROVIDER_TIMEOUT_MS` | existing | the provider's per-attempt timeout is 4 s inside the DO's 6 s |

Game: no new project setting. `little_days/ai_tutor/cloud_enabled=false` stays.

## 7. Tests and evidence

- Worker: `cd cloud && npm test` → **172 passed** (baseline 151 + 21);
  `npm run typecheck` clean. `provider_openai.test.ts` (fake fetch): request
  shape, key only in the header, schema, valid reply → TutorTurn, invalid
  JSON / refusal / empty → `null`, retry on 5xx/429, no retry on 4xx,
  per-attempt timeout + caller abort, no logging of prompt/transcript/key,
  base URL + extra headers. `chat.test.ts`: off by default, production-shaped
  env refuses, config bounds, session + gated turn + idempotency + D1 numbers
  only, rolling window (K, cleared on end), word cap (session default,
  per-turn, band), child redirect + reply redirect + redirect lines valid,
  empty transcript, faulty provider → mock, quota by server clock, and the
  OpenAI path through the Durable Object with a fake fetch (valid reply with
  usage + cost, invalid JSON → mock, flagged reply → redirect, banned word →
  mock, 503 → mock). `realtime.test.ts`: still 503 with a key (turns-only module).
- Godot: `PASS - 169 case(s), 0 failure(s)` with and without the mock
  (baseline 168 + `test_tutor_free_chat`). Privacy guards unchanged and green:
  the controller holds no network class, so no allowlist entry.
- Mock: `node tools/tutor_mock_server/server.mjs` then the suite; the chat
  scenario prints the four replies (`mock`, `mock`, `safety`/`personal_data`,
  `mock`/capped) and `chatoff: refused=["feature_disabled"]`.

## 8. What is blocked, and by what

| Blocked | Why | Unblocks |
| --- | --- | --- |
| Any live OpenAI call | `OPENAI_API_KEY` is **absent** on the dev Worker and on this Mac; **no OpenAI request was made** while building this. The live provider path is exercised only against a fake fetch. | Owner sets the secret on dev (`wrangler secret put OPENAI_API_KEY --env dev`) and QA runs `cloud/README` smoke against dev with synthetic text. Until then every turn is `provider: "mock"`. |
| Chat on staging/production | `chatAllowed()` requires `DEV_MODE`; the flag alone is not enough (tested). | The privacy gates in `docs/ALIZ_TUTOR_PRIVACY_REVIEW.md` (consent, retention, vendor terms, transcript handling) pass and the gate is widened deliberately. |
| Chat in any app build | `little_days/ai_tutor/cloud_enabled=false`; nothing under `cloud/` loads. | Same review. |
| Live child audio / realtime chat | Chat runs on the REST turns path with on-device STT text; the provider's `realtime` is `null`; no microphone audio leaves the device. | Not planned in this slice. |
| Persisting the conversation | The rolling window lives in Durable Object storage for the session only and is cleared on end; D1 holds numbers/ids. Idempotency rows hold the reply JSON for 24 h like lesson turns (no transcript). | — |
| Lead wiring | `tutor_scene.gd` is untouched: the one-line hook and the entry button (§5) are the lead's. | — |
