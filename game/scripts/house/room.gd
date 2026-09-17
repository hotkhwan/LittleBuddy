extends Node3D

## One room of the house: floor, walls, a window, two doors, three pieces of
## furniture, a rug and a set of semantic spawn points.
##
## The whole room is BUILT FROM `house_layout.gd`, not hand-placed in the .tscn.
## The visible mesh, the collision box and the box the navigation bake sees are
## therefore the same numbers -- which is the only way "the wall the child can see"
## and "the wall the navigation mesh knows about" can be guaranteed not to drift.
##
## ## This used to be a greybox, and the change was only skin deep
##
## Every collider, every stand position and every semantic id is exactly what the
## greybox had. What changed is that `BoxMesh` is gone: geometry now comes from
## `prop_kit.gd` and `room_props.gd`, so every architectural edge carries the
## ~2 cm bevel `docs/ART_BIBLE.md` §5 demands ("a hard 90-degree corner is the
## single strongest 'this is a prototype' signal", and §13.7 lists exactly this
## room geometry as the open issue), and each piece of furniture is the shape of
## the word it teaches rather than a coloured box.
##
## ## Draw calls, not triangles (§10)
##
## The floor planks, the walls, the skirting, the wainscot, the window, the door
## frames, the rug and the dressing all merge into ONE `ArrayMesh` carrying
## vertex colours and ONE shared material. A room is 1 shell + 3 furniture +
## 2 doors = **6 draw calls**, and only one room is ever visible, so adding
## detail costs nothing until it adds a mesh.
##
## ## Lazy wiring
##
## `build()` is idempotent and is called from every public method, because the
## headless `--script` test runner never fires `_ready()` for nodes added to the
## root -- the same rule `activity_target.gd` and `little_buddy_character.gd`
## already follow.

