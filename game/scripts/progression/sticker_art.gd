class_name StickerArt
extends RefCounted

## Sticker pictures for the book, the summary and the celebration flourish.
##
## Static only; call from a `Control._draw()`:
##
##     StickerArt.draw_sticker(self, sticker_dict, Rect2(Vector2.ZERO, size), locked)
##
## Two sources, one look:
##
##   * Eleven of the sixteen stickers are drawn from the same bundled Nieobie
##     icon set as the rest of the UI (`assets/ui/icons/stickers/`), so the milk
##     on a sticker card and the milk anywhere else are the same drawing.
##   * The remaining five -- banana, soap, towel, toothbrush, pillow -- have no
##     on-theme glyph anywhere in the 815-icon pack, so they keep their polygon
##     recipe. `build_parts()` still covers every word, which also makes it the
##     safety net: a sticker can never come out blank because an image failed to
##     import.
##
## Both paths render in the same language: flat pastel shapes, each carrying a
## darker die-cut rim, like a real sticker. A glyph gets that rim from
## `_draw_glyph()`; a polygon gets it per part from `_draw_part()`.
##
## Locked stickers are the same shape in soft lavender -- the child sees the
## outline of what is coming. Never a padlock, never a cross.

# -- Warm pastel palette (shared with the rest of the child-facing UI) --------
const CREAM: Color = Color(1.0, 0.965, 0.898)
const DUSTY_BLUE: Color = Color(0.604, 0.753, 0.851)
const SOFT_PINK: Color = Color(1.0, 0.757, 0.8)
const MINT: Color = Color(0.659, 0.902, 0.812)
const PEACH: Color = Color(1.0, 0.827, 0.714)
const LAVENDER: Color = Color(0.839, 0.78, 0.941)
const INK: Color = Color(0.349, 0.259, 0.169)
const WHITE: Color = Color(1.0, 1.0, 1.0)

## Silhouette colours for a not-yet-earned sticker.
const LOCKED_FILL: Color = Color(0.851, 0.827, 0.886)
const LOCKED_OUTLINE: Color = Color(0.784, 0.753, 0.835)

const ARC_STEPS: int = 20

## Sticker word -> bundled Nieobie glyph (CC0), on the same optical grid as the
## rest of the UI icons. A word that is absent here falls through to
## `build_parts()` and keeps its polygon recipe.
##
## Absent on purpose, because the 815-icon pack has nothing on-theme for them:
##   banana, soap, towel, toothbrush, pillow.
## The nearest candidates were a pear (not a banana), a paint brush (not a
## toothbrush) and a pair of closed eyes (not a pillow) -- each of which would
## teach the wrong word, which is worse than a hand-drawn shape.
const GLYPH_PATHS: Dictionary = {
	"milk": "res://assets/ui/icons/stickers/milk.svg",
	"teddy": "res://assets/ui/icons/stickers/teddy.svg",
	"apple": "res://assets/ui/icons/stickers/apple.svg",
	"star": "res://assets/ui/icons/stickers/star.svg",
	"ball": "res://assets/ui/icons/stickers/ball.svg",
	"shirt": "res://assets/ui/icons/stickers/shirt.svg",
	"shoes": "res://assets/ui/icons/stickers/shoes.svg",
	"moon": "res://assets/ui/icons/stickers/moon.svg",
	"heart": "res://assets/ui/icons/stickers/heart.svg",
	"cloud": "res://assets/ui/icons/stickers/cloud.svg",
	"rainbow": "res://assets/ui/icons/stickers/rainbow.svg",
}

## Die-cut rim around a glyph, as a fraction of the sticker's side. Without it a
## pale sticker (milk is `#FFFFFF`, cloud `#E6F0FA`) would disappear into the
## cream card.
const RIM_RATIO: float = 0.022


# ---------------------------------------------------------------------------
# Public entry points
# ---------------------------------------------------------------------------

