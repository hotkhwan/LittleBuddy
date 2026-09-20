extends RefCounted

## Wires a `SpeechService` to a `SpeechFeedback` panel.
##
## Kept apart from the panel for one reason: the panel must stay a pure
## presenter that a test can drive by hand, and the service is an autoload with
## real device state behind it. This is the only file that knows both.
##
## It is also where the "is speech even possible" question gets answered ONCE,
## so the panel never has to guess. On a device with no permission the child
## presses Speak and gets a sentence about grown-ups and Settings; on a build
## with no backend at all they get "you can tap it instead". Neither case leaves
## them looking at nothing, which is what used to happen in both.

const Feedback := preload("res://scripts/ui/speech_feedback.gd")


static func classify_failure(reason: String) -> int:
	## Maps a backend's failure string onto a child-facing state.
	##
	## Substring matching, deliberately: backends word these differently and a
	## new one must degrade to a friendly retry rather than to an unhandled
	## branch. Permission is singled out because it is the one failure a parent
	## can actually fix, so it earns its own sentence.
	var text: String = reason.strip_edges().to_lower()
	if text.contains("permission") or text.contains("denied") or text.contains("authoriz"):
		return Feedback.State.PERMISSION_NEEDED
	if text.contains("unavailable") or text.contains("not available") \
			or text.contains("unsupported") or text.contains("no backend"):
		return Feedback.State.UNAVAILABLE
	if text.contains("no match") or text.contains("nomatch") \
			or text.contains("not understood") or text.contains("empty"):
		return Feedback.State.NOT_UNDERSTOOD
	# "timeout": the window closed with nothing heard. Not a misunderstanding
	# (nothing was said) and not a broken microphone -- ERROR's copy is the
	# gentle "Let's try again" with the tap reminder, which is right for it.
	return Feedback.State.ERROR


var _panel: Node = null
var _service: Object = null
var _matched_checker: Callable = Callable()


## `matched_checker` takes the transcript and returns true when it satisfied the
## current prompt. Optional: without it a transcript shows as HEARD and nothing
## claims the child was right, which is the honest default.
func bind(panel: Node, service: Object, matched_checker: Callable = Callable()) -> void:
	_panel = panel
	_service = service
	_matched_checker = matched_checker
	if _service == null or _panel == null:
		return
	_connect("listening_started", _on_listening_started)
	_connect("listening_stopped", _on_listening_stopped)
	_connect("partial_recognized", _on_partial)
	_connect("recognized", _on_recognized)
	_connect("recognition_failed", _on_failed)
	_connect("permission_result", _on_permission)
	_connect("availability_changed", _on_availability)


func _connect(signal_name: String, handler: Callable) -> void:
	if not _service.has_signal(signal_name):
		return
	if _service.is_connected(signal_name, handler):
		return
	_service.connect(signal_name, handler)


## Called when the child presses Speak, BEFORE listening starts, so an
## impossible attempt explains itself instead of appearing to do nothing.
## Returns true when listening should actually be attempted.
func on_speak_pressed() -> bool:
	if _service == null:
		_show(Feedback.State.UNAVAILABLE)
		return false
	if _service.has_method("is_available") and not bool(_service.call("is_available")):
		_show(Feedback.State.UNAVAILABLE)
		return false
	if _service.has_method("has_permission") and not bool(_service.call("has_permission")):
		_show(Feedback.State.PERMISSION_NEEDED)
		if _service.has_method("request_permission"):
			_service.call("request_permission")
		return false
	return true


func _on_listening_started() -> void:
	_show(Feedback.State.LISTENING)


func _on_listening_stopped() -> void:
	# Only the LISTENING state is cleared here. A transcript or a failure has
	# already replaced it by the time this arrives in the usual order, and
	# stomping those would flash the answer away. The stop that follows an
	# early match leaves PROCESSING up, and the final replaces that.
	if _state() == Feedback.State.LISTENING:
		_show(Feedback.State.PROCESSING)


## An interim guess while the microphone is still open.
##
## Two jobs. The child sees the words land ("I hear: milk") instead of a
## silent pulse, and -- the responsiveness fix -- if the guess already satisfies
## the prompt, listening is ended right now. Waiting for the recogniser's own
## end-of-utterance decision can take seconds on-device; ending the session
## makes the backend report what it has as the final transcript (both the
## native plugin and the mock do this), which then flows through `recognized`
## and the runner exactly as a natural final would. Nothing is invented: the
## words are the recogniser's, and the runner still runs its own matcher.
func _on_partial(text: String) -> void:
	var heard: String = text.strip_edges()
	if heard.is_empty():
		return
	if _matched_checker.is_valid() and bool(_matched_checker.call(heard)):
		_show(Feedback.State.PROCESSING)
		if _service != null and _service.has_method("stop_listening"):
			_service.call("stop_listening")
		return
	_show(Feedback.State.LISTENING, heard)


func _on_recognized(text: String) -> void:
	var heard: String = text.strip_edges()
	if heard.is_empty():
		_show(Feedback.State.NOT_UNDERSTOOD)
		return
	if not _matched_checker.is_valid():
		# Nobody can say whether it was right, so nobody claims it was.
		_show(Feedback.State.HEARD, heard)
		return
	if bool(_matched_checker.call(heard)):
		_show(Feedback.State.MATCHED, heard)
	else:
		_show(Feedback.State.NOT_UNDERSTOOD, heard)


func _on_failed(reason: String) -> void:
	_show(classify_failure(reason))


func _on_permission(granted: bool) -> void:
	if not granted:
		_show(Feedback.State.PERMISSION_NEEDED)


func _on_availability(available: bool) -> void:
	if not available and _state() == Feedback.State.LISTENING:
		_show(Feedback.State.UNAVAILABLE)


func _state() -> int:
	if _panel == null or not _panel.has_method("get_state"):
		return Feedback.State.IDLE
	return int(_panel.call("get_state"))


## Named `_show`, not `_set`: `Object._set(StringName, Variant) -> bool` is a
## built-in virtual and overriding it with a different signature is a parse error.
func _show(state: int, detail: String = "") -> void:
	if _panel != null and _panel.has_method("set_state"):
		_panel.call("set_state", state, detail)
