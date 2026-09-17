class_name ProfileStore
extends RefCounted

## Pure, testable persistence logic for the child's local profile.
## Owns reading/writing user://profile.json and defending against every
## corruption/failure mode so gameplay never crashes or silently loses stars.
##
## Schema v2 adds level/chapter progression on top of the v1 schema. There are
## two separate, never-summed star currencies:
##   - "stars"        lifetime TASK star total (+1 per completed task). Still
##                     the only thing that feeds sticker unlockAtStars
##                     thresholds. Never touched by level seeding/migration.
##   - "starsByLevel"  per-level 0..3 RATING (best-ever, max-wins). Drives
##                     level/chapter unlocking. Never folded into "stars".

const DEFAULT_PATH := "user://profile.json"
const CURRENT_VERSION := 2

## Where Agent LEVEL's level->task/chapter mapping is expected to live at
## runtime. This file does not exist yet as of Phase 1 SAVE landing; reading
## it is fully defensive (see `_load_level_definitions`) so migration never
## depends on it existing.
const DEFAULT_LEVELS_PATH := "res://content/levels/levels.json"
const DEFAULT_MISSIONS_PATH := "res://content/missions/missions.json"

## Chapter 2 must always be unlocked after a v1->v2 migration so a returning
## profile is never stranded (see docs/PHASE1_CONTRACT.md). If the level
## definitions file is absent we still need *some* concrete first-level id to
## unlock; "milkTime" is the id given for that slot in the contract's own
## schema example.
const CH1_CHAPTER_ID := "ch1"
const CH2_CHAPTER_ID := "ch2"
const CH2_FALLBACK_FIRST_LEVEL_ID := "milkTime"

var path: String
var levels_path: String
var missions_path: String

func _init(p_path: String = DEFAULT_PATH, p_levels_path: String = DEFAULT_LEVELS_PATH, p_missions_path: String = DEFAULT_MISSIONS_PATH) -> void:
	path = p_path
	levels_path = p_levels_path
	missions_path = p_missions_path


## Canonical default schema. Always returns a fresh Dictionary (no shared
## references) so callers can freely mutate the result.
func default_profile() -> Dictionary:
	return {
		"profileVersion": CURRENT_VERSION,
		"stars": 0,
		"completedActivities": [],
		"currentChapter": CH1_CHAPTER_ID,
		"currentLevel": "",
		"starsByLevel": {},
		"unlockedChapters": [CH1_CHAPTER_ID],
		"unlockedLevels": [],
		"unlockedRooms": [],
		"settings": default_settings(),
	}


func default_settings() -> Dictionary:
	return {
		"speechLocale": "en-US",
		"speechEnabled": true,
		"thaiHints": true,
		"soundEnabled": true,
		"ttsSpeed": "normal",
	}


## Loads the profile from disk, handling every failure mode safely:
## missing file, zero-byte file, invalid JSON, JSON parsing to a
## non-Dictionary, missing keys, and wrong-typed values. Never throws.
func load_profile() -> Dictionary:
	if not FileAccess.file_exists(path):
		return default_profile()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return default_profile()

	var text := file.get_as_text()
	file.close()

	if text.strip_edges() == "":
		return default_profile()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return default_profile()

	return _sanitize(parsed)


