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
## └── UI                      status text + transition fade + VirtualJoystick
## ```
##
## ## Two ways to drive, both live at once
##
## Tap a place and Little Buddy walks there. Push the thumbstick in the
## bottom-left and he walks that way. Both are wired here, in `_build_joystick()`,
## because this is the layer that owns the camera (which turns a screen direction
## into a world one), the character and the tap router all at once.
##
## The stick was added on a physical-device request for RoV-style control and
## deliberately overrides `LITTLE_BUDDY_GAME_BIBLE.md` §6's "no complicated
## virtual joystick in early versions"; see `scripts/input/virtual_joystick.gd`.
## Tap-to-walk was not removed and is not degraded.
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
const VirtualJoystickScript := preload("res://scripts/input/virtual_joystick.gd")

## Owned by agentCAM. Adopted if it exists, ignored if it does not.
const ROOM_CAMERA_SCRIPT_PATH: String = "res://scripts/camera/room_camera.gd"
## Owned by agentTARGET. `load()`ed rather than `preload()`ed on purpose: a
## `preload` of a file this agent does not own would make the whole house fail to
## PARSE if that file were ever moved, taking every test down with it.
const TARGET_REGISTRY_SCRIPT_PATH: String = "res://scripts/navigation/activity_target_registry.gd"

## The interactive kitchen. Probed with `ResourceLoader.exists` at build time, so
## a stripped build simply has a static kitchen instead of failing to load.
const KITCHEN_STATE_SCRIPT: String = "res://scripts/kitchen/kitchen_state.gd"
const KITCHEN_VIEW_SCRIPT: String = "res://scripts/kitchen/kitchen_view.gd"

## The domain layer, reached DOWN into for the content cross-check. `load()`ed
## rather than `preload()`ed for the same reason as the registry above, and
## because a house that cannot parse would take the whole suite down with it.
const CONTENT_LIBRARY_SCRIPT_PATH: String = "res://scripts/content/content_library.gd"
const CONTENT_VALIDATOR_SCRIPT_PATH: String = "res://scripts/content/content_validator.gd"

## Story Mode's level loop -- the thing that turns four walkable rooms into "A
## Day With Little Buddy". `load()`ed rather than `preload()`ed so a house that
## has no level loop yet (or whose level loop fails to parse) still builds,
## still walks and still renders.
const LEVEL_DIRECTOR_SCRIPT_PATH: String = "res://scripts/gameplay/house_level_director.gd"

## Free Play's loop: no objective, but a word and a reaction for every object the
## child touches. `load()`ed for the same reason as the level director -- a house
## whose Free Play loop is missing is still a walkable house.
const FREE_PLAY_DIRECTOR_SCRIPT_PATH: String = "res://scripts/gameplay/house_freeplay_director.gd"

## First run, once per profile. Same lazy-load rule again: a build with no
## onboarding script starts the session directly.
const ONBOARDING_DIRECTOR_SCRIPT_PATH: String = "res://scripts/onboarding/onboarding_director.gd"

const CAMERA_FOV: float = 55.0
## Only a fallback for callers with no viewport; anything real is fitted to the
## live aspect ratio.
const REFERENCE_ASPECT: float = 4.0 / 3.0

## How this session chooses what to do, using the SAME vocabulary as
## `baby_room.gd::ProgressionMode` so the two worlds cannot drift into two names
## for one idea. `main.gd` sets it before the world enters the tree.
##
##   * `STORY` -- the authored Chapter 3 journey.
##   * `FREE_PLAY` -- the unlocked rooms, no objective, nothing to finish.
enum ProgressionMode { STORY, FREE_PLAY }

## Free Play has no goal, so the status line is an invitation rather than an
## instruction. Kept short: the player cannot read.
const FREE_PLAY_STATUS: String = "Off you go!"

## Emitted whenever the child ends up in a room, however they got there.
signal room_entered(room_id: String, spawn_id: String)
## Short, warm, child-facing text. Never an error.
signal status_changed(message: String)

