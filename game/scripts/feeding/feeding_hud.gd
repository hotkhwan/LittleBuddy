extends CanvasLayer

## The 2D layer over the highchair: prompt bar, star counter, Home, Back, the
## hint pill, the encouragement pill, and the overlay that draws sparkle lines,
## the guided-mode arrow and nothing else.
##
## Built in code so the headless runner can instantiate it without a scene, and
## laid out under a `SafeArea` so nothing lands under a notch. Sits on layer 0,
## BELOW the Baby Room's own `UI` layer (1): the room's grown-up gear, its
## celebration burst and the session summary all stay on top, exactly where a
## parent and a child already expect them.
##
## The two prompt labels are exposed through `set_prompt(english, helper)` only,
## so the Localization service can bind them later without knowing the layout.
##
## Every panel is one of the shared 9-slice frames in `assets/ui/styles/` --
## the same cream panel as the speech bubble, the same peach button as the
## menu's house -- so the highchair looks like the rest of the game rather than
## like a second product. Every colour is a palette token or a derivation.

signal home_pressed()
signal back_pressed()

const _Palette := preload("res://scripts/ui/palette.gd")
const _RatingStar := preload("res://scripts/ui/rating_star.gd")
const _IconGlyph := preload("res://scripts/progression/icon_glyph.gd")
const _SafeArea := preload("res://scripts/ui/safe_area.gd")
const _SubtitleStrip := preload("res://scripts/voice/subtitle_strip.gd")
const _Typography := preload("res://scripts/ui/typography.gd")

const FRAME_PANEL: StyleBox = preload("res://assets/ui/styles/panel_cream.tres")
const FRAME_BUTTON: StyleBox = preload("res://assets/ui/styles/btn_peach.tres")
const FRAME_BUTTON_DOWN: StyleBox = preload("res://assets/ui/styles/btn_peach_down.tres")
const FRAME_HINT: StyleBox = preload("res://assets/ui/styles/small/btn_cream.tres")
const FRAME_ENCOURAGE: StyleBox = preload("res://assets/ui/styles/btn_mint.tres")

## ART_BIBLE.md section 8: a child-facing control is never smaller than this.
const ROUND_BUTTON: float = 200.0
const PROMPT_FONT: int = _Typography.SECTION
const HELPER_FONT: int = _Typography.HELPER
const COUNT_FONT: int = _Typography.COUNT
const HINT_FONT: int = _Typography.BODY
const ENCOURAGE_FONT: int = _Typography.SECTION
const ENCOURAGE_SECONDS: float = 1.8

## Sparkle lines live this long.
const SPARKLE_SECONDS: float = 0.55
## The subtitle pill sits at the bottom centre; the Back button owns the bottom
## left (200 px round + 8 px margin), so the pill keeps clear of it sideways.
const SUBTITLE_BOTTOM_MARGIN: float = 24.0
const SUBTITLE_SIDE_CLEARANCE: float = 232.0

var _safe: Control = null
var _prompt_label: Label = null
var _helper_label: Label = null
var _count_label: Label = null
var _counter_star: TextureRect = null
var _task_star: TextureRect = null
var _hint: PanelContainer = null
var _hint_label: Label = null
var _encourage: PanelContainer = null
var _encourage_label: Label = null
var _home_button: Button = null
var _back_button: Button = null
var _overlay: Control = null
var _built: bool = false
var _encourage_generation: int = 0
var _subtitle: Control = null


func _ready() -> void:
	build()


## Idempotent; callable before `_ready()` for the headless runner.
func build() -> void:
	if _built:
		return
	_built = true
	layer = 0
	name = "FeedingHud"

	_safe = _SafeArea.new()
	_safe.name = "SafeArea"
	_safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)

	_overlay = FeedingOverlay.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_overlay)

	_build_prompt_bar()
	_build_star_counter()
	_build_buttons()
	_build_hint()
	_build_encouragement()
	_build_subtitle()


# ---------------------------------------------------------------------------
# Public surface
# ---------------------------------------------------------------------------

## The English ask on top, the helper line beneath. Empty helper hides the line.
func set_prompt(english: String, helper: String) -> void:
	build()
	_prompt_label.text = english
	# The helper line follows the family's chosen helper language (Agent F's
	# Localization service). `helper` is the authored Thai hint, which stays the
	# Thai answer and the fallback; loaded by path so the HUD still builds
	# without the service.
	var line: String = helper
	var rtl: bool = false
	var loc: Resource = load("res://scripts/localization/localization.gd") \
			if ResourceLoader.exists("res://scripts/localization/localization.gd") else null
	if loc is GDScript and (loc as GDScript).has_method("helper_line"):
		line = String((loc as GDScript).call("helper_line", english, helper))
		if (loc as GDScript).has_method("is_rtl"):
			rtl = bool((loc as GDScript).call("is_rtl"))
	var font_helper: Resource = load("res://scripts/localization/helper_font.gd") \
			if ResourceLoader.exists("res://scripts/localization/helper_font.gd") else null
	if font_helper is GDScript and (font_helper as GDScript).has_method("apply"):
		(font_helper as GDScript).call("apply", _helper_label)
	_helper_label.text = line
	_helper_label.text_direction = Control.TEXT_DIRECTION_RTL if rtl else Control.TEXT_DIRECTION_AUTO
	_helper_label.visible = not line.strip_edges().is_empty()


