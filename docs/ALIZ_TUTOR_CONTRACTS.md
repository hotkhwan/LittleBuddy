# Aliz Tutor Mode — shared contracts (lead-owned)

Every agent builds against these interfaces. Consumers reach a provider through
`has_method()` guards or `ResourceLoader.exists()` so each piece runs (with a
stub) before the others land. All dictionaries use camelCase keys.

## Feature flag
`game/scripts/tutor/tutor_flags.gd`: `TutorFlags.cloud_enabled()` (false in
public builds), `local_tutor_enabled()` (always true), `backend_url()`.
No cloud call, microphone upload or LLM turn may run while `cloud_enabled()` is
false. The scripted local tutor must give a complete 5-minute lesson without it.

## LessonEngine (Agent A) — `game/scripts/tutor/lesson/lesson_engine.gd`
Deterministic owner of the educational progression. Pure GDScript, no nodes.
- `load_lesson(lesson_id: String) -> bool`
- `current_step() -> Dictionary` `{stepId, kind: "ask"|"teach"|"celebrate", questionText, teachText, visualAssetId, expectedAnswers: [String], objective, hint, encouragement}`
- `evaluate(transcript: String) -> Dictionary` `{outcome: "correct"|"incorrect"|"unclear", matched: String, hint, encouragement, lessonAction: "next_question"|"retry"|"give_hint"|"complete"}` — normalises case/punctuation, accepts synonyms from the lesson data; second wrong answer on a step returns `give_hint`, third returns `next_question` with `outcome: "unclear"` (never a fail state).
- `advance() -> void`, `is_complete() -> bool`, `progress() -> Dictionary` `{lessonId, stepIndex, stepCount, correctFirstTry, completed}`
- `save_progress(save_service)`, `load_progress(save_service)` under settings key `tutorProgress` (camelCase, per lessonId).
- Lesson data: `game/content/tutor/lessons/<lessonId>.json`, schema in `game/content/tutor/lesson_schema.json`; subjects index `game/content/tutor/subjects.json`.

## TutorTurn (shared schema, validated client AND server)
```json
{"speech":"...","subtitle":"...","emotion":"happy","gesture":"clap",
 "visual":{"type":"flashcard","assetId":"apple_red"},
 "lessonAction":"next_question","nextQuestion":"..."}
```
- emotion ∈ neutral, listening, thinking, happy, encouraging, smile
- gesture ∈ none, nod, tilt, point, clap, wave
- visual.type ∈ none, flashcard, model; visual.assetId ∈ the approved list in `game/content/tutor/assets_allowlist.json` (apple_red, banana_yellow, cat, dog, number_1, number_2, number_3, color_blue, color_green, color_red, color_yellow, orange_orange, grapes_purple)
- lessonAction ∈ next_question, retry, give_hint, complete, end_session
- speech ≤ 160 chars, subtitle ≤ 160 chars, nextQuestion ≤ 120 chars; ASCII-printable plus common punctuation; age filter (no URLs, no numbers > 20 digits, no banned words list in the validator).
- Anything invalid → the validator returns the safe fallback turn `{"speech":"Let's try together!","emotion":"encouraging","gesture":"tilt","visual":{"type":"none"},"lessonAction":"retry"}`.
- Client validator: `game/scripts/tutor/turn/tutor_turn.gd` (Agent E; Agent B may write a first version and E takes it over). Server validator: `backend/src/turn_validator.js` (Agent D). Same rules, same fixture file `game/content/tutor/turn_fixtures.json` used by both test suites.

## ConversationProvider (Agent E; Agent B stubs) — `game/scripts/tutor/providers/`
- `ScriptedConversationProvider` (local): builds the TutorTurn from LessonEngine output only. Always available.
- `BackendConversationProvider` (cloud, flag-gated): POST turns to the backend; never holds a provider secret.
- Interface: `begin_session(lesson_id) -> void` + signal `session_ready(session: Dictionary)`; `submit_turn(transcript: String, lesson_context: Dictionary) -> void` + signal `turn_ready(turn: Dictionary)`; `end_session()`; signal `provider_failed(reason: String)`; `cancel()`.

## SpeechRecognitionProvider / SpeechSynthesisProvider (Agent E)
- Recognition: wraps the existing `SpeechService` (on-device) — states start, listening, partial, final, processing, retry, unavailable; hard caps; mic never open during playback.
- Synthesis: `speak_turn(turn) -> Signal finished`; plays a recorded/bundled line via `/root/Voice` when one matches, else backend TTS bytes (flag-gated), else on-device TTS. Emits amplitude for lip sync through `LipSyncSource` (below). Music ducks via the existing duck hook.

## TutorFace (Agent C) on `pink_girl_buddy.gd` (documented at the file top)
- `set_expression(name)` name ∈ neutral, listening, thinking, happy, encouraging, smile
- `play_gesture(name)` name ∈ nod, tilt, point, clap, wave (returns duration seconds)
- `set_speaking(active: bool)`; `set_mouth_open(amount: float)` 0..1, smoothed inside; mouth closes when `set_speaking(false)`
- `LipSyncSource` node (`game/scripts/characters/buddy/buddy_lip_sync.gd`): attach to an AudioStreamPlayer's bus, reads the amplitude envelope (AudioEffectCapture or SpectrumAnalyzer) and calls `set_mouth_open`; never a fixed timer.
- Must not disturb locomotion, carry pose, idle, blink or the existing face moods.

## TutorQuota (Agent F) — `game/scripts/tutor/quota/tutor_quota.gd`
- `refresh() -> void` + signal `quota_changed(state)`; `state()` → `{entitlement: "free"|"family_club", dailyAllowanceSeconds, usedSeconds, remainingSeconds, resetAtUtc, resetAtLocalText, sessionActive}`
- Server is the authority when cloud is enabled; local mirror only for the scripted tutor (still UTC-day keyed, persisted, restart-proof).
- Signals `near_end(remainingSeconds)` (60 s), `expired` (fires only at a safe turn boundary requested by the scene via `request_end_at_boundary()`).

## Tutor scene (Agent B) — `game/scenes/tutor/classroom.tscn`, `game/scripts/tutor/tutor_scene.gd`
Orchestrates LessonEngine → provider → synthesis → face; HUD with Home, Mute, Repeat, Picture card, Microphone, Exit lesson; flashcard board; state banner (Listening / Thinking / Speaking / Great! / Let's try together!). Break screen: "Great job today!" / "Come back tomorrow for more Little Days!" / "Keep playing with Bunny!" with Continue Playing and Home. Entry from the title screen button "Learn with Aliz" (lead wires it).

## Backend (Agent D) — `backend/` (Node 22, no external dependencies)
Endpoints: `POST /api/v1/tutor/sessions`, `POST /api/v1/tutor/sessions/{id}/turns`, `GET /api/v1/tutor/entitlement`, `POST /api/v1/tutor/sessions/{id}/end`, plus dev-only `POST /api/v1/dev/entitlement` and mock billing. Server-side quota (UTC day), idempotency keys on turns, rate limits, timeouts, structured-output validation, usage/cost accounting, `MockConversationProvider` default, OpenAI adapter behind `OPENAI_API_KEY` (never present in the client; not present on this machine today).
