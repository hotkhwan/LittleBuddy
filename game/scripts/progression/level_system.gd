class_name LevelSystem
extends RefCounted

## Chapters, level order and unlock progression, over the existing mission
## content. No new gameplay: a level *is* a mission with six extra fields (see
## `LevelDefinition`), and `MissionRunner` still runs it.
##
## ## Unlock rule
##
## **Progression gates on COMPLETION, never on a star count.** Completion and
## rating are two different facts:
##
##   - `levelCompleted[id]` -- the child reached the end of the level. True even
##     if they skipped every task. This, and only this, unlocks anything.
##   - `starsByLevel[id]` -- the honest 0..3 rating. Star 1 requires genuinely
##     completing the core objective, so a skipped-through level rates 0.
##
## A child may therefore unlock the whole journey with 0 stars, which is the
## point: the skip button is the room's no-dead-end escape hatch and must never
## become a lock, while a skipped level must never be flattered as a success.
## Concretely:
##
##   - the first level of the first chapter is always unlocked;
##   - level N+1 unlocks when level N is completed;
##   - chapter C+1 unlocks when every chained level of chapter C is completed;
##   - a level tagged with a `chapterId` but absent from that chapter's
##     `levelIds` chain is a bonus level: it unlocks with the chapter and never
##     blocks chapter completion.
##
## The unlocked set is *derived* from the completion map rather than
## accumulated, so it is idempotent by construction: replaying a level, or
## applying the same result twice, cannot produce a different answer.
##
## Every method that takes a `completed_levels` Dictionary accepts truthy values
## of any shape (`true`, or a v2-era star count >= 1), so an older caller or an
## un-migrated map still reads correctly instead of silently locking a child out.
##
## The old `unlockAtStars` gate is untouched. `ContentLibrary.get_unlocked_
## missions()` still works, stickers still use it, and `is_mission_available()`
## below routes each mission to whichever gate applies to it.
##
## ## SaveService
##
## Another agent owns `SaveService`. Everything here works without it: the pure
## methods take `stars_by_level` as a plain `Dictionary`. `apply_completion()`
## will additionally persist through the autoload when it exists, probing with
## `get_node_or_null` + `has_method` so a missing or older SaveService degrades
## to "compute the answer, persist nothing" instead of crashing.

const SELF_PATH: String = "res://scripts/progression/level_system.gd"
const LEVEL_DEFINITION_SCRIPT_PATH: String = "res://scripts/progression/level_definition.gd"
const STAR_RULES_SCRIPT_PATH: String = "res://scripts/progression/star_rules.gd"

const DEFAULT_INDEX_PATH: String = "res://content/index.json"
const DEFAULT_CHAPTERS_PATH: String = "res://content/chapters/chapters.json"

const SAVE_SERVICE_NODE: String = "SaveService"

var _library: Object = null
var _chapters: Array = []
var _chapters_by_id: Dictionary = {}
var _levels_by_id: Dictionary = {}
var _level_ids_ordered: Array = []
var _level_id_by_mission: Dictionary = {}
var _warnings: Array = []
var _save_service: Object = null


## Convenience constructor. Untyped return for the same cold-cache reason as
## `ContentLibrary.create()`.
static func create(library: Object = null, chapters_path: String = "") -> RefCounted:
	var script: GDScript = load(SELF_PATH) as GDScript
	if script == null:
		return null
	var system: RefCounted = script.new()
	system.call("load_all", library, chapters_path)
	return system


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

## `library` is a loaded `ContentLibrary` (untyped so this never depends on the
## global class cache). Safe to call repeatedly.
func load_all(library: Object = null, chapters_path: String = "") -> void:
	_reset()
	_library = library
	_load_levels()
	_load_chapters(chapters_path)


func _reset() -> void:
	_library = null
	_chapters = []
	_chapters_by_id = {}
	_levels_by_id = {}
	_level_ids_ordered = []
	_level_id_by_mission = {}
	_warnings = []


