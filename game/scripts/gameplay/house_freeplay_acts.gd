extends RefCounted

## WHAT HAPPENS AT A THING in Free Play -- the decision, with no node in it.
##
## `house_freeplay_director.gd` describes the situation Aliz has arrived in as
## a plain dictionary and asks `decide()` what to do; it then does it. Keeping
## the choice here means `test_freeplay_acts.gd` can prove every rule -- "Bunny
## in her arms at the bed is a lie-down, alone at the bed is a sit" -- without
## a house, a rig or a kitchen.
##
## ## The one rule
##
## When Aliz carries Bunny to a thing, the act applies to BUNNY; alone, it
## applies to her. A prop in her hand goes into whatever will take it.
##
## ## The situation
##
##   `localId`      "bed", "toyBox", "fridge" ... (the local half of the id)
##   `actions`      the target's supported actions (`sit`, `wash`, `open` ...)
##   `carrying`     "child" | "item" | ""
##   `isCharacter`  the target is Bunny himself
##   `openable`     it opens (a storage lid, the wardrobe doors)
##   `isOpen`       ... and is open now
##   `canStore`     the carried prop may go in (storage model says yes)
##   `station`      the kitchen's `describe()` for this id, or {} off-kitchen
##   `kitchenHeld`  the kitchen item in her hand ("" for none)
##   `canFeed`      the kitchen item in hand is something Bunny eats
##   `canPlaceHere` the kitchen says the held item may be put down here
##   `combines`     ... and it combines with what is on the station
##   `childAt`      the surface Bunny was last set down on ("table" when he is
##                  sitting at his highchair spot), "" when he is elsewhere
##
## ## The answer
##
## `{"act": String, ...}` where `act` is one of the `ACT_*` constants, plus
## whatever that act needs (`activity`, `careKind`, `item`).

const ACT_NONE: String = "none"
const ACT_TOGGLE_OPEN: String = "toggleOpen"
const ACT_STORE_ITEM: String = "storeItem"
const ACT_PLACE_ON_TABLE: String = "placeOnTable"
const ACT_PLACE_CHILD: String = "placeChild"
const ACT_CARE_CHILD: String = "careChild"
const ACT_SIT: String = "sit"
const ACT_WASH_HANDS: String = "washHands"
const ACT_BUBBLES: String = "bubbles"
const ACT_KITCHEN_OPEN: String = "kitchenOpen"
const ACT_KITCHEN_CLOSE: String = "kitchenClose"
const ACT_KITCHEN_TAKE: String = "kitchenTake"
const ACT_KITCHEN_PLACE: String = "kitchenPlace"
const ACT_FEED_CHILD: String = "feedChild"
## Arriving at him with empty hands and nothing to feed him: pick him up. Free
## Play used to answer `ACT_NONE` here (owner bug: arriving at Bunny with empty
## hands was a dead end, not the carry a child would expect a tap on him to be).
const ACT_CARRY_CHILD: String = "carryChild"

## What Bunny does once he is set down on each surface. The sofa uses the
## seated posture his `carried` clip already has (knees up, hands resting):
## there is no separate sitting clip on the rig, and the semantic name of the
## clip matters less than a child who visibly sits rather than stands on the
## cushions. The table is his highchair spot, ready for a spoon.
const CHILD_ACTIVITY_FOR: Dictionary = {
	"bed": "bedtime",
	"sofa": "carried",
	"table": "carried",
}
## The care act each basin opens on Bunny.
const CARE_KIND_FOR: Dictionary = {
	"sink": "washFace",
	"bath": "washFace",
}


static func decide(situation: Dictionary) -> Dictionary:
	var local_id: String = String(situation.get("localId", ""))
	var actions: Array = situation.get("actions", []) as Array
	var carrying: String = String(situation.get("carrying", ""))
	var station: Dictionary = situation.get("station", {}) if situation.get("station", null) is Dictionary else {}
	var in_kitchen: bool = not String(station.get("role", "")).is_empty()
	var held: String = String(situation.get("kitchenHeld", ""))
	if held == "none":
		held = ""

	if bool(situation.get("isCharacter", false)):
		if not held.is_empty() and bool(situation.get("canFeed", false)):
			return {"act": ACT_FEED_CHILD, "item": held}
		# Truly empty hands only: something in the kitchen hand that is not a
		# meal (a spoon) still means "not now" rather than "pick him up", and a
		# prop already in her `carry_controller` arm is a hand that is full too.
		if held.is_empty() and carrying.is_empty():
			return {"act": ACT_CARRY_CHILD}
		return {"act": ACT_NONE}

	if carrying == "child":
		if CARE_KIND_FOR.has(local_id):
			return {"act": ACT_CARE_CHILD, "careKind": String(CARE_KIND_FOR[local_id]),
					"surface": local_id}
		if CHILD_ACTIVITY_FOR.has(local_id):
			return {"act": ACT_PLACE_CHILD, "activity": String(CHILD_ACTIVITY_FOR[local_id]),
					"surface": local_id}
		if bool(situation.get("openable", false)):
			return {"act": ACT_TOGGLE_OPEN}
		return {"act": ACT_NONE}

	if carrying == "item":
		if bool(situation.get("openable", false)):
			if not bool(situation.get("isOpen", false)):
				return {"act": ACT_TOGGLE_OPEN}
			if bool(situation.get("canStore", false)):
				return {"act": ACT_STORE_ITEM}
			return {"act": ACT_NONE}
		if actions.has("eat"):
			return {"act": ACT_PLACE_ON_TABLE}
		return {"act": ACT_NONE}

	# Empty arms. The kitchen first: its stations have their own state.
	if in_kitchen:
		# Bunny is sitting at the table and she has brought his food: that is a
		# meal, not a plate set down beside him (owner playtest 2026-09-21: the
		# dining area with Bunny is the feeding mini-game).
		if local_id == "table" and String(situation.get("childAt", "")) == "table" \
				and not held.is_empty() and bool(situation.get("canFeed", false)):
			return {"act": ACT_FEED_CHILD, "item": held, "atTable": true}
		var opens: bool = bool(station.get("opens", false))
		var is_open: bool = bool(station.get("open", false))
		var on_top: String = String(station.get("on", ""))
		if on_top == "none":
			on_top = ""
		var inside: Array = station.get("inside", []) as Array
		if not held.is_empty():
			if bool(situation.get("canPlaceHere", false)) and (not opens or is_open):
				return {"act": ACT_KITCHEN_PLACE, "combines": bool(situation.get("combines", false))}
			if opens and not is_open:
				return {"act": ACT_KITCHEN_OPEN}
			return {"act": ACT_NONE}
		if opens and not is_open:
			return {"act": ACT_KITCHEN_OPEN}
		if not on_top.is_empty():
			return {"act": ACT_KITCHEN_TAKE, "item": on_top}
		if not inside.is_empty() and (is_open or not opens):
			return {"act": ACT_KITCHEN_TAKE, "item": String(inside[0])}
		if opens and is_open:
			return {"act": ACT_KITCHEN_CLOSE}
		return {"act": ACT_NONE}

	if bool(situation.get("openable", false)):
		return {"act": ACT_TOGGLE_OPEN}
	if local_id == "sink":
		return {"act": ACT_WASH_HANDS}
	if local_id == "bath":
		return {"act": ACT_BUBBLES}
	if actions.has("sit") and not actions.has("eat"):
		return {"act": ACT_SIT}
	return {"act": ACT_NONE}
