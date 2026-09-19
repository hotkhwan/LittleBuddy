class_name ContentLibrary
extends RefCounted

## Loads and indexes all bundled Little Buddy content (objects, tasks, missions,
## stickers, vocabulary).
##
## Defensive by design, mirroring `ActivityLoader`: a missing, unreadable or
## malformed file never crashes and never raises. The affected collection simply
## stays empty, a human-readable warning is recorded in `get_load_warnings()`,
## and loading continues with everything else. Callers can therefore always call
## any getter without null checks.
##
## All getters return deep copies, so consumers cannot corrupt the shared index.
##
## Offline only: content is read exclusively from `res://`. No network access.

const SELF_PATH: String = "res://scripts/content/content_library.gd"

const DEFAULT_INDEX_PATH: String = "res://content/index.json"

const MODES: Array[String] = ["findIt", "sayIt", "followInstruction"]

const INTERACTIONS: Array[String] = [
	"dragToMouth",
	"dragToHug",
	"dragToBath",
	"dragToDress",
	"dragToToyBox",
	"tap",
	# Care acts performed ON the child at a piece of furniture. They are drags
	# too, but not deliveries -- see `house_task_plan.gd::CARE_INTERACTIONS`.
	"brushTeeth",
	"washFace",
	"dryFace",
]

## Fallback category list used when `index.json` is missing or unreadable.
const FALLBACK_CATEGORIES: Array[Dictionary] = [
	{"categoryId": "feeding", "title": "Feeding", "tasksFile": "res://content/feeding/tasks.json"},
	{"categoryId": "dressing", "title": "Dress Up", "tasksFile": "res://content/dressing/tasks.json"},
	{"categoryId": "bath", "title": "Bath Time", "tasksFile": "res://content/bath/tasks.json"},
	{"categoryId": "play", "title": "Play Room", "tasksFile": "res://content/play/tasks.json"},
	{"categoryId": "bedtime", "title": "Bedtime", "tasksFile": "res://content/bedtime/tasks.json"},
]

const LEGACY_ACTIVITY_PATH: String = "res://content/feeding/feed_milk.json"

var _index: Dictionary = {}
var _categories: Array = []

var _objects: Array = []
var _objects_by_id: Dictionary = {}

var _tasks: Array = []
var _tasks_by_id: Dictionary = {}
var _tasks_by_category: Dictionary = {}
var _tasks_by_mode: Dictionary = {}

var _missions: Array = []
var _missions_by_id: Dictionary = {}

var _stickers: Array = []
var _stickers_by_id: Dictionary = {}

var _words: Array = []
var _words_by_id: Dictionary = {}

var _warnings: Array = []


## Convenience constructor: builds and loads a library in one call.
##
## Deliberately returns an untyped `RefCounted` rather than `ContentLibrary`: a
## script may not reference its own `class_name` before Godot's global class
## cache has been rebuilt, and `--headless --script` does not rebuild it. Typing
## this would make the whole script fail to compile on a cold checkout.
static func create(index_path: String = DEFAULT_INDEX_PATH) -> RefCounted:
	var script: GDScript = load(SELF_PATH) as GDScript
	if script == null:
		return null
	var library: RefCounted = script.new()
	library.call("load_all", index_path)
	return library


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

## Loads (or reloads) every content file. Safe to call repeatedly.
func load_all(index_path: String = DEFAULT_INDEX_PATH) -> void:
	_reset()

	_index = _read_json_dict(index_path, "content index")
	_categories = _resolve_categories()

	_load_objects()
	_load_tasks()
	_load_missions()
	_load_stickers()
	_load_vocabulary()


func _reset() -> void:
	_index = {}
	_categories = []
	_objects = []
	_objects_by_id = {}
	_tasks = []
	_tasks_by_id = {}
	_tasks_by_category = {}
	_tasks_by_mode = {}
	_missions = []
	_missions_by_id = {}
	_stickers = []
	_stickers_by_id = {}
	_words = []
	_words_by_id = {}
	_warnings = []


