extends Node3D

## One greybox room of the house: floor, walls, two doors, three activity targets
## and a set of semantic spawn points.
##
## The whole room is BUILT FROM `house_layout.gd`, not hand-placed in the .tscn.
## The visible box, the collision box and the box the navigation bake sees are
## therefore the same numbers -- which is the only way "the wall the child can see"
## and "the wall the navigation mesh knows about" can be guaranteed not to drift.
##
## Greybox means correct scale, collision, navigation and obvious room identity.
## The materials are flat colours and are meant to be thrown away: when the art
## pipeline delivers real rooms, they replace `_build_*()` below and nothing in
## `house_world.gd`, `room_transition_controller.gd` or the content layer changes,
## because every one of them addresses this room only by semantic id.
##
## ## Lazy wiring
##
## `build()` is idempotent and is called from every public method, because the
## headless `--script` test runner never fires `_ready()` for nodes added to the
## root -- the same rule `activity_target.gd` and `little_buddy_character.gd`
## already follow.

const HouseLayout := preload("res://scripts/house/house_layout.gd")
const ActivityTargetScript := preload("res://scripts/navigation/activity_target.gd")
const InteractionPointScript := preload("res://scripts/navigation/interaction_point.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## Which room this is: "bedroom", "bathroom", "kitchen" or "livingRoom".
@export var room_id: String = HouseLayout.BEDROOM

var _built: bool = false
var _targets: Array = []
var _doors_by_target: Dictionary = {}
var _geometry: Node3D = null
var _target_root: Node3D = null


func _ready() -> void:
	build()


## -- Room contract (§3) --------------------------------------------------------

func get_room_id() -> String:
	return room_id


## Walkable extent in world XZ. The floor edge, not the wall, because the walls
## sit entirely outside the floor so every side is bounded identically.
func get_floor_bounds() -> Rect2:
	return HouseLayout.world_floor_bounds(room_id)


func get_floor_y() -> float:
	build()
	return HouseLayout.FLOOR_Y + position.y


## `{spawnId: Vector3}` in WORLD space. Always contains "default".
func get_spawn_points() -> Dictionary:
	build()
	var local_points: Dictionary = HouseLayout.spawn_points(room_id)
	var world_points: Dictionary = {}
	for spawn_id: String in local_points.keys():
		world_points[spawn_id] = _to_world(local_points[spawn_id])
	return world_points


## Where to put the child for `spawn_id`. An unknown spawn id falls back to this
## room's "default" rather than to the origin -- a coordinate that does not exist
## must never strand a child outside the navigation mesh.
func get_spawn_position(spawn_id: String) -> Vector3:
	build()
	var points: Dictionary = HouseLayout.spawn_points(room_id)
	if points.has(spawn_id):
		return _to_world(points[spawn_id])
	return _to_world(points.get(HouseLayout.DEFAULT_SPAWN, Vector3(0.0, HouseLayout.FLOOR_Y, 0.0)))


func has_spawn_point(spawn_id: String) -> bool:
	return HouseLayout.spawn_points(room_id).has(spawn_id)


## The room's `ActivityTarget` nodes -- furniture AND doors. They live inside the
## room, never in a global bucket, so a room is self-contained.
func get_activity_targets() -> Array:
	build()
	return _targets.duplicate()


## Accepts either half of the address: `"bed"` or `"bedroom.bed"`. The
## `ActivityTarget` contract reports `get_activity_target_id()` as the SEMANTIC
## id, so a caller holding only the local half would otherwise find nothing.
func get_activity_target(target_id: String) -> Node:
	build()
	for target: Node in _targets:
		for candidate: String in _ids_of(target):
			if candidate == target_id:
				return target
	return null


## Every id a target answers to: the semantic one, and the local one when the
## target is new enough to distinguish them.
func _ids_of(target: Node) -> Array:
	var ids: Array = [String(target.call("get_activity_target_id"))]
	if target.has_method("get_local_target_id"):
		var local: String = String(target.call("get_local_target_id"))
		if not ids.has(local):
			ids.append(local)
	return ids


func get_camera_framing() -> Dictionary:
	return HouseLayout.camera_framing(room_id)


## The room's doors, as plain dictionaries carrying `targetId`, `toRoomId` and
## `toSpawnId`. Strings only: the transition controller never needs a node.
func get_doors() -> Array:
	return HouseLayout.doors(room_id)


## The door reached by walking to `target_id`, or an empty Dictionary. This is
## how a tap on a door becomes a room transition.
##
## Keyed by BOTH the local id (`"doorToBathroom"`) and the semantic one
## (`"bedroom.doorToBathroom"`), because the character echoes back whichever id
## the target reports and that has already changed once this week.
func get_door_for_target(target_id: String) -> Dictionary:
	build()
	return _doors_by_target.get(target_id, {})


## -- Activation ----------------------------------------------------------------

## Shows or hides the room and, importantly, enables or disables its activity
## targets. A disabled target reports no id, so a stray tap on a room the child
## is not in can never start a walk into another room.
func set_active(active: bool) -> void:
	build()
	visible = active
	for target: Node in _targets:
		if target.has_method("set_target_enabled"):
			target.call("set_target_enabled", active)


func is_active() -> bool:
	return visible


## -- Construction --------------------------------------------------------------

## Idempotent. Safe to call before `_ready()`, which the headless runner never
## fires.
func build() -> void:
	if _built:
		return
	_built = true

	if not HouseLayout.has_room(room_id):
		# An unknown room id builds nothing rather than half a room. The world
		# refuses to enter a room it cannot find, so this is visible, not silent.
		push_warning("Room '%s' is not in the house layout; nothing was built." % room_id)
		return

	# Position comes from the layout, never from the .tscn, so the room's world
	# placement and its baked navigation mesh cannot disagree.
	position = HouseLayout.room_origin(room_id)

	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	add_child(_geometry)
	_target_root = Node3D.new()
	_target_root.name = "Targets"
	add_child(_target_root)

	_build_floor()
	_build_walls()
	_build_doors()
	_build_furniture()


func _build_floor() -> void:
	var bounds: Rect2 = HouseLayout.FLOOR_BOUNDS
	var mesh := MeshInstance3D.new()
	mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = bounds.size
	mesh.mesh = plane
	mesh.material_override = _material(HouseLayout.floor_color(room_id))
	mesh.position = Vector3(bounds.get_center().x, HouseLayout.FLOOR_Y, bounds.get_center().y)
	_geometry.add_child(mesh)

	# The collider is what the navigation mesh is baked from, so it is exactly the
	# interior floor: 4 x 4 m, top face at floor level.
	_add_collider(
		"FloorBody",
		Vector3(bounds.size.x, 0.2, bounds.size.y),
		Vector3(bounds.get_center().x, HouseLayout.FLOOR_Y - 0.1, bounds.get_center().y)
	)


## Back wall and two side walls, all OUTSIDE the floor. The front (camera-facing)
## side is deliberately open: this is a doll's-house view and a wall there would
## hide the whole room.
func _build_walls() -> void:
	var bounds: Rect2 = HouseLayout.FLOOR_BOUNDS
	var thickness: float = HouseLayout.WALL_THICKNESS
	var height: float = HouseLayout.WALL_HEIGHT
	var half_door: float = HouseLayout.DOOR_WIDTH * 0.5

	_add_box(
		"WallBack",
		Vector3(bounds.size.x + thickness * 2.0, height, thickness),
		Vector3(0.0, height * 0.5, bounds.position.y - thickness * 0.5),
		HouseLayout.WALL_COLOR
	)

	for side: int in [-1, 1]:
		var wall_x: float = float(side) * (bounds.end.x + thickness * 0.5)
		# Back segment: from the back wall up to the near edge of the doorway.
		var back_start: float = bounds.position.y - thickness
		var back_end: float = HouseLayout.DOOR_Z - half_door
		_add_box(
			"Wall%sBack" % ("Left" if side < 0 else "Right"),
			Vector3(thickness, height, back_end - back_start),
			Vector3(wall_x, height * 0.5, (back_start + back_end) * 0.5),
			HouseLayout.WALL_COLOR
		)
		# Front segment: from the far edge of the doorway to the open front.
		var front_start: float = HouseLayout.DOOR_Z + half_door
		var front_end: float = bounds.end.y
		_add_box(
			"Wall%sFront" % ("Left" if side < 0 else "Right"),
			Vector3(thickness, height, front_end - front_start),
			Vector3(wall_x, height * 0.5, (front_start + front_end) * 0.5),
			HouseLayout.WALL_COLOR
		)
		# Lintel over the doorway, so the opening reads as a door rather than as a
		# hole in the wall.
		_add_box(
			"Lintel%s" % ("Left" if side < 0 else "Right"),
			Vector3(thickness, height - HouseLayout.DOOR_HEIGHT, HouseLayout.DOOR_WIDTH),
			Vector3(
				wall_x,
				(height + HouseLayout.DOOR_HEIGHT) * 0.5,
				HouseLayout.DOOR_Z
			),
			HouseLayout.WALL_COLOR
		)


## Each door is a closed slab (so the child cannot walk through it) plus an
## `ActivityTarget` with an authored `InteractionPoint` in front of it.
func _build_doors() -> void:
	for door: Dictionary in HouseLayout.doors(room_id):
		var size := Vector3(
			HouseLayout.DOOR_THICKNESS, HouseLayout.DOOR_HEIGHT, HouseLayout.DOOR_WIDTH
		)
		var centre: Vector3 = door["position"]
		_add_box("Door_%s" % String(door["targetId"]), size, centre, HouseLayout.DOOR_COLOR)
		# A handle, purely so a child can see which side opens.
		_add_box(
			"Handle_%s" % String(door["targetId"]),
			Vector3(0.06, 0.08, 0.16),
			centre + Vector3(0.0, -0.05, -float(door["side"]) * 0.28),
			Color(0.95, 0.88, 0.5),
			false
		)
		var target: Node = _add_target(
			String(door["targetId"]),
			String(door["displayName"]),
			size + Vector3(0.2, 0.0, 0.0),
			centre,
			door["stand"] as Vector3,
			["open", "goThrough"]
		)
		# The destination also lives ON the target, per the `ActivityTarget`
		# contract, so anything holding only the node can still ask where it goes.
		_set_if_present(target, "to_room_id", String(door["toRoomId"]))
		_set_if_present(target, "to_spawn_id", String(door["toSpawnId"]))
		for id: String in _ids_of(target):
			_doors_by_target[id] = door


func _build_furniture() -> void:
	for prop: Dictionary in HouseLayout.furniture(room_id):
		_add_box(
			"Prop_%s" % String(prop["targetId"]),
			prop["size"] as Vector3,
			prop["position"] as Vector3,
			prop["color"] as Color
		)
		_add_target(
			String(prop["targetId"]),
			String(prop["displayName"]),
			prop["size"] as Vector3,
			prop["position"] as Vector3,
			prop["stand"] as Vector3,
			prop["actions"] as Array
		)


## -- Node factories ------------------------------------------------------------

## A visible box plus (optionally) its static collider. One call, one set of
## numbers: the thing you can see and the thing the navigation bake reads are the
## same box by construction.
func _add_box(
	node_name: String,
	size: Vector3,
	centre: Vector3,
	color: Color,
	solid: bool = true
) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = centre
	_geometry.add_child(mesh)
	if solid:
		_add_collider("%sBody" % node_name, size, centre)


func _add_collider(node_name: String, size: Vector3, centre: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	# House geometry has its own collision layer: layer 1 is draggable pickups and
	# layer 2 is activity targets, and the navigation bake selects this layer only.
	body.collision_layer = HouseLayout.HOUSE_GEOMETRY_LAYER
	body.collision_mask = 0
	body.input_ray_pickable = false
	body.position = centre
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_geometry.add_child(body)


## Builds one `ActivityTarget` with an authored `InteractionPoint`.
##
## Every optional field is set defensively (`_set_if_present`), because the
## `ActivityTarget` contract is owned by another agent and may gain `room_id`,
## `supported_actions` and friends at any time. A room must build correctly
## against both the old and the new shape.
func _add_target(
	target_id: String,
	display: String,
	size: Vector3,
	centre: Vector3,
	stand: Vector3,
	actions: Array
) -> Node:
	var target := Area3D.new()
	target.name = target_id
	target.set_script(ActivityTargetScript)
	target.position = centre

	# CHILDREN FIRST, then properties, then methods -- in that order and for a
	# reason. `ActivityTarget._ensure_resolved()` latches on its first call and
	# caches the `InteractionPoint` it finds at that moment. Calling ANY of its
	# methods (including a setter) before the marker has been added leaves the
	# target permanently convinced it has no interaction point, and it then
	# computes a stand position from the approach direction instead -- which put
	# every door's stand position inside a wall.
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	# A generous tap box: a four-year-old taps a region, not a pixel.
	box.size = Vector3(maxf(size.x, 0.4), maxf(size.y, 0.4), maxf(size.z, 0.4))
	shape.shape = box
	target.add_child(shape)

	var point := Marker3D.new()
	point.name = "InteractionPoint"
	point.set_script(InteractionPointScript)
	point.position = stand - centre
	target.add_child(point)

	target.set("target_id", target_id)
	target.set("display_name", display)
	target.set("arrival_radius", 0.25)
	_set_if_present(target, "room_id", room_id)
	if target.has_method("set_supported_actions"):
		# Never `set()` on a typed `PackedStringArray` export from an untyped
		# Array literal -- that is a known GDScript trap, and the contract supplies
		# this setter precisely to avoid it.
		target.call("set_supported_actions", actions)

	_target_root.add_child(target)
	_targets.append(target)
	return target


func _set_if_present(node: Object, property: String, value: Variant) -> void:
	for entry: Dictionary in node.get_property_list():
		if String(entry.get("name", "")) == property:
			node.set(property, value)
			return


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


## Room-local to world. Uses `SpatialUtil` rather than `global_position`, which
## silently returns (0, 0, 0) for a node that is not inside the tree.
func _to_world(local: Vector3) -> Vector3:
	return SpatialUtil.world_transform(self) * local
