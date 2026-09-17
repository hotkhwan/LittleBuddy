class_name ProfileStore
extends RefCounted

## Pure, testable persistence logic for the child's local profile.
## Owns reading/writing user://profile.json and defending against every
## corruption/failure mode so gameplay never crashes or silently loses stars.
##
## Schema v3 splits *finishing* a level from *how well* it was played. Three
## independent things live side by side here and are never summed or conflated:
##   - "stars"          lifetime TASK star total (+1 per completed task). Still
##                       the only thing that feeds sticker unlockAtStars
##                       thresholds. Never touched by level seeding/migration.
##   - "starsByLevel"    per-level 0..3 RATING (best-ever, max-wins). An honest
##                       score: star 1 means the core objective was genuinely
##                       completed, so a level finished entirely by skipping
##                       rates 0. Never folded into "stars".
##   - "levelCompleted"  levelId -> true. "The child reached the end of this
##                       level", true even if every task was skipped. THIS is
##                       what gates unlocking, so the skip button can never trap
##                       a child, while a 0-star completion stays honest.
##
## Schema v4 promotes WHERE IN THE HOUSE the child is to top-level
## `currentRoomId` / `currentSpawnId`. Two semantic strings, never a coordinate:
## a `Vector3` that was valid when it was written drifts out of the navigation
## mesh the moment a sofa moves, and a saved coordinate is then a way of
## stranding a child with no route back. A room id plus a spawn id can always be
## re-resolved against the CURRENT layout.

const DEFAULT_PATH := "user://profile.json"
const CURRENT_VERSION := 4

## -- World location (v4) --------------------------------------------------------

const ROOM_FIELD: String = "currentRoomId"
const SPAWN_FIELD: String = "currentSpawnId"

## The last-resort location. Deliberately duplicated from
## `HouseLayout.FALLBACK_ROOM` / `HouseLayout.DEFAULT_SPAWN` rather than
## imported: the save layer is domain logic and must not reach into
## `scripts/house/**` (CLAUDE.md "domain logic ... must never reference 3D node
## types"; house_layout.gd is full of `Vector3`/`Rect2`). The duplication is not
## left to trust -- `test_save_world_location.gd` asserts the two agree, so a
## rename on either side fails the build instead of silently diverging.
const FALLBACK_ROOM_ID: String = "bedroom"
const DEFAULT_SPAWN_ID: String = "default"

## A room/spawn id is a single camelCase segment. Anything else -- a compound
## semantic id like "bedroom.bed", a NodePath, a number, a Dictionary, an
## absurdly long string -- is not a location this schema can honour, so it falls
## back rather than being written through to the house.
const MAX_SEMANTIC_ID_LENGTH: int = 64

## -- The v3 compatibility shim, and how to remove it -----------------------------
##
## Under v3 the world location lived at `settings.worldState`, because
## `ProfileStore` preserves unknown JSON-safe keys inside `settings` and that let
## HouseWorld ship without a schema bump. v4 makes it a first-class top-level
## field, which is what `docs/SLICE_CONTRACT.md` §4 asks for.
##
## The contract also says to REMOVE the old key. This build does not, because the
## only reader/writer of it is `scripts/house/world_state.gd`
## (`read_from_profile()` / `write_into_profile()`), which is outside this agent's
## write scope and is being edited by nobody tonight. Deleting the key here would
## silently strand every HouseWorld restore in the bedroom while every test still
## reported green -- the worst possible failure shape.
##
## So for exactly one release `settings.worldState` stays a supported *write*
## channel: if it is present it wins, and it is normalised to agree with the
## top-level fields on every load and save. It is never synthesised on a profile
## that does not already have it, so a fresh v4 profile's `settings` block is
## clean.
##
## To finish the migration, in one commit:
##   1. point `world_state.gd` `read_from_profile()`/`write_into_profile()` at the
##      top-level `currentRoomId`/`currentSpawnId` (it already owns those two
##      constant names),
##   2. flip `DROP_LEGACY_WORLD_STATE` to true here,
##   3. drop the `settings.worldState` expectations in `test_world_state.gd`.
## Nothing else changes.
##
## `drop_legacy_world_state` below is the same switch as an instance field, so a
## test can run the POST-shim configuration today. That is not decoration: while
## the shim is on, `_sanitize()` reads the legacy key on every load for every
## version, which makes `_migrate_v3_to_v4()` redundant and therefore able to rot
## unnoticed -- a mutation disabling it survived the whole suite until this seam
## existed. The day the shim is switched off, that dead step would be the ONLY
## thing lifting a v3 profile's location, and every returning child would wake up
## in the bedroom.
const LEGACY_WORLD_STATE_KEY: String = "worldState"
const DROP_LEGACY_WORLD_STATE: bool = false

