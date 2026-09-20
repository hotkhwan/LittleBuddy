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
## Seven words, and only seven: OPEN, TAKE, PLACE, ENTER, HUG, CARRY, FEED.
## Each is a picture first (drawn by the layer) and a word second, and each has
## ONE colour from the locked palette so the same act always looks the same.
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

const VERBS: Array[String] = [
	VERB_OPEN, VERB_TAKE, VERB_PLACE, VERB_ENTER, VERB_HUG, VERB_CARRY, VERB_FEED,
]

## Nothing in the hand. `kitchen_items.gd` spells it `""`; older callers say
## `"none"`. `is_nothing()` accepts both so a context author cannot get it wrong.
const NONE: String = ""


static func is_nothing(item: Variant) -> bool:
	var text: String = String(item).strip_edges()
	return text.is_empty() or text == "none"

## Priorities a target reports by default. Higher wins. A door is the lowest:
## when a child stands between the fridge and the doorway, the fridge is the
## thing they came for.
const PRIORITY_DOOR: int = 1
const PRIORITY_FURNITURE: int = 2
const PRIORITY_CHARACTER: int = 3
## Added on top when the target is what the current mission beat is about.
const MISSION_BONUS: int = 10

## The default activation radius, metres, when a target supplies none.
const DEFAULT_RADIUS: float = 1.6


static func is_verb(verb: String) -> bool:
	return VERBS.has(verb)


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
##   `storage`   -- Dictionary for a container with a lid: `isOpen`.
##   `character` -- Dictionary for a character target: `canHug`, `canCarry`,
##                  `canFeed`.
static func verb_for_target(description: Dictionary, context: Dictionary = {}) -> String:
	if not bool(description.get("enabled", true)):
		return ""
	if bool(description.get("isDoor", false)):
		return VERB_ENTER

	var holding: bool = not is_nothing(context.get("held", NONE))

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
		return ""

	if context.has("storage"):
		# A lid: opening and closing are the same gesture, and "OPEN" is the
		# word a child knows for both.
		return VERB_OPEN

	var actions: Array = description.get("supportedActions", []) as Array
	if actions.has("open"):
		return VERB_OPEN
	if actions.has("pickUp"):
		return VERB_TAKE
	if actions.has("goThrough"):
		return VERB_ENTER
	return ""


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
## Deterministic: two equal entries keep their input order.
static func pick(candidates: Array, actor: Vector3, preferred_ids: Array = []) -> Dictionary:
	var ranked: Array = []
	for entry: Variant in candidates:
		if not (entry is Dictionary):
			continue
		var offer: Dictionary = entry
		var verb: String = String(offer.get("verb", ""))
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
		copy["distance"] = distance
		copy["score"] = score
		ranked.append(copy)
	if ranked.is_empty():
		return {}
	ranked.sort_custom(_better)
	return ranked[0]


static func _better(a: Dictionary, b: Dictionary) -> bool:
	var score_a: int = int(a["score"])
	var score_b: int = int(b["score"])
	if score_a != score_b:
		return score_a > score_b
	return float(a["distance"]) < float(b["distance"])
