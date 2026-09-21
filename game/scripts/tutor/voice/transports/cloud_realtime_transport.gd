extends "res://scripts/tutor/voice/transports/realtime_transport.gd"

## CloudRealtimeTransport -- a WebSocket client for the vendor's Realtime
## speech-to-speech API, driven entirely by what OUR backend hands out.
## UNTESTED LIVE: no key exists on this machine. Every test runs against the
## recorded event fixtures (`tests/fixtures/tutor_realtime_events.json`) and
## the deterministic mock server (`tools/tutor_mock_server/`). Event names
## follow the vendor's docs as cited in `docs/ALIZ_TUTOR_REALTIME.md`.
##
## ## What the game holds, and what it never holds
##
## The client never names the vendor, a model, a voice id, a hostname or an
## auth header. All of that arrives in ONE response from the backend's
## `POST /v1/tutor/realtime/token` (`docs/ALIZ_TUTOR_CLOUD_CLIENT.md`):
##
##   {"token": "ek_...", "expiresAt": "<ISO 8601 or unix seconds>",
##    "model": "<informational>", "url": "wss://...",
##    "subprotocols": ["realtime", "<vendor prefix>.<token>"],   -- optional
##    "headers": ["Name: value"],                                 -- optional
##    "sessionUpdate": {"type": "session.update", "session": {...}}}  -- optional
##
## and is passed straight through. The ephemeral token lives in memory for
## the session and is never logged or persisted. The previous shape
## (`clientSecret.value` + `wsUrl`) is still accepted.
##
## ## Flow
##
##   connect_session(token)   -> WebSocketPeer.connect_to_url(url) (TLS for
##                               wss; plain ws ONLY to a loopback host -- the
##                               mock server)
##   open                     -> send token.sessionUpdate if present; wait
##                               `session.created` / `session.updated` -> `connected`
##   send_text(text, ctx)     -> `conversation.item.create` (role user,
##                               input_text) + `response.create`
##   send_audio(pcm)          -> `input_audio_buffer.append` {audio: base64}
##   server streams           -> `response.output_audio_transcript.delta` /
##                               `response.output_text.delta` -> text deltas;
##                               `response.output_audio.delta` -> audio delta
##                               (RMS envelope) + `response_audio_chunk(pcm)`;
##                               `response.function_call_arguments.done` ->
##                               `tool_call(name, args)` (show_card / gesture /
##                               set_emotion, each validated, off-list dropped);
##                               `input_audio_buffer.speech_started` ->
##                               `server_speech_started`;
##                               `conversation.item.input_audio_transcription.completed`
##                               -> `input_transcript`; `response.done` ->
##                               usage recorded, then `response_done(turn)` where
##                               the turn is the accumulated transcript plus the
##                               tool-call visual/gesture, VALIDATED, with the
##                               lesson action the LessonEngine decided locally
##                               (a model never owns progression). A response
##                               made only of function calls gets its outputs
##                               back plus one `response.create` (once per turn).
##   cancel()                 -> `response.cancel` (+ `conversation.item.truncate`
##                               at the PLAYED position from the audio player)
##                               and the chunks not yet played are dropped.
##
## ## Gate
##
## `flag_enabled()` (TutorFlags.cloud_enabled()) is read before any socket is
## constructed -- the privacy guard proves the source order. The only other
## way in is `enable_for_tests()`: refused on a mobile or release build and,
## even then, only a loopback `ws://` address is dialled. `attach_test_sink()`
## opens NO socket at all: it lets the fixture test feed recorded events
## through `handle_event()` and read what would have been sent.

const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const CloudApi := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")

## Raw PCM16 mono 24 kHz bytes of one audio delta, for the playback buffer.
signal response_audio_chunk(pcm: PackedByteArray)
## A validated tool call from the model: `show_card {assetId}`, `gesture {name}`,
## `set_emotion {name}`. Anything off the allowlists never gets here.
signal tool_call(name: String, args: Dictionary)
## The `response.usage` block of each finished response, accumulated.
signal usage_updated(usage: Dictionary)
signal server_speech_stopped()

