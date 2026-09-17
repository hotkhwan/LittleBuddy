extends RefCounted

## First run, for a child who cannot read.
##
## Three things have to be true or onboarding is worse than nothing, and all
## three are the kind that stay invisible until a real four-year-old is holding
## the iPad:
##
##   1. **It runs once.** A tutorial that replays on every launch is the fastest
##      way to make a child stop opening a game. Completion has to survive a real
##      load/save round trip through `ProfileStore`, not just an in-memory flag.
##   2. **It cannot trap anybody.** There is no Skip button, because Skip is a
##      word. So every single step must end by itself -- and the whole run must
##      reach the end and be RECORDED as done with no input at all.
##   3. **It is spoken.** Every line is read out. A pre-reader gets nothing from
##      a caption, so a silent onboarding is a blank screen with a hand on it.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract section 8):
## a typed `-> Array` returns an empty Array when the case aborts, and a crashing
## case then reports `[PASS]` with no assertion having run.

const Plan := preload("res://scripts/onboarding/onboarding_plan.gd")
const DirectorScript := preload("res://scripts/onboarding/onboarding_director.gd")
const GestureHintScript := preload("res://scripts/onboarding/gesture_hint.gd")
const ProfileStoreScript := preload("res://scripts/save/profile_store.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"

## One "frame" of the driven clock. Small enough that a step never overshoots by
## more than this, big enough that a whole run is a few hundred iterations.
const TICK: float = 0.1
## Generous: the plan's own total is asserted separately, so this only has to
## stop a runaway loop.
const MAX_TICKS: int = 2000


## A save service that remembers settings and nothing else. Enough for the
## decision and for `set_setting`, and it records how often it was written so a
## "records completion twice" regression is visible.
class FakeSave extends RefCounted:
	var settings: Dictionary = {}
	var writes: int = 0

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		if settings.has(key):
			return settings[key]
		return default_value

	func set_setting(key: String, value: Variant) -> void:
		writes += 1
		settings[key] = value

	func get_stars() -> int:
		return 0


## A voice that writes down what it was asked to say.
class FakeTts extends RefCounted:
	var lines: Array = []

	func speak(text: String, _interrupt: bool = true) -> void:
		lines.append(text)


func test_name() -> String:
	return "onboarding"


func run():
	var failures: Array = []
	failures.append_array(_test_the_plan_is_a_plan())
	failures.append_array(_test_it_runs_once())
	failures.append_array(_test_completion_survives_a_real_save())
	failures.append_array(_test_nobody_can_get_stuck())
	failures.append_array(_test_doing_it_early_advances_early())
	failures.append_array(_test_every_line_is_spoken())
	failures.append_array(_test_the_child_is_never_locked_out_of_the_world())
	failures.append_array(_test_the_hand_points_at_a_real_object())
	failures.append_array(_test_the_gesture_hint_draws_something())
	failures.append_array(_test_the_world_defers_the_session())
	return failures


## -- The plan ------------------------------------------------------------------

func _test_the_plan_is_a_plan():
	var failures: Array = []
	var steps: Array = Plan.steps()

	if steps.size() < 4:
		failures.append("first run has only %d steps; the brief asks for Little Buddy, a "
				% steps.size() + "tap-to-walk hint, a drag hint, a spoken intro and one action")

	var seen: Array = []
	var gestures: Array = []
	for step: Variant in steps:
		var data: Dictionary = step as Dictionary
		var step_id: String = String(data.get("stepId", ""))
		if step_id.is_empty():
			failures.append("a step has no stepId")
		if seen.has(step_id):
			failures.append("duplicate step id '%s'" % step_id)
		seen.append(step_id)

		if String(data.get("speech", "")).strip_edges().is_empty():
			failures.append(
				"step '%s' says nothing. The player is a pre-reader: a step with no spoken " % step_id
				+ "line is a picture with no explanation."
			)

		# THE anti-trap assertion. A step with no timeout, a negative one, or one
		# longer than the plan's own ceiling is a step a child could sit in for
		# ever with no Skip button to press.
		var timeout: float = float(data.get("timeoutSec", 0.0))
		if timeout <= 0.0:
			failures.append(
				"step '%s' has a timeoutSec of %.2f. Every step must end BY ITSELF: there is " % [step_id, timeout]
				+ "no Skip button, because Skip is a word a four-year-old cannot read."
			)
		if timeout > Plan.MAX_STEP_SECONDS:
			failures.append("step '%s' lasts %.1fs, over the %.1fs ceiling"
					% [step_id, timeout, Plan.MAX_STEP_SECONDS])
		gestures.append(String(data.get("gesture", "")))

	# The two gestures the brief names by hand.
	if not gestures.has(Plan.GESTURE_TAP_FLOOR):
		failures.append("no step shows the tap-to-walk gesture")
	if not gestures.has(Plan.GESTURE_DRAG):
		failures.append("no step shows the drag gesture")

	# Exactly one step asks the child to DO something and finish it; that is the
	# brief's "one easy action".
	var completable: int = 0
	for step: Variant in steps:
		if not String((step as Dictionary).get("requires", "")).is_empty():
			completable += 1
	if completable < 1:
		failures.append("no step can be completed by the child; first run never asks them to "
				+ "do anything")

	if Plan.total_seconds() > 45.0:
		failures.append("first run takes %.0fs with no input at all; that is a lesson, not an "
				% Plan.total_seconds() + "introduction")

	return failures


## -- It runs once --------------------------------------------------------------

func _test_it_runs_once():
	var failures: Array = []

	if Plan.should_run(true):
		failures.append(
			"onboarding still wants to run for a profile whose settings.%s is true. A tutorial "
			% Plan.SETTING_KEY + "that replays on every launch is the fastest way to make a "
			+ "child stop opening a game."
		)
	# Everything that is NOT an explicit `true` means "never been shown".
	for value: Variant in [null, false, "", 0, "true", {}]:
		if not Plan.should_run(value):
			failures.append("onboarding was skipped for settings.%s = %s, which is not a "
					% [Plan.SETTING_KEY, str(value)] + "recorded completion")

	# No save service at all -> never run. Onboarding that cannot be recorded
	# would play every launch, and it is what keeps the headless runner booting
	# the plain house every other case asserts against.
	if DirectorScript.should_run(null):
		failures.append("onboarding runs with no save service; it could never be recorded as "
				+ "done, so it would replay for ever")

	var done: FakeSave = FakeSave.new()
	done.settings[Plan.SETTING_KEY] = true
	if DirectorScript.should_run(done):
		failures.append("the director ignores a recorded completion")

	var fresh: FakeSave = FakeSave.new()
	if not DirectorScript.should_run(fresh):
		failures.append("a fresh profile does not get first run at all")

	return failures


## The flag has to come back off DISK. `settings.onboardingDone` is not part of
## the declared schema -- it relies on `ProfileStore` preserving unknown JSON-safe
## settings keys -- so if that behaviour ever changed, onboarding would silently
## replay for every child on every launch with this whole case otherwise green.
func _test_completion_survives_a_real_save():
	var failures: Array = []
	var path: String = "user://test_onboarding_%d.json" % randi()
	var store: RefCounted = ProfileStoreScript.new(path)
	var service: Node = SaveServiceScript.new(store)
	service.call("reload_profile")

	if not DirectorScript.should_run(service):
		failures.append("a brand new profile on disk does not get first run")

	service.call("set_setting", Plan.SETTING_KEY, true)

	var reloaded: RefCounted = ProfileStoreScript.new(path)
	var profile: Dictionary = reloaded.call("load_profile")
	var settings: Variant = profile.get("settings", null)
	if typeof(settings) != TYPE_DICTIONARY:
		failures.append("the saved profile has no settings block")
	elif (settings as Dictionary).get(Plan.SETTING_KEY, null) != true:
		failures.append(
			"settings.%s did not survive a save/load round trip (got %s). ProfileStore "
			% [Plan.SETTING_KEY, str((settings as Dictionary).get(Plan.SETTING_KEY, null))]
			+ "preserves unknown JSON-safe settings keys, and onboarding relies on exactly "
			+ "that instead of adding a schema field."
		)

	var second: Node = SaveServiceScript.new(reloaded)
	second.call("reload_profile")
	if DirectorScript.should_run(second):
		failures.append("a reloaded profile that has completed first run still wants it")

	service.free()
	second.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return failures


## -- Nobody can get stuck ------------------------------------------------------

## The whole run, with NO input of any kind: no tap, no walk, no arrival. It must
## still reach the end, and it must still be recorded, or a child who ignores the
## tutorial gets it again tomorrow.
func _test_nobody_can_get_stuck():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]

	var save: FakeSave = FakeSave.new()
	var director: Node = _make_director(world, save, FakeTts.new())
	if director == null:
		_release(world)
		return ["the house built no onboarding director"]

	var seen: Array = []
	director.connect("step_changed", func(step_id: String) -> void: seen.append(step_id))

	if not bool(director.call("start")):
		failures.append("first run refused to start")

	var ticks: int = 0
	while not bool(director.call("is_finished")) and ticks < MAX_TICKS:
		director.call("step", TICK)
		ticks += 1

	if not bool(director.call("is_finished")):
		failures.append(
			"first run never ended with no input at all. There is no Skip button in this game "
			+ "-- a four-year-old cannot read one -- so the clock IS the escape hatch, and a "
			+ "step that does not time out is a child stuck for ever."
		)
	if bool(director.call("is_running")):
		failures.append("first run reports itself as still running after finishing")
	if save.settings.get(Plan.SETTING_KEY, null) != true:
		failures.append("a timed-out first run was not recorded as done, so it plays again "
				+ "tomorrow and the day after")
	if seen != Plan.step_ids():
		failures.append("the steps ran as %s, expected %s" % [str(seen), str(Plan.step_ids())])

	var elapsed: float = float(ticks) * TICK
	if elapsed > Plan.total_seconds() + 2.0:
		failures.append("an untouched first run took %.1fs, longer than the plan's own %.1fs"
				% [elapsed, Plan.total_seconds()])

	# Finishing twice must not write the flag twice.
	var writes: int = save.writes
	director.call("finish")
	if save.writes != writes:
		failures.append("finish() is not idempotent; it wrote completion again")

	_release(world)
	return failures


