extends RefCounted

## The locked palette, in one place, as code.
##
## `docs/ART_BIBLE.md` §3 is the source of truth and it is LOCKED. Until now the
## seven tokens existed only as hand-typed `Color(...)` literals scattered across
## a dozen `.tscn` files, which is how `#000000` and a near-red get in: nobody
## typing `Color(0.9, 0.2, 0.2, 1)` into an inspector field thinks of themselves
## as inventing a colour.
##
## This file exists so that
##
##   * a screen can say `Palette.INK` instead of four decimals, and
##   * `test_ui_palette.gd` can assert, mechanically, that every colour the UI
##     actually ships is one of these or a documented derivation of them.
##
## Engine-agnostic by design: `Color` is a core type, not a 3D one, so this
## stays on the right side of the `test_architecture_guard.gd` line.
##
## **Never add a colour here without adding it to the art bible first.** The
## bible locks; this follows.

# --- The seven tokens (§3) -------------------------------------------------

const CREAM: Color = Color(1.0, 0.965, 0.898)        # #FFF6E5
const DUSTY_BLUE: Color = Color(0.604, 0.753, 0.851) # #9AC0D9
const SOFT_PINK: Color = Color(1.0, 0.757, 0.800)    # #FFC1CC
const MINT: Color = Color(0.659, 0.902, 0.812)       # #A8E6CF
const PEACH: Color = Color(1.0, 0.827, 0.714)        # #FFD3B6
const LAVENDER: Color = Color(0.839, 0.780, 0.941)   # #D6C7F0
const INK: Color = Color(0.349, 0.259, 0.169)        # #59422B -- the only "dark"

# --- Semantic roles (§3) ---------------------------------------------------

## Body copy that is not the headline.
const INK_SOFT: Color = Color(0.541, 0.451, 0.345)   # #8A7358

## The single most important colour in the game.
const STAR_EARNED: Color = Color(1.0, 0.780, 0.239)  # #FFC73D
## The one still within reach. Pulses at ~0.6 Hz; never a different hue from
## `STAR_EARNED`, because it is a promise of the same thing.
const STAR_NEXT: Color = Color(1.0, 0.882, 0.600)    # #FFE199
## Not yet earned. A warm GHOST, drawn as an outline -- never grey, never a
## slot, never crossed out. If this ever tests as grey the screen has started
## telling a four-year-old they came up short.
const STAR_GHOST: Color = Color(0.910, 0.863, 0.784) # #E8DCC8

## Marks a control as belonging to a grown-up.
const PARENT_CHROME: Color = LAVENDER

## The scrim behind a celebratory panel. Warm `ink`, never black: pure black in a
## pastel scene reads as a hole punched in the picture.
const SCRIM: Color = Color(0.349, 0.259, 0.169, 0.42)

# --- Derivations (§3: "exactly three steps") -------------------------------

## Light = 45% toward `cream`. Deep = 22% toward `ink`. Never darken by value
## alone -- mixing toward `ink` is what keeps a shadow warm.
static func light(base: Color) -> Color:
	return base.lerp(CREAM, 0.45)


static func deep(base: Color) -> Color:
	return base.lerp(INK, 0.22)


# --- Rules a test can ask about --------------------------------------------

## Pure black, in any alpha. Banned everywhere (§3).
static func is_black(color: Color) -> bool:
	return is_zero_approx(color.r) and is_zero_approx(color.g) and is_zero_approx(color.b)


## Red, or near enough to read as one. Banned as a UI colour (§3, and `CLAUDE.md`
## has no red X and no failure colour).
##
## "Red" here means a colour whose red channel dominates BOTH others by a clear
## margin while being saturated enough to read as a hue rather than as a warm
## neutral. That admits `peach` (#FFD3B6, barely saturated), `softPink`
## (#FFC1CC, pink not red) and `ink` (#59422B, a brown), and rejects anything a
## child would read as a warning.
static func is_red(color: Color) -> bool:
	var top: float = maxf(color.r, maxf(color.g, color.b))
	var bottom: float = minf(color.r, minf(color.g, color.b))
	if top <= 0.0:
		return false
	var saturation: float = (top - bottom) / top
	if saturation < 0.45:
		return false
	if color.r < color.g or color.r < color.b:
		return false
	# Hue within +/-20 degrees of pure red.
	var hue: float = color.h
	return hue < 0.055 or hue > 0.945


## A colour with no warmth left in it -- the thing an unearned star must never
## become. Grey is the difference between "one still to find" and "you failed".
static func is_grey(color: Color) -> bool:
	var top: float = maxf(color.r, maxf(color.g, color.b))
	var bottom: float = minf(color.r, minf(color.g, color.b))
	if top <= 0.0:
		return true
	return (top - bottom) / top < 0.06
