extends RefCounted

## Every listening session ends, exactly once, in one of three faces.
##
## Drives the real `SpeechService` with a scripted backend (tests only; the
## `OS.has_feature("mobile")` guard in the service is untouched) through every
## path -- success, misheard, timeout with and without a partial, permission
## refused, unavailable, a backend that never says "stopped", and late
## duplicate callbacks -- and asserts:
##
##   * exactly one terminal signal (`recognized` OR `recognition_failed`), then
##     exactly one `session_ended`;
##   * `listening_stopped` exactly once, even when the backend forgot it;
##   * `is_listening()` false afterwards (what the music duck polls);
##   * the feedback panel lands on SUCCESS / RETRY / UNAVAILABLE;
##   * the HUD's Speak button is disabled while live and back on every ending.

const ServiceScript := preload("res://scripts/speech/speech_service.gd")
const BackendScript := preload("res://scripts/speech/speech_backend.gd")
const Feedback := preload("res://scripts/ui/speech_feedback.gd")
const Binder := preload("res://scripts/ui/speech_feedback_binder.gd")
const HouseHud := preload("res://scripts/gameplay/house_hud.gd")


## A backend the test plays like a piano. It does nothing on its own.
class ScriptedBackend:
	extends SpeechBackend
	var available: bool = true
	var permission: bool = true
	var starts: int = 0
	var stops: int = 0
	## What a stop hands over as the final, when non-empty (a hypothesis).
	var hypothesis_on_stop: String = ""
	## Whether a stop is followed by `listening_stopped` (the native plugin does;
	## the iOS failure path does not).
	var announces_stop: bool = true

	func is_available() -> bool:
		return available

	func has_permission() -> bool:
		return permission

	func start_listening(_locale: String = "en-US") -> void:
		starts += 1
		listening_started.emit()

	func stop_listening() -> void:
		stops += 1
		if announces_stop:
			listening_stopped.emit()
		if not hypothesis_on_stop.is_empty():
			recognized.emit(hypothesis_on_stop)

	func is_listening() -> bool:
		return true  # deliberately stuck, like the iOS flag after a failure

	func get_backend_name() -> String:
		return "scripted"


## Counts what a session emitted.
class Tally:
	extends RefCounted
	var started: int = 0
	var stopped: int = 0
	var partials: Array = []
	var finals: Array = []
	var failures: Array = []
	var ended: Array = []

	func attach(service: Node) -> void:
		service.listening_started.connect(func() -> void: started += 1)
		service.listening_stopped.connect(func() -> void: stopped += 1)
		service.partial_recognized.connect(func(text: String) -> void: partials.append(text))
		service.recognized.connect(func(text: String) -> void: finals.append(text))
		service.recognition_failed.connect(func(reason: String) -> void: failures.append(reason))
		service.session_ended.connect(func(outcome: String) -> void: ended.append(outcome))

	func terminals() -> int:
		return finals.size() + failures.size()


func test_name() -> String:
	return "speech_end_states"


func run():
	var failures: Array = []
	failures.append_array(_test_success())
	failures.append_array(_test_misheard_is_retry())
	failures.append_array(_test_timeout_without_partial())
	failures.append_array(_test_timeout_after_partial_hands_over_the_hypothesis())
	failures.append_array(_test_timeout_after_partial_with_nothing_to_hand_over())
	failures.append_array(_test_failure_without_stopped())
	failures.append_array(_test_unavailable_never_opens())
	failures.append_array(_test_late_callbacks_are_dropped())
	failures.append_array(_test_second_press_during_a_session_is_ignored())
	failures.append_array(_test_every_face_is_one_of_three())
	failures.append_array(_test_speak_button_lock())
	return failures


func _service(backend: SpeechBackend) -> Node:
	var service: Node = ServiceScript.new()
	service.call("_set_backend", backend, "scripted")
	return service


func _check_single_ending(failures: Array, tally: Tally, service: Node, label: String,
		expected_outcome: String) -> void:
	if tally.terminals() != 1:
		failures.append("%s: %d terminal signal(s) (finals %s, failures %s); exactly one is the rule"
				% [label, tally.terminals(), str(tally.finals), str(tally.failures)])
	if tally.ended != [expected_outcome]:
		failures.append("%s: session_ended %s, expected [%s]" % [label, str(tally.ended), expected_outcome])
	if bool(service.call("is_listening")) or bool(service.call("has_active_session")):
		failures.append("%s: the service still says it is listening after the ending" % label)
	if tally.started > 0 and tally.stopped != 1:
		failures.append("%s: listening_stopped emitted %d time(s), expected exactly 1" % [label, tally.stopped])


