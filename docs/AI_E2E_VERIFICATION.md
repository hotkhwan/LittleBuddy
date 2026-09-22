# AI path — end-to-end verification (development Worker)

Date: 2026-09-22. Checkout: `feature/ui-meshy-cloud` at `41393bf` (Codex's `0f1bc51`
merged; HEAD advanced to `7daea89` during the run, identity work only). Godot 4.7.2
headless on macOS. Worker: `https://little-days-api-dev.hotkhwan.workers.dev`
(`DEV_MODE=1`, `provider: workers_ai`, `migrations: 7`). Nothing was deployed, no
game script, `cloud/` file or `wrangler.toml` was edited, no device was used, every
transcript below is a fixed adult string or the classroom's simulated-child hook.

## Verdict in one paragraph

The chain **Godot Classroom → Worker (TutorSessionDO) → Workers AI → validated
TutorTurn → Aliz face/gesture → TTS lip sync → mic gate** runs end to end and every
stage that is wired is exercised by the runs below. Two stages named in the brief
are **not in the runtime path at all**: the *Learning Agent / AI Search curriculum
retrieval* (only a `/v1/dev/learning/search` probe route uses it; the tutor turn
path never calls the planner, the retriever or `validateToolCall`) and the
*Expression Director / cue contract / lip-sync driver / tool router* on the client
(referenced by tests only; the scene drives `TutorFace` directly through
`_speak_turn -> _face/_gesture`). Workers AI itself **does answer** (two valid,
model-authored turns were served, 4.4 s and 5.8 s), but on the dev Worker the
standard route (`gemma-4-26b`) hits the DO's 6 s provider budget on every turn
observed (10/10) and the **deterministic mock answers with
`provider: "mock", fallback: "provider_timeout"`**. Chat mode never reaches Workers
AI by construction (`provider: "mock", fallback: null`). Both offline legs hold: flag
off = scripted tutor with nothing from `cloud/` in the tree; flag on + dead backend =
quiet scripted fallback, `provider_failed` path says "Let's try together!", the
classroom never dies.

## Per-stage table

Evidence lines are verbatim from the runs (commands in the next section).
PASS = observed working; FALLBACK = the safe fallback served instead;
NOT REACHED = no runtime path exists on this head.

