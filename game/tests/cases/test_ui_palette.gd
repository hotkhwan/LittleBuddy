extends RefCounted

## The locked palette, enforced instead of remembered.
##
## `docs/ART_BIBLE.md` §3 is LOCKED and says three things that had no guard at
## all until this file existed:
##
##   * **`#000000` is banned everywhere** -- text, outlines, eyes, UI, shadow
##     colour. Pure black in a pastel scene reads as a hole punched in the
##     picture. `ink` `#59422B` is the only dark.
##   * **Red is banned as a UI colour**, and so is anything near it. There is no
##     failure colour in this game; try-again is `peach`.
##   * **An unearned star is `#E8DCC8`, a warm ghost, outline only -- never grey
##     and never an "empty slot."** It shipped as a 45%-alpha copy of the *solid*
##     star, which composites to a pale blob: three of them in a row after a
##     0-star run was the entire message the child got.
##
## Scope is deliberately split, and the failure messages say which is which:
## the black ban is project-wide (nothing in the repo violates it today, so it
## can only ever catch a regression), while the red ban covers the screens this
## agent owns. Widening the red ban is a good idea and a separate change -- it
## would currently also have an opinion about the deep rose the baby room prints
## its sticker caption in, which is a judgement call, not a defect.

const _Palette := preload("res://scripts/ui/palette.gd")
const _RatingStar := preload("res://scripts/ui/rating_star.gd")

## Everything, because pure black is never right anywhere.
const BLACK_BAN_DIRS: Array[String] = ["res://scenes", "res://scripts", "res://assets/ui"]

## The screens this phase owns.
const UI_DIRS: Array[String] = [
	"res://scenes/main",
	"res://scenes/progression",
	"res://scripts/ui",
]

## `#000000` exactly, plus the "I nudged it off zero" near misses that read
## identically on a screen.
const BLACK_EPSILON: float = 0.02

## The art bible's own hex values. If a constant in `palette.gd` drifts from the
## locked document, that is a defect in the code, not in the document.
const LOCKED_TOKENS: Dictionary = {
	"cream": "fff6e5",
	"dustyBlue": "9ac0d9",
	"softPink": "ffc1cc",
	"mint": "a8e6cf",
	"peach": "ffd3b6",
	"lavender": "d6c7f0",
	"ink": "59422b",
}

const LOCKED_STARS: Dictionary = {
	"star earned": "ffc73d",
	"star next": "ffe199",
	"star unearned (ghost)": "e8dcc8",
}


func test_name() -> String:
	return "ui_palette"


func run():
	var failures: Array = []
	failures.append_array(_test_the_speak_button_is_mint())
	failures.append_array(_test_palette_matches_the_locked_document())
	failures.append_array(_test_no_pure_black_anywhere())
	failures.append_array(_test_no_red_in_the_owned_ui())
	failures.append_array(_test_unearned_star_is_a_warm_ghost())
	failures.append_array(_test_only_an_earned_star_is_opaque())
	return failures


# ---------------------------------------------------------------------------
# palette.gd vs the art bible
# ---------------------------------------------------------------------------

func _test_palette_matches_the_locked_document():
	var failures: Array = []

	var tokens: Dictionary = {
		"cream": _Palette.CREAM, "dustyBlue": _Palette.DUSTY_BLUE,
		"softPink": _Palette.SOFT_PINK, "mint": _Palette.MINT,
		"peach": _Palette.PEACH, "lavender": _Palette.LAVENDER,
		"ink": _Palette.INK,
	}
	for name: String in LOCKED_TOKENS.keys():
		failures.append_array(_expect_hex(name, tokens[name], String(LOCKED_TOKENS[name])))

	var stars: Dictionary = {
		"star earned": _Palette.STAR_EARNED,
		"star next": _Palette.STAR_NEXT,
		"star unearned (ghost)": _Palette.STAR_GHOST,
	}
	for name: String in LOCKED_STARS.keys():
		failures.append_array(_expect_hex(name, stars[name], String(LOCKED_STARS[name])))

	return failures


## Within half a 0-255 step, which is as close as a `Color(r, g, b)` literal
## written to three decimals can get.
func _expect_hex(name: String, color: Color, expected_hex: String):
	var expected: Color = Color.html(expected_hex)
	var delta: float = maxf(absf(color.r - expected.r),
			maxf(absf(color.g - expected.g), absf(color.b - expected.b)))
	if delta > 0.003:
		return ["palette: %s is #%s; ART_BIBLE.md section 3 locks it to #%s"
				% [name, color.to_html(false), expected_hex.to_upper()]]
	return []


