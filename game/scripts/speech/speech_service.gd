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
##
## ## A listening session always ends, exactly once (2026-09-20)
##
## Every `start_listening()` that actually opens the microphone is a SESSION,
## and a session ends in exactly one terminal signal -- `recognized(text)` or
## `recognition_failed(reason)` -- followed by `session_ended(outcome)`. Nothing
## in the backend can prevent that:
##
##   * no partial within `NO_PARTIAL_CAP_SECONDS` (4 s)         -> capped
##   * no final within `AFTER_PARTIAL_CAP_SECONDS` (6 s) of the
##     last partial                                            -> capped
##
## A cap asks the backend to stop (which makes both the native plugin and the
## mock report the hypothesis they have as the final) and, if nothing terminal
## arrives within `CAP_GRACE_SECONDS`, reports `timeout` itself. A second
## terminal for the same session -- a late native callback, a backend that
## fails and then also finishes -- is dropped. `listening_stopped` is
## guaranteed before the terminal, because the iOS backend's failure path does
## not emit it. `is_listening()` answers from the session, not from the
## backend's cached flag, so the music duck that polls it always releases.
##
## No transcript is ever held here: the cap needs only WHETHER a partial came,
## and when.
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
## After the terminal signal of every session (and after an immediate
## `unavailable` failure, which is a session that never opened). `outcome` is
## `OUTCOME_RECOGNIZED` or `OUTCOME_FAILED`. The Speak button re-enables on this.
signal session_ended(outcome: String)

const OUTCOME_RECOGNIZED: String = "recognized"
const OUTCOME_FAILED: String = "failed"
const REASON_TIMEOUT: String = "timeout"
const REASON_UNAVAILABLE: String = "unavailable"

## Hard caps. See the class docs.
const NO_PARTIAL_CAP_SECONDS: float = 4.0
const AFTER_PARTIAL_CAP_SECONDS: float = 6.0
## How long a capped session waits for the backend to hand over its hypothesis
## before `timeout` is reported for it.
const CAP_GRACE_SECONDS: float = 0.75

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

## The live session. `_session_id` increments per session so a late callback
## for an old one is recognisable; the times are seconds of session age.
var _session_active: bool = false
var _session_id: int = 0
var _session_age: float = 0.0
var _had_partial: bool = false
var _since_partial: float = 0.0
var _capping: bool = false
var _since_cap: float = 0.0
var _stopped_emitted: bool = false


func _ready() -> void:
	_load_diagnostics()
	_select_backend()
	# Announce initial state so UI can reflect it without polling.
	availability_changed.emit(is_available())
	_write_diagnostics()


func _process(delta: float) -> void:
	advance(delta)


## Runs the session watchdog. Called every frame by `_process()`; a headless
## test drives it directly, exactly as `AudioDirector.advance()` is.
func advance(delta: float) -> void:
	if not _session_active or delta <= 0.0:
		return
	_session_age += delta
	if _capping:
		_since_cap += delta
		if _since_cap >= CAP_GRACE_SECONDS:
			_finish_session_failed(REASON_TIMEOUT)
		return
	if _had_partial:
		_since_partial += delta
		if _since_partial >= AFTER_PARTIAL_CAP_SECONDS:
			_cap_session(_since_partial - AFTER_PARTIAL_CAP_SECONDS)
	elif _session_age >= NO_PARTIAL_CAP_SECONDS:
		_cap_session(_session_age - NO_PARTIAL_CAP_SECONDS)


## Asks the backend to wrap up. It reports its hypothesis as the final (or
## nothing at all), and the grace timer covers the second case. `overshoot` is
## how far past the cap this frame already ran; it counts against the grace, so
## one long frame cannot stretch the ending.
func _cap_session(overshoot: float = 0.0) -> void:
	if _capping or not _session_active:
		return
	_capping = true
	_since_cap = 0.0
	if _backend != null:
		_backend.stop_listening()  # may end the session synchronously
	if _session_active and _capping:
		_since_cap = maxf(overshoot, 0.0)
		if _since_cap >= CAP_GRACE_SECONDS:
			_finish_session_failed(REASON_TIMEOUT)


## A session that is live right now. Tests and diagnostics.
func has_active_session() -> bool:
	return _session_active


## Seconds since the current session started. Tests and diagnostics.
func session_age() -> float:
	return _session_age


func session_had_partial() -> bool:
	return _had_partial


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
		"audioDriver": AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "unknown",
		"audioMixRate": AudioServer.get_mix_rate() if AudioServer.has_method("get_mix_rate") else 0,
		"nativeAudioSession": audio_session_diagnostics(),
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


## An autoload by name, through the main loop's root, so a service built
## outside a running scene (the headless runner) gets null and no engine error
## about absolute paths.
func _autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(node_name))


func _tts_available() -> bool:
	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("is_available"):
		return bool(tts.call("is_available"))
	return false


## Which voice speaks, e.g. "Samantha (compact)". Diagnostics only (the live
## panel, not the persisted file).
func _tts_voice() -> String:
	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("describe_voice"):
		return String(tts.call("describe_voice"))
	return ""


## The game's own voice must be quiet before the microphone opens: on a device
## the speaker and the mic are inches apart, and a prompt still being spoken is
## the likeliest thing to be transcribed. Stopping it also makes the loop feel
## immediate -- the child pressed Speak, so the game listens now.
func _hush_tts() -> void:
	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("stop"):
		tts.call("stop")


func is_available() -> bool:
	if not _speech_enabled():
		return false
	return _backend != null and _backend.is_available()


