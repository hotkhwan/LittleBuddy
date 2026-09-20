extends Control

## A PROCEDURAL FLASHCARD: one big simple picture and the English word under
## it, drawn in `_draw()` for each id on the tutor assets allowlist. The same
## control is the HUD's picture card and, through a `SubViewport`, the texture
## on the classroom's lesson board -- so the card on the wall and the card in
## the child's hand are the same drawing.
##
## Chrome (card, rim, word) is palette-only. The PICTURE colours are content,
## not chrome: an apple is red and a banana is yellow, and a colour card that is
## not its own colour teaches the wrong word. They are pastel and warm, listed
## once below, and none of them is black.

const Palette := preload("res://scripts/ui/palette.gd")

## Picture colours (content, see the class doc).
const APPLE_RED: Color = Color(0.937, 0.451, 0.416)
const BANANA_YELLOW: Color = Color(1.0, 0.851, 0.400)
const ORANGE_ORANGE: Color = Color(1.0, 0.663, 0.318)
const GRAPE_PURPLE: Color = Color(0.686, 0.541, 0.859)
const LEAF_GREEN: Color = Color(0.522, 0.769, 0.529)
const SKY_BLUE: Color = Color(0.522, 0.694, 0.910)
const CAT_PEACH: Color = Color(1.0, 0.800, 0.620)
const DOG_BROWN: Color = Color(0.792, 0.612, 0.435)
const STEM_BROWN: Color = Palette.INK_SOFT

const WORDS: Dictionary = {
	"apple_red": "apple", "banana_yellow": "banana", "cat": "cat", "dog": "dog",
	"number_1": "one", "number_2": "two", "number_3": "three",
	"color_blue": "blue", "color_green": "green", "color_red": "red", "color_yellow": "yellow",
	"orange_orange": "orange", "grapes_purple": "grapes",
}

const CARD_RADIUS_FRACTION: float = 0.09
const RIM_PX: float = 6.0

var asset_id: String = "apple_red":
	set(value):
		asset_id = value
		queue_redraw()
## Draw the word strip under the picture. The 3D board turns it off when it
## shows the word on its own label.
var show_word: bool = true:
	set(value):
		show_word = value
		queue_redraw()
var word_font_size: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


static func word_for(id: String) -> String:
	return String(WORDS.get(id, id.replace("_", " ")))


static func known_ids() -> Array:
	return WORDS.keys()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 1.0 or h <= 1.0:
		return
	# The card.
	var radius: float = minf(w, h) * CARD_RADIUS_FRACTION
	var rim: StyleBoxFlat = StyleBoxFlat.new()
	rim.bg_color = Palette.deep(Palette.PEACH)
	rim.set_corner_radius_all(int(radius))
	draw_style_box(rim, Rect2(Vector2.ZERO, size))
	var face: StyleBoxFlat = StyleBoxFlat.new()
	face.bg_color = Palette.CREAM
	face.set_corner_radius_all(int(maxf(radius - RIM_PX, 2.0)))
	draw_style_box(face, Rect2(Vector2(RIM_PX, RIM_PX), size - Vector2(RIM_PX, RIM_PX) * 2.0))

	# The picture area: a square in the top part, the word strip beneath.
	var strip: float = h * 0.22 if show_word else 0.0
	var area: Rect2 = Rect2(Vector2(w * 0.1, h * 0.08), Vector2(w * 0.8, h - strip - h * 0.14))
	var side: float = minf(area.size.x, area.size.y)
	var centre: Vector2 = area.get_center()
	_draw_picture(asset_id, centre, side)

	if show_word:
		var font: Font = ThemeDB.fallback_font
		var font_size: int = word_font_size if word_font_size > 0 else int(h * 0.13)
		var text: String = word_for(asset_id)
		var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size)
		var baseline: Vector2 = Vector2((w - text_size.x) * 0.5, h - strip * 0.5 + text_size.y * 0.32)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Palette.INK)


