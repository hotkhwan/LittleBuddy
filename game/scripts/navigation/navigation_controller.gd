extends Node3D

## Turns a child's tap into a destination, and nothing else.
##
## Owns the two halves of tap-to-walk that need the engine -- a camera ray and a
## physics query -- and keeps them away from both the movement state machine and
## the mission layer. The decision of *what a tap means* is split out into
## `classify_tap()`, which is pure and tested; only `_cast_for_target()` needs a
## live physics world.
##
## ## Designed for a landscape iPhone held by a four-year-old
##
## * **One tap, one destination.** No camera control, no precision required.
##   (This used to read "no joystick" as well. A second round of physical-device
##   feedback asked for RoV-style analog control and got it --
##   `scripts/input/virtual_joystick.gd`. Tap-to-walk was NOT replaced: both ship,
##   and `set_press_claimant()` below is the entire boundary between them.)
## * **The floor needs no collision geometry.** A tap that hits no activity target
##   is intersected with the horizontal plane `y = floor_height` analytically, so
##   the entire lower part of the screen is walkable surface. There is no thin
##   floor collider to miss and no gap between rug and floorboard to fall down.
## * **Near-misses are forgiven downstream.** A tap that lands just off the
##   navigation mesh walks to the nearest standable point instead of being
##   refused (`CharacterMovementController.SNAP_RADIUS`).
## * **Taps are handled in `_unhandled_input`**, so every UI control and every
##   `DraggableObject` -- both of which call `set_input_as_handled()` -- wins
##   outright. Thumbs resting on buttons at the screen edges, which is exactly how
##   a phone is held in landscape, can never start a walk. This is also what keeps
##   drag-and-drop working unchanged: a press that begins a drag never reaches
##   here at all.
## * **Targets sit on their own collision layer (2)**, so target-tap raycasting
##   cannot interfere with the layer-1 pickups.
##
## ## A tap has to answer back
##
## Routing a tap correctly is not the same as making a child feel in control, and
## the difference showed up the first time a four-year-old's parent played this on
## a phone: *"controlling the character isn't smooth -- you have to tap the bed or
## the wardrobe for him to walk."* The mechanism was fine (16 of 16 synthetic
## floor taps across a live room were classified FLOOR and accepted); what was
## missing was any acknowledgement at all. A tap on bare floor drew nothing, and
## the only evidence it had landed arrived a fraction of a second later, somewhere
## else on the screen, as a small character starting to move.
##
## So a floor tap now marks the floor -- `TapRipple`, in the same mint "go here"
## language `HouseStage` uses for a directed beat -- and ticks, on the frame of
## the press and before anything has moved. It is drawn HERE rather than in a
## director because this is the one place every floor tap passes through, which is
## what makes it work identically in Story mode, in Free Play and in onboarding.
##
## ## Lazy wiring
##
## `_ensure_wired()` runs from every public method rather than only `_ready()`,
## because the headless `--script` runner never fires `_ready()`.

const NavMath := preload("res://scripts/navigation/nav_math.gd")
const ActivityTargetScript := preload("res://scripts/navigation/activity_target.gd")
const TapRippleScript := preload("res://scripts/navigation/tap_ripple.gd")

## Soft click under a floor tap. Named rather than imported: `class_name SfxPlayer`
## is unavailable in the headless `--script` runner, and the autoload itself is
## optional everywhere (see `draggable_object.gd`, which does the same).
const SFX_GENTLE_TAP: String = "gentle_tap"
const SFX_AUTOLOAD_PATH: String = "/root/Sfx"

## What a tap turned out to mean.
enum TapKind { NONE, TARGET, FLOOR }

const RAY_LENGTH: float = 40.0

## Node paths are resolved lazily; both may be left empty and set in code.
@export var character_path: NodePath = NodePath()
@export var camera_path: NodePath = NodePath()

## The plane taps are projected onto when they hit no activity target. Room
## floors are flat, so one number is enough and is far more forgiving than a
## collider.
@export var floor_height: float = 0.0

## Set false while an overlay is up, exactly as `baby_room.gd` switches off
## physics picking. A stray tap behind a summary screen must not move anybody --
## and any marker left on the floor is taken with it, so a summary never opens
## over a mint disc promising a walk that is no longer going to happen.
@export var taps_enabled: bool = true:
	set(value):
		taps_enabled = value
		if not value and _ripple != null:
			_ripple.call("dismiss")