## Levels are authored directly onto the mission records (see
## `LevelDefinition.is_authored_level()`), and their play order lives in
## chapters.json. There is deliberately no separate levels.json: a
## `DEFAULT_LEVELS_PATH` constant pointed at one for the whole of Phase 1 and
## the file was never created, so the read always fell through. Both paths are
## constructor arguments purely as a test seam.
const DEFAULT_MISSIONS_PATH := "res://content/missions/missions.json"
const DEFAULT_CHAPTERS_PATH := "res://content/chapters/chapters.json"

## The first chapter and its first level must always be unlocked after a
## migration so a returning profile is never stranded (see
## docs/PHASE1_CONTRACT.md). These constants are only the last-resort answer for
## when chapters.json/missions.json cannot be read at all; normally both are
## derived from the content itself.
const CH1_CHAPTER_ID := "ch1"
const CH2_CHAPTER_ID := "ch2"
const CH2_FALLBACK_FIRST_LEVEL_ID := "milkTime"

var path: String
var missions_path: String
var chapters_path: String

## Test seam for the shim above. Production always leaves this at the constant.
var drop_legacy_world_state: bool = DROP_LEGACY_WORLD_STATE

func _init(p_path: String = DEFAULT_PATH, p_missions_path: String = DEFAULT_MISSIONS_PATH, p_chapters_path: String = DEFAULT_CHAPTERS_PATH) -> void:
	path = p_path
	missions_path = p_missions_path
	chapters_path = p_chapters_path


