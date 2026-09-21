extends RefCounted

## Shared surface treatment, independent of routing and input. Dimensions are
## design-space pixels; callers continue to own accessible hit rectangles.
const Palette := preload("res://scripts/ui/palette.gd")
const RADIUS: int = 28
const INSET: float = 24.0

static func panel(tint: Color = Palette.CREAM, radius: int = RADIUS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = Palette.CREAM.lightened(0.55)
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(Palette.INK, 0.13)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 6)
	style.content_margin_left = INSET
	style.content_margin_right = INSET
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style

static func button(control: Button, tint: Color, radius: int = RADIUS) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := panel(tint, radius)
		if state == "pressed":
			style.bg_color = Palette.deep(tint)
			style.shadow_size = 2
			style.shadow_offset = Vector2(0, 2)
		elif state == "disabled":
			style.bg_color = tint.lerp(Palette.CREAM, 0.6)
			style.shadow_size = 0
		elif state == "focus":
			style.border_color = Palette.deep(Palette.MINT)
		control.add_theme_stylebox_override(state, style)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		control.add_theme_color_override(state, Palette.INK)
	control.add_theme_color_override("font_disabled_color", Color(Palette.INK, 0.55))
