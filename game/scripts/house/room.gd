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
	var all: Array = _targets.duplicate()
	# Inhabitants contribute targets too. Little Buddy registers its own, so a
	# mission can say "go to bedroom.littleBuddy" -- and without this the room's
	# registry would not contain it and the reference would miss silently, which
	# is exactly what `test_semantic_validation` exists to catch.
	for child: Node in get_children():
		if child.has_method("get_activity_target"):
			var contributed: Node = child.call("get_activity_target")
			if contributed != null and not all.has(contributed):
				all.append(contributed)
	return all


## Accepts either half of the address: `"bed"` or `"bedroom.bed"`. The
## `ActivityTarget` contract reports `get_activity_target_id()` as the SEMANTIC
## id, so a caller holding only the local half would otherwise find nothing.
func get_activity_target(target_id: String) -> Node:
	build()
	# Over the COLLECTED list, not the private one: an inhabitant's target is
	# reachable by `get_activity_targets()` and must be findable by id too, or a
	# mission can see it in the registry and fail to look it up.
	for target: Node in get_activity_targets():
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
	_build_stage(shell)
	_build_floor(shell)
	_build_walls(shell)
	_build_window(shell)
	_build_rug(shell)
	_build_dressing(shell)
	_add_mesh("Shell", Kit.commit(shell), false)

	# Floor dressing is its own mesh for one reason: the shell does not cast
	# shadows (see `_add_mesh`), and anything standing ON the floor must, or it
	# floats (§7: "Shadows are what ground objects on the floor"). One extra
	# mesh, one extra draw call, still one material.
	var dressing: SurfaceTool = Kit.begin()
	_build_floor_dressing(dressing)
	_add_mesh("FloorDressing", Kit.commit(dressing))

	_build_doors()
	_build_furniture()
	_build_storages()


## The STAGE: what the child sees where the room itself runs out.
##
## The camera fits the 4 x 4 m floor and its headroom, and the room ended exactly
## there, so every aspect ratio wider or taller than the room's own showed flat
## environment colour past the walls -- large unexplained beige margins at the
## screen edges, worst on a 4:3 iPad. Zooming in to hide them is the wrong fix:
## it crops the room the framing was carefully built to keep whole.
##
## So the ROOM stays the size it is and the WORLD gets bigger. An apron floor
## continues the boards outwards, and a surrounding band of wall rises well above
## the room's own 2.2 m, so the shot reads as one room of a larger house rather
## than as a model floating in a void.
##
## Entirely visual: no collider, no navigation, nothing addressable. It is added
## to the shell's `SurfaceTool`, so it costs no extra draw call, and the shell
## does not cast shadows so it cannot darken the room.
const STAGE_APRON: float = 7.0
const STAGE_WALL_HEIGHT: float = 6.0
const STAGE_INSET: float = 0.02


func _build_stage(tool: SurfaceTool) -> void:
	var bounds: Rect2 = HouseLayout.FLOOR_BOUNDS
	var thickness: float = HouseLayout.WALL_THICKNESS
	var apron_extent: float = bounds.size.x + STAGE_APRON * 2.0
	var floor_tone: Color = _shade(HouseLayout.floor_color(room_id), 0.82)

	# Apron floor, a hair BELOW the boards so the two never z-fight, and darker so
	# the room's own floor still reads as the lit, occupied area.
	Kit.box(
		tool,
		Kit.at(Vector3(bounds.get_center().x,
				HouseLayout.FLOOR_Y - FLOOR_THICKNESS - STAGE_INSET,
				bounds.get_center().y)),
		Vector3(apron_extent, FLOOR_THICKNESS, apron_extent),
		floor_tone
	)

	# Surrounding wall band. Set OUTSIDE the room's own walls and taller than
	# them, so it fills the upper corners without ever being seen through the
	# doorways -- the doorway openings are in the room walls, which sit in front.
	var outer: float = bounds.end.x + thickness + 0.9
	var wall_tone: Color = _shade(HouseLayout.WALL_COLOR, 0.88)
	var mid_y: float = STAGE_WALL_HEIGHT * 0.5

	Kit.box(
		tool,
		Kit.at(Vector3(0.0, mid_y, bounds.position.y - thickness - 0.9)),
		Vector3(outer * 2.0 + thickness * 2.0, STAGE_WALL_HEIGHT, thickness),
		wall_tone
	)
	for side: int in [-1, 1]:
		Kit.box(
			tool,
			Kit.at(Vector3(float(side) * outer, mid_y, bounds.get_center().y)),
			Vector3(thickness, STAGE_WALL_HEIGHT, apron_extent * 0.92),
			wall_tone
		)


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