func _draw_picture(id: String, c: Vector2, s: float) -> void:
	var r: float = s * 0.5
	match id:
		"apple_red":
			draw_circle(c + Vector2(-r * 0.28, r * 0.08), r * 0.62, APPLE_RED)
			draw_circle(c + Vector2(r * 0.28, r * 0.08), r * 0.62, APPLE_RED)
			draw_circle(c + Vector2(0.0, r * 0.22), r * 0.66, APPLE_RED)
			draw_rect(Rect2(c + Vector2(-r * 0.05, -r * 0.9), Vector2(r * 0.1, r * 0.42)), STEM_BROWN)
			_leaf(c + Vector2(r * 0.3, -r * 0.72), r * 0.3, 0.6)
			draw_circle(c + Vector2(-r * 0.32, -r * 0.18), r * 0.14, Color(1, 1, 1, 0.55))
		"banana_yellow":
			_banana(c, r, BANANA_YELLOW)
		"orange_orange":
			draw_circle(c + Vector2(0.0, r * 0.1), r * 0.78, ORANGE_ORANGE)
			_leaf(c + Vector2(r * 0.18, -r * 0.72), r * 0.34, 0.2)
			draw_circle(c + Vector2(-r * 0.3, -r * 0.18), r * 0.14, Color(1, 1, 1, 0.5))
		"grapes_purple":
			var rr: float = r * 0.24
			var rows: Array = [[-1.5, -0.5, 0.5, 1.5], [-1.0, 0.0, 1.0], [-0.5, 0.5], [0.0]]
			for row: int in range(rows.size()):
				for col in rows[row]:
					draw_circle(c + Vector2(float(col) * rr * 1.9, (-0.85 + float(row) * 0.95) * rr * 1.7), rr, GRAPE_PURPLE)
			draw_rect(Rect2(c + Vector2(-r * 0.04, -r * 0.98), Vector2(r * 0.08, r * 0.28)), STEM_BROWN)
			_leaf(c + Vector2(r * 0.3, -r * 0.8), r * 0.3, 0.5)
		"cat":
			_animal(c, r, CAT_PEACH, true)
		"dog":
			_animal(c, r, DOG_BROWN, false)
		"number_1", "number_2", "number_3":
			var n: int = int(id.split("_")[1])
			draw_circle(c, r * 0.82, Palette.LAVENDER)
			var font: Font = ThemeDB.fallback_font
			var fs: int = int(r * 1.15)
			var text: String = str(n)
			var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs)
			draw_string(font, c + Vector2(-ts.x * 0.5, ts.y * 0.28), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Palette.INK)
			for i: int in range(n):
				var x: float = (float(i) - float(n - 1) * 0.5) * r * 0.36
				draw_circle(c + Vector2(x, r * 0.98), r * 0.11, Palette.STAR_EARNED)
		"color_blue", "color_green", "color_red", "color_yellow":
			var colour: Color = {
				"color_blue": SKY_BLUE, "color_green": LEAF_GREEN,
				"color_red": APPLE_RED, "color_yellow": BANANA_YELLOW,
			}[id]
			var swatch: StyleBoxFlat = StyleBoxFlat.new()
			swatch.bg_color = colour
			swatch.set_corner_radius_all(int(r * 0.3))
			draw_style_box(swatch, Rect2(c - Vector2(r * 0.8, r * 0.8), Vector2(r * 1.6, r * 1.6)))
			draw_circle(c + Vector2(-r * 0.35, -r * 0.35), r * 0.16, Color(1, 1, 1, 0.5))
		_:
			draw_circle(c, r * 0.7, Palette.MINT)


func _leaf(at: Vector2, length: float, tilt: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(14):
		var t: float = float(i) / 13.0 * TAU
		var p: Vector2 = Vector2(cos(t) * length, sin(t) * length * 0.42).rotated(-0.6 - tilt)
		points.append(at + p)
	draw_colored_polygon(points, LEAF_GREEN)


func _banana(c: Vector2, r: float, colour: Color) -> void:
	var outer: PackedVector2Array = PackedVector2Array()
	var inner: PackedVector2Array = PackedVector2Array()
	# A fat crescent: the outer arc is a circle, the inner one a flatter,
	# higher circle, so the middle is thick and the tips taper.
	var steps: int = 24
	for i: int in range(steps + 1):
		var f: float = float(i) / float(steps)
		var t: float = lerpf(0.08, 0.92, f) * PI
		outer.append(c + Vector2(cos(t) * r * 0.95, sin(t) * r * 0.95 - r * 0.3))
		inner.append(c + Vector2(cos(t) * r * 0.95, sin(t) * r * 0.42 - r * 0.3))
	inner.reverse()
	outer.append_array(inner)
	draw_colored_polygon(outer, colour)
	draw_circle(c + Vector2(-r * 0.93, -r * 0.24), r * 0.08, STEM_BROWN)
	draw_circle(c + Vector2(r * 0.93, -r * 0.24), r * 0.08, STEM_BROWN)


func _animal(c: Vector2, r: float, colour: Color, is_cat: bool) -> void:
	if is_cat:
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.62, -r * 0.2), c + Vector2(-r * 0.58, -r * 0.95), c + Vector2(-r * 0.1, -r * 0.55)]), colour)
		draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.62, -r * 0.2), c + Vector2(r * 0.58, -r * 0.95), c + Vector2(r * 0.1, -r * 0.55)]), colour)
	draw_circle(c, r * 0.7, colour)
	if not is_cat:
		draw_circle(c + Vector2(-r * 0.7, -r * 0.05), r * 0.26, STEM_BROWN)
		draw_circle(c + Vector2(r * 0.7, -r * 0.05), r * 0.26, STEM_BROWN)
		draw_circle(c + Vector2(-r * 0.7, r * 0.3), r * 0.24, STEM_BROWN)
		draw_circle(c + Vector2(r * 0.7, r * 0.3), r * 0.24, STEM_BROWN)
	# Eyes, nose, smile -- ink, never black.
	draw_circle(c + Vector2(-r * 0.26, -r * 0.1), r * 0.08, Palette.INK)
	draw_circle(c + Vector2(r * 0.26, -r * 0.1), r * 0.08, Palette.INK)
	draw_circle(c + Vector2(0.0, r * 0.12), r * 0.07, Palette.SOFT_PINK if is_cat else Palette.INK)
	draw_arc(c + Vector2(-r * 0.1, r * 0.16), r * 0.12, 0.2, PI - 0.2, 10, Palette.INK, r * 0.03)
	draw_arc(c + Vector2(r * 0.1, r * 0.16), r * 0.12, 0.2, PI - 0.2, 10, Palette.INK, r * 0.03)
	if is_cat:
		for side: float in [-1.0, 1.0]:
			for k: int in range(2):
				var y: float = r * (0.1 + 0.12 * float(k))
				draw_line(c + Vector2(side * r * 0.25, y), c + Vector2(side * r * 0.85, y + (float(k) - 0.5) * r * 0.16), Palette.INK, r * 0.025)
