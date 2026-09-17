extends RefCounted

## Pure, static, testable math for tap-to-walk. No Node, no Camera3D, no
## NavigationAgent3D, no SceneTree -- exactly the same trick
## `scripts/interaction/drag_plane.gd` uses for dragging, and for the same
## reason: the headless `--script` test runner has no physics frames and no
## synchronised navigation map, so every decision that *can* be pure is pure and
## is covered by real assertions.
##
## Everything here works on the horizontal plane. Y is deliberately ignored for
## distance/arrival tests: a child taps a floor, and a character standing 2 cm
## lower than the tap point has still arrived.
##
## Referenced by `preload()` rather than `class_name` -- global class names come
## from the editor's script-class cache, which the headless runner does not
## build.

## Absorbs the float32 (Vector3) vs float64 (GDScript float) rounding mismatch so
## an exact-boundary comparison is stable rather than flip-flopping.
const EPSILON: float = 0.000001


## Horizontal (XZ) distance. Y is ignored on purpose -- see the class docs.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


## True when `a` is within `radius` of `b` horizontally. Inclusive at the
## boundary, so arrival is decided once and never oscillates.
static func is_within(a: Vector3, b: Vector3, radius: float) -> bool:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return dx * dx + dz * dz <= radius * radius + EPSILON


## Flattens `point` onto the plane `y = floor_y`.
static func flatten(point: Vector3, floor_y: float) -> Vector3:
	return Vector3(point.x, floor_y, point.z)


## Intersects a camera ray with the horizontal floor plane `y = floor_y`.
##
## Returns a Vector3, or `null` when the ray is parallel to the floor or would
## only hit it *behind* the camera (tapping the sky above the horizon). Never
## returns NaN and never divides by zero -- a degenerate input degrades to "no
## hit", which the caller turns into a harmless ignored tap rather than a walk to
## a garbage coordinate somewhere past the horizon.
static func ray_to_floor(ray_origin: Vector3, ray_direction: Vector3, floor_y: float) -> Variant:
	if is_zero_approx(ray_direction.y):
		return null
	var t: float = (floor_y - ray_origin.y) / ray_direction.y
	if t < 0.0:
		return null
	var hit: Vector3 = ray_origin + ray_direction * t
	if is_nan(hit.x) or is_nan(hit.y) or is_nan(hit.z):
		return null
	return hit


## True when `path` actually ends at `target`.
##
## This is how reachability is decided. `NavigationServer3D.map_get_path()` never
## fails loudly: asked for a point off the navigation mesh it silently returns a
## path to the closest point it *could* reach, so the only way to know a tap was
## unreachable is to compare the path's last point with what was asked for.
## An empty path is never a reach.
static func path_reaches(path: PackedVector3Array, target: Vector3, tolerance: float) -> bool:
	if path.is_empty():
		return false
	return is_within(path[path.size() - 1], target, tolerance)


## The point the character will really end up at: the last point of `path`, or
## `fallback` when the path is empty.
static func path_endpoint(path: PackedVector3Array, fallback: Vector3) -> Vector3:
	if path.is_empty():
		return fallback
	return path[path.size() - 1]


## Index of the waypoint to steer at next.
##
## Consumes every waypoint already within `waypoint_radius` and never moves
## backwards, so a character that drifts slightly cannot re-target a waypoint it
## has already passed and start shuffling between two points (the classic
## navigation jitter). The returned index is always a valid index into `path`
## unless the path is empty, in which case it is 0.
static func advance_path_index(
	path: PackedVector3Array, position: Vector3, index: int, waypoint_radius: float
) -> int:
	if path.is_empty():
		return 0
	var next: int = maxi(index, 0)
	var last: int = path.size() - 1
	while next < last and is_within(position, path[next], waypoint_radius):
		next += 1
	return mini(next, last)


## Yaw (radians, for `Node3D.rotation.y`) that points the node's -Z forward axis
## from `from` towards `to`. A zero-length delta keeps `current_yaw` rather than
## snapping to an arbitrary direction, so arriving exactly on top of a target
## never makes the character spin.
static func yaw_towards(from: Vector3, to: Vector3, current_yaw: float) -> float:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	if absf(dx) < EPSILON and absf(dz) < EPSILON:
		return current_yaw
	return atan2(-dx, -dz)


## Rotates `current` towards `target` by at most `max_step` radians, the short
## way round. Calm, never a snap -- a child should see Little Buddy turn.
static func step_yaw(current: float, target: float, max_step: float) -> float:
	var difference: float = angle_difference(current, target)
	if absf(difference) <= max_step:
		return target
	return current + signf(difference) * max_step


## True once the character is facing `target_yaw` within `tolerance`.
static func yaw_reached(current: float, target_yaw: float, tolerance: float) -> bool:
	return absf(angle_difference(current, target_yaw)) <= tolerance + EPSILON


## Horizontal velocity that walks `position` towards `waypoint` at `speed`,
## clamped so a single long frame can never overshoot the waypoint (which would
## show up as a visible stutter-and-correct). Y is always 0: gravity is the
## character body's business, not the path's.
static func steer_velocity(position: Vector3, waypoint: Vector3, speed: float, delta: float) -> Vector3:
	var to_waypoint: Vector3 = Vector3(waypoint.x - position.x, 0.0, waypoint.z - position.z)
	var distance: float = to_waypoint.length()
	if distance <= EPSILON or speed <= 0.0:
		return Vector3.ZERO
	var capped: float = speed
	if delta > 0.0:
		capped = minf(speed, distance / delta)
	return (to_waypoint / distance) * capped


## Where to stand in order to interact with something at `target_position`.
##
## `stand_distance` metres away, on the side the character is approaching from,
## so Little Buddy never walks *through* an object to reach the far side of it
## for no reason. Degenerate case (already exactly on the target) falls back to
## +Z so the result is always a real, finite position.
static func stand_position(
	target_position: Vector3, approach_from: Vector3, stand_distance: float
) -> Vector3:
	var away: Vector3 = Vector3(
		approach_from.x - target_position.x, 0.0, approach_from.z - target_position.z
	)
	if away.length() <= EPSILON:
		away = Vector3.BACK
	return target_position + away.normalized() * maxf(stand_distance, 0.0)