## Pulled FORWARD, toward the open fourth wall, and grown.
##
## A rug is the only thing that can dress the near half of a room for free: it is
## a flat plate at floor level with no collider, so it costs the navigation bake
## nothing at all, and it is the cheapest possible answer to "the front third is
## bare boards". Each one now reaches the `default` spawn at z = 1.5, so the
## child arrives standing ON something rather than on empty timber.
func _rug_placement() -> Dictionary:
	match room_id:
		HouseLayout.BEDROOM:
			return {"size": Vector2(2.15, 1.75), "at": Vector2(0.40, 0.95)}
		HouseLayout.BATHROOM:
			return {"size": Vector2(1.85, 1.35), "at": Vector2(0.10, 0.85)}
		HouseLayout.KITCHEN:
			return {"size": Vector2(2.00, 1.80), "at": Vector2(0.45, 0.80)}
		HouseLayout.LIVING_ROOM:
			return {"size": Vector2(2.55, 1.95), "at": Vector2(-0.10, 0.75)}
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
			_nursery_wall_art(tool, -1.22, 1.44, accent)
		HouseLayout.BATHROOM:
			_mirror(tool, -1.20, 1.36)
		HouseLayout.KITCHEN:
			_kitchen_fixtures(tool)
		HouseLayout.LIVING_ROOM:
			_wall_picture(tool, -1.10, 1.52, accent)


## -- The nursery's wall -----------------------------------------------------------
##
## The bedroom is where the baby lives, and it was telling the child so with a
## framed abstract square -- the same generic picture the living room has. A
## cloud with three charms hanging under it is the cheapest possible "this is the
## baby's room": it is read instantly, it costs one extrusion group in the shell
## mesh, and it carries no text for a player who cannot read.
##
## It stays ABOVE the bed's headboard and BELOW the wall top, so it neither
## collides with furniture nor leaves the frame; and it is flat wall art rather
## than a hanging mobile, because anything hanging over a cot invites a tap that
## does nothing.
func _nursery_wall_art(tool: SurfaceTool, x: float, y: float, accent: Color) -> void:
	var facing: Vector3 = Vector3(-90.0, 0.0, 0.0)
	var cloud: Color = accent
	# Three overlapping discs plus a bar under them: a cloud has no outline in
	# this style, so its silhouette has to do all the work (§2, silhouette test).
	for lobe: Array in [[-0.20, 0.015, 0.145], [0.0, 0.055, 0.180], [0.19, 0.005, 0.135]]:
		Kit.plate(
			tool,
			Kit.at_rotated(Vector3(x + float(lobe[0]), y + float(lobe[1]), INNER_Z + 0.035),
					facing),
			Kit.circle(float(lobe[2]), 16), 0.045, cloud, 0.012
		)
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y - 0.055, INNER_Z + 0.035), facing),
			Kit.rounded_rect(Vector2(0.48, 0.15), 0.07, 3), 0.045, cloud, 0.012)

	# Three charms on three cords. Diamonds rather than discs: a disc beside a
	# round cloud is one more bubble, and the point of the charms is a second
	# shape.
	var charm: Color = Palette.deep(HouseLayout.dominant_color(room_id))
	var index: int = 0
	for drop: Array in [[-0.18, 0.23], [0.02, 0.33], [0.20, 0.26]]:
		var at_x: float = x + float(drop[0])
		var length: float = float(drop[1])
		Kit.plate(
			tool,
			Kit.at_rotated(Vector3(at_x, y - 0.12 - length * 0.5, INNER_Z + 0.028), facing),
			Kit.rounded_rect(Vector2(0.016, length), 0.006, 2), 0.02,
			Palette.deep(accent), 0.004
		)
		Kit.plate(
			tool,
			Kit.at_rotated(Vector3(at_x, y - 0.12 - length, INNER_Z + 0.04),
					Vector3(-90.0, 0.0, 45.0)),
			Kit.rounded_rect(Vector2(0.115, 0.115), 0.028, 3), 0.035, charm, 0.01
		)
		index += 1


