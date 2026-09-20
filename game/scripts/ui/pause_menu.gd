extends Control

## The friendly "take a break?" card behind the HUD's Home button.
##
## Three things a child (or the grown-up beside them) can do, and nothing else:
##
##   * **Continue** -- the biggest, mint, first. Closing the card is the thing
##     most presses of Home turn out to mean, so it is the easiest press here.
##   * **Home** -- peach, with the same house the title screen uses, so the way
##     out is the same picture as the way in. The HUD decides what "home" does
##     (it asks the world to `leave_to_home()`); this card only says it was asked.
##   * **Grown-ups** -- lavender (`PARENT_CHROME`), smaller, last. It leads to the
##     existing parental gate, and a child should not be drawn to it.
##
## No red, no "quit", no "are you sure you want to lose progress": nothing is
## lost -- stars are saved as they are earned -- so the card never threatens.
## It eats every tap behind it (`MOUSE_FILTER_STOP`) so the room cannot be
## walked while it is up, and it never pauses the `SceneTree`, so nothing in the
## world is left frozen if the card is dismissed from somewhere unexpected.
##
## Built in code, like `house_hud.gd`, and `build()` is idempotent for the
## headless runner.

const Palette := preload("res://scripts/ui/palette.gd")
const HouseGlyphScript := preload("res://scenes/main/house_glyph.gd")

const CARD_WIDTH: float = 560.0
const CARD_HEIGHT: float = 470.0
const TITLE_FONT_SIZE: int = 40
const BUTTON_FONT_SIZE: int = 32
const SMALL_FONT_SIZE: int = 27
## ART_BIBLE §8: 240 px is the floor for a child's tap target.
const BUTTON_WIDTH: float = 400.0
const BUTTON_HEIGHT: float = 96.0
const SMALL_BUTTON_HEIGHT: float = 76.0
const GAP: float = 18.0

const TITLE_TEXT: String = "Take a break?"
const CONTINUE_TEXT: String = "Continue"
const HOME_TEXT: String = "Home"
const SETTINGS_TEXT: String = "Grown-ups"

signal continue_pressed()
signal home_pressed()
signal settings_pressed()
signal opened()
signal closed()

var _built: bool = false
var _scrim: ColorRect = null
var _card: PanelContainer = null
var _title: Label = null
var _continue: Button = null
var _home: Button = null
var _settings: Button = null


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	name = "PauseMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Palette.SCRIM
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_style: StyleBoxFlat = StyleBoxFlat.new()
	card_style.bg_color = Palette.CREAM
	card_style.border_color = Palette.deep(Palette.PEACH)
	card_style.set_border_width_all(4)
	card_style.set_corner_radius_all(36)
	card_style.content_margin_left = 40.0
	card_style.content_margin_right = 40.0
	card_style.content_margin_top = 30.0
	card_style.content_margin_bottom = 34.0
	_card.add_theme_stylebox_override("panel", card_style)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.offset_left = -CARD_WIDTH * 0.5
	_card.offset_right = CARD_WIDTH * 0.5
	_card.offset_top = -CARD_HEIGHT * 0.5
	_card.offset_bottom = CARD_HEIGHT * 0.5
	add_child(_card)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", int(GAP))
	_card.add_child(column)

	_title = Label.new()
	_title.name = "Title"
	_title.text = TITLE_TEXT
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", Palette.INK)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)

	_continue = _button("ContinueButton", CONTINUE_TEXT, Palette.MINT, BUTTON_HEIGHT, BUTTON_FONT_SIZE)
	_continue.pressed.connect(_on_continue)
	column.add_child(_continue)

	_home = _button("HomeButton", HOME_TEXT, Palette.HOME_CHROME, BUTTON_HEIGHT, BUTTON_FONT_SIZE)
	_home.pressed.connect(_on_home)
	# The house from the title screen, at the left of the word, so the button
	# reads without the word.
	var house: Control = HouseGlyphScript.new()
	house.name = "HouseGlyph"
	house.set("tint", Palette.INK)
	house.set("face_color", Palette.HOME_CHROME)
	house.set("window_color", Palette.HOME_CHROME)
	house.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	house.offset_left = 26.0
	house.offset_right = 26.0 + 60.0
	house.offset_top = -30.0
	house.offset_bottom = 30.0
	_home.add_child(house)
	column.add_child(_home)

	_settings = _button("SettingsButton", SETTINGS_TEXT, Palette.PARENT_CHROME,
			SMALL_BUTTON_HEIGHT, SMALL_FONT_SIZE)
	_settings.pressed.connect(_on_settings)
	column.add_child(_settings)


func open() -> void:
	build()
	if visible:
		return
	visible = true
	opened.emit()


func close() -> void:
	build()
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	build()
	return visible


## The three controls, for a test or a harness: `continue`, `home`, `settings`.
func get_buttons() -> Dictionary:
	build()
	return {"continue": _continue, "home": _home, "settings": _settings}


func get_title_text() -> String:
	build()
	return _title.text


func _on_continue() -> void:
	continue_pressed.emit()
	close()


func _on_home() -> void:
	home_pressed.emit()


func _on_settings() -> void:
	settings_pressed.emit()


func _button(node_name: String, text: String, tint: Color, height: float, font_size: int) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, height)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Palette.INK)
	button.add_theme_color_override("font_hover_color", Palette.INK)
	button.add_theme_color_override("font_pressed_color", Palette.INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Palette.deep(tint) if state == "pressed" else tint
		style.border_color = Palette.deep(tint)
		style.set_border_width_all(3)
		style.set_corner_radius_all(int(height * 0.5))
		button.add_theme_stylebox_override(state, style)
	return button
