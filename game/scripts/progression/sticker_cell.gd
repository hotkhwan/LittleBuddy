class_name StickerCell
extends Control

## One square in the sticker book grid.
##
## Unlocked: the real sticker on a warm card, with its English word underneath.
## Locked: the same shape as a soft lavender silhouette on a paler card -- the
## child can see what is coming. No padlock, no cross, no "not yet" wording.
##
## Emits `pressed(sticker_id, unlocked)`; it does not speak or play sound itself
## so the owning screen stays in charge of audio.

signal pressed(sticker_id: String, unlocked: bool)

const _StickerArt := preload("res://scripts/progression/sticker_art.gd")

## The card is the same re-paletted Kenney 9-slice as every other panel in the
## game, so a sticker card, the speech bubble and the summary panel share one
## corner radius and one edge treatment instead of each inventing their own.
const CARD_UNLOCKED: StyleBox = preload("res://assets/ui/styles/panel_cream.tres")
const CARD_LOCKED: StyleBox = preload("res://assets/ui/styles/panel_lilac.tres")

const LABEL_COLOR: Color = Color(0.349, 0.259, 0.169)
const LABEL_COLOR_LOCKED: Color = Color(0.639, 0.616, 0.678)

## Big, forgiving touch target for small fingers. Six of these plus their gaps
## still fit across an iPad in landscape inside the safe area. The book grows
## them from here to fill the page -- see `StickerBookScreen.cell_size()`.
const MIN_SIZE: Vector2 = Vector2(190.0, 210.0)

## Height as a multiple of width. The extra is the strip the word sits in.
const ASPECT: float = MIN_SIZE.y / MIN_SIZE.x

## Caption band, as a fraction of the card height, so a card that grew to fill an
## iPad page does not keep a phone-sized word wedged under it.
const CAPTION_RATIO: float = 0.2
const CAPTION_FONT_RATIO: float = 0.125

var _sticker: Dictionary = {}
var _unlocked: bool = false
var _interactive: bool = true
var _show_caption: bool = true
var _held: bool = false
var _label: Label


func _ready() -> void:
	custom_minimum_size = MIN_SIZE
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP if _interactive else Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_ensure_label()
	_refresh()


## `sticker` is a content-library sticker dictionary.
##
## `show_caption` off leaves the picture alone on the card: the session summary
## already prints the word large beside it, and printing it twice was the single
## most redundant thing on that screen.
func setup(sticker: Dictionary, unlocked: bool, interactive: bool = true,
		show_caption: bool = true) -> void:
	_sticker = sticker.duplicate(true)
	_unlocked = unlocked
	_interactive = interactive
	_show_caption = show_caption
	if is_inside_tree():
		mouse_filter = Control.MOUSE_FILTER_STOP if _interactive else Control.MOUSE_FILTER_IGNORE
		_ensure_label()
		_refresh()


func get_sticker_id() -> String:
	return String(_sticker.get("stickerId", ""))


func get_word() -> String:
	return String(_sticker.get("word", ""))


func is_unlocked() -> bool:
	return _unlocked


## Small, gentle bounce -- reused by the celebration flourish.
func pop() -> void:
	if not is_inside_tree():
		return
	pivot_offset = size * 0.5
	scale = Vector2(0.86, 0.86)
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _ensure_label() -> void:
	if _label == null:
		_label = Label.new()
		_label.name = "WordLabel"
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_label)
	_layout_label()


func _layout_label() -> void:
	if _label == null:
		return
	var band: float = _caption_band()
	_label.position = Vector2(0.0, size.y - band - 6.0)
	_label.size = Vector2(size.x, band)
	_label.add_theme_font_size_override(
		"font_size", maxi(int(round(size.y * CAPTION_FONT_RATIO)), 20))


## Height reserved under the picture for the word; zero when there is no word.
func _caption_band() -> float:
	if not _unlocked or not _show_caption:
		return 0.0
	return maxf(size.y * CAPTION_RATIO, 30.0)


func _refresh() -> void:
	if _label != null:
		# The word is shown for earned stickers only -- a locked card stays a
		# pure silhouette so there is nothing to feel bad about.
		var captioned: bool = _unlocked and _show_caption
		_label.text = String(_sticker.get("displayName", get_word())) if captioned else ""
		_label.add_theme_color_override(
			"font_color", LABEL_COLOR if _unlocked else LABEL_COLOR_LOCKED)
		_layout_label()
	queue_redraw()


func _on_resized() -> void:
	pivot_offset = size * 0.5
	_layout_label()
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return

	var card: Rect2 = Rect2(Vector2(4.0, 4.0), size - Vector2(8.0, 8.0))
	draw_style_box(CARD_UNLOCKED if _unlocked else CARD_LOCKED, card)

	if _sticker.is_empty():
		return

	var inset: float = maxf(card.size.x * 0.06, 8.0)
	var art_height: float = card.size.y - _caption_band() - inset * 1.6
	var art: Rect2 = Rect2(
		card.position + Vector2(inset, inset * 0.8),
		Vector2(card.size.x - inset * 2.0, maxf(art_height, 24.0)))
	_StickerArt.draw_sticker(self, _sticker, art, not _unlocked)


func _gui_input(event: InputEvent) -> void:
	if not _interactive:
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_held = true
			accept_event()
		elif _held:
			_held = false
			accept_event()
			if Rect2(Vector2.ZERO, size).has_point(button.position):
				pop()
				pressed.emit(get_sticker_id(), _unlocked)

	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_held = true
			accept_event()
		elif _held:
			_held = false
			accept_event()
			if Rect2(Vector2.ZERO, size).has_point(touch.position):
				pop()
				pressed.emit(get_sticker_id(), _unlocked)
