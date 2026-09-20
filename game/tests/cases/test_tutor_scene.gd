extends RefCounted

## The classroom, driven headless from the outside: it loads, a whole simulated
## lesson runs to the break card through the LessonEngine with no hang, every
## button routes, Home leaves to the title screen, the quota mirror survives a
## reload, and nothing the HUD draws lands on Aliz's face at either shipped
## aspect ratio.
##
## Everything is driven through `advance(delta)` and the scene's public
## surface -- the same calls `_process()` and the buttons make -- with the
## autoloads detached by the runner, so the on-device speech path is absent and
## the scene's own fallbacks are what is under test.

const SCENE_PATH: String = "res://scenes/tutor/classroom.tscn"
const HOME_PATH: String = "res://scenes/main/main.tscn"
const Turn := preload("res://scripts/tutor/turn/tutor_turn.gd")
const Hud := preload("res://scripts/tutor/ui/tutor_hud.gd")
const ExitConfirm := preload("res://scripts/tutor/ui/tutor_exit_confirm.gd")
const LocalQuota := preload("res://scripts/tutor/classroom/tutor_local_quota.gd")

const MAX_TRIANGLES: int = 40000
const STEP: float = 0.1
const MAX_STEPS: int = 6000
const SIZES: Array = [Vector2(1334, 750), Vector2(2340, 1080)]


## A dictionary-backed SaveService: the three methods the scene and the quota
## duck-type, and nothing that could touch `user://`.
class FakeSave extends RefCounted:
	var settings: Dictionary = {}
	var saves: int = 0
	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value
	func save_profile() -> bool:
		saves += 1
		return true
	func get_profile() -> Dictionary:
		return {"settings": settings, "unlockedRooms": []}


func test_name() -> String:
	return "tutor_scene"


func run():
	var failures: Array = []
	failures.append_array(_test_scene_loads_and_is_within_budget())
	failures.append_array(_test_full_simulated_lesson_completes())
	failures.append_array(_test_simulation_is_refused_when_off())
	failures.append_array(_test_every_button_routes())
	failures.append_array(_test_home_and_free_play_leave())
	failures.append_array(_test_quota_mirror_persists_and_ends_at_boundary())
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
	if save != null:
		scene.set_save_service(save)
	scene.enable_simulation(sim)
	scene.begin_lesson("fruits_01")
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
		if scene.classroom().prop_source("table") != "primitive" and not FileAccess.file_exists("res://content/tutor/props_manifest.json"):
			failures.append("without a props manifest the table must be the primitive")
	if scene.aliz() == null:
		failures.append("Aliz is not in the classroom")
	elif not scene.is_seated():
		failures.append("Aliz is not seated")
	if scene.state() != "speaking":
		failures.append("after begin_lesson the scene should be speaking the first step, got '%s'" % scene.state())
	var board: Node = scene.classroom().get_board()
	if board == null or String(board.current_card()) != "apple_red":
		failures.append("the board should show the apple card first")
	if scene.hud().current_card() != "apple_red":
		failures.append("the HUD card should be the apple")
	var lights: int = _count_lights(scene)
	if lights != 1:
		failures.append("exactly one DirectionalLight3D, found %d" % lights)
	_free(scene)
	return failures


func _count_lights(node: Node) -> int:
	var n: int = 1 if node is DirectionalLight3D else 0
	for child: Node in node.get_children():
		n += _count_lights(child)
	return n


func _test_full_simulated_lesson_completes():
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var scene: Node = _make(save)
	var answers: Array = ["correct", "wrong", "nothing"]
	var asked: int = 0
	var states_seen: Dictionary = {}
	scene.state_changed.connect(func(s: String) -> void: states_seen[s] = true)
	var steps: int = 0
	while not scene.is_lesson_complete() and steps < MAX_STEPS:
		steps += 1
		scene.advance(STEP)
		if scene.state() == "listening":
			if scene.hud().banner_kind() != Hud.BANNER_LISTENING:
				failures.append("listening state should show the Listening banner")
			if not scene.hud().is_listening_shown():
				failures.append("listening state should pulse the mic ring")
			scene.simulate(answers[asked % answers.size()])
			asked += 1
	if not scene.is_lesson_complete():
		failures.append("the simulated lesson did not complete within %d steps (state '%s')" % [MAX_STEPS, scene.state()])
	if scene.state() != "break" or not scene.break_card().is_open():
		failures.append("a completed lesson should land on the break card (state '%s')" % scene.state())
	for wanted in ["speaking", "listening", "thinking", "celebrate", "break"]:
		if not states_seen.has(wanted):
			failures.append("the loop never reached state '%s'" % wanted)
	if asked < 5:
		failures.append("expected several asks, got %d" % asked)
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
		failures.append("silence should have been answered with 'Let's try together!'")
	var progress: Dictionary = scene.lesson_engine().progress()
	if not bool(progress.get("completed", false)):
		failures.append("engine progress should say completed: %s" % str(progress))
	if typeof(save.settings.get("tutorProgress", null)) != TYPE_DICTIONARY:
		failures.append("lesson progress should be saved under settings.tutorProgress")
	if scene.break_card().offers_learn_again() != true:
		failures.append("with time left the break card should offer Learn again")
	_free(scene)
	return failures


