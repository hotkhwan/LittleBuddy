extends "res://scripts/tutor/voice/transports/realtime_transport.gd"

## CloudRealtimeTransport -- a WebSocket client for the vendor's Realtime
## speech-to-speech API, driven entirely by what OUR backend hands out.
## UNTESTED LIVE: no key exists on this machine; the mock transport carries
## every test. Event names and flow follow the vendor's docs as fetched on
## 2026-09-20 and cited in `docs/ALIZ_TUTOR_REALTIME.md`.
##
## ## What the game holds, and what it never holds
##
## The client never names the vendor, a model, a voice id, a hostname or an
## auth header. All of that arrives in ONE response from the backend's
## `POST /api/v1/tutor/realtime/token` (DEV_MODE: a mock token), shaped:
##
##   {"clientSecret": {"value": "ek_...", "expiresAt": 1756310470},
##    "wsUrl": "<the vendor's wss URL with ?model=...>",
##    "subprotocols": ["realtime", "<insecure-key subprotocol prefix>.<ek_...>"],
##    "headers": [],                       -- alternative to subprotocols
##    "sessionUpdate": {"type": "session.update", "session": {...}},
##    "quotaSessionId": "...", "expiresInSeconds": 600}
##
## and is passed straight through: URL, subprotocols/headers, and the first
## `session.update` payload (session type, audio formats, turn_detection,
## voice, instructions). The ephemeral secret lives in memory for the
## session and is never logged or persisted.
##
## ## Flow
##
##   request_token(parentToken, lessonId, clientId)
##                            -> POST TutorFlags.backend_url() + TOKEN_PATH
##                               (our backend, plain HTTP client, 8 s) ->
##                               `token_ready(token)` or `error`
##   connect_session(token)   -> WebSocketPeer.connect_to_url(wsUrl, TLS)
##   open                     -> send token.sessionUpdate; wait `session.created`
##                               / `session.updated` -> `connected`
##   send_text(text, ctx)     -> `conversation.item.create` (role user,
##                               input_text) + `response.create`
##   send_audio(pcm)          -> `input_audio_buffer.append` {audio: base64}
##                               (no PCM source in the game today)
##   server streams           -> `response.output_audio_transcript.delta` /
##                               `response.output_text.delta` -> text deltas;
##                               `response.output_audio.delta` -> audio delta
##                               (RMS of the PCM16 chunk as the envelope);
##                               `input_audio_buffer.speech_started` ->
##                               `server_speech_started`;
##                               `conversation.item.input_audio_transcription.completed`
##                               -> `input_transcript`; `response.done` ->
##                               `response_done(turn)` where the turn is the
##                               accumulated transcript VALIDATED plus the
##                               lesson action the LessonEngine decided locally
##                               (a model never owns progression); `error` ->
##                               `error(code, message)`.
##   cancel()                 -> `response.cancel` (+ `conversation.item.truncate`
##                               for the item being played) and the chunks not
##                               yet played are dropped -- WebSocket clients own
##                               playback, so truncation is the client's job.
##
## ## Gate
##
## `flag_enabled()` (TutorFlags.cloud_enabled()) is read before any socket is
## constructed -- the privacy guard proves the source order -- and there is no
## test override here: with the flag off `connect_session()` refuses.
## Playback of the returned audio is not implemented in this file (the audio
## bytes are measured for the envelope and dropped); wiring them to an
## AudioStreamGenerator on the "Voice" bus is the follow-up once a live key
## and the backend endpoint exist.

const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

signal token_ready(token: Dictionary)

const TOKEN_PATH: String = "/api/v1/tutor/realtime/token"
const TOKEN_TIMEOUT_SECONDS: float = 8.0
const MAX_TEXT_CHARS: int = 500
const CONNECT_TIMEOUT_SECONDS: float = 8.0
const RESPONSE_TIMEOUT_SECONDS: float = 12.0


## THE gate, before any primitive appears below.
static func flag_enabled() -> bool:
	return TutorFlags.cloud_enabled()


