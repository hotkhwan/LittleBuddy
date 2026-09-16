class_name DraggableObject
extends Area3D

## Shared touch/drag mechanics for child-facing 3D pickup objects
## (`MilkBottle`, `Teddy`). Movement is a direct Area3D transform update --
## no `RigidBody3D`, no physics simulation.
##
## Two independent, always-available paths reach every pickup, matching the
## existing Baby Room input pattern:
##   1. `Area3D.input_event` (built-in 3D physics picking) starts a
##      press/drag/tap for whichever pointer touched the shape first.
##   2. `_input()` tracks that SAME pointer's motion/release for the rest of
##      the gesture, so a fast drag that moves off the original screen
##      position still gets updates (physics picking alone would stop firing
##      the moment the pointer leaves the shape's on-screen footprint).
##
## Single-award / no-duplicate guarantees (see also FeedActivity's own state
## guard, which is the authoritative backstop for the milk star):
##   - Only ONE pointer (mouse, or a single touch `index`) can ever drive an
##     interaction at a time. Its index is latched in `_active_pointer_index`
##     the moment a press lands on this object; every other pointer's press
##     is ignored until the latch is released on that pointer's own release.
##     This is what stops a second finger landing mid-drag from starting a
##     second, concurrent drag or a duplicate delivery.
##   - A delivery is latched per-gesture in `_delivered_this_drag`, checked
##     before `_on_dropped_in_zone()` / `_on_tapped()` ever run, so re-entering
##     the drop zone after already delivering (or mashing tap+drag together)
##     cannot fire twice within the same press-to-release gesture.
##   - `set_enabled(false)` immediately drops the latch and (if a gesture was
##     mid-flight and had not yet delivered) animates back home, so a scene
##     transition mid-drag never strands the object or leaves a stale pointer
##     latch blocking future input.
##
## A plain tap (press+release with negligible on-screen movement) always
## still calls `_on_tapped()` -- the guaranteed, non-negotiable accessibility
## fallback for a child who cannot drag.

signal pickup_started
signal returned_to_origin

## No touch/mouse pointer currently owns this object's gesture.
const NO_POINTER: int = -1000000
## Godot doesn't give the mouse pointer an "index" the way touches have one;
## use a fixed sentinel so both codepaths can share the same latch field.
const MOUSE_POINTER_INDEX: int = -1

const TAP_MOVE_THRESHOLD_PX: float = 24.0
const RETURN_DURATION_SEC: float = 0.35
const PICKUP_FEEDBACK_DURATION_SEC: float = 0.18
const PICKUP_SCALE: float = 1.12
const PICKUP_TILT_DEG: float = 8.0

## How enthusiastically the object needs to enter the drop zone during a
## drag before delivery fires. Set by `set_drop_zone()`.
var drag_enabled: bool = true

var _camera: Camera3D = null
var _drop_zone: Area3D = null
var _drop_zone_radius: float = 0.22

## The transform this object always belongs to at rest. Captured once in
## `_ready()` (or explicitly via `reset_position()`), and NEVER overwritten
## by a drag gesture -- otherwise grabbing the object mid-return-flight would
## adopt its current in-flight position as the new "home".
var _home_transform: Transform3D = Transform3D.IDENTITY

var _active_pointer_index: int = NO_POINTER
var _is_dragging: bool = false
var _delivered_this_drag: bool = false
var _press_screen_position: Vector2 = Vector2.ZERO
var _drag_plane: Plane = Plane()
var _grab_offset: Vector3 = Vector3.ZERO
var _active_tween: Tween = null


func _ready() -> void:
	input_ray_pickable = true
	collision_layer = 1
	collision_mask = 0
	_home_transform = transform
	input_event.connect(_on_input_event)
	set_process_input(true)


## -- Public API (contract) -------------------------------------------------

func set_enabled(value: bool) -> void:
	drag_enabled = value
	input_ray_pickable = value
	if not value and _active_pointer_index != NO_POINTER and not _delivered_this_drag:
		# The activity moved on while a finger was still down -- release the
		# latch and animate home rather than stranding the object mid-air.
		_active_pointer_index = NO_POINTER
		_is_dragging = false
		animate_return_to_origin()


## Instantly snaps back to the resting transform and clears any in-flight
## gesture state. Used for hard resets (e.g. a fresh activity cycle), not for
## the gentle release-outside-the-zone case -- see `animate_return_to_origin()`.
func reset_position() -> void:
	_kill_active_tween()
	_active_pointer_index = NO_POINTER
	_is_dragging = false
	_delivered_this_drag = false
	transform = _home_transform


## Public wrapper so callers (e.g. baby_room.gd, once a delivered Teddy's
## reaction finishes) can send the object smoothly back home without
## reaching into private drag state.
func animate_return_to_origin() -> void:
	_kill_active_tween()
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "transform", _home_transform, RETURN_DURATION_SEC)
	_active_tween.finished.connect(_on_return_tween_finished, CONNECT_ONE_SHOT)