## Set false to keep a plain `Camera3D` even when `room_camera.gd` exists.
@export var auto_adopt_room_camera: bool = true

## Cross-checks the bundled content's semantic target references against the ids
## this world really has, once, on `_ready()`, in debug builds only. See
## `validate_content()`.
@export var auto_validate_content: bool = true

var _built: bool = false
var _progression_mode: int = ProgressionMode.STORY
## Room ids Free Play may start in. Empty means "every room in the house", which
## is what an unplayed profile (`unlockedRooms: []`) must mean -- a child locked
## out of all four rooms would be a dead end, and the fallback room is always
## re-added below.
var _unlocked_room_ids: Array = []
var _rooms: Array = []
var _rooms_by_id: Dictionary = {}
var _kitchen_state: RefCounted = null
var _kitchen_view: Node3D = null
var _regions: Dictionary = {}
var _registered_target_ids: Array = []
## The RoV-style thumbstick, built into the world's own `UI` layer so it exists
## in Story, in Free Play and during first run alike.
var _joystick: Control = null
var _world_state: RefCounted = null
## Story Mode's level loop, built on the first frame. Null in Free Play and in
## every headless test that never asks for it.
var _director: Node = null
var _director_booted: bool = false
## Free Play's loop. Null in Story.
var _free_play_director: Node = null
## First run. Null once it has been played, and in every headless test.
var _onboarding: Node = null
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
	if auto_validate_content and OS.is_debug_build():
		_report_content_problems()


## Story Mode picks up its level loop on the FIRST FRAME rather than in
## `_ready()`, and that timing is deliberate.
##
## The headless `--script` runner fires no frames at all, so every existing test
## of this world keeps exercising exactly what it exercised before: a bare,
## objective-free, walkable house. A real run reaches frame one a few
## milliseconds later and the day begins. Tests that DO want the level loop ask
## for it by name with `ensure_level_director()`, which is honest about what it
## is building.
##
## Free Play never builds one: it has no objective by definition. It builds its
## OWN loop instead (`house_freeplay_director.gd`), which is where tapping an
## object becomes an English word and a reaction.
##
## First run comes before either of them. When `onboarding_director.gd` decides
## this profile has never been shown the game, the session is deferred until it
## says it has finished -- by success, by timeout, or by the child ignoring the
## whole thing, all three of which end the same way.
func _process(_delta: float) -> void:
	if _director_booted:
		return
	_director_booted = true
	if _begin_onboarding():
		return
	begin_session()


## Starts whichever loop this session is: Free Play's, or Story's.
##
## Public, and called by hand from the tests, for the same reason
## `ensure_level_director()` is: the headless `--script` runner fires no frames,
## so the only way to assert what a real first frame does is to be able to ask
## for it by name.
func begin_session() -> void:
	if is_free_play():
		var free_play: Node = ensure_free_play_director()
		if free_play != null and free_play.has_method("start"):
			free_play.call("start")
		return
	var director: Node = ensure_level_director()
	if director != null and director.has_method("start"):
		director.call("start")


## Builds and starts first run, or returns false when it is not wanted. See
## `onboarding_director.gd::should_run()` -- a build with no save service never
## runs it, which is also what keeps the headless runner booting the plain,
## objective-free house every existing case asserts against.
func _begin_onboarding() -> bool:
	var onboarding: Node = ensure_onboarding_director()
	if onboarding == null:
		return false
	if not bool(onboarding.call("should_run_now")):
		return false
	if not onboarding.is_connected("finished", _on_onboarding_finished):
		onboarding.connect("finished", _on_onboarding_finished, CONNECT_ONE_SHOT)
	if not bool(onboarding.call("start")):
		return false
	return true


func _on_onboarding_finished() -> void:
	begin_session()


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
	_build_joystick()

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
	_build_kitchen()


