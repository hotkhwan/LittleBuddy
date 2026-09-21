extends Control

## "Play with Bunny" -> which activity?
##
## The card grid a child sees after the title screen's Play with Bunny button.
## One big picture button per Bunny-care level, built from CONTENT -- the house
## chapter's levels, each mapped to its mission -- never from a second, hand-kept
## list of activities. Every card is always selectable: a finished level stays
## on the grid with its 0..3 star rating, because the owner's playtest found
## there was no way back to the feeding mini-game once it had been played once.
##
## ## What this file decides, and what it does not
##
## It decides WHICH cards exist (`entries_for()`, pure and static) and what a
## tap means (`activity_chosen(mission_id)`). It does not start anything: the
## title screen hands the mission id to the house through
## `main.gd::build_scene(..., mission_id)`, and `HouseLevelDirector.start()`
## decides whether it is playable. Replay reward policy lives at the director's
## one reward seam, not here -- this screen never touches stars, it only shows
## them.
##
## ## Why the playable filter is duplicated from the director
##
## `entries_for()` keeps a level only when its mission has at least one task
## the house can play, mirroring `HouseLevelDirector._playable_mission_for_level`
## rule for rule (the same two static `describe_unplayable` checks). It is
## duplicated rather than shared so this menu never has to instantiate a level
## director to draw four buttons; `test_activity_picker.gd` pins the two
## together by asking a real director to start every card the picker lists.
##
## ## Child UX (CLAUDE.md, ART_BIBLE §8)
##
## Cards are 256 px square (floor 240), captions 28 pt (floor 27), pictures
## first and words second, the palette only, a big Back button, no lock icons,
## no greyed-out cards, no timers. The stars are `rating_star.gd`'s: earned
## gold, the next one breathing, the rest a ghost -- never an empty slot.

signal activity_chosen(mission_id: String)
signal back_pressed

const Palette := preload("res://scripts/ui/palette.gd")
const IconGlyph := preload("res://scripts/progression/icon_glyph.gd")
const RatingStar := preload("res://scripts/ui/rating_star.gd")
const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")
const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")

## The Bunny-care chapter. The same id `HouseLevelDirector.HOUSE_CHAPTER_ID`
## names; the house is Chapter 3 and this menu lists the house.
const HOUSE_CHAPTER_ID: String = "ch3"

## Shown to the child, in this exact form.
const TITLE: String = "Play with Bunny"
const BACK_LABEL: String = "Back"

const CARD_SIDE: float = 256.0
const CARD_GAP: float = 28.0
const COLUMNS: int = 4
const CAPTION_FONT_SIZE: int = 28
const TITLE_FONT_SIZE: int = 52
const BACK_FONT_SIZE: int = 34
const BACK_SIZE: Vector2 = Vector2(260.0, 120.0)
const MARGIN: float = 24.0
const GRID_TOP: float = 168.0
const STAR_SIZE: float = 44.0
const PICTURE_TOP: float = 18.0
const PICTURE_SIZE: float = 104.0
const CAPTION_TOP: float = 126.0
const CAPTION_HEIGHT: float = 72.0
const STARS_TOP: float = 202.0
const PRESS_SCALE: Vector2 = Vector2(0.94, 0.94)
const PRESS_SECONDS: float = 0.08
const TAP_SFX: String = "gentle_tap"
const BACKDROP_ALPHA: float = 1.0

## The four button faces the title screen already uses, in rotation, so the
## grid reads as the same family of buttons as the row beneath it.
const CARD_STYLES: Array = [
	["res://assets/ui/styles/btn_mint.tres", "res://assets/ui/styles/btn_mint_down.tres", "mint"],
	["res://assets/ui/styles/btn_peach.tres", "res://assets/ui/styles/btn_peach_down.tres", "peach"],
	["res://assets/ui/styles/btn_pink.tres", "res://assets/ui/styles/btn_pink_down.tres", "pink"],
	["res://assets/ui/styles/btn_lavender.tres", "res://assets/ui/styles/btn_lavender_down.tres", "lavender"],
]
const BACK_STYLE: String = "res://assets/ui/styles/btn_peach.tres"
const BACK_STYLE_DOWN: String = "res://assets/ui/styles/btn_peach_down.tres"

