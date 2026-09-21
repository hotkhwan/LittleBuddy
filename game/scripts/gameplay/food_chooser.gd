extends Control

## WHICH ONE? -- the fridge's food chooser, for Free Play.
##
## Arriving at the open fridge used to hand over whatever was first inside
## (always the banana): no choice, and so no reason to open it twice. This card
## shows what is inside as two or three big pictures, each with its English
## word; the child taps one, hears the word, and Aliz takes THAT. Tapping the
## dark around the cards takes nothing and puts the room back -- a child who
## changes their mind is never stuck behind a card.
##
## Pure presentation: it is handed rows (`itemId`, `word`, `color`, `shape`)
## and emits the pick. It never reads the kitchen. Cards are 260 x 300 px,
## comfortably over the 240 px the touch rules ask for a pre-reader.

const Palette := preload("res://scripts/ui/palette.gd")

signal picked(item_id: String)
signal dismissed()

const CARD_SIZE := Vector2(260.0, 300.0)
const CARD_GAP: float = 40.0
const ROW_LIFT: float = 70.0
const PICTURE_RADIUS: float = 78.0
const WORD_FONT_SIZE: int = 40
const TITLE: String = "Which one?"

var _built: bool = false
var _scrim: ColorRect = null
var _row: HBoxContainer = null
var _title: Label = null
var _cards: Array = []
var _rows: Array = []


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	name = "FoodChooser"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Palette.SCRIM
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)

	_title = Label.new()
	_title.name = "Title"
	_title.text = TITLE
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override("font_size", 56)
	_title.add_theme_color_override("font_color", Palette.CREAM)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.offset_left = -400.0
	_title.offset_right = 400.0
	_title.offset_top = 56.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	_row = HBoxContainer.new()
	_row.name = "Cards"
	_row.add_theme_constant_override("separation", int(CARD_GAP))
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_row.grow_vertical = Control.GROW_DIRECTION_BOTH
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	visible = false


## Shows one card per row. `rows`: `[{"itemId", "word", "color": Color, "shape"}]`.
func open(rows: Array) -> void:
	build()
	for card: Variant in _cards:
		if not is_instance_valid(card):
			continue
		# Freed outright, not deferred: a second opening must not count the
		# first opening's cards, and the headless runner never has an idle frame.
		if (card as Node).get_parent() == _row:
			_row.remove_child(card as Node)
		(card as Node).free()
	_cards.clear()
	_rows = []
	for row: Variant in rows:
		if not (row is Dictionary):
			continue
		var data: Dictionary = row as Dictionary
		var card: Button = _make_card(data)
		_row.add_child(card)
		_cards.append(card)
		_rows.append(data)
	_row.reset_size()
	# Centre the row on the card row's own size, whatever the viewport.
	var total: float = CARD_SIZE.x * float(_cards.size()) + CARD_GAP * float(maxi(_cards.size() - 1, 0))
	_row.offset_left = -total * 0.5
	_row.offset_right = total * 0.5
	# Lifted off centre: the HUD's subtitle pill sits just below the middle
	# of the screen and was covering the middle card's word (seen in
	# docs/shots/freeplay_chooser_ipad.png).
	_row.offset_top = -CARD_SIZE.y * 0.5 - ROW_LIFT
	_row.offset_bottom = CARD_SIZE.y * 0.5 - ROW_LIFT
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func get_card_count() -> int:
	return _cards.size()


func get_card_size() -> Vector2:
	return CARD_SIZE


func get_item_ids() -> Array:
	var ids: Array = []
	for data: Dictionary in _rows:
		ids.append(String(data.get("itemId", "")))
	return ids


## Picks by id -- what a tap on that card does. Public so a test can choose
## without synthesising a touch. False for an id that is not on a card.
func pick(item_id: String) -> bool:
	if not visible:
		return false
	for data: Dictionary in _rows:
		if String(data.get("itemId", "")) == item_id:
			close()
			picked.emit(item_id)
			return true
	return false


## A tap on the dark: nothing taken, the room comes back.
func dismiss() -> void:
	if not visible:
		return
	close()
	dismissed.emit()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var released: bool = false
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		released = true
	elif event is InputEventMouseButton and not (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		released = true
	if released:
		# Only reaches here when no card took the press (cards STOP their input).
		dismiss()


func _make_card(data: Dictionary) -> Button:
	var card := Button.new()
	card.name = "Card_%s" % String(data.get("itemId", ""))
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var normal := StyleBoxFlat.new()
	normal.bg_color = Palette.CREAM
	normal.set_corner_radius_all(28)
	normal.border_width_bottom = 8
	normal.border_color = Palette.deep(Palette.CREAM)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Palette.light(Palette.MINT)
	pressed.set_corner_radius_all(28)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", normal)
	card.add_theme_stylebox_override("pressed", pressed)
	card.add_theme_stylebox_override("focus", normal)

	var picture := Control.new()
	picture.name = "Picture"
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	picture.offset_top = 40.0 + PICTURE_RADIUS
	picture.set_meta("shape", String(data.get("shape", "ball")))
	var tint: Variant = data.get("color", Palette.PEACH)
	picture.set_meta("color", tint if tint is Color else Palette.PEACH)
	picture.draw.connect(_draw_picture.bind(picture))
	card.add_child(picture)

	var word := Label.new()
	word.name = "Word"
	word.text = String(data.get("word", ""))
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	word.add_theme_font_size_override("font_size", WORD_FONT_SIZE)
	word.add_theme_color_override("font_color", Palette.INK)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	word.offset_top = -92.0
	word.offset_bottom = -28.0
	card.add_child(word)

	card.pressed.connect(func() -> void: pick(String(data.get("itemId", ""))))
	return card


## The item as a shape in its own colour -- the same vocabulary
## `kitchen_items.gd` gives the 3D prop, so the card and the thing agree.
func _draw_picture(picture: Control) -> void:
	var shape: String = String(picture.get_meta("shape", "ball"))
	var color: Color = picture.get_meta("color", Palette.PEACH)
	var o := Vector2.ZERO
	var r: float = PICTURE_RADIUS
	match shape:
		"flat":
			# A banana: a thick arc.
			picture.draw_arc(o + Vector2(0.0, -r * 0.3), r * 0.9, PI * 0.15, PI * 0.85, 24, color, r * 0.42)
		"cup":
			picture.draw_rect(Rect2(o + Vector2(-r * 0.45, -r * 0.7), Vector2(r * 0.9, r * 1.5)), color, true)
			picture.draw_rect(Rect2(o + Vector2(-r * 0.25, -r * 0.95), Vector2(r * 0.5, r * 0.3)), Palette.SOFT_PINK, true)
		"bowl":
			picture.draw_circle(o, r, color)
			picture.draw_rect(Rect2(o + Vector2(-r, -r), Vector2(r * 2.0, r)), Palette.CREAM, true)
			picture.draw_circle(o + Vector2(0.0, -r * 0.05), r * 0.7, Palette.light(color))
		_:
			picture.draw_circle(o, r, color)
			picture.draw_circle(o + Vector2(-r * 0.3, -r * 0.3), r * 0.22, Color(1.0, 1.0, 1.0, 0.55))
			picture.draw_rect(Rect2(o + Vector2(-4.0, -r - 14.0), Vector2(8.0, 22.0)), Palette.INK_SOFT, true)