func _resolve_categories() -> Array:
	var raw: Variant = _index.get("categories", null)
	var resolved: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for entry: Variant in (raw as Array):
			if typeof(entry) == TYPE_DICTIONARY and String((entry as Dictionary).get("categoryId", "")) != "":
				resolved.append(entry)
	if resolved.is_empty():
		_warn("content index has no usable 'categories'; using built-in fallback list")
		for fallback: Dictionary in FALLBACK_CATEGORIES:
			resolved.append(fallback.duplicate(true))
	return resolved


func _load_objects() -> void:
	var path: String = String(_index.get("objectsFile", "res://content/objects.json"))
	var data: Dictionary = _read_json_dict(path, "objects")
	for entry: Variant in _array_field(data, "objects", path):
		if typeof(entry) != TYPE_DICTIONARY:
			_warn("%s: skipped a non-object entry in 'objects'" % path)
			continue
		var object_data: Dictionary = entry
		var object_id: String = String(object_data.get("objectId", ""))
		if object_id.is_empty():
			_warn("%s: skipped an object with a missing 'objectId'" % path)
			continue
		if _objects_by_id.has(object_id):
			_warn("%s: duplicate objectId '%s' ignored" % [path, object_id])
			continue
		_objects.append(object_data)
		_objects_by_id[object_id] = object_data


func _load_tasks() -> void:
	for category_entry: Variant in _categories:
		if typeof(category_entry) != TYPE_DICTIONARY:
			continue
		var category: Dictionary = category_entry
		var category_id: String = String(category.get("categoryId", ""))
		var path: String = String(category.get("tasksFile", ""))
		if path.is_empty():
			_warn("category '%s' has no 'tasksFile'" % category_id)
			continue

		var data: Dictionary = _read_json_dict(path, "tasks for '%s'" % category_id)
		for entry: Variant in _array_field(data, "tasks", path):
			if typeof(entry) != TYPE_DICTIONARY:
				_warn("%s: skipped a non-object entry in 'tasks'" % path)
				continue
			var task: Dictionary = entry
			var task_id: String = String(task.get("taskId", ""))
			if task_id.is_empty():
				_warn("%s: skipped a task with a missing 'taskId'" % path)
				continue
			if _tasks_by_id.has(task_id):
				_warn("%s: duplicate taskId '%s' ignored" % [path, task_id])
				continue

			_tasks.append(task)
			_tasks_by_id[task_id] = task

			var task_category: String = String(task.get("category", category_id))
			if not _tasks_by_category.has(task_category):
				_tasks_by_category[task_category] = []
			(_tasks_by_category[task_category] as Array).append(task)

			var mode: String = String(task.get("mode", ""))
			if not mode.is_empty():
				if not _tasks_by_mode.has(mode):
					_tasks_by_mode[mode] = []
				(_tasks_by_mode[mode] as Array).append(task)


func _load_missions() -> void:
	var path: String = String(_index.get("missionsFile", "res://content/missions/missions.json"))
	var data: Dictionary = _read_json_dict(path, "missions")
	for entry: Variant in _array_field(data, "missions", path):
		if typeof(entry) != TYPE_DICTIONARY:
			_warn("%s: skipped a non-object entry in 'missions'" % path)
			continue
		var mission: Dictionary = entry
		var mission_id: String = String(mission.get("missionId", ""))
		if mission_id.is_empty():
			_warn("%s: skipped a mission with a missing 'missionId'" % path)
			continue
		if _missions_by_id.has(mission_id):
			_warn("%s: duplicate missionId '%s' ignored" % [path, mission_id])
			continue
		_missions.append(mission)
		_missions_by_id[mission_id] = mission


