@tool
class_name IconGlyph
extends Control

## One tiny procedurally drawn icon, sized to fill the control.
##
## Used for the pieces of child-facing UI that must read without any text: the
## back arrow, the star counter, the "play again" replay arrow, the heart. Drawn
## with `_draw()` so there is no image dependency and nothing to import.
##
## Purely decorative -- it never eats a touch (`MOUSE_FILTER_IGNORE`), so it can
## sit inside a `Button` without stealing its input.

enum Glyph {
	STAR,
	BACK,
	REPLAY,
	HEART,
}

const _StickerArt := preload("res://scripts/progression/sticker_art.gd")

@export var glyph: Glyph = Glyph.STAR:
	set(value):
		glyph = value
		queue_redraw()

@export var fill_color: Color = Color(1.0, 0.82, 0.2):
	set(value):
		fill_color = value
		queue_redraw()

@export var outline_color: Color = Color(0.8, 0.58, 0.05):
	set(value):
		outline_color = value
		queue_redraw()

@export_range(0.0, 12.0, 0.5) var outline_width: float = 3.0:
	set(value):
		outline_width = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	if side <= 1.0:
		return
	var center: Vector2 = size * 0.5
	var radius: float = side * 0.5

	match glyph:
		Glyph.STAR:
			_StickerArt.draw_star(self, center, radius * 0.96, fill_color, outline_color, outline_width)
		Glyph.BACK:
			_draw_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.55, 0.0),
				center + Vector2(radius * 0.25, -radius * 0.7),
				center + Vector2(radius * 0.25, -radius * 0.26),
				center + Vector2(radius * 0.7, -radius * 0.26),
				center + Vector2(radius * 0.7, radius * 0.26),
				center + Vector2(radius * 0.25, radius * 0.26),
				center + Vector2(radius * 0.25, radius * 0.7),
			]))
		Glyph.REPLAY:
			draw_arc(center, radius * 0.6, deg_to_rad(40.0), deg_to_rad(330.0), 28,
					fill_color, radius * 0.24, true)
			var tip: Vector2 = center + Vector2(cos(deg_to_rad(40.0)), sin(deg_to_rad(40.0))) * radius * 0.6
			_draw_polygon(PackedVector2Array([
				tip + Vector2(-radius * 0.3, -radius * 0.06),
				tip + Vector2(radius * 0.24, -radius * 0.2),
				tip + Vector2(radius * 0.06, radius * 0.34),
			]))
		Glyph.HEART:
			var rect: Rect2 = Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
			_StickerArt.draw_sticker(self, {"word": "heart", "color": fill_color.to_html(false)}, rect, false)


func _draw_polygon(points: PackedVector2Array) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, fill_color)
	if outline_width <= 0.0:
		return
	var loop: PackedVector2Array = points.duplicate()
	loop.append(points[0])
	draw_polyline(loop, outline_color, outline_width, true)
