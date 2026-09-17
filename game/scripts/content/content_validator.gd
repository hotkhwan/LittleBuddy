class_name ContentValidator
extends RefCounted

## Static validation for the bundled content set.
##
## Every function returns an `Array` of human-readable problem strings; an empty
## array means "no problems found". Nothing here throws, asserts or pushes an
## error, so it is safe to run from a test case, a debug screen, or a build step.
##
## `library` parameters are deliberately untyped so this script never depends on
## the global class-name cache being warm.

## Required top-level keys on every task.
const REQUIRED_TASK_KEYS: Array[String] = [
	"taskId",
	"category",
	"mode",
	"objectId",
	"targetWords",
	"prompt",
	"instruction",
	"repeatPrompt",
	"acceptedCommands",
	"interaction",
	"reward",
	"difficulty",
	"cooldown",
]

const REQUIRED_OBJECT_KEYS: Array[String] = ["objectId", "word", "category"]
const REQUIRED_MISSION_KEYS: Array[String] = ["missionId", "title", "taskIds"]
const REQUIRED_STICKER_KEYS: Array[String] = ["stickerId", "word", "unlockAtStars"]
const REQUIRED_WORD_KEYS: Array[String] = ["wordId", "word", "category"]

const EXPECTED_CATEGORIES: Array[String] = ["feeding", "dressing", "bath", "play", "bedtime"]
const EXPECTED_MODES: Array[String] = ["findIt", "sayIt", "followInstruction"]

const VALID_INTERACTIONS: Array[String] = [
	"dragToMouth",
	"dragToHug",
	"dragToBath",
	"dragToDress",
	"dragToToyBox",
	"tap",
]

## Acceptance targets from the overnight build plan. Tests assert against these
## so a content regression fails loudly instead of silently shrinking the game.
const MIN_CATEGORIES: int = 5
const MIN_TASKS: int = 25
const MIN_WORDS: int = 30
const MIN_PHRASE_VARIANTS: int = 80
const MIN_MISSIONS: int = 5
const MIN_STICKERS: int = 12
const MAX_STICKERS: int = 20
const MIN_MISSION_TASKS: int = 5
const MAX_MISSION_TASKS: int = 8

## The live iPhone build reads this file through `ActivityLoader`. Its keys and
## its six accepted phrases are a frozen contract: additive changes only.
const LEGACY_ACTIVITY_PATH: String = "res://content/feeding/feed_milk.json"

const LEGACY_REQUIRED_KEYS: Array[String] = [
	"activityId",
	"category",
	"prompt",
	"instruction",
	"repeatPrompt",
	"targetWords",
	"acceptedCommands",
	"reward",
	"successPhrases",
	"retryPhrase",
	"thankYouPhrase",
	"hungerRelief",
	"thaiHint",
]

const LEGACY_ACCEPTED_COMMANDS: Array[String] = [
	"milk",
	"give milk",
	"give baby milk",
	"give the baby milk",
	"give the baby some milk",
	"baby wants milk",
]

## ---------------------------------------------------------------------------
## Semantic activity targets (contract §2)
## ---------------------------------------------------------------------------
##
## Content addresses the world as `"<roomId>.<targetId>"` -- `"kitchen.fridge"`,
## `"bedroom.doorToBathroom"` -- and never as a node name, a path or a
## coordinate. A reference to a target that does not exist is silent: the level
## loads, the child taps, and nothing happens. So it is checked here, against the
## ids the REAL world reports, and a miss is a loud problem.
##
## The id list is injected as plain Strings. This file must never import
## `scripts/house/**` (or navigation, character or camera) and must never hold a
## 3D type -- `test_architecture_guard.gd` fails the build if it does -- so the
## caller resolves `HouseWorld.get_semantic_target_ids()` and hands over the
## Array. The validator stays pure data, exactly like the rest of the domain
## layer.
##
## Which JSON keys carry a target reference is DECLARED by the content index
## (`semanticTargetKeys`) rather than hard-coded, so content can add a third key
## without a code change and still be validated.

const CONTENT_INDEX_PATH: String = "res://content/index.json"
const SEMANTIC_TARGET_KEYS_FIELD: String = "semanticTargetKeys"

