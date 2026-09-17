extends RefCounted

## The English word a house object teaches, and its optional Thai hint.
##
## Free Play has no objective, so the *word* is the reward: a child taps the
## fridge, hears "fridge", and Little Buddy walks over and opens it. That is the
## whole loop, and this table is the half of it that has to be right.
##
## ## Pure, and deliberately not content
##
## Dictionary in, Dictionary out -- no node, no `Vector3`, no `ContentLibrary`.
## Three reasons it lives here rather than in `content/vocabulary/vocabulary.json`:
##
##   1. these words are properties of the HOUSE (`bedroom.wardrobe`), not of a
##      lesson, and the house is built from `house_layout.gd`, not from content;
##   2. Free Play must work with no content set loaded at all -- a child tapping
##      a sofa cannot depend on a JSON read succeeding;
##   3. `content/**` is another agent's file tonight.
##
## Where a word DOES also exist in the vocabulary set, the two must agree, or a
## child would be taught "toy box" in the story and something else in Free Play.
## `test_freeplay.gd` asserts that overlap against the real JSON, so the
## duplication cannot drift silently.
##
## ## Doors teach rooms
##
## A door is an activity target like any other, so tapping one says a word too --
## and the honest word for "the thing that takes you to the kitchen" is
## **kitchen**. Room names are already in the taught vocabulary, so a door is a
## free repetition rather than a fifth noun for a rectangle.

const HouseLayout := preload("res://scripts/house/house_layout.gd")
const HouseRoute := preload("res://scripts/house/house_route.gd")
const SemanticId := preload("res://scripts/navigation/semantic_id.gd")

## Local target id -> the word a tap teaches.
##
## `thai` is the LONG-PRESS hint only (ART_BIBLE section 9): it is never spoken,
## because the voice is an en-US one and a Thai string read by an English voice
## teaches a child the wrong sound for their own language.
const WORDS: Dictionary = {
	# bedroom
	"bed": {"word": "bed", "thai": "เตียง"},
	"wardrobe": {"word": "wardrobe", "thai": "ตู้เสื้อผ้า"},
	"toy": {"word": "toy", "thai": "ของเล่น"},
	# bathroom
	"sink": {"word": "sink", "thai": "อ่างล้างหน้า"},
	"bath": {"word": "bath", "thai": "อ่างอาบน้ำ"},
	"towel": {"word": "towel", "thai": "ผ้าเช็ดตัว"},
	# kitchen
	"fridge": {"word": "fridge", "thai": "ตู้เย็น"},
	"counter": {"word": "counter", "thai": "เคาน์เตอร์"},
	"table": {"word": "table", "thai": "โต๊ะ"},
	# living room
	"sofa": {"word": "sofa", "thai": "โซฟา"},
	"toyBox": {"word": "toy box", "thai": "กล่องของเล่น"},
	"book": {"word": "book", "thai": "หนังสือ"},
}

## Room id -> the Thai for that room, for the doors.
const ROOM_THAI: Dictionary = {
	"bedroom": "ห้องนอน",
	"bathroom": "ห้องน้ำ",
	"kitchen": "ห้องครัว",
	"livingRoom": "ห้องนั่งเล่น",
}

## The word ids in `content/vocabulary/vocabulary.json` these entries must agree
## with. Keyed by the local target id. Anything not listed is house-only and has
## no content counterpart to drift from.
const SHARED_WITH_VOCABULARY: Dictionary = {
	"bed": "bed",
	"towel": "towel",
	"table": "table",
	"sofa": "sofa",
	"toyBox": "toyBox",
	"bedroom": "bedroom",
	"bathroom": "bathroom",
	"kitchen": "kitchen",
	"livingRoom": "livingRoom",
}

## What Little Buddy does when he gets there, per object.
##
## **Only names from the contract's sixteen-verb action vocabulary**
## (`character_action_driver.gd::KNOWN_ACTIONS`) -- never an animation filename,
## and never a verb that merely sounds right. `dress` and `play` are both drop
## zone / lesson words rather than actions, and a character asked for one of them
## would simply do nothing; `test_freeplay.gd` checks this whole table against
## the real list so that cannot happen quietly.
##
## This is what turns "tap a thing" into a small piece of play rather than a
## walk: the bed is for sleeping in, the table is for eating at, the toy is for
## hugging. An action with no clip yet still starts, times out and returns to
## idle, so an unanimated verb is never a stuck child.
const ACTIONS: Dictionary = {
	"bed": "sleep",
	"wardrobe": "pickUp",
	"toy": "hug",
	"sink": "brushTeeth",
	"bath": "wave",
	"towel": "pickUp",
	"fridge": "drink",
	"counter": "pickUp",
	"table": "eat",
	"sofa": "sit",
	"toyBox": "pickUp",
	"book": "pickUp",
}

## The reaction spoken after the action, so an arrival is warm rather than
## silent. Short, forward-looking, never a score (CLAUDE.md child UX).
const REACTIONS: Array[String] = ["Nice!", "Great!", "Yay!", "Look!"]


## `{ "word": "fridge", "thai": "ตู้เย็น", "action": "drink" }` for a semantic id.
##
## Accepts either half of the address -- `"kitchen.fridge"` or a bare
## `"fridge"` -- because the character echoes back whichever id the target
## reports. An id this house does not have returns empty strings rather than
## null, so no caller ever has to check for null before reading a key.
static func describe(semantic_id: Variant) -> Dictionary:
	var local: String = _local_of(semantic_id)
	if local.is_empty():
		return _entry("", "", "")

	if HouseRoute.is_door_id(local):
		var destination: String = HouseRoute.door_destination(local)
		if destination.is_empty():
			return _entry("", "", "")
		# No action: walking through IS what a door does, and asking for one
		# would play it in the room the child is about to leave.
		return _entry(
			HouseLayout.display_name(destination),
			String(ROOM_THAI.get(destination, "")),
			""
		)

	var entry: Variant = WORDS.get(local, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return _entry("", "", "")
	return _entry(
		String((entry as Dictionary).get("word", "")),
		String((entry as Dictionary).get("thai", "")),
		String(ACTIONS.get(local, ""))
	)


## Just the English word, or "" for an id this house does not have.
static func word_for(semantic_id: Variant) -> String:
	return String(describe(semantic_id).get("word", ""))


static func thai_for(semantic_id: Variant) -> String:
	return String(describe(semantic_id).get("thai", ""))


## The semantic action to play on arrival, or "" for "just stand there".
static func action_for(semantic_id: Variant) -> String:
	return String(describe(semantic_id).get("action", ""))


## True when this house object teaches anything at all. Used by the tests to
## prove that EVERY id the world reports is covered -- a new prop with no word
## would otherwise be a silent tap, which is the one thing Free Play cannot have.
static func has_word(semantic_id: Variant) -> bool:
	return not word_for(semantic_id).is_empty()


## A short, warm line for arriving somewhere. Deterministic given `seed_value`
## so a test can assert it without a random.
static func reaction_for(seed_value: int) -> String:
	if REACTIONS.is_empty():
		return ""
	return REACTIONS[absi(seed_value) % REACTIONS.size()]


static func _entry(word: String, thai: String, action: String) -> Dictionary:
	return {"word": word, "thai": thai, "action": action}


static func _local_of(semantic_id: Variant) -> String:
	var text: String = String(semantic_id).strip_edges()
	if text.is_empty():
		return ""
	var local: String = SemanticId.target_of(text)
	return local if not local.is_empty() else text