var _socket = null  # WebSocketPeer; constructed only inside the guarded branch
var _http = null  # HTTPClient for the token request; same rule
var _http_state: Dictionary = {}
var _token: Dictionary = {}
var _elapsed: float = 0.0
var _response_elapsed: float = 0.0
var _connecting: bool = false
var _session_ready: bool = false
var _transcript: String = ""
var _lesson_context: Dictionary = {}
var _current_item_id: String = ""
var _played_ms: float = 0.0
var _event_serial: int = 0
var _last_error: String = ""


func transport_name() -> String:
	return "cloud_realtime"


func is_available() -> bool:
	return flag_enabled()


func last_error() -> String:
	return _last_error


## Asks OUR backend for the realtime token (the vendor address, the ephemeral
## secret and the session config all come back in it). Flag-gated; the only
## address this file ever dials for it is `TutorFlags.backend_url()`.
func request_token(parent_approval_token: String, lesson_id: String, client_id: String) -> bool:
	if not flag_enabled():
		_last_error = "cloud_disabled"
		error.emit("cloud_disabled", "the cloud tutor is off in this build")
		return false
	if not _http_state.is_empty():
		return false
	var base: String = TutorFlags.backend_url().strip_edges().trim_suffix("/")
	var scheme_end: int = base.find("://")
	if scheme_end <= 0:
		error.emit("bad_backend_url", "backend_url() is not a URL")
		return false
	var scheme: String = base.left(scheme_end).to_lower()
	var rest: String = base.substr(scheme_end + 3)
	var slash: int = rest.find("/")
	var authority: String = rest if slash < 0 else rest.left(slash)
	var prefix: String = "" if slash < 0 else rest.substr(slash)
	var host: String = authority
	var port: int = 443 if scheme == "https" else 80
	var colon: int = authority.rfind(":")
	if colon > 0:
		host = authority.left(colon)
		port = int(authority.substr(colon + 1))
	_http = HTTPClient.new()
	var err: int = _http.connect_to_host(host, port, TLSOptions.client() if scheme == "https" else null)
	if err != OK:
		_http = null
		error.emit("provider_unavailable", "backend refused: %d" % err)
		return false
	_http_state = {
		"path": prefix + TOKEN_PATH, "sent": false, "elapsed": 0.0, "bytes": PackedByteArray(),
		"body": JSON.stringify({"parentApprovalToken": parent_approval_token, "lessonId": lesson_id, "clientId": client_id}),
	}
	return true


func connect_session(token: Dictionary) -> bool:
	if not flag_enabled():
		_last_error = "cloud_disabled"
		error.emit("cloud_disabled", "the cloud tutor is off in this build")
		return false
	var url: String = String(token.get("wsUrl", "")).strip_edges()
	if url.is_empty() or not url.to_lower().begins_with("wss"):
		_last_error = "bad_token"
		error.emit("bad_token", "the token carries no secure socket address")
		return false
	if String((token.get("clientSecret", {}) as Dictionary).get("value", "")).is_empty():
		_last_error = "bad_token"
		error.emit("bad_token", "the token carries no client secret")
		return false
	_token = token.duplicate(true)
	_socket = WebSocketPeer.new()
	var protocols: PackedStringArray = PackedStringArray()
	for entry: Variant in token.get("subprotocols", []):
		protocols.append(String(entry))
	if not protocols.is_empty():
		_socket.supported_protocols = protocols
	var headers: PackedStringArray = PackedStringArray()
	for entry: Variant in token.get("headers", []):
		headers.append(String(entry))
	if not headers.is_empty():
		_socket.handshake_headers = headers
	var err: int = _socket.connect_to_url(url, TLSOptions.client())
	if err != OK:
		_last_error = "connect_failed"
		_socket = null
		error.emit("connect_failed", "socket refused: %d" % err)
		return false
	_connecting = true
	_elapsed = 0.0
	_session_ready = false
	return true


func send_audio(pcm: PackedByteArray) -> bool:
	if not _open or pcm.is_empty():
		return false
	return _send({"type": "input_audio_buffer.append", "audio": Marshalls.raw_to_base64(pcm)})


