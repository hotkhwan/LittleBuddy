extends RefCounted

## "A Day With Little Buddy", played end to end by a child who never speaks.
##
## All five Chapter 3 levels are run inside the REAL house -- the real scene, the
## real navigation meshes, the real transition controller, the real mission
## runner, the real `RewardManager`/`RewardLedger` and the real `LevelSystem` --
## by a simulated child who does exactly two things: taps the thing the prompt is
## about, and taps the object it asks for.
##
## What that proves, and why each half matters:
##
##   * **Touch alone reaches 3/3 at RUNTIME.** `test_chapter3_slice` already
##     proves it of the content; this proves the engine honours it. A star rule is
##     easy to keep honest in JSON and easy to lose in a runtime that gates a task
##     behind something else.
##   * **Every star is paid exactly once**, through the one ledger. Re-awarding a
##     task after the level adds nothing.
##   * **The day happens in order.** Shuffled, `goodMorning` rinses a cup in the
##     bedroom before the child has walked to the bathroom.
##   * **Room transitions are part of the level**, not a separate mode: the level
##     starts in its authored first room and ends in its authored last one, having
##     gone through real doors on the way.
##   * **The objects are asleep until Little Buddy gets there**, so "bring the
##     toothbrush to the sink" cannot be answered from the bedroom.
##   * **Nothing is left stuck**: no Disabled character, no Walking with nowhere
##     to go, and the summary hands control back when it closes.
##
## A tap on a spawned object is simulated as `on_object_chosen()` -- the same
## funnel `SpawnedObject.chosen` fires into -- because `DraggableObject`'s tap
## path builds a `Tween`, which needs a live tree the headless runner does not
## have. The enable gate that a real tap would hit is asserted separately, in
## `_deliver_gate`.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"

const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const LevelSystemScript := preload("res://scripts/progression/level_system.gd")
const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")
const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const RewardManagerScript := preload("res://scripts/rewards/reward_manager.gd")
const StarRulesScript := preload("res://scripts/progression/star_rules.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")
## `class_name` is unavailable in the headless runner; the static level-order rule
## is reached through the preloaded script instead.
const HouseLevelDirector := preload("res://scripts/gameplay/house_level_director.gd")

const STEP: float = 1.0 / 60.0
const WALK_FRAMES: int = 1800
const SETTLE_FRAMES: int = 240
const MAX_TASKS: int = 40

## `[levelId, missionId, firstRoom, lastRoom]` -- the slice, as
## `docs/SLICE_CONTRACT.md` §1 locks it.
const LEVELS: Array = [
	["goodMorning", "goodMorningRoutine", "bedroom", "bathroom"],
	["gettingDressed", "morningRoutine", "bathroom", "bedroom"],
	["breakfast", "breakfastTime", "bedroom", "kitchen"],
	["playTime", "toddlerPlayTime", "kitchen", "livingRoom"],
	["tidyAndBed", "tidyAndBedtime", "livingRoom", "bedroom"],
]


func test_name() -> String:
	return "slice_level_loop"


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]

	failures.append_array(_test_the_journey_starts_at_the_beginning())
	for row: Array in LEVELS:
		failures.append_array(_test_level(tree, row))
	failures.append_array(_test_the_summary_hands_control_back(tree))
	return failures