## Registers the drop target (e.g. `MouthDropZone`/`HugDropZone`) this object
## delivers into. `zone` should be positioned by the caller (baby_room.gd)
## from `BabyView3D.get_mouth_position()`/`get_hug_position()` every frame.
func set_drop_zone(zone: Area3D, radius: float = 0.22) -> void:
	_drop_zone = zone
	_drop_zone_radius = radius


## True while a pointer (mouse or touch) currently owns this object's
## press/drag/tap gesture. Lets subclasses avoid double-handling the raycast
## fallback while the primary input path is already driving an interaction.
func is_interaction_active() -> bool:
	return _active_pointer_index != NO_POINTER


## -- Virtual hooks for subclasses -------------------------------------------

## Called exactly once per successful delivery -- either the object entered
## the drop zone during a drag, or it was tapped (the tap fallback treats
## every tap as an immediate, unconditional delivery). Base implementation is
## a no-op; MilkBottle emits `delivered`, Teddy emits `comforted`.
func _on_dropped_in_zone() -> void:
	pass


## -- Input: press (built-in Area3D physics picking) -------------------------

func _on_input_event(camera: Node, event: InputEvent, _click_position: Vector3, _click_normal: Vector3, _shape_idx: int) -> void:
	if not drag_enabled:
		return
	if not _is_press_event(event):
		return
	if _active_pointer_index != NO_POINTER:
		return  # Another pointer already owns this gesture -- ignore.

	if camera is Camera3D:
		_camera = camera as Camera3D

	_begin_interaction(_pointer_index_for(event), _screen_position_of(event))

	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


## -- Input: motion + release (global, so a fast drag off-shape still tracks) -

func _input(event: InputEvent) -> void:
	if _active_pointer_index == NO_POINTER:
		return
	if _pointer_index_for(event) != _active_pointer_index:
		return  # A stray/unrelated pointer -- fully ignored while we own the gesture.

	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		_update_drag(_screen_position_of(event))
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if _is_release_event(event):
		_end_interaction(_screen_position_of(event))
		var viewport2: Viewport = get_viewport()
		if viewport2 != null:
			viewport2.set_input_as_handled()


## -- Gesture lifecycle -------------------------------------------------------

func _begin_interaction(pointer_index: int, screen_position: Vector2) -> void:
	_active_pointer_index = pointer_index
	_press_screen_position = screen_position
	_is_dragging = false
	_delivered_this_drag = false
	_kill_active_tween()

	if _camera != null:
		_drag_plane = DragPlane.make_plane(global_position, _camera.global_position)
		var hit: Variant = _project_to_plane(screen_position)
		_grab_offset = (hit as Vector3) - global_position if hit != null else Vector3.ZERO
	else:
		_grab_offset = Vector3.ZERO

	pickup_started.emit()
	_play_pickup_feedback()


func _update_drag(screen_position: Vector2) -> void:
	if not _is_dragging and screen_position.distance_to(_press_screen_position) >= TAP_MOVE_THRESHOLD_PX:
		_is_dragging = true

	var hit: Variant = _project_to_plane(screen_position)
	if hit == null:
		return
	global_position = (hit as Vector3) - _grab_offset
	_check_drop_zone_during_drag()


func _end_interaction(screen_position: Vector2) -> void:
	_active_pointer_index = NO_POINTER

	if _delivered_this_drag:
		return  # Already handled by _check_drop_zone_during_drag().

	var moved_far_enough: bool = screen_position.distance_to(_press_screen_position) >= TAP_MOVE_THRESHOLD_PX
	if not _is_dragging and not moved_far_enough:
		_deliver_via_tap()
		return

	animate_return_to_origin()


func _check_drop_zone_during_drag() -> void:
	if _delivered_this_drag or _drop_zone == null:
		return
	if DragPlane.point_in_drop_zone(global_position, _drop_zone.global_position, _drop_zone_radius):
		_delivered_this_drag = true
		_is_dragging = false
		_kill_active_tween()
		global_position = _drop_zone.global_position
		_on_dropped_in_zone()


func _deliver_via_tap() -> void:
	if _delivered_this_drag:
		return
	_delivered_this_drag = true
	_on_dropped_in_zone()


func _on_return_tween_finished() -> void:
	_active_tween = null
	returned_to_origin.emit()


## -- Cosmetic feedback (Tween-driven; cheap, no particles) -------------------

func _play_pickup_feedback() -> void:
	_kill_active_tween()
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "scale", Vector3.ONE * PICKUP_SCALE, PICKUP_FEEDBACK_DURATION_SEC)
	_active_tween.parallel().tween_property(self, "rotation:z", deg_to_rad(PICKUP_TILT_DEG), PICKUP_FEEDBACK_DURATION_SEC)


func _kill_active_tween() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null


## -- Helpers ------------------------------------------------------------------

func _project_to_plane(screen_position: Vector2) -> Variant:
	if _camera == null:
		return null
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_position)
	return DragPlane.intersect_ray(_drag_plane, ray_origin, ray_direction)


func _pointer_index_for(event: InputEvent) -> int:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).index
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).index
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return MOUSE_POINTER_INDEX
	return NO_POINTER


func _screen_position_of(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).position
	return Vector2.ZERO


func _is_press_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		return mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _is_release_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		return mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	return false
