extends RefCounted

## Every door, both ways, three times: one crossing is exactly one transition.
##
## Owner report (2026-09-21, real device): "some rooms enter and immediately
## bounce back out". This walks Aliz through every door of the ring in both
## directions, three round trips per door pair, on the REAL house -- baked
## meshes, real `ActivityTarget` doors, the real `RoomTransitionController` --
## and after every crossing asserts:
##
##   1. exactly one `transition_started` and one `transition_completed`;
##   2. the room id and the world state name the same room and the arrival spawn;
##   3. she stands on that spawn, at rest, in control (not disabled);
##   4. standing there for a full second produces NO second transition and no
##      movement -- the arrival spawn is the return door's own stand point, so
##      this is the assertion that arriving is not the same as re-arriving;
##   5. the next crossing back goes through the door she is standing at.
##
## Run twice: on the bare world, and with the Free Play director attached (the
## mode the device is played in most), whose `interaction_ready` handler runs
## after the controller's on the same signal.
##
## And the case that WAS the report: Story mode, a task in the bedroom, and
## the child taps the kitchen door of her own accord. The level director used
## to route her home the instant the transition completed -- she was standing
## on the return door's stand point, so she was back in the bedroom 0.33 s
## after entering the kitchen. She must now stay in the kitchen, at rest and
## in control, for at least a second; the level's own assist brings her home
## later (`house_level_director.gd::assist_now()`), which is not a bounce.
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")
const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const RewardManagerScript := preload("res://scripts/rewards/reward_manager.gd")

const DT: float = 1.0 / 60.0
## Room crossing plus the turn to face: 4 m at 1.05 m/s is under 4 s; 10 s cap.
const WALK_BUDGET: int = 600
const REST_FRAMES: int = 60
const ROUND_TRIPS: int = 3
const MODE_FREE_PLAY: int = 1


func test_name() -> String:
	return "room_transitions"


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	failures.append_array(_test_every_door_both_ways(tree, false))
	failures.append_array(_test_every_door_both_ways(tree, true))
	failures.append_array(_test_story_mode_does_not_bounce_her_back(tree))
	return failures


func _test_story_mode_does_not_bounce_her_back(tree: SceneTree):
	var failures: Array = []
	var world: Node = _instantiate(tree, false)
	if world == null:
		return ["story: could not instantiate %s" % SCENE_PATH]
	var provider: RefCounted = NavMapProviderScript.create(world.call("get_navigation_map"))
	if not bool(provider.call("force_sync", Vector3.ZERO)):
		_release(tree, world)
		return ["story: the house navigation map never answered a query"]
	var ledger: RefCounted = RewardLedgerScript.create()
	ledger.set("min_interval_ms", 0)
	RewardManagerScript.set_shared_ledger(ledger)
	var director: Node = world.call("ensure_level_director")
	if director == null:
		_release(tree, world)
		return ["story: the house built no level director"]
	var runner: Node = director.call("get_runner")
	var character: Node = world.call("get_character")
	var log: Array = []
	world.call("get_transition_controller").connect("transition_completed",
			func(room: String, _spawn: String) -> void: log.append(room))

	director.call("_start_level", "goodMorningRoutine")
	_pump_story(character, director, 30)
	# The first task that asks for a walk to something in the bedroom.
	var found: bool = false
	for _guard: int in range(20):
		var plan: Dictionary = director.call("get_current_plan")
		if not String(plan.get("walkTargetId", "")).is_empty() \
				and String(plan.get("roomId", "")) == "bedroom":
			found = true
			break
		runner.call("skip_current_task")
		_pump_story(character, director, 20)
	if not found:
		_release(tree, world)
		return ["story: the level has no bedroom walk task; the case is vacuous"]

	# She taps the OTHER door, of her own accord.
	if not bool(character.call("move_to", "bedroom.doorToKitchen")):
		failures.append("story: she would not walk to the kitchen door")
	var entered_at: int = -1
	for frame: int in range(WALK_BUDGET):
		_pump_story(character, director, 1)
		if String(world.call("get_current_room_id")) == "kitchen":
			entered_at = frame
			break
	if entered_at < 0:
		failures.append("story: she never reached the kitchen (%s)" % str(log))
	else:
		# A full second in the kitchen: still there, at rest, in control.
		_pump_story(character, director, 60)
		if String(world.call("get_current_room_id")) != "kitchen":
			failures.append("story: she was walked back out of the kitchen within a second "
					+ "of entering it (transitions %s)" % str(log))
		if log != ["kitchen"]:
			failures.append("story: expected one transition into the kitchen, got %s" % str(log))
		if String(character.call("get_state_name")) == "disabled":
			failures.append("story: she is disabled after wandering into the kitchen")
		if bool(character.call("is_busy")):
			failures.append("story: she is %s a second after entering the kitchen; nobody asked "
					% character.call("get_state_name") + "her to go anywhere")
		if not bool(runner.call("is_running")):
			failures.append("story: wandering through a door ended the level")
	_release(tree, world)
	return failures


