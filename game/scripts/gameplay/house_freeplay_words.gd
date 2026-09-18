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
	"toyShelf": {"word": "shelf", "thai": "ชั้นวางของ"},
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
	"toyShelf": "pickUp",
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


## -- What a child can pick up and move ------------------------------------------
##
## Free Play used to have no draggable object in it at all, which made the drag
## gesture first run teaches a demonstration over an empty floor. These are the
## real ones.
##
## Each entry is `objectId` (a record in `content/objects.json`), the content
## `interaction` that decides WHICH landing pad it belongs in (`drop_zone.gd`
## owns that mapping -- this table never names a zone id directly), and the
## semantic action Little Buddy plays when it arrives.
##
## Two flavours on purpose, because they teach different things:
##
##   * **to Little Buddy** -- `dragToMouth` / `dragToHug` / `tap`. The pad rides
##     on him, so the target is a face rather than a spot on the floor.
##   * **to the furniture** -- `dragToBath` / `dragToToyBox`. The pad sits on a
##     real prop, named in `DRAG_FOCUS` below.
##
## Three per room: enough that the row is worth looking at twice, few enough
## that four 0.61 m grab colliders never crowd each other in a 4 m room.
const DRAGGABLES: Dictionary = {
	"bedroom": [
		{"objectId": "teddy", "interaction": "dragToHug", "action": "hug"},
		{"objectId": "pillow", "interaction": "dragToHug", "action": "hug"},
		{"objectId": "blanket", "interaction": "dragToHug", "action": "hug"},
	],
	"bathroom": [
		{"objectId": "bathToy", "interaction": "dragToBath", "action": "wave"},
		{"objectId": "soap", "interaction": "dragToBath", "action": "clap"},
		{"objectId": "toothbrush", "interaction": "tap", "action": "brushTeeth"},
	],
	"kitchen": [
		{"objectId": "apple", "interaction": "dragToMouth", "action": "eat"},
		{"objectId": "banana", "interaction": "dragToMouth", "action": "eat"},
		{"objectId": "milk", "interaction": "dragToMouth", "action": "drink"},
	],
	"livingRoom": [
		{"objectId": "ball", "interaction": "dragToToyBox", "action": "pickUp"},
		{"objectId": "blocks", "interaction": "dragToToyBox", "action": "pickUp"},
		{"objectId": "starToy", "interaction": "dragToToyBox", "action": "pickUp"},
	],
}

## The prop a room's furniture-mounted landing pad sits on, as a LOCAL target id.
##
## One per room, deliberately: `house_stage.gd` tracks every prop pad to a single
## focus point, so a room with two furniture targets would put both pads in the
## same place. Rooms whose objects all go to Little Buddy have no entry, and
## their pads simply follow him.
const DRAG_FOCUS: Dictionary = {
	"bathroom": "bath",
	"livingRoom": "toyBox",
}

## Warm, short, and about the OBJECT rather than about the child. Spoken after
## the word, never a score (CLAUDE.md child UX).
const DROP_REACTIONS: Array[String] = ["Thank you!", "Yay!", "Nice one!", "Lovely!"]


## The draggable set for a room, `[]` for a room with none. A fresh Array of
## fresh Dictionaries every call, so a caller may mutate the result freely.
static func draggables_for(room_id: Variant) -> Array:
	var entries: Variant = DRAGGABLES.get(String(room_id).strip_edges(), null)
	if typeof(entries) != TYPE_ARRAY:
		return []
	var copy: Array = []
	for entry: Variant in entries as Array:
		if typeof(entry) == TYPE_DICTIONARY:
			copy.append((entry as Dictionary).duplicate())
	return copy


## The entry for one object id in one room, or an empty Dictionary. Shaped like a
## real entry either way, so a caller never has to test for null.
static func draggable_entry(room_id: Variant, object_id: Variant) -> Dictionary:
	var wanted: String = String(object_id).strip_edges()
	for entry: Variant in draggables_for(room_id):
		if String((entry as Dictionary).get("objectId", "")) == wanted:
			return entry as Dictionary
	return {"objectId": "", "interaction": "", "action": ""}


## The LOCAL id of the prop this room's furniture pad rides on, or "".
static func drag_focus_for(room_id: Variant) -> String:
	return String(DRAG_FOCUS.get(String(room_id).strip_edges(), ""))


## Every object id any room can put in a child's hand. Used by the tests to prove
## each one is a real `objects.json` record.
static func all_draggable_object_ids() -> Array:
	var ids: Array = []
	for room_id: Variant in DRAGGABLES.keys():
		for entry: Variant in draggables_for(room_id):
			var id: String = String((entry as Dictionary).get("objectId", ""))
			if not id.is_empty() and not ids.has(id):
				ids.append(id)
	return ids


## A short, warm line for putting something where it belongs. Deterministic given
## `seed_value` so a test can assert it without a random.
static func drop_reaction_for(seed_value: int) -> String:
	if DROP_REACTIONS.is_empty():
		return ""
	return DROP_REACTIONS[absi(seed_value) % DROP_REACTIONS.size()]


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
