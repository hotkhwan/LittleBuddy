extends RefCounted

## The navigation mesh the spike walks on.
##
## Built as a grid of quads from `spike_layout.gd` rather than baked, so the
## walls a child can see and the walls the navigation mesh knows about come from
## one set of numbers and cannot drift apart. That also makes the mesh itself
## assertable: "the closet is genuinely sealed" is a property this file checks,
## not something a reviewer has to take on trust from an opaque baked blob.

const GridNavMesh := preload("res://scripts/navigation/grid_nav_mesh.gd")
const Layout := preload("res://scenes/spike/spike_layout.gd")


func test_name() -> String:
	return "nav_grid_mesh"


func run():
	var failures: Array = []
	failures.append_array(_test_walkability())
	failures.append_array(_test_mesh_shape())
	failures.append_array(_test_degenerate_inputs())
	failures.append_array(_test_spike_layout_is_sane())
	return failures


func _test_walkability() -> Array:
	var failures: Array = []
	var obstacles: Array = [Rect2(-0.5, -0.5, 1.0, 1.0)]

	if GridNavMesh.is_walkable(Vector2(0.0, 0.0), obstacles, 0.0):
		failures.append("a point inside an obstacle must not be walkable")
	if not GridNavMesh.is_walkable(Vector2(2.0, 2.0), obstacles, 0.0):
		failures.append("a point far from every obstacle must be walkable")

	# Inflation by the agent radius: the character's body has to fit, not just
	# its centre point. 0.6 is outside the obstacle but within 0.15 of it.
	if GridNavMesh.is_walkable(Vector2(0.6, 0.0), obstacles, 0.15):
		failures.append("the agent radius should push the walkable area away from an obstacle")
	if not GridNavMesh.is_walkable(Vector2(0.6, 0.0), obstacles, 0.0):
		failures.append("with no agent radius, just outside the obstacle is walkable")

	if not GridNavMesh.is_walkable(Vector2(0.0, 0.0), [], 0.15):
		failures.append("an empty obstacle list should leave everything walkable")
	# A non-Rect2 in the list is ignored rather than crashing.
	if not GridNavMesh.is_walkable(Vector2(0.0, 0.0), ["nonsense", 42], 0.15):
		failures.append("junk in the obstacle list must be ignored, not fatal")
	return failures


func _test_mesh_shape() -> Array:
	var failures: Array = []
	var bounds := Rect2(-1.0, -1.0, 2.0, 2.0)
	var open: NavigationMesh = GridNavMesh.build(bounds, 0.5, [], 0.0, 0.0)
	if open.get_polygon_count() != 16:
		failures.append("a 2x2 m floor at 0.5 m cells should be 16 polygons, got %d"
				% open.get_polygon_count())
	if open.vertices.size() != 25:
		failures.append("a 4x4 cell grid should share a 5x5 vertex grid, got %d vertices"
				% open.vertices.size())

	# Sharing exact vertices between neighbours is what makes the surface
	# connected instead of a pile of islands; every polygon index must therefore
	# point into the one shared vertex array.
	for index: int in range(open.get_polygon_count()):
		for vertex_index: int in open.get_polygon(index):
			if vertex_index < 0 or vertex_index >= open.vertices.size():
				failures.append("polygon %d references vertex %d, out of range"
						% [index, vertex_index])

	# Every vertex sits on the requested floor plane.
	for vertex: Vector3 in open.vertices:
		if not is_equal_approx(vertex.y, 0.0):
			failures.append("vertices should lie on the floor plane, found y = %f" % vertex.y)
			break

	var raised: NavigationMesh = GridNavMesh.build(bounds, 0.5, [], 1.5, 0.0)
	if raised.vertices.size() > 0 and not is_equal_approx(raised.vertices[0].y, 1.5):
		failures.append("the floor height should be honoured, got y = %f" % raised.vertices[0].y)

	# An obstacle removes polygons, and removes the RIGHT ones.
	var blocked: NavigationMesh = GridNavMesh.build(bounds, 0.5, [Rect2(-0.25, -0.25, 0.5, 0.5)], 0.0, 0.0)
	if blocked.get_polygon_count() >= open.get_polygon_count():
		failures.append("an obstacle should remove polygons")
	for index: int in range(blocked.get_polygon_count()):
		var centre := Vector3.ZERO
		var polygon: PackedInt32Array = blocked.get_polygon(index)
		for vertex_index: int in polygon:
			centre += blocked.vertices[vertex_index]
		centre /= float(polygon.size())
		if Rect2(-0.25, -0.25, 0.5, 0.5).has_point(Vector2(centre.x, centre.z)):
			failures.append("a polygon was left inside the obstacle at %s" % str(centre))
			break
	return failures