const MAX_TEXT_CHARS: int = 500
const CONNECT_TIMEOUT_SECONDS: float = 8.0
const RESPONSE_TIMEOUT_SECONDS: float = 12.0
const BYTES_PER_MS: float = 48.0  # PCM16 mono 24 kHz
const TOOL_SHOW_CARD: String = "show_card"
const TOOL_GESTURE: String = "gesture"
const TOOL_EMOTION: String = "set_emotion"
const MAX_TOOL_ROUNDS_PER_TURN: int = 1
## The server refused a response.create because the previous reply was still
## being cancelled: a lost request, not a broken socket.
const BUSY_ERROR_CODE: String = "conversation_already_has_active_response"


## THE gate, before any primitive appears below.
static func flag_enabled() -> bool:
	return TutorFlags.cloud_enabled()


var _socket = null  # WebSocketPeer; constructed only inside the guarded branch
var _sink: Callable = Callable()
var _dev_override: bool = false
var _token: Dictionary = {}
var _elapsed: float = 0.0
var _response_elapsed: float = 0.0
var _connecting: bool = false
var _session_ready: bool = false
var _transcript: String = ""
var _lesson_context: Dictionary = {}
var _current_item_id: String = ""
var _response_id: String = ""
var _received_ms: float = 0.0
var _played_ms_source: Callable = Callable()
var _event_serial: int = 0
var _last_error: String = ""
var _tool_visual: Dictionary = {}
var _tool_gesture: String = ""
var _tool_emotion: String = ""
var _pending_calls: Array[Dictionary] = []
var _call_args: Dictionary = {}
var _response_items: Array[String] = []
var _tool_rounds: int = 0
var _had_audio: bool = false
var _server_initiated: bool = false
## Responses we cancelled: their late deltas and `response.done` are ignored
## so they can never touch the turn that follows a barge-in.
var _cancelled_ids: Array[String] = []
var _usage: Dictionary = {"tokensIn": 0, "tokensOut": 0, "audioSecondsIn": 0.0, "audioSecondsOut": 0.0, "responses": 0}
var _sent: Array[Dictionary] = []


func transport_name() -> String:
	return "cloud_realtime"


func is_available() -> bool:
	return flag_enabled() or _dev_override


func last_error() -> String:
	return _last_error


func usage() -> Dictionary:
	return _usage.duplicate(true)


func had_audio_this_response() -> bool:
	return _had_audio


## True while the current response was opened by the server (server VAD).
func is_server_initiated() -> bool:
	return _server_initiated


func streamed_text() -> String:
	return _transcript


## Types (and non-audio payloads) of every client event sent; tests read it.
func sent_events() -> Array:
	return _sent.duplicate(true)


## The audio player's played position, for `conversation.item.truncate`.
func set_played_ms_source(source: Callable) -> void:
	_played_ms_source = source


## Unix seconds when the token expires, 0 when unknown.
func token_expires_unix() -> int:
	return int(_token.get("expiresUnix", 0))


## Arms the transport WITHOUT the project flag, for the headless suite only.
## Refused on a mobile or release-template build; only loopback `ws://`.
func enable_for_tests(enabled: bool = true) -> bool:
	if enabled and (OS.has_feature("mobile") or OS.has_feature("template_release")):
		_dev_override = false
		return false
	_dev_override = enabled
	return _dev_override


## Fixture mode: no socket, `sink(event)` receives what would be sent and the
## test feeds server events through `handle_event()`. Refused on mobile/release.
func attach_test_sink(sink: Callable) -> bool:
	if OS.has_feature("mobile") or OS.has_feature("template_release"):
		return false
	_sink = sink
	_open = true
	_session_ready = false
	return true


# -- lifecycle ---------------------------------------------------------------------------