## A child who does the thing does not have to wait out the clock as well.
func _test_doing_it_early_advances_early():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var character: Node = world.call("get_character")

	var director: Node = _make_director(world, FakeSave.new(), FakeTts.new())
	if director == null:
		_release(world)
		return ["the house built no onboarding director"]
	director.call("start")

	# Run up to the tap-to-walk step.
	var ticks: int = 0
	while String(director.call("get_step_id")) != Plan.STEP_TAP_FLOOR and ticks < MAX_TICKS:
		director.call("step", TICK)
		ticks += 1
	if String(director.call("get_step_id")) != Plan.STEP_TAP_FLOOR:
		_release(world)
		return ["first run never reached the '%s' step" % Plan.STEP_TAP_FLOOR]

	# The child taps the floor. The character starts walking; that is the signal.
	character.emit_signal("move_started", "")
	director.call("step", TICK)

	if String(director.call("get_step_id")) == Plan.STEP_TAP_FLOOR:
		failures.append(
			"the child walked and first run stayed on the 'tap the floor' step. Doing the "
			+ "thing has to be enough; otherwise the hand keeps pointing at the floor while "
			+ "Little Buddy is already standing on it."
		)

	# And the next step's own early exit: arriving at any object at all.
	ticks = 0
	while String(director.call("get_step_id")) != Plan.STEP_TAP_THING and ticks < MAX_TICKS:
		director.call("step", TICK)
		ticks += 1
	if String(director.call("get_step_id")) == Plan.STEP_TAP_THING:
		character.emit_signal("interaction_ready", "bedroom.wardrobe")
		director.call("step", TICK)
		if String(director.call("get_step_id")) == Plan.STEP_TAP_THING:
			failures.append("arriving at an object did not finish the 'tap a thing' step")
	else:
		failures.append("first run never reached the '%s' step" % Plan.STEP_TAP_THING)

	_release(world)
	return failures


