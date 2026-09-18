extends RefCounted

## First launch: does a child who has never opened this game before actually get
## taught anything?
##
## For a while the answer was no, and every other test was green while it was no.
## Onboarding lives in the house, because three of the four things it teaches
## (walk there, use that, carry this) do not exist anywhere else. But
## `ProfileStore.default_profile()` writes `currentChapter: "ch1"`, `main.gd`
## routes ch1 and ch2 to the Baby Room, and so a brand new player was routed
## straight past the tutorial and never saw it once. Nothing in the suite noticed,
## because every piece worked perfectly on its own.
##
## So this case asserts the JOIN, end to end and through the real hand-off:
##
##   1. a brand new profile is recognised as one;
##   2. `main.gd` sends it to a world where first run can actually play;
##   3. that world, on its real first frame, is RUNNING the tutorial and has NOT
##      started the session underneath it;
##   4. a profile that has already been shown the game gets none of this and goes
##      straight to playing -- the tutorial runs exactly once, for ever;
##   5. Chapter 2 routing is untouched, because a caregiver chapter with no
##      locomotion has nothing to do with any of it.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract section 8).

const MainScript := preload("res://scenes/main/main.gd")
const Plan := preload("res://scripts/onboarding/onboarding_plan.gd")
const ProfileStoreScript := preload("res://scripts/save/profile_store.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const BABY_ROOM_SCENE: String = "res://scenes/baby_room/baby_room.tscn"

## `main.gd::ProgressionMode`, and `main.gd::Route`. The same ordinals every
## world in this project uses.
const MODE_STORY: int = 0
const MODE_FREE_PLAY: int = 1
const ROUTE_BABY_ROOM: int = 0
const ROUTE_HOUSE_WORLD: int = 1


## Settings in, settings out. `set_setting` is never called here -- first run
## records itself through the director, which `test_onboarding.gd` covers.
class FakeSave extends RefCounted:
	var settings: Dictionary = {}

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		if settings.has(key):
			return settings[key]
		return default_value

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value

	func get_stars() -> int:
		return 0


func test_name() -> String:
	return "routing_first_run"


func run():
	var failures: Array = []
	failures.append_array(_test_a_brand_new_profile_has_never_been_shown_the_game())
	failures.append_array(_test_the_menu_sends_a_new_child_somewhere_that_can_teach())
	failures.append_array(_test_a_brand_new_profile_really_reaches_the_tutorial())
	failures.append_array(_test_a_returning_child_is_never_taught_twice())
	failures.append_array(_test_the_tutorial_hands_over_cleanly())
	failures.append_array(_test_chapter_two_routing_is_untouched())
	return failures


## -- The decision, with no tree and no save file --------------------------------

func _test_a_brand_new_profile_has_never_been_shown_the_game():
	var failures: Array = []

	if MainScript.ONBOARDING_SETTING_KEY != Plan.SETTING_KEY:
		failures.append(
			"main.gd reads settings.%s and onboarding_plan.gd writes settings.%s. The two have "
			% [MainScript.ONBOARDING_SETTING_KEY, Plan.SETTING_KEY]
			+ "drifted apart, so first launch would be offered for ever however many times a "
			+ "child completed it."
		)

	# What a genuinely brand new save carries. If a default profile ever DID hold
	# the flag, first run would be skipped by every child who ever installed the
	# game -- which is the exact bug this file exists for, one layer down.
	var defaults: Dictionary = ProfileStoreScript.new("user://test_first_run_unused.json").default_profile()
	var settings: Variant = defaults.get("settings", null)
	if typeof(settings) != TYPE_DICTIONARY:
		failures.append("a default profile has no settings block")
	elif (settings as Dictionary).get(Plan.SETTING_KEY, null) == true:
		failures.append("a brand new profile is already marked as having seen first run")

	var house: String = MainScript.first_run_scene_path()
	if not MainScript.wants_first_run(null, house):
		failures.append(
			"a profile with no settings.%s recorded is not offered first launch. A missing key "
			% Plan.SETTING_KEY + "IS a brand new child; this is the whole decision."
		)
	# Anything that is not an explicit `true` means "has not been shown".
	for value: Variant in [null, false, "", 0, "true", {}]:
		if not MainScript.wants_first_run(value, house):
			failures.append("settings.%s = %s was read as a recorded completion"
					% [Plan.SETTING_KEY, str(value)])
	if MainScript.wants_first_run(true, house):
		failures.append(
			"a profile that has completed first run is offered it again. A tutorial that replays "
			+ "on every launch is the fastest way to make a child stop opening a game."
		)
	# A build with no house has no first run, rather than a first run in a world
	# where nobody walks.
	if MainScript.wants_first_run(null, ""):
		failures.append("first launch was offered with no scene to run it in")

	return failures


func _test_the_menu_sends_a_new_child_somewhere_that_can_teach():
	var failures: Array = []
	var path: String = MainScript.first_run_scene_path()

	if path != MainScript.HOUSE_WORLD_PATH:
		failures.append(
			"first launch opens '%s'. It has to be the house: tap-to-walk, tap-an-object and "
			% path + "drag-a-thing are the lesson, and the Baby Room has none of them -- the "
			+ "baby does not walk and never will (contract section 5)."
		)
	if path == BABY_ROOM_SCENE:
		failures.append("first launch teaches walking in the one world with no navigation")
	if not path.is_empty() and not ResourceLoader.exists(path):
		failures.append("first launch opens '%s', which is not in this build" % path)

	return failures


## -- The join, through the real hand-off ----------------------------------------

## Everything above is arithmetic. This is the assertion that would have caught
## the original bug: build the scene `main.gd` would build, for the profile a
## brand new child really has, and run its real first frame.
func _test_a_brand_new_profile_really_reaches_the_tutorial():
	var failures: Array = []
	var world: Node = _open_first_run()
	if world == null:
		return ["main.gd could not open its own first-launch scene"]

	var onboarding: Node = world.call("ensure_onboarding_director")
	if onboarding == null:
		_release(world)
		return ["the first-launch world builds no onboarding at all"]
	var save: FakeSave = FakeSave.new()
	onboarding.call("set_save_service", save)
	onboarding.call("set_tts", null)

	# The real first frame. `_ready()` does not fire in the `--script` runner and
	# no frame is ever drawn, so the world's own `_process()` is called by hand --
	# which is the code a device runs a few milliseconds after the scene loads.
	world.call("_process", 0.0)

	if not bool(world.call("is_onboarding_active")):
		failures.append(
			"a brand new profile opened the game and first run did not play. This is the whole "
			+ "point: a four-year-old who cannot read is looking at a house with no idea that any "
			+ "of it can be touched."
		)
	if String(onboarding.call("get_step_id")).is_empty():
		failures.append("first run is 'active' but is on no step")

	# And the session waits for it. A Free Play welcome talking over the tutorial
	# is two voices for a child who understands neither.
	var free_play: Node = world.call("get_free_play_director")
	if free_play != null and bool(free_play.call("is_running")):
		failures.append(
			"the Free Play loop started underneath first run, so the welcome line and the first "
			+ "tutorial line are spoken over each other."
		)

	_release(world)
	return failures


func _test_a_returning_child_is_never_taught_twice():
	var failures: Array = []
	var world: Node = _open_first_run()
	if world == null:
		return ["main.gd could not open its own first-launch scene"]

	var onboarding: Node = world.call("ensure_onboarding_director")
	if onboarding == null:
		_release(world)
		return ["the first-launch world builds no onboarding at all"]
	var save: FakeSave = FakeSave.new()
	save.settings[Plan.SETTING_KEY] = true
	onboarding.call("set_save_service", save)

	world.call("_process", 0.0)

	if bool(world.call("is_onboarding_active")):
		failures.append(
			"first run played again for a child who has already completed it. Only an explicit "
			+ "`true` counts as done, and this profile has one."
		)
	var free_play: Node = world.call("get_free_play_director")
	if free_play == null or not bool(free_play.call("is_running")):
		failures.append(
			"skipping the tutorial skipped the game with it: the session never started, so the "
			+ "child gets a walkable house with no HUD and nothing that answers a touch."
		)

	_release(world)
	return failures


## -- The hand-over ---------------------------------------------------------------

## What happens in the second between the tutorial ending and the game starting.
##
## Two pieces of chrome swap over there -- the tutorial's caption and hand go
## away, Free Play's star counter comes back -- and a still frame of that moment
## is the only way to tell whether it really happened. It is also the moment a
## render made this agent doubt, so it is written down rather than looked at.
func _test_the_tutorial_hands_over_cleanly():
	var failures: Array = []
	var world: Node = _open_first_run()
	if world == null:
		return ["main.gd could not open its own first-launch scene"]

	var onboarding: Node = world.call("ensure_onboarding_director")
	if onboarding == null:
		_release(world)
		return ["the first-launch world builds no onboarding at all"]
	var save: FakeSave = FakeSave.new()
	onboarding.call("set_save_service", save)
	world.call("_process", 0.0)

	# The tutorial asks Free Play for something real to drag, which must not
	# start the session under it.
	if String(onboarding.call("get_drag_object_id")).is_empty():
		failures.append(
			"first run has no real object to demonstrate a drag with, so the one gesture it "
			+ "cannot teach by pointing is mimed over an empty floor again."
		)

	var ticks: int = 0
	while not bool(onboarding.call("is_finished")) and ticks < 2000:
		onboarding.call("step", 0.1)
		ticks += 1
	if not bool(onboarding.call("is_finished")):
		failures.append("first run never ended")
		_release(world)
		return failures

	if not String(onboarding.call("get_caption")).is_empty():
		failures.append(
			"the tutorial's caption is still on screen after it ended ('%s'), sitting over the "
			% String(onboarding.call("get_caption")) + "word card Free Play is about to show."
		)
	var hint: Control = onboarding.call("get_hint")
	if hint != null and hint.get_parent() is CanvasItem \
			and (hint.get_parent() as CanvasItem).visible:
		failures.append("the tutorial's overlay is still visible after it ended")

	var free_play: Node = world.call("get_free_play_director")
	if free_play == null or not bool(free_play.call("is_running")):
		failures.append(
			"the tutorial ended and nothing started. A child who has just been told 'now let's "
			+ "play' gets a silent house with no HUD."
		)
		_release(world)
		return failures
	var hud: Control = free_play.call("get_hud")
	if hud != null and not bool(hud.call("is_free_play_mode")):
		failures.append("the HUD came back in Story Mode")
	if save.settings.get(Plan.SETTING_KEY, null) != true:
		failures.append("first run ended without recording itself, so it plays again tomorrow")
	# And the toys it laid out are still there to play with.
	if free_play.call("get_draggables").is_empty():
		failures.append("the pickups the tutorial demonstrated on were cleared away the moment "
				+ "the child was allowed to touch them")

	_release(world)
	return failures


## -- Chapter 2 is not involved --------------------------------------------------

## First launch is about the tutorial, not about chapters. The caregiver chapter
## must route exactly where it always did, because the Baby Room may never
## acquire navigation (`test_architecture_guard.gd` fails the build if it does).
func _test_chapter_two_routing_is_untouched():
	var failures: Array = []

	if MainScript.route_for_chapter("ch2") != ROUTE_BABY_ROOM:
		failures.append("ch2 no longer routes to the Baby Room; Chapter 2 is a caregiver chapter "
				+ "and has no locomotion to play with")
	if MainScript.route_for_chapter("ch1") != ROUTE_BABY_ROOM:
		failures.append("ch1's route changed; first launch was supposed to be decided BEFORE the "
				+ "chapter, not by rewriting what a chapter means")
	if MainScript.route_for_chapter("ch3") != ROUTE_HOUSE_WORLD:
		failures.append("ch3 no longer routes to the house")
	if MainScript.story_scene_path("ch2") != BABY_ROOM_SCENE:
		failures.append("Story Mode's Chapter 2 scene changed to '%s'"
				% MainScript.story_scene_path("ch2"))

	return failures


## -- Helpers --------------------------------------------------------------------

## The scene `main.gd` hands off to on a first launch, configured the way
## `main.gd` configures it, for a brand new profile.
func _open_first_run():
	var path: String = MainScript.first_run_scene_path()
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var profile: Dictionary = ProfileStoreScript.new("user://test_first_run_unused.json").default_profile()
	var world: Node = MainScript.build_scene(path, MODE_FREE_PLAY, [], profile)
	if world == null:
		return null
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
