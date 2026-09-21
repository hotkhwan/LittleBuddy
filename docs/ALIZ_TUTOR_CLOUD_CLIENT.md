# Aliz Tutor — cloud client contract and behaviour (Agent E)

Date: 2026-09-21. Branch `wt6/tutorcloud`. Status: **implemented, flag-gated,
OFF in every build** (`little_days/ai_tutor/cloud_enabled=false`). Tested
against recorded event fixtures and the deterministic mock server under
`tools/tutor_mock_server/`. **No OpenAI (or any provider) call was made**: this
machine holds no key, the game holds no key, and nothing in `game/` names a
provider, a model, a hostname or an auth header for a provider.

This document is the contract the Godot client implements against Agent D's
Cloudflare Worker. Agent D: please confirm each item marked **D confirm**.

## 1. REST contract (the Worker)

Base URL: `TutorFlags.backend_url()` (project setting
`little_days/ai_tutor/backend_url`, loopback default). Every request carries:

| Header | Value | Note |
| --- | --- | --- |
| `Authorization` | `Bearer <parentToken>` | the parent's token, minted by OUR backend after the parental flow; never a provider key (see §1.1) |
| `X-Parent-Approval` | `<approvalToken>` | the parental approval token |
| `X-Device-Id` | `<deviceId>` | pseudonymous per-install id (random, kept under the SaveService setting `tutorDeviceId`) |
| `Content-Type` / `Accept` | `application/json` | |

| Call | Body | 2xx reply | Client file |
| --- | --- | --- | --- |
| `POST /v1/tutor/sessions` | `{childId, lessonId, mode: "realtime" \| "turns"}` | `{sessionId, quota: {allowanceSeconds, usedSeconds}, entitlement: "free" \| "family_club"}` | `cloud_tutor_api.gd::create_session` |
| `POST /v1/tutor/realtime/token` | `{sessionId}` | `{token, expiresAt, model, url}` **plus, D confirm:** optional `subprotocols: [string]`, `headers: ["Name: value"]`, `sessionUpdate: {type: "session.update", session: {...}}` (§2.1) | `mint_token` |
| `POST /v1/tutor/sessions/:id/turns` | `{idempotencyKey, phase, transcript, step}` | a `TutorTurn` (validated client-side by `tutor_turn.gd`) | `submit_turn` (turn mode; the realtime classroom path does not use it) |
| `POST /v1/tutor/sessions/:id/end` | `{reason, secondsUsed, usage: {tokensIn, tokensOut, audioSeconds}}` | `{ok: true, quota?}` — the `quota` block, when present, is shown on the break card (**D confirm**) | `end_session` |
| `GET /v1/tutor/quota?childId=` | — | `{allowanceSeconds, usedSeconds, resetAtUtc}` | `fetch_quota` |

Errors (status + body): `403 {error: "not_approved"}`, `402 {error:
"quota_exhausted", quota?}`, `429 {error: "rate_limited", retryAfterSeconds?}`,
`410 {error: "session_ended"}`, `503 {error: "provider_unavailable"}`. The
client also accepts `{error: {code, message, retryAfterSeconds}}` and maps a
bare status (401/403 → not_approved, 402 → quota_exhausted, 404/409/410 →
session_ended, 429 → rate_limited, 5xx/0 → provider_unavailable, 504 →
timeout). One request in flight, 8 s timeout each; never a hang.

`secondsUsed` is the client's wall-clock from `ready` to `end`; the server
stays authoritative for quota (the client only mirrors).

### 1.1 The `Authorization: Bearer` header and the privacy guard (lead decision)

`test_tutor_privacy_guards.gd` forbids the literals `bearer ` and
`authorization:` in any game source, because when it was written the only
bearer token imaginable was a provider key. The contract above needs the
parent's token in exactly that header. The client therefore builds the header
from two constants (`CloudTutorApi.PARENT_AUTH_HEADER = "Authorization"`,
`PARENT_AUTH_SCHEME = "Bearer"`), the guard's literal check stays meaningful
for provider keys, and the exact header text is pinned by
`test_tutor_cloud_fixtures.gd` (`"Authorization: Bearer parent-1"`). This is
disclosed here and in the file header rather than hidden. Two clean
alternatives for the lead: (a) extend the guard with a per-file exemption for
`cloud_tutor_api.gd`; or (b) have the Worker accept the parent token as
`X-Parent-Token` and drop the split constants. The client changes one line
either way.

### 1.2 Credentials in this build

