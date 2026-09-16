## Desktop/dev speech backend. Simulates the async recognition flow so the
## full gameplay loop (mic button -> listening -> recognized -> feedMilk) is
## testable on macOS/editor without a microphone or native plugin.
##
## This is a DEV AID ONLY. It must never be selected on a real device in
## place of a genuine backend — `SpeechService` only picks this on desktop
## platforms. It records nothing and never touches disk or network.
class_name MockSpeechBackend
extends SpeechBackend

## Canned transcript emitted by the next successful `start_listening()` call.
var next_transcript: String = "milk"

## Delay before the canned result is delivered, in seconds. Kept short so
## manual testing in the editor stays snappy.
var response_delay: float = 0.6

var _has_permission: bool = true
var _is_listening: bool = false
var _simulate_failure: bool = false
var _failure_reason: String = "mock_failure"


## Test helper: make the next `start_listening()` call fail instead of
## succeeding, with an optional reason string.
func simulate_next_failure(reason: String = "mock_failure") -> void:
	_simulate_failure = true
	_failure_reason = reason


## Test helper: revert to normal (successful) canned recognition.
func clear_simulated_failure() -> void:
	_simulate_failure = false


func is_available() -> bool:
	return true


func has_permission() -> bool:
	return _has_permission


func request_permission() -> void:
	_has_permission = true
	permission_result.emit(true)


func start_listening(_locale: String = "en-US") -> void:
	if _is_listening:
		return
	_is_listening = true
	listening_started.emit()

	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		var timer := (main_loop as SceneTree).create_timer(response_delay)
		timer.timeout.connect(_on_delay_finished)
	else:
		# No SceneTree available (e.g. running under --script tests) — resolve
		# immediately rather than hanging forever.
		_on_delay_finished()


func stop_listening() -> void:
	if not _is_listening:
		return
	_is_listening = false
	listening_stopped.emit()


func is_listening() -> bool:
	return _is_listening


func get_backend_name() -> String:
	return "mock"


func _on_delay_finished() -> void:
	if not _is_listening:
		return
	_is_listening = false
	listening_stopped.emit()

	if _simulate_failure:
		_simulate_failure = false
		recognition_failed.emit(_failure_reason)
	else:
		recognized.emit(next_transcript)