## -- The kitchen's fixtures ------------------------------------------------------
##
## A fridge, a worktop and a table is a *room with furniture in it*. A sink, a tap
## and a hob is a KITCHEN, and the difference is the one a four-year-old uses to
## name the place. Reviewed cold, the room before this could as easily have been
## read as a hallway with a cupboard in it.
##
## ## Why they are drawn into the shell and have no colliders
##
## Every one of these sits ON the worktop, inside the counter's own 1.8 x 0.6 m
## collider and inside its `ActivityTarget` box, so the child's tap still lands on
## "counter" wherever on it they touch. A separate body would have split one
## generous touch target into three small ones and taken floor away from a baked
## navigation mesh that cannot be re-baked from here -- which is also why nothing
## here stands on the floor.
##
## ## The worktop is a shared surface, so these are placed around what uses it
##
## `kitchen_view.gd` puts carried items down at the counter's CENTRE
## (`x = -0.8`). The sink and the hob therefore live at the two ends, with a
## hand's width of clear worktop either side of the drop zone. The plant that used
## to stand at `x = -1.46` is gone: it was occupying the only part of the worktop
## a sink could go, and a kitchen that reads as a kitchen is worth more than a
## second pot in a room that already has one on the sill.
const SINK_X: float = -1.24
const HOB_X: float = -0.26
## The counter's own top (`HouseLayout.furniture()`: centre 0.45, height 0.9).
const WORKTOP_Y: float = 0.90
## Forward of the counter's centre line, so the basin is not half swallowed by
## the splashback at this camera angle.
const FIXTURE_Z: float = -1.62


func _kitchen_fixtures(tool: SurfaceTool) -> void:
	var steel: Color = Palette.deep(Palette.DUSTY_BLUE)

	# The sink: a real open basin. §6 wants visible interior depth in anything
	# that holds something, and a solid-topped basin reads as a cupboard door
	# lying flat -- which is exactly how the bath failed its first three passes.
	# It stands proud of the worktop rather than being sunk into it, because the
	# counter is a solid mesh and a recess would simply be filled by it.
	Kit.vessel(
		tool,
		Kit.at(Vector3(SINK_X, WORKTOP_Y + 0.055, FIXTURE_Z)),
		Kit.rounded_rect(Vector2(0.42, 0.34), 0.10, 3),
		0.11, 0.035, 0.03,
		Palette.CREAM, Palette.DUSTY_BLUE
	)
	# The tap. §7: "there is no metal; 'metal' is a dusty-blue convention."
	Kit.cylinder(tool, Kit.at(Vector3(SINK_X, WORKTOP_Y + 0.11, FIXTURE_Z - 0.17)),
			0.022, 0.22, steel, 10)
	Kit.box(tool, Kit.at(Vector3(SINK_X, WORKTOP_Y + 0.215, FIXTURE_Z - 0.115)),
			Vector3(0.042, 0.042, 0.13), steel, 0.014)

	# The hob: a plate and two rings. Two rings rather than four, because at this
	# camera distance four would merge into a texture, and the ring is the whole
	# reason this is a stove and not a chopping board.
	Kit.plate(tool, Kit.at(Vector3(HOB_X, WORKTOP_Y + 0.018, FIXTURE_Z)),
			Kit.rounded_rect(Vector2(0.44, 0.36), 0.09, 3), 0.036, Palette.DUSTY_BLUE, 0.012)
	for side: float in [-1.0, 1.0]:
		Kit.torus(tool, Kit.at(Vector3(HOB_X + side * 0.105, WORKTOP_Y + 0.042, FIXTURE_Z)),
				0.062, 0.013, steel, 14, 6)

	# Wall cupboards over the worktop -- the storage the fridge is not. Set to the
	# LEFT of the window (which spans x -0.50 to 0.80) so nothing overlaps, and
	# kept below 1.75 m so the shot still holds them.
	var door_face: Color = Palette.light(Palette.PEACH)
	Kit.plate(tool, Kit.at_rotated(Vector3(-1.18, 1.50, INNER_Z + 0.16), Vector3(-90.0, 0.0, 0.0)),
			Kit.rounded_rect(Vector2(1.22, 0.46), 0.05, 3), 0.30, HouseLayout.WOOD_COLOR, 0.018)
	for side: float in [-1.0, 1.0]:
		Kit.plate(
			tool,
			Kit.at_rotated(Vector3(-1.18 + side * 0.30, 1.50, INNER_Z + 0.315),
					Vector3(-90.0, 0.0, 0.0)),
			Kit.rounded_rect(Vector2(0.54, 0.36), 0.04, 3), 0.035, door_face, 0.012
		)
		Kit.sphere(tool, Kit.at(Vector3(-1.18 + side * 0.055, 1.38, INNER_Z + 0.34)),
				0.028, Palette.CREAM, 10, 6)


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