## Which picture a card gets. By mission first, then by the mission's authored
## `category`, then a star -- so new content always gets SOME picture and a
## pre-reader can still tell "hungry" from "bedtime" without reading either.
const PICTURE_BY_MISSION: Dictionary = {
	"imHungry": "bottle",
	"snackTime": "bowl",
	"breakfastTime": "bowl",
	"brushMyTeeth": "brush",
	"goodMorningRoutine": "sun",
}
const PICTURE_BY_CATEGORY: Dictionary = {
	"feeding": "bowl",
	"care": "bottle",
	"routine": "sun",
	"dressing": "shirt",
	"play": "ball",
	"bedtime": "moon",
}

var _entries: Array = []
var _cards: Array = []
var _back_button: Button = null
var _title_label: Label = null
var _grid: GridContainer = null
var _built: bool = false
## Latched on the first tap. Two fast taps on one card -- trivially easy for a
## child -- must be one choice, not two departures.
var _chosen: bool = false


func _init() -> void:
	name = "ActivityPicker"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


# ---------------------------------------------------------------------------
# The list -- pure, static, content-driven
# ---------------------------------------------------------------------------

## The cards, in the chapter's authored order: `{missionId, levelId, title,
## thaiTitle, category, stars}` per playable house level. `stars_by_level` is
## the profile's `starsByLevel` map (or `{}`); it only decorates, it never
## filters -- a finished level is listed like any other. `[]` when there is no
## level system or content, which the caller treats as "go straight in".
static func entries_for(system: Variant, library: Variant, stars_by_level: Dictionary) -> Array:
	var entries: Array = []
	if system == null or library == null or not system.has_method("get_levels_in_chapter"):
		return entries
	for level_id: String in (system.call("get_levels_in_chapter", HOUSE_CHAPTER_ID) as PackedStringArray):
		var mission_id: String = String(system.call("get_mission_id_for_level", level_id))
		if mission_id.is_empty() or playable_task_count(library, mission_id) <= 0:
			continue
		var level: RefCounted = system.call("get_level", level_id)
		var title: String = level_id
		var thai_title: String = ""
		var category: String = ""
		if level != null:
			if level.has_method("get_title"):
				title = String(level.call("get_title")).strip_edges()
			if level.has_method("get_thai_title"):
				thai_title = String(level.call("get_thai_title")).strip_edges()
			if level.has_method("get_category"):
				category = String(level.call("get_category")).strip_edges()
		if title.is_empty():
			title = level_id
		entries.append({
			"missionId": mission_id,
			"levelId": level_id,
			"title": title,
			"thaiTitle": thai_title,
			"category": category,
			"stars": clampi(_as_int(stars_by_level.get(level_id, 0)), 0, 3),
		})
	return entries


## Tasks a child could actually finish in the house. Mirrors
## `HouseLevelDirector._playable_task_count` exactly; see the class doc.
static func playable_task_count(library: Variant, mission_id: String) -> int:
	if library == null or not library.has_method("get_mission_tasks"):
		return 0
	var count: int = 0
	for task: Variant in library.call("get_mission_tasks", mission_id):
		if not String(MissionRunnerScript.describe_unplayable(task, library)).is_empty():
			continue
		var plan: Dictionary = TaskPlan.describe(task, "")
		if not String(TaskPlan.describe_unplayable_in_house(plan)).is_empty():
			continue
		count += 1
	return count


## The picture name for an entry. Pure, so the mapping can be asserted.
static func picture_for(entry: Dictionary) -> String:
	var mission_id: String = String(entry.get("missionId", ""))
	if PICTURE_BY_MISSION.has(mission_id):
		return String(PICTURE_BY_MISSION[mission_id])
	var category: String = String(entry.get("category", ""))
	if PICTURE_BY_CATEGORY.has(category):
		return String(PICTURE_BY_CATEGORY[category])
	return "star"