func _pump_story(character: Node, director: Node, frames: int) -> void:
	for _frame: int in range(frames):
		character.call("step_movement", DT)
		director.call("step", DT)


func _test_every_door_both_ways(tree: SceneTree, free_play: bool):
	var failures: Array = []
	var label: String = "freePlay" if free_play else "world"
	var world: Node = _instantiate(tree, free_play)
	if world == null:
		return ["%s: could not instantiate %s" % [label, SCENE_PATH]]
	var provider: RefCounted = NavMapProviderScript.create(world.call("get_navigation_map"))
	if not bool(provider.call("force_sync", Vector3.ZERO)):
		_release(tree, world)
		return ["%s: the house navigation map never answered a query" % label]

	var controller: Node = world.call("get_transition_controller")
	var character: Node = world.call("get_character")
	var log: Dictionary = {"started": [], "completed": [], "refused": []}
	controller.connect("transition_started",
			func(from_room: String, to_room: String) -> void: log["started"].append([from_room, to_room]))
	controller.connect("transition_completed",
			func(room: String, spawn: String) -> void: log["completed"].append([room, spawn]))
	controller.connect("transition_refused",
			func(room: String, reason: String) -> void: log["refused"].append([room, reason]))

	for room_id: String in HouseLayout.room_ids():
		for door: Dictionary in HouseLayout.doors(room_id):
			var to_room: String = String(door["toRoomId"])
			var back_door: String = HouseLayout.door_target_id(room_id)
			for trip: int in range(ROUND_TRIPS):
				var tag: String = "%s %s->%s trip %d" % [label, room_id, to_room, trip + 1]
				world.call("place_in_room", room_id, HouseLayout.DEFAULT_SPAWN)
				character.call("stop")
				failures.append_array(_cross(world, character, log,
						"%s.%s" % [room_id, String(door["targetId"])], room_id, to_room, tag))
				if String(world.call("get_current_room_id")) != to_room:
					continue
				# ...and straight back through the door she is standing at.
				failures.append_array(_cross(world, character, log,
						"%s.%s" % [to_room, back_door], to_room, room_id, tag + " (back)"))

	_release(tree, world)
	return failures


