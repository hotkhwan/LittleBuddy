extends RefCounted

## ============================================================================
## WHAT LITTLE BUDDY NEEDS -- derived, never a parallel set of flags.
## ============================================================================
##
## The brief asks for nine child states and is explicit that they must be
## "coherent gameplay state, not unrelated visual flags". Nine independent
## booleans would be exactly that failure: they could contradict each other (a
## child both `sleepy` and `wantsToPlay`), drift out of step with `BabyState`,
## and give the presentation no way to decide what to show.
##
## So nothing here is stored. Every state is DERIVED from the stats that already
## exist in `baby_state.gd`, and the presentation asks for exactly one answer:
## `dominant()`.
##
## ## The stats behind them
##
## `BabyState` already holds `hunger`, `happiness`, `energy` and `cleanliness`.
## Two more were added for this pass -- `thirst` and `freshness` (a clean nappy)
## -- because "thirsty" and "needsChanging" are separate caregiving acts with
## separate objects, and folding them into hunger and cleanliness would have made
## Milk Time and a nappy change indistinguishable to the game.
##
## ## One need at a time
##
## A real infant signals one thing loudest. `dominant()` returns the most urgent
## unmet need by a fixed priority, so the child has ONE readable presentation and
## the caregiver has ONE obvious next action. `crying` sits at the top because it
## is what a child does when several needs go unmet at once -- it is a summary of
## the others, not a tenth independent thing.
##
## ## Nothing here renders
##
## No `Node3D`, no pose name, no mesh. `child_presentation.gd` maps a need onto a
## pose and a mood; this file decides only what is true.

const NONE: String = ""
const CRYING: String = "crying"
const HUNGRY: String = "hungry"
const THIRSTY: String = "thirsty"
const NEEDS_CHANGING: String = "needsChanging"
const NEEDS_BATH: String = "needsBath"
const DIRTY: String = "dirty"
const SLEEPY: String = "sleepy"
const NEEDS_COMFORT: String = "needsComfort"
const WANTS_TO_PLAY: String = "wantsToPlay"

## Every state the brief names, in the order `dominant()` considers them.
##
## The order IS the design. Distress first, then the needs that hurt, then the
## ones that merely matter -- a child who is hungry AND wants to play should be
## fed, and a game that announced "wantsToPlay" there would be teaching the wrong
## thing about looking after someone.
const PRIORITY: Array[String] = [
	CRYING,
	HUNGRY,
	THIRSTY,
	NEEDS_CHANGING,
	NEEDS_BATH,
	DIRTY,
	SLEEPY,
	NEEDS_COMFORT,
	WANTS_TO_PLAY,
]

## Thresholds, all on the 0-100 scale `BabyState` uses.
##
## `hunger` and `thirst` count UP towards discomfort (80 = starving); `energy`,
## `cleanliness`, `freshness` and `happiness` count DOWN (0 = desperate). That
## inversion is inherited from `BabyState.hunger` and is preserved rather than
## "tidied", because every existing caller already reads it that way.
const HUNGRY_AT: float = 40.0
const THIRSTY_AT: float = 45.0
const SLEEPY_BELOW: float = 30.0
const DIRTY_BELOW: float = 55.0
const BATH_BELOW: float = 30.0
const CHANGING_BELOW: float = 35.0
const COMFORT_BELOW: float = 35.0
const PLAY_BELOW: float = 60.0

## How many simultaneous unmet needs tip a child into crying.
const CRYING_NEED_COUNT: int = 3
## ...or one need this far past its threshold on its own.
const CRYING_SEVERITY: float = 85.0


## `true` for each state the stats currently satisfy. Used by tests and the
## parent diagnostic; gameplay should ask `dominant()`.
static func active_states(stats: Dictionary) -> Array:
	var hunger: float = float(stats.get("hunger", 0.0))
	var thirst: float = float(stats.get("thirst", 0.0))
	var energy: float = float(stats.get("energy", 100.0))
	var cleanliness: float = float(stats.get("cleanliness", 100.0))
	var freshness: float = float(stats.get("freshness", 100.0))
	var happiness: float = float(stats.get("happiness", 100.0))

	var states: Array = []
	if hunger >= HUNGRY_AT:
		states.append(HUNGRY)
	if thirst >= THIRSTY_AT:
		states.append(THIRSTY)
	if freshness < CHANGING_BELOW:
		states.append(NEEDS_CHANGING)
	if cleanliness < BATH_BELOW:
		states.append(NEEDS_BATH)
	elif cleanliness < DIRTY_BELOW:
		# `dirty` and `needsBath` are the same axis at two depths, so they are
		# deliberately exclusive: a child who needs a bath is not ALSO merely
		# dirty, and reporting both would double-count towards crying.
		states.append(DIRTY)
	if energy < SLEEPY_BELOW:
		states.append(SLEEPY)
	if happiness < COMFORT_BELOW:
		states.append(NEEDS_COMFORT)
	elif happiness < PLAY_BELOW:
		states.append(WANTS_TO_PLAY)

	if _is_crying(stats, states):
		states.append(CRYING)
	return states


## Crying is a SUMMARY of the others: several needs unmet at once, or one that
## has gone far past the point of asking nicely.
static func _is_crying(stats: Dictionary, states: Array) -> bool:
	if states.size() >= CRYING_NEED_COUNT:
		return true
	if float(stats.get("hunger", 0.0)) >= CRYING_SEVERITY:
		return true
	if float(stats.get("thirst", 0.0)) >= CRYING_SEVERITY:
		return true
	if float(stats.get("happiness", 100.0)) <= (100.0 - CRYING_SEVERITY):
		return true
	return false


## The ONE need the child is signalling, or `NONE` when content.
static func dominant(stats: Dictionary) -> String:
	var active: Array = active_states(stats)
	for state: String in PRIORITY:
		if active.has(state):
			return state
	return NONE


static func is_content(stats: Dictionary) -> bool:
	return dominant(stats) == NONE


## The caregiver action that answers a need. One verb each, drawn from the P6
## interaction vocabulary, so a mission can ask "what would help?" without a
## lookup table of its own.
const ANSWER: Dictionary = {
	HUNGRY: "giveBottle",
	THIRSTY: "giveBottle",
	NEEDS_CHANGING: "changeOutfit",
	NEEDS_BATH: "washFace",
	DIRTY: "washFace",
	SLEEPY: "putChildToBed",
	NEEDS_COMFORT: "holdChild",
	WANTS_TO_PLAY: "holdChild",
	CRYING: "holdChild",
}


static func answering_action(state: String) -> String:
	return String(ANSWER.get(state, ""))


## What the child "says", in the game's own voice. Short, warm, and never a
## complaint -- a child who is hungry asks, it does not accuse. Bunny asks Aliz
## by name when he is hungry: that is Mission 01's opening line, and the same
## words on the bubble and in the voice is what makes it one conversation.
const LINES: Dictionary = {
	HUNGRY: "I'm hungry, Aliz!",
	THIRSTY: "I'm thirsty!",
	NEEDS_CHANGING: "I need changing.",
	NEEDS_BATH: "I need a bath!",
	DIRTY: "I'm messy!",
	SLEEPY: "I'm sleepy...",
	NEEDS_COMFORT: "Cuddle me?",
	WANTS_TO_PLAY: "Let's play!",
	CRYING: "Waah!",
}


static func line_for(state: String) -> String:
	return String(LINES.get(state, "I'm happy!"))