## The kitchen's interactive layer: a fridge that opens, food that can be taken
## out of it, and a counter things can be put down on.
##
## Mounted here rather than inside `room.gd` because `room.gd` builds STATIC
## geometry -- it is the file that folds the whole room into one `SurfaceTool` --
## and these items appear and disappear as the child plays. Keeping them in a
## sibling node is what lets the room stay a single draw call.
##
## Degrades silently and completely: a house without a kitchen, or a build where
## the scripts are absent, is exactly the house it was before.
func _build_kitchen() -> void:
	if _kitchen_state != null:
		return
	var room: Node = _rooms_by_id.get(HouseLayout.KITCHEN, null)
	if room == null or not ResourceLoader.exists(KITCHEN_STATE_SCRIPT):
		return
	var state_script: Resource = load(KITCHEN_STATE_SCRIPT)
	var view_script: Resource = load(KITCHEN_VIEW_SCRIPT)
	if not (state_script is GDScript) or not (view_script is GDScript):
		return
	_kitchen_state = (state_script as GDScript).new()
	_kitchen_view = (view_script as GDScript).new()
	room.add_child(_kitchen_view)
	_kitchen_view.call("setup", _kitchen_state, room, _character)


## The kitchen's model, so a mission can ask what Aliz is carrying.
func get_kitchen_state() -> RefCounted:
	build_world()
	return _kitchen_state


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

	# House geometry is solid.
	#
	# The body shipped with `collision_mask = 0`, which was harmless while every
	# metre of travel came from a path baked onto the navigation mesh. Direct
	# drive points wherever a thumb points, so the walls have to mean something.
	# The navigation clamp in `CharacterMovementController._clamp_to_navigable()`
	# is the primary guarantee -- it is strictly stronger, because the mesh is
	# inset by the agent radius and cut around the furniture -- and this is the
	# second line of defence behind it.
	_character.collision_mask = HouseLayout.HOUSE_GEOMETRY_LAYER

	# Warm feedback on arrival. Connected AFTER the transition controller and to
	# `arrived` rather than `interaction_ready`, so for a door the "at the door"
	# line lands first and the room change gets the last word.
	if not _character.is_connected("arrived", _on_arrived):
		_character.connect("arrived", _on_arrived)
	# The stick is switched off whenever the character is -- a summary screen, a
	# room transition, a cutscene. `state_changed` fires from `set_disabled()`,
	# so this needs nothing from the directors that call it.
	if not _character.is_connected("state_changed", _on_character_state_changed):
		_character.connect("state_changed", _on_character_state_changed)


## -- The thumbstick --------------------------------------------------------------

## Builds the virtual thumbstick and joins it to the character, the camera and
## the tap router.
##
## It lives in the world's own `UI` `CanvasLayer` rather than in a director's
## HUD, and that placement is the decision: Story, Free Play and first run all
## get exactly the same control, and none of them has to remember to build it.
##
## It is moved to the FRONT of that layer so `house_hud.gd` -- added later, by
## whichever director is running -- draws over it and, more importantly, gets its
## Next and Speak presses first. The stick is also geometrically clear of both
## (`VirtualJoystick.activation_rect()` clamps itself against the screen centre),
## so this is belt and braces rather than the guarantee.
func _build_joystick() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null or _character == null:
		return
	var stick: Control = VirtualJoystickScript.new()
	ui.add_child(stick)
	ui.move_child(stick, 0)
	stick.call("build")
	_joystick = stick

	stick.connect("moved", _on_joystick_moved)
	stick.connect("released", _on_joystick_released)
	stick.connect("grabbed", _on_joystick_grabbed)
	stick.connect("tapped", _on_joystick_tapped)

	if _nav_controller != null and _nav_controller.has_method("set_press_claimant"):
		_nav_controller.call("set_press_claimant", stick)


func get_joystick() -> Control:
	build_world()
	return _joystick


## Re-asserts the stick every physics frame while a thumb is on it.
##
## Polled rather than purely event-driven because a thumb held perfectly still
## past the dead zone emits no further events, and "held still" must keep meaning
## "keep walking". It is also what makes the stick win a tie: a stray tap
## elsewhere on the floor sets a destination, and the very next frame the thumb
## that is still down replaces it.
func _physics_process(_delta: float) -> void:
	if _joystick == null or _character == null or not is_instance_valid(_joystick):
		return
	if not bool(_joystick.call("is_active")):
		return
	var vector: Vector2 = _joystick.call("get_vector")
	_drive_character(vector)


