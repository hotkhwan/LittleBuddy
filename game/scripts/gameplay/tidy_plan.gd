extends RefCounted

## ============================================================================
## TIDY UP -- the cleanup activity, as pure domain.
## ============================================================================
##
## A room starts with a few things on the floor; the child puts each one where it
## belongs; the room ends tidy. No `Node3D` here either -- this decides what is
## scattered, whether a placement was right, and what is said about it.
##
## ## Three to six items, and why not more
##
## `CLAUDE.md` forbids timers and failure pressure, so the only way this activity
## can go wrong is by being BORING. Six is about the limit of a three-year-old's
## patience for a repeated action, and three is enough to feel like a job. Past
## six it stops being a game and becomes chores, which is the exact failure the
## brief warns about ("do not make cleanup tedious").
##
## ## Every item teaches a word
##
## Each scattered thing carries an English word and the two verbs that go with
## it -- `open`, `put away`, `close`. That is the whole vocabulary set the brief
## asks for, and it arrives through play rather than through a word list.

const StorageModel := preload("res://scripts/gameplay/storage_model.gd")

const MIN_ITEMS: int = 3
const MAX_ITEMS: int = 6

## The vocabulary this activity is responsible for teaching.
const WORDS: Array[String] = [
	"toy", "book", "shirt", "open", "close", "put away", "clean up",
]

## One row per scatterable thing. `tags` is what decides where it belongs, and
## it is deliberately the SAME vocabulary the storage accepts -- a `toy` goes in
## whatever takes `toy`, so adding a second toy cabinet needs no code.
## The toy ids are `content/objects.json` records, so the house can put the
## real thing on the floor (`house_freeplay_director.gd` scatters them).
const ITEMS: Array[Dictionary] = [
	{"itemId": "teddy", "word": "teddy", "tags": ["toy"]},
	{"itemId": "ball", "word": "ball", "tags": ["toy"]},
	{"itemId": "blocks", "word": "blocks", "tags": ["toy"]},
	{"itemId": "starToy", "word": "star", "tags": ["toy"]},
	{"itemId": "squareToy", "word": "square", "tags": ["toy"]},
	{"itemId": "circleToy", "word": "circle", "tags": ["toy"]},
	{"itemId": "book", "word": "book", "tags": ["book"]},
	{"itemId": "shirt", "word": "shirt", "tags": ["clothes"]},
	{"itemId": "socks", "word": "socks", "tags": ["clothes"]},
]


## The encouragement said when an item lands correctly. Rotated by index so a
## six-item tidy does not say "Great!" six times, which stops reading as praise.
const PRAISE: Array[String] = [
	"Great!", "Nice!", "Well done!", "Good job!", "Lovely!", "Clever!",
]


## What to say for each refusal. These are the sentences the brief asks for, and
## every one is a REDIRECTION: none says no, none says wrong.
static func refusal_line(reason: String, storage_word: String = "") -> String:
	match reason:
		StorageModel.REFUSED_CLOSED:
			return "Open the %s first!" % storage_word if not storage_word.is_empty() \
					else "Open it first!"
		StorageModel.REFUSED_FULL:
			return "That one is full! Try another."
		StorageModel.REFUSED_WRONG_PLACE:
			return "Not that one. Try again!"
		StorageModel.REFUSED_ALREADY:
			return "That one is already away!"
		_:
			return ""


static func praise_line(index: int) -> String:
	if PRAISE.is_empty():
		return "Great!"
	return PRAISE[index % PRAISE.size()]


## The prompt that names the next thing to do. Short, one instruction, and it
## names the object so the word is heard in context rather than drilled.
static func prompt_line(item_word: String) -> String:
	return "Put the %s away!" % item_word


static func finished_line() -> String:
	return "All tidy! Great job!"


## -- The plan ------------------------------------------------------------------

var items: Array = []
var placed: Array = []


