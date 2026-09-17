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
## still fit across an iPad in landscape inside the safe area.
const MIN_SIZE: Vector2 = Vector2(190.0, 210.0)

var _sticker: Dictionary = {}
var _unlocked: bool = false
var _interactive: bool = true
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
func setup(sticker: Dictionary, unlocked: bool, interactive: bool = true) -> void:
	_sticker = sticker.duplicate(true)
	_unlocked = unlocked
	_interactive = interactive
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
		_label.add_theme_font_size_override("font_size", 26)
		add_child(_label)
	_layout_label()


func _layout_label() -> void:
	if _label == null:
		return
	_label.position = Vector2(0.0, size.y - 42.0)
	_label.size = Vector2(size.x, 36.0)


func _refresh() -> void:
	if _label != null:
		# The word is shown for earned stickers only -- a locked card stays a
		# pure silhouette so there is nothing to feel bad about.
		_label.text = String(_sticker.get("displayName", get_word())) if _unlocked else ""
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

	var art_height: float = card.size.y - (44.0 if _unlocked else 16.0)
	var art: Rect2 = Rect2(
		card.position + Vector2(10.0, 8.0),
		Vector2(card.size.x - 20.0, maxf(art_height, 24.0)))
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
