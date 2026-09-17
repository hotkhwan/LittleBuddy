extends RefCounted

## Room transitions: the door loop, and every way it is allowed to fail.
##
## The three properties this file exists to defend (contract §4):
##   1. an unknown destination is REFUSED, not crashed, and the child stays put;
##   2. control is ALWAYS restored, including on the failure path;
##   3. arrival fires EXACTLY once.
##
## `run()` is untyped on purpose -- a typed `-> Array` turns a crashed case into
## a silent [PASS].

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")

const STEP: float = 1.0 / 60.0
const MAX_FRAMES: int = 3000


func test_name() -> String:
	return "room_transition"


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var world: Node = _instantiate(tree)
	if world == null:
		return ["could not instantiate %s" % SCENE_PATH]

	failures.append_array(_test_navigation_answers(world))
	failures.append_array(_test_bedroom_to_bathroom(world))
	failures.append_array(_test_unknown_room_is_refused(world))
	failures.append_array(_test_tapping_a_door_transitions_once(world))
	failures.append_array(_test_arrival_fires_once(world))
	failures.append_array(_test_path_replacement(world))
	failures.append_array(_test_unreachable_target(world))
	failures.append_array(_test_reentrant_transition_is_refused(world))

	tree.root.remove_child(world)
	world.free()
	return failures


## The trap `NavMapProvider.force_sync()` exists for: a non-zero
## `map_get_iteration_id()` is NOT proof the map answers. Everything below walks
## real paths, so if the map were silently empty every reachability assertion
## would pass for the wrong reason. Prove it answers first.
func _test_navigation_answers(world: Node):
	var failures: Array = []
	var map: RID = world.call("get_navigation_map")
	var provider: RefCounted = NavMapProviderScript.create(map)
	if not bool(provider.call("force_sync", Vector3.ZERO)):
		failures.append("the house navigation map never answered a query; every reachability "
				+ "assertion below would pass for the wrong reason")
		return failures

	# And the rooms must be separate islands: no path may run between them.
	var bedroom: Vector3 = HouseLayout.room_origin("bedroom")
	var bathroom: Vector3 = HouseLayout.room_origin("bathroom")
	var across: PackedVector3Array = provider.call("query_path", bedroom, bathroom)
	if NavMath.path_reaches(across, bathroom, 0.5):
		failures.append("there is a walkable path from the bedroom to the bathroom; the rooms "
				+ "are connected and doors are not the only way between them")
	return failures


func _test_bedroom_to_bathroom(world: Node):
	var failures: Array = []
	var controller: Node = world.call("get_transition_controller")
	var character: Node = world.call("get_character")
	_reset(world)

	var completed: Array = []
	var refused: Array = []
	var started: Array = []
	controller.connect("transition_completed",
			func(room: String, spawn: String) -> void: completed.append([room, spawn]))
	controller.connect("transition_refused",
			func(room: String, reason: String) -> void: refused.append([room, reason]))
	controller.connect("transition_started",
			func(from_room: String, to_room: String) -> void: started.append([from_room, to_room]))

	if not bool(controller.call("request_transition", "bathroom", "fromBedroom")):
		failures.append("the bedroom -> bathroom transition was refused")
	if String(world.call("get_current_room_id")) != "bathroom":
		failures.append("after the transition the current room is '%s'"
				% String(world.call("get_current_room_id")))
	if completed.size() != 1:
		failures.append("expected exactly one transition_completed, got %d" % completed.size())
	if refused.size() != 0:
		failures.append("a successful transition emitted a refusal: %s" % str(refused))
	if started != [["bedroom", "bathroom"]]:
		failures.append("expected one start bedroom->bathroom, got %s" % str(started))

	var bathroom: Node = world.call("get_room", "bathroom")
	var expected: Vector3 = bathroom.call("get_spawn_position", "fromBedroom")
	var actual: Vector3 = SpatialUtil.world_position(character as Node3D)
	if not NavMath.is_within(actual, expected, 0.05):
		failures.append("the child should arrive at %s, is at %s" % [str(expected), str(actual)])

	# Rule 2: control is back.
	if String(character.call("get_state_name")) == "disabled":
		failures.append("the child is still disabled after a completed transition")
	if not bool(character.call("move_to", "bathroom.sink")):
		failures.append("the child cannot be sent to the sink after arriving in the bathroom")
	character.call("stop")

	# Only the current room is live.
	if not bool(bathroom.call("is_active")):
		failures.append("the bathroom is not active after entering it")
	if bool(world.call("get_room", "bedroom").call("is_active")):
		failures.append("the bedroom is still active after leaving it")
	if bool(character.call("move_to", "bedroom.bed")):
		failures.append("the child walked to a target in a room they are not in")

	# And the character's registry holds EXACTLY the room the child is standing
	# in. Disabling the other rooms' targets already stops them being walked to;
	# scoping the registry as well is what keeps the failure mode "I have never
	# heard of that" rather than "I know it but it is switched off", and keeps the
	# registry the size of one room instead of the whole house.
	var registered: Array = world.call("get_registered_target_ids")
	if registered.size() != 5:
		failures.append("expected the bathroom's 5 targets to be registered, got %d: %s"
				% [registered.size(), str(registered)])
	for target_id: String in registered:
		if not target_id.begins_with("bathroom."):
			failures.append("'%s' is registered while the child is in the bathroom" % target_id)
	return failures