## Where floor dressing stands: hard against the two side walls, in the front
## third, and nowhere else.
##
## ## Why the foreground needed dressing at all
##
## Every piece of furniture in this house is against the back wall by layout, so
## the near half of all four rooms was bare boards: no foreground, no depth, and
## a child who walks forward into an empty half-room.
##
## ## Why it is NOT in the front corners, which is where it wants to be
##
## Floor dressing is the one kind of clutter that can break the game. It has a
## collider, it takes floor away from the navigation bake, and a level that
## cannot reach a stand point is a dead end. `tools/bake_navmesh.gd` probes a
## corner-to-corner crossing from (-1.6, 1.6) to (1.6, 1.6) after every bake --
## the two front corners, exactly where foreground dressing belongs. A plant
## there put an obstacle ON a probe endpoint and all four rooms came back
## "the child cannot walk from ... to ...". That probe is right and the placement
## was wrong.
##
## So the numbers below are derived, not chosen. Along the side wall the free
## window in z runs from the door stand at z = 0.6 to the corner probe at
## z = 1.6; one 0.20 m agent radius off each end leaves 0.6 m, and a 0.34 m
## footprint centred at z = 1.15 sits inside it with 0.20 m of margin at the door
## and 0.10 m at the corner. That is why every dressing item here is 0.34 m
## across and no wider, and why they are tall rather than fat.
##
## Deliberately sparse: another system places the child's choice objects on the
## floor beside the furniture they belong with, and it needs that floor free.
const DRESSING_FOOTPRINT: float = 0.34
const DRESSING_LEFT: Vector2 = Vector2(-1.76, 1.15)
const DRESSING_RIGHT: Vector2 = Vector2(1.76, 1.15)


## `{kind, at, size}` per item. `size` is the collider, not the mesh.
func _floor_dressing() -> Array:
	var accent: Color = HouseLayout.accent_color(room_id)
	# The pot takes the room's DOMINANT colour, never its accent. Two of the four
	# rooms accent on `mint`, and a deep-mint pot under mint foliage is one green
	# lump: the pot has to be the thing the leaves sit against.
	var plant: Dictionary = {
		"kind": "plant", "at": DRESSING_LEFT, "height": 0.80,
		"color": Palette.deep(HouseLayout.dominant_color(room_id)),
	}
	match room_id:
		HouseLayout.BEDROOM:
			return [plant, {
				"kind": "basket", "at": DRESSING_RIGHT, "height": 0.40,
				"color": Palette.deep(HouseLayout.dominant_color(room_id)),
			}]
		HouseLayout.BATHROOM:
			return [plant, {
				"kind": "stepStool", "at": DRESSING_RIGHT, "height": 0.30,
				"color": Palette.light(accent),
			}]
		HouseLayout.KITCHEN:
			return [plant, {
				"kind": "stool", "at": DRESSING_RIGHT, "height": 0.38,
				"color": Palette.light(accent),
			}]
		HouseLayout.LIVING_ROOM:
			return [plant, {
				"kind": "footstool", "at": DRESSING_RIGHT, "height": 0.30,
				"color": Palette.deep(accent),
			}]
		_:
			return []


