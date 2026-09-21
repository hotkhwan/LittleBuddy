extends RefCounted

## Shared roles in the 1024-high UI design space. Keep the system font and
## HelperFont fallback chain: Thai tone marks need natural font line metrics.
const DISPLAY: int = 48
const SECTION: int = 32
const BODY: int = 28
const HELPER: int = 22
const BUTTON: int = 28
const COUNT: int = 32

static func apply(label: Label, role: int, wrap: bool = true) -> void:
	label.add_theme_font_size_override("font_size", role)
	label.add_theme_constant_override("line_spacing", 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