| # | Stage | Evidence (verbatim) | Result |
|---|---|---|---|
| 1 | Worker health, provider config, D1 migrations | `{"ok":true,"service":"little-days-cloud","apiVersion":"v1","devMode":true,"provider":"workers_ai","lessons":6,"billingEnabled":false,"db":{"ok":true,"migrations":7}}` | PASS |
| 2 | Dev sign-in → consent → lesson session (approval token only on tutor routes) | `SIGNIN 201 {"parentId":"f5d8e58d-…","provider":"dev","hasPt":true,"hasPa":true}` / `CONSENT 200 … "ai_tutor":{"version":1,…,"granted":true}` / `LESSON_SESSION 201 {"sessionId":"c652c03b-…","lessonKnown":true,"mode":"lesson","entitlement":"free",…}` | PASS |
| 3 | AI Search curriculum retrieval (`AI_SEARCH` binding, `little-days-curriculum/default`, mapped to approved ids) | `AISEARCH 200 1488ms {"query":"child knows red and blue but struggles with green","grade":"prek","results":[{"lessonId":"en-prek-colors-look-touch-v1","score":0.6284287,…},{"lessonId":"en-prek-body-actions-v1","score":0.4251736,…}]}` / `AISEARCH 200 1362ms {"query":"cat and dog animal words","grade":"kindergarten","results":[{"lessonId":"en-kindergarten-phonics-animals-v1","score":1,…}]}` | PASS (live index answers) — **but only via the dev probe route; see stage 4** |
| 4 | Learning Agent (planner + retrieval + 11-tool `validateToolCall`) inside a tutor turn | `grep` over `cloud/src` outside `learning/`: the only importer is `cloud/src/routes/dev.ts:13` (`CloudflareCurriculumSearch, ManagedCurriculumRetriever`). `TutorSessionDO.produceTurn` (tutor_session_do.ts:517) calls `this.provider().generateTurn` → `validateTurn`; no retriever, no planner, no `AlizLearningAgent`. Turn bodies expose no retrieval/curriculum/tool fields: `keys=["turn","quota","endAtBoundary","turnIndex","chargedSeconds","provider","cached","fallback","contextSource","usage"]` | NOT REACHED |
| 5 | Workers AI serves a lesson turn (standard route, `@cf/google/gemma-4-26b-a4b-it`) | `LESSON_TURN {"i":1,…,"provider":"mock","fallback":"provider_timeout","contextSource":"server","latencyMs":6000,…}` (same for i=2,3; 10/10 standard-route turns across three runs). `wrangler tail`: `[tutor-session] provider workers-ai-router:@cf/google/gemma-4-26b-a4b-it failed: provider_timeout` | FALLBACK (mock, `provider_timeout` at the 6000 ms budget) |
| 6 | Workers AI serves a lesson turn (complex route, `@cf/openai/gpt-oss-120b`, chosen by the `why/because/explain` regex) | `AI-E2E lesson turn 3: provider=workers-ai-router:@cf/google/gemma-4-26b-a4b-it fallback=null contextSource=server latencyMs=4432 tokens=258/423 valid=true reasons=[] emotion=encouraging gesture=clap visual={ "type": "model", "assetId": "dog" } action=give_hint speech="A dog says woof! Can you say woof?"` (earlier run: `latencyMs=5836 tokens=258/382`, same text) | PASS (model-authored, validated; note the label names the primary model, not the one that served) |
| 7 | Chat session on Workers AI | `CHAT_TURN {"i":1,…,"provider":"mock","fallback":null,"mode":"chat","chat":{"responseMaxWords":25,"historyTurns":1,"redirected":null,"capped":false},"latencyMs":0,…,"turn":{"speech":"Apples grow on trees. They can be red or green.",…,"lessonAction":"none"}}` (3/3) | FALLBACK by construction: the Workers AI turn provider has no `generateChatTurn`, so `chatProviderOf(primaryTurns) ?? this.mockChat` picks the mock and reports **no** fallback reason |
| 8 | Server TutorTurn validator / asset allowlist (`fallbackTurn` on invalid output) | Every turn body's `turn` re-validated by the client: `AI-SMOKE: raw server turns … valid=true reasons=[]` ×6; `AI-E2E lesson turn 1..3 … valid=true`; chat ×3 `valid=true` after the client's `none → retry` mapping | PASS |
| 9 | Client validator + `tool_applied` (semantic tool = flashcard visual) | `AI-SMOKE: server provider histogram={ "mock/provider_timeout": 6 }` with `invalid_raw=0`; `tool_applied("show_card", {assetId})` is what `cloud_tutor_session.gd:874` emits for a `flashcard` visual; the board shows `apple_red / banana_yellow / orange_orange` per turn | PASS |
| 10 | Client `LearningToolRouter` / `LearningAgentResponse` / `TutorCueContract` applied to a live turn | `grep` over `game/scripts`, `game/scenes`: referenced only by `tests/cases/test_learning_agent_client.gd`, `test_tutor_expression_system.gd`, `test_tutor_session_contract.gd` | NOT REACHED |
| 11 | Expression Director → Aliz | Same grep: `TutorExpressionDirector` is not instanced by any scene. The live path is `tutor_scene.gd:_speak_turn` → `_face(expression)` → `PinkGirlBuddy.set_expression`, `_gesture(g)` → `play_gesture` | NOT REACHED (director); the direct path is stage 12 |
| 12 | Aliz face / gesture per turn (TutorFace read-backs) | `TURN 5 [server=mock/provider_timeout] [words=cloud voice=tts] action=next_question turn(emotion=happy gesture=clap) aliz(expression=happy gesture=nod)` / `TURN 7 … turn(emotion=encouraging gesture=point) aliz(expression=encouraging gesture=encourage)` / `TURN 13 … aliz(expression=happy gesture=celebrate)` — `expressions=["smile", "happy", "encouraging"] encouraging_seen=true`, no consecutive repeat | PASS (pool overrides the server gesture on answer turns, by design: `TutorGesturePool`) |
| 13 | Lip sync while the voice plays | `#05 … voice=tts … mouth=0.977 lip=0.977 samples=756` / `#07 … mouth=0.991 lip=0.991 samples=819` (every voiced turn > 0.9) | PASS (TTS pseudo-envelope; headless has no platform voice) |
| 14 | Voice path | `[words=cloud voice=tts]` on every server-authored turn; `cloud_voiced=0` in the baseline smoke; session ready with `fallback=provider_unavailable` (realtime token mint 503 → turns path) | PASS on the local TTS path; cloud audio NOT REACHED (no realtime provider on the Worker, by configuration) |
| 15 | Microphone while Aliz speaks / after | Per sample while speaking: `recOpen=false vadUngated=false` on all 17 turns; on every `listening` entry `mic capturing=true recognitionOpen=false vadGated=true`; at the end `mic after listening: is_capturing=false cloud_streaming_allowed=false` | PASS (hands-free keeps capture for barge-in but the recogniser is closed and the VAD gated; recogniser re-arms after) |
| 16 | Cloud session lifecycle | `history=["signing_in", "consenting", "quota", "creating", "minting", "ready", "ending", "ended"]` / `summary={ "reason": "smoke_done", … "serverAck": true, … "serverUsage": { "turns": 6.0, "llmInputTokens": 0.0, …} }` | PASS |
| 17 | Offline A — flag off | `A flag off: provider=scripted (res://scripts/tutor/providers/scripted_conversation_provider.gd) synth=res://scripts/tutor/providers/local_synthesis_provider.gd cloud nodes=[]` / `A flag off: 3 answers judged locally, 6 turns spoken` | PASS |
| 18 | Offline B — flag on, backend on a closed port | `B closed port: judged=3 spoken=6 words=local voice=voice session=signing_in fell_back=["provider_unavailable", …] fallbacks=["provider_unavailable", "provider_unavailable", "cloud_not_ready", …] provider_failed=[] requests=["signIn:provider_unavailable", …]` / `B provider_failed: spoke 'Let's try together!' banner=together provider now=res://scripts/tutor/providers/scripted_conversation_provider.gd` | PASS (quiet scripted fallback on an unreachable backend; the "Let's try together!" line is the `provider_failed` path) |
| 19 | Synthetic-only inputs | `AI-SMOKE: transcripts=simulated (scene hook only; no child audio, no real child)`; node/GDScript probes send fixed adult strings (`cat`, `a bird`, `why does the dog say woof…`, `What does apple mean?`) | PASS |
| 20 | Godot suite on this head | `PASS - 188 case(s), 0 failure(s)` (186 existing + the two `test_ai_e2e_*` cases; `test_ai_e2e_dev_provider` SKIPs without `LD_TUTOR_DEV_URL` and PASSes with it) | PASS |