const HouseLayout := preload("res://scripts/house/house_layout.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/house/prop_kit.gd")
const RoomProps := preload("res://scripts/house/room_props.gd")
const ActivityTargetScript := preload("res://scripts/navigation/activity_target.gd")
const InteractionPointScript := preload("res://scripts/navigation/interaction_point.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## -- Architectural dimensions (all in metres) ----------------------------------

## The floor reads as boards, not as a tinted plane. Eight of them, each with its
## own bevel, so the joints are real grooves that catch the one directional
## light -- which is most of what separates "a wooden floor" from "a brown quad".
const FLOOR_PLANKS: int = 12
const FLOOR_THICKNESS: float = 0.12
## Tucks the boards under the walls so there is no seam at the skirting.
const FLOOR_OVERHANG: float = 0.17

## Panelling. A cream wall with a coloured lower half is the entire "room mood"
## system of §3 made out of geometry: the accent changes, the cream does not.
const SKIRTING_HEIGHT: float = 0.10
const SKIRTING_DEPTH: float = 0.055
const WAINSCOT_HEIGHT: float = 0.70
const WAINSCOT_DEPTH: float = 0.035
const RAIL_HEIGHT: float = 0.05
const RAIL_DEPTH: float = 0.065

## §5: "Every room gets one. The cheapest warmth in the scene." Centred a little
## right of the middle, which is the one x that is clear of the back-wall
## furniture in all four rooms.
const WINDOW_CENTRE: Vector2 = Vector2(0.15, 1.50)
const WINDOW_SIZE: Vector2 = Vector2(1.30, 1.06)
const WINDOW_GLASS: Vector2 = Vector2(1.10, 0.86)
const WINDOW_FRAME: float = 0.10
const WINDOW_DEPTH: float = 0.07

## The inner face of a wall, in room-local coordinates.
const INNER_X: float = 2.0
const INNER_Z: float = -2.0

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

	# One `SurfaceTool` for everything static: see the class docs on draw calls.
	var shell: SurfaceTool = Kit.begin()
	_build_floor(shell)
	_build_walls(shell)
	_build_window(shell)
	_build_rug(shell)
	_build_dressing(shell)
	_add_mesh("Shell", Kit.commit(shell), false)

	_build_doors()
	_build_furniture()


func _build_floor(tool: SurfaceTool) -> void:
	var bounds: Rect2 = HouseLayout.FLOOR_BOUNDS
	var extent: float = bounds.size.x + FLOOR_OVERHANG * 2.0
	var plank: float = extent / float(FLOOR_PLANKS)
	var wood: Color = HouseLayout.floor_color(room_id)
	for index: int in range(FLOOR_PLANKS):
		# Alternate boards are shaded by 4%. Not a pattern -- just enough variation
		# that the eye reads timber rather than a painted surface.
		var shade: float = 1.0 if index % 2 == 0 else 0.93
		Kit.box(
			tool,
			Kit.at(Vector3(-extent * 0.5 + plank * (float(index) + 0.5),
					HouseLayout.FLOOR_Y - FLOOR_THICKNESS * 0.5, bounds.get_center().y)),
			Vector3(plank, FLOOR_THICKNESS, extent),
			_shade(wood, shade),
			0.014
		)

	# The collider is what the navigation mesh is baked from, so it is exactly the
	# interior floor: 4 x 4 m, top face at floor level. Unchanged from the
	# greybox; the boards above are visual only.
	_add_collider(
		"FloorBody",
		Vector3(bounds.size.x, 0.2, bounds.size.y),
		Vector3(bounds.get_center().x, HouseLayout.FLOOR_Y - 0.1, bounds.get_center().y)
	)


## Back wall and two side walls, all OUTSIDE the floor. The front (camera-facing)
## side is deliberately open: this is a doll's-house view and a wall there would
## hide the whole room.
func _build_walls(tool: SurfaceTool) -> void:
	var bounds: Rect2 = HouseLayout.FLOOR_BOUNDS
	var thickness: float = HouseLayout.WALL_THICKNESS
	var height: float = HouseLayout.WALL_HEIGHT
	var half_door: float = HouseLayout.DOOR_WIDTH * 0.5

	_add_box(
		tool,
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
			tool,
			"Wall%sBack" % ("Left" if side < 0 else "Right"),
			Vector3(thickness, height, back_end - back_start),
			Vector3(wall_x, height * 0.5, (back_start + back_end) * 0.5),
			HouseLayout.WALL_COLOR
		)
		# Front segment: from the far edge of the doorway to the open front.
		var front_start: float = HouseLayout.DOOR_Z + half_door
		var front_end: float = bounds.end.y
		_add_box(
			tool,
			"Wall%sFront" % ("Left" if side < 0 else "Right"),
			Vector3(thickness, height, front_end - front_start),
			Vector3(wall_x, height * 0.5, (front_start + front_end) * 0.5),
			HouseLayout.WALL_COLOR
		)
		# Lintel over the doorway, so the opening reads as a door rather than as a
		# hole in the wall.
		_add_box(
			tool,
			"Lintel%s" % ("Left" if side < 0 else "Right"),
			Vector3(thickness, height - HouseLayout.DOOR_HEIGHT, HouseLayout.DOOR_WIDTH),
			Vector3(
				wall_x,
				(height + HouseLayout.DOOR_HEIGHT) * 0.5,
				HouseLayout.DOOR_Z
			),
			HouseLayout.WALL_COLOR
		)
		_build_architrave(tool, side)

	_build_panelling(tool)


## Skirting, wainscot and a chair rail on the inner face of every wall segment.
##
## This is the room's MOOD (§3): the base stays `cream` in all four rooms and
## only the lower panel takes the room's dominant colour. It is also what stops
## a 2.2 m cream wall reading as an untextured plane -- three horizontal breaks
## at toddler height, each with its own bevel, each catching the light
## differently.
func _build_panelling(tool: SurfaceTool) -> void:
	# A step DOWN from the room's dominant, not the dominant itself. Two of the
	# four rooms are dominant-`peach`, and the floorboards are `peach` too: at full
	# strength the panelling and the floor were the same value and the room lost
	# its horizon.
	var dominant: Color = Palette.deep(HouseLayout.dominant_color(room_id))
	for face: Dictionary in _wall_faces():
		var normal: Vector3 = face["normal"]
		var axis: Vector3 = face["axis"]
		var centre: Vector3 = face["centre"]
		var length: float = face["length"]
		for band: Array in [
			[SKIRTING_HEIGHT * 0.5, SKIRTING_HEIGHT, SKIRTING_DEPTH, Palette.CREAM],
			[SKIRTING_HEIGHT + (WAINSCOT_HEIGHT - SKIRTING_HEIGHT) * 0.5,
					WAINSCOT_HEIGHT - SKIRTING_HEIGHT, WAINSCOT_DEPTH, dominant],
			[WAINSCOT_HEIGHT + RAIL_HEIGHT * 0.5, RAIL_HEIGHT, RAIL_DEPTH, Palette.CREAM],
		]:
			var depth: float = float(band[2])
			Kit.box(
				tool,
				Kit.at(centre + normal * (depth * 0.5) + Vector3(0.0, float(band[0]), 0.0)),
				Vector3(
					absf(axis.x) * length + absf(normal.x) * depth,
					float(band[1]),
					absf(axis.z) * length + absf(normal.z) * depth
				),
				band[3] as Color,
				0.016
			)


## The three visible wall faces, as `{normal, axis, centre, length}` in room-local
## space: the back wall, and the two segments either side of each doorway.
func _wall_faces() -> Array:
	var half_door: float = HouseLayout.DOOR_WIDTH * 0.5
	var back_end: float = HouseLayout.DOOR_Z - half_door
	var front_start: float = HouseLayout.DOOR_Z + half_door
	var faces: Array = [{
		"normal": Vector3.BACK,
		"axis": Vector3.RIGHT,
		"centre": Vector3(0.0, 0.0, INNER_Z),
		"length": INNER_X * 2.0,
	}]
	for side: float in [-1.0, 1.0]:
		faces.append({
			"normal": Vector3(-side, 0.0, 0.0),
			"axis": Vector3.BACK,
			"centre": Vector3(side * INNER_X, 0.0, (INNER_Z + back_end) * 0.5),
			"length": back_end - INNER_Z,
		})
		faces.append({
			"normal": Vector3(-side, 0.0, 0.0),
			"axis": Vector3.BACK,
			"centre": Vector3(side * INNER_X, 0.0, (front_start - INNER_Z) * 0.5),
			"length": -INNER_Z - front_start,
		})
	return faces


## A moulding round each doorway. §5 wants doors that read as doors; an opening
## cut straight out of a flat wall reads as a hole.
func _build_architrave(tool: SurfaceTool, side: int) -> void:
	var trim: Color = Palette.deep(Palette.CREAM)
	var half_door: float = HouseLayout.DOOR_WIDTH * 0.5
	var x: float = float(side) * (INNER_X - 0.03)
	var top: float = HouseLayout.DOOR_HEIGHT + 0.03
	for offset: float in [-(half_door + 0.045), half_door + 0.045]:
		Kit.box(tool, Kit.at(Vector3(x, top * 0.5, HouseLayout.DOOR_Z + offset)),
				Vector3(0.06, top, 0.09), trim, 0.018)
	Kit.box(tool, Kit.at(Vector3(x, top - 0.045, HouseLayout.DOOR_Z)),
			Vector3(0.06, 0.09, HouseLayout.DOOR_WIDTH + 0.18), trim, 0.018)


## The window: a soft rounded frame, a flat sky plane and a sill. §5 is explicit
## that there is no glass, no transparency and no reflection -- the sky is an
## opaque colour, and that is the whole trick.
func _build_window(tool: SurfaceTool) -> void:
	var centre := Vector3(WINDOW_CENTRE.x, WINDOW_CENTRE.y, INNER_Z + 0.012)
	Kit.plate(
		tool,
		Kit.at_rotated(centre, Vector3(-90.0, 0.0, 0.0)),
		Kit.rounded_rect(WINDOW_GLASS, 0.06, 3),
		0.024,
		Kit.WINDOW_SKY,
		0.008
	)
	var half: Vector2 = WINDOW_SIZE * 0.5
	var frame_z: float = INNER_Z + WINDOW_DEPTH * 0.5 + 0.018
	for y: float in [-(half.y - WINDOW_FRAME * 0.5), half.y - WINDOW_FRAME * 0.5]:
		Kit.box(tool, Kit.at(centre + Vector3(0.0, y, frame_z - centre.z)),
				Vector3(WINDOW_SIZE.x, WINDOW_FRAME, WINDOW_DEPTH), Palette.CREAM, 0.018)
	for x: float in [-(half.x - WINDOW_FRAME * 0.5), half.x - WINDOW_FRAME * 0.5]:
		Kit.box(tool, Kit.at(centre + Vector3(x, 0.0, frame_z - centre.z)),
				Vector3(WINDOW_FRAME, WINDOW_SIZE.y, WINDOW_DEPTH), Palette.CREAM, 0.018)
	# One vertical glazing bar. Two would start to read as a grid.
	Kit.box(tool, Kit.at(centre + Vector3(0.0, 0.0, frame_z - centre.z - 0.012)),
			Vector3(0.055, WINDOW_GLASS.y, WINDOW_DEPTH - 0.024), Palette.CREAM, 0.014)
	# The sill, proud enough to hold a plant and to cast a shadow on the wall.
	Kit.box(tool, Kit.at(Vector3(WINDOW_CENTRE.x, WINDOW_CENTRE.y - half.y - 0.035,
			INNER_Z + 0.09)), Vector3(WINDOW_SIZE.x + 0.16, 0.07, 0.20),
			Palette.CREAM, 0.018)


## One rug per room (§5), in the room's dominant colour, sized and placed to sit
## under whatever the child plays with in that room.
func _build_rug(tool: SurfaceTool) -> void:
	var rug: Dictionary = _rug_placement()
	if rug.is_empty():
		return
	var size: Vector2 = rug["size"]
	var at: Vector2 = rug["at"]
	Kit.plate(
		tool,
		Kit.at(Vector3(at.x, HouseLayout.FLOOR_Y + 0.008, at.y)),
		Kit.rounded_rect(size, minf(size.x, size.y) * 0.22, 4),
		0.016,
		HouseLayout.accent_color(room_id),
		0.005
	)


func _rug_placement() -> Dictionary:
	match room_id:
		HouseLayout.BEDROOM:
			return {"size": Vector2(1.95, 1.45), "at": Vector2(0.62, 0.85)}
		HouseLayout.BATHROOM:
			return {"size": Vector2(1.30, 0.95), "at": Vector2(0.30, 0.30)}
		HouseLayout.KITCHEN:
			return {"size": Vector2(1.70, 1.50), "at": Vector2(0.50, 0.60)}
		HouseLayout.LIVING_ROOM:
			return {"size": Vector2(2.40, 1.70), "at": Vector2(-0.15, 0.35)}
		_:
			return {}


## "Tidy but lived-in" (§5). Deliberately only ever placed on a sill, a worktop or
## a wall: nothing here has a collider, so nothing here may stand anywhere the
## child could walk, or he would walk through it.
func _build_dressing(tool: SurfaceTool) -> void:
	var accent: Color = HouseLayout.accent_color(room_id)
	# Every room gets the same plant on the same sill. Repetition across rooms is
	# what makes four rooms read as one home.
	RoomProps.plant(
		tool,
		Kit.at(Vector3(WINDOW_CENTRE.x - 0.42, WINDOW_CENTRE.y - WINDOW_SIZE.y * 0.5, INNER_Z + 0.10)),
		0.52,
		Palette.deep(accent)
	)
	match room_id:
		HouseLayout.BEDROOM:
			_wall_picture(tool, -1.25, 1.52, accent)
		HouseLayout.BATHROOM:
			_mirror(tool, -1.20, 1.36)
		HouseLayout.KITCHEN:
			RoomProps.plant(tool, Kit.at(Vector3(-1.46, 0.90, -1.62)), 0.62,
					Palette.deep(Palette.SOFT_PINK))
		HouseLayout.LIVING_ROOM:
			_wall_picture(tool, -1.10, 1.52, accent)


## A framed picture. No text, no representational subject -- one soft shape, so
## it stays warm without competing with the object the room is teaching.
func _wall_picture(tool: SurfaceTool, x: float, y: float, accent: Color) -> void:
	var facing: Vector3 = Vector3(-90.0, 0.0, 0.0)
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.03), facing),
			Kit.rounded_rect(Vector2(0.50, 0.40), 0.05, 3), 0.055, Palette.CREAM, 0.018)
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.055), facing),
			Kit.rounded_rect(Vector2(0.38, 0.28), 0.04, 3), 0.03,
			accent, 0.01)
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y - 0.01, INNER_Z + 0.075), facing),
			Kit.circle(0.085, 16), 0.02, accent, 0.006)


