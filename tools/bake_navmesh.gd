extends SceneTree

## Bakes one committed navigation mesh per house room, from COLLISION geometry.
##
## Usage (from the repository root):
##
##     /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##         --script res://../tools/bake_navmesh.gd
##
## Writes `res://scenes/house/navmesh/<roomId>_navmesh.tres`, one per room, and
## prints a report you are expected to read: polygon counts, mesh bounds, and a
## live reachability probe per room.
##
## ## Why this is a script and not "open the editor and click Bake"
##
## A bake you can re-run from a command line is a bake you can diff, review and
## repeat on another machine. `.tres` (text) rather than `.res` (binary) for the
## same reason: the committed navigation mesh is reviewable in a pull request.
##
## ## What was actually verified on Godot 4.7.2
##
## `NavigationServer3D.parse_source_geometry_data()` + `bake_from_source_geometry_data()`
## DO work headlessly, with two conditions that cost an hour to find:
##
##   1. the root node must be **inside the SceneTree**, and the tree must be
##      running -- calling this from `_initialize()` fails with
##      "The root node needs to be inside the SceneTree" and silently produces an
##      empty mesh, so the bake runs from `_process()` on a later frame;
##   2. `agent_radius` must be an exact multiple of `cell_size`, or Godot ceils it
##      to whole voxels and warns that it lost precision.
##
## Geometry is parsed with the ROOM as the parse root, so Godot's parser converts
## everything into room-local space and the same mesh is produced whether the room
## sits at x = 0 or x = 30. The `NavigationRegion3D` then carries the room's world
## position. The bake asserts this: all four rooms are the same 4 x 4 m shell and
## must bake to the same bounds.
##
## ## Rebake when
##
##   * a room's floor, walls, doors or furniture change size or position
##     (anything in `house_layout.gd`);
##   * the agent radius/height, cell size or slope limits change;
##   * the Godot version changes (Recast output is not guaranteed stable).
##
## ## Conventions
##
##   * **Collision is authoritative.** Only `StaticBody3D` collision shapes on
##     `HouseLayout.HOUSE_GEOMETRY_LAYER` are parsed. Visual meshes are ignored, so
##     the wall the child collides with and the wall the mesh knows about cannot
##     drift. `Area3D` activity targets are not colliders and never carve the mesh.
##   * **Obstacles are solid boxes.** Anything a child must walk round gets a
##     collider; anything decorative does not.
##   * **Doors are closed slabs.** A door blocks the navigation mesh; the child
##     leaves through the room transition, never by walking through the doorway.
##   * **Floor-level polygons only.** Recast happily bakes the flat top of a
##     wardrobe as a walkable island. Those islands are stripped after baking
##     (`_keep_floor_polygons`), so the committed mesh is exactly the floor a
##     toddler can stand on and is small enough to read in a diff.

const HouseLayout := preload("res://scripts/house/house_layout.gd")
const RoomScript := preload("res://scripts/house/room.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")

## How far above/below the floor a polygon may sit and still count as floor.
const FLOOR_BAND: float = 0.25

var _frames: int = 0
var _failures: int = 0


func _process(_delta: float) -> bool:
	# The navigation parser refuses to run before the tree is up, so let a couple
	# of frames pass first. See the class docs.
	_frames += 1
	if _frames < 2:
		return false
	_bake_all()
	return true


func _bake_all() -> void:
	print("Baking house navigation meshes (Godot %s)" % Engine.get_version_info()["string"])
	var directory: String = HouseLayout.NAVMESH_DIR
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)

	var bounds_by_room: Dictionary = {}
	for room_id: String in HouseLayout.room_ids():
		bounds_by_room[room_id] = _bake_room(room_id)

	_check_rooms_agree(bounds_by_room)

	print("")
	if _failures == 0:
		print("OK - %d room(s) baked into %s" % [HouseLayout.room_ids().size(), directory])
		quit(0)
	else:
		print("FAILED - %d problem(s)" % _failures)
		quit(1)


