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

---

## Addendum 2026-09-20 (evening): HANDS-FREE conversation supersedes push-to-talk

Owner change request. The child does not press a microphone button per turn.
Entering **Learn with Aliz** (after the parental gate and, for cloud, the
compliance gate) starts an active tutor session with the microphone live for
the whole session; Aliz welcomes the child; the system detects speech start
and end; Aliz answers with streaming speech; the child can interrupt (barge-in)
and Aliz stops and listens. Push-to-talk survives only as a **fallback** when
hands-free is unavailable (permission denied, no recogniser) or turned off by a
parent (`handsFreeMode` setting).

### Microphone scope (hard rules, test-enforced)
Capture only while `TutorVoiceSession.is_active()`. Never on the title screen,
in Free Play, in the background, after Exit, after quota expiry, without the
gate. Background → stop capture, stop streaming, suspend the session;
foreground → do NOT reopen; the child must re-enter Tutor Mode. A visible mic
activity indicator (live level) and an obvious Mute are mandatory.

### TutorVoiceSession (Agent E) — `game/scripts/tutor/voice/tutor_voice_session.gd`
States: `idle → welcoming → listening → child_speaking → thinking → aliz_speaking → (interrupted → listening) … → closing → ended`.
- `start(lesson_id, opts)`, `stop(reason)`, `mute(bool)`, `is_active()`, `is_capturing()`, `get_state()`, `get_input_level()` (0..1 for the indicator)
- signals `state_changed(from, to)`, `child_speech_started`, `child_speech_ended(transcript)`, `partial_transcript(text)`, `aliz_started(turn)`, `aliz_finished(turn)`, `barge_in`, `session_ended(reason)`
- VAD (`game/scripts/tutor/voice/vad.gd`, pure): energy envelope with adaptive noise floor; speech start = level above floor+margin for ≥ 120 ms; speech end = below floor for `endSilenceMs` (900 ms), extended to 1600 ms when the utterance so far is < 600 ms or the last partial ends in a hesitation ("um", "uh", trailing "a", "the"); long pause 3000 ms with no speech = prompt again, never an AI reply; noise rejection: ignore bursts < 120 ms and single spikes. Tuned constants live in `game/content/tutor/vad_profile_child.json`. When the recogniser itself provides end-of-utterance (on-device SpeechService partial/final), VAD gates when to open and close it; when a server VAD exists (Realtime), the client VAD only drives barge-in and the indicator.
- Barge-in: on `child_speech_started` during `aliz_speaking` → `Voice.stop()`, cancel the provider response (`transport.cancel()`), `set_speaking(false)` (mouth 0 within 120 ms), `set_expression("listening")` + turn toward the child (gesture `tilt`), flush queued audio/turns, capture the new turn with the correct context. No overlapping replies; cancelled audio is never replayed. Echo control: the mic is gated against playback — while Aliz speaks, barge-in requires level > playback-echo estimate + margin for ≥ 200 ms; on iOS the native plugin selects the voice-processing audio session mode (patch to `ios/speech_plugin/src`, lead rebuilds); barge-in is never disabled to hide an echo bug.
- Transports (`game/scripts/tutor/voice/transports/`): `RealtimeTransport` interface (`connect_session(token)`, `send_audio(pcm)`/`send_text(text)`, `cancel()`, `close()`, signals `response_text_delta`, `response_audio_delta`, `response_done(turn)`, `input_transcript(text)`, `error`), `MockRealtimeTransport` (deterministic, synthetic: streams a scripted TutorTurn as text deltas plus an audio-like envelope; used by all tests and the offline demo), `OpenAIRealtimeTransport` (WebSocket to the official Realtime API using the CURRENT documented event names fetched from the docs today — cite them in `docs/ALIZ_TUTOR_REALTIME.md`; ephemeral client secret from the backend `POST /api/v1/tutor/realtime/token`; flag-gated; never holds a permanent key; untested live here because no key exists).
- Offline demo (always available): hands-free with the on-device recogniser (SpeechService) + client VAD + `ScriptedConversationProvider` + the voice pack / device TTS. This is what runs on the Mac and on device today.

### Lesson engine additions (Agent A)
Step kind `choose` (Aliz asks "What would you like to learn today?"; expectedAnswers map to `subjectId`/`lessonId`; routes into that lesson), step kind `sound` ("Can you make a cat sound?" expects onomatopoeia synonyms: meow/miaow/mew), reaction fields on steps `{gesture, sfx, alizSound}` (Aliz laughs, claps and says "Meow!"), and `handle_interjection(transcript) -> Dictionary` for barge-in topic switches ("Wait! I want a dog!" → jump to the dog item in the current lesson or to the animals lesson; returns `{handled, lessonAction, line}`). Owner's example dialogue is the acceptance script.

### Aliz states (Agent C)
Add `interrupted` (stop mouth, turn toward camera, listening face within 200 ms), `explaining` (point + small nods while speaking), `celebrating` (clap + happy), keep blinking in every state; expressions, mouth and gestures on separate layers so they never conflict.

### Backend (Agent D)
`POST /api/v1/tutor/realtime/token` (ephemeral client secret per the official docs; DEV_MODE returns a mock token; quota session is created alongside; server-side usage from audio seconds reported by the transport's server events, never the client timer), `docs/ALIZ_TUTOR_REALTIME_EVALUATION.md` (Realtime vs STT→LLM→TTS on latency, cost, interruption, transcripts, lesson control, safety controls, platform compatibility, with cited current prices/docs).

### Settings (Agent F)
`handsFreeMode` (default on), `aiVoiceId` (configured list, default the cheerful youthful female preset name from the voice evaluation; on-device fallback), child learning history view (read-only list of completed lessons and stars) next to "Delete learning history".