func _load_stickers() -> void:
	var path: String = String(_index.get("stickersFile", "res://content/stickers/stickers.json"))
	var data: Dictionary = _read_json_dict(path, "stickers")
	for entry: Variant in _array_field(data, "stickers", path):
		if typeof(entry) != TYPE_DICTIONARY:
			_warn("%s: skipped a non-object entry in 'stickers'" % path)
			continue
		var sticker: Dictionary = entry
		var sticker_id: String = String(sticker.get("stickerId", ""))
		if sticker_id.is_empty():
			_warn("%s: skipped a sticker with a missing 'stickerId'" % path)
			continue
		if _stickers_by_id.has(sticker_id):
			_warn("%s: duplicate stickerId '%s' ignored" % [path, sticker_id])
			continue
		_stickers.append(sticker)
		_stickers_by_id[sticker_id] = sticker

	_stickers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _as_int(a.get("unlockAtStars", 0)) < _as_int(b.get("unlockAtStars", 0)))


func _load_vocabulary() -> void:
	var path: String = String(_index.get("vocabularyFile", "res://content/vocabulary/vocabulary.json"))
	var data: Dictionary = _read_json_dict(path, "vocabulary")
	for entry: Variant in _array_field(data, "words", path):
		if typeof(entry) != TYPE_DICTIONARY:
			_warn("%s: skipped a non-object entry in 'words'" % path)
			continue
		var word: Dictionary = entry
		var word_id: String = String(word.get("wordId", ""))
		if word_id.is_empty():
			_warn("%s: skipped a word with a missing 'wordId'" % path)
			continue
		if _words_by_id.has(word_id):
			_warn("%s: duplicate wordId '%s' ignored" % [path, word_id])
			continue
		_words.append(word)
		_words_by_id[word_id] = word


# ---------------------------------------------------------------------------
# Objects
# ---------------------------------------------------------------------------

func get_objects() -> Array:
	return _copy_array(_objects)


func get_object(object_id: String) -> Dictionary:
	var found: Variant = _objects_by_id.get(object_id, null)
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return (found as Dictionary).duplicate(true)


func has_object(object_id: String) -> bool:
	return _objects_by_id.has(object_id)


func get_object_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for object_id: Variant in _objects_by_id.keys():
		ids.append(String(object_id))
	return ids


func get_objects_in_category(category: String) -> Array:
	var result: Array = []
	for object_data: Variant in _objects:
		if typeof(object_data) == TYPE_DICTIONARY and String((object_data as Dictionary).get("category", "")) == category:
			result.append((object_data as Dictionary).duplicate(true))
	return result


func get_object_count() -> int:
	return _objects.size()


# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------

func get_tasks() -> Array:
	return _copy_array(_tasks)


func get_task(task_id: String) -> Dictionary:
	var found: Variant = _tasks_by_id.get(task_id, null)
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return (found as Dictionary).duplicate(true)


func has_task(task_id: String) -> bool:
	return _tasks_by_id.has(task_id)


func get_task_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for task_id: Variant in _tasks_by_id.keys():
		ids.append(String(task_id))
	return ids


func get_tasks_in_category(category: String) -> Array:
	return _copy_array(_tasks_by_category.get(category, []))


func get_tasks_with_mode(mode: String) -> Array:
	return _copy_array(_tasks_by_mode.get(mode, []))


func get_tasks_for_object(object_id: String) -> Array:
	var result: Array = []
	for task: Variant in _tasks:
		if typeof(task) == TYPE_DICTIONARY and String((task as Dictionary).get("objectId", "")) == object_id:
			result.append((task as Dictionary).duplicate(true))
	return result


func get_task_count() -> int:
	return _tasks.size()


func get_categories() -> Array:
	return _copy_array(_categories)


func get_category_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for category: Variant in _categories:
		if typeof(category) == TYPE_DICTIONARY:
			ids.append(String((category as Dictionary).get("categoryId", "")))
	return ids