## Which level Chapter 3 opens on, as a pure rule.
##
## This is a bug that shipped and was found by LOOKING at the game: a saved
## resume pointer left on `sayItChallenge` -- a bonus level tagged `ch3` -- opened
## the chapter on eight vocabulary cards instead of on waking up, and Next handed
## the same level back forever because a bonus level has no successor. The day
## could never start, and every test was green.
func _test_the_journey_starts_at_the_beginning():
	var failures: Array = []
	var chain: Array = ["goodMorning", "gettingDressed", "breakfast", "playTime", "tidyAndBed"]
	var bonus: Array = ["sayItChallenge"]
	var all_open: Array = chain + bonus

	# A fresh profile opens on the first beat of the day.
	var fresh: Array = HouseLevelDirector.resume_order(chain, bonus, ["goodMorning"], {}, "")
	if fresh.is_empty() or String(fresh[0]) != "goodMorning":
		failures.append("a new player should start at 'goodMorning', got %s" % str(fresh))

	# A pointer parked on the bonus level must NOT hijack the day.
	var hijack: Array = HouseLevelDirector.resume_order(
		chain, bonus, all_open, {"goodMorning": true}, "sayItChallenge")
	if hijack.is_empty() or String(hijack[0]) != "gettingDressed":
		failures.append("a resume pointer on the bonus level must not open Chapter 3 on it; "
				+ "expected 'gettingDressed' next, got %s" % str(hijack))
	if not hijack.has("sayItChallenge"):
		failures.append("the bonus level must still be reachable, just not first")

	# A pointer on a real chain level IS honoured -- that is what resuming means.
	var resumed: Array = HouseLevelDirector.resume_order(
		chain, bonus, all_open, {"goodMorning": true}, "breakfast")
	if resumed.is_empty() or String(resumed[0]) != "breakfast":
		failures.append("a saved chain level must be resumed, got %s" % str(resumed))

	# Once the whole day is done, the bonus level may lead -- it is the only thing
	# left to play.
	var finished: Dictionary = {}
	for level_id: Variant in chain:
		finished[String(level_id)] = true
	var after: Array = HouseLevelDirector.resume_order(
		chain, bonus, all_open, finished, "sayItChallenge")
	if after.is_empty() or String(after[0]) != "sayItChallenge":
		failures.append("with the day finished, the unplayed bonus level may lead, got %s"
				% str(after))

	# ...but once THAT is finished too, the pointer must not hand the same level
	# back for ever. A finished journey starts a new day at the beginning.
	var everything: Dictionary = finished.duplicate()
	everything["sayItChallenge"] = true
	var again: Array = HouseLevelDirector.resume_order(
		chain, bonus, all_open, everything, "sayItChallenge")
	if again.is_empty() or String(again[0]) != "goodMorning":
		failures.append("a finished journey must begin a new day rather than repeat the level it "
				+ "ended on, got %s" % str(again))

	# Every level stays reachable however odd the inputs are: a corrupt unlock
	# list must open the chapter rather than empty the house.
	var corrupt: Array = HouseLevelDirector.resume_order(chain, bonus, [], {}, "somethingElse")
	if corrupt.size() != all_open.size():
		failures.append("a corrupt unlock list must still offer every level, got %s" % str(corrupt))
	if String(corrupt[0]) != "goodMorning":
		failures.append("a corrupt unlock list must still start at the beginning of the day")

	# v2-era completion maps stored a star COUNT rather than `true`.
	var legacy: Array = HouseLevelDirector.resume_order(chain, bonus, all_open, {"goodMorning": 2}, "")
	if legacy.is_empty() or String(legacy[0]) != "gettingDressed":
		failures.append("a legacy completion value (a star count) must read as completed, got %s"
				% str(legacy))
	return failures


# ---------------------------------------------------------------------------
# One level, played by touch alone
# ---------------------------------------------------------------------------

