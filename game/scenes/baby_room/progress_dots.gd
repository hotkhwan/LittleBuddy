extends Control

## "How far through are we?" for a child who cannot read: one slot per task in
## the current mission, filled in from the left as tasks are finished, with the
## task being played right now sitting slightly larger on a soft halo.
##
## A finished task is the same gold star that sits on the counter, pops in the
## celebration and heads the session summary -- earning one *is* how you get a
## star, so the row reads as "these are the stars from this round" rather than
## as an abstract row of dots. A task still to come is the outline of that same
## star, so the child can see the shape they are filling in.
##
## Deliberately NOT a score: there is no number, no percentage, no fraction and
## no "you missed one". A skipped task fills in exactly like a completed one --
## the child sees progress, never a mark against them.
##
## Cheap: one shared texture, a handful of `draw_texture_rect` calls, redrawn
## only when the state changes.

## Kept alive for the lifetime of the script, not loaded per draw: `_draw()` only
## records commands and the renderer binds the texture later in the frame, so a
## texture held in nothing but a local would be freed before it was ever drawn
## and the row would come out as solid squares.
const STAR: Texture2D = preload("res://assets/ui/icons/star.svg")

const SLOT_SIZE: float = 40.0
const CURRENT_SIZE: float = 54.0
const SPACING: float = 52.0

## Filled: the same warm gold as the star counter and the celebration.
const DONE_COLOR: Color = Color(1.0, 0.78, 0.24)
const DONE_SHADOW: Color = Color(0.72, 0.5, 0.11, 0.55)
## Still to come: a pale ghost of the same star on the cream bubble.
const TODO_COLOR: Color = Color(0.86, 0.79, 0.67, 0.75)
## The halo behind the task in play, so "you are here" survives on any backdrop.
const CURRENT_HALO: Color = Color(1.0, 1.0, 1.0, 0.85)
const CURRENT_HALO_RIM: Color = Color(0.99, 0.72, 0.32, 0.9)

## Hard cap so a hostile/odd content file can never draw a thousand stars.
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


## Fills in the slot for the task that just ended (completed OR skipped -- they
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
		var side: float = SLOT_SIZE
		var color: Color = TODO_COLOR

		if slot <= _completed:
			color = DONE_COLOR
		elif slot == _current:
			side = CURRENT_SIZE
			color = DONE_COLOR
			# A soft disc under the current star: on a pale nursery wall a gold
			# outline alone is not enough to say "this one".
			var halo: float = side * 0.62
			draw_circle(center, halo, CURRENT_HALO)
			draw_arc(center, halo, 0.0, TAU, 28, CURRENT_HALO_RIM, 3.0, true)

		var box: Rect2 = Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side))
		if slot <= _completed:
			# A one-pixel drop keeps a gold star legible against the cream
			# speech bubble directly above it.
			draw_texture_rect(
				STAR, Rect2(box.position + Vector2(0.0, 2.0), box.size), false, DONE_SHADOW)
		draw_texture_rect(STAR, box, false, color)
