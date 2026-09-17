extends RefCounted

## Pure navigation math: floor ray projection, arrival, waypoint advance, facing,
## reachability and stand positions.
##
## These are the primitives every movement decision is built from, and they are
## the reason the rest of the movement system can be tested at all -- none of
## this needs a camera, a physics world or a synchronised navigation map.

const NavMath := preload("res://scripts/navigation/nav_math.gd")


func test_name() -> String:
	return "nav_math"


func run():
	var failures: Array = []
	failures.append_array(_test_flat_distance_ignores_height())
	failures.append_array(_test_ray_to_floor())
	failures.append_array(_test_path_reaches())
	failures.append_array(_test_advance_path_index())
	failures.append_array(_test_facing())
	failures.append_array(_test_steer_velocity())
	failures.append_array(_test_stand_position())
	return failures


## A character standing slightly above or below the tap point has still arrived.
## If Y counted, a character on a rug would never reach anything.
func _test_flat_distance_ignores_height() -> Array:
	var failures: Array = []
	var a := Vector3(0.0, 0.0, 0.0)
	var b := Vector3(0.0, 5.0, 0.0)
	if not is_equal_approx(NavMath.flat_distance(a, b), 0.0):
		failures.append("flat_distance() must ignore Y, got %f" % NavMath.flat_distance(a, b))
	if not NavMath.is_within(a, b, 0.01):
		failures.append("is_within() must ignore Y")
	if not is_equal_approx(NavMath.flat_distance(Vector3(3.0, 9.0, 4.0), Vector3.ZERO), 5.0):
		failures.append("flat_distance() should be the XZ distance")

	# Boundary is inclusive, so arrival is decided once and never oscillates.
	if not NavMath.is_within(Vector3(0.2, 0.0, 0.0), Vector3.ZERO, 0.2):
		failures.append("a point exactly on the radius must count as within")
	if NavMath.is_within(Vector3(0.3, 0.0, 0.0), Vector3.ZERO, 0.2):
		failures.append("a point outside the radius must not count as within")
	return failures


func _test_ray_to_floor() -> Array:
	var failures: Array = []

	# A ray angled down from a camera hits the floor at a finite point.
	var hit: Variant = NavMath.ray_to_floor(Vector3(0.0, 4.0, 4.0), Vector3(0.0, -1.0, -1.0).normalized(), 0.0)
	if hit == null:
		failures.append("expected a downward ray to hit the floor")
	elif not (hit as Vector3).is_equal_approx(Vector3(0.0, 0.0, 0.0)):
		failures.append("expected the floor hit at the origin, got %s" % str(hit))

	# A non-zero floor height shifts the hit, it does not break it.
	var raised: Variant = NavMath.ray_to_floor(Vector3(0.0, 4.0, 4.0), Vector3(0.0, -1.0, -1.0).normalized(), 1.0)
	if raised == null or not is_equal_approx((raised as Vector3).y, 1.0):
		failures.append("expected the hit to lie on the requested floor plane, got %s" % str(raised))

	# Tapping above the horizon: the ray would only meet the floor behind the
	# camera. Must be null, never a point somewhere past the horizon.
	if NavMath.ray_to_floor(Vector3(0.0, 4.0, 4.0), Vector3(0.0, 0.5, -1.0).normalized(), 0.0) != null:
		failures.append("a ray pointing up must not produce a floor hit")

	# A ray exactly parallel to the floor: null, never a division by zero.
	if NavMath.ray_to_floor(Vector3(0.0, 4.0, 4.0), Vector3(0.0, 0.0, -1.0), 0.0) != null:
		failures.append("a ray parallel to the floor must return null")

	# Degenerate direction.
	if NavMath.ray_to_floor(Vector3(0.0, 4.0, 4.0), Vector3.ZERO, 0.0) != null:
		failures.append("a zero-length ray direction must return null")

	# A camera already on the floor plane still resolves (t == 0).
	var on_plane: Variant = NavMath.ray_to_floor(Vector3(1.0, 0.0, 2.0), Vector3(0.0, -1.0, 0.0), 0.0)
	if on_plane == null or not (on_plane as Vector3).is_equal_approx(Vector3(1.0, 0.0, 2.0)):
		failures.append("a ray starting on the plane should hit at its own origin")
	return failures