func _on_joystick_moved(x: float, y: float) -> void:
	_drive_character(Vector2(x, y))


func _on_joystick_released() -> void:
	if _character != null and _character.has_method("stop_driving"):
		_character.call("stop_driving")


## The child has changed their mind about how they are driving. Retire the
## tap-to-walk marker so the floor is not still promising a destination that is
## no longer going to be walked to.
func _on_joystick_grabbed() -> void:
	if _nav_controller != null and _nav_controller.has_method("cancel_tap_feedback"):
		_nav_controller.call("cancel_tap_feedback")


## A press inside the stick's zone that never became a stick gesture. Handed
## straight back to tap-to-walk, ripple and all, so the bottom-left of the floor
## is exactly as tappable as the rest of it.
func _on_joystick_tapped(x: float, y: float) -> void:
	if _nav_controller != null and _nav_controller.has_method("handle_tap"):
		_nav_controller.call("handle_tap", Vector2(x, y))


func _drive_character(stick: Vector2) -> void:
	if _character == null or not _character.has_method("drive"):
		return
	var direction: Vector3 = drive_direction(_camera_basis(), stick)
	_character.call("drive", direction.x, direction.z)


## Turns a screen-space stick vector into a world-space direction.
##
## Camera-relative, which is what every MOBA does and what a child expects:
## "up" is away from the camera and "left" is left of the picture, whatever the
## room's own axes happen to be. The camera's pitch is projected out, so a
## downward-looking camera does not shorten the forward vector.
##
## Static and `Basis`-in / `Vector3`-out so the whole conversion is assertable
## without a camera, a viewport or a room.
static func drive_direction(camera_basis: Basis, stick: Vector2) -> Vector3:
	var forward: Vector3 = -camera_basis.z
	forward.y = 0.0
	var right: Vector3 = camera_basis.x
	right.y = 0.0
	if forward.length_squared() < 0.000001 or right.length_squared() < 0.000001:
		# A camera looking straight down or straight up has no usable heading.
		# Fall back to world axes rather than to a direction of zero, which would
		# read to a child as a control that had stopped working.
		forward = Vector3(0.0, 0.0, -1.0)
		right = Vector3(1.0, 0.0, 0.0)
	forward = forward.normalized()
	right = right.normalized()
	# Screen `+y` is DOWN the screen, which is towards the camera.
	var direction: Vector3 = right * stick.x - forward * stick.y
	if direction.length() > 1.0:
		direction = direction.normalized()
	return direction


func _camera_basis() -> Basis:
	if _camera == null or not is_instance_valid(_camera):
		return Basis.IDENTITY
	return SpatialUtil.world_transform(_camera).basis


func _on_character_state_changed(state_name: String) -> void:
	if _joystick == null or not is_instance_valid(_joystick):
		return
	_joystick.call("set_enabled", state_name != "disabled")


## -- Session -------------------------------------------------------------------

## Story or Free Play. Set BEFORE the world enters the tree (`main.gd` configures
## the instantiated scene and only then adds it), because Free Play changes where
## the child starts.
func set_progression_mode(mode: int) -> void:
	_progression_mode = ProgressionMode.FREE_PLAY if mode == ProgressionMode.FREE_PLAY \
			else ProgressionMode.STORY
	if _built:
		# Already running: at least keep the status line honest.
		_announce_current_room()


func get_progression_mode() -> int:
	return _progression_mode


func is_free_play() -> bool:
	return _progression_mode == ProgressionMode.FREE_PLAY


