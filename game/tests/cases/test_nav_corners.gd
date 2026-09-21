extends RefCounted

## Taps around the furniture never leave Aliz walking into it.
##
## Owner report (2026-09-21, real device): "clicking near furniture or at an
## obstructed angle makes Aliz walk into the obstacle and get stuck". This drives
## the REAL house -- baked meshes, real colliders, `move_and_slide()` -- with
## synthetic floor taps at eight points round each piece of furniture the report
## names (bed, wardrobe, bath, table, fridge, both toy boxes) and round every
## doorway, plus one tap in the middle of each footprint. Every tap must end
## within a time budget in exactly one of two ways:
##
##   * she ARRIVES: at rest, within tolerance of the nearest walkable point to
##     the tap (which is where a tap inside a footprint is projected to);
##   * or the walk is REFUSED or GIVEN UP with `move_failed`, at rest.
##
## Either way she is never left busy, never inside a collider, never off the
## mesh, and never still pushing at a wardrobe when the budget runs out.
##
## One more case with a deliberately bad provider (a straight line through the
## bed) proves the no-progress guard: a body blocked by furniture re-paths once
## and then gives up cleanly, rather than pressing against it forever.
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")
const NavigationProviderScript := preload("res://scripts/navigation/navigation_provider.gd")

const DT: float = 1.0 / 60.0
## 10 seconds of frames. A 4 m room crosses in under 4 s at walking pace.
const BUDGET_FRAMES: int = 600
## How far outside a footprint the ring of taps sits.
const RING_GAP: float = 0.10
## How close to the projected destination counts as arrived. The arrival radius
## is 0.18; the body can stop up to its clearance short of the mesh edge.
const ARRIVE_TOLERANCE: float = 0.30
const ON_MESH_TOLERANCE: float = 0.06
const TAP_FLOOR: int = 2

## What the report names, by room and local id. Storage rows are targets too.
const SUBJECTS: Dictionary = {
	"bedroom": ["bed", "wardrobe", "toyBox"],
	"bathroom": ["bath"],
	"kitchen": ["table", "fridge"],
	"livingRoom": ["toyBox"],
}


func test_name() -> String:
	return "nav_corners"


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
		for room_id: String in SUBJECTS.keys():
			for local_id: String in SUBJECTS[room_id]:
				failures.append_array(_test_ring(world, provider, room_id, local_id))
		for room_id: String in HouseLayout.room_ids():
			failures.append_array(_test_doorways(world, provider, room_id))
		failures.append_array(_test_blocked_walk_gives_up(world, provider))

	tree.root.remove_child(world)
	world.free()
	return failures


## Eight taps round `local_id` and one in the middle of it.
func _test_ring(world: Node, provider: RefCounted, room_id: String, local_id: String):
	var failures: Array = []
	var box: Dictionary = _box_of(room_id, local_id)
	if box.is_empty():
		return ["%s.%s: not in the layout" % [room_id, local_id]]
	var origin: Vector3 = HouseLayout.room_origin(room_id)
	var centre: Vector3 = origin + (box["position"] as Vector3)
	var size: Vector3 = box["size"]
	var points: Array = [Vector3(centre.x, HouseLayout.FLOOR_Y, centre.z)]
	for dx: int in [-1, 0, 1]:
		for dz: int in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			points.append(Vector3(
				centre.x + float(dx) * (size.x * 0.5 + RING_GAP),
				HouseLayout.FLOOR_Y,
				centre.z + float(dz) * (size.z * 0.5 + RING_GAP)
			))
	for point: Vector3 in points:
		failures.append_array(_tap_and_judge(world, provider, room_id, point,
				"%s.%s" % [room_id, local_id]))
	return failures