# ---------------------------------------------------------------------------
# Pure black
# ---------------------------------------------------------------------------

func _test_no_pure_black_anywhere():
	var failures: Array = []
	var scanned: int = 0

	for dir_path: String in BLACK_BAN_DIRS:
		for path: String in _files_under(dir_path, [".tscn", ".gd", ".tres", ".svg"]):
			scanned += 1
			var text: String = _code_of(path)
			if text.is_empty():
				continue

			for color: Color in _colors_in(text):
				if _is_black(color):
					failures.append(
						"%s uses Color(%.3f, %.3f, %.3f) -- ART_BIBLE.md section 3 bans #000000 "
						% [path, color.r, color.g, color.b]
						+ "everywhere; a pure black in a pastel scene reads as a hole. Use ink #59422B.")

			for hex: String in _hex_colors_in(text):
				if _is_black(Color.html(hex)):
					failures.append("%s uses #%s; ART_BIBLE.md section 3 bans pure black. Use ink #59422B."
							% [path, hex])

	if scanned == 0:
		failures.append("ui_palette: the black scan found no files at all; it is vacuous")

	return failures


# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------

func _test_no_red_in_the_owned_ui():
	var failures: Array = []
	var scanned: int = 0

	for dir_path: String in UI_DIRS:
		for path: String in _files_under(dir_path, [".tscn", ".gd"]):
			scanned += 1
			var text: String = _code_of(path)
			for color: Color in _colors_in(text):
				if _Palette.is_red(color):
					failures.append(
						"%s uses Color(%.3f, %.3f, %.3f) (#%s), which reads as red. "
						% [path, color.r, color.g, color.b, color.to_html(false)]
						+ "ART_BIBLE.md section 3 bans red as a UI colour; try-again is peach #FFD3B6.")

	if scanned == 0:
		failures.append("ui_palette: the red scan found no files at all; it is vacuous")

	return failures


# ---------------------------------------------------------------------------
# The star row
# ---------------------------------------------------------------------------

func _test_unearned_star_is_a_warm_ghost():
	var failures: Array = []

	var ghost: Color = _RatingStar.color_for(_RatingStar.State.GHOST)
	if _Palette.is_grey(ghost):
		failures.append(
			"the unearned star is #%s, which has no warmth left in it. " % ghost.to_html(false)
			+ "ART_BIBLE.md section 8: it is a warm GHOST (#E8DCC8), never grey -- grey is the "
			+ "difference between 'one still to find' and 'you failed'.")
	if ghost.r <= ghost.b:
		failures.append("the unearned star #%s is not warm; it must sit on the cream side of neutral"
				% ghost.to_html(false))

	# Outline, not a faded fill. A pale SOLID star is the "empty slot" the bible
	# bans by name, and it is what this screen used to draw.
	for state: int in [_RatingStar.State.GHOST, _RatingStar.State.NEXT]:
		var path: String = _RatingStar.texture_path_for(state)
		if path != _RatingStar.STAR_OUTLINE_PATH:
			failures.append(
				"an unearned star paints %s. ART_BIBLE.md section 8 says outline only: " % path
				+ "a pale filled star reads as an empty slot, not as a star still to find.")
		if not ResourceLoader.exists(path):
			failures.append("the unearned star points at %s, which does not exist" % path)

	var earned_path: String = _RatingStar.texture_path_for(_RatingStar.State.EARNED)
	if earned_path != _RatingStar.STAR_FILLED_PATH:
		failures.append("an earned star must paint the solid glyph, not %s" % earned_path)
	if not ResourceLoader.exists(earned_path):
		failures.append("the earned star points at %s, which does not exist" % earned_path)

	# Exactly one star is ever the pulsing "next" one, and only when there is one
	# left to find.
	if _RatingStar.state_for(0, 3) != _RatingStar.State.EARNED:
		failures.append("with three stars earned, the first star is not shown as earned")
	if _RatingStar.state_for(0, 0) != _RatingStar.State.NEXT:
		failures.append(
			"with no stars earned, the first star is not the 'next' one. That pulse is the only "
			+ "thing alive on a 0-star row; without it the row is three empty outlines.")
	if _RatingStar.state_for(2, 0) != _RatingStar.State.GHOST:
		failures.append("with no stars earned, the third star should be a quiet ghost")

	return failures


