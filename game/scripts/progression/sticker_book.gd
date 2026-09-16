class_name StickerBook
extends RefCounted

## Persistent record of which stickers the child has unlocked.
##
## Pure logic, no autoload dependency: it talks to *any* object that exposes
## `get_setting(key, default)` / `set_setting(key, value)`. In the running game
## that object is the `SaveService` autoload; in tests it is a tiny fake. When
## no save object is attached the book still works, backed by memory only, so
## scene previews and the headless test runner never crash.
##
## Storage: `SaveService` deliberately has no sticker API, so the unlocked ids
## live in the profile's `settings` block under `unlockedStickers` as a plain
## JSON array of strings. `ProfileStore` preserves unknown settings keys whose
## value is a JSON-safe type, so this survives the save/load round trip without
## any change to the save layer.
##
## Everything here is defensive: a missing, wrong-typed or half-corrupt stored
## value degrades to "nothing unlocked yet" instead of raising. A sticker is
## never *un*-unlocked, even if the star count somehow drops (a reset profile
## clears the list because the whole settings block is replaced).
##
## Offline only. No network, no analytics.

const SELF_PATH: String = "res://scripts/progression/sticker_book.gd"

## Key inside `profile.settings`. camelCase, per the project JSON convention.
const SETTING_KEY: String = "unlockedStickers"

## Absolute cap so a corrupt/hostile file can never make the UI allocate wildly.
const MAX_STORED_IDS: int = 512

var _save_service: Object = null
## Mirror of the persisted list. Also the sole storage when nothing is attached.
var _memory: Array = []


## Convenience constructor.
##
## Returns an untyped `RefCounted` on purpose: a script may not reference its
## own `class_name` before Godot's global class cache has been rebuilt, and
## `--headless --script` does not rebuild it.
static func create(save_service: Object = null) -> RefCounted:
	var script: GDScript = load(SELF_PATH) as GDScript
	if script == null:
		return null
	var book: RefCounted = script.new()
	book.call("attach", save_service)
	return book