## The single most important rule in the whole spike: `map_get_path()` never says
## "unreachable", it silently returns a path that stops short. Comparing the
## path's real endpoint with what was asked for IS the reachability test.
func _test_path_reaches() -> Array:
	var failures: Array = []
	var target := Vector3(5.0, 0.0, 0.0)

	var full := PackedVector3Array([Vector3.ZERO, Vector3(2.0, 0.0, 0.0), target])
	if not NavMath.path_reaches(full, target, 0.25):
		failures.append("a path ending at the target must count as reaching it")

	var short := PackedVector3Array([Vector3.ZERO, Vector3(2.0, 0.0, 0.0)])
	if NavMath.path_reaches(short, target, 0.25):
		failures.append("a path stopping short must NOT count as reaching the target")

	if NavMath.path_reaches(PackedVector3Array(), target, 0.25):
		failures.append("an empty path must never count as reaching the target")

	# Just inside / just outside the tolerance.
	var near := PackedVector3Array([Vector3.ZERO, Vector3(4.8, 0.0, 0.0)])
	if not NavMath.path_reaches(near, target, 0.25):
		failures.append("a path ending within tolerance must count as reaching")
	if NavMath.path_reaches(near, target, 0.1):
		failures.append("tolerance must actually be applied")

	if not NavMath.path_endpoint(short, Vector3.ONE).is_equal_approx(Vector3(2.0, 0.0, 0.0)):
		failures.append("path_endpoint() should return the last point")
	if not NavMath.path_endpoint(PackedVector3Array(), Vector3.ONE).is_equal_approx(Vector3.ONE):
		failures.append("path_endpoint() should fall back for an empty path")
	return failures


func _test_advance_path_index() -> Array:
	var failures: Array = []
	var path := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0),
	])

	# Standing on waypoint 0 consumes it and aims at 1.
	if NavMath.advance_path_index(path, Vector3.ZERO, 0, 0.12) != 1:
		failures.append("standing on a waypoint should consume it")

	# Standing between waypoints consumes nothing.
	if NavMath.advance_path_index(path, Vector3(1.5, 0.0, 0.0), 1, 0.12) != 1:
		failures.append("a position between waypoints should not advance the index")

	# A cluster of waypoints within one radius is consumed in a single step,
	# rather than one per frame (which would stall the character on the spot).
	var cluster := PackedVector3Array([
		Vector3.ZERO, Vector3(0.05, 0.0, 0.0), Vector3(0.1, 0.0, 0.0), Vector3(4.0, 0.0, 0.0),
	])
	if NavMath.advance_path_index(cluster, Vector3.ZERO, 0, 0.12) != 3:
		failures.append("a cluster of waypoints inside the radius should all be consumed at once")

	# But a waypoint that has NOT been reached is never skipped, even if the
	# character is standing much further along the line.
	if NavMath.advance_path_index(path, Vector3(2.0, 0.0, 0.0), 0, 0.12) != 0:
		failures.append("advance must not skip a waypoint the character is not standing on")

	# THE ANTI-JITTER RULE: the index never goes backwards, so drifting back
	# towards a consumed waypoint cannot make the character shuffle between two
	# points forever.
	if NavMath.advance_path_index(path, Vector3.ZERO, 2, 0.12) < 2:
		failures.append("advance_path_index() must never move backwards")

	# Never runs off the end.
	if NavMath.advance_path_index(path, Vector3(3.0, 0.0, 0.0), 3, 0.12) != 3:
		failures.append("the final waypoint must never be consumed past the end")
	if NavMath.advance_path_index(PackedVector3Array(), Vector3.ZERO, 5, 0.12) != 0:
		failures.append("an empty path must return index 0, not a bad index")
	return failures