func _test_level(tree: SceneTree, row: Array):
	var failures: Array = []
	var level_id: String = String(row[0])
	var mission_id: String = String(row[1])
	var first_room: String = String(row[2])
	var last_room: String = String(row[3])

	var session: Dictionary = _open_house(tree)
	if session.has("error"):
		return [String(session["error"])]
	var world: Node = session["world"]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]

	var started_ids: Array = []
	var completed_ids: Array = []
	var skipped_ids: Array = []
	var transitions: Array = []
	var rated: Array = []
	director.connect("task_plan_changed",
			func(task_id: String, _kind: String) -> void: started_ids.append(task_id))
	runner.connect("task_completed",
			func(task_id: String, _stars: int) -> void: completed_ids.append(task_id))
	runner.connect("task_skipped", func(task_id: String) -> void: skipped_ids.append(task_id))
	director.connect("level_finished",
			func(_level: String, stars: int) -> void: rated.append(stars))
	world.call("get_transition_controller").connect("transition_completed",
			func(room_id: String, _spawn: String) -> void: transitions.append(room_id))

	if not bool(director.call("_start_level", mission_id)):
		_close_house(tree, session)
		return ["%s: the level would not start" % level_id]

	if String(world.call("get_current_room_id")) != first_room:
		failures.append("%s starts in the %s; the authored roomPath begins in the %s"
				% [level_id, world.call("get_current_room_id"), first_room])

	var play: Dictionary = _play_by_touch(director, runner, character)
	failures.append_array(play["failures"])
	# The gate can only be exercised by a level that asks the child to walk
	# somewhere AND then choose something there. `gettingDressed` does all its
	# choosing on the spot, so demanding the check everywhere would be a false
	# failure -- but a level that HAS such a task and never checked would mean the
	# assertion silently stopped running.
	if _has_deliver_task(session["library"], mission_id) and not bool(play["gateChecked"]):
		failures.append("%s has a walk-then-touch task but the gate was never checked; that "
				% level_id + "assertion has gone vacuous")

	# -- The day happened in order --------------------------------------------
	var authored: Array = _authored_task_ids(session["library"], mission_id)
	if started_ids != authored:
		failures.append("%s played its beats in the wrong order.\n      authored: %s\n      played:   %s"
				% [level_id, str(authored), str(started_ids)])

	# -- Everything completed, nothing skipped --------------------------------
	if not skipped_ids.is_empty():
		failures.append("%s had to skip %s; a touch-only child should finish every task"
				% [level_id, str(skipped_ids)])
	if completed_ids.size() != authored.size():
		failures.append("%s completed %d of %d tasks by touch"
				% [level_id, completed_ids.size(), authored.size()])

	# -- Touch alone rated 3/3 ------------------------------------------------
	if rated != [3]:
		failures.append("%s rated %s for a touch-only player; speech must never be needed for a "
				% [level_id, str(rated)] + "star")

	# -- The stars were paid, once each ---------------------------------------
	var rewards: Node = director.call("get_reward_manager")
	var expected_stars: int = int(MissionRunnerScript.expected_stars(runner.call("get_tasks")))
	var paid: int = int(rewards.call("get_stars"))
	if paid != expected_stars:
		failures.append("%s paid %d stars for a flawless run, expected %d"
				% [level_id, paid, expected_stars])
	var awarded: Array = runner.call("get_awarded_task_ids")
	if awarded.size() != completed_ids.size():
		failures.append("%s awarded %d task ids for %d completions"
				% [level_id, awarded.size(), completed_ids.size()])
	# The no-double-award guarantee, exercised rather than assumed: replay every
	# completion through the very same writer and the total must not move.
	for task_id: Variant in awarded:
		rewards.call("award", String(task_id), 1)
	if int(rewards.call("get_stars")) != paid:
		failures.append("%s: re-awarding its completed tasks paid again (%d -> %d). The ledger is "
				% [level_id, paid, int(rewards.call("get_stars"))] + "the only thing standing "
				+ "between a re-fired signal and a double star.")

	# -- Completion and rooms -------------------------------------------------
	var system: RefCounted = director.call("get_level_system")
	var applied: Dictionary = system.call("resolve_completion", level_id, 3, {}, {})
	if not bool(applied.get("completed", false)):
		failures.append("%s did not record completion" % level_id)
	if String(world.call("get_current_room_id")) != last_room:
		failures.append("%s ends in the %s; the authored roomPath ends in the %s"
				% [level_id, world.call("get_current_room_id"), last_room])
	if first_room != last_room and transitions.is_empty():
		failures.append("%s crosses rooms but no transition ever ran; the room change did not go "
				% level_id + "through RoomTransitionController")
	if level_id == "tidyAndBed" and transitions != ["kitchen", "bedroom"]:
		failures.append("the walk home must pass through the kitchen (the living room has no door "
				+ "to the bedroom), got %s" % str(transitions))

	# -- And the child is still somewhere real, in one piece ------------------
	var position: Vector3 = SpatialUtil.world_position(character as Node3D)
	var bounds: Rect2 = HouseLayout.world_floor_bounds(last_room)
	if not bounds.has_point(Vector2(position.x, position.z)):
		failures.append("%s left the child at %s, outside the %s"
				% [level_id, str(position), last_room])

	_close_house(tree, session)
	return failures


