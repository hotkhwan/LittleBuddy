extends Control
class_name StarIcon

## Small hand-drawn 5-point star for the star counter -- no external art
## dependency, just a `_draw()` polygon computed from `size`. Keeps the
## child-facing UI a step above a plain "* N" text glyph without needing any
## bundled image.

@export var star_color: Color = Color(1.0, 0.82, 0.2)
@export var outline_color: Color = Color(0.8, 0.58, 0.05)
@export var outline_width: float = 3.0


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var points: PackedVector2Array = _star_points()
	if points.size() < 3:
		return
	draw_colored_polygon(points, star_color)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, outline_color, outline_width, true)


func _star_points() -> PackedVector2Array:
	var center: Vector2 = size * 0.5
	var outer_radius: float = minf(size.x, size.y) * 0.5
	var inner_radius: float = outer_radius * 0.42
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(10):
		var radius: float = outer_radius if i % 2 == 0 else inner_radius
		var angle: float = deg_to_rad(-90.0 + i * 36.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points
