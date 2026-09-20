extends Control

## A bouncing arrow, a pulsing ring and a ripple: how this game explains itself
## to somebody who cannot read a word of any language.
##
## Every first-run instruction in `onboarding_plan.gd` is ultimately one of two
## pictures -- *press here* or *drag from here to there* -- so this draws exactly
## those two, in the locked palette, and nothing else. It is reused by Free Play's
## idle nudge, which is the same problem with no tutorial around it: a child who
## has stopped touching the screen needs a picture, not a sentence.
##
## ## Why an arrow and not a hand
##
## It shipped as a large cream hand. Photographed cold
## (`docs/shots/alt_focus_buddy_ipad.png`) the hand was a white blob the size
## of the toy box it was pointing at, it covered the very object it meant, and
## nobody could say which way it pointed. The owner's note: unclear and ugly.
##
## A downward arrow bouncing onto a ring is the marker every game a child has
## seen uses for "this one". It is coloured (peach on a mint ring, an ink
## edge), it never covers the target -- it hangs above it and drops -- and its
## direction is unambiguous. `show_ring()` keeps the ring alone for the beat
## that is about Little Buddy's face.
##
## ## Drawn, not composed
##
## `_draw()` primitives only -- circles, arcs, capsules, polygons. No texture,
## no atlas, no `ImageTexture` held in a local. ART_BIBLE section 8 records
## what happened the last time a glyph resource went out of scope between
## `_draw()` recording its commands and the renderer binding them: every sticker
## painted as a solid square. Primitives cannot have that bug.
##
## ## Never in the way
##
## `MOUSE_FILTER_IGNORE`, full-rect, drawn above the world and below nothing that
## matters. A child who taps the arrow taps straight through it to the floor
## underneath, which is the whole point -- the hint is pointing at the thing they
## should touch, so touching the hint must do the right thing.
##
## ## Headless
##
## `step(delta)` is public and `_process()` does nothing but forward to it, so the
## animation clock can be driven by hand in the test runner, which draws no
## frames at all.

const Palette := preload("res://scripts/ui/palette.gd")

## The locked palette (ART_BIBLE section 3). `#000000` is banned everywhere, so
## the outline is ink.
const CREAM: Color = Palette.CREAM
const INK: Color = Palette.INK
const MINT: Color = Palette.MINT
const SOFT_PINK: Color = Palette.SOFT_PINK
const PEACH: Color = Palette.PEACH
const GOLD: Color = Palette.STAR_EARNED

## One press cycle: the arrow falls, touches, the ripple runs, the arrow lifts.
const TAP_CYCLE_SEC: float = 1.55
const TAP_FALL_SEC: float = 0.42
const TAP_HOLD_SEC: float = 0.18
const TAP_LIFT_SEC: float = 0.40

## One drag cycle: the arrow presses, travels, releases, and the trail fades.
const DRAG_CYCLE_SEC: float = 2.3
const DRAG_TRAVEL_SEC: float = 1.2

## How far above the point the arrow starts, in pixels at the 1366x1024 reference.
const HAND_LIFT_PX: float = 96.0

## The arrow. Sized from ART_BIBLE section 8's touch-target rule rather than by
## eye: the thing being pointed AT is at least 240 px across, so the marker has
## to hold its own on the same screen -- about 120 px tall -- while staying
## narrower than the smallest prop, so it never hides what it points at.
const ARROW_SHAFT_WIDTH: float = 26.0
const ARROW_SHAFT_LENGTH: float = 58.0
const ARROW_HEAD_HALF: float = 40.0
const ARROW_HEAD_LENGTH: float = 44.0
const OUTLINE_PX: float = 6.0
## Clear air between the arrow's tip and the ring, so the tip is never lost in
## the ring's own stroke.
const TIP_GAP_PX: float = 12.0

## The ring that marks the target itself, under the arrow. It pulses at roughly
## the 0.6 Hz the art bible uses for "this is the next one".
const RING_RADIUS: float = 62.0
const RING_WIDTH: float = 9.0
const RIPPLE_MAX_RADIUS: float = 130.0

