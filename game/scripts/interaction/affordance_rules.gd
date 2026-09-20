extends RefCounted

## The pure half of proximity affordances: which action word a thing offers,
## what colour that word is, and which offer wins when several are in reach.
##
## No node, no camera, no tree. `affordance_layer.gd` gathers candidates from
## the scene and asks this file what to show; `test_affordance.gd` asks it the
## same questions with dictionaries and gets the same answers.
##
## ## The vocabulary
##
## Eleven words: OPEN, TAKE, PLACE, ENTER, HUG, CARRY, FEED, SIT, WASH, COOK and
## SOON. Each is a picture first (drawn by the layer) and a word second, and
## each has ONE colour from the locked palette so the same act always looks the
## same. The last four arrived with Free Play's furniture (2026-09-20): a sofa
## you can sit on, a sink and a bath that wash, a counter that cooks, and a door
## that is not open yet -- which says SOON, kindly, instead of ENTER.
##
## ## Who decides the verb
##
## A target describes ITSELF (`ActivityTarget.describe_semantics()`) and the
## layer supplies CONTEXT it cannot know -- whether the fridge is open, what is
## in Aliz's hand -- as a second dictionary. `verb_for_target()` combines the
## two. Nothing here names a node type, a station id list or a mission.

const Palette := preload("res://scripts/ui/palette.gd")

const VERB_OPEN: String = "OPEN"
const VERB_TAKE: String = "TAKE"
const VERB_PLACE: String = "PLACE"
const VERB_ENTER: String = "ENTER"
const VERB_HUG: String = "HUG"
const VERB_CARRY: String = "CARRY"
const VERB_FEED: String = "FEED"
const VERB_SIT: String = "SIT"
const VERB_WASH: String = "WASH"
const VERB_COOK: String = "COOK"
## A door the child may not go through yet. Never a lock, never a red X: a
## small pastel sign that says so and asks for a grown-up.
const VERB_SOON: String = "SOON"

const VERBS: Array[String] = [
	VERB_OPEN, VERB_TAKE, VERB_PLACE, VERB_ENTER, VERB_HUG, VERB_CARRY, VERB_FEED,
	VERB_SIT, VERB_WASH, VERB_COOK, VERB_SOON,
]

## What the word pill under the picture says. Every verb is its own label
## except SOON, whose whole point is the sentence.
const LABELS: Dictionary = {
	VERB_SOON: "Soon! Ask a grown-up",
}


static func label_for(verb: String) -> String:
	return String(LABELS.get(verb, verb))

## Nothing in the hand. `kitchen_items.gd` spells it `""`; older callers say
## `"none"`. `is_nothing()` accepts both so a context author cannot get it wrong.
const NONE: String = ""


static func is_nothing(item: Variant) -> bool:
	var text: String = String(item).strip_edges()
	return text.is_empty() or text == "none"

## Priority bands. Higher wins; distance only breaks a tie inside a band.
##
##   3  doors and characters -- fixed, and the thing a beat is about
##   2  furniture and kitchen stations
##   1  loose floor props (`spawned_object.gd`, `drop_zone.gd` report their own)
##
## Doors used to share band 1 with props, so a banana dropped by the kitchen
## door won on distance and the door read "take" (QA frames
## `qa_ux_*_door_enter`). A door is a room; a banana is a banana.
const PRIORITY_PROP: int = 1
const PRIORITY_FURNITURE: int = 2
const PRIORITY_STATION: int = PRIORITY_FURNITURE
const PRIORITY_DOOR: int = 3
const PRIORITY_CHARACTER: int = 3
## Added on top when the target is what the current mission beat is about.
const MISSION_BONUS: int = 10
## Added when the target is in front of the actor (see `pick()`); enough to
## lift furniture over a door she has her back to, never over the mission.
const FACING_BONUS: int = 4
## Half-angle of "in front": 55 degrees either side of where she faces.
const FACING_COS: float = 0.5736

## The default activation radius, metres, when a target supplies none.
const DEFAULT_RADIUS: float = 1.6


static func is_verb(verb: String) -> bool:
	return VERBS.has(verb)


## The canonical spelling of a provider's verb, or "" for a word this layer has
## no picture for. The contract said lowercase (`"carry"`, `"place"`, `"take"`)
## and the first providers did exactly that while the badge compared against
## upper-case constants -- so the child saw a raw lowercase word over a dot.
## Every spelling now lands on one constant; the constants are what the layer
## draws and what `get_current_verb()` reports.
static func normalize_verb(raw: Variant) -> String:
	var verb: String = String(raw).strip_edges().to_upper()
	return verb if VERBS.has(verb) else ""


