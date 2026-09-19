extends RefCounted

## ============================================================================
## THE CHILD'S STATS -- the caregiver game's own, deliberately not Chapter 2's.
## ============================================================================
##
## Six bounded axes, 0-100, that `child_needs.gd` derives the nine named states
## from.
##
## ## Why this is not `scripts/baby/baby_state.gd`
##
## The obvious move was to reuse Chapter 2's `BabyState` and add two fields to
## it. `test_house_chapter2_untouched.gd` rejected that, and it was right twice
## over:
##
##   1. **The boundary.** That guard's rule is "Chapter 2 and Chapter 3 share a
##      character API, not a world". Chapter 2 is finished and shipped; reaching
##      into it from the house is how a finished thing stops being finished.
##   2. **The design.** `BabyState` exists to serve one MVP flow -- it starts at
##      `hunger = 80` specifically so the milk lesson begins with a hungry baby,
##      and it documents that "only hunger affects gameplay tonight". Bolting
##      `thirst` and `freshness` onto it would have pushed Chapter 3's concerns
##      into a file whose whole job is Chapter 2's.
##
## So Chapter 2 keeps its container untouched, and the caregiver game has its
## own. The two never meet.
##
## ## The direction of each axis
##
## `hunger` and `thirst` count UP towards discomfort; `energy`, `cleanliness`,
## `freshness` and `happiness` count DOWN. That mixed convention is inherited
## from `BabyState.hunger` and is kept on purpose rather than "tidied", so a
## reader moving between the two chapters is never surprised.

signal stat_changed(stat_name: String, value: float)

const MIN_VALUE: float = 0.0
const MAX_VALUE: float = 100.0

## Where a fresh day starts. The child begins a little hungry and a little
## rumpled, because "A Day as Buddy" opens with Wake Up and there has to be
## something to do.
const START: Dictionary = {
	"hunger": 55.0,
	"thirst": 20.0,
	"happiness": 70.0,
	"energy": 75.0,
	"cleanliness": 60.0,
	"freshness": 70.0,
}

var hunger: float = START["hunger"]
var thirst: float = START["thirst"]
var happiness: float = START["happiness"]
var energy: float = START["energy"]
var cleanliness: float = START["cleanliness"]
var freshness: float = START["freshness"]


static func _clamped(value: float) -> float:
	return clampf(value, MIN_VALUE, MAX_VALUE)


## One setter, by name, so callers and save data speak the same vocabulary and a
## new axis does not need a new method on every caller.
func set_stat(stat_name: String, value: float) -> void:
	var clamped: float = _clamped(value)
	match stat_name:
		"hunger": hunger = clamped
		"thirst": thirst = clamped
		"happiness": happiness = clamped
		"energy": energy = clamped
		"cleanliness": cleanliness = clamped
		"freshness": freshness = clamped
		_: return
	stat_changed.emit(stat_name, clamped)


func get_stat(stat_name: String) -> float:
	return float(describe().get(stat_name, 0.0))


func adjust(stat_name: String, delta: float) -> void:
	set_stat(stat_name, get_stat(stat_name) + delta)


## camelCase keys, per `CLAUDE.md`, and the shape `child_needs.gd` takes. Pure
## data: the needs model is static and reasons about a Dictionary, so a test can
## ask "what would a starving child need?" without constructing anything.
func describe() -> Dictionary:
	return {
		"hunger": hunger,
		"thirst": thirst,
		"happiness": happiness,
		"energy": energy,
		"cleanliness": cleanliness,
		"freshness": freshness,
	}


## Restores from save data, ignoring anything it does not recognise so an older
## or newer profile never fails to load.
func restore(data: Dictionary) -> void:
	for stat_name: String in START.keys():
		if data.has(stat_name):
			set_stat(stat_name, float(data[stat_name]))


func reset() -> void:
	for stat_name: String in START.keys():
		set_stat(stat_name, float(START[stat_name]))
