## Bridges to the native Godot iOS plugin singleton "LittleBuddySpeech"
## (see ios/speech_plugin/). If the singleton is absent — e.g. running in the
## editor, on macOS, or before the native plugin is built into the Xcode
## export — this backend degrades silently to "unavailable". It never
## errors or crashes when the singleton is missing.
class_name IosSpeechBackend
extends SpeechBackend

const SINGLETON_NAME := "LittleBuddySpeech"

var _singleton: Object = null
var _is_listening_cached: bool = false


func _init() -> void:
	if Engine.has_singleton(SINGLETON_NAME):
		_singleton = Engine.get_singleton(SINGLETON_NAME)
		_connect_native_signals()


func is_available() -> bool:
	if _singleton == null:
		return false
	if _singleton.has_method("is_available"):
		return bool(_singleton.call("is_available"))
	return false


func has_permission() -> bool:
	if _singleton == null:
		return false
	if _singleton.has_method("has_permission"):
		return bool(_singleton.call("has_permission"))
	return false


func request_permission() -> void:
	if _singleton == null or not _singleton.has_method("request_permission"):
		permission_result.emit(false)
		return
	_singleton.call("request_permission")


func start_listening(locale: String = "en-US") -> void:
	if _singleton == null or not _singleton.has_method("start_listening"):
		recognition_failed.emit("unavailable")
		return
	_singleton.call("start_listening", locale)


func stop_listening() -> void:
	if _singleton == null or not _singleton.has_method("stop_listening"):
		return
	_singleton.call("stop_listening")


func is_listening() -> bool:
	return _is_listening_cached


## Hands-free tutor: forwarded to the native plugin when the binary has them
## (docs/patches/agentE_ios_speech_plugin.diff); a no-op on an older binary.
func set_voice_processing(enabled: bool) -> void:
	if _singleton != null and _singleton.has_method("set_voice_processing"):
		_singleton.call("set_voice_processing", enabled)


func get_input_level() -> float:
	if _singleton != null and _singleton.has_method("get_input_level"):
		return clampf(float(_singleton.call("get_input_level")), 0.0, 1.0)
	return 0.0


func get_backend_name() -> String:
	return "ios"


func _connect_native_signals() -> void:
	_safe_connect("permission_result", Callable(self, "_on_permission_result"))
	_safe_connect("recognized", Callable(self, "_on_recognized"))
	# Added in the 2026-09-20 plugin build; an older binary without the signal
	# is skipped by `_safe_connect`, and the game then simply waits for finals.
	_safe_connect("partial_result", Callable(self, "_on_partial_result"))
	_safe_connect("recognition_failed", Callable(self, "_on_recognition_failed"))
	_safe_connect("listening_started", Callable(self, "_on_listening_started"))
	_safe_connect("listening_stopped", Callable(self, "_on_listening_stopped"))


func _safe_connect(signal_name: String, callable: Callable) -> void:
	if _singleton == null:
		return
	if not _singleton.has_signal(signal_name):
		return
	if _singleton.is_connected(signal_name, callable):
		return
	_singleton.connect(signal_name, callable)


func _on_permission_result(granted: bool) -> void:
	permission_result.emit(granted)


func _on_recognized(text: String) -> void:
	recognized.emit(text)


func _on_partial_result(text: String) -> void:
	partial_recognized.emit(text)


func _on_recognition_failed(reason: String) -> void:
	recognition_failed.emit(reason)


func _on_listening_started() -> void:
	_is_listening_cached = true
	listening_started.emit()


func _on_listening_stopped() -> void:
	_is_listening_cached = false
	listening_stopped.emit()
