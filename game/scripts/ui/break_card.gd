extends Control

## The break card: "Great job today!"
##
## Shown by a director at a SAFE POINT once the play-session clock
## (`play_session.gd`) has passed the grown-up's threshold -- never mid-activity,
## never over a close-up, never while Bunny is in Aliz's arms. It is a soft
## suggestion, not a lock: the biggest button is Keep Playing, nothing counts
## down, nothing is lost, and Home saves before it leaves. The owner's copy,
## exactly:
##
##   title   "Great job today!"
##   body    "Let's take a little break."
##           "Come back soon for more Little Days!"
##   Home         peach, with the house glyph the title screen uses
##   Keep Playing mint, the biggest
##
## The helper line under the title (the family's language, `Localization`) is
## shown when there is one for it and left out when there is not. On open the
## card asks `/root/Voice` for the two lines by id (`aliz_023_break`,
## `aliz_024_come_back`) and, when there is no such director, says the same
## English through `TtsService`. Both are looked up by name and both are
## optional: a build with neither shows a silent card.
##
## Built in code like `pause_menu.gd`, `build()` idempotent, no `SceneTree`
## pause, every tap behind it eaten (`MOUSE_FILTER_STOP`). What the buttons DO
## belongs to the host (`break_host.gd`, `baby_room.gd`): this card only says
## which one was pressed.

const Palette := preload("res://scripts/ui/palette.gd")
const HouseGlyphScript := preload("res://scenes/main/house_glyph.gd")
const Localization := preload("res://scripts/localization/localization.gd")

const CARD_WIDTH: float = 640.0
const CARD_HEIGHT: float = 520.0
const TITLE_FONT_SIZE: int = 48
const HELPER_FONT_SIZE: int = 26
const BODY_FONT_SIZE: int = 30
const BUTTON_FONT_SIZE: int = 34
const SMALL_BUTTON_FONT_SIZE: int = 30
## ART_BIBLE §8: 240 px is the floor for a child's tap target. Keep Playing is
## the biggest thing on the card on purpose.
const KEEP_BUTTON_WIDTH: float = 460.0
const KEEP_BUTTON_HEIGHT: float = 108.0
const HOME_BUTTON_WIDTH: float = 400.0
const HOME_BUTTON_HEIGHT: float = 88.0
const GAP: float = 16.0

const TITLE_TEXT: String = "Great job today!"
const BODY_LINE_1: String = "Let's take a little break."
const BODY_LINE_2: String = "Come back soon for more Little Days!"
const HOME_TEXT: String = "Home"
const KEEP_PLAYING_TEXT: String = "Keep Playing"

## Voice line ids (Agent V's director) and the English each one says.
const VOICE_BREAK_ID: String = "aliz_023_break"
const VOICE_COME_BACK_ID: String = "aliz_024_come_back"
const VOICE_BREAK_ENGLISH: String = "Great job today! Let's take a little break."
const VOICE_COME_BACK_ENGLISH: String = BODY_LINE_2

signal keep_playing_pressed()
signal home_pressed()
signal opened()
signal closed()