## The simulated child: tap the thing, walk there, tap the object it asks for.
func _play_by_touch(director: Node, runner: Node, character: Node):
	var failures: Array = []
	var gate_checked: bool = false
	var marker_checked: bool = false
	var guard: int = 0

	while bool(runner.call("is_running")) and guard < MAX_TASKS:
		guard += 1
		var task_id: String = String(runner.call("get_current_task_id"))
		var plan: Dictionary = director.call("get_current_plan")
		_pump(character, director, 4)

		if bool(plan.get("needsWalk", false)):
			# A child who cannot read needs the place marked on the floor, and the
			# mark must go away once they are standing on it.
			var stage: Node = director.call("get_stage")
			var same_room: bool = String(plan.get("roomId", "")) \
					== String((director.call("get_current_plan") as Dictionary).get("roomId", ""))
			if same_room and not bool(director.call("is_beat_reached")) \
					and not bool(stage.call("is_beat_marker_visible")):
				failures.append("task '%s' asks the child to walk somewhere but marks nowhere; "
						% task_id + "the prompt is words a four-year-old cannot read")
			marker_checked = true
			# The gate: a task that has to be walked to must not be answerable
			# from where the child is standing now.
			if bool(plan.get("needsChoices", false)) and not bool(director.call("is_beat_reached")):
				gate_checked = true
				if _any_object_enabled(runner):
					failures.append("task '%s' had live objects before Little Buddy got to the %s"
							% [task_id, plan.get("walkTargetId", "")])
			if not bool(character.call("move_to", String(plan.get("walkTargetId", "")))):
				# Another room: the loop routes itself there. Give it the frames.
				director.call("assist_now")
			_pump_until_task_changes(character, director, runner, task_id, WALK_FRAMES)

		if String(runner.call("get_current_task_id")) != task_id:
			continue  # travel / goAndDo finished by arriving.

		if bool(plan.get("needsChoices", false)):
			_pump(character, director, 4)
			if not bool(director.call("is_beat_reached")):
				failures.append("task '%s' never reached its beat; the child would be asked to "
						% task_id + "touch something that is not awake")
			elif not _all_objects_enabled(runner):
				failures.append("task '%s' reached its beat but its objects are still asleep"
						% task_id)
			runner.call("on_object_chosen", String(plan.get("objectId", "")))

		_pump(character, director, SETTLE_FRAMES)
		if bool(runner.call("is_running")) \
				and String(runner.call("get_current_task_id")) == task_id:
			failures.append("task '%s' (%s) could not be finished by touch; the level would "
					% [task_id, plan.get("kind", "")] + "dead-end here")
			runner.call("skip_current_task")
			_pump(character, director, 30)

		if String(character.call("get_state_name")) == "disabled" \
				and bool(runner.call("is_running")):
			failures.append("the child was left Disabled during task '%s'" % task_id)

	if guard >= MAX_TASKS:
		failures.append("the level never finished; the loop ran %d times" % guard)
	if marker_checked and bool(director.call("get_stage").call("is_beat_marker_visible")):
		failures.append("the level ended with the 'go here' disc still on the floor")
	return {"failures": failures, "gateChecked": gate_checked}


# ---------------------------------------------------------------------------
# The summary hands control back
# ---------------------------------------------------------------------------

## A level ends on a summary, and the summary is the one place the child is
## deliberately frozen. Closing it MUST give them back a house they can tap.
func _test_the_summary_hands_control_back(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open_house(tree)
	if session.has("error"):
		return [String(session["error"])]
	var world: Node = session["world"]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]
	var navigation: Node = world.get_node_or_null("NavigationController")

	director.call("_start_level", "goodMorningRoutine")
	_play_by_touch(director, runner, character)

	if not bool(director.call("is_summary_open")):
		failures.append("the level ended without a summary; there is nowhere for the child to go")
	if String(character.call("get_state_name")) != "disabled":
		failures.append("the child is still drivable behind the summary overlay")
	if navigation != null and bool(navigation.get("taps_enabled")):
		failures.append("taps still reach the room behind the summary overlay")

	director.call("dismiss_summary")
	if bool(director.call("is_summary_open")):
		failures.append("the summary would not close")
	if String(character.call("get_state_name")) == "disabled":
		failures.append("closing the summary left the child Disabled -- a dead end with a friendly "
				+ "face")
	if navigation != null and not bool(navigation.get("taps_enabled")):
		failures.append("closing the summary left the room untappable")
	if not bool(runner.call("is_running")):
		failures.append("closing the summary left no level running; the journey must always "
				+ "continue rather than end on an empty screen")
	var here: Vector3 = HouseLayout.room_origin(String(world.call("get_current_room_id")))
	if not bool(character.call("move_to_ground", here.x, here.z)):
		failures.append("the child cannot be walked after the summary closed")

	_close_house(tree, session)
	return failures


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