## The rooms this session may start in, as semantic room ids.
##
## An empty list means "all of them". That is deliberate and is the single most
## important line in this section: a fresh profile carries `unlockedRooms: []`,
## and reading that as "no room is unlocked" would lock a child out of the whole
## house on their first Free Play. The fallback room is force-added for the same
## reason -- the resolver must always have somewhere real to land.
func set_unlocked_room_ids(room_ids: Variant) -> void:
	var ids: Array = []
	if typeof(room_ids) == TYPE_ARRAY:
		for entry: Variant in (room_ids as Array):
			var room_id: String = String(entry).strip_edges()
			if not room_id.is_empty() and not ids.has(room_id):
				ids.append(room_id)
	elif typeof(room_ids) == TYPE_PACKED_STRING_ARRAY:
		for entry: String in (room_ids as PackedStringArray):
			var room_id: String = entry.strip_edges()
			if not room_id.is_empty() and not ids.has(room_id):
				ids.append(room_id)
	if not ids.is_empty() and not ids.has(HouseLayout.FALLBACK_ROOM):
		ids.append(HouseLayout.FALLBACK_ROOM)
	_unlocked_room_ids = ids


## Every room this session may start in. Never empty: an unset or empty unlock
## list opens the whole house.
func get_unlocked_room_ids() -> Array:
	build_world()
	var all_ids: Array = get_room_ids()
	var open: Array = []
	for room_id: String in all_ids:
		if _unlocked_room_ids.has(room_id):
			open.append(room_id)
	# ONE fallback, covering both ways the set can come up empty -- an unset list
	# and a list naming only rooms this house does not have. Written as a single
	# branch on purpose: an earlier version tested `_unlocked_room_ids.is_empty()`
	# separately as well, and deleting either branch left the other quietly
	# covering for it, so neither was actually under test.
	if open.is_empty():
		return all_ids
	return open


func is_room_unlocked(room_id: String) -> bool:
	return get_unlocked_room_ids().has(room_id)


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


## Story Mode's level loop, or null when it has not been built (Free Play, or a
## headless test that never asked for one).
func get_level_director() -> Node:
	return _director


## Builds and binds the level loop, without starting a level. Idempotent, and
## duck-typed throughout: a house whose director script is missing or malformed
## degrades to a walkable house with no objective rather than failing to load.
func ensure_level_director() -> Node:
	build_world()
	if _director != null and is_instance_valid(_director):
		return _director
	if not ResourceLoader.exists(LEVEL_DIRECTOR_SCRIPT_PATH):
		return null
	var script: Resource = load(LEVEL_DIRECTOR_SCRIPT_PATH)
	if not (script is GDScript):
		return null
	var director: Object = (script as GDScript).new()
	if not (director is Node) or not director.has_method("bind"):
		if director is Node:
			(director as Node).free()
		return null
	_director = director as Node
	_director.name = "LevelDirector"
	add_child(_director)
	_director.call("bind", self)
	return _director


## Free Play's loop, or null when its script is missing or malformed. Idempotent
## and duck-typed, exactly like `ensure_level_director()`: a house that cannot
## build one degrades to a walkable, silent house rather than failing to load.
func ensure_free_play_director() -> Node:
	if _free_play_director != null and is_instance_valid(_free_play_director):
		return _free_play_director
	_free_play_director = _build_helper(FREE_PLAY_DIRECTOR_SCRIPT_PATH, "FreePlayDirector")
	return _free_play_director


func get_free_play_director() -> Node:
	return _free_play_director


## First run's director, or null when its script is missing. Built (and bound)
## without being STARTED, so a caller can ask `should_run_now()` first.
func ensure_onboarding_director() -> Node:
	if _onboarding != null and is_instance_valid(_onboarding):
		return _onboarding
	_onboarding = _build_helper(ONBOARDING_DIRECTOR_SCRIPT_PATH, "Onboarding")
	return _onboarding


func get_onboarding_director() -> Node:
	return _onboarding


## True while first run is on screen. Nothing is disabled while it is -- the
## child can play straight through it -- so this is information, not a gate.
func is_onboarding_active() -> bool:
	return _onboarding != null and is_instance_valid(_onboarding) \
			and bool(_onboarding.call("is_running"))


