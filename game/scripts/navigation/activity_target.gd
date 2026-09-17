extends Area3D

## A thing in the world that Little Buddy can be told to go to, addressed by a
## **semantic id** and nothing else.
##
## This is the object on the far side of the architecture rule. Mission and
## content code says `character.move_to("milkBottle")`; it never sees this node,
## never sees a `Vector3`, and never sees a `NavigationAgent3D`. Everything
## spatial -- where to stand, which way to face, how close is close enough --
## lives here, in the scene, next to the art.
##
## ## Layers
##
## Activity targets sit alone on collision layer 2 so that tap-routing can
## raycast for them without colliding with the existing draggable pickups on
## layer 1. `input_ray_pickable` stays false: these are found by
## `NavigationController`'s explicit raycast, not by viewport physics picking, so
## a target can never swallow a press that a `DraggableObject` needed. That is
## what keeps drag-and-drop working unchanged alongside navigation.
##
## ## Lazy wiring
##
## Everything resolves on first use rather than in `_ready()`. The headless
## `--script` test runner never fires `_ready()` for nodes added to the root, so a
## target that only worked after `_ready()` would be untestable -- the same reason
## `session_summary.gd` has `_ensure_resolved()`.

const NavMath := preload("res://scripts/navigation/nav_math.gd")
const InteractionPointScript := preload("res://scripts/navigation/interaction_point.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## Layer 2 (bit value 2). Layer 1 belongs to `DraggableObject`.
const ACTIVITY_TARGET_LAYER: int = 2

## Used when no `InteractionPoint` child was authored: stand this far back from
## the object, on whichever side the character is approaching from.
const DEFAULT_STAND_DISTANCE: float = 0.55

## How close the character must get before this target counts as reached.
## Deliberately looser than a floor tap: arriving "at the sink" means standing
## near it, not on a specific square centimetre.
const DEFAULT_ARRIVAL_RADIUS: float = 0.22

## The semantic name mission/content code uses. Must be unique within a room.
@export var target_id: String = ""

## Shown/spoken name, if a room ever wants to label it. Not used for routing.
@export var display_name: String = ""

## A disabled target is still in the scene but cannot be walked to -- the
## equivalent of `DraggableObject.set_enabled(false)`, and used for the same
## reason: an object that is not part of the current task must not be tappable.
@export var target_enabled: bool = true

@export var stand_distance: float = DEFAULT_STAND_DISTANCE
@export var arrival_radius: float = DEFAULT_ARRIVAL_RADIUS

var _resolved: bool = false
var _interaction_point: Marker3D = null


func _ready() -> void:
	_ensure_resolved()


## Idempotent, and called from every public method, so this node behaves
## identically whether or not `_ready()` ever ran.
func _ensure_resolved() -> void:
	if _resolved:
		return
	_resolved = true
	collision_layer = ACTIVITY_TARGET_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = false
	input_ray_pickable = false
	for child: Node in get_children():
		if child is Marker3D and child.get_script() == InteractionPointScript:
			_interaction_point = child as Marker3D
			return
	# Tolerate a plain Marker3D named InteractionPoint, so a scene authored
	# before the script existed still works.
	var named: Node = get_node_or_null("InteractionPoint")
	if named is Marker3D:
		_interaction_point = named as Marker3D


## The semantic id. Duck-typed on purpose: `NavigationController` walks up the
## ancestors of whatever its raycast hit looking for anything that answers this,
## so a target can be wrapped in a prop scene without any type coupling.
func get_activity_target_id() -> String:
	_ensure_resolved()
	return target_id


func is_target_enabled() -> bool:
	_ensure_resolved()
	return target_enabled


func set_target_enabled(value: bool) -> void:
	_ensure_resolved()
	target_enabled = value


func has_interaction_point() -> bool:
	_ensure_resolved()
	return _interaction_point != null


## Where to stand. An authored `InteractionPoint` wins; otherwise it is computed
## on the approach side so the character does not walk through the object to
## reach an arbitrary fixed spot behind it.
func get_stand_position(approach_from: Vector3) -> Vector3:
	_ensure_resolved()
	if _interaction_point != null and _interaction_point.has_method("get_stand_position"):
		return _interaction_point.call("get_stand_position")
	if _interaction_point != null:
		return SpatialUtil.world_position(_interaction_point)
	return NavMath.stand_position(SpatialUtil.world_position(self), approach_from, stand_distance)


## What to turn towards on arrival.
func get_facing_position() -> Vector3:
	_ensure_resolved()
	if _interaction_point != null and _interaction_point.has_method("get_facing_position"):
		return _interaction_point.call("get_facing_position")
	return SpatialUtil.world_position(self)


## Everything a mover needs, in one call. Keyed camelCase to match the project's
## JSON/dictionary convention.
func describe(approach_from: Vector3) -> Dictionary:
	_ensure_resolved()
	return {
		"targetId": target_id,
		"displayName": display_name,
		"enabled": target_enabled,
		"standPosition": get_stand_position(approach_from),
		"facePosition": get_facing_position(),
		"arrivalRadius": arrival_radius,
	}
