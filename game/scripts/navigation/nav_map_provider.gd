extends "res://scripts/navigation/navigation_provider.gd"

## The real navigation provider: queries a `NavigationServer3D` map.
##
## Built either from a `NavigationAgent3D` (normal gameplay -- the agent owns the
## map, the agent radius and the path post-processing settings) or from a raw map
## RID (tests, and any caller that has no agent yet). Either way the only engine
## surface the movement controller ever sees is this object's two methods.
##
## ## Headless synchronisation
##
## Navigation maps synchronise on physics frames. The `--script` test runner runs
## none, so a freshly built map answers every query with "nothing here" until it
## has been forced through a sync -- and `map_force_update()` is itself
## asynchronous: the first call schedules the rebuild and a later call observes
## it. `force_sync()` therefore loops until the map actually answers, with a hard
## attempt cap so a genuinely empty map can never hang a test. Measured on Godot
## 4.7.2 this settles on the second `map_force_update()`.
##
## `force_sync()` is a test/bootstrap affordance and is NOT called during normal
## gameplay -- forcing a synchronous navigation rebuild inside a frame is exactly
## the stall the performance budget forbids.

const FORCE_SYNC_MAX_ATTEMPTS: int = 40
const FORCE_SYNC_DELAY_MSEC: int = 5

var _map: RID = RID()
var _agent: NavigationAgent3D = null


## `source` is a `NavigationAgent3D`, an `RID`, or null (which leaves the
## provider unready and every query falling back to a straight line, so a
## half-built scene still walks instead of crashing).
static func create(source: Variant = null) -> RefCounted:
	var provider: RefCounted = (load("res://scripts/navigation/nav_map_provider.gd") as GDScript).new()
	provider.call("bind", source)
	return provider


func bind(source: Variant) -> void:
	_agent = null
	_map = RID()
	if source is NavigationAgent3D:
		_agent = source as NavigationAgent3D
	elif source is RID:
		_map = source as RID


## The map this provider queries. Resolved from the agent every call rather than
## cached, because an agent's map changes when it enters the tree -- caching it at
## construction time is how you get a provider permanently bound to a dead RID.
func get_map() -> RID:
	# `is_inside_tree()` matters: an agent that has not entered the tree has no
	# map yet, and asking for one logs an error. Falling through to the raw map
	# (usually also empty) leaves the provider "not ready", which the movement
	# controller already handles by walking in a straight line.
	if _agent != null and is_instance_valid(_agent) and _agent.is_inside_tree():
		var agent_map: RID = _agent.get_navigation_map()
		if agent_map.is_valid():
			return agent_map
	return _map


func is_navigation_ready() -> bool:
	var map: RID = get_map()
	if not map.is_valid():
		return false
	if not NavigationServer3D.map_is_active(map):
		return false
	# Iteration 0 means "never synchronised": every query against it returns
	# nothing and logs an error. Treating that as "not ready" is what lets the
	# caller fall back to a straight line instead of refusing to move.
	return NavigationServer3D.map_get_iteration_id(map) > 0


func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not is_navigation_ready():
		return super.query_path(from, to)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(get_map(), from, to, true)
	if path.is_empty():
		# The map is live but produced nothing (character standing off-mesh).
		# Straight line beats standing still.
		return super.query_path(from, to)
	return path


func snap_to_navigable(point: Vector3) -> Vector3:
	if not is_navigation_ready():
		return point
	return NavigationServer3D.map_get_closest_point(get_map(), point)


## Forces the map through a real synchronisation. Returns true once the map
## genuinely answers queries. Test/bootstrap only -- see the class docs.
##
## Success is decided by asking the map who owns the polygon nearest
## `probe_point`, NOT by the iteration id. A non-zero iteration id only means a
## rebuild has been scheduled and observed; the map can still return nothing for
## another round, and treating that as "synchronised" is how a navigation test
## ends up asserting that everything is unreachable and passing for entirely the
## wrong reason. `map_get_closest_point_owner()` returns an invalid RID when the
## map has no usable polygons, which is unambiguous.
func force_sync(probe_point: Vector3 = Vector3.ZERO) -> bool:
	var map: RID = get_map()
	if not map.is_valid():
		return false
	NavigationServer3D.set_active(true)
	for _attempt: int in range(FORCE_SYNC_MAX_ATTEMPTS):
		NavigationServer3D.map_force_update(map)
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			if NavigationServer3D.map_get_closest_point_owner(map, probe_point).is_valid():
				return true
		OS.delay_msec(FORCE_SYNC_DELAY_MSEC)
	return false
