extends Node3D

## Where a task's objects and landing pads actually are, in the room.
##
## The Baby Room stages a task with `ActivityScene`: a fixed spawn row in front
## of a baby that never moves, and drop zones glued to the baby's mouth and
## chest. Neither assumption survives a toddler who walks: the objects have to
## appear wherever the beat happens -- at the sink, at the table, at the toy box
## -- and the pads have to follow a character across a 4 m room.
##
## So this is the house's equivalent of `ActivityScene`, and it deliberately
## speaks the SAME context vocabulary (`objectAnchor`, `spawnPoints`,
## `dropZones`), because that is what lets the existing, tested mode handlers run
## here untouched. No mode handler knows it is in a house.
##
## ## Two kinds of landing pad, which is the whole drag design
##
##   * **On Little Buddy** -- `mouth`, `hug`, `dress`, `hand`. Drag the milk to
##     the toddler. The pad follows him every frame, so it is correct whether he
##     is standing at the table or half way across the kitchen.
##   * **On the furniture** -- `toyBox`, `bath`. Drag the blocks to the toy box.
##     The pad sits on the task's semantic target.
##
## Both are generous (a child aims with a whole hand), and a tap on the object
## always delivers it anyway -- `DraggableObject` routes tap and drag into one
## latch, so a child who cannot drag is never locked out.
##
## ## Layers
##
## Nothing here touches collision layers. Spawned pickups stay on layer 1 and
## activity targets on layer 2, exactly as `test_architecture_guard` requires;
## a drop zone is not a physics volume at all -- it is a named position and a
## radius, tested geometrically.
##
## ## Objects belong where they live
##
## This file used to lay every choice out in a fixed row in front of the child,
## and said so: *"the row goes where the CHILD will be, never where the furniture
## is."* Played on a phone, that is exactly what it looked like -- a toothbrush,
## a bar of soap and a towel materialising at a toddler's feet in the middle of
## the floor, in the same place, in every room, for every task. The owner's note
## was short: *the items we are given to choose should be placed at their
## positions in the room.*
##
## So the objects are now a small cluster placed against the piece of furniture
## the task is ABOUT, and the place is derived rather than listed per task:
##
##   1. the task's own `focusTargetId` -- `bathroom.sink`, `kitchen.fridge`,
##      `livingRoom.toyBox` -- resolved to the LIVE `ActivityTarget` in the scene,
##      so moving a prop moves its objects with it and no coordinate is copied
##      here;
##   2. failing that, the object's `category` from `content/objects.json` through
##      `CATEGORY_HOME_TARGETS`: clothes belong at the wardrobe, food at the
##      table, bath things at the sink, toys at the toy box, bedding at the bed.
##      This is what places the dressing tasks, which name no target at all;
##   3. failing that -- an unknown room, a target in a room the child is not in --
##      the old row at the child's feet, unchanged. A layout that cannot be
##      derived must still be reachable.
##
## The target's own `standPosition` supplies the geometry: it is the authored,
## navigable, child-reachable point in front of that furniture, so the direction
## from the furniture to it is the direction the row must be laid along, and the
## distance to it is how far out the row belongs. Nothing here guesses which way
## a sink faces.

