extends RefCounted

## The feeding minigame's rules, with no scene attached.
##
## Everything a test wants to prove about the highchair -- which tasks it takes,
## what a mistake costs, what sits on the tray, how long a sip is held -- lives
## here as plain functions on plain values. `feeding_table.gd` is the picture;
## this file is the game.
##
## ## Credit, in one sentence
##
## A task starts worth its full reward. The FIRST wrong item halves it, the
## SECOND switches the stage to guided mode (the right item glows, an arrow
## points to Bunny's mouth) and the next delivery finishes the task. Nothing is
## ever taken away after that, nothing is scored, and nothing is red.
##
## ## The half star, honestly
##
## Stars are integers all the way down: `MissionRunner._award()`,
## `RewardLedger.award()` and `SaveService.add_stars()` all take an `int`, and
## `star_rules.gd` rates a level from task ids, not amounts. There is no
## fractional star to pay out, so a halved task is paid **0 stars** through the
## ordinary reward path (`stars_for_credit()`), the task still counts as
## COMPLETED for the level rating (`MissionRunner` records the id either way),
## and the half star is drawn on the stage and on the summary as "almost" --
## a picture of how close it was, never a deduction the child can watch.

const ITEM_APPLE: String = "apple"
const ITEM_BANANA: String = "banana"
const ITEM_MILK: String = "milk"
const ITEM_WATER: String = "water"

## The four `followInstruction` objects this stage knows how to feed.
const HANDLED_ITEMS: Array[String] = [ITEM_APPLE, ITEM_BANANA, ITEM_MILK, ITEM_WATER]

const HANDLED_MODE: String = "followInstruction"
const HANDLED_INTERACTION: String = "dragToMouth"

const CREDIT_FULL: String = "full"
const CREDIT_HALF: String = "half"
const CREDIT_GUIDED: String = "guided"

## Tray slots, left to right as the child sees them.
const SLOT_LEFT: String = "left"
const SLOT_CENTRE: String = "centre"
const SLOT_RIGHT: String = "right"

## A sip is a HOLD, not a tap: the cup tips while the finger stays, and Bunny
## drinks. Long enough to read as drinking, short enough for a three-year-old.
const HOLD_SECONDS: float = 1.2
## An apple goes in three bites.
const BITES: int = 3
const BITE_GAP_SEC: float = 0.36
## The peel folds down over this long.
const PEEL_SECONDS: float = 0.4
const PEEL_STRIPS: int = 3

## The mouth drop target, as a fraction of the viewport HEIGHT: 90 px on a
## 750-high iPad frame, 130 px on a 1080-high phone frame. Generous on purpose.
const MOUTH_RADIUS_RATIO: float = 90.0 / 750.0
## How close a finger has to land to pick an item up. Bigger than the item.
const TOUCH_RADIUS_RATIO: float = 120.0 / 750.0

## Idle nudges: after this long with nothing happening the target item hops and
## the prompt is repeated. After `NUDGES_BEFORE_TAP_HELP` nudges a plain tap on
## the item carries it to Bunny's mouth, so a child who cannot drag still wins.
const NUDGE_IDLE_SECONDS: float = 7.0
const NUDGES_BEFORE_TAP_HELP: int = 2

## Short and kind. Never "wrong", never "no".
const PEEL_HINT: String = "Peel it!"
const TAP_HELP_HINT: String = "Tap to help!"
const SUCCESS_PHRASE: String = "Great!"
const ALMOST_PHRASE: String = "Almost!"


## -- Routing ----------------------------------------------------------------------

## Does the highchair stage this task? A `followInstruction` drag-to-mouth of one
## of the four foods. `findIt` and `sayIt` tasks stay in the room untouched.
static func handles_task(task: Variant) -> bool:
	if typeof(task) != TYPE_DICTIONARY:
		return false
	var task_dict: Dictionary = task
	if String(task_dict.get("mode", "")) != HANDLED_MODE:
		return false
	if String(task_dict.get("interaction", "")) != HANDLED_INTERACTION:
		return false
	return HANDLED_ITEMS.has(String(task_dict.get("objectId", "")))


static func is_handled_item(item_id: String) -> bool:
	return HANDLED_ITEMS.has(item_id)


static func needs_peel(item_id: String) -> bool:
	return item_id == ITEM_BANANA


static func is_drink(item_id: String) -> bool:
	return item_id == ITEM_MILK or item_id == ITEM_WATER


## -- Credit ---------------------------------------------------------------------------

static func credit_for_mistakes(mistakes: int) -> String:
	if mistakes <= 0:
		return CREDIT_FULL
	if mistakes == 1:
		return CREDIT_HALF
	return CREDIT_GUIDED


static func is_guided(mistakes: int) -> bool:
	return credit_for_mistakes(mistakes) == CREDIT_GUIDED


## The integer the reward path can actually pay. See the class doc.
static func stars_for_credit(credit: String, reward_stars: int) -> int:
	if credit == CREDIT_FULL:
		return maxi(0, reward_stars)
	return 0


## Whether the stage should draw a half star for this task right now.
static func shows_half_star(mistakes: int) -> bool:
	return mistakes >= 1


## -- The tray -------------------------------------------------------------------------

## What sits on the tray for a target, by slot. Both fruits are always out (so a
## wrong fruit is possible and can be answered kindly), plus exactly one drink:
## the target drink, or -- for a fruit task -- the water cup beside the apple and
## the milk bottle beside the banana. The target is ALWAYS present.
static func tray_items_for(target_id: String) -> Dictionary:
	var drink: String = target_id if is_drink(target_id) else \
			(ITEM_WATER if target_id == ITEM_APPLE else ITEM_MILK)
	return {
		SLOT_LEFT: ITEM_BANANA,
		SLOT_CENTRE: ITEM_APPLE,
		SLOT_RIGHT: drink,
	}


static func tray_item_ids(target_id: String) -> Array:
	var slots: Dictionary = tray_items_for(target_id)
	return [slots[SLOT_LEFT], slots[SLOT_CENTRE], slots[SLOT_RIGHT]]


## -- Words ------------------------------------------------------------------------------

## "Try the apple!" -- points at the right thing, never at the wrong one.
static func try_phrase(target_display_name: String) -> String:
	var word: String = target_display_name.strip_edges().to_lower()
	if word.is_empty():
		return "Try again!"
	return "Try the %s!" % word


## -- Geometry -----------------------------------------------------------------------------

static func mouth_radius_px(viewport_height: float) -> float:
	return maxf(48.0, viewport_height * MOUTH_RADIUS_RATIO)


static func touch_radius_px(viewport_height: float) -> float:
	return maxf(64.0, viewport_height * TOUCH_RADIUS_RATIO)


static func tap_helps_after(nudges: int) -> bool:
	return nudges >= NUDGES_BEFORE_TAP_HELP


## The fraction of the item left after `bites_taken` of `BITES`.
static func bite_scale(bites_taken: int) -> float:
	return clampf(1.0 - float(bites_taken) / float(BITES), 0.0, 1.0)


## Liquid left in the cup while a sip is being held, 1.0 -> 0.35.
static func liquid_level_for_hold(hold_seconds: float) -> float:
	var t: float = clampf(hold_seconds / HOLD_SECONDS, 0.0, 1.0)
	return lerpf(1.0, 0.35, t)