## Used only when the index declares none -- a missing declaration is itself
## reported, so this is a safety net rather than a default worth relying on.
const DEFAULT_SEMANTIC_TARGET_KEYS: Array[String] = ["targetId", "requiresWalkTo"]

## Anti-vacuity floor. A scanner that finds nothing to check reports "no
## problems" forever; if the declared keys stop matching the authored data, that
## silence is the failure, not the result.
const MIN_SEMANTIC_TARGET_REFERENCES: int = 1

## How many known ids to name in a failure message before trailing off. Enough
## to spot a typo, short enough to read.
const MAX_REPORTED_KNOWN_IDS: int = 12


## Runs every structural check. `library` must be a loaded `ContentLibrary`.
static func validate(library: Variant) -> Array:
	var problems: Array = []
	if library == null:
		problems.append("validator: no library supplied")
		return problems

	for warning: Variant in library.get_load_warnings():
		problems.append("load: %s" % String(warning))

	problems.append_array(validate_categories(library))
	problems.append_array(validate_objects(library))
	problems.append_array(validate_tasks(library))
	problems.append_array(validate_missions(library))
	problems.append_array(validate_stickers(library))
	problems.append_array(validate_vocabulary(library))
	return problems


## Structural checks plus the "is this actually a 2-3 hour game" size targets.
##
## `world_target_ids` is the list of semantic target ids the world actually
## contains, as plain Strings. `null` means "the caller has no world to check
## against" and skips that section -- a build step or a content-only test can
## still run everything else. Anything else, including an empty Array, is taken
## as a request to validate and is checked (an empty Array is itself reported,
## because silently passing on no data is how this class of guard rots).
static func validate_all(library: Variant, world_target_ids: Variant = null) -> Array:
	var problems: Array = validate(library)
	problems.append_array(validate_counts(library))
	problems.append_array(validate_legacy_activity())
	problems.append_array(validate_semantic_targets(library, world_target_ids))
	return problems


# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------

static func validate_categories(library: Variant) -> Array:
	var problems: Array = []
	var ids: Array = []
	for category_id: String in library.get_category_ids():
		if category_id.is_empty():
			problems.append("categories: found a category with an empty categoryId")
			continue
		if ids.has(category_id):
			problems.append("categories: duplicate categoryId '%s'" % category_id)
		ids.append(category_id)

	for expected: String in EXPECTED_CATEGORIES:
		if not ids.has(expected):
			problems.append("categories: missing required category '%s'" % expected)

	for mode: String in EXPECTED_MODES:
		if library.get_tasks_with_mode(mode).is_empty():
			problems.append("modes: no task uses mini-game mode '%s'" % mode)

	return problems


static func validate_objects(library: Variant) -> Array:
	var problems: Array = []
	var seen: Dictionary = {}

	for object_data: Variant in library.get_objects():
		if typeof(object_data) != TYPE_DICTIONARY:
			problems.append("objects: entry is not an object")
			continue
		var object_dict: Dictionary = object_data
		var object_id: String = String(object_dict.get("objectId", ""))
		var label: String = "object '%s'" % object_id

		problems.append_array(_check_camel_case_keys(object_dict, label))

		for key: String in REQUIRED_OBJECT_KEYS:
			if not object_dict.has(key):
				problems.append("%s: missing required key '%s'" % [label, key])

		if object_id.is_empty():
			problems.append("objects: entry has an empty objectId")
			continue
		if not _is_camel_case(object_id):
			problems.append("%s: objectId is not camelCase" % label)
		if seen.has(object_id):
			problems.append("objects: duplicate objectId '%s'" % object_id)
		seen[object_id] = true

		if String(object_dict.get("word", "")).strip_edges().is_empty():
			problems.append("%s: 'word' is empty" % label)

		var interaction: String = String(object_dict.get("defaultInteraction", ""))
		if not interaction.is_empty() and not VALID_INTERACTIONS.has(interaction):
			problems.append("%s: unknown defaultInteraction '%s'" % [label, interaction])

	return problems


