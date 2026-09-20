# Aliz Tutor: OpenAI Realtime API vs the modular STT -> LLM -> TTS pipeline

Date: 2026-09-20. Author: Agent D (backend). **Nothing here was tested live**:
this machine has no `OPENAI_API_KEY`, no audio was streamed, and no latency
was measured. Every claim is either from the official docs fetched today
(cited), from list prices fetched today (`backend/config/prices.json`), or a
labelled assumption. The backend already ships the server side of both
options (`POST /api/v1/tutor/realtime/token`, `POST /api/v1/tutor/sessions/{id}/usage`)
so the decision can be tested without more backend work.

Sources fetched 2026-09-20:
- Client secrets reference: https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets/methods/create
- Realtime guide: https://developers.openai.com/api/docs/guides/realtime
- Conversations guide (interruptions): https://developers.openai.com/api/docs/guides/realtime-conversations
- VAD guide: https://developers.openai.com/api/docs/guides/realtime-vad
- Pricing: https://developers.openai.com/api/docs/pricing
- WebSocket auth from a client (Agents SDK source, since the WebSocket guide page returned 404 today):
  https://github.com/openai/openai-agents-js/blob/main/packages/agents-realtime/src/openaiRealtimeWebsocket.ts

## The two options

**Modular (what is built and tested):** on-device speech recognition
(`SpeechService`) -> the game's deterministic `LessonEngine` decides the outcome
-> one HTTPS turn to the backend -> small text model (or the deterministic mock)
returns a validated `TutorTurn` -> bundled/on-device TTS -> face + lip sync.
Cloud is optional and flag-gated; the scripted path runs a full lesson offline.

**Realtime:** the backend mints an ephemeral client secret (`ek_...`) bound to
a quota session; the device streams microphone audio to OpenAI over WebSocket
(or WebRTC) and plays the model's audio back. The model does STT, reasoning
and TTS in one place; the backend never sees the audio.

## Comparison