func connect_session(raw_token: Dictionary) -> bool:
	if _sink.is_valid():
		# Fixture mode (attach_test_sink): no socket exists; the test feeds
		# `session.created` itself. Refused on mobile/release at attach time.
		_token = normalise_token(raw_token)
		_open = true
		_connecting = false
		_session_ready = false
		return true
	if not (flag_enabled() or _dev_override):
		_last_error = "cloud_disabled"
		error.emit("cloud_disabled", "the cloud tutor is off in this build")
		return false
	var token: Dictionary = normalise_token(raw_token)
	var url: String = String(token.get("url", ""))
	var scheme: String = _scheme_of(url)
	var host: String = _host_of(url)
	var secure: bool = scheme == "wss"
	# A plain socket is dialled only to a loopback host (the mock server) or
	# to the host of TutorFlags.backend_url() (a developer's Worker relay).
	var plain_allowed: bool = scheme == "ws" and (CloudApi.is_loopback(host) or (not host.is_empty() and host == _backend_host()))
	if url.is_empty() or not (secure or plain_allowed):
		_last_error = "bad_token"
		error.emit("bad_token", "the token carries no secure socket address")
		return false
	if String(token.get("token", "")).is_empty():
		_last_error = "bad_token"
		error.emit("bad_token", "the token carries no client secret")
		return false
	if _dev_override and not flag_enabled() and not CloudApi.is_loopback(host):
		_last_error = "bad_token"
		error.emit("bad_token", "a test-armed transport only dials loopback")
		return false
	_token = token
	_socket = WebSocketPeer.new()
	var protocols: PackedStringArray = PackedStringArray()
	for entry: Variant in token.get("subprotocols", []):
		protocols.append(String(entry))
	var headers: PackedStringArray = PackedStringArray()
	for entry: Variant in token.get("headers", []):
		headers.append(String(entry))
	if protocols.is_empty() and headers.is_empty():
		# Neither pass-through given: the ephemeral token rides the same
		# header shape the REST client uses (see cloud_tutor_api.gd's note).
		headers.append("%s: %s %s" % [CloudApi.PARENT_AUTH_HEADER, CloudApi.PARENT_AUTH_SCHEME, String(token["token"])])
	if not protocols.is_empty():
		_socket.supported_protocols = protocols
	if not headers.is_empty():
		_socket.handshake_headers = headers
	var err: int = _socket.connect_to_url(url, TLSOptions.client() if secure else null)
	if err != OK:
		_last_error = "connect_failed"
		_socket = null
		error.emit("connect_failed", "socket refused: %d" % err)
		return false
	_connecting = true
	_elapsed = 0.0
	_session_ready = false
	_response_elapsed = 0.0
	return true


func send_audio(pcm: PackedByteArray) -> bool:
	if not _open or pcm.is_empty():
		return false
	var ok: bool = _send({"type": "input_audio_buffer.append", "audio": Marshalls.raw_to_base64(pcm)})
	if ok:
		_usage["audioSecondsIn"] = float(_usage["audioSecondsIn"]) + float(pcm.size()) / (BYTES_PER_MS * 1000.0)
	return ok


func send_text(text: String, lesson_context: Dictionary = {}) -> bool:
	if not _open or _responding:
		return false
	var line: String = text.strip_edges().left(MAX_TEXT_CHARS)
	_lesson_context = lesson_context.duplicate(true)
	_reset_response()
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
	if not _response_id.is_empty():
		_cancelled_ids.append(_response_id)
		if _cancelled_ids.size() > 16:
			_cancelled_ids.pop_front()
	_send({"type": "response.cancel"})
	if not _current_item_id.is_empty():
		_send({"type": "conversation.item.truncate", "item_id": _current_item_id, "content_index": 0,
			"audio_end_ms": int(played_ms())})
	_responding = false
	_transcript = ""
	response_cancelled.emit()


func close() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_connecting = false
	_responding = false
	_session_ready = false
	_token = {}
	super.close()


## Milliseconds of the current reply the child has actually heard.
func played_ms() -> float:
	if _played_ms_source.is_valid():
		return maxf(float(_played_ms_source.call()), 0.0)
	return _received_ms


# -- the pump -----------------------------------------------------------------------------

func advance(delta: float) -> void:
	if _socket == null:
		if _open and _responding:
			_tick_response_timeout(delta)
		return
	_socket.poll()
	match _socket.get_ready_state():
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
					_handle_event_text(packet.get_string_from_utf8())
			if _responding:
				_tick_response_timeout(delta)
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			var code: int = _socket.get_close_code()
			_socket = null
			var was_open: bool = _open
			_open = false
			_connecting = false
			_responding = false
			_session_ready = false
			if was_open:
				closed.emit("closed:%d" % code)
			else:
				_last_error = "connect_failed"
				error.emit("connect_failed", "socket closed during handshake: %d" % code)