## Taps on and round both door slabs: the slab itself (in the wall), the stand
## point, and the floor either side of the opening.
func _test_doorways(world: Node, provider: RefCounted, room_id: String):
	var failures: Array = []
	var origin: Vector3 = HouseLayout.room_origin(room_id)
	for door: Dictionary in HouseLayout.doors(room_id):
		var slab: Vector3 = origin + (door["position"] as Vector3)
		var side: float = float(door["side"])
		var points: Array = [
			Vector3(slab.x, HouseLayout.FLOOR_Y, slab.z),
			Vector3(slab.x - side * 0.25, HouseLayout.FLOOR_Y, slab.z),
			Vector3(slab.x - side * 0.25, HouseLayout.FLOOR_Y, slab.z + 0.55),
			Vector3(slab.x - side * 0.25, HouseLayout.FLOOR_Y, slab.z - 0.55),
			Vector3(slab.x - side * 0.25, HouseLayout.FLOOR_Y, slab.z + 1.0),
			Vector3(slab.x + side * 0.4, HouseLayout.FLOOR_Y, slab.z),
			Vector3(slab.x - side * 0.05, HouseLayout.FLOOR_Y, slab.z - 0.9),
			Vector3(slab.x - side * 0.05, HouseLayout.FLOOR_Y, slab.z + 1.3),
		]
		for point: Vector3 in points:
			failures.append_array(_tap_and_judge(world, provider, room_id, point,
					"%s.%s" % [room_id, String(door["targetId"])]))
	return failures


## A provider that ignores the mesh sends her straight through the bed, and the
## bed's +X face holds her exactly as the physics body would on a device (the
## headless runner steps no physics, so the collider is played by hand: any
## step that crosses the face is put back on it). The walk must end on its own,
## cleanly, inside the budget -- one re-path, then `blocked`, then rest.
func _test_blocked_walk_gives_up(world: Node, provider: RefCounted):
	var failures: Array = []
	var aliz: Node3D = world.call("get_character")
	var nav: Node = world.get_node("NavigationController")
	world.call("place_in_room", "bedroom", HouseLayout.DEFAULT_SPAWN)
	var origin: Vector3 = HouseLayout.room_origin("bedroom")
	# Directly in front of the bed's +X face, then a destination on its far side.
	var start: Vector3 = origin + Vector3(HouseLayout.BED_STAND_X + 0.15, HouseLayout.FLOOR_Y, HouseLayout.BED_POSITION.z)
	var beyond: Vector3 = origin + Vector3(HouseLayout.BED_POSITION.x - 0.30, HouseLayout.FLOOR_Y, HouseLayout.BED_POSITION.z)
	var face_x: float = origin.x + HouseLayout.BED_POSITION.x + HouseLayout.BED_SIZE.x * 0.5 + 0.22
	SpatialUtil.set_world_position(aliz, start)
	aliz.call("stop")
	aliz.call("set_navigation_provider", NavigationProviderScript.new())

	var failed: Array = []
	var handler: Callable = func(_id: String, reason: String) -> void: failed.append(reason)
	aliz.connect("move_failed", handler)
	var accepted: bool = bool(nav.call("apply_tap",
			{"kind": TAP_FLOOR, "targetId": "", "x": beyond.x, "z": beyond.z, "reason": ""}))
	if not accepted:
		failures.append("blocked: the straight-line provider refused a walk it should have started")
	var frames: int = BUDGET_FRAMES
	for frame: int in range(BUDGET_FRAMES):
		aliz.call("step_movement", DT)
		var p: Vector3 = SpatialUtil.world_position(aliz)
		if p.x < face_x:
			SpatialUtil.set_world_position(aliz, Vector3(face_x, p.y, p.z))
		if not bool(aliz.call("is_busy")):
			frames = frame + 1
			break
	aliz.disconnect("move_failed", handler)
	aliz.call("set_navigation_provider", provider)

	var here: Vector3 = SpatialUtil.world_position(aliz)
	if frames >= BUDGET_FRAMES:
		failures.append("blocked: still walking into the bed after %d frames (at %s, state %s)"
				% [frames, _fmt(here), aliz.call("get_state_name")])
	elif frames > 90:
		failures.append("blocked: it took %d frames (%.2f s) to give up; a child watches every one"
				% [frames, float(frames) * DT])
	if failed != ["blocked"]:
		failures.append("blocked: expected exactly one move_failed 'blocked', got %s" % str(failed))
	if bool(aliz.call("is_busy")):
		failures.append("blocked: Aliz is still busy after giving up")
	# The destination disc was let go: a released disc fades out in a quarter
	# second, a disc still promising a destination holds for ever. The headless
	# runner has no frames, so the fade is ticked by hand.
	var ripple: Node = nav.call("get_tap_ripple")
	if ripple != null and ripple.has_method("is_holding"):
		ripple.call("advance", 1.0)
		if bool(ripple.call("is_holding")):
			failures.append("blocked: the destination disc is still on the floor after giving up")
	if here.x < origin.x + HouseLayout.BED_POSITION.x + HouseLayout.BED_SIZE.x * 0.5:
		failures.append("blocked: she ended inside the bed's footprint at %s" % _fmt(here))
	# Standing still afterwards: no residual push, no jitter.
	var rest: Vector3 = SpatialUtil.world_position(aliz)
	for _frame: int in range(60):
		aliz.call("step_movement", DT)
	if NavMath.flat_distance(SpatialUtil.world_position(aliz), rest) > 0.01:
		failures.append("blocked: she kept moving after the walk was given up")
	return failures


