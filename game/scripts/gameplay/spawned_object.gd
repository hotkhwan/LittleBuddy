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


## -- Identity ----------------------------------------------------------------

func configure(spec: Dictionary) -> void:
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