func _tick_response_timeout(delta: float) -> void:
	_response_elapsed += delta
	if _response_elapsed >= RESPONSE_TIMEOUT_SECONDS:
		_responding = false
		_last_error = "timeout"
		error.emit("timeout", "no response.done in %.0f s" % RESPONSE_TIMEOUT_SECONDS)


# -- server events -------------------------------------------------------------------------

func _handle_event_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		handle_event(parsed)


## One server event (names per the vendor docs, see the file header). Public
## so the fixture test drives the exact path a live socket takes.
func handle_event(event: Dictionary) -> void:
	var kind: String = String(event.get("type", ""))
	var response_id: String = String(event.get("response_id", (event.get("response", {}) as Dictionary).get("id", "")))
	if not response_id.is_empty() and _cancelled_ids.has(response_id):
		if kind == "response.done":
			_record_usage((event.get("response", {}) as Dictionary).get("usage", {}))
		return
	match kind:
		"session.created", "session.updated":
			if not _session_ready:
				_session_ready = true
				connected.emit({"transport": transport_name(), "session": String((event.get("session", {}) as Dictionary).get("id", ""))})
		"response.created":
			if not _responding:
				# Server-initiated (server VAD with create_response): the reply
				# streams like any other; the lesson context is empty, so the
				# validated turn carries the neutral `retry` action.
				_lesson_context = {}
				_reset_response()
				_responding = true
				_server_initiated = true
			_response_id = String((event.get("response", {}) as Dictionary).get("id", ""))
			_response_elapsed = 0.0
		"response.output_item.added":
			var item: Dictionary = event.get("item", {})
			var item_type: String = String(item.get("type", ""))
			var item_id: String = String(item.get("id", ""))
			_response_items.append(item_type)
			if item_type == "function_call":
				_call_args[item_id] = {"name": String(item.get("name", "")), "callId": String(item.get("call_id", "")), "args": ""}
			elif item_type == "message":
				_current_item_id = item_id
		"response.output_audio_transcript.delta", "response.output_text.delta":
			if not _responding:
				return  # a late delta after a cancel is never shown
			var delta_text: String = String(event.get("delta", ""))
			_transcript += delta_text
			_response_elapsed = 0.0
			response_text_delta.emit(delta_text)
		"response.output_audio.delta":
			if not _responding:
				return  # cancelled audio is never played
			var bytes: PackedByteArray = Marshalls.base64_to_raw(String(event.get("delta", "")))
			if bytes.is_empty():
				return
			_had_audio = true
			_received_ms += float(bytes.size()) / BYTES_PER_MS
			_usage["audioSecondsOut"] = float(_usage["audioSecondsOut"]) + float(bytes.size()) / (BYTES_PER_MS * 1000.0)
			_response_elapsed = 0.0
			response_audio_chunk.emit(bytes)
			response_audio_delta.emit(pcm16_rms(bytes), bytes.size())
		"response.function_call_arguments.delta":
			var item_id: String = String(event.get("item_id", ""))
			if _call_args.has(item_id):
				_call_args[item_id]["args"] = String(_call_args[item_id]["args"]) + String(event.get("delta", ""))
		"response.function_call_arguments.done":
			var item_id: String = String(event.get("item_id", ""))
			var known: Dictionary = _call_args.get(item_id, {})
			var name: String = String(event.get("name", known.get("name", "")))
			var call_id: String = String(event.get("call_id", known.get("callId", "")))
			var raw_args: String = String(event.get("arguments", known.get("args", "")))
			_apply_tool_call(name, call_id, raw_args)
		"input_audio_buffer.speech_started":
			server_speech_started.emit()
		"input_audio_buffer.speech_stopped":
			server_speech_stopped.emit()
		"conversation.item.input_audio_transcription.completed":
			input_transcript.emit(String(event.get("transcript", "")))
		"response.cancelled":
			if _responding:
				_responding = false
				response_cancelled.emit()
		"response.done":
			_on_response_done(event.get("response", {}))
		"error":
			var body: Dictionary = event.get("error", event)
			_last_error = String(body.get("code", "error"))
			if _last_error == BUSY_ERROR_CODE:
				# Our response.create raced the server's cancel of the previous
				# reply: no response follows this request. The socket is fine.
				_responding = false
			error.emit(_last_error, String(body.get("message", "")))


