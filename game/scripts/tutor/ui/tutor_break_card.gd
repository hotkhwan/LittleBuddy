extends Control

## THE BREAK SCREEN. Shown when the lesson is finished for today -- the quota
## provider said `expired` at a safe boundary, or the lesson completed and the
## daily five minutes are used -- and it says so in the warmest possible way:
##
##     Great job today!
##     Come back tomorrow for more Little Days!
##     Keep playing with Bunny!
##
## with **Continue Playing** (back to the house's Free Play) first and biggest,
## and **Home**. When the lesson completed with time still left, a third
## button, **Learn again**, is offered as well. No timer, no lock icon, no
## countdown: a four-year-old is told the day's lesson is done, not that they
## ran out. Never traps: both exits always work, and it never pauses the tree.

const Palette := preload("res://scripts/ui/palette.gd")
const HouseGlyphScript := preload("res://scenes/main/house_glyph.gd")

signal continue_playing_pressed()
signal home_pressed()
signal learn_again_pressed()

const CARD_WIDTH: float = 720.0
const CARD_HEIGHT: float = 520.0
const TITLE_TEXT: String = "Great job today!"
const LINE_TOMORROW: String = "Come back tomorrow for more Little Days!"
const LINE_BUNNY: String = "Keep playing with Bunny!"
const CONTINUE_TEXT: String = "Continue Playing"
const HOME_TEXT: String = "Home"
const AGAIN_TEXT: String = "Learn again"

var _built: bool = false
var _title: Label = null
var _line_tomorrow: Label = null
var _line_bunny: Label = null
var _continue: Button = null
var _home: Button = null
var _again: Button = null
var _stars: HBoxContainer = null


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	name = "BreakCard"
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
	style.border_color = Palette.deep(Palette.MINT)
	style.set_border_width_all(5)
	style.set_corner_radius_all(40)
	style.content_margin_left = 44.0
	style.content_margin_right = 44.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 34.0
	card.add_theme_stylebox_override("panel", style)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -CARD_WIDTH * 0.5
	card.offset_right = CARD_WIDTH * 0.5
	card.offset_top = -CARD_HEIGHT * 0.5
	card.offset_bottom = CARD_HEIGHT * 0.5
	add_child(card)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)

	_stars = HBoxContainer.new()
	_stars.name = "Stars"
	_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	_stars.add_theme_constant_override("separation", 10)
	column.add_child(_stars)
	for i: int in range(3):
		var star: Control = (load("res://scripts/progression/icon_glyph.gd") as GDScript).new()
		star.name = "Star%d" % i
		star.custom_minimum_size = Vector2(54.0, 54.0)
		star.set("glyph", 0)
		star.set("tint", Palette.STAR_EARNED)
		_stars.add_child(star)

	_title = _label("Title", TITLE_TEXT, 48, Palette.INK)
	column.add_child(_title)
	_line_tomorrow = _label("LineTomorrow", LINE_TOMORROW, 28, Palette.INK_SOFT)
	column.add_child(_line_tomorrow)
	_line_bunny = _label("LineBunny", LINE_BUNNY, 28, Palette.INK_SOFT)
	column.add_child(_line_bunny)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	column.add_child(spacer)

	_continue = _button("ContinueButton", CONTINUE_TEXT, Palette.MINT, 100.0, 34)
	_continue.pressed.connect(func() -> void: continue_playing_pressed.emit())
	column.add_child(_continue)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)

	_home = _button("HomeButton", HOME_TEXT, Palette.HOME_CHROME, 84.0, 30)
	_home.custom_minimum_size = Vector2(250.0, 84.0)
	_home.pressed.connect(func() -> void: home_pressed.emit())
	var house: Control = HouseGlyphScript.new()
	house.name = "HouseGlyph"
	house.set("tint", Palette.INK)
	house.set("face_color", Palette.HOME_CHROME)
	house.set("window_color", Palette.HOME_CHROME)
	house.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	house.offset_left = 22.0
	house.offset_top = 14.0
	house.offset_right = 74.0
	house.offset_bottom = -14.0
	_home.add_child(house)
	row.add_child(_home)

	_again = _button("AgainButton", AGAIN_TEXT, Palette.LAVENDER, 84.0, 30)
	_again.custom_minimum_size = Vector2(250.0, 84.0)
	_again.pressed.connect(func() -> void: learn_again_pressed.emit())
	_again.visible = false
	row.add_child(_again)


## Shows the card. `time_left` true offers "Learn again" and softens the
## tomorrow line, because the day is not actually over.
func open(time_left: bool = false) -> void:
	build()
	_again.visible = time_left
	_line_tomorrow.text = "Want to learn more, or go and play?" if time_left else LINE_TOMORROW
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func offers_learn_again() -> bool:
	return _again != null and _again.visible


func press_continue() -> void:
	continue_playing_pressed.emit()


func press_home() -> void:
	home_pressed.emit()


func press_learn_again() -> void:
	if offers_learn_again():
		learn_again_pressed.emit()


func texts() -> Array:
	return [_title.text, _line_tomorrow.text, _line_bunny.text, _continue.text, _home.text]


func _label(node_name: String, text: String, font_size: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(node_name: String, text: String, tint: Color, height: float, font_size: int) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(520.0, height)
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