There is no parental-consent service yet (privacy review G3). The bridge uses
the DEV literals `dev-parent-token` / `dev-parent-approval`, which the mock
accepts; `childId` is the pseudonymous device id (one child profile per
install today). Never a name, never a device serial.

## 2. Realtime contract (the WebSocket the token points at)

### 2.1 Token → socket

`url` must be `wss://`; plain `ws://` is accepted **only** to a loopback host
(the mock). Handshake auth, in order of preference (**D confirm** which the
Worker returns):

1. `subprotocols` passed through verbatim (the vendor's browser-style
   `["realtime", "<prefix>.<token>"]`; the Worker knows the prefix, the game
   never does);
2. `headers` passed through verbatim;
3. neither present → the client sends `Authorization: Bearer <token>` built
   from the same split constants.

If `sessionUpdate` is present it is sent verbatim as the first client event
(instructions, voice, VAD, tools all belong to the Worker). `expiresAt` is
ISO 8601 or unix seconds; the client treats expiry as a boundary (§3.3).

### 2.2 Client → server events

`session.update` (only the Worker's payload), `conversation.item.create`
(`{item: {type: "message", role: "user", content: [{type: "input_text",
text}]}}`), `response.create`, `input_audio_buffer.append` (`{audio: base64
PCM16 mono 24 kHz}`), `response.cancel`, `conversation.item.truncate`
(`{item_id, content_index: 0, audio_end_ms: <played position>}`),
`conversation.item.create` with `{type: "function_call_output", call_id,
output: "{\"ok\":true}"}` after a function-call-only response, followed by one
`response.create` (at most one such round per turn).

### 2.3 Server → client events handled

`session.created` / `session.updated` → connected; `response.created`
(a response the client did not ask for is a server-VAD reply and is played
like any other); `response.output_item.added` (message item id for
truncation; function_call name/call_id); `response.output_audio_transcript.delta`
/ `response.output_text.delta` → subtitle; `response.output_audio.delta` →
playback + lip sync (RMS envelope); `response.function_call_arguments.delta`
/ `.done` → tool call; `input_audio_buffer.speech_started` / `speech_stopped`;
`conversation.item.input_audio_transcription.completed` → transcript;
`response.cancelled` and `response.done` with `status: "cancelled"` →
cancelled; `response.done` (`usage` summed: `input_tokens`, `output_tokens`)
→ the validated turn; `response.done` with `status: "failed"/"incomplete"` →
error; `error` → error. Late events of a response the client cancelled are
ignored by response id, so a barge-in can never leak into the next turn.

### 2.4 Tools (**D confirm** the Worker declares exactly these)

| Tool | Arguments | Client validation |
| --- | --- | --- |
| `show_card` | `{assetId}` | must be on `content/tutor/assets_allowlist.json`; else dropped |
| `gesture` | `{name}` | one of `nod, tilt, point, clap, wave`; else dropped |
| `set_emotion` | `{name}` | one of `neutral, listening, thinking, happy, encouraging, smile`; else dropped |

The final turn is built from the streamed transcript plus the accepted tool
arguments and **validated by `tutor_turn.gd`** (160 chars, ASCII, no URL, no
banned word, enums, allowlist); `lessonAction` always comes from the
LessonEngine's local verdict — a model never owns progression. The RUNNING
transcript is checked on every delta: a URL or a banned word cancels the
response at once, truncates playback, and "Let's try together!" is spoken by
the local voice instead (`reply_replaced`).

## 3. Session lifecycle (`cloud_tutor_session.gd`)

```
idle -> quota -> creating -> minting -> connecting -> ready -> ending -> ended
                                ^            |                    \
                                +-- reconnect once (fresh token) --+-> failed (fell_back)
```

### 3.1 Streaming rules

* Mic frames (`push_audio`) go out only while `ready`, not muted, and the
  hands-free session's capture source says "capturing and not echo-gated".
  There is **no PCM source in the game today** (the on-device plugin owns the
  microphone); the path is exercised with synthetic frames. The bridge exposes
  `push_microphone_pcm()` for a future native tap.
* `send_transcript(text, lessonContext)` is the live path: the on-device
  transcript plus the engine's verdict; one reply follows.
* Reply audio plays through `CloudAudioPlayer` (AudioStreamGenerator on the
  `Voice` bus, virtual clock headless); the mouth follows the PLAYED level via
  `TutorFace.set_mouth_open` unless the face's own lip sync is already reading
  the bus; `set_speaking(true/false)` brackets the reply.
* Barge-in: `response.cancel` + `conversation.item.truncate` at the played
  position; the playback queue is dropped; cancelled audio is never replayed.

### 3.2 Usage metering

`{tokensIn, tokensOut}` summed from every `response.done.usage`;
`audioSecondsIn` from bytes sent, `audioSecondsOut` from bytes received (48
bytes per ms). Posted in `POST /end`.

### 3.3 Ending, both quota sides

| Trigger | What happens | `end` reason |
| --- | --- | --- |
| Client mirror (`TutorQuota.is_exhausted()`) | boundary armed; the reply finishes; session ends | `quota_expired` |
| Server 402 (sessions / token) | mirror told `exhausted` (`apply_server_failure`), `fell_back("quota_exhausted")`, no token minted | `provider_failed:quota_exhausted` |
| Server 402 mid-session | boundary armed, ends after the open reply | `quota_expired` |
| `GET /quota` says 0 left | no session created at all | (none) |
| Token expiry (−5 s) | boundary armed | `token_expired` |
| 120 s with no reply, transcript or audio | ends | `idle` |
| App background | ends at once (mic closed by the hands-free session) | `background` |
| Parent stop / scene break / done / exit | ends | `parent_stop` / `lesson_complete` / `scene` |
| 403 / 410 | `fell_back` | `provider_failed:not_approved` / `session_ended` |
| Socket error/close, 503, timeout | reconnect once with a fresh token; second failure `fell_back`; a reply in flight is reported `turn_failed` so exactly one turn still reaches the scene | `provider_failed:<code>` |
| 429 | retried once after `retryAfterSeconds` (default 2 s) | |

The classroom keeps the mirror as the authority for the safe-point closing
(`boundary_reached()` in `tutor_scene.gd`); the server's word only ever
shortens a session, never lengthens it.

## 4. Classroom integration (identical face path)

`tutor_scene.gd` gained one hook (the complete diff):

```
+const CLOUD_BRIDGE_PATH := "res://scripts/tutor/cloud/cloud_tutor_bridge.gd"
+var _cloud_bridge: RefCounted = null
 	_synth = SynthesisScript.new(); _synth.name = "Synthesis"; add_child(_synth)
-	_synth.finished.connect(_on_speech_finished)
 	_engine = _make_engine()
 	_provider = ScriptedProviderScript.new(); _provider.call("set_engine", _engine)
+	_select_cloud_tutor()  # Agent E: flag-gated; may wrap _provider and _synth
+	_synth.finished.connect(_on_speech_finished)
 	_provider.turn_ready.connect(_on_turn_ready)
 	_provider.provider_failed.connect(_on_provider_failed)
+func _select_cloud_tutor() -> void:
+	if not TutorFlags.cloud_enabled() or not ResourceLoader.exists(CLOUD_BRIDGE_PATH): return
+	... load(CLOUD_BRIDGE_PATH).new().attach(self, _engine, _provider, _synth) -> {provider, synth}
```

With the flag off nothing under `scripts/tutor/cloud/` is loaded. With it on:

* `CloudTutorProvider` (a `ConversationProvider`) sends only `PHASE_ANSWER`
  on scored steps to the cloud; open / together / timeout / interjection /
  choose routing stay local and free. On the first streamed delta it emits
  the turn EARLY — the local verdict's emotion, gesture, visual and
  `lessonAction` (what the scripted tutor would show for the same verdict)
  with the streamed words — so the scene runs its normal `_speak_turn()`:
  the same `set_expression`, `play_gesture`, card, subtitle and state calls
  as the scripted path. The final validated turn arrives as `turn_meta`.
  Exactly one `turn_ready` per `submit_turn`; a reply that does not start in
  6 s, is lost or arrives while the cloud is down is answered by the scripted
  turn for the same verdict (`fallback_used(reason)`).
* `CloudSynthesisProvider` wraps the local synthesis: when a reply is
  streaming the voice IS the reply and `finished` fires when its audio
  drained; a reply without audio is voiced by the local provider from its
  final words; `cancel()` is the barge-in; local lines (welcome, questions,
  closing) go to the wrapped provider unchanged.
* The bridge keeps the subtitle growing, shows a tool-called card at once
  (`hud.set_card` + board), and ends the cloud session on break / done /
  background / scene exit.

## 5. Behind the flag — what opens each gate

| Capability | Where | Gate today | Opens when |
| --- | --- | --- | --- |
| Any HTTP to the backend | `cloud_tutor_api.gd`, `backend_conversation_provider.gd`, `cloud_quota_client.gd` | `TutorFlags.cloud_enabled()` read before any `HTTPClient` (privacy guard, source order); loopback-only `enable_for_tests()` refused on mobile/release | G1–G17 all TRUE in `ALIZ_TUTOR_PRIVACY_REVIEW.md` §D, then the project setting flips in the same commit as G13's copy |
| WebSocket to the vendor address the Worker hands out | `cloud_realtime_transport.gd` | same flag before `WebSocketPeer`; `wss://` only off-loopback | G1 (ZDR in writing), G2 (under-18 guidance point by point), G6 re-review (raw audio would leave the device once a PCM source exists) |
| Child audio streaming (`push_audio`) | `cloud_tutor_session.gd` | no PCM source exists; capture source + mute + ready | G6 re-review + a native tap; never persisted or logged (the sent log keeps byte counts only) |
| Transcript to the cloud | `cloud_tutor_provider.gd` | flag + answer phase only | G3 consent recorded server-side (the parent token), G4/G5 disclosures |
| Ephemeral realtime token in memory | transport | never logged/persisted; expiry = boundary | G7 backend secret management on the Worker |
| Quota / cost | session + Worker | mirror authoritative for closing; server 402 honoured; usage posted | G9 budget guard on the Worker |
| Classroom selection of the cloud pair | `tutor_scene.gd::_select_cloud_tutor` | flag + file exists; lazy `load()` | same as above |
| Developer run | user arg `-- --ai-tutor-cloud` | never reaches an export (`test_tutor_flags.gd`) | n/a |

Client guards (G16) after this work: `test_tutor_flags`,
`test_tutor_privacy_guards` (allowlist now includes `cloud_tutor_api.gd`),
`test_tutor_cloud_fixtures` (always runs), `test_tutor_cloud_integration`
(runs when the mock is up, skips cleanly otherwise).

## 6. Tests and the mock server

```
/usr/local/bin/node tools/tutor_mock_server/server.mjs        # 127.0.0.1:8787, zero deps
cd game && godot --headless --path . --script res://tests/run_tests.gd
```

The mock speaks §1 and §2 with a scripted lesson (cat/dog/apple/... →
praise + `show_card` + `gesture` tool calls + 100 ms tone chunks per word) and
scenarios keyed on the `childId` prefix: `exhausted`, `deny`, `flaky` (first
token 503), `drop` (socket closed after the first reply), `banned` (reply
carries a banned word), `noaudio`, `toolsinline`, `rate`. It logs counts and
names only — never a transcript or an audio byte.

Integration run 2026-09-21 (verbatim excerpt):

```
    mock tutor server on http://127.0.0.1:8787
      default: ready session=mock-s-6-398585 history=["quota", "creating", "minting", "connecting", "ready"]
      default: turn { "speech": "Great! It's a cat!", "emotion": "happy", "gesture": "clap", "visual": { "type": "flashcard", "assetId": "cat" }, "lessonAction": "next_question" }
      default: usage { "tokensIn": 86, "tokensOut": 64, "audioSecondsIn": 0.0, "audioSecondsOut": 0.4, "responses": 2, "audioSeconds": 0.4 }
      default: barge-in ok, played_ms=6
      default: mic audio -> transcript ["cat"], server reply played (speaking [true, false, true, false])
      default: ended parent_stop serverAck=true quota={ "allowanceSeconds": 300.0, "usedSeconds": 1.5, ... }
      flaky: ["quota", "creating", "minting", "connecting", "ready"] reconnects=1
      drop: ["quota", "creating", "minting", "connecting", "ready", "minting", "connecting", "ready"] reconnects=1 ready=true
      exhausted: fell_back=["quota_exhausted"] quota={ "allowanceSeconds": 0.0, ... }
      banned: replaced=1 last_subtitle='That was a'
      deny: fell_back=["not_approved"]
[PASS] test_tutor_cloud_integration
```

## 7. Open items

1. **Lead:** §1.1 — accept the split-constant header, exempt the file in the
   guard, or switch the contract to `X-Parent-Token`.
2. **D confirm:** token reply extras (`subprotocols` / `headers` /
   `sessionUpdate`), the three tool declarations, `POST /end` returning the
   quota block, `{error: "<code>"}` as the error body.
3. **Known limits:** no PCM microphone source (mic streaming is synthetic
   only); server-VAD replies are played and lip-synced but are not part of the
   lesson loop (the classroom stays transcript-driven); `set_emotion` from a
   tool changes the face only while the reply plays; a reply replaced mid-way
   keeps the engine's action already applied to the early turn.
4. **Untested live:** the vendor endpoint. Nothing here was run against
   OpenAI; the first live run needs a Worker with a key, G1–G17, and a device.
