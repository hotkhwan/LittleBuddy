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
	var dominant: Color = _panel_color()
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


## Which of §3's three steps the wainscot takes, and the rule is about the FLOOR
## rather than about taste.
##
## `deep(dominant)` used to be applied in all four rooms, for a reason that was
## only ever true in two of them: the kitchen and the living room are both
## dominant-`peach` and the floorboards are `peach`, so a full-strength wainscot
## was the same value as the boards in front of it and the room lost its horizon.
##
## Applied to the other two it was a straight loss. `deep(dustyBlue)` is a cold
## slate grey, and it was 0.7 m tall on all three walls of the bathroom -- the
## single largest field of colour in that room, and the one thing in the house
## that read as an institution rather than as a home. `deep(lavender)` is the
## same grey-mauve §3 already rejected for the nursery basket ("cold, the least
## appealing object in the house"), and it was wrapped round the baby's room.
##
## So the step is chosen against the floor: a dominant that would disappear into
## `peach` boards is deepened, and one that already contrasts with them is used at
## full strength, which is what §3's room-mood table actually asks for. Both
## values are §3 tokens or its documented `deep` derivation either way.
func _panel_color() -> Color:
	var dominant: Color = HouseLayout.dominant_color(room_id)
	var floor_tone: Color = HouseLayout.floor_color(room_id)
	var difference: float = maxf(
		absf(dominant.r - floor_tone.r),
		maxf(absf(dominant.g - floor_tone.g), absf(dominant.b - floor_tone.b))
	)
	if difference < 0.10:
		return Palette.deep(dominant)
	return dominant


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
	_build_curtains(tool)


## -- Curtains ------------------------------------------------------------------
##
## The one addition that changes every room at once, and the cheapest warmth in
## the house after the window itself.
##
## Before this, the top third of all three walls was an unbroken 1.3 m field of
## `cream` in every room -- the largest single area in the shot, carrying nothing.
## The window sat in the middle of it as a pale blue rectangle with a cream frame
## on a cream wall, which is a hole, not a window. A window is only warm when
## something soft hangs beside it.
##
## Three decisions, each of which was the alternative's problem:
##
##   * **Beside the glass, never over it.** The first pass hung a valance across
##     the window head and two panels over the frame, and both rooms came back
##     with the window looking like a *picture frame in the accent colour* rather
##     than like a window with curtains: the cloth ringed the glass on three
##     sides and the cream frame stopped reading at all. The panels now stop at
##     the glass edge and there is no valance -- a pole above the head does the
##     same tying-together job without covering anything.
##   * **Three lobes with a scalloped hem, not a panel.** A flat rectangle of
##     accent beside a window is a poster. What makes cloth read in a style with
##     no textures and almost no shading (§7) is the break between the lobes, the
##     middle one standing proud and a step lighter, and a hem that is not a
##     straight line.
##   * **Sill length, not floor length.** The sill is 20 cm deep and stands proud
##     of the wall, so a floor-length curtain either passes through it or has to
##     be pushed out in front of it, and in two rooms the counter and the bath are
##     immediately below. The hem stops just above the sill in all four rooms,
##     which is also what makes four rooms read as one home.
##
## No collider, nothing tappable, and it merges into the shell mesh, so this is
## zero extra draw calls and nothing new for a child to aim at.
const CURTAIN_TOP_Y: float = 2.04
const CURTAIN_HEM_Y: float = 1.02
const CURTAIN_POLE_Y: float = 2.085
## From the window's centre to each panel's centre. Set so the panels stop level
## with the glass: any further in and the cloth reads as a frame round the sky.
const CURTAIN_OFFSET_X: float = 0.66
const CURTAIN_WIDTH: float = 0.28
const CURTAIN_Z: float = 0.105


## The cloth colour: the room's accent -- except where the accent IS the sky.
##
## §3 gives the bedroom `dustyBlue` as its accent and §5 fixes the window sky at
## `#B8DBED`, and those two are four points apart on every channel. Rendered, the
## bedroom's first pair of curtains and the pane behind them were a single blue
## field with a cream frame lost inside it: the window stopped being a window.
## The nursery therefore hangs its DOMINANT instead, which is what a lavender
## nursery wants beside a blue window anyway. Every other room's accent is
## nowhere near the sky and is used as §3 intends.
##
## The test is on HUE and nothing else, and that is not fastidiousness: measured
## per channel, `mint` is 0.117 from the sky and `dustyBlue` is 0.118, so a
## channel-distance rule hung dusty-blue curtains in the bathroom -- whose accent
## is mint -- on the first run. By hue they are not close at all: 202 degrees
## against 154.
func _curtain_color() -> Color:
	var accent: Color = HouseLayout.accent_color(room_id)
	var gap: float = absf(accent.h - Kit.WINDOW_SKY.h)
	if minf(gap, 1.0 - gap) < 0.05:
		return HouseLayout.dominant_color(room_id)
	return accent


