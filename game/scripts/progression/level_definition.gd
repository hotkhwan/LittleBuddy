class_name LevelDefinition
extends RefCounted

## A thin, read-only view over one entry in `content/missions/missions.json`.
##
## A mission already *is* a level in all but name -- ordered `taskIds`, an intro
## and an outro phrase, a title in two languages. Rather than building a parallel
## `levels.json` and keeping the two in sync forever, the level layer is six
## additive fields on the existing mission record:
##
## ```jsonc
## {
##   "missionId": "feedingTime",   // unchanged, MissionRunner still drives this
##   "chapterId": "ch2",           // new
##   "levelId": "milkTime",        // new
##   "levelNumber": 6,             // new
##   "storyBeat": "...",           // new
##   "template": "fetchAndGive",   // new
##   "starRules": { ... }          // new
## }
## ```
##
## Every pre-existing key keeps working, and a mission **without** the new fields
## still loads: `levelId` falls back to `missionId`, the template falls back to
## `sequenceRoutine`, and star rules are derived from the task modes. That is
## what lets the seven shipped missions keep running untouched.
##
## `get_mission()` returns the original record verbatim, so `MissionRunner` and
## `ContentLibrary` never need to know this class exists.

const SELF_PATH: String = "res://scripts/progression/level_definition.gd"
const STAR_RULES_SCRIPT_PATH: String = "res://scripts/progression/star_rules.gd"

## The six level templates from `docs/LEVEL_MATRIX.md`. Data, not code paths --
## nothing here dispatches on them yet; they document what a level is made of.
const TEMPLATES: Array[String] = [
	"fetchAndGive",
	"chooseCorrectObject",
	"placeIt",
	"sequenceRoutine",
	"walkTo",
	"storybookBeat",
]

## What an untagged mission is: an ordered routine of tasks.
const DEFAULT_TEMPLATE: String = "sequenceRoutine"

var _data: Dictionary = {}


## Deliberately returns `RefCounted`, not `LevelDefinition`: a script may not
## reference its own `class_name` before Godot's global class cache is warm, and
## `--headless --script` never warms it. Mirrors `ContentLibrary.create()`.
static func create(mission: Variant) -> RefCounted:
	var script: GDScript = load(SELF_PATH) as GDScript
	if script == null:
		return null
	var definition: RefCounted = script.new()
	definition.call("initialize", mission)
	return definition


func initialize(mission: Variant) -> void:
	if typeof(mission) == TYPE_DICTIONARY:
		_data = (mission as Dictionary).duplicate(true)
	else:
		_data = {}


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

func get_mission_id() -> String:
	return String(_data.get("missionId", ""))


## The stable id progression is keyed by. Falls back to `missionId` so an
## untagged mission is still addressable as a level.
func get_level_id() -> String:
	var level_id: String = String(_data.get("levelId", "")).strip_edges()
	if not level_id.is_empty():
		return level_id
	return get_mission_id()


func get_chapter_id() -> String:
	return String(_data.get("chapterId", "")).strip_edges()


func get_level_number() -> int:
	return _as_int(_data.get("levelNumber", 0))


## True when this mission has been explicitly promoted to a level (it carries
## both a `levelId` and a `chapterId`). False for a plain legacy mission.
func is_authored_level() -> bool:
	return not String(_data.get("levelId", "")).strip_edges().is_empty() \
		and not get_chapter_id().is_empty()


func is_empty() -> bool:
	return _data.is_empty()


# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------

## The child-facing level title. `levelTitle` exists because the level name and
## the historical mission name differ for three of the Chapter 2 levels (mission
## `feedingTime` is level "Milk Time"), and renaming `title` would not have been
## an additive change -- anything already reading the mission title must keep
## seeing the value it has always seen. Falls back to `title`.
func get_title() -> String:
	var level_title: String = String(_data.get("levelTitle", "")).strip_edges()
	if not level_title.is_empty():
		return level_title
	return get_mission_title()


func get_thai_title() -> String:
	var level_title: String = String(_data.get("levelThaiTitle", "")).strip_edges()
	if not level_title.is_empty():
		return level_title
	return get_mission_thai_title()


## The untouched mission-level strings, for anything that predates the level layer.
func get_mission_title() -> String:
	return String(_data.get("title", ""))


func get_mission_thai_title() -> String:
	return String(_data.get("thaiTitle", ""))


func get_story_beat() -> String:
	return String(_data.get("storyBeat", ""))


func get_category() -> String:
	return String(_data.get("category", ""))


func get_intro_phrase() -> String:
	return String(_data.get("introPhrase", ""))


func get_outro_phrase() -> String:
	return String(_data.get("outroPhrase", ""))


func get_template() -> String:
	var template: String = String(_data.get("template", "")).strip_edges()
	if template.is_empty():
		return DEFAULT_TEMPLATE
	return template


func has_known_template() -> bool:
	return TEMPLATES.has(get_template())


# ---------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------

## Authored task order, deduplicated. This is the answer to "which tasks belong
## to level X" -- the save migration uses it to seed old profiles.
func get_task_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	var raw: Variant = _data.get("taskIds", [])
	if typeof(raw) != TYPE_ARRAY:
		return ids
	for entry: Variant in (raw as Array):
		var task_id: String = String(entry).strip_edges()
		if task_id.is_empty() or ids.has(task_id):
			continue
		ids.append(task_id)
	return ids


func has_task(task_id: String) -> bool:
	return get_task_ids().has(task_id)


## The legacy star-count gate. Untouched by the level layer: anything still
## using `unlockAtStars` (stickers, the old mission list) keeps working.
func get_unlock_at_stars() -> int:
	return _as_int(_data.get("unlockAtStars", 0))


func has_authored_star_rules() -> bool:
	return typeof(_data.get("starRules", null)) == TYPE_DICTIONARY


## Canonical star rules for this level.
##
## Uses the authored `starRules` when present. Otherwise derives them: listening
## = the `findIt`/`sayIt` tasks, core = the rest, optional = none. Pass the
## level's resolved task dictionaries (`ContentLibrary.get_mission_tasks()`) to
## get the mode-aware derivation; with nothing passed, every task is core.
func get_star_rules(resolved_tasks: Array = []) -> Dictionary:
	var star_rules: GDScript = load(STAR_RULES_SCRIPT_PATH) as GDScript
	if star_rules == null:
		return {}
	if has_authored_star_rules():
		return star_rules.normalize(_data.get("starRules"))
	if not resolved_tasks.is_empty():
		return star_rules.derive_from_tasks(resolved_tasks)
	return star_rules.derive_from_task_ids(get_task_ids())


# ---------------------------------------------------------------------------
# Raw access
# ---------------------------------------------------------------------------

## The untouched mission record, for `MissionRunner` / `ContentLibrary`.
func get_mission() -> Dictionary:
	return _data.duplicate(true)


## A flat summary for the journey map / level-select UI.
func to_dictionary() -> Dictionary:
	return {
		"levelId": get_level_id(),
		"missionId": get_mission_id(),
		"chapterId": get_chapter_id(),
		"levelNumber": get_level_number(),
		"title": get_title(),
		"thaiTitle": get_thai_title(),
		"missionTitle": get_mission_title(),
		"storyBeat": get_story_beat(),
		"template": get_template(),
		"category": get_category(),
		"taskIds": get_task_ids(),
		"unlockAtStars": get_unlock_at_stars(),
		"isAuthoredLevel": is_authored_level(),
	}


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