static func _as_int(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return int(round(float(value)))
		TYPE_BOOL:
			return 1 if value else 0
		_:
			return 0


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

## Builds the screen for `entries`. Idempotent per instance: a second call
## rebuilds the grid (a returning menu may have new stars to show).
func build(entries: Array) -> void:
	_entries = entries.duplicate(true)
	_chosen = false
	if not _built:
		_built = true
		_build_chrome()
	for card: Node in _cards:
		card.queue_free()
	_cards = []
	for index: int in range(_entries.size()):
		var card: Button = _build_card(_entries[index] as Dictionary, index)
		_grid.add_child(card)
		_cards.append(card)


func _build_chrome() -> void:
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.CREAM, BACKDROP_ALPHA)
	backdrop.add_theme_stylebox_override("panel", style)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = TITLE
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title_label.add_theme_color_override("font_color", Palette.INK)
	_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title_label.offset_top = MARGIN
	_title_label.offset_bottom = MARGIN + BACK_SIZE.y
	add_child(_title_label)

	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.text = ""
	_back_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_back_button.offset_left = MARGIN
	_back_button.offset_top = MARGIN
	_back_button.offset_right = MARGIN + BACK_SIZE.x
	_back_button.offset_bottom = MARGIN + BACK_SIZE.y
	_apply_style(_back_button, BACK_STYLE, BACK_STYLE_DOWN)
	var arrow: TextureRect = IconGlyph.new()
	arrow.name = "BackIcon"
	arrow.set("glyph", IconGlyph.Glyph.BACK)
	arrow.set("tint", Palette.INK)
	arrow.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	arrow.offset_left = 22.0
	arrow.offset_top = 22.0
	arrow.offset_right = 22.0 + BACK_SIZE.y - 44.0
	arrow.offset_bottom = -22.0
	_back_button.add_child(arrow)
	var back_caption := Label.new()
	back_caption.name = "BackCaption"
	back_caption.text = BACK_LABEL
	back_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back_caption.add_theme_font_size_override("font_size", BACK_FONT_SIZE)
	back_caption.add_theme_color_override("font_color", Palette.INK)
	back_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	back_caption.offset_left = BACK_SIZE.y - 16.0
	_back_button.add_child(back_caption)
	_back_button.pressed.connect(_on_back_pressed)
	_wire_press_feedback(_back_button)
	add_child(_back_button)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var grid_width: float = CARD_SIDE * float(COLUMNS) + CARD_GAP * float(COLUMNS - 1)
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.anchor_left = 0.5
	scroll.anchor_right = 0.5
	scroll.offset_left = -grid_width * 0.5 - MARGIN
	scroll.offset_right = grid_width * 0.5 + MARGIN
	scroll.offset_top = GRID_TOP
	scroll.offset_bottom = -MARGIN
	scroll.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(scroll)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(centre)

	_grid = GridContainer.new()
	_grid.name = "Cards"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", int(CARD_GAP))
	_grid.add_theme_constant_override("v_separation", int(CARD_GAP))
	centre.add_child(_grid)


func _build_card(entry: Dictionary, index: int) -> Button:
	var mission_id: String = String(entry.get("missionId", ""))
	var style: Array = CARD_STYLES[index % CARD_STYLES.size()]
	var card := Button.new()
	card.name = "Card_%s" % mission_id
	card.focus_mode = Control.FOCUS_NONE
	card.text = ""
	card.custom_minimum_size = Vector2(CARD_SIDE, CARD_SIDE)
	card.set_meta("missionId", mission_id)
	card.set_meta("levelId", String(entry.get("levelId", "")))
	_apply_style(card, String(style[0]), String(style[1]))

	var picture := ActivityPicture.new()
	picture.name = "Picture"
	picture.kind = picture_for(entry)
	picture.set_anchors_preset(Control.PRESET_CENTER_TOP)
	picture.offset_left = -PICTURE_SIZE * 0.5
	picture.offset_right = PICTURE_SIZE * 0.5
	picture.offset_top = PICTURE_TOP
	picture.offset_bottom = PICTURE_TOP + PICTURE_SIZE
	picture.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.add_child(picture)

	var caption := Label.new()
	caption.name = "Caption"
	caption.text = String(entry.get("title", mission_id))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", CAPTION_FONT_SIZE)
	caption.add_theme_color_override("font_color", Palette.INK)
	caption.set_anchors_preset(Control.PRESET_TOP_WIDE)
	caption.offset_left = 12.0
	caption.offset_right = -12.0
	caption.offset_top = CAPTION_TOP
	caption.offset_bottom = CAPTION_TOP + CAPTION_HEIGHT
	card.add_child(caption)

	var stars := HBoxContainer.new()
	stars.name = "Stars"
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.add_theme_constant_override("separation", 6)
	stars.set_anchors_preset(Control.PRESET_TOP_WIDE)
	stars.offset_top = STARS_TOP
	stars.offset_bottom = STARS_TOP + STAR_SIZE
	var earned: int = clampi(int(entry.get("stars", 0)), 0, 3)
	for star_index: int in range(3):
		var star: TextureRect = RatingStar.new()
		star.name = "Star%d" % (star_index + 1)
		star.custom_minimum_size = Vector2(STAR_SIZE, STAR_SIZE)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.call("set_state", RatingStar.state_for(star_index, earned))
		stars.add_child(star)
	card.add_child(stars)

	card.pressed.connect(_on_card_pressed.bind(mission_id))
	_wire_press_feedback(card)
	return card


