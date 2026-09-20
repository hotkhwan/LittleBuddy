@tool
extends Control

## The Dress Up icon: a little T-shirt with a heart on it.
##
## Drawn in code, in the locked palette, on the same 86% optical box
## `icon_glyph.gd` and `house_glyph.gd` use, so it sits at matching weight
## inside a matching button. The bundled icon pack has no clothing, and a
## pre-reader has to tell "dress up" from "play" without reading either word.
##
## Rounded forms only: the hem and sleeves are rounded, and the heart is two
## circles on a point. Purely decorative -- `MOUSE_FILTER_IGNORE`, so it never
## eats the press meant for the `Button` it sits inside.

## The shirt. Ink by default; never black, never red.
@export var tint: Color = Color(0.349, 0.259, 0.169):
	set(value):
		tint = value
		queue_redraw()

## The heart is knocked out in the colour of the button face behind it.
@export var face_color: Color = Color(1.0, 0.757, 0.800):
	set(value):
		face_color = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var box: float = minf(size.x, size.y) * 0.86
	if box <= 0.0:
		return
	var o: Vector2 = Vector2((size.x - box) * 0.5, (size.y - box) * 0.5)

	# Body: a rounded rectangle from the chest to the hem.
	var body := Rect2(o + Vector2(box * 0.24, box * 0.16), Vector2(box * 0.52, box * 0.78))
	_rounded(body, box * 0.09, tint)

	# Sleeves: two rounded slabs angled out from the shoulders.
	for side: float in [-1.0, 1.0]:
		var centre: Vector2 = o + Vector2(box * 0.5 + side * box * 0.36, box * 0.30)
		var sleeve := Rect2(centre - Vector2(box * 0.14, box * 0.16), Vector2(box * 0.28, box * 0.30))
		_rounded(sleeve, box * 0.08, tint)
		draw_circle(o + Vector2(box * 0.5 + side * box * 0.36, box * 0.46), box * 0.09, tint)

	# Neckline: a scoop knocked out at the top.
	draw_circle(o + Vector2(box * 0.5, box * 0.13), box * 0.12, face_color)

	# The heart, centred on the chest.
	var heart_at: Vector2 = o + Vector2(box * 0.5, box * 0.55)
	var r: float = box * 0.075
	draw_circle(heart_at + Vector2(-r * 0.95, -r * 0.3), r, face_color)
	draw_circle(heart_at + Vector2(r * 0.95, -r * 0.3), r, face_color)
	draw_colored_polygon(PackedVector2Array([
		heart_at + Vector2(-r * 1.9, -r * 0.05),
		heart_at + Vector2(r * 1.9, -r * 0.05),
		heart_at + Vector2(0.0, r * 1.7),
	]), face_color)


func _rounded(rect: Rect2, radius: float, color: Color) -> void:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	draw_rect(Rect2(rect.position + Vector2(r, 0.0), Vector2(rect.size.x - r * 2.0, rect.size.y)), color)
	draw_rect(Rect2(rect.position + Vector2(0.0, r), Vector2(rect.size.x, rect.size.y - r * 2.0)), color)
	for corner: Vector2 in [Vector2(r, r), Vector2(rect.size.x - r, r),
			Vector2(r, rect.size.y - r), Vector2(rect.size.x - r, rect.size.y - r)]:
		draw_circle(rect.position + corner, r, color)