static func validate_tasks(library: Variant) -> Array:
	var problems: Array = []
	var seen: Dictionary = {}
	var category_ids: Array = Array(library.get_category_ids())

	for task_data: Variant in library.get_tasks():
		if typeof(task_data) != TYPE_DICTIONARY:
			problems.append("tasks: entry is not an object")
			continue
		var task: Dictionary = task_data
		var task_id: String = String(task.get("taskId", ""))
		var label: String = "task '%s'" % task_id

		problems.append_array(_check_camel_case_keys(task, label))

		for key: String in REQUIRED_TASK_KEYS:
			if not task.has(key):
				problems.append("%s: missing required key '%s'" % [label, key])

		if task_id.is_empty():
			problems.append("tasks: entry has an empty taskId")
			continue
		if not _is_camel_case(task_id):
			problems.append("%s: taskId is not camelCase" % label)
		if seen.has(task_id):
			problems.append("tasks: duplicate taskId '%s'" % task_id)
		seen[task_id] = true

		var category: String = String(task.get("category", ""))
		if not category_ids.has(category):
			problems.append("%s: unknown category '%s'" % [label, category])

		var mode: String = String(task.get("mode", ""))
		if not EXPECTED_MODES.has(mode):
			problems.append("%s: unknown mode '%s'" % [label, mode])

		var interaction: String = String(task.get("interaction", ""))
		if not VALID_INTERACTIONS.has(interaction):
			problems.append("%s: unknown interaction '%s'" % [label, interaction])

		var object_id: String = String(task.get("objectId", ""))
		if object_id.is_empty():
			problems.append("%s: 'objectId' is empty" % label)
		elif not library.has_object(object_id):
			problems.append("%s: references unknown objectId '%s'" % [label, object_id])

		for key: String in ["prompt", "instruction", "repeatPrompt"]:
			if String(task.get(key, "")).strip_edges().is_empty():
				problems.append("%s: '%s' is empty" % [label, key])

		problems.append_array(_check_string_list(task.get("targetWords", null), "%s: targetWords" % label))
		problems.append_array(
			_check_string_list(task.get("acceptedCommands", null), "%s: acceptedCommands" % label)
		)

		var target_words: Variant = task.get("targetWords", null)
		var accepted: Variant = task.get("acceptedCommands", null)
		if typeof(accepted) == TYPE_ARRAY and typeof(target_words) == TYPE_ARRAY:
			problems.append_array(_check_target_word_coverage(accepted, target_words, label))

		problems.append_array(_check_reward(task.get("reward", null), label))
		problems.append_array(_check_int_range(task.get("difficulty", null), "%s: difficulty" % label, 1, 5))
		problems.append_array(_check_int_range(task.get("cooldown", null), "%s: cooldown" % label, 0, 60))

		if task.has("thaiHint") and String(task.get("thaiHint", "")).strip_edges().is_empty():
			problems.append("%s: 'thaiHint' is present but empty" % label)

	return problems


static func validate_missions(library: Variant) -> Array:
	var problems: Array = []
	var seen: Dictionary = {}

	for mission_data: Variant in library.get_missions():
		if typeof(mission_data) != TYPE_DICTIONARY:
			problems.append("missions: entry is not an object")
			continue
		var mission: Dictionary = mission_data
		var mission_id: String = String(mission.get("missionId", ""))
		var label: String = "mission '%s'" % mission_id

		problems.append_array(_check_camel_case_keys(mission, label))

		for key: String in REQUIRED_MISSION_KEYS:
			if not mission.has(key):
				problems.append("%s: missing required key '%s'" % [label, key])

		if mission_id.is_empty():
			problems.append("missions: entry has an empty missionId")
			continue
		if not _is_camel_case(mission_id):
			problems.append("%s: missionId is not camelCase" % label)
		if seen.has(mission_id):
			problems.append("missions: duplicate missionId '%s'" % mission_id)
		seen[mission_id] = true

		if String(mission.get("title", "")).strip_edges().is_empty():
			problems.append("%s: 'title' is empty" % label)

		var task_ids: Variant = mission.get("taskIds", null)
		if typeof(task_ids) != TYPE_ARRAY:
			problems.append("%s: 'taskIds' must be an array" % label)
			continue

		var id_list: Array = task_ids
		if id_list.size() < MIN_MISSION_TASKS or id_list.size() > MAX_MISSION_TASKS:
			problems.append(
				"%s: has %d tasks, expected %d-%d"
				% [label, id_list.size(), MIN_MISSION_TASKS, MAX_MISSION_TASKS]
			)

		for entry: Variant in id_list:
			var task_id: String = String(entry)
			if task_id.is_empty():
				problems.append("%s: contains an empty taskId" % label)
			elif not library.has_task(task_id):
				problems.append("%s: references unknown taskId '%s'" % [label, task_id])

		problems.append_array(
			_check_int_range(mission.get("unlockAtStars", 0), "%s: unlockAtStars" % label, 0, 100000)
		)

	return problems


