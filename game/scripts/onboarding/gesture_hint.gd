extends Control

## A pointing hand, a pulsing ring and a ripple: how this game explains itself to
## somebody who cannot read a word of any language.
##
## Every first-run instruction in `onboarding_plan.gd` is ultimately one of two
## pictures -- *press here* or *drag from here to there* -- so this draws exactly
## those two, in the locked palette, and nothing else. It is reused by Free Play's
## idle nudge, which is the same problem with no tutorial around it: a child who
## has stopped touching the screen needs a picture, not a sentence.
##
## ## Drawn, not composed
##
## `_draw()` primitives only -- circles, arcs, capsules. No texture, no atlas, no
## `ImageTexture` held in a local. ART_BIBLE section 8 records what happened the
## last time a glyph resource went out of scope between `_draw()` recording its
## commands and the renderer binding them: every sticker painted as a solid
## square. Primitives cannot have that bug.
##
## ## Never in the way
##
## `MOUSE_FILTER_IGNORE`, full-rect, drawn above the world and below nothing that
## matters. A child who taps the hand taps straight through it to the floor
## underneath, which is the whole point -- the hint is pointing at the thing they
## should touch, so touching the hint must do the right thing.
##
## ## Headless
##
## `step(delta)` is public and `_process()` does nothing but forward to it, so the
## animation clock can be driven by hand in the test runner, which draws no
## frames at all.

## The locked palette (ART_BIBLE section 3). `#000000` is banned everywhere, so
## the outline is ink.
const CREAM: Color = Color("#FFF6E5")
const INK: Color = Color("#59422B")
const MINT: Color = Color("#A8E6CF")
const SOFT_PINK: Color = Color("#FFC1CC")

## One press cycle: the hand falls, touches, the ripple runs, the hand lifts.
const TAP_CYCLE_SEC: float = 1.55
const TAP_FALL_SEC: float = 0.42
const TAP_HOLD_SEC: float = 0.18
const TAP_LIFT_SEC: float = 0.40

## One drag cycle: the hand presses, travels, releases, and the trail fades.
const DRAG_CYCLE_SEC: float = 2.3
const DRAG_TRAVEL_SEC: float = 1.2

## How far above the point the hand starts, in pixels at the 1366x1024 reference.
const HAND_LIFT_PX: float = 100.0

## The hand itself. Sized from ART_BIBLE section 8's touch-target rule rather
## than by eye: the thing being pointed AT has to be at least 240 px across, so a
## hand that is much smaller than that reads as a speck on the same screen. The
## whole hand is roughly 150 px tall, the ring it presses about 125 px across.
const PALM_RADIUS: float = 42.0
const FINGER_WIDTH: float = 28.0
const FINGER_LENGTH: float = 60.0
const THUMB_WIDTH: float = 23.0
const OUTLINE_PX: float = 6.0

## The ring that marks the target itself, under the hand. It pulses at roughly
## the 0.6 Hz the art bible uses for "this is the next one".
const RING_RADIUS: float = 62.0
const RING_WIDTH: float = 8.0
const RIPPLE_MAX_RADIUS: float = 130.0

## The thing the demonstrated drag is carrying. A hand sliding across an empty
## floor reads as "wave your finger"; a hand with something under it reads as
## "move this", which is the lesson.
const TOKEN_RADIUS: float = 34.0
const TOKEN_COLOR: Color = Color("#FFD3B6")

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
	_draw_ring(centre, radius + pulse * 10.0, MINT, 0.34 + pulse * 0.3)
	_draw_ring(centre, radius * 1.42 + pulse * 18.0, CREAM, 0.1 + pulse * 0.16)


func _draw_tap() -> void:
	var phase: float = fmod(_clock, TAP_CYCLE_SEC)

	# The ring under the finger is always there: it is the "this one" marker, and
	# it keeps pulsing even between presses so the eye has somewhere to rest.
	var pulse: float = 0.5 + 0.5 * sin(_clock * TAU * 0.6)
	_draw_ring(_from, RING_RADIUS + pulse * 7.0, MINT, 0.34 + pulse * 0.26)

	# The ripple runs from the moment of contact outwards, and fades as it goes.
	if phase >= TAP_FALL_SEC:
		var since: float = clampf((phase - TAP_FALL_SEC) / 0.75, 0.0, 1.0)
		if since < 1.0:
			var eased: float = 1.0 - pow(1.0 - since, 3.0)
			_draw_ring(
				_from,
				RING_RADIUS + eased * (RIPPLE_MAX_RADIUS - RING_RADIUS),
				CREAM,
				(1.0 - since) * 0.75
			)

	_draw_hand(_from + Vector2(0.0, _tap_hand_offset(phase)))