func _bake_room(room_id: String) -> AABB:
	var room := Node3D.new()
	room.name = room_id
	room.set_script(RoomScript)
	room.set("room_id", room_id)
	root.add_child(room)
	room.call("build")

	var navigation_mesh := _new_navigation_mesh()
	var source := NavigationMeshSourceGeometryData3D.new()
	# The ROOM is the parse root, so the geometry arrives in room-local space.
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, source, room)
	if not source.has_data():
		_fail("%s: no source geometry was parsed; the room built no colliders" % room_id)
		room.queue_free()
		return AABB()

	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	var baked_polygons: int = navigation_mesh.get_polygon_count()
	var floor_mesh := _keep_floor_polygons(navigation_mesh)
	var kept: int = floor_mesh.get_polygon_count()

	var path: String = HouseLayout.navmesh_path(room_id)
	var error: int = ResourceSaver.save(floor_mesh, path)
	if error != OK:
		_fail("%s: could not save %s (error %d)" % [room_id, path, error])

	var bounds: AABB = _mesh_bounds(floor_mesh)
	print("")
	print("  %s" % room_id)
	print("    source faces        : %d" % (source.get_indices().size() / 3))
	print("    polygons baked      : %d  (kept at floor level: %d)" % [baked_polygons, kept])
	print("    mesh bounds (local) : pos %s size %s" % [
		_round(bounds.position), _round(bounds.size)
	])
	print("    saved               : %s" % path)

	if kept < 8:
		_fail("%s: only %d floor polygons; the room is not walkable" % [room_id, kept])
	_probe_reachability(room_id, floor_mesh)

	room.queue_free()
	return bounds


## The bake settings, in one place. `agent_radius` is an exact multiple of
## `cell_size` on purpose -- Godot ceils it to whole voxels otherwise and warns.
func _new_navigation_mesh() -> NavigationMesh:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.cell_size = HouseLayout.NAV_CELL_SIZE
	navigation_mesh.cell_height = HouseLayout.NAV_CELL_HEIGHT
	navigation_mesh.agent_radius = HouseLayout.NAV_AGENT_RADIUS
	navigation_mesh.agent_height = HouseLayout.NAV_AGENT_HEIGHT
	navigation_mesh.agent_max_climb = HouseLayout.NAV_AGENT_MAX_CLIMB
	navigation_mesh.agent_max_slope = HouseLayout.NAV_AGENT_MAX_SLOPE
	# Collision, not visuals: the wall the child hits and the wall the mesh knows
	# about are then the same object by construction.
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	navigation_mesh.geometry_collision_mask = HouseLayout.HOUSE_GEOMETRY_LAYER
	return navigation_mesh


## Strips every polygon that is not at floor level -- the tops of wardrobes,
## counters and walls, which Recast correctly considers walkable and which a
## toddler correctly cannot reach. Rebuilds the vertex array so the committed
## resource carries nothing it does not use.
func _keep_floor_polygons(source_mesh: NavigationMesh) -> NavigationMesh:
	var vertices: PackedVector3Array = source_mesh.get_vertices()
	var result := NavigationMesh.new()
	result.cell_size = source_mesh.cell_size
	result.cell_height = source_mesh.cell_height
	result.agent_radius = source_mesh.agent_radius
	result.agent_height = source_mesh.agent_height
	result.agent_max_climb = source_mesh.agent_max_climb
	result.agent_max_slope = source_mesh.agent_max_slope

	var kept_vertices := PackedVector3Array()
	var remap: Dictionary = {}
	var polygons: Array = []

	for index: int in range(source_mesh.get_polygon_count()):
		var polygon: PackedInt32Array = source_mesh.get_polygon(index)
		var at_floor: bool = true
		for vertex_index: int in polygon:
			if absf(vertices[vertex_index].y - HouseLayout.FLOOR_Y) > FLOOR_BAND:
				at_floor = false
				break
		if not at_floor:
			continue
		var rebuilt := PackedInt32Array()
		for vertex_index: int in polygon:
			if not remap.has(vertex_index):
				remap[vertex_index] = kept_vertices.size()
				kept_vertices.append(vertices[vertex_index])
			rebuilt.append(int(remap[vertex_index]))
		polygons.append(rebuilt)

	result.vertices = kept_vertices
	for polygon: PackedInt32Array in polygons:
		result.add_polygon(polygon)
	return result


