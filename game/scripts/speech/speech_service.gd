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

## Name the native iOS plugin registers itself under (see IosSpeechBackend).
const IOS_SINGLETON_NAME: String = "LittleBuddySpeech"

## Local-only capability snapshot, for diagnosing speech on a device where
## there is no console. Contains no audio and no transcripts.
const DIAG_PATH: String = "user://speech_diag.json"

signal availability_changed(available: bool)
signal permission_result(granted: bool)
signal listening_started()
signal listening_stopped()
## Interim hypothesis while the microphone is still open. UI may show it;
## gameplay acts only on `recognized`. Never counted, never written anywhere.
signal partial_recognized(text: String)
signal recognized(text: String)
signal recognition_failed(reason: String)

var _backend: SpeechBackend = null
var _backend_name: String = "unavailable"

## Diagnostic counters. Deliberately record only WHETHER recognition happened,
## never what was said -- a transcript of a child's speech is exactly the kind
## of derived personal data this project refuses to persist.
var _listen_count: int = 0
var _recognized_count: int = 0
var _failed_count: int = 0
var _last_failure_reason: String = ""
var _launch_count: int = 1
## The locale last requested. A capability flag, not content -- no word the child
## said is ever held here. See `describe_diagnostics()`.
var _last_locale: String = "en-US"


func _ready() -> void:
	_load_diagnostics()
	_select_backend()
	# Announce initial state so UI can reflect it without polling.
	availability_changed.emit(is_available())
	_write_diagnostics()


