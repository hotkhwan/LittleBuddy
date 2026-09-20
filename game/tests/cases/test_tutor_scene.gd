extends RefCounted

## The classroom, driven headless from the outside: it loads, a whole
## hands-free lesson (welcome, subject choice, questions answered right, wrong,
## with a cough, with a pause and by interrupting Aliz) runs to the break card
## through the LessonEngine with no hang, every button routes, Home leaves to
## the title screen, the quota ends the lesson with Aliz's closing at a
## boundary and survives a restart, the microphone is captured only inside a
## session, the background rule holds, the no-recogniser fallbacks appear, and
## nothing the HUD draws lands on Aliz's face at either shipped aspect ratio.
##
## Everything is driven through `advance(delta)` and the scene's public
## surface -- the same calls `_process()` and the buttons make -- with the
## autoloads detached by the runner, so the on-device speech path is absent
## and the DEV simulation (through the voice session's hook) stands in.

const SCENE_PATH: String = "res://scenes/tutor/classroom.tscn"
const HOME_PATH: String = "res://scenes/main/main.tscn"
const Turn := preload("res://scripts/tutor/turn/tutor_turn.gd")
const Hud := preload("res://scripts/tutor/ui/tutor_hud.gd")
const Indicator := preload("res://scripts/tutor/ui/tutor_mic_indicator.gd")
const ExitConfirm := preload("res://scripts/tutor/ui/tutor_exit_confirm.gd")
const SceneScript := preload("res://scripts/tutor/tutor_scene.gd")

const MAX_TRIANGLES: int = 40000
const STEP: float = 0.1
const MAX_STEPS: int = 8000
const SIZES: Array = [Vector2(1334, 750), Vector2(2340, 1080)]


## A dictionary-backed SaveService: the methods the scene, the engine and the
## quota duck-type, and nothing that could touch `user://`.
class FakeSave extends RefCounted:
	var settings: Dictionary = {}
	var stars: int = 0
	var saves: int = 0
	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value
	func save_profile() -> bool:
		saves += 1
		return true
	func add_stars(amount: int) -> int:
		stars += amount
		return stars
	func get_profile() -> Dictionary:
		return {"settings": settings, "unlockedRooms": [], "stars": stars}


func test_name() -> String:
	return "tutor_scene"


func run():
	var failures: Array = []
	failures.append_array(_test_scene_loads_and_is_within_budget())
	failures.append_array(_test_full_hands_free_lesson_completes())
	failures.append_array(_test_barge_in_and_partials())
	failures.append_array(_test_interjection_switches_the_item())
	failures.append_array(_test_idle_interruption_is_not_an_attempt())
	failures.append_array(_test_no_recogniser_fallbacks())
	failures.append_array(_test_simulation_is_refused_when_off())
	failures.append_array(_test_every_button_routes())
	failures.append_array(_test_home_and_free_play_leave())
	failures.append_array(_test_quota_closes_at_boundary_and_persists())
	failures.append_array(_test_background_rule())
	failures.append_array(_test_provider_failure_falls_back())
	failures.append_array(_test_nothing_covers_alizs_face())
	failures.append_array(_test_break_card_copy())
	return failures


# ---------------------------------------------------------------------------

func _make(save: Object = null, sim: bool = true) -> Node:
	var packed: PackedScene = load(SCENE_PATH)
	var scene: Node = packed.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(scene)
	scene.build()
	scene.set_save_service(save if save != null else FakeSave.new())
	scene.enable_simulation(sim)
	scene.begin_lesson()
	return scene