func _build_floor_dressing(tool: SurfaceTool) -> void:
	for item: Dictionary in _floor_dressing():
		var at: Vector2 = item["at"]
		# One footprint for everything here, and it is a constraint, not a
		# convenience: see `DRESSING_FOOTPRINT`.
		var size := Vector3(DRESSING_FOOTPRINT, float(item["height"]), DRESSING_FOOTPRINT)
		var color: Color = item["color"]
		# Pivot at base centre (§6), so `at` is literally where it stands.
		var stands: Transform3D = Kit.at(Vector3(at.x, HouseLayout.FLOOR_Y, at.y))
		match String(item["kind"]):
			"plant":
				RoomProps.floor_plant(tool, stands, color)
			"basket":
				RoomProps.basket(tool, stands, color)
			"stepStool":
				RoomProps.step_stool(tool, stands, color)
			"stool":
				RoomProps.stool(tool, stands, color)
			"footstool":
				RoomProps.footstool(tool, stands, color)
			_:
				continue
		_add_collider(
			"Dressing_%s_%dBody" % [String(item["kind"]), int(at.x * 100.0)],
			size,
			Vector3(at.x, HouseLayout.FLOOR_Y + size.y * 0.5, at.y)
		)


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
		_build_door_sign(door)


## A sign over each doorway saying where it goes, in a picture first and a word
## second.
##
## The problem it solves is real and was visible in every screenshot: two
## identical arched doors, one on each side of the room, and nothing whatsoever
## to tell a child which is the kitchen. Route knowledge lived only in
## `toRoomId`, which the player cannot read.
##
## It is built as ENVIRONMENT, not as UI: a wooden plaque screwed to the wall
## above the architrave, with a chunky painted glyph and the room's name under
## it. A `Control` overlay would have been quicker and would have read as a
## debug label floating in the air -- the brief asks for the opposite.
##
## The glyph is the load-bearing half. A four-year-old who cannot read "KITCHEN"
## can still learn "the door with the plate on it", so the word is the smaller
## element and the picture is the big one. `Label3D` is used for the word because
## it is lit, occluded and scaled by the same camera as everything else, so it
## sits in the room rather than on top of it.
## Sized and placed to sit ON THE DOOR, in its upper third.
##
## The first attempt hung it on the wall above the architrave, which failed twice
## over: the door is 1.9 m and the wall is 2.2 m, so a 0.5 m plaque did not fit
## and was clipped by the ceiling, and a sign on a side wall is edge-on to this
## camera and unreadable. On the door itself it faces into the room, sits at
## roughly a child's eye line, and cannot be cropped by the wall top.
##
## ## It was twice this size, and that was the "giant placeholder room label"
##
## The plaque used to be 0.92 x 0.46 m -- as wide as the door, wider than the
## child -- carrying a 64 pt word. Reviewed cold on an iPad it read as a debug
## label that had been given a frame, not as part of the house, and it was the
## single loudest object in every room. It is now 0.60 x 0.30 m
## (`HouseLayout.DOOR_SIGN_SIZE`): a thin accent rim round a cream face, with the
## word set smaller. The glyph did NOT shrink proportionally -- it is the half a
## four-year-old reads, so it now fills more of a smaller board.
## Wide enough for the longest label ("LIVING ROOM") at the size below.
const SIGN_SIZE: Vector2 = HouseLayout.DOOR_SIGN_SIZE

## One distinct pastel per destination, so the sign reads by COLOUR before the
## child has focused on either the glyph or the word. Neither
## `HouseLayout.accent_color()` nor `dominant_color()` could be reused: both
## give two rooms the same value (mint for bathroom AND kitchen; peach for
## kitchen AND living room), which is fine for room mood and useless for
## telling two doors apart.
const SIGN_COLORS: Dictionary = {
	HouseLayout.BEDROOM: Palette.LAVENDER,
	HouseLayout.BATHROOM: Palette.DUSTY_BLUE,
	HouseLayout.KITCHEN: Palette.PEACH,
	HouseLayout.LIVING_ROOM: Palette.SOFT_PINK,
}
const SIGN_DEPTH: float = 0.03