static func validate_stickers(library: Variant) -> Array:
	var problems: Array = []
	var seen: Dictionary = {}

	for sticker_data: Variant in library.get_stickers():
		if typeof(sticker_data) != TYPE_DICTIONARY:
			problems.append("stickers: entry is not an object")
			continue
		var sticker: Dictionary = sticker_data
		var sticker_id: String = String(sticker.get("stickerId", ""))
		var label: String = "sticker '%s'" % sticker_id

		problems.append_array(_check_camel_case_keys(sticker, label))

		for key: String in REQUIRED_STICKER_KEYS:
			if not sticker.has(key):
				problems.append("%s: missing required key '%s'" % [label, key])

		if sticker_id.is_empty():
			problems.append("stickers: entry has an empty stickerId")
			continue
		if not _is_camel_case(sticker_id):
			problems.append("%s: stickerId is not camelCase" % label)
		if seen.has(sticker_id):
			problems.append("stickers: duplicate stickerId '%s'" % sticker_id)
		seen[sticker_id] = true

		if String(sticker.get("word", "")).strip_edges().is_empty():
			problems.append("%s: 'word' is empty" % label)

		problems.append_array(
			_check_int_range(sticker.get("unlockAtStars", null), "%s: unlockAtStars" % label, 0, 100000)
		)

	return problems


static func validate_vocabulary(library: Variant) -> Array:
	var problems: Array = []
	var seen: Dictionary = {}
	var category_ids: Array = Array(library.get_category_ids())

	for word_data: Variant in library.get_words():
		if typeof(word_data) != TYPE_DICTIONARY:
			problems.append("vocabulary: entry is not an object")
			continue
		var word: Dictionary = word_data
		var word_id: String = String(word.get("wordId", ""))
		var label: String = "word '%s'" % word_id

		problems.append_array(_check_camel_case_keys(word, label))

		for key: String in REQUIRED_WORD_KEYS:
			if not word.has(key):
				problems.append("%s: missing required key '%s'" % [label, key])

		if word_id.is_empty():
			problems.append("vocabulary: entry has an empty wordId")
			continue
		if not _is_camel_case(word_id):
			problems.append("%s: wordId is not camelCase" % label)
		if seen.has(word_id):
			problems.append("vocabulary: duplicate wordId '%s'" % word_id)
		seen[word_id] = true

		if String(word.get("word", "")).strip_edges().is_empty():
			problems.append("%s: 'word' is empty" % label)

		var category: String = String(word.get("category", ""))
		if not category_ids.has(category):
			problems.append("%s: unknown category '%s'" % [label, category])

		var object_id: String = String(word.get("objectId", ""))
		if not object_id.is_empty() and not library.has_object(object_id):
			problems.append("%s: references unknown objectId '%s'" % [label, object_id])

	return problems


## Asserts the content set is big enough to carry 2-3 hours of replayable play.
static func validate_counts(library: Variant) -> Array:
	var problems: Array = []
	problems.append_array(_check_min(library.get_category_ids().size(), MIN_CATEGORIES, "categories"))
	problems.append_array(_check_min(library.get_task_count(), MIN_TASKS, "tasks"))
	problems.append_array(_check_min(library.get_word_count(), MIN_WORDS, "vocabulary words"))
	problems.append_array(
		_check_min(library.get_phrase_variant_count(), MIN_PHRASE_VARIANTS, "phrase variants")
	)
	problems.append_array(_check_min(library.get_mission_count(), MIN_MISSIONS, "missions"))

	var stickers: int = library.get_sticker_count()
	if stickers < MIN_STICKERS or stickers > MAX_STICKERS:
		problems.append(
			"counts: %d stickers, expected %d-%d" % [stickers, MIN_STICKERS, MAX_STICKERS]
		)

	return problems


