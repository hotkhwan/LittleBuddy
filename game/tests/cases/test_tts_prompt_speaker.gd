extends RefCounted
## `PromptSpeaker` makes the lines that are currently only *displayed* audible --
## a mission's `introPhrase` / `outroPhrase` -- without making the lines a mode
## handler already speaks stutter.

const PromptSpeakerScript := preload("res://scripts/speech/prompt_speaker.gd")
const TtsServiceScript := preload("res://scripts/speech/tts_service.gd")
const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")


func test_name() -> String:
	return "tts_prompt_speaker"


func run():
	var failures: Array = []
	failures.append_array(_test_speaks_an_unspoken_line())
	failures.append_array(_test_does_not_double_speak())
	failures.append_array(_test_queues_never_interrupts())
	failures.append_array(_test_attach_is_safe())
	failures.append_array(_test_mission_intro_and_outro_become_audible())
	return failures


func _make_tts():
	var tts = TtsServiceScript.new()
	var timers: Array = []
	var started: Array = []
	tts.set_timer_factory(
		func(_duration: float, callback: Callable) -> void: timers.append(callback)
	)
	tts.speech_started.connect(func(text: String) -> void: started.append(text))
	return {"tts": tts, "timers": timers, "started": started}


func _test_speaks_an_unspoken_line():
	var failures: Array = []
	var harness = _make_tts()
	var speaker: Node = PromptSpeakerScript.new()
	speaker.set_tts(harness["tts"])

	speaker.on_prompt("Good morning!", "อรุณสวัสดิ์")
	speaker.flush()

	var spoken: Array = harness["started"]
	if not spoken.has("Good morning!"):
		failures.append("a displayed-only line should be spoken, got %s" % str(spoken))
	if spoken.has("อรุณสวัสดิ์"):
		failures.append("the Thai hint must never be handed to the English voice")

	speaker.free()
	harness["tts"].free()
	return failures


func _test_does_not_double_speak():
	var failures: Array = []
	var harness = _make_tts()
	var tts = harness["tts"]
	var speaker: Node = PromptSpeakerScript.new()
	speaker.set_tts(tts)

	# The order a mode handler produces: emit the prompt, then speak it itself.
	speaker.on_prompt("Wake up, Buddy!", "")
	tts.speak("Wake up, Buddy!")
	speaker.flush()

	var count: int = 0
	for line in harness["started"]:
		if String(line) == "Wake up, Buddy!":
			count += 1
	if count != 1:
		failures.append("a line already spoken by the mode must not be repeated (spoken %dx)" % count)
	if tts.get_pending_count() != 0:
		failures.append("nothing should have been queued behind an already-spoken line")

	# Also covered when the line is merely QUEUED by someone else.
	harness["started"].clear()
	tts.speak("Now the milk.", false)
	speaker.on_prompt("Now the milk.", "")
	speaker.flush()
	if tts.get_pending_texts().count("Now the milk.") > 1:
		failures.append("an already-queued line must not be queued twice")

	speaker.free()
	tts.free()
	return failures


func _test_queues_never_interrupts():
	var failures: Array = []
	var harness = _make_tts()
	var tts = harness["tts"]
	var speaker: Node = PromptSpeakerScript.new()
	speaker.set_tts(tts)

	tts.speak("Let's brush our teeth.")
	speaker.on_prompt("Great job! All done.", "")
	speaker.flush()

	if tts.get_current_text() != "Let's brush our teeth.":
		failures.append(
			"the speaker must never cut off a line already being spoken (current is '%s')"
			% tts.get_current_text()
		)
	if not tts.get_pending_texts().has("Great job! All done."):
		failures.append("the new line should be queued behind the current one")

	speaker.free()
	tts.free()
	return failures


func _test_attach_is_safe():
	var failures: Array = []
	if PromptSpeakerScript.attach(null, null) != null:
		failures.append("attach(null, null) should return null, not crash or half-wire")

	var harness = _make_tts()
	var runner: Node = MissionRunnerScript.new()
	if PromptSpeakerScript.attach(runner, harness["tts"], "no_such_signal") != null:
		failures.append("attaching to a signal that does not exist should return null")

	var speaker: Node = PromptSpeakerScript.attach(runner, harness["tts"])
	if speaker == null:
		failures.append("attach() should return the speaker for a real prompt_changed signal")
	elif speaker.get_parent() != runner:
		failures.append("the speaker should parent itself to the source so it shares its lifetime")

	runner.free()  # frees the speaker with it
	harness["tts"].free()
	return failures


## End-to-end: the real mission intro and outro strings, through the real runner.
func _test_mission_intro_and_outro_become_audible():
	var failures: Array = []
	var library = ContentLibraryScript.create()
	if library == null:
		return ["could not create ContentLibrary"]

	var mission_id: String = ""
	var intro: String = ""
	var outro: String = ""
	for mission in library.get_missions():
		if typeof(mission) != TYPE_DICTIONARY:
			continue
		if String((mission as Dictionary).get("chapterId", "")) != "ch3":
			continue
		mission_id = String((mission as Dictionary).get("missionId", ""))
		intro = String((mission as Dictionary).get("introPhrase", "")).strip_edges()
		outro = String((mission as Dictionary).get("outroPhrase", "")).strip_edges()
		if not intro.is_empty() and not outro.is_empty():
			break

	if mission_id.is_empty():
		return ["no ch3 mission found to check intro/outro speech"]

	var harness = _make_tts()
	var runner: Node = MissionRunnerScript.new()
	var speaker: Node = PromptSpeakerScript.attach(runner, harness["tts"])
	if speaker == null:
		runner.free()
		harness["tts"].free()
		return ["attach() failed for a real MissionRunner"]

	runner.set_seed(1)
	runner.start_mission(mission_id, library, {"tts": harness["tts"], "library": library})
	speaker.flush()

	var heard: Array = harness["started"].duplicate()
	heard.append_array(harness["tts"].get_pending_texts())
	if not intro.is_empty() and not heard.has(intro):
		failures.append(
			"mission intro \"%s\" is still never spoken (heard: %s)" % [intro, str(heard)]
		)

	runner.cancel()
	runner.free()
	harness["tts"].free()
	return failures
