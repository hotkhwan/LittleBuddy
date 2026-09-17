extends Node3D

## HouseWorld: four greybox rooms, one child, one navigation map, discrete doors.
##
## This is the Chapter 3+ world. It is NOT the Baby Room and it never touches it:
## the approved product decision is that **the baby does not walk**, so Chapter 2
## keeps its tap/drag caregiving gameplay and acquires no navigation at all.
##
## ```
## HouseWorld (this node)
## ├── WorldCamera             Camera3D (+ room_camera.gd when it exists)
## ├── Navigation              one NavigationRegion3D per room, built here
## ├── Rooms                   Bedroom / Bathroom / Kitchen / LivingRoom
## ├── LittleBuddy             CharacterBody3D + little_buddy_character.gd
## ├── NavigationController    tap -> destination
## ├── RoomTransitionController
## └── UI                      status text + transition fade
## ```
##
## **No new autoload singletons.** Everything above is composed here and passed
## in by reference, exactly as `CLAUDE.md` requires.
##
## ## The parts owned by other agents
##
## The room camera (`scripts/camera/**`) and the extended `ActivityTarget`
## contract (`scripts/navigation/**`) belong to other agents and may or may not
## exist yet. Both are consumed **defensively**: every call goes through
## `has_method()`, and when the camera cannot frame a room this file falls back to
## `room_framing.gd` so the world is always navigable, renderable and testable.
## Nothing here depends on a type it does not own.
##
## ## Lazy wiring
##
## `build_world()` is idempotent and is called from every public method, because
## the headless `--script` test runner never fires `_ready()`.

