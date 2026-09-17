extends RefCounted

## The shared UI chrome: bundled icons, re-paletted 9-slice frames, and the
## geometry of the child-facing controls in the baby room.
##
## These are the things that only ever break on a device: a `.tres` that points
## at a texture nobody imported, an icon that still carries Nieobie's
## `fill="currentColor"` (which Godot resolves to black, so `modulate` silently
## paints it black), a nine-patch whose margins are bigger than its own source,
## or two big buttons that quietly land on top of each other at one aspect
## ratio and not the other.
##
## All of the geometry here is computed from the stored anchors and offsets, so
## the case needs no viewport, no layout pass and no autoloads.

const IconGlyphScript := preload("res://scripts/progression/icon_glyph.gd")
const CelebrationScript := preload("res://scripts/progression/celebration.gd")
const StickerBookScreenScript := preload("res://scenes/progression/sticker_book_screen.gd")

const BABY_ROOM_SCENE: String = "res://scenes/baby_room/baby_room.tscn"
const STYLES_DIR: String = "res://assets/ui/styles"
const ICONS_DIR: String = "res://assets/ui/icons"

## Landscape safe-area sizes, in the project's 1366x1024 design space, for the
## two shapes the game ships on: an iPhone (~2.17:1) and an iPad (~1.44:1).
const SAFE_AREA_PHONE: Vector2 = Vector2(2170.0, 992.0)
const SAFE_AREA_TABLET: Vector2 = Vector2(1425.0, 992.0)

## Big enough for a three-year-old's finger, per the brief.
const MIN_BUTTON_SIDE: float = 200.0
const MIN_SPEAK_SIDE: float = 240.0

## The controls that must never collide, whatever the aspect ratio.
const LAID_OUT_NODES: Array = [
	"UI/SafeArea/StarCounter",
	"UI/SafeArea/TopStack",
	"UI/SafeArea/StickerButton",
	"UI/SafeArea/NextButton",
	"UI/SafeArea/MicButton",
	"UI/SafeArea/ListeningLabel",
]


func test_name() -> String:
	return "ui_chrome"


func run() -> Array:
	var failures: Array = []
	failures.append_array(_test_icons())
	failures.append_array(_test_styles())
	failures.append_array(_test_celebration_anchor())
	failures.append_array(_test_sticker_columns())
	failures.append_array(_test_room_layout())
	return failures


# ---------------------------------------------------------------------------
# Icons
# ---------------------------------------------------------------------------

func _test_icons() -> Array:
	var failures: Array = []

	for glyph: Variant in IconGlyphScript.ICON_PATHS.keys():
		var path: String = String(IconGlyphScript.ICON_PATHS[glyph])
		if not ResourceLoader.exists(path):
			failures.append("IconGlyph glyph %s points at missing icon %s" % [str(glyph), path])
			continue
		if load(path) == null:
			failures.append("icon %s did not load as a texture" % path)

	var dir: DirAccess = DirAccess.open(ICONS_DIR)
	if dir == null:
		return ["%s is missing" % ICONS_DIR]

	for file_name: String in dir.get_files():
		if not file_name.ends_with(".svg"):
			continue
		var source: String = "%s/%s" % [ICONS_DIR, file_name]
		var text: String = FileAccess.get_file_as_string(source)
		if text.contains("currentColor"):
			failures.append(
				"%s still uses fill=\"currentColor\"; Godot resolves that to black and "
				% source + "modulate multiplies, so every tint would come out black")
		# A 24x24 import would be a blurry smear on a retina iPad.
		var import_text: String = FileAccess.get_file_as_string(source + ".import")
		if import_text.is_empty():
			failures.append("%s has no .import file" % source)
		elif import_text.contains("svg/scale=1.0"):
			failures.append("%s imports at svg/scale=1.0 (24x24); it needs an explicit scale"
					% source)

	return failures