func _apply_style(button: Button, normal_path: String, down_path: String) -> void:
	var normal: Resource = load(normal_path) if ResourceLoader.exists(normal_path) else null
	var down: Resource = load(down_path) if ResourceLoader.exists(down_path) else normal
	if normal is StyleBox:
		for state: String in ["normal", "hover", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, normal as StyleBox)
	if down is StyleBox:
		button.add_theme_stylebox_override("pressed", down as StyleBox)


func _wire_press_feedback(button: Button) -> void:
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))


# ---------------------------------------------------------------------------
# Taps
# ---------------------------------------------------------------------------

func _on_card_pressed(mission_id: String) -> void:
	if _chosen:
		return
	_chosen = true
	activity_chosen.emit(mission_id)


func _on_back_pressed() -> void:
	if _chosen:
		return
	back_pressed.emit()


func _on_button_down(button: Button) -> void:
	_squish(button, PRESS_SCALE)
	var sfx: Node = _autoload("Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", TAP_SFX)


func _on_button_up(button: Button) -> void:
	_squish(button, Vector2.ONE)


func _squish(button: Button, to: Vector2) -> void:
	button.pivot_offset = button.size * 0.5
	if not is_inside_tree():
		button.scale = to
		return
	var tween: Tween = create_tween()
	tween.tween_property(button, "scale", to, PRESS_SECONDS).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------------------
# For the menu, the tests and the screenshot harness
# ---------------------------------------------------------------------------

func get_entries() -> Array:
	return _entries.duplicate(true)


func get_mission_ids() -> Array:
	var ids: Array = []
	for entry: Dictionary in _entries:
		ids.append(String(entry.get("missionId", "")))
	return ids


## The card buttons, in grid order.
func get_cards() -> Array:
	return _cards.duplicate()


func get_card(mission_id: String) -> Button:
	for card: Button in _cards:
		if String(card.get_meta("missionId", "")) == mission_id:
			return card
	return null


func get_back_button() -> Button:
	return _back_button


## Taps the card for `mission_id`, as a finger would. False when there is none.
func choose(mission_id: String) -> bool:
	var card: Button = get_card(mission_id)
	if card == null:
		return false
	card.pressed.emit()
	return true


func _autoload(autoload_name: String) -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree) or (loop as SceneTree).root == null:
		return null
	return (loop as SceneTree).root.get_node_or_null(autoload_name)


# ---------------------------------------------------------------------------
# The pictures
# ---------------------------------------------------------------------------