func get_prompt() -> String:
	build()
	return _prompt_label.text


func get_helper() -> String:
	build()
	return _helper_label.text


func set_star_count(total: int) -> void:
	build()
	_count_label.text = str(maxi(total, 0))


## How much THIS task is still worth: `full` paints a gold star, `half` and
## `guided` paint the half star. Drawn beside the lifetime counter so the child
## can see the star they are working for.
func set_task_credit(credit: String) -> void:
	build()
	var state: int = _RatingStar.State.EARNED
	if credit != "full":
		state = _RatingStar.State.HALF
	_task_star.call("set_state", state)
	_task_star.visible = true


func hide_task_star() -> void:
	build()
	_task_star.visible = false


func pop_task_star() -> void:
	build()
	if not is_inside_tree() or not _task_star.visible:
		return
	_task_star.pivot_offset = _task_star.size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(_task_star, "scale", Vector2.ONE * 1.35, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_task_star, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE)


func get_task_star_state() -> int:
	build()
	return int(_task_star.get("state"))


## A short hint ("Peel it!", "Tap to help!") floating just above a stage point.
func show_hint(text: String, at: Vector2) -> void:
	build()
	_hint_label.text = text
	_hint.visible = true
	move_hint(at)


func move_hint(at: Vector2) -> void:
	build()
	if not _hint.visible:
		return
	var local: Vector2 = at - _safe.global_position
	var hint_size: Vector2 = _hint.get_combined_minimum_size()
	_hint.position = Vector2(local.x - hint_size.x * 0.5, local.y - hint_size.y - 96.0)


func hide_hint() -> void:
	build()
	_hint.visible = false


func is_hint_visible() -> bool:
	build()
	return _hint.visible


func get_hint_text() -> String:
	build()
	return _hint_label.text


## "Great!", "Try the apple!" -- bottom centre, gone again in under two seconds.
func show_encouragement(text: String) -> void:
	build()
	if text.strip_edges().is_empty():
		return
	_encourage_label.text = text
	_encourage.visible = true
	_encourage_generation += 1
	var generation: int = _encourage_generation
	if not is_inside_tree():
		return
	var timer: SceneTreeTimer = get_tree().create_timer(ENCOURAGE_SECONDS)
	timer.timeout.connect(_hide_encouragement_if.bind(generation), CONNECT_ONE_SHOT)


func _hide_encouragement_if(generation: int) -> void:
	if generation == _encourage_generation:
		_encourage.visible = false


func get_encouragement() -> String:
	build()
	return _encourage_label.text if _encourage.visible else ""


func sparkle_at(at: Vector2) -> void:
	build()
	_overlay.call("sparkle_at", at - _safe.global_position)


## The guided-mode arrow from the right item to Bunny's mouth.
func set_guide(from: Vector2, to: Vector2, on: bool) -> void:
	build()
	_overlay.call("set_guide", from - _safe.global_position, to - _safe.global_position, on)


func is_guide_visible() -> bool:
	build()
	return bool(_overlay.get("guide_on"))


func get_home_button() -> Button:
	build()
	return _home_button


func get_back_button() -> Button:
	build()
	return _back_button


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("line_spacing", 4)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_prompt_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "PromptBar"
	bar.add_theme_stylebox_override("panel", FRAME_PANEL)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -340.0
	bar.offset_right = 340.0
	bar.offset_top = 8.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_safe.add_child(bar)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	bar.add_child(column)
	var title := _label("Baby's table", _Typography.HELPER, _Palette.INK_SOFT)
	title.name = "ActivityTitle"
	column.add_child(title)

	_prompt_label = _label("", PROMPT_FONT, _Palette.INK)
	_prompt_label.name = "PromptLabel"
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_prompt_label)

	_helper_label = _label("", HELPER_FONT, _Palette.INK_SOFT)
	_helper_label.name = "HelperLabel"
	_helper_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_helper_label.visible = false
	column.add_child(_helper_label)