## Exact commands

Server side (node 22, synthetic adult text; the script lives in the session scratchpad,
its full log is reproduced by the gated Godot case below):

```sh
curl -sS "https://little-days-api-dev.hotkhwan.workers.dev/healthz?db=1"
# sign-in: POST /v1/parents {provider:"dev", subject, clientId} -> parentToken (pt1.*), parentApprovalToken (pa1.*)
# consent: PUT /v1/consent {kind:"ai_tutor", granted:true}   authorization: Bearer <pt>
# AI Search probe: GET /v1/dev/learning/search?q=<text>&grade=prek   authorization: Bearer <pt>
# tutor routes take ONLY x-parent-approval: <pa>  (a Bearer header wins in authMiddleware and then
#   approvalToken is null -> 403 not_approved; the first probe run hit exactly that)
# POST /v1/tutor/sessions {lessonId:"animals_cat_dog", clientId, mode:"lesson"}
# POST /v1/tutor/sessions/<id>/turns {transcript, lessonContext:{stepId,outcome,matched,lessonAction}}  idempotency-key: <id>:tN
# POST /v1/tutor/sessions {clientId, mode:"chat"}  then turns with {transcript}
# POST /v1/tutor/sessions/<id>/end {reason}
cd cloud && npx wrangler tail --env dev --format json      # read-only; captured the DO's provider log line
```

Client side, Godot 4.7.2 (run from `game/`):

```sh
# 1. New AI classroom smoke (real scene, real time, per-turn stage log; ~2.5 min)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/smoke_ai_classroom.gd -- --ai-tutor-cloud \
  --tutor-backend-url=https://little-days-api-dev.hotkhwan.workers.dev
#    -> "AI-SMOKE: PASS"  (state=listening turns=17 cloud_authored=6 raw_server_turns=6 invalid_raw=0)

# 2. Existing classroom smoke, same URL (baseline)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/smoke_tutor_cloud_classroom.gd -- --ai-tutor-cloud \
  --tutor-backend-url=https://little-days-api-dev.hotkhwan.workers.dev
#    -> "SMOKE: FAIL" ONLY on its own 150 s budget (state=thinking, completed=false, cloud_authored=9,
#       provider_failed=[]): every server turn costs ~10 s (6 s provider budget + round trip).

# 3. Gated live case through the game's REST client (SKIP without the variable)
LD_TUTOR_DEV_URL=https://little-days-api-dev.hotkhwan.workers.dev \
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_one.gd -- test_ai_e2e_dev_provider
#    -> "[PASS] test_ai_e2e_dev_provider"

# 4. Offline / fallback legs (no network, part of the suite)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_one.gd -- test_ai_e2e_offline_fallback
#    -> "[PASS] test_ai_e2e_offline_fallback"

# 5. Whole suite
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run_tests.gd
#    -> "PASS - 188 case(s), 0 failure(s)"
```