## Verifies the frozen `feed_milk.json` contract consumed by the live build.
static func validate_legacy_activity(path: String = LEGACY_ACTIVITY_PATH) -> Array:
	var problems: Array = []

	if not FileAccess.file_exists(path):
		problems.append("legacy: missing %s" % path)
		return problems

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		problems.append("legacy: could not open %s" % path)
		return problems

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		problems.append("legacy: %s is not a JSON object" % path)
		return problems

	var data: Dictionary = parsed

	for key: String in LEGACY_REQUIRED_KEYS:
		if not data.has(key):
			problems.append("legacy: %s lost required key '%s'" % [path, key])

	problems.append_array(_check_camel_case_keys(data, "legacy feed_milk.json"))

	if String(data.get("activityId", "")) != "feedMilk":
		problems.append("legacy: activityId must stay 'feedMilk'")

	var accepted: Variant = data.get("acceptedCommands", null)
	if typeof(accepted) != TYPE_ARRAY:
		problems.append("legacy: acceptedCommands must be an array")
	else:
		for phrase: String in LEGACY_ACCEPTED_COMMANDS:
			if not (accepted as Array).has(phrase):
				problems.append("legacy: acceptedCommands lost required phrase '%s'" % phrase)

	var reward: Variant = data.get("reward", null)
	if typeof(reward) != TYPE_DICTIONARY or _as_int((reward as Dictionary).get("stars", -1)) != 1:
		problems.append("legacy: reward.stars must equal 1")

	return problems


# ---------------------------------------------------------------------------
# Semantic activity targets
# ---------------------------------------------------------------------------

## The JSON keys that carry a semantic target reference, as declared by the
## content index. Falls back to the two the contract names when the index cannot
## be read; `validate_semantic_targets()` reports that separately rather than
## letting it pass unnoticed.
static func semantic_target_keys(index_path: String = CONTENT_INDEX_PATH) -> Array:
	var index: Dictionary = _read_json_object(index_path)
	var declared: Variant = index.get(SEMANTIC_TARGET_KEYS_FIELD, null)
	var keys: Array = []
	if typeof(declared) == TYPE_ARRAY:
		for entry: Variant in (declared as Array):
			var key: String = str(entry).strip_edges()
			if not key.is_empty() and not keys.has(key):
				keys.append(key)
	return keys


## Every semantic target reference in the content set, as
## `{"id", "key", "where"}` dictionaries.
##
## Deliberately generic: it walks the loaded records depth-first and reports any
## value stored under one of the declared keys, wherever it is nested. Content
## can therefore move `targetId` from the top of a task into a step list without
## the validator going quietly blind.
static func collect_semantic_target_references(
	library: Variant, keys: Variant = null, index_path: String = CONTENT_INDEX_PATH
) -> Array:
	var found_keys: Array = keys if typeof(keys) == TYPE_ARRAY else semantic_target_keys(index_path)
	if found_keys.is_empty():
		found_keys = []
		found_keys.assign(DEFAULT_SEMANTIC_TARGET_KEYS)

	var references: Array = []
	if library == null:
		return references

	for section: Array in [
		["tasks", "taskId", library.get_tasks()],
		["missions", "missionId", library.get_missions()],
		["objects", "objectId", library.get_objects()],
		["stickers", "stickerId", library.get_stickers()],
		["vocabulary", "wordId", library.get_words()],
	]:
		var section_name: String = str(section[0])
		var id_key: String = str(section[1])
		for record: Variant in (section[2] as Array):
			if typeof(record) != TYPE_DICTIONARY:
				continue
			var record_id: String = str((record as Dictionary).get(id_key, ""))
			var label: String = "%s '%s'" % [section_name.trim_suffix("s"), record_id]
			_collect_target_references_into(record, found_keys, label, references)

	return references