func _test_success():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	var service: Node = _service(backend)
	var tally := Tally.new()
	tally.attach(service)

	service.call("start_listening")
	if not bool(service.call("is_listening")):
		failures.append("success: start did not open a session")
	service.call("advance", 1.0)
	backend.partial_recognized.emit("mil")
	service.call("advance", 1.0)
	backend.listening_stopped.emit()
	backend.recognized.emit("milk")
	_check_single_ending(failures, tally, service, "success", "recognized")
	if tally.finals != ["milk"] or tally.partials != ["mil"]:
		failures.append("success: heard %s / %s" % [str(tally.partials), str(tally.finals)])
	service.free()
	return failures


func _test_misheard_is_retry():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	var service: Node = _service(backend)
	var tally := Tally.new()
	tally.attach(service)
	var panel: Control = Feedback.new()
	panel.build()
	var binder = Binder.new()
	binder.bind(panel, service, func(text: String) -> bool: return text == "milk")

	service.call("start_listening")
	backend.listening_stopped.emit()
	backend.recognized.emit("banana")
	_check_single_ending(failures, tally, service, "misheard", "recognized")
	if Feedback.terminal_class(panel.get_state()) != Feedback.TERMINAL_RETRY:
		failures.append("misheard: the panel is in state %d, expected the RETRY face" % panel.get_state())
	var copy: String = panel.get_title_text() + " " + panel.get_detail_text()
	if not copy.contains("Try again!") or not copy.contains("banana") or not copy.contains("tap"):
		failures.append("misheard: copy should be 'Try again! I heard: banana ... tap': '%s'" % copy)
	panel.free()
	service.free()
	return failures


func _test_timeout_without_partial():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	backend.announces_stop = false  # the backend never says it stopped
	var service: Node = _service(backend)
	var tally := Tally.new()
	tally.attach(service)

	service.call("start_listening")
	service.call("advance", 3.9)
	if backend.stops != 0 or tally.terminals() != 0:
		failures.append("no-partial: capped before 4 s (stops %d, terminals %d)" % [backend.stops, tally.terminals()])
	service.call("advance", 0.2)
	if backend.stops != 1:
		failures.append("no-partial: the 4 s cap did not ask the backend to stop")
	if tally.terminals() != 0:
		failures.append("no-partial: a terminal was reported before the grace elapsed")
	service.call("advance", ServiceScript.CAP_GRACE_SECONDS + 0.05)
	_check_single_ending(failures, tally, service, "no-partial timeout", "failed")
	if tally.failures != ["timeout"]:
		failures.append("no-partial: expected a single 'timeout', got %s" % str(tally.failures))
	if tally.stopped != 1:
		failures.append("no-partial: the service must emit listening_stopped itself when the backend does not")
	service.free()
	return failures


func _test_timeout_after_partial_hands_over_the_hypothesis():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	backend.hypothesis_on_stop = "milk"
	var service: Node = _service(backend)
	var tally := Tally.new()
	tally.attach(service)

	service.call("start_listening")
	service.call("advance", 3.5)
	backend.partial_recognized.emit("milk")  # at 3.5 s: the 4 s cap must reset
	service.call("advance", 1.0)  # 4.5 s of age, 1.0 s since the partial
	if backend.stops != 0:
		failures.append("after-partial: capped at 4 s of age although a partial had arrived")
	service.call("advance", 4.9)  # 5.9 s since the partial
	if backend.stops != 0:
		failures.append("after-partial: capped before 6 s since the last partial")
	service.call("advance", 0.2)  # 6.1 s
	if backend.stops != 1:
		failures.append("after-partial: the 6 s cap did not stop the backend")
	# The backend handed its hypothesis over on stop: that is the final.
	_check_single_ending(failures, tally, service, "after-partial", "recognized")
	if tally.finals != ["milk"] or not tally.failures.is_empty():
		failures.append("after-partial: expected the hypothesis as the final, got finals %s failures %s"
				% [str(tally.finals), str(tally.failures)])
	# The grace elapsing later must not add a timeout on top.
	service.call("advance", 2.0)
	if tally.terminals() != 1 or tally.ended.size() != 1:
		failures.append("after-partial: a second ending arrived after the grace")
	service.free()
	return failures


