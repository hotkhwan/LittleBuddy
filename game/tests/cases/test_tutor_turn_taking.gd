extends RefCounted

## Turn-taking in the classroom (Agent T1, 2026-09-21; owner: "yes yes",
## repeated acknowledgements, cut replies). Deterministic, on the real scene
## with the real hands-free session in capture-only mode, the scripted
## provider and the paced local voice (autoloads detached by the runner).
##
##   * Aliz never talks over herself: no `speak` while `is_speaking`
##     (`overlapsRefused == 0` through a whole lesson) and no line is cut by
##     the lesson loop itself (`speechCuts == 0`).
##   * One acknowledgement per child answer: two finals 200 ms apart, a
##     partial then a final, a VAD end plus a recogniser final -> exactly one
##     praise line, one engine attempt.
##   * A cut line's boundary never runs: Repeat during a question re-asks
##     once and applies nothing; Repeat during praise is ignored and the
##     step still advances; End lesson mid-line applies nothing.
##   * A barge-in flushes: the cut sentence is never resumed; a lesson
##     switch never re-speaks the old lesson's question.
##   * Mic scope: capture false while thinking, paused, on the break card,
##     in the background and after Home; true (and the recogniser armed)
##     while Listening.
##   * Provider failure: exactly one fallback line, then listening.
##   * Silence: two repeats, then together + cards (unchanged).
##   * Praise composition across every shipped lesson: one opener, no
##     doubled phrase, consecutive correct answers differ.

const SCENE_PATH: String = "res://scenes/tutor/classroom.tscn"
const Turn := preload("res://scripts/tutor/turn/tutor_turn.gd")
const Hud := preload("res://scripts/tutor/ui/tutor_hud.gd")
const ScriptedScript := preload("res://scripts/tutor/providers/scripted_conversation_provider.gd")
const LessonEngineScript := preload("res://scripts/tutor/lesson/lesson_engine.gd")

const STEP: float = 0.1
const MAX_STEPS: int = 6000
const LESSONS: Array[String] = ["english_colors_fruits", "animals_cat_dog", "colors_red_blue", "numbers_one_two_three", "everyday_cup_spoon"]


class FakeSave extends RefCounted:
	var settings: Dictionary = {}
	var stars: int = 0
	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value
	func save_profile() -> bool:
		return true
	func add_stars(amount: int) -> int:
		stars += amount
		return stars
	func get_profile() -> Dictionary:
		return {"settings": settings, "unlockedRooms": [], "stars": stars}


## Watches the synthesis provider: started/finished pairing and overlap.
## Its `finished` handler must run BEFORE the scene's (which starts the next
## line from inside `finished`), so the scene's connection is re-made after.
class VoiceWatch extends RefCounted:
	var started: Array = []
	var finished: Array = []
	var open: int = 0
	var overlaps: int = 0
	func attach(synth: Node, scene: Node) -> void:
		var scene_handler: Callable = Callable(scene, "_on_speech_finished")
		var rewire: bool = synth.finished.is_connected(scene_handler)
		if rewire:
			synth.finished.disconnect(scene_handler)
		synth.started.connect(func(t: String) -> void:
			started.append(t)
			open += 1
			if open > 1:
				overlaps += 1)
		synth.finished.connect(func(t: String) -> void:
			finished.append(t)
			open = maxi(open - 1, 0))
		if rewire:
			synth.finished.connect(scene_handler)


func test_name() -> String:
	return "tutor_turn_taking"


func run():
	var failures: Array = []
	failures.append_array(_test_never_talks_over_itself())
	failures.append_array(_test_one_acknowledgement_per_answer())
	failures.append_array(_test_repeat_never_runs_the_cut_boundary())
	failures.append_array(_test_pause_and_buttons_never_run_the_cut_boundary())
	failures.append_array(_test_barge_in_flushes_and_never_resumes())
	failures.append_array(_test_mic_scope_per_state())
	failures.append_array(_test_provider_failure_speaks_once())
	failures.append_array(_test_silence_two_repeats_then_together())
	failures.append_array(_test_praise_composition_every_lesson())
	return failures


# ---------------------------------------------------------------------------

func _make(save: Object = null) -> Node:
	var packed: PackedScene = load(SCENE_PATH)
	var scene: Node = packed.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(scene)
	scene.build()
	scene.set_save_service(save if save != null else FakeSave.new())
	scene.enable_simulation(true)
	if scene.quota() != null and scene.quota().has_method("pause_for"):
		scene.quota().pause_for("test")  # these cases are about turns, not minutes
	scene.begin_lesson()
	return scene


