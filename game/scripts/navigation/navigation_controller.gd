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
## * **No joystick, no camera control, no precision.** One tap, one destination.
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
## ## Lazy wiring
##
## `_ensure_wired()` runs from every public method rather than only `_ready()`,
## because the headless `--script` runner never fires `_ready()`.

const NavMath := preload("res://scripts/navigation/nav_math.gd")
const ActivityTargetScript := preload("res://scripts/navigation/activity_target.gd")

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
## physics picking. A stray tap behind a summary screen must not move anybody.
@export var taps_enabled: bool = true

## Emitted whenever a tap produced no usable destination, so a room can give
## gentle feedback if it wants to. Reasons: "aboveHorizon", "disabled".
## Never shown as a failure to the child -- there is no red X in this game.
signal tap_ignored(reason: String)

signal target_tapped(target_id: String)
signal floor_tapped(x: float, z: float)

var _wired: bool = false
var _character: Node = null
var _camera: Camera3D = null


func _ready() -> void:
	_ensure_wired()
	set_process_unhandled_input(true)


func _ensure_wired() -> void:
	if _wired:
		return
	_wired = true
	if not character_path.is_empty():
		_character = get_node_or_null(character_path)
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as Camera3D


## Binds the character this controller drives and hands it every `ActivityTarget`
## found beneath `search_root` (defaulting to this controller's owner/parent, so
## a whole room registers in one call). Returns how many targets were registered.
func bind_character(character: Node, search_root: Node = null) -> int:
	_ensure_wired()
	_character = character
	var root: Node = search_root
	if root == null:
		root = get_parent() if get_parent() != null else self
	return register_targets_under(root)


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
	handle_tap(screen_position as Vector2)


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
			floor_tapped.emit(x, z)
			return bool(_character.call("move_to_ground", x, z))
		_:
			tap_ignored.emit(String(tap.get("reason", "")))
			return false


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