## Sanitizes/migrates an arbitrary Dictionary into the canonical schema.
## Partial or malformed data is merged over defaults rather than discarded,
## so a corrupt "settings" block never wipes a valid star count and vice versa.
func _sanitize(raw: Dictionary) -> Dictionary:
	var result := default_profile()

	# Forward-compatible migration hook keyed on profileVersion. Versions <= 1
	# (including missing/malformed version values, treated as legacy) run the
	# additive v1->v2 migration once. Version 2 is passed through untouched so
	# migration is idempotent. An unknown/newer version is never migrated --
	# it simply falls through to the same field-by-field validation below,
	# exactly like corrupt data, so a save from a future build never crashes
	# an older one.
	var version_value = raw.get("profileVersion", CURRENT_VERSION)
	var version := CURRENT_VERSION
	if typeof(version_value) == TYPE_INT or typeof(version_value) == TYPE_FLOAT:
		version = int(version_value)
	raw = _migrate(raw, version)

	# stars: must be a non-negative number. This is the lifetime TASK star
	# total; it is never derived from or combined with starsByLevel.
	if raw.has("stars"):
		var stars = raw["stars"]
		if (typeof(stars) == TYPE_INT or typeof(stars) == TYPE_FLOAT) and stars >= 0:
			result["stars"] = int(stars)

	# completedActivities: must be an array of strings, de-duplicated.
	result["completedActivities"] = _sanitize_string_array(raw.get("completedActivities", null))

	# currentChapter / currentLevel: free-form ids, must be strings.
	if raw.has("currentChapter") and typeof(raw["currentChapter"]) == TYPE_STRING:
		result["currentChapter"] = raw["currentChapter"]
	if raw.has("currentLevel") and typeof(raw["currentLevel"]) == TYPE_STRING:
		result["currentLevel"] = raw["currentLevel"]

	# starsByLevel: Dictionary<String levelId, int 0..3>. Wrong-typed keys or
	# values are dropped individually rather than discarding the whole map.
	var stars_by_level_result: Dictionary = {}
	if raw.has("starsByLevel") and typeof(raw["starsByLevel"]) == TYPE_DICTIONARY:
		var raw_stars_by_level: Dictionary = raw["starsByLevel"]
		for level_id in raw_stars_by_level.keys():
			if typeof(level_id) != TYPE_STRING:
				continue
			var value = raw_stars_by_level[level_id]
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				continue
			stars_by_level_result[level_id] = clampi(int(value), 0, 3)
	result["starsByLevel"] = stars_by_level_result

	# unlockedChapters / unlockedLevels / unlockedRooms: arrays of unique
	# strings, same shape/validation as completedActivities.
	result["unlockedChapters"] = _sanitize_string_array(raw.get("unlockedChapters", null))
	result["unlockedLevels"] = _sanitize_string_array(raw.get("unlockedLevels", null))
	result["unlockedRooms"] = _sanitize_string_array(raw.get("unlockedRooms", null))

	# settings: merge known keys with type validation; preserve unknown
	# forward-compatible keys only if they are JSON-safe types.
	var settings_result: Dictionary = default_settings()
	if raw.has("settings") and typeof(raw["settings"]) == TYPE_DICTIONARY:
		var raw_settings: Dictionary = raw["settings"]
		for key in raw_settings.keys():
			var value = raw_settings[key]
			match key:
				"speechLocale":
					if typeof(value) == TYPE_STRING and value != "":
						settings_result[key] = value
				"speechEnabled", "thaiHints":
					if typeof(value) == TYPE_BOOL:
						settings_result[key] = value
				_:
					var safe_types := [TYPE_STRING, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_ARRAY, TYPE_DICTIONARY]
					if safe_types.has(typeof(value)):
						settings_result[key] = value
	result["settings"] = settings_result

	result["profileVersion"] = CURRENT_VERSION

	return result


## De-duplicating string-array sanitizer shared by every array-of-ids field.
func _sanitize_string_array(raw_value: Variant) -> Array:
	var cleaned: Array = []
	if typeof(raw_value) != TYPE_ARRAY:
		return cleaned
	for item in raw_value:
		if typeof(item) == TYPE_STRING and not cleaned.has(item):
			cleaned.append(item)
	return cleaned


## Migration hook. Only legacy (<=1, including missing/malformed) versions are
## migrated; version 2 (and any unknown future version) pass through
## unchanged and rely on _sanitize()'s field-by-field validation, which keeps
## migration idempotent by construction (running it twice is a no-op).
func _migrate(raw: Dictionary, version: int) -> Dictionary:
	if version <= 1:
		return _migrate_v1_to_v2(raw)
	return raw