## Draws `sticker` (a content-library sticker dictionary) to fill `rect`.
static func draw_sticker(canvas: CanvasItem, sticker: Dictionary, rect: Rect2, locked: bool = false) -> void:
	if canvas == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var square: Rect2 = _square(rect)
	var base: Color = color_from_hex(String(sticker.get("color", "")), PEACH)
	var word: String = String(sticker.get("word", "")).to_lower()
	var primitive: String = String(sticker.get("primitive", "sphere")).to_lower()

	var glyph: Texture2D = glyph_for(word)
	if glyph != null:
		_draw_glyph(canvas, glyph, square, base, locked)
		return

	var rim_width: float = maxf(minf(square.size.x, square.size.y) * RIM_RATIO * 2.0, 2.0)
	for part: Variant in build_parts(word, primitive, square, base):
		if typeof(part) == TYPE_DICTIONARY:
			_draw_part(canvas, part, locked, rim_width)


## The bundled glyph for `word`, or null if this sticker is drawn from polygons.
##
## Guarded rather than `preload`ed: a missing or not-yet-imported image must drop
## back to the polygon recipe, never take the sticker book down with it.
##
## The result is cached, and that cache is load-bearing, not an optimisation.
## `_draw()` only *records* draw commands; the renderer binds the texture later
## in the frame. A texture held in nothing but a local would drop to zero
## references the moment `_draw()` returned, and the renderer would fall back to
## its 1x1 white texture -- which is exactly the solid coloured square this used
## to paint instead of a sticker.
static var _glyph_cache: Dictionary = {}