## The one colour for a word. Unknown words get cream, never a new colour.
static func verb_color(verb: String) -> Color:
	match verb:
		VERB_OPEN:
			return Palette.VERB_OPEN
		VERB_TAKE:
			return Palette.VERB_TAKE
		VERB_PLACE:
			return Palette.VERB_PLACE
		VERB_ENTER:
			return Palette.VERB_ENTER
		VERB_HUG:
			return Palette.VERB_HUG
		VERB_CARRY:
			return Palette.VERB_CARRY
		VERB_FEED:
			return Palette.VERB_FEED
		VERB_SIT:
			return Palette.LAVENDER
		VERB_WASH:
			return Palette.light(Palette.DUSTY_BLUE)
		VERB_COOK:
			return Palette.light(Palette.PEACH)
		VERB_SOON:
			return Palette.light(Palette.LAVENDER)
		_:
			return Palette.CREAM


## The action word for a target, or "" when it offers nothing right now.
##
## `description` is `ActivityTarget.describe_semantics()` (or any dictionary
## with the same keys): `isDoor`, `supportedActions`, `enabled`.
##
## `context` is what the layer knows and the target does not. All keys optional:
##   `held`      -- String, the item in the actor's hand (`"none"` for empty).
##   `station`   -- Dictionary for a kitchen station:
##                    `opens`, `isOpen`, `inside` (Array), `on` (String),
##                    `canPlace` (bool: the held item may be put down here).
##   `storage`   -- Dictionary for a container with a lid: `isOpen`, and
##                  optionally `canPlace` (the carried thing may go in).
##   `character` -- Dictionary for a character target: `canHug`, `canCarry`,
##                  `canFeed`.
##   `carrying`  -- String: `"child"` while Bunny is in the actor's arms,
##                  `"item"` for a prop, `""`/absent for empty arms. A child in
##                  her arms turns every seat into PLACE and every basin into
##                  WASH, because the act applies to HIM.
##   `door`      -- Dictionary for a door: `locked` (true shows SOON).
static func verb_for_target(description: Dictionary, context: Dictionary = {}) -> String:
	if not bool(description.get("enabled", true)):
		return ""
	if bool(description.get("isDoor", false)):
		var door: Dictionary = context.get("door", {}) if context.get("door", null) is Dictionary else {}
		return VERB_SOON if bool(door.get("locked", false)) else VERB_ENTER

	var holding: bool = not is_nothing(context.get("held", NONE))
	var carrying: String = String(context.get("carrying", ""))
	var actions: Array = description.get("supportedActions", []) as Array

	if carrying == "child":
		# Bunny in her arms: he is what the furniture is for.
		if context.has("character"):
			return ""
		if _is_seat(actions) or actions.has("sleep"):
			return VERB_PLACE
		if actions.has("wash"):
			return VERB_WASH
		return ""

	if context.has("character"):
		var who: Dictionary = context["character"]
		if bool(who.get("canFeed", false)) and holding:
			return VERB_FEED
		if bool(who.get("canCarry", false)):
			return VERB_CARRY
		if bool(who.get("canHug", false)):
			return VERB_HUG
		return ""

	if context.has("station"):
		var station: Dictionary = context["station"]
		var opens: bool = bool(station.get("opens", false))
		var is_open: bool = bool(station.get("isOpen", false))
		if holding:
			# Holding something: the only thing worth offering is a place to put
			# it, and a shut fridge has to be opened before it can take anything.
			# When what is in the hand COMBINES with what is already on the
			# counter, putting it down is cooking, and the word says so.
			if bool(station.get("canCook", false)) and (not opens or is_open):
				return VERB_COOK
			if bool(station.get("canPlace", false)) and (not opens or is_open):
				return VERB_PLACE
			if opens and not is_open:
				return VERB_OPEN
			return ""
		if opens and not is_open:
			return VERB_OPEN
		var inside: Array = station.get("inside", []) as Array
		if not is_nothing(station.get("on", NONE)):
			return VERB_TAKE
		if not inside.is_empty() and (is_open or not opens):
			return VERB_TAKE
		if carrying == "item":
			# A loose prop (a teddy, a ball) is not kitchen stock; the one station
			# it can be set down on is the table.
			return VERB_PLACE if actions.has("eat") else ""
		return _furniture_verb(actions)

	if context.has("storage"):
		var storage: Dictionary = context["storage"]
		if carrying == "item":
			# Something to put away: an open box takes it, a shut one has to be
			# opened first -- the same order the fridge uses.
			if bool(storage.get("isOpen", false)):
				return VERB_PLACE if bool(storage.get("canPlace", true)) else ""
			return VERB_OPEN
		# A lid: opening and closing are the same gesture, and "OPEN" is the
		# word a child knows for both.
		return VERB_OPEN

	if carrying == "item":
		# A loose prop can be set down on a table; anything else stays a walk.
		if actions.has("eat"):
			return VERB_PLACE
		if actions.has("open"):
			return VERB_OPEN
		return ""

	if actions.has("open"):
		return VERB_OPEN
	if actions.has("pickUp"):
		return VERB_TAKE
	if actions.has("goThrough"):
		return VERB_ENTER
	return _furniture_verb(actions)


