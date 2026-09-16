class_name DragPlane
extends RefCounted

## Pure, testable math for the Baby Room's drag interactions
## (`MilkBottle`, `Teddy`). No Node/Viewport/Camera3D dependency, so this can
## be unit tested headlessly without a running scene tree -- see
## `res://tests/cases/test_drag_plane.gd`.
##
## The drag plane itself is computed ONCE at drag start (`make_plane`) and
## reused for the whole drag. Recomputing a plane from the latest hit point
## every frame would let the plane wander as the finger moves, producing the
## drift/jitter this design explicitly avoids.


## Builds a plane through `anchor_point` whose normal faces `camera_position`.
## Degenerate case (camera exactly at the anchor) falls back to a fixed
## arbitrary unit normal instead of producing a zero-length/NaN normal.
static func make_plane(anchor_point: Vector3, camera_position: Vector3) -> Plane:
	var to_camera: Vector3 = camera_position - anchor_point
	var normal: Vector3
	if to_camera.length_squared() < 0.000001:
		normal = Vector3.BACK
	else:
		normal = to_camera.normalized()
	return Plane(normal, anchor_point.dot(normal))


## Intersects the ray (`ray_origin`, `ray_direction`) with `plane`.
## Returns a Vector3 hit point, or `null` when:
##   - the ray is parallel to the plane (no unique intersection), or
##   - the intersection lies behind the ray origin.
## Never returns NaN and never divides by zero -- both are guarded explicitly
## so a stray/degenerate input (e.g. a zero-length direction, which makes the
## denominator exactly zero) always degrades to "no hit" instead of crashing.
static func intersect_ray(plane: Plane, ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	var denom: float = plane.normal.dot(ray_direction)
	if is_zero_approx(denom):
		return null
	var t: float = (plane.d - plane.normal.dot(ray_origin)) / denom
	if t < 0.0:
		return null
	return ray_origin + ray_direction * t


## Drop-zone hit test: true when `point` lies within `radius` of `zone_center`.
## A point exactly on the boundary counts as inside (inclusive), which keeps
## the check stable/repeatable at the edge instead of flip-flopping on
## floating point noise.
static func point_in_drop_zone(point: Vector3, zone_center: Vector3, radius: float) -> bool:
	return point.distance_squared_to(zone_center) <= radius * radius