| Dimension | Modular STT -> LLM -> TTS | Realtime API | Notes |
| --- | --- | --- | --- |
| **Latency (turn)** | On-device STT final ~0.3-1 s after silence + HTTPS turn (mock: ms; small model: ~1-2 s) + on-device TTS start ~0.2 s. Estimate 1.5-3 s to first word. | Designed for sub-second first audio after the user stops; VAD end-of-speech detection adds `silence_duration_ms` (default 500 ms) or the semantic classifier's wait. Estimate 0.7-1.5 s. | Neither number measured here. The realtime win is real but the modular path is already within the range small children tolerate when the face shows "thinking". |
| **Cost per 5-min session** | LLM-only (device speech): **$0.00106**; cloud STT+TTS: **$0.01606** (docs/ALIZ_TUTOR_COST_MODEL.md, A1-A5). | gpt-realtime-mini: **$0.0543**; gpt-realtime: **$0.1731** (assumptions A-RT1..A-RT6 below). | Realtime-mini is ~51x the device-speech pipeline and ~3.4x the all-cloud pipeline. Output audio is 71 % of the realtime cost. |
| **Interruption / barge-in** | None natively: mic is closed during playback by design (contract: "mic never open during playback"); a Repeat button and short lines stand in. | Native. With `turn_detection` (`server_vad` or `semantic_vad`) and `interrupt_response: true`, the server cancels the response when speech starts and emits `response.cancelled`; the client receives `input_audio_buffer.speech_started`, stops playback and sends `conversation.item.truncate` so the unplayed audio is dropped from the context. Setting `interrupt_response: false` and `create_response: false` keeps VAD but not the automatic response. Manual `response.cancel` exists for client-driven stops. | For a 3-6 year old, barge-in is double-edged: it rewards talking over Aliz and needs the mic open during playback (echo/feedback on a tablet speaker). If realtime is tried, start with `interrupt_response: false`. |
| **VAD choice** | On-device recognizer decides end of utterance. | `server_vad` "uses periods of silence to automatically chunk the audio" (`threshold` 0.5, `prefix_padding_ms` 300, `silence_duration_ms` 500, optional `idle_timeout_ms`). `semantic_vad` "uses a semantic classifier to detect when the user has finished speaking, based on the words they have uttered"; `eagerness` `low` "will let the user take their time to speak", `high` "will chunk the audio as soon as possible", `auto` = `medium`. | Children pause mid-word and mid-sentence; the backend defaults to `semantic_vad` with `eagerness: low` (env `REALTIME_TURN_DETECTION=server_vad` switches). Untested. |
| **Transcript availability** | Always: the on-device recognizer produces the transcript before anything leaves the device, and the LessonEngine grades it locally. | Optional: `session.audio.input.transcription` (`model`, `language`, `prompt`) turns on input transcription; the transcript arrives as separate events after the model may already be answering, and is a by-product, not the input the model used. | The backend requests `gpt-4o-mini-transcribe`, `language: "en"` so a transcript exists for grading and parent review; it costs extra and lags. |
| **Lesson control** | Deterministic. `LessonEngine` chooses `outcome`/`lessonAction`; the server resolves `stepId` from the lesson file; the model only phrases one beat; a strict JSON schema + `turn_validator` (enums, allowlist, 160 chars, banned words, safe fallback) gate every word. | Prompt-driven. Instructions carry the ordered steps (server-built from the lesson file, `buildRealtimeInstructions`); `tools` could expose `advance_step`/`show_card` functions and `max_output_tokens` bounds length, but there is no structured-output schema for spoken audio and no server-side validator can run before the child hears it. | This is the decisive gap for a kids' product: with realtime, safety and lesson adherence rest on the prompt and the model, not on code we test. |
| **Child-safety controls** | Every reply validated server- and client-side; transcript never persisted; only text reaches the provider; `store: false`; no user identifier sent. | Audio of the child goes to the provider; input transcription creates a text record on their side; moderation is the model's own; `tracing` should stay off; the `OpenAI-Safety-Identifier` header is "recommended, not required" and must NOT be sent (it would be a persistent identifier of a child's device). ZDR: an org-level agreement; the docs fetched today do not state realtime-specific retention. | The privacy review's gate conditions (ZDR in writing, consent record) are stricter for realtime because raw voice leaves the device. |
| **Platform compatibility (Godot 4.7)** | Works today: `HTTPRequest`, on-device speech plugin, bundled audio. | WebSocket: Godot's `WebSocketPeer` can open `wss://api.openai.com/v1/realtime?model=...`; the ephemeral key travels either in the `Authorization: Bearer ek_...` handshake header (native platforms support `handshake_headers`) or as the subprotocols `realtime`, `openai-insecure-api-key.<ek_...>` the way the official JS SDK does in browsers. Audio is base64 PCM16 at 24 kHz via `input_audio_buffer.append`; Godot captures at the mix rate (44.1/48 kHz) through `AudioEffectCapture` and must resample; playback via `AudioStreamGenerator`. WebRTC: Godot exposes `WebRTCPeerConnection` but the native implementation is a separate GDExtension (webrtc-native) and the SDP exchange endpoint is another moving part; not worth it for a first trial. | WebSocket from Godot is feasible engineering (resampling, base64 framing, jitter buffer, lip-sync from the generator's amplitude) but is several days of client work and was not attempted. |
| **Offline** | Full lesson offline (scripted provider). | Nothing works offline. | Realtime can only ever be an optional layer. |
| **Backend readiness** | Complete and tested (88 tests). | Token minting, quota-bounded expiry, usage reports and cost accounting are implemented and unit-tested with a fake fetch; the client and the live path are not. | |

## Realtime cost assumptions (per 5-minute session)

Prices: gpt-realtime-mini audio in $10 / cached $0.30 / out $20 per 1M tokens,
text in $0.60 / cached $0.06 / out $2.40; gpt-realtime audio in $32 / cached
$0.40 / out $64, text in $4 / cached $0.40 / out $16 (pricing page, 2026-09-20).
The page does **not** state how many audio tokens a minute of audio is
(`prices.json` keeps `audioTokensPerMinute: null`), hence A-RT1.