## Loads `script_path`, instantiates it, adds it as a child and hands it this
## world. Null for anything that is not a `Node` answering `bind()`.
##
## One function for both loops rather than two near-identical copies, so there
## is a single place where "a missing or broken helper degrades to a plain
## walkable house" is decided, and a single place a test has to break to prove
## it. `ensure_level_director()` above predates it and is left alone: it carries
## its own history in its comments.
func _build_helper(script_path: String, node_name: String) -> Node:
	build_world()
	if not ResourceLoader.exists(script_path):
		return null
	var script: Resource = load(script_path)
	if not (script is GDScript):
		return null
	var built: Object = (script as GDScript).new()
	if not (built is Node) or not built.has_method("bind"):
		if built is Node:
			(built as Node).free()
		return null
	var node: Node = built as Node
	node.name = node_name
	add_child(node)
	node.call("bind", self)
	return node


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

	# A thumb still on the stick must not drive the child straight back through
	# the door they just came out of. The gesture is dropped; lifting and
	# pressing again starts a new one.
	if _joystick != null and is_instance_valid(_joystick):
		_joystick.call("cancel")

	_register_room_targets(room)
	if _world_state != null:
		_world_state.call("set_location", room_id, spawn_id)
	_frame_room(room)
	_play_transition_fade()
	_announce_current_room()
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


## Resolves an arbitrary (possibly rubbish) room/spawn pair against the layout,
## against the rooms this world actually contains, and against this session's
## unlocked set, then enters it. Always ends with the child somewhere real.
##
## Four falls, in order, and every one of them is tested:
##   1. an unknown SPAWN  -> that room's default spawn (`WorldState.resolve`);
##   2. an unknown ROOM   -> the bedroom's default spawn (`WorldState.resolve`);
##   3. a room the layout knows but this scene does not -> the bedroom;
##   4. a room this session has not unlocked -> the first unlocked room.
## There is no fifth case in which nothing happens, because `get_unlocked_room_ids()`
## is never empty while the house has a single room in it.
func enter_saved_location(room_id: String, spawn_id: String) -> bool:
	build_world()
	var resolved: Dictionary = WorldStateScript.resolve(room_id, spawn_id)
	var target_room: String = String(resolved["roomId"])
	var target_spawn: String = String(resolved["spawnId"])
	# ONE guard, deliberately, rather than a scene check and an unlock check that
	# each happen to cover the other: two overlapping fallbacks both survived a
	# mutation that deleted either one of them, which means neither was really
	# being tested.
	if not has_room(target_room) or not is_room_unlocked(target_room):
		target_room = _first_open_room()
		# The spawn came from a room the child is no longer going to, so it means
		# nothing here; the destination's own default does.
		target_spawn = HouseLayout.DEFAULT_SPAWN
	if target_room.is_empty():
		# Not one room in the whole house. Nothing sane is left to do, and silence
		# would look like a frozen game.
		push_warning("HouseWorld has no room to place the child in.")
		return false
	return place_in_room(target_room, target_spawn)


## The room a fallback lands in: the bedroom when it is open, otherwise whichever
## room is. "" only when the house has no rooms at all.
func _first_open_room() -> String:
	var open: Array = get_unlocked_room_ids()
	if open.has(HouseLayout.FALLBACK_ROOM):
		return HouseLayout.FALLBACK_ROOM
	if open.is_empty():
		return ""
	return String(open[0])


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


## Pulls the camera in on one activity target, addressed the only way content is
## allowed to address anything: by semantic id.
##
## The camera deliberately knows nothing about rooms or ids -- `focus_activity()`
## on `room_camera.gd` takes a world position -- so the resolution happens here,
## which is the layer that owns both the scene tree and the id map. An activity
## calls this to move in, and `restore_room_frame()` to let go again.
##
## Returns false, and changes nothing, for an id this house does not have; a
## missed close-up is a worse outcome than no close-up, but it is never a crash
## and never leaves the camera stranded somewhere the child cannot see.
##
## `radius` is the half-width kept on screen around the target. Left at 0 the
## camera uses its own default, which is sized to include the spot the child
## stands on.
func focus_activity(semantic_id: String, radius: float = 0.0) -> bool:
	build_world()
	var target: Node = get_target_by_semantic_id(semantic_id)
	if target == null or not (target is Node3D):
		push_warning("HouseWorld: cannot focus on unknown target '%s'." % semantic_id)
		return false
	_adopt_room_camera()
	if _camera == null or not _camera.has_method("focus_activity"):
		return false
	# `global_position` silently reports the origin outside the tree, which in the
	# headless runner is every node -- `spatial_util.gd` exists for exactly this.
	var focus: Vector3 = SpatialUtil.world_position(target as Node3D)
	if radius > 0.0:
		_camera.call("focus_activity", focus, radius)
	else:
		_camera.call("focus_activity", focus)
	return true


