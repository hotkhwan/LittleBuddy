extends RefCounted

## Every interaction anchor in the house is somewhere Aliz can really stand.
##
## Owner report (2026-09-21, real device): "walking + interaction must complete
## for cabinet/wardrobe, bed, bathtub, fridge, toy box, feeding table". A target
## whose stand point is off the navigation mesh, inside the eroded margin round
## its own collider, or unreachable from where the child spawns, is a walk that
## ends pressed against furniture -- and `test_freeplay_acts.gd`'s `_arrive()`
## TELEPORTS to the stand point, so none of that showed up in the suite.
##
## For every room, every `ActivityTarget` (furniture, storage, doors) and every
## spawn point, on the REAL baked meshes and the REAL colliders:
##
##   1. the stand point is ON the mesh (its nearest navigable point is itself);
##   2. it is reachable from the room's default spawn and every arrival spawn;
##   3. it is clear of every solid collider by at least the body's radius;
##   4. it faces the object (the facing point lies in the object's footprint).
##
## And the one number underneath all of it: the mesh is eroded by at least the
## body's capsule radius plus a little, or the path can be legal and the body
## still scrape.
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")

## How far a stand point may sit from its own nearest navigable point and still
## count as "on the mesh". Under one bake cell.
const ON_MESH_TOLERANCE: float = 0.04
## How close a path's end must come to the stand point to count as reaching it.
const REACH_TOLERANCE: float = 0.05
## The margin the erosion must hold over the body's capsule radius.
const BODY_CLEARANCE: float = 0.02
## How far the facing point may lie outside the object's own footprint.
const FACING_SLACK: float = 0.12


func test_name() -> String:
	return "interaction_anchors"


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var world: Node = _instantiate(tree)
	if world == null:
		return ["could not instantiate %s" % SCENE_PATH]

	var provider: RefCounted = NavMapProviderScript.create(world.call("get_navigation_map"))
	if not bool(provider.call("force_sync", Vector3.ZERO)):
		failures.append("the house navigation map never answered a query")
	else:
		var body_radius: float = _body_radius(world.call("get_character"))
		failures.append_array(_test_margin_covers_the_body(body_radius))
		for room_id: String in HouseLayout.room_ids():
			failures.append_array(_test_room_anchors(world, provider, room_id, body_radius))

	tree.root.remove_child(world)
	world.free()
	return failures


## The erosion radius is what keeps a legal path off the furniture. If the body
## is fatter than the margin, every corner waypoint is a scrape.
func _test_margin_covers_the_body(body_radius: float):
	var failures: Array = []
	if body_radius <= 0.0:
		return ["the character has no capsule collider to measure"]
	if HouseLayout.NAV_AGENT_RADIUS < body_radius + BODY_CLEARANCE:
		failures.append("NAV_AGENT_RADIUS %.2f is not at least the body radius %.2f + %.2f; "
				% [HouseLayout.NAV_AGENT_RADIUS, body_radius, BODY_CLEARANCE]
				+ "a path hugging a corner puts the body inside the furniture")
	return failures


func _test_room_anchors(world: Node, provider: RefCounted, room_id: String, body_radius: float):
	var failures: Array = []
	world.call("place_in_room", room_id, HouseLayout.DEFAULT_SPAWN)
	var room: Node = world.call("get_room", room_id)
	if room == null:
		return ["%s: no room node" % room_id]
	var boxes: Array = _solid_boxes(room)
	if boxes.is_empty():
		return ["%s: no solid colliders were found under the room" % room_id]
	var spawns: Dictionary = room.call("get_spawn_points")
	var default_spawn: Vector3 = spawns.get(HouseLayout.DEFAULT_SPAWN, Vector3.ZERO)

	# The spawn points themselves must be standable, or the first frame in a
	# room already has the child in a wall.
	for spawn_id: String in spawns.keys():
		var spawn: Vector3 = spawns[spawn_id]
		var label: String = "%s spawn '%s'" % [room_id, spawn_id]
		failures.append_array(_expect_on_mesh(provider, spawn, label))
		failures.append_array(_expect_clear(boxes, spawn, body_radius, label))

	var expected: int = HouseLayout.furniture(room_id).size() \
			+ HouseLayout.storages(room_id).size() + HouseLayout.doors(room_id).size()
	var targets: Array = room.call("get_activity_targets")
	if targets.size() < expected:
		failures.append("%s: %d activity targets built, the layout lists %d"
				% [room_id, targets.size(), expected])

	for target: Node in targets:
		if not target.has_method("describe"):
			continue
		var info: Dictionary = target.call("describe", default_spawn)
		var id: String = String(info.get("targetId", target.name))
		var stand: Vector3 = info.get("standPosition", Vector3.ZERO)
		var face: Vector3 = info.get("facePosition", stand)

		failures.append_array(_expect_on_mesh(provider, stand, id))
		failures.append_array(_expect_clear(boxes, stand, body_radius, id))
		for spawn_id: String in spawns.keys():
			var path: PackedVector3Array = provider.call("query_path", spawns[spawn_id], stand)
			if not NavMath.path_reaches(path, stand, REACH_TOLERANCE):
				failures.append("%s: stand point %s is not reachable from spawn '%s' (path ends %.2f m short)"
						% [id, _fmt(stand), spawn_id,
						NavMath.flat_distance(NavMath.path_endpoint(path, spawns[spawn_id]), stand)])
		# Facing: the point she turns to must be the object, not the room.
		if NavMath.flat_distance(face, stand) < 0.05:
			failures.append("%s: the facing point is on top of the stand point" % id)
		var footprint: Rect2 = _target_footprint(target)
		if footprint.size.x > 0.0 and not footprint.grow(FACING_SLACK).has_point(Vector2(face.x, face.z)):
			failures.append("%s: the facing point %s is outside the object's footprint %s"
					% [id, _fmt(face), str(footprint)])
	return failures