const HouseLayout := preload("res://scripts/house/house_layout.gd")
const RoomFraming := preload("res://scripts/house/room_framing.gd")
const WorldStateScript := preload("res://scripts/house/world_state.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## Owned by agentCAM. Adopted if it exists, ignored if it does not.
const ROOM_CAMERA_SCRIPT_PATH: String = "res://scripts/camera/room_camera.gd"
## Owned by agentTARGET. `load()`ed rather than `preload()`ed on purpose: a
## `preload` of a file this agent does not own would make the whole house fail to
## PARSE if that file were ever moved, taking every test down with it.
const TARGET_REGISTRY_SCRIPT_PATH: String = "res://scripts/navigation/activity_target_registry.gd"

const CAMERA_FOV: float = 55.0
## Only a fallback for callers with no viewport; anything real is fitted to the
## live aspect ratio.
const REFERENCE_ASPECT: float = 4.0 / 3.0

## Emitted whenever the child ends up in a room, however they got there.
signal room_entered(room_id: String, spawn_id: String)
## Short, warm, child-facing text. Never an error.
signal status_changed(message: String)

## Set false to keep a plain `Camera3D` even when `room_camera.gd` exists.
@export var auto_adopt_room_camera: bool = true

var _built: bool = false
var _rooms: Array = []
var _rooms_by_id: Dictionary = {}
var _regions: Dictionary = {}
var _registered_target_ids: Array = []
var _world_state: RefCounted = null
## Optional: agentTARGET's semantic-id lookup. Null when that file is absent, in
## which case `get_target_by_semantic_id()` falls back to asking the rooms.
var _registry: RefCounted = null
## The house owns its navigation map rather than borrowing the world default, so
## it changes no global state and can be freed without trace.
var _owned_map: RID = RID()

@onready var _camera: Camera3D = get_node_or_null("WorldCamera") as Camera3D
@onready var _navigation_root: Node3D = get_node_or_null("Navigation") as Node3D
@onready var _rooms_root: Node3D = get_node_or_null("Rooms") as Node3D
@onready var _character: CharacterBody3D = get_node_or_null("LittleBuddy") as CharacterBody3D
@onready var _nav_controller: Node3D = get_node_or_null("NavigationController") as Node3D
@onready var _transition: Node = get_node_or_null("RoomTransitionController")
@onready var _status_label: Label = get_node_or_null("UI/StatusLabel") as Label
@onready var _fade: ColorRect = get_node_or_null("UI/Fade") as ColorRect


func _ready() -> void:
	build_world()
	var viewport: Viewport = get_viewport()
	if viewport != null:
		# Re-fit on rotation and on any resize, so a room never crops when the
		# device turns. Contract §6.
		viewport.size_changed.connect(_reframe_current_room)


## The house owns its navigation map, so it must give the RID back; a leaked map
## stays on the server for the rest of the session.
##
## On PREDELETE rather than in `_exit_tree()`, for two reasons: a world that is
## removed from the tree and re-added would otherwise come back without a
## navigation map, and in the headless runner `_exit_tree()` never fires at all,
## so every test would leak one.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _owned_map.is_valid():
		NavigationServer3D.free_rid(_owned_map)
		_owned_map = RID()


## -- Construction --------------------------------------------------------------

## Idempotent; safe to call by hand in the headless runner, where `_ready()` never
## fires.
func build_world() -> void:
	if _built:
		return
	_built = true
	_resolve_nodes()

	_collect_rooms()
	_build_target_registry()
	_build_navigation()
	_wire_character()

	_world_state = WorldStateScript.create()
	var start: Dictionary = WorldStateScript.resolve(
		_world_state.call("get_room_id"), _world_state.call("get_spawn_id")
	)
	place_in_room(String(start["roomId"]), String(start["spawnId"]))


## `@onready` does not run in the headless `--script` runner, so every node is
## resolved here as well. Null-tolerant throughout: a partially authored scene
## must degrade, not crash.
func _resolve_nodes() -> void:
	if _camera == null:
		_camera = get_node_or_null("WorldCamera") as Camera3D
	if _navigation_root == null:
		_navigation_root = get_node_or_null("Navigation") as Node3D
	if _rooms_root == null:
		_rooms_root = get_node_or_null("Rooms") as Node3D
	if _character == null:
		_character = get_node_or_null("LittleBuddy") as CharacterBody3D
	if _nav_controller == null:
		_nav_controller = get_node_or_null("NavigationController") as Node3D
	if _transition == null:
		_transition = get_node_or_null("RoomTransitionController")
	if _status_label == null:
		_status_label = get_node_or_null("UI/StatusLabel") as Label
	if _fade == null:
		_fade = get_node_or_null("UI/Fade") as ColorRect


func _collect_rooms() -> void:
	if _rooms_root == null:
		return
	for child: Node in _rooms_root.get_children():
		if not child.has_method("get_room_id"):
			continue
		if child.has_method("build"):
			child.call("build")
		var room_id: String = String(child.call("get_room_id"))
		if room_id.is_empty() or _rooms_by_id.has(room_id):
			push_warning("Duplicate or empty room id '%s'; ignoring the second one." % room_id)
			continue
		_rooms_by_id[room_id] = child
		_rooms.append(child)


## Builds the semantic-id lookup, if that part of the contract has landed.
##
## Entirely optional. The house is navigable without it -- the character keeps its
## own per-room registry (see `_register_room_targets`) -- but with it, content can
## resolve `"kitchen.fridge"` without touching the scene tree, and a duplicate
## semantic id anywhere in the house becomes a loud, reported problem rather than
## a target that silently shadows another.
func _build_target_registry() -> void:
	if not ResourceLoader.exists(TARGET_REGISTRY_SCRIPT_PATH):
		return
	var script: Resource = load(TARGET_REGISTRY_SCRIPT_PATH)
	if not (script is GDScript):
		return
	var registry: Object = (script as GDScript).new()
	if not (registry is RefCounted) or not registry.has_method("register_all"):
		return
	_registry = registry as RefCounted
	_registry.call("register_all", self)


## Duplicate/malformed semantic ids found while registering, or an empty Array.
func get_target_problems() -> Array:
	build_world()
	if _registry == null or not _registry.has_method("get_problems"):
		return []
	return _registry.call("get_problems")


func get_target_registry() -> RefCounted:
	build_world()
	return _registry


## One navigation map for the whole house, one baked region per room.
##
## The rooms are 10 m apart (`HouseLayout.ROOM_SPACING`), so their meshes are
## separate islands on that map and no path can ever run from one room to
## another. That is what makes "walk to the bathroom sink from the bedroom"
## correctly unreachable instead of a walk through a wall.
##
## **Nothing is baked here.** Each region loads a committed `.tres` produced by
## `tools/bake_navmesh.gd`. Runtime baking is a frame-blocking stall and the
## performance budget forbids it.
func _build_navigation() -> void:
	if _navigation_root == null:
		return

	_owned_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(_owned_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(_owned_map, HouseLayout.NAV_CELL_SIZE)
	# Both cell dimensions must match the baked meshes. A map coarser than its
	# meshes warns about rasterisation errors and can merge edges that should stay
	# apart -- and the edges that must never merge here are the room boundaries.
	NavigationServer3D.map_set_cell_height(_owned_map, HouseLayout.NAV_CELL_HEIGHT)
	NavigationServer3D.map_set_edge_connection_margin(
		_owned_map, HouseLayout.NAV_EDGE_CONNECTION_MARGIN
	)
	NavigationServer3D.map_set_active(_owned_map, true)

	for room: Node in _rooms:
		var room_id: String = String(room.call("get_room_id"))
		var region := NavigationRegion3D.new()
		region.name = "%sRegion" % room_id
		# POSITION BEFORE THE TREE, map before mesh. Both orderings are load-bearing:
		#   * a region only pushes its transform to the NavigationServer when it
		#     enters the tree or when its transform changes while inside it, and in
		#     the headless runner a node added to the root is never "inside" -- so a
		#     position set afterwards was silently dropped and all four rooms' meshes
		#     ended up stacked on the origin, which made every room look walkable
		#     from every other;
		#   * assigning a mesh while the region is still on the world default map
		#     rasterises it at that map's coarser cell size and warns about it.
		region.position = HouseLayout.room_origin(room_id)
		_navigation_root.add_child(region)
		region.set_navigation_map(_owned_map)
		# Belt and braces: push the transform to the server by hand, so the region
		# is in the right place whether or not the node ever entered a live tree.
		NavigationServer3D.region_set_transform(
			region.get_rid(), Transform3D(Basis.IDENTITY, HouseLayout.room_origin(room_id))
		)

		var path: String = HouseLayout.navmesh_path(room_id)
		if not ResourceLoader.exists(path):
			# Deliberately not fatal. `NavigationProvider`'s straight-line fallback
			# means an unbaked room still lets the child walk rather than freezing
			# (contract §5) -- but it IS a bake that somebody forgot to run.
			push_warning("No baked navigation mesh for '%s' (%s). Run tools/bake_navmesh.gd."
					% [room_id, path])
			_regions[room_id] = region
			continue
		var mesh: Resource = load(path)
		if mesh is NavigationMesh:
			region.navigation_mesh = mesh as NavigationMesh
		_regions[room_id] = region


func _wire_character() -> void:
	if _character == null:
		return
	if _nav_controller != null:
		if _camera != null:
			_nav_controller.call("set_camera", _camera)
		# Bound with a search root that contains no targets on purpose: only the
		# CURRENT room's targets are ever registered (see `_register_room_targets`),
		# because target ids are unique per room, not globally -- `doorToBathroom`
		# exists in both the bedroom and the living room.
		_nav_controller.call("bind_character", _character, _character)
		_nav_controller.set("floor_height", HouseLayout.FLOOR_Y)

	var agent: NavigationAgent3D = _character.get_node_or_null("NavigationAgent3D")
	if agent != null and _owned_map.is_valid():
		agent.set_navigation_map(_owned_map)

	if _owned_map.is_valid() and _character.has_method("set_navigation_provider"):
		# Bind the movement provider to the map RID rather than leaving it to
		# resolve one from the agent.
		#
		# `NavMapProvider.get_map()` only trusts an agent that is INSIDE THE TREE,
		# and in the headless `--script` runner a node added to the root is not --
		# so the provider silently fell back to an invalid map, reported "not
		# ready", and every query degraded to a straight line. Navigation then
		# "worked" in the tests while ignoring every wall in the house, which is
		# precisely the kind of passing-for-the-wrong-reason the contract warns
		# about. The house owns the map, so the RID is the authoritative source
		# either way.
		_character.call("set_navigation_provider", NavMapProviderScript.create(_owned_map))

	if _transition != null and _transition.has_method("bind"):
		_transition.call("bind", self, _character)

	# Warm feedback on arrival. Connected AFTER the transition controller and to
	# `arrived` rather than `interaction_ready`, so for a door the "at the door"
	# line lands first and the room change gets the last word.
	if not _character.is_connected("arrived", _on_arrived):
		_character.connect("arrived", _on_arrived)


## -- Public API ----------------------------------------------------------------

func get_room_ids() -> Array:
	build_world()
	var ids: Array = _rooms_by_id.keys()
	ids.sort()
	return ids


func has_room(room_id: String) -> bool:
	build_world()
	return _rooms_by_id.has(room_id)


func get_room(room_id: String) -> Node:
	build_world()
	return _rooms_by_id.get(room_id, null)


func get_current_room_id() -> String:
	build_world()
	return String(_world_state.call("get_room_id")) if _world_state != null else ""


func get_current_spawn_id() -> String:
	build_world()
	return String(_world_state.call("get_spawn_id")) if _world_state != null else ""


func get_current_room() -> Node:
	return get_room(get_current_room_id())


func get_character() -> Node:
	build_world()
	return _character


func get_transition_controller() -> Node:
	build_world()
	return _transition


func get_navigation_map() -> RID:
	build_world()
	return _owned_map


func get_world_state() -> RefCounted:
	build_world()
	return _world_state


## Lookup by the semantic id content data uses -- `"kitchen.fridge"` -- without
## anybody outside this file touching the scene tree.
func get_target_by_semantic_id(semantic_id: String) -> Node:
	build_world()
	if _registry != null and _registry.has_method("get_target"):
		var found: Object = _registry.call("get_target", semantic_id)
		if found is Node:
			return found as Node
	var parts: PackedStringArray = semantic_id.split(".", false)
	if parts.size() != 2:
		return null
	var room: Node = get_room(parts[0])
	if room == null or not room.has_method("get_activity_target"):
		return null
	return room.call("get_activity_target", parts[1])


## Every semantic id in the house. Used by the uniqueness tests, and by anything
## that wants to validate content against the world.
func get_semantic_target_ids() -> Array:
	build_world()
	var ids: Array = []
	for room: Node in _rooms:
		var room_id: String = String(room.call("get_room_id"))
		for target: Node in room.call("get_activity_targets"):
			# `get_activity_target_id()` is already the semantic id under the
			# current contract; composing one is the fallback for a duck-typed
			# target that only knows its local half.
			if target.has_method("get_semantic_id"):
				ids.append(String(target.call("get_semantic_id")))
			else:
				ids.append(HouseLayout.semantic_id(
					room_id, String(target.call("get_activity_target_id"))
				))
	return ids


## Puts the child in `room_id` at `spawn_id`.
##
## The one place a room change actually happens -- used by the transition
## controller, by save restore and by the world's own start-up, so there is
## exactly one code path and it cannot diverge. An unknown spawn falls back to the
## room's default; an unknown ROOM is refused here (the caller decides what to do
## about it) rather than silently redirected, because silently moving a child
## somewhere they did not ask to go is worse than not moving them at all.
func place_in_room(room_id: String, spawn_id: String) -> bool:
	build_world()
	var room: Node = get_room(room_id)
	if room == null:
		return false

	for other: Node in _rooms:
		other.call("set_active", other == room)

	var spawn: Vector3 = room.call("get_spawn_position", spawn_id)
	if _character != null:
		SpatialUtil.set_world_position(_character, spawn)
		# Turn into the room, towards its open front. A child arriving through a
		# door should be looking at the room rather than at the door they came
		# through -- and, just as importantly, the camera should see a face rather
		# than the back of a head.
		var room_origin: Vector3 = SpatialUtil.world_transform(room as Node3D).origin
		var face_point: Vector3 = Vector3(
			room_origin.x, spawn.y, room_origin.z + HouseLayout.FLOOR_BOUNDS.end.y
		)
		_character.rotation.y = NavMath.yaw_towards(spawn, face_point, _character.rotation.y)
		if _character.has_method("stop"):
			_character.call("stop")

	_register_room_targets(room)
	if _world_state != null:
		_world_state.call("set_location", room_id, spawn_id)
	_frame_room(room)
	_play_transition_fade()
	_set_status("You are in the %s!" % HouseLayout.display_name(room_id))
	room_entered.emit(room_id, get_current_spawn_id())
	return true


## -- Save / restore ------------------------------------------------------------

## Restores the child's semantic position from a loaded profile. An invalid,
## missing or corrupt room/spawn resolves to the room default and ultimately to
## the bedroom default -- never to a raw coordinate, and never to nowhere.
func restore_from_profile(profile: Variant) -> bool:
	build_world()
	var state: RefCounted = WorldStateScript.read_from_profile(profile)
	return enter_saved_location(
		String(state.call("get_room_id")), String(state.call("get_spawn_id"))
	)


## Resolves an arbitrary (possibly rubbish) room/spawn pair against the layout
## AND against the rooms this world actually contains, then enters it. Always
## ends with the child somewhere real.
func enter_saved_location(room_id: String, spawn_id: String) -> bool:
	build_world()
	var resolved: Dictionary = WorldStateScript.resolve(room_id, spawn_id)
	var target_room: String = String(resolved["roomId"])
	if not has_room(target_room):
		target_room = HouseLayout.FALLBACK_ROOM
	if not has_room(target_room):
		# Not even the bedroom is in this world. Nothing sane is left to do, and
		# silence would look like a frozen game.
		push_warning("HouseWorld contains no '%s'; the child was not placed."
				% HouseLayout.FALLBACK_ROOM)
		return false
	return place_in_room(target_room, String(resolved["spawnId"]))


## Returns a copy of `profile` carrying the current room/spawn.
func write_into_profile(profile: Variant) -> Dictionary:
	build_world()
	if _world_state == null:
		return profile if typeof(profile) == TYPE_DICTIONARY else {}
	return _world_state.call("write_into_profile", profile)


## -- Targets -------------------------------------------------------------------

## Only the current room's targets are registered with the character.
##
## Two reasons. A room the child is not in must not be walkable to, and target
## ids are only required to be unique WITHIN a room -- `doorToBathroom` exists in
## both the bedroom and the living room -- so a single global registry would
## silently shadow one with the other.
func _register_room_targets(room: Node) -> void:
	_unregister_all_targets()
	if _character == null or room == null:
		return
	for target: Node in room.call("get_activity_targets"):
		if bool(_character.call("register_activity_target", target)):
			_registered_target_ids.append(String(target.call("get_activity_target_id")))


func _unregister_all_targets() -> void:
	if _character == null:
		return
	for target_id: String in _character.call("get_activity_target_ids"):
		_character.call("unregister_activity_target", target_id)
	_registered_target_ids.clear()


func get_registered_target_ids() -> Array:
	build_world()
	return _registered_target_ids.duplicate()


## -- Camera --------------------------------------------------------------------

## Frames `room` with whatever camera this world actually has.
##
## Preferred path: the room camera owned by agentCAM, addressed only by
## `frame_room()`. Fallback path: fit the camera here from the room's framing
## metadata. The fallback exists so a missing camera can never produce a black
## screen -- and because a camera-pitch sign error once put every object
## off-screen while all the tests passed, so this is also the thing that renders
## must be checked against.
func _frame_room(room: Node) -> void:
	if room == null:
		return
	_adopt_room_camera()
	if _camera == null:
		return
	var framing: Dictionary = room.call("get_camera_framing")
	if _camera.has_method("frame_room"):
		# The room hands over DATA -- bounds, focus, angle, distances -- and never
		# imports a type from the camera's directory. Contract §6.
		_camera.call("frame_room", framing)
		_camera.current = true
		return

	var distance: float = RoomFraming.fit_distance(framing, _current_aspect(), CAMERA_FOV)
	_camera.fov = CAMERA_FOV
	# Set with `look_at_from_position()` in code, never trusted to a hand-written
	# Transform3D in the .tscn: that is exactly where the inverted-pitch bug lived.
	_camera.look_at_from_position(
		RoomFraming.camera_position(framing, distance),
		framing.get("focus", Vector3.ZERO),
		Vector3.UP
	)
	_camera.current = true


func _reframe_current_room() -> void:
	_frame_room(get_current_room())


## Attaches agentCAM's room camera if it has landed, and only if it really is a
## `Camera3D` script that answers `frame_room()`. Duck-typed on purpose: this file
## must build and run whether or not that agent's work exists.
func _adopt_room_camera() -> void:
	if not auto_adopt_room_camera or _camera == null or _camera.get_script() != null:
		return
	if not ResourceLoader.exists(ROOM_CAMERA_SCRIPT_PATH):
		return
	var script: Resource = load(ROOM_CAMERA_SCRIPT_PATH)
	if not (script is GDScript):
		return
	if (script as GDScript).get_instance_base_type() != "Camera3D":
		return
	_camera.set_script(script)
	if not _camera.has_method("frame_room"):
		# It exists but does not speak the contract's API. Hand the camera back
		# rather than half-using it.
		_camera.set_script(null)


func _current_aspect() -> float:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return REFERENCE_ASPECT
	var size: Vector2 = viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return REFERENCE_ASPECT
	return size.x / size.y


## -- Feedback ------------------------------------------------------------------

## A quick fade-up on the new room, so a room change reads as a beat rather than
## as a jump cut. Purely cosmetic and deliberately NOT part of the transition's
## control flow: control is already back by the time this runs, so a fade that
## never finishes (no tree, no tween) cannot strand a child.
func _play_transition_fade() -> void:
	if _fade == null:
		return
	_fade.modulate.a = 1.0
	if not is_inside_tree():
		_fade.modulate.a = 0.0
		return
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, 0.28)


## Short, warm, and always the DISPLAY name -- a child is never shown the
## camelCase id the code uses. A plain floor tap is simply "Here!".
func _on_arrived(target_id: String) -> void:
	if target_id.strip_edges().is_empty():
		_set_status("Here!")
		return
	var target: Node = get_target_by_semantic_id(target_id)
	var display: String = ""
	if target != null:
		display = String(target.get("display_name")).strip_edges()
	if display.is_empty():
		display = target_id
	_set_status("At the %s!" % display)


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
	status_changed.emit(message)