## The thing the demonstrated drag is carrying. An arrow sliding across an empty
## floor reads as "wave your finger"; an arrow with something under it reads as
## "move this", which is the lesson.
const TOKEN_RADIUS: float = 34.0
const TOKEN_COLOR: Color = Palette.PEACH

const MODE_NONE: String = "none"
const MODE_TAP: String = "tap"
const MODE_RING: String = "ring"
const MODE_DRAG: String = "drag"

var _mode: String = MODE_NONE
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _clock: float = 0.0
var _built: bool = false


func _ready() -> void:
	build()


## Idempotent, and called from every public method: `_ready()` does not fire for
## a node added to the root in the headless runner.
func build() -> void:
	if _built:
		return
	_built = true
	name = "GestureHint"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# NOT `set_anchors_preset()`. That one keeps the control's current 0x0 rect,
	# which has now cost this project a celebration card over the baby's face and
	# a HUD that wrapped every label to one character per line.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	step(delta)


## The animation clock. Public so the headless runner, which draws no frames, can
## advance it by hand and assert what the child would be looking at.
func step(delta: float) -> void:
	if _mode == MODE_NONE or not visible:
		return
	_clock += maxf(delta, 0.0)
	queue_redraw()


## -- Public API ----------------------------------------------------------------

## "Press here." `point` is in this control's own coordinates, which for a
## CanvasLayer overlay is the same space `Camera3D.unproject_position()` returns.
func show_tap(point: Vector2) -> void:
	build()
	if _mode != MODE_TAP or not _from.is_equal_approx(point):
		_clock = 0.0
	_mode = MODE_TAP
	_from = point
	_to = point
	visible = true
	queue_redraw()


## "Look here." The pulsing ring with NO hand on it.
##
## Used for the one beat that is about Little Buddy himself. A pointing hand
## there would sit squarely over his face -- and his face is the entire reason
## the step exists -- while also telling the child to tap a character who is not
## tappable. Rendering caught this; no test would have.
func show_ring(point: Vector2) -> void:
	build()
	if _mode != MODE_RING or not _from.is_equal_approx(point):
		_clock = 0.0
	_mode = MODE_RING
	_from = point
	_to = point
	visible = true
	queue_redraw()


## "Drag from here to there." Shown, never required.
func show_drag(from: Vector2, to: Vector2) -> void:
	build()
	if _mode != MODE_DRAG or not _from.is_equal_approx(from) or not _to.is_equal_approx(to):
		_clock = 0.0
	_mode = MODE_DRAG
	_from = from
	_to = to
	visible = true
	queue_redraw()


func hide_hint() -> void:
	build()
	_mode = MODE_NONE
	visible = false
	queue_redraw()


func get_mode() -> String:
	build()
	return _mode


func get_point() -> Vector2:
	build()
	return _from


func get_clock() -> float:
	return _clock


## -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	match _mode:
		MODE_TAP:
			_draw_tap()
		MODE_RING:
			_draw_pulse(_from, RING_RADIUS * 1.25)
		MODE_DRAG:
			_draw_drag()
		_:
			pass


## The "this one" ring, pulsing at ~0.6 Hz (ART_BIBLE section 3's rate for the
## current/next star), with a slow halo behind it.
func _draw_pulse(centre: Vector2, radius: float) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_clock * TAU * 0.6)
	_draw_ring(centre, radius * 1.42 + pulse * 18.0, CREAM, 0.12 + pulse * 0.16, RING_WIDTH + 6.0)
	_draw_ring(centre, radius + pulse * 10.0, MINT, 0.55 + pulse * 0.35)
	_draw_ring(centre, radius + pulse * 10.0, INK, 0.22, 2.0)
	_draw_sparkles(centre, radius + 26.0, pulse)