# ---------------------------------------------------------------------------
# 9-slice frames
# ---------------------------------------------------------------------------

func _test_styles() -> Array:
	var failures: Array = []

	var dir: DirAccess = DirAccess.open(STYLES_DIR)
	if dir == null:
		return ["%s is missing" % STYLES_DIR]

	var count: int = 0
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		count += 1
		var path: String = "%s/%s" % [STYLES_DIR, file_name]
		var style: Resource = load(path)
		if style == null or not (style is StyleBoxTexture):
			failures.append("%s did not load as a StyleBoxTexture" % path)
			continue

		var box: StyleBoxTexture = style
		var texture: Texture2D = box.texture
		if texture == null:
			failures.append("%s has no texture" % path)
			continue

		var texture_size: Vector2 = texture.get_size()
		if texture_size.x < 64.0 or texture_size.y < 64.0:
			failures.append("%s is only %s; the corners would be mush on a retina iPad"
					% [path, str(texture_size)])

		# Overlapping slices make the nine-patch fold in on itself.
		if box.texture_margin_left + box.texture_margin_right >= texture_size.x:
			failures.append("%s has horizontal texture margins wider than its own texture" % path)
		if box.texture_margin_top + box.texture_margin_bottom >= texture_size.y:
			failures.append("%s has vertical texture margins taller than its own texture" % path)

	if count == 0:
		failures.append("no styles found in %s" % STYLES_DIR)

	return failures


# ---------------------------------------------------------------------------
# Celebration
# ---------------------------------------------------------------------------

## The reward moment must not land on the baby, who lives in the middle of the
## screen. This is the regression guard for the celebration that used to default
## to the screen centre and hide the character at the happiest moment.
func _test_celebration_anchor() -> Array:
	var failures: Array = []

	for area: Vector2 in [SAFE_AREA_PHONE, SAFE_AREA_TABLET]:
		var celebration: Control = CelebrationScript.new()
		# Set directly so `_effective_size()` never has to reach for a viewport.
		celebration.size = area

		var card_size: Vector2 = CelebrationScript.STICKER_SIZE
		var origin: Vector2 = celebration.call("_moment_origin")
		var card: Rect2 = Rect2(origin - card_size * 0.5, card_size)

		if not Rect2(Vector2.ZERO, area).encloses(card):
			failures.append("at %s the celebration card %s escapes the safe area"
					% [str(area), str(card)])

		# The baby occupies the middle third; the card must clear it entirely.
		if card.position.x < area.x * 0.66:
			failures.append("at %s the celebration card starts at x=%.0f, over the baby"
					% [str(area), card.position.x])

		if celebration.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			failures.append("the celebration does not ignore touches")

		celebration.free()

	return failures


# ---------------------------------------------------------------------------
# Sticker book grid
# ---------------------------------------------------------------------------

func _test_sticker_columns() -> Array:
	var failures: Array = []

	var width: float = StickerBookScreenScript.COLUMN_WIDTH
	var cases: Array = [
		# available width, sticker count, expected columns
		[width * 8.6, 16, 8],   # phone-shaped landscape: 8 x 2, no scrolling
		[width * 6.5, 16, 6],   # iPad-shaped landscape: 6 + 6 + 4
		[width * 2.0, 16, StickerBookScreenScript.COLUMNS_MIN],
		[width * 40.0, 16, StickerBookScreenScript.COLUMNS_MAX],
		[width * 8.0, 3, 3],    # fewer stickers than columns: one tidy row
	]

	for entry: Variant in cases:
		var row: Array = entry
		var got: int = StickerBookScreenScript.pick_columns(float(row[0]), int(row[1]))
		if got != int(row[2]):
			failures.append("pick_columns(%.0f, %d) = %d, expected %d"
					% [float(row[0]), int(row[1]), got, int(row[2])])

	# Whatever it picks, the grid has to fit the width it was given.
	for columns_available: int in range(3, 12):
		var available: float = width * float(columns_available) + 1.0
		var picked: int = StickerBookScreenScript.pick_columns(available, 16)
		if float(picked) * width > available:
			failures.append("pick_columns overflowed: %d columns in %.0f px"
					% [picked, available])

	return failures


