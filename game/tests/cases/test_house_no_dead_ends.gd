extends RefCounted

## The promise that matters more than any star: **a child can always get out.**
##
## Four-year-olds do not retry, do not read, and do not know that the toy they
## need is in another room. So every one of these has to be true of the running
## house, not just of the design:
##
##   1. **Skip works, always, and pays nothing.** A level skipped end to end
##      still COMPLETES -- so the journey never locks -- and still rates 0, so it
##      is never flattered. `levelCompleted` and `starsByLevel` are different
##      facts and this is where that split earns its keep.
##   2. **A skipped walk does not strand the level.** The next task that needs
##      another room routes itself there through `RoomTransitionController`,
##      without the child having to work out which door.
##   3. **A refused transition leaves a playable child.** Not Disabled, not
##      mid-walk, not busy -- and the task is still there to do.
##   4. **Assist moves a child who touches nothing**, and only ever moves him:
##      it never answers a question and never awards a star on its own.
##
## Every failure here would look like "the game just stopped" on an iPad, which
## is the one bug this project cannot ship.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"

const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")
const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const RewardManagerScript := preload("res://scripts/rewards/reward_manager.gd")
const StarRulesScript := preload("res://scripts/progression/star_rules.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")
const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")

const MISSION_ID: String = "goodMorningRoutine"
const LEVEL_ID: String = "goodMorning"

const STEP: float = 1.0 / 60.0
const WALK_FRAMES: int = 1800
const SETTLE_FRAMES: int = 120
const MAX_TASKS: int = 40


func test_name() -> String:
	return "house_no_dead_ends"


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]

	failures.append_array(_test_skipping_everything_completes_and_pays_nothing(tree))
	failures.append_array(_test_a_skipped_walk_routes_itself(tree))
	failures.append_array(_test_a_refused_transition_leaves_a_playable_child(tree))
	failures.append_array(_test_assist_moves_a_child_who_touches_nothing(tree))
	return failures


## 1. The escape hatch, used for every single task.
func _test_skipping_everything_completes_and_pays_nothing(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open_house(tree)
	if session.has("error"):
		return [String(session["error"])]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]

	var rated: Array = []
	var skipped: Array = []
	director.connect("level_finished",
			func(_level_id: String, stars: int) -> void: rated.append(stars))
	runner.connect("task_skipped", func(task_id: String) -> void: skipped.append(task_id))

	director.call("_start_level", MISSION_ID)
	var guard: int = 0
	while bool(runner.call("is_running")) and guard < MAX_TASKS:
		guard += 1
		var before: String = String(runner.call("get_current_task_id"))
		runner.call("skip_current_task")
		_pump(character, director, 20)
		if bool(runner.call("is_running")) \
				and String(runner.call("get_current_task_id")) == before:
			failures.append("skip did not move past '%s'; the Next button is the one affordance "
					% before + "that must never fail")
			break
		# Only while a task is still running: the summary at the end of the level
		# freezes the child deliberately, and hands control back when it closes
		# (asserted below).
		if bool(runner.call("is_running")) \
				and String(character.call("get_state_name")) == "disabled":
			failures.append("skipping left the child Disabled after '%s'" % before)

	if bool(runner.call("is_running")):
		failures.append("skipping every task did not finish the level")
	if skipped.size() < 7:
		failures.append("only %d tasks were skipped; the level has more than that" % skipped.size())
	if rated != [0]:
		failures.append("a level skipped end to end rated %s; it must rate 0 rather than be "
				% str(rated) + "flattered as a success")

	# Nothing was paid for, by anybody.
	var rewards: Node = director.call("get_reward_manager")
	if int(rewards.call("get_stars")) != 0:
		failures.append("skipping paid %d stars; a skip must cost nothing and earn nothing"
				% int(rewards.call("get_stars")))
	if not (runner.call("get_awarded_task_ids") as Array).is_empty():
		failures.append("a skipped task was recorded as awarded: %s"
				% str(runner.call("get_awarded_task_ids")))

	# ...and yet the level is COMPLETE, so the journey opens up regardless.
	var system: RefCounted = director.call("get_level_system")
	var outcome: Dictionary = system.call("resolve_completion", LEVEL_ID, 0, {}, {})
	if not bool(outcome.get("completed", false)):
		failures.append("a 0-star level must still be recorded as completed, or the skip button "
				+ "becomes a lock")
	if int(outcome.get("stars", -1)) != 0:
		failures.append("a 0-star completion stored %s stars" % str(outcome.get("stars")))
	if not bool(director.call("is_summary_open")):
		failures.append("the level ended with no summary; a 0-star run is celebrated, not hidden")

	# And the child is still a working character afterwards.
	director.call("dismiss_summary")
	if String(character.call("get_state_name")) == "disabled":
		failures.append("the child was left Disabled after a skipped-through level")

	_close_house(tree, session)
	return failures


