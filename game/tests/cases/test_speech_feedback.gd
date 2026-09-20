extends RefCounted

## The speech feedback panel: what the child is allowed to be told.
##
## This exists because the reported bug was not a crash -- it was SILENCE. The
## Speak button did something invisible, and on a device that is
## indistinguishable from the feature being broken. So the things worth pinning
## are about what is always said, never about pixels:
##
##   1. **Every state says something.** A state that renders blank is the old bug
##      with extra steps, so `copy_for_state()` must answer for every enum value.
##   2. **Nothing is a failure.** No "wrong", no "no", no "incorrect", no score.
##      `CLAUDE.md`'s child UX rules are absolute about this.
##   3. **The touch fallback is never hidden.** Every state that means speech did
##      not work must also say tapping works, or a child can be trapped at a
##      prompt they cannot pass.
##   4. **Failure strings map to the right face.** A permission problem must be
##      distinguishable from "did not catch that", because only one of them is a
##      thing a parent can fix.
##   5. **Transient states clear themselves**, so a stale "I'm listening..." can
##      never outlive the microphone.

const Feedback := preload("res://scripts/ui/speech_feedback.gd")
const Binder := preload("res://scripts/ui/speech_feedback_binder.gd")

const ALL_STATES: Array[int] = [
	Feedback.State.IDLE,
	Feedback.State.LISTENING,
	Feedback.State.PROCESSING,
	Feedback.State.HEARD,
	Feedback.State.MATCHED,
	Feedback.State.NOT_UNDERSTOOD,
	Feedback.State.PERMISSION_NEEDED,
	Feedback.State.UNAVAILABLE,
	Feedback.State.ERROR,
]

## States that mean "speech did not work for you just now". Each must point at
## touch.
const FALLBACK_STATES: Array[int] = [
	Feedback.State.NOT_UNDERSTOOD,
	Feedback.State.PERMISSION_NEEDED,
	Feedback.State.UNAVAILABLE,
	Feedback.State.ERROR,
]

## Words a children's app must never show for a speech attempt.
const BANNED: Array[String] = [
	"wrong", "incorrect", "fail", "failed", "error:", "invalid", "denied",
	"no match", "bad", "%",
]


func test_name() -> String:
	return "speech_feedback"


func run():
	var failures: Array = []
	failures.append_array(_test_every_state_speaks())
	failures.append_array(_test_nothing_reads_as_failure())
	failures.append_array(_test_touch_is_always_offered())
	failures.append_array(_test_failure_strings_are_classified())
	failures.append_array(_test_binder_shows_the_live_guess_and_ends_listening_on_a_match())
	failures.append_array(_test_binder_never_claims_a_match_it_cannot_check())
	failures.append_array(_test_mock_backend_reports_what_it_heard_on_stop())
	failures.append_array(_test_transient_states_clear())
	failures.append_array(_test_the_panel_renders_its_copy())
	return failures


func _test_every_state_speaks():
	var failures: Array = []
	for state in ALL_STATES:
		var copy: Dictionary = Feedback.copy_for_state(state, "milk")
		if not copy.has("title") or not copy.has("detail") or not copy.has("color"):
			failures.append("state %d is missing a title/detail/color key" % state)
			continue
		if state == Feedback.State.IDLE:
			continue
		if String(copy["title"]).strip_edges().is_empty():
			failures.append(("state %d renders an EMPTY title. A state with nothing to say is "
					+ "the silent Speak button this panel exists to replace.") % state)
	# and the transcript must actually appear, or "You said:" is a lie
	var heard: Dictionary = Feedback.copy_for_state(Feedback.State.HEARD, "milk")
	if not String(heard["title"]).to_lower().contains("milk"):
		failures.append("HEARD does not include the recognised word; it read '%s'"
				% String(heard["title"]))
	return failures