const DropZoneScript := preload("res://scripts/gameplay/drop_zone.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const ObjectSpawnerScript := preload("res://scripts/gameplay/object_spawner.gd")

const ANCHOR_NAME: String = "ObjectAnchor"

## Spawn row, local to the anchor. Four slots, 0.46 m apart: wide enough that two
## 0.34 m grab colliders never overlap (a child's tap must be unambiguous), and
## narrow enough that the whole row stays inside a 4 m room.
const SPAWN_SPACING: float = 0.46
const SPAWN_SLOTS: int = 4
const SPAWN_LIFT: float = 0.02

## Derived layouts are a 2x2 cluster rather than a 1x4 line, and this is the
## spacing of its second rank -- towards the room's open side, away from the
## furniture.
##
## A line of four at `OBJECT_SCALE` is 3.1 m wide. Laid against a sink in a 4 m
## room it reaches both corners, which is not "the things at the sink", it is the
## old row moved backwards; rendered, its end object ended up leaning on a plant
## pot in the corner. A 2x2 is about 1.0 x 0.95 m and sits beside the furniture
## like a set of things somebody put down there.
##
## Slightly under `SPAWN_SPACING` because depth separates on screen more cheaply
## than width does: the camera looks down at 32 degrees, so a metre of depth is
## both a vertical offset and a size change.
const SPAWN_DEPTH_SPACING: float = 0.44

## Cluster order, so that any CONTIGUOUS run of slots still reads as a group --
## `ModeHandler._spawn_points_for()` centres a short choice set by slicing, so a
## 3-object row gets slots 0..2 and a 1-object row gets slot 1.
##
##   0 back-left   1 front-left   2 front-right   3 back-right
##
## `x` is along the face of the furniture, `z` is towards the room's open side.
const CLUSTER_SLOTS: Array[Vector2] = [
	Vector2(-0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5),
]

## The whole row is scaled up, on the ANCHOR rather than on the objects.
##
## `ObjectSpawner` sizes a pickup for the Baby Room's close camera (a 0.34 m grab
## collider, measured there at >= 220 px). The house camera frames a whole 4 m
## room from across it, and the same object lands at about a third of that on a
## 1334 px landscape iPad -- too small for a four-year-old's finger. Scaling the
## anchor multiplies the visual, the collider AND the spacing together, and
## leaves each object's own `scale` at 1 so the pickup/return/settle tweens in
## `DraggableObject` still animate to the right size.
const OBJECT_SCALE: float = 1.8

## Extra scale for a row that sits at the BACK of the room, where the camera is
## further away and everything is smaller.
##
## Measured, not guessed. `unproject_position()` on the grab collider's two edges,
## in a real 1334x616 landscape-phone frame: the old row at the front of the room
## presented a 98 px touch target, and the same object at the sink or the fridge
## presented 63 px. Putting objects where they belong costs on-screen size, and a
## four-year-old's finger does not care about the reason.
##
## Full compensation is not available -- it would need 2.8x, which is a 3.9 m row
## in a 4 m room and an apple the size of a fridge shelf. 1.28x at the back wall
## recovers the target to ~80 px while the whole row still fits inside the floor
## with the spacing that keeps two grab colliders from ever overlapping.
const DEPTH_SCALE_MAX: float = 1.28

## How far in front of the beat the row is laid out, towards the room's open
## front -- i.e. towards the camera, between the toddler and the viewer, where a
## child's fingers can reach on an iPad held in landscape. Used only by the
## fallback layout now: see `_resolve_place()`.
const ROW_FRONT_OFFSET: float = 0.78
## Keeps the row off the walls whatever the beat is standing next to.
const ROW_MARGIN: float = 0.75

## -- Where a task's objects belong --------------------------------------------

## Object category -> the local target id of the furniture it lives at. Derived
## from `content/objects.json`'s own `category` field, which every object already
## carries, so adding an object never needs an edit here -- only a brand new
## CATEGORY would. Five entries, one per category the content ships.
const CATEGORY_HOME_TARGETS: Dictionary = {
	"feeding": "table",
	"dressing": "wardrobe",
	"bath": "sink",
	"play": "toyBox",
	"bedtime": "bed",
}

## For a beat with NO walk (`findIt`, `sayIt`, the dressing tasks): the row sits
## this fraction of the way from the furniture out towards its stand point, so
## the objects hug the thing they belong to. The child is somewhere else entirely
## and is not standing in them.
const SHELF_INSET: float = 0.72
## For a beat the child DOES walk to: he will be standing on the stand point, so
## the row goes past him, out towards the room's open side. Objects laid between
## him and the furniture would be behind him from the camera.
const SHELF_PAST_CHILD: float = 0.50
## However close a piece of furniture's stand point is, never lay the row on top
## of the furniture itself.
const SHELF_MIN: float = 0.34

## How far an object must stay clear of any furniture footprint. An object's
## visual reaches about 0.23 m from its centre at `OBJECT_SCALE`, so this leaves
## a real gap rather than a touching edge -- a toy half inside the bath is a toy
## the child will try to grab and miss.
const PLACE_CLEARANCE: float = 0.26
## A blocked slot is pushed out towards the room's open side in these steps until
## it is clear. Bounded: a slot that cannot be freed keeps its least-bad position
## rather than disappearing.
const PLACE_STEP: float = 0.28
const PLACE_STEP_COUNT: int = 6
## Keeps every object inside the walkable floor. Larger than the 0.20 m
## navigation agent radius, so anything the child can see, the child can reach.
const PLACE_EDGE_MARGIN: float = 0.34

## Furniture at least this tall, standing between the camera and an object, hides
## it. A 0.45 m sofa seat or bed does not (you see over it from 32 degrees up); a
## 0.7 m table or a 1.7 m fridge does.
const OCCLUDER_MIN_HEIGHT: float = 0.62
## How far in front of an object a tall thing has to be before perspective lifts
## the object clear of it again.
const OCCLUSION_RANGE: float = 1.5
## Being hidden is worse than being 20 cm into a skirting board and better than
## being outside the room. Sits between the two so the search prefers, in order:
## visible and clear, visible and slightly crowded, hidden, outside.
const OCCLUSION_PENALTY: float = 0.45

## Pads that ride on the toddler, as local offsets from his feet. He is 0.85 m
## tall, so the mouth sits at ~0.62 m.
const ZONE_BODY_OFFSETS: Dictionary = {
	"mouth": Vector3(0.0, 0.62, 0.10),
	"hug": Vector3(0.0, 0.45, 0.16),
	"dress": Vector3(0.0, 0.45, 0.10),
	"hand": Vector3(0.0, 0.40, 0.20),
}
## Pads that sit on furniture, lifted clear of the prop and pulled towards the
## camera so the object is dropped in FRONT of the box rather than inside it.
const ZONE_PROP_OFFSET: Vector3 = Vector3(0.0, 0.30, 0.26)

const BODY_ZONE_RADIUS: float = 0.34
const PROP_ZONE_RADIUS: float = 0.40

## The "go here" disc. A pre-reader cannot read "Walk to the bathroom", and the
## two doors of a room look identical, so the place the task wants is marked on
## the floor in the same soft pastel language the drop zones already use. It is a
## hint, not a gate: tapping anything else still works, and the disc disappears
## the moment Little Buddy arrives.
const BEAT_MARKER_RADIUS: float = 0.42
const BEAT_MARKER_HEIGHT: float = 0.014
const BEAT_MARKER_COLOR: Color = Color(0.66, 0.90, 0.81, 0.42)

var _anchor: Node3D = null
var _zones: Dictionary = {}
var _beat_marker: MeshInstance3D = null
var _resolved: bool = false

var _character: Node3D = null
## The world position prop pads track: the current task's semantic target.
var _prop_focus: Vector3 = Vector3.ZERO
var _plan: Dictionary = {}

## The ONE live slot array. `get_spawn_points()` hands out this instance rather
## than a copy, and `begin_task()` rewrites its elements in place.
##
## That is load-bearing and deliberate. `HouseLevelDirector` builds the mission
## context once per LEVEL, and `MissionRunner` shallow-`duplicate()`s it, so the
## array object the mode handler reads at spawn time is this one -- which is what
## lets every task lay its objects out somewhere different without any change to
## `build_context()`'s shape or to the director. `test_house_stage_placement.gd`
## asserts the sharing, so a future deep copy upstream fails loudly here instead
## of silently freezing every task's layout at level one.
var _spawn_points: Array = []

## The semantic id the current layout was derived from ("bathroom.sink"), or ""
## when it fell back to the child's feet. Diagnostics and tests only.
var _place_id: String = ""

## Handed in through `build_context()`. Used for exactly one thing: looking up an
## object's `category`, which is how a task that names no target still knows its
## clothes belong at the wardrobe.
var _library: Object = null


func _ready() -> void:
	_ensure_resolved()


func _process(_delta: float) -> void:
	update_zones()


## -- Wiring --------------------------------------------------------------------

## Idempotent, and called from every public method: the headless `--script`
## runner never fires `_ready()` for a node added to the root.
func _ensure_resolved() -> void:
	if _resolved:
		return
	_resolved = true

	_anchor = get_node_or_null(ANCHOR_NAME) as Node3D
	if _anchor == null:
		_anchor = Node3D.new()
		_anchor.name = ANCHOR_NAME
		add_child(_anchor)
	_anchor.scale = Vector3.ONE * OBJECT_SCALE
	_spawn_points = default_slot_offsets()

	for zone_id: String in DropZoneScript.known_zone_ids():
		var radius: float = BODY_ZONE_RADIUS if ZONE_BODY_OFFSETS.has(zone_id) else PROP_ZONE_RADIUS
		var zone: Area3D = DropZoneScript.create(zone_id, radius)
		if zone == null:
			continue
		# Not a physics volume: a named position and a radius, exactly as the
		# Baby Room's hand-built zones. Set here as well as in `_ready()` because
		# `_ready()` does not fire in the headless runner.
		zone.input_ray_pickable = false
		zone.monitoring = false
		zone.monitorable = false
		zone.collision_layer = 0
		zone.collision_mask = 0
		add_child(zone)
		_zones[zone_id] = zone


func bind_character(character: Node3D) -> void:
	_ensure_resolved()
	_character = character
	update_zones()


## -- The context the mode handlers already speak ------------------------------

func build_context(extra: Dictionary = {}) -> Dictionary:
	_ensure_resolved()
	var context: Dictionary = {
		"objectAnchor": _anchor,
		"spawnPoints": get_spawn_points(),
		"dropZones": get_drop_zones(),
	}
	for key: Variant in extra.keys():
		context[key] = extra[key]
	# Kept, not copied: the only thing the stage asks of it is an object's
	# category. Optional -- a stage with no library simply loses derivation rule 2.
	var library: Variant = context.get("library", null)
	_library = library if library is Object else null
	return context


func get_object_anchor() -> Node3D:
	_ensure_resolved()
	return _anchor


## The current slot layout, local to the object anchor, in slot order.
##
## Returns the LIVE array, not a copy -- see `_spawn_points`. Callers read it;
## only `begin_task()` writes it.
func get_spawn_points() -> Array:
	_ensure_resolved()
	return _spawn_points


## The straight row, local to the anchor: what the stage shows before any task
## has been staged, and what it falls back to when no place can be derived.
static func default_slot_offsets() -> Array:
	var points: Array = []
	var half: float = float(SPAWN_SLOTS - 1) * 0.5
	for slot: int in range(SPAWN_SLOTS):
		points.append(Vector3((float(slot) - half) * SPAWN_SPACING, SPAWN_LIFT, 0.0))
	return points


## The semantic id this task's objects were laid out against ("kitchen.table"),
## or "" if the layout fell back to the child's feet.
func get_place_id() -> String:
	return _place_id


## The current layout in WORLD space, slot by slot. What a test measures: it is
## the thing a child actually sees and touches, and it folds in the anchor's
## position and its `OBJECT_SCALE`, both of which are easy to forget.
func get_spawn_world_positions() -> Array:
	_ensure_resolved()
	var anchor_transform: Transform3D = SpatialUtil.world_transform(_anchor)
	var points: Array = []
	for offset: Variant in _spawn_points:
		points.append(anchor_transform * (offset as Vector3))
	return points


func get_drop_zones() -> Dictionary:
	_ensure_resolved()
	return _zones.duplicate()


func get_drop_zone(zone_id: String) -> Node:
	_ensure_resolved()
	var zone: Variant = _zones.get(zone_id, null)
	return zone as Node if zone is Node else null


## -- Per task -------------------------------------------------------------------

## Stages `plan`: lays the choice objects out where they BELONG in the room, and
## points the prop pads at the task's target.
##
## `focus` is the world position of the thing the task is about (the sink, the
## table, the toy box) and `stand` is where the toddler will be standing when the
## beat happens -- `null` for a task that asks for no walk. Both come from the
## director, which owns the semantic-id lookup.
##
## The stage also resolves the task's target NODE itself when it can, because a
## single `focus` point cannot say which way a sink faces and the row has to go
## in FRONT of the furniture, on the side the child can reach. That is read live
## from the scene, never from a table of coordinates: the props are being
## re-modelled and a copied number here would be wrong within the week.
##
## MUST run before the mode handler spawns, which is why the director calls it
## from `task_started` -- `MissionRunner` emits that signal and only then calls
## `handler.start()`.
func begin_task(plan: Dictionary, focus: Variant = null, stand: Variant = null) -> void:
	_ensure_resolved()
	_plan = plan.duplicate(true)

	var room_id: String = String(plan.get("roomId", ""))
	var beat: Vector3 = _character_position()
	if stand is Vector3:
		beat = stand as Vector3

	_prop_focus = (focus as Vector3) if focus is Vector3 else beat

	var place: Dictionary = _resolve_place(plan, focus, stand, room_id)
	if place.is_empty():
		# Nothing to belong to. The row a child could always reach, unchanged --
		# including its scale, which the derived path may have raised.
		_place_id = ""
		_anchor.scale = Vector3.ONE * OBJECT_SCALE
		_write_slots(default_slot_offsets())
		SpatialUtil.set_world_position(_anchor, _row_position(beat, room_id))
	else:
		_place_id = String(place.get("sourceId", ""))
		_apply_place(place, String(place.get("roomId", room_id)))
	update_zones()


## Keeps the pads where they belong. Cheap -- a handful of vector writes -- and
## driven from `_process()` in a live scene and from the director's `step()` in
## the headless runner, so the two behave identically.
func update_zones() -> void:
	if not _resolved:
		return
	var here: Vector3 = _character_position()
	for zone_id: Variant in _zones.keys():
		var zone: Node3D = _zones[zone_id] as Node3D
		if zone == null:
			continue
		var offset: Variant = ZONE_BODY_OFFSETS.get(String(zone_id), null)
		if offset is Vector3:
			SpatialUtil.set_world_position(zone, here + (offset as Vector3))
		else:
			SpatialUtil.set_world_position(zone, _prop_focus + ZONE_PROP_OFFSET)


## Shows the "go here" disc at a world position, or hides it when `where` is not
## a `Vector3`. Built lazily so a stage that never needs one never pays for it.
func show_beat_marker(where: Variant) -> void:
	_ensure_resolved()
	if not (where is Vector3):
		if _beat_marker != null:
			_beat_marker.visible = false
		return
	if _beat_marker == null:
		_beat_marker = MeshInstance3D.new()
		_beat_marker.name = "BeatMarker"
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = BEAT_MARKER_RADIUS
		mesh.bottom_radius = BEAT_MARKER_RADIUS
		mesh.height = BEAT_MARKER_HEIGHT
		_beat_marker.mesh = mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = BEAT_MARKER_COLOR
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.roughness = 1.0
		_beat_marker.material_override = material
		add_child(_beat_marker)
	SpatialUtil.set_world_position(
		_beat_marker, (where as Vector3) + Vector3(0.0, HouseLayout.FLOOR_Y + 0.008, 0.0)
	)
	_beat_marker.visible = true


func is_beat_marker_visible() -> bool:
	_ensure_resolved()
	return _beat_marker != null and _beat_marker.visible


## Hides every landing pad and the "go here" disc. Called when a level ends so
## nothing is left glowing on an empty floor.
func clear_markers() -> void:
	_ensure_resolved()
	for zone: Variant in _zones.values():
		if zone is Node and (zone as Node).has_method("set_marker_visible"):
			(zone as Node).call("set_marker_visible", false)
	show_beat_marker(null)


func get_plan() -> Dictionary:
	return _plan.duplicate(true)


## -- Layout ---------------------------------------------------------------------

## Where this task's objects belong, or `{}` for "nowhere in particular".
##
##   `origin`   Vector3 -- the middle of the row, on the floor,
##   `outward`  Vector3 -- unit, furniture -> open floor (the reachable side),
##   `axis`     Vector3 -- unit, along the face of the furniture,
##   `roomId`   String,
##   `sourceId` String  -- the semantic id it was derived from.
##
## Pure geometry once the target is found; see `_place_from()` for the arithmetic
## and `_target_place()` / `_category_place()` for the two derivation rules.
func _resolve_place(
	plan: Dictionary, focus: Variant, stand: Variant, room_id: String
) -> Dictionary:
	var place: Dictionary = _target_place(String(plan.get("focusTargetId", "")), plan, room_id)
	if place.is_empty():
		place = _category_place(plan, room_id)
	if not place.is_empty():
		return place

	# Rule 3: no target resolved, but the director still told us where the beat
	# is. Use the two points it gave us -- better than the child's feet whenever
	# they actually differ. This is the path Free Play takes, which names a room
	# and a focus prop but never a task.
	if focus is Vector3 and stand is Vector3 \
			and NavMath.flat_distance(focus as Vector3, stand as Vector3) > 0.05 \
			and _is_actionable_room(plan, room_id):
		return _place_from(focus as Vector3, stand as Vector3, plan, room_id, "")
	return {}


## Rule 1: the task named a target, and the target is in the scene, in the room
## the child can act in, and is not a doorway.
func _target_place(semantic_id: String, plan: Dictionary, room_id: String) -> Dictionary:
	var target: Node3D = _find_activity_target(semantic_id)
	if target == null:
		return {}
	if target.has_method("is_door") and bool(target.call("is_door")):
		# Objects in a doorway would be walked through and are never what a
		# `travel` beat is about anyway.
		return {}
	var here: Vector3 = _character_position()
	var focus: Vector3 = SpatialUtil.world_position(target)
	var stand: Vector3 = focus + Vector3.BACK * ROW_FRONT_OFFSET
	if target.has_method("describe"):
		var info: Dictionary = target.call("describe", here)
		var described: Variant = info.get("standPosition", null)
		if described is Vector3:
			stand = described as Vector3
	var target_room: String = room_id
	if target.has_method("get_room_id"):
		var named: String = String(target.call("get_room_id"))
		if not named.is_empty():
			target_room = named
	if not _is_actionable_room(plan, target_room):
		return {}
	return _place_from(focus, stand, plan, target_room, semantic_id)


## Rule 2: the task named no target at all (every dressing task), so the OBJECT
## says where it belongs -- `category` in `content/objects.json`, mapped through
## `CATEGORY_HOME_TARGETS` and resolved in the room the child is actually in.
func _category_place(plan: Dictionary, room_id: String) -> Dictionary:
	var category: String = _category_of(String(plan.get("objectId", "")))
	if category.is_empty() or not CATEGORY_HOME_TARGETS.has(category):
		return {}
	var room: String = room_id
	if room.is_empty() or not _is_actionable_room(plan, room):
		room = _room_containing(_character_position())
	if room.is_empty():
		return {}
	var semantic_id: String = HouseLayout.semantic_id(
		room, String(CATEGORY_HOME_TARGETS[category]))
	return _target_place(semantic_id, plan, room)


## The arithmetic, once a furniture centre and its stand point are known.
##
## `outward` is furniture -> stand point: the authored, navigable approach side,
## which is by definition the side a child can reach from. `axis` is that turned
## a quarter turn, i.e. along the face of the furniture, which is where a row of
## things laid out at a sink or a wardrobe goes.
func _place_from(
	focus: Vector3, stand: Vector3, plan: Dictionary, room_id: String, source_id: String
) -> Dictionary:
	var away: Vector3 = Vector3(stand.x - focus.x, 0.0, stand.z - focus.z)
	var reach: float = away.length()
	var outward: Vector3 = Vector3.BACK if reach <= NavMath.EPSILON else away / reach

	var shelf: float = maxf(reach * SHELF_INSET, SHELF_MIN)
	if bool(plan.get("needsWalk", false)):
		# The child will be standing on the stand point when this beat happens, so
		# the row goes PAST him towards the open side. Objects laid between him and
		# the furniture would sit behind his back from the camera.
		shelf = reach + SHELF_PAST_CHILD

	return {
		"origin": Vector3(
			focus.x + outward.x * shelf, HouseLayout.FLOOR_Y, focus.z + outward.z * shelf),
		"outward": outward,
		"axis": Vector3(outward.z, 0.0, -outward.x),
		"roomId": room_id,
		"sourceId": source_id,
	}


## Lays the four slots out on `place` and moves the anchor to match.
##
## Three things have to be true of every slot afterwards, and they are enforced
## here rather than hoped for: inside the walkable floor, clear of every piece of
## furniture, and no closer to its neighbour than a grab collider is wide.
## `test_house_stage_placement.gd` re-measures all three for every shipped task.
func _apply_place(place: Dictionary, room_id: String) -> void:
	var origin: Vector3 = place.get("origin", Vector3.ZERO)
	var axis: Vector3 = place.get("axis", Vector3.RIGHT)
	var outward: Vector3 = place.get("outward", Vector3.BACK)
	# Scale FIRST: it sets the spacing, which sets the width of the row, which is
	# what has to be fitted into the room.
	var object_scale: float = depth_scale(origin.z, room_id)
	_anchor.scale = Vector3.ONE * object_scale
	var pitch: float = SPAWN_SPACING * object_scale
	var depth: float = SPAWN_DEPTH_SPACING * object_scale

	var bounds: Variant = null
	if HouseLayout.has_room(room_id):
		bounds = HouseLayout.world_floor_bounds(room_id).grow(-PLACE_EDGE_MARGIN)
	var blockers: Array = _obstacle_rects(room_id)

	# The cluster's centre sits half a rank further out than the shelf, so it is
	# the BACK rank -- the one nearest the furniture -- that the shelf distance
	# actually describes.
	var centre: Vector3 = origin + outward * (depth * 0.5)

	# Move the whole cluster first, so the spacing survives being fitted into the
	# room. Only then is each slot allowed to move on its own.
	var wanted: Array = []
	for slot: Vector2 in CLUSTER_SLOTS:
		wanted.append(centre + axis * (slot.x * pitch) + outward * (slot.y * depth))
	var shift: Vector3 = _fit_offset(wanted, bounds)

	# Each slot is then free to move on its own, but never on top of a slot that
	# has already been settled: the minimum gap is the grab collider itself, so no
	# two objects can ever share touchable area however crowded the room is.
	var gap: float = ObjectSpawnerScript.GRAB_SIZE_M * object_scale
	var placed: Array = []
	for point: Variant in wanted:
		placed.append(_free_position(
				(point as Vector3) + shift, axis, outward, bounds, blockers, placed, gap))

	SpatialUtil.set_world_position(_anchor, centre + shift)
	var anchor_transform: Transform3D = SpatialUtil.world_transform(_anchor)
	var to_local: Transform3D = anchor_transform.affine_inverse()
	var offsets: Array = []
	for point: Variant in placed:
		var local: Vector3 = to_local * (point as Vector3)
		offsets.append(Vector3(local.x, SPAWN_LIFT, local.z))
	_write_slots(offsets)


## How big an object laid out at world depth `z` in `room_id` should be.
##
## The rooms all face the camera down +Z, so "how far back" is one number. Pure,
## so the row width and the touch-target size can both be asserted without a
## renderer. A room this layout does not know about gets the plain scale.
static func depth_scale(z: float, room_id: String) -> float:
	if not HouseLayout.has_room(room_id):
		return OBJECT_SCALE
	var bounds: Rect2 = HouseLayout.world_floor_bounds(room_id)
	if bounds.size.y <= 0.0:
		return OBJECT_SCALE
	var back: float = clampf((bounds.end.y - z) / bounds.size.y, 0.0, 1.0)
	return OBJECT_SCALE * lerpf(1.0, DEPTH_SCALE_MAX, back)


## The scale the current layout is presented at, `OBJECT_SCALE` or more.
func get_object_scale() -> float:
	_ensure_resolved()
	return _anchor.scale.x


## Rewrites the live slot array IN PLACE. Never reassigns `_spawn_points`: the
## mission context is holding that exact array object.
func _write_slots(offsets: Array) -> void:
	_spawn_points.resize(offsets.size())
	for i: int in range(offsets.size()):
		_spawn_points[i] = offsets[i]


## How far the whole cluster has to move for all of it to sit inside `bounds`.
##
## Zero when it already does. Moving every slot by the SAME vector is the only
## correction that preserves the spacing, which is what keeps two grab colliders
## from ever overlapping; per-slot clamping is left to `_free_position()`, after
## this has done what it can for the group.
static func _fit_offset(points: Array, bounds: Variant) -> Vector3:
	if not (bounds is Rect2) or points.is_empty():
		return Vector3.ZERO
	var box: Rect2 = bounds
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for entry: Variant in points:
		var point: Vector3 = entry
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)

	var shift := Vector3.ZERO
	shift.x = maxf(0.0, box.position.x - min_x) - maxf(0.0, max_x - box.end.x)
	shift.z = maxf(0.0, box.position.y - min_z) - maxf(0.0, max_z - box.end.y)
	return shift