## -- Expectations ----------------------------------------------------------------

func _expect_on_mesh(provider: RefCounted, point: Vector3, label: String):
	var failures: Array = []
	var snapped: Vector3 = provider.call("snap_to_navigable", point)
	var off: float = NavMath.flat_distance(snapped, point)
	if off > ON_MESH_TOLERANCE:
		failures.append("%s: point %s is %.2f m off the navigation mesh (nearest %s)"
				% [label, _fmt(point), off, _fmt(snapped)])
	return failures


func _expect_clear(boxes: Array, point: Vector3, body_radius: float, label: String):
	var failures: Array = []
	for box: Dictionary in boxes:
		var rect: Rect2 = box["rect"]
		var gap: float = _rect_distance(rect, Vector2(point.x, point.z))
		if gap < body_radius - 0.005:
			failures.append("%s: point %s is %.2f m from collider '%s' (%s); the body needs %.2f"
					% [label, _fmt(point), gap, String(box["name"]), str(rect), body_radius])
	return failures


## -- Geometry ---------------------------------------------------------------------

## Every solid, above-floor box collider on the house layer under `root`, as
## world-space XZ rectangles. The floor slab (its top at the floor) is skipped:
## the child stands on it, not against it.
func _solid_boxes(root: Node) -> Array:
	var found: Array = []
	_collect_boxes(root, found)
	return found


func _collect_boxes(node: Node, found: Array) -> void:
	if node is StaticBody3D and ((node as StaticBody3D).collision_layer & HouseLayout.HOUSE_GEOMETRY_LAYER) != 0:
		for child: Node in node.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
				var size: Vector3 = ((child as CollisionShape3D).shape as BoxShape3D).size
				var centre: Vector3 = SpatialUtil.world_position(child as Node3D)
				if centre.y + size.y * 0.5 <= HouseLayout.FLOOR_Y + 0.02:
					continue
				found.append({
					"name": node.name,
					"rect": Rect2(centre.x - size.x * 0.5, centre.z - size.z * 0.5, size.x, size.z),
				})
	for child: Node in node.get_children():
		_collect_boxes(child, found)


## The target's tap box on the floor plane, world space.
func _target_footprint(target: Node) -> Rect2:
	if not (target is Node3D):
		return Rect2()
	for child: Node in target.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var size: Vector3 = ((child as CollisionShape3D).shape as BoxShape3D).size
			var centre: Vector3 = SpatialUtil.world_position(child as Node3D)
			return Rect2(centre.x - size.x * 0.5, centre.z - size.z * 0.5, size.x, size.z)
	return Rect2()


static func _rect_distance(rect: Rect2, point: Vector2) -> float:
	var dx: float = maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy: float = maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return Vector2(dx, dy).length()


func _body_radius(character: Node) -> float:
	if character == null:
		return 0.0
	for child: Node in character.get_children():
		if child is CollisionShape3D:
			var shape: Shape3D = (child as CollisionShape3D).shape
			if shape is CapsuleShape3D:
				return (shape as CapsuleShape3D).radius
			if shape is CylinderShape3D:
				return (shape as CylinderShape3D).radius
			if shape is SphereShape3D:
				return (shape as SphereShape3D).radius
	return 0.0


static func _fmt(v: Vector3) -> String:
	return "(%.2f, %.2f)" % [v.x, v.z]


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
