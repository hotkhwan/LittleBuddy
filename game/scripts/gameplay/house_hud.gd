extends Control

## The child-facing chrome for a Chapter 3 level: what to do, how far through we
## are, how many stars there are, and the way out.
##
## Built in code rather than as a `.tscn` so it can be added to whatever
## `CanvasLayer` the world already has without either agent owning a scene file
## the other might be editing. It is deliberately small: a pre-reader gets a
## short spoken prompt and four touchable things, not a dashboard.
##
## ## Rules from CLAUDE.md that this file is where they become visible
##
##   * No red anywhere, no `#000000`, no score, no percentage, no timer.
##   * The un-earned progress dot is a warm ghost (`#E8DCC8`), never grey and
##     never an empty slot.
##   * **Next is always there while a task is running.** It is the escape hatch:
##     it completes nothing, costs nothing, blames nobody, and simply moves on.
##   * Speak is HIDDEN, not greyed, when there is nothing to speak to. A child
##     poking a dead button learns the wrong lesson.

## The locked palette (SLICE_CONTRACT §7 / ART_BIBLE).
const CREAM: Color = Color("#FFF6E5")
const DUSTY_BLUE: Color = Color("#9AC0D9")
const SOFT_PINK: Color = Color("#FFC1CC")
const MINT: Color = Color("#A8E6CF")
const LAVENDER: Color = Color("#D6C7F0")
const INK: Color = Color("#59422B")
const STAR_GOLD: Color = Color("#FFC73D")
const STAR_GHOST: Color = Color("#E8DCC8")

const PROMPT_FONT_SIZE: int = 42
const HINT_FONT_SIZE: int = 27
const CAPTION_FONT_SIZE: int = 24
const BUTTON_FONT_SIZE: int = 30
const STAR_FONT_SIZE: int = 34

const DOT_SIZE: float = 26.0
const DOT_GAP: float = 12.0

const ENCOURAGEMENT_SEC: float = 1.8

signal skip_pressed()
signal speak_pressed()

var _prompt: Label = null
var _hint: Label = null
var _caption: Label = null
var _stars: Label = null
var _encouragement: Label = null
var _dots: HBoxContainer = null
var _next_button: Button = null
var _speak_button: Button = null

var _total: int = 0
var _current: int = 0
var _done: Dictionary = {}
var _built: bool = false


func _ready() -> void:
	build()


## Idempotent, and called from every public method: `_ready()` does not fire for
## a node added to the root in the headless runner.
func build() -> void:
	if _built:
		return
	_built = true
	name = "HouseHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_caption = _add_label("Caption", CAPTION_FONT_SIZE, LAVENDER)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_caption.offset_left = -400.0
	_caption.offset_top = 30.0
	_caption.offset_right = -36.0
	_caption.offset_bottom = 120.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption.visible = false

	_prompt = _add_label("Prompt", PROMPT_FONT_SIZE, CREAM)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_prompt.offset_left = 150.0
	_prompt.offset_top = 132.0
	_prompt.offset_right = -150.0
	_prompt.offset_bottom = 232.0
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_hint = _add_label("ThaiHint", HINT_FONT_SIZE, SOFT_PINK)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_left = 150.0
	_hint.offset_top = 236.0
	_hint.offset_right = -150.0
	_hint.offset_bottom = 288.0
	_hint.visible = false

	_encouragement = _add_label("Encouragement", PROMPT_FONT_SIZE, MINT)
	_encouragement.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_encouragement.offset_left = -300.0
	_encouragement.offset_top = 300.0
	_encouragement.offset_right = 300.0
	_encouragement.offset_bottom = 380.0
	_encouragement.visible = false

	_stars = _add_label("StarCount", STAR_FONT_SIZE, STAR_GOLD)
	_stars.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_stars.offset_left = 36.0
	_stars.offset_top = 26.0
	_stars.offset_right = 260.0
	_stars.offset_bottom = 84.0
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stars.text = "★ 0"

	_dots = HBoxContainer.new()
	_dots.name = "ProgressDots"
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.add_theme_constant_override("separation", int(DOT_GAP))
	_dots.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_dots.offset_left = 38.0
	_dots.offset_top = 92.0
	_dots.offset_right = 600.0
	_dots.offset_bottom = 92.0 + DOT_SIZE
	add_child(_dots)

	_next_button = _add_button("NextButton", "Next", DUSTY_BLUE)
	_next_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_next_button.offset_left = -260.0
	_next_button.offset_top = -126.0
	_next_button.offset_right = -36.0
	_next_button.offset_bottom = -34.0
	_next_button.pressed.connect(_on_next_pressed)
	_next_button.visible = false

	_speak_button = _add_button("SpeakButton", "Speak", SOFT_PINK)
	_speak_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_speak_button.offset_left = -112.0
	_speak_button.offset_top = -126.0
	_speak_button.offset_right = 112.0
	_speak_button.offset_bottom = -34.0
	_speak_button.pressed.connect(_on_speak_pressed)
	_speak_button.visible = false