## The nearest free spot to `wanted`, searched outwards in the cluster's own
## frame: along the face of the furniture, away from it, and the diagonals.
##
## Deterministic and bounded. A slot that cannot be freed at all keeps the
## least-blocked candidate rather than vanishing or being clamped into a wall:
## an object the child cannot see is a dead end, and there is never a dead end.
func _free_position(
	wanted: Vector3,
	axis: Vector3,
	outward: Vector3,
	bounds: Variant,
	blockers: Array,
	taken: Array,
	gap: float
) -> Vector3:
	var best: Vector3 = _clamp_into(wanted, bounds)
	var best_penalty: float = _penalty(best, bounds, blockers, taken, gap)
	if best_penalty <= 0.0:
		return best

	var directions: Array = [
		outward, -outward, axis, -axis,
		(outward + axis).normalized(), (outward - axis).normalized(),
		(-outward + axis).normalized(), (-outward - axis).normalized(),
	]
	for step: int in range(1, PLACE_STEP_COUNT + 1):
		for direction: Variant in directions:
			var candidate: Vector3 = _clamp_into(
				wanted + (direction as Vector3) * (float(step) * PLACE_STEP), bounds)
			var penalty: float = _penalty(candidate, bounds, blockers, taken, gap)
			if penalty <= 0.0:
				return candidate
			if penalty < best_penalty:
				best_penalty = penalty
				best = candidate
	return best


