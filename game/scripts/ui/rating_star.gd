@tool
extends TextureRect

## One star in a 0-3 level rating -- and, since the highchair minigame, the star
## on a counter and the "almost" half star.
##
## ## Why this is not an `IconGlyph` with a paler tint
##
## `docs/ART_BIBLE.md` §8 is specific, and it is specific because this is the
## most emotionally loaded element in the game:
##
## > Earned `#FFC73D`; next `#FFE199` pulsing; unearned `#E8DCC8` outline only --
## > **a ghost, not an empty slot.**
##
## A tinted copy of the solid star glyph cannot be an outline. The screen this
## replaces faded the *filled* star to 45% alpha instead, which composites to a
## pale solid blob on cream. Three of those in a row is precisely the "empty
## slot" the bible forbids, and after a 0-star run it was the entire message:
## three pale holes where the reward should be, under a gold star reading "+0".
##
## So there are two textures, and the outline one is *the same path*: `star.svg`
## scaled to 92.5% about its own centre and stroked at 0.52 units so the stroke's
## outer edge lands back on the original silhouette. The gold star and the ghost
## star therefore share one outline at every size -- one glyph, two states, no
## second star added to the icon family (§8: "one shared glyph at every size").
##
## ## The four states
##
## `EARNED`  the child has this one. Glossy: gold fill, a lighter highlight
##           across the top-left, a deeper rim and a soft warm shadow -- the
##           star on the owner's UI sheet, drawn in `_draw()` over the glyph.
## `HALF`    the left half is gold, the right half is the pale outline. "So
##           close" -- shown while a halved task is still on the table, and on
##           the summary as "almost". Never a deduction: it appears, it is never
##           taken from a full star on screen.
## `NEXT`    the first one they have not: warm, brighter than a ghost, and
##           breathing gently, so even a 0-star row has something alive on it
##           saying "there is one waiting here" rather than "you got none".
## `GHOST`   further out. Quiet, warm, still unmistakably a star.
##
## ## Alpha carries meaning, deliberately
##
## Only `EARNED` paints at alpha 1.0. Every other state sits one step back
## (0.97 / 0.95 / 0.90) -- a real, small recession, and the same difference
## `test_level_summary.gd::_expect_filled()` counts to decide how many stars a
## child is being shown. Raise the ghost (or the half) to 1.0 and that case
## would count it as earned and go quietly green, so `test_ui_palette.gd` pins
## the invariant rather than leaving it to a comment.
##
## Purely decorative: `MOUSE_FILTER_IGNORE`, so it can sit inside a `Button`
## without stealing the press.

const _Palette := preload("res://scripts/ui/palette.gd")

const STAR_FILLED_PATH: String = "res://assets/ui/icons/star.svg"
const STAR_OUTLINE_PATH: String = "res://assets/ui/icons/star_outline.svg"

enum State { EARNED, NEXT, GHOST, HALF }

## Only an earned star is fully present. See the note above.
const ALPHA_EARNED: float = 1.0
const ALPHA_HALF: float = 0.97
const ALPHA_NEXT: float = 0.95
const ALPHA_GHOST: float = 0.90

## ~0.6 Hz, per the art bible: one unhurried breath in and out.
const PULSE_PERIOD: float = 1.0 / 0.6
## Kept small. On a screen a four-year-old holds 30 cm from their face, a big
## throb is agitating rather than inviting.
const PULSE_SCALE: float = 0.07
const PULSE_FADE: float = 0.18

## The procedural star drawn over the glyph. Inner radius as a fraction of the
## outer, then two rounds of corner smoothing so the points are pillowy rather
## than sharp -- the same silhouette family as `star.svg`.
const INNER_RATIO: float = 0.52
const ROUNDING_PASSES: int = 2
## Outline weight and shadow drop as fractions of the control's size.
const RIM_RATIO: float = 0.045
const SHADOW_DROP_RATIO: float = 0.05
const HIGHLIGHT_ALPHA: float = 0.62

@export var state: State = State.GHOST:
	set(value):
		state = value
		_apply_state()

## The colour actually painted, exposed so it can be read back in a test without
## a rendering pass. Driven by `state`; setting it directly is not meaningful.
var tint: Color = Color(1.0, 1.0, 1.0, 1.0)

var _tween: Tween = null


func _init() -> void:
	# Same setup as `icon_glyph.gd`: the TextureRect default reports the full
	# 240 px source as its minimum size, which blows open every container it sits
	# in.
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_state()


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_apply_state()


# ---------------------------------------------------------------------------
# The contract, static so it can be reasoned about without a scene tree
# ---------------------------------------------------------------------------

## The colour each state paints in, alpha included.
static func color_for(star_state: int) -> Color:
	match star_state:
		State.EARNED:
			return Color(_Palette.STAR_EARNED, ALPHA_EARNED)
		State.HALF:
			return Color(_Palette.STAR_EARNED, ALPHA_HALF)
		State.NEXT:
			return Color(_Palette.STAR_NEXT, ALPHA_NEXT)
		_:
			return Color(_Palette.STAR_GHOST, ALPHA_GHOST)


## Solid glyph or outline glyph. Only an earned star is ever filled: a filled
## pale star is an empty slot, which is the thing the bible bans. The half star
## starts from the outline and paints its gold half on top.
static func texture_path_for(star_state: int) -> String:
	return STAR_FILLED_PATH if star_state == State.EARNED else STAR_OUTLINE_PATH