## The coupling `test_level_summary.gd::_expect_filled()` depends on.
##
## That case counts how many stars a child is being shown by looking for a tint
## at full alpha. Give the ghost alpha 1.0 and it counts all three as earned --
## and reports [PASS] while the screen shows a 0-star run as a perfect score.
func _test_only_an_earned_star_is_opaque():
	var failures: Array = []

	if not is_equal_approx(_RatingStar.color_for(_RatingStar.State.EARNED).a, 1.0):
		failures.append("an earned star must paint at full alpha")

	for state: int in [_RatingStar.State.NEXT, _RatingStar.State.GHOST]:
		if _RatingStar.color_for(state).a >= 1.0:
			failures.append(
				"an unearned star paints at full alpha. test_level_summary.gd counts earned stars "
				+ "by alpha, so this would make every 0-star summary silently assert as a 3-star "
				+ "one -- see the note in rating_star.gd.")

	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## A file's contents with GDScript comments removed.
##
## Without this the scan reads its own documentation: every file that *explains*
## the ban ("`#000000` is banned everywhere") would be reported as breaking it,
## and so would this one. `#` only opens a comment outside a string literal, so
## quoting is tracked rather than assumed.
func _code_of(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	if not path.ends_with(".gd"):
		return text

	var out: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n"):
		var quote: String = ""
		var escaped: bool = false
		var cut: int = -1
		for i: int in range(line.length()):
			var c: String = line[i]
			if escaped:
				escaped = false
			elif not quote.is_empty():
				if c == "\\":
					escaped = true
				elif c == quote:
					quote = ""
			elif c == "\"" or c == "'":
				quote = c
			elif c == "#":
				cut = i
				break
		out.append(line.substr(0, cut) if cut >= 0 else line)
	return "\n".join(out)


func _is_black(color: Color) -> bool:
	return color.r <= BLACK_EPSILON and color.g <= BLACK_EPSILON and color.b <= BLACK_EPSILON


## Every `Color(r, g, b[, a])` literal in `text`, as real Colors.
func _colors_in(text: String) -> Array:
	var found: Array = []
	var regex: RegEx = RegEx.new()
	regex.compile("Color\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)")
	for match: RegExMatch in regex.search_all(text):
		found.append(Color(
			float(match.get_string(1)), float(match.get_string(2)), float(match.get_string(3))))
	return found


## Every `#rrggbb` / `#rgb` literal, e.g. in an SVG fill or a `Color.html()` call.
func _hex_colors_in(text: String) -> Array:
	var found: Array = []
	var regex: RegEx = RegEx.new()
	regex.compile("#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\\b")
	for match: RegExMatch in regex.search_all(text):
		found.append(match.get_string(1))
	return found


static func _files_under(dir_path: String, suffixes: Array) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		for suffix: String in suffixes:
			if file_name.ends_with(suffix):
				found.append("%s/%s" % [dir_path, file_name])
				break
	for sub: String in dir.get_directories():
		found.append_array(_files_under("%s/%s" % [dir_path, sub], suffixes))
	return found


## ART_BIBLE section 3 assigns `mint` to the speak button twice -- in the palette
## row and again in the semantic-roles table. It is the colour this game uses to
## mean "go", which is exactly what inviting a child to speak is.
##
## The in-house HUD shipped it as `softPink`: a legal palette token, so no
## existing scan objected, but the wrong one and inconsistent with the Baby
## Room's speak control. Colour-by-role is the kind of rule that only a test can
## hold, because every candidate value is "in the palette".
func _test_the_speak_button_is_mint():
	var failures: Array = []

	var path: String = "res://scripts/gameplay/house_hud.gd"
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["ui_palette: could not read %s" % path]
	var source: String = file.get_as_text()
	file.close()

	var line: String = ""
	for raw: String in source.split("\n"):
		if raw.contains("\"SpeakButton\""):
			line = raw.strip_edges()
			break

	if line.is_empty():
		failures.append("ui_palette: no SpeakButton is created in %s; has it been renamed? "
				% path + "This check would then be silently guarding nothing.")
	elif not line.contains("MINT"):
		failures.append(
			("ui_palette: the speak button is tinted with something other than MINT (%s). "
			+ "ART_BIBLE section 3 assigns mint to it in two places, and mint is this game's "
			+ "\"go\" colour.") % line
		)

	return failures