## Canonical default schema. Always returns a fresh Dictionary (no shared
## references) so callers can freely mutate the result.
func default_profile() -> Dictionary:
	return {
		"profileVersion": CURRENT_VERSION,
		"stars": 0,
		"completedActivities": [],
		"currentChapter": CH1_CHAPTER_ID,
		"currentLevel": "",
		ROOM_FIELD: FALLBACK_ROOM_ID,
		SPAWN_FIELD: DEFAULT_SPAWN_ID,
		"starsByLevel": {},
		"levelCompleted": {},
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
	# additive v1->v3 migration once; a v2 profile runs the small v2->v3 step.
	# Version 3 is passed through untouched so migration is idempotent. An
	# unknown/newer version is never migrated --
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

	# currentRoomId / currentSpawnId (v4): where in the house the child is, as two
	# semantic ids. Anything that is not a plain id falls back to bedroom/default,
	# so a corrupt or stale save can never point at nowhere.
	var location: Dictionary = _resolve_world_location(raw)
	result[ROOM_FIELD] = location[ROOM_FIELD]
	result[SPAWN_FIELD] = location[SPAWN_FIELD]

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

	# levelCompleted: Dictionary<String levelId, true>. Deliberately parallel to
	# starsByLevel and deliberately NOT derived from it -- a level can be
	# completed with 0 stars. Only truthy entries are kept, so the key set is
	# exactly "the levels the child has reached the end of"; a stored `false` (or
	# 0) is dropped rather than preserved as a negative fact.
	result["levelCompleted"] = _sanitize_completion_map(raw.get("levelCompleted", null))

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
	# The v3 compatibility shim. `settings.worldState` is never created here --
	# only kept in agreement with the authoritative top-level fields when a caller
	# is still using it, so a stale or malformed mirror can never contradict the
	# real location. See DROP_LEGACY_WORLD_STATE above.
	if settings_result.has(LEGACY_WORLD_STATE_KEY):
		if drop_legacy_world_state:
			settings_result.erase(LEGACY_WORLD_STATE_KEY)
		else:
			settings_result[LEGACY_WORLD_STATE_KEY] = {
				ROOM_FIELD: result[ROOM_FIELD],
				SPAWN_FIELD: result[SPAWN_FIELD],
			}

	result["settings"] = settings_result

	result["profileVersion"] = CURRENT_VERSION

	return result


## -- World location ---------------------------------------------------------------

## Resolves the child's saved location out of a raw profile, tolerating every
## shape a hand-edited, half-written, downgraded or corrupt file can produce.
## Always returns two non-empty semantic ids.
##
## `settings.worldState` (the v3 home, still written by `world_state.gd`) takes
## precedence over the top-level fields when it is present, because it is the
## channel a live caller just wrote through; the top-level fields are then
## brought into agreement with it. Once the shim is removed this whole branch
## goes with it and the top-level fields are simply read.
func _resolve_world_location(raw: Dictionary) -> Dictionary:
	var room: String = _sanitize_semantic_id(raw.get(ROOM_FIELD, null), FALLBACK_ROOM_ID)
	var spawn: String = _sanitize_semantic_id(raw.get(SPAWN_FIELD, null), DEFAULT_SPAWN_ID)

	var legacy: Dictionary = {} if drop_legacy_world_state else _legacy_world_state(raw)
	if not legacy.is_empty():
		room = _sanitize_semantic_id(legacy.get(ROOM_FIELD, null), FALLBACK_ROOM_ID)
		spawn = _sanitize_semantic_id(legacy.get(SPAWN_FIELD, null), DEFAULT_SPAWN_ID)

	return {ROOM_FIELD: room, SPAWN_FIELD: spawn}


## `settings.worldState` as a Dictionary, or `{}` when it is absent or is not a
## Dictionary at all (a stored `5`, a String, an Array -- all shapes the corrupt
## cases in `test_world_state.gd` already exercise).
func _legacy_world_state(raw: Dictionary) -> Dictionary:
	var settings: Variant = raw.get("settings", null)
	if typeof(settings) != TYPE_DICTIONARY:
		return {}
	var legacy: Variant = (settings as Dictionary).get(LEGACY_WORLD_STATE_KEY, null)
	if typeof(legacy) != TYPE_DICTIONARY:
		return {}
	return legacy


## One camelCase segment, or the fallback. Rejects non-Strings (so a persisted
## `Vector3`, Array or Dictionary can never become a location), the empty and
## whitespace-only string, compound ids such as "bedroom.bed", anything that
## looks like a path, and absurd lengths. Surrounding whitespace is forgiven
## rather than treated as a different room.
static func _sanitize_semantic_id(value: Variant, fallback: String) -> String:
	if typeof(value) != TYPE_STRING:
		return fallback
	var cleaned: String = String(value).strip_edges()
	if cleaned.is_empty() or cleaned.length() > MAX_SEMANTIC_ID_LENGTH:
		return fallback
	for forbidden: String in [".", "/", ":", " ", "\t", "\n"]:
		if cleaned.contains(forbidden):
			return fallback
	return cleaned


## Normalizes an arbitrary value into `{levelId: true}`. Accepts the canonical
## Dictionary form, and also a plain Array of ids, so a hand-edited or
## half-written profile still yields something sane.
func _sanitize_completion_map(raw_value: Variant) -> Dictionary:
	var cleaned: Dictionary = {}
	if typeof(raw_value) == TYPE_ARRAY:
		for item in raw_value:
			if typeof(item) == TYPE_STRING and item != "":
				cleaned[item] = true
		return cleaned
	if typeof(raw_value) != TYPE_DICTIONARY:
		return cleaned
	var raw_map: Dictionary = raw_value
	for level_id in raw_map.keys():
		if typeof(level_id) != TYPE_STRING or level_id == "":
			continue
		if _is_truthy(raw_map[level_id]):
			cleaned[level_id] = true
	return cleaned


static func _is_truthy(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return float(value) >= 1.0
		_:
			return false


## De-duplicating string-array sanitizer shared by every array-of-ids field.
func _sanitize_string_array(raw_value: Variant) -> Array:
	var cleaned: Array = []
	if typeof(raw_value) != TYPE_ARRAY:
		return cleaned
	for item in raw_value:
		if typeof(item) == TYPE_STRING and not cleaned.has(item):
			cleaned.append(item)
	return cleaned


## Migration hook, as a CHAIN rather than three independent jumps: every older
## version is lifted one step at a time to the current schema, so v1->v4 and
## v2->v4 are literally the tested v1->v3/v2->v3 steps followed by the tested
## v3->v4 step. There is no fourth code path that could drift away from them.
##
## Legacy (<=1, including missing/malformed) versions run the full seeding
## migration; a v2 profile runs only the small levelCompleted step; a v3 profile
## only has its world location promoted. Version 4 -- and any unknown future
## version -- passes through unchanged and relies on _sanitize()'s
## field-by-field validation, which keeps migration idempotent by construction
## (running it twice is a no-op).
func _migrate(raw: Dictionary, version: int) -> Dictionary:
	if version <= 1:
		return _migrate_v3_to_v4(_migrate_v1_to_v3(raw))
	if version == 2:
		return _migrate_v3_to_v4(_migrate_v2_to_v3(raw))
	if version == 3:
		return _migrate_v3_to_v4(raw)
	return raw


## v3 -> v4. Promotes the world location from `settings.worldState` to the
## top-level `currentRoomId`/`currentSpawnId` fields. Nothing else is read or
## written: stars, completedActivities, starsByLevel, levelCompleted, the unlock
## sets and every other setting are carried over verbatim.
##
## A v1/v2 profile has no world location at all and simply gains the bedroom
## default, which is where a child who has never been in the house belongs.
##
## The old key is left in place for one release; see DROP_LEGACY_WORLD_STATE.
func _migrate_v3_to_v4(raw: Dictionary) -> Dictionary:
	var migrated := raw.duplicate(true)

	# Reads the legacy key DIRECTLY rather than going through
	# `_resolve_world_location()`, which honours `drop_legacy_world_state`. A
	# migration must be able to read the old shape even -- especially -- once the
	# rest of the code has stopped looking at it; that is what makes it a
	# migration rather than a second reader.
	var legacy: Dictionary = _legacy_world_state(migrated)
	var room_source: Variant = legacy.get(ROOM_FIELD, migrated.get(ROOM_FIELD, null))
	var spawn_source: Variant = legacy.get(SPAWN_FIELD, migrated.get(SPAWN_FIELD, null))

	migrated[ROOM_FIELD] = _sanitize_semantic_id(room_source, FALLBACK_ROOM_ID)
	migrated[SPAWN_FIELD] = _sanitize_semantic_id(spawn_source, DEFAULT_SPAWN_ID)

	if drop_legacy_world_state and typeof(migrated.get("settings", null)) == TYPE_DICTIONARY:
		(migrated["settings"] as Dictionary).erase(LEGACY_WORLD_STATE_KEY)

	return migrated


## v2 -> v3. The only new fact is `levelCompleted`, and the only honest thing a
## v2 profile can say about it is "a level I rated at least 1 star on was
## obviously finished". Nothing else changes: stars, completedActivities,
## starsByLevel, the unlock sets and settings are all carried over verbatim.
##
## A v2 rating of 0 is NOT treated as completion. Under v2 every finished level
## was force-rated to at least 1 star, so a stored 0 cannot have come from a
## finished level -- and under-crediting is safe while over-crediting is not.
func _migrate_v2_to_v3(raw: Dictionary) -> Dictionary:
	var migrated := raw.duplicate(true)

	var completed_levels: Dictionary = _sanitize_completion_map(migrated.get("levelCompleted", null))
	if typeof(migrated.get("starsByLevel", null)) == TYPE_DICTIONARY:
		var stars_by_level: Dictionary = migrated["starsByLevel"]
		for level_id in stars_by_level.keys():
			if typeof(level_id) != TYPE_STRING or level_id == "":
				continue
			if _is_truthy(stars_by_level[level_id]):
				completed_levels[level_id] = true
	migrated["levelCompleted"] = completed_levels

	return migrated


## Additive, lossless v1 -> v3 migration.
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
## - The same levels -- and only those -- are marked in levelCompleted, so a
##   returning child keeps exactly the progression they already had.
## - The first chapter and its first level are always unlocked afterwards so no
##   profile can be stranded, even if the content files are missing.
func _migrate_v1_to_v3(raw: Dictionary) -> Dictionary:
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

	# Completion is seeded from exactly the levels that earned the seeded star:
	# never fewer (that would send a returning child backwards) and never more.
	var completed_levels: Dictionary = _sanitize_completion_map(migrated.get("levelCompleted", null))
	for level_id in stars_by_level.keys():
		completed_levels[String(level_id)] = true

	var first_chapter: String = seed["firstChapterId"]
	if first_chapter == "":
		first_chapter = CH2_CHAPTER_ID
	if not unlocked_chapters.has(CH1_CHAPTER_ID):
		unlocked_chapters.append(CH1_CHAPTER_ID)
	if not unlocked_chapters.has(first_chapter):
		unlocked_chapters.append(first_chapter)

	var first_level: String = seed["firstLevelId"]
	if first_level == "":
		first_level = CH2_FALLBACK_FIRST_LEVEL_ID
	if not unlocked_levels.has(first_level):
		unlocked_levels.append(first_level)

	migrated["currentChapter"] = first_chapter
	migrated["currentLevel"] = first_level
	migrated["starsByLevel"] = stars_by_level
	migrated["levelCompleted"] = completed_levels
	migrated["unlockedChapters"] = unlocked_chapters
	migrated["unlockedLevels"] = unlocked_levels
	if typeof(migrated.get("unlockedRooms", null)) != TYPE_ARRAY:
		migrated["unlockedRooms"] = []

	return migrated


## Builds starsByLevel/unlockedLevels/unlockedChapters seeds from a list of
## already-completed activity ids, using the level definitions authored onto
## missions.json and the play order in chapters.json. Levels are only granted a
## star when every one of their tasks is already completed; nothing here ever
## touches "stars" (the task-star total).
func _seed_level_progress(completed: Array) -> Dictionary:
	var stars_by_level: Dictionary = {}
	var unlocked_levels: Array = []
	var unlocked_chapters: Array = []

	for level_def in _load_level_definitions():
		var level_id: String = String(level_def.get("levelId", ""))
		if level_id.is_empty():
			continue
		var chapter_id: String = String(level_def.get("chapterId", ""))

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

	var start := _first_chapter_and_level()

	return {
		"starsByLevel": stars_by_level,
		"unlockedLevels": unlocked_levels,
		"unlockedChapters": unlocked_chapters,
		"firstChapterId": String(start.get("chapterId", "")),
		"firstLevelId": String(start.get("levelId", "")),
	}


## The start of the authored journey: the lowest-numbered chapter in
## chapters.json and the first level of its chain. Returns empty strings for any
## missing/unreadable/malformed input, in which case the caller falls back to the
## CH2_* constants so a migration can never strand a profile.
func _first_chapter_and_level() -> Dictionary:
	var empty := {"chapterId": "", "levelId": ""}
	if chapters_path.is_empty() or not FileAccess.file_exists(chapters_path):
		return empty

	var file := FileAccess.open(chapters_path, FileAccess.READ)
	if file == null:
		return empty
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return empty
	var chapters_raw = parsed.get("chapters", null)
	if typeof(chapters_raw) != TYPE_ARRAY:
		return empty

	var best_number := 0
	var best := empty
	for entry in chapters_raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var chapter: Dictionary = entry
		var chapter_id: String = String(chapter.get("chapterId", "")).strip_edges()
		if chapter_id.is_empty():
			continue
		var level_ids = chapter.get("levelIds", null)
		if typeof(level_ids) != TYPE_ARRAY or (level_ids as Array).is_empty():
			continue
		var number := 0
		var number_value = chapter.get("chapterNumber", 0)
		if typeof(number_value) == TYPE_INT or typeof(number_value) == TYPE_FLOAT:
			number = int(number_value)
		if best["chapterId"] != "" and number >= best_number:
			continue
		best_number = number
		best = {
			"chapterId": chapter_id,
			"levelId": String((level_ids as Array)[0]).strip_edges(),
		}

	return best


## Reads the level->task/chapter mapping needed to seed starsByLevel and
## levelCompleted. Fully defensive throughout: any missing file, unreadable
## file, invalid JSON, or unexpected shape simply yields an empty Array so
## migration seeds nothing rather than failing.
##
## Levels are authored directly onto the mission records in `missions_path`
## (default res://content/missions/missions.json), matching
## `LevelDefinition.is_authored_level()`: a mission entry with a non-empty
## "levelId" AND "chapterId" is a level, using that mission's own "taskIds".
func _load_level_definitions() -> Array:
	return _load_level_definitions_from_missions_file()


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
