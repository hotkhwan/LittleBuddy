extends Control

## "How far through are we?" for a child who cannot read: one soft dot per task
## in the current mission, filled in from the left as tasks are finished, with
## the task being played right now drawn slightly larger and outlined.
##
## Deliberately NOT a score: there is no number, no percentage, no fraction and
## no "you missed one". A skipped task fills in exactly like a completed one --
## the child sees progress, never a mark against them.
##
## Cheap: a handful of `draw_circle` calls, redrawn only when the state changes.

const DOT_RADIUS: float = 11.0
const CURRENT_RADIUS: float = 15.0
const SPACING: float = 34.0
const OUTLINE_WIDTH: float = 3.0

const DONE_COLOR: Color = Color(1.0, 0.78, 0.28)
const DONE_OUTLINE: Color = Color(0.86, 0.58, 0.12)
const CURRENT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)
const CURRENT_OUTLINE: Color = Color(0.99, 0.72, 0.32)
const TODO_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
const TODO_OUTLINE: Color = Color(0.62, 0.57, 0.5, 0.45)

## Hard cap so a hostile/odd content file can never draw a thousand dots.
const MAX_DOTS: int = 12

var _total: int = 0
var _completed: int = 0
var _current: int = 0  ## 1-based index of the task in play; 0 = none.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


## Starts a fresh mission of `total` tasks.
func configure(total: int) -> void:
	_total = clampi(total, 0, MAX_DOTS)
	_completed = 0
	_current = 0
	visible = _total > 0
	queue_redraw()


## `index` is 1-based, as emitted by `MissionRunner.mission_progress`.
func set_current(index: int) -> void:
	_current = clampi(index, 0, _total)
	_completed = maxi(_completed, _current - 1)
	queue_redraw()


## Fills in the dot for the task that just ended (completed OR skipped -- they
## look identical on purpose).
func mark_current_done() -> void:
	_completed = clampi(maxi(_completed, _current), 0, _total)
	queue_redraw()


func clear() -> void:
	configure(0)


func get_total() -> int:
	return _total


func get_completed() -> int:
	return _completed


func _draw() -> void:
	if _total <= 0:
		return

	var span: float = SPACING * float(_total - 1)
	var start_x: float = (size.x - span) * 0.5
	var center_y: float = size.y * 0.5

	for i: int in range(_total):
		var center: Vector2 = Vector2(start_x + SPACING * float(i), center_y)
		var slot: int = i + 1
		var radius: float = DOT_RADIUS
		var fill: Color = TODO_COLOR
		var outline: Color = TODO_OUTLINE

		if slot <= _completed:
			fill = DONE_COLOR
			outline = DONE_OUTLINE
		elif slot == _current:
			radius = CURRENT_RADIUS
			fill = CURRENT_COLOR
			outline = CURRENT_OUTLINE

		draw_circle(center, radius, fill)
		draw_arc(center, radius, 0.0, TAU, 24, outline, OUTLINE_WIDTH, true)