## How badly a point is placed: 0.0 is free, and anything above says how deep it
## sits inside furniture, how far outside the floor it is, or how much it crowds
## an object that is already down. A number rather than a bool, so a slot that
## cannot be fully freed still takes the least-bad spot.
static func _penalty(
	point: Vector3, bounds: Variant, blockers: Array, taken: Array, gap: float
) -> float:
	var flat := Vector2(point.x, point.z)
	var score: float = 0.0
	for entry: Variant in blockers:
		var blocker: Dictionary = entry
		var box: Rect2 = blocker["rect"]
		if box.has_point(flat):
			var dx: float = minf(point.x - box.position.x, box.end.x - point.x)
			var dz: float = minf(point.z - box.position.y, box.end.y - point.z)
			score += minf(dx, dz)
		elif _is_hidden_behind(flat, box, float(blocker.get("height", 0.0))):
			score += OCCLUSION_PENALTY
	if bounds is Rect2 and not (bounds as Rect2).has_point(flat):
		score += 1.0
	for entry: Variant in taken:
		var other: Vector3 = entry
		var distance: float = flat.distance_to(Vector2(other.x, other.z))
		if distance < gap:
			score += gap - distance
	return score


## Would a 20 cm object at `point` be hidden behind this piece of furniture?
##
## Every room is seen from one fixed direction -- the camera sits on the room's
## open +Z side and looks back into it (`HouseLayout.camera_framing`) -- so
## "between the child's eye and the object" is simply "at a greater Z, across the
## same X". That one fact is what makes this a two-line test instead of a
## rendering query.
##
## Found by rendering: `findMilk` put the apple directly behind the kitchen table,
## where a 0.7 m table top hid a 0.2 m apple completely. "Find the apple" with the
## apple invisible is the worst kind of dead end, because it looks like the game
## is working.
static func _is_hidden_behind(point: Vector2, box: Rect2, height: float) -> bool:
	if height < OCCLUDER_MIN_HEIGHT:
		return false
	if point.x < box.position.x or point.x > box.end.x:
		return false
	var in_front: float = box.position.y - point.y
	return in_front > 0.0 and in_front < OCCLUSION_RANGE