## Additive, lossless v1 -> v2 migration.
##
## - "stars", "completedActivities" and every "settings" key (including
##   "unlockedStickers") are carried over untouched; this function does not
##   even read them beyond a defensive scan of completedActivities used only
##   to decide what to seed.
## - starsByLevel is seeded from completedActivities: any level whose full
##   task list is already completed is granted exactly 1 star (core
##   completion only -- we cannot retroactively know whether the listening or
##   optional star was earned, and under-crediting is safe while
##   over-crediting is not).
## - Chapter 2 and its first level are always unlocked afterwards so no
##   profile can be stranded, even if the level definitions file described
##   below is missing.
func _migrate_v1_to_v2(raw: Dictionary) -> Dictionary:
	var migrated := raw.duplicate(true)

	var completed: Array = []
	if typeof(migrated.get("completedActivities", null)) == TYPE_ARRAY:
		for item in migrated["completedActivities"]:
			if typeof(item) == TYPE_STRING:
				completed.append(item)

	var seed := _seed_level_progress(completed)
	var stars_by_level: Dictionary = seed["starsByLevel"]
	var unlocked_levels: Array = seed["unlockedLevels"]
	var unlocked_chapters: Array = seed["unlockedChapters"]

	if not unlocked_chapters.has(CH1_CHAPTER_ID):
		unlocked_chapters.append(CH1_CHAPTER_ID)
	if not unlocked_chapters.has(CH2_CHAPTER_ID):
		unlocked_chapters.append(CH2_CHAPTER_ID)

	var first_ch2_level: String = seed["firstCh2LevelId"]
	if first_ch2_level == "":
		first_ch2_level = CH2_FALLBACK_FIRST_LEVEL_ID
	if not unlocked_levels.has(first_ch2_level):
		unlocked_levels.append(first_ch2_level)

	migrated["currentChapter"] = CH2_CHAPTER_ID
	migrated["currentLevel"] = first_ch2_level
	migrated["starsByLevel"] = stars_by_level
	migrated["unlockedChapters"] = unlocked_chapters
	migrated["unlockedLevels"] = unlocked_levels
	if typeof(migrated.get("unlockedRooms", null)) != TYPE_ARRAY:
		migrated["unlockedRooms"] = []

	return migrated


## Builds starsByLevel/unlockedLevels/unlockedChapters seeds from a list of
## already-completed activity ids, using whatever level definitions can be
## read at runtime (see `_load_level_definitions`). Levels are only granted a
## star when every one of their tasks is already completed; nothing here ever
## touches "stars" (the task-star total).
func _seed_level_progress(completed: Array) -> Dictionary:
	var stars_by_level: Dictionary = {}
	var unlocked_levels: Array = []
	var unlocked_chapters: Array = []
	var first_ch2_level_id := ""

	for level_def in _load_level_definitions():
		var level_id: String = String(level_def.get("levelId", ""))
		if level_id.is_empty():
			continue
		var chapter_id: String = String(level_def.get("chapterId", ""))
		if chapter_id == CH2_CHAPTER_ID and first_ch2_level_id.is_empty():
			first_ch2_level_id = level_id

		var task_ids: Array = level_def.get("taskIds", [])
		if task_ids.is_empty():
			continue

		var all_done := true
		for task_id in task_ids:
			if not completed.has(String(task_id)):
				all_done = false
				break
		if not all_done:
			continue

		stars_by_level[level_id] = 1
		unlocked_levels.append(level_id)
		if not chapter_id.is_empty() and not unlocked_chapters.has(chapter_id):
			unlocked_chapters.append(chapter_id)

	return {
		"starsByLevel": stars_by_level,
		"unlockedLevels": unlocked_levels,
		"unlockedChapters": unlocked_chapters,
		"firstCh2LevelId": first_ch2_level_id,
	}


## Reads the level->task/chapter mapping needed to seed starsByLevel. Fully
## defensive throughout: any missing file, unreadable file, invalid JSON, or
## unexpected shape simply yields an empty Array so migration seeds nothing
## rather than failing.
##
## Tries two sources, in order, since the level layer is authored
## concurrently by another agent and this must not depend on exactly which
## shape it lands in:
##   1. A dedicated `levels_path` file (defaults to
##      res://content/levels/levels.json): { "levels": [ { "levelId": "...",
##      "chapterId": "...", "taskIds": [...] } OR { "missionId": "..." } ] }.
##      Entries may specify "missionId" instead of "taskIds", in which case
##      the task list is resolved from missions_path.
##   2. Levels authored directly onto `missions_path` (defaults to the
##      already-shipped res://content/missions/missions.json), matching
##      `LevelDefinition.is_authored_level()`: a mission entry with a
##      non-empty "levelId" AND "chapterId" is a level, using that mission's
##      own "taskIds".
func _load_level_definitions() -> Array:
	var from_levels_file := _load_level_definitions_from_levels_file()
	if not from_levels_file.is_empty():
		return from_levels_file
	return _load_level_definitions_from_missions_file()