## Restores the counters from a previous run. Without this, every relaunch
## resets them to zero and a tester's evidence is silently destroyed -- which is
## exactly what happened the first time this was used on a device.
func _load_diagnostics() -> void:
	if not FileAccess.file_exists(DIAG_PATH):
		return
	var file := FileAccess.open(DIAG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var prev: Dictionary = parsed
	_listen_count = int(prev.get("listenCount", 0))
	_recognized_count = int(prev.get("recognizedCount", 0))
	_failed_count = int(prev.get("failedCount", 0))
	_last_failure_reason = String(prev.get("lastFailureReason", ""))
	_launch_count = int(prev.get("launchCount", 0)) + 1


## Writes a small snapshot of the speech stack to `user://speech_diag.json`.
##
## On a device there is no console to read, so this is the only way to find out
## whether the native plugin actually registered its singleton and which backend
## was chosen. Pull it with:
##   xcrun devicectl device copy from --device <UDID> \
##     --domain-type appDataContainer --domain-identifier com.pointit.littlebuddy \
##     --source Documents/speech_diag.json --destination ./speech_diag.json
##
## Local only. Contains no audio, no transcripts and no personal data -- just
## capability flags. Never uploaded.
func _write_diagnostics() -> void:
	var diag: Dictionary = {
		"platform": OS.get_name(),
		"modelName": OS.get_model_name(),
		"backend": get_backend_name(),
		"nativeSingletonPresent": Engine.has_singleton(IOS_SINGLETON_NAME),
		"isAvailable": is_available(),
		"hasPermission": has_permission(),
		"speechEnabledSetting": _speech_enabled(),
		"ttsAvailable": _tts_available(),
		"listenCount": _listen_count,
		"recognizedCount": _recognized_count,
		"failedCount": _failed_count,
		"lastFailureReason": _last_failure_reason,
		"launchCount": _launch_count,
		"writtenAt": Time.get_datetime_string_from_system(true),
	}
	var file := FileAccess.open(DIAG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(diag, "\t"))
	file.close()


func _tts_available() -> bool:
	var tts: Node = get_node_or_null("/root/TtsService")
	if tts != null and tts.has_method("is_available"):
		return bool(tts.call("is_available"))
	return false


## Which voice speaks, e.g. "Samantha (compact)". Diagnostics only (the live
## panel, not the persisted file).
func _tts_voice() -> String:
	var tts: Node = get_node_or_null("/root/TtsService")
	if tts != null and tts.has_method("describe_voice"):
		return String(tts.call("describe_voice"))
	return ""


## The game's own voice must be quiet before the microphone opens: on a device
## the speaker and the mic are inches apart, and a prompt still being spoken is
## the likeliest thing to be transcribed. Stopping it also makes the loop feel
## immediate -- the child pressed Speak, so the game listens now.
func _hush_tts() -> void:
	var tts: Node = get_node_or_null("/root/TtsService")
	if tts != null and tts.has_method("stop"):
		tts.call("stop")


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
	_last_locale = locale
	if not is_available():
		recognition_failed.emit("unavailable")
		return
	_hush_tts()
	_backend.start_listening(locale)


func stop_listening() -> void:
	if _backend != null:
		_backend.stop_listening()


func is_listening() -> bool:
	return _backend != null and _backend.is_listening()


## -- Parent diagnostics --------------------------------------------------------

## A live snapshot for the on-screen parent diagnostic: capability flags and
## counts only.
##
## It deliberately carries NO transcript. `test_speech_privacy_guard.gd` forbids
## this file from holding recognised words in a member variable at all, and that
## guard is right -- this is a long-lived autoload that writes a file to disk, so
## anything it remembers is one bug away from being persisted. The parent panel
## that wants to display the last transcript subscribes to `recognized` and holds
## it in its own short-lived memory instead, which dies with the screen.
##
## This exists because a JSON file in the app container is not something a parent
## can read on an iPhone at the kitchen table, and "is speech working?" is
## exactly the question they need answered there.
func describe_diagnostics() -> Dictionary:
	return {
		"platform": OS.get_name(),
		"modelName": OS.get_model_name(),
		"backend": get_backend_name(),
		"nativeSingletonPresent": Engine.has_singleton(IOS_SINGLETON_NAME),
		"isAvailable": is_available(),
		"hasPermission": has_permission(),
		"isListening": is_listening(),
		"speechEnabledSetting": _speech_enabled(),
		"ttsAvailable": _tts_available(),
		"ttsVoice": _tts_voice(),
		"locale": _last_locale,
		"lastFailureReason": _last_failure_reason,
		"listenCount": _listen_count,
		"recognizedCount": _recognized_count,
		"failedCount": _failed_count,
		"launchCount": _launch_count,
		"fallbackActive": get_backend_name() != "ios",
	}


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

	if OS.has_feature("mobile"):
		# A real device — iOS OR ANDROID — with no native recognizer behind it.
		# Report unavailable honestly and let the touch fallback carry the game.
		#
		# This used to test `ios` alone, which was one platform too narrow and is
		# a shipping bug rather than a tidiness point. On Android neither branch
		# above matched, so execution fell through to the MOCK: `is_available()`
		# returns true and `next_transcript` is the canned `"milk"`. The Speak
		# button would therefore appear on a build with no speech support at all,
		# and 0.6 s after any tap the game would accept `"milk"` whether or not
		# the child made a sound — every speaking task passed, silently, without
		# speech. For a product whose entire purpose is a child practising
		# English aloud, that is the worst possible failure: it looks like
		# success.
		#
		# `mobile` covers both platforms and any future one, so the next mobile
		# export cannot re-introduce it by omission.
		_set_backend(SpeechBackend.new(), "unavailable")
		return

	# Editor and desktop only. The mock exists so the game can be developed and
	# tested without a device; it must never be reachable on one.
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
	_backend.partial_recognized.connect(_on_partial_recognized)
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
	if _backend.partial_recognized.is_connected(_on_partial_recognized):
		_backend.partial_recognized.disconnect(_on_partial_recognized)
	if _backend.recognized.is_connected(_on_recognized):
		_backend.recognized.disconnect(_on_recognized)
	if _backend.recognition_failed.is_connected(_on_recognition_failed):
		_backend.recognition_failed.disconnect(_on_recognition_failed)


func _on_availability_changed(available: bool) -> void:
	availability_changed.emit(available)


func _on_permission_result(granted: bool) -> void:
	permission_result.emit(granted)


func _on_listening_started() -> void:
	_listen_count += 1
	_write_diagnostics()
	listening_started.emit()


func _on_listening_stopped() -> void:
	listening_stopped.emit()


## Passed straight through: not counted, not written, not remembered.
func _on_partial_recognized(text: String) -> void:
	partial_recognized.emit(text)


func _on_recognized(text: String) -> void:
	_recognized_count += 1
	_write_diagnostics()
	recognized.emit(text)


func _on_recognition_failed(reason: String) -> void:
	_failed_count += 1
	_last_failure_reason = reason
	_write_diagnostics()
	recognition_failed.emit(reason)


## Reads `speechEnabled` from SaveService defensively — SaveService is
## authored concurrently and must never be assumed to exist.
func _speech_enabled() -> bool:
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null and save_service.has_method("get_setting"):
		var value = save_service.call("get_setting", "speechEnabled", true)
		return bool(value)
	return true
