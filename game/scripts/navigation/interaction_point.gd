@tool
extends Marker3D

## Where Little Buddy stands, and which way Little Buddy looks, in order to
## interact with the thing this marker belongs to.
##
## Authored in the scene next to the object rather than computed, because "the
## right side of the sink, facing the taps" is a set-dressing decision and the
## person placing the sink is the person who knows it. An `ActivityTarget`
## without one of these falls back to a computed stand position (see
## `NavMath.stand_position()`), which is serviceable but will occasionally put
## the character somewhere silly -- inside a bed, say.
##
## Facing defaults to the parent object. `face_point_path` overrides it, for the
## cases where you want the character looking at a tap rather than at the sink's
## centre of mass.

const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## Node to look at on arrival. Relative to this marker. Empty means "look at my
## parent", which is right almost every time.
@export var face_point_path: NodePath = NodePath()

## Optional: how far to stand back from the facing point. Zero (the default)
## means this marker's own position is the stand position, which is the whole
## reason it was placed by hand.
@export var extra_stand_distance: float = 0.0


## GLOBAL position to stand at. Derived from the live transform every call, so it
## tracks a moved or animated parent instead of drifting from a cached value --
## the same rule `BabyView3D.get_mouth_position()` follows.
func get_stand_position() -> Vector3:
	var here: Vector3 = SpatialUtil.world_position(self)
	if extra_stand_distance <= 0.0:
		return here
	var face: Vector3 = get_facing_position()
	var away: Vector3 = Vector3(here.x - face.x, 0.0, here.z - face.z)
	if away.length() <= 0.000001:
		away = Vector3.BACK
	return face + away.normalized() * extra_stand_distance


## GLOBAL position to turn towards on arrival.
func get_facing_position() -> Vector3:
	if not face_point_path.is_empty():
		var explicit: Node = get_node_or_null(face_point_path)
		if explicit is Node3D:
			return SpatialUtil.world_position(explicit as Node3D)
	var parent: Node = get_parent()
	if parent is Node3D:
		return SpatialUtil.world_position(parent as Node3D)
	return SpatialUtil.world_position(self)
