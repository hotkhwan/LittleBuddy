# Aliz Tutor Mode — speech pipeline (Agent E)

Owner: Agent E. Binding contracts: `docs/ALIZ_TUTOR_CONTRACTS.md` (incl. the
2026-09-20 evening addendum). Tests: `game/tests/cases/test_tutor_turn.gd`,
`test_tutor_providers.gd`, `test_tutor_voice_session.gd`. Headless demo:
`game/tests/demo_tutor_voice_session.gd`.

## Pipeline

```
 microphone (native plugin, via SpeechService)      loudspeaker (Voice bus / TtsService)
        |  level (0..1)          | transcript                 ^
        v                        v                            |
   vad.gd  ---- start/end ---> OnDeviceRecognitionProvider    VoicePackSynthesisProvider
        \                        |  final(text)               ^  speak_turn(turn)
         \ barge-in              v                            |
          `--> TutorVoiceSession --> ConversationProvider --> TutorTurn (tutor_turn.gd) --'
                    |                 scripted (local)  |  backend (flag)  |  RealtimeTransport (flag / mock)
                    `--> face (set_expression / play_gesture / set_speaking / set_listening_pose), all has_method-guarded
```

Everything Aliz says is a **TutorTurn** that passed the client validator.
The **LessonEngine** alone owns progression: providers never call `advance()`;
the session applies `lessonAction` after the turn is spoken.

## Files

| File | Role |
| --- | --- |
| `game/scripts/tutor/turn/tutor_turn.gd` | Client validator, rule-for-rule mirror of `backend/src/turn_validator.js`. Shared truth table `game/content/tutor/turn_fixtures.json` (39 cases, run by `npm test` and the Godot suite). Extra fields dropped; client-only passthroughs `nextLessonId`, `nextStepId`, `wantsSfx` (safe identifiers). |
| `providers/conversation_provider.gd` | Base + phases `open / answer / timeout / together / interjection`; `lesson_context_for()` (what the backend receives). Signals `session_ready`, `turn_ready`, `provider_failed`, `lesson_routed`. |
| `providers/scripted_conversation_provider.gd` | Local, deterministic, always available. 3 phrasings per outcome chosen by `hash(lessonId:stepId)+attempt` (or `set_seed`). Choose-step routing (`switch_lesson`), sound-step reactions (gesture, `wantsSfx`, `alizSound` not doubled), barge-in through `handle_interjection()`. |
| `providers/backend_conversation_provider.gd` | Flag-gated HTTP client to `TutorFlags.backend_url()`. Sessions (parent token), turns (`Idempotency-Key = sessionId:stepId:attempt`), end. 8 s timeout. Every failure (`quota_exhausted`, `not_approved`, `provider_unavailable`, `rate_limited`, `timeout`, `session_ended`, `not_found`, `invalid_turn`, …) → `fallback_used(reason)` + the scripted turn for the SAME verdict: exactly one `turn_ready` per `submit_turn`. Sends transcript text + lesson context only. |
| `providers/speech_recognition_provider.gd` + `on_device_recognition_provider.gd` | States `start → listening → partial* → processing? → final \| retry \| unavailable`, one terminal per session, own watchdog (4 s / 6 s + 1 s), echo prevention (`begin_listening()` refused while playback; playback `started` cancels a session; a cancelled session never yields a final), hands-free `set_continuous()`. Simulation (`simulated_transcript`) refused on `OS.has_feature("mobile")`. |
| `providers/speech_synthesis_provider.gd` + `voice_pack_synthesis_provider.gd` | `speak_turn(turn, spokenLineId)`: recording via `Voice.say`/`say_text` → device voice under the pack queue → `TtsService` → paced clock. `started` fires **before** any sound; `finished` exactly once. `lip_sync_bus()` = `Voice`, `lip_sync_player()` for recordings, `platform_speech_started/finished` forwarded for the text envelope. |
| `providers/backend_synthesis_provider.gd` | Stub: `is_available()` false, no network primitive; documents the future backend TTS route (`aiVoiceId` preset). |
| `tutor_turn_ux.gd` | Per-turn face/banner state machine: listening, thinking, speaking, success, incorrect, timeout, unavailable (offline offer "Let's play with Bunny instead!"). |
| `voice/vad.gd` + `content/tutor/vad_profile_child.json` | Pure energy VAD: adaptive floor (running minimum), start ≥120 ms above floor+0.06, end after 900 ms (1600 ms for <600 ms utterances or a trailing hesitation), long pause 3000 ms, bursts <120 ms ignored, echo gate (playback estimate + 0.08 for 200 ms). |
| `voice/tutor_voice_session.gd` | Hands-free state machine (below). |
| `voice/transports/*` | `RealtimeTransport` interface, `MockRealtimeTransport`, `CloudRealtimeTransport` (see `docs/ALIZ_TUTOR_REALTIME.md`). |