func _load_levels() -> void:
	if _library == null or not _library.has_method("get_missions"):
		_warn("no content library supplied; no levels loaded")
		return
	var definition_script: GDScript = load(LEVEL_DEFINITION_SCRIPT_PATH) as GDScript
	if definition_script == null:
		_warn("could not load level_definition.gd")
		return

	for entry: Variant in _library.call("get_missions"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var definition: RefCounted = definition_script.new()
		definition.call("initialize", entry)
		var level_id: String = String(definition.call("get_level_id"))
		if level_id.is_empty():
			_warn("mission without a usable id skipped")
			continue
		if _levels_by_id.has(level_id):
			_warn("duplicate levelId '%s' ignored" % level_id)
			continue
		_levels_by_id[level_id] = definition
		_level_ids_ordered.append(level_id)
		var mission_id: String = String(definition.call("get_mission_id"))
		if not mission_id.is_empty():
			_level_id_by_mission[mission_id] = level_id


func _load_chapters(chapters_path: String) -> void:
	var path: String = chapters_path
	if path.is_empty():
		path = _chapters_path_from_index()

	var data: Dictionary = _read_json_dict(path, "chapters")
	var raw: Variant = data.get("chapters", null)
	if typeof(raw) != TYPE_ARRAY:
		if not data.is_empty():
			_warn("%s: 'chapters' is missing or is not an array" % path)
		return

	for entry: Variant in (raw as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			_warn("%s: skipped a non-object chapter entry" % path)
			continue
		var chapter: Dictionary = (entry as Dictionary).duplicate(true)
		var chapter_id: String = String(chapter.get("chapterId", "")).strip_edges()
		if chapter_id.is_empty():
			_warn("%s: skipped a chapter with no 'chapterId'" % path)
			continue
		if _chapters_by_id.has(chapter_id):
			_warn("%s: duplicate chapterId '%s' ignored" % [path, chapter_id])
			continue
		chapter["levelIds"] = _resolve_chain(chapter_id, chapter.get("levelIds", []), path)
		chapter["bonusLevelIds"] = _bonus_level_ids(chapter_id, chapter["levelIds"])
		_chapters.append(chapter)
		_chapters_by_id[chapter_id] = chapter

	_chapters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _as_int(a.get("chapterNumber", 0)) < _as_int(b.get("chapterNumber", 0)))


## Drops chain entries that resolve to no level, so a typo cannot silently wall
## a child off from the rest of a chapter.
func _resolve_chain(chapter_id: String, raw: Variant, path: String) -> Array:
	var chain: Array = []
	if typeof(raw) != TYPE_ARRAY:
		_warn("%s: chapter '%s' has no 'levelIds' array" % [path, chapter_id])
		return chain
	for entry: Variant in (raw as Array):
		var level_id: String = String(entry).strip_edges()
		if level_id.is_empty() or chain.has(level_id):
			continue
		if not _levels_by_id.has(level_id):
			_warn("%s: chapter '%s' lists unknown levelId '%s'" % [path, chapter_id, level_id])
			continue
		chain.append(level_id)
	return chain


## Levels tagged with this chapter but not in its chain.
func _bonus_level_ids(chapter_id: String, chain: Array) -> Array:
	var bonus: Array = []
	for level_id: Variant in _level_ids_ordered:
		var definition: RefCounted = _levels_by_id[level_id]
		if String(definition.call("get_chapter_id")) != chapter_id:
			continue
		if chain.has(String(level_id)):
			continue
		bonus.append(String(level_id))
	return bonus


func _chapters_path_from_index() -> String:
	var index: Dictionary = _read_json_dict(DEFAULT_INDEX_PATH, "content index")
	var path: String = String(index.get("chaptersFile", "")).strip_edges()
	if path.is_empty():
		return DEFAULT_CHAPTERS_PATH
	return path


# ---------------------------------------------------------------------------
# Levels
# ---------------------------------------------------------------------------

func get_level_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for level_id: Variant in _level_ids_ordered:
		ids.append(String(level_id))
	return ids


func has_level(level_id: String) -> bool:
	return _levels_by_id.has(level_id)


## The `LevelDefinition` for `level_id`, or `null`.
func get_level(level_id: String) -> RefCounted:
	var found: Variant = _levels_by_id.get(level_id, null)
	if found == null:
		return null
	return found


func get_level_for_mission(mission_id: String) -> RefCounted:
	var level_id: String = String(_level_id_by_mission.get(mission_id, ""))
	if level_id.is_empty():
		return null
	return get_level(level_id)


## The mission id `MissionRunner.start_mission()` needs for this level.
func get_mission_id_for_level(level_id: String) -> String:
	var definition: RefCounted = get_level(level_id)
	if definition == null:
		return ""
	return String(definition.call("get_mission_id"))


func get_level_summary(level_id: String) -> Dictionary:
	var definition: RefCounted = get_level(level_id)
	if definition == null:
		return {}
	return definition.call("to_dictionary")


## THE seeding hook. "Which tasks belong to level X?" -- answered without the
## caller reaching into mission JSON or into this class's internals.
func get_level_task_ids(level_id: String) -> PackedStringArray:
	var definition: RefCounted = get_level(level_id)
	if definition == null:
		return PackedStringArray()
	return definition.call("get_task_ids")


## Star rules for a level, authored or derived from its task modes.
func get_star_rules(level_id: String) -> Dictionary:
	var definition: RefCounted = get_level(level_id)
	if definition == null:
		return {}
	var tasks: Array = []
	var mission_id: String = String(definition.call("get_mission_id"))
	if _library != null and _library.has_method("get_mission_tasks") and not mission_id.is_empty():
		tasks = _library.call("get_mission_tasks", mission_id)
	return definition.call("get_star_rules", tasks)


## Rate one play of a level. Pure: `session` is `{completedTaskIds, optionalObjectiveIds}`.
func rate_session(level_id: String, session: Variant) -> int:
	var star_rules: GDScript = load(STAR_RULES_SCRIPT_PATH) as GDScript
	if star_rules == null:
		return 0
	return int(star_rules.evaluate(get_star_rules(level_id), session))


func describe_session(level_id: String, session: Variant) -> Dictionary:
	var star_rules: GDScript = load(STAR_RULES_SCRIPT_PATH) as GDScript
	if star_rules == null:
		return {}
	return star_rules.describe(get_star_rules(level_id), session)


# ---------------------------------------------------------------------------
# Chapters
# ---------------------------------------------------------------------------

func get_chapters() -> Array:
	var copy: Array = []
	for chapter: Variant in _chapters:
		copy.append((chapter as Dictionary).duplicate(true))
	return copy


func get_chapter_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for chapter: Variant in _chapters:
		ids.append(String((chapter as Dictionary).get("chapterId", "")))
	return ids


func get_chapter(chapter_id: String) -> Dictionary:
	var found: Variant = _chapters_by_id.get(chapter_id, null)
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return (found as Dictionary).duplicate(true)


## Chained levels of a chapter, in play order, followed by its bonus levels.
func get_levels_in_chapter(chapter_id: String) -> PackedStringArray:
	var chapter: Dictionary = get_chapter(chapter_id)
	var ids: PackedStringArray = PackedStringArray()
	for level_id: Variant in _array(chapter.get("levelIds", [])):
		ids.append(String(level_id))
	for level_id: Variant in _array(chapter.get("bonusLevelIds", [])):
		ids.append(String(level_id))
	return ids


## Only the chained levels -- the ones chapter completion depends on.
func get_chapter_chain(chapter_id: String) -> PackedStringArray:
	var chapter: Dictionary = get_chapter(chapter_id)
	var ids: PackedStringArray = PackedStringArray()
	for level_id: Variant in _array(chapter.get("levelIds", [])):
		ids.append(String(level_id))
	return ids


## The authored journey as one flat list: every chapter in play order, each
## chapter's chain before its bonus levels. This is the ORDER a child meets the
## content in, which is what "levels since last seen" has to be measured against.
func get_journey_level_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for chapter: Variant in _chapters:
		for level_id: Variant in get_levels_in_chapter(String((chapter as Dictionary).get("chapterId", ""))):
			var text: String = String(level_id)
			if not ids.has(text):
				ids.append(text)
	return ids


## 1-based position of `level_id` in `get_journey_level_ids()`, or 0 when the
## level is not part of the authored journey.
##
## Deliberately 1-based with 0 meaning "unknown": `VocabularyReview` treats a
## `lastSeenLevel` of 0 as "never honestly placed" and falls back to the neutral
## weight, so an unrecognised level can never be mistaken for level zero and
## resurface the whole vocabulary at once.
func get_level_ordinal(level_id: String) -> int:
	var wanted: String = level_id.strip_edges()
	if wanted.is_empty():
		return 0
	var ids: PackedStringArray = get_journey_level_ids()
	for i: int in range(ids.size()):
		if ids[i] == wanted:
			return i + 1
	return 0


func get_first_chapter_id() -> String:
	if _chapters.is_empty():
		return ""
	return String((_chapters[0] as Dictionary).get("chapterId", ""))


func get_first_level_id() -> String:
	for chapter: Variant in _chapters:
		var chain: Array = _array((chapter as Dictionary).get("levelIds", []))
		if not chain.is_empty():
			return String(chain[0])
	return ""


## The level that follows `level_id`: next in the chapter chain, otherwise the
## first chained level of the next chapter. "" at the end of the journey.
func get_next_level_id(level_id: String) -> String:
	for i: int in range(_chapters.size()):
		var chain: Array = _array((_chapters[i] as Dictionary).get("levelIds", []))
		var position: int = chain.find(level_id)
		if position == -1:
			continue
		if position + 1 < chain.size():
			return String(chain[position + 1])
		for j: int in range(i + 1, _chapters.size()):
			var next_chain: Array = _array((_chapters[j] as Dictionary).get("levelIds", []))
			if not next_chain.is_empty():
				return String(next_chain[0])
		return ""
	return ""


# ---------------------------------------------------------------------------
# Progression -- pure, no autoloads
# ---------------------------------------------------------------------------

## "Did the child reach the end of this level?" -- NOT "did they earn a star?".
## A level completed entirely by skipping is complete and rates 0.
func is_level_complete(level_id: String, completed_levels: Dictionary) -> bool:
	if not completed_levels.has(level_id):
		return false
	return _is_truthy(completed_levels[level_id])


## A chapter is complete when every CHAINED level in it has been completed.
## Bonus levels never block it.
func is_chapter_complete(chapter_id: String, completed_levels: Dictionary) -> bool:
	var chain: Array = _array(get_chapter(chapter_id).get("levelIds", []))
	if chain.is_empty():
		return false
	for level_id: Variant in chain:
		if not is_level_complete(String(level_id), completed_levels):
			return false
	return true


## The full derived unlock state for a given `levelCompleted` map.
## Returns `{"levels": PackedStringArray, "chapters": PackedStringArray}`.
func compute_unlocks(completed_levels: Dictionary) -> Dictionary:
	var levels: PackedStringArray = PackedStringArray()
	var chapters: PackedStringArray = PackedStringArray()

	var chapter_unlocked: bool = true
	for chapter: Variant in _chapters:
		var chapter_dict: Dictionary = chapter
		var chapter_id: String = String(chapter_dict.get("chapterId", ""))
		if not chapter_unlocked:
			break
		chapters.append(chapter_id)

		var previous_complete: bool = true
		for level_id: Variant in _array(chapter_dict.get("levelIds", [])):
			if not previous_complete:
				break
			levels.append(String(level_id))
			previous_complete = is_level_complete(String(level_id), completed_levels)

		# Bonus levels ride along with the chapter itself.
		for level_id: Variant in _array(chapter_dict.get("bonusLevelIds", [])):
			levels.append(String(level_id))

		chapter_unlocked = is_chapter_complete(chapter_id, completed_levels)

	return {"levels": levels, "chapters": chapters}


func is_level_unlocked(level_id: String, completed_levels: Dictionary) -> bool:
	return (compute_unlocks(completed_levels)["levels"] as PackedStringArray).has(level_id)


func is_chapter_unlocked(chapter_id: String, completed_levels: Dictionary) -> bool:
	return (compute_unlocks(completed_levels)["chapters"] as PackedStringArray).has(chapter_id)


## Routes a mission to whichever gate owns it.
##
##   - promoted to a level -> completion gating (this class);
##   - still a plain mission -> the legacy `unlockAtStars` task-star threshold.
##
## `task_stars` is the LIFETIME TASK-STAR TOTAL (`SaveService.get_stars()`), not
## a level rating. The two currencies are never summed.
func is_mission_available(mission_id: String, task_stars: int, completed_levels: Dictionary) -> bool:
	var definition: RefCounted = get_level_for_mission(mission_id)
	if definition == null:
		return true
	if bool(definition.call("is_authored_level")):
		return is_level_unlocked(String(definition.call("get_level_id")), completed_levels)
	return int(definition.call("get_unlock_at_stars")) <= task_stars


## Levels that `completed_levels` opens up which `previous_completed` did not.
func newly_unlocked_levels(previous_completed: Dictionary, completed_levels: Dictionary) -> PackedStringArray:
	return _difference(
		compute_unlocks(previous_completed)["levels"],
		compute_unlocks(completed_levels)["levels"]
	)


func newly_unlocked_chapters(previous_completed: Dictionary, completed_levels: Dictionary) -> PackedStringArray:
	return _difference(
		compute_unlocks(previous_completed)["chapters"],
		compute_unlocks(completed_levels)["chapters"]
	)


## Applies a finished play of a level and returns the outcome. Pure -- takes and
## returns plain data, writes nothing.
##
## Reaching this function means the child reached the end of the level, so the
## level is COMPLETED here unconditionally, however many tasks were skipped.
## `awarded_stars` is the separate, honest rating and is max-merged, so a worse
## replay never lowers it and a repeated award never stacks. Unlocks are derived
## from the completion map only -- `awarded_stars` never affects them, which is
## what makes "a child may unlock the next level with 0 stars" true by
## construction rather than by discipline.
func resolve_completion(level_id: String, awarded_stars: int, stars_by_level: Dictionary, completed_levels: Dictionary = {}) -> Dictionary:
	var star_rules: GDScript = load(STAR_RULES_SCRIPT_PATH) as GDScript
	var previous: int = _stars_for(level_id, stars_by_level)
	var awarded: int = awarded_stars
	var merged: int = awarded
	if star_rules != null:
		awarded = int(star_rules.clamp_stars(awarded_stars))
		merged = int(star_rules.merge(previous, awarded))
	else:
		merged = maxi(previous, awarded)

	var updated: Dictionary = stars_by_level.duplicate(true)
	updated[level_id] = merged

	var was_completed: bool = is_level_complete(level_id, completed_levels)
	var updated_completed: Dictionary = completed_levels.duplicate(true)
	updated_completed[level_id] = true

	var unlocked_levels: PackedStringArray = newly_unlocked_levels(completed_levels, updated_completed)
	var unlocked_chapters: PackedStringArray = newly_unlocked_chapters(completed_levels, updated_completed)

	return {
		"levelId": level_id,
		"awardedStars": awarded,
		"previousStars": previous,
		"stars": merged,
		"improved": merged > previous,
		"starsByLevel": updated,
		"completed": true,
		"newlyCompleted": not was_completed,
		"levelCompleted": updated_completed,
		"newlyUnlockedLevels": unlocked_levels,
		"newlyUnlockedChapters": unlocked_chapters,
		"nextLevelId": get_next_level_id(level_id),
		"bonusSticker": merged >= 3,
	}


## The seeding answer for the save migration: every level whose tasks all appear
## in `completed_activities` gets exactly 1 star (core completion). We cannot
## know retroactively whether the listening or optional star was earned, so we
## never grant more -- under-crediting is safe, over-crediting is not.
func seed_stars_from_completed_activities(completed_activities: Variant) -> Dictionary:
	var completed: Dictionary = {}
	if typeof(completed_activities) == TYPE_ARRAY or typeof(completed_activities) == TYPE_PACKED_STRING_ARRAY:
		for entry: Variant in completed_activities:
			completed[String(entry)] = true

	var seeded: Dictionary = {}
	for level_id: Variant in _level_ids_ordered:
		var task_ids: PackedStringArray = get_level_task_ids(String(level_id))
		if task_ids.is_empty():
			continue
		var all_done: bool = true
		for task_id: String in task_ids:
			if not completed.has(task_id):
				all_done = false
				break
		if all_done:
			seeded[String(level_id)] = 1
	return seeded


## The completion half of the same seeding answer: exactly the levels that earn
## the seeded star are marked completed, so a returning child is never sent
## backwards and is never credited with a level they did not finish.
func seed_completed_from_completed_activities(completed_activities: Variant) -> Dictionary:
	var seeded: Dictionary = {}
	for level_id: Variant in seed_stars_from_completed_activities(completed_activities).keys():
		seeded[String(level_id)] = true
	return seeded


# ---------------------------------------------------------------------------
# SaveService bridge -- always optional
# ---------------------------------------------------------------------------

## Test seam. Injecting a stub keeps every code path below exercisable without
## an autoload.
func set_save_service(service: Object) -> void:
	_save_service = service


func get_save_service() -> Object:
	if _save_service != null:
		return _save_service
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var root: Window = (loop as SceneTree).root
		if root != null:
			return root.get_node_or_null(NodePath(SAVE_SERVICE_NODE))
	return null


## Current per-level ratings from SaveService, or `{}` when it is absent.
func load_stars_by_level() -> Dictionary:
	var service: Object = get_save_service()
	if service == null or not service.has_method("get_stars_by_level"):
		return {}
	var stored: Variant = service.call("get_stars_by_level")
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return (stored as Dictionary).duplicate(true)


## Current completion map from SaveService, or `{}` when it is absent.
func load_completed_levels() -> Dictionary:
	var service: Object = get_save_service()
	if service == null or not service.has_method("get_level_completed"):
		return {}
	var stored: Variant = service.call("get_level_completed")
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return (stored as Dictionary).duplicate(true)


## `resolve_completion()` plus persistence, when a SaveService is available.
## Every call is probed with `has_method`, so a partial or missing SaveService
## degrades to "return the computed result, persist nothing".
##
## Completion is recorded even when `awarded_stars` is 0 -- that is the whole
## point of the split, and it is what lets a child who skipped everything still
## move on.
func apply_completion(level_id: String, awarded_stars: int) -> Dictionary:
	var stars_by_level: Dictionary = load_stars_by_level()
	var completed_levels: Dictionary = load_completed_levels()
	var outcome: Dictionary = resolve_completion(level_id, awarded_stars, stars_by_level, completed_levels)

	var service: Object = get_save_service()
	if service == null:
		return outcome

	if service.has_method("mark_level_completed"):
		service.call("mark_level_completed", level_id)

	if bool(outcome.get("improved", false)) and service.has_method("set_level_stars"):
		service.call("set_level_stars", level_id, int(outcome.get("stars", 0)))

	if service.has_method("unlock_level"):
		for unlocked: String in (outcome.get("newlyUnlockedLevels", PackedStringArray()) as PackedStringArray):
			service.call("unlock_level", unlocked)

	if service.has_method("unlock_chapter"):
		for unlocked: String in (outcome.get("newlyUnlockedChapters", PackedStringArray()) as PackedStringArray):
			service.call("unlock_chapter", unlocked)

	var next_level_id: String = String(outcome.get("nextLevelId", ""))
	if not next_level_id.is_empty() and service.has_method("set_current_level"):
		if (outcome.get("newlyUnlockedLevels", PackedStringArray()) as PackedStringArray).has(next_level_id):
			service.call("set_current_level", next_level_id)

	return outcome


# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

func get_load_warnings() -> Array:
	return _warnings.duplicate()


func get_summary() -> Dictionary:
	return {
		"chapters": _chapters.size(),
		"levels": _level_ids_ordered.size(),
		"authoredLevels": _authored_level_count(),
		"warnings": _warnings.size(),
	}


func _authored_level_count() -> int:
	var count: int = 0
	for level_id: Variant in _level_ids_ordered:
		if bool((_levels_by_id[level_id] as RefCounted).call("is_authored_level")):
			count += 1
	return count


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _warn(message: String) -> void:
	_warnings.append(message)


func _stars_for(level_id: String, stars_by_level: Dictionary) -> int:
	if not stars_by_level.has(level_id):
		return 0
	return clampi(_as_int(stars_by_level[level_id]), 0, 3)


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


static func _array(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value


static func _difference(before: Variant, after: Variant) -> PackedStringArray:
	var previous: Dictionary = {}
	if typeof(before) == TYPE_PACKED_STRING_ARRAY or typeof(before) == TYPE_ARRAY:
		for entry: Variant in before:
			previous[String(entry)] = true
	var result: PackedStringArray = PackedStringArray()
	if typeof(after) == TYPE_PACKED_STRING_ARRAY or typeof(after) == TYPE_ARRAY:
		for entry: Variant in after:
			var text: String = String(entry)
			if not previous.has(text) and not result.has(text):
				result.append(text)
	return result


## Completion maps store `true`. A v2-era star count (>= 1) is also accepted, so
## a caller that has not yet switched to the completion map degrades to the old
## answer instead of locking a child out of their own progress.
static func _is_truthy(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return float(value) >= 1.0
		_:
			return false


static func _as_int(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(round(float(value)))
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value).to_int()
		_:
			return 0
