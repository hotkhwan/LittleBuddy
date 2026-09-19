extends RefCounted

## Where the HUD's text is allowed to be, given what the camera is currently
## doing. Pure: Dictionaries and ints in, a Dictionary out. No node, no viewport,
## no tree, so every rule below can be asserted headlessly.
##
## ## The defect this module exists for
##
## `docs/WORLD_CAMERA_PASS.md` §7.1: during a close-up the status line, the task
## line, the Thai hint and the assist line occupied the top ~35% of the screen
## while the beat put the character dead centre, so the text sat on the face
## (`docs/shots/c_beat_counter_ipad.png`, `docs/shots/hud_feed_BEFORE_ipad.png`).
##
## That agent also proved it is **not fixable from the camera**: `solve()` aims at
## screen centre, so a bigger chrome inset only pushes the camera back and carries
## the overlap with it. The text has to move instead, and it has to move by a rule
## rather than by a nudge, because the free part of the screen is different at
## every beat.
##
## ## The rule
##
## A close-up's **radius** -- the half-width of the square `camera_focus.gd`
## composed -- already says which shot this is, and it is measured rather than
## guessed. Rendered from the two shipped missions:
##
## | beat | kind | radius |
## |---|---|---|
## | `walkToBathroom` | `travel` | no close-up |
## | `wakeUpBuddy`, `sayGoodMorning` | `choose` | 1.88 m |
## | `bananaOnCounter`, `mashTheBanana`, `carrySnackToBunny`, `feedBunnySnack` | `goAndDo` | 0.90 m |
##
## The two classes are 1 m apart and nothing lands between them, so one threshold
## separates them cleanly:
##
##   * **no close-up** -> `EXPLORE`. The room shot puts the child small and low;
##     the top of the frame is wall, and the full stack fits there.
##   * **wide close-up** (a row of objects to choose from) -> `PREPARE`. Still a
##     near-room shot, so the top still works -- but compacted, because the beat
##     is the subject now and 35% of the screen is not chrome's to take.
##   * **tight close-up** (one subject filling the middle) -> `FEED`. Nothing may
##     cross the centre at all: the text retreats to the left margin beneath the
##     stars, and the Thai hint stands down.
##
## `taskKind` overrides the measurement when a caller supplies it -- see
## `kind_mode()`. On every beat in both shipped missions the two agree, which is
## why the HUD needs nothing from the director to get this right today.
##
## ## COMPLETE is not a position, it is a subject
##
## The other three choose *where* the text goes. `COMPLETE` chooses *what is
## worth showing*: the task is done, so the instruction for it is noise, and the
## dot that just turned gold and the star total are the whole point. It keeps the
## interrupted mode's encouragement slot, lasts a moment, and is cancelled by the
## next prompt -- see `house_hud.gd`'s `REWARD_SECONDS`.

const MODE_EXPLORE: int = 0
const MODE_PREPARE: int = 1
const MODE_FEED: int = 2
const MODE_COMPLETE: int = 3

const MODE_NAMES: Array[String] = ["EXPLORE", "PREPARE", "FEED", "COMPLETE"]

## Where a close-up stops being "one subject in the middle" and becomes "a row of
## things spread across the room". Measured, not tuned: the tight beats compose
## 0.90 m (the `camera_focus.MIN_RADIUS` floor) and the choice rows compose
## 1.88 m. Anything inside that gap is a shot nobody has authored yet, and the
## safe answer for an unknown shot is the conservative layout, so the threshold
## sits deliberately near the BOTTOM of the gap.
const WIDE_SHOT_RADIUS: float = 1.30

## Below this a reported radius is not a close-up at all. `get_camera_focus()`
## returns 0.0 when the camera is holding the room shot.
const MIN_CLOSE_UP_RADIUS: float = 0.05