## Draws the acknowledgement for a floor tap. Off only for a deliberate opt-out
## (the Phase 2A navigation spike, which has its own debug drawing).
@export var tap_feedback_enabled: bool = true

## Emitted whenever a tap produced no usable destination, so a room can give
## gentle feedback if it wants to. Reasons: "aboveHorizon", "disabled".
## Never shown as a failure to the child -- there is no red X in this game.
signal tap_ignored(reason: String)

signal target_tapped(target_id: String)
signal floor_tapped(x: float, z: float)

var _wired: bool = false
var _character: Node = null
var _camera: Camera3D = null
var _ripple: Node3D = null
## The last touch press, so its emulated mouse twin is not routed as a second
## tap. `pointing/emulate_mouse_from_touch` is on: one finger on the iPad
## produces an `InputEventScreenTouch` AND an `InputEventMouseButton` at the same
## spot, and before this both reached `handle_tap()` -- two `target_tapped`s per
## tap, the word spoken twice over itself, two ripples. The stick and the
## draggables already latch the pair; this is the router's latch.
var _last_touch_position: Vector2 = Vector2(INF, INF)
var _last_touch_msec: int = -100000
const TOUCH_TWIN_WINDOW_MSEC: int = 120
const TOUCH_TWIN_DISTANCE: float = 3.0
## Optional. Anything answering `claims_press(Vector2) -> bool` that owns part of
## the screen. Today that is the virtual thumbstick; see `set_press_claimant()`.
var _press_claimant: Object = null


func _ready() -> void:
	_ensure_wired()
	set_process_unhandled_input(true)
	set_process(true)


## Nothing but the tap marker's animation clock. Kept as one forwarding call so
## the marker behaves identically in a live scene and in the headless runner,
## which has no frames and steps `advance()` by hand.
func _process(delta: float) -> void:
	if _ripple != null:
		_ripple.call("advance", delta)


func _ensure_wired() -> void:
	if _wired:
		return
	_wired = true
	if not character_path.is_empty():
		_character = get_node_or_null(character_path)
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as Camera3D
	_ensure_ripple()


## Built lazily and kept: two unshaded discs, re-used for every tap for the whole
## session. Never rebuilt, never freed between taps.
func _ensure_ripple() -> void:
	if _ripple != null or not tap_feedback_enabled:
		return
	var node: Node3D = TapRippleScript.new()
	node.name = "TapRipple"
	_ripple = node
	add_child(node)


## The tap marker, for a room that wants to read it (and for the tests).
func get_tap_ripple() -> Node3D:
	_ensure_wired()
	return _ripple


## Hands part of the screen to another input owner.
##
## `claimant` is anything answering `claims_press(screen_position) -> bool`.
## Duck-typed on purpose: this file must keep working with no claimant at all,
## and must not import the input layer.
##
## The virtual thumbstick is the claimant in Chapter 3. Its activation zone is
## bottom-left, and a press inside it belongs to the stick, not to tap-to-walk:
## without this, one thumb would both grab the stick AND set a destination, and
## the two would spend the rest of the gesture fighting over where Little Buddy
## was going. Outside the zone -- which is most of the screen -- nothing about
## tap-to-walk changes.
func set_press_claimant(claimant: Object) -> void:
	_ensure_wired()
	_press_claimant = claimant


## True when `screen_position` belongs to someone else.
func is_press_claimed(screen_position: Vector2) -> bool:
	_ensure_wired()
	if _press_claimant == null or not is_instance_valid(_press_claimant):
		return false
	if not _press_claimant.has_method("claims_press"):
		return false
	return bool(_press_claimant.call("claims_press", screen_position))


## Retires the destination marker without an arrival.
##
## Called when the child switches to the thumbstick mid-walk: the tap they made a
## moment ago is no longer what is happening, and a mint disc still sitting on
## the floor promising a destination nobody is walking to is a lie -- the same
## reason a refused tap releases it in `apply_tap()`.
func cancel_tap_feedback() -> void:
	_ensure_wired()
	if _ripple != null:
		_ripple.call("release")