func _load_level_definitions_from_levels_file() -> Array:
	if levels_path.is_empty() or not FileAccess.file_exists(levels_path):
		return []

	var file := FileAccess.open(levels_path, FileAccess.READ)
	if file == null:
		return []
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []

	var levels_raw = parsed.get("levels", null)
	if typeof(levels_raw) != TYPE_ARRAY:
		return []

	var resolved: Array = []
	for entry in levels_raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var level_id: String = String(entry.get("levelId", ""))
		if level_id.is_empty():
			continue
		var chapter_id: String = String(entry.get("chapterId", ""))

		var task_ids = entry.get("taskIds", null)
		if typeof(task_ids) != TYPE_ARRAY or (task_ids as Array).is_empty():
			var mission_id: String = String(entry.get("missionId", ""))
			if not mission_id.is_empty():
				task_ids = _resolve_mission_task_ids(mission_id)
		if typeof(task_ids) != TYPE_ARRAY:
			task_ids = []

		resolved.append({
			"levelId": level_id,
			"chapterId": chapter_id,
			"taskIds": task_ids,
		})

	return resolved


## Reads levels authored directly onto mission records, e.g.:
##   { "missionId": "feedingTime", "chapterId": "ch2", "levelId": "milkTime",
##     "taskIds": [...] }
## A mission missing "levelId" or "chapterId" is a plain legacy mission, not
## a level, and is skipped -- mirrors `LevelDefinition.is_authored_level()`.
func _load_level_definitions_from_missions_file() -> Array:
	if missions_path.is_empty() or not FileAccess.file_exists(missions_path):
		return []

	var file := FileAccess.open(missions_path, FileAccess.READ)
	if file == null:
		return []
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []

	var missions_raw = parsed.get("missions", null)
	if typeof(missions_raw) != TYPE_ARRAY:
		return []

	var resolved: Array = []
	for entry in missions_raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var mission: Dictionary = entry
		var level_id: String = String(mission.get("levelId", "")).strip_edges()
		var chapter_id: String = String(mission.get("chapterId", "")).strip_edges()
		if level_id.is_empty() or chapter_id.is_empty():
			continue

		var task_ids = mission.get("taskIds", [])
		if typeof(task_ids) != TYPE_ARRAY:
			task_ids = []

		resolved.append({
			"levelId": level_id,
			"chapterId": chapter_id,
			"taskIds": task_ids,
		})

	return resolved


## Defensively resolves a mission's taskIds from missions_path. Missing file,
## unreadable file, invalid JSON, or an unknown mission id all yield an empty
## Array rather than raising.
func _resolve_mission_task_ids(mission_id: String) -> Array:
	if missions_path.is_empty() or not FileAccess.file_exists(missions_path):
		return []

	var file := FileAccess.open(missions_path, FileAccess.READ)
	if file == null:
		return []
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []

	var missions_raw = parsed.get("missions", null)
	if typeof(missions_raw) != TYPE_ARRAY:
		return []

	for mission_entry in missions_raw:
		if typeof(mission_entry) != TYPE_DICTIONARY:
			continue
		if String((mission_entry as Dictionary).get("missionId", "")) == mission_id:
			var task_ids = (mission_entry as Dictionary).get("taskIds", [])
			if typeof(task_ids) == TYPE_ARRAY:
				return task_ids
			return []

	return []


## Writes the profile to disk, sanitizing it first so a bad in-memory state
## can never be persisted. Writes via a temp file + rename to avoid
## corrupting the profile if the app is killed mid-write. Returns true on
## success.
func save_profile(profile: Dictionary) -> bool:
	var sanitized := _sanitize(profile)
	var json_text := JSON.stringify(sanitized, "\t")
	var tmp_path := path + ".tmp"

	var tmp_file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if tmp_file == null:
		return false
	tmp_file.store_string(json_text)
	tmp_file.close()

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var err := DirAccess.rename_absolute(tmp_path, path)
	if err == OK:
		return true

	# Fallback: atomic rename failed (e.g. platform limitation). Write
	# directly rather than losing the data entirely.
	var direct := FileAccess.open(path, FileAccess.WRITE)
	if direct == null:
		return false
	direct.store_string(json_text)
	direct.close()

	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)

	return true