## Picks `count` items, clamped to the child-sized range. Deterministic given
## `seed_value`, so a test asserts a real plan rather than a shuffled one and a
## child can be handed the same room twice.
static func build(count: int, seed_value: int = 0) -> RefCounted:
	var plan = new()
	var wanted: int = clampi(count, MIN_ITEMS, MAX_ITEMS)
	var pool: Array = ITEMS.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Fisher-Yates over a copy: never mutates the const table.
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	plan.items = pool.slice(0, wanted)
	return plan


## A plan for ONE container: only items it will take (`accepted_tags`, an
## empty list meaning anything), never an id in `exclude` (things already on
## the floor), at most `count` of them. `count` is clamped to 1..`MAX_ITEMS`
## rather than 3..6, because the box may have only two free slots left and a
## tidy of two is still a tidy; a plan with nothing in it is the caller's cue
## to just open the lid.
static func build_for(accepted_tags: Array, count: int, seed_value: int = 0,
		exclude: Array = []) -> RefCounted:
	var plan = new()
	var wanted: int = clampi(count, 1, MAX_ITEMS)
	var pool: Array = []
	for row: Dictionary in ITEMS:
		var item_id: String = String(row["itemId"])
		if exclude.has(item_id):
			continue
		if accepted_tags.is_empty():
			pool.append(row)
			continue
		for tag: Variant in row["tags"]:
			if accepted_tags.has(String(tag)):
				pool.append(row)
				break
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	plan.items = pool.slice(0, wanted)
	return plan


func total() -> int:
	return items.size()


func remaining() -> int:
	return maxi(0, items.size() - placed.size())


func is_complete() -> bool:
	return remaining() == 0


func next_item() -> Dictionary:
	for row: Dictionary in items:
		if not placed.has(String(row["itemId"])):
			return row
	return {}


func tags_for(item_id: String) -> Array:
	for row: Dictionary in items:
		if String(row["itemId"]) == item_id:
			return (row["tags"] as Array).duplicate()
	return []


func word_for(item_id: String) -> String:
	for row: Dictionary in items:
		if String(row["itemId"]) == item_id:
			return String(row["word"])
	return item_id


## Marks `item_id` as put away when the host's OWN storage has already taken
## it (the room's model stores the real node; this plan only keeps score).
## Same shape as `place()`'s success: the sentence to say and whether that was
## the last one. `recorded` is false for an id this plan never scattered, so
## a teddy that was already on the floor gets the ordinary "In it goes!".
func record_placed(item_id: String) -> Dictionary:
	if tags_for(item_id).is_empty():
		return {"recorded": false, "say": "", "complete": is_complete()}
	if not placed.has(item_id):
		placed.append(item_id)
	var done: bool = is_complete()
	return {
		"recorded": true,
		"say": finished_line() if done else praise_line(placed.size() - 1),
		"complete": done,
	}


## The child took it back out: it counts again. Never an error.
func unplace(item_id: String) -> bool:
	var index: int = placed.find(item_id)
	if index < 0:
		return false
	placed.remove_at(index)
	return true


## Attempts to put `item_id` into `storage`. Returns
## `{"accepted": bool, "reason": String, "say": String, "complete": bool}` --
## one call gives the outcome AND the sentence, so no caller can place an item
## and forget to respond to it.
func place(item_id: String, storage: RefCounted, storage_word: String = "") -> Dictionary:
	var tags: Array = tags_for(item_id)
	var reason: String = storage.call("store", item_id, tags)
	if reason != StorageModel.ACCEPTED:
		return {
			"accepted": false,
			"reason": reason,
			"say": refusal_line(reason, storage_word),
			"complete": false,
		}
	if not placed.has(item_id):
		placed.append(item_id)
	var done: bool = is_complete()
	return {
		"accepted": true,
		"reason": StorageModel.ACCEPTED,
		"say": finished_line() if done else praise_line(placed.size() - 1),
		"complete": done,
	}