func _free(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		if scene.get_parent() != null:
			scene.get_parent().remove_child(scene)
		scene.free()


func _until(scene: Node, predicate: Callable, max_steps: int = MAX_STEPS) -> int:
	for i: int in range(max_steps):
		if predicate.call():
			return i
		scene.advance(STEP)
	return -1


func _ready(scene: Node) -> bool:
	if scene.state() != "listening":
		return false
	var session: Object = scene.voice_session()
	if session != null and session.has_method("is_simulating") and bool(session.call("is_simulating")):
		return false
	return scene.hud().banner_kind() == Hud.BANNER_LISTENING


func _reach_first_question(scene: Node) -> bool:
	if _until(scene, func() -> bool: return _ready(scene), 400) < 0:
		return false
	scene.simulate("correct")  # "fruits" -> English Basics
	return _until(scene, func() -> bool: return _ready(scene) and not scene.is_choosing_subject(), 800) >= 0


func _capturing(scene: Node) -> bool:
	var session: Object = scene.voice_session()
	return session != null and session.has_method("is_capturing") and bool(session.call("is_capturing"))


func _recogniser_open(scene: Node) -> bool:
	var session: Object = scene.voice_session()
	if session == null or not session.has_method("diagnostics"):
		return false
	return bool((session.call("diagnostics") as Dictionary).get("recognitionOpen", false))


func _step_index(scene: Node) -> int:
	var progress: Dictionary = scene.lesson_engine().call("progress")
	return int(progress.get("stepIndex", -1))


# ---------------------------------------------------------------------------

func _test_never_talks_over_itself():
	var failures: Array = []
	var scene: Node = _make()
	var watch := VoiceWatch.new()
	watch.attach(scene.synthesis(), scene)
	var lines_at_attach: int = int(scene.turn_taking_counters().get("linesStarted", 0))  # the welcome already went out
	var answers: Array = ["correct", "wrong", "correct", "cough", "pause_then_finish", "wrong", "wrong", "correct"]
	var asked: int = 0
	var steps: int = 0
	while not scene.is_lesson_complete() and steps < MAX_STEPS:
		steps += 1
		scene.advance(STEP)
		if _ready(scene):
			scene.simulate(answers[asked % answers.size()])
			asked += 1
	if not scene.is_lesson_complete():
		failures.append("the lesson did not complete (state %s)" % scene.state())
	if watch.overlaps != 0:
		failures.append("the voice was started %d time(s) while a line was still open" % watch.overlaps)
	var counters: Dictionary = scene.turn_taking_counters()
	if int(counters.get("overlapsRefused", 0)) != 0 or int(counters.get("speechCuts", 0)) != 0:
		failures.append("the lesson loop itself never cuts or overlaps a line: %s" % str(counters))
	if int(counters.get("linesStarted", 0)) - lines_at_attach != watch.started.size():
		failures.append("every line the scene started reached the voice once: %s vs %d" % [str(counters), watch.started.size()])
	# No doubled phrase and at most one opener in anything spoken.
	for turn: Dictionary in scene.turn_log():
		var said: String = String(turn.get("speech", ""))
		if Turn.dedupe_adjacent_phrases(said) != said:
			failures.append("doubled phrase spoken: '%s'" % said)
		var openers: int = 0
		for sentence: String in Turn.split_sentences(said):
			if Turn.is_acknowledgement(Turn.phrase_key(sentence)):
				openers += 1
		if openers > 1:
			failures.append("%d openers in one line: '%s'" % [openers, said])
	_free(scene)
	return failures


func _test_one_acknowledgement_per_answer():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		_free(scene)
		return ["never reached the first question"]
	var session: Object = scene.voice_session()
	var answer: String = String(scene.current_step().get("expectedAnswers", ["apple"])[0])
	# Two finals 200 ms apart (a VAD end plus a recogniser final, a recogniser
	# that reports twice): one answer.
	var lines_before: int = scene.turn_log().size()
	session.child_speech_ended.emit(answer)
	scene.advance(STEP)
	scene.advance(STEP)
	session.child_speech_ended.emit(answer)
	if _until(scene, func() -> bool: return scene.state() == "speaking", 20) < 0:
		failures.append("the first final should be answered (state %s)" % scene.state())
	_until(scene, func() -> bool: return _ready(scene), 400)
	var praise_lines: int = 0
	for turn: Dictionary in scene.turn_log().slice(lines_before):
		if String(turn.get("emotion", "")) == "happy":
			praise_lines += 1
	if praise_lines != 1:
		failures.append("two finals 200 ms apart must earn exactly one praise line, got %d: %s" % [praise_lines, str(scene.turn_log().slice(lines_before))])
	var counters: Dictionary = scene.turn_taking_counters()
	if int(counters.get("answersDropped", 0)) != 1:
		failures.append("the second final is counted as dropped: %s" % str(counters))
	if _step_index(scene) < 2:
		failures.append("the answered step advanced once (index %d)" % _step_index(scene))
	# Partial then final: one answer, one attempt.
	var attempts_before: int = int(scene.lesson_engine().call("attempts"))
	var index_before: int = _step_index(scene)
	answer = String(scene.current_step().get("expectedAnswers", ["red"])[0])
	lines_before = scene.turn_log().size()
	session.partial_transcript.emit(answer.left(2))
	scene.advance(STEP)
	session.child_speech_ended.emit(answer)
	scene.advance(STEP)
	session.child_speech_ended.emit(answer)  # the recogniser's own late final
	_until(scene, func() -> bool: return _ready(scene) and _step_index(scene) != index_before, 400)
	praise_lines = 0
	for turn: Dictionary in scene.turn_log().slice(lines_before):
		if String(turn.get("emotion", "")) == "happy":
			praise_lines += 1
	if praise_lines != 1:
		failures.append("partial + final + late final must earn exactly one praise line, got %d" % praise_lines)
	if int(scene.lesson_engine().call("attempts")) > 1 and attempts_before == 0 and _step_index(scene) == index_before:
		failures.append("the answer was judged more than once")
	_free(scene)
	return failures


func _test_repeat_never_runs_the_cut_boundary():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		_free(scene)
		return ["never reached the first question"]
	var watch := VoiceWatch.new()
	watch.attach(scene.synthesis(), scene)
	# Repeat during the question: the question is re-asked once, nothing else.
	scene.hud().press("repeat")
	if scene.state() != "speaking":
		failures.append("Repeat re-asks (state %s)" % scene.state())
	var question: String = String(scene.current_turn().get("speech", ""))
	scene.advance(STEP)
	scene.hud().press("repeat")  # a second tap mid-line: cut and re-ask, once
	var cuts_after_two: int = int(scene.turn_taking_counters().get("speechCuts", 0))
	if cuts_after_two != 1:
		failures.append("a Repeat mid-line cuts the line once, counted: %s" % str(scene.turn_taking_counters()))
	if scene.synthesis().current_text() != question:
		failures.append("Repeat says the question, not a different line: '%s'" % scene.synthesis().current_text())
	var index_before: int = _step_index(scene)
	if _until(scene, func() -> bool: return _ready(scene), 400) < 0:
		failures.append("after Repeat the mic reopens (state %s)" % scene.state())
	if _step_index(scene) != index_before:
		failures.append("Repeat applied a lesson action (step %d -> %d)" % [index_before, _step_index(scene)])
	if watch.overlaps != 0:
		failures.append("Repeat overlapped the voice %d time(s)" % watch.overlaps)
	# Repeat during praise: ignored; the praise plays out and the step advances.
	scene.simulate("correct")
	if _until(scene, func() -> bool: return scene.state() == "speaking" and String(scene.current_turn().get("emotion", "")) == "happy", 200) < 0:
		failures.append("the correct answer is praised (state %s)" % scene.state())
	var praise: String = String(scene.current_turn().get("speech", ""))
	scene.advance(STEP)
	scene.hud().press("repeat")
	if String(scene.current_turn().get("speech", "")) != praise or not scene.synthesis().is_speaking():
		failures.append("Repeat never cuts praise: now saying '%s'" % scene.synthesis().current_text())
	if _until(scene, func() -> bool: return _step_index(scene) == index_before + 1 and _ready(scene), 400) < 0:
		failures.append("the praised step still advances after a Repeat press (step %d, state %s)" % [_step_index(scene), scene.state()])
	var hint_after: bool = false
	for turn: Dictionary in scene.turn_log().slice(scene.turn_log().size() - 3):
		if String(turn.get("lessonAction", "")) == "give_hint":
			hint_after = true
	if hint_after:
		failures.append("a correct answer must never be followed by a hint")
	if watch.overlaps != 0:
		failures.append("praise + Repeat overlapped the voice %d time(s)" % watch.overlaps)
	_free(scene)
	return failures


func _test_pause_and_buttons_never_run_the_cut_boundary():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		_free(scene)
		return ["never reached the first question"]
	scene.simulate("correct")
	if _until(scene, func() -> bool: return scene.state() == "speaking" and String(scene.current_turn().get("emotion", "")) == "happy", 200) < 0:
		failures.append("the correct answer is praised (state %s)" % scene.state())
	var index_before: int = _step_index(scene)
	var lines_before: int = scene.turn_log().size()
	# End lesson mid-praise: paused, silent, mic held, nothing applied.
	scene.hud().press("end")
	if scene.state() != "paused" or scene.synthesis().is_speaking():
		failures.append("End lesson pauses and silences (state %s speaking %s)" % [scene.state(), str(scene.synthesis().is_speaking())])
	for i: int in range(20):
		scene.advance(STEP)
	if scene.turn_log().size() != lines_before:
		failures.append("nothing is spoken while paused: %s" % str(scene.turn_log().slice(lines_before)))
	if _capturing(scene):
		failures.append("paused: the microphone must be held")
	if _step_index(scene) != index_before:
		failures.append("the cut praise's advance must not run on pause (step %d -> %d)" % [index_before, _step_index(scene)])
	# Keep going: the step is re-asked (one line), the mic reopens.
	scene.hud().exit_confirm().press_keep()
	if scene.state() != "speaking":
		failures.append("Keep going re-asks (state %s)" % scene.state())
	if _until(scene, func() -> bool: return _ready(scene), 400) < 0:
		failures.append("after Keep going the mic reopens (state %s)" % scene.state())
	if not _capturing(scene):
		failures.append("listening again: capture must be on")
	# Home mid-line: done, nothing more spoken, session closed.
	scene.hud().press("repeat")
	lines_before = scene.turn_log().size()
	scene.leave_to_home()
	for i: int in range(5):
		scene.advance(STEP)
	if scene.state() != "done" or scene.turn_log().size() != lines_before or _capturing(scene):
		failures.append("Home mid-line: done, silent, mic closed (state %s lines +%d capturing %s)" % [scene.state(), scene.turn_log().size() - lines_before, str(_capturing(scene))])
	_free(scene)
	return failures


func _test_barge_in_flushes_and_never_resumes():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		_free(scene)
		return ["never reached the first question"]
	var watch := VoiceWatch.new()
	watch.attach(scene.synthesis(), scene)
	var fruits_question: String = String(scene.current_turn().get("speech", ""))
	scene.hud().press("repeat")
	var lines_before: int = scene.turn_log().size()
	scene.simulate("interrupt")  # "Wait! I want a dog!" over the question
	if _until(scene, func() -> bool: return scene.state() == "listening", 20) < 0:
		failures.append("a barge-in opens the mic (state %s)" % scene.state())
	if scene.synthesis().is_speaking():
		failures.append("a barge-in cuts the line at once")
	if _until(scene, func() -> bool: return scene.state() == "speaking", 60) < 0:
		failures.append("the interjection is answered (state %s)" % scene.state())
	var reply: String = String(scene.current_turn().get("speech", ""))
	if reply == fruits_question:
		failures.append("the cut question must not be resumed as the reply to the barge-in")
	# The switch: the next lines are the animals lesson; the fruits question is never spoken again.
	if _until(scene, func() -> bool: return _ready(scene) and scene.current_lesson_id() == "animals_cat_dog", 600) < 0:
		failures.append("'I want a dog' switches to the animals lesson (lesson %s, state %s)" % [scene.current_lesson_id(), scene.state()])
	for turn: Dictionary in scene.turn_log().slice(lines_before):
		if String(turn.get("speech", "")) == fruits_question and String(turn.get("visual", {}).get("assetId", "")) == "apple_red":
			failures.append("the old lesson's question was spoken after the switch: %s" % str(scene.turn_log().slice(lines_before)))
			break
	if watch.overlaps != 0:
		failures.append("the barge-in path overlapped the voice %d time(s)" % watch.overlaps)
	# Barge-in mid-praise: exactly one line follows before the mic reopens.
	scene.simulate("correct")
	if _until(scene, func() -> bool: return scene.state() == "speaking" and String(scene.current_turn().get("emotion", "")) == "happy", 200) < 0:
		failures.append("praised (state %s)" % scene.state())
	lines_before = scene.turn_log().size()
	scene.simulate("interrupt", "look a bird outside")
	_until(scene, func() -> bool: return _ready(scene), 400)
	var after: Array = scene.turn_log().slice(lines_before)
	if after.size() != 1:
		failures.append("an idle interruption of praise is followed by exactly one line (the next question), got %s" % str(after))
	_free(scene)
	return failures


func _test_mic_scope_per_state():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		_free(scene)
		return ["never reached the first question"]
	if not _capturing(scene):
		failures.append("listening: capture on")
	if _until(scene, func() -> bool: return _recogniser_open(scene), 10) < 0:
		failures.append("listening: the recogniser is armed within a few frames")
	var start_diag: Dictionary = scene.voice_session().call("diagnostics")
	if int(start_diag.get("cancelledOpen", 0)) != 0:
		failures.append("from the welcome to the first question no open recogniser was cancelled by Aliz: %s" % str(start_diag))
	# Thinking: held.
	scene.simulate("correct")
	if _until(scene, func() -> bool: return scene.state() == "thinking", 60) < 0:
		failures.append("thinking reached (state %s)" % scene.state())
	elif _capturing(scene) or _recogniser_open(scene):
		failures.append("thinking: the microphone is held (capturing %s open %s)" % [str(_capturing(scene)), str(_recogniser_open(scene))])
	# Speaking (praise) and the celebrate beat: gated, no recogniser opened.
	_until(scene, func() -> bool: return scene.state() == "speaking", 60)
	var armed_before: int = int((scene.voice_session().call("diagnostics") as Dictionary).get("armed", 0))
	_until(scene, func() -> bool: return scene.state() == "celebrate", 200)
	if _recogniser_open(scene):
		failures.append("celebrate: no recogniser is open")
	if _until(scene, func() -> bool: return _ready(scene) and _recogniser_open(scene), 400) < 0:
		failures.append("the next question opens the mic")
	var diag: Dictionary = scene.voice_session().call("diagnostics")
	if int(diag.get("armed", 0)) - armed_before != 1:
		failures.append("praise -> celebrate -> question arms the recogniser exactly once, got %d" % (int(diag.get("armed", 0)) - armed_before))
	if int(diag.get("cancelledOpen", 0)) != 0:
		failures.append("no open recogniser was cancelled by Aliz's own reply: %s" % str(diag))
	# Paused: held; kept: reopened.
	scene.hud().press("end")
	scene.advance(STEP)
	if _capturing(scene):
		failures.append("paused: held")
	scene.hud().exit_confirm().press_keep()
	if _until(scene, func() -> bool: return _ready(scene) and _capturing(scene), 400) < 0:
		failures.append("kept: listening with capture on")
	# Background: closed; resume card; tap: reopened.
	scene.go_background()
	if _capturing(scene) or bool(scene.voice_session().call("is_active")):
		failures.append("background: the session is closed")
	scene.return_from_background()
	scene.hud().press_resume()
	if _until(scene, func() -> bool: return _ready(scene) and _capturing(scene), 400) < 0:
		failures.append("resume: listening with capture on")
	# Break (parent stop): closed.
	scene.hud().press("end")
	scene.hud().exit_confirm().press_stop()
	if scene.state() != "break" or _capturing(scene) or bool(scene.voice_session().call("is_active")):
		failures.append("break: the session is closed")
	_free(scene)
	return failures


func _test_provider_failure_speaks_once():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		_free(scene)
		return ["never reached the first question"]
	var watch := VoiceWatch.new()
	watch.attach(scene.synthesis(), scene)
	var lines_before: int = scene.turn_log().size()
	scene.provider().provider_failed.emit("backend unreachable")
	if String(scene.current_turn().get("speech", "")) != "Let's try together!":
		failures.append("the fallback line is spoken: %s" % str(scene.current_turn().get("speech")))
	if _until(scene, func() -> bool: return _ready(scene), 400) < 0:
		failures.append("listening again after the fallback (state %s)" % scene.state())
	if scene.turn_log().size() - lines_before != 1 or watch.started.size() != 1:
		failures.append("exactly one fallback utterance: %d turn(s), %d voice start(s)" % [scene.turn_log().size() - lines_before, watch.started.size()])
	# A failure while Aliz is mid-line: the fallback replaces it, once, no overlap.
	scene.hud().press("repeat")
	lines_before = scene.turn_log().size()
	var starts_before: int = watch.started.size()
	scene.provider().provider_failed.emit("backend unreachable")
	_until(scene, func() -> bool: return _ready(scene), 400)
	if scene.turn_log().size() - lines_before != 1 or watch.started.size() - starts_before != 1 or watch.overlaps != 0:
		failures.append("a failure mid-line: one fallback, no overlap (turns +%d, starts +%d, overlaps %d)" % [scene.turn_log().size() - lines_before, watch.started.size() - starts_before, watch.overlaps])
	_free(scene)
	return failures


func _test_silence_two_repeats_then_together():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		_free(scene)
		return ["never reached the first question"]
	var question: String = String(scene.current_turn().get("speech", ""))
	var lines_before: int = scene.turn_log().size()
	var index_before: int = _step_index(scene)
	var cards_after_second_repeat: bool = false
	var elapsed: float = 0.0
	while elapsed < 80.0 and _step_index(scene) == index_before:
		scene.advance(STEP)
		elapsed += STEP
		var run: int = 0
		for turn: Dictionary in scene.turn_log().slice(lines_before):
			run = run + 1 if String(turn.get("speech", "")) == question else 0
		if run >= 2 and scene.state() == "listening" and not scene.hud().answer_cards_shown().is_empty():
			cards_after_second_repeat = true
	# Per unanswered attempt: the question, two repeats, then a together /
	# hint / taught line -- never the same question a fourth time in a row.
	var longest_run: int = 0
	var run_now: int = 0
	var together: int = 0
	for turn: Dictionary in scene.turn_log().slice(lines_before):
		var said: String = String(turn.get("speech", ""))
		if said == question:
			run_now += 1
			longest_run = maxi(longest_run, run_now)
		else:
			run_now = 0
			if said.contains("try together") or said.contains("Say it with me") or said.contains("Together now"):
				together += 1
	if longest_run != 2:
		failures.append("silence: the question is repeated exactly twice per attempt, longest run %d: %s" % [longest_run, str(scene.turn_log().slice(lines_before))])
	if together < 1:
		failures.append("silence: then Aliz says it together")
	if not cards_after_second_repeat:
		failures.append("silence: after the second repeat the answer cards are up")
	if _step_index(scene) == index_before:
		failures.append("silence: the lesson moves on within %.0f s (state %s)" % [elapsed, scene.state()])
	_free(scene)
	return failures


## Every shipped lesson, every ask step, the step's own success line: one
## opener, no doubled phrase, and consecutive correct answers differ.
func _test_praise_composition_every_lesson():
	var failures: Array = []
	for lesson_id: String in LESSONS:
		var engine: RefCounted = LessonEngineScript.new()
		if not engine.load_lesson(lesson_id):
			failures.append("%s did not load" % lesson_id)
			continue
		var provider: RefCounted = ScriptedScript.new()
		provider.set_engine(engine)
		provider.begin_session(lesson_id)
		var previous: String = ""
		var guard: int = 0
		while not bool(engine.is_complete()) and guard < 80:
			guard += 1
			var step: Dictionary = engine.current_step()
			if String(step.get("kind", "")) == "ask" or String(step.get("kind", "")) == "sound":
				var answers: Array = step.get("expectedAnswers", [])
				var verdict: Dictionary = engine.evaluate(String(answers[0]) if not answers.is_empty() else "")
				var turn: Dictionary = provider.turn_for_verdict(step, verdict, "answer")
				var said: String = String(turn.get("speech", ""))
				if Turn.dedupe_adjacent_phrases(said) != said:
					failures.append("%s/%s: doubled phrase '%s'" % [lesson_id, step.get("stepId"), said])
				var openers: int = 0
				for sentence: String in Turn.split_sentences(said):
					if Turn.is_acknowledgement(Turn.phrase_key(sentence)):
						openers += 1
				if openers > 1:
					failures.append("%s/%s: %d openers in '%s'" % [lesson_id, step.get("stepId"), openers, said])
				var first: String = Turn.split_sentences(said)[0] if not Turn.split_sentences(said).is_empty() else ""
				if not previous.is_empty() and first == previous and Turn.is_acknowledgement(Turn.phrase_key(first)):
					failures.append("%s/%s: consecutive praise opens the same way ('%s')" % [lesson_id, step.get("stepId"), first])
				previous = first
				engine.advance()
				# The step that follows praise loses its own leading acknowledgement.
				var following: Dictionary = engine.current_step()
				if not following.is_empty() and String(following.get("kind", "")) != "celebrate":
					var opened: Dictionary = provider.open_turn(following)
					var text: String = String(opened.get("speech", ""))
					if Turn.starts_with_acknowledgement(text) and Turn.split_sentences(text).size() > 1:
						failures.append("%s/%s: praised twice across the boundary: '%s'" % [lesson_id, following.get("stepId"), text])
				continue
			engine.advance()
	return failures