var _built: bool = false
var _scrim: ColorRect = null
var _card: PanelContainer = null
var _title: Label = null
var _helper: Label = null
var _body_1: Label = null
var _body_2: Label = null
var _keep: Button = null
var _home: Button = null
## Injectable voices, for a test. Null means "look up by name".
var _voice: Object = null
var _tts: Object = null
var _voice_injected: bool = false
## What was asked of the voices on the last open, in order. Tests.
var _spoken: Array = []


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
	card_style.border_color = Palette.deep(Palette.MINT)
	card_style.set_border_width_all(4)
	card_style.set_corner_radius_all(40)
	card_style.content_margin_left = 44.0
	card_style.content_margin_right = 44.0
	card_style.content_margin_top = 34.0
	card_style.content_margin_bottom = 36.0
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

	_title = _label("Title", TITLE_TEXT, TITLE_FONT_SIZE, Palette.INK)
	column.add_child(_title)

	_helper = _label("Helper", "", HELPER_FONT_SIZE, Palette.INK_SOFT)
	_helper.visible = false
	column.add_child(_helper)

	_body_1 = _label("Body1", BODY_LINE_1, BODY_FONT_SIZE, Palette.INK)
	column.add_child(_body_1)
	_body_2 = _label("Body2", BODY_LINE_2, BODY_FONT_SIZE, Palette.INK_SOFT)
	column.add_child(_body_2)

	var spacer: Control = Control.new()
	spacer.name = "Spacer"
	spacer.custom_minimum_size = Vector2(0.0, 6.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_keep = _button("KeepPlayingButton", KEEP_PLAYING_TEXT, Palette.MINT,
			KEEP_BUTTON_WIDTH, KEEP_BUTTON_HEIGHT, BUTTON_FONT_SIZE)
	_keep.pressed.connect(_on_keep_playing)
	column.add_child(_keep)

	_home = _button("HomeButton", HOME_TEXT, Palette.HOME_CHROME,
			HOME_BUTTON_WIDTH, HOME_BUTTON_HEIGHT, SMALL_BUTTON_FONT_SIZE)
	_home.pressed.connect(_on_home)
	# The house from the title screen, so Home reads without the word.
	var house: Control = HouseGlyphScript.new()
	house.name = "HouseGlyph"
	house.set("tint", Palette.INK)
	house.set("face_color", Palette.HOME_CHROME)
	house.set("window_color", Palette.HOME_CHROME)
	house.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	house.offset_left = 26.0
	house.offset_right = 26.0 + 56.0
	house.offset_top = -28.0
	house.offset_bottom = 28.0
	house.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(house)
	column.add_child(_home)


## -- Open / close ----------------------------------------------------------------

func open() -> void:
	build()
	if visible:
		return
	_refresh_helper()
	visible = true
	_say_lines()
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


## The two controls, for a test or a harness: `keep`, `home`.
func get_buttons() -> Dictionary:
	build()
	return {"keep": _keep, "home": _home}


func get_title_text() -> String:
	build()
	return _title.text


func get_body_lines() -> PackedStringArray:
	build()
	return PackedStringArray([_body_1.text, _body_2.text])


func get_helper_text() -> String:
	build()
	return _helper.text if _helper.visible else ""


## What the card asked the voices to say on its last open, in order. Tests.
func get_spoken() -> Array:
	return _spoken.duplicate()


## -- Voice -------------------------------------------------------------------------

## Both optional; a test hands in doubles. `voice` answers `say(id)`; `tts`
## answers `speak(text, interrupt)`.
func set_voices(voice: Object, tts: Object) -> void:
	_voice = voice
	_tts = tts
	_voice_injected = true


func _say_lines() -> void:
	_spoken.clear()
	var voice: Object = _voice if _voice_injected else _find("Voice")
	if voice != null and is_instance_valid(voice) and voice.has_method("say"):
		voice.call("say", VOICE_BREAK_ID)
		voice.call("say", VOICE_COME_BACK_ID)
		_spoken.append(VOICE_BREAK_ID)
		_spoken.append(VOICE_COME_BACK_ID)
		return
	var tts: Object = _tts if _voice_injected else _find("TtsService")
	if tts != null and is_instance_valid(tts) and tts.has_method("speak"):
		tts.call("speak", VOICE_BREAK_ENGLISH, true)
		tts.call("speak", VOICE_COME_BACK_ENGLISH, false)
		_spoken.append(VOICE_BREAK_ENGLISH)
		_spoken.append(VOICE_COME_BACK_ENGLISH)


func _find(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(autoload_name))


## -- Helper line ---------------------------------------------------------------------

## The family's language under the English title, when the table has it.
func _refresh_helper() -> void:
	var text: String = Localization.helper_line(TITLE_TEXT)
	_helper.text = text
	_helper.visible = not text.strip_edges().is_empty()
	_helper.text_direction = Control.TEXT_DIRECTION_RTL if Localization.is_rtl() \
			else Control.TEXT_DIRECTION_AUTO


## -- Buttons ---------------------------------------------------------------------------

func _on_keep_playing() -> void:
	keep_playing_pressed.emit()
	close()


func _on_home() -> void:
	home_pressed.emit()


func _label(node_name: String, text: String, font_size: int, tint: Color) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(node_name: String, text: String, tint: Color, width: float, height: float,
		font_size: int) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, height)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
