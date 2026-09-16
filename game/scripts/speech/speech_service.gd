## Autoload facade for speech recognition. Gameplay code depends only on this
## API — never on a concrete backend or native plugin.
##
## Backend selection:
##   1. Native iOS plugin singleton present & available -> IosSpeechBackend
##   2. Otherwise, iOS export target without the plugin  -> unavailable
##      (never fake a recognition result on-device)
##   3. Otherwise (editor/macOS/desktop/etc.)             -> MockSpeechBackend
##
## `recognition_failed` is never fatal; touch gameplay must stay fully
## playable regardless of backend state.
extends Node

signal availability_changed(available: bool)
signal permission_result(granted: bool)
signal listening_started()
signal listening_stopped()
signal recognized(text: String)
signal recognition_failed(reason: String)

var _backend: SpeechBackend = null
var _backend_name: String = "unavailable"


func _ready() -> void:
	_select_backend()
	# Announce initial state so UI can reflect it without polling.
	availability_changed.emit(is_available())


func is_available() -> bool:
	if not _speech_enabled():
		return false
	return _backend != null and _backend.is_available()


func has_permission() -> bool:
	return _backend != null and _backend.has_permission()


func request_permission() -> void:
	if _backend == null:
		permission_result.emit(false)
		return
	_backend.request_permission()


func start_listening(locale: String = "en-US") -> void:
	if not is_available():
		recognition_failed.emit("unavailable")
		return
	_backend.start_listening(locale)


func stop_listening() -> void:
	if _backend != null:
		_backend.stop_listening()


func is_listening() -> bool:
	return _backend != null and _backend.is_listening()


func get_backend_name() -> String:
	return _backend_name


func _select_backend() -> void:
	# IMPORTANT: on iOS, pick IosSpeechBackend whenever the native singleton
	# is present at all — NOT only when its is_available() happens to be
	# true at this exact instant. `_select_backend()` runs once, at
	# `_ready()`, typically within the first frame of the app; but the
	# native SFSpeechRecognizer's `isAvailable`/`supportsOnDeviceRecognition`
	# state can genuinely still be settling at that moment (it is a
	# KVO-observed property, not guaranteed true immediately after
	# construction), and no permission has been requested yet either. If we
	# gated backend *selection* on a single early availability snapshot, a
	# transient/early `false` would permanently downgrade this session to
	# the inert no-op `SpeechBackend` for the app's entire lifetime — even
	# after the recognizer becomes available and the user grants permission
	# — because nothing ever re-runs `_select_backend()`. That was a real
	# bug: it made speech permanently non-functional on-device regardless of
	# how correctly the native plugin itself behaved.
	#
	# `is_available()` below is still checked live (fresh call into the
	# native singleton) every time gameplay code calls
	# `SpeechService.is_available()`, so this fix does not weaken the
	# "unavailable" reporting contract — it only stops baking in a one-time,
	# possibly-premature snapshot as a permanent decision.
	if Engine.has_singleton(IosSpeechBackend.SINGLETON_NAME):
		_set_backend(IosSpeechBackend.new(), "ios")
		return

	if OS.has_feature("ios"):
		# Real iOS device/export without the native plugin present.
		# Never substitute the mock here — report unavailable honestly.
		_set_backend(SpeechBackend.new(), "unavailable")
		return

	_set_backend(MockSpeechBackend.new(), "mock")


func _set_backend(backend: SpeechBackend, backend_name: String) -> void:
	_disconnect_backend_signals()
	_backend = backend
	_backend_name = backend_name
	_connect_backend_signals()


func _connect_backend_signals() -> void:
	if _backend == null:
		return
	_backend.availability_changed.connect(_on_availability_changed)
	_backend.permission_result.connect(_on_permission_result)
	_backend.listening_started.connect(_on_listening_started)
	_backend.listening_stopped.connect(_on_listening_stopped)
	_backend.recognized.connect(_on_recognized)
	_backend.recognition_failed.connect(_on_recognition_failed)


func _disconnect_backend_signals() -> void:
	if _backend == null:
		return
	if _backend.availability_changed.is_connected(_on_availability_changed):
		_backend.availability_changed.disconnect(_on_availability_changed)
	if _backend.permission_result.is_connected(_on_permission_result):
		_backend.permission_result.disconnect(_on_permission_result)
	if _backend.listening_started.is_connected(_on_listening_started):
		_backend.listening_started.disconnect(_on_listening_started)
	if _backend.listening_stopped.is_connected(_on_listening_stopped):
		_backend.listening_stopped.disconnect(_on_listening_stopped)
	if _backend.recognized.is_connected(_on_recognized):
		_backend.recognized.disconnect(_on_recognized)
	if _backend.recognition_failed.is_connected(_on_recognition_failed):
		_backend.recognition_failed.disconnect(_on_recognition_failed)


func _on_availability_changed(available: bool) -> void:
	availability_changed.emit(available)


func _on_permission_result(granted: bool) -> void:
	permission_result.emit(granted)


func _on_listening_started() -> void:
	listening_started.emit()


func _on_listening_stopped() -> void:
	listening_stopped.emit()


func _on_recognized(text: String) -> void:
	recognized.emit(text)


func _on_recognition_failed(reason: String) -> void:
	recognition_failed.emit(reason)


## Reads `speechEnabled` from SaveService defensively — SaveService is
## authored concurrently and must never be assumed to exist.
func _speech_enabled() -> bool:
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null and save_service.has_method("get_setting"):
		var value = save_service.call("get_setting", "speechEnabled", true)
		return bool(value)
	return true
