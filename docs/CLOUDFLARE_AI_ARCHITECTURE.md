# Cloudflare AI architecture

Last updated: 2026-09-22

## Purpose and operating boundary

Little Days uses Cloudflare as an optional, server-side extension to its deterministic, offline-first English lessons. The game must remain playable without a network connection. AI may explain, rank an approved lesson, or produce a validated tutor turn; it does not own curriculum, progression, rewards, or unrestricted game execution.

Only English curriculum is enabled for V1. The schema reserves other languages and subjects, but they are roadmap-disabled. Aliz is presented as a learning companion, never as a replacement parent, teacher, therapist, friend, or human relationship.

## Request path

```text
Godot client
  -> api.littledays.joinanny.com
     -> authentication, consent, quota and closed-production gates
     -> TutorSessionDO (one ordered state stream per tutor session)
        -> approved local lesson context
        -> provider registry
           -> Workers AI binding (standard text/structured/tool inference)
           -> deterministic mock/local fallback
        -> TutorTurn validator and asset allowlist
        -> numeric usage/cost recording in D1
     -> validated semantic response to Godot
```

The client never receives provider credentials and never selects an arbitrary provider model. Provider choice, model identifiers, timeout, quotas, and budgets are server configuration.

## Implemented components

| Component | Current implementation | Safety boundary |
|---|---|---|
| API edge | Hono Worker in `cloud/src/app.ts` | Body limits, authentication, rate limits, closed-production gate, child-safe API errors |
| Session state | `TutorSessionDO` | Serializes turns, isolates sessions, enforces ownership/idempotency, charges quotas, expires idle sessions |
| Standard inference | `WorkersAIProvider` over `env.AI` | Normalizes chat, JSON schema and tool calls; timeout/cancel handling; classifies 429 and capacity errors |
| Tutor output | `TutorTurn` contract and validator | Enum restrictions, text limits, banned content checks and approved asset IDs; invalid output becomes a deterministic fallback |
| Curriculum | Versioned corpus plus approved retrievers | Only active English lessons; draft/unknown IDs cannot cross the managed-retrieval boundary; prompt-injection patterns are rejected |
| Planning | `LearningPlanner` | Deterministic grade, language, time, activity and mastery constraints precede ranking |
| Agent tools | `AlizLearningAgent` and exact tool validators | Eleven semantic tools only, exact argument shapes, per-minute limit, lesson-scoped assets |
| Voice protocol | Provider-neutral WebSocket event contracts and fallback state machine | Child audio runtime gate, bounded event parsing, child-safe errors, Cloudflare → Gemini → standard → local fallback |
| Telemetry | D1 usage rows and benchmark artifacts | Numeric token/cost/latency signals; request logging excludes bodies, headers, URL parameters and conversation text |

## Workers AI adapter

`WorkersAIProvider` supports three normalized operations:

- `chat`: messages with bounded generation settings;
- `structured`: Cloudflare JSON-schema response format, accepting string or object-valued binding responses;
- `toolCall`: direct Workers AI function definitions with normalized function arguments.

The tutor bridge sends a short system policy and trusted, server-resolved lesson context. Its response remains untrusted until the shared TutorTurn validator accepts it. Token usage is normalized to input, output, cached input, and total counts when the provider supplies them.

The default provider timeout is configurable and adapter errors expose only stable internal categories: timeout, rate limited, capacity, invalid response, or provider error. Provider messages are not intended for child display.

## Curriculum retrieval and planning

The authoritative curriculum is the reviewed corpus in `cloud/curriculum/english/corpus.json`. Every lesson carries version, publication state, language, subject, age band, grade, skill, difficulty, standard, lesson type, objective, prompts, accepted responses, hints, common mistakes, props, variants, and duration.

`ApprovedCurriculumRetriever` is the deterministic retrieval path and fallback. `ManagedCurriculumRetriever` can consume managed-search result IDs, but maps them back through the locally approved active catalog. A search service therefore cannot introduce an unknown or draft lesson into a child session.

`LearningPlanner` constrains candidates to English, grade, available activity types, remaining session time, parent settings, mastery, preferences, and recent lessons. AI retrieval/ranking can help find candidates; it cannot randomly invent the curriculum or override these constraints.