## The word for a piece of furniture with nothing in hand: a seat says SIT, a
## basin says WASH. Nothing else in the house has a word yet.
static func _furniture_verb(actions: Array) -> String:
	if actions.has("wash"):
		return VERB_WASH
	if _is_seat(actions):
		return VERB_SIT
	return ""


static func _is_seat(actions: Array) -> bool:
	return actions.has("sit")


## Flat distance from `actor` to `anchor`: height is ignored, because a fridge
## handle 1 m up is exactly as reachable as its foot.
static func flat_distance(anchor: Vector3, actor: Vector3) -> float:
	return Vector2(anchor.x - actor.x, anchor.z - actor.z).length()


static func in_range(anchor: Vector3, actor: Vector3, radius: float) -> bool:
	return flat_distance(anchor, actor) <= maxf(radius, 0.0)


## The offer to show, out of every `candidates` entry, or `{}`.
##
## Each candidate is the target's `get_affordance()` dictionary (`verb`,
## `anchor`, `radius`, `priority`, `target`) plus, optionally, `targetId`.
## Out-of-range entries are dropped. The rest are ordered by:
##
##   1. mission relevance -- the id in `preferred_ids` (the beat's walk or focus
##      target) gets `MISSION_BONUS` on top of its own priority;
##   2. priority, higher first;
##   3. distance, nearer first.
##
##   4. and, when the actor's `facing` (a flat unit vector) is supplied, the
##      NEAREST fixed target (band 2 or above) in front of her gets
##      `FACING_BONUS` before the bands are compared. She walked up to the toy
##      box and turned to face it; the kitchen door a metre further on, in band
##      3, must not shout over it. Loose props never take the bonus -- a banana
##      at her feet stays a banana -- and the bonus is smaller than
##      `MISSION_BONUS`, so a beat's own target still wins from any angle.
##
## Deterministic: two equal entries keep their input order.
static func pick(candidates: Array, actor: Vector3, preferred_ids: Array = [],
		facing: Variant = null) -> Dictionary:
	var ranked: Array = []
	var forward: Vector3 = Vector3.ZERO
	if facing is Vector3:
		forward = Vector3((facing as Vector3).x, 0.0, (facing as Vector3).z)
		if forward.length_squared() > 0.000001:
			forward = forward.normalized()
		else:
			forward = Vector3.ZERO
	for entry: Variant in candidates:
		if not (entry is Dictionary):
			continue
		var offer: Dictionary = entry
		var verb: String = normalize_verb(offer.get("verb", ""))
		if verb.is_empty():
			continue
		if not (offer.get("anchor", null) is Vector3):
			continue
		var anchor: Vector3 = offer["anchor"]
		var radius: float = float(offer.get("radius", DEFAULT_RADIUS))
		var distance: float = flat_distance(anchor, actor)
		if distance > radius:
			continue
		var score: int = int(offer.get("priority", PRIORITY_FURNITURE))
		if preferred_ids.has(String(offer.get("targetId", ""))):
			score += MISSION_BONUS
		var copy: Dictionary = offer.duplicate()
		copy["verb"] = verb
		copy["distance"] = distance
		copy["score"] = score
		copy["faced"] = false
		if forward != Vector3.ZERO and distance > 0.05 \
				and int(offer.get("priority", PRIORITY_FURNITURE)) >= PRIORITY_FURNITURE:
			var towards: Vector3 = Vector3(anchor.x - actor.x, 0.0, anchor.z - actor.z).normalized()
			copy["faced"] = towards.dot(forward) >= FACING_COS
		ranked.append(copy)
	if ranked.is_empty():
		return {}
	var nearest_faced: int = -1
	for index: int in range(ranked.size()):
		if not bool(ranked[index]["faced"]):
			continue
		if nearest_faced < 0 or float(ranked[index]["distance"]) < float(ranked[nearest_faced]["distance"]):
			nearest_faced = index
	if nearest_faced >= 0:
		ranked[nearest_faced]["score"] = int(ranked[nearest_faced]["score"]) + FACING_BONUS
	ranked.sort_custom(_better)
	return ranked[0]


static func _better(a: Dictionary, b: Dictionary) -> bool:
	var score_a: int = int(a["score"])
	var score_b: int = int(b["score"])
	if score_a != score_b:
		return score_a > score_b
	return float(a["distance"]) < float(b["distance"])