func _on_response_done(response: Dictionary) -> void:
	_record_usage(response.get("usage", {}))
	var status: String = String(response.get("status", "completed"))
	if not _responding:
		return
	if status == "cancelled":
		_responding = false
		response_cancelled.emit()
		return
	if status != "completed":
		_responding = false
		_last_error = "response_%s" % status
		var details: Dictionary = response.get("status_details", {})
		error.emit(_last_error, String((details.get("error", {}) as Dictionary).get("message", "")))
		return
	# A function-call-only response: hand the outputs back and let the model
	# speak, once per turn; the pending visual/gesture carry into that reply.
	if _only_function_calls() and not _pending_calls.is_empty() and _tool_rounds < MAX_TOOL_ROUNDS_PER_TURN:
		_tool_rounds += 1
		for call: Dictionary in _pending_calls:
			_send({"type": "conversation.item.create", "item": {"type": "function_call_output",
				"call_id": String(call["callId"]), "output": JSON.stringify({"ok": true})}})
		_pending_calls.clear()
		_response_items.clear()
		_send({"type": "response.create"})
		_response_elapsed = 0.0
		return
	_responding = false
	var done: Dictionary = build_turn(_transcript, _lesson_context, _tool_visual, _tool_gesture, _tool_emotion)
	response_done.emit(done)


func _only_function_calls() -> bool:
	if _response_items.is_empty():
		return false
	for item_type: String in _response_items:
		if item_type != "function_call":
			return false
	return not _had_audio and _transcript.strip_edges().is_empty()


## Tool arguments from the model, validated field by field: an asset off the
## allowlist, a gesture or emotion off its enum, or unparseable JSON is
## DROPPED (never a reason to fall back -- the words still carry the turn).
func _apply_tool_call(name: String, call_id: String, raw_args: String) -> void:
	var parsed: Variant = JSON.parse_string(raw_args) if not raw_args.strip_edges().is_empty() else {}
	var args: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var accepted: Dictionary = {}
	match name:
		TOOL_SHOW_CARD:
			var asset: String = String(args.get("assetId", args.get("asset_id", "")))
			if TurnValidator.allowed_asset_ids().has(asset):
				_tool_visual = {"type": "flashcard", "assetId": asset}
				accepted = {"assetId": asset}
		TOOL_GESTURE:
			var gesture: String = String(args.get("name", args.get("gesture", "")))
			if TurnValidator.GESTURES.has(gesture) and gesture != "none":
				_tool_gesture = gesture
				accepted = {"name": gesture}
		TOOL_EMOTION:
			var emotion: String = String(args.get("name", args.get("emotion", "")))
			if TurnValidator.EMOTIONS.has(emotion):
				_tool_emotion = emotion
				accepted = {"name": emotion}
	_pending_calls.append({"name": name, "callId": call_id})
	if not accepted.is_empty():
		tool_call.emit(name, accepted)