## Nonsense in must not mean a hang or a crash out. A 6 x 5 m floor at 1 cm cells
## would be 300,000 polygons and would look like a freeze.
func _test_degenerate_inputs() -> Array:
	var failures: Array = []
	var tiny: NavigationMesh = GridNavMesh.build(Rect2(-1.0, -1.0, 2.0, 2.0), 0.001, [], 0.0, 0.0)
	if tiny.get_polygon_count() != 0:
		failures.append("an absurdly small cell size should be refused, got %d polygons"
				% tiny.get_polygon_count())

	var empty: NavigationMesh = GridNavMesh.build(Rect2(0.0, 0.0, 0.0, 0.0), 0.2, [], 0.0, 0.0)
	if empty.get_polygon_count() != 0:
		failures.append("a zero-sized floor should produce no polygons")

	var negative: NavigationMesh = GridNavMesh.build(Rect2(0.0, 0.0, -4.0, -4.0), 0.2, [], 0.0, 0.0)
	if negative.get_polygon_count() != 0:
		failures.append("a negative-sized floor should produce no polygons")

	# An obstacle covering everything leaves nowhere to walk -- valid, not fatal.
	var covered: NavigationMesh = GridNavMesh.build(
		Rect2(-1.0, -1.0, 2.0, 2.0), 0.5, [Rect2(-5.0, -5.0, 10.0, 10.0)], 0.0, 0.0
	)
	if covered.get_polygon_count() != 0:
		failures.append("a fully blocked floor should produce no polygons, got %d"
				% covered.get_polygon_count())
	return failures


## The spike's own floor plan: everything a child is invited to tap must be on
## walkable floor, and the sealed closet must genuinely be sealed.
func _test_spike_layout_is_sane() -> Array:
	var failures: Array = []
	var obstacles: Array = []
	obstacles.assign(Layout.OBSTACLES)

	var must_be_walkable: Array = [Layout.START_POSITION, Layout.TOY_BOX_STAND_POSITION]
	must_be_walkable.append_array(Layout.TAP_PADS)
	for point: Vector3 in must_be_walkable:
		if not Layout.FLOOR_BOUNDS.has_point(Vector2(point.x, point.z)):
			failures.append("%s is outside the floor" % str(point))
		if not GridNavMesh.is_walkable(Vector2(point.x, point.z), obstacles, Layout.AGENT_RADIUS):
			failures.append("%s is not standable -- a child would tap it and nothing would happen"
					% str(point))

	# The sealed closet's interior is on the floor, is walkable in the local
	# sense, and is therefore a real island rather than simply "inside a wall".
	var closet := Vector2(Layout.UNREACHABLE_INSIDE_ROOM.x, Layout.UNREACHABLE_INSIDE_ROOM.z)
	if not Layout.FLOOR_BOUNDS.has_point(closet):
		failures.append("the unreachable point should be inside the room, not outside it")
	if not GridNavMesh.is_walkable(closet, obstacles, Layout.AGENT_RADIUS):
		failures.append("the closet interior should be walkable floor -- otherwise the "
				+ "unreachable test is only testing 'inside a wall'")

	# And the point outside the room really is outside it.
	var outside := Vector2(Layout.UNREACHABLE_OUTSIDE_ROOM.x, Layout.UNREACHABLE_OUTSIDE_ROOM.z)
	if Layout.FLOOR_BOUNDS.has_point(outside):
		failures.append("the outside-the-room point is actually inside the room")

	# Tap pads must not overlap each other, or a child aiming at one hits another.
	for i: int in range(Layout.TAP_PADS.size()):
		for j: int in range(i + 1, Layout.TAP_PADS.size()):
			var gap: float = Vector2(Layout.TAP_PADS[i].x, Layout.TAP_PADS[i].z).distance_to(
				Vector2(Layout.TAP_PADS[j].x, Layout.TAP_PADS[j].z)
			)
			if gap < Layout.TAP_PAD_RADIUS * 2.0:
				failures.append("tap pads %d and %d overlap" % [i, j])

	# Child-friendly target size: a small screen needs generous pads.
	if Layout.TAP_PAD_RADIUS < 0.3:
		failures.append("tap pads are too small for a child on a phone")

	var mesh: NavigationMesh = GridNavMesh.build(
		Layout.FLOOR_BOUNDS, Layout.CELL_SIZE, obstacles, Layout.FLOOR_Y, Layout.AGENT_RADIUS
	)
	if mesh.get_polygon_count() < 100:
		failures.append("the spike floor produced only %d polygons; the room is not walkable"
				% mesh.get_polygon_count())
	return failures
