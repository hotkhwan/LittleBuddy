extends RefCounted
## The call sites really reach the voice pack.
##
## A `VoiceDirector` is parked at `/root/Voice` for the duration of each case
## (the lead's autoload, simulated), with a real `TtsService` behind it whose
## safety timers are captured, so every cue lands as a fallback utterance that
## the test can see and drain. Asserted:
##   * the highchair: Aliz's learning line on a task, "Yummy!" on the first
##     bite, "More, please!" half-way, "Hmph!" + the `hmph` face on a wrong
##     item followed by "Let's try again!" (and "It's okay" on the 2nd miss),
##     "Thank you, Aliz!" then "All done!" on success;
##   * Bunny in the house: says a new need once, not again inside the cooldown,
##     and one "Hmph!" when a need escalates;
##   * the summary: "You earned a star!" after the headline, the sticker line
##     when one unlocked;
##   * the menu: the welcome pair once per launch;
##   * `PromptSpeaker` routes through the pack and never double-speaks;
##   * without `/root/Voice` every one of these paths still speaks through
##     TtsService (the pre-pack behaviour) -- the pack is an addition.

const DirectorScript := preload("res://scripts/voice/voice_director.gd")
const TtsServiceScript := preload("res://scripts/speech/tts_service.gd")
const PromptSpeakerScript := preload("res://scripts/speech/prompt_speaker.gd")
const MainScript := preload("res://scenes/main/main.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const Rules := preload("res://scripts/feeding/feeding_rules.gd")
const Actor := preload("res://scripts/care/child_actor.gd")
const Baby := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
const Needs := preload("res://scripts/care/child_needs.gd")
const Present := preload("res://scripts/care/child_presentation.gd")

const FEEDING_TABLE_SCENE: String = "res://scenes/feeding/feeding_table.tscn"
const SESSION_SUMMARY_SCENE: String = "res://scenes/progression/session_summary.tscn"


class FakeSave:
	extends Node
	var settings: Dictionary = {}
	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value


class PromptSource:
	extends Node
	signal prompt_changed(prompt: String, thai_hint: String)
	signal encouragement(text: String)


func test_name() -> String:
	return "voice_wiring"


func run():
	var failures: Array = []
	var root: Node = _root()
	if root == null:
		return ["voice_wiring: no SceneTree root available"]
	if root.get_node_or_null("Voice") != null:
		return ["voice_wiring: a Voice node is already at /root; the runner should have detached it"]
	failures.append_array(_test_feeding_table(root))
	failures.append_array(_test_child_actor(root))
	failures.append_array(_test_session_summary(root))
	failures.append_array(_test_menu_welcome(root))
	failures.append_array(_test_prompt_speaker(root))
	failures.append_array(_test_without_voice_the_old_path_still_speaks(root))
	if root.get_node_or_null("Voice") != null:
		failures.append("voice_wiring: left a Voice node behind at /root")
	return failures


# -- Harness --------------------------------------------------------------------


## Parks a director at /root/Voice. Returns {voice, tts, tts_timers, started}.
func _install(root: Node) -> Dictionary:
	var tts = TtsServiceScript.new()
	tts.name = "TtsService"
	var tts_timers: Array = []
	tts.set_timer_factory(func(_d: float, cb: Callable) -> void: tts_timers.append(cb))
	var save := FakeSave.new()
	save.name = "SaveService"
	var voice = DirectorScript.new()
	voice.name = "Voice"
	voice.set_timer_factory(func(_d: float, _cb: Callable) -> void: pass)
	voice.set_tts(tts)
	voice.set_save_service(save)
	var started: Array = []
	voice.line_started.connect(func(line_id: String, _c: String, text: String) -> void:
		started.append(line_id if not line_id.is_empty() else "text:" + text))
	root.add_child(tts)
	root.add_child(save)
	root.add_child(voice)
	voice.build()
	return {"voice": voice, "tts": tts, "tts_timers": tts_timers, "started": started, "save": save}


func _uninstall(h: Dictionary) -> void:
	for key: String in ["voice", "tts", "save"]:
		var node: Node = h[key]
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


## Finishes utterances until nothing is speaking (bounded), so queued lines
## surface in `started` in order.
func _drain(h: Dictionary) -> void:
	var voice = h["voice"]
	var tts = h["tts"]
	for _i: int in range(24):
		if not voice.is_speaking() and not tts.is_speaking():
			return
		var timers: Array = h["tts_timers"]
		if timers.is_empty():
			return
		(timers.pop_back() as Callable).call()


func _root() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


func _make_table(root: Node, failures: Array) -> Node3D:
	if not ResourceLoader.exists(FEEDING_TABLE_SCENE):
		failures.append("voice_wiring: %s does not exist" % FEEDING_TABLE_SCENE)
		return null
	var table: Node3D = (load(FEEDING_TABLE_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(table)
	table.call("build")
	table.call("set_instant", true)
	table.call("set_active", true)
	return table


func _free_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


# -- Cases ----------------------------------------------------------------------


func _test_feeding_table(root: Node):
	var failures: Array = []
	var library: RefCounted = ContentLibraryScript.create()
	if library == null:
		return ["voice_wiring: could not load the content library"]
	var h: Dictionary = _install(root)
	var voice = h["voice"]
	var table: Node3D = _make_table(root, failures)
	if table == null:
		_uninstall(h)
		return failures
	var started: Array = h["started"]

	var task: Dictionary = library.get_task("feedApple")
	table.call("set_task", task, "apple", "")
	if voice.current_line() != "aliz_011_apple":
		failures.append("setting the apple task should have Aliz say her apple line, got '%s' (pending %s)"
				% [voice.current_line(), str(voice.pending_line_ids())])
	_drain(h)

	# The wrong item: Bunny sulks, then Aliz encourages.
	table.call("tap_item", "banana")
	table.call("begin_drag", "banana")
	table.call("drag_to_mouth")
	if int(table.call("get_mistakes")) != 1:
		failures.append("harness: the banana should have counted as a mistake")
	if voice.current_line() != "bunny_012_upset":
		failures.append("a wrong item should bring 'Hmph!' at once, got '%s'" % voice.current_line())
	if voice.pending_line_ids() != ["aliz_008_try_again"]:
		failures.append("'Let's try again!' should follow the hmph: %s" % str(voice.pending_line_ids()))
	var face: String = String(table.call("get_bunny_face"))
	if face != "hmph" and face != "":
		failures.append("the wrong item must set the hmph face, got '%s'" % face)
	_drain(h)
	# Second miss: the warmer second line.
	table.call("begin_drag", "banana")
	table.call("drag_to_mouth")
	if voice.pending_line_ids() != ["aliz_008_try_again", "aliz_009_its_okay"]:
		failures.append("the second miss adds It's okay: %s" % str(voice.pending_line_ids()))
	_drain(h)

	# Half-way through the meal: "More, please!".
	var apple: Node3D = table.call("get_item", "apple")
	var halfway: int = int(table.get("HALFWAY_BITE"))
	if halfway < 1 or halfway >= Rules.BITES:
		failures.append("HALFWAY_BITE should be strictly inside the meal, got %d" % halfway)
	table.call("_bite", apple, halfway, int(table.get("_generation")))
	if voice.current_line() != "bunny_004_more":
		failures.append("the half-way bite should bring 'More, please!', got '%s'" % voice.current_line())
	_drain(h)

	# Success: yummy on the first bite, thank you, all done -- in that order.
	var before: int = started.size()
	table.call("begin_drag", "apple")
	table.call("drag_to_mouth")
	_drain(h)
	var after: Array = started.slice(before)
	if after.find("bunny_003_yummy") < 0:
		failures.append("the first bite should bring 'Yummy!': %s" % str(after))
	var thanks: int = after.find("bunny_005_thank_you")
	var done: int = after.find("aliz_020_all_done")
	if thanks < 0 or done < 0 or done < thanks:
		failures.append("success should end with Thank you, Aliz! then All done!: %s" % str(after))
	if after.has("text:Great!"):
		failures.append("with the pack, the device-voice 'Great!' is replaced by Bunny's thanks: %s" % str(after))
	if not bool(table.call("is_task_finished")):
		failures.append("harness: the apple task should have finished")

	_free_node(table)
	_uninstall(h)
	return failures


func _test_child_actor(root: Node):
	var failures: Array = []
	if not Baby.is_pose_available(Baby.PREFERRED_POSE):
		print("     voice_wiring: Bunny's model is not in this checkout; the need cues are not driven here")
		return failures
	var h: Dictionary = _install(root)
	var voice = h["voice"]
	var started: Array = h["started"]
	var bunny := Node3D.new()
	bunny.set_script(Actor)
	root.add_child(bunny)
	bunny.call("build")
	var stats: RefCounted = bunny.call("get_stats")

	stats.call("set_stat", "hunger", 72.0)
	bunny.call("set_activity", Present.ACTIVITY_IDLE)
	bunny.call("_refresh")
	if String(bunny.call("get_need")) != Needs.HUNGRY:
		failures.append("harness: the actor should be hungry")
	if not started.has("bunny_001_hungry"):
		failures.append("a new hungry need should be said: %s" % str(started))
	_drain(h)
	var count: int = started.count("bunny_001_hungry")
	# Content, then hungry again inside the cooldown: no second line.
	stats.call("set_stat", "hunger", 10.0)
	bunny.call("_refresh")
	stats.call("set_stat", "hunger", 72.0)
	bunny.call("_refresh")
	if started.count("bunny_001_hungry") != count:
		failures.append("the same need inside the cooldown must not be said again (%d -> %d)"
				% [count, started.count("bunny_001_hungry")])
	if float(bunny.call("get_need_line_cooldown_sec")) < 10.0:
		failures.append("the per-need cooldown should be long enough that he does not chatter")

	# Left alone long enough: one Hmph.
	bunny.call("_tick_ignored", 120.0)
	if not bool(bunny.call("is_urgent")):
		failures.append("harness: 120 s of hunger should be urgent")
	if started.count("bunny_012_upset") != 1:
		failures.append("an ignored need brings exactly one Hmph, got %d" % started.count("bunny_012_upset"))
	bunny.call("_tick_ignored", 120.0)
	if started.count("bunny_012_upset") != 1:
		failures.append("a second escalation tick must not repeat the Hmph")
	if not bool(bunny.call("has_voiced_urgent")):
		failures.append("has_voiced_urgent() should report the Hmph")
	# Being cared for resets it, so the next long wait may sulk again.
	bunny.call("satisfy", Needs.HUNGRY, 70.0)
	if bool(bunny.call("has_voiced_urgent")):
		failures.append("care resets the urgent voice flag")

	_free_node(bunny)
	_uninstall(h)
	return failures


func _test_session_summary(root: Node):
	var failures: Array = []
	if not ResourceLoader.exists(SESSION_SUMMARY_SCENE):
		return ["voice_wiring: %s missing" % SESSION_SUMMARY_SCENE]
	var h: Dictionary = _install(root)
	var started: Array = h["started"]
	var screen: Control = (load(SESSION_SUMMARY_SCENE) as PackedScene).instantiate() as Control
	root.add_child(screen)
	screen.call("show_summary", 2, 12, [{"stickerId": "milk", "word": "milk", "displayName": "Milk"}])
	_drain(h)
	var star: int = started.find("aliz_021_star")
	var sticker: int = started.find("aliz_022_sticker")
	if star < 0:
		failures.append("earning stars should bring 'You earned a star!': %s" % str(started))
	if sticker < 0 or sticker < star:
		failures.append("a new sticker brings its line after the star: %s" % str(started))
	if started.is_empty() or not String(started[0]).begins_with("text:"):
		failures.append("the headline is still spoken first (through the pack): %s" % str(started))
	_free_node(screen)
	_uninstall(h)

	# No stars, no sticker: neither reward line.
	var h2: Dictionary = _install(root)
	var screen2: Control = (load(SESSION_SUMMARY_SCENE) as PackedScene).instantiate() as Control
	root.add_child(screen2)
	screen2.call("show_summary", 0, 12, [])
	_drain(h2)
	if (h2["started"] as Array).has("aliz_021_star") or (h2["started"] as Array).has("aliz_022_sticker"):
		failures.append("no star and no sticker means no reward line: %s" % str(h2["started"]))
	_free_node(screen2)
	_uninstall(h2)
	return failures


func _test_menu_welcome(root: Node):
	var failures: Array = []
	var h: Dictionary = _install(root)
	var voice = h["voice"]
	MainScript.reset_welcome_for_tests()
	var menu: Node = MainScript.new()
	menu.call("_welcome_once")
	if voice.current_line() != "aliz_001_welcome" or voice.pending_line_ids() != ["aliz_002_lets_play"]:
		failures.append("menu ready should welcome then invite: %s / %s"
				% [voice.current_line(), str(voice.pending_line_ids())])
	if not MainScript.has_welcomed_this_launch():
		failures.append("the welcome must be remembered for the launch")
	_drain(h)
	var before: int = (h["started"] as Array).size()
	var again: Node = MainScript.new()
	again.call("_welcome_once")
	if (h["started"] as Array).size() != before:
		failures.append("returning to the title must not welcome a second time")
	menu.free()
	again.free()
	MainScript.reset_welcome_for_tests()
	_uninstall(h)
	return failures


func _test_prompt_speaker(root: Node):
	var failures: Array = []
	var h: Dictionary = _install(root)
	var voice = h["voice"]
	var tts = h["tts"]
	var source := PromptSource.new()
	root.add_child(source)
	var speaker: Node = PromptSpeakerScript.attach(source, tts)
	if speaker == null:
		_free_node(source)
		_uninstall(h)
		return ["harness: PromptSpeaker.attach failed"]
	# A mission intro that is one of the 36 lines plays the recorded line.
	source.prompt_changed.emit("Let's make some milk!", "")
	speaker.call("flush")
	if voice.current_line() != "aliz_014_milk_time":
		failures.append("a prompt that is a recorded line routes to it, got '%s'" % voice.current_line())
	# A mode handler already speaking the same words: not repeated.
	source.prompt_changed.emit("Let's make some milk!", "")
	speaker.call("flush")
	if tts.get_pending_count() != 0 or not voice.pending_line_ids().is_empty():
		failures.append("the same prompt must not be queued twice: tts pending %d, voice pending %s"
				% [tts.get_pending_count(), str(voice.pending_line_ids())])
	_drain(h)
	# Any other prompt goes through the pack as an ad-hoc line (subtitled).
	source.prompt_changed.emit("Walk to the kitchen.", "")
	speaker.call("flush")
	if voice.current_text() != "Walk to the kitchen." or String(tts.get_current_text()) != "Walk to the kitchen.":
		failures.append("free prompts still reach the device voice, under the pack: '%s'" % voice.current_text())
	_drain(h)
	# Encouragement is a reaction: it queues behind Bunny rather than cutting him.
	voice.say("bunny_003_yummy")
	source.encouragement.emit("Great!")
	if voice.current_line() != "bunny_003_yummy" or voice.pending_line_ids() != ["aliz_006_good_job"]:
		failures.append("praise must not cut Bunny's Yummy: %s / %s"
				% [voice.current_line(), str(voice.pending_line_ids())])
	_free_node(source)
	_uninstall(h)
	return failures


func _test_without_voice_the_old_path_still_speaks(root: Node):
	var failures: Array = []
	var tts = TtsServiceScript.new()
	tts.name = "TtsService"
	var timers: Array = []
	tts.set_timer_factory(func(_d: float, cb: Callable) -> void: timers.append(cb))
	root.add_child(tts)
	var spoken: Array = []
	tts.speech_started.connect(func(text: String) -> void: spoken.append(text))

	# The highchair's own TtsService lookup needs a live tree (`is_inside_tree()`
	# is false for root children in this runner), so its no-pack path is
	# covered by `test_feeding_table.gd`; here the bridge must simply say no.
	var library: RefCounted = ContentLibraryScript.create()
	var table: Node3D = _make_table(root, failures)
	if table != null and library != null:
		var bridge: GDScript = load("res://scripts/voice/voice_bridge.gd")
		if bool(bridge.call("say_text", table, "Great!")) or bool(bridge.call("cue", table, "foodBite")):
			failures.append("without /root/Voice the bridge must return false so callers keep TtsService")
		table.call("set_task", library.get_task("feedApple"), "apple", "")
		table.call("begin_drag", "apple")
		table.call("drag_to_mouth")
		if not bool(table.call("is_task_finished")):
			failures.append("without the pack the highchair still completes a task")
	_free_node(table)

	var source := PromptSource.new()
	root.add_child(source)
	var speaker: Node = PromptSpeakerScript.attach(source, tts)
	if speaker != null:
		source.prompt_changed.emit("Good morning!", "")
		speaker.call("flush")
		if not spoken.has("Good morning!"):
			failures.append("without the pack PromptSpeaker still speaks through TtsService: %s" % str(spoken))
	_free_node(source)
	_free_node(tts)
	return failures