func _test_timeout_after_partial_with_nothing_to_hand_over():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	var service: Node = _service(backend)
	var tally := Tally.new()
	tally.attach(service)
	service.call("start_listening")
	backend.partial_recognized.emit("m")
	service.call("advance", 6.05)
	service.call("advance", ServiceScript.CAP_GRACE_SECONDS + 0.05)
	_check_single_ending(failures, tally, service, "after-partial no final", "failed")
	if tally.failures != ["timeout"]:
		failures.append("after-partial no final: expected 'timeout', got %s" % str(tally.failures))
	service.free()
	return failures


func _test_failure_without_stopped():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	var service: Node = _service(backend)
	var tally := Tally.new()
	tally.attach(service)
	var panel: Control = Feedback.new()
	panel.build()
	var binder = Binder.new()
	binder.bind(panel, service)

	service.call("start_listening")
	backend.recognition_failed.emit("permission denied")  # no listening_stopped first
	_check_single_ending(failures, tally, service, "permission", "failed")
	if Feedback.terminal_class(panel.get_state()) != Feedback.TERMINAL_UNAVAILABLE:
		failures.append("permission: the panel is in state %d, expected the UNAVAILABLE face" % panel.get_state())
	if not panel.get_title_text().contains("Voice is not ready"):
		failures.append("permission: title '%s' should read 'Voice is not ready'" % panel.get_title_text())
	if not panel.get_detail_text().to_lower().contains("tap it instead"):
		failures.append("permission: detail '%s' should offer 'tap it instead'" % panel.get_detail_text())
	panel.free()
	service.free()
	return failures


func _test_unavailable_never_opens():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	backend.available = false
	var service: Node = _service(backend)
	var tally := Tally.new()
	tally.attach(service)
	var panel: Control = Feedback.new()
	panel.build()
	var binder = Binder.new()
	binder.bind(panel, service)

	service.call("start_listening")
	if backend.starts != 0:
		failures.append("unavailable: the backend was asked to start")
	if tally.failures != ["unavailable"] or tally.ended != ["failed"]:
		failures.append("unavailable: expected failed('unavailable') + session_ended, got %s / %s"
				% [str(tally.failures), str(tally.ended)])
	if bool(service.call("is_listening")):
		failures.append("unavailable: the service claims to be listening")
	if Feedback.terminal_class(panel.get_state()) != Feedback.TERMINAL_UNAVAILABLE:
		failures.append("unavailable: the panel is in state %d, expected the UNAVAILABLE face" % panel.get_state())
	if panel.get_title_text() != "Voice is not ready" or panel.get_detail_text() != "Tap it instead!":
		failures.append("unavailable: copy is '%s' / '%s'" % [panel.get_title_text(), panel.get_detail_text()])
	panel.free()
	service.free()
	return failures


func _test_late_callbacks_are_dropped():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	var service: Node = _service(backend)
	var tally := Tally.new()
	tally.attach(service)

	service.call("start_listening")
	backend.listening_stopped.emit()
	backend.recognized.emit("milk")
	# The native layer can still call back after the session ended.
	backend.recognized.emit("milk")
	backend.recognition_failed.emit("something exploded")
	backend.listening_stopped.emit()
	backend.partial_recognized.emit("mi")
	_check_single_ending(failures, tally, service, "late callbacks", "recognized")
	if not tally.partials.is_empty():
		failures.append("late callbacks: a partial after the ending reached the UI")
	service.free()
	return failures


func _test_second_press_during_a_session_is_ignored():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	var service: Node = _service(backend)
	var tally := Tally.new()
	tally.attach(service)
	service.call("start_listening")
	service.call("start_listening")
	if backend.starts != 1:
		failures.append("a second press during a live session started the backend again (%d starts)" % backend.starts)
	backend.listening_stopped.emit()
	backend.recognized.emit("milk")
	_check_single_ending(failures, tally, service, "double press", "recognized")
	# And a fresh press afterwards opens a fresh session.
	service.call("start_listening")
	if backend.starts != 2 or not bool(service.call("is_listening")):
		failures.append("after an ending the next press must open a new session")
	service.free()
	return failures