func get_modes() -> Array:
	var raw: Variant = _index.get("modes", null)
	if typeof(raw) == TYPE_ARRAY and not (raw as Array).is_empty():
		return (raw as Array).duplicate(true)
	return MODES.duplicate()


func get_interactions() -> Array:
	var raw: Variant = _index.get("interactions", null)
	if typeof(raw) == TYPE_ARRAY and not (raw as Array).is_empty():
		return (raw as Array).duplicate(true)
	return INTERACTIONS.duplicate()


# ---------------------------------------------------------------------------
# Missions
# ---------------------------------------------------------------------------

func get_missions() -> Array:
	return _copy_array(_missions)


func get_mission(mission_id: String) -> Dictionary:
	var found: Variant = _missions_by_id.get(mission_id, null)
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return (found as Dictionary).duplicate(true)


func has_mission(mission_id: String) -> bool:
	return _missions_by_id.has(mission_id)


func get_mission_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for mission_id: Variant in _missions_by_id.keys():
		ids.append(String(mission_id))
	return ids


## Resolved task dictionaries for a mission, in authored order.
## Unresolvable task ids are skipped rather than returned as nulls.
func get_mission_tasks(mission_id: String) -> Array:
	var mission: Variant = _missions_by_id.get(mission_id, null)
	if typeof(mission) != TYPE_DICTIONARY:
		return []
	var result: Array = []
	for task_id: Variant in _string_array((mission as Dictionary).get("taskIds", [])):
		var task: Dictionary = get_task(String(task_id))
		if not task.is_empty():
			result.append(task)
	return result


func get_unlocked_missions(stars: int) -> Array:
	var result: Array = []
	for mission: Variant in _missions:
		if typeof(mission) != TYPE_DICTIONARY:
			continue
		if _as_int((mission as Dictionary).get("unlockAtStars", 0)) <= stars:
			result.append((mission as Dictionary).duplicate(true))
	return result


func get_mission_count() -> int:
	return _missions.size()


# ---------------------------------------------------------------------------
# Stickers
# ---------------------------------------------------------------------------

func get_stickers() -> Array:
	return _copy_array(_stickers)


func get_sticker(sticker_id: String) -> Dictionary:
	var found: Variant = _stickers_by_id.get(sticker_id, null)
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return (found as Dictionary).duplicate(true)


func get_sticker_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for sticker_id: Variant in _stickers_by_id.keys():
		ids.append(String(sticker_id))
	return ids


func get_unlocked_stickers(stars: int) -> Array:
	var result: Array = []
	for sticker: Variant in _stickers:
		if typeof(sticker) != TYPE_DICTIONARY:
			continue
		if _as_int((sticker as Dictionary).get("unlockAtStars", 0)) <= stars:
			result.append((sticker as Dictionary).duplicate(true))
	return result


## The cheapest sticker the child has not yet reached. `{}` when all are earned.
func get_next_sticker(stars: int) -> Dictionary:
	for sticker: Variant in _stickers:
		if typeof(sticker) != TYPE_DICTIONARY:
			continue
		if _as_int((sticker as Dictionary).get("unlockAtStars", 0)) > stars:
			return (sticker as Dictionary).duplicate(true)
	return {}


## Stickers whose threshold falls in `(previous_stars, current_stars]` — i.e. the
## ones to celebrate right now after a star award.
func get_stickers_unlocked_between(previous_stars: int, current_stars: int) -> Array:
	var result: Array = []
	for sticker: Variant in _stickers:
		if typeof(sticker) != TYPE_DICTIONARY:
			continue
		var threshold: int = _as_int((sticker as Dictionary).get("unlockAtStars", 0))
		if threshold > previous_stars and threshold <= current_stars:
			result.append((sticker as Dictionary).duplicate(true))
	return result


func get_sticker_count() -> int:
	return _stickers.size()


# ---------------------------------------------------------------------------
# Vocabulary
# ---------------------------------------------------------------------------

func get_words() -> Array:
	return _copy_array(_words)


