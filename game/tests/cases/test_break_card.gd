extends RefCounted

## THE BREAK CARD, and where it is allowed to appear.
##
##   card     the owner's copy exactly; Keep Playing is the biggest button; the
##            two voice ids go to `/root/Voice` when there is one and the same
##            English to `TtsService` when there is not; nothing says "quit"
##   host     holds taps / character / affordances / narration and puts back
##            exactly what it found; Keep Playing snoozes the clock; Home saves
##            and asks the world to `leave_to_home()`; music comes down and back
##   Free Play  waits while Bunny is in her arms and shows once she is calm
##   Story      never over a care overlay; shows after the next task completes;
##              the runner is held between tasks and released by Keep Playing;
##              after the summary the next level is parked until Keep Playing
##   Baby Room  wired at the same seams (read from the script: the room needs a
##              3D viewport the headless runner has not got, as
##              `test_level_summary.gd` explains)
##   free house every room enters in Free Play on a free-starter profile
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const CardScript := preload("res://scripts/ui/break_card.gd")
const HostScript := preload("res://scripts/session/break_host.gd")
const SessionScript := preload("res://scripts/session/play_session.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const L10n := preload("res://scripts/localization/localization.gd")
const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const BABY_ROOM_SCRIPT: String = "res://scenes/baby_room/baby_room.gd"
const MODE_FREE_PLAY: int = 1
const DT: float = 1.0 / 30.0


class FakeVoice extends RefCounted:
	var said: Array = []
	func say(line_id: String) -> void:
		said.append(line_id)


class FakeTts extends RefCounted:
	var lines: Array = []
	func speak(text: String, _interrupt: bool = true) -> void:
		lines.append(text)


class FakeSave extends RefCounted:
	var saved: int = 0
	var settings: Dictionary = {}
	func save_profile() -> bool:
		saved += 1
		return true
	func get_setting(key: String, fallback: Variant = null) -> Variant:
		return settings.get(key, fallback)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value
	func get_stars() -> int:
		return 0


class FakeAudio extends RefCounted:
	var db: float = -6.0
	func get_music_volume_db() -> float:
		return db
	func set_music_volume_db(value: float) -> void:
		db = clampf(value, -60.0, 0.0)


class FakeWorld extends Node:
	var left: int = 0
	func leave_to_home() -> bool:
		left += 1
		return true
	func get_character() -> Node:
		return null


func test_name() -> String:
	return "break_card"


func run():
	var failures: Array = []
	failures.append_array(_test_card_copy_and_voice())
	failures.append_array(_test_host_home_saves_and_leaves())
	failures.append_array(_test_free_play_waits_then_shows())
	failures.append_array(_test_story_seams())
	failures.append_array(_test_baby_room_is_wired())
	failures.append_array(_test_every_room_enters_in_free_play())
	_drop_session()
	return failures


## -- The card ------------------------------------------------------------------------

func _test_card_copy_and_voice():
	var failures: Array = []
	var card: Control = CardScript.new()
	card.call("build")
	if String(card.call("get_title_text")) != "Great job today!":
		failures.append("card: the title is '%s'" % card.call("get_title_text"))
	var body: PackedStringArray = card.call("get_body_lines")
	if body.size() != 2 or body[0] != "Let's take a little break." \
			or body[1] != "Come back soon for more Little Days!":
		failures.append("card: the body is %s" % str(body))
	var buttons: Dictionary = card.call("get_buttons")
	var keep: Button = buttons.get("keep")
	var home: Button = buttons.get("home")
	if keep == null or home == null:
		failures.append("card: the two buttons are missing")
	else:
		if keep.text != "Keep Playing" or home.text != "Home":
			failures.append("card: the buttons read '%s' / '%s'" % [keep.text, home.text])
		if keep.custom_minimum_size.x <= home.custom_minimum_size.x \
				or keep.custom_minimum_size.y <= home.custom_minimum_size.y:
			failures.append("card: Keep Playing is not the biggest button")
		if keep.custom_minimum_size.x < 240.0 or home.custom_minimum_size.x < 240.0:
			failures.append("card: a button is under the 240 px touch floor")
		if home.find_child("HouseGlyph", true, false) == null:
			failures.append("card: Home has no house glyph")
	for text: String in [card.call("get_title_text"), body[0], body[1], keep.text, home.text]:
		var lowered: String = text.to_lower()
		for banned: String in ["quit", "exit", "%", "time's up", "stop", "locked", "subscribe"]:
			if lowered.find(banned) >= 0:
				failures.append("card: '%s' contains '%s'" % [text, banned])

	# Voice: the director's ids, in order.
	var voice: FakeVoice = FakeVoice.new()
	var tts: FakeTts = FakeTts.new()
	card.call("set_voices", voice, tts)
	card.call("open")
	if voice.said != ["aliz_023_break", "aliz_024_come_back"]:
		failures.append("card: the voice director was asked for %s" % str(voice.said))
	if not tts.lines.is_empty():
		failures.append("card: TTS spoke as well as the voice director")
	if not card.visible:
		failures.append("card: open() did not show it")
	# ...and the English fallback when there is no director.
	card.call("close")
	card.call("set_voices", null, tts)
	card.call("open")
	if tts.lines.size() != 2 or tts.lines[0].find("Great job today") < 0 \
			or tts.lines[1] != "Come back soon for more Little Days!":
		failures.append("card: the TTS fallback said %s" % str(tts.lines))
	# Keep Playing closes and says so; Home only says so.
	var kept: Array = []
	card.connect("keep_playing_pressed", func() -> void: kept.append(true))
	var homes: Array = []
	card.connect("home_pressed", func() -> void: homes.append(true))
	keep.pressed.emit()
	if kept.size() != 1 or card.visible:
		failures.append("card: Keep Playing did not close the card")
	card.call("open")
	home.pressed.emit()
	if homes.size() != 1 or not card.visible:
		failures.append("card: Home closed the card itself; the host decides what Home does")
	# The helper line follows the family's language and is hidden when off.
	L10n.set_helper_language("off")
	card.call("close")
	card.call("open")
	if not String(card.call("get_helper_text")).is_empty():
		failures.append("card: a helper line shows with the helper off")
	L10n.set_helper_language(L10n.DEFAULT_HELPER_LANGUAGE)
	card.free()
	return failures


## -- The host: Home --------------------------------------------------------------------

func _test_host_home_saves_and_leaves():
	var failures: Array = []
	var world: FakeWorld = FakeWorld.new()
	var host: Node = HostScript.new()
	world.add_child(host)
	var save: FakeSave = FakeSave.new()
	var audio: FakeAudio = FakeAudio.new()
	host.call("set_services", save, audio)
	host.call("bind", world, null)
	var session: Node = host.call("get_session")
	if session == null:
		world.free()
		return ["host: no session was made"]
	session.call("set_settings_source", save)
	session.call("reset")
	session.call("set_threshold_minutes", 5)
	session.call("tick", 301.0)
	if not bool(host.call("is_due")):
		failures.append("host: not due after five active minutes")
	if not bool(host.call("show")):
		failures.append("host: show() refused")
	if absf(audio.db - (-14.0)) > 0.01:
		failures.append("host: the music was not ducked (%.1f dB)" % audio.db)
	var card: Control = host.call("get_card")
	if card == null or not card.visible:
		failures.append("host: no card on screen")
	else:
		(card.call("get_buttons") as Dictionary)["home"].pressed.emit()
	if save.saved != 1:
		failures.append("host: Home did not save the profile (saved %d)" % save.saved)
	if world.left != 1:
		failures.append("host: Home did not call leave_to_home() (%d)" % world.left)
	if bool(session.call("is_due")) or float(session.call("get_active_seconds")) != 0.0:
		failures.append("host: Home did not start a fresh session")
	world.free()
	return failures


## -- Free Play ---------------------------------------------------------------------------

func _test_free_play_waits_then_shows():
	var failures: Array = []
	var world: Node = _build_house(true)
	if world == null:
		return ["could not build the house"]
	var director: Node = world.call("ensure_free_play_director")
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	var tts: FakeTts = FakeTts.new()
	var save: FakeSave = FakeSave.new()
	director.call("set_tts", tts)
	director.call("set_save_service", save)
	director.call("start")
	var aliz: Node3D = world.call("get_character")
	var bunny: Node = world.get_node_or_null("Rooms/Bedroom/LittleBuddyChild")
	var host: Node = director.call("get_break_host")
	var session: Node = host.call("get_session") if host != null else null
	if host == null or session == null:
		_release(world)
		return ["free play: no break host / session"]
	var audio: FakeAudio = FakeAudio.new()
	host.call("set_services", save, audio)
	session.call("set_settings_source", save)
	session.call("reset")
	session.call("set_threshold_minutes", 5)
	world.call("place_in_room", "bedroom", "")

	# Bunny in her arms when the clock says so: the card waits.
	if bunny != null:
		SpatialUtil.set_world_position(aliz, SpatialUtil.world_position(bunny) + Vector3(0.0, 0.0, 0.62))
		if not bool(bunny.call("perform_affordance", aliz)):
			failures.append("free play: could not pick Bunny up")
		_step(aliz, director, 40)
	session.call("tick", 301.0)
	if not bool(session.call("is_due")):
		failures.append("free play: the clock is not due")
	if bool(director.call("is_calm")):
		failures.append("free play: calm with Bunny in her arms")
	_step(aliz, director, 150)
	if bool(host.call("is_open")):
		failures.append("free play: the card came up while Bunny was carried")
	if aliz != null and not bool(aliz.call("is_carrying_node")):
		failures.append("free play: Bunny was dropped")
	# Put him down: calm for two seconds, then the card. Frame by frame, so
	# the calm the card waited for can be read the moment it appears.
	var nav: Node = world.get_node_or_null("NavigationController")
	var taps_before: Variant = nav.get("taps_enabled") if nav != null else null
	var layer: Control = world.call("get_affordance_layer")
	var hud: Control = director.call("get_hud")
	if bunny != null:
		aliz.call("put_down_carried")
	var calm_before_card: float = -1.0
	var became_calm: bool = false
	for _frame: int in range(240):
		var calm_now: float = float(director.call("get_calm_seconds"))
		if bool(director.call("is_calm")):
			became_calm = true
		_step(aliz, director, 1)
		if bool(host.call("is_open")):
			calm_before_card = calm_now
			break
	if not became_calm:
		failures.append("free play: never calm standing still with empty hands (state %s)" % aliz.call("get_state_name"))
	if calm_before_card < 0.0:
		failures.append("free play: the card did not show after two calm seconds")
	elif calm_before_card < 2.0 - DT * 1.5:
		failures.append("free play: the card came up after only %.2f calm seconds" % calm_before_card)
	if bool(host.call("is_open")):
		if nav != null and bool(nav.get("taps_enabled")):
			failures.append("free play: taps stayed on under the card")
		if String(aliz.call("get_state_name")) != "disabled":
			failures.append("free play: the character was not held under the card")
		if layer != null and bool(layer.call("is_enabled")):
			failures.append("free play: affordances stayed on under the card")
		if hud != null and not bool(hud.call("is_narration_covered")):
			failures.append("free play: the HUD narration was not covered")
		if absf(audio.db - (-14.0)) > 0.01:
			failures.append("free play: the music was not ducked")
		var hint: Control = director.call("get_hint")
		_step(aliz, director, 400)
		if hint != null and hint.visible:
			failures.append("free play: the pointing hand nudged over the card")
		# Keep Playing: everything back, clock snoozed.
		host.call("keep_playing")
		if bool(host.call("is_open")):
			failures.append("free play: Keep Playing left the card up")
		if nav != null and nav.get("taps_enabled") != taps_before:
			failures.append("free play: taps not restored (%s -> %s)" % [str(taps_before), str(nav.get("taps_enabled"))])
		if String(aliz.call("get_state_name")) == "disabled":
			failures.append("free play: the character stayed disabled after Keep Playing")
		if layer != null and not bool(layer.call("is_enabled")):
			failures.append("free play: affordances not restored")
		if hud != null and bool(hud.call("is_narration_covered")):
			failures.append("free play: the HUD narration stayed covered")
		if absf(audio.db - (-6.0)) > 0.01:
			failures.append("free play: the music did not come back (%.1f dB)" % audio.db)
		if bool(session.call("is_due")) or absf(float(session.call("get_snooze_left")) - 180.0) > 0.01:
			failures.append("free play: Keep Playing did not snooze for 180 s")
		_step(aliz, director, 120)
		if bool(host.call("is_open")):
			failures.append("free play: the card came straight back after Keep Playing")
	_release(world)
	return failures


## -- Story -----------------------------------------------------------------------------

func _test_story_seams():
	var failures: Array = []
	var world: Node = _build_house(false)
	if world == null:
		return ["could not build the house"]
	var director: Node = world.call("ensure_level_director")
	if director == null:
		_release(world)
		return ["the house built no level director"]
	director.call("start")
	var runner: Node = director.call("get_runner")
	var aliz: Node = world.call("get_character")
	var host: Node = director.call("get_break_host")
	var session: Node = host.call("get_session") if host != null else null
	if runner == null or host == null or session == null or not bool(runner.call("is_running")):
		_release(world)
		return ["story: no runner / host / session, or the level did not start"]
	var save: FakeSave = FakeSave.new()
	host.call("set_services", save, FakeAudio.new())
	session.call("set_settings_source", save)
	session.call("reset")
	session.call("set_threshold_minutes", 5)
	session.call("tick", 301.0)

	# Due, but a task is under way (and the care overlay is up): no card.
	var care: Control = director.get("_care_overlay")
	if care != null:
		care.visible = true
	var task_before: String = String(runner.call("get_current_task_id"))
	_step(aliz, director, 120)
	if bool(host.call("is_open")):
		failures.append("story: the card came up mid-task, over the care overlay")
	if bool(runner.call("is_advance_held")):
		failures.append("story: the runner was held before any seam")
	if care != null:
		care.visible = false

	# The task completes (Next, the touch fallback): the runner parks, the
	# reaction gets its moment, then the card.
	runner.call("skip_current_task")
	if not bool(runner.call("is_advance_held")):
		failures.append("story: the runner was not held at the seam")
	if String(runner.call("get_current_task_id")) != task_before:
		failures.append("story: the next task started under the seam")
	if bool(host.call("is_open")):
		failures.append("story: the card came up before the acknowledgement")
	_step(aliz, director, 60)
	if not bool(host.call("is_open")):
		failures.append("story: the card did not show after the task's seam")
	if String(runner.call("get_current_task_id")) != task_before:
		failures.append("story: the next task started under the card")
	if bool(director.call("is_summary_open")):
		failures.append("story: the summary opened under the card")
	# Keep Playing: the parked task starts now.
	host.call("keep_playing")
	if bool(runner.call("is_advance_held")):
		failures.append("story: Keep Playing left the runner held")
	if bool(runner.call("is_running")) and String(runner.call("get_current_task_id")) == task_before:
		failures.append("story: the next task did not start after Keep Playing")
	if String(aliz.call("get_state_name")) == "disabled":
		failures.append("story: the child was left disabled after Keep Playing")
	# Snoozed: the next seams pass without a card.
	runner.call("skip_current_task")
	_step(aliz, director, 60)
	if bool(host.call("is_open")) or bool(runner.call("is_advance_held")):
		failures.append("story: the card came back at the very next seam")

	# After the summary: the next level is parked until Keep Playing.
	session.call("tick", 400.0)
	var guard: int = 0
	while bool(runner.call("is_running")) and guard < 20:
		guard += 1
		if bool(host.call("is_open")):
			# A seam on the way to the end: answer it and carry on.
			host.call("keep_playing")
			session.call("tick", 400.0)
		runner.call("skip_current_task")
		_step(aliz, director, 60)
	if bool(host.call("is_open")):
		host.call("keep_playing")
		session.call("tick", 400.0)
		_step(aliz, director, 10)
	if not bool(director.call("is_summary_open")):
		failures.append("story: the level did not end on the summary")
	else:
		var level_before: String = String(director.call("get_mission_id"))
		director.call("advance_to_next_level")
		if not bool(host.call("is_open")):
			failures.append("story: no card after the summary although the clock was due")
		if bool(director.call("is_running")):
			failures.append("story: the next level started under the card")
		host.call("keep_playing")
		_step(aliz, director, 5)
		if not bool(director.call("is_running")):
			failures.append("story: the parked level did not start after Keep Playing (was %s)" % level_before)
	_release(world)
	return failures


## -- Baby Room --------------------------------------------------------------------------

func _test_baby_room_is_wired():
	var failures: Array = []
	var file: FileAccess = FileAccess.open(BABY_ROOM_SCRIPT, FileAccess.READ)
	if file == null:
		return ["baby room: cannot read %s" % BABY_ROOM_SCRIPT]
	var source: String = file.get_as_text()
	file.close()
	for needle: String in [
		"PlaySessionScript.get_or_create(",
		"_hold_for_break_if_due()",
		"set_advance_held",
		"_break_at_summary_seam(",
		"is_dragging",
		"\"set_held\", \"menu\", true",
		"save_profile",
		"mark_break_taken",
	]:
		if not source.contains(needle):
			failures.append("baby room: %s is not wired (missing `%s`)" % [BABY_ROOM_SCRIPT, needle])
	# Both seams: the completion hook AND the skip hook call the hold.
	if source.count("_hold_for_break_if_due()") < 3:
		failures.append("baby room: the seam hook is not called from both task completion and skip")
	# Never ends the app.
	if source.contains("get_tree().quit") or source.contains("tree.quit"):
		failures.append("baby room: something quits the app")
	return failures


## -- Every room enters in Free Play ------------------------------------------------------

func _test_every_room_enters_in_free_play():
	var failures: Array = []
	var world: Node = _build_house(true)
	if world == null:
		return ["could not build the house"]
	var director: Node = world.call("ensure_free_play_director")
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("set_tts", FakeTts.new())
	director.call("set_save_service", FakeSave.new())
	director.call("start")
	var transition: Node = world.call("get_transition_controller")
	var refused: Array = []
	if transition != null:
		transition.connect("transition_refused", func(room_id: String, reason: String) -> void:
			refused.append("%s:%s" % [room_id, reason]))
	for room_id: Variant in world.call("get_room_ids"):
		if not bool(director.call("is_room_open", String(room_id))):
			failures.append("free play: '%s' is not open" % room_id)
		if transition != null and not bool(transition.call("request_transition", String(room_id), "")):
			failures.append("free play: could not enter '%s'" % room_id)
	for entry: Variant in refused:
		if String(entry).ends_with(":locked"):
			failures.append("free play: a door refused as locked (%s)" % entry)
	_release(world)
	return failures


## -- Helpers ----------------------------------------------------------------------------

func _step(aliz: Node, director: Node, frames: int) -> void:
	for _i: int in range(frames):
		if aliz != null:
			aliz.call("step_movement", DT)
		director.call("step", DT)


func _build_house(free_play: bool):
	if not ResourceLoader.exists(HOUSE_SCENE):
		return null
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	if free_play:
		world.call("set_progression_mode", MODE_FREE_PLAY)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	world.call("build_world")
	return world


func _release(world) -> void:
	if world == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()


## The clock is parked under the root; leave the tree as it was found.
func _drop_session() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var session: Node = SessionScript.find(tree)
	if session != null:
		tree.root.remove_child(session)
		session.free()
