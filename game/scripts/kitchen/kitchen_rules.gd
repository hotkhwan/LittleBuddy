extends RefCounted

## WHAT THE KITCHEN LETS YOU DO -- all of it, as rules rather than as scattered
## `if`s inside node code.
##
## Adapted from `RestaurantGame3DUnity` (MIT, see `docs/THIRD_PARTY_NOTICES.md`).
## Its `IGetItem` / `IPutItem*` interfaces say that a STATION declares what it
## will accept and what it gives back. That is the idea kept here, with two
## changes that matter for a four-year-old:
##
##   * **Nothing is ever refused rudely.** `refusal_for()` returns a kind sentence
##     ("The bowl goes on the counter first") rather than a boolean, because
##     `CLAUDE.md` bans failure language and a silent no-op is its own kind of
##     dead end -- the child taps and nothing happens and they do not know why.
##
##   * **No timers.** The reference's `Functionality.Process()` runs a countdown
##     and resets it if you let go. There is no countdown here. Preparing food is
##     a gesture in the existing `care_overlay.gd`, which has no way to lose.
##
## PURE, and therefore assertable: every rule below is a static function over
## plain strings and dictionaries. `test_kitchen.gd` plays whole recipes through
## this file with no scene at all.

const Items := preload("res://scripts/kitchen/kitchen_items.gd")

## The kitchen's stations, keyed by the target id the house already uses. These
## are the ids `house_layout.gd` gives the kitchen's furniture, so a station is
## not a new thing in the world -- it is a role the existing furniture plays.
const STATION_FRIDGE: String = "fridge"
const STATION_COUNTER: String = "counter"
const STATION_TABLE: String = "table"
const STATION_SINK: String = "sink"

## What each station is FOR, in one word the rest of the code can branch on.
##   `store`    things live here and can be taken out (fridge, cupboard)
##   `prepare`  things are put down here and changed (counter)
##   `serve`    finished food is set out here (table)
const STATIONS: Dictionary = {
	STATION_FRIDGE: {
		"role": "store", "word": "fridge", "thai": "ตู้เย็น", "opens": true,
		# What is inside at the start of the day.
		"holds": ["banana", "apple", "bottle"],
	},
	STATION_COUNTER: {
		"role": "prepare", "word": "counter", "thai": "เคาน์เตอร์", "opens": false,
		"holds": ["bowl", "spoon"],
	},
	STATION_TABLE: {
		"role": "serve", "word": "table", "thai": "โต๊ะ", "opens": false,
		"holds": [],
	},
	STATION_SINK: {
		"role": "prepare", "word": "sink", "thai": "อ่างล้าง", "opens": false,
		"holds": [],
	},
}

## PREPARING: what a station turns things into.
##
## Keyed `<stationId>/<onStation>+<inHand>` -> result. Both halves matter: mashing
## a banana needs the banana on the counter AND the spoon in hand, which is the
## whole reason "combine" is a real step and not a button.
const COMBINATIONS: Dictionary = {
	"counter/banana+spoon": "mashedBanana",
	"counter/bowl+banana": "fruitBowl",
	"counter/bowl+apple": "fruitBowl",
	"counter/bottle+bowl": "bottleOfMilk",
}

## The gesture each preparation opens, reusing the existing care close-up rather
## than inventing a second mini-game framework. An id not listed here is prepared
## by simply combining, with no close-up.
const PREPARE_GESTURES: Dictionary = {
	"mashedBanana": "mashFood",
	"fruitBowl": "mashFood",
	"bottleOfMilk": "prepareMilk",
}

## What Bunny will actually accept. Feeding Bunny a spoon is not a failure state;
## it is simply something Bunny does not eat, and is answered with a kind line.
const FEEDABLE: Array[String] = ["bottleOfMilk", "mashedBanana", "fruitBowl"]


# ---------------------------------------------------------------------------
# Stations
# ---------------------------------------------------------------------------

static func is_station(station_id: String) -> bool:
	return STATIONS.has(station_id)