func _test_nothing_reads_as_failure():
	var failures: Array = []
	for state in ALL_STATES:
		var copy: Dictionary = Feedback.copy_for_state(state, "milk")
		var text: String = (String(copy["title"]) + " " + String(copy["detail"])).to_lower()
		for word: String in BANNED:
			if text.contains(word):
				failures.append(("state %d says '%s' (in \"%s\"). No mistake in this game is "
						+ "allowed to read as a failure -- no red X, no score, no 'wrong'.")
						% [state, word, text.strip_edges()])
	return failures


func _test_touch_is_always_offered():
	var failures: Array = []
	for state in FALLBACK_STATES:
		var copy: Dictionary = Feedback.copy_for_state(state, "")
		var text: String = (String(copy["title"]) + " " + String(copy["detail"])).to_lower()
		if not text.contains("tap"):
			failures.append(("state %d means speech did not work, but never mentions tapping. "
					+ "A child who cannot be heard must still be able to finish: \"%s\"")
					% [state, text.strip_edges()])
		if not Feedback.touch_remains_available(state):
			failures.append("touch_remains_available(%d) is false; touch is never withdrawn"
					% state)
	return failures


func _test_failure_strings_are_classified():
	var failures: Array = []
	var cases: Dictionary = {
		"permission denied by user": Feedback.State.PERMISSION_NEEDED,
		"Speech authorization was refused": Feedback.State.PERMISSION_NEEDED,
		"recognizer unavailable": Feedback.State.UNAVAILABLE,
		"no backend": Feedback.State.UNAVAILABLE,
		"no match": Feedback.State.NOT_UNDERSTOOD,
		"empty transcript": Feedback.State.NOT_UNDERSTOOD,
		"something exploded": Feedback.State.ERROR,
		"": Feedback.State.ERROR,
	}
	for reason: String in cases.keys():
		var got: int = Binder.classify_failure(reason)
		if got != int(cases[reason]):
			failures.append("classify_failure(\"%s\") gave %d, expected %d"
					% [reason, got, int(cases[reason])])
	return failures


func _test_transient_states_clear():
	var failures: Array = []
	for state in [Feedback.State.HEARD, Feedback.State.MATCHED,
			Feedback.State.NOT_UNDERSTOOD, Feedback.State.ERROR]:
		if Feedback.hold_seconds(state) <= 0.0:
			failures.append(("state %d never clears itself. A receipt that stays forever "
					+ "becomes the UI.") % state)
	# LISTENING must NOT self-clear: it ends when the microphone ends.
	if Feedback.hold_seconds(Feedback.State.LISTENING) > 0.0:
		failures.append("LISTENING auto-clears on a timer; it must end when listening ends, "
				+ "or the panel will claim to be deaf while the microphone is still open")

	var panel: Control = Feedback.new()
	panel.build()
	panel.set_state(Feedback.State.HEARD, "milk")
	if panel.get_state() != Feedback.State.HEARD:
		failures.append("set_state(HEARD) did not stick")
	panel.step(Feedback.HEARD_SECONDS + 0.1)
	if panel.get_state() != Feedback.State.IDLE:
		failures.append("HEARD did not fall back to IDLE after its hold; got %d"
				% panel.get_state())
	panel.free()
	return failures


func _test_the_panel_renders_its_copy():
	var failures: Array = []
	var panel: Control = Feedback.new()
	panel.build()

	panel.set_state(Feedback.State.IDLE)
	var idle_visible: bool = bool(panel.get_node("Panel").visible)
	if idle_visible:
		failures.append("the panel is visible at IDLE; it must get out of the way entirely")

	panel.set_state(Feedback.State.LISTENING)
	if not bool(panel.get_node("Panel").visible):
		failures.append("the panel is hidden while LISTENING, which is the one state the child "
				+ "most needs to see")
	var expected: Dictionary = Feedback.copy_for_state(Feedback.State.LISTENING)
	if panel.get_title_text() != String(expected["title"]):
		failures.append("the rendered title '%s' is not the copy '%s'"
				% [panel.get_title_text(), String(expected["title"])])

	panel.set_state(Feedback.State.HEARD, "milk")
	if not panel.get_title_text().to_lower().contains("milk"):
		failures.append("the rendered HEARD title does not show the word: '%s'"
				% panel.get_title_text())
	panel.free()
	return failures