## Helper for scene code: `StickerBook.create(StickerBook.find_save_service(self))`.
static func find_save_service(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_node_or_null("/root/SaveService")


# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------

## Attaches a persistence backend. Anything lacking the two settings methods is
## rejected (and the book falls back to memory) rather than half-wired.
func attach(save_service: Object = null) -> void:
	if save_service != null \
			and save_service.has_method("get_setting") \
			and save_service.has_method("set_setting"):
		_save_service = save_service
	else:
		_save_service = null
	_memory = _read()


func has_save_service() -> bool:
	return _save_service != null


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

## Unlocked sticker ids, in unlock order. Always a fresh Array of String.
func get_unlocked_ids() -> Array:
	return _read()


func is_unlocked(sticker_id: String) -> bool:
	return _read().has(sticker_id)


func get_unlocked_count() -> int:
	return _read().size()


## Resolved sticker dictionaries for everything unlocked, in the library's own
## (threshold-sorted) order. Ids the library no longer knows about are skipped.
func get_unlocked_stickers(library: Object) -> Array:
	var unlocked: Array = _read()
	var result: Array = []
	for sticker: Variant in _library_stickers(library):
		if typeof(sticker) != TYPE_DICTIONARY:
			continue
		var sticker_id: String = String((sticker as Dictionary).get("stickerId", ""))
		if unlocked.has(sticker_id):
			result.append(sticker)
	return result


## Every sticker in the library paired with its unlocked flag, ready for the
## grid UI: `[{ "sticker": {...}, "unlocked": bool }, ...]`.
func build_grid_entries(library: Object) -> Array:
	var unlocked: Array = _read()
	var entries: Array = []
	for sticker: Variant in _library_stickers(library):
		if typeof(sticker) != TYPE_DICTIONARY:
			continue
		var sticker_dict: Dictionary = sticker
		var sticker_id: String = String(sticker_dict.get("stickerId", ""))
		if sticker_id.is_empty():
			continue
		entries.append({
			"sticker": sticker_dict,
			"unlocked": unlocked.has(sticker_id),
		})
	return entries


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

## Unlocks one sticker. Returns `true` only the first time -- so a caller can
## use the return value as its own "celebrate once" guard.
func unlock(sticker_id: String) -> bool:
	var clean_id: String = sticker_id.strip_edges()
	if clean_id.is_empty():
		return false
	var current: Array = _read()
	if current.has(clean_id):
		return false
	current.append(clean_id)
	_write(current)
	return true


## Brings the book up to date with a star total and returns the ids that were
## newly unlocked by this call (empty when nothing changed).
##
## Idempotent: calling it repeatedly with the same star count returns `[]` and
## writes nothing. Purely additive: a *lower* star count never revokes anything.
func sync_with_stars(stars: int, library: Object) -> Array:
	var current: Array = _read()
	var newly: Array = []

	for sticker: Variant in _earned_stickers(stars, library):
		if typeof(sticker) != TYPE_DICTIONARY:
			continue
		var sticker_id: String = String((sticker as Dictionary).get("stickerId", ""))
		if sticker_id.is_empty() or current.has(sticker_id):
			continue
		current.append(sticker_id)
		newly.append(sticker_id)

	if not newly.is_empty():
		_write(current)
	return newly


## The celebration moment. Call right after stars were awarded, with the star
## total from *before* and *after* the award.
##
## Returns the full sticker dictionaries to celebrate -- only ones that were not
## already unlocked, so a sticker can never be celebrated twice even if the same
## star transition is replayed. Persists everything earned before returning.
func register_star_change(previous_stars: int, current_stars: int, library: Object) -> Array:
	var already: Dictionary = {}
	for sticker_id: Variant in _read():
		already[String(sticker_id)] = true

	var celebrate: Array = []
	if library != null and library.has_method("get_stickers_unlocked_between"):
		var crossed: Variant = library.call(
			"get_stickers_unlocked_between", maxi(previous_stars, 0), maxi(current_stars, 0))
		if typeof(crossed) == TYPE_ARRAY:
			for sticker: Variant in (crossed as Array):
				if typeof(sticker) != TYPE_DICTIONARY:
					continue
				var sticker_id: String = String((sticker as Dictionary).get("stickerId", ""))
				if sticker_id.is_empty() or already.has(sticker_id):
					continue
				already[sticker_id] = true
				celebrate.append(sticker)

	# Catch up on anything the transition window missed (e.g. a profile restored
	# with stars already banked), so the book is never behind the star count.
	sync_with_stars(current_stars, library)
	return celebrate


## Wipes the unlocked list. Only for an explicit parent-initiated reset.
func clear() -> void:
	_write([])


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _read() -> Array:
	var raw: Variant = _memory
	if _save_service != null:
		raw = _save_service.call("get_setting", SETTING_KEY, null)
		if raw == null:
			raw = []
	return _sanitize(raw)


func _write(ids: Array) -> void:
	var clean: Array = _sanitize(ids)
	_memory = clean
	if _save_service != null:
		# Hand over a fresh copy: the save layer keeps the reference we give it.
		_save_service.call("set_setting", SETTING_KEY, clean.duplicate())


## Accepts anything and returns a de-duplicated Array of non-empty Strings.
## Wrong types, nested junk and oversized payloads all degrade to something
## harmless instead of raising.
static func _sanitize(raw: Variant) -> Array:
	var result: Array = []
	var source: Array = []

	match typeof(raw):
		TYPE_ARRAY:
			source = raw
		TYPE_PACKED_STRING_ARRAY:
			for entry: String in (raw as PackedStringArray):
				source.append(entry)
		_:
			return result

	for entry: Variant in source:
		if typeof(entry) != TYPE_STRING and typeof(entry) != TYPE_STRING_NAME:
			continue
		var sticker_id: String = String(entry).strip_edges()
		if sticker_id.is_empty() or result.has(sticker_id):
			continue
		result.append(sticker_id)
		if result.size() >= MAX_STORED_IDS:
			break

	return result


func _library_stickers(library: Object) -> Array:
	if library == null or not library.has_method("get_stickers"):
		return []
	var stickers: Variant = library.call("get_stickers")
	if typeof(stickers) != TYPE_ARRAY:
		return []
	return stickers


func _earned_stickers(stars: int, library: Object) -> Array:
	if library == null or not library.has_method("get_unlocked_stickers"):
		return []
	var stickers: Variant = library.call("get_unlocked_stickers", maxi(stars, 0))
	if typeof(stickers) != TYPE_ARRAY:
		return []
	return stickers
