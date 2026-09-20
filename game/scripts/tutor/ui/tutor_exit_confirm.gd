extends Control

## "Stop the lesson?" -- the small confirm behind the classroom's Exit button.
## Two answers, and the safe one (Keep going) is the big mint one, first, so a
## child who wandered onto Exit lands back in the lesson. No red, no "quit",
## nothing is lost either way: the quota mirror has already counted the
## minutes, and the lesson picks up at its next step tomorrow.

const Palette := preload("res://scripts/ui/palette.gd")

signal keep_going()
signal stop_confirmed()

const CARD_WIDTH: float = 540.0
const CARD_HEIGHT: float = 300.0
## The card sits at the LEFT, beside Aliz rather than over her: she stays in
## view while the child decides, and the question reads as hers.
## `tutor_scene.gd::face_screen_rect()` is what the layout test checks against.
const CARD_LEFT: float = 44.0
const CARD_DROP: float = 40.0
const TITLE_TEXT: String = "Stop the lesson?"
const KEEP_TEXT: String = "Keep going"
const STOP_TEXT: String = "Yes, stop"

var _built: bool = false
var _keep: Button = null
var _stop: Button = null


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	name = "ExitConfirm"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var scrim: ColorRect = ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Palette.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var card: PanelContainer = PanelContainer.new()
	card.name = "Card"
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Palette.CREAM
	style.border_color = Palette.deep(Palette.PEACH)
	style.set_border_width_all(4)
	style.set_corner_radius_all(36)
	style.content_margin_left = 40.0
	style.content_margin_right = 40.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 26.0
	card.add_theme_stylebox_override("panel", style)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	card.offset_left = CARD_LEFT
	card.offset_right = CARD_LEFT + CARD_WIDTH
	card.offset_top = -CARD_HEIGHT * 0.5 + CARD_DROP
	card.offset_bottom = CARD_HEIGHT * 0.5 + CARD_DROP
	add_child(card)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = TITLE_TEXT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Palette.INK)
	column.add_child(title)

	_keep = _button("KeepButton", KEEP_TEXT, Palette.MINT, 88.0, 32)
	_keep.pressed.connect(_on_keep)
	column.add_child(_keep)
	_stop = _button("StopButton", STOP_TEXT, Palette.PEACH, 72.0, 28)
	_stop.pressed.connect(_on_stop)
	column.add_child(_stop)


func open() -> void:
	build()
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Where the card lands in a viewport of `viewport_size`.
static func card_rect(viewport_size: Vector2) -> Rect2:
	return Rect2(CARD_LEFT, viewport_size.y * 0.5 - CARD_HEIGHT * 0.5 + CARD_DROP, CARD_WIDTH, CARD_HEIGHT)


func press_keep() -> void:
	_on_keep()


func press_stop() -> void:
	_on_stop()


func _on_keep() -> void:
	close()
	keep_going.emit()


func _on_stop() -> void:
	close()
	stop_confirmed.emit()


func _button(node_name: String, text: String, tint: Color, height: float, font_size: int) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(400.0, height)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Palette.INK)
	button.add_theme_color_override("font_hover_color", Palette.INK)
	button.add_theme_color_override("font_pressed_color", Palette.INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = tint.darkened(0.08) if state == "pressed" else tint
		style.set_corner_radius_all(int(height * 0.5))
		style.set_border_width_all(3)
		style.border_color = Palette.CREAM
		button.add_theme_stylebox_override(state, style)
	return button