func send_text(text: String, lesson_context: Dictionary = {}) -> bool:
	if not _open or _responding:
		return false
	var line: String = text.strip_edges().left(MAX_TEXT_CHARS)
	_lesson_context = lesson_context.duplicate(true)
	_transcript = ""
	_current_item_id = ""
	_played_ms = 0.0
	_response_elapsed = 0.0
	var ok: bool = _send({
		"type": "conversation.item.create",
		"item": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": line}]},
	})
	if ok:
		ok = _send({"type": "response.create"})
	_responding = ok
	return ok


func cancel() -> void:
	if not _open or not _responding:
		return
	_send({"type": "response.cancel"})
	if not _current_item_id.is_empty():
		_send({"type": "conversation.item.truncate", "item_id": _current_item_id, "content_index": 0,
			"audio_end_ms": int(_played_ms)})
	_responding = false
	_transcript = ""
	response_cancelled.emit()


func close() -> void:
	if _http != null:
		_http.close()
		_http = null
		_http_state = {}
	if _socket != null:
		_socket.close()
		_socket = null
	_connecting = false
	_responding = false
	_token = {}
	super.close()


func advance(delta: float) -> void:
	if _http != null:
		_pump_token(delta)
	if _socket == null:
		return
	_socket.poll()
	var state: int = _socket.get_ready_state()
	match state:
		WebSocketPeer.STATE_CONNECTING:
			_elapsed += delta
			if _elapsed >= CONNECT_TIMEOUT_SECONDS:
				_last_error = "timeout"
				error.emit("timeout", "socket did not open in %.0f s" % CONNECT_TIMEOUT_SECONDS)
				close()
		WebSocketPeer.STATE_OPEN:
			if _connecting:
				_connecting = false
				_open = true
				var update: Variant = _token.get("sessionUpdate", null)
				if typeof(update) == TYPE_DICTIONARY:
					_send(update)
			while _socket != null and _socket.get_available_packet_count() > 0:
				var packet: PackedByteArray = _socket.get_packet()
				if _socket.was_string_packet():
					_handle_event(packet.get_string_from_utf8())
			if _responding:
				_response_elapsed += delta
				if _response_elapsed >= RESPONSE_TIMEOUT_SECONDS:
					_responding = false
					_last_error = "timeout"
					error.emit("timeout", "no response.done in %.0f s" % RESPONSE_TIMEOUT_SECONDS)
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			var code: int = _socket.get_close_code()
			_socket = null
			var was_open: bool = _open
			_open = false
			_connecting = false
			_responding = false
			if was_open:
				closed.emit("closed:%d" % code)
			else:
				_last_error = "connect_failed"
				error.emit("connect_failed", "socket closed during handshake: %d" % code)


func _pump_token(delta: float) -> void:
	_http_state["elapsed"] = float(_http_state["elapsed"]) + delta
	if float(_http_state["elapsed"]) >= TOKEN_TIMEOUT_SECONDS:
		_finish_token(0, "", "timeout")
		return
	_http.poll()
	match _http.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			return
		HTTPClient.STATUS_CONNECTED:
			if not bool(_http_state["sent"]):
				_http_state["sent"] = true
				var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
				if _http.request(HTTPClient.METHOD_POST, String(_http_state["path"]), headers, String(_http_state["body"])) != OK:
					_finish_token(0, "", "provider_unavailable")
				return
			if _http.has_response():
				_finish_token(_http.get_response_code(), (_http_state["bytes"] as PackedByteArray).get_string_from_utf8(), "")
		HTTPClient.STATUS_BODY:
			if not _http_state.has("code"):
				_http_state["code"] = _http.get_response_code()
			var chunk: PackedByteArray = _http.read_response_body_chunk()
			if chunk.size() > 0:
				var bytes: PackedByteArray = _http_state["bytes"]
				bytes.append_array(chunk)
				_http_state["bytes"] = bytes
		HTTPClient.STATUS_DISCONNECTED:
			if _http_state.has("code"):
				_finish_token(int(_http_state["code"]), (_http_state["bytes"] as PackedByteArray).get_string_from_utf8(), "")
			else:
				_finish_token(0, "", "provider_unavailable")
		_:
			_finish_token(0, "", "provider_unavailable")


