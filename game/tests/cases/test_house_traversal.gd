extends RefCounted

## The Phase 2B traversal route, end to end, driven only by semantic ids:
##
##     bedroom -> door -> bathroom -> sink -> living room -> kitchen -> table
##             -> back to the bedroom
##
## This is the proof that the four rooms are one navigable world: walking,
## arrival, room transitions, camera reframing and save-safe world state, in one
## continuous run with no coordinates anywhere in the script.
##
## There is deliberately **no English mission content here** -- no vocabulary, no
## tasks, no stars. Phase 2B is the world; the lessons come later.
##
## `run()` is untyped on purpose.

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const WorldState := preload("res://scripts/house/world_state.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")

const STEP: float = 1.0 / 60.0
const MAX_FRAMES: int = 4000

## Each leg: the semantic id to walk to, and the room the child should be in
## afterwards. Doors change room; furniture does not.
const ROUTE: Array[Array] = [
	["bedroom.doorToBathroom", "bathroom"],
	["bathroom.sink", "bathroom"],
	["bathroom.doorToLivingRoom", "livingRoom"],
	["livingRoom.doorToKitchen", "kitchen"],
	["kitchen.table", "kitchen"],
	["kitchen.doorToBedroom", "bedroom"],
]


func test_name() -> String:
	return "house_traversal"


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var packed: Resource = load(SCENE_PATH)
	if not (packed is PackedScene):
		return ["could not load %s" % SCENE_PATH]
	var world: Node = (packed as PackedScene).instantiate()
	tree.root.add_child(world)
	world.call("_ready")

	var character: Node = world.call("get_character")
	var camera: Camera3D = world.get_node_or_null("WorldCamera") as Camera3D

	# Prove the map answers before walking anywhere. Without this the whole route
	# could pass on straight-line fallback paths that ignore every wall.
	var provider: RefCounted = NavMapProviderScript.create(world.call("get_navigation_map"))
	if not bool(provider.call("force_sync", Vector3.ZERO)):
		failures.append("the house navigation map never answered; the route below would prove "
				+ "nothing")
		tree.root.remove_child(world)
		world.free()
		return failures

	world.call("place_in_room", "bedroom", "default")
	character.call("set_disabled", false)

	var arrivals: Array = []
	var transitions: Array = []
	var statuses: Array = []
	character.connect("arrived", func(id: String) -> void: arrivals.append(id))
	world.call("get_transition_controller").connect("transition_completed",
			func(room: String, _spawn: String) -> void: transitions.append(room))
	world.connect("status_changed", func(message: String) -> void: statuses.append(message))

	for leg: Array in ROUTE:
		var target_id: String = String(leg[0])
		var expected_room: String = String(leg[1])
		var from_room: String = String(world.call("get_current_room_id"))

		arrivals.clear()
		if not bool(character.call("move_to", target_id)):
			failures.append("could not set off for %s from the %s" % [target_id, from_room])
			continue
		_run_until_idle(character)

		if arrivals != [target_id]:
			failures.append("expected exactly one arrival at %s, got %s"
					% [target_id, str(arrivals)])
		if String(world.call("get_current_room_id")) != expected_room:
			failures.append("after walking to %s the child should be in the %s, is in the %s"
					% [target_id, expected_room, String(world.call("get_current_room_id"))])
			continue

		# Control is back after every leg, door or not.
		if String(character.call("get_state_name")) == "disabled":
			failures.append("the child is disabled after walking to %s" % target_id)
		if bool(character.call("is_busy")):
			failures.append("the child is still busy after arriving at %s" % target_id)

		# The child is standing in the room they are supposed to be in.
		var position: Vector3 = SpatialUtil.world_position(character as Node3D)
		var floor_bounds: Rect2 = HouseLayout.world_floor_bounds(expected_room)
		if not floor_bounds.has_point(Vector2(position.x, position.z)):
			failures.append("after %s the child is at %s, outside the %s"
					% [target_id, str(position), expected_room])

		# The camera followed. A room change that does not reframe leaves the child
		# off screen, which no test of state alone would ever catch.
		if camera != null:
			var room_origin: Vector3 = HouseLayout.room_origin(expected_room)
			if absf(camera.position.x - room_origin.x) > 2.0:
				failures.append("after entering the %s the camera is at x=%.2f, the room is at "
						% [expected_room, camera.position.x] + "x=%.2f" % room_origin.x)
			if camera.position.y <= HouseLayout.FLOOR_Y:
				failures.append("the camera dropped below the floor in the %s" % expected_room)

		# World state stayed semantic and save-safe at every step.
		var saved: Dictionary = world.call("write_into_profile", {})
		var read_back: RefCounted = WorldState.read_from_profile(saved)
		if String(read_back.call("get_room_id")) != expected_room:
			failures.append("after %s the saved room is '%s', expected '%s'"
					% [target_id, String(read_back.call("get_room_id")), expected_room])
		if not HouseLayout.spawn_points(expected_room).has(
			String(read_back.call("get_spawn_id"))
		):
			failures.append("after %s the saved spawn '%s' does not exist in the %s"
					% [target_id, String(read_back.call("get_spawn_id")), expected_room])

	# The full circuit: three doors used, every room visited, home again.
	if transitions != ["bathroom", "livingRoom", "kitchen", "bedroom"]:
		failures.append("expected to pass through the bathroom, living room, kitchen and back "
				+ "to the bedroom, got %s" % str(transitions))
	if String(world.call("get_current_room_id")) != "bedroom":
		failures.append("the route should end where it started")

	# Every room change said something short and warm to the child.
	if statuses.size() < ROUTE.size():
		failures.append("the child got %d pieces of feedback across %d legs"
				% [statuses.size(), ROUTE.size()])
	for message: String in statuses:
		if message.strip_edges().is_empty():
			failures.append("an empty status message was shown")
		for harsh: String in ["error", "fail", "wrong", "invalid"]:
			if message.to_lower().contains(harsh):
				failures.append("the child was shown '%s'; there is no failure language in "
						% message + "this game")

	# And after all that the child is still a working, drivable character.
	if not bool(character.call("move_to", "bedroom.toy")):
		failures.append("the child cannot be driven after completing the route")
	character.call("stop")

	tree.root.remove_child(world)
	world.free()
	return failures


func _run_until_idle(character: Node) -> void:
	for _frame: int in range(MAX_FRAMES):
		character.call("step_movement", STEP)
		if String(character.call("get_state_name")) == "idle":
			return
