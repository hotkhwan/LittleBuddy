extends RefCounted

## THE PLAY-SESSION CLOCK (`play_session.gd`): active seconds only.
##
##   * background / focus notifications stop the clock (injected by hand);
##   * `pause_for("loading")` / `resume_for()` balance; `set_held()` is a level;
##   * time before an owner attaches (title, splash) does not count;
##   * the threshold fires ONCE, `is_due()` holds until answered;
##   * Keep Playing snoozes for `SNOOZE_SECONDS` of ACTIVE time, then fires again;
##   * Home (`mark_break_taken`) starts over;
##   * the setting is read live: 0 is off, odd values snap, corrupt values default;
##   * one instance per tree, no autoload;
##   * `SpeechService.is_requesting_permission()` is honoured when it exists.
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const SessionScript := preload("res://scripts/session/play_session.gd")


class FakeSettings extends RefCounted:
	var values: Dictionary = {}
	func get_setting(key: String, fallback: Variant = null) -> Variant:
		return values.get(key, fallback)


class FakeSpeech extends RefCounted:
	var requesting: bool = false
	func is_requesting_permission() -> bool:
		return requesting


class Counter extends RefCounted:
	var fired: int = 0
	var at: Array = []
	func on_threshold(seconds: float) -> void:
		fired += 1
		at.append(seconds)


func test_name() -> String:
	return "play_session"


func run():
	var failures: Array = []
	failures.append_array(_test_counts_only_while_active())
	failures.append_array(_test_threshold_once_and_snooze())
	failures.append_array(_test_setting_is_live())
	failures.append_array(_test_one_per_tree())
	failures.append_array(_test_permission_prompt_holds())
	return failures


func _make(threshold_minutes: int = 5) -> Array:
	var session: Node = SessionScript.new()
	var settings: FakeSettings = FakeSettings.new()
	settings.values[SessionScript.SETTING_KEY] = threshold_minutes
	session.call("set_settings_source", settings)
	var owner: Node = Node.new()
	session.call("attach", owner)
	return [session, settings, owner]


func _free(parts: Array) -> void:
	(parts[0] as Node).free()
	(parts[2] as Node).free()


