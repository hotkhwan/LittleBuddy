# Aliz Tutor — realtime voice transport (Agent E)

Status 2026-09-20: **implemented, flag-gated, UNTESTED LIVE** (no vendor key
exists on this machine; the backend token endpoint `POST
/api/v1/tutor/realtime/token` is Agent D's follow-up). Every test runs on
`MockRealtimeTransport`. Nothing in the game names the vendor, a model, a
voice id, a hostname or an auth header; all of that arrives in the backend's
token response and is passed through.

## Sources (fetched 2026-09-20)

* Realtime conversations guide — https://developers.openai.com/api/docs/guides/realtime-conversations
  (session.update example with `"type": "realtime"`, `"model": "gpt-realtime-2.1"`,
  `audio.input.format {"type":"audio/pcm","rate":24000}`, `audio.input.turn_detection {"type":"semantic_vad"}`,
  `audio.output.voice "marin"`; lifecycle table of client/server events; interruption &
  truncation procedure for WebSocket clients; push-to-talk with `turn_detection: null`).
* Voice activity detection guide — https://developers.openai.com/api/docs/guides/realtime-vad
  (`server_vad` with `threshold`, `prefix_padding_ms`, `silence_duration_ms`; `semantic_vad` with `eagerness`).
* WebSockets connection guide — https://developers.openai.com/api/docs/guides/voice-websockets?api=realtime
  (`wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1`; server: `Authorization: Bearer <key>` header;
  browser-like clients: subprotocols `["realtime", "openai-insecure-api-key." + EPHEMERAL_KEY]`).
* Client secrets reference — https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets/methods/create
  (`POST /realtime/client_secrets`, `expires_after {anchor:"created_at", seconds 10..7200, default 600}`,
  response `{value: "ek_…", expires_at, session}`).
* Getting started — https://developers.openai.com/api/docs/guides/realtime (`response.output_text.delta`,
  `response.output_audio.delta`, `response.output_audio_transcript.delta`).

## Event names used (`cloud_realtime_transport.gd`)

Client → server: `session.update` (payload supplied by the backend token), `conversation.item.create`
(`{item:{type:"message", role:"user", content:[{type:"input_text", text}]}}`), `response.create`,
`input_audio_buffer.append` (`{audio: base64}`), `response.cancel`, `conversation.item.truncate`
(`{item_id, content_index: 0, audio_end_ms}`).

Server → client: `session.created` / `session.updated` → `connected`; `response.output_item.added` (item id for
truncation); `response.output_audio_transcript.delta` / `response.output_text.delta` → `response_text_delta`;
`response.output_audio.delta` → `response_audio_delta(rms, bytes)`; `input_audio_buffer.speech_started` →
`server_speech_started`; `conversation.item.input_audio_transcription.completed` → `input_transcript`;
`response.cancelled` → `response_cancelled`; `response.done` → `response_done(turn)`; `error` → `error(code, message)`.

## Token flow (what the backend must return)

`CloudRealtimeTransport.request_token(parentApprovalToken, lessonId, clientId)` → `POST TutorFlags.backend_url() + /api/v1/tutor/realtime/token`
(8 s timeout) → `token_ready(token)`:

```json
{"clientSecret": {"value": "ek_...", "expiresAt": 1756310470},
 "wsUrl": "wss://.../v1/realtime?model=...",
 "subprotocols": ["realtime", "<insecure-key prefix>.ek_..."],
 "headers": [],
 "sessionUpdate": {"type": "session.update", "session": {"type": "realtime", "output_modalities": ["audio"], "audio": {"input": {"format": {"type": "audio/pcm", "rate": 24000}, "turn_detection": {"type": "semantic_vad"}}, "output": {"format": {"type": "audio/pcm", "rate": 24000}, "voice": "..."}}, "instructions": "..."}},
 "quotaSessionId": "...", "expiresInSeconds": 600}
```

The backend creates the vendor client secret server-side (its own key never reaches the game), mints the session config
(instructions, voice preset from `aiVoiceId`, VAD mode), and opens the quota session alongside; usage is charged from the
vendor's server events, never the client's timer.

## What the transport does and does not do today

* Does: connect with the given URL/subprotocols/headers over TLS; send the backend's `session.update`; `send_text`
  (the on-device transcript + the LessonEngine's verdict) → one response; stream text deltas and an RMS envelope;
  `response.done` → a validated `TutorTurn` whose `lessonAction`/visual come from the engine's verdict (a model never owns
  progression); `cancel()` → `response.cancel` + `conversation.item.truncate`, remaining deltas dropped; 8 s connect / 12 s
  response timeouts → `error`; the session falls back to the scripted provider on any `error`.
* Does not (yet): send microphone audio (Godot never opens a microphone in this project; PCM would come from the native
  plugin), play the returned audio bytes (measured for the envelope and dropped; wiring to an `AudioStreamGenerator` on the
  `Voice` bus is the follow-up once a live key exists), or hold any permanent credential.

## Gate

`flag_enabled()` (`TutorFlags.cloud_enabled()`) is read before any `HTTPClient` / `WebSocketPeer` appears in the file
(the privacy guard proves the source order); there is **no** test override in this transport. With the flag off,
`request_token()` and `connect_session()` refuse with `cloud_disabled`.