## One simple drawing per activity, in the locked palette, on a cream disc.
## Rounded forms only; the same optical weight as the title screen's glyphs.
## Purely decorative -- it never eats the touch meant for the card.
class ActivityPicture extends Control:
	const _Palette := preload("res://scripts/ui/palette.gd")
	var kind: String = "star":
		set(value):
			kind = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		var c: Vector2 = size * 0.5
		var r: float = s * 0.5
		draw_circle(c, r, Color(_Palette.CREAM, 0.9))
		match kind:
			"bottle":
				# A baby bottle, teat up.
				draw_rect(Rect2(c + Vector2(-r * 0.30, -r * 0.20), Vector2(r * 0.60, r * 0.86)),
						Color(1.0, 0.988, 0.949), true)
				draw_rect(Rect2(c + Vector2(-r * 0.30, -r * 0.20), Vector2(r * 0.60, r * 0.86)),
						_Palette.DUSTY_BLUE, false, 4.0)
				draw_rect(Rect2(c + Vector2(-r * 0.18, -r * 0.40), Vector2(r * 0.36, r * 0.20)),
						_Palette.DUSTY_BLUE, true)
				draw_circle(c + Vector2(0.0, -r * 0.52), r * 0.16, _Palette.SOFT_PINK)
			"bowl":
				# A bowl with a spoon.
				draw_circle(c + Vector2(0.0, r * 0.10), r * 0.56, _Palette.PEACH)
				draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.46), Vector2(r * 1.24, r * 0.56)),
						Color(_Palette.CREAM, 0.9), true)
				draw_arc(c + Vector2(0.0, r * 0.10), r * 0.56, 0.0, PI, 24, _Palette.INK, 4.0)
				draw_line(c + Vector2(-r * 0.62, r * 0.10), c + Vector2(r * 0.62, r * 0.10), _Palette.INK, 4.0)
				draw_line(c + Vector2(r * 0.20, r * 0.02), c + Vector2(r * 0.52, -r * 0.50), _Palette.INK, 6.0)
				draw_circle(c + Vector2(r * 0.56, -r * 0.56), r * 0.13, _Palette.INK)
			"sun":
				for i: int in range(8):
					var a: float = TAU * float(i) / 8.0
					draw_line(c + Vector2.from_angle(a) * r * 0.50, c + Vector2.from_angle(a) * r * 0.74,
							_Palette.STAR_EARNED, 6.0)
				draw_circle(c, r * 0.36, _Palette.STAR_EARNED)
			"shirt":
				var body := PackedVector2Array([
					c + Vector2(-r * 0.36, -r * 0.20), c + Vector2(-r * 0.68, -r * 0.44),
					c + Vector2(-r * 0.44, -r * 0.62), c + Vector2(-r * 0.20, -r * 0.50),
					c + Vector2(r * 0.20, -r * 0.50), c + Vector2(r * 0.44, -r * 0.62),
					c + Vector2(r * 0.68, -r * 0.44), c + Vector2(r * 0.36, -r * 0.20),
					c + Vector2(r * 0.36, r * 0.60), c + Vector2(-r * 0.36, r * 0.60),
				])
				draw_colored_polygon(body, _Palette.SOFT_PINK)
				draw_circle(c + Vector2(-r * 0.09, r * 0.06), r * 0.10, _Palette.INK)
				draw_circle(c + Vector2(r * 0.09, r * 0.06), r * 0.10, _Palette.INK)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-r * 0.19, r * 0.10), c + Vector2(r * 0.19, r * 0.10), c + Vector2(0.0, r * 0.30),
				]), _Palette.INK)
			"ball":
				draw_circle(c, r * 0.56, _Palette.MINT)
				draw_arc(c, r * 0.56, 0.0, TAU, 40, _Palette.INK, 4.0)
				draw_arc(c + Vector2(-r * 0.56, 0.0), r * 0.56, -PI * 0.35, PI * 0.35, 20, _Palette.INK, 4.0)
				draw_arc(c + Vector2(r * 0.56, 0.0), r * 0.56, PI * 0.65, PI * 1.35, 20, _Palette.INK, 4.0)
			"moon":
				draw_circle(c, r * 0.54, _Palette.STAR_NEXT)
				draw_circle(c + Vector2(r * 0.26, -r * 0.16), r * 0.46, Color(_Palette.CREAM, 0.9))
				draw_circle(c + Vector2(r * 0.44, r * 0.40), r * 0.07, _Palette.STAR_EARNED)
			"brush":
				draw_rect(Rect2(c + Vector2(-r * 0.10, -r * 0.60), Vector2(r * 0.20, r * 1.10)),
						_Palette.DUSTY_BLUE, true)
				draw_rect(Rect2(c + Vector2(-r * 0.24, -r * 0.60), Vector2(r * 0.48, r * 0.26)),
						_Palette.CREAM, true)
				draw_rect(Rect2(c + Vector2(-r * 0.24, -r * 0.60), Vector2(r * 0.48, r * 0.26)),
						_Palette.INK, false, 3.0)
			_:
				var pts := PackedVector2Array()
				for i: int in range(10):
					var a: float = -PI * 0.5 + TAU * float(i) / 10.0
					var rr: float = r * (0.62 if i % 2 == 0 else 0.30)
					pts.append(c + Vector2.from_angle(a) * rr)
				draw_colored_polygon(pts, _Palette.STAR_EARNED)