static func _clamp_into(point: Vector3, bounds: Variant) -> Vector3:
	if not (bounds is Rect2):
		return point
	var box: Rect2 = bounds
	return Vector3(
		clampf(point.x, box.position.x, box.end.x),
		point.y,
		clampf(point.z, box.position.y, box.end.y))


## Every furniture footprint in a room, in world space, grown by the clearance an
## object needs, each with the height of the thing that made it. Read from
## `HouseLayout` -- the same table the room builder and the navigation bake use --
## so a prop that moves moves its keep-out with it.
##
## The height is what makes the occlusion test possible; see `_penalty()`.
static func _obstacle_rects(room_id: String) -> Array:
	var rects: Array = []
	if not HouseLayout.has_room(room_id):
		return rects
	var origin: Vector3 = HouseLayout.room_origin(room_id)
	for prop: Variant in HouseLayout.furniture(room_id):
		var entry: Dictionary = prop
		var size: Vector3 = entry.get("size", Vector3.ONE)
		var position: Vector3 = entry.get("position", Vector3.ZERO)
		rects.append({
			"rect": Rect2(
				origin.x + position.x - size.x * 0.5,
				origin.z + position.z - size.z * 0.5,
				size.x, size.z).grow(PLACE_CLEARANCE),
			"height": size.y,
		})
	return rects