func _build_curtains(tool: SurfaceTool) -> void:
	var cloth: Color = _curtain_color()
	var facing := Vector3(-90.0, 0.0, 0.0)
	var span: float = (CURTAIN_OFFSET_X + CURTAIN_WIDTH * 0.5) * 2.0 + 0.14

	# The pole. A curtain needs something to hang FROM or it is a banner taped to
	# a wall, and a 4 cm wooden rod reads at gameplay distance where a track would
	# not. Wood, because it is the one warm dark line the top of the wall has.
	Kit.cylinder(
		tool,
		Kit.at_rotated(Vector3(WINDOW_CENTRE.x, CURTAIN_POLE_Y, INNER_Z + CURTAIN_Z),
				Vector3(0.0, 0.0, 90.0)),
		0.021, span, Palette.deep(HouseLayout.WOOD_COLOR), 10, 0.008
	)
	for side: float in [-1.0, 1.0]:
		Kit.sphere(tool, Kit.at(Vector3(WINDOW_CENTRE.x + side * span * 0.5,
				CURTAIN_POLE_Y, INNER_Z + CURTAIN_Z)), 0.042,
				Palette.deep(HouseLayout.WOOD_COLOR), 10, 5)

	var pleat: float = CURTAIN_WIDTH / 3.0
	for side: float in [-1.0, 1.0]:
		var centre_x: float = WINDOW_CENTRE.x + side * CURTAIN_OFFSET_X
		for index: int in range(3):
			var at_x: float = centre_x - CURTAIN_WIDTH * 0.5 + pleat * (float(index) + 0.5)
			var middle: bool = index == 1
			# The middle lobe hangs 4 cm shorter, which is the whole scalloped hem:
			# three lobes cut off on one line is a board with grooves in it.
			var hem: float = CURTAIN_HEM_Y + (0.045 if middle else 0.0)
			var drop: float = CURTAIN_TOP_Y - hem
			Kit.plate(
				tool,
				Kit.at_rotated(Vector3(at_x, hem + drop * 0.5,
						INNER_Z + CURTAIN_Z + (0.014 if middle else 0.0)), facing),
				Kit.rounded_rect(Vector2(pleat * 1.34, drop), pleat * 0.52, 3),
				0.045,
				Palette.light(cloth) if middle else cloth,
				0.012
			)


