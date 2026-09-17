extends RefCounted

## Child-proofing: the house, played badly on purpose.
##
## `test_slice_level_loop.gd` proves the day works when it is played the way an
## adult would play it. This case proves it survives the way a four-year-old
## actually plays it -- hammering, two hands at once, dragging while walking,
## pressing Skip halfway to the bathroom, wandering into another room mid-task,
## and mashing Next on the summary.
##
## **The invariant, everywhere: no dead ends.** After every abuse below the child
## must be left in a state they can act on -- never stuck Walking with nowhere to
## go, never stuck Interacting, never Disabled with no overlay in front of them,
## and never holding a task whose objects are asleep for good.
##
## Stars are checked at the same time, because the cheapest way to "fix" a double
## tap is to let it pay twice.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"

const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const RewardManagerScript := preload("res://scripts/rewards/reward_manager.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")
const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")

const STEP: float = 1.0 / 60.0
const WALK_FRAMES: int = 1800
const SETTLE_FRAMES: int = 240
const MAX_TASKS: int = 40

## The level used for the stress runs: it walks, it travels through a door and it
## has an object to choose, so one mission exercises all four task kinds.
const MISSION_ID: String = "goodMorningRoutine"

## How hard a small child hammers.
const MASH: int = 25

## States a child must never be left in with nothing in front of them.
const STUCK_STATES: Array[String] = ["disabled"]


func test_name() -> String:
	return "childproof_house"


## The `SaveService` autoload, lifted out of the tree for the duration of this
## case and put back afterwards.
##
## `run_tests.gd` says "cases must not depend on autoloads -- `--script` does not
## load them". That is NOT true of Godot 4.7: `/root/SaveService`,
## `/root/SpeechService`, `/root/TtsService` and `/root/Sfx` are all live during a
## headless run. A case that finishes a level therefore reaches the REAL
## `SaveService`, whose in-memory profile starts empty because `_ready()` never
## fired -- so `LevelSystem.apply_completion()` persists an empty-but-for-this-run
## profile straight over `user://profile.json`.
##
## Two consequences, both reported alongside this change:
##   * the suite rewrites the developer's (and on a device, the CHILD'S) save;
##   * `test_level_progression._test_degrades_without_a_save_service` asserts
##     "no SaveService in the tree" against a tree that has one, and only passes
##     because no earlier-alphabetical case had yet completed a level.
##
## This case completes several levels and sorts before `test_level_progression`,
## so it detaches the autoload rather than quietly poisoning the run. Detaching
## (rather than pointing it at a temp file) is what leaves its in-memory state
## exactly as it was found.
var _detached_save: Node = null


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]

	_detach_save_service(tree)

	failures.append_array(_test_mashing_the_right_answer(tree))
	failures.append_array(_test_two_fingers_at_once(tree))
	failures.append_array(_test_touching_objects_while_walking(tree))
	failures.append_array(_test_skip_halfway_there(tree))
	failures.append_array(_test_wandering_off_mid_task(tree))
	failures.append_array(_test_mashing_the_summary(tree))
	failures.append_array(_test_cancelling_and_coming_back(tree))

	failures.append_array(_reattach_save_service(tree))
	return failures


func _detach_save_service(tree: SceneTree) -> void:
	var save: Node = tree.root.get_node_or_null(NodePath("SaveService"))
	if save == null:
		return
	_detached_save = save
	tree.root.remove_child(save)


func _reattach_save_service(tree: SceneTree):
	var failures: Array = []
	if _detached_save == null:
		return failures
	if not is_instance_valid(_detached_save):
		return ["the SaveService autoload was freed while it was detached"]
	tree.root.add_child(_detached_save)
	_detached_save = null
	if tree.root.get_node_or_null(NodePath("SaveService")) == null:
		failures.append("the SaveService autoload was not put back; every later case would run "
				+ "against a tree this one changed")
	return failures


## -- 1. Rapid tapping ------------------------------------------------------------