func _build_star_counter() -> void:
	var panel := PanelContainer.new()
	panel.name = "StarCounter"
	panel.add_theme_stylebox_override("panel", FRAME_PANEL)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	_safe.add_child(panel)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	_counter_star = _RatingStar.new()
	_counter_star.name = "CounterStar"
	_counter_star.custom_minimum_size = Vector2(44.0, 44.0)
	_counter_star.call("set_state", _RatingStar.State.EARNED)
	row.add_child(_counter_star)

	_count_label = _label("0", COUNT_FONT, _Palette.INK)
	_count_label.name = "StarCountLabel"
	_count_label.custom_minimum_size = Vector2(56.0, 0.0)
	row.add_child(_count_label)

	# This task's star, one step back from the lifetime count.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(6.0, 0.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	_task_star = _RatingStar.new()
	_task_star.name = "TaskStar"
	_task_star.custom_minimum_size = Vector2(36.0, 36.0)
	_task_star.call("set_state", _RatingStar.State.EARNED)
	_task_star.visible = false
	row.add_child(_task_star)


func _round_button(node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(ROUND_BUTTON, ROUND_BUTTON)
	button.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, _inset_frame(FRAME_BUTTON))
	button.add_theme_stylebox_override("pressed", _inset_frame(FRAME_BUTTON_DOWN))
	return button


## Stylebox inset changes only visible art. The full 200-square Button still
## owns input, including its transparent outer margin.
func _inset_frame(source: StyleBox) -> StyleBox:
	var frame: StyleBox = source.duplicate()
	for side: String in ["left", "top", "right", "bottom"]:
		frame.set("expand_margin_" + side, -26.0)
	return frame


func _build_buttons() -> void:
	# Home: top-right, left of the room's grown-up gear. Peach, like the menu's
	# own house button (`Palette.HOME_CHROME`): the way out of a level is the
	# same colour as the way in.
	_home_button = _round_button("HomeButton")
	_home_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_home_button.offset_right = -116.0
	_home_button.offset_left = -116.0 - ROUND_BUTTON
	_home_button.offset_top = 8.0
	_home_button.offset_bottom = 8.0 + ROUND_BUTTON
	_home_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_home_button.pressed.connect(func() -> void: home_pressed.emit())
	_safe.add_child(_home_button)
	var house := _IconGlyph.new()
	house.set("glyph", _IconGlyph.Glyph.PICTURE_HOUSE)
	house.set_anchors_preset(Control.PRESET_FULL_RECT)
	house.offset_left = 60.0
	house.offset_right = -60.0
	house.offset_top = 42.0
	house.offset_bottom = -78.0
	house.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home_button.add_child(house)
	_add_button_caption(_home_button, "Home")

	# Back: bottom-left, like the concept.
	_back_button = _round_button("BackButton")
	_back_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_back_button.offset_left = 8.0
	_back_button.offset_right = 8.0 + ROUND_BUTTON
	_back_button.offset_top = -8.0 - ROUND_BUTTON
	_back_button.offset_bottom = -8.0
	_back_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	_safe.add_child(_back_button)
	var arrow: TextureRect = _IconGlyph.new()
	arrow.set("glyph", _IconGlyph.Glyph.BACK)
	arrow.set("tint", _Palette.INK)
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow.offset_left = 68.0
	arrow.offset_right = -68.0
	arrow.offset_top = 50.0
	arrow.offset_bottom = -86.0
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(arrow)
	_add_button_caption(_back_button, "Back")


func _add_button_caption(button: Button, text: String) -> void:
	var label := _label(text, _Typography.BUTTON, _Palette.INK)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 28.0
	label.offset_right = -28.0
	label.offset_top = 120.0
	label.offset_bottom = -48.0
	button.add_child(label)


func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.name = "Hint"
	_hint.add_theme_stylebox_override("panel", FRAME_HINT)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	_safe.add_child(_hint)
	_hint_label = _label("", HINT_FONT, _Palette.INK)
	_hint_label.name = "HintLabel"
	_hint.add_child(_hint_label)


## The voice pack's subtitle strip (reads `Voice.line_started/finished` itself).
func _build_subtitle() -> void:
	_subtitle = _SubtitleStrip.new()
	_subtitle.name = "SubtitleStrip"
	_safe.add_child(_subtitle)
	_subtitle.call("build")
	_subtitle.call("set_bottom_margin", SUBTITLE_BOTTOM_MARGIN)
	_subtitle.call("set_side_clearance", SUBTITLE_SIDE_CLEARANCE)


func get_subtitle_strip() -> Control:
	build()
	return _subtitle


