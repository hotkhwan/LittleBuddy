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

const DropZoneScript := preload("res://scripts/gameplay/drop_zone.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")

const ANCHOR_NAME: String = "ObjectAnchor"

## Spawn row, local to the anchor. Four slots, 0.46 m apart: wide enough that two
## 0.34 m grab colliders never overlap (a child's tap must be unambiguous), and
## narrow enough that the whole row stays inside a 4 m room.
const SPAWN_SPACING: float = 0.46
const SPAWN_SLOTS: int = 4
const SPAWN_LIFT: float = 0.02

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

## How far in front of the beat the row is laid out, towards the room's open
## front -- i.e. towards the camera, between the toddler and the viewer, where a
## child's fingers can reach on an iPad held in landscape.
const ROW_FRONT_OFFSET: float = 0.78
## Keeps the row off the walls whatever the beat is standing next to.
const ROW_MARGIN: float = 0.75

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
	return context


func get_object_anchor() -> Node3D:
	_ensure_resolved()
	return _anchor


func get_spawn_points() -> Array:
	var points: Array = []
	var half: float = float(SPAWN_SLOTS - 1) * 0.5
	for slot: int in range(SPAWN_SLOTS):
		points.append(Vector3((float(slot) - half) * SPAWN_SPACING, SPAWN_LIFT, 0.0))
	return points


func get_drop_zones() -> Dictionary:
	_ensure_resolved()
	return _zones.duplicate()


func get_drop_zone(zone_id: String) -> Node:
	_ensure_resolved()
	var zone: Variant = _zones.get(zone_id, null)
	return zone as Node if zone is Node else null


## -- Per task -------------------------------------------------------------------

## Stages `plan`: lays the choice row out where the beat happens and points the
## prop pads at the task's target.
##
## `focus` is the world position of the thing the task is about (the sink, the
## table, the toy box) and `stand` is where the toddler will be standing when the
## beat happens. Both come from the world, which owns the scene tree; this node
## never resolves a semantic id itself.
##
## The row goes where the CHILD will be, never where the furniture is: objects
## laid out at the back wall are half the size on screen and behind the toddler.
## `stand` is therefore only passed for a task that walks somewhere; a task with
## no walk lays its objects out at the toddler's feet, wherever he happens to be.
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
	SpatialUtil.set_world_position(_anchor, _row_position(beat, room_id))
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