func _build_door_sign(door: Dictionary) -> void:
	var to_room: String = String(door["toRoomId"])
	var centre: Vector3 = door["position"]
	var side: float = float(door["side"])
	var accent: Color = SIGN_COLORS.get(to_room, Palette.MINT)
	# Just inside the room and above the doorway, FACING THE CAMERA -- a hanging
	# shop sign rather than a plate screwed flat to the door. Both doors are on
	# the side walls, so anything lying flat on them is edge-on to this camera and
	# unreadable; that was the first two attempts. The kit extrudes towards +Z by
	# default (the door itself rotates that by 90 degrees), so an unrotated
	# plaque already faces the way the child is looking.
	var origin := Vector3(
		side * HouseLayout.DOOR_SIGN_X, HouseLayout.DOOR_SIGN_CENTRE_Y, centre.z
	)

	var tool: SurfaceTool = Kit.begin()
	# Bracket back to the wall, so the sign is hanging off something.
	Kit.box(
		tool,
		Kit.at(Vector3(side * 0.13, 0.0, 0.0)),
		Vector3(0.26, 0.04, 0.04),
		Palette.deep(accent)
	)
	# Plaque: a soft accent board with a cream face, so the destination reads by
	# COLOUR before the child has focused on either the glyph or the word. The
	# accent is only a 2 cm rim now rather than a solid slab -- at the old size a
	# saturated board was the brightest thing in the room and pulled the eye off
	# the furniture the beat was actually about.
	Kit.extrude(tool, Kit.at(Vector3.ZERO), Kit.arch(SIGN_SIZE, 0.12, 6),
			SIGN_DEPTH, accent, 0.012)
	Kit.extrude(tool, Kit.at(Vector3(0.0, 0.0, SIGN_DEPTH * 0.55)),
			Kit.arch(SIGN_SIZE - Vector2(0.07, 0.07), 0.09, 6), 0.018,
			Palette.CREAM, 0.009)
	_build_room_glyph(tool, to_room, SIGN_DEPTH * 0.9, accent)

	var mesh: MeshInstance3D = _add_mesh("DoorSign_%s" % to_room, Kit.commit(tool), false)
	if mesh == null:
		return
	mesh.position = origin

	var label := Label3D.new()
	label.name = "DoorSignLabel_%s" % to_room
	label.text = HouseLayout.display_name(to_room).to_upper()
	# Smaller board, smaller word -- but still `ink` on `cream`, and that was
	# tried the other way first. A word set in the plaque's own deepened accent
	# looked calmer in isolation and vanished in the room: `deep(peach)` on a
	# cream face, 40 px wide at gameplay distance, is pastel on pastel. The word
	# is the secondary element by SIZE, not by contrast.
	label.font_size = 48
	label.pixel_size = 0.00104
	label.modulate = Palette.INK
	label.outline_size = 0
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.position = origin + Vector3(0.0, -0.101, SIGN_DEPTH * 1.1)
	_geometry.add_child(label)


## One chunky painted symbol per destination, drawn from the same primitives as
## the furniture so it belongs to the house. Deliberately simple shapes: at
## gameplay distance a detailed icon becomes a smudge, so this is the big element
## and the word underneath is the small one -- a four-year-old who cannot read
## "KITCHEN" can still learn "the door with the plate on it".
##
## `z` is depth towards the camera; x/y are in the sign's face.
##
## `GLYPH_SCALE` is 0.78 against a board that shrank by 0.65, which is the whole
## point: on a smaller sign the picture keeps more of the face and the word gives
## some up, because the picture is the half that works on a pre-reader.
const GLYPH_SCALE: float = 0.78
## Centre of the picture in the sign's face; the word sits below it.
const GLYPH_Y: float = 0.046