## -- It is spoken --------------------------------------------------------------

func _test_every_line_is_spoken():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]

	var tts: FakeTts = FakeTts.new()
	var director: Node = _make_director(world, FakeSave.new(), tts)
	if director == null:
		_release(world)
		return ["the house built no onboarding director"]

	director.call("start")
	var ticks: int = 0
	while not bool(director.call("is_finished")) and ticks < MAX_TICKS:
		director.call("step", TICK)
		ticks += 1

	if tts.lines.size() < Plan.total():
		failures.append(
			"first run spoke %d lines for %d steps. The player cannot read: a step whose line "
			% [tts.lines.size(), Plan.total()]
			+ "is only drawn on screen does not exist for them."
		)
	for line: Variant in tts.lines:
		if String(line).strip_edges().is_empty():
			failures.append("first run asked the voice to say an empty line")

	if director.call("get_spoken_lines") != tts.lines:
		failures.append("the director's own record of what it said disagrees with the voice")

	# Kindness (CLAUDE.md child UX): no report-card vocabulary anywhere.
	for line: Variant in tts.lines:
		var lowered: String = String(line).to_lower()
		for banned: String in ["wrong", "fail", "oops", "score", "percent", "%"]:
			if lowered.contains(banned):
				failures.append("first run says '%s', which is not how this game talks to a "
						% String(line) + "four-year-old")

	_release(world)
	return failures


## -- Never a cage --------------------------------------------------------------

## A child who ignores every hint must be PLAYING, not blocked. So first run
## never switches taps off and never disables the character -- at any step.
func _test_the_child_is_never_locked_out_of_the_world():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var character: Node = world.call("get_character")
	var nav: Node = world.get_node_or_null("NavigationController")

	var director: Node = _make_director(world, FakeSave.new(), FakeTts.new())
	if director == null:
		_release(world)
		return ["the house built no onboarding director"]
	director.call("start")

	var ticks: int = 0
	while not bool(director.call("is_finished")) and ticks < MAX_TICKS:
		director.call("step", TICK)
		ticks += 1
		if nav != null and not bool(nav.get("taps_enabled")):
			failures.append("first run switched taps off at step '%s'; a child who ignores it "
					% String(director.call("get_step_id")) + "must still be playing")
			break
		if character != null and String(character.call("get_state_name")) == "disabled":
			failures.append("first run disabled the character at step '%s'"
					% String(director.call("get_step_id")))
			break

	_release(world)
	return failures


