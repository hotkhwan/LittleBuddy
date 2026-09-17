@tool
extends TextureRect

## One star in a 0-3 level rating.
##
## ## Why this is not an `IconGlyph` with a paler tint
##
## `docs/ART_BIBLE.md` §8 is specific, and it is specific because this is the
## most emotionally loaded element in the game:
##
## > Earned `#FFC73D`; next `#FFE199` pulsing; unearned `#E8DCC8` outline only --
## > **a ghost, not an empty slot.**
##
## A tinted copy of the solid star glyph cannot be an outline. The screen this
## replaces faded the *filled* star to 45% alpha instead, which composites to a
## pale solid blob on cream. Three of those in a row is precisely the "empty
## slot" the bible forbids, and after a 0-star run it was the entire message:
## three pale holes where the reward should be, under a gold star reading "+0".
##
## So there are two textures, and the outline one is *the same path*: `star.svg`
## scaled to 92.5% about its own centre and stroked at 0.52 units so the stroke's
## outer edge lands back on the original silhouette. The gold star and the ghost
## star therefore share one outline at every size -- one glyph, two states, no
## second star added to the icon family (§8: "one shared glyph at every size").
##
## ## The three states
##
## `EARNED`  the child has this one.
## `NEXT`    the first one they have not: warm, brighter than a ghost, and
##           breathing gently, so even a 0-star row has something alive on it
##           saying "there is one waiting here" rather than "you got none".
## `GHOST`   further out. Quiet, warm, still unmistakably a star.
##
## ## Alpha carries meaning, deliberately
##
## Only `EARNED` paints at alpha 1.0. The two unearned states sit one step back
## (0.95 / 0.90) -- a real, small recession, and the same difference
## `test_level_summary.gd::_expect_filled()` counts to decide how many stars a
## child is being shown. Raise the ghost to 1.0 and that case would count every
## star as earned and go quietly green, so `test_ui_palette.gd` pins the
## invariant rather than leaving it to a comment.
##
## Purely decorative: `MOUSE_FILTER_IGNORE`, so it can sit inside a `Button`
## without stealing the press.

const _Palette := preload("res://scripts/ui/palette.gd")

const STAR_FILLED_PATH: String = "res://assets/ui/icons/star.svg"
const STAR_OUTLINE_PATH: String = "res://assets/ui/icons/star_outline.svg"

enum State { EARNED, NEXT, GHOST }

## Only an earned star is fully present. See the note above.
const ALPHA_EARNED: float = 1.0
const ALPHA_NEXT: float = 0.95
const ALPHA_GHOST: float = 0.90

## ~0.6 Hz, per the art bible: one unhurried breath in and out.
const PULSE_PERIOD: float = 1.0 / 0.6
## Kept small. On a screen a four-year-old holds 30 cm from their face, a big
## throb is agitating rather than inviting.
const PULSE_SCALE: float = 0.07
const PULSE_FADE: float = 0.18

@export var state: State = State.GHOST:
	set(value):
		state = value
		_apply_state()

## The colour actually painted, exposed so it can be read back in a test without
## a rendering pass. Driven by `state`; setting it directly is not meaningful.
var tint: Color = Color(1.0, 1.0, 1.0, 1.0)

var _tween: Tween = null


func _init() -> void:
	# Same setup as `icon_glyph.gd`: the TextureRect default reports the full
	# 240 px source as its minimum size, which blows open every container it sits
	# in.
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_state()


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_apply_state()


# ---------------------------------------------------------------------------
# The contract, static so it can be reasoned about without a scene tree
# ---------------------------------------------------------------------------

## The colour each state paints in, alpha included.
static func color_for(star_state: int) -> Color:
	match star_state:
		State.EARNED:
			return Color(_Palette.STAR_EARNED, ALPHA_EARNED)
		State.NEXT:
			return Color(_Palette.STAR_NEXT, ALPHA_NEXT)
		_:
			return Color(_Palette.STAR_GHOST, ALPHA_GHOST)


## Solid glyph or outline glyph. Only an earned star is ever filled: a filled
## pale star is an empty slot, which is the thing the bible bans.
static func texture_path_for(star_state: int) -> String:
	return STAR_FILLED_PATH if star_state == State.EARNED else STAR_OUTLINE_PATH


## `index` is 0-based; `earned` is how many of the row are lit. Exactly one star
## is ever `NEXT` -- the first unearned one.
static func state_for(index: int, earned: int) -> int:
	if index < earned:
		return State.EARNED
	if index == earned:
		return State.NEXT
	return State.GHOST


# ---------------------------------------------------------------------------

func set_state(value: int) -> void:
	state = value as State


func _apply_state() -> void:
	var path: String = texture_path_for(state)
	texture = load(path) if ResourceLoader.exists(path) else null
	tint = color_for(state)
	self_modulate = tint
	_apply_pulse()


func _apply_pulse() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	scale = Vector2.ONE
	modulate.a = 1.0

	# `is_inside_tree()` keeps the headless runner honest -- `_ready()` never
	# fires for a node added to the root there, and `create_tween()` needs a tree.
	if state != State.NEXT or Engine.is_editor_hint() or not is_inside_tree():
		return

	pivot_offset = size * 0.5
	_tween = create_tween().set_loops()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * (1.0 + PULSE_SCALE), PULSE_PERIOD * 0.5)
	_tween.parallel().tween_property(self, "modulate:a", 1.0 - PULSE_FADE, PULSE_PERIOD * 0.5)
	_tween.tween_property(self, "scale", Vector2.ONE, PULSE_PERIOD * 0.5)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, PULSE_PERIOD * 0.5)


func _on_resized() -> void:
	pivot_offset = size * 0.5