## Every state the panel can end on is one of the three faces, and only the
## non-terminal states are none.
func _test_every_face_is_one_of_three():
	var failures: Array = []
	var expected: Dictionary = {
		Feedback.State.IDLE: "",
		Feedback.State.LISTENING: "",
		Feedback.State.PROCESSING: "",
		Feedback.State.HEARD: "",
		Feedback.State.MATCHED: Feedback.TERMINAL_SUCCESS,
		Feedback.State.NOT_UNDERSTOOD: Feedback.TERMINAL_RETRY,
		Feedback.State.ERROR: Feedback.TERMINAL_RETRY,
		Feedback.State.UNAVAILABLE: Feedback.TERMINAL_UNAVAILABLE,
		Feedback.State.PERMISSION_NEEDED: Feedback.TERMINAL_UNAVAILABLE,
	}
	for state: int in expected.keys():
		if Feedback.terminal_class(state) != String(expected[state]):
			failures.append("terminal_class(%d) = '%s', expected '%s'" % [state, Feedback.terminal_class(state), expected[state]])
	# The faces say what the spec says.
	if Feedback.copy_for_state(Feedback.State.MATCHED)["title"] != "Great!":
		failures.append("SUCCESS must read 'Great!'")
	for state: int in [Feedback.State.NOT_UNDERSTOOD, Feedback.State.ERROR]:
		var copy: Dictionary = Feedback.copy_for_state(state, "banana")
		if copy["title"] != "Try again!" or not String(copy["detail"]).contains("You can tap it too!"):
			failures.append("RETRY (%d) must read 'Try again!' + 'You can tap it too!': %s" % [state, str(copy)])
	for state: int in [Feedback.State.UNAVAILABLE, Feedback.State.PERMISSION_NEEDED]:
		var copy: Dictionary = Feedback.copy_for_state(state)
		if copy["title"] != "Voice is not ready" or not String(copy["detail"]).to_lower().contains("tap it instead"):
			failures.append("UNAVAILABLE (%d) must read 'Voice is not ready' + 'tap it instead': %s" % [state, str(copy)])
	# The timeout the service reports lands on the RETRY face.
	if Feedback.terminal_class(Binder.classify_failure(ServiceScript.REASON_TIMEOUT)) != Feedback.TERMINAL_RETRY:
		failures.append("a timeout must be the RETRY face")
	if Feedback.terminal_class(Binder.classify_failure(ServiceScript.REASON_UNAVAILABLE)) != Feedback.TERMINAL_UNAVAILABLE:
		failures.append("'unavailable' must be the UNAVAILABLE face")
	return failures


## The Speak button is held while a session is live and comes back on EVERY
## ending, through the real HUD and the real service under the root.
func _test_speak_button_lock():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var backend := ScriptedBackend.new()
	var service: Node = _service(backend)
	service.name = "SpeechService"
	tree.root.add_child(service)

	var hud: Control = HouseHud.new()
	hud.call("build")
	hud.call("set_speak_visible", true)
	hud.speak_pressed.connect(func() -> void: service.call("start_listening"))
	var speak: Button = hud.find_child("SpeakButton", true, false) as Button

	# Success ending.
	speak.pressed.emit()
	if not bool(hud.call("is_speak_locked")):
		failures.append("lock: Speak stayed enabled during a live session")
	backend.listening_stopped.emit()
	backend.recognized.emit("milk")
	if bool(hud.call("is_speak_locked")):
		failures.append("lock: Speak did not come back after a recognised final")

	# Timeout ending.
	speak.pressed.emit()
	if not bool(hud.call("is_speak_locked")):
		failures.append("lock: Speak stayed enabled on the second session")
	service.call("advance", ServiceScript.NO_PARTIAL_CAP_SECONDS + ServiceScript.CAP_GRACE_SECONDS + 0.1)
	if bool(hud.call("is_speak_locked")):
		failures.append("lock: Speak did not come back after a timeout")

	# Failure ending.
	speak.pressed.emit()
	backend.recognition_failed.emit("permission denied")
	if bool(hud.call("is_speak_locked")):
		failures.append("lock: Speak did not come back after a failure")

	# Unavailable: no session opens, so the button is never taken away.
	backend.available = false
	speak.pressed.emit()
	if bool(hud.call("is_speak_locked")):
		failures.append("lock: Speak was disabled although no session opened (unavailable)")

	hud.free()
	tree.root.remove_child(service)
	service.free()
	return failures