func _free(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		if scene.get_parent() != null:
			scene.get_parent().remove_child(scene)
		scene.free()


## Steps the scene until `predicate` holds. Returns the step count, or -1.
func _until(scene: Node, predicate: Callable, max_steps: int = MAX_STEPS) -> int:
	for i: int in range(max_steps):
		if predicate.call():
			return i
		scene.advance(STEP)
	return -1


## The mic is open for the child and no simulated utterance is in flight.
func _ready_to_answer(scene: Node) -> bool:
	if scene.state() != "listening":
		return false
	var session: Object = scene.voice_session()
	if session != null and session.has_method("is_simulating") and bool(session.call("is_simulating")):
		return false
	return scene.hud().banner_kind() == Hud.BANNER_LISTENING


## Runs from the welcome to the first question of the lesson.
func _reach_first_question(scene: Node) -> bool:
	if _until(scene, func() -> bool: return _ready_to_answer(scene), 400) < 0:
		return false
	scene.simulate("correct")  # "fruits" -> English Basics
	return _until(scene, func() -> bool:
		return _ready_to_answer(scene) and not scene.is_choosing_subject(), 800) >= 0


func _test_scene_loads_and_is_within_budget():
	var failures: Array = []
	if not ResourceLoader.exists(SCENE_PATH):
		return ["%s is missing" % SCENE_PATH]
	var scene: Node = _make()
	if scene.classroom() == null:
		failures.append("the classroom was not built")
	else:
		var room_tris: int = scene.classroom().count_triangles()
		var all_tris: int = scene.classroom().count_triangles_under(scene)
		if room_tris <= 500:
			failures.append("the classroom is suspiciously empty: %d triangles" % room_tris)
		if all_tris > MAX_TRIANGLES:
			failures.append("scene is %d triangles against the %d ceiling" % [all_tris, MAX_TRIANGLES])
		if scene.classroom().prop_source("table") != "primitive":
			failures.append("Aliz's table stays the primitive her seat is fitted to")
		if FileAccess.file_exists("res://content/tutor/props_manifest.json") \
				and ResourceLoader.exists("res://assets/tutor/props/fruit_set.glb") \
				and scene.classroom().prop_source("fruit_set") != "glb":
			failures.append("the manifest names fruit_set.glb; it should stand in for the primitive fruit")
	if scene.aliz() == null:
		failures.append("Aliz is not in the classroom")
	elif not scene.is_seated():
		failures.append("Aliz is not seated")
	if scene.state() != "speaking":
		failures.append("entering the classroom should have Aliz welcoming the child, got '%s'" % scene.state())
	if String(scene.current_turn().get("speech", "")) != SceneScript.WELCOME_TEXT:
		failures.append("the first thing Aliz says is the welcome, got %s" % str(scene.current_turn().get("speech")))
	if not scene.is_choosing_subject():
		failures.append("after the welcome the scene should be waiting for a subject")
	var lights: int = _count_lights(scene)
	if lights != 1:
		failures.append("exactly one DirectionalLight3D, found %d" % lights)
	var session: Object = scene.voice_session()
	if session == null or not bool(session.call("is_active")):
		failures.append("entering the classroom starts the voice session")
	if not scene.using_real_engine() and ResourceLoader.exists("res://scripts/tutor/lesson/lesson_engine.gd"):
		failures.append("the real LessonEngine exists and should be the one bound")
	_free(scene)
	return failures


func _count_lights(node: Node) -> int:
	var n: int = 1 if node is DirectionalLight3D else 0
	for child: Node in node.get_children():
		n += _count_lights(child)
	return n


func _test_full_hands_free_lesson_completes():
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var scene: Node = _make(save)
	# The whole lesson, answered slowly, runs past the 300 s allowance; hold
	# the meter (a legitimate hold, the way a menu does) so this case is about
	# the lesson and the quota case below is about the quota.
	if scene.quota() != null and scene.quota().has_method("pause_for"):
		scene.quota().pause_for("test")
	var answers: Array = ["correct", "wrong", "wrong", "cough", "pause_then_finish", "wrong", "correct"]
	var asked: int = 0
	var states_seen: Dictionary = {}
	scene.state_changed.connect(func(s: String) -> void: states_seen[s] = true)
	var indicator_states: Dictionary = {}
	var steps: int = 0
	while not scene.is_lesson_complete() and steps < MAX_STEPS:
		steps += 1
		scene.advance(STEP)
		indicator_states[scene.hud().indicator_state()] = true
		if _ready_to_answer(scene):
			scene.simulate(answers[asked % answers.size()])
			asked += 1
	if not scene.is_lesson_complete():
		failures.append("the simulated lesson did not complete within %d steps (state '%s', step %s)"
			% [MAX_STEPS, scene.state(), str(scene.current_step().get("stepId"))])
	if _until(scene, func() -> bool: return scene.state() == "break", 200) < 0:
		failures.append("a completed lesson should land on the break card (state '%s')" % scene.state())
	if not scene.break_card().is_open():
		failures.append("the break card should be open")
	for wanted in ["speaking", "listening", "thinking", "celebrate", "break"]:
		if not states_seen.has(wanted):
			failures.append("the loop never reached state '%s'" % wanted)
	for wanted in [Indicator.STATE_LISTENING, Indicator.STATE_HEARING, Indicator.STATE_ALIZ]:
		if not indicator_states.has(wanted):
			failures.append("the mic indicator never showed '%s' (saw %s)" % [wanted, str(indicator_states.keys())])
	if asked < 6:
		failures.append("expected several asks, got %d" % asked)
	if scene.current_lesson_id() != "english_colors_fruits" and scene.using_real_engine():
		failures.append("'fruits' should have routed to the English Basics lesson, got '%s'" % scene.current_lesson_id())
	var log: Array = scene.turn_log()
	if log.size() < 8:
		failures.append("expected a full turn log, got %d turns" % log.size())
	var saw_hint: bool = false
	var saw_together: bool = false
	for turn in log:
		if not Turn.is_valid(turn):
			failures.append("an invalid turn reached the scene: %s" % str(turn))
		if String(turn.get("lessonAction", "")) == "give_hint":
			saw_hint = true
		if String(turn.get("speech", "")).begins_with("Let's try together"):
			saw_together = true
	if not saw_hint:
		failures.append("a second miss should have produced a give_hint turn")
	if not saw_together:
		failures.append("a miss should have been answered with 'Let's try together!'")
	var progress: Dictionary = scene.lesson_engine().progress()
	if not bool(progress.get("completed", false)):
		failures.append("engine progress should say completed: %s" % str(progress))
	if typeof(save.settings.get("tutorProgress", null)) != TYPE_DICTIONARY:
		failures.append("lesson progress should be saved under settings.tutorProgress")
	if not scene.break_card().offers_learn_again():
		failures.append("with time left the break card should offer Learn again")
	var session: Object = scene.voice_session()
	if session != null and bool(session.call("is_active")):
		failures.append("the voice session must be closed on the break card (mic scope)")
	_free(scene)
	return failures


func _test_barge_in_and_partials():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		failures.append("never reached the first question (state '%s')" % scene.state())
		_free(scene)
		return failures
	# A cough is not speech: with the child-tuned VAD an 80 ms burst is
	# ignored outright -- no hearing banner, no turn, the mic simply stays open
	# (the owner's rule: no reply for every cough or room noise). A real
	# utterance that pauses mid-sentence DOES show the hearing banner first.
	scene.simulate("cough")
	for i: int in range(30):
		scene.advance(STEP)
	if scene.hud().banner_kind() == Hud.BANNER_HEARING:
		failures.append("a cough must not read as the child talking")
	if _until(scene, func() -> bool: return _ready_to_answer(scene), 60) < 0:
		failures.append("a cough should leave the mic open, got state '%s'" % scene.state())
	scene.simulate("pause_then_finish")
	if _until(scene, func() -> bool: return scene.hud().banner_kind() == Hud.BANNER_HEARING, 30) < 0:
		failures.append("the child starting to talk should show the hearing banner")
	if _until(scene, func() -> bool: return scene.state() == "speaking", 200) < 0:
		failures.append("a paused-then-finished answer should be evaluated and answered (state '%s')" % scene.state())
	if _until(scene, func() -> bool: return _ready_to_answer(scene), 200) < 0:
		failures.append("after Aliz's reply the mic should reopen (state '%s')" % scene.state())
	var attempts_before: Variant = scene.lesson_engine().call("attempts") if scene.lesson_engine().has_method("attempts") else 0
	if int(attempts_before) != 0:
		failures.append("a cough must not count as an attempt")
	# Interrupt Aliz while she speaks: she stops and listens.
	scene.hud().press("repeat")
	if scene.state() != "speaking":
		failures.append("Repeat should have Aliz speaking")
	scene.simulate("interrupt")
	if _until(scene, func() -> bool: return scene.state() == "listening", 20) < 0:
		failures.append("a barge-in should stop Aliz and open the mic (state '%s')" % scene.state())
	elif scene.hud().banner_kind() != Hud.BANNER_INTERRUPTED:
		failures.append("a barge-in should show the 'I'm listening!' banner, got '%s'" % scene.hud().banner_kind())
	if scene.synthesis().is_speaking():
		failures.append("a barge-in must cut Aliz's speech")
	# "Wait! I want a dog!" in the fruits lesson is a subject switch: Aliz
	# answers it ("Okay! Let's learn about animals!") -- acted upon, not scored.
	if _until(scene, func() -> bool: return scene.state() == "thinking" or scene.state() == "speaking", 40) < 0:
		failures.append("the interrupting utterance should be acted upon (state '%s')" % scene.state())
	elif scene.state() == "speaking":
		var last: Dictionary = scene.turn_log().back() if not scene.turn_log().is_empty() else {}
		if not String(last.get("speech", "")).begins_with("Okay"):
			failures.append("the interruption should be answered with an 'Okay…' line, got %s" % str(last.get("speech", "")))
	_free(scene)
	return failures


func _test_no_recogniser_fallbacks():
	var failures: Array = []
	# No SpeechService (detached) and no simulation: hands-free is unavailable.
	var scene: Node = _make(null, false)
	var reached: int = _until(scene, func() -> bool: return scene.state() == "awaitMic", 400)
	if reached < 0:
		failures.append("without a recogniser the scene should wait on Tap-to-talk (state '%s')" % scene.state())
	if not scene.hud().is_tap_to_talk_visible():
		failures.append("without hands-free the Tap-to-talk button must show")
	if scene.hud().indicator_state() != Indicator.STATE_OFF and scene.hud().indicator_state() != "":
		failures.append("with nothing captured the indicator must say off, got '%s'" % scene.hud().indicator_state())
	var cards: Array = scene.hud().answer_cards_shown()
	if cards.is_empty():
		failures.append("without a recogniser the subject choice should offer answer cards")
	else:
		scene.hud().tap_answer_card(String(cards[0]))
		if scene.state() != "speaking" or scene.is_choosing_subject():
			failures.append("tapping a subject card should choose it (state '%s')" % scene.state())
	# First question: the cards include the right answer; tapping it is correct.
	if _until(scene, func() -> bool: return scene.state() == "awaitMic" and not scene.is_choosing_subject(), 600) < 0:
		failures.append("never reached the first question by touch (state '%s')" % scene.state())
	else:
		var answer: String = String(scene.current_step().get("visualAssetId", ""))
		var shown: Array = scene.hud().answer_cards_shown()
		if not shown.has(answer) or shown.size() < 2:
			failures.append("answer cards should include the right card among others, got %s" % str(shown))
		else:
			scene.hud().tap_answer_card(answer)
			if _until(scene, func() -> bool: return scene.state() == "speaking", 20) < 0:
				failures.append("a tapped answer should be judged")
			elif String(scene.current_turn().get("emotion", "")) != "happy":
				failures.append("the right card should earn a happy turn, got %s" % str(scene.current_turn()))
	# Tap-to-talk without a recogniser says it together and moves on.
	if _until(scene, func() -> bool: return scene.state() == "awaitMic", 600) < 0:
		failures.append("never returned to a question by touch")
	else:
		scene.hud().press("tapToTalk")
		if scene.state() != "speaking" or not String(scene.current_turn().get("speech", "")).begins_with("Let's try together"):
			failures.append("Tap-to-talk without a recogniser should say it together, got %s" % str(scene.current_turn().get("speech")))
		if String(scene.current_turn().get("lessonAction", "")) != "next_question":
			failures.append("say-together must move the lesson on, never trap")
	_free(scene)
	return failures


func _test_simulation_is_refused_when_off():
	var failures: Array = []
	var scene: Node = _make(null, false)
	_until(scene, func() -> bool: return scene.state() == "awaitMic", 400)
	var before: String = scene.state()
	scene.simulate("correct")
	scene.advance(STEP * 10.0)
	if scene.state() != before:
		failures.append("a simulated transcript must be refused while simulation is off")
	var session: Object = scene.voice_session()
	if session != null and session.has_method("simulate_child_audio"):
		# The hands-free session takes a level clip plus a transcript.
		var clip: Array = [[0.02, 200], [0.35, 700], [0.02, 1200]]
		var script: Script = session.get_script()
		if script != null and script.has_method("preset_clip"):
			clip = script.call("preset_clip", "answer")
		session.call("simulate_child_audio", clip, "apple")
		for i: int in range(20):
			scene.advance(STEP)
		if scene.state() != before:
			failures.append("the session must refuse simulated audio while simulation is off")
	_free(scene)
	return failures


func _test_every_button_routes():
	var failures: Array = []
	var scene: Node = _make()
	var hud: Control = scene.hud()
	for wanted in ["home", "end", "mute", "tapToTalk", "repeat", "card"]:
		if hud.buttons().get(wanted, null) == null:
			failures.append("HUD is missing the %s button" % wanted)
	if hud.is_tap_to_talk_visible():
		failures.append("with a live (simulated) session the Tap-to-talk button stays hidden")
	# Mute silences the voice, the session and the indicator says so.
	hud.press("mute")
	scene.advance(STEP)
	if not scene.is_muted() or not scene.synthesis().is_muted() or not hud.is_muted():
		failures.append("Mute should mute the scene, the voice and the HUD glyph")
	if hud.indicator_state() != Indicator.STATE_MUTED:
		failures.append("while muted the indicator must say Muted, got '%s'" % hud.indicator_state())
	var session: Object = scene.voice_session()
	if session != null and session.has_method("is_muted") and not bool(session.call("is_muted")):
		failures.append("Mute should mute the voice session")
	hud.press("mute")
	if scene.is_muted():
		failures.append("Mute should toggle back")
	if not _reach_first_question(scene):
		failures.append("never reached the first question")
	# Picture card shows and hides the flashcard.
	hud.press("card")
	if not hud.is_card_shown():
		failures.append("the picture-card button should show the flashcard")
	hud.press("card")
	if hud.is_card_shown():
		failures.append("the picture-card button should hide it again")
	# Repeat re-speaks the current question.
	var question: String = String(scene.current_turn().get("speech", ""))
	hud.press("repeat")
	if scene.state() != "speaking" or scene.synthesis().current_text() != question:
		failures.append("Repeat should say the question again ('%s'), got state '%s' text '%s'"
			% [question, scene.state(), scene.synthesis().current_text()])
	if _until(scene, func() -> bool: return scene.state() == "listening", 400) < 0:
		failures.append("after Repeat the mic should open again")
	# End lesson -> confirm -> Keep going resumes the step.
	hud.press("end")
	if not hud.is_exit_confirm_open() or scene.state() != "paused":
		failures.append("End lesson should open the confirm and pause the loop")
	hud.exit_confirm().press_keep()
	if hud.is_exit_confirm_open() or scene.state() != "speaking":
		failures.append("Keep going should close the confirm and re-ask the step (state '%s')" % scene.state())
	# End lesson -> Yes ends on the break card, with time left, mic released.
	hud.press("end")
	hud.exit_confirm().press_stop()
	if scene.state() != "break" or not scene.break_card().is_open():
		failures.append("Yes, stop should show the break card")
	if session != null and bool(session.call("is_active")):
		failures.append("End lesson must close the voice session")
	# Learn again restarts with the welcome.
	scene.break_card().press_learn_again()
	if scene.state() != "speaking" or scene.break_card().is_open() or not scene.is_choosing_subject():
		failures.append("Learn again should restart with Aliz's welcome")
	if session != null and not bool(session.call("is_active")):
		failures.append("Learn again should reopen the session")
	# Home always works, even mid-speech.
	hud.press("home")
	if scene.last_departure() != "home" or scene.state() != "done":
		failures.append("Home should leave (departure '%s', state '%s')" % [scene.last_departure(), scene.state()])
	if session != null and bool(session.call("is_active")):
		failures.append("Home must close the voice session")
	_free(scene)
	return failures


func _test_home_and_free_play_leave():
	var failures: Array = []
	var script: GDScript = load("res://scripts/tutor/tutor_scene.gd")
	var home: String = String(script.get_script_constant_map().get("HOME_SCENE_PATH", ""))
	if home != HOME_PATH:
		failures.append("Home must go to %s, scene says %s" % [HOME_PATH, home])
	if not ResourceLoader.exists(HOME_PATH):
		failures.append("%s does not exist" % HOME_PATH)
	var scene: Node = _make()
	scene.break_card().press_continue()
	if scene.last_departure() != "freePlay" and scene.last_departure() != "home":
		failures.append("Continue Playing should leave to Free Play (or Home in a house-less build), got '%s'" % scene.last_departure())
	if scene.last_departure() == "freePlay":
		var main_script: GDScript = load("res://scenes/main/main.gd")
		var path: String = String(main_script.call("free_play_scene_path"))
		if path.is_empty() or not ResourceLoader.exists(path):
			failures.append("Free Play target '%s' does not exist" % path)
	_free(scene)
	return failures


func _test_quota_closes_at_boundary_and_persists():
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var scene: Node = _make(save)
	if scene.quota() == null:
		_free(scene)
		return ["the scene has no quota meter"]
	# Run a little lesson time, then leave: the used seconds must be on disk.
	for i: int in range(120):
		scene.advance(STEP)
	scene.leave_to_home()
	var stored: Variant = save.settings.get("tutorQuota", null)
	if typeof(stored) != TYPE_DICTIONARY:
		failures.append("the quota should persist under settings.tutorQuota (Agent F's key), keys: %s" % str(save.settings.keys()))
	if save.settings.has("tutorLocalQuota"):
		failures.append("the old tutorLocalQuota key must be gone")
	var used_before: float = float(scene.quota().state().get("usedSeconds", 0.0))
	if used_before < 10.0 or used_before > 14.0:
		failures.append("12 s of lesson should count about 12 s, got %.1f" % used_before)
	_free(scene)
	# A fresh scene on the same save (a restart) continues from that count.
	var again: Node = _make(save)
	var state: Dictionary = again.quota().state()
	if absf(float(state.get("usedSeconds", 0.0)) - used_before) > 0.5:
		failures.append("after a restart the quota should resume near %.1f s, got %s" % [used_before, str(state.get("usedSeconds"))])
	if float(state.get("dailyAllowanceSeconds", 0.0)) != 300.0:
		failures.append("the free allowance is 300 s a day, got %s" % str(state.get("dailyAllowanceSeconds")))
	# Exhaustion: Aliz finishes her sentence, speaks the closing, then the card.
	var reached_q: bool = _reach_first_question(again)
	if not reached_q:
		failures.append("never reached the first question for the quota case")
	again.quota().tick(400.0)
	again.simulate("correct")
	var reached: int = _until(again, func() -> bool: return again.state() == "break", 1200)
	if reached < 0:
		failures.append("an exhausted quota should end on the break card (state '%s')" % again.state())
	else:
		var closing_said: bool = false
		for turn in again.turn_log():
			if String(turn.get("speech", "")) == SceneScript.CLOSING_TEXT:
				closing_said = true
		if not closing_said:
			failures.append("Aliz should speak the friendly closing before the card")
		if again.break_card().offers_learn_again():
			failures.append("with the day's minutes used the break card must not offer Learn again")
		var session: Object = again.voice_session()
		if session != null and bool(session.call("is_active")):
			failures.append("the closing must release the microphone")
	_free(again)
	# A day that starts exhausted: the closing straight away, no mic opened.
	var spent: Node = _make(save)
	if not spent.is_closing():
		failures.append("a spent day should go straight to Aliz's closing (state '%s')" % spent.state())
	var spent_session: Object = spent.voice_session()
	if spent_session != null and bool(spent_session.call("is_active")):
		failures.append("no session may open on a spent day")
	_free(spent)
	return failures


func _test_background_rule():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		failures.append("never reached the first question")
	var session: Object = scene.voice_session()
	scene.go_background()
	if session != null and bool(session.call("is_active")):
		failures.append("going to the background must stop the session")
	if scene.state() != "background":
		failures.append("the scene should sit in the background state, got '%s'" % scene.state())
	scene.advance(STEP)
	if scene.hud().indicator_state() != Indicator.STATE_OFF:
		failures.append("in the background the indicator must say off")
	scene.return_from_background()
	if not scene.hud().is_resume_card_shown():
		failures.append("returning should show the tap-to-continue card")
	if session != null and bool(session.call("is_active")):
		failures.append("returning must NOT reopen the microphone by itself")
	scene.hud().press_resume()
	if session != null and not bool(session.call("is_active")):
		failures.append("tapping to continue should reopen the session")
	if scene.state() != "speaking":
		failures.append("tapping to continue should re-ask the step, got '%s'" % scene.state())
	_free(scene)
	return failures


func _test_provider_failure_falls_back():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		failures.append("never reached the first question")
	scene.provider().provider_failed.emit("backend unreachable")
	if String(scene.current_turn().get("speech", "")) != "Let's try together!":
		failures.append("a provider failure should speak the fallback turn, got %s" % str(scene.current_turn().get("speech")))
	if scene.hud().banner_kind() != Hud.BANNER_TOGETHER:
		failures.append("a provider failure should show the Let's try together banner")
	if scene.provider() == null or scene.provider().provider_name() != "scripted":
		failures.append("after a failure the scripted provider must be in place")
	if _until(scene, func() -> bool: return scene.state() == "listening", 400) < 0:
		failures.append("the lesson should resume after a provider failure (state '%s')" % scene.state())
	_free(scene)
	return failures


func _test_nothing_covers_alizs_face():
	var failures: Array = []
	var scene: Node = _make()
	for size in SIZES:
		var face: Rect2 = scene.face_screen_rect(size)
		if face.size.x < 20.0 or face.size.y < 20.0:
			failures.append("%s: face rect came back empty (%s)" % [str(size), str(face)])
			continue
		var screen: Rect2 = Rect2(Vector2.ZERO, size)
		if not screen.encloses(face):
			failures.append("%s: Aliz's face is not fully on screen: %s" % [str(size), str(face)])
		var rects: Dictionary = Hud.layout_rects(size)
		for key in rects.keys():
			if (rects[key] as Rect2).intersects(face):
				failures.append("%s: HUD '%s' %s covers Aliz's face %s" % [str(size), key, str(rects[key]), str(face)])
		if ExitConfirm.card_rect(size).intersects(face):
			failures.append("%s: the exit confirm covers Aliz's face" % str(size))
		var centre: Vector2 = face.get_center()
		if centre.x < size.x * 0.35 or centre.x > size.x * 0.65 or centre.y > size.y * 0.7:
			failures.append("%s: Aliz's face is off-centre at %s" % [str(size), str(centre)])
	_free(scene)
	return failures


func _test_break_card_copy():
	var failures: Array = []
	var scene: Node = _make()
	var card: Control = scene.break_card()
	card.open(false)
	var texts: Array = card.texts()
	for wanted in ["Great job today!", "Come back tomorrow for more Little Days!", "Let's keep playing with Bunny!", "Continue Playing", "Home"]:
		if not texts.has(wanted):
			failures.append("break card is missing '%s' (has %s)" % [wanted, str(texts)])
	for text in texts:
		var lower: String = String(text).to_lower()
		for banned in ["lock", "expired", "limit", "buy", "upgrade", "subscribe", "%"]:
			if lower.find(banned) >= 0:
				failures.append("break card copy '%s' contains '%s'" % [text, banned])
	if SceneScript.CLOSING_TEXT.length() > Turn.MAX_SPEECH:
		failures.append("the closing line must fit the turn validator")
	_free(scene)
	return failures


## QA B1: "Wait! I want a dog!" while Aliz asks about the cat must actually move
## the lesson to the dog -- board, question and scoring -- not only say so.
func _test_interjection_switches_the_item():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		failures.append("never reached the first question (state '%s')" % scene.state())
		_free(scene)
		return failures
	if not scene.using_real_engine():
		_free(scene)
		return failures
	var before: String = String(scene.current_step().get("stepId", ""))
	scene.hud().press("repeat")  # Aliz is speaking the apple question
	scene.simulate("interrupt", "Wait! I want the banana!")
	if _until(scene, func() -> bool: return String(scene.current_step().get("stepId", "")).contains("banana") and _ready_to_answer(scene), 400) < 0:
		failures.append("after 'I want the banana' the lesson should be on the banana step and listening, got step %s (was %s) state %s"
				% [str(scene.current_step().get("stepId")), before, scene.state()])
	if scene.has_method("board_asset_id") and not String(scene.board_asset_id()).contains("banana"):
		failures.append("the board should show the banana after the switch, got %s" % str(scene.board_asset_id()))
	scene.simulate("correct")
	if _until(scene, func() -> bool: return scene.state() == "celebrate" or scene.state() == "speaking", 200) < 0:
		failures.append("answering on the banana step should be judged, got state %s" % scene.state())
	_free(scene)
	return failures


## QA B2: an interruption Aliz cannot act on ("look, a bird outside!") during
## her praise must not be scored, and the correct answer it cut must still
## advance the lesson.
func _test_idle_interruption_is_not_an_attempt():
	var failures: Array = []
	var scene: Node = _make()
	if not _reach_first_question(scene):
		failures.append("never reached the first question")
		_free(scene)
		return failures
	var step_before: String = String(scene.current_step().get("stepId", ""))
	scene.simulate("correct")
	if _until(scene, func() -> bool: return scene.state() == "speaking", 200) < 0:
		failures.append("the correct answer should have Aliz praising (state %s)" % scene.state())
		_free(scene)
		return failures
	scene.simulate("interrupt", "look a bird outside")
	if _until(scene, func() -> bool: return _ready_to_answer(scene), 400) < 0:
		failures.append("after an idle interruption the mic should reopen (state %s)" % scene.state())
	var step_after: String = String(scene.current_step().get("stepId", ""))
	if step_after == step_before:
		failures.append("the correct answer cut by the interruption must still advance the lesson (still on %s)" % step_before)
	var engine: Object = scene.lesson_engine()
	if engine != null and engine.has_method("attempts") and int(engine.call("attempts")) != 0:
		failures.append("an idle interruption must not count as an attempt on the new step")
	_free(scene)
	return failures
