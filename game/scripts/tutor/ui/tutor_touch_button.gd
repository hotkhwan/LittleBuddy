extends Button

## Compact visible faces retain the original child-sized interaction area.
## The full-screen SafeArea parent never clips these transparent hit margins.
var touch_size: float = 0.0

func _has_point(point: Vector2) -> bool:
	var hit_size := Vector2(maxf(size.x, touch_size), maxf(size.y, touch_size))
	return Rect2((size - hit_size) * 0.5, hit_size).has_point(point)
