extends RefCounted

## RealtimeTransport -- the interface a streaming voice backend presents to
## `TutorVoiceSession` (`docs/ALIZ_TUTOR_CONTRACTS.md` addendum).
##
##   connect_session(token) -> bool        token: what the backend's
##                                          POST /api/v1/tutor/realtime/token returned
##   send_audio(pcm) -> bool               PCM16 mono 24 kHz bytes (no source in
##                                          the game today: Godot never opens the
##                                          microphone; the native plugin owns it)
##   send_text(text, lesson_context) -> bool   the on-device transcript + the
##                                          engine's verdict; ONE response follows
##   cancel()                              barge-in: stop the response now; what
##                                          was not yet played is never played
##   close()                               end of session
##   advance(delta)                        the pump (frame or test)
##
##   signal connected(info)                the session is open
##   signal response_text_delta(text)      streamed words (subtitle)
##   signal response_audio_delta(level, bytes)   audio-like envelope 0..1 per
##                                          chunk + its byte count (lip sync,
##                                          echo estimate); the mock synthesises
##                                          it, the cloud transport measures it
##   signal response_done(turn)            the VALIDATED TutorTurn for the reply
##   signal response_cancelled()           a cancel took effect; no `response_done`
##   signal input_transcript(text)         the server's transcript of sent audio
##   signal server_speech_started()        server-side VAD saw the child start
##   signal error(code, message)
##   signal closed(reason)
##
## Implementations: `MockRealtimeTransport` (deterministic, offline, used by
## every test and the demo) and `CloudRealtimeTransport` (flag-gated WebSocket
## to the address the backend hands out; untested live -- no key exists here).

signal connected(info: Dictionary)
signal response_text_delta(text: String)
signal response_audio_delta(level: float, bytes: int)
signal response_done(turn: Dictionary)
signal response_cancelled()
signal input_transcript(text: String)
signal server_speech_started()
signal error(code: String, message: String)
signal closed(reason: String)

const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")

var _open: bool = false
var _responding: bool = false


func transport_name() -> String:
	return "base"


func is_available() -> bool:
	return false


func is_connected_session() -> bool:
	return _open


func is_responding() -> bool:
	return _responding


func connect_session(_token: Dictionary) -> bool:
	error.emit("not_implemented", "base transport")
	return false


func send_audio(_pcm: PackedByteArray) -> bool:
	return false


func send_text(_text: String, _lesson_context: Dictionary = {}) -> bool:
	return false


func cancel() -> void:
	pass


func close() -> void:
	if _open:
		_open = false
		closed.emit("closed")


func advance(_delta: float) -> void:
	pass
