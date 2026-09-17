extends Camera3D

## The reusable room camera. A thin applier over `camera_framing.gd`.
##
## Everything hard lives in the pure maths module; this node only reads the live
## aspect ratio and the device insets, asks for a transform, and assigns it. That
## split is the point: framing can be asserted headlessly at four aspect ratios in
## milliseconds, and the only thing that cannot be tested that way is "did we
## remember to call it".
##
## ## For a room author
##
## ```gdscript
## camera.frame_room(room.get_camera_framing())   # fit the room, re-fits on resize
## camera.focus_activity(fridge_position)          # optional close-up
## camera.restore_room_frame()                     # back out again
## ```
##
## `frame_room()` connects itself to `size_changed`, so rotation, iPad
## multitasking and a resized desktop window all re-fit with no further calls.
##
## ## What this node deliberately does NOT do
##
## No orbit, no pinch zoom, no drag-to-look, no `_input()` handler at all. A
## four-year-old cannot operate a camera and should never be asked to. The
## composition -- pitch, yaw, look-at point -- is authored per room and is
## identical on every device; only how far back the camera stands changes.
##
## The transform is always computed and assigned, never read from the `.tscn`. A
## hand-written `Transform3D` with an inverted pitch shipped once and put the
## baby, the bottle and the teddy entirely below the viewport while every test
## passed, which is why `baby_room.gd` and the Phase 2A spike both set their
## camera in code and why this does too.

const Framing := preload("res://scripts/camera/camera_framing.gd")
const Insets := preload("res://scripts/camera/safe_area_insets.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## Emitted after every fit, including the automatic ones on resize. Carries the
## full `solve()` dictionary, so a room can react (or a test can inspect) without
## recomputing anything.
signal framed(solution: Dictionary)

var _room_framing: Dictionary = {}
var _active_framing: Dictionary = {}
var _last_solution: Dictionary = {}
var _focused: bool = false
var _wired: bool = false


func _ready() -> void:
	_ensure_wired()


func _notification(what: int) -> void:
	# Entering the tree is the first moment a viewport can exist. Re-fit then, so
	# a camera framed before it was added to the scene still ends up correct.
	if what == NOTIFICATION_ENTER_TREE:
		_ensure_wired()
		if not _active_framing.is_empty():
			refresh()


## Lazy wiring, because `_ready()` does NOT fire for nodes added to the root in
## the headless `--script` test runner (contract section 10). Every public entry
## point calls this first, so the camera is correctly connected whether the engine
## started it or a test did.
##
## `_wired` latches only on SUCCESS. Wiring while there is no viewport -- a camera
## framed before it was added to the scene, or anything in the headless runner --
## must leave the camera willing to try again, otherwise it would silently spend
## the rest of the session disconnected from `size_changed` and crop the room the
## first time the iPad was rotated. That is a failure no test would see and no
## developer would reproduce on a Mac.
func _ensure_wired() -> void:
	keep_aspect = Camera3D.KEEP_HEIGHT
	if _wired:
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	if not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)
	_wired = true


## True once the camera is actually connected to its viewport's `size_changed`.
func is_wired() -> bool:
	return _wired


## -- Public API ----------------------------------------------------------------

## Frames a room at the CURRENT aspect ratio, and keeps it framed.
##
## `framing` is the plain dictionary described in `camera_framing.gd`: bounds,
## focus, angle, minDistance, maxDistance (everything else optional). A room never
## imports a type from this directory -- it just hands over data.
func frame_room(framing: Dictionary) -> void:
	_ensure_wired()
	_room_framing = Framing.normalise_framing(framing)
	_active_framing = _room_framing
	_focused = false
	refresh()


## Moves in on a single point -- an activity target, a door, the character --
## without changing the shot. Same pitch, same yaw, same clamps; only closer.
##
## Takes a world position rather than a target id because this node knows nothing
## about rooms or targets: the caller resolves `"kitchen.fridge"` to a position
## and passes it. `radius` is the half-width of the box kept on screen around it;
## make it large enough to include the spot the child will be standing on.
func focus_activity(focus: Vector3, radius: float = Framing.DEFAULT_ACTIVITY_RADIUS) -> void:
	_ensure_wired()
	if _room_framing.is_empty():
		# No room framed yet: focus on its own is still better than nothing.
		_room_framing = Framing.normalise_framing({"focus": focus})
	_active_framing = Framing.focus_framing(_room_framing, focus, radius)
	_focused = true
	refresh()


## Back to the whole-room shot.
func restore_room_frame() -> void:
	_ensure_wired()
	if _room_framing.is_empty():
		return
	_active_framing = _room_framing
	_focused = false
	refresh()


## Re-fits at the current aspect. Called automatically on `size_changed`; safe to
## call by hand after anything that changes the viewport.
func refresh() -> void:
	_ensure_wired()
	if _active_framing.is_empty():
		return
	var solution: Dictionary = Framing.solve(
		_active_framing, current_aspect(), current_insets()
	)
	_last_solution = solution
	fov = float(solution["fov"])
	keep_aspect = Camera3D.KEEP_HEIGHT
	_set_world_transform(solution["transform"])
	current = true
	framed.emit(solution)


## -- Read-only accessors (for rooms, transitions and tests) --------------------

func is_focused_on_activity() -> bool:
	return _focused


func get_room_framing() -> Dictionary:
	return _room_framing.duplicate(true)


func get_active_framing() -> Dictionary:
	return _active_framing.duplicate(true)


## The last `solve()` result: distance, required distance, binding axis, whether
## it fitted. Empty until something has been framed.
func get_last_solution() -> Dictionary:
	return _last_solution.duplicate(true)


func current_aspect() -> float:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		return Framing.aspect_from_size(viewport.get_visible_rect().size)
	return Framing.REFERENCE_ASPECT


func current_insets() -> Vector4:
	var chrome: Vector4 = Insets.chrome_insets()
	if _active_framing.has("chromeInsets"):
		var authored: Vector4 = _active_framing["chromeInsets"]
		# Zero means "the room did not author any", not "this room has no HUD".
		if authored != Vector4.ZERO:
			chrome = authored
	return Insets.current_insets(chrome)


## -- Internals -----------------------------------------------------------------

func _on_viewport_resized() -> void:
	refresh()


## `Node3D.look_at_from_position()` requires the node to be inside the tree, and
## `global_transform` silently returns the identity when it is not -- the trap
## `spatial_util.gd` exists for. The transform is already fully computed by the
## pure solver, so assigning it directly works in both cases and keeps a headless
## test honest about where the camera actually ended up.
func _set_world_transform(world: Transform3D) -> void:
	var orthonormal := Transform3D(world.basis.orthonormalized(), world.origin)
	if is_inside_tree():
		global_transform = orthonormal
		return
	var parent: Node = get_parent()
	if parent is Node3D:
		transform = SpatialUtil.world_transform(parent as Node3D).affine_inverse() * orthonormal
	else:
		transform = orthonormal