## One rug per room (§5), in the room's dominant colour, sized and placed to sit
## under whatever the child plays with in that room.
func _build_rug(tool: SurfaceTool) -> void:
	var rug: Dictionary = _rug_placement()
	if rug.is_empty():
		return
	var size: Vector2 = rug["size"]
	var at: Vector2 = rug["at"]
	var accent: Color = HouseLayout.accent_color(room_id)
	# A BORDER and a paler field, rather than one flat slab of accent, and it buys
	# two things for ~90 triangles. A 2 m plate of saturated mint or dusty blue is
	# the largest single colour in the room shot and it was competing with the
	# child standing on it; dropping the middle to `light()` puts the strongest
	# value where the eye should go (her, and whatever she is carrying) and leaves
	# the accent as a frame. And a rug with a border reads as a RUG -- without one
	# a rounded rectangle of flat colour on floorboards reads as spilt paint.
	Kit.plate(
		tool,
		Kit.at(Vector3(at.x, HouseLayout.FLOOR_Y + 0.008, at.y)),
		Kit.rounded_rect(size, minf(size.x, size.y) * 0.22, 4),
		0.016,
		accent,
		0.005
	)
	var field: Vector2 = size - Vector2(0.26, 0.26)
	Kit.plate(
		tool,
		Kit.at(Vector3(at.x, HouseLayout.FLOOR_Y + 0.013, at.y)),
		Kit.rounded_rect(field, minf(field.x, field.y) * 0.20, 4),
		0.010,
		Palette.light(accent),
		0.004
	)
	# Four spots on the field, and they are what turns a rug into a rug that was
	# CHOSEN. A border round a plain field reads as a mat; a pattern reads as
	# something somebody picked for this room, which is §5's "tidy but lived-in"
	# in the one place it costs nothing -- the rug is a flat plate with no
	# collider, so the navigation bake never sees any of this.
	#
	# Six spots round the field's edge, rather than a scatter or a grid: at
	# gameplay distance a grid becomes a texture (and §7 has no textures), and a
	# scatter reads as mess.
	#
	# Six and not four, because the CHILD stands in the middle of the rug. Four at
	# the corners left the kitchen and the bedroom showing one visible spot with
	# the rest behind her, and one lone circle on a plain field does not read as a
	# pattern -- it reads as a mark. Two more at the mid-sides mean at least three
	# are always clear of her, in every room.
	#
	# `cream`, and that was drawn in the ACCENT first and looked at: a dot the
	# same colour as the border, sitting on that border's `light()` step, has the
	# value of a shadow and none of the shape of one, and it read as a hole in the
	# rug. Cream is the house's base note -- it is already the mattress, the sill
	# and the window frames -- and a cream spot on a pale field is unambiguously a
	# pattern.
	var spot: float = minf(field.x, field.y) * 0.072
	# PULLED IN off the corners. The offsets below were set against the field's
	# rectangular extent, but the rug is a ROUNDED rect -- at the old +/-0.56,
	# +/-0.54 the corner spots landed exactly where the corner radius has cut the
	# rug away, so they sat half on the floorboards and read as stains rather
	# than as a pattern. The mid-edge pair had the same problem at 0.62.
	var spots: Array = [
		Vector2(-0.40, -0.39), Vector2(0.40, -0.39),
		Vector2(-0.40, 0.39), Vector2(0.40, 0.39),
		Vector2(-0.47, 0.0), Vector2(0.47, 0.0),
	]
	for spot_at: Vector2 in spots:
		Kit.plate(
			tool,
			Kit.at(Vector3(at.x + spot_at.x * field.x, HouseLayout.FLOOR_Y + 0.018,
					at.y + spot_at.y * field.y)),
			Kit.circle(spot, 14), 0.008, Palette.CREAM, 0.003
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
			# Grown from 1.85 x 1.35. It was the smallest rug in the house by a
			# clear margin, in the room with the emptiest floor, and at the wide
			# iPhone aspect the near half of the bathroom was three metres of bare
			# boards with a child standing on a mat in the middle of them. A rug is
			# free floor dressing -- a flat plate with no collider, so the navigation
			# bake never sees it -- and this one still clears the bath mat at
			# z = -0.72 and both dressing corners at x = +/-1.76.
			return {"size": Vector2(2.10, 1.60), "at": Vector2(0.10, 0.85)}
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
			_bathroom_fixtures(tool)
		HouseLayout.KITCHEN:
			_kitchen_fixtures(tool)
		HouseLayout.LIVING_ROOM:
			_gallery_wall(tool, accent)


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

	# Three sparkles drifting off to the right of the cloud, in the ONE colour §3
	# calls "the single most important colour in the game". They are why this wall
	# now reads at a glance rather than after a moment's looking: the cloud and
	# its charms are all the room's own lavender-and-blue, so until something warm
	# landed on that wall the whole composition was a single hue.
	#
	# Three, at three sizes, on a rising diagonal -- a row of equal marks is a
	# pattern and a scatter is a mess. They live in the gap between the cloud's
	# right lobe (x ~ -1.03) and the LEFT CURTAIN's outer edge (x -0.65), and the
	# middle one used to be at -0.66: with the curtains hung, half of it
	# disappeared behind the cloth and the rest read as something yellow caught in
	# the hem. It is at -0.78 now, and all three clear -0.70.
	#
	# They are CROSSED LOZENGES, not discs. Rendered as discs they read as three
	# yellow dots -- the kit has no five-point star outline, and two crossed
	# lozenges is the twinkle that shape is standing in for anyway.
	for star: Array in [[0.36, 0.17, 0.085], [0.44, 0.33, 0.058], [0.29, -0.09, 0.046]]:
		var radius: float = float(star[2])
		var centre := Vector3(x + float(star[0]), y + float(star[1]), INNER_Z + 0.032)
		for turn: float in [22.0, 112.0]:
			Kit.plate(
				tool,
				Kit.at_rotated(centre, Vector3(-90.0, 0.0, turn)),
				Kit.rounded_rect(Vector2(radius * 2.0, radius * 0.62), radius * 0.31, 3),
				0.028, Palette.STAR_EARNED, 0.007
			)


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
## The plan is `HouseLayout`'s (`WORKTOP_*`), because `kitchen_view.gd` stands
## the child's ingredients on the same 1.8 m plank and two files placing things
## on one surface by eye is how a bowl ends up half inside a hob.
##
## Left to right: hob, prep board, sink -- **the sink under the window**, which
## is where a sink is. The first version of this room had it in the dark
## left-hand corner under the wall units, with a bare stretch of worktop under
## the window; cold, that is a workbench, not a kitchen.
##
## The board is the piece that earns its place twice. `kitchen_view.gd` puts a
## carried item down at `WORKTOP_BOARD_X`, so it is the visible answer to "where
## does this go?", and it is the warm dark field that a cream bottle or a pale
## banana needs behind it -- on bare cream worktop, against a cream wall, an
## ingredient measured a handful of pale pixels on an iPad render, which is a
## gameplay defect and not a taste one.
const CUPBOARD_X: float = -1.15
const CUPBOARD_Y: float = 1.50
const CUPBOARD_SIZE: Vector2 = Vector2(1.26, 0.50)
const CUPBOARD_DEPTH: float = 0.30
## The tiled band between the worktop and the wall units. Left of the window,
## whose sill takes over as the splashback for the rest of the run.
const SPLASHBACK_X: float = -1.17
const SPLASHBACK_SIZE: Vector2 = Vector2(1.10, 0.30)


func _kitchen_fixtures(tool: SurfaceTool) -> void:
	var steel: Color = Palette.deep(Palette.DUSTY_BLUE)
	var top: float = HouseLayout.WORKTOP_Y

	# The sink: a real open basin. §6 wants visible interior depth in anything
	# that holds something, and a solid-topped basin reads as a cupboard door
	# lying flat -- which is exactly how the bath failed its first three passes.
	# It stands proud of the worktop rather than being sunk into it, because the
	# counter is a solid mesh and a recess would simply be filled by it.
	Kit.vessel(
		tool,
		Kit.at(Vector3(HouseLayout.WORKTOP_SINK_X, top + 0.055, HouseLayout.WORKTOP_SINK_Z)),
		Kit.rounded_rect(Vector2(0.44, 0.36), 0.10, 3),
		0.11, 0.035, 0.03,
		Palette.CREAM, Palette.DUSTY_BLUE
	)
	# The tap. §7: "there is no metal; 'metal' is a dusty-blue convention."
	Kit.cylinder(tool, Kit.at(Vector3(HouseLayout.WORKTOP_SINK_X, top + 0.12,
			HouseLayout.WORKTOP_SINK_Z - 0.17)), 0.024, 0.24, steel, 10)
	Kit.box(tool, Kit.at(Vector3(HouseLayout.WORKTOP_SINK_X, top + 0.235,
			HouseLayout.WORKTOP_SINK_Z - 0.112)),
			Vector3(0.044, 0.044, 0.14), steel, 0.014)

	# The hob: a plate and two rings. Two rings rather than four, because at this
	# camera distance four would merge into a texture, and the ring is the whole
	# reason this is a stove and not a chopping board.
	Kit.plate(tool, Kit.at(Vector3(HouseLayout.WORKTOP_HOB_X, top + 0.018,
			HouseLayout.WORKTOP_HOB_Z)),
			Kit.rounded_rect(Vector2(0.38, 0.32), 0.08, 3), 0.036, Palette.DUSTY_BLUE, 0.012)
	for side: float in [-1.0, 1.0]:
		Kit.torus(tool, Kit.at(Vector3(HouseLayout.WORKTOP_HOB_X + side * 0.092,
				top + 0.042, HouseLayout.WORKTOP_HOB_Z)),
				0.056, 0.013, steel, 14, 6)

	# The prep board. Deliberately the one WOOD-coloured thing on a cream worktop:
	# it is both the drop zone and the contrast the ingredients stand against.
	Kit.plate(
		tool,
		Kit.at(Vector3(HouseLayout.WORKTOP_BOARD_X,
				top + HouseLayout.WORKTOP_BOARD_THICKNESS * 0.5, HouseLayout.WORKTOP_BOARD_Z)),
		Kit.rounded_rect(HouseLayout.WORKTOP_BOARD_SIZE, 0.07, 3),
		HouseLayout.WORKTOP_BOARD_THICKNESS, HouseLayout.WOOD_COLOR, 0.012
	)

	# A pan on the hob. Two rings on a blue plate say "a flat thing with circles
	# on it"; a pan standing in one of them is what makes it a STOVE, and it is
	# the only object in the room that says food gets cooked here.
	#
	# It stands inside the hob's own footprint, so it takes nothing from the
	# worktop plan: `kitchen_view.gd` stands the child's ingredients between
	# x -1.02 and -0.58 and the hob is at -1.50.
	var pan_y: float = top + 0.10
	Kit.vessel(
		tool,
		Kit.at(Vector3(HouseLayout.WORKTOP_HOB_X - 0.092, pan_y,
				HouseLayout.WORKTOP_HOB_Z)),
		Kit.circle(0.092, 14), 0.115, 0.022, 0.02, steel, Palette.CREAM
	)
	Kit.plate(tool, Kit.at(Vector3(HouseLayout.WORKTOP_HOB_X - 0.092, pan_y + 0.062,
			HouseLayout.WORKTOP_HOB_Z)), Kit.circle(0.086, 14), 0.024,
			Palette.CREAM, 0.008)
	Kit.sphere(tool, Kit.at(Vector3(HouseLayout.WORKTOP_HOB_X - 0.092, pan_y + 0.090,
			HouseLayout.WORKTOP_HOB_Z)), 0.028, steel, 10, 5)
	# The handle, pointing into the room so it is a handle and not a stub.
	Kit.cylinder(tool, Kit.at_rotated(Vector3(HouseLayout.WORKTOP_HOB_X - 0.092,
			pan_y + 0.012, HouseLayout.WORKTOP_HOB_Z + 0.16),
			Vector3(90.0, 0.0, 0.0)), 0.018, 0.16, Palette.deep(HouseLayout.WOOD_COLOR), 8)

	_splashback(tool)
	_wall_cupboards(tool)
	_table_mat(tool)


## The placemat on the table, laid exactly where `kitchen_view.gd` serves a
## finished dish (`TABLE_MAT_FORWARD` of the table's centre).
##
## Read from the furniture table rather than typed as a coordinate, so a table
## that moves takes its mat with it.
func _table_mat(tool: SurfaceTool) -> void:
	for row: Dictionary in HouseLayout.furniture(room_id):
		if String(row["targetId"]) != "table":
			continue
		var size: Vector3 = row["size"]
		var centre: Vector3 = row["position"]
		Kit.plate(
			tool,
			Kit.at(Vector3(
				centre.x,
				centre.y + size.y * 0.5 + HouseLayout.TABLE_MAT_THICKNESS * 0.5,
				centre.z + size.z * HouseLayout.TABLE_MAT_FORWARD
			)),
			Kit.rounded_rect(HouseLayout.TABLE_MAT_SIZE, 0.06, 3),
			HouseLayout.TABLE_MAT_THICKNESS,
			# Two colours were tried and looked at before this one. The room's own
			# accent, `light(mint)`, is the EXACT colour of the rug's field, so the
			# mat matched the floor two metres behind it pixel for pixel and read
			# as a rectangular hole cut through the table. `light(dustyBlue)` fixed
			# that and brought its own problem: it is the coolest, least saturated
			# thing in a warm room and at the wide iPhone aspect it read as a grey
			# patch. `softPink` is warm, is nothing else in this kitchen, and is
			# the one value a cream bowl of pale yellow food sits cleanly on.
			Palette.SOFT_PINK,
			0.008
		)
		return


## The tiled band between the worktop and the wall units.
##
## Cheap, and it does more for "this is a kitchen" than any single prop: a
## horizontal accent at worktop height ties the counter, the hob and the
## cupboards into one run instead of three objects parked against a cream wall.
## Four tiles rather than a grid -- at this camera distance a real tile pattern
## merges into noise, and §7 has no textures to draw it with anyway.
##
## ## The field is the accent at FULL strength, and it was `light()` first
##
## Rendered, `light(mint)` behind cream tiles is cream behind cream: the panel
## existed in the mesh and could not be found in the picture, and the whole run
## was still a beige wall. The grout lines are the only thing the tiles have to
## say and they need a value under them to say it with. The kitchen has no other
## mint above worktop height, so this is also where the room gets its §3 accent.
func _splashback(tool: SurfaceTool) -> void:
	var base_y: float = HouseLayout.WORKTOP_Y + SPLASHBACK_SIZE.y * 0.5 + 0.01
	_tiles(
		tool,
		Vector2(SPLASHBACK_X, base_y),
		SPLASHBACK_SIZE,
		HouseLayout.accent_color(room_id),
		4
	)


## Wall units over the worktop -- the storage the fridge is not.
##
## Set to the LEFT of the window (which spans x -0.50 to 0.80) so nothing
## overlaps, and kept below 1.75 m so the room shot still holds them.
##
## The first pass of these read, cold, as a framed picture: a flat peach slab
## with two paler rectangles on it and two knobs too small to see. What fixes it
## is not more detail but the two things that say "cupboard" in silhouette -- a
## carcass with a visible UNDERSIDE (so it is a box hanging on a wall rather than
## a panel stuck to one) and handles that are BARS, which at 1.5 m read as two
## dark strokes where a sphere reads as nothing at all.
func _wall_cupboards(tool: SurfaceTool) -> void:
	var facing: Vector3 = Vector3(-90.0, 0.0, 0.0)
	var front: float = INNER_Z + CUPBOARD_DEPTH
	Kit.plate(
		tool,
		Kit.at_rotated(Vector3(CUPBOARD_X, CUPBOARD_Y, INNER_Z + CUPBOARD_DEPTH * 0.5), facing),
		Kit.rounded_rect(CUPBOARD_SIZE, 0.05, 3), CUPBOARD_DEPTH,
		HouseLayout.WOOD_COLOR, 0.018
	)
	# The underside lip: a shadow line under a wall unit is most of what tells the
	# eye it is hanging off the wall, and there are no shadows in this game (§7).
	Kit.box(
		tool,
		Kit.at(Vector3(CUPBOARD_X, CUPBOARD_Y - CUPBOARD_SIZE.y * 0.5 - 0.018,
				INNER_Z + CUPBOARD_DEPTH * 0.5 + 0.012)),
		Vector3(CUPBOARD_SIZE.x + 0.05, 0.036, CUPBOARD_DEPTH + 0.03),
		Palette.deep(HouseLayout.WOOD_COLOR), 0.012
	)
	# The doors take the room's ACCENT, a step lighter. They were `light(peach)`
	# on a `deep(peach)` carcass against a `cream` wall -- three values of one
	# warm neutral, which is why the first pass of these read as a framed picture
	# rather than as cupboards. Painted units are also simply what a kitchen a
	# four-year-old has been in looks like, and §3 gives this room `mint`.
	var door_face: Color = Palette.light(HouseLayout.accent_color(room_id))
	for side: float in [-1.0, 1.0]:
		Kit.plate(
			tool,
			Kit.at_rotated(Vector3(CUPBOARD_X + side * 0.305, CUPBOARD_Y, front + 0.012),
					facing),
			Kit.rounded_rect(Vector2(0.56, 0.40), 0.04, 3), 0.035, door_face, 0.012
		)
		# A bar handle on the door's inner edge, running down the door.
		Kit.box(
			tool,
			Kit.at(Vector3(CUPBOARD_X + side * 0.075, CUPBOARD_Y - 0.03, front + 0.05)),
			Vector3(0.026, 0.16, 0.026), Palette.deep(Palette.DUSTY_BLUE), 0.008
		)


## -- The living room's wall ------------------------------------------------------
##
## The living room was the plainest room in the house after the bathroom, and
## measurably so: above the sofa it had 1.3 m of unbroken `cream` carrying ONE
## 0.50 x 0.40 m frame whose mount was cream and whose picture was a pale pink
## rectangle on it. Cold, on a phone, there was nothing on that wall at all.
##
## Three frames at three sizes, hung as a group, is the single cheapest thing a
## room can have that says a family lives in it -- and unlike a fourth piece of
## furniture it costs no collider, no touch target and no navigation floor.
##
## They are hung to the LEFT of the window, because the right-hand half of that
## wall belongs to the toy box and the curtain, and the group is deliberately
## asymmetric: three frames in a row at one height is a corridor in an office.
func _gallery_wall(tool: SurfaceTool, accent: Color) -> void:
	# Three mounts, three §3 tokens, none of them `deep()`. The first version hung
	# the two small frames on `deep(peach)` and `deep(softPink)` and they came
	# back as two brown boxes: at 0.30 m across, a deepened pastel has no hue left
	# in it at this distance -- it is just a dark rectangle, and two dark
	# rectangles beside a pale one is not a gallery.
	_wall_picture(tool, -1.42, 1.50, Vector2(0.52, 0.42), accent, "blob")
	_wall_picture(tool, -0.92, 1.66, Vector2(0.30, 0.30), Palette.MINT, "arch")
	_wall_picture(tool, -0.92, 1.22, Vector2(0.30, 0.36), Palette.LAVENDER, "hill")
	_wall_clock(tool, 1.42, 1.54, accent)


## A framed picture. No text, no representational subject -- one soft shape, so
## it stays warm without competing with the object the room is teaching.
##
## The MOUNT is the picture's colour and the picture is drawn on it in cream.
## That is the other way round from the first version, and it is the difference
## between a frame that reads and one that does not: a cream mount on a cream
## wall inside a cream frame leaves nothing but a thin outline, and the pale
## shape floated on it was, at gameplay distance, invisible.
func _wall_picture(
	tool: SurfaceTool, x: float, y: float, size: Vector2, ink: Color, subject: String
) -> void:
	var facing: Vector3 = Vector3(-90.0, 0.0, 0.0)
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.03), facing),
			Kit.rounded_rect(size, 0.05, 3), 0.055, Palette.deep(Palette.CREAM), 0.018)
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.055), facing),
			Kit.rounded_rect(size - Vector2(0.10, 0.10), 0.04, 3), 0.03, ink, 0.01)
	var face: Color = Palette.CREAM
	match subject:
		"arch":
			Kit.plate(tool, Kit.at_rotated(Vector3(x, y - 0.02, INNER_Z + 0.075), facing),
					Kit.circle(size.y * 0.24, 16), 0.02, face, 0.006)
		"hill":
			for lobe: Array in [[-0.05, -0.03, 0.30], [0.05, 0.02, 0.24]]:
				Kit.plate(tool, Kit.at_rotated(Vector3(
						x + size.x * float(lobe[0]), y + size.y * float(lobe[1]),
						INNER_Z + 0.075), facing),
						Kit.circle(size.y * float(lobe[2]), 14), 0.02, face, 0.006)
		_:
			Kit.plate(tool, Kit.at_rotated(Vector3(x, y - 0.01, INNER_Z + 0.075), facing),
					Kit.rounded_rect(Vector2(size.x * 0.46, size.y * 0.46),
							size.y * 0.20, 3), 0.02, face, 0.006)