func _build_room_glyph(tool: SurfaceTool, room: String, z: float, accent: Color) -> void:
	var ink: Color = Palette.deep(accent)
	var s: float = GLYPH_SCALE
	var y: float = GLYPH_Y
	var face: Color = Palette.CREAM
	match room:
		HouseLayout.BEDROOM:
			# A bed: base, headboard, pillow.
			Kit.box(tool, Kit.at(Vector3(0.02 * s, y - 0.03 * s, z)),
					Vector3(0.30 * s, 0.075 * s, 0.02), ink)
			Kit.box(tool, Kit.at(Vector3(-0.15 * s, y + 0.03 * s, z)),
					Vector3(0.05 * s, 0.14 * s, 0.02), ink)
			Kit.box(tool, Kit.at(Vector3(-0.07 * s, y + 0.035 * s, z + 0.01)),
					Vector3(0.09 * s, 0.05 * s, 0.02), face)
		HouseLayout.BATHROOM:
			# A tub with a water drop above it.
			Kit.box(tool, Kit.at(Vector3(0.0, y - 0.045 * s, z)),
					Vector3(0.30 * s, 0.09 * s, 0.02), ink)
			Kit.sphere(tool, Kit.at(Vector3(0.0, y + 0.075 * s, z)), 0.05 * s, ink, 12, 7)
		HouseLayout.KITCHEN:
			# A plate, with a spoon beside it.
			Kit.sphere(tool, Kit.at(Vector3(-0.02 * s, y, z - 0.02)), 0.105 * s, ink, 16, 8)
			Kit.sphere(tool, Kit.at(Vector3(-0.02 * s, y, z + 0.005)), 0.072 * s, face, 16, 8)
			Kit.box(tool, Kit.at(Vector3(0.15 * s, y, z)),
					Vector3(0.028 * s, 0.17 * s, 0.02), ink)
			Kit.sphere(tool, Kit.at(Vector3(0.15 * s, y + 0.085 * s, z)), 0.035 * s, ink, 10, 6)
		HouseLayout.LIVING_ROOM:
			# A sofa: seat plus two arms.
			Kit.box(tool, Kit.at(Vector3(0.0, y - 0.025 * s, z)),
					Vector3(0.30 * s, 0.08 * s, 0.02), ink)
			Kit.box(tool, Kit.at(Vector3(0.0, y + 0.045 * s, z - 0.005)),
					Vector3(0.22 * s, 0.07 * s, 0.02), face)
			for arm: int in [-1, 1]:
				Kit.box(tool, Kit.at(Vector3(float(arm) * 0.135 * s, y + 0.035 * s, z)),
						Vector3(0.05 * s, 0.12 * s, 0.02), ink)
		_:
			Kit.sphere(tool, Kit.at(Vector3(0.0, y, z)), 0.09 * s, ink, 12, 7)


## Containers the child can open and put things into.
##
## The LID is the whole reason this is not just another `_prop()`: "open" and
## "closed" have to be visibly different states, and a colour change would not
## read at gameplay distance. So the lid is its own node with its own pivot, and
## opening it swings it back on the hinge -- an unmistakable silhouette change
## that a three-year-old reads instantly and that needs no text.
##
## Built from `HouseLayout.storages()`, with no per-room branch here: a new
## container is a row of data.
const LID_THICKNESS: float = 0.055
const LID_SWING_SECONDS: float = 0.28

var _storage_lids: Dictionary = {}
var _storage_models: Dictionary = {}