## `index` is 0-based; `earned` is how many of the row are lit. Exactly one star
## is ever `NEXT` -- the first unearned one.
static func state_for(index: int, earned: int) -> int:
	if index < earned:
		return State.EARNED
	if index == earned:
		return State.NEXT
	return State.GHOST


## True for the two states that carry gold: a full star and the half star.
static func is_lit(star_state: int) -> bool:
	return star_state == State.EARNED or star_state == State.HALF


# ---------------------------------------------------------------------------
# Geometry, static so a test can check it never degenerates
# ---------------------------------------------------------------------------

## A five-point star with softly rounded corners, fitted to `rect`.
static func star_polygon(rect: Rect2) -> PackedVector2Array:
	var centre: Vector2 = rect.position + rect.size * 0.5
	var outer: float = minf(rect.size.x, rect.size.y) * 0.5
	var inner: float = outer * INNER_RATIO
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(10):
		var radius: float = outer if i % 2 == 0 else inner
		var angle: float = -PI * 0.5 + float(i) * PI / 5.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	for _pass: int in range(ROUNDING_PASSES):
		points = _chaikin(points)
	return points


## One Chaikin subdivision of a closed polygon: every corner becomes two points
## a quarter of the way along each neighbouring edge.
static func _chaikin(points: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var count: int = points.size()
	for i: int in range(count):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % count]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


# ---------------------------------------------------------------------------

func set_state(value: int) -> void:
	state = value as State


func _apply_state() -> void:
	var path: String = texture_path_for(state)
	tint = color_for(state)
	if is_lit(state):
		# The glossy states are drawn entirely in `_draw()`. `self_modulate`
		# multiplies custom drawing too, so it carries only the state's alpha
		# and the glyph is not shown underneath a second, procedural star.
		texture = null
		self_modulate = Color(1.0, 1.0, 1.0, tint.a)
	else:
		texture = load(path) if ResourceLoader.exists(path) else null
		self_modulate = tint
	_apply_pulse()
	queue_redraw()


## The glossy star. Drawn AFTER the texture, so it sits on top of the glyph.
func _draw() -> void:
	if not is_lit(state):
		return
	var side: float = minf(size.x, size.y)
	if side < 4.0:
		return
	var rect: Rect2 = Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var body: Rect2 = rect.grow(-side * 0.04)
	var star: PackedVector2Array = star_polygon(body)
	var gold: Color = _Palette.STAR_EARNED
	var rim: Color = _Palette.deep(gold)
	var rim_width: float = side * RIM_RATIO

	# Soft warm shadow, only where it peeks out from under the star.
	var drop: Vector2 = Vector2(0.0, side * SHADOW_DROP_RATIO)
	var shadow: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in star:
		shadow.append(p + drop)
	for piece: PackedVector2Array in Geometry2D.clip_polygons(shadow, star):
		draw_colored_polygon(piece, Color(_Palette.SCRIM, 0.22))

	if state == State.HALF:
		# The pale outline star underneath (the glyph is hidden while lit), then
		# the gold LEFT half painted over it.
		draw_polyline(_closed(star), Color(_Palette.STAR_GHOST, ALPHA_HALF), rim_width, true)
		var left: Rect2 = Rect2(rect.position - Vector2(side, side), Vector2(side * 1.5, side * 3.0))
		var half_mask: PackedVector2Array = PackedVector2Array([
			left.position, left.position + Vector2(left.size.x, 0.0), left.end, left.position + Vector2(0.0, left.size.y)])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(star, half_mask):
			draw_colored_polygon(piece, gold)
			_draw_gloss(piece, body, side)
			draw_polyline(_closed(piece), rim, rim_width, true)
		return

	draw_colored_polygon(star, gold)
	_draw_gloss(star, body, side)
	draw_polyline(_closed(star), rim, rim_width, true)


## A lighter lozenge across the upper left of the star, clipped to it.
func _draw_gloss(star: PackedVector2Array, body: Rect2, side: float) -> void:
	var centre: Vector2 = body.position + body.size * Vector2(0.42, 0.40)
	var highlight: PackedVector2Array = PackedVector2Array()
	for i: int in range(18):
		var angle: float = float(i) / 18.0 * TAU
		highlight.append(centre + Vector2(cos(angle) * side * 0.26, sin(angle) * side * 0.16).rotated(-0.5))
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(star, highlight):
		draw_colored_polygon(piece, Color(_Palette.light(_Palette.STAR_EARNED), HIGHLIGHT_ALPHA))
	# A tiny bright dot, top-left point.
	var dot: Vector2 = body.position + body.size * Vector2(0.36, 0.30)
	draw_circle(dot, side * 0.045, Color(_Palette.CREAM, 0.85))


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = points.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out


func _apply_pulse() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	scale = Vector2.ONE
	modulate.a = 1.0

	# `is_inside_tree()` keeps the headless runner honest -- `_ready()` never
	# fires for a node added to the root there, and `create_tween()` needs a tree.
	if state != State.NEXT or Engine.is_editor_hint() or not is_inside_tree():
		return

	pivot_offset = size * 0.5
	_tween = create_tween().set_loops()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * (1.0 + PULSE_SCALE), PULSE_PERIOD * 0.5)
	_tween.parallel().tween_property(self, "modulate:a", 1.0 - PULSE_FADE, PULSE_PERIOD * 0.5)
	_tween.tween_property(self, "scale", Vector2.ONE, PULSE_PERIOD * 0.5)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, PULSE_PERIOD * 0.5)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()