## Binds the character this controller drives and hands it every `ActivityTarget`
## found beneath `search_root` (defaulting to this controller's owner/parent, so
## a whole room registers in one call). Returns how many targets were registered.
func bind_character(character: Node, search_root: Node = null) -> int:
	_ensure_wired()
	_character = character
	# The destination disc is retired the moment the walk it marks is over. The
	# character is the only thing that knows when that is, and `arrived` fires
	# exactly once per request (see `CharacterMovementController`'s latch), so one
	# guarded connection is the whole of it. Duck-typed and idempotent: a test
	# double with no such signal, or a second `bind_character()`, is a no-op.
	if character != null and character.has_signal("arrived") \
			and not character.is_connected("arrived", _on_character_arrived):
		character.connect("arrived", _on_character_arrived)
	var root: Node = search_root
	if root == null:
		root = get_parent() if get_parent() != null else self
	return register_targets_under(root)


func _on_character_arrived(_target_id: String) -> void:
	if _ripple != null:
		_ripple.call("release")


func set_camera(camera: Camera3D) -> void:
	_ensure_wired()
	_camera = camera


func get_character() -> Node:
	_ensure_wired()
	return _character


## Walks `root` and registers every activity target it finds with the character.
func register_targets_under(root: Node) -> int:
	_ensure_wired()
	if _character == null or root == null:
		return 0
	var count: int = 0
	for node: Node in _collect_targets(root):
		if bool(_character.call("register_activity_target", node)):
			count += 1
	return count


## -- Tap classification (pure; no camera, no physics) -------------------------

## What should happen for a tap that hit `collider` (or null for a miss)?
##
## `ray_origin`/`ray_direction` describe the tap; `floor_y` is the floor plane.
## Returns a camelCase dictionary:
##   `{"kind": TapKind, "targetId": String, "x": float, "z": float, "reason": String}`
##
## Pure on purpose. Everything genuinely difficult about tap routing -- does a
## hit object own a target, does a miss fall on the floor or above the horizon,
## does a disabled target swallow the tap -- is decided here and is covered by
## real assertions, with no camera, no viewport and no physics world.
static func classify_tap(
	collider: Object, ray_origin: Vector3, ray_direction: Vector3, floor_y: float
) -> Dictionary:
	var result: Dictionary = {"kind": TapKind.NONE, "targetId": "", "x": 0.0, "z": 0.0, "reason": ""}

	var target_id: String = target_id_for(collider)
	if not target_id.is_empty():
		result["kind"] = TapKind.TARGET
		result["targetId"] = target_id
		return result

	var hit: Variant = NavMath.ray_to_floor(ray_origin, ray_direction, floor_y)
	if hit == null:
		# Tapped the sky, or a ray parallel to the floor. Harmless: do nothing.
		result["reason"] = "aboveHorizon"
		return result

	result["kind"] = TapKind.FLOOR
	result["x"] = (hit as Vector3).x
	result["z"] = (hit as Vector3).z
	return result


## The activity-target id owned by `node` or by any of its ancestors, or "".
##
## Duck-typed and ancestor-walking so a target can be nested inside a prop scene,
## or be a child of a bigger piece of furniture, without any type coupling. A
## target that is disabled reports "" -- it is not tappable, and, importantly,
## the tap then falls through to the floor underneath it rather than being eaten.
static func target_id_for(node: Object) -> String:
	var current: Object = node
	var guard: int = 0
	while current != null and guard < 32:
		guard += 1
		if current.has_method("get_activity_target_id"):
			var enabled: bool = true
			if current.has_method("is_target_enabled"):
				enabled = bool(current.call("is_target_enabled"))
			if enabled:
				var id: String = String(current.call("get_activity_target_id"))
				if not id.strip_edges().is_empty():
					return id
		if not (current is Node):
			return ""
		current = (current as Node).get_parent()
	return ""


## -- Tap routing --------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not taps_enabled:
		return
	var screen_position: Variant = _press_position(event)
	if screen_position == null:
		return
	if is_emulated_twin(event):
		return
	if is_press_claimed(screen_position as Vector2):
		return
	handle_tap(screen_position as Vector2)


## True for the synthetic mouse press that follows a touch press at the same
## spot. Public so the latch can be asserted without a touchscreen.
func is_emulated_twin(event: InputEvent) -> bool:
	var state: Array = [_last_touch_position, _last_touch_msec]
	var result: bool = check_emulated_twin(event, state)
	_last_touch_position = state[0]
	_last_touch_msec = state[1]
	return result