## Contract §4, rule 1. The one that must not crash.
func _test_unknown_room_is_refused(world: Node):
	var failures: Array = []
	var controller: Node = world.call("get_transition_controller")
	var character: Node = world.call("get_character")
	_reset(world)

	var before_room: String = String(world.call("get_current_room_id"))
	var before_position: Vector3 = SpatialUtil.world_position(character as Node3D)
	var completed: Array = []
	var refused: Array = []
	controller.connect("transition_completed",
			func(room: String, spawn: String) -> void: completed.append([room, spawn]))
	controller.connect("transition_refused",
			func(room: String, reason: String) -> void: refused.append([room, reason]))

	if bool(controller.call("request_transition", "dungeon", "default")):
		failures.append("a transition to an unknown room reported success")
	if refused != [["dungeon", "unknownRoom"]]:
		failures.append("expected one 'unknownRoom' refusal, got %s" % str(refused))
	if not completed.is_empty():
		failures.append("a refused transition still emitted transition_completed")
	if String(world.call("get_current_room_id")) != before_room:
		failures.append("a refused transition moved the child to '%s'"
				% String(world.call("get_current_room_id")))
	if not NavMath.is_within(SpatialUtil.world_position(character as Node3D), before_position, 0.01):
		failures.append("a refused transition moved the child")

	# Rule 2 on the FAILURE path: still in control, and still able to walk.
	if String(character.call("get_state_name")) == "disabled":
		failures.append("the child was left disabled by a refused transition -- every tap "
				+ "would do nothing for the rest of the session")
	if bool(character.call("is_busy")):
		failures.append("the child is still busy after a refused transition")
	if not bool(character.call("move_to", "bedroom.bed")):
		failures.append("the child cannot walk after a refused transition")
	character.call("stop")

	# An empty destination is the same story.
	if bool(controller.call("request_transition", "", "")):
		failures.append("a transition to an empty room id reported success")
	if String(character.call("get_state_name")) == "disabled":
		failures.append("an empty destination left the child disabled")
	return failures


## The whole child-facing loop, driven only by a semantic id: tap the door, walk
## to it, turn to face it, change room. Exactly once.
func _test_tapping_a_door_transitions_once(world: Node):
	var failures: Array = []
	var controller: Node = world.call("get_transition_controller")
	var character: Node = world.call("get_character")
	_reset(world)

	var completed: Array = []
	controller.connect("transition_completed",
			func(room: String, spawn: String) -> void: completed.append(room))

	var door_id: String = "bedroom.doorToBathroom"
	if not bool(character.call("move_to", door_id)):
		failures.append("the child would not walk to %s" % door_id)
		return failures
	_run_until_idle(character)

	if completed != ["bathroom"]:
		failures.append("walking to the bedroom's bathroom door should change room exactly "
				+ "once, got %s" % str(completed))
	if String(world.call("get_current_room_id")) != "bathroom":
		failures.append("the child is in '%s', expected the bathroom"
				% String(world.call("get_current_room_id")))
	if String(character.call("get_state_name")) == "disabled":
		failures.append("the child is disabled after walking through a door")
	return failures


func _test_arrival_fires_once(world: Node):
	var failures: Array = []
	var character: Node = world.call("get_character")
	_reset(world)

	var arrivals: Array = []
	var ready: Array = []
	var arrived_handler: Callable = func(id: String) -> void: arrivals.append(id)
	var ready_handler: Callable = func(id: String) -> void: ready.append(id)
	character.connect("arrived", arrived_handler)
	character.connect("interaction_ready", ready_handler)

	if not bool(character.call("move_to", "bedroom.bed")):
		failures.append("the child would not walk to the bed")
	_run_until_idle(character)

	if arrivals != ["bedroom.bed"]:
		failures.append("expected exactly one arrival at the bed, got %s" % str(arrivals))
	if ready != ["bedroom.bed"]:
		failures.append("expected exactly one interaction-ready at the bed, got %s" % str(ready))

	# Keep stepping: a latch that only holds for one frame is not a latch.
	for _frame: int in range(120):
		character.call("step_movement", STEP)
	if arrivals.size() != 1:
		failures.append("arrival fired again while standing still (%d times)" % arrivals.size())

	character.disconnect("arrived", arrived_handler)
	character.disconnect("interaction_ready", ready_handler)
	return failures