## ART_BIBLE §8: 27 pt at the 1366x1024 reference is the floor for any text a
## child is meant to read, and a "compact" mode is exactly where that rule gets
## quietly broken. Asserted in `test_hud_presentation.gd` against every size in
## every layout below.
const MIN_FONT_SIZE: int = 27

## The task kinds `house_task_plan.gd` produces, and the mode each one wants.
## A kind this does not name falls through to the measured radius.
const KIND_MODES: Dictionary = {
	"choose": MODE_PREPARE,
	"deliver": MODE_FEED,
	"goAndDo": MODE_FEED,
	"care": MODE_FEED,
}


static func mode_name(mode: int) -> String:
	if mode < 0 or mode >= MODE_NAMES.size():
		return "EXPLORE"
	return MODE_NAMES[mode]


static func mode_from_name(value: String) -> int:
	var index: int = MODE_NAMES.find(value.strip_edges().to_upper())
	return index if index >= 0 else -1


## The mode a task kind asks for, or -1 for "no opinion".
##
## Optional by design. Nothing calls it today: the HUD reaches the same answer
## from the radius on every beat in both shipped missions, so the director does
## not have to learn a new call for the defect to be fixed. It exists so that if
## a future beat ever composes a shot whose tightness misrepresents it, one line
## in the director can say so authoritatively instead of this file growing a
## special case.
static func kind_mode(kind: String) -> int:
	var key: String = kind.strip_edges()
	if not KIND_MODES.has(key):
		return -1
	return int(KIND_MODES[key])


## The mode for the current state.
##
## `state` keys, all optional:
##   `freePlay`     -- bool. Free Play has no objective, so it has no beat and no
##                     close-up worth reacting to: it is always EXPLORE.
##   `rewarding`    -- bool. A task completed a moment ago.
##   `focusRadius`  -- float. The live close-up's radius, 0.0 for the room shot.
##   `taskKind`     -- String. Authoritative when non-empty and recognised.
static func derive(state: Dictionary) -> int:
	if bool(state.get("freePlay", false)):
		return MODE_EXPLORE
	if bool(state.get("rewarding", false)):
		return MODE_COMPLETE
	return shot_mode(
		float(state.get("focusRadius", 0.0)), String(state.get("taskKind", ""))
	)


## The mode the *camera* is asking for, ignoring the reward moment. Split out
## because `COMPLETE` borrows this mode's encouragement slot rather than
## inventing a place of its own.
static func shot_mode(focus_radius: float, task_kind: String = "") -> int:
	var radius: float = focus_radius if is_finite(focus_radius) else 0.0
	if radius < MIN_CLOSE_UP_RADIUS:
		return MODE_EXPLORE
	var wanted: int = kind_mode(task_kind)
	if wanted >= 0:
		return wanted
	return MODE_PREPARE if radius >= WIDE_SHOT_RADIUS else MODE_FEED


