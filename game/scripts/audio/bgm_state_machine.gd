class_name BgmStateMachine
extends RefCounted
## Which piece of music the game wants, and how long it may take to get there.
##
## Four musical situations, plus silence:
##
##     silent    -> nothing playing (boot, parent settings, a paused session)
##     menu      -> title and menu screens
##     house     -> free exploration of the house
##     miniGame  -> a mission or activity is running
##     reward    -> stars, stickers, celebration
##
## The state is deliberately NOT "which track". A caller says *where the child
## is*; the manifest decides what that sounds like, and a scene with no track
## simply plays nothing. That is what lets music arrive later without a single
## gameplay file changing.
##
## ## Every transition is a crossfade, and the minimum is not zero
##
## `FADE_SECONDS` has no entry below `MIN_FADE_SECONDS`, and `fade_seconds_to()`
## enforces that floor. A hard cut is a transient, and a transient is the one
## thing a 4-year-old holding an iPad 30 cm from their face should never get --
## the same reasoning that gives every SFX in this project a measured attack
## ramp (see `test_audio_assets.gd`).
##
## ## Reward is a visit, not a destination
##
## `request_return()` exists because a celebration interrupts something and then
## gives it back. The machine remembers one step of history so the caller does
## not have to.
##
## Pure logic: no `Node`, no `AudioStream`, no 3D types. Testable without a tree.

const STATE_SILENT: String = "silent"
const STATE_MENU: String = "menu"
const STATE_HOUSE: String = "house"
const STATE_MINI_GAME: String = "miniGame"
const STATE_REWARD: String = "reward"

const STATES: Array[String] = [
	STATE_SILENT,
	STATE_MENU,
	STATE_HOUSE,
	STATE_MINI_GAME,
	STATE_REWARD,
]

## Seconds to fade INTO each state. Fading out of the old track shares the same
## duration, so the two curves cross in the middle and the total energy stays
## roughly flat instead of dipping to silence between tracks.
##
## The numbers are a judgement, but the shape is not: arriving somewhere exciting
## is quicker than settling into somewhere calm, and going quiet is unhurried
## because a fade-out that the child notices is a fade-out that interrupts.
const FADE_SECONDS: Dictionary = {
	STATE_SILENT: 1.4,
	STATE_MENU: 1.5,
	STATE_HOUSE: 1.2,
	STATE_MINI_GAME: 0.8,
	STATE_REWARD: 0.5,
}

## No transition may be shorter than this. See the class docs: a hard cut is a
## startle, and there is no situation in a caregiving game that needs one.
const MIN_FADE_SECONDS: float = 0.25
const MAX_FADE_SECONDS: float = 4.0

# -- Outcomes of a request. --------------------------------------------------

const OUTCOME_CHANGED: String = "changed"
const OUTCOME_SAME_STATE: String = "sameState"
const OUTCOME_UNKNOWN_STATE: String = "unknownState"

var _state: String = STATE_SILENT
var _previous_state: String = STATE_SILENT


static func is_known_state(state: String) -> bool:
	return STATES.has(state)


func state() -> String:
	return _state


## The state before the current one. After `menu -> reward` this is `menu`, which
## is where `request_return()` goes back to.
func previous_state() -> String:
	return _previous_state


## Asks for `state`.
##
## Returns `{"outcome", "from", "to", "fadeSeconds"}`. `outcome` is
## `changed` when the state moved, `sameState` when the request was already
## satisfied (a no-op the caller should not act on), or `unknownState` when the
## name is not one of `STATES` -- in which case NOTHING changes. A typo must not
## silence the game.
func request(state: String) -> Dictionary:
	if not is_known_state(state):
		return {
			"outcome": OUTCOME_UNKNOWN_STATE,
			"from": _state,
			"to": _state,
			"fadeSeconds": 0.0,
		}
	if state == _state:
		return {
			"outcome": OUTCOME_SAME_STATE,
			"from": _state,
			"to": _state,
			"fadeSeconds": 0.0,
		}
	var from: String = _state
	_previous_state = from
	_state = state
	return {
		"outcome": OUTCOME_CHANGED,
		"from": from,
		"to": _state,
		"fadeSeconds": fade_seconds_to(_state),
	}


## Goes back to where the music was before the current state. Used after a
## celebration. When there is nowhere to return to this is a no-op.
func request_return() -> Dictionary:
	return request(_previous_state)


## How long the fade into `state` lasts, floored at `MIN_FADE_SECONDS` so no
## caller and no future table edit can produce a hard cut.
static func fade_seconds_to(state: String) -> float:
	var declared: float = float(FADE_SECONDS.get(state, MIN_FADE_SECONDS))
	return clampf(declared, MIN_FADE_SECONDS, MAX_FADE_SECONDS)


## Resets to silence without recording history. For a fresh session.
func reset() -> void:
	_state = STATE_SILENT
	_previous_state = STATE_SILENT