| # | Assumption | Value |
| --- | --- | --- |
| A-RT1 | Audio token rate | 10 tokens/s input, 20 tokens/s output. Derived from OpenAI's earlier published per-minute equivalences for gpt-4o-realtime ($0.06/min at $100/M in; $0.24/min at $200/M out); not on today's page, so treat as +/-50 %. |
| A-RT2 | Responses per 5-min session | 12 (same as A1 in the cost model) |
| A-RT3 | Child speech committed per turn | 7.5 s -> 75 input audio tokens |
| A-RT4 | Aliz speech per turn | 8 s -> 160 output audio tokens |
| A-RT5 | Instructions (lesson steps) | 900 text tokens, cached after the first response |
| A-RT6 | Output text (assistant transcript) | 40 tokens per response |
| A-RT7 | Context growth | each response re-reads the whole conversation as cached input: sum over 12 turns = 15,510 cached audio tokens; `truncation: "auto"` may reduce this |

Derived: new audio in 900, cached audio in 15,510, audio out 1,920, text in
900 + 9,900 cached, text out 480 tokens.

| | gpt-realtime-mini | gpt-realtime |
| --- | --- | --- |
| audio in (new) | $0.0090 | $0.0288 |
| audio in (cached history) | $0.0047 | $0.0062 |
| audio out | $0.0384 | $0.1229 |
| text in + cached | $0.0011 | $0.0076 |
| text out | $0.0012 | $0.0077 |
| **per session** | **$0.0543** | **$0.1731** |
| per free user-month (9 sessions, A7) | $0.49 | $1.56 |
| per Family Club user-month (45 sessions, A8 x A9) | $2.45 | $7.79 |
| 1,000 users, free only | $489 | $1,558 |
| 1,000 users, 10 % Family Club | $685 | $2,181 |
| 10,000 users, 10 % Family Club | $6,847 | $21,814 |

Same rows for the modular pipeline (cost model doc): 1,000 users at 10 %
Family Club = **$13.38** (device speech) or **$202** (all-cloud speech).
Realtime does not benefit from the instructional-turn cache (every session is
a live conversation), so the flat-cost effect that makes the modular LLM
almost free at scale does not apply.

Quota binding: the backend charges realtime sessions by its own clock,
bounded by the token expiry (remaining quota + 30 s), so the worst case per
free user is 330 s/day regardless of what the client reports; the daily turn
cap also counts each mint and each usage report. Budget guard applies.

## Recommendation for V1

**Ship the modular pipeline; do not put the Realtime API in front of a child in V1.**

1. Safety and lesson adherence are enforced in code on the modular path
   (schema + validator + server-side lesson authority + fallback turn). On
   the realtime path they are enforced by a prompt, after the fact, with the
   child's raw voice at the provider. For a Kids-Category app that is the wrong
   trust model to start with.
2. Cost: ~50x per session against device speech; at 10,000 users the
   difference is roughly $6,700/month (mini) to $21,000/month (full) versus
   ~$134, and the cache cannot help.
3. Offline-first: the scripted tutor is the product when the flag is off;
   realtime adds nothing there.
4. Client engineering (24 kHz resampling, base64 audio framing over
   `WebSocketPeer`, jitter buffering, lip sync from the generator) is real work
   that has not started, while the modular client pieces exist.

**Keep the door open:** the backend endpoints are in place. If a later
experiment is wanted, run it as a Family Club-only, DEV/TestFlight-only
feature behind its own flag with: `gpt-realtime-mini`, WebSocket transport,
`server_vad` or `semantic_vad` with `interrupt_response: false` (mic gated by
the game, honouring "mic never open during playback"), input transcription on
for grading, `tools` for `advance_step` so the lesson state stays in the game,
no safety identifier header, ZDR confirmed in writing, and the quota-bounded
token expiry as the hard stop. Measure real latency and real token counts on
device before trusting any number in this document.
