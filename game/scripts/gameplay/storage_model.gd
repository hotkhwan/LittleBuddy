extends RefCounted

## ============================================================================
## STORAGE -- one cabinet, drawer, shelf or toy box, as pure domain.
## ============================================================================
##
## No `Node3D`, no mesh, no `NodePath`. `CLAUDE.md` keeps domain logic
## engine-agnostic, and this is the file that decides whether a toy may go in a
## wardrobe -- a rule that has nothing to do with rendering and everything to do
## with whether the game makes sense.
##
## ## Semantic ids, not node paths
##
## A storage is addressed as `"bedroom.toyBox"` and an item as `"teddy"` with
## tags `["toy"]`. Nothing here knows where either is on screen. That is what
## stops every cabinet becoming a one-off: a new drawer is a row of data, not a
## new script.
##
## ## Refusal is never a failure
##
## The single most important method is `why_refused()`, and it exists because
## "nothing happened" is the worst possible answer for a four-year-old. Dropping
## a shirt on a closed wardrobe, on a full one, and on the toy box are three
## different situations, and each deserves its own gentle sentence:
##
##   * `REFUSED_CLOSED`     -> "Open the wardrobe first!"
##   * `REFUSED_FULL`       -> "It's full!"
##   * `REFUSED_WRONG_PLACE`-> "Try the toy box!"
##
## None of them is "wrong". `CLAUDE.md`'s child UX rules have no failure state,
## so a refusal is always a redirection.

const ACCEPTED: String = ""
const REFUSED_CLOSED: String = "closed"
const REFUSED_FULL: String = "full"
const REFUSED_WRONG_PLACE: String = "wrongPlace"
const REFUSED_ALREADY: String = "already"

const DEFAULT_CAPACITY: int = 6

var storage_id: String = ""
var accepted_tags: Array = []
var capacity: int = DEFAULT_CAPACITY
var is_open: bool = false
var stored_items: Array = []


static func create(id: String, tags: Array, item_capacity: int = DEFAULT_CAPACITY) -> RefCounted:
	var model = new()
	model.storage_id = id
	model.accepted_tags = tags.duplicate()
	model.capacity = maxi(1, item_capacity)
	return model


## Builds from a plain data row, so a room can declare its storage as content
## rather than as code:
##   {"storageId": "bedroom.toyBox", "acceptedItemTags": ["toy"], "capacity": 4}
static func from_dict(row: Dictionary) -> RefCounted:
	var tags: Array = []
	if typeof(row.get("acceptedItemTags", null)) == TYPE_ARRAY:
		tags = row.get("acceptedItemTags")
	return create(
		String(row.get("storageId", "")),
		tags,
		int(row.get("capacity", DEFAULT_CAPACITY))
	)


func open() -> void:
	is_open = true


func close() -> void:
	is_open = false


func toggle() -> bool:
	is_open = not is_open
	return is_open


func is_full() -> bool:
	return stored_items.size() >= capacity


func count() -> int:
	return stored_items.size()


func contains(item_id: String) -> bool:
	return stored_items.has(item_id)


## Does this storage take an item carrying `item_tags`? Tag match only -- the
## open/full questions are asked separately by `why_refused()`, because a child
## dropping a toy on a CLOSED toy box has aimed correctly and should be told to
## open it, not told it is the wrong place.
func matches_tags(item_tags: Array) -> bool:
	if accepted_tags.is_empty():
		return true
	for tag: Variant in item_tags:
		if accepted_tags.has(String(tag)):
			return true
	return false


## "" when the item would be accepted, else the reason. Ordered so the answer is
## the most USEFUL one rather than the first one found: aiming at the wrong
## cabinet is worth saying before "it is closed", because opening it would not
## have helped.
func why_refused(item_id: String, item_tags: Array) -> String:
	if contains(item_id):
		return REFUSED_ALREADY
	if not matches_tags(item_tags):
		return REFUSED_WRONG_PLACE
	if not is_open:
		return REFUSED_CLOSED
	if is_full():
		return REFUSED_FULL
	return ACCEPTED


func can_store(item_id: String, item_tags: Array) -> bool:
	return why_refused(item_id, item_tags) == ACCEPTED


## Puts the item away. Returns the refusal reason, or "" on success -- callers
## get the outcome AND the sentence to say from one call, so there is no way to
## store an item and forget to react to it.
func store(item_id: String, item_tags: Array) -> String:
	var reason: String = why_refused(item_id, item_tags)
	if reason != ACCEPTED:
		return reason
	stored_items.append(item_id)
	return ACCEPTED


## Takes an item back out. Returns false when it was not in there -- used by
## undo and by a child who changes their mind, never as an error.
func remove(item_id: String) -> bool:
	var index: int = stored_items.find(item_id)
	if index < 0:
		return false
	stored_items.remove_at(index)
	return true


func describe() -> Dictionary:
	return {
		"storageId": storage_id,
		"acceptedItemTags": accepted_tags.duplicate(),
		"capacity": capacity,
		"isOpen": is_open,
		"storedItems": stored_items.duplicate(),
	}