## A wall clock. Not a word this game teaches, which is exactly why it is safe
## (§6 -- "two nouns must never share a shape"), and it is the one object that
## fills a bare upper wall without inviting a tap that would do nothing.
func _wall_clock(tool: SurfaceTool, x: float, y: float, rim: Color) -> void:
	var facing: Vector3 = Vector3(-90.0, 0.0, 0.0)
	var hand: Color = Palette.deep(rim)
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.03), facing),
			Kit.circle(0.21, 20), 0.055, rim, 0.016)
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.062), facing),
			Kit.circle(0.168, 20), 0.026, Palette.CREAM, 0.008)
	# Four ticks rather than twelve: at gameplay distance twelve is a dotted ring.
	for quarter: int in range(4):
		var angle: float = TAU * float(quarter) / 4.0
		Kit.plate(
			tool,
			Kit.at_rotated(Vector3(x + cos(angle) * 0.132, y + sin(angle) * 0.132,
					INNER_Z + 0.078), facing),
			Kit.circle(0.017, 8), 0.014, hand, 0.004
		)
	# Ten past ten, because that is the shape a clock face is drawn in: two hands
	# low and together read as one stroke.
	for arm: Array in [[0.098, 62.0, 0.020], [0.132, 155.0, 0.016]]:
		var reach: float = float(arm[0])
		var turn: float = deg_to_rad(float(arm[1]))
		Kit.plate(
			tool,
			Kit.at_rotated(Vector3(x + cos(turn) * reach * 0.5, y + sin(turn) * reach * 0.5,
					INNER_Z + 0.082), Vector3(-90.0, 0.0, float(arm[1]))),
			Kit.rounded_rect(Vector2(reach, float(arm[2])), float(arm[2]) * 0.5, 2),
			0.014, hand, 0.004
		)


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
			# The one exception to the "pot takes the room's dominant" rule above,
			# and it is the baby's room that earns it. `deep(lavender)` rendered as
			# a grey-mauve pail and was, cold, the least appealing object in the
			# house -- it read as a bin standing next to a cot. §3 gives the
			# nursery `softPink` as its dominant, so a soft pink basket is both the
			# warmest thing on that side of the room and the correct note for it.
			return [plant, {
				"kind": "basket", "at": DRESSING_RIGHT, "height": 0.40,
				"color": Palette.SOFT_PINK,
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


## -- The bathroom's fixtures ----------------------------------------------------
##
## This was the plainest room in the house, and it was plain for one measurable
## reason: `mint` is its §3 accent and the only mint anywhere in it was the paler
## field of the rug. Sink, bath, towel rail, mirror glass and wainscot were all
## cream or dusty blue, so the room had one hue and two values.
##
## Four things fix it, and every one of them is what a real bathroom has:
##
##   * **A tiled band behind the basin.** The strongest "this room is a bathroom"
##     cue there is, the room's accent finally doing some work, and flat geometry
##     on a wall -- no collider, nothing to tap, nothing in the child's way.
##   * **Bubbles over the bath**, on the emptiest wall in the house.
##   * **A bath mat**, on the floor in front of the tub, exactly where the child
##     stands to use it. The bathroom's rug is the smallest in the house and the
##     far half of its floor was bare boards.
##   * **A bigger mirror with a coloured frame.** A 0.27 m cream disc on a cream
##     wall measured, cold, as a smudge.
func _bathroom_fixtures(tool: SurfaceTool) -> void:
	var accent: Color = HouseLayout.accent_color(room_id)
	# Behind the basin. Sized off the furniture table rather than typed out twice,
	# so a sink that moves takes its tiles with it.
	#
	# ## Wide and low -- it was tall and square first
	#
	# The first version tiled behind the BATH as well, each in a 0.42 m panel three
	# tiles across. Both came back reading as a grid of squares hung on the wall
	# rather than as a tiled surface, and the bath's was the worse of the two: the
	# tub stands half a metre proud of the wall it was tiled against, so its panel
	# floated in the air above it. The kitchen's splashback is the same function
	# and reads correctly for one reason -- it is long and low and it sits directly
	# on the worktop. A tiled panel has to be a BAND.
	#
	# So: one band, behind the basin only, much wider than the basin, starting just
	# above the chair rail -- whose top is at 0.75 and which stands 6.5 cm proud of
	# the wall, so anything lower is pierced by it. The bath wall gets bubbles
	# instead, which is the better answer for it anyway.
	for row: Dictionary in HouseLayout.furniture(room_id):
		if String(row["targetId"]) != "sink":
			continue
		var size: Vector3 = row["size"]
		var centre: Vector3 = row["position"]
		_tiles(tool, Vector2(centre.x, 0.925), Vector2(size.x + 0.52, 0.31), accent, 4)
	_bubbles(tool)
	# The mat. A flat plate at floor level, so it costs the navigation bake nothing
	# at all -- and it belongs precisely where the bath's authored stand point is,
	# which is the one place in this room where a mat is not an obstacle but the
	# whole reason you put one down.
	Kit.plate(
		tool,
		Kit.at(Vector3(0.95, HouseLayout.FLOOR_Y + 0.008, -0.72)),
		Kit.rounded_rect(Vector2(0.92, 0.52), 0.16, 4), 0.016, accent, 0.005
	)
	Kit.plate(
		tool,
		Kit.at(Vector3(0.95, HouseLayout.FLOOR_Y + 0.013, -0.72)),
		Kit.rounded_rect(Vector2(0.76, 0.36), 0.12, 4), 0.010,
		Palette.light(accent), 0.004
	)
	_mirror(tool, -1.20, 1.58, accent)


## Soap bubbles drifting up the wall over the bath.
##
## The bathroom's back wall to the right of the window is 1.0 m wide and 1.3 m
## tall and carried nothing at all -- the emptiest surface in the house. It is
## also the one wall a tiled band cannot help, because the tub stands half a
## metre proud of it.
##
## Bubbles are the right answer for three reasons. They are what this room is
## ABOUT, so they reinforce the words the level teaches rather than competing
## with them; "bubble" is not itself a word the vocabulary owns (it has `soap`,
## `water`, `bath`, `clean`, `wet` and `dry`), so §6's one-object-one-word rule
## is safe; and the nursery already establishes the house's convention that a
## wall may carry a soft drawn shape -- this is that room's cloud, for this room.
##
## Five, at five sizes, on a rising diagonal, for the reason the nursery's
## sparkles are written down with: a row of equal marks is a pattern and a
## scatter is a mess. Every one of them stays right of x = 1.00, clear of both
## the window (which ends at 0.80) and the right-hand curtain (which ends at
## 0.95).
##
## Each gets one cream catchlight, upper-left -- the same single-highlight rule
## §4 puts on the character's eyes, and what stops five flat discs reading as
## five holes.
func _bubbles(tool: SurfaceTool) -> void:
	var facing: Vector3 = Vector3(-90.0, 0.0, 0.0)
	var skin: Color = Palette.light(Palette.DUSTY_BLUE)
	for bubble: Array in [
		[1.16, 1.16, 0.088], [1.44, 1.48, 0.135], [1.76, 1.22, 0.068],
		[1.62, 1.84, 0.098], [1.14, 1.72, 0.056],
	]:
		var radius: float = float(bubble[2])
		var at := Vector3(float(bubble[0]), float(bubble[1]), INNER_Z + 0.03)
		Kit.plate(tool, Kit.at_rotated(at, facing), Kit.circle(radius, 16), 0.04,
				skin, 0.010)
		Kit.plate(
			tool,
			Kit.at_rotated(at + Vector3(-radius * 0.34, radius * 0.34, 0.022), facing),
			Kit.circle(radius * 0.26, 10), 0.016, Palette.CREAM, 0.005
		)


## A tiled panel: a field of colour with a grid of paler tiles standing proud of
## it, so the grout lines are real grooves that the one directional light can
## find. `columns` tiles across, two courses high.
##
## Deliberately a small number of big tiles. At this camera distance a real tile
## pattern merges into noise, and §7 has no textures to draw one with anyway.
##
## The tiles are the field's own `light()` step and NOT `cream`, which is what
## they were on the first render. Cream tiles on a cream wall left only the grout
## lines visible, and a panel of mint grout lines with nothing behind them reads
## as wire mesh -- the bathroom came back looking like it had two racks bolted to
## the wall. The field has to be the mass and the tiles the highlight, not the
## other way round.
func _tiles(
	tool: SurfaceTool, centre: Vector2, size: Vector2, color: Color, columns: int
) -> void:
	var facing: Vector3 = Vector3(-90.0, 0.0, 0.0)
	Kit.plate(
		tool,
		Kit.at_rotated(Vector3(centre.x, centre.y, INNER_Z + 0.02), facing),
		Kit.rounded_rect(size, 0.035, 2), 0.04, color, 0.012
	)
	var wide: float = size.x / float(columns)
	var high: float = size.y * 0.5
	for column: int in range(columns):
		for course: int in range(2):
			Kit.plate(
				tool,
				Kit.at_rotated(Vector3(
					centre.x - size.x * 0.5 + wide * (float(column) + 0.5),
					centre.y - size.y * 0.5 + high * (float(course) + 0.5),
					INNER_Z + 0.045), facing),
				Kit.rounded_rect(Vector2(wide - 0.028, high - 0.028), 0.022, 2),
				0.018, Palette.light(color), 0.008
			)


func _mirror(tool: SurfaceTool, x: float, y: float, frame: Color) -> void:
	var facing: Vector3 = Vector3(-90.0, 0.0, 0.0)
	# The frame takes the room's accent. A cream disc on a cream wall was, cold,
	# a smudge -- the mirror is the only thing on this wall at eye height and it
	# has to be found before it can read as a mirror.
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.03), facing),
			Kit.circle(0.31, 20), 0.055, frame, 0.018)
	# No reflection, no transparency (§7): a pale flat disc reads as a mirror
	# because of where it is, not because of what it does.
	Kit.plate(tool, Kit.at_rotated(Vector3(x, y, INNER_Z + 0.062), facing),
			Kit.circle(0.252, 20), 0.024, Palette.light(Palette.DUSTY_BLUE), 0.008)


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
		_storage_front(body_tool, size, color)
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