func _record_usage(raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var block: Dictionary = raw
	_usage["tokensIn"] = int(_usage["tokensIn"]) + int(block.get("input_tokens", 0))
	_usage["tokensOut"] = int(_usage["tokensOut"]) + int(block.get("output_tokens", 0))
	_usage["responses"] = int(_usage["responses"]) + 1
	usage_updated.emit(usage())


func _reset_response() -> void:
	_transcript = ""
	_current_item_id = ""
	_response_id = ""
	_received_ms = 0.0
	_response_elapsed = 0.0
	_tool_visual = {}
	_tool_gesture = ""
	_tool_emotion = ""
	_pending_calls.clear()
	_call_args.clear()
	_response_items.clear()
	_tool_rounds = 0
	_had_audio = false
	_server_initiated = false


# -- pure helpers ---------------------------------------------------------------------------

## The reply as a TutorTurn: the streamed words plus what the tools asked for,
## validated; the lesson action and default visual come from the engine's
## verdict. Anything that fails the validator becomes the safe fallback.
static func build_turn(transcript: String, lesson_context: Dictionary, tool_visual: Dictionary = {},
		tool_gesture: String = "", tool_emotion: String = "") -> Dictionary:
	var action: String = String(lesson_context.get("lessonAction", "retry"))
	var outcome: String = String(lesson_context.get("outcome", "unclear"))
	var candidate: Dictionary = {
		"speech": transcript.strip_edges(),
		"emotion": tool_emotion if not tool_emotion.is_empty() else ("happy" if outcome == "correct" else "encouraging"),
		"gesture": tool_gesture if not tool_gesture.is_empty() else ("clap" if outcome == "correct" else "tilt"),
		"visual": {"type": "none"},
		"lessonAction": action,
	}
	var asset: String = String(lesson_context.get("visualAssetId", ""))
	if not asset.is_empty():
		candidate["visual"] = {"type": "flashcard", "assetId": asset}
	if not tool_visual.is_empty():
		candidate["visual"] = tool_visual.duplicate(true)
	for key: String in ["nextLessonId", "nextStepId"]:
		if lesson_context.has(key):
			candidate[key] = String(lesson_context[key])
	return TurnValidator.coerce(candidate)


## `{token, url, expiresUnix, model, subprotocols, headers, sessionUpdate}`
## from either token shape the backend has used.
static func normalise_token(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"token": String(raw.get("token", "")), "url": String(raw.get("url", raw.get("wsUrl", ""))).strip_edges(),
		"model": String(raw.get("model", "")), "subprotocols": [], "headers": [], "expiresUnix": 0,
	}
	if String(out["token"]).is_empty() and typeof(raw.get("clientSecret", null)) == TYPE_DICTIONARY:
		out["token"] = String((raw["clientSecret"] as Dictionary).get("value", ""))
	for key: String in ["subprotocols", "headers"]:
		if typeof(raw.get(key, null)) == TYPE_ARRAY:
			out[key] = (raw[key] as Array).duplicate()
	if typeof(raw.get("sessionUpdate", null)) == TYPE_DICTIONARY:
		out["sessionUpdate"] = (raw["sessionUpdate"] as Dictionary).duplicate(true)
	var expires: Variant = raw.get("expiresAt", null)
	if expires == null and typeof(raw.get("clientSecret", null)) == TYPE_DICTIONARY:
		expires = (raw["clientSecret"] as Dictionary).get("expiresAt", null)
	out["expiresUnix"] = expires_unix(expires)
	return out


## Unix seconds from an ISO 8601 string, a unix number, or 0 when unknown.
static func expires_unix(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var number: float = float(value)
		return int(number / 1000.0) if number > 1.0e11 else int(number)
	if typeof(value) == TYPE_STRING:
		var text: String = String(value).strip_edges()
		if text.is_valid_int():
			return int(text)
		var iso: String = text.trim_suffix("Z")
		var dot: int = iso.find(".")
		if dot >= 0:
			iso = iso.left(dot)
		if iso.length() >= 19:
			return int(Time.get_unix_time_from_datetime_string(iso))
	return 0


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


## "wss" / "ws" / "" -- the scheme before "://", lower-cased.
static func _scheme_of(url: String) -> String:
	var at: int = url.find("://")
	return url.left(at).to_lower() if at > 0 else ""


## The host of the configured backend, for a plain-socket relay on it.
static func _backend_host() -> String:
	var parts: Dictionary = CloudApi.parse_url(TutorFlags.backend_url())
	return String(parts.get("host", ""))


static func _host_of(url: String) -> String:
	var scheme_end: int = url.find("://")
	if scheme_end < 0:
		return ""
	var rest: String = url.substr(scheme_end + 3)
	var end: int = rest.length()
	for stop: String in ["/", "?", "#"]:
		var at: int = rest.find(stop)
		if at >= 0 and at < end:
			end = at
	var authority: String = rest.left(end)
	var colon: int = authority.rfind(":")
	if colon > 0 and authority.find("]") < colon:
		return authority.left(colon)
	return authority


func _send(event: Dictionary) -> bool:
	_event_serial += 1
	var payload: Dictionary = event.duplicate(true)
	if not payload.has("event_id"):
		payload["event_id"] = "ld_%d" % _event_serial
	var kind: String = String(payload.get("type", ""))
	if kind != "input_audio_buffer.append":
		_sent.append(payload.duplicate(true))
	else:
		_sent.append({"type": kind, "bytes": Marshalls.base64_to_raw(String(payload.get("audio", ""))).size()})
	if _sink.is_valid():
		_sink.call(payload)
		return true
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _socket.send_text(JSON.stringify(payload)) == OK
