extends RefCounted

## The genuinely engine-dependent half: a REAL `NavigationServer3D` map, built
## from the spike's real navigation mesh, queried with real paths.
##
## ## Why this can be tested at all
##
## Navigation maps synchronise on physics frames and the `--script` runner runs
## none, so a fresh map answers every query with nothing and logs
## "query failed because it was made before first map synchronization".
## `NavMapProvider.force_sync()` drives the map through a real synchronisation by
## calling `map_force_update()` until the map reports a non-zero iteration id --
## `map_force_update()` is itself two-phase, so one call is not enough. Measured
## on Godot 4.7.2 it settles on the second call.
##
## If that ever stops working, this file must fail loudly rather than quietly
## assert nothing, so the first thing it does is prove the map really is live.
##
## Covers the reachability half of required behaviours 1, 2 and 4 against real
## pathfinding rather than against a stub.

const NavMapProvider := preload("res://scripts/navigation/nav_map_provider.gd")
const GridNavMesh := preload("res://scripts/navigation/grid_nav_mesh.gd")
const MovementController := preload("res://scripts/character/character_movement_controller.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const Layout := preload("res://scenes/spike/spike_layout.gd")

var _map: RID = RID()
var _region: RID = RID()


func test_name() -> String:
	return "nav_map_provider"


func run():
	var failures: Array = []
	var provider: RefCounted = _build_spike_map()

	if not bool(provider.call("force_sync")):
		# Never silently pass. A navigation test that cannot reach the navigation
		# server is not a passing test, it is an absent one.
		_teardown()
		return ["the navigation map never synchronised; every assertion below "
				+ "would have been vacuous. Check NavMapProvider.force_sync()."]
	if not bool(provider.call("is_navigation_ready")):
		_teardown()
		return ["the provider reports the map is not ready after force_sync()"]

	failures.append_array(_test_map_is_really_live(provider))
	failures.append_array(_test_reachable_destinations(provider))
	failures.append_array(_test_paths_route_around_obstacles(provider))
	failures.append_array(_test_sealed_closet_is_unreachable(provider))
	failures.append_array(_test_outside_the_room_is_unreachable(provider))
	failures.append_array(_test_controller_over_a_real_map(provider))
	failures.append_array(_test_unready_provider_degrades_to_a_straight_line())

	_teardown()
	return failures


## Guards against the whole file becoming vacuous: if the map answers nothing,
## `path_reaches()` returns false for everything and the "unreachable" assertions
## below would pass for entirely the wrong reason.
func _test_map_is_really_live(provider: RefCounted) -> Array:
	var failures: Array = []
	var snapped: Vector3 = provider.call("snap_to_navigable", Layout.UNREACHABLE_OUTSIDE_ROOM)
	if snapped.is_equal_approx(Vector3.ZERO):
		failures.append("snap_to_navigable() returned the origin -- the map is not answering")
	if not Layout.FLOOR_BOUNDS.grow(0.3).has_point(Vector2(snapped.x, snapped.z)):
		failures.append("snapping a far-away point should land inside the room, got %s" % str(snapped))

	var path: PackedVector3Array = provider.call(
		"query_path", Layout.START_POSITION, Layout.TAP_PADS[0]
	)
	if path.size() < 2:
		failures.append("a path across an open floor should have at least two points, got %d"
				% path.size())
	return failures


func _test_reachable_destinations(provider: RefCounted) -> Array:
	var failures: Array = []
	for pad: Vector3 in Layout.TAP_PADS:
		var path: PackedVector3Array = provider.call("query_path", Layout.START_POSITION, pad)
		if not NavMath.path_reaches(path, pad, MovementController.REACH_TOLERANCE):
			failures.append("tap pad %s is not reachable from the start; a child would tap it "
					% str(pad) + "and nothing would happen (path ends at %s)"
					% str(NavMath.path_endpoint(path, Vector3.ZERO)))

	var stand: Vector3 = Layout.TOY_BOX_STAND_POSITION
	var to_box: PackedVector3Array = provider.call("query_path", Layout.START_POSITION, stand)
	if not NavMath.path_reaches(to_box, stand, MovementController.REACH_TOLERANCE):
		failures.append("the toy box's interaction point is not reachable")
	return failures


## The table sits between the start position and the toy box. A path that ignores
## it would walk Little Buddy straight through the furniture.
func _test_paths_route_around_obstacles(provider: RefCounted) -> Array:
	var failures: Array = []
	var table: Rect2 = Layout.OBSTACLES[Layout.TABLE_OBSTACLE_INDEX]
	var from := Vector3(0.0, 0.0, 1.6)
	var to := Vector3(0.0, 0.0, -1.6)

	var path: PackedVector3Array = provider.call("query_path", from, to)
	if not NavMath.path_reaches(path, to, MovementController.REACH_TOLERANCE):
		failures.append("the far side of the table should still be reachable")
		return failures
	if path.size() < 3:
		failures.append("a path straight through the table should have been bent around it, "
				+ "got a %d-point path" % path.size())

	# Sample the path densely and confirm it never passes through the table.
	for index: int in range(path.size() - 1):
		var a: Vector3 = path[index]
		var b: Vector3 = path[index + 1]
		for sample: int in range(21):
			var point: Vector3 = a.lerp(b, float(sample) / 20.0)
			if table.has_point(Vector2(point.x, point.z)):
				failures.append("the path crosses the table at %s" % str(point))
				return failures
	return failures


## The headline unreachable case, and the realistic one: floor a child can see,
## inside the room, behind a closed wall.
func _test_sealed_closet_is_unreachable(provider: RefCounted) -> Array:
	var failures: Array = []
	var closet: Vector3 = Layout.UNREACHABLE_INSIDE_ROOM
	var path: PackedVector3Array = provider.call("query_path", Layout.START_POSITION, closet)

	if NavMath.path_reaches(path, closet, MovementController.REACH_TOLERANCE):
		failures.append("the sealed closet is reachable -- the walls are not actually sealing it")

	# And it must be far enough away that the forgiving snap does not quietly
	# accept it, or "unreachable" would only ever mean "slightly off the mesh".
	var endpoint: Vector3 = NavMath.path_endpoint(path, Layout.START_POSITION)
	var gap: float = NavMath.flat_distance(endpoint, closet)
	if gap <= MovementController.SNAP_RADIUS:
		failures.append("the closet is only %.2f m from the nearest standable point, inside the "
				% gap + "snap radius; it would be forgiven rather than refused")
	return failures


func _test_outside_the_room_is_unreachable(provider: RefCounted) -> Array:
	var failures: Array = []
	var outside: Vector3 = Layout.UNREACHABLE_OUTSIDE_ROOM
	var path: PackedVector3Array = provider.call("query_path", Layout.START_POSITION, outside)
	if NavMath.path_reaches(path, outside, MovementController.REACH_TOLERANCE):
		failures.append("a point far outside the room should not be reachable")

	# A tap just past the skirting board, on the other hand, IS forgiven.
	var near_edge := Vector3(Layout.FLOOR_BOUNDS.end.x + 0.3, 0.0, 1.5)
	var near_path: PackedVector3Array = provider.call("query_path", Layout.START_POSITION, near_edge)
	var near_gap: float = NavMath.flat_distance(
		NavMath.path_endpoint(near_path, Vector3.ZERO), near_edge
	)
	if near_gap > MovementController.SNAP_RADIUS:
		failures.append("a tap 0.3 m past the wall ends %.2f m from the nearest standable point; "
				% near_gap + "a child's near-miss would be refused")
	return failures


## The full stack over real pathfinding: reachable target accepted and walked,
## unreachable target refused without disturbing anything.
func _test_controller_over_a_real_map(provider: RefCounted) -> Array:
	var failures: Array = []
	var controller: RefCounted = MovementController.create(provider)
	controller.call("set_position", Layout.START_POSITION)

	if int(controller.call("request_move", Layout.UNREACHABLE_INSIDE_ROOM)) != MovementController.MoveResult.UNREACHABLE:
		failures.append("the sealed closet should be refused as UNREACHABLE")
	if String(controller.call("get_state_name")) != "idle":
		failures.append("a refused tap must leave the character idle, not walking")

	var pad: Vector3 = Layout.TAP_PADS[0]
	if int(controller.call("request_move", pad)) != MovementController.MoveResult.ACCEPTED:
		failures.append("a tap pad should be accepted")

	# Walk it for real, along the real path.
	var position: Vector3 = Layout.START_POSITION
	var yaw: float = 0.0
	var arrived: int = 0
	var dt: float = 1.0 / 60.0
	for _frame: int in range(1800):
		var step: Dictionary = controller.call("advance", position, yaw, dt)
		position += (step["velocity"] as Vector3) * dt
		yaw = float(step["yaw"])
		arrived += 1 if bool(step["arrived"]) else 0
		if String(step["stateName"]) == "idle":
			break

	if arrived != 1:
		failures.append("walking a real path should arrive exactly once, got %d" % arrived)
	if not NavMath.is_within(position, pad, MovementController.ARRIVAL_RADIUS):
		failures.append("expected to reach the tap pad, stopped at %s" % str(position))
	return failures


## A provider with no map at all -- a room whose navigation has not been built,
## or a map that has not synchronised yet -- must still let the child move.
## Refusing to walk is a worse failure than walking through a wall.
func _test_unready_provider_degrades_to_a_straight_line() -> Array:
	var failures: Array = []
	var orphan: RefCounted = NavMapProvider.create(null)
	if bool(orphan.call("is_navigation_ready")):
		failures.append("a provider with no map should not claim to be ready")

	var path: PackedVector3Array = orphan.call("query_path", Vector3.ZERO, Vector3(3.0, 0.0, 0.0))
	if path.size() != 2 or not path[1].is_equal_approx(Vector3(3.0, 0.0, 0.0)):
		failures.append("an unready provider should fall back to a straight line, got %s" % str(path))
	if not orphan.call("snap_to_navigable", Vector3(9.0, 0.0, 9.0)).is_equal_approx(Vector3(9.0, 0.0, 9.0)):
		failures.append("an unready provider should treat everywhere as standable")
	if bool(orphan.call("force_sync")):
		failures.append("force_sync() on a provider with no map should report failure, not hang")

	var controller: RefCounted = MovementController.create(orphan)
	if int(controller.call("request_move", Vector3(3.0, 0.0, 0.0))) != MovementController.MoveResult.ACCEPTED:
		failures.append("with no navigation built, a tap should still be accepted so the child "
				+ "can move")
	return failures


## -- Fixture -------------------------------------------------------------------

func _build_spike_map() -> RefCounted:
	var obstacles: Array = []
	obstacles.assign(Layout.OBSTACLES)
	var mesh: NavigationMesh = GridNavMesh.build(
		Layout.FLOOR_BOUNDS, Layout.CELL_SIZE, obstacles, Layout.FLOOR_Y, Layout.AGENT_RADIUS
	)

	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(_map, mesh.cell_size)
	# Small enough that the closet walls (0.5 m thick once inflated) can never be
	# bridged by an edge connection, which would silently make the sealed closet
	# reachable and quietly weaken the unreachable test.
	NavigationServer3D.map_set_edge_connection_margin(_map, 0.05)
	NavigationServer3D.map_set_active(_map, true)

	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _map)
	NavigationServer3D.region_set_enabled(_region, true)
	NavigationServer3D.region_set_navigation_mesh(_region, mesh)

	return NavMapProvider.create(_map)


func _teardown() -> void:
	if _region.is_valid():
		NavigationServer3D.free_rid(_region)
		_region = RID()
	if _map.is_valid():
		NavigationServer3D.free_rid(_map)
		_map = RID()
