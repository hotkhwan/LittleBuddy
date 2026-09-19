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
## ## Cuts and moves
##
## Two kinds of change, and they must not look the same:
##
##   * **A cut.** `frame_room()` and a re-fit after a resize are applied
##     instantly. A room change is already covered by the transition fade, and a
##     device that has just been rotated must be correct on the very next frame,
##     not half a second later.
##   * **A move.** `focus_activity()` and `restore_room_frame()` glide, driven by
##     a critically damped spring: zero velocity at the start, no overshoot at
##     the end. This is a calm game for small children and a camera that snaps
##     towards a child's own character reads as a jolt.
##
## The per-frame work lives in `step()` and `_process()` merely forwards to it,
## the same split `house_level_director.gd` uses, so a headless test drives the
## identical code a device does. `settle()` finishes the current move at once for
## a caller that only cares where the shot ends up.
##
## ## What this node deliberately does NOT do
##
## No orbit, no pinch zoom, no drag-to-look, and it handles no raw events at all.
## A four-year-old cannot operate a camera and should never be asked to. The
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

## Roughly how long an eased move takes to arrive. Critically damped, so this is
## a settling time rather than a duration: ~63% of the way in 0.55 s and visually
## finished a little under a second later. Slow enough to read as the camera
## leaning in, quick enough that a child never waits for it.
const EASE_SMOOTH_TIME: float = 0.55

## Within this, the move is over. Small enough to be invisible, large enough that
## the spring's asymptote does not leave the camera creeping for ever.
const SETTLE_DISTANCE: float = 0.002

## A stalled frame (a room loading, a device waking) must not teleport the shot.
const MAX_STEP_SECONDS: float = 0.1

## Emitted after every fit, including the automatic ones on resize. Carries the
## full `solve()` dictionary, so a room can react (or a test can inspect) without
## recomputing anything.
##
## Emitted when the fit is SOLVED, not when an eased move finishes: the solution
## is the answer, and where the camera happens to be part way through a glide is
## presentation.
signal framed(solution: Dictionary)

var _room_framing: Dictionary = {}
var _active_framing: Dictionary = {}
var _last_solution: Dictionary = {}
var _focused: bool = false
var _wired: bool = false

## Where the shot is going, where it currently is, and how fast. `_placed` stays
## false until something has been framed at all, which is what makes the very
## first fit a cut: there is nothing to glide away from.
var _goal: Transform3D = Transform3D.IDENTITY
var _applied: Transform3D = Transform3D.IDENTITY
var _velocity: Vector3 = Vector3.ZERO
var _placed: bool = false
var _moving: bool = false


func _ready() -> void:
	_ensure_wired()


## The eased move, one frame at a time. See `step()`.
func _process(delta: float) -> void:
	step(delta)


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
	# Explicitly, every time, and this is not defensive noise.
	#
	# `HouseWorld` adopts this script by calling `set_script()` on a plain
	# `Camera3D` that is ALREADY in the tree, and a node only decides whether to
	# call `_process()` when it becomes ready. A script attached afterwards
	# therefore never gets a frame: every eased move froze part way, for ever,
	# with `is_moving()` stuck true -- on a device, but not in the headless tests,
	# which step the camera by hand. Found by rendering the game.
	set_process(true)
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
## Applied as a CUT, not a glide: a room change already has the transition fade
## over it, and a re-fit must be right immediately.
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
## make it large enough to include the spot the child will be standing on --
## `camera_focus.gd` is the module that works out what "large enough" is.
##
## EASED. Calling it repeatedly with a slowly moving focus is the intended usage:
## the spring re-aims without restarting, so a close-up can follow a child who
## wanders without ever jerking.
func focus_activity(focus: Vector3, radius: float = Framing.DEFAULT_ACTIVITY_RADIUS) -> void:
	_ensure_wired()
	if _room_framing.is_empty():
		# No room framed yet: focus on its own is still better than nothing.
		_room_framing = Framing.normalise_framing({"focus": focus})
	_active_framing = Framing.focus_framing(_room_framing, focus, radius)
	_focused = true
	refresh(true)


## Back to the whole-room shot. Eased, for the same reason moving in is: letting
## go of an activity should look like the camera relaxing, not like a cut.
func restore_room_frame() -> void:
	_ensure_wired()
	if _room_framing.is_empty():
		return
	_active_framing = _room_framing
	_focused = false
	refresh(true)