## -- Live scene lookups ---------------------------------------------------------

## The `ActivityTarget` addressed by `semantic_id`, found by walking the world
## this stage was added to.
##
## Duck-typed exactly as `NavigationController.target_id_for()` is, so a target
## wrapped inside a prop scene resolves without any type coupling -- which is the
## point, because the props are being re-modelled around this file.
func _find_activity_target(semantic_id: String) -> Node3D:
	if semantic_id.strip_edges().is_empty():
		return null
	var root: Node = get_parent()
	if root == null:
		root = self
	return _search_for_target(root, semantic_id, 0)


func _search_for_target(node: Node, semantic_id: String, depth: int) -> Node3D:
	if node == null or depth > 12:
		return null
	if node is Node3D and node.has_method("get_activity_target_id"):
		if String(node.call("get_activity_target_id")) == semantic_id:
			return node as Node3D
	for child: Node in node.get_children():
		var found: Node3D = _search_for_target(child, semantic_id, depth + 1)
		if found != null:
			return found
	return null


## The category of a content object ("bath", "dressing"), or "".
func _category_of(object_id: String) -> String:
	if _library == null or object_id.strip_edges().is_empty():
		return ""
	if not _library.has_method("get_object"):
		return ""
	var record: Variant = _library.call("get_object", object_id)
	if typeof(record) != TYPE_DICTIONARY:
		return ""
	return String((record as Dictionary).get("category", "")).strip_edges()


