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
signal recognized(text: String)
signal recognition_failed(reason: String)


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