## -- The hand points at something real -----------------------------------------

func _test_the_hand_points_at_a_real_object():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]

	var director: Node = _make_director(world, FakeSave.new(), FakeTts.new())
	if director == null:
		_release(world)
		return ["the house built no onboarding director"]
	director.call("start")

	var thing_id: String = String(director.call("get_thing_id"))
	if thing_id.is_empty():
		failures.append("first run points the 'tap a thing' hint at nothing at all")
	elif world.call("get_target_by_semantic_id", thing_id) == null:
		failures.append("first run points at '%s', which is not in this house" % thing_id)
	elif thing_id.contains("doorTo"):
		failures.append(
			"first run's one easy action is a DOOR (%s). Tapping it changes the whole room, "
			% thing_id + "which is a confusing first lesson and moves the child out of the "
			+ "scene the run set up."
		)

	# And the spoken line names it, rather than saying something generic.
	var ticks: int = 0
	while String(director.call("get_step_id")) != Plan.STEP_TAP_THING and ticks < MAX_TICKS:
		director.call("step", TICK)
		ticks += 1
	var caption: String = String(director.call("get_caption"))
	var display: String = String(world.call("get_target_by_semantic_id", thing_id).get("display_name"))
	if not display.is_empty() and not caption.to_lower().contains(display.to_lower()):
		failures.append("first run says '%s' but is pointing at the %s" % [caption, display])

	_release(world)
	return failures


## -- The overlay itself --------------------------------------------------------

## The hint is a picture; a picture that never changes is a static image of a
## hand, which is not a gesture. Drive its clock and check it moves.
func _test_the_gesture_hint_draws_something():
	var failures: Array = []
	var hint: Control = GestureHintScript.new()
	hint.call("build")

	if hint.visible:
		failures.append("the gesture hint starts visible; it would be on screen with nothing "
				+ "to point at")
	if hint.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		failures.append(
			"the gesture hint can eat input. It sits ON TOP of the thing it is telling the "
			+ "child to touch, so a child who does exactly as it says would be ignored."
		)
	if hint.size == Vector2.ZERO and hint.anchor_right != 1.0:
		failures.append("the gesture hint is not full-rect; set_anchors_and_offsets_preset() "
				+ "is the one that also sets the offsets")

	hint.call("show_tap", Vector2(400.0, 300.0))
	if not hint.visible:
		failures.append("show_tap() left the hint hidden")
	if String(hint.call("get_mode")) != "tap":
		failures.append("show_tap() did not switch to the tap gesture")
	if not (hint.call("get_point") as Vector2).is_equal_approx(Vector2(400.0, 300.0)):
		failures.append("the hint is not where it was told to point")

	var before: float = float(hint.call("get_clock"))
	hint.call("step", 0.25)
	if is_equal_approx(float(hint.call("get_clock")), before):
		failures.append("the hint's animation clock does not advance; the hand would never "
				+ "move and there would be no gesture at all")

	hint.call("show_drag", Vector2(200.0, 400.0), Vector2(600.0, 400.0))
	if String(hint.call("get_mode")) != "drag":
		failures.append("show_drag() did not switch to the drag gesture")

	hint.call("hide_hint")
	if hint.visible:
		failures.append("hide_hint() left the hint on screen")

	hint.free()
	return failures


## -- The house defers to it ----------------------------------------------------

func _test_the_world_defers_the_session():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]

	var director: Node = world.call("ensure_onboarding_director")
	if director == null:
		failures.append("HouseWorld builds no onboarding director")
	elif world.call("ensure_onboarding_director") != director:
		failures.append("ensure_onboarding_director() is not idempotent; a second call built "
				+ "a second overlay")

	# With no `/root/SaveService` -- which is every headless run -- the house must
	# come up exactly as it always has: walkable, objective-free, no tutorial.
	if bool(world.call("is_onboarding_active")):
		failures.append("onboarding is running with no save service to record it in")

	_release(world)
	return failures


## -- Helpers -------------------------------------------------------------------

func _build_house():
	if not ResourceLoader.exists(HOUSE_SCENE):
		return null
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	if world == null:
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	# `_ready()` does not fire for a node added to the root in the `--script`
	# runner, so the world is built by hand.
	world.call("build_world")
	return world


func _make_director(world, save, tts):
	var director: Node = world.call("ensure_onboarding_director")
	if director == null:
		return null
	director.call("set_save_service", save)
	director.call("set_tts", tts)
	return director


func _release(world) -> void:
	if world == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()