Attempted and not possible from here: `wrangler dev --local --env dev` with
`PROVIDER_TIMEOUT_MS=30000` answered every turn with
`fallback: "provider_error:Binding AI needs to be run remotely"` because `[ai]` /
`[env.dev.ai]` carry no `remote = true` (`env.AI … not supported` in the binding
table); `wrangler dev --remote` was not permitted in this session. So the
"give Workers AI more than 6 s" experiment remains for the owner (see below).

## New files

| File | Purpose | Result line |
|---|---|---|
| `game/tests/smoke_ai_classroom.gd` | Real classroom against the dev Worker; per turn: server provider/fallback, validator verdict on the raw body, lessonAction, server gesture vs the gesture Aliz played, `get_expression()`, `get_mouth_open()` + `LipSyncSource.amount()` sampled while the voice plays, voice path, recogniser/VAD state while speaking and on each listening entry; ends the cloud session and checks the server ack | `AI-SMOKE: PASS` |
| `game/tests/cases/test_ai_e2e_offline_fallback.gd` | Suite case: flag off → scripted tutor, no `cloud/` script instanced; flag on (in-memory, restored) + closed loopback port → quiet scripted fallback, `fell_back(provider_unavailable)`, `provider_failed` → "Let's try together!" + TOGETHER banner, mic reopened, mic closed on leave | `[PASS] test_ai_e2e_offline_fallback` |
| `game/tests/cases/test_ai_e2e_dev_provider.gd` | Suite case gated by `LD_TUTOR_DEV_URL`: lesson session (correct / incorrect / unclear+why) and chat session through `cloud_tutor_api.gd`; prints provider, fallback, contextSource, latency, tokens, validator verdict per turn; asserts the contract (validated turn, provider label, `mode: chat` with `lessonAction: none` on the wire, word cap, `/end` ack) and reports which provider served rather than asserting it | `[PASS] test_ai_e2e_dev_provider` (SKIP without the variable) |
| `docs/AI_E2E_VERIFICATION.md` | This report | — |

No `.uid` sidecars were generated for the new scripts (headless runs do not write them);
opening the project in the editor will add them.

## Findings (file:line, no fix applied)

1. **Standard route always times out on the dev Worker.** `cloud/src/env.ts:220`
   defaults `providerTimeoutMs` to 6000 and `[env.dev.vars]` in
   `cloud/wrangler.toml` sets no `PROVIDER_TIMEOUT_MS`; Codex's own benchmark
   (`docs/AI_PROVIDER_BENCHMARK.md`) measured the selected standard models at
   7,290 / 7,542 ms median. Observed: 10/10 standard-route turns
   `provider: "mock", fallback: "provider_timeout", latencyMs: 6000`; the only
   model-authored turns came from the complex route (`gpt-oss-120b`, 4.4 s / 5.8 s).
   The child experience stays safe (mock lines) but pays the full 6 s wait first.
2. **The router's fallback model can never run after a timeout.**
   `cloud/src/tutor/workers_ai_provider.ts:185-187`: `catch … if (input.signal.aborted) throw error; return fallback.generateTurn(input)` — the DO aborts that same
   signal at `providerTimeoutMs` (`cloud/src/do/tutor_session_do.ts:521`) and each
   model's own `timeoutMs` equals the whole budget, so a slow primary always ends in
   the mock, never in `glm-4.7-flash`.
3. **Provider label does not name the model that served.**
   `cloud/src/tutor/workers_ai_provider.ts:180` fixes `name` to
   `workers-ai-router:<primaryModel>`; the complex-route turns above were served by
   `gpt-oss-120b` but reported as `…gemma-4-26b-a4b-it`. Usage/cost rows inherit
   the wrong model attribution.
