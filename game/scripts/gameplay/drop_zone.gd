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
	# CARE ACTS. They map to `hand` -- the same zone a tap uses -- because from
	# the drop-zone system's point of view that is exactly what they are: a tool
	# in the player's hand. The gesture itself lives in `care_overlay.gd` and
	# needs no landing pad, so inventing a `face` zone would have forced every
	# one of the five activity scenes to declare a node none of them uses.
	"brushTeeth": ZONE_HAND,
	"washFace": ZONE_HAND,
	"dryFace": ZONE_HAND,
	# Mission 01's two acts. `prepareMilk` is a tool in the hand at the counter,
	# exactly like the three above. `giveBottle` is the one care act whose landing
	# place is Bunny's own MOUTH, so it takes that zone -- the same one the Baby
	# Room's `dragToMouth` uses, which is why no new zone is needed here either.
	"prepareMilk": ZONE_HAND,
	"giveBottle": ZONE_MOUTH,
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

const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

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

## -- Affordances -------------------------------------------------------------------
##
## A zone offers `place` to an actor carrying an ITEM (a child in her arms is
## put down through the child's own affordance, on a standable floor spot, not
## on a zone). Performing it sets the item down AT the zone through the actor's
## `put_down_carried()`, and when it lands the zone tells the item, which
## delivers through the same funnel a drag does. `radius` here is the reach
## offered to the HUD, not the zone's own catch radius.
const AFFORDABLE_GROUP: String = "affordable"
const AFFORD_VERB_PLACE: String = "place"
const AFFORD_REACH: float = 1.0
const AFFORD_ANCHOR_LIFT: float = 0.22
const AFFORD_PRIORITY: int = 2

var _pending_carry: Node = null
var _pending_item: Node3D = null


func _ready() -> void:
	# Never a pick target and never a physics participant -- it exists purely as
	# a named position + radius.
	input_ray_pickable = false
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	add_to_group(AFFORDABLE_GROUP)
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
	add_to_group(AFFORDABLE_GROUP)
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


func get_affordance(actor: Node3D) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return {}
	if not actor.has_method("is_carrying_node") or not bool(actor.call("is_carrying_node")):
		return {}
	var carried: Node = actor.call("get_carried_node") if actor.has_method("get_carried_node") else null
	if carried == null or carried.has_method("set_carried_by"):
		return {}  # the child is put down on the floor, not on a pad
	if _pending_item != null:
		return {}  # already landing something here
	return {
		"verb": AFFORD_VERB_PLACE,
		"anchor": SpatialUtil.world_position(self) + Vector3(0.0, AFFORD_ANCHOR_LIFT, 0.0),
		"radius": AFFORD_REACH,
		"priority": AFFORD_PRIORITY,
		"target": self,
	}


func perform_affordance(actor: Node3D) -> bool:
	if get_affordance(actor).is_empty():
		return false
	var item: Node3D = actor.call("get_carried_node") as Node3D
	if not bool(actor.call("put_down_carried", SpatialUtil.world_position(self))):
		return false
	# Deliver when it LANDS, not when it leaves her hand: the arrival is the
	# thing the child watches, and a reaction that fires while the spoon is
	# still in the air belongs to nothing on screen.
	var carry: Node = actor.call("get_carry_controller") if actor.has_method("get_carry_controller") else null
	if carry != null and carry.has_signal("carry_ended"):
		_pending_carry = carry
		_pending_item = item
		carry.connect("carry_ended", _on_carry_landed, CONNECT_ONE_SHOT)
	else:
		_deliver(item)
	return true


func _on_carry_landed(node: Node3D) -> void:
	var item: Node3D = _pending_item
	_pending_item = null
	_pending_carry = null
	if node == item:
		_deliver(item)


func _deliver(item: Node3D) -> void:
	if item == null or not is_instance_valid(item):
		return
	if item.has_method("deliver_placed"):
		item.call("deliver_placed", self)


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
	# Grouped here as well as in `_ready()`, which the headless runner never fires.
	zone.add_to_group(AFFORDABLE_GROUP)
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