static func _collect_target_references_into(
	value: Variant, keys: Array, label: String, out: Array
) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for key: Variant in (value as Dictionary).keys():
				var key_text: String = str(key)
				var child: Variant = (value as Dictionary)[key]
				if keys.has(key_text) and _is_text(child):
					out.append({"id": str(child), "key": key_text, "where": label})
					continue
				_collect_target_references_into(child, keys, label, out)
		TYPE_ARRAY:
			for entry: Variant in (value as Array):
				_collect_target_references_into(entry, keys, label, out)
		_:
			pass


## Checks every semantic target reference in the content set against the ids the
## world really has.
##
## `world_target_ids` is an Array of Strings -- typically
## `HouseWorld.get_semantic_target_ids()`. `null` skips the section entirely, so
## a content-only caller is unaffected; an empty Array is a problem, not a pass.
static func validate_semantic_targets(
	library: Variant, world_target_ids: Variant = null, index_path: String = CONTENT_INDEX_PATH
) -> Array:
	var problems: Array = []
	if world_target_ids == null:
		return problems

	if typeof(world_target_ids) != TYPE_ARRAY:
		problems.append(
			"semanticTargets: the world target id list must be an array of strings, got %s"
			% type_string(typeof(world_target_ids))
		)
		return problems

	var known: Dictionary = {}
	for entry: Variant in (world_target_ids as Array):
		var known_id: String = str(entry).strip_edges()
		if not known_id.is_empty():
			known[known_id] = true
	if known.is_empty():
		problems.append(
			"semanticTargets: no world target ids were supplied, so no reference could be "
			+ "checked. Pass the ids the world reports; an empty list is not a pass."
		)
		return problems

	var keys: Array = semantic_target_keys(index_path)
	if keys.is_empty():
		problems.append(
			"semanticTargets: %s declares no '%s', so the scan cannot know which keys carry a "
			% [index_path, SEMANTIC_TARGET_KEYS_FIELD]
			+ "target reference"
		)
		return problems

	if library == null:
		problems.append("semanticTargets: no library supplied")
		return problems

	var references: Array = collect_semantic_target_references(library, keys, index_path)
	var known_sample: String = _describe_known_ids(known)

	for reference: Variant in references:
		var entry_map: Dictionary = reference
		var referenced: String = str(entry_map["id"]).strip_edges()
		var key_text: String = str(entry_map["key"])
		var where: String = str(entry_map["where"])
		if referenced.is_empty():
			problems.append("%s: '%s' is empty; a target reference must be a semantic id"
					% [where, key_text])
			continue
		if known.has(referenced):
			continue
		problems.append(
			("%s: '%s' references target '%s', which does not exist in the world. Content "
			+ "addresses targets as '<roomId>.<targetId>' and every one must be real -- a "
			+ "reference that misses is silent at runtime: the child taps and nothing happens. "
			+ "Known ids: %s") % [where, key_text, referenced, known_sample]
		)

	if references.size() < MIN_SEMANTIC_TARGET_REFERENCES:
		problems.append(
			("semanticTargets: the scan found %d reference(s) under the declared keys %s, fewer "
			+ "than the %d required. Either the content stopped addressing the world by semantic "
			+ "id, or '%s' no longer names the keys it is actually authored under -- and a "
			+ "validator that finds nothing to check reports no problems forever.")
			% [references.size(), str(keys), MIN_SEMANTIC_TARGET_REFERENCES,
					SEMANTIC_TARGET_KEYS_FIELD]
		)

	return problems


static func _describe_known_ids(known: Dictionary) -> String:
	var ids: Array = known.keys()
	ids.sort()
	if ids.size() <= MAX_REPORTED_KNOWN_IDS:
		return ", ".join(PackedStringArray(ids))
	var head: Array = ids.slice(0, MAX_REPORTED_KNOWN_IDS)
	return "%s, ... (%d in total)" % [", ".join(PackedStringArray(head)), ids.size()]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME


static func _read_json_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## camelCase: starts with a lowercase letter, then letters/digits only.
## Rejects snake_case, kebab-case, PascalCase and keys containing spaces.
static func is_camel_case(text: String) -> bool:
	return _is_camel_case(text)


