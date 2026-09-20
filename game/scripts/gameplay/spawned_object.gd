class_name SpawnedObject
extends "res://scripts/interaction/draggable_object.gd"

## A content-driven pickup, built at runtime by `ObjectSpawner` from one record
## in `content/objects.json`. Adding a new toy/food/clothing item therefore needs
## no new scene file and no new script -- only JSON.
##
## All drag mechanics (finger-following via a stable drag plane, latched pointer
## index for multi-touch safety, per-gesture delivery latch, pickup/return
## tweens, tap fallback) are inherited unchanged from `DraggableObject`. This
## subclass owns only its identity (`object_id`) and forwards the single
## "the child picked me" event.
##
## Tap and drag-into-zone deliberately funnel into the SAME signal: a mode
## handler must not care which one the child used, and a child who cannot drag
## must never be locked out of a task.

## Emitted exactly once per gesture, from either a tap or a drop-zone delivery.
## The per-gesture latch lives in `DraggableObject._delivered_this_drag`.
signal chosen(object_id: String)

const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

const SETTLE_DURATION_SEC: float = 0.25
const DIM_MIX: float = 0.5

var object_id: String = ""
var word: String = ""
var category: String = ""
var interaction: String = ""

## True for the object the current task is actually asking for. Handlers set it;
## it is never used to hide or disable the distractors (a child must always be
## allowed to touch the "wrong" thing and get a kind response).
var is_target: bool = false

var _materials: Array = []
var _base_colors: Array = []

## -- Affordances -------------------------------------------------------------------
##
## The data half of the on-screen verb icons (see `child_actor.gd` for the
## contract). A pickup offers exactly one verb, `take`, to an actor whose hands
## are free and who is close enough; picking it up hands it to the actor's
## `carry_node()` (`carry_controller.gd`), which lifts it visibly out of its
## row and into her `itemHoldRight` socket. Putting it down is a `DropZone`'s
## affordance, not this object's -- the zone is where it should go.
const AFFORDABLE_GROUP: String = "affordable"
const AFFORD_VERB_TAKE: String = "take"
## Reach, metres from the object: an arm's length plus the object's own row
## spacing, so an object at the edge of the row is still offered.
const AFFORD_REACH: float = 1.0
const AFFORD_ANCHOR_LIFT: float = 0.28
## Below the child (3), level with furniture (1)... a prop is a small thing.
const AFFORD_PRIORITY: int = 1


## -- Identity ----------------------------------------------------------------

func configure(spec: Dictionary) -> void:
	add_to_group(AFFORDABLE_GROUP)
	object_id = String(spec.get("objectId", ""))
	word = String(spec.get("word", ""))
	category = String(spec.get("category", ""))
	interaction = String(spec.get("interaction", ""))
	name = "Spawned_%s" % object_id if not object_id.is_empty() else "SpawnedObject"


func register_material(material: StandardMaterial3D) -> void:
	_materials.append(material)
	_base_colors.append(material.albedo_color)


## Sets the resting transform. Must be usable before AND after `_ready()`, since
## the spawner positions the object while it is still detached from the tree.
func set_home_position(position_value: Vector3) -> void:
	position = position_value
	_home_transform = transform


func get_home_position() -> Vector3:
	return _home_transform.origin


func get_affordance(actor: Node3D) -> Dictionary:
	if actor == null or not is_instance_valid(actor) or not drag_enabled:
		return {}
	if not actor.has_method("carry_node"):
		return {}
	if actor.has_method("is_carrying_node") and bool(actor.call("is_carrying_node")):
		return {}
	if is_carried_by(actor):
		return {}
	return {
		"verb": AFFORD_VERB_TAKE,
		"anchor": SpatialUtil.world_position(self) + Vector3(0.0, AFFORD_ANCHOR_LIFT, 0.0),
		"radius": AFFORD_REACH,
		"priority": AFFORD_PRIORITY,
		"target": self,
	}


func perform_affordance(actor: Node3D) -> bool:
	if get_affordance(actor).is_empty():
		return false
	return bool(actor.call("carry_node", self, "itemHoldRight"))


## True while this object is in `actor`'s hands (it is re-parented under the
## actor's carry controller for the duration).
func is_carried_by(actor: Node) -> bool:
	if actor == null or not actor.has_method("get_carried_node"):
		return false
	return actor.call("get_carried_node") == self


## The carry set this object down on `zone`. Counts as a delivery exactly as a
## drag into the zone would, through the same single funnel -- so a child who
## carries the spoon to the bowl and a child who drags it there are the same
## child to every handler -- but only when the zone is the one this object was
## told to deliver to, and only once.
func deliver_placed(zone: Area3D) -> bool:
	if zone == null or _drop_zone == null or zone != _drop_zone:
		return false
	if _delivered_this_drag:
		return false
	_delivered_this_drag = true
	_on_dropped_in_zone()
	if zone.has_method("notify_delivered"):
		zone.call("notify_delivered", object_id)
	# A fresh gesture may deliver again later, exactly as a drag's release
	# re-arms the latch.
	_delivered_this_drag = false
	return true


## -- Delivery ------------------------------------------------------------------

## Single funnel for tap and drag delivery (see `DraggableObject`).
func _on_dropped_in_zone() -> void:
	_settle_after_delivery()
	chosen.emit(object_id)


## Mirrors `MilkBottle.try_deliver_from_raycast()` so `baby_room.gd`'s explicit
## `intersect_ray` fallback can reach spawned objects too. Guarded so it can
## never double-deliver alongside the primary input path.
func try_deliver_from_raycast() -> void:
	if not drag_enabled or is_interaction_active():
		return
	_deliver_via_tap()


func set_enabled(value: bool) -> void:
	super.set_enabled(value)
	for i: int in range(_materials.size()):
		var material: StandardMaterial3D = _materials[i]
		var base: Color = _base_colors[i]
		material.albedo_color = base if value else base.lerp(Color(0.62, 0.62, 0.66), DIM_MIX)


func _settle_after_delivery() -> void:
	# Tracked in the inherited `_active_tween` so a hard `reset_position()`
	# mid-settle cancels it instead of fighting the snap home.
	_kill_active_tween()
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "scale", Vector3.ONE, SETTLE_DURATION_SEC)
	_active_tween.parallel().tween_property(self, "rotation:z", 0.0, SETTLE_DURATION_SEC)