static func station(station_id: String) -> Dictionary:
	return (STATIONS.get(station_id, {}) as Dictionary).duplicate(true)


static func role_of(station_id: String) -> String:
	return String(station(station_id).get("role", ""))


## True for a station with a door that visibly opens. The fridge is the only one
## today; the rule exists so a cupboard is a data row rather than a new branch.
static func opens(station_id: String) -> bool:
	return bool(station(station_id).get("opens", false))


## What a station starts the day holding.
static func initial_contents(station_id: String) -> Array:
	var held: Variant = station(station_id).get("holds", [])
	return (held as Array).duplicate() if held is Array else []


# ---------------------------------------------------------------------------
# The verbs
# ---------------------------------------------------------------------------

## Can the hand take `item_id` out of `station_id`, given what the hand holds?
##
## Four rules, and each one is a thing a child can see: the station must have it,
## the hand must be empty, the item must be carryable, and a closed door must be
## opened first. That last one is the reason the fridge is worth having.
static func can_take(
	station_id: String, item_id: String, contents: Array, in_hand: String, is_open: bool
) -> bool:
	if not is_station(station_id) or not Items.exists(item_id):
		return false
	if opens(station_id) and not is_open:
		return false
	if not contents.has(item_id):
		return false
	if in_hand != Items.NONE:
		return false
	return Items.is_carryable(item_id)


## Can what is in the hand be put down on `station_id`?
##
## A `store` station only takes back what belongs in it; a `prepare` station
## takes anything, because that is what a worktop is for.
static func can_place(station_id: String, in_hand: String, on_station: String) -> bool:
	if not is_station(station_id) or in_hand == Items.NONE:
		return false
	if on_station != Items.NONE and not _combines(station_id, on_station, in_hand):
		# Something is already there and these two do not go together.
		return false
	if role_of(station_id) == "serve":
		# Only finished food is set out to eat.
		return FEEDABLE.has(in_hand)
	return true


## The item two things become on a station, or `NONE` if they do not combine.
## Order-insensitive: putting the spoon on the banana and the banana on the spoon
## are the same act to a child, so they are the same act here.
static func combination(station_id: String, on_station: String, in_hand: String) -> String:
	if on_station == Items.NONE or in_hand == Items.NONE:
		return Items.NONE
	var direct: String = String(COMBINATIONS.get(
			"%s/%s+%s" % [station_id, on_station, in_hand], Items.NONE))
	if direct != Items.NONE:
		return direct
	return String(COMBINATIONS.get(
			"%s/%s+%s" % [station_id, in_hand, on_station], Items.NONE))


static func _combines(station_id: String, on_station: String, in_hand: String) -> bool:
	return combination(station_id, on_station, in_hand) != Items.NONE


## The close-up gesture a prepared item is made with, or "" for none.
static func gesture_for(result_id: String) -> String:
	return String(PREPARE_GESTURES.get(result_id, ""))


## Will Bunny eat or drink this?
static func is_feedable(item_id: String) -> bool:
	return FEEDABLE.has(item_id)


# ---------------------------------------------------------------------------
# Saying no, kindly
# ---------------------------------------------------------------------------

## Why an action did not happen, in words a child can act on. Never blames, never
## says "wrong" -- `test_ui_kindness` and `test_chapter3_slice` both scan
## child-facing strings for exactly that.
static func refusal_for(
	station_id: String, item_id: String, in_hand: String, is_open: bool
) -> String:
	if not is_station(station_id):
		return ""
	if opens(station_id) and not is_open:
		return "Let's open the %s first!" % String(station(station_id).get("word", "door"))
	if in_hand != Items.NONE and item_id != Items.NONE:
		return "Your hands are full! Put the %s down first." % Items.word_for(in_hand)
	if role_of(station_id) == "serve" and in_hand != Items.NONE \
			and not FEEDABLE.has(in_hand):
		return "Let's finish making the food first!"
	return "Let's try something else!"