## Re-fits at the current aspect. Called automatically on `size_changed`; safe to
## call by hand after anything that changes the viewport.
##
## Applies the result instantly unless `eased` is true, because everything that
## reaches this by itself -- a rotation, a resize, iPad multitasking -- has to be
## correct on the next frame rather than half a second later.
func refresh(eased: bool = false) -> void:
	_ensure_wired()
	if _active_framing.is_empty():
		return
	var solution: Dictionary = Framing.solve(
		_active_framing, current_aspect(), current_insets()
	)
	_last_solution = solution
	fov = float(solution["fov"])
	keep_aspect = Camera3D.KEEP_HEIGHT
	_goal = solution["transform"]
	if eased and _placed:
		_moving = true
	else:
		_settle_now()
	current = true
	framed.emit(solution)


## Advances an eased move. `_process()` does nothing else, so a headless test
## drives exactly the same code a device does; call it by hand there.
func step(delta: float) -> void:
	if not _moving or not is_finite(delta) or delta <= 0.0:
		return
	var elapsed: float = minf(delta, MAX_STEP_SECONDS)
	var origin: Vector3 = _smooth_damp(_applied.origin, _goal.origin, elapsed)
	# The composition is authored per room, so in practice both bases are already
	# identical and this is a no-op. It is here so a room that ever authored a
	# different `yaw` would turn smoothly rather than flipping on arrival.
	var turn: float = clampf(1.0 - exp(-elapsed / maxf(EASE_SMOOTH_TIME * 0.5, 0.0001)), 0.0, 1.0)
	var basis: Basis = _applied.basis.slerp(_goal.basis, turn)
	_applied = Transform3D(basis, origin)
	if origin.distance_to(_goal.origin) <= SETTLE_DISTANCE:
		_settle_now()
		return
	_set_world_transform(_applied)


## Finishes the current move immediately. The shot's DESTINATION is the contract;
## the glide is presentation, and a caller (or an assertion) that only cares
## where the camera ends up says so here rather than pumping frames.
func settle() -> void:
	if _active_framing.is_empty():
		return
	_settle_now()


## True while an eased move is still running.
func is_moving() -> bool:
	return _moving


## -- Read-only accessors (for rooms, transitions and tests) --------------------

func is_focused_on_activity() -> bool:
	return _focused


## The half-width of the close-up currently being held, in metres, or 0.0 while
## the room shot is up.
##
## Exists so a layer that must not obstruct the shot can ask how tight it is
## without knowing anything about beats, tasks or the director.
## `scripts/ui/hud_presentation.gd` is the caller: the difference between a
## 0.90 m shot (one subject filling the middle) and a 1.88 m one (a row of
## objects across the room) is exactly the difference between where its text can
## and cannot go, and this is where that number already lives.
##
## Read from `bounds` rather than cached separately, so it cannot drift away from
## the shot that is actually on screen: `focus_framing()` builds those bounds as
## a square of side `radius * 2`, and `refresh()` fits that same square.
func get_focus_radius() -> float:
	if not _focused or _active_framing.is_empty():
		return 0.0
	var bounds: Variant = _active_framing.get("bounds")
	if not (bounds is Rect2):
		return 0.0
	return maxf((bounds as Rect2).size.x, (bounds as Rect2).size.y) * 0.5


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


func _settle_now() -> void:
	_moving = false
	_velocity = Vector3.ZERO
	_applied = _goal
	_placed = true
	_set_world_transform(_goal)


## Critically damped spring, the standard closed-form approximation.
##
## Chosen over a `Tween` and over a plain `lerp` for one reason each. A tween has
## a fixed duration and would have to be cancelled and restarted every time the
## close-up re-aims at a child who has taken a step, which shows up as a stutter.
## A plain exponential `lerp` starts at full speed, so the first frame of a
## pull-in is its fastest -- exactly the jolt this is meant to avoid. A spring
## starts from rest, accelerates, and arrives without overshooting, and it
## absorbs a moving target without restarting anything.
func _smooth_damp(from: Vector3, to: Vector3, delta: float) -> Vector3:
	var omega: float = 2.0 / EASE_SMOOTH_TIME
	var x: float = omega * delta
	var decay: float = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change: Vector3 = from - to
	var temp: Vector3 = (_velocity + change * omega) * delta
	_velocity = (_velocity - temp * omega) * decay
	return to + (change + temp) * decay


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