4. **Chat mode never reaches Workers AI and does not say so.**
   `cloud/src/do/tutor_session_do.ts:569-570` picks
   `chatProviderOf(primaryTurns) ?? this.mockChat`; `createWorkersAITurnProvider`
   (`workers_ai_provider.ts:150-172`) returns only `generateTurn`, so every chat turn is
   `provider: "mock", fallback: null`. `docs/AI_CLASSROOM_HERO_FEATURE.md`
   ("short child-safe AI responses available through the Worker path") overstates
   the current state.
5. **Learning Agent, planner and AI Search are not on the tutor turn path.**
   Only `cloud/src/routes/dev.ts:52-62` (`GET /v1/dev/learning/search`) uses
   `ManagedCurriculumRetriever`; `produceTurn` (`tutor_session_do.ts:517`) never
   retrieves, plans or calls `validateToolCall`, and the turn body carries no
   retrieval/curriculum/tool fields. `docs/CLOUDFLARE_AI_ARCHITECTURE.md` already
   says DO persistence for agent state is not wired; `docs/AI_LEARNING_AGENT.md`
   "Integration requirements" reads as if the validator runs per turn — it does not
   run anywhere at runtime yet.
6. **Client Expression Director stack is test-only.**
   `game/scripts/tutor/expression/*.gd`, `learning/*.gd`,
   `session/tutor_session_contract.gd` are referenced by no scene or script outside
   `game/tests/cases/`; the classroom drives `PinkGirlBuddy.set_expression /
   play_gesture / set_speaking` directly from `game/scripts/tutor/tutor_scene.gd:705-765`
   and `:1751-1776`. Gesture rotation on answer turns comes from
   `tutor_gesture_pool.gd`, not from the director's `rotate()`.
7. **Model-facing gesture enum is a subset.** `workers_ai_provider.ts:137`
   (`TUTOR_SCHEMA.gesture`) allows only `none|nod|tilt|point|clap|wave`; the server
   validator accepts `thumbsUp|celebrate|listening|thinking|encourage` too. Harmless
   today (the pool overrides answer gestures) but the model cannot ask for a
   celebration.
8. **Local dev cannot exercise Workers AI.** `cloud/wrangler.toml:64-65` and
   `:138-139` (`[ai]`, `[env.dev.ai]`) lack `remote = true`; wrangler 4.135 reports
   `env.AI … not supported` and the DO logs `provider_error:Binding AI needs to be
   run remotely`.
9. **Baseline smoke budget.** `game/tests/smoke_tutor_cloud_classroom.gd:27`
   `MAX_SECONDS = 150` cannot finish a lesson while each server turn takes ~10 s
   (finding 1); it reports FAIL on `state=thinking` with `provider_failed=[]`. Not a
   game defect.
10. **Auth footgun (documentation).** A tutor-route request that carries
    `Authorization: Bearer` is treated as a bearer session (`cloud/src/auth/middleware.ts:43-48`), `approvalToken` is null and the route answers 403
    `not_approved` even when `X-Parent-Approval` is also present. The game client
    sends exactly one credential per request and is unaffected.

## What remains

- Owner decision on `PROVIDER_TIMEOUT_MS` for dev (≥ p95 of the chosen standard
  model, or a per-model budget) and a router retry budget that is not the same
  signal — then re-run command 1/3 and expect `workers-ai-router:*` in the histogram
  for standard turns.
- Wire (or explicitly descope) the Learning Agent on the turn path: retrieval →
  planner → `validateToolCall` → tool fields in the turn body, plus DO state; until
  then AI Search is a verified index without a consumer.
- Wire the Expression Director / cue contract / lip-sync driver into
  `tutor_scene.gd`, or record that `TutorGesturePool` + direct `TutorFace` calls are
  the shipped design and retire the unused classes.
- A Workers AI chat provider (`generateChatTurn`) if chat is meant to be AI; or
  mark chat "mock only" in the hero doc.
- OPENAI: `openAiFactoryWired: true` but no key on the dev Worker; not used in any
  run here (`TUTOR_PROVIDER=workers_ai`). External providers remain NR as in the
  benchmark.
- Realtime/cloud audio: token mint answers 503 on the dev Worker, so the classroom
  runs the turns path with the local voice; cloud audio and lip sync from streamed
  PCM were not exercised.
- AI Search index population beyond the 12 corpus lessons and the fifth (`skill`)
  filter are unchanged; the live probe used `grade` only, as the adapter does.
- Physical device, real microphone, child audio: not run, not claimed.