static func _is_camel_case(text: String) -> bool:
	if text.is_empty():
		return false
	var first: String = text.substr(0, 1)
	if first < "a" or first > "z":
		return false
	for i: int in range(text.length()):
		var character: String = text.substr(i, 1)
		var is_lower: bool = character >= "a" and character <= "z"
		var is_upper: bool = character >= "A" and character <= "Z"
		var is_digit: bool = character >= "0" and character <= "9"
		if not (is_lower or is_upper or is_digit):
			return false
	return true


static func _check_camel_case_keys(data: Dictionary, label: String) -> Array:
	var problems: Array = []
	for key: Variant in data.keys():
		var key_text: String = String(key)
		if not _is_camel_case(key_text):
			problems.append("%s: key '%s' is not camelCase" % [label, key_text])
	return problems


static func _check_string_list(value: Variant, label: String) -> Array:
	var problems: Array = []
	if typeof(value) != TYPE_ARRAY:
		problems.append("%s must be an array" % label)
		return problems
	var list: Array = value
	if list.is_empty():
		problems.append("%s must not be empty" % label)
		return problems
	var seen: Dictionary = {}
	for entry: Variant in list:
		if typeof(entry) != TYPE_STRING and typeof(entry) != TYPE_STRING_NAME:
			problems.append("%s contains a non-string entry" % label)
			continue
		var text: String = String(entry)
		if text.strip_edges().is_empty():
			problems.append("%s contains an empty string" % label)
			continue
		if text != text.to_lower():
			problems.append("%s entry '%s' must be lowercase for tolerant matching" % [label, text])
		if seen.has(text):
			problems.append("%s contains duplicate entry '%s'" % [label, text])
		seen[text] = true
	return problems


## At least one accepted phrase must contain a target word, otherwise speech can
## never succeed for that task.
static func _check_target_word_coverage(accepted: Array, target_words: Array, label: String) -> Array:
	var problems: Array = []
	for word_entry: Variant in target_words:
		var word: String = String(word_entry).to_lower().strip_edges()
		if word.is_empty():
			continue
		var covered: bool = false
		for phrase_entry: Variant in accepted:
			if String(phrase_entry).to_lower().find(word) != -1:
				covered = true
				break
		if not covered:
			problems.append("%s: no acceptedCommands entry contains target word '%s'" % [label, word])
	return problems


static func _check_reward(reward: Variant, label: String) -> Array:
	var problems: Array = []
	if typeof(reward) != TYPE_DICTIONARY:
		problems.append("%s: 'reward' must be an object" % label)
		return problems
	var reward_dict: Dictionary = reward
	if not reward_dict.has("stars"):
		problems.append("%s: 'reward' is missing 'stars'" % label)
		return problems
	var stars: Variant = reward_dict.get("stars")
	if not _is_whole_number(stars):
		problems.append(
			"%s: 'reward.stars' must be a whole number, got %s (%s)"
			% [label, str(stars), type_string(typeof(stars))]
		)
		return problems
	if _as_int(stars) < 0:
		problems.append("%s: 'reward.stars' must not be negative" % label)
	return problems


static func _check_int_range(value: Variant, label: String, minimum: int, maximum: int) -> Array:
	var problems: Array = []
	if not _is_whole_number(value):
		problems.append(
			"%s must be a whole number, got %s (%s)"
			% [label, str(value), type_string(typeof(value))]
		)
		return problems
	var number: int = _as_int(value)
	if number < minimum or number > maximum:
		problems.append("%s must be between %d and %d, got %d" % [label, minimum, maximum, number])
	return problems


## JSON has no integer type, so Godot parses `1` as `1.0`. Accept any numeric
## value with no fractional part; reject strings, bools, nulls and `1.5`.
static func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_equal_approx(float(value), floor(float(value)))
	return false


static func _check_min(actual: int, minimum: int, label: String) -> Array:
	if actual < minimum:
		return ["counts: %d %s, expected at least %d" % [actual, label, minimum]]
	return []


static func _as_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT:
		return int(round(float(value)))
	return -1