## The front of a container, painted.
##
## A toy box is a container the child is meant to want to open, and both of them
## were drawn as five slabs of one flat colour with a knob on the lid. Cold, the
## bedroom's read as a green crate and the living room's as a pink crate -- the
## two most saturated objects in their rooms, each carrying no information at all
## about what it is for.
##
## A recessed panel and a painted motif on the face the camera sees costs nothing
## that matters: it is inside the container's existing collider and its existing
## `ActivityTarget` box, so the tap target is still the whole box, and it goes
## into the body's own `SurfaceTool`, so it is still one draw call.
##
## The motif is a plain disc. It cannot be a picture of a toy -- §6 is explicit
## that two nouns must never share a shape, and `ball`, `blocks`, `teddy` and
## `toy` are all words this game teaches elsewhere.
func _storage_front(tool: SurfaceTool, size: Vector3, color: Color) -> void:
	var front: float = size.z * 0.5 + 0.004
	Kit.plate(
		tool,
		Kit.at_rotated(Vector3(0.0, -0.01, front), Vector3(-90.0, 0.0, 0.0)),
		Kit.rounded_rect(Vector2(size.x - 0.20, size.y - 0.14), 0.05, 3), 0.03,
		Palette.light(color), 0.012
	)
	Kit.plate(
		tool,
		Kit.at_rotated(Vector3(0.0, -0.01, front + 0.018), Vector3(-90.0, 0.0, 0.0)),
		Kit.circle(size.y * 0.20, 16), 0.018, Palette.CREAM, 0.006
	)
	# A plinth band, so the box stands on something instead of just stopping at
	# the floor. Two centimetres proud is all a bevelled edge needs to catch the
	# sun, and it is the same trick the wall units' underside lip uses.
	Kit.box(
		tool,
		Kit.at(Vector3(0.0, -size.y * 0.5 + 0.035, 0.0)),
		Vector3(size.x + 0.02, 0.07, size.z + 0.02), Palette.deep(color), 0.016
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