func _test_simulation_is_refused_when_off():
	var failures: Array = []
	var scene: Node = _make(null, false)
	# Speak the teach line, then the question; without recognition or
	# simulation the mic becomes the say-together button.
	var reached: int = _until(scene, func() -> bool: return scene.state() == "awaitMic", 400)
	if reached < 0:
		failures.append("without speech or simulation the scene should wait on the mic (state '%s')" % scene.state())
	var before: String = scene.state()
	scene.simulate("correct")
	if scene.state() != before:
		failures.append("a simulated transcript must be refused while simulation is off")
	if not scene.hud().is_mic_enabled():
		failures.append("the mic should be enabled while waiting on it")
	scene.hud().press("mic")
	if scene.state() != "speaking" or not String(scene.current_turn().get("speech", "")).begins_with("Let's try together"):
		failures.append("the mic without recognition should say it together, got state '%s' / %s" % [scene.state(), str(scene.current_turn().get("speech"))])
	if String(scene.current_turn().get("lessonAction", "")) != "next_question":
		failures.append("say-together must move the lesson on, never trap")
	_free(scene)
	return failures


func _test_every_button_routes():
	var failures: Array = []
	var scene: Node = _make()
	var hud: Control = scene.hud()
	for wanted in ["home", "mute", "mic", "repeat", "card", "stop"]:
		if hud.buttons().get(wanted, null) == null:
			failures.append("HUD is missing the %s button" % wanted)
	# Mute toggles the synthesis shim (and the audio director, when present).
	hud.press("mute")
	if not scene.is_muted() or not scene.synthesis().is_muted() or not hud.is_muted():
		failures.append("Mute should mute the scene, the voice and the HUD glyph")
	hud.press("mute")
	if scene.is_muted():
		failures.append("Mute should toggle back")
	# Picture card shows and hides the flashcard.
	hud.press("card")
	if not hud.is_card_shown():
		failures.append("the picture-card button should show the flashcard")
	hud.press("card")
	if hud.is_card_shown():
		failures.append("the picture-card button should hide it again")
	# Repeat re-speaks the current question.
	if _until(scene, func() -> bool: return scene.state() == "listening", 400) < 0:
		failures.append("never reached listening")
	var question: String = String(scene.current_turn().get("speech", ""))
	hud.press("repeat")
	if scene.state() != "speaking" or scene.synthesis().current_text() != question:
		failures.append("Repeat should say the question again ('%s'), got state '%s' text '%s'"
			% [question, scene.state(), scene.synthesis().current_text()])
	if _until(scene, func() -> bool: return scene.state() == "listening", 400) < 0:
		failures.append("after Repeat the mic should open again")
	# Stop -> confirm -> Keep going resumes the step.
	hud.press("stop")
	if not hud.is_exit_confirm_open() or scene.state() != "paused":
		failures.append("Stop should open the confirm and pause the loop")
	hud.exit_confirm().press_keep()
	if hud.is_exit_confirm_open() or scene.state() != "speaking":
		failures.append("Keep going should close the confirm and re-ask the step (state '%s')" % scene.state())
	# Stop -> Yes ends on the break card, with time left.
	hud.press("stop")
	hud.exit_confirm().press_stop()
	if scene.state() != "break" or not scene.break_card().is_open():
		failures.append("Yes, stop should show the break card")
	# Learn again restarts the lesson.
	scene.break_card().press_learn_again()
	if scene.state() != "speaking" or scene.break_card().is_open():
		failures.append("Learn again should restart the lesson")
	# Home always works, even mid-speech.
	hud.press("home")
	if scene.last_departure() != "home" or scene.state() != "done":
		failures.append("Home should leave (departure '%s', state '%s')" % [scene.last_departure(), scene.state()])
	_free(scene)
	return failures


func _test_home_and_free_play_leave():
	var failures: Array = []
	if scene_home_path() != HOME_PATH:
		failures.append("Home must go to %s, scene says %s" % [HOME_PATH, scene_home_path()])
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