func _mirror(tool: SurfaceTool, x: float, y: float) -> void:
	var facing: Vector3 = Vector3(-90.0, 0.0, 0.0)
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.03), facing),
			Kit.circle(0.27, 20), 0.055, Palette.CREAM, 0.018)
	# No reflection, no transparency (§7): a pale flat disc reads as a mirror
	# because of where it is, not because of what it does.
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.062), facing),
			Kit.circle(0.222, 20), 0.024, Palette.DUSTY_BLUE, 0.008)


## Each door is a closed slab (so the child cannot walk through it) plus an
## `ActivityTarget` with an authored `InteractionPoint` in front of it.
func _build_doors() -> void:
	for door: Dictionary in HouseLayout.doors(room_id):
		var size := Vector3(
			HouseLayout.DOOR_THICKNESS, HouseLayout.DOOR_HEIGHT, HouseLayout.DOOR_WIDTH
		)
		var centre: Vector3 = door["position"]
		var side: float = float(door["side"])
		var tool: SurfaceTool = Kit.begin()
		# §5: rounded-top, no visible hinges, handle as a soft sphere. The arch is
		# most of what stops a door slab reading as a plank.
		var facing := Vector3(0.0, 90.0, 0.0)
		Kit.extrude(
			tool,
			Kit.at_rotated(Vector3.ZERO, facing),
			Kit.arch(Vector2(HouseLayout.DOOR_WIDTH, HouseLayout.DOOR_HEIGHT), 0.07, 7),
			HouseLayout.DOOR_THICKNESS,
			HouseLayout.DOOR_COLOR,
			0.018
		)
		# A sunk panel, on the side the child is standing on.
		Kit.extrude(
			tool,
			Kit.at_rotated(Vector3(-side * 0.046, -0.07, 0.0), facing),
			Kit.arch(Vector2(0.62, 1.46), 0.06, 6),
			0.055,
			Palette.light(HouseLayout.DOOR_COLOR),
			0.016
		)
		Kit.sphere(tool, Kit.at(Vector3(-side * 0.075, -0.06, -side * 0.28)),
				0.052, Palette.CREAM, 12, 6)
		# Like the shell, a door does not cast: it is 1.9 m of wall, and its
		# shadow is a hard diagonal band thrown right across the room floor.
		var mesh: MeshInstance3D = _add_mesh(
				"Door_%s" % String(door["targetId"]), Kit.commit(tool), false)
		if mesh != null:
			mesh.position = centre
		_add_collider("Door_%sBody" % String(door["targetId"]), size, centre)
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
		var target_id: String = String(prop["targetId"])
		var size: Vector3 = prop["size"]
		var centre: Vector3 = prop["position"]
		var tool: SurfaceTool = Kit.begin()
		if not RoomProps.build(tool, target_id, room_id, size):
			# An id with no authored shape still gets a correctly sized, correctly
			# bevelled solid rather than nothing at all.
			Kit.box(tool, Transform3D.IDENTITY, size, prop["color"] as Color, Kit.PROP_BEVEL)
		var mesh: MeshInstance3D = _add_mesh("Prop_%s" % target_id, Kit.commit(tool))
		if mesh != null:
			mesh.position = centre
		_add_collider("Prop_%sBody" % target_id, size, centre)
		_add_target(
			String(prop["targetId"]),
			String(prop["displayName"]),
			prop["size"] as Vector3,
			prop["position"] as Vector3,
			prop["stand"] as Vector3,
			prop["actions"] as Array
		)