## -- Prompt --------------------------------------------------------------------

func set_prompt(text: String, thai_hint: String = "") -> void:
	build()
	_prompt.text = text
	_hint.text = thai_hint
	_hint.visible = not thai_hint.strip_edges().is_empty()


func get_prompt() -> String:
	build()
	return _prompt.text


func set_caption(text: String) -> void:
	build()
	_caption.text = text
	_caption.visible = not text.strip_edges().is_empty()


func show_encouragement(text: String) -> void:
	build()
	if text.strip_edges().is_empty():
		return
	_encouragement.text = text
	_encouragement.visible = true
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.create_timer(ENCOURAGEMENT_SEC).timeout.connect(hide_encouragement, CONNECT_ONE_SHOT)


func hide_encouragement() -> void:
	build()
	_encouragement.visible = false


## -- Progress ------------------------------------------------------------------

## One dot per task. A dot is a *place in the story*, never a mark out of ten:
## a skipped task fills its dot exactly like a completed one.
func configure_progress(total: int) -> void:
	build()
	_total = maxi(0, total)
	_current = 0
	_done = {}
	for child: Node in _dots.get_children():
		_dots.remove_child(child)
		child.free()
	for index: int in range(_total):
		var dot: Panel = Panel.new()
		dot.name = "Dot%d" % index
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", _dot_style(STAR_GHOST))
		_dots.add_child(dot)
	_dots.visible = _total > 0


func set_current(index: int) -> void:
	build()
	_current = clampi(index, 0, _total)
	_refresh_dots()


func mark_current_done() -> void:
	build()
	if _current >= 1:
		_done[_current] = true
	_refresh_dots()


func clear_progress() -> void:
	configure_progress(0)


func get_total() -> int:
	build()
	return _total


## How many dots are filled. Used by the tests as the child-visible measure of
## "did the level move forward", which is true for a skip as well as a star.
func get_done_count() -> int:
	build()
	return _done.size()


func _refresh_dots() -> void:
	for index: int in range(_dots.get_child_count()):
		var dot: Panel = _dots.get_child(index) as Panel
		if dot == null:
			continue
		var position_number: int = index + 1
		var color: Color = STAR_GHOST
		if _done.has(position_number):
			color = STAR_GOLD
		elif position_number == _current:
			color = MINT
		dot.add_theme_stylebox_override("panel", _dot_style(color))


## -- Stars ---------------------------------------------------------------------

func set_stars(total: int) -> void:
	build()
	_stars.text = "★ %d" % maxi(0, total)


func get_star_text() -> String:
	build()
	return _stars.text


## -- Buttons -------------------------------------------------------------------

func set_skip_visible(value: bool) -> void:
	build()
	_next_button.visible = value


func is_skip_visible() -> bool:
	build()
	return _next_button.visible


func set_speak_visible(value: bool) -> void:
	build()
	_speak_button.visible = value


func is_speak_visible() -> bool:
	build()
	return _speak_button.visible


## Everything off, for an overlay (the summary) or the end of a level.
func set_play_chrome_visible(value: bool) -> void:
	build()
	_prompt.visible = value
	_hint.visible = value and not _hint.text.strip_edges().is_empty()
	_dots.visible = value and _total > 0
	_caption.visible = value and not _caption.text.strip_edges().is_empty()
	_stars.visible = value
	if not value:
		_next_button.visible = false
		_speak_button.visible = false
		_encouragement.visible = false


func _on_next_pressed() -> void:
	skip_pressed.emit()


func _on_speak_pressed() -> void:
	speak_pressed.emit()


## -- Construction helpers ------------------------------------------------------

func _add_label(node_name: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# An ink outline rather than a shadow: it keeps the text readable over a
	# cream wall and a dusty-blue floor alike, and ink is the palette's darkest
	# colour -- `#000000` is banned everywhere.
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 10)
	add_child(label)
	return label


func _add_button(node_name: String, text: String, tint: Color) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, _button_style(tint, state == "pressed"))
	add_child(button)
	return button


func _button_style(tint: Color, pressed: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = tint.darkened(0.08) if pressed else tint
	style.set_corner_radius_all(28)
	style.set_border_width_all(3)
	style.border_color = CREAM
	return style


func _dot_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(DOT_SIZE * 0.5))
	return style
