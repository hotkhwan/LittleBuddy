# Aliz Tutor — realtime voice transport (Agent E)

Status 2026-09-21: **implemented, flag-gated, UNTESTED LIVE** (no vendor key
exists on this machine; **no OpenAI call was made**). The client side of the
Worker contract lives in `docs/ALIZ_TUTOR_CLOUD_CLIENT.md`; this file is the
transport's own reference. Every test runs on `MockRealtimeTransport`, on the
recorded events in `tests/fixtures/tutor_realtime_events.json`
(`test_tutor_cloud_fixtures.gd`, always) or on the mock server under
`tools/tutor_mock_server/` (`test_tutor_cloud_integration.gd`, when it is up).
Nothing in the game names the vendor, a model, a voice id, a hostname or an
auth header for a provider; all of that arrives in the backend's token
response and is passed through.

## Sources (fetched 2026-09-20)

* Realtime conversations guide — https://developers.openai.com/api/docs/guides/realtime-conversations
  (session.update example with `"type": "realtime"`, audio formats, `turn_detection`, lifecycle table of
  client/server events; interruption & truncation procedure for WebSocket clients).
* Voice activity detection guide — https://developers.openai.com/api/docs/guides/realtime-vad
  (`server_vad` / `semantic_vad`, `create_response`, `interrupt_response`).
* WebSockets connection guide — https://developers.openai.com/api/docs/guides/voice-websockets?api=realtime
  (browser-like clients: subprotocols `["realtime", "<insecure-key prefix>." + EPHEMERAL_KEY]`).
* Client secrets reference — https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets/methods/create
  (`POST /realtime/client_secrets`, `expires_after`, response `{value: "ek_…", expires_at, session}`).
* Function calling in realtime sessions — `session.tools`, `response.function_call_arguments.delta/.done`,
  `conversation.item.create {type: "function_call_output"}` then `response.create` (realtime guide, same fetch).

## Token (what the backend returns; both shapes accepted)

```json
{"token": "ek_...", "expiresAt": "2026-09-21T23:59:00Z", "model": "<informational>",
 "url": "wss://<vendor or relay>/v1/realtime?model=...",
 "subprotocols": ["realtime", "<vendor prefix>.ek_..."],
 "headers": [],
 "sessionUpdate": {"type": "session.update", "session": {"type": "realtime", "output_modalities": ["audio"],
   "audio": {"input": {"format": {"type": "audio/pcm", "rate": 24000}, "turn_detection": {"type": "semantic_vad"}},
             "output": {"format": {"type": "audio/pcm", "rate": 24000}, "voice": "..."}},
   "instructions": "...", "tools": [{"type": "function", "name": "show_card", ...}, {"type": "function", "name": "gesture", ...}]}}}
```

Legacy `{"clientSecret": {"value", "expiresAt"}, "wsUrl", ...}` still normalises
(`CloudRealtimeTransport.normalise_token`). `url` must be `wss://`; a plain
`ws://` is dialled only to a loopback host (the mock) or to the host of
`TutorFlags.backend_url()` (a developer's Worker relay). Handshake auth:
`subprotocols` pass through, else `headers` pass through, else the ephemeral
token rides the same header shape the REST client uses (see the contract doc
§1.1). The token lives in memory for the session, never logged or persisted;
its expiry is a session boundary.

## Event names used (`cloud_realtime_transport.gd`)

Client → server: `session.update` (the backend's payload), `conversation.item.create`
(`{item: {type: "message", role: "user", content: [{type: "input_text", text}]}}`), `response.create`,
`input_audio_buffer.append` (`{audio: base64 PCM16 mono 24 kHz}`), `response.cancel`, `conversation.item.truncate`
(`{item_id, content_index: 0, audio_end_ms: <played position from CloudAudioPlayer>}`),
`conversation.item.create` (`{item: {type: "function_call_output", call_id, output}}`) + `response.create`
after a function-call-only response (at most one round per turn).

Server → client: `session.created` / `session.updated` → `connected`; `response.created` (unrequested = a
server-VAD reply, played like any other); `response.output_item.added` (message item id for truncation,
function_call name/call_id); `response.output_audio_transcript.delta` / `response.output_text.delta` →
`response_text_delta`; `response.output_audio.delta` → `response_audio_chunk(pcm)` + `response_audio_delta(rms, bytes)`;
`response.function_call_arguments.delta` / `.done` → `tool_call(name, args)` (validated: `show_card {assetId}` on the
asset allowlist, `gesture {name}` / `set_emotion {name}` in their enums; anything else dropped);
`input_audio_buffer.speech_started` / `speech_stopped` → `server_speech_started` / `server_speech_stopped`;
`conversation.item.input_audio_transcription.completed` → `input_transcript`; `response.cancelled` and
`response.done {status: "cancelled"}` → `response_cancelled`; `response.done` → `usage_updated` (input/output
tokens summed) then `response_done(turn)`; `response.done {status: failed|incomplete}` and `error` →
`error(code, message)`; the error `conversation_already_has_active_response` (our `response.create` raced the
server's cancel of the previous reply) closes the request without a reply and is NOT a socket failure. Late
events of a response the client cancelled are ignored by response id.

`response_done(turn)` is the accumulated transcript plus the accepted tool
arguments, VALIDATED by `tutor_turn.gd`; `lessonAction`, the default visual
and the fallback emotion/gesture come from the LessonEngine's local verdict
(`build_turn(transcript, lessonContext, toolVisual, toolGesture, toolEmotion)`).

## What the transport does and does not do

* Does: connect with the given URL/subprotocols/headers (TLS for `wss`); send
  the backend's `session.update`; `send_text` → one response; stream text
  deltas, raw audio chunks and an RMS envelope; tool calls; usage
  (`tokensIn`, `tokensOut`, `audioSecondsIn/Out` from bytes at 48 bytes/ms);
  `cancel()` → `response.cancel` + `conversation.item.truncate` at the played
  position; 8 s connect / 12 s response timeouts → `error`.
* Playback: `CloudAudioPlayer` (`scripts/tutor/cloud/cloud_audio_player.gd`)
  plays the chunks through an `AudioStreamGenerator` on the `Voice` bus on a
  virtual clock (also headless), reports the played level for the mouth and
  `played_ms()` for truncation, and drops the queue on barge-in.
* Does not: open a microphone (Godot never does in this project; PCM would come
  from the native plugin — `CloudTutorSession.push_audio` is exercised with
  synthetic frames only), hold any permanent credential, or decide lesson
  progression.

## Gate

`flag_enabled()` (`TutorFlags.cloud_enabled()`) is read before any `WebSocketPeer`
appears in the file (the privacy guard proves the source order). With the flag
off `connect_session()` refuses with `cloud_disabled`. Two test seams exist,
both refused on a mobile or release-template build: `enable_for_tests()`
(loopback `ws://` only, for the mock server) and `attach_test_sink()` (no
socket at all; the fixture test feeds `handle_event()` and reads
`sent_events()`, where audio appears as a byte count only).