## Back out to the whole-room shot. Safe to call when nothing was focused.
func restore_room_frame() -> void:
	build_world()
	if _camera != null and _camera.has_method("restore_room_frame"):
		_camera.call("restore_room_frame")
		return
	# No room camera: re-fit the room with the fallback path instead, so the shot
	# still returns to the room rather than staying wherever it was left.
	_frame_room(get_current_room())


func is_focused_on_activity() -> bool:
	build_world()
	if _camera != null and _camera.has_method("is_focused_on_activity"):
		return bool(_camera.call("is_focused_on_activity"))
	return false


func get_camera() -> Camera3D:
	build_world()
	_adopt_room_camera()
	return _camera


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


## Story names the room the child just walked into. Free Play has no objective,
## so it says something warm and open instead of announcing a destination the
## child did not choose.
func _announce_current_room() -> void:
	if is_free_play():
		_set_status(FREE_PLAY_STATUS)
		return
	_set_status("You are in the %s!" % HouseLayout.display_name(get_current_room_id()))


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
	status_changed.emit(message)


## Hides (or shows) the world's own status line.
##
## Free Play keeps it: "Off you go!" and "At the sink!" are the only words on
## screen there. A Story level turns it off, because the level already has one
## voice telling the child what to do and two lines of text competing for the top
## of the screen is one more thing than a pre-reader can read. `status_changed`
## still fires, so nothing that listens to it is affected.
func set_status_visible(value: bool) -> void:
	build_world()
	if _status_label != null:
		_status_label.visible = value


func is_status_visible() -> bool:
	build_world()
	return _status_label != null and _status_label.visible


## -- Content cross-check -------------------------------------------------------

## Checks the bundled content's semantic target references against the ids this
## house really has, and returns the problems.
##
## The direction of the dependency is the point. `content_validator.gd` is domain
## code: it must hold no 3D type and must not import `scripts/house/`,
## `scripts/navigation/`, `scripts/character/` or `scripts/camera/`, and
## `test_architecture_guard.gd` fails the build if it ever does. So the world
## reaches DOWN into the validator and hands it plain Strings; the validator never
## reaches up.
##
## `library` is a loaded `ContentLibrary`; null loads one.
func validate_content(library: Variant = null) -> Array:
	build_world()
	var loaded: Variant = library
	if loaded == null:
		var script: Resource = load(CONTENT_LIBRARY_SCRIPT_PATH)
		if not (script is GDScript):
			return ["house: could not load %s" % CONTENT_LIBRARY_SCRIPT_PATH]
		loaded = (script as GDScript).call("create")
	var validator: Resource = load(CONTENT_VALIDATOR_SCRIPT_PATH)
	if not (validator is GDScript):
		return ["house: could not load %s" % CONTENT_VALIDATOR_SCRIPT_PATH]
	return (validator as GDScript).call(
		"validate_semantic_targets", loaded, get_semantic_target_ids()
	)


## Fail loudly, once, on a debug run: a content reference to a target that does
## not exist is otherwise completely silent -- the level loads, the child taps
## and nothing happens.
##
## `push_error` rather than anything child-facing, and debug-only, so a shipped
## build never pays for it and no player ever sees it.
func _report_content_problems() -> void:
	for problem: Variant in validate_content():
		push_error("HouseWorld content check: %s" % String(problem))