## One crossing, fully asserted. `door_id` is the semantic id of the door in
## the room she is standing in.
func _cross(world: Node, character: Node, log: Dictionary, door_id: String,
		from_room: String, to_room: String, tag: String):
	var failures: Array = []
	for key: String in log.keys():
		(log[key] as Array).clear()
	var arrivals: Array = []
	var arrived_handler: Callable = func(id: String) -> void: arrivals.append(id)
	character.connect("arrived", arrived_handler)

	if not bool(character.call("move_to", door_id)):
		character.disconnect("arrived", arrived_handler)
		return ["%s: she would not walk to %s" % [tag, door_id]]
	var frames: int = _pump(character, WALK_BUDGET, true)
	character.disconnect("arrived", arrived_handler)
	if frames >= WALK_BUDGET:
		failures.append("%s: still %s after %d frames on the way to %s"
				% [tag, character.call("get_state_name"), frames, door_id])
		return failures

	# 1. Exactly one transition.
	if (log["started"] as Array) != [[from_room, to_room]]:
		failures.append("%s: expected one start %s->%s, got %s" % [tag, from_room, to_room, str(log["started"])])
	var expected_spawn: String = HouseLayout.arrival_spawn_id(from_room)
	if (log["completed"] as Array) != [[to_room, expected_spawn]]:
		failures.append("%s: expected one completion [%s, %s], got %s"
				% [tag, to_room, expected_spawn, str(log["completed"])])
	if not (log["refused"] as Array).is_empty():
		failures.append("%s: a clean crossing emitted a refusal: %s" % [tag, str(log["refused"])])
	if arrivals != [door_id]:
		failures.append("%s: expected one arrival at %s, got %s" % [tag, door_id, str(arrivals)])

	# 2. Room id and world state agree, and name the arrival spawn.
	var room_now: String = String(world.call("get_current_room_id"))
	if room_now != to_room:
		failures.append("%s: the current room is '%s'" % [tag, room_now])
	var state: RefCounted = world.call("get_world_state")
	if state != null:
		if String(state.call("get_room_id")) != to_room \
				or String(state.call("get_spawn_id")) != expected_spawn:
			failures.append("%s: world state says %s/%s, expected %s/%s" % [tag,
					state.call("get_room_id"), state.call("get_spawn_id"), to_room, expected_spawn])
	if String(world.call("get_current_spawn_id")) != expected_spawn:
		failures.append("%s: current spawn id is '%s', expected '%s'"
				% [tag, world.call("get_current_spawn_id"), expected_spawn])

	# 3. On the spawn, at rest, in control.
	var room: Node = world.call("get_room", to_room)
	var spawn: Vector3 = room.call("get_spawn_position", expected_spawn)
	var here: Vector3 = SpatialUtil.world_position(character as Node3D)
	if not NavMath.is_within(here, spawn, 0.05):
		failures.append("%s: she should stand on the spawn %s, is at %s" % [tag, str(spawn), str(here)])
	if String(character.call("get_state_name")) == "disabled":
		failures.append("%s: she is disabled after the crossing" % tag)
	if bool(character.call("is_busy")):
		failures.append("%s: she is still busy (%s) after the crossing" % [tag, character.call("get_state_name")])

	# 4. A second standing still is not a second crossing.
	for key: String in log.keys():
		(log[key] as Array).clear()
	_pump(character, REST_FRAMES, false)
	if not (log["started"] as Array).is_empty() or not (log["completed"] as Array).is_empty():
		failures.append("%s: a second transition fired while she stood on the arrival spawn: %s / %s"
				% [tag, str(log["started"]), str(log["completed"])])
	if String(world.call("get_current_room_id")) != to_room:
		failures.append("%s: she bounced to '%s' while standing still" % [tag, world.call("get_current_room_id")])
	if not NavMath.is_within(SpatialUtil.world_position(character as Node3D), here, 0.01):
		failures.append("%s: she moved while standing on the arrival spawn" % tag)
	return failures


## -- Helpers --------------------------------------------------------------------------

## Steps the character (and any director) for up to `frames`; with `until_idle`
## returns early once she is at rest.
func _pump(character: Node, frames: int, until_idle: bool) -> int:
	for frame: int in range(frames):
		character.call("step_movement", DT)
		if until_idle and not bool(character.call("is_busy")):
			return frame + 1
	return frames


func _instantiate(tree: SceneTree, free_play: bool) -> Node:
	var packed: Resource = load(SCENE_PATH)
	if packed == null or not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	if world == null:
		return null
	if free_play:
		world.call("set_progression_mode", MODE_FREE_PLAY)
	tree.root.add_child(world)
	if free_play:
		world.call("build_world")
		var director: Node = world.call("ensure_free_play_director")
		if director != null:
			director.call("start")
	else:
		world.call("_ready")
	return world


func _release(tree: SceneTree, world: Node) -> void:
	if world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()