## -- One tap, judged ---------------------------------------------------------------

func _tap_and_judge(world: Node, provider: RefCounted, room_id: String, tap: Vector3, label: String):
	var failures: Array = []
	var aliz: Node3D = world.call("get_character")
	var nav: Node = world.get_node("NavigationController")
	world.call("place_in_room", room_id, HouseLayout.DEFAULT_SPAWN)
	aliz.call("stop")

	var failed: Array = []
	var arrivals: Array = []
	var fail_handler: Callable = func(_id: String, reason: String) -> void: failed.append(reason)
	var arrive_handler: Callable = func(_id: String) -> void: arrivals.append(_id)
	aliz.connect("move_failed", fail_handler)
	aliz.connect("arrived", arrive_handler)

	var accepted: bool = bool(nav.call("apply_tap",
			{"kind": TAP_FLOOR, "targetId": "", "x": tap.x, "z": tap.z, "reason": ""}))
	var frames: int = _pump_until_idle(aliz, BUDGET_FRAMES)
	aliz.disconnect("move_failed", fail_handler)
	aliz.disconnect("arrived", arrive_handler)

	var here: Vector3 = SpatialUtil.world_position(aliz)
	var wanted: Vector3 = provider.call("snap_to_navigable", tap)
	var tag: String = "%s tap %s" % [label, _fmt(tap)]

	if frames >= BUDGET_FRAMES:
		failures.append("%s: still %s after %d frames at %s, %.2f m from the destination %s"
				% [tag, aliz.call("get_state_name"), frames, _fmt(here),
				NavMath.flat_distance(here, wanted), _fmt(wanted)])
		return failures
	if bool(aliz.call("is_busy")):
		failures.append("%s: busy (%s) after the walk ended" % [tag, aliz.call("get_state_name")])
	if accepted:
		if arrivals.is_empty() and failed.is_empty():
			failures.append("%s: the walk ended with neither an arrival nor a move_failed" % tag)
		if not arrivals.is_empty() and NavMath.flat_distance(here, wanted) > ARRIVE_TOLERANCE:
			failures.append("%s: arrived %.2f m from the nearest walkable point %s (at %s)"
					% [tag, NavMath.flat_distance(here, wanted), _fmt(wanted), _fmt(here)])
	elif failed.is_empty():
		failures.append("%s: the tap was refused without a move_failed" % tag)

	var snapped: Vector3 = provider.call("snap_to_navigable", here)
	if NavMath.flat_distance(snapped, here) > ON_MESH_TOLERANCE:
		failures.append("%s: ended %.2f m off the mesh at %s"
				% [tag, NavMath.flat_distance(snapped, here), _fmt(here)])
	var room: Node = world.call("get_room", room_id)
	for box: Dictionary in _solid_boxes(room):
		var rect: Rect2 = box["rect"]
		if rect.grow(-0.005).has_point(Vector2(here.x, here.z)):
			failures.append("%s: ended INSIDE collider '%s' at %s" % [tag, String(box["name"]), _fmt(here)])
	return failures


## -- Helpers ---------------------------------------------------------------------------

func _pump_until_idle(aliz: Node, budget: int) -> int:
	for frame: int in range(budget):
		aliz.call("step_movement", DT)
		if not bool(aliz.call("is_busy")):
			return frame + 1
	return budget


func _box_of(room_id: String, local_id: String) -> Dictionary:
	for prop: Dictionary in HouseLayout.furniture(room_id):
		if String(prop["targetId"]) == local_id:
			return prop
	for row: Dictionary in HouseLayout.storages(room_id):
		if String(row["storageId"]) == local_id:
			return row
	return {}


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
