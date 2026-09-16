extends RefCounted


func test_name() -> String:
	return "drag_plane"


func run() -> Array:
	var failures: Array = []

	var anchor: Vector3 = Vector3(1.0, 0.5, 0.2)
	var camera_pos: Vector3 = Vector3(1.0, 0.5, 3.0)  # directly "in front of" the anchor along +Z
	var plane: Plane = DragPlane.make_plane(anchor, camera_pos)

	if not plane.normal.is_equal_approx(Vector3(0.0, 0.0, 1.0)):
		failures.append("make_plane() normal should face the camera along +Z, got %s" % plane.normal)

	# -- A ray straight into the plane hits it exactly at the anchor.
	var ray_origin: Vector3 = Vector3(1.0, 0.5, 10.0)
	var ray_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
	var hit: Variant = DragPlane.intersect_ray(plane, ray_origin, ray_direction)
	if hit == null:
		failures.append("expected a perpendicular ray to hit the plane")
	elif not (hit as Vector3).is_equal_approx(anchor):
		failures.append("expected the hit point to equal the anchor, got %s" % hit)

	# -- An off-center parallel ray still hits the (infinite) plane, at the correct depth.
	var offset_origin: Vector3 = Vector3(3.0, 2.0, 10.0)
	var offset_hit: Variant = DragPlane.intersect_ray(plane, offset_origin, ray_direction)
	if offset_hit == null:
		failures.append("expected an off-center parallel ray to still hit the plane")
	elif not is_equal_approx((offset_hit as Vector3).z, anchor.z):
		failures.append("expected the hit point to lie on the plane (z == anchor.z), got %s" % offset_hit)

	# -- A ray parallel to the plane (perpendicular to its normal) must return
	#    null -- never NaN, never a crash.
	var parallel_direction: Vector3 = Vector3(1.0, 0.0, 0.0)
	var parallel_hit: Variant = DragPlane.intersect_ray(plane, ray_origin, parallel_direction)
	if parallel_hit != null:
		failures.append("expected a ray parallel to the plane to return null, got %s" % parallel_hit)

	# -- A degenerate (zero-length) ray direction must also return null, never NaN/crash.
	var degenerate_hit: Variant = DragPlane.intersect_ray(plane, ray_origin, Vector3.ZERO)
	if degenerate_hit != null:
		failures.append("expected a zero-length ray direction to return null")

	# -- A ray pointing away from the plane (intersection behind the origin) must return null.
	var away_hit: Variant = DragPlane.intersect_ray(plane, ray_origin, Vector3(0.0, 0.0, 1.0))
	if away_hit != null:
		failures.append("expected a ray pointing away from the plane to return null")

	# -- Stability: the exact same ray always produces the exact same result.
	var repeat_hit: Variant = DragPlane.intersect_ray(plane, ray_origin, ray_direction)
	var same_result: bool = (hit == null and repeat_hit == null) or (
		hit is Vector3 and repeat_hit is Vector3 and (hit as Vector3).is_equal_approx(repeat_hit as Vector3)
	)
	if not same_result:
		failures.append("expected repeated calls with the same ray to produce the same result")

	# -- Degenerate make_plane(): camera exactly at the anchor must not crash/NaN,
	#    and must still produce a stable, unit-length normal.
	var degenerate_plane: Plane = DragPlane.make_plane(anchor, anchor)
	if is_nan(degenerate_plane.normal.x) or is_nan(degenerate_plane.normal.y) or is_nan(degenerate_plane.normal.z):
		failures.append("make_plane() with camera == anchor produced a NaN normal")
	if not is_equal_approx(degenerate_plane.normal.length(), 1.0):
		failures.append("make_plane() should always produce a unit-length normal")

	# -- point_in_drop_zone(): inside / outside / boundary.
	var zone_center: Vector3 = Vector3(0.0, 0.0, 0.0)
	var radius: float = 0.2

	if not DragPlane.point_in_drop_zone(Vector3(0.05, 0.0, 0.0), zone_center, radius):
		failures.append("expected a point well inside the radius to be in the drop zone")

	if DragPlane.point_in_drop_zone(Vector3(1.0, 0.0, 0.0), zone_center, radius):
		failures.append("expected a point well outside the radius to NOT be in the drop zone")

	if not DragPlane.point_in_drop_zone(Vector3(radius, 0.0, 0.0), zone_center, radius):
		failures.append("expected a point exactly on the boundary to count as inside the drop zone")

	return failures