func _test_counts_only_while_active():
	var failures: Array = []
	var parts: Array = _make()
	var session: Node = parts[0]
	var owner: Node = parts[2]

	# Nothing attached: nothing counts (the title screen, the splash).
	var lone: Node = SessionScript.new()
	lone.call("set_settings_source", parts[1])
	lone.call("tick", 10.0)
	if float(lone.call("get_active_seconds")) != 0.0:
		failures.append("time with no owner attached counted (%.1f s)" % float(lone.call("get_active_seconds")))
	lone.free()

	session.call("tick", 2.0)
	if absf(float(session.call("get_active_seconds")) - 2.0) > 0.001:
		failures.append("two active seconds counted as %.2f" % float(session.call("get_active_seconds")))

	# Background.
	session.call("notification", Node.NOTIFICATION_APPLICATION_PAUSED)
	session.call("tick", 30.0)
	if absf(float(session.call("get_active_seconds")) - 2.0) > 0.001:
		failures.append("time in the background counted")
	session.call("notification", Node.NOTIFICATION_APPLICATION_RESUMED)
	session.call("tick", 1.0)
	if absf(float(session.call("get_active_seconds")) - 3.0) > 0.001:
		failures.append("the clock did not resume after APPLICATION_RESUMED")

	# Focus out (the OS permission prompt raises this).
	session.call("notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	session.call("tick", 30.0)
	if absf(float(session.call("get_active_seconds")) - 3.0) > 0.001:
		failures.append("time without focus counted")
	session.call("notification", Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	session.call("notification", Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	session.call("tick", 30.0)
	if absf(float(session.call("get_active_seconds")) - 3.0) > 0.001:
		failures.append("time without window focus counted")
	session.call("notification", Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)

	# Loading, counted holds.
	session.call("pause_for", "loading")
	session.call("pause_for", "loading")
	session.call("tick", 5.0)
	session.call("resume_for", "loading")
	session.call("tick", 5.0)
	if absf(float(session.call("get_active_seconds")) - 3.0) > 0.001:
		failures.append("a nested loading hold released after one resume")
	session.call("resume_for", "loading")
	session.call("resume_for", "loading")  # one too many: harmless
	session.call("tick", 1.0)
	if absf(float(session.call("get_active_seconds")) - 4.0) > 0.001:
		failures.append("the clock did not resume after the loading holds balanced")

	# The Grown-ups panel / pause card, as a level.
	session.call("set_held", "menu", true)
	session.call("tick", 20.0)
	session.call("set_held", "menu", false)
	session.call("tick", 1.0)
	if absf(float(session.call("get_active_seconds")) - 5.0) > 0.001:
		failures.append("time in the menu counted")

	# The owner going away stops the clock (leaving the room).
	session.call("detach", owner)
	session.call("tick", 10.0)
	if absf(float(session.call("get_active_seconds")) - 5.0) > 0.001:
		failures.append("time after the owner detached counted")
	session.call("attach", owner)
	owner.free()
	session.call("tick", 10.0)
	if absf(float(session.call("get_active_seconds")) - 5.0) > 0.001:
		failures.append("time after the owner was freed counted")
	if bool(session.call("has_owner")):
		failures.append("a freed owner is still counted as one")
	session.free()
	return failures


func _test_threshold_once_and_snooze():
	var failures: Array = []
	var parts: Array = _make(5)
	var session: Node = parts[0]
	var counter: Counter = Counter.new()
	session.connect("threshold_reached", counter.on_threshold)

	for _i: int in range(299):
		session.call("tick", 1.0)
	if counter.fired != 0 or bool(session.call("is_due")):
		failures.append("the threshold fired before five minutes")
	session.call("tick", 1.0)
	if counter.fired != 1 or not bool(session.call("is_due")):
		failures.append("the threshold did not fire at five minutes (fired %d)" % counter.fired)
	for _i: int in range(600):
		session.call("tick", 1.0)
	if counter.fired != 1:
		failures.append("the threshold fired again while nobody had answered (%d)" % counter.fired)
	if not bool(session.call("is_due")):
		failures.append("is_due() dropped before anyone answered")

	# Keep Playing: quiet for SNOOZE_SECONDS of ACTIVE time, then once more.
	session.call("keep_playing")
	if bool(session.call("is_due")):
		failures.append("Keep Playing left the card due")
	if absf(float(session.call("get_snooze_left")) - SessionScript.SNOOZE_SECONDS) > 0.001:
		failures.append("the snooze is %.0f s, expected %.0f" % [float(session.call("get_snooze_left")), SessionScript.SNOOZE_SECONDS])
	# Background time must not eat the snooze.
	session.call("notification", Node.NOTIFICATION_APPLICATION_PAUSED)
	session.call("tick", 1000.0)
	session.call("notification", Node.NOTIFICATION_APPLICATION_RESUMED)
	if absf(float(session.call("get_snooze_left")) - SessionScript.SNOOZE_SECONDS) > 0.001:
		failures.append("the snooze ran down in the background")
	for _i: int in range(int(SessionScript.SNOOZE_SECONDS) - 1):
		session.call("tick", 1.0)
	if counter.fired != 1:
		failures.append("the card came back before the snooze ran out")
	session.call("tick", 1.0)
	if counter.fired != 2 or not bool(session.call("is_due")):
		failures.append("the threshold did not fire again after the snooze (fired %d)" % counter.fired)

	# Home: a fresh session.
	session.call("mark_break_taken")
	if bool(session.call("is_due")) or float(session.call("get_active_seconds")) != 0.0:
		failures.append("Home did not start a fresh session")
	session.call("tick", 100.0)
	if counter.fired != 2:
		failures.append("a fresh session fired early")
	_free(parts)
	return failures


func _test_setting_is_live():
	var failures: Array = []
	var parts: Array = _make(5)
	var session: Node = parts[0]
	var settings: FakeSettings = parts[1]
	var counter: Counter = Counter.new()
	session.connect("threshold_reached", counter.on_threshold)

	if int(session.call("get_threshold_minutes")) != 5:
		failures.append("the default read as %d minutes" % int(session.call("get_threshold_minutes")))
	session.call("tick", 120.0)
	# Off: never fires, however long.
	settings.values[SessionScript.SETTING_KEY] = 0
	session.call("tick", 10000.0)
	if counter.fired != 0 or bool(session.call("is_enabled")):
		failures.append("Off still fired the reminder")
	# Back to 10: already past it, fires on the next tick.
	settings.values[SessionScript.SETTING_KEY] = 10
	session.call("tick", 0.1)
	if counter.fired != 1:
		failures.append("switching the reminder back on did not apply live (fired %d)" % counter.fired)
	# Corrupt and odd values.
	for raw: Variant in ["banana", null, 3.7, -4, {"a": 1}, 15, 7, 12.6, "10"]:
		settings.values[SessionScript.SETTING_KEY] = raw
		session.call("tick", 0.0)
		var got: int = int(session.call("get_threshold_minutes"))
		var expect: int = SessionScript.normalise_minutes(raw)
		if got != expect:
			failures.append("setting %s read as %d minutes, expected %d" % [str(raw), got, expect])
	if SessionScript.normalise_minutes("banana") != 5 or SessionScript.normalise_minutes(null) != 5:
		failures.append("a corrupt setting does not read as the default")
	if SessionScript.normalise_minutes(-4) != 0 or SessionScript.normalise_minutes(0) != 0:
		failures.append("a non-positive setting does not read as Off")
	if SessionScript.normalise_minutes(7) != 5 or SessionScript.normalise_minutes(12.6) != 15 \
			or SessionScript.normalise_minutes(3.7) != 5 or SessionScript.normalise_minutes(100) != 15:
		failures.append("odd minutes do not snap to the offered choices")
	# `set_threshold_minutes` applies without a settings source.
	var bare: Node = SessionScript.new()
	bare.call("set_threshold_minutes", 15)
	if int(bare.call("get_threshold_minutes")) != 15:
		failures.append("set_threshold_minutes(15) read back as %d" % int(bare.call("get_threshold_minutes")))
	bare.free()
	_free(parts)
	return failures


func _test_one_per_tree():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var before: Node = SessionScript.find(tree)
	var first: Node = SessionScript.get_or_create(tree)
	var second: Node = SessionScript.get_or_create(tree)
	if first == null or first != second:
		failures.append("get_or_create() made two clocks for one tree")
	if first != null and first.get_parent() != tree.root:
		failures.append("the clock is not parked under the root")
	if first != null and first.name != SessionScript.NODE_NAME:
		failures.append("the clock is named '%s', not %s" % [first.name, SessionScript.NODE_NAME])
	# Not an autoload: nothing in project.godot names it.
	var config: ConfigFile = ConfigFile.new()
	if config.load("res://project.godot") == OK:
		for key: String in config.get_section_keys("autoload") if config.has_section("autoload") else []:
			if String(config.get_value("autoload", key)).find("play_session") >= 0:
				failures.append("play_session.gd was added as an autoload; it is created on first use instead")
	# Leave the tree as it was found.
	if before == null and first != null:
		tree.root.remove_child(first)
		first.free()
	return failures


func _test_permission_prompt_holds():
	var failures: Array = []
	var parts: Array = _make(5)
	var session: Node = parts[0]
	var speech: FakeSpeech = FakeSpeech.new()
	session.call("set_speech_service", speech)
	session.call("tick", 1.0)
	speech.requesting = true
	session.call("tick", 30.0)
	if absf(float(session.call("get_active_seconds")) - 1.0) > 0.001:
		failures.append("time under a speech permission request counted")
	speech.requesting = false
	session.call("tick", 1.0)
	if absf(float(session.call("get_active_seconds")) - 2.0) > 0.001:
		failures.append("the clock did not resume after the permission request")
	# A service without the method is simply not asked.
	session.call("set_speech_service", RefCounted.new())
	session.call("tick", 1.0)
	if absf(float(session.call("get_active_seconds")) - 3.0) > 0.001:
		failures.append("a speech service with no is_requesting_permission() held the clock")
	_free(parts)
	return failures