## A stand-in for `SpeechService` with the same signals and the two methods the
## binder calls. Records `stop_listening()` so the early-stop path is provable.
class StubSpeech extends RefCounted:
	signal availability_changed(available: bool)
	signal permission_result(granted: bool)
	signal listening_started()
	signal listening_stopped()
	signal partial_recognized(text: String)
	signal recognized(text: String)
	signal recognition_failed(reason: String)
	var stops: int = 0
	func is_available() -> bool:
		return true
	func has_permission() -> bool:
		return true
	func stop_listening() -> void:
		stops += 1


func _test_binder_shows_the_live_guess_and_ends_listening_on_a_match():
	var failures: Array = []
	var panel: Control = Feedback.new()
	panel.build()
	var speech := StubSpeech.new()
	var binder = Binder.new()
	binder.bind(panel, speech, func(heard: String) -> bool: return heard.to_lower().contains("milk"))

	speech.listening_started.emit()
	if panel.get_state() != Feedback.State.LISTENING:
		failures.append("listening_started should show LISTENING")
	if panel.get_detail_text().contains("I hear"):
		failures.append("nothing has been heard yet; the detail must not claim otherwise")

	# A guess that does not satisfy the prompt: shown live, microphone stays open.
	speech.partial_recognized.emit("ba")
	if panel.get_state() != Feedback.State.LISTENING:
		failures.append("a non-matching partial must keep LISTENING, got %d" % panel.get_state())
	if not panel.get_detail_text().contains("ba"):
		failures.append("the live guess should be shown under 'I'm listening', got '%s'"
				% panel.get_detail_text())
	if speech.stops != 0:
		failures.append("a non-matching partial must not end listening")

	# A guess that satisfies the prompt: listening ends NOW, and the final that
	# the backend then reports is what completes the task.
	speech.partial_recognized.emit("milk")
	if speech.stops != 1:
		failures.append("a matching partial should end listening once, stops=%d" % speech.stops)
	if panel.get_state() != Feedback.State.PROCESSING:
		failures.append("after the early stop the panel should say 'One moment', got %d" % panel.get_state())
	speech.listening_stopped.emit()
	speech.recognized.emit("milk")
	if panel.get_state() != Feedback.State.MATCHED:
		failures.append("the final transcript should show MATCHED, got %d" % panel.get_state())
	if not panel.get_detail_text().contains("milk"):
		failures.append("MATCHED should show the word that earned it, got '%s'" % panel.get_detail_text())

	# A final that does not match: 'Try again' WITH the heard word and the tap reminder.
	speech.listening_started.emit()
	speech.recognized.emit("banana")
	if panel.get_state() != Feedback.State.NOT_UNDERSTOOD:
		failures.append("a non-matching final should show NOT_UNDERSTOOD, got %d" % panel.get_state())
	var retry_text: String = (panel.get_title_text() + " " + panel.get_detail_text()).to_lower()
	if not retry_text.contains("banana") or not retry_text.contains("tap"):
		failures.append("retry copy should name what was heard and offer the tap: '%s'" % retry_text)
	for word: String in BANNED:
		if retry_text.contains(word):
			failures.append("retry copy reads as failure ('%s' in '%s')" % [word, retry_text])

	# A blank partial is ignored; an empty final is a gentle retry.
	speech.partial_recognized.emit("   ")
	speech.recognized.emit("")
	if panel.get_state() != Feedback.State.NOT_UNDERSTOOD:
		failures.append("an empty final should be a gentle retry")

	# A timeout (nothing said in the window) is the gentle ERROR copy with a tap.
	speech.recognition_failed.emit("timeout")
	var timeout_text: String = (panel.get_title_text() + " " + panel.get_detail_text()).to_lower()
	if panel.get_state() != Feedback.State.ERROR or not timeout_text.contains("tap"):
		failures.append("a timeout should read as 'let's try again' with the tap offer: '%s'" % timeout_text)

	panel.free()
	return failures