func _finish_token(code: int, text: String, transport_reason: String) -> void:
	if _http != null:
		_http.close()
		_http = null
	_http_state = {}
	if not transport_reason.is_empty():
		_last_error = transport_reason
		error.emit(transport_reason, "token request failed")
		return
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else {}
	var body: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if code < 200 or code >= 300:
		var err: Variant = body.get("error", {})
		_last_error = String((err as Dictionary).get("code", "http_%d" % code)) if typeof(err) == TYPE_DICTIONARY else "http_%d" % code
		error.emit(_last_error, "token request refused")
		return
	token_ready.emit(body)


## Server events (names per the vendor docs, see the file header).
func _handle_event(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var event: Dictionary = parsed
	var kind: String = String(event.get("type", ""))
	match kind:
		"session.created", "session.updated":
			if not _session_ready:
				_session_ready = true
				connected.emit({"transport": transport_name(), "session": String((event.get("session", {}) as Dictionary).get("id", ""))})
		"response.output_item.added":
			_current_item_id = String((event.get("item", {}) as Dictionary).get("id", ""))
		"response.output_audio_transcript.delta", "response.output_text.delta":
			var delta_text: String = String(event.get("delta", ""))
			_transcript += delta_text
			response_text_delta.emit(delta_text)
		"response.output_audio.delta":
			var bytes: PackedByteArray = Marshalls.base64_to_raw(String(event.get("delta", "")))
			_played_ms += float(bytes.size()) / 48.0  # PCM16 mono 24 kHz: 48 bytes per ms
			response_audio_delta.emit(pcm16_rms(bytes), bytes.size())
		"input_audio_buffer.speech_started":
			server_speech_started.emit()
		"conversation.item.input_audio_transcription.completed":
			input_transcript.emit(String(event.get("transcript", "")))
		"response.cancelled":
			if _responding:
				_responding = false
				response_cancelled.emit()
		"response.done":
			if _responding:
				_responding = false
				response_done.emit(build_turn(_transcript, _lesson_context))
		"error":
			var body: Dictionary = event.get("error", event)
			_last_error = String(body.get("code", "error"))
			error.emit(_last_error, String(body.get("message", "")))


## The reply as a TutorTurn: the streamed words, validated, with the lesson
## action and visual the LessonEngine decided before the request. Anything
## the model said that fails the validator becomes the safe fallback.
static func build_turn(transcript: String, lesson_context: Dictionary) -> Dictionary:
	var action: String = String(lesson_context.get("lessonAction", "retry"))
	var outcome: String = String(lesson_context.get("outcome", "unclear"))
	var candidate: Dictionary = {
		"speech": transcript.strip_edges(),
		"emotion": "happy" if outcome == "correct" else "encouraging",
		"gesture": "clap" if outcome == "correct" else "tilt",
		"visual": {"type": "none"},
		"lessonAction": action,
	}
	var asset: String = String(lesson_context.get("visualAssetId", ""))
	if not asset.is_empty():
		candidate["visual"] = {"type": "flashcard", "assetId": asset}
	return TurnValidator.coerce(candidate)


## RMS of little-endian PCM16 as a 0..1 envelope level.
static func pcm16_rms(bytes: PackedByteArray) -> float:
	var count: int = bytes.size() / 2
	if count == 0:
		return 0.0
	var sum: float = 0.0
	for i: int in range(count):
		var sample: int = bytes.decode_s16(i * 2)
		var v: float = float(sample) / 32768.0
		sum += v * v
	return clampf(sqrt(sum / float(count)), 0.0, 1.0)


func _send(event: Dictionary) -> bool:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	_event_serial += 1
	var payload: Dictionary = event.duplicate(true)
	if not payload.has("event_id"):
		payload["event_id"] = "ld_%d" % _event_serial
	return _socket.send_text(JSON.stringify(payload)) == OK
