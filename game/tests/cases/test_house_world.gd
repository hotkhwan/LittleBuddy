extends RefCounted

## HouseWorld structure: the four rooms, their ids, their targets, their spawns,
## their scale, their baked navigation and their camera framing.
##
## `run()` is deliberately UNTYPED. A `-> Array` annotation makes a case that
## aborts mid-run return an empty Array, which the runner reports as [PASS] --
## `test_runner_fails_loud.gd` enforces this project-wide.

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const RoomFraming := preload("res://scripts/house/room_framing.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const ToddlerView := preload("res://scripts/character/toddler_view.gd")

## Contract §3, verbatim. If these ever disagree with the contract, the contract
## wins and this list is the thing that is wrong.
const REQUIRED_TARGETS: Dictionary = {
	"bedroom": ["bed", "wardrobe", "toy"],
	"bathroom": ["sink", "bath", "towel"],
	"kitchen": ["fridge", "table", "counter"],
	"livingRoom": ["sofa", "toyBox", "book"],
}

## Every aspect ratio the game ships on: 4:3 iPad, 16:9, tall landscape iPhone.
const ASPECT_RATIOS: Array[float] = [1366.0 / 1024.0, 16.0 / 9.0, 19.5 / 9.0]

## The house must never bake at runtime -- Godot documents it as a frame-blocking
## stall and the performance budget forbids it.
const RUNTIME_BAKE_CALLS: Array[String] = [
	"bake_navigation_mesh(", "bake_from_source_geometry_data(", "parse_source_geometry_data(",
]
const SHIPPED_HOUSE_SCRIPTS: Array[String] = [
	"res://scripts/house/house_world.gd",
	"res://scripts/house/room.gd",
	"res://scripts/house/house_layout.gd",
	"res://scripts/house/room_transition_controller.gd",
	"res://scripts/house/world_state.gd",
	"res://scripts/house/room_framing.gd",
]


func test_name() -> String:
	return "house_world"


func run():
	var failures: Array = []
	failures.append_array(_test_layout_is_a_ring())
	failures.append_array(_test_scale())
	failures.append_array(_test_no_runtime_baking())
	failures.append_array(_test_baked_navmesh_resources())
	failures.append_array(_test_camera_framing_fits_every_screen())

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		failures.append("no SceneTree; the world could not be instantiated")
		return failures
	var world: Node = _instantiate(tree)
	if world == null:
		failures.append("could not instantiate %s" % SCENE_PATH)
		return failures

	failures.append_array(_test_structure(world))
	failures.append_array(_test_rooms(world))
	failures.append_array(_test_targets(world))
	failures.append_array(_test_spawns(world))
	failures.append_array(_test_navigation_regions(world))
	failures.append_array(_test_character(world))

	tree.root.remove_child(world)
	world.free()
	return failures


## -- Pure checks ---------------------------------------------------------------

## No dead ends (contract §4): every room reachable from every other, directly or
## via one intermediate room.
func _test_layout_is_a_ring():
	var failures: Array = []
	var ids: Array = HouseLayout.room_ids()
	if ids.size() != 4:
		failures.append("the house should have 4 rooms, has %d" % ids.size())
	for expected: String in REQUIRED_TARGETS.keys():
		if not ids.has(expected):
			failures.append("the contract requires a room id '%s'" % expected)

	for from_id: String in ids:
		var reachable: Array = [from_id]
		for door: Dictionary in HouseLayout.doors(from_id):
			var neighbour: String = String(door["toRoomId"])
			if not reachable.has(neighbour):
				reachable.append(neighbour)
			for hop: Dictionary in HouseLayout.doors(neighbour):
				if not reachable.has(String(hop["toRoomId"])):
					reachable.append(String(hop["toRoomId"]))
		for to_id: String in ids:
			if not reachable.has(to_id):
				failures.append("%s cannot reach %s in one hop; that is a dead end"
						% [from_id, to_id])

		# Each room's two doors must lead somewhere real, and somewhere different.
		var doors: Array = HouseLayout.doors(from_id)
		if doors.size() != 2:
			failures.append("%s has %d doors, expected 2" % [from_id, doors.size()])
		var destinations: Array = []
		for door: Dictionary in doors:
			var destination: String = String(door["toRoomId"])
			if destination == from_id:
				failures.append("%s has a door to itself" % from_id)
			if not HouseLayout.has_room(destination):
				failures.append("%s has a door to unknown room '%s'" % [from_id, destination])
			if destinations.has(destination):
				failures.append("%s has two doors to %s" % [from_id, destination])
			destinations.append(destination)
			# The spawn the door lands on must exist in the destination room.
			if not HouseLayout.spawn_points(destination).has(String(door["toSpawnId"])):
				failures.append("%s's door to %s lands on spawn '%s', which %s does not have"
						% [from_id, destination, String(door["toSpawnId"]), destination])
	return failures


## Contract §3: toddler ~0.85 m, door ~1.9 m, counter ~0.9 m, sofa seat ~0.4 m,
## rooms ~4 x 4 m. Greybox is allowed to be ugly; it is not allowed to be the
## wrong size, because every camera and framing judgement depends on this.
func _test_scale():
	var failures: Array = []
	if not is_equal_approx(ToddlerView.HEIGHT, 0.85):
		failures.append("the toddler should be 0.85 m tall, is %.2f" % ToddlerView.HEIGHT)
	if not is_equal_approx(HouseLayout.DOOR_HEIGHT, 1.9):
		failures.append("a door should be 1.9 m, is %.2f" % HouseLayout.DOOR_HEIGHT)
	if not is_equal_approx(HouseLayout.FLOOR_BOUNDS.size.x, 4.0) \
			or not is_equal_approx(HouseLayout.FLOOR_BOUNDS.size.y, 4.0):
		failures.append("rooms should be 4 x 4 m, are %s" % str(HouseLayout.FLOOR_BOUNDS.size))
	if HouseLayout.DOOR_WIDTH < 0.8:
		failures.append("a door narrower than 0.8 m is a hard tap target for a four-year-old")

	var sized: Dictionary = {"counter": 0.9, "sofa": 0.75, "table": 0.7, "fridge": 1.7}
	for room_id: String in HouseLayout.room_ids():
		for prop: Dictionary in HouseLayout.furniture(room_id):
			var target_id: String = String(prop["targetId"])
			var size: Vector3 = prop["size"]
			if sized.has(target_id) and not is_equal_approx(size.y, float(sized[target_id])):
				failures.append("the %s should be %.2f m tall, is %.2f"
						% [target_id, float(sized[target_id]), size.y])
			if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
				failures.append("%s.%s has a degenerate size %s" % [room_id, target_id, str(size)])
			# Nothing may be taller than the room.
			if size.y > HouseLayout.WALL_HEIGHT:
				failures.append("%s.%s is taller than the room" % [room_id, target_id])
	return failures


func _test_no_runtime_baking():
	var failures: Array = []
	for path: String in SHIPPED_HOUSE_SCRIPTS:
		var source: String = _read(path)
		if source.is_empty():
			failures.append("could not read %s" % path)
			continue
		for call_name: String in RUNTIME_BAKE_CALLS:
			if source.contains(call_name):
				failures.append("%s calls %s; navigation must be baked offline by "
						% [path, call_name] + "tools/bake_navmesh.gd, never at runtime")
	return failures


## The committed, inspectable navigation meshes (contract §5).
func _test_baked_navmesh_resources():
	var failures: Array = []
	for room_id: String in HouseLayout.room_ids():
		var path: String = HouseLayout.navmesh_path(room_id)
		if not path.ends_with(".tres"):
			failures.append("%s is not a text resource; a baked mesh must be diffable" % path)
		if not FileAccess.file_exists(path):
			failures.append("no baked navigation mesh at %s; run tools/bake_navmesh.gd" % path)
			continue
		var resource: Resource = load(path)
		if not (resource is NavigationMesh):
			failures.append("%s is not a NavigationMesh" % path)
			continue
		var mesh: NavigationMesh = resource as NavigationMesh
		if mesh.get_polygon_count() < 8:
			failures.append("%s has only %d polygons; the room is not walkable"
					% [path, mesh.get_polygon_count()])
		if not is_equal_approx(mesh.agent_radius, HouseLayout.NAV_AGENT_RADIUS):
			failures.append("%s was baked with agent radius %.2f, the layout says %.2f"
					% [path, mesh.agent_radius, HouseLayout.NAV_AGENT_RADIUS])
		# Floor-level polygons only: a walkable island on top of a wardrobe is a
		# place a toddler cannot reach and must not be in the committed mesh.
		for vertex: Vector3 in mesh.get_vertices():
			if absf(vertex.y - HouseLayout.FLOOR_Y) > 0.3:
				failures.append("%s contains geometry %.2f m off the floor" % [path, vertex.y])
				break
	return failures


## The check the inverted-pitch bug would have failed: the fallback framing must
## look DOWN at the room from above it, and fit the whole room on every screen
## the game ships on.
func _test_camera_framing_fits_every_screen():
	var failures: Array = []
	for room_id: String in HouseLayout.room_ids():
		var framing: Dictionary = HouseLayout.camera_framing(room_id)
		for key: String in ["bounds", "focus", "angle", "minDistance", "maxDistance"]:
			if not framing.has(key):
				failures.append("%s's camera framing has no '%s'" % [room_id, key])
		var bounds: Rect2 = framing["bounds"]
		if not bounds.encloses(HouseLayout.world_floor_bounds(room_id)):
			failures.append("%s's framing bounds do not contain its floor" % room_id)

		for aspect: float in ASPECT_RATIOS:
			var distance: float = RoomFraming.fit_distance(framing, aspect, 55.0)
			var position: Vector3 = RoomFraming.camera_position(framing, distance)
			if position.y <= HouseLayout.FLOOR_Y:
				failures.append("%s: the camera is not above the floor at aspect %.2f"
						% [room_id, aspect])
			var forward: Vector3 = (Vector3(framing["focus"]) - position).normalized()
			if forward.y >= 0.0:
				failures.append("%s: the camera is pitched upwards at aspect %.2f; every "
						% [room_id, aspect] + "object would be off screen")
			if distance >= float(framing["maxDistance"]):
				failures.append("%s: no distance frames the room at aspect %.2f"
						% [room_id, aspect])
	return failures


## -- Instantiated checks -------------------------------------------------------

func _test_structure(world: Node):
	var failures: Array = []
	var expected: Dictionary = {
		"WorldCamera": "Camera3D",
		"Navigation": "Node3D",
		"Rooms": "Node3D",
		"LittleBuddy": "CharacterBody3D",
		"NavigationController": "Node3D",
		"RoomTransitionController": "Node",
	}
	for node_name: String in expected.keys():
		var node: Node = world.get_node_or_null(node_name)
		if node == null:
			failures.append("HouseWorld has no %s" % node_name)
			continue
		if not node.is_class(String(expected[node_name])):
			failures.append("%s should be a %s, is a %s"
					% [node_name, String(expected[node_name]), node.get_class()])

	# The performance budget, as a test: one camera, one light, one environment.
	var text: String = _read(SCENE_PATH)
	for single: String in ["Camera3D", "DirectionalLight3D", "WorldEnvironment"]:
		if text.count('type="%s"' % single) != 1:
			failures.append("expected exactly one %s in the house scene" % single)
	for banned: String in ["OmniLight3D", "SpotLight3D", "GPUParticles3D", "RigidBody3D"]:
		if text.contains('type="%s"' % banned):
			failures.append("the house must not contain a %s (performance budget)" % banned)
	return failures


func _test_rooms(world: Node):
	var failures: Array = []
	var ids: Array = world.call("get_room_ids")
	var expected: Array = REQUIRED_TARGETS.keys()
	expected.sort()
	if ids != expected:
		failures.append("HouseWorld should contain exactly %s, contains %s"
				% [str(expected), str(ids)])

	var seen: Array = []
	for room_id: String in ids:
		if seen.has(room_id):
			failures.append("duplicate room id '%s'" % room_id)
		seen.append(room_id)
		var room: Node = world.call("get_room", room_id)
		if room == null:
			failures.append("no room node for '%s'" % room_id)
			continue
		for method: String in [
			"get_room_id", "get_floor_bounds", "get_floor_y", "get_spawn_points",
			"get_spawn_position", "get_activity_targets", "get_camera_framing", "get_doors",
		]:
			if not room.has_method(method):
				failures.append("%s does not implement the room contract's %s()"
						% [room_id, method])
		if String(room.call("get_room_id")) != room_id:
			failures.append("%s reports the wrong room id" % room_id)
		# The room must really be where the layout says, or its baked navigation
		# mesh is in the wrong place.
		var origin: Vector3 = SpatialUtil.world_transform(room as Node3D).origin
		if not NavMath.is_within(origin, HouseLayout.room_origin(room_id), 0.01):
			failures.append("%s is at %s, the layout says %s"
					% [room_id, str(origin), str(HouseLayout.room_origin(room_id))])
		# Rooms must not overlap, or their navigation meshes could connect.
		for other_id: String in ids:
			if other_id == room_id:
				continue
			if HouseLayout.world_floor_bounds(room_id).intersects(
				HouseLayout.world_floor_bounds(other_id)
			):
				failures.append("%s overlaps %s" % [room_id, other_id])
	return failures


func _test_targets(world: Node):
	var failures: Array = []
	var global_ids: Array = []
	for room_id: String in world.call("get_room_ids"):
		var room: Node = world.call("get_room", room_id)
		var local_ids: Array = []
		for target: Node in room.call("get_activity_targets"):
			var local: String = _local_id(target)
			if local_ids.has(local):
				failures.append("%s has two targets called '%s'" % [room_id, local])
			local_ids.append(local)

			var semantic: String = _semantic_id(target, room_id)
			if global_ids.has(semantic):
				failures.append("duplicate semantic id '%s'" % semantic)
			global_ids.append(semantic)
			if semantic != "%s.%s" % [room_id, local]:
				failures.append("'%s' should address as '%s.%s'" % [semantic, room_id, local])

			# Contract §7: targets live on collision layer 2, alone.
			if int(target.get("collision_layer")) != 2:
				failures.append("%s is on collision layer %d, must be 2"
						% [semantic, int(target.get("collision_layer"))])
			if not bool(target.call("has_interaction_point")):
				failures.append("%s has no InteractionPoint; where does the child stand?"
						% semantic)
			# The stand position must be inside the room, not inside a wall.
			var described: Dictionary = target.call("describe", Vector3.ZERO)
			var stand: Vector3 = described.get("standPosition", Vector3.ZERO)
			var walkable: Rect2 = HouseLayout.world_floor_bounds(room_id).grow(
				-HouseLayout.NAV_AGENT_RADIUS
			)
			if not walkable.has_point(Vector2(stand.x, stand.z)):
				failures.append("%s's stand position %s is outside the walkable floor"
						% [semantic, str(stand)])
			if world.call("get_target_by_semantic_id", semantic) != target:
				failures.append("%s cannot be looked up by its semantic id" % semantic)

		for required: String in REQUIRED_TARGETS[room_id]:
			if not local_ids.has(required):
				failures.append("%s is missing its required '%s' target" % [room_id, required])
		# 3 furniture + 2 doors + however many CONTAINERS the room declares.
		#
		# The bare 5 was right while every room was furniture-plus-doors. The tidy
		# activity added a third kind of target -- a toy box, a shelf -- and it is
		# declared in `HouseLayout.storages()` per room, so the expected count is
		# derived from the layout rather than restated here. Hardcoding 5 would
		# have meant either no containers or a test that stopped describing the
		# rooms.
		# 3 furniture + 2 doors + containers + INHABITANTS. Little Buddy registers
		# its own target so a mission can say "go to the child"; deriving the
		# count keeps this test describing the room rather than freezing it.
		var inhabitants: int = 0
		for child: Node in room.get_children():
			if child.has_method("get_activity_target") and child.call("get_activity_target") != null:
				inhabitants += 1
		var expected_targets: int = 5 + HouseLayout.storages(room_id).size() + inhabitants
		if local_ids.size() != expected_targets:
			failures.append("%s has %d targets, expected 3 furniture + 2 doors + %d container(s) + %d inhabitant(s)"
					% [room_id, local_ids.size(), HouseLayout.storages(room_id).size(), inhabitants])

	var problems: Array = world.call("get_target_problems")
	if not problems.is_empty():
		failures.append("the target registry reported %s" % str(problems))
	return failures


func _test_spawns(world: Node):
	var failures: Array = []
	for room_id: String in world.call("get_room_ids"):
		var room: Node = world.call("get_room", room_id)
		var spawns: Dictionary = room.call("get_spawn_points")
		if not spawns.has("default"):
			failures.append("%s has no safe default spawn point" % room_id)
		if spawns.size() < 3:
			failures.append("%s has %d spawn points; it needs one per door plus a default"
					% [room_id, spawns.size()])
		var walkable: Rect2 = HouseLayout.world_floor_bounds(room_id).grow(
			-HouseLayout.NAV_AGENT_RADIUS
		)
		for spawn_id: String in spawns.keys():
			var point: Vector3 = spawns[spawn_id]
			if not walkable.has_point(Vector2(point.x, point.z)):
				failures.append("%s's '%s' spawn %s is not on the walkable floor"
						% [room_id, spawn_id, str(point)])
		# An unknown spawn id falls back to this room's default, never to nowhere.
		var fallback: Vector3 = room.call("get_spawn_position", "noSuchSpawn")
		if not NavMath.is_within(fallback, spawns["default"], 0.01):
			failures.append("%s's unknown-spawn fallback is %s, not its default"
					% [room_id, str(fallback)])
	return failures


func _test_navigation_regions(world: Node):
	var failures: Array = []
	var navigation: Node = world.get_node_or_null("Navigation")
	if navigation == null:
		return ["HouseWorld has no Navigation node"]
	var regions: Array = []
	for child: Node in navigation.get_children():
		if child is NavigationRegion3D:
			regions.append(child)
	if regions.size() != world.call("get_room_ids").size():
		failures.append("expected one navigation region per room, found %d" % regions.size())
	for region: NavigationRegion3D in regions:
		if region.navigation_mesh == null:
			failures.append("%s has no navigation mesh" % region.name)
			continue
		if region.navigation_mesh.get_polygon_count() < 8:
			failures.append("%s's navigation mesh is empty" % region.name)
	var map: RID = world.call("get_navigation_map")
	if not map.is_valid():
		failures.append("the house owns no navigation map")
	return failures


func _test_character(world: Node):
	var failures: Array = []
	var character: Node = world.call("get_character")
	if character == null:
		return ["HouseWorld has no LittleBuddy"]
	if character.get_node_or_null("NavigationAgent3D") == null:
		failures.append("the character has no NavigationAgent3D")
	if character.get_node_or_null("CollisionShape3D") == null:
		failures.append("the character has no collision shape")

	# The semantic action API, intact and unforked: the same character script the
	# spike proved, driven only by semantic names.
	for method: String in [
		"move_to", "move_to_ground", "play_action", "stop", "is_busy", "get_state_name",
		"set_disabled", "register_activity_target",
	]:
		if not character.has_method(method):
			failures.append("the character lost %s(); the spike's movement API was forked"
					% method)

	var view: Node = character.get_node_or_null("ToddlerView")
	if view == null:
		failures.append("the character has no toddler placeholder view")
	else:
		view.call("build")
		for action: String in ["idle", "walk"]:
			if not bool(character.call("can_play_action", action)):
				failures.append("the character cannot play '%s'; the animation seam is not "
						% action + "bound to the toddler view")
		if bool(character.call("can_play_action", "brushTeeth")):
			failures.append("'brushTeeth' is not animated yet and must not claim to be")

	if String(character.call("get_state_name")) != "idle":
		failures.append("the child should start idle, is '%s'"
				% String(character.call("get_state_name")))
	return failures


## -- Helpers -------------------------------------------------------------------

func _instantiate(tree: SceneTree) -> Node:
	var packed: Resource = load(SCENE_PATH)
	if packed == null or not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	if world == null:
		return null
	tree.root.add_child(world)
	# The headless runner never fires `_ready()`; the whole world is built there.
	world.call("_ready")
	return world


func _local_id(target: Node) -> String:
	if target.has_method("get_local_target_id"):
		return String(target.call("get_local_target_id"))
	return String(target.call("get_activity_target_id"))


func _semantic_id(target: Node, room_id: String) -> String:
	if target.has_method("get_semantic_id"):
		return String(target.call("get_semantic_id"))
	return HouseLayout.semantic_id(room_id, String(target.call("get_activity_target_id")))


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