## Which backend is behind the service: ios / unavailable / mock (or a test's name).
func backend_name() -> String:
	return _backend_name


func has_permission() -> bool:
	return _backend != null and _backend.has_permission()


func request_permission() -> void:
	if _backend == null:
		permission_result.emit(false)
		return
	_backend.request_permission()


func start_listening(locale: String = "en-US") -> void:
	_last_locale = locale
	if _session_active:
		return  # one session at a time; the Speak button is disabled meanwhile
	if not is_available():
		# A session that never opened still ends, so a Speak button that
		# disabled itself on the press is re-enabled.
		_failed_count += 1
		_last_failure_reason = REASON_UNAVAILABLE
		_write_diagnostics()
		recognition_failed.emit(REASON_UNAVAILABLE)
		session_ended.emit(OUTCOME_FAILED)
		return
	_open_session()
	_hush_tts()
	_backend.start_listening(locale)
	# A backend that refused synchronously has already closed the session.


func stop_listening() -> void:
	if _backend != null:
		_backend.stop_listening()


## Whether a session is live. The backend's own flag is deliberately NOT
## consulted: the iOS backend's failure path leaves it set, and a duck keyed on
## a stuck flag would never release.
func is_listening() -> bool:
	return _session_active


## Hands-free tutor (Agent E): ends the live session NOW as
## `recognition_failed("cancelled")` + `session_ended(failed)` and asks the
## backend to stop. A barge-in or the start of Aliz's playback must not wait
## for the backend's hypothesis or the 4 s cap; whatever the backend reports
## afterwards is a late terminal and is dropped like any other.
func cancel_listening() -> void:
	if not _session_active:
		return
	_finish_session_failed("cancelled")
	if _backend != null:
		_backend.stop_listening()


## Hands-free tutor: the platform's echo-cancelled voice mode while a
## TutorVoiceSession is active (native plugin only; no-op elsewhere).
func set_voice_processing(enabled: bool) -> void:
	if _backend != null and _backend.has_method("set_voice_processing"):
		_backend.set_voice_processing(enabled)


## Hands-free tutor: the microphone level 0..1 for the VAD and the mic
## indicator while a session is live; 0 otherwise. A number, never audio.
func get_input_level() -> float:
	if not _session_active or _backend == null or not _backend.has_method("get_input_level"):
		return 0.0
	return clampf(float(_backend.get_input_level()), 0.0, 1.0)


func audio_session_diagnostics() -> Dictionary:
	if _backend != null and _backend.has_method("audio_session_diagnostics"):
		return _backend.call("audio_session_diagnostics")
	return {}


func _open_session() -> void:
	_session_id += 1
	_session_active = true
	_session_age = 0.0
	_had_partial = false
	_since_partial = 0.0
	_capping = false
	_since_cap = 0.0
	_stopped_emitted = false


## Ends the session, emitting `listening_stopped` first when the backend did
## not. Returns false when no session is live (a late or duplicate terminal).
func _close_session() -> bool:
	if not _session_active:
		return false
	_session_active = false
	_capping = false
	if not _stopped_emitted:
		_stopped_emitted = true
		listening_stopped.emit()
	return true


func _finish_session_failed(reason: String) -> void:
	if not _close_session():
		return
	_failed_count += 1
	_last_failure_reason = reason
	_write_diagnostics()
	recognition_failed.emit(reason)
	session_ended.emit(OUTCOME_FAILED)


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
	_backend.audio_session_changed.connect(_on_audio_session_changed)


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
	if _backend.audio_session_changed.is_connected(_on_audio_session_changed):
		_backend.audio_session_changed.disconnect(_on_audio_session_changed)


func _on_audio_session_changed(_snapshot: Dictionary) -> void:
	_write_diagnostics()


func _on_availability_changed(available: bool) -> void:
	availability_changed.emit(available)


func _on_permission_result(granted: bool) -> void:
	permission_result.emit(granted)


func _on_listening_started() -> void:
	if not _session_active:
		# A backend that starts on its own (never in this project, but a
		# contract is a contract): adopt it as a session so it is still capped.
		_open_session()
	_listen_count += 1
	_write_diagnostics()
	listening_started.emit()


func _on_listening_stopped() -> void:
	if _stopped_emitted:
		return
	_stopped_emitted = true
	listening_stopped.emit()


## Passed straight through: not counted, not written, not remembered. Only the
## fact that one arrived, and when, is kept for the cap.
func _on_partial_recognized(text: String) -> void:
	if not _session_active:
		return
	if not text.strip_edges().is_empty():
		_had_partial = true
		_since_partial = 0.0
	partial_recognized.emit(text)


func _on_recognized(text: String) -> void:
	if not _close_session():
		return  # a late final for a session that already ended
	_recognized_count += 1
	_write_diagnostics()
	recognized.emit(text)
	session_ended.emit(OUTCOME_RECOGNIZED)


## A failure for the live session ends it. One arriving with no session live --
## the iOS backend re-emitting an error after a cap already ended the session --
## is dropped: the child has already been answered once, and a second "Try
## again" on top of "Great!" is exactly the double ending this file forbids.
func _on_recognition_failed(reason: String) -> void:
	if not _session_active:
		return
	_finish_session_failed(reason)


## Reads `speechEnabled` from SaveService defensively — SaveService is
## authored concurrently and must never be assumed to exist.
func _speech_enabled() -> bool:
	var save_service: Node = _autoload("SaveService")
	if save_service != null and save_service.has_method("get_setting"):
		var value = save_service.call("get_setting", "speechEnabled", true)
		return bool(value)
	return true