func _draw_tap() -> void:
	var phase: float = fmod(_clock, TAP_CYCLE_SEC)

	# The ring under the arrow is always there: it is the "this one" marker, and
	# it keeps pulsing even between presses so the eye has somewhere to rest.
	var pulse: float = 0.5 + 0.5 * sin(_clock * TAU * 0.6)
	_draw_ring(_from, RING_RADIUS + 10.0 + pulse * 7.0, CREAM, 0.14 + pulse * 0.12, RING_WIDTH + 6.0)
	_draw_ring(_from, RING_RADIUS + pulse * 7.0, MINT, 0.62 + pulse * 0.30)
	_draw_ring(_from, RING_RADIUS + pulse * 7.0, INK, 0.22, 2.0)

	# The ripple runs from the moment of contact outwards, and fades as it goes.
	if phase >= TAP_FALL_SEC:
		var since: float = clampf((phase - TAP_FALL_SEC) / 0.75, 0.0, 1.0)
		if since < 1.0:
			var eased: float = 1.0 - pow(1.0 - since, 3.0)
			_draw_ring(
				_from,
				RING_RADIUS + eased * (RIPPLE_MAX_RADIUS - RING_RADIUS),
				PEACH,
				(1.0 - since) * 0.8
			)
			if since > 0.1:
				_draw_sparkles(_from, RING_RADIUS + eased * 40.0, 1.0 - since)

	_draw_arrow(_from + Vector2(0.0, _tap_hand_offset(phase) - TIP_GAP_PX))


func _draw_drag() -> void:
	var phase: float = fmod(_clock, DRAG_CYCLE_SEC)
	var travel: float = clampf(phase / DRAG_TRAVEL_SEC, 0.0, 1.0)
	# Ease-out, 150-250 ms feel: nothing snaps (ART_BIBLE section 8).
	var eased: float = 1.0 - pow(1.0 - travel, 3.0)
	var at: Vector2 = _from.lerp(_to, eased)

	# Where it started, where it is going.
	_draw_ring(_from, RING_RADIUS * 0.72, SOFT_PINK, 0.55)
	var pulse: float = 0.5 + 0.5 * sin(_clock * TAU * 0.6)
	_draw_ring(_to, RING_RADIUS + pulse * 7.0, MINT, 0.62 + 0.30 * pulse)
	_draw_ring(_to, RING_RADIUS + pulse * 7.0, INK, 0.22, 2.0)

	# A dotted trail behind the arrow, so the movement is legible even in a still.
	var dots: int = 9
	for index: int in range(dots + 1):
		var along: float = float(index) / float(dots)
		if along > eased:
			break
		var dot: Vector2 = _from.lerp(_to, along)
		draw_circle(dot, 8.0, Color(INK.r, INK.g, INK.b, 0.16 + 0.2 * along))
		draw_circle(dot, 6.0, Color(PEACH.r, PEACH.g, PEACH.b, 0.45 + 0.45 * along))

	var lifted: float = 0.0
	if phase > DRAG_TRAVEL_SEC:
		# Released: the arrow lifts away rather than teleporting back, and the
		# thing it was carrying stays where it was put.
		lifted = -clampf((phase - DRAG_TRAVEL_SEC) / 0.5, 0.0, 1.0) * HAND_LIFT_PX
		_draw_token(_to)
	else:
		_draw_token(at)
	_draw_arrow(at + Vector2(0.0, lifted - TOKEN_RADIUS - TIP_GAP_PX))


## The thing being dragged. Not any real object in the game -- a soft peach disc,
## which is the shape language every prop in this house shares.
func _draw_token(centre: Vector2) -> void:
	draw_circle(centre, TOKEN_RADIUS + OUTLINE_PX, INK)
	draw_circle(centre, TOKEN_RADIUS, TOKEN_COLOR)
	draw_circle(centre + Vector2(-TOKEN_RADIUS * 0.3, -TOKEN_RADIUS * 0.3), TOKEN_RADIUS * 0.22,
			Color(CREAM.r, CREAM.g, CREAM.b, 0.7))


