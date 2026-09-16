class_name StickerArt
extends RefCounted

## Procedural sticker drawing -- every sticker in the book is built from
## polygons, circles and arcs at draw time. Nothing here loads an image, so the
## sticker book can never break because a piece of art is missing, and it costs
## no texture memory on a phone.
##
## Static only; call from a `Control._draw()`:
##
##     StickerArt.draw_sticker(self, sticker_dict, Rect2(Vector2.ZERO, size), locked)
##
## Locked stickers are drawn as a soft lavender silhouette of the real shape --
## the child sees the outline of what is coming. Never a padlock, never a cross.

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

	for part: Variant in build_parts(word, primitive, square, base):
		if typeof(part) == TYPE_DICTIONARY:
			_draw_part(canvas, part, locked)


## A plain 5-point star, used by the counter, the celebration and the summary.
static func draw_star(canvas: CanvasItem, center: Vector2, radius: float,
		fill: Color = Color(1.0, 0.82, 0.2), outline: Color = Color(0.8, 0.58, 0.05),
		outline_width: float = 3.0) -> void:
	if canvas == null or radius <= 0.0:
		return
	var points: PackedVector2Array = star_points(center, radius, radius * 0.42)
	canvas.draw_colored_polygon(points, fill)
	if outline_width > 0.0:
		var loop: PackedVector2Array = points.duplicate()
		loop.append(points[0])
		canvas.draw_polyline(loop, outline, outline_width, true)


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


static func _banana(rect: Rect2, base: Color) -> Array:
	return [_poly(_ring_segment_points(
			_p(rect, 0.5, 0.14), _u(rect, 0.7), _u(rect, 0.52), 28.0, 152.0), base)]


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
		_circle(_p(rect, 0.3, 0.26), _u(rect, 0.1), WHITE),
		_circle(_p(rect, 0.5, 0.17), _u(rect, 0.08), WHITE),
		_circle(_p(rect, 0.67, 0.28), _u(rect, 0.07), WHITE),
		_poly(rounded_rect_points(_r(rect, 0.2, 0.44, 0.8, 0.78), _u(rect, 0.12)), base),
	]


static func _towel(rect: Rect2, base: Color) -> Array:
	return [
		_poly(rounded_rect_points(_r(rect, 0.24, 0.16, 0.76, 0.86), _u(rect, 0.08)), base),
		_poly(rounded_rect_points(_r(rect, 0.24, 0.36, 0.76, 0.44), 0.0), CREAM),
		_poly(rounded_rect_points(_r(rect, 0.24, 0.56, 0.76, 0.64), 0.0), CREAM),
	]


static func _toothbrush(rect: Rect2, base: Color) -> Array:
	return [
		_poly(rounded_rect_points(_r(rect, 0.12, 0.6, 0.72, 0.74), _u(rect, 0.07)), base),
		_poly(rounded_rect_points(_r(rect, 0.62, 0.54, 0.88, 0.76), _u(rect, 0.06)), base),
		_poly(rounded_rect_points(_r(rect, 0.64, 0.34, 0.7, 0.56), 0.0), WHITE),
		_poly(rounded_rect_points(_r(rect, 0.72, 0.3, 0.78, 0.56), 0.0), WHITE),
		_poly(rounded_rect_points(_r(rect, 0.8, 0.34, 0.86, 0.56), 0.0), WHITE),
	]


static func _pillow(rect: Rect2, base: Color) -> Array:
	return [
		_poly(rounded_rect_points(_r(rect, 0.12, 0.3, 0.88, 0.72), _u(rect, 0.18)), base),
		_arc(_p(rect, 0.5, 0.36), _u(rect, 0.2), 40.0, 140.0, _u(rect, 0.035), CREAM),
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

static func _draw_part(canvas: CanvasItem, part: Dictionary, locked: bool) -> void:
	var fill: Color = part.get("color", PEACH)
	if locked:
		fill = LOCKED_FILL
	var outline: Color = LOCKED_OUTLINE if locked else fill.darkened(0.22)

	match String(part.get("kind", "")):
		"poly":
			var points: PackedVector2Array = part.get("points", PackedVector2Array())
			if points.size() < 3:
				return
			canvas.draw_colored_polygon(points, fill)
			var loop: PackedVector2Array = points.duplicate()
			loop.append(points[0])
			canvas.draw_polyline(loop, outline, 2.0, true)
		"circle":
			var radius: float = float(part.get("radius", 0.0))
			var center: Vector2 = part.get("center", Vector2.ZERO)
			if radius <= 0.0:
				return
			canvas.draw_circle(center, radius, fill)
			canvas.draw_arc(center, radius, 0.0, TAU, 24, outline, 2.0, true)
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