## The instance-free half of the latch above, shared with any other input
## poller that faces the same iPad quirk (`affordance_layer.gd`'s badge:
## `pointing/emulate_mouse_from_touch` delivers a touch AND a synthetic mouse
## press to whichever `Control` the finger landed on, and each poller needs
## its own memory of the last touch to catch its own twin).
##
## `state` is a two-element `[Vector2 position, int msec]` array the CALLER
## owns and this mutates in place -- Arrays are references in GDScript, so a
## `Control` with its own two fields can wrap this in one line (see
## `is_emulated_twin()` above) without a shared singleton or a second node.
static func check_emulated_twin(event: InputEvent, state: Array) -> bool:
	if state.size() < 2:
		state.resize(2)
		state[0] = Vector2(INF, INF)
		state[1] = -100000
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			state[0] = touch.position
			state[1] = Time.get_ticks_msec()
		return false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if Time.get_ticks_msec() - int(state[1]) <= TOUCH_TWIN_WINDOW_MSEC \
				and mouse.position.distance_to(state[0] as Vector2) <= TOUCH_TWIN_DISTANCE:
			return true
	return false


## Public so a room can feed it a tap from its own input handling (the Baby Room
## already has a raycast fallback of its own) and so it can be exercised directly.
func handle_tap(screen_position: Vector2) -> Dictionary:
	_ensure_wired()
	if not taps_enabled or _character == null or _camera == null:
		tap_ignored.emit("disabled")
		return {"kind": TapKind.NONE, "targetId": "", "x": 0.0, "z": 0.0, "reason": "disabled"}

	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var collider: Object = _cast_for_target(origin, direction)
	var tap: Dictionary = classify_tap(collider, origin, direction, floor_height)
	apply_tap(tap)
	return tap


## Applies a classified tap to the bound character. Split from `handle_tap()` so
## the routing can be tested without a camera or a physics world.
func apply_tap(tap: Dictionary) -> bool:
	_ensure_wired()
	if _character == null:
		return false
	match int(tap.get("kind", TapKind.NONE)):
		TapKind.TARGET:
			var target_id: String = String(tap.get("targetId", ""))
			target_tapped.emit(target_id)
			return bool(_character.call("move_to", target_id))
		TapKind.FLOOR:
			var x: float = float(tap.get("x", 0.0))
			var z: float = float(tap.get("z", 0.0))
			# FIRST, before anything is asked of anybody: the child pressed the
			# floor and the floor answers. A walk that is refused a line later
			# still gets its acknowledgement -- what must never happen is a press
			# that the screen ignores.
			acknowledge_floor_tap(x, z)
			floor_tapped.emit(x, z)
			var accepted: bool = bool(_character.call("move_to_ground", x, z))
			if not accepted and _ripple != null:
				# Nobody is going anywhere, so the destination disc fades straight
				# back out. Gently, and with no failure language: there is no red X
				# in this game, and a child who taps a wall has done nothing wrong.
				_ripple.call("release")
			return accepted
		_:
			tap_ignored.emit(String(tap.get("reason", "")))
			return false


## Marks the floor at `(x, z)` and ticks. Public so a room with its own input
## handling can acknowledge a tap it routed itself, and so a test can assert the
## feedback without a camera or a physics world.
func acknowledge_floor_tap(x: float, z: float) -> void:
	_ensure_wired()
	if _ripple == null:
		return
	_ripple.call("show_at", x, z, floor_height)
	_play_tap_sound()


## Optional everywhere. The `Sfx` autoload is absent in a scene preview and is
## detached for the duration of the headless test run, so this must degrade to
## silence rather than to an error.
func _play_tap_sound() -> void:
	if not is_inside_tree():
		return
	var sfx: Node = get_node_or_null(NodePath(SFX_AUTOLOAD_PATH))
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", SFX_GENTLE_TAP)


## The only part of this file that needs a live physics world. Queries the
## activity-target layer ONLY, so it can never steal a hit from a layer-1
## draggable pickup.
func _cast_for_target(origin: Vector3, direction: Vector3) -> Object:
	var world: World3D = get_world_3d()
	if world == null:
		return null
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return null
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, origin + direction * RAY_LENGTH
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = ActivityTargetScript.ACTIVITY_TARGET_LAYER
	var hit: Dictionary = space.intersect_ray(query)
	return hit.get("collider", null)


func _collect_targets(root: Node) -> Array:
	var found: Array = []
	if root.has_method("get_activity_target_id") and root.has_method("describe"):
		found.append(root)
	for child: Node in root.get_children():
		found.append_array(_collect_targets(child))
	return found


func _press_position(event: InputEvent) -> Variant:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			return mouse.position
		return null
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			return touch.position
		return null
	return null