func get_word(word_id: String) -> Dictionary:
	var found: Variant = _words_by_id.get(word_id, null)
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return (found as Dictionary).duplicate(true)


func get_word_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for word_id: Variant in _words_by_id.keys():
		ids.append(String(word_id))
	return ids


func get_words_in_category(category: String) -> Array:
	var result: Array = []
	for word: Variant in _words:
		if typeof(word) == TYPE_DICTIONARY and String((word as Dictionary).get("category", "")) == category:
			result.append((word as Dictionary).duplicate(true))
	return result


func get_word_count() -> int:
	return _words.size()


# ---------------------------------------------------------------------------
# Phrase variants
# ---------------------------------------------------------------------------

## Every distinct child-facing English string across prompts, instructions,
## repeat prompts and accepted commands. Used for content coverage reporting.
func get_phrase_variants() -> PackedStringArray:
	var seen: Dictionary = {}
	var phrases: PackedStringArray = PackedStringArray()
	for task: Variant in _tasks:
		if typeof(task) != TYPE_DICTIONARY:
			continue
		var task_dict: Dictionary = task
		for key: String in ["prompt", "instruction", "repeatPrompt"]:
			var phrase: String = String(task_dict.get(key, "")).strip_edges()
			if not phrase.is_empty() and not seen.has(phrase):
				seen[phrase] = true
				phrases.append(phrase)
		for command: Variant in _string_array(task_dict.get("acceptedCommands", [])):
			var text: String = String(command).strip_edges()
			if not text.is_empty() and not seen.has(text):
				seen[text] = true
				phrases.append(text)
	return phrases


func get_phrase_variant_count() -> int:
	return get_phrase_variants().size()


# ---------------------------------------------------------------------------
# Legacy compatibility
# ---------------------------------------------------------------------------

## The original shipped feeding activity, untouched. Kept separate from the task
## index so `feedMilk` is never double-registered.
func get_legacy_feeding_activity() -> Dictionary:
	var path: String = String(_index.get("legacyActivityFile", LEGACY_ACTIVITY_PATH))
	return _read_json_dict(path, "legacy feeding activity")


# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

func get_load_warnings() -> Array:
	return _warnings.duplicate()


func has_load_warnings() -> bool:
	return not _warnings.is_empty()


func is_empty() -> bool:
	return _tasks.is_empty() and _objects.is_empty()


func get_summary() -> Dictionary:
	return {
		"categories": _categories.size(),
		"objects": _objects.size(),
		"tasks": _tasks.size(),
		"missions": _missions.size(),
		"stickers": _stickers.size(),
		"words": _words.size(),
		"phraseVariants": get_phrase_variant_count(),
		"warnings": _warnings.size(),
	}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _warn(message: String) -> void:
	_warnings.append(message)


func _read_json_dict(path: String, label: String) -> Dictionary:
	if path.is_empty():
		_warn("no path configured for %s" % label)
		return {}
	if not FileAccess.file_exists(path):
		_warn("missing file for %s: %s" % [label, path])
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_warn("could not open file for %s: %s" % [label, path])
		return {}

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_warn("invalid JSON object for %s: %s" % [label, path])
		return {}

	return parsed


func _array_field(data: Dictionary, key: String, path: String) -> Array:
	if data.is_empty():
		return []
	var raw: Variant = data.get(key, null)
	if typeof(raw) != TYPE_ARRAY:
		_warn("%s: '%s' is missing or is not an array" % [path, key])
		return []
	return raw


static func _copy_array(source: Variant) -> Array:
	if typeof(source) != TYPE_ARRAY:
		return []
	var result: Array = []
	for entry: Variant in (source as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			result.append((entry as Dictionary).duplicate(true))
		else:
			result.append(entry)
	return result


static func _string_array(source: Variant) -> Array:
	if typeof(source) != TYPE_ARRAY:
		return []
	return source


static func _as_int(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value).to_int()
		_:
			return 0