func _draw_drag() -> void:
	var phase: float = fmod(_clock, DRAG_CYCLE_SEC)
	var travel: float = clampf(phase / DRAG_TRAVEL_SEC, 0.0, 1.0)
	# Ease-out, 150-250 ms feel: nothing snaps (ART_BIBLE section 8).
	var eased: float = 1.0 - pow(1.0 - travel, 3.0)
	var at: Vector2 = _from.lerp(_to, eased)

	# Where it started, where it is going.
	_draw_ring(_from, RING_RADIUS * 0.72, SOFT_PINK, 0.42)
	_draw_ring(_to, RING_RADIUS, MINT, 0.34 + 0.26 * (0.5 + 0.5 * sin(_clock * TAU * 0.6)))

	# A dotted trail behind the hand, so the movement is legible even in a still.
	var dots: int = 9
	for index: int in range(dots + 1):
		var along: float = float(index) / float(dots)
		if along > eased:
			break
		var dot: Vector2 = _from.lerp(_to, along)
		draw_circle(dot, 7.0, Color(CREAM.r, CREAM.g, CREAM.b, 0.28 + 0.4 * along))

	var lifted: float = 0.0
	if phase > DRAG_TRAVEL_SEC:
		# Released: the hand lifts away rather than teleporting back, and the
		# thing it was carrying stays where it was put.
		lifted = -clampf((phase - DRAG_TRAVEL_SEC) / 0.5, 0.0, 1.0) * HAND_LIFT_PX
		_draw_token(_to)
	else:
		_draw_token(at)
	_draw_hand(at + Vector2(0.0, lifted))


## The thing being dragged. Not any real object in the game -- a soft peach disc,
## which is the shape language every prop in this house shares.
func _draw_token(centre: Vector2) -> void:
	draw_circle(centre, TOKEN_RADIUS + OUTLINE_PX, INK)
	draw_circle(centre, TOKEN_RADIUS, TOKEN_COLOR)


## How far above the point the hand is right now, in pixels. 0 is "touching".
func _tap_hand_offset(phase: float) -> float:
	if phase < TAP_FALL_SEC:
		var falling: float = phase / TAP_FALL_SEC
		return -HAND_LIFT_PX * (1.0 - (1.0 - pow(1.0 - falling, 3.0)))
	if phase < TAP_FALL_SEC + TAP_HOLD_SEC:
		return 0.0
	var lift: float = clampf((phase - TAP_FALL_SEC - TAP_HOLD_SEC) / TAP_LIFT_SEC, 0.0, 1.0)
	return -HAND_LIFT_PX * (1.0 - pow(1.0 - lift, 3.0))


## A pointing hand: one finger up towards the tip, a rounded palm below it.
## `tip` is where the fingertip is, so the hand always points AT the thing.
func _draw_hand(tip: Vector2) -> void:
	var finger_end: Vector2 = tip + Vector2(0.0, FINGER_LENGTH)
	var palm_centre: Vector2 = tip + Vector2(6.0, FINGER_LENGTH + PALM_RADIUS * 0.72)

	# Ink outline first, as a slightly fatter copy underneath. Rounded forms only
	# (ART_BIBLE section 4): capsule finger, spherical palm, nothing with a corner.
	draw_line(tip, finger_end, INK, FINGER_WIDTH + OUTLINE_PX * 2.0, true)
	draw_circle(tip, (FINGER_WIDTH + OUTLINE_PX * 2.0) * 0.5, INK)
	draw_circle(palm_centre, PALM_RADIUS + OUTLINE_PX, INK)

	draw_line(tip, finger_end, CREAM, FINGER_WIDTH, true)
	draw_circle(tip, FINGER_WIDTH * 0.5, CREAM)
	draw_circle(palm_centre, PALM_RADIUS, CREAM)

	# A thumb, so the shape reads as a hand and not as a lollipop.
	var thumb_from: Vector2 = palm_centre + Vector2(-PALM_RADIUS * 0.55, -2.0)
	var thumb_to: Vector2 = thumb_from + Vector2(-27.0, 18.0)
	draw_line(thumb_from, thumb_to, INK, THUMB_WIDTH + OUTLINE_PX * 2.0, true)
	draw_line(thumb_from, thumb_to, CREAM, THUMB_WIDTH, true)


func _draw_ring(centre: Vector2, radius: float, color: Color, alpha: float) -> void:
	if radius <= 0.0:
		return
	draw_arc(
		centre, radius, 0.0, TAU, 48,
		Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0)), RING_WIDTH, true
	)
