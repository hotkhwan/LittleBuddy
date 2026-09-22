## Contract for provider implementations. Implementations may use cloud or
## native capabilities, but callers depend only on this lifecycle.
class_name VoiceProvider
extends RefCounted

func provider_name() -> String:
	return "local"

func is_available() -> bool:
	return false

func start_session(_context: Dictionary) -> Error:
	return ERR_UNAVAILABLE

func interrupt(_turn_id: String) -> void:
	pass

func cancel(_turn_id: String) -> void:
	pass

func stop_session() -> void:
	pass