func _test_binder_never_claims_a_match_it_cannot_check():
	var failures: Array = []
	var panel: Control = Feedback.new()
	panel.build()
	var speech := StubSpeech.new()
	var binder = Binder.new()
	binder.bind(panel, speech)  # no matched_checker

	speech.listening_started.emit()
	speech.partial_recognized.emit("milk")
	if speech.stops != 0:
		failures.append("without a checker the binder cannot know a partial matches; it must not stop")
	if panel.get_state() != Feedback.State.LISTENING or not panel.get_detail_text().contains("milk"):
		failures.append("without a checker a partial is still shown live")
	speech.recognized.emit("milk")
	if panel.get_state() != Feedback.State.HEARD:
		failures.append("without a checker a final is HEARD -- a receipt, not a verdict; got %d"
				% panel.get_state())
	if not panel.get_title_text().to_lower().contains("milk"):
		failures.append("HEARD should echo the word, got '%s'" % panel.get_title_text())
	panel.free()
	return failures


func _test_mock_backend_reports_what_it_heard_on_stop():
	var failures: Array = []
	var Mock: GDScript = load("res://scripts/speech/mock_speech_backend.gd")
	var partials: Array = []
	var finals: Array = []

	# The headless runner is a SceneTree whose timers never fire, so the two
	# timer callbacks are driven by hand in the order the timers would fire.
	var mock = Mock.new()
	mock.partial_recognized.connect(func(t: String) -> void: partials.append(t))
	mock.recognized.connect(func(t: String) -> void: finals.append(t))
	mock.start_listening()
	if not mock.is_listening():
		failures.append("the mock should be listening after start_listening()")
	if not partials.is_empty() or not finals.is_empty():
		failures.append("nothing should be reported before the delays elapse")
	mock._on_partial_due()
	if partials != ["milk"]:
		failures.append("the mock should offer its canned line as a partial first, got %s" % str(partials))
	if not finals.is_empty():
		failures.append("a partial is not a final")
	mock._on_delay_finished()
	if finals != ["milk"]:
		failures.append("the mock should then deliver the final once, got %s" % str(finals))
	if mock.is_listening():
		failures.append("the mock should have stopped after the final")

	# A stop with a partial pending reports it as the final (the native contract).
	partials.clear()
	finals.clear()
	mock.emit_partial = true
	mock._is_listening = true
	mock._partial_offered = true
	mock.stop_listening()
	if finals != ["milk"]:
		failures.append("stop after a partial should report that partial as recognized, got %s" % str(finals))
	if mock.is_listening():
		failures.append("stop_listening must stop")

	# A stop before anything was heard is quiet: no transcript, no failure.
	finals.clear()
	var fails: Array = []
	mock.recognition_failed.connect(func(r: String) -> void: fails.append(r))
	mock._is_listening = true
	mock._partial_offered = false
	mock.stop_listening()
	if not finals.is_empty() or not fails.is_empty():
		failures.append("a stop before any hypothesis must report nothing, got finals=%s fails=%s"
				% [str(finals), str(fails)])

	# A simulated failure offers no partial and fails honestly.
	partials.clear()
	finals.clear()
	fails.clear()
	mock.simulate_next_failure("mock_failure")
	mock.start_listening()
	mock._on_partial_due()
	mock._on_delay_finished()
	if not partials.is_empty() or not finals.is_empty() or fails != ["mock_failure"]:
		failures.append("a simulated failure must not leak a partial or a final; got partials=%s finals=%s fails=%s"
				% [str(partials), str(finals), str(fails)])
	return failures