## 2. Skip the walk, and the level still gets to the bathroom by itself.
func _test_a_skipped_walk_routes_itself(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open_house(tree)
	if session.has("error"):
		return [String(session["error"])]
	var world: Node = session["world"]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]

	var transitions: Array = []
	var completed: Array = []
	world.call("get_transition_controller").connect("transition_completed",
			func(room_id: String, _spawn: String) -> void: transitions.append(room_id))
	runner.connect("task_completed",
			func(task_id: String, _stars: int) -> void: completed.append(task_id))

	director.call("_start_level", MISSION_ID)

	var skipped_walk: bool = false
	var guard: int = 0
	while bool(runner.call("is_running")) and guard < MAX_TASKS:
		guard += 1
		var task_id: String = String(runner.call("get_current_task_id"))
		var plan: Dictionary = director.call("get_current_plan")
		_pump(character, director, 4)

		if TaskPlan.is_travel(plan):
			# The child never taps the door. This is the case that used to strand a
			# level: everything after it happens in a room nobody walked to.
			skipped_walk = true
			runner.call("skip_current_task")
			_pump(character, director, 30)
			continue

		# NO `move_to` anywhere below: if the child ends up in the bathroom, the
		# level loop took them there.
		_pump_until_task_changes(character, director, runner, task_id, WALK_FRAMES)
		if String(runner.call("get_current_task_id")) != task_id:
			continue
		if bool(plan.get("needsChoices", false)):
			runner.call("on_object_chosen", String(plan.get("objectId", "")))
		_pump(character, director, SETTLE_FRAMES)
		if bool(runner.call("is_running")) \
				and String(runner.call("get_current_task_id")) == task_id:
			failures.append("task '%s' could not be finished after the walk was skipped" % task_id)
			runner.call("skip_current_task")
			_pump(character, director, 30)

	if not skipped_walk:
		failures.append("this level has no travel task; the case is vacuous")
	if not transitions.has("bathroom"):
		failures.append("the child never reached the bathroom after skipping the walk. The level "
				+ "loop must route itself through the doors rather than asking a four-year-old "
				+ "to work out that the sink is in another room. Transitions: %s" % str(transitions))
	if String(world.call("get_current_room_id")) != "bathroom":
		failures.append("the level ended in the %s rather than the bathroom"
				% world.call("get_current_room_id"))
	if not completed.has("brushTeethMorning"):
		failures.append("the task in the other room never completed; completed: %s" % str(completed))
	if bool(runner.call("is_running")):
		failures.append("the level never finished after a skipped walk")

	_close_house(tree, session)
	return failures


## 3. A refusal is not a state a child can be left in.
func _test_a_refused_transition_leaves_a_playable_child(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open_house(tree)
	if session.has("error"):
		return [String(session["error"])]
	var world: Node = session["world"]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]
	var transition: Node = world.call("get_transition_controller")

	director.call("_start_level", MISSION_ID)
	_pump(character, director, 10)

	var refusals: Array = []
	transition.connect("transition_refused",
			func(_room_id: String, reason: String) -> void: refusals.append(reason))

	var room_before: String = String(world.call("get_current_room_id"))
	if bool(transition.call("request_transition", "garage", "default")):
		failures.append("the house accepted a transition to a room it does not have")
	if refusals != ["unknownRoom"]:
		failures.append("expected one 'unknownRoom' refusal, got %s" % str(refusals))
	if String(world.call("get_current_room_id")) != room_before:
		failures.append("a refused transition moved the child anyway")

	_pump(character, director, 10)
	if String(character.call("get_state_name")) == "disabled":
		failures.append("a refused transition left the child Disabled -- every request would be "
				+ "silently ignored from here on, which is a frozen game")
	if bool(character.call("is_busy")):
		failures.append("a refused transition left the child busy")
	if not bool(runner.call("is_running")):
		failures.append("a refused transition ended the level")
	if not bool(character.call("move_to", "bedroom.bed")):
		failures.append("the child cannot be walked after a refused transition")
	character.call("stop")

	_close_house(tree, session)
	return failures


## 4. Assist: the way out for a child who touches nothing at all.
func _test_assist_moves_a_child_who_touches_nothing(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open_house(tree)
	if session.has("error"):
		return [String(session["error"])]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]

	director.call("_start_level", MISSION_ID)
	# Walk past the opening tap-a-pillow beat to the first task that needs feet.
	var guard: int = 0
	while bool(runner.call("is_running")) and guard < MAX_TASKS:
		guard += 1
		if bool((director.call("get_current_plan") as Dictionary).get("needsWalk", false)):
			break
		runner.call("skip_current_task")
		_pump(character, director, 20)

	var plan: Dictionary = director.call("get_current_plan")
	if not bool(plan.get("needsWalk", false)):
		_close_house(tree, session)
		return ["no task in this level asks the child to walk; the case is vacuous"]

	var task_id: String = String(runner.call("get_current_task_id"))
	var stars_before: int = int(director.call("get_reward_manager").call("get_stars"))

	# Assist BEFORE anything is touched. It must move the child, and only move him.
	director.call("assist_now")
	_pump_until_task_changes(character, director, runner, task_id, WALK_FRAMES)

	var moved_on: bool = String(runner.call("get_current_task_id")) != task_id
	if not (moved_on or bool(director.call("is_beat_reached"))):
		failures.append("assist did not get the child to '%s'; a child who touches nothing has no "
				% String(plan.get("walkTargetId", "")) + "way forward")
	if String(character.call("get_state_name")) == "disabled":
		failures.append("assist left the child Disabled")

	if bool(plan.get("needsChoices", false)):
		# Assist walks. It must never answer the question for the child.
		if int(director.call("get_reward_manager").call("get_stars")) != stars_before:
			failures.append("assist awarded a star for a task the child never touched")

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

	var provider: RefCounted = NavMapProviderScript.create(world.call("get_navigation_map"))
	if not bool(provider.call("force_sync", Vector3.ZERO)):
		tree.root.remove_child(world)
		world.free()
		return {"error": "the house navigation map never answered"}

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
	}


func _close_house(tree: SceneTree, session: Dictionary) -> void:
	var world: Node = session.get("world", null)
	if world == null:
		return
	tree.root.remove_child(world)
	world.free()


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