## One destination, never a queue: a second request replaces the first.
func _test_path_replacement(world: Node):
	var failures: Array = []
	var character: Node = world.call("get_character")
	_reset(world)

	var arrivals: Array = []
	var handler: Callable = func(id: String) -> void: arrivals.append(id)
	character.connect("arrived", handler)

	character.call("move_to", "bedroom.bed")
	for _frame: int in range(20):
		character.call("step_movement", STEP)
	var controller: RefCounted = character.call("get_movement_controller")
	var serial_before: int = int(controller.call("get_move_serial"))

	character.call("move_to", "bedroom.wardrobe")
	var serial_after: int = int(controller.call("get_move_serial"))
	if serial_after != serial_before + 1:
		failures.append("a replacing request should bump the move serial exactly once (%d -> %d)"
				% [serial_before, serial_after])
	if String(controller.call("get_target_id")) != "bedroom.wardrobe":
		failures.append("the second request did not replace the first; the child is still "
				+ "heading for '%s'" % String(controller.call("get_target_id")))

	_run_until_idle(character)
	if arrivals != ["bedroom.wardrobe"]:
		failures.append("a replaced walk must not also arrive at the abandoned target, got %s"
				% str(arrivals))
	character.disconnect("arrived", handler)
	return failures


## A tap the child genuinely cannot reach changes nothing at all -- no walk, no
## half-path, and certainly no red X.
func _test_unreachable_target(world: Node):
	var failures: Array = []
	var character: Node = world.call("get_character")
	_reset(world)

	var reasons: Array = []
	var handler: Callable = func(_id: String, reason: String) -> void: reasons.append(reason)
	character.connect("move_failed", handler)

	# Another room entirely: on the same navigation map, but a separate island.
	var elsewhere: Vector3 = HouseLayout.room_origin("kitchen")
	if bool(character.call("move_to_ground", elsewhere.x, elsewhere.z)):
		failures.append("the child set off towards another room across a wall")
	if reasons != ["unreachable"]:
		failures.append("expected one 'unreachable', got %s" % str(reasons))
	if String(character.call("get_state_name")) != "idle":
		failures.append("an unreachable tap disturbed the child's state ('%s')"
				% String(character.call("get_state_name")))

	# Inside a solid object is unreachable too, but a tap just beside one is
	# forgiven -- a child taps a region, not a pixel.
	reasons.clear()
	var beside_bed: Vector3 = HouseLayout.room_origin("bedroom") + Vector3(-1.0, 0.0, -0.5)
	if not bool(character.call("move_to_ground", beside_bed.x, beside_bed.z)):
		failures.append("a tap on open floor beside the bed should be accepted, got %s"
				% str(reasons))
	character.call("stop")
	character.disconnect("move_failed", handler)
	return failures


## A transition requested from inside a transition must be refused rather than
## re-entering, or `transition_completed` could fire more than once per door.
func _test_reentrant_transition_is_refused(world: Node):
	var failures: Array = []
	var controller: Node = world.call("get_transition_controller")
	var character: Node = world.call("get_character")
	_reset(world)

	var refused: Array = []
	var completed: Array = []
	var nested: Array = []
	controller.connect("transition_refused",
			func(_room: String, reason: String) -> void: refused.append(reason))
	controller.connect("transition_completed",
			func(room: String, _spawn: String) -> void: completed.append(room))
	controller.connect("transition_started", func(_from: String, _to: String) -> void:
		if nested.is_empty():
			nested.append(bool(controller.call("request_transition", "kitchen", "default"))))

	controller.call("request_transition", "bathroom", "fromBedroom")
	if nested != [false]:
		failures.append("a transition requested during a transition should be refused, got %s"
				% str(nested))
	if refused != ["busy"]:
		failures.append("expected one 'busy' refusal, got %s" % str(refused))
	if completed != ["bathroom"]:
		failures.append("expected exactly one completion, got %s" % str(completed))
	if String(character.call("get_state_name")) == "disabled":
		failures.append("the child was left disabled by a re-entrant transition")
	return failures


## -- Helpers -------------------------------------------------------------------

## Back to the bedroom default, with every signal connection from the previous
## sub-test dropped, so one sub-test cannot contaminate the next.
func _reset(world: Node) -> void:
	var controller: Node = world.call("get_transition_controller")
	for signal_name: String in [
		"transition_completed", "transition_refused", "transition_started"
	]:
		for connection: Dictionary in controller.get_signal_connection_list(signal_name):
			controller.disconnect(signal_name, connection["callable"])
	world.call("place_in_room", "bedroom", "default")
	var character: Node = world.call("get_character")
	character.call("set_disabled", false)
	character.call("stop")


func _run_until_idle(character: Node) -> void:
	for _frame: int in range(MAX_FRAMES):
		character.call("step_movement", STEP)
		if String(character.call("get_state_name")) == "idle":
			return


func _instantiate(tree: SceneTree) -> Node:
	var packed: Resource = load(SCENE_PATH)
	if packed == null or not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	if world == null:
		return null
	tree.root.add_child(world)
	world.call("_ready")
	return world
