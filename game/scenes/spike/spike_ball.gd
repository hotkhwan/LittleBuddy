extends "res://scripts/interaction/draggable_object.gd"

## The drag/drop regression proof.
##
## An ordinary `DraggableObject`, unchanged in every way, dropped into a scene
## that also has tap-to-walk. If this still picks up, drags, delivers and taps
## exactly as it does in the Baby Room, then navigation has not broken the
## interaction model the game already ships.
##
## Its drop zone is pinned to Little Buddy's chest and is updated every frame, so
## it moves **while the character walks**. Delivering to a moving target is a
## harder case than the Baby Room's stationary baby, and it is the one that would
## expose navigation and dragging fighting over the same pointer.

const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

signal delivered

## The node the drop zone follows (Little Buddy), and the local offset to sit at.
var _follow_node: Node3D = null
var _follow_offset: Vector3 = Vector3.ZERO
var _zone: Area3D = null


## `zone` is a plain Area3D owned by the scene; this object just keeps it glued
## to `follow_node` and asks `DraggableObject` to deliver into it.
func attach_to_character(zone: Area3D, follow_node: Node3D, offset: Vector3, radius: float) -> void:
	_zone = zone
	_follow_node = follow_node
	_follow_offset = offset
	set_drop_zone(zone, radius)


func _process(_delta: float) -> void:
	update_zone_position()


## Extracted so it can be stepped by hand in a test, where there is no frame loop.
func update_zone_position() -> void:
	if _zone == null or not is_instance_valid(_zone):
		return
	if _follow_node == null or not is_instance_valid(_follow_node):
		return
	SpatialUtil.set_world_position(
		_zone, SpatialUtil.world_position(_follow_node) + _follow_offset
	)


func _on_dropped_in_zone() -> void:
	delivered.emit()
