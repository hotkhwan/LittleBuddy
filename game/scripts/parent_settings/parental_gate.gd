class_name ParentalGate
extends Control

## Reusable "press and hold" gate.
##
## A child taps; a grown-up holds. The caller gets `unlocked()` only after the
## pointer has been held down continuously on this control for `hold_duration`
## seconds. Releasing (or sliding off) cancels cleanly and resets the progress
## to zero -- it can never get stuck part-way.
##
## All of the timing logic lives in plain methods (`begin_hold`, `advance`,
## `cancel_hold`, `reset`) rather than inside `_process`, so it can be driven
## directly from tests with no SceneTree and no autoloads.
##
## Two visual styles:
##   RING -- a small, deliberately dull gear with a progress ring around it.
##           Used as the unobtrusive entry affordance in a screen corner.
##   BAR  -- a rounded pill that fills left-to-right. Used for
##           hold-to-confirm actions (e.g. erasing progress).

signal unlocked()
signal hold_started()
signal hold_canceled()
signal progress_changed(progress: float)

enum Style { RING, BAR }

const DEFAULT_HOLD_SECONDS := 3.0

@export var hold_duration: float = DEFAULT_HOLD_SECONDS
@export var style: Style = Style.RING
## Idle opacity of the gear in RING style. Deliberately low so the affordance
## reads as "settings", not as part of the game.
@export var idle_alpha: float = 0.38
@export var accent_color: Color = Color(0.42, 0.56, 0.72) # dusty blue
@export var backdrop_color: Color = Color(0.32, 0.31, 0.29, 0.16)
@export var fill_color: Color = Color(0.9, 0.62, 0.62) # soft pink (BAR)

var _holding: bool = false
var _elapsed: float = 0.0
var _has_unlocked: bool = false

var _bar_backdrop := StyleBoxFlat.new()
var _bar_fill := StyleBoxFlat.new()


# -- Pure logic (directly testable) -------------------------------------------

## Starts (or restarts) a hold. No-op while already holding or once unlocked,
## so repeated press events -- e.g. a touch that also synthesises a mouse
## click -- cannot restart or double-count the hold.
func begin_hold() -> void:
	if _has_unlocked or _holding:
		return
	_holding = true
	_elapsed = 0.0
	hold_started.emit()
	progress_changed.emit(0.0)
	_refresh()


## Advances an in-progress hold. Ignored entirely when not holding, so a
## cancelled gate can never creep toward unlocking on its own.
func advance(delta: float) -> void:
	if not _holding or _has_unlocked or delta <= 0.0:
		return
	_elapsed += delta
	progress_changed.emit(get_progress())
	if _elapsed >= hold_duration:
		_holding = false
		_has_unlocked = true
		_refresh()
		unlocked.emit()
		return
	_refresh()


## Cancels an in-progress hold and resets progress to zero. Safe to call at any
## time, including when no hold is running.
func cancel_hold() -> void:
	if not _holding:
		return
	_holding = false
	_elapsed = 0.0
	progress_changed.emit(0.0)
	hold_canceled.emit()
	_refresh()


## Clears the "already unlocked" latch so the gate can be used again.
func reset() -> void:
	_holding = false
	_elapsed = 0.0
	_has_unlocked = false
	progress_changed.emit(0.0)
	_refresh()


## 0.0 .. 1.0
func get_progress() -> float:
	if hold_duration <= 0.0:
		return 1.0
	return clampf(_elapsed / hold_duration, 0.0, 1.0)


func is_holding() -> bool:
	return _holding


func has_unlocked() -> bool:
	return _has_unlocked


# -- Node plumbing ------------------------------------------------------------

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	if not mouse_exited.is_connected(cancel_hold):
		mouse_exited.connect(cancel_hold)
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


func _notification(what: int) -> void:
	# Losing focus / being hidden mid-hold must not leave a half-filled ring.
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_EXIT_TREE:
		cancel_hold()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			begin_hold()
		else:
			cancel_hold()
		accept_event()
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				begin_hold()
			else:
				cancel_hold()
			accept_event()
		return

	# A finger that slides off the control cancels, matching the mouse behaviour.
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not Rect2(Vector2.ZERO, size).has_point(drag.position):
			cancel_hold()


func _refresh() -> void:
	set_process(_holding)
	queue_redraw()


# -- Drawing ------------------------------------------------------------------

func _draw() -> void:
	match style:
		Style.BAR:
			_draw_bar()
		_:
			_draw_ring()


func _draw_ring() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 3.0
	if radius <= 2.0:
		return

	var progress: float = get_progress()
	var alpha: float = lerpf(idle_alpha, 1.0, progress if _holding else 0.0)

	draw_circle(center, radius, backdrop_color)

	var gear: Color = Color(0.36, 0.36, 0.38, alpha)
	var gear_radius: float = radius * 0.40
	# Body: a thick ring with a small hub hole, plus stubby teeth.
	draw_arc(center, gear_radius, 0.0, TAU, 32, gear, maxf(radius * 0.26, 3.0), true)
	for i in 8:
		var angle: float = TAU * float(i) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			center + direction * gear_radius,
			center + direction * (gear_radius + radius * 0.20),
			gear,
			maxf(radius * 0.16, 2.0),
			true
		)

	if progress > 0.0:
		draw_arc(
			center,
			radius - 1.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * progress,
			48,
			accent_color,
			maxf(radius * 0.12, 3.0),
			true
		)


func _draw_bar() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var corner: int = int(minf(size.y * 0.5, 28.0))

	_bar_backdrop.bg_color = Color(0.94, 0.91, 0.87, 1.0)
	_bar_backdrop.set_corner_radius_all(corner)
	_bar_backdrop.border_color = Color(0.82, 0.74, 0.70, 1.0)
	_bar_backdrop.set_border_width_all(2)
	draw_style_box(_bar_backdrop, Rect2(Vector2.ZERO, size))

	var progress: float = get_progress()
	if progress > 0.0:
		_bar_fill.bg_color = fill_color
		_bar_fill.set_corner_radius_all(corner)
		draw_style_box(
			_bar_fill, Rect2(Vector2.ZERO, Vector2(maxf(size.x * progress, 1.0), size.y))
		)