func _build_storages() -> void:
	var StorageModel := preload("res://scripts/gameplay/storage_model.gd")
	for row: Dictionary in HouseLayout.storages(room_id):
		var storage_id: String = String(row["storageId"])
		var size: Vector3 = row["size"]
		var centre: Vector3 = row["position"]
		var color: Color = row["color"]

		# Body: a box with its top open, so an item dropped in has somewhere to be.
		var body_tool: SurfaceTool = Kit.begin()
		var wall: float = 0.055
		Kit.box(body_tool, Kit.at(Vector3(0.0, -size.y * 0.5 + wall * 0.5, 0.0)),
				Vector3(size.x, wall, size.z), Palette.deep(color))
		for sx: int in [-1, 1]:
			Kit.box(body_tool, Kit.at(Vector3(float(sx) * (size.x - wall) * 0.5, 0.0, 0.0)),
					Vector3(wall, size.y, size.z), color)
		for sz: int in [-1, 1]:
			Kit.box(body_tool, Kit.at(Vector3(0.0, 0.0, float(sz) * (size.z - wall) * 0.5)),
					Vector3(size.x - wall * 2.0, size.y, wall), color)
		var body: MeshInstance3D = _add_mesh("Storage_%s" % storage_id, Kit.commit(body_tool))
		if body != null:
			body.position = centre

		# Lid, hinged along the BACK edge so it opens away from the camera and
		# never covers the opening the child is aiming at.
		var open_degrees: float = float(row.get("openDegrees", 0.0))
		if open_degrees > 0.0:
			var hinge := Node3D.new()
			hinge.name = "StorageLid_%s" % storage_id
			hinge.position = centre + Vector3(0.0, size.y * 0.5, -size.z * 0.5)
			_geometry.add_child(hinge)

			var lid_tool: SurfaceTool = Kit.begin()
			Kit.box(lid_tool, Kit.at(Vector3(0.0, LID_THICKNESS * 0.5, size.z * 0.5)),
					Vector3(size.x, LID_THICKNESS, size.z), Palette.light(color))
			Kit.box(lid_tool, Kit.at(Vector3(0.0, LID_THICKNESS + 0.018, size.z * 0.5)),
					Vector3(size.x * 0.30, 0.036, 0.09), Palette.deep(color))
			var lid := MeshInstance3D.new()
			lid.name = "Lid"
			lid.mesh = Kit.commit(lid_tool)
			lid.material_override = Kit.material()
			hinge.add_child(lid)
			_storage_lids[storage_id] = hinge

		var model: RefCounted = StorageModel.from_dict({
			"storageId": storage_id,
			"acceptedItemTags": row.get("acceptedItemTags", []),
			"capacity": row.get("capacity", 4),
		})
		_storage_models[storage_id] = model

		_add_collider("Storage_%sBody" % storage_id, size, centre)
		_add_target(
			storage_id,
			String(row.get("displayName", storage_id)),
			size + Vector3(0.18, 0.10, 0.18),
			centre,
			row["stand"] as Vector3,
			["open", "putAway"]
		)


## The storage domain objects this room owns, keyed by local id. The activity
## asks the ROOM for its containers rather than reaching into the scene tree.
func get_storages() -> Dictionary:
	build()
	return _storage_models.duplicate()


func get_storage(storage_id: String) -> RefCounted:
	build()
	return _storage_models.get(storage_id, null)


## Opens or closes a container and swings its lid to match. Returns the new open
## state. The model and the mesh are moved together here so they cannot disagree
## -- a lid that says open while the model refuses items is the worst outcome.
func set_storage_open(storage_id: String, open_it: bool) -> bool:
	build()
	var model: RefCounted = _storage_models.get(storage_id, null)
	if model == null:
		return false
	if open_it:
		model.call("open")
	else:
		model.call("close")
	_swing_lid(storage_id, open_it)
	return open_it


func toggle_storage(storage_id: String) -> bool:
	build()
	var model: RefCounted = _storage_models.get(storage_id, null)
	if model == null:
		return false
	return set_storage_open(storage_id, not bool(model.get("is_open")))


func is_storage_open(storage_id: String) -> bool:
	build()
	var model: RefCounted = _storage_models.get(storage_id, null)
	return model != null and bool(model.get("is_open"))


func _swing_lid(storage_id: String, open_it: bool) -> void:
	var hinge: Node3D = _storage_lids.get(storage_id, null)
	if hinge == null:
		return
	var degrees: float = 0.0
	for row: Dictionary in HouseLayout.storages(room_id):
		if String(row["storageId"]) == storage_id:
			degrees = float(row.get("openDegrees", 0.0))
			break
	var target: float = -degrees if open_it else 0.0
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	if tree == null:
		# Headless: snap. A test asserts the END state, and there is no frame loop
		# to tween on.
		hinge.rotation_degrees.x = target
		return
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(hinge, "rotation_degrees:x", target, LID_SWING_SECONDS)


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
