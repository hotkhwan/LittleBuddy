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
## A press that ended well before the hold could complete: a tap. The gate does
## nothing with it itself; a host may use it to SHOW what a hold would do (the
## Baby Room's corner gear opens the gate card, which explains the 3 s hold).
signal tapped()

enum Style { RING, BAR }

const DEFAULT_HOLD_SECONDS := 1.0
## A press released within this long counts as a tap (`tapped`), not as an
## abandoned hold. Well under any hold duration, so it can never race `unlocked`.
const TAP_MAX_SECONDS := 0.45
## How far a finger may wander outside the control before the hold is
## cancelled. Under `emulate_mouse_from_touch` a held finger jitters by a few
## pixels every frame; on an 84 px gear that used to reach `mouse_exited` and
## reset the ring part-way through. The hold now survives a wobble and cancels
## only when the pointer has clearly slid off.
const SLIDE_OFF_MARGIN: float = 40.0

@export var hold_duration: float = DEFAULT_HOLD_SECONDS
@export var style: Style = Style.RING
## Idle opacity of the gear in RING style. Deliberately low so the affordance
## reads as "settings", not as part of the game.
@export var idle_alpha: float = 0.38
@export var accent_color: Color = Color(0.42, 0.56, 0.72) # dusty blue
@export var backdrop_color: Color = Color(0.32, 0.31, 0.29, 0.16)
@export var fill_color: Color = Color(0.9, 0.62, 0.62) # soft pink (BAR)

## BAR style uses the same re-paletted Kenney 9-slices as every other control:
## a cream track with a soft-pink fill sliding across it. The fill is drawn at
## the track's full width into a child that clips to the progress, because
## drawing a nine-patch at a fraction of its width would squash its corners
## instead of revealing them.
const BAR_TRACK: StyleBox = preload("res://assets/ui/styles/small/btn_cream_flat.tres")
const BAR_FILL: StyleBox = preload("res://assets/ui/styles/small/btn_pink.tres")

var _holding: bool = false
var _elapsed: float = 0.0
var _has_unlocked: bool = false

var _fill_clip: Control = null
var _fill_art: Control = null


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


## The pointer came up. A hold that had barely started is reported as a tap
## (after the cancel, so a `tapped` handler sees a clean gate); anything longer
## is an abandoned hold and cancels quietly. Returns true when it was a tap.
## No-op when nothing was being held, so the second release a touch produces
## (the emulated mouse button, then the touch itself) cannot tap twice.
func end_hold() -> bool:
	if not _holding:
		return false
	var was_tap: bool = _elapsed < TAP_MAX_SECONDS
	cancel_hold()
	if was_tap:
		tapped.emit()
	return was_tap


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
	# Deliberately NOT `mouse_exited -> cancel_hold`: with the mouse emulated from
	# touch that signal fires on finger jitter. Sliding off is judged from the
	# pointer position instead, with `SLIDE_OFF_MARGIN` of tolerance (see
	# `_gui_input`).
	if style == Style.BAR:
		_build_bar_fill()
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
			end_hold()
		accept_event()
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				begin_hold()
			else:
				end_hold()
			accept_event()
		return

	# A finger (or the mouse it is emulated as) that clearly slides off the
	# control cancels. A wobble inside the margin does not.
	if _holding and (event is InputEventScreenDrag or event is InputEventMouseMotion):
		var pointer: Vector2 = event.get("position")
		if not _tolerant_rect().has_point(pointer):
			cancel_hold()


## The control's own rect grown by `SLIDE_OFF_MARGIN` on every side, in local
## coordinates (the space `_gui_input` positions arrive in).
func _tolerant_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size).grow(SLIDE_OFF_MARGIN)


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
	draw_style_box(BAR_TRACK, Rect2(Vector2.ZERO, size))
	_update_bar_fill()


## Builds the clipped fill. Only for BAR style, and only from `_ready()`, so a
## RING gate -- and a gate built in a test with no scene tree -- never pays for
## nodes it does not use.
func _build_bar_fill() -> void:
	if _fill_clip != null:
		return
	_fill_clip = Control.new()
	_fill_clip.name = "BarFill"
	_fill_clip.clip_contents = true
	_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill_clip)
	# Behind whatever the scene put inside the gate: the label on the
	# hold-to-erase bar has to stay readable as the fill slides under it.
	move_child(_fill_clip, 0)

	_fill_art = Control.new()
	_fill_art.name = "BarFillArt"
	_fill_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_art.draw.connect(_on_fill_art_draw)
	_fill_clip.add_child(_fill_art)


func _update_bar_fill() -> void:
	if _fill_clip == null:
		return
	var progress: float = get_progress()
	_fill_clip.visible = progress > 0.0
	_fill_clip.position = Vector2.ZERO
	_fill_clip.size = Vector2(size.x * progress, size.y)
	_fill_art.size = size
	_fill_art.queue_redraw()


func _on_fill_art_draw() -> void:
	if _fill_art == null:
		return
	_fill_art.draw_style_box(BAR_FILL, Rect2(Vector2.ZERO, _fill_art.size))
