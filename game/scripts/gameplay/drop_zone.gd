class_name DropZone
extends Area3D

## A reusable, *named* delivery target for `DraggableObject`s.
##
## The Baby Room already creates `MouthDropZone`/`HugDropZone` by hand and glues
## them to `BabyView3D.get_mouth_position()`/`get_hug_position()`. This class
## generalises that idea so `BathDropZone`, `DressDropZone`, `ToyBoxDropZone` and
## `HandDropZone` are pure data: a `zone_id`, a catch `radius`, and an optional
## `follow` anchor on the baby.
##
## Deliberately NOT a physics volume: like the hand-rolled zones in
## `baby_room.gd` it keeps `monitoring`/`monitorable` off and no collision shape.
## `DraggableObject` tests membership geometrically via
## `DragPlane.point_in_drop_zone(point, zone.global_position, radius)`, which is
## cheaper and, more importantly, forgiving -- a small child's imprecise drag
## registers as soon as the object gets *near* the target.
##
## Content never names a zone directly; it names an `interaction`
## (`dragToMouth`, `dragToBath`, ...). `zone_id_for_interaction()` is the single
## mapping from content vocabulary to zone ids, so a task can never reference a
## zone that does not exist.

## Every zone id the game knows about.
const ZONE_MOUTH: String = "mouth"
const ZONE_HUG: String = "hug"
const ZONE_BATH: String = "bath"
const ZONE_DRESS: String = "dress"
const ZONE_TOY_BOX: String = "toyBox"
const ZONE_HAND: String = "hand"

## Content `interaction` value -> zone id. `tap` maps to the baby's hands: a
## "just give it to me" target that is *also* completable with a plain tap, so
## tap-only content still has a real, non-dangling zone.
const INTERACTION_TO_ZONE_ID: Dictionary = {
	"dragToMouth": ZONE_MOUTH,
	"dragToHug": ZONE_HUG,
	"dragToBath": ZONE_BATH,
	"dragToDress": ZONE_DRESS,
	"dragToToyBox": ZONE_TOY_BOX,
	"tap": ZONE_HAND,
}

## Conventional scene-node name per zone id, so `ActivityScene` and the Baby Room
## can find a zone by name as well as by id.
const ZONE_NODE_NAMES: Dictionary = {
	ZONE_MOUTH: "MouthDropZone",
	ZONE_HUG: "HugDropZone",
	ZONE_BATH: "BathDropZone",
	ZONE_DRESS: "DressDropZone",
	ZONE_TOY_BOX: "ToyBoxDropZone",
	ZONE_HAND: "HandDropZone",
}

## Anchor on `BabyView3D` a zone tracks each frame, or "" for a fixed prop zone.
const FOLLOW_NONE: String = ""
const FOLLOW_MOUTH: String = "mouth"
const FOLLOW_HUG: String = "hug"

## Generous by design: bigger than the baby-room default (0.22) because spawned
## content objects are larger and a child aiming with a whole hand is not precise.
const DEFAULT_RADIUS: float = 0.26

const MARKER_ALPHA: float = 0.32
const MARKER_HEIGHT: float = 0.012

## Emitted when a `SpawnedObject` reports it was delivered into this zone.
## Handlers connect to the object rather than the zone, so this is informational.
signal object_delivered(object_id: String)

@export var zone_id: String = ""
@export var radius: float = DEFAULT_RADIUS
## "" | "mouth" | "hug" -- see FOLLOW_* above.
@export var follow: String = FOLLOW_NONE
## Extra offset applied after following the baby anchor (used by `hand`).
@export var follow_offset: Vector3 = Vector3.ZERO
## Draws a soft pastel landing pad. On for prop zones (bath/toy box), off for
## zones that sit on the baby -- there the baby is already the visible target.
@export var show_marker: bool = false
@export var marker_color: Color = Color(0.72, 0.86, 0.98)

var _marker: MeshInstance3D = null