## Hands-free session (`TutorVoiceSession`)

`idle → welcoming → listening → child_speaking → thinking → aliz_speaking → (interrupted → child_speaking) … → closing → ended`

* `start(lesson_id, {gatePassed: true, handsFree, locale, simulation})` — refused without the gate.
* **Capture only while** active, not muted, and in `listening / child_speaking / aliz_speaking / interrupted`. Never idle, thinking, closing, ended. `on_app_background()` ends the session; `on_app_foreground()` reopens nothing; `on_quota_expired()`, `stop()`, `mute(true)` stop capture at once. `get_input_level()` is 0 whenever nothing is captured.
* **Level sources**: `set_level_source(Callable)` (the patched native plugin's `get_input_level()`, see patches) → full hands-free with barge-in. No level source → **recogniser-driven mode**: the recogniser is re-armed after each turn, partials mark `child_speaking`, its timeout is the long pause; no barge-in (honest limitation: the mic cannot be open under Aliz's voice without a level to gate the echo). `simulate_child_audio(frames, transcript)` → the dev "simulated child audio" panel path (presets `answer`, `cough`, `pause_then_finish`, `silence`, `interrupt`).
* **Barge-in**: VAD start under the echo gate while Aliz speaks → `synth.cancel()` (Voice/TtsService stop), `transport.cancel()`, `set_speaking(false)`, `set_expression("listening")` + `tilt`, queued turns flushed, the utterance captured and submitted as `interjection`. Measured: Voice.stop and mouth 0 within 0.01 ms of detection (synchronous); detection itself is 200 ms after the child starts (the gate's hold).
* Long pause → the question again (local; never a model reply); after 2 re-prompts, "say it together" and move on. "stop" / "I'm done" / "bye" → goodbye + end.
* A transport reply streams: Aliz is `aliz_speaking` from the first delta; a barge-in mid-stream cancels the transport and the reply is never voiced.

## On-device vs cloud vs gated

| Piece | Where | Gate |
| --- | --- | --- |
| Recognition | on-device (`SpeechService` → native plugin; desktop mock; simulation on desktop only) | none — never leaves the device |
| VAD, echo gate | on-device, pure | none |
| Scripted conversation | on-device, deterministic | none — always available |
| Voice pack / device TTS | on-device | none |
| Backend conversation (`POST /api/v1/tutor/sessions/…/turns`) | cloud (our backend) | `TutorFlags.cloud_enabled()` first in source order; test override is loopback-only |
| Realtime transport (WebSocket) | cloud (vendor, address from our backend's token) | same flag; no test override; untested live |
| Backend TTS | not built | stub |

No audio ever leaves the game: the backend receives transcript text and lesson context; the realtime transport today has `send_text` only (Godot never opens a microphone; the native plugin owns it). The privacy guard (`test_tutor_privacy_guards.gd`) allowlists exactly `backend_conversation_provider.gd`, `backend_synthesis_provider.gd` and `voice/transports/cloud_realtime_transport.gd`.

## Patches for the lead (`docs/patches/`)

* `agentE_ios_speech_plugin.diff` — `set_voice_processing(bool)` (AVAudioSession `.voiceChat` + input-node voice processing while a tutor session is active, default mode restored), `is_voice_processing()`, `get_input_level()` (smoothed RMS 0..1, never audio). Lead rebuilds the plugin.
* `agentE_speech_service.diff` — `SpeechService.cancel_listening()` (ends the live session now: barge-in / playback start must not wait for the 4 s cap), `set_voice_processing()`, `get_input_level()` forwarded through `SpeechBackend` / `IosSpeechBackend`. Verified against the speech test cases.
* `agentE_backend_turn_validator.diff` — `switch_lesson`, `jump_step` in the server enum (the shared fixtures already carry them; `npm test` fails 3 shared cases until applied; the openai provider schema test needs the same two values).

## Scene binding (what `tutor_scene.gd` calls)

Unchanged names from Agent B's draft: `ScriptedConversationProvider.set_engine / begin_session / submit_turn(transcript, {phase}) / end_session / cancel`, signals `turn_ready / provider_failed` (+ `lesson_routed`); `VoicePackSynthesisProvider.speak_turn(turn, line_id) / cancel / advance / is_speaking / set_muted / voice_used`, signals `started / finished`; `TurnValidator.coerce / fallback_turn / make`. New for hands-free: `TutorVoiceSession.start/stop/mute/is_active/is_capturing/get_state/get_input_level/simulate_child_audio/set_level_source`, signals per the contract.
