## Base interface for a speech recognition backend.
##
## Backends NEVER touch the network and NEVER write recorded audio to disk.
## All methods are safe no-ops by default so an "unavailable" backend can be
## constructed directly (e.g. `SpeechBackend.new()`) without special-casing.
class_name SpeechBackend
extends RefCounted

signal availability_changed(available: bool)
signal permission_result(granted: bool)
signal listening_started()
signal listening_stopped()
## An interim hypothesis while still listening. Optional: a backend that only
## ever produces final results simply never emits it. Never a success on its
## own -- gameplay acts on `recognized`.
signal partial_recognized(text: String)
signal recognized(text: String)
signal recognition_failed(reason: String)
signal audio_session_changed(snapshot: Dictionary)


func is_available() -> bool:
	return false


func has_permission() -> bool:
	return false


func request_permission() -> void:
	# Default backend has nothing to grant; report denial so callers never
	# hang waiting for `permission_result`.
	permission_result.emit(false)


func start_listening(_locale: String = "en-US") -> void:
	recognition_failed.emit("unavailable")


func stop_listening() -> void:
	pass


func is_listening() -> bool:
	return false


func get_backend_name() -> String:
	return "unavailable"


## Hands-free tutor (Agent E). Optional capabilities; the base has neither.
## `set_voice_processing(true)` asks the platform for its echo-cancelled
## voice-chat audio mode while a TutorVoiceSession is active. `get_input_level()`
## is the current microphone RMS 0..1 (a number for a VAD/indicator, never
## audio), 0 when not listening or unsupported.
func set_voice_processing(_enabled: bool) -> void:
	pass


func get_input_level() -> float:
	return 0.0
