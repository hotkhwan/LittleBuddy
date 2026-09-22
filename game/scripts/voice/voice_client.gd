## Provider-neutral realtime voice transport for Godot.
##
## Audio is streamed as binary PCM16 and is never written to disk. Transcripts
## are emitted and immediately discarded. Production child audio requires both
## the remotely supplied launch flag and current-session parent consent.
class_name VoiceClient
extends Node

signal connected(provider: String)
signal disconnected(reason: String)
signal transcript_partial(turn_id: String, text: String)
signal transcript_final(turn_id: String, text: String)
signal assistant_text(turn_id: String, text: String)
signal assistant_audio(turn_id: String, pcm16: PackedByteArray, sample_rate: int)
signal turn_metrics(metrics: Dictionary)
signal fallback_requested(from_provider: String, to_provider: String, reason: String)
signal child_safe_error(message: String)

const CHILD_SAFE_ERROR := "Let's keep learning another way."
const MAX_CONTROL_BYTES := 4096
const MAX_RECONNECT_ATTEMPTS := 2

var live_child_audio_enabled := false
var parent_voice_consent := false
var synthetic_or_adult_qa := false
var _socket: WebSocketPeer
var _url := ""
var _headers := PackedStringArray()
var _provider := "local"
var _session_id := ""
var _locale := "en-US"
var _session_start_sent := false
var _active_turn_id := ""
var _pending_audio_turn_id := ""
var _pending_audio_sample_rate := 16000
var _reconnect_attempts := 0
var _intentional_close := false


func configure_gate(child_audio_enabled: bool, consent_granted: bool, qa_mode: bool = false) -> void:
	live_child_audio_enabled = child_audio_enabled
	parent_voice_consent = consent_granted
	synthetic_or_adult_qa = qa_mode


func is_allowed() -> bool:
	return synthetic_or_adult_qa or (live_child_audio_enabled and parent_voice_consent)


func connect_session(url: String, session_id: String, provider: String, headers := PackedStringArray(), locale: String = "en-US") -> Error:
	if not is_allowed():
		child_safe_error.emit(CHILD_SAFE_ERROR)
		return ERR_UNAUTHORIZED
	if not url.begins_with("wss://") or session_id.is_empty():
		return ERR_INVALID_PARAMETER
	_url = url
	_session_id = session_id
	_provider = provider
	_headers = headers
	_locale = locale
	_intentional_close = false
	return _open_socket()


func _open_socket() -> Error:
	_socket = WebSocketPeer.new()
	_session_start_sent = false
	return _socket.connect_to_url(_url, TLSOptions.client(), _headers)


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _session_start_sent:
				_session_start_sent = true
				_send_event({"type": "session.start", "sessionId": _session_id, "locale": _locale})
			while _socket.get_available_packet_count() > 0:
				_read_packet()
		WebSocketPeer.STATE_CLOSED:
			var reason := _socket.get_close_reason()
			_socket = null
			if _intentional_close:
				disconnected.emit(reason)
			elif _reconnect_attempts < MAX_RECONNECT_ATTEMPTS and is_allowed():
				_reconnect_attempts += 1
				_open_socket()
			else:
				disconnected.emit("connection_lost")
				_request_next_fallback("disconnected")


func start_turn(turn_id: String, sample_rate: int = 16000) -> Error:
	if not _can_send() or turn_id.is_empty() or sample_rate < 8000 or sample_rate > 48000:
		return ERR_UNAVAILABLE
	_active_turn_id = turn_id
	return _send_event({"type": "audio.start", "turnId": turn_id, "format": "pcm16", "sampleRate": sample_rate})


func send_audio_frame(pcm16: PackedByteArray) -> Error:
	if not _can_send() or _active_turn_id.is_empty() or pcm16.is_empty():
		return ERR_UNAVAILABLE
	# Packet data is handed directly to WebSocketPeer and never retained here.
	return _socket.send(pcm16, WebSocketPeer.WRITE_MODE_BINARY)


func end_turn() -> Error:
	if _active_turn_id.is_empty():
		return ERR_UNAVAILABLE
	var turn_id := _active_turn_id
	_active_turn_id = ""
	return _send_event({"type": "audio.end", "turnId": turn_id})


func interrupt(turn_id: String = _active_turn_id) -> Error:
	if turn_id.is_empty():
		return ERR_INVALID_PARAMETER
	_active_turn_id = ""
	return _send_event({"type": "turn.interrupt", "turnId": turn_id})


func cancel(turn_id: String = _active_turn_id) -> Error:
	if turn_id.is_empty():
		return ERR_INVALID_PARAMETER
	_active_turn_id = ""
	return _send_event({"type": "turn.cancel", "turnId": turn_id})


func close_session() -> void:
	_intentional_close = true
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_event({"type": "session.end", "sessionId": _session_id})
		_socket.close(1000, "session complete")
	_active_turn_id = ""


func _read_packet() -> void:
	var packet := _socket.get_packet()
	if _socket.was_string_packet():
		if packet.size() > MAX_CONTROL_BYTES:
			return
		_handle_event(JSON.parse_string(packet.get_string_from_utf8()))
	elif not _pending_audio_turn_id.is_empty():
		assistant_audio.emit(_pending_audio_turn_id, packet, _pending_audio_sample_rate)


func _handle_event(value: Variant) -> void:
	if not (value is Dictionary):
		return
	var event: Dictionary = value
	var event_type := String(event.get("type", ""))
	var turn_id := String(event.get("turnId", ""))
	match event_type:
		"session.ready":
			_reconnect_attempts = 0
			connected.emit(String(event.get("provider", _provider)))
		"transcript.partial": transcript_partial.emit(turn_id, String(event.get("text", "")))
		"transcript.final": transcript_final.emit(turn_id, String(event.get("text", "")))
		"assistant.text": assistant_text.emit(turn_id, String(event.get("text", "")))
		"assistant.audio":
			_pending_audio_turn_id = turn_id
			_pending_audio_sample_rate = clampi(int(event.get("sampleRate", 16000)), 8000, 48000)
		"turn.metrics":
			var metrics: Dictionary = event.get("metrics", {})
			turn_metrics.emit(metrics.duplicate())
		"fallback": fallback_requested.emit(String(event.get("from", _provider)), String(event.get("to", "local")), String(event.get("reason", "provider_unavailable")))
		# Never display provider-controlled or infrastructure error text.
		"error": child_safe_error.emit(CHILD_SAFE_ERROR)


func _send_event(event: Dictionary) -> Error:
	if not _can_send():
		return ERR_UNAVAILABLE
	return _socket.send_text(JSON.stringify(event))


func _can_send() -> bool:
	return is_allowed() and _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _request_next_fallback(reason: String) -> void:
	var next := "standard" if _provider in ["cloudflare", "gemini"] else "local"
	fallback_requested.emit(_provider, next, reason)