## Twenty-five taps on the right object. Exactly one star, exactly one
## completion, and the level carries on.
func _test_mashing_the_right_answer(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open(tree)
	if session.has("error"):
		return [String(session["error"])]

	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var rewards: Node = director.call("get_reward_manager")

	var completions: Array = []
	runner.connect("task_completed",
			func(task_id: String, _stars: int) -> void: completions.append(task_id))

	var reached: Dictionary = _reach_a_choice_task(session)
	if not bool(reached.get("found", false)):
		_close(tree, session)
		return ["%s never presented a task with something to touch" % MISSION_ID]

	var task_id: String = String(reached["taskId"])
	var object_id: String = String(reached["objectId"])
	var before: int = int(rewards.call("get_stars"))

	# Every completion id the ledger actually paid for, and every one it refused.
	var granted: Array = []
	var refused: Array = []
	rewards.connect("award_granted",
			func(cid: String, _g: int, _p: int, _t: int) -> void: granted.append(cid))
	rewards.connect("award_refused",
			func(cid: String, reason: String) -> void: refused.append("%s:%s" % [cid, reason]))

	for _i: int in range(MASH):
		runner.call("on_object_chosen", object_id)
	_pump(session, 8)

	# The headless runner has no frames, so `MissionRunner._delay()` resolves
	# immediately and the mission walks forward under the mash instead of pausing
	# for TASK_GAP_SEC. That makes this a HARSHER test than a device -- the later
	# taps land on live successor tasks rather than on a dead handler -- so the
	# thing to assert is not a star total but that no completion is ever paid
	# twice, which is the guarantee a device needs too.
	var seen: Dictionary = {}
	for entry: Variant in granted:
		var key: String = String(entry)
		if seen.has(key):
			failures.append("completion '%s' was paid more than once under %d taps" % [key, MASH])
		seen[key] = true
	if granted.is_empty():
		failures.append("%d taps on the right object paid nothing at all" % MASH)
	var paid: int = int(rewards.call("get_stars")) - before
	if paid != granted.size():
		failures.append("the star total moved by %d for %d granted awards" % [paid, granted.size()])

	var hits: int = 0
	for entry: Variant in completions:
		if String(entry) == task_id:
			hits += 1
	if hits != 1:
		failures.append("task '%s' completed %d times under mashing" % [task_id, hits])

	# The task the child was actually on is never re-payable, however it is asked.
	var already: int = int(rewards.call("get_stars"))
	for _i: int in range(MASH):
		rewards.call("award", task_id, 1)
	if int(rewards.call("get_stars")) != already:
		failures.append("re-awarding '%s' after the fact paid again; the ledger is the only thing "
				% task_id + "between a re-fired signal and a double star")

	failures.append_array(_check_not_stuck(session, "after mashing the right answer"))
	# ...and the level is still going somewhere.
	_pump(session, SETTLE_FRAMES)
	if bool(runner.call("is_running")) and String(runner.call("get_current_task_id")) == task_id:
		failures.append("mashing '%s' left the level on the same task; it did not move on"
				% object_id)

	_close(tree, session)
	return failures


## -- 2. Two or more fingers -------------------------------------------------------

## The right object and a wrong one delivered in the same frame, in both orders.
## One star, and a wrong answer landing after a right one must not undo it or
## turn the success into a gentle retry.
func _test_two_fingers_at_once(tree: SceneTree):
	var failures: Array = []
	for order: Array in [["target", "distractor"], ["distractor", "target"]]:
		var session: Dictionary = _open(tree)
		if session.has("error"):
			return [String(session["error"])]
		var director: Node = session["director"]
		var runner: Node = session["runner"]
		var rewards: Node = director.call("get_reward_manager")

		var skipped: Array = []
		runner.connect("task_skipped", func(task_id: String) -> void: skipped.append(task_id))

		var reached: Dictionary = _reach_a_choice_task(session)
		if not bool(reached.get("found", false)):
			_close(tree, session)
			return ["%s never presented a task with something to touch" % MISSION_ID]

		var target_id: String = String(reached["objectId"])
		var other_id: String = _other_object_id(runner, target_id)
		if other_id.is_empty():
			# A one-object row cannot express this case; not a failure, but say so
			# rather than passing silently.
			_close(tree, session)
			continue

		var granted: Array = []
		rewards.connect("award_granted",
				func(cid: String, _g: int, _p: int, _t: int) -> void: granted.append(cid))
		for hand: Variant in order:
			runner.call("on_object_chosen", target_id if String(hand) == "target" else other_id)
		_pump(session, 8)

		if granted.size() != 1 or String(granted[0]).ends_with(reached["taskId"]) == false:
			failures.append("two fingers (%s) produced %s; exactly one award for '%s' was expected"
					% [str(order), str(granted), reached["taskId"]])
		if not skipped.is_empty():
			failures.append("two fingers (%s) made the runner give up on %s; a second hand must "
					% [str(order), str(skipped)] + "never be read as failing")
		failures.append_array(_check_not_stuck(session, "after a two-finger touch %s" % str(order)))
		_close(tree, session)
	return failures


## -- 3. Touching / dragging while walking ------------------------------------------

## The objects of a walk-then-choose task must be asleep until Little Buddy gets
## there -- that is the only thing stopping "bring the toothbrush to the sink"
## from being answered from the bedroom. Asserted here DURING the walk, and the
## child must not be stuck when the walk finishes.
func _test_touching_objects_while_walking(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open(tree)
	if session.has("error"):
		return [String(session["error"])]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]

	if not bool(director.call("_start_level", MISSION_ID)):
		_close(tree, session)
		return ["%s would not start" % MISSION_ID]

	var checked: bool = false
	var guard: int = 0
	while bool(runner.call("is_running")) and guard < MAX_TASKS:
		guard += 1
		var task_id: String = String(runner.call("get_current_task_id"))
		var plan: Dictionary = director.call("get_current_plan")
		_pump(session, 4)

		if bool(plan.get("needsWalk", false)) and bool(plan.get("needsChoices", false)) \
				and not bool(director.call("is_beat_reached")):
			checked = true
			if _any_object_enabled(runner):
				failures.append("task '%s' could be answered before Little Buddy walked to the %s"
						% [task_id, plan.get("walkTargetId", "")])
			# A child WILL grab at them anyway. Doing so must change nothing.
			for _i: int in range(MASH):
				runner.call("on_object_chosen", String(plan.get("objectId", "")))
			_pump(session, 4)

		if bool(plan.get("needsWalk", false)):
			if not bool(character.call("move_to", String(plan.get("walkTargetId", "")))):
				director.call("assist_now")
			_pump_until_task_changes(session, task_id, WALK_FRAMES)
		if String(runner.call("get_current_task_id")) != task_id:
			continue
		if bool(plan.get("needsChoices", false)):
			_pump(session, 4)
			runner.call("on_object_chosen", String(plan.get("objectId", "")))
		_pump(session, SETTLE_FRAMES)
		if bool(runner.call("is_running")) \
				and String(runner.call("get_current_task_id")) == task_id:
			failures.append("task '%s' could not be finished after being grabbed at mid-walk"
					% task_id)
			runner.call("skip_current_task")
			_pump(session, 30)
		failures.append_array(_check_not_stuck(session, "during task '%s'" % task_id))

	if not checked:
		failures.append("no walk-then-choose task was ever observed mid-walk; this assertion has "
				+ "gone vacuous")
	if guard >= MAX_TASKS:
		failures.append("the level never finished under mid-walk grabbing")
	_close(tree, session)
	return failures


## -- 4. Pressing Skip halfway there -------------------------------------------------

## Skip while Little Buddy is mid-walk. He must not keep sliding across the room
## on his own into the next task, and he must not be left Disabled.
func _test_skip_halfway_there(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open(tree)
	if session.has("error"):
		return [String(session["error"])]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]

	if not bool(director.call("_start_level", MISSION_ID)):
		_close(tree, session)
		return ["%s would not start" % MISSION_ID]

	var skipped: bool = false
	var guard: int = 0
	while bool(runner.call("is_running")) and guard < MAX_TASKS:
		guard += 1
		var task_id: String = String(runner.call("get_current_task_id"))
		var plan: Dictionary = director.call("get_current_plan")
		_pump(session, 4)

		if not skipped and bool(plan.get("needsWalk", false)):
			character.call("move_to", String(plan.get("walkTargetId", "")))
			_pump(session, 20)
			if String(character.call("get_state_name")) != "walking":
				# The target was next to him; try the next walking task instead.
				pass
			else:
				skipped = true
				director.call("_on_skip_pressed")
				_pump(session, 30)
				if String(character.call("get_state_name")) == "walking":
					failures.append("Skip left Little Buddy still walking to a task nobody is "
							+ "playing any more")
				failures.append_array(_check_not_stuck(session, "immediately after Skip"))
				continue

		if bool(plan.get("needsWalk", false)):
			if not bool(character.call("move_to", String(plan.get("walkTargetId", "")))):
				director.call("assist_now")
			_pump_until_task_changes(session, task_id, WALK_FRAMES)
		if String(runner.call("get_current_task_id")) != task_id:
			continue
		if bool(plan.get("needsChoices", false)):
			_pump(session, 4)
			runner.call("on_object_chosen", String(plan.get("objectId", "")))
		_pump(session, SETTLE_FRAMES)
		if bool(runner.call("is_running")) \
				and String(runner.call("get_current_task_id")) == task_id:
			runner.call("skip_current_task")
			_pump(session, 30)

	if not skipped:
		failures.append("no walking task was ever interrupted by Skip; the assertion is vacuous")
	if guard >= MAX_TASKS:
		failures.append("the level never finished after a mid-walk Skip")
	# The level still ended somewhere a child can act.
	failures.append_array(_check_not_stuck(session, "at the end of a skipped-through level"))
	_close(tree, session)
	return failures


## -- 5. Wandering into another room mid-task ------------------------------------------

## The child walks out through a door in the middle of a task. The loop must work
## out what the task needs from the new room rather than leaving them somewhere
## nothing can happen.
func _test_wandering_off_mid_task(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open(tree)
	if session.has("error"):
		return [String(session["error"])]
	var world: Node = session["world"]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var transition: Node = world.call("get_transition_controller")

	if not bool(director.call("_start_level", MISSION_ID)):
		_close(tree, session)
		return ["%s would not start" % MISSION_ID]
	_pump(session, 8)

	var here: String = String(world.call("get_current_room_id"))
	var elsewhere: String = _another_room(world, here)
	if elsewhere.is_empty():
		_close(tree, session)
		return ["the house has only one room; the wandering case cannot run"]

	var task_before: String = String(runner.call("get_current_task_id"))
	if not bool(transition.call("request_transition", elsewhere, "default")):
		_close(tree, session)
		return ["could not walk the child from the %s to the %s" % [here, elsewhere]]
	_pump(session, 60)

	if String(world.call("get_current_room_id")) != elsewhere:
		failures.append("the child did not actually change room")
	failures.append_array(_check_not_stuck(session, "after wandering into the %s" % elsewhere))
	if not bool(runner.call("is_running")):
		failures.append("changing room mid-task ended the level")

	# An unknown room is refused, and refusal is not a failure state either.
	transition.call("request_transition", "atticOfDoom", "default")
	_pump(session, 30)
	failures.append_array(_check_not_stuck(session, "after a refused transition"))
	if String(world.call("get_current_room_id")) != elsewhere:
		failures.append("a refused transition moved the child anyway")

	# And the level still finishes from wherever the child ended up.
	var play: Array = _play_out(session)
	failures.append_array(play)
	if String(runner.call("get_current_task_id")) == task_before \
			and bool(runner.call("is_running")):
		failures.append("the level never got past the task the child wandered away from")
	_close(tree, session)
	return failures


## -- 6. Mashing the summary ------------------------------------------------------------

## Next and Play Again, hammered. The summary must never be left half-open, the
## child must never be left Disabled behind a closed overlay, and there must
## always be something to play next.
func _test_mashing_the_summary(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open(tree)
	if session.has("error"):
		return [String(session["error"])]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]

	if not bool(director.call("_start_level", MISSION_ID)):
		_close(tree, session)
		return ["%s would not start" % MISSION_ID]
	failures.append_array(_play_out(session))

	if not bool(director.call("is_summary_open")):
		_close(tree, session)
		return failures + ["the level ended with no summary; there is nowhere for the child to go"]

	# The API is guarded, so hammering it is a no-op after the first press.
	for _i: int in range(MASH):
		director.call("advance_to_next_level")
		_pump(session, 2)
	if bool(director.call("is_summary_open")):
		failures.append("the summary stayed open after Next was pressed %d times" % MASH)
	if not bool(runner.call("is_running")):
		failures.append("mashing Next left no level running")
	failures.append_array(_check_not_stuck(session, "after mashing Next"))

	# The raw signal path a real button uses has no such guard. Firing it straight
	# at the director, repeatedly, must still leave a playable house.
	for _i: int in range(6):
		director.call("_on_summary_next_level")
		_pump(session, 2)
		director.call("_on_summary_play_again")
		_pump(session, 2)
	if bool(director.call("is_summary_open")):
		failures.append("the summary is open after Next/Play Again were fired directly")
	if not bool(runner.call("is_running")):
		failures.append("repeated Next/Play Again left no level running")
	if String(character.call("get_state_name")) == "disabled":
		failures.append("repeated Next/Play Again left the child Disabled with no overlay in "
				+ "front of them -- a dead end with a friendly face")

	# Closing rather than advancing must also lead forward, not to an empty room.
	failures.append_array(_play_out(session))
	if bool(director.call("is_summary_open")):
		director.call("dismiss_summary")
		_pump(session, 4)
		if not bool(runner.call("is_running")):
			failures.append("closing the summary left the journey with nothing to play")
		failures.append_array(_check_not_stuck(session, "after closing the summary"))

	_close(tree, session)
	return failures


## -- 7. Cancelling and coming back --------------------------------------------------------

## The parent takes the iPad away mid-task (the app is backgrounded, the runner is
## cancelled) and the child comes back. Starting again must work, and must not
## leave a half-finished task wedged.
func _test_cancelling_and_coming_back(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open(tree)
	if session.has("error"):
		return [String(session["error"])]
	var director: Node = session["director"]
	var runner: Node = session["runner"]

	if not bool(director.call("_start_level", MISSION_ID)):
		_close(tree, session)
		return ["%s would not start" % MISSION_ID]
	_pump(session, 12)

	runner.call("cancel")
	_pump(session, 30)
	if bool(runner.call("is_running")):
		failures.append("cancel() left the mission running")
	failures.append_array(_check_not_stuck(session, "after the activity was cancelled"))

	if not bool(director.call("_start_level", MISSION_ID)):
		failures.append("the level could not be started again after a cancel; the child would "
				+ "come back to nothing")
	_pump(session, 12)
	if not bool(runner.call("is_running")):
		failures.append("restarting after a cancel produced no running level")
	failures.append_array(_play_out(session))
	failures.append_array(_check_not_stuck(session, "after a cancel-and-replay"))
	_close(tree, session)
	return failures


# ---------------------------------------------------------------------------
# Shared assertions
# ---------------------------------------------------------------------------

## No dead ends: the child is not Disabled unless the summary is deliberately in
## front of them, and not left walking with no level running.
##
## The overlay state is read from the director rather than passed in, because a
## caller that has to remember to say "the summary is up" is a caller that will
## one day forget and turn this into an assertion that never fires.
func _check_not_stuck(session: Dictionary, context: String):
	var failures: Array = []
	var character: Node = session["character"]
	var runner: Node = session["runner"]
	var director: Node = session["director"]
	var state: String = String(character.call("get_state_name"))
	var overlay_open: bool = bool(director.call("is_summary_open"))

	if STUCK_STATES.has(state) and not overlay_open:
		failures.append("%s: the child is '%s' with nothing in front of them" % [context, state])
	if state == "walking" and not bool(runner.call("is_running")) and not overlay_open:
		failures.append("%s: the child is still walking with no level running" % context)
	return failures


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

func _open(tree: SceneTree):
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

	# A fresh ledger with the spam-tap WINDOW switched off, so what is measured
	# here is the duplicate guard rather than the clock: a headless run completes
	# a whole level inside one millisecond, which would refuse every award for
	# reasons that have nothing to do with a child's fingers.
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


func _close(tree: SceneTree, session: Dictionary) -> void:
	var world: Node = session.get("world", null)
	if world == null:
		return
	tree.root.remove_child(world)
	world.free()


func _pump(session: Dictionary, frames: int) -> void:
	var character: Node = session["character"]
	var director: Node = session["director"]
	for _frame: int in range(frames):
		character.call("step_movement", STEP)
		director.call("step", STEP)


func _pump_until_task_changes(session: Dictionary, task_id: String, frames: int) -> void:
	var character: Node = session["character"]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	for _frame: int in range(frames):
		character.call("step_movement", STEP)
		director.call("step", STEP)
		if String(runner.call("get_current_task_id")) != task_id:
			return
		if bool(director.call("is_beat_reached")) \
				and String(character.call("get_state_name")) == "idle":
			return


## Starts the level and plays normally until a task with objects to touch is live
## and reachable. Returns `{found, taskId, objectId}`.
func _reach_a_choice_task(session: Dictionary):
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]

	if not bool(director.call("_start_level", MISSION_ID)):
		return {"found": false}

	var guard: int = 0
	while bool(runner.call("is_running")) and guard < MAX_TASKS:
		guard += 1
		var task_id: String = String(runner.call("get_current_task_id"))
		var plan: Dictionary = director.call("get_current_plan")
		_pump(session, 4)

		if bool(plan.get("needsWalk", false)):
			if not bool(character.call("move_to", String(plan.get("walkTargetId", "")))):
				director.call("assist_now")
			_pump_until_task_changes(session, task_id, WALK_FRAMES)
		if String(runner.call("get_current_task_id")) != task_id:
			continue

		if bool(plan.get("needsChoices", false)):
			_pump(session, 4)
			if bool(director.call("is_beat_reached")):
				return {
					"found": true,
					"taskId": task_id,
					"objectId": String(plan.get("objectId", "")),
				}

		runner.call("skip_current_task")
		_pump(session, 30)
	return {"found": false}


## Finishes whatever is left of the level the honest way.
func _play_out(session: Dictionary):
	var failures: Array = []
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]

	var guard: int = 0
	while bool(runner.call("is_running")) and guard < MAX_TASKS:
		guard += 1
		var task_id: String = String(runner.call("get_current_task_id"))
		var plan: Dictionary = director.call("get_current_plan")
		_pump(session, 4)
		if bool(plan.get("needsWalk", false)):
			if not bool(character.call("move_to", String(plan.get("walkTargetId", "")))):
				director.call("assist_now")
			_pump_until_task_changes(session, task_id, WALK_FRAMES)
		if String(runner.call("get_current_task_id")) != task_id:
			continue
		if bool(plan.get("needsChoices", false)):
			_pump(session, 4)
			runner.call("on_object_chosen", String(plan.get("objectId", "")))
		_pump(session, SETTLE_FRAMES)
		if bool(runner.call("is_running")) \
				and String(runner.call("get_current_task_id")) == task_id:
			runner.call("skip_current_task")
			_pump(session, 30)
	if guard >= MAX_TASKS:
		failures.append("the level would not finish; the play loop ran %d times" % guard)
	return failures


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


## Any spawned object that is NOT the target -- the "second finger" in case 2.
func _other_object_id(runner: Node, target_id: String) -> String:
	for node: Variant in _spawned_objects(runner):
		if not (node is Node) or not is_instance_valid(node):
			continue
		var object_id: String = String((node as Node).get("object_id"))
		if not object_id.is_empty() and object_id != target_id:
			return object_id
	return ""


func _another_room(world: Node, not_this_one: String) -> String:
	for room_id: Variant in world.call("get_room_ids"):
		if String(room_id) != not_this_one:
			return String(room_id)
	return ""
