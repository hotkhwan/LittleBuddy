extends RefCounted

## The sticker pictures, and the page they sit on.
##
## Two things here only ever break on a device. The first is a glyph that
## silently fails to draw -- `_draw()` merely records commands and the renderer
## binds the texture later in the frame, so a glyph held in nothing but a local
## is freed before it is ever drawn and the card comes out as a solid coloured
## square. The second is a page that overflows: cards are grown from their
## minimum to fill the screen, and an off-by-one in that sum pushes the last
## column past the safe area where nothing but a real iPad would show it.

const StickerArtScript := preload("res://scripts/progression/sticker_art.gd")
const StickerCellScript := preload("res://scripts/progression/sticker_cell.gd")
const StickerBookScreenScript := preload("res://scenes/progression/sticker_book_screen.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")

## The five words the 815-icon Nieobie pack has nothing on-theme for. They keep
## their polygon recipe; see `StickerArt.GLYPH_PATHS`.
const POLYGON_WORDS: Array[String] = [
	"banana", "soap", "towel", "toothbrush", "pillow",
]

## Landscape safe-area sizes in the project's 1366x1024 design space, matching
## `test_ui_chrome.gd`: an iPhone (~2.17:1) and an iPad (~1.44:1).
const SAFE_AREA_PHONE: Vector2 = Vector2(2170.0, 992.0)
const SAFE_AREA_TABLET: Vector2 = Vector2(1425.0, 992.0)


func test_name() -> String:
	return "ui_stickers"


func run() -> Array:
	var failures: Array = []
	failures.append_array(_test_glyphs_load())
	failures.append_array(_test_every_sticker_has_art())
	failures.append_array(_test_glyph_cache_keeps_a_reference())
	failures.append_array(_test_page_fits())
	return failures


# ---------------------------------------------------------------------------
# Glyphs
# ---------------------------------------------------------------------------

func _test_glyphs_load() -> Array:
	var failures: Array = []

	for word: Variant in StickerArtScript.GLYPH_PATHS.keys():
		var path: String = String(StickerArtScript.GLYPH_PATHS[word])
		if not ResourceLoader.exists(path):
			failures.append("sticker glyph '%s' points at missing %s" % [str(word), path])
			continue

		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			failures.append("%s did not load as a texture" % path)
			continue
		# A 24x24 import would be a blurry smear on a card grown to fill an iPad.
		if texture.get_width() < 200 or texture.get_height() < 200:
			failures.append("%s imports at %s; a sticker card is up to 330px wide"
					% [path, str(texture.get_size())])

		var source: String = FileAccess.get_file_as_string(path)
		if source.contains("currentColor"):
			failures.append(
				"%s still uses fill=\"currentColor\"; Godot resolves that to black " % path
				+ "and the sticker tint multiplies, so every sticker would come out black")

	return failures


## Every sticker in the content pack must resolve to *something* drawable:
## either a bundled glyph, or a polygon recipe. A word that has neither would
## reach the device as an empty card.
func _test_every_sticker_has_art() -> Array:
	var failures: Array = []

	var library: Object = ContentLibraryScript.create()
	if library == null or not library.has_method("get_stickers"):
		return ["the content library has no get_stickers()"]

	var seen_polygons: Array[String] = []
	for entry: Variant in library.call("get_stickers"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sticker: Dictionary = entry
		var word: String = String(sticker.get("word", "")).to_lower()
		if word.is_empty():
			failures.append("a sticker in the content pack has no word")
			continue

		if StickerArtScript.glyph_for(word) != null:
			continue

		seen_polygons.append(word)
		# No glyph -- the polygon recipe has to produce something.
		var base: Color = StickerArtScript.color_from_hex(
				String(sticker.get("color", "")), StickerArtScript.PEACH)
		var parts: Array = StickerArtScript.build_parts(
				word, String(sticker.get("primitive", "sphere")).to_lower(),
				Rect2(Vector2.ZERO, Vector2(200.0, 200.0)), base)
		if parts.is_empty():
			failures.append("sticker '%s' has neither a glyph nor a polygon recipe" % word)

	seen_polygons.sort()
	var expected: Array[String] = POLYGON_WORDS.duplicate()
	expected.sort()
	if seen_polygons != expected:
		# Not a style rule: if a word quietly loses its glyph, this is the only
		# place that notices before the book is on a device.
		failures.append("stickers drawn from polygons are %s, expected %s"
				% [str(seen_polygons), str(expected)])

	return failures


## The cache is load-bearing, not an optimisation -- see `StickerArt.glyph_for`.
func _test_glyph_cache_keeps_a_reference() -> Array:
	var first: Texture2D = StickerArtScript.glyph_for("milk")
	if first == null:
		return ["the milk glyph did not load at all"]
	var second: Texture2D = StickerArtScript.glyph_for("milk")
	if first != second:
		return ["glyph_for() returns a fresh texture each call; a texture held only "
			+ "by a local is freed before _draw()'s commands are rendered, which "
			+ "paints the sticker as a solid square"]
	# An unknown word must be cached as "nothing", not re-probed forever.
	if StickerArtScript.glyph_for("banana") != null:
		return ["'banana' resolved to a glyph; it is meant to keep its polygon recipe"]
	return []


# ---------------------------------------------------------------------------
# Page layout
# ---------------------------------------------------------------------------

## Cards grow from their minimum to fill the page. Whatever size that lands on,
## the grid has to fit the width AND the height it was handed.
func _test_page_fits() -> Array:
	var failures: Array = []
	var gap: float = StickerBookScreenScript.GAP
	var minimum: Vector2 = StickerCellScript.MIN_SIZE

	for area: Vector2 in [SAFE_AREA_PHONE, SAFE_AREA_TABLET]:
		var width: float = area.x - StickerBookScreenScript.SCROLLBAR_ALLOWANCE
		# The page is the safe area minus the header row and the layout gap.
		var height: float = area.y - 200.0

		for total: int in [1, 3, 8, 16, 24]:
			var columns: int = StickerBookScreenScript.pick_columns(width, total)
			var cell: Vector2 = StickerBookScreenScript.cell_size(
					width, height, columns, total)

			if cell.x < minimum.x or cell.y < minimum.y:
				failures.append("at %s with %d stickers the card shrank to %s, below the %s minimum"
						% [str(area), total, str(cell), str(minimum)])

			var rows: int = int(ceil(float(total) / float(columns)))
			var used_width: float = cell.x * float(columns) + gap * float(columns - 1)
			var used_height: float = cell.y * float(rows) + gap * float(rows - 1)

			if used_width > width + 0.5:
				failures.append("at %s with %d stickers the grid is %.0f wide in %.0f"
						% [str(area), total, used_width, width])
			# Only when the cards had room to grow past their minimum: a very
			# short page legitimately scrolls rather than shrinking the cards
			# below a three-year-old's finger.
			if cell.x > minimum.x + 0.5 and used_height > height + 0.5:
				failures.append("at %s with %d stickers the grid is %.0f tall in %.0f"
						% [str(area), total, used_height, height])

		# A page that has not been laid out yet must fall back to the minimum,
		# never to zero or to something enormous.
		var unlaid: Vector2 = StickerBookScreenScript.cell_size(width, 0.0, 6, 16)
		if unlaid != minimum:
			failures.append("with no page height the card is %s, expected the minimum %s"
					% [str(unlaid), str(minimum)])

	return failures