func _test_facing() -> Array:
	var failures: Array = []

	# Godot's forward is -Z, so facing a point at -Z is yaw 0.
	if not is_equal_approx(NavMath.yaw_towards(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 0.0), 0.0):
		failures.append("facing -Z should be yaw 0, got %f"
				% NavMath.yaw_towards(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 0.0))

	# Facing +X should be yaw -90 degrees (rotating the -Z forward onto +X).
	var east: float = NavMath.yaw_towards(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 0.0)
	var east_forward: Vector3 = Basis.from_euler(Vector3(0.0, east, 0.0)) * Vector3(0.0, 0.0, -1.0)
	if not east_forward.is_equal_approx(Vector3(1.0, 0.0, 0.0)):
		failures.append("yaw_towards() must actually point the -Z forward axis at the target, got %s"
				% str(east_forward))

	# Height is ignored: looking at something above you does not tilt the yaw.
	var raised: float = NavMath.yaw_towards(Vector3.ZERO, Vector3(1.0, 9.0, 0.0), 0.0)
	if not is_equal_approx(raised, east):
		failures.append("yaw_towards() must ignore height")

	# Standing exactly on the target keeps the current heading rather than
	# snapping to an arbitrary direction (which would look like a spin).
	if not is_equal_approx(NavMath.yaw_towards(Vector3.ZERO, Vector3.ZERO, 1.234), 1.234):
		failures.append("a zero-length facing delta must keep the current yaw")

	# step_yaw takes the short way round the circle, not the long way.
	var stepped: float = NavMath.step_yaw(3.0, -3.0, 0.1)
	if not is_equal_approx(stepped, 3.1):
		failures.append("step_yaw() must turn the short way round, got %f" % stepped)
	# And it clamps rather than snapping.
	if is_equal_approx(NavMath.step_yaw(0.0, 1.0, 0.1), 1.0):
		failures.append("step_yaw() must clamp to max_step")
	# Unless the remaining turn is already inside max_step.
	if not is_equal_approx(NavMath.step_yaw(0.0, 0.05, 0.1), 0.05):
		failures.append("step_yaw() must land exactly on target once within max_step")

	if not NavMath.yaw_reached(0.05, 0.0, 0.12):
		failures.append("yaw_reached() should accept a heading inside the tolerance")
	if NavMath.yaw_reached(0.5, 0.0, 0.12):
		failures.append("yaw_reached() should reject a heading outside the tolerance")
	# Across the +/-PI wrap.
	if not NavMath.yaw_reached(PI - 0.01, -PI + 0.01, 0.12):
		failures.append("yaw_reached() must handle the PI wrap")
	return failures


func _test_steer_velocity() -> Array:
	var failures: Array = []

	var velocity: Vector3 = NavMath.steer_velocity(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 0.85, 0.016)
	if not is_equal_approx(velocity.length(), 0.85):
		failures.append("steer_velocity() should run at the requested speed, got %f" % velocity.length())
	if not is_zero_approx(velocity.y):
		failures.append("steer_velocity() must never produce vertical motion")

	# Overshoot clamp: one long frame must not sail past the waypoint.
	var close: Vector3 = NavMath.steer_velocity(Vector3.ZERO, Vector3(0.01, 0.0, 0.0), 5.0, 1.0)
	if close.length() > 0.011:
		failures.append("steer_velocity() must clamp so a frame cannot overshoot, got %f" % close.length())

	# Degenerate inputs are zero, never NaN.
	if not NavMath.steer_velocity(Vector3.ZERO, Vector3.ZERO, 1.0, 0.016).is_equal_approx(Vector3.ZERO):
		failures.append("steering at your own position must be zero velocity")
	if not NavMath.steer_velocity(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 0.0, 0.016).is_equal_approx(Vector3.ZERO):
		failures.append("zero speed must be zero velocity")
	return failures


## Standing to interact: always on the approach side, so Little Buddy never walks
## through an object to stand behind it.
func _test_stand_position() -> Array:
	var failures: Array = []
	var object_at := Vector3(0.0, 0.0, 0.0)

	var from_east: Vector3 = NavMath.stand_position(object_at, Vector3(5.0, 0.0, 0.0), 0.5)
	if not from_east.is_equal_approx(Vector3(0.5, 0.0, 0.0)):
		failures.append("approaching from +X should stand at +X, got %s" % str(from_east))

	var from_west: Vector3 = NavMath.stand_position(object_at, Vector3(-5.0, 0.0, 0.0), 0.5)
	if not from_west.is_equal_approx(Vector3(-0.5, 0.0, 0.0)):
		failures.append("approaching from -X should stand at -X, got %s" % str(from_west))

	# Standing exactly on the object is degenerate but must still be finite.
	var degenerate: Vector3 = NavMath.stand_position(object_at, object_at, 0.5)
	if is_nan(degenerate.x) or is_nan(degenerate.z):
		failures.append("a degenerate approach must not produce NaN")
	if not is_equal_approx(NavMath.flat_distance(degenerate, object_at), 0.5):
		failures.append("a degenerate approach should still stand the right distance away")

	# Never lifted off the floor by the approach height.
	var from_above: Vector3 = NavMath.stand_position(object_at, Vector3(5.0, 3.0, 0.0), 0.5)
	if not is_equal_approx(from_above.y, 0.0):
		failures.append("stand_position() must stay at the target's height")
	return failures