func _build_encouragement() -> void:
	_encourage = PanelContainer.new()
	_encourage.name = "Encouragement"
	_encourage.add_theme_stylebox_override("panel", FRAME_ENCOURAGE)
	_encourage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Left of the chair, level with Bunny's tummy: clear of his face, the prompt
	# bar, the tray and the Back button at every aspect ratio.
	_encourage.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_encourage.anchor_left = 0.0
	_encourage.anchor_right = 0.0
	_encourage.anchor_top = 0.55
	_encourage.anchor_bottom = 0.55
	_encourage.offset_left = 24.0
	_encourage.offset_right = 24.0
	_encourage.offset_top = -50.0
	_encourage.offset_bottom = 50.0
	_encourage.grow_horizontal = Control.GROW_DIRECTION_END
	_encourage.grow_vertical = Control.GROW_DIRECTION_BOTH
	_encourage.visible = false
	_safe.add_child(_encourage)
	_encourage_label = _label("", ENCOURAGE_FONT, _Palette.INK)
	_encourage_label.name = "EncouragementLabel"
	_encourage.add_child(_encourage_label)


# ---------------------------------------------------------------------------
# Drawn pieces
# ---------------------------------------------------------------------------



## Sparkle lines around a bite and the guided-mode arrow. Nothing here blocks
## touch and nothing runs when there is nothing to draw.
class FeedingOverlay extends Control:
	var guide_on: bool = false
	var _guide_from: Vector2 = Vector2.ZERO
	var _guide_to: Vector2 = Vector2.ZERO
	var _guide_phase: float = 0.0
	var _bursts: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func sparkle_at(at: Vector2) -> void:
		_bursts.append({"at": at, "t": 0.0})
		queue_redraw()

	func set_guide(from: Vector2, to: Vector2, on: bool) -> void:
		_guide_from = from
		_guide_to = to
		guide_on = on
		queue_redraw()

	func _process(delta: float) -> void:
		var alive: Array = []
		for burst: Dictionary in _bursts:
			burst["t"] = float(burst["t"]) + delta
			if float(burst["t"]) < SPARKLE_SECONDS:
				alive.append(burst)
		_bursts = alive
		if guide_on:
			_guide_phase = fmod(_guide_phase + delta, 1.4)
		if guide_on or not _bursts.is_empty():
			queue_redraw()

	func _draw() -> void:
		for burst: Dictionary in _bursts:
			_draw_burst(burst["at"], float(burst["t"]) / SPARKLE_SECONDS)
		if guide_on:
			_draw_guide()

	## Six short gold lines radiating out, like the concept's little sparkle.
	func _draw_burst(at: Vector2, t: float) -> void:
		var alpha: float = 1.0 - t * t
		var reach: float = lerpf(34.0, 92.0, t)
		var length: float = lerpf(38.0, 14.0, t)
		var gold: Color = Color(_Palette.STAR_EARNED, alpha)
		var rim: Color = Color(_Palette.deep(_Palette.STAR_EARNED), alpha)
		for i: int in range(6):
			var angle: float = deg_to_rad(-90.0 + 60.0 * float(i) + 18.0)
			var dir: Vector2 = Vector2(cos(angle), sin(angle))
			draw_line(at + dir * reach, at + dir * (reach + length), rim, 15.0, true)
			draw_line(at + dir * reach, at + dir * (reach + length), gold, 10.0, true)
		draw_circle(at, lerpf(8.0, 18.0, t), Color(_Palette.CREAM, alpha * 0.8))

	## A soft dotted arrow that walks from the item to the mouth.
	func _draw_guide() -> void:
		var delta: Vector2 = _guide_to - _guide_from
		var length: float = delta.length()
		if length < 24.0:
			return
		var dir: Vector2 = delta / length
		var start: Vector2 = _guide_from + dir * 40.0
		var end: Vector2 = _guide_to - dir * 56.0
		var run: float = maxf((end - start).length(), 1.0)
		var offset: float = fmod(_guide_phase / 1.4, 1.0) * 44.0
		var d: float = offset
		while d < run:
			var p: Vector2 = start + dir * d
			var fade: float = 0.55 + 0.45 * sin((d / run) * PI)
			draw_circle(p, 13.0, Color(_Palette.deep(_Palette.STAR_EARNED), fade * 0.7))
			draw_circle(p, 10.0, Color(_Palette.STAR_NEXT, fade))
			d += 44.0
		# Head.
		var tip: Vector2 = end + dir * 26.0
		var side: Vector2 = Vector2(-dir.y, dir.x)
		var head := PackedVector2Array([tip, end - dir * 4.0 + side * 22.0, end - dir * 4.0 - side * 22.0])
		draw_colored_polygon(head, _Palette.STAR_EARNED)
		draw_polyline(PackedVector2Array([head[1], head[0], head[2], head[1]]), Color(_Palette.INK_SOFT, 0.6), 3.0, true)