static func glyph_for(word: String) -> Texture2D:
	var key: String = word.to_lower()
	if _glyph_cache.has(key):
		return _glyph_cache[key] as Texture2D

	var texture: Texture2D = null
	var path: String = String(GLYPH_PATHS.get(key, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_glyph_cache[key] = texture
	return texture


static func star_points(center: Vector2, outer_radius: float, inner_radius: float,
		tips: int = 5) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(tips, 3) * 2
	var step: float = 360.0 / float(count)
	for i: int in range(count):
		var radius: float = outer_radius if i % 2 == 0 else inner_radius
		var angle: float = deg_to_rad(-90.0 + float(i) * step)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Rounded-rectangle outline as a polygon (Godot has no rounded polygon prim).
static func rounded_rect_points(rect: Rect2, radius: float, steps: int = 5) -> PackedVector2Array:
	var r: float = clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var points: PackedVector2Array = PackedVector2Array()
	if r <= 0.01:
		points.append(rect.position)
		points.append(rect.position + Vector2(rect.size.x, 0.0))
		points.append(rect.position + rect.size)
		points.append(rect.position + Vector2(0.0, rect.size.y))
		return points

	var corners: Array[Vector2] = [
		rect.position + Vector2(rect.size.x - r, r),   # top-right
		rect.position + Vector2(rect.size.x - r, rect.size.y - r),  # bottom-right
		rect.position + Vector2(r, rect.size.y - r),   # bottom-left
		rect.position + Vector2(r, r),                 # top-left
	]
	var start_angles: Array[float] = [-90.0, 0.0, 90.0, 180.0]

	for i: int in range(4):
		var center: Vector2 = corners[i]
		var start: float = start_angles[i]
		for s: int in range(steps + 1):
			var angle: float = deg_to_rad(start + 90.0 * (float(s) / float(steps)))
			points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points


## Parses "#RRGGBB" defensively; anything unparseable falls back to `fallback`.
static func color_from_hex(hex: String, fallback: Color) -> Color:
	var text: String = hex.strip_edges().trim_prefix("#")
	if text.is_empty() or not Color.html_is_valid(text):
		return fallback
	return Color.html(text)


# ---------------------------------------------------------------------------
# Part construction
# ---------------------------------------------------------------------------

## The drawing recipe for one sticker: a list of
## `{kind: "poly"|"circle"|"arc", ...}` dictionaries.
##
## Public so tests can check that every polygon actually triangulates -- a
## self-intersecting polygon makes Godot's triangulator bail out and silently
## draw nothing, which would only show up as a blank sticker on the device.
static func build_parts(word: String, primitive: String, rect: Rect2, base: Color) -> Array:
	match word:
		"milk":
			return _milk(rect, base)
		"teddy":
			return _teddy(rect, base)
		"apple":
			return _apple(rect, base)
		"banana":
			return _banana(rect, base)
		"star":
			return _star(rect, base)
		"ball":
			return _ball(rect, base)
		"shirt":
			return _shirt(rect, base)
		"shoes":
			return _shoes(rect, base)
		"soap":
			return _soap(rect, base)
		"towel":
			return _towel(rect, base)
		"toothbrush":
			return _toothbrush(rect, base)
		"pillow":
			return _pillow(rect, base)
		"moon":
			return _moon(rect, base)
		"heart":
			return _heart(rect, base)
		"cloud":
			return _cloud(rect, base)
		"rainbow":
			return _rainbow(rect)
		_:
			return _fallback(primitive, rect, base)


static func _milk(rect: Rect2, base: Color) -> Array:
	return [
		_poly(rounded_rect_points(_r(rect, 0.26, 0.28, 0.74, 0.92), _u(rect, 0.12)), base),
		_poly(rounded_rect_points(_r(rect, 0.41, 0.16, 0.59, 0.34), _u(rect, 0.03)), base),
		_poly(rounded_rect_points(_r(rect, 0.36, 0.06, 0.64, 0.2), _u(rect, 0.05)), SOFT_PINK),
		_poly(rounded_rect_points(_r(rect, 0.31, 0.56, 0.69, 0.87), _u(rect, 0.08)), DUSTY_BLUE),
	]


static func _teddy(rect: Rect2, base: Color) -> Array:
	return [
		_circle(_p(rect, 0.27, 0.3), _u(rect, 0.14), base),
		_circle(_p(rect, 0.73, 0.3), _u(rect, 0.14), base),
		_circle(_p(rect, 0.5, 0.52), _u(rect, 0.3), base),
		_circle(_p(rect, 0.5, 0.63), _u(rect, 0.15), CREAM),
		_circle(_p(rect, 0.4, 0.45), _u(rect, 0.04), INK),
		_circle(_p(rect, 0.6, 0.45), _u(rect, 0.04), INK),
		_circle(_p(rect, 0.5, 0.58), _u(rect, 0.05), INK),
	]


static func _apple(rect: Rect2, base: Color) -> Array:
	return [
		_poly(PackedVector2Array([
			_p(rect, 0.47, 0.18), _p(rect, 0.54, 0.18),
			_p(rect, 0.54, 0.38), _p(rect, 0.47, 0.38),
		]), Color(0.42, 0.29, 0.17)),
		_poly(PackedVector2Array([
			_p(rect, 0.54, 0.26), _p(rect, 0.78, 0.16), _p(rect, 0.62, 0.36),
		]), MINT),
		_circle(_p(rect, 0.38, 0.58), _u(rect, 0.24), base),
		_circle(_p(rect, 0.62, 0.58), _u(rect, 0.24), base),
		_circle(_p(rect, 0.5, 0.66), _u(rect, 0.24), base),
	]


## Radius 0.5 of the side, not 0.7: the old crescent was wider than its own card
## and spilled over the neighbouring stickers once the book grew its cards to
## fill the page.
static func _banana(rect: Rect2, base: Color) -> Array:
	return [_poly(_ring_segment_points(
			_p(rect, 0.5, 0.2), _u(rect, 0.5), _u(rect, 0.3), 20.0, 160.0), base)]


static func _star(rect: Rect2, base: Color) -> Array:
	return [_poly(star_points(_p(rect, 0.5, 0.52), _u(rect, 0.42), _u(rect, 0.18)), base)]


static func _ball(rect: Rect2, base: Color) -> Array:
	return [
		_circle(_p(rect, 0.5, 0.5), _u(rect, 0.36), base),
		_arc(_p(rect, 0.5, 0.42), _u(rect, 0.24), 30.0, 150.0, _u(rect, 0.07), WHITE),
		_arc(_p(rect, 0.5, 0.6), _u(rect, 0.24), 210.0, 330.0, _u(rect, 0.07), WHITE),
	]


static func _shirt(rect: Rect2, base: Color) -> Array:
	return [_poly(PackedVector2Array([
		_p(rect, 0.18, 0.34), _p(rect, 0.36, 0.2), _p(rect, 0.43, 0.28),
		_p(rect, 0.57, 0.28), _p(rect, 0.64, 0.2), _p(rect, 0.82, 0.34),
		_p(rect, 0.73, 0.48), _p(rect, 0.67, 0.42), _p(rect, 0.67, 0.84),
		_p(rect, 0.33, 0.84), _p(rect, 0.33, 0.42), _p(rect, 0.27, 0.48),
	]), base)]


static func _shoes(rect: Rect2, base: Color) -> Array:
	return [
		_poly(PackedVector2Array([
			_p(rect, 0.16, 0.7), _p(rect, 0.16, 0.34), _p(rect, 0.32, 0.34),
			_p(rect, 0.4, 0.52), _p(rect, 0.82, 0.62), _p(rect, 0.86, 0.7),
		]), base),
		_poly(rounded_rect_points(_r(rect, 0.12, 0.7, 0.9, 0.8), _u(rect, 0.04)), CREAM),
		_poly(PackedVector2Array([
			_p(rect, 0.2, 0.44), _p(rect, 0.44, 0.44), _p(rect, 0.44, 0.5), _p(rect, 0.2, 0.5),
		]), WHITE),
	]


static func _soap(rect: Rect2, base: Color) -> Array:
	return [
		_circle(_p(rect, 0.29, 0.25), _u(rect, 0.115), WHITE),
		_circle(_p(rect, 0.52, 0.15), _u(rect, 0.09), WHITE),
		_circle(_p(rect, 0.71, 0.27), _u(rect, 0.075), WHITE),
		_poly(rounded_rect_points(_r(rect, 0.14, 0.45, 0.86, 0.82), _u(rect, 0.16)), base),
	]


static func _towel(rect: Rect2, base: Color) -> Array:
	return [
		_poly(rounded_rect_points(_r(rect, 0.22, 0.13, 0.78, 0.87), _u(rect, 0.11)), base),
		_poly(rounded_rect_points(_r(rect, 0.22, 0.61, 0.78, 0.68), 0.0), WHITE),
		_poly(rounded_rect_points(_r(rect, 0.22, 0.72, 0.78, 0.79), 0.0), WHITE),
	]


## Handle plus one bristle pad, not five separate bristles: at sticker size the
## thin bristles collapsed into a single block and the whole thing read as a
## hammer.
static func _toothbrush(rect: Rect2, base: Color) -> Array:
	return [
		_poly(rounded_rect_points(_r(rect, 0.09, 0.56, 0.72, 0.73), _u(rect, 0.085)), base),
		_poly(rounded_rect_points(_r(rect, 0.6, 0.5, 0.93, 0.78), _u(rect, 0.1)), base),
		_poly(rounded_rect_points(_r(rect, 0.63, 0.24, 0.9, 0.55), _u(rect, 0.07)), WHITE),
	]


## Two nested rounded rectangles: `_draw_part()` rims each one, so the inner
## shape reads as the piping around a pillow rather than as a plain slab.
static func _pillow(rect: Rect2, base: Color) -> Array:
	return [
		_poly(rounded_rect_points(_r(rect, 0.09, 0.25, 0.91, 0.75), _u(rect, 0.22)), base),
		_poly(rounded_rect_points(_r(rect, 0.17, 0.33, 0.83, 0.67), _u(rect, 0.15)), base),
	]


static func _moon(rect: Rect2, base: Color) -> Array:
	return [_poly(_ring_segment_points(
			_p(rect, 0.36, 0.5), _u(rect, 0.46), _u(rect, 0.26), 56.0, 304.0), base)]


static func _heart(rect: Rect2, base: Color) -> Array:
	return [
		_circle(_p(rect, 0.33, 0.4), _u(rect, 0.21), base),
		_circle(_p(rect, 0.67, 0.4), _u(rect, 0.21), base),
		_poly(PackedVector2Array([
			_p(rect, 0.13, 0.44), _p(rect, 0.87, 0.44), _p(rect, 0.5, 0.86),
		]), base),
	]


static func _cloud(rect: Rect2, base: Color) -> Array:
	return [
		_circle(_p(rect, 0.33, 0.48), _u(rect, 0.19), base),
		_circle(_p(rect, 0.52, 0.4), _u(rect, 0.23), base),
		_circle(_p(rect, 0.7, 0.5), _u(rect, 0.17), base),
		_poly(rounded_rect_points(_r(rect, 0.18, 0.48, 0.84, 0.68), _u(rect, 0.09)), base),
	]


static func _rainbow(rect: Rect2) -> Array:
	var center: Vector2 = _p(rect, 0.5, 0.78)
	return [
		_arc(center, _u(rect, 0.42), 180.0, 360.0, _u(rect, 0.09), SOFT_PINK),
		_arc(center, _u(rect, 0.32), 180.0, 360.0, _u(rect, 0.09), PEACH),
		_arc(center, _u(rect, 0.22), 180.0, 360.0, _u(rect, 0.09), DUSTY_BLUE),
	]


static func _fallback(primitive: String, rect: Rect2, base: Color) -> Array:
	match primitive:
		"capsule":
			return [_poly(rounded_rect_points(_r(rect, 0.32, 0.14, 0.68, 0.86), _u(rect, 0.18)), base)]
		"box":
			return [_poly(rounded_rect_points(_r(rect, 0.18, 0.22, 0.82, 0.78), _u(rect, 0.1)), base)]
		"cylinder":
			return [_poly(rounded_rect_points(_r(rect, 0.34, 0.18, 0.66, 0.82), _u(rect, 0.08)), base)]
		"torus":
			return [_arc(_p(rect, 0.5, 0.5), _u(rect, 0.3), 0.0, 360.0, _u(rect, 0.12), base)]
		_:
			return [_circle(_p(rect, 0.5, 0.5), _u(rect, 0.36), base)]


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

## One bundled glyph, drawn as a flat shape in the sticker's colour with a
## darker rim -- a die-cut sticker rather than a flat icon.
##
## The rim is eight offset copies of the same white texture rather than an
## outline shader: it needs no material, no extra import, and it works for any
## silhouette, including the disjoint ones (the moon's sparkle, the ball's
## panels).
static func _draw_glyph(canvas: CanvasItem, glyph: Texture2D, rect: Rect2,
		base: Color, locked: bool) -> void:
	var fill: Color = LOCKED_FILL if locked else _sticker_fill(base)
	var rim: Color = LOCKED_OUTLINE if locked else _rim_color(fill)
	var offset: float = maxf(minf(rect.size.x, rect.size.y) * RIM_RATIO, 1.0)

	for i: int in range(8):
		var angle: float = deg_to_rad(float(i) * 45.0)
		var shift: Vector2 = Vector2(cos(angle), sin(angle)) * offset
		canvas.draw_texture_rect(glyph, Rect2(rect.position + shift, rect.size), false, rim)

	canvas.draw_texture_rect(glyph, rect, false, fill)


## Keeps a near-white sticker (milk is `#FFFFFF`) from reading as a hole in the
## cream card, without touching the colours that already have body.
static func _sticker_fill(base: Color) -> Color:
	var luminance: float = base.get_luminance()
	if luminance <= 0.86:
		return base
	return base.darkened((luminance - 0.86) * 0.7)


## The lighter the fill, the darker the edge has to be to survive on cream.
static func _rim_color(fill: Color) -> Color:
	return fill.darkened(lerpf(0.24, 0.44, fill.get_luminance()))


static func _draw_part(canvas: CanvasItem, part: Dictionary, locked: bool,
		rim_width: float = 2.0) -> void:
	var fill: Color = part.get("color", PEACH)
	if locked:
		fill = LOCKED_FILL
	var outline: Color = LOCKED_OUTLINE if locked else _rim_color(fill)

	match String(part.get("kind", "")):
		"poly":
			var points: PackedVector2Array = part.get("points", PackedVector2Array())
			if points.size() < 3:
				return
			canvas.draw_colored_polygon(points, fill)
			var loop: PackedVector2Array = points.duplicate()
			loop.append(points[0])
			canvas.draw_polyline(loop, outline, rim_width, true)
		"circle":
			var radius: float = float(part.get("radius", 0.0))
			var center: Vector2 = part.get("center", Vector2.ZERO)
			if radius <= 0.0:
				return
			canvas.draw_circle(center, radius, fill)
			canvas.draw_arc(center, radius, 0.0, TAU, 24, outline, rim_width, true)
		"arc":
			var arc_center: Vector2 = part.get("center", Vector2.ZERO)
			canvas.draw_arc(
				arc_center,
				float(part.get("radius", 0.0)),
				deg_to_rad(float(part.get("from", 0.0))),
				deg_to_rad(float(part.get("to", 0.0))),
				ARC_STEPS,
				fill,
				float(part.get("width", 2.0)),
				true)


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

static func _poly(points: PackedVector2Array, color: Color) -> Dictionary:
	return {"kind": "poly", "points": points, "color": color}


static func _circle(center: Vector2, radius: float, color: Color) -> Dictionary:
	return {"kind": "circle", "center": center, "radius": radius, "color": color}


static func _arc(center: Vector2, radius: float, from_deg: float, to_deg: float,
		width: float, color: Color) -> Dictionary:
	return {
		"kind": "arc", "center": center, "radius": radius,
		"from": from_deg, "to": to_deg, "width": width, "color": color,
	}


## Normalised point inside `rect` (0..1 on each axis).
static func _p(rect: Rect2, u: float, v: float) -> Vector2:
	return rect.position + Vector2(u * rect.size.x, v * rect.size.y)


## Normalised sub-rectangle of `rect`.
static func _r(rect: Rect2, u0: float, v0: float, u1: float, v1: float) -> Rect2:
	var top_left: Vector2 = _p(rect, u0, v0)
	return Rect2(top_left, _p(rect, u1, v1) - top_left)


## Normalised length, relative to the shorter side.
static func _u(rect: Rect2, amount: float) -> float:
	return minf(rect.size.x, rect.size.y) * amount


static func _arc_points(center: Vector2, radius: float, from_deg: float, to_deg: float,
		steps: int = ARC_STEPS) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(steps, 2)
	for i: int in range(count + 1):
		var t: float = float(i) / float(count)
		var angle: float = deg_to_rad(lerpf(from_deg, to_deg, t))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## A curved band: the outer arc, then the inner arc walked back. Used for the
## banana and the crescent moon.
##
## The two arcs are strictly concentric on purpose. Subtracting one offset
## circle from another is the textbook crescent, but those two boundaries cross
## near the tips and taper to a sliver -- and Godot's triangulator answers a
## self-intersecting or sliver polygon by drawing nothing at all, which would
## reach the device as a blank sticker. Concentric arcs can never cross.
static func _ring_segment_points(center: Vector2, outer_radius: float, inner_radius: float,
		from_deg: float, to_deg: float, steps: int = 24) -> PackedVector2Array:
	var outer: float = maxf(outer_radius, 0.001)
	var inner: float = clampf(inner_radius, 0.0, outer * 0.92)
	var points: PackedVector2Array = _arc_points(center, outer, from_deg, to_deg, steps)
	points.append_array(_arc_points(center, inner, to_deg, from_deg, steps))
	return points


## The largest centred square inside `rect`, so stickers never stretch.
static func _square(rect: Rect2) -> Rect2:
	var side: float = minf(rect.size.x, rect.size.y)
	return Rect2(rect.position + (rect.size - Vector2(side, side)) * 0.5, Vector2(side, side))
