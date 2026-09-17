@tool
extends Control

## The Free Play icon: a house.
##
## Every other glyph in the game comes from `icon_glyph.gd` and the bundled
## Nieobie pack (CC0), and that is still the rule. The pack has no house, and the
## menu needs two pictures a four-year-old can tell apart without reading either
## caption -- a triangle that means "carry on with the story" and a house that
## means "go in and play". Colour alone would not do it.
##
## So this is a placeholder in exactly the sense `toddler_view.gd` is: drawn in
## code, in the locked palette, sized on the SAME 86% optical box `icon_glyph.gd`
## re-boxes its icons onto, so the two sit at matching weight inside matching
## 300px buttons. When the art pass produces a house icon, this file is deleted
## and the node becomes an `IconGlyph` with one more enum value.
##
## Rounded forms only, per the art bible: the body and the doorway are
## rounded rectangles and the roof is the only straight edge.
##
## Purely decorative -- `MOUSE_FILTER_IGNORE`, so it never eats the press meant
## for the `Button` it sits inside.

## The house itself. Ink by default; never black, never red.
@export var tint: Color = Color(0.349, 0.259, 0.169):
	set(value):
		tint = value
		queue_redraw()

## What the doorway is knocked out in -- the colour of the button face behind it,
## so the opening reads as a hole rather than as a second shape.
@export var face_color: Color = Color(0.984, 0.820, 0.675):
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
	var origin: Vector2 = Vector2((size.x - box) * 0.5, (size.y - box) * 0.5)

	var roof_height: float = box * 0.42
	var eave: float = box * 0.03
	draw_colored_polygon(
		PackedVector2Array([
			origin + Vector2(box * 0.5, 0.0),
			origin + Vector2(box + eave, roof_height),
			origin + Vector2(-eave, roof_height),
		]),
		tint
	)

	var body: Rect2 = Rect2(
		origin + Vector2(box * 0.14, roof_height - box * 0.03),
		Vector2(box * 0.72, box * 0.61)
	)
	_draw_rounded(body, box * 0.10, tint)

	# Flush with the bottom of the body, so the house stands on the ground
	# instead of floating a door in the middle of a wall.
	var door_width: float = box * 0.22
	var door_height: float = box * 0.34
	var door: Rect2 = Rect2(
		Vector2(body.position.x + (body.size.x - door_width) * 0.5,
				body.end.y - door_height),
		Vector2(door_width, door_height)
	)
	_draw_rounded(door, box * 0.06, face_color)


func _draw_rounded(rect: Rect2, radius: float, color: Color) -> void:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	if r <= 0.0:
		draw_rect(rect, color)
		return
	draw_rect(
		Rect2(rect.position + Vector2(r, 0.0), Vector2(rect.size.x - r * 2.0, rect.size.y)), color
	)
	draw_rect(
		Rect2(rect.position + Vector2(0.0, r), Vector2(rect.size.x, rect.size.y - r * 2.0)), color
	)
	for corner: Vector2 in [
		Vector2(r, r),
		Vector2(rect.size.x - r, r),
		Vector2(r, rect.size.y - r),
		Vector2(rect.size.x - r, rect.size.y - r),
	]:
		draw_circle(rect.position + corner, r, color)