## The layout for a mode, as plain numbers.
##
## Every rect is `[offsetLeft, offsetTop, offsetRight, offsetBottom]` against the
## anchor named beside it, in the project's reference pixels -- the same units
## `house_hud.gd` already authors its buttons in.
##
## Keys:
##   `promptAnchor`  -- "topWide" or "topLeft" (the left margin rail)
##   `promptRect`, `promptSize`, `promptLeftAligned`
##   `hintRect`, `hintSize`, `hintVisible`
##   `encouragementRect` (against BOTTOM_WIDE), `encouragementSize`
##   `promptVisible`  -- false only in COMPLETE
##   `starSize`
static func layout(mode: int) -> Dictionary:
	match mode:
		MODE_PREPARE:
			# Compacted, not moved. A `choose` shot is still nearly the room, so
			# the top of the frame is still wall -- but the stack drops from 248 px
			# to 102 px, which is 14% of an iPad's height instead of 33%.
			return {
				"promptAnchor": "topWide",
				"promptRect": [150.0, 90.0, -150.0, 146.0],
				"promptSize": 34,
				"promptLeftAligned": false,
				"promptInverted": false,
				"promptVisible": true,
				"hintRect": [150.0, 150.0, -150.0, 192.0],
				"hintSize": 27,
				"hintVisible": true,
				"encouragementRect": [260.0, -216.0, -260.0, -136.0],
				"encouragementSize": 36,
				"starSize": 34,
			}
		MODE_FEED:
			# The left margin, under the stars and the progress dots, left
			# aligned: one column of chrome down the edge and an empty middle.
			# It starts at y=160 rather than tucking straight under the dots
			# because `onboarding_director.gd`'s caption owns y 52..156 on a first
			# run, and two cream lines in the same place is the defect again in
			# miniature.
			return {
				"promptAnchor": "topLeft",
				"promptRect": [36.0, 160.0, 436.0, 268.0],
				"promptSize": 30,
				"promptLeftAligned": true,
				# Ink on a cream outline, the opposite way round from every other
				# line in this HUD and for the same reason the Free Play word card
				# is: the rail sits in the left margin, and in a close-up the left
				# margin is a pale cream wall almost every time. Cream-on-cream
				# with a thin ink edge rendered legible-but-weak; ink reads at a
				# glance, and the cream outline keeps it readable if the rail ever
				# lands on the wardrobe instead.
				"promptInverted": true,
				"promptVisible": true,
				# Hidden, not deleted. See `house_hud.gd`'s note on why that is
				# safe for a hint specifically.
				"hintRect": [36.0, 272.0, 436.0, 320.0],
				"hintSize": 27,
				"hintVisible": false,
				"encouragementRect": [260.0, -216.0, -260.0, -136.0],
				"encouragementSize": 36,
				"starSize": 34,
			}
		MODE_COMPLETE:
			# Nothing to instruct: it is done. The dot that just turned gold and
			# the star total are what the child should be looking at, so the star
			# count grows and the praise takes the bottom band on its own.
			return {
				"promptAnchor": "topWide",
				"promptRect": [150.0, 132.0, -150.0, 232.0],
				"promptSize": 42,
				"promptLeftAligned": false,
				"promptInverted": false,
				"promptVisible": false,
				"hintRect": [150.0, 236.0, -150.0, 288.0],
				"hintSize": 27,
				"hintVisible": false,
				"encouragementRect": [260.0, -224.0, -260.0, -136.0],
				"encouragementSize": 44,
				"starSize": 42,
			}
		_:
			# EXPLORE: the room shot, and the only change from what shipped is
			# that the assist line is no longer a fourth line in the same column.
			return {
				"promptAnchor": "topWide",
				"promptRect": [150.0, 132.0, -150.0, 232.0],
				"promptSize": 42,
				"promptLeftAligned": false,
				"promptInverted": false,
				"promptVisible": true,
				"hintRect": [150.0, 236.0, -150.0, 288.0],
				"hintSize": 27,
				"hintVisible": true,
				"encouragementRect": [260.0, -216.0, -260.0, -136.0],
				"encouragementSize": 36,
				"starSize": 34,
			}


## How much of a `viewport_size`-tall screen this mode's text stack occupies at
## the top, in pixels. The P0 number: it was 248 px of 750 (33%) at every beat,
## and a test now holds the close-up modes well under that.
static func top_stack_height(mode: int) -> float:
	var l: Dictionary = layout(mode)
	if String(l["promptAnchor"]) != "topWide":
		return 0.0
	var bottom: float = float((l["promptRect"] as Array)[3]) if bool(l["promptVisible"]) else 0.0
	if bool(l["hintVisible"]):
		bottom = maxf(bottom, float((l["hintRect"] as Array)[3]))
	return maxf(bottom, 0.0)


## Every font size a mode authors, for the ART_BIBLE §8 floor check.
static func font_sizes(mode: int) -> Array:
	var l: Dictionary = layout(mode)
	return [int(l["promptSize"]), int(l["hintSize"]),
			int(l["encouragementSize"]), int(l["starSize"])]
