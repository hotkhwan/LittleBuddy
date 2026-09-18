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