## Which room a world point is in, or "". Generous by half a metre so a child
## standing in a doorway still counts as being in the room he came from.
static func _room_containing(point: Vector3) -> String:
	for room_id: Variant in HouseLayout.room_ids():
		var bounds: Rect2 = HouseLayout.world_floor_bounds(String(room_id)).grow(0.5)
		if bounds.has_point(Vector2(point.x, point.z)):
			return String(room_id)
	return ""


## May this task's objects be staged in `room_id`?
##
## Yes when the child is already there, and yes when the task asks him to walk
## there (the director routes him, and `begin_task()` runs again on arrival). No
## otherwise: objects laid out in a room nobody is in are objects nobody can see,
## and for a `findIt` beat with no walk that is an unanswerable question.
func _is_actionable_room(plan: Dictionary, room_id: String) -> bool:
	if room_id.is_empty():
		return false
	if bool(plan.get("needsWalk", false)):
		return true
	var here: String = _room_containing(_character_position())
	return here.is_empty() or here == room_id


## The row sits between the beat and the camera, clamped inside the room so an
## object can never be laid out inside a wall -- a toy the child can see but not
## reach is a dead end with a friendly face.
func _row_position(beat: Vector3, room_id: String) -> Vector3:
	var point: Vector3 = Vector3(beat.x, HouseLayout.FLOOR_Y, beat.z + ROW_FRONT_OFFSET)
	if HouseLayout.has_room(room_id):
		var bounds: Rect2 = HouseLayout.world_floor_bounds(room_id)
		# In WORLD units: the anchor's scale multiplies the local spacing, so a
		# row that fits on paper can still end up inside a wall if this forgets it.
		var half_row: float = float(SPAWN_SLOTS - 1) * 0.5 * SPAWN_SPACING * OBJECT_SCALE
		point.x = clampf(
			point.x, bounds.position.x + half_row + 0.2, bounds.end.x - half_row - 0.2
		)
		point.z = clampf(point.z, bounds.position.y + ROW_MARGIN, bounds.end.y - 0.3)
	return point


func _character_position() -> Vector3:
	if _character == null or not is_instance_valid(_character):
		return Vector3.ZERO
	return SpatialUtil.world_position(_character)