The configured binding name is `AI_SEARCH`, and the intended instance name is `little-days-curriculum`. Until that managed instance is successfully created, populated, indexed, and retrieval-tested, the approved local retriever is the operational path and the managed search must be reported as not ready.

## Agent state and tools

Learning-agent state is deliberately bounded:

- session and child-profile identifiers;
- approved lesson and current objective;
- turn number;
- recent mastery signals and responses;
- the tools allowed for that session.

The allowlist contains `show_learning_card`, `show_prop`, `set_emotion`, `play_gesture`, `look_at`, `award_star`, `start_minigame`, `suggest_activity`, `repeat_prompt`, `give_hint`, and `complete_lesson`. Tool arguments use exact schemas, identifiers are restricted, intensity is bounded, lesson assets are checked, and calls are rate-limited. No shell, filesystem, network, arbitrary scene execution, or raw Godot command is exposed.

Durable Object persistence for this new learning-agent state is not yet wired. Existing tutor session and quota state already use Durable Objects; deployment must not claim learning-agent recovery until the new state is connected and recovery/concurrency tests pass.

## AI Gateway

Workers AI currently routes through Cloudflare's actual `default` AI Gateway from the provider registry. Requests set `skipCache: true`; personalized child conversation must not be cached. The desired dedicated gateway name is `little-days-ai`, but creating or administering that gateway is currently blocked by the available Cloudflare token permissions. Routing must remain on `default` until the owner grants the required permission or creates the dedicated gateway.

Gateway analytics may be used for provider status, aggregate latency, rate limiting, retry observation and cost tracking. Configuration must not intentionally log raw child audio or unnecessary conversation text. If a future gateway feature requires payload logging to deliver value, it needs a separate privacy review and explicit safe configuration before use.

## Voice architecture

The implemented voice layer is a provider-neutral protocol and fallback foundation, not a production child-audio service. It defines session, binary audio, transcript, assistant text/audio, interruption, cancellation, turn metrics and fallback events. Errors collapse to a short child-safe transition.

Production voice remains gated by all of the following:

- `LIVE_CHILD_AUDIO_ENABLED=true`;
- valid consent and entitlement;
- an approved provider deployment;
- privacy/legal approval and measured adult/synthetic QA.

Current development and closed-production configuration keeps `LIVE_CHILD_AUDIO_ENABLED=false`. Cloudflare Voice Agent, STT and TTS adapters must not be described as live until a real end-to-end WebSocket/audio run has completed. Local lessons and local/native speech remain the terminal fallback.

## Environment and resource status

| Resource/configuration | Development | Closed production |
|---|---|---|
| Worker | `little-days-api-dev` | `little-days-api` at `api.littledays.joinanny.com` |
| D1 | `little-days-dev` | `little-days-prod` |
| Workers AI binding | `AI` configured | `AI` configured |
| AI Gateway | Actual `default`; dedicated gateway pending permission | Actual `default`; dedicated gateway pending permission |
| AI Search binding | `AI_SEARCH` configured for namespace `default`; target instance pending actual setup verification | Same; do not claim indexed until verified |
| Production gate | `PRODUCTION_ENABLED=false` | `PRODUCTION_ENABLED=false` |
| Billing | disabled | disabled |
| Live child audio | disabled | disabled |

Bindings in configuration are necessary but not proof that a remote resource exists, is indexed, or is healthy. Deployment reporting must distinguish configuration, successful API/resource inspection, successful indexing, and a passing live retrieval/inference test.

## Privacy and observability

- Do not retain raw child audio by default.
- Do not store full conversation history long-term by default.
- Store minimum learning signals and numeric usage needed for progress, quota and cost controls.
- Never place provider secrets in Godot, repository configuration, benchmark artifacts or logs.
- Keep personalized response caching disabled.
- Use synthetic/adult content for provider and voice benchmarks.
- Preserve account, parent, child and session ownership checks before AI access.

## Failure behavior

Every network/provider failure must degrade toward a safe experience:

```text
managed retrieval -> approved local retrieval
reasoning model -> standard model -> deterministic local lesson
premium voice -> standard voice -> standard text -> local lesson
invalid model output -> validated deterministic TutorTurn fallback
```

Children must not see HTTP status codes, quota infrastructure messages, provider names, stack traces or raw exception strings. Closed production may expose health/readiness endpoints while tutor, billing, school and child-audio traffic remains closed.