func scene_home_path() -> String:
	var script: GDScript = load("res://scripts/tutor/tutor_scene.gd")
	return String(script.get_script_constant_map().get("HOME_SCENE_PATH", ""))


func _test_quota_mirror_persists_and_ends_at_boundary():
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	# Run a little lesson time, then leave: the used seconds must be on disk.
	var scene: Node = _make(save)
	for i: int in range(120):
		scene.advance(STEP)
	scene.leave_to_home()
	var stored: Variant = save.settings.get(LocalQuota.SETTING_KEY, null)
	if typeof(stored) != TYPE_DICTIONARY:
		failures.append("the quota mirror should persist under settings.%s" % LocalQuota.SETTING_KEY)
		_free(scene)
		return failures
	var used: float = float((stored as Dictionary).get("usedSeconds", 0.0))
	if used < 10.0 or used > 14.0:
		failures.append("12 s of lesson should count about 12 s, stored %.1f" % used)
	if save.saves == 0:
		failures.append("leaving should save the profile")
	_free(scene)
	# A fresh scene on the same save (a restart) continues from that count.
	var again: Node = _make(save)
	var state: Dictionary = again.quota().state()
	if absf(float(state.get("usedSeconds", 0.0)) - used) > 0.2:
		failures.append("after a restart the quota should resume at %.1f s, got %s" % [used, str(state.get("usedSeconds"))])
	if float(state.get("dailyAllowanceSeconds", 0.0)) != 300.0:
		failures.append("the local allowance is 300 s a day")
	_free(again)
	# A new UTC day resets it; the previous day's count does not leak.
	var quota: RefCounted = LocalQuota.new(save)
	quota.set_date_override("2099-01-01")
	if quota.used_seconds() != 0.0:
		failures.append("a new UTC day should start at zero, got %.1f" % quota.used_seconds())
	# Corrupt storage is a fresh day, not a crash.
	save.settings[LocalQuota.SETTING_KEY] = "garbage"
	var corrupt: RefCounted = LocalQuota.new(save)
	if corrupt.used_seconds() != 0.0:
		failures.append("corrupt quota storage should restore to zero")
	# Exhaustion ends the lesson at a boundary, never mid-turn, and the break
	# card then has no Learn again.
	var tiny_save: FakeSave = FakeSave.new()
	tiny_save.settings[LocalQuota.SETTING_KEY] = {"utcDate": LocalQuota.new(null).utc_date(), "usedSeconds": 297.0}
	var short: Node = _make(tiny_save)
	var expired_during: String = ""
	short.state_changed.connect(func(s: String) -> void:
		if s == "break" and expired_during.is_empty():
			expired_during = "ok")
	var reached: int = _until(short, func() -> bool: return short.state() == "break", 800)
	if reached < 0:
		failures.append("an exhausted quota should end on the break card (state '%s')" % short.state())
	elif short.break_card().offers_learn_again():
		failures.append("with the day's minutes used the break card must not offer Learn again")
	if short.synthesis().is_speaking():
		failures.append("the break card must not cut Aliz off mid-sentence")
	_free(short)
	return failures


func _test_provider_failure_falls_back():
	var failures: Array = []
	var scene: Node = _make()
	if _until(scene, func() -> bool: return scene.state() == "listening", 400) < 0:
		failures.append("never reached listening")
	scene.provider().provider_failed.emit("backend unreachable")
	if String(scene.current_turn().get("speech", "")) != "Let's try together!":
		failures.append("a provider failure should speak the fallback turn, got %s" % str(scene.current_turn().get("speech")))
	if scene.hud().banner_kind() != Hud.BANNER_TOGETHER:
		failures.append("a provider failure should show the Let's try together banner")
	if scene.provider() == null or scene.provider().provider_name() != "scripted":
		failures.append("after a failure the scripted provider must be in place")
	# ...and the lesson carries on afterwards.
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
		# The face sits in the middle third, where the camera puts a subject.
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
	for wanted in ["Great job today!", "Come back tomorrow for more Little Days!", "Keep playing with Bunny!", "Continue Playing", "Home"]:
		if not texts.has(wanted):
			failures.append("break card is missing '%s' (has %s)" % [wanted, str(texts)])
	for text in texts:
		var lower: String = String(text).to_lower()
		for banned in ["lock", "expired", "limit", "buy", "upgrade", "subscribe", "%"]:
			if lower.find(banned) >= 0:
				failures.append("break card copy '%s' contains '%s'" % [text, banned])
	_free(scene)
	return failures