func _open_house(tree: SceneTree):
	var packed: Resource = load(SCENE_PATH)
	if not (packed is PackedScene):
		return {"error": "could not load %s" % SCENE_PATH}
	var world: Node = (packed as PackedScene).instantiate()
	tree.root.add_child(world)
	world.call("_ready")

	# Prove the navigation map answers before anything walks anywhere. Without
	# this the whole level could pass on straight-line paths through walls.
	var provider: RefCounted = NavMapProviderScript.create(world.call("get_navigation_map"))
	if not bool(provider.call("force_sync", Vector3.ZERO)):
		tree.root.remove_child(world)
		world.free()
		return {"error": "the house navigation map never answered"}

	# A fresh ledger per level, with the spam-tap window switched off: the guard
	# exists to swallow a double-fired FINGER, and a headless run completes eight
	# tasks inside one millisecond. The duplicate guard -- the one this case
	# actually cares about -- is untouched.
	var ledger: RefCounted = RewardLedgerScript.create()
	ledger.set("min_interval_ms", 0)
	RewardManagerScript.set_shared_ledger(ledger)

	var director: Node = world.call("ensure_level_director")
	if director == null:
		tree.root.remove_child(world)
		world.free()
		return {"error": "the house built no level director"}
	return {
		"world": world,
		"director": director,
		"runner": director.call("get_runner"),
		"character": world.call("get_character"),
		"library": director.call("get_library"),
	}


func _close_house(tree: SceneTree, session: Dictionary) -> void:
	var world: Node = session.get("world", null)
	if world == null:
		return
	tree.root.remove_child(world)
	world.free()


## True when the level contains a task that has to be walked to AND then touched
## -- the only shape that can exercise the "objects stay asleep until you get
## there" gate.
func _has_deliver_task(library: Object, mission_id: String) -> bool:
	if library == null or not library.has_method("get_mission_tasks"):
		return false
	for task: Variant in library.call("get_mission_tasks", mission_id):
		var plan: Dictionary = TaskPlan.describe(task, "")
		if bool(plan.get("needsWalk", false)) and bool(plan.get("needsChoices", false)):
			return true
	return false


func _authored_task_ids(library: Object, mission_id: String) -> Array:
	var ids: Array = []
	if library == null or not library.has_method("get_mission_tasks"):
		return ids
	for task: Variant in library.call("get_mission_tasks", mission_id):
		if not String(MissionRunnerScript.describe_unplayable(task, library)).is_empty():
			continue
		ids.append(String((task as Dictionary).get("taskId", "")))
	return ids


func _pump(character: Node, director: Node, frames: int) -> void:
	for _frame: int in range(frames):
		character.call("step_movement", STEP)
		director.call("step", STEP)


func _pump_until_task_changes(
	character: Node, director: Node, runner: Node, task_id: String, frames: int
) -> void:
	for _frame: int in range(frames):
		character.call("step_movement", STEP)
		director.call("step", STEP)
		if String(runner.call("get_current_task_id")) != task_id:
			return
		if bool(director.call("is_beat_reached")) \
				and String(character.call("get_state_name")) == "idle":
			return


func _spawned_objects(runner: Node) -> Array:
	var handler: Node = runner.call("get_handler")
	if handler == null or not is_instance_valid(handler):
		return []
	if not handler.has_method("get_spawned_objects"):
		return []
	return handler.call("get_spawned_objects")


func _any_object_enabled(runner: Node) -> bool:
	for node: Variant in _spawned_objects(runner):
		if node is Node and is_instance_valid(node) and bool((node as Node).get("drag_enabled")):
			return true
	return false


func _all_objects_enabled(runner: Node) -> bool:
	var objects: Array = _spawned_objects(runner)
	if objects.is_empty():
		return false
	for node: Variant in objects:
		if not (node is Node) or not is_instance_valid(node):
			return false
		if not bool((node as Node).get("drag_enabled")):
			return false
	return true