# ---------------------------------------------------------------------------
# Baby room layout
# ---------------------------------------------------------------------------

func _test_room_layout() -> Array:
	var failures: Array = []

	if not ResourceLoader.exists(BABY_ROOM_SCENE):
		return ["%s does not exist" % BABY_ROOM_SCENE]
	var packed: PackedScene = load(BABY_ROOM_SCENE) as PackedScene
	if packed == null or not packed.can_instantiate():
		return ["%s cannot be instantiated (broken resource reference?)" % BABY_ROOM_SCENE]

	# Never added to the tree: the room loads content and starts a mission in
	# `_ready()`, and none of that is needed to check its stored geometry.
	var room: Node = packed.instantiate()
	if room == null:
		return ["%s did not instantiate" % BABY_ROOM_SCENE]

	var sizes: Dictionary = {
		"UI/SafeArea/StickerButton": MIN_BUTTON_SIDE,
		"UI/SafeArea/NextButton": MIN_BUTTON_SIDE,
		"UI/SafeArea/MicButton": MIN_SPEAK_SIDE,
	}
	for node_path: Variant in sizes.keys():
		var control: Control = room.get_node_or_null(NodePath(String(node_path))) as Control
		if control == null:
			failures.append("the baby room has no %s" % String(node_path))
			continue
		var rect: Rect2 = _stored_rect(control, SAFE_AREA_TABLET)
		var required: float = float(sizes[node_path])
		if rect.size.x < required or rect.size.y < required:
			failures.append("%s is %s; a child's finger needs at least %.0f square"
					% [String(node_path), str(rect.size), required])
		if not is_equal_approx(rect.size.x, rect.size.y):
			failures.append("%s is %s, not square" % [String(node_path), str(rect.size)])

	for area: Vector2 in [SAFE_AREA_PHONE, SAFE_AREA_TABLET]:
		var rects: Dictionary = {}
		for node_path: Variant in LAID_OUT_NODES:
			var control: Control = room.get_node_or_null(NodePath(String(node_path))) as Control
			if control == null:
				failures.append("the baby room has no %s" % String(node_path))
				continue
			rects[node_path] = _stored_rect(control, area)

		# Plus the celebration, which is created in code rather than in the scene.
		var celebration: Control = CelebrationScript.new()
		celebration.size = area
		var card_size: Vector2 = CelebrationScript.STICKER_SIZE
		rects["<celebration card>"] = Rect2(
			Vector2(celebration.call("_moment_origin")) - card_size * 0.5, card_size)
		celebration.free()

		var names: Array = rects.keys()
		for i: int in range(names.size()):
			var rect: Rect2 = rects[names[i]]
			if not Rect2(Vector2.ZERO, area).encloses(rect):
				failures.append("at %s, %s (%s) is outside the safe area"
						% [str(area), String(names[i]), str(rect)])
			for j: int in range(i + 1, names.size()):
				var other: Rect2 = rects[names[j]]
				if rect.intersects(other):
					failures.append("at %s, %s overlaps %s"
							% [str(area), String(names[i]), String(names[j])])

	room.free()
	return failures


## The rect a Control will occupy inside a parent of `parent_size`, from the
## anchors and offsets stored in the scene -- no layout pass required.
static func _stored_rect(control: Control, parent_size: Vector2) -> Rect2:
	var left: float = control.anchor_left * parent_size.x + control.offset_left
	var top: float = control.anchor_top * parent_size.y + control.offset_top
	var right: float = control.anchor_right * parent_size.x + control.offset_right
	var bottom: float = control.anchor_bottom * parent_size.y + control.offset_bottom
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))