func _ready() -> void:
	# Never a pick target and never a physics participant -- it exists purely as
	# a named position + radius.
	input_ray_pickable = false
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	if zone_id.is_empty():
		zone_id = _zone_id_from_node_name(name)
	if show_marker:
		_build_marker()
	# Landing pads start hidden: a pad only makes sense while a task is actually
	# asking the child to drag something here. Showing every pad during a
	# "Find the spoon" task is just noise on the floor.
	set_marker_visible(false)


## -- Public API --------------------------------------------------------------

func configure(new_zone_id: String, new_radius: float = DEFAULT_RADIUS) -> void:
	zone_id = new_zone_id
	radius = maxf(0.05, new_radius)


func get_zone_id() -> String:
	return zone_id


func get_radius() -> float:
	return radius


## Geometric membership test, identical in spirit to `DragPlane.point_in_drop_zone`
## but usable without loading that script.
func contains_point(point: Vector3) -> bool:
	return point.distance_to(global_position) <= radius


## Moves the zone onto its baby anchor. Called every frame by `ActivityScene`
## (cheap: a couple of Vector3 reads) so the zone stays glued to the mouth/chest
## even if `BabyView3D` changes proportions or bobs while idling. Positions are
## never hardcoded here.
func update_from_baby(baby_view: Node) -> void:
	if follow == FOLLOW_NONE or baby_view == null:
		return
	if follow == FOLLOW_MOUTH and baby_view.has_method("get_mouth_position"):
		global_position = baby_view.get_mouth_position() + follow_offset
	elif follow == FOLLOW_HUG and baby_view.has_method("get_hug_position"):
		global_position = baby_view.get_hug_position() + follow_offset


func notify_delivered(object_id: String) -> void:
	object_delivered.emit(object_id)


## -- Static helpers (pure, unit-testable) ------------------------------------

## The zone a content `interaction` value delivers into. Returns "" for an
## unknown interaction -- callers treat that as "tap-only", never as a crash.
static func zone_id_for_interaction(interaction: String) -> String:
	return String(INTERACTION_TO_ZONE_ID.get(interaction, ""))


static func is_known_interaction(interaction: String) -> bool:
	return INTERACTION_TO_ZONE_ID.has(interaction)


static func is_known_zone_id(value: String) -> bool:
	return ZONE_NODE_NAMES.has(value)


static func known_zone_ids() -> Array:
	return ZONE_NODE_NAMES.keys()


static func known_interactions() -> Array:
	return INTERACTION_TO_ZONE_ID.keys()


static func node_name_for_zone_id(value: String) -> String:
	return String(ZONE_NODE_NAMES.get(value, ""))


## Builds a zone at runtime. Typed as `Area3D` rather than `DropZone` because a
## script may not reference its own `class_name` before Godot's global class
## cache has been rebuilt, and `--headless --script` never rebuilds it.
static func create(new_zone_id: String, new_radius: float = DEFAULT_RADIUS) -> Area3D:
	var script: GDScript = load("res://scripts/gameplay/drop_zone.gd") as GDScript
	if script == null:
		return null
	var zone: Area3D = Area3D.new()
	zone.set_script(script)
	zone.name = node_name_for_zone_id(new_zone_id) if is_known_zone_id(new_zone_id) else new_zone_id
	zone.set("zone_id", new_zone_id)
	zone.set("radius", maxf(0.05, new_radius))
	return zone


## -- Internals ----------------------------------------------------------------

static func _zone_id_from_node_name(node_name: String) -> String:
	for candidate: Variant in ZONE_NODE_NAMES.keys():
		if String(ZONE_NODE_NAMES[candidate]) == node_name:
			return String(candidate)
	return ""


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.name = "ZoneMarker"
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = MARKER_HEIGHT
	_marker.mesh = mesh

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(marker_color.r, marker_color.g, marker_color.b, MARKER_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.9
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = material
	add_child(_marker)


## Shows/hides the soft landing pad. Built lazily so a zone that was configured
## without a marker can still reveal one when a task targets it.
func set_marker_visible(value: bool) -> void:
	if value and _marker == null:
		_build_marker()
	if _marker != null:
		_marker.visible = value