## -- Node factories ------------------------------------------------------------

## A bevelled box written into the shared shell mesh, plus its static collider.
## One call, one set of numbers: the thing you can see and the thing the
## navigation bake reads are the same box by construction.
func _add_box(
	tool: SurfaceTool,
	node_name: String,
	size: Vector3,
	centre: Vector3,
	color: Color
) -> void:
	Kit.box(tool, Kit.at(centre), size, color)
	_add_collider("%sBody" % node_name, size, centre)


## One finished `ArrayMesh` becomes one `MeshInstance3D` sharing the house's one
## material -- so this is exactly one draw call, whatever is in it.
## `casts` is false for the room SHELL, and that is a deliberate doll's-house
## cheat rather than an oversight. Three 2.2 m walls lit by one mid-morning sun
## throw the whole interior into shade -- the first render with shadows on was a
## room where every surface was shadowed and no object had a shadow of its own,
## which is exactly backwards. The shell is the box the scene lives in; the
## furniture and the child are what have to sit on the floor (§7), so they cast
## and it does not.
func _add_mesh(node_name: String, mesh: ArrayMesh, casts: bool = true) -> MeshInstance3D:
	if mesh == null:
		return null
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = Kit.material()
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_geometry.add_child(instance)
	return instance


## Multiplies a colour's brightness without touching its alpha. Used only for the
## floor boards; everything else takes a §3 token or one of its two steps.
func _shade(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


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


## -- Budget diagnostics (ART_BIBLE.md section 10) --------------------------------
##
## Measured, not guessed. `test_art_rooms.gd` asserts both against the locked
## ceilings; nothing else calls these.

## Every `MeshInstance3D` in the room. Because all of them share one material,
## this IS the room's draw-call count.
func count_meshes() -> int:
	build()
	var total: int = 0
	if _geometry == null:
		return 0
	for child: Node in _geometry.get_children():
		if child is MeshInstance3D:
			total += 1
	return total


func count_triangles() -> int:
	build()
	var total: int = 0
	if _geometry == null:
		return 0
	for child: Node in _geometry.get_children():
		if child is MeshInstance3D:
			total += Kit.triangles((child as MeshInstance3D).mesh)
	return total


## Room-local to world. Uses `SpatialUtil` rather than `global_position`, which
## silently returns (0, 0, 0) for a node that is not inside the tree.
func _to_world(local: Vector3) -> Vector3:
	return SpatialUtil.world_transform(self) * local
