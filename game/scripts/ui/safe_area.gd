class_name SafeArea
extends Control
## Full-rect container that insets itself to the device safe area.
##
## Put the child-facing UI under this node so nothing lands under a notch,
## Dynamic Island, rounded corner or home indicator. The insets come from
## `DisplayServer.get_display_safe_area()` -- no per-device constants, so this
## works for any iPhone or iPad without layout assumptions about either.
##
## On desktop the platform safe area is reported in screen coordinates rather
## than window coordinates, so it is deliberately ignored there and only the
## minimum cosmetic margin applies. That keeps the macOS editor/run view
## identical to what it was before.

## Never let UI hug the bezel, even where the platform reports no unsafe area.
const MIN_MARGIN: float = 16.0

## Extra breathing room on the two short edges in landscape, where the notch /
## Dynamic Island and the rounded corners live on a phone.
const MIN_MARGIN_HORIZONTAL: float = 24.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Purely a layout wrapper: it must never eat touches meant for the 3D room.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_safe_area):
		viewport.size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _notification(what: int) -> void:
	# Rotation / multitasking resize / keyboard changes on iOS.
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_apply_safe_area()


func _apply_safe_area() -> void:
	var insets: Vector4 = _compute_insets()
	offset_left = insets.x
	offset_top = insets.y
	offset_right = -insets.z
	offset_bottom = -insets.w


## Returns (left, top, right, bottom) in viewport pixels.
func _compute_insets() -> Vector4:
	var left: float = MIN_MARGIN_HORIZONTAL
	var top: float = MIN_MARGIN
	var right: float = MIN_MARGIN_HORIZONTAL
	var bottom: float = MIN_MARGIN

	if _platform_reports_safe_area():
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window: Vector2i = DisplayServer.window_get_size()
		var viewport_size: Vector2 = get_viewport_rect().size

		if window.x > 0 and window.y > 0 and safe.size.x > 0 and safe.size.y > 0 \
				and viewport_size.x > 0.0 and viewport_size.y > 0.0:
			# The safe area is in physical window pixels; the UI lives in the
			# stretched viewport space, so convert between them.
			var scale_x: float = viewport_size.x / float(window.x)
			var scale_y: float = viewport_size.y / float(window.y)

			left = maxf(left, float(safe.position.x) * scale_x)
			top = maxf(top, float(safe.position.y) * scale_y)
			right = maxf(right, float(window.x - (safe.position.x + safe.size.x)) * scale_x)
			bottom = maxf(bottom, float(window.y - (safe.position.y + safe.size.y)) * scale_y)

	return Vector4(left, top, right, bottom)


func _platform_reports_safe_area() -> bool:
	var platform: String = OS.get_name()
	return platform == "iOS" or platform == "Android"