## How far above the point the arrow is right now, in pixels. 0 is "touching".
func _tap_hand_offset(phase: float) -> float:
	if phase < TAP_FALL_SEC:
		var falling: float = phase / TAP_FALL_SEC
		return -HAND_LIFT_PX * (1.0 - (1.0 - pow(1.0 - falling, 3.0)))
	if phase < TAP_FALL_SEC + TAP_HOLD_SEC:
		return 0.0
	var lift: float = clampf((phase - TAP_FALL_SEC - TAP_HOLD_SEC) / TAP_LIFT_SEC, 0.0, 1.0)
	return -HAND_LIFT_PX * (1.0 - pow(1.0 - lift, 3.0))


## A fat, friendly arrow pointing DOWN at `tip`. Peach with an ink edge and a
## cream shine, so it reads on a cream wall and a blue rug alike and never
## looks like a warning.
func _draw_arrow(tip: Vector2) -> void:
	var head_base: Vector2 = tip + Vector2(0.0, -ARROW_HEAD_LENGTH)
	var shaft_top: Vector2 = head_base + Vector2(0.0, -ARROW_SHAFT_LENGTH)

	# Outline first: a slightly fatter copy of everything, in ink.
	var o: float = OUTLINE_PX
	var head_outline: PackedVector2Array = PackedVector2Array([
		tip + Vector2(0.0, o * 1.6),
		head_base + Vector2(-(ARROW_HEAD_HALF + o * 1.4), -o * 0.6),
		head_base + Vector2(ARROW_HEAD_HALF + o * 1.4, -o * 0.6),
	])
	draw_colored_polygon(head_outline, INK)
	draw_line(shaft_top, head_base + Vector2(0.0, 4.0), INK, ARROW_SHAFT_WIDTH + o * 2.0, true)
	draw_circle(shaft_top, (ARROW_SHAFT_WIDTH + o * 2.0) * 0.5, INK)

	# The arrow itself.
	var head: PackedVector2Array = PackedVector2Array([
		tip, head_base + Vector2(-ARROW_HEAD_HALF, 0.0), head_base + Vector2(ARROW_HEAD_HALF, 0.0),
	])
	draw_line(shaft_top, head_base + Vector2(0.0, 6.0), PEACH, ARROW_SHAFT_WIDTH, true)
	draw_circle(shaft_top, ARROW_SHAFT_WIDTH * 0.5, PEACH)
	draw_colored_polygon(head, PEACH)

	# A shine down the left of the shaft, the way every prop in the house has one.
	draw_line(shaft_top + Vector2(-ARROW_SHAFT_WIDTH * 0.22, 4.0),
			head_base + Vector2(-ARROW_SHAFT_WIDTH * 0.22, -6.0),
			Color(CREAM.r, CREAM.g, CREAM.b, 0.75), ARROW_SHAFT_WIDTH * 0.22, true)


## Four small gold dots around the ring: the same sparkle the star reward uses,
## so "look here" and "well done" share a vocabulary.
func _draw_sparkles(centre: Vector2, radius: float, strength: float) -> void:
	var alpha: float = clampf(0.35 + 0.55 * strength, 0.0, 1.0)
	for index: int in range(4):
		var angle: float = -PI * 0.5 + index * PI * 0.5 + _clock * 0.9
		var at: Vector2 = centre + Vector2(cos(angle), sin(angle)) * radius
		var r: float = 6.0 + 3.0 * strength
		draw_circle(at, r + 2.5, Color(INK.r, INK.g, INK.b, alpha * 0.35))
		draw_circle(at, r, Color(GOLD.r, GOLD.g, GOLD.b, alpha))


func _draw_ring(centre: Vector2, radius: float, color: Color, alpha: float, width: float = RING_WIDTH) -> void:
	if radius <= 0.0:
		return
	draw_arc(
		centre, radius, 0.0, TAU, 48,
		Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0)), width, true
	)