## Puts the mesh on a real navigation map and asks it real questions: can the
## child cross the room, and is the inside of the wardrobe correctly unreachable?
##
## Success is decided by whether the map ANSWERS, never by
## `map_get_iteration_id()` -- a non-zero iteration id only means a rebuild was
## scheduled, and treating it as proof once produced a navigation test that passed
## while asserting everything was unreachable.
func _probe_reachability(room_id: String, navigation_mesh: NavigationMesh) -> void:
	var map: RID = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(map, navigation_mesh.cell_size)
	# Must match the mesh, or Godot warns about rasterisation error on the edges.
	NavigationServer3D.map_set_cell_height(map, navigation_mesh.cell_height)
	NavigationServer3D.map_set_edge_connection_margin(map, HouseLayout.NAV_EDGE_CONNECTION_MARGIN)
	NavigationServer3D.map_set_active(map, true)

	var region := NavigationRegion3D.new()
	root.add_child(region)
	region.set_navigation_map(map)
	region.navigation_mesh = navigation_mesh

	var provider: RefCounted = NavMapProviderScript.create(map)
	if not bool(provider.call("force_sync", Vector3.ZERO)):
		_fail("%s: the baked mesh never answered a navigation query" % room_id)
		region.queue_free()
		NavigationServer3D.free_rid(map)
		return

	# Corner to corner, inside the agent-radius margin.
	var from := Vector3(-1.6, HouseLayout.FLOOR_Y, 1.6)
	var to := Vector3(1.6, HouseLayout.FLOOR_Y, 1.6)
	var crossing: PackedVector3Array = provider.call("query_path", from, to)
	if not NavMath.path_reaches(crossing, to, 0.25):
		_fail("%s: the child cannot walk from %s to %s" % [room_id, from, to])

	# Every authored stand position must be somewhere the child can actually get to.
	for entry: Dictionary in HouseLayout.furniture(room_id) + HouseLayout.doors(room_id):
		var stand: Vector3 = entry["stand"]
		var path: PackedVector3Array = provider.call("query_path", from, stand)
		if not NavMath.path_reaches(path, stand, 0.3):
			_fail("%s: the interaction point for '%s' at %s is not reachable"
					% [room_id, String(entry["targetId"]), _round(stand)])

	# And the inside of a solid object must NOT be reachable, or the obstacle is
	# not really cutting the mesh.
	var solid: Vector3 = HouseLayout.furniture(room_id)[0]["position"]
	solid.y = HouseLayout.FLOOR_Y
	var into_solid: PackedVector3Array = provider.call("query_path", from, solid)
	if NavMath.path_reaches(into_solid, solid, 0.05):
		_fail("%s: the child can walk inside '%s'; its collider is not cutting the mesh"
				% [room_id, String(HouseLayout.furniture(room_id)[0]["targetId"])])
	print("    reachability        : crossing ok, %d stand points ok, obstacles solid"
			% (HouseLayout.furniture(room_id).size() + HouseLayout.doors(room_id).size()))

	region.queue_free()
	NavigationServer3D.free_rid(map)


## All four rooms are the same 4 x 4 m shell, so they must bake to the same
## bounds. A mismatch means the parse picked up a world-space transform, which is
## the one way this whole approach could be silently wrong.
func _check_rooms_agree(bounds_by_room: Dictionary) -> void:
	var reference: AABB = AABB()
	var reference_room: String = ""
	for room_id: String in bounds_by_room.keys():
		var bounds: AABB = bounds_by_room[room_id]
		if reference_room.is_empty():
			reference = bounds
			reference_room = room_id
			continue
		if absf(bounds.position.x - reference.position.x) > 0.3 \
				or absf(bounds.position.z - reference.position.z) > 0.3:
			_fail("%s baked at %s but %s baked at %s; the parse is not room-local"
					% [room_id, _round(bounds.position), reference_room, _round(reference.position)])


func _mesh_bounds(navigation_mesh: NavigationMesh) -> AABB:
	var vertices: PackedVector3Array = navigation_mesh.get_vertices()
	if vertices.is_empty():
		return AABB()
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex: Vector3 in vertices:
		bounds = bounds.expand(vertex)
	return bounds


func _round(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]


func _fail(message: String) -> void:
	_failures += 1
	print("    [PROBLEM] %s" % message)
