extends RefCounted
## `LevelDefinition` -- the thin level view over a mission record.
##
## The design bet is that a mission already IS a level, so the level layer is
## six additive fields rather than a parallel `levels.json`. Two things have to
## stay true for that bet to pay off, and both are asserted here:
##
##   1. a mission WITHOUT the new fields still loads and still rates (the seven
##      shipped missions must keep working);
##   2. the original mission record is never mutated, so `MissionRunner` and
##      `ContentLibrary` keep seeing exactly what they saw before.

const LevelDefinitionScript := preload("res://scripts/progression/level_definition.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")

## A mission exactly as it was authored before the level layer existed.
const LEGACY_MISSION: Dictionary = {
	"missionId": "legacyThing",
	"title": "Legacy Thing",
	"thaiTitle": "ของเก่า",
	"category": "feeding",
	"introPhrase": "Hello!",
	"outroPhrase": "Bye!",
	"unlockAtStars": 12,
	"taskIds": ["feedMilk", "findBowl", "sayMilk"],
}


func test_name() -> String:
	return "level_definition"


func run():
	var failures: Array = []
	failures.append_array(_test_authored_level())
	failures.append_array(_test_legacy_mission_still_works())
	failures.append_array(_test_malformed_input())
	failures.append_array(_test_does_not_mutate_the_mission())
	failures.append_array(_test_shipped_templates())
	return failures


func _test_authored_level():
	var failures: Array = []

	var mission: Dictionary = {
		"missionId": "feedingTime",
		"title": "Feeding Time",
		"thaiTitle": "เวลาอาหาร",
		"category": "feeding",
		"introPhrase": "I'm hungry!",
		"outroPhrase": "Thank you!",
		"unlockAtStars": 0,
		"taskIds": ["feedMilk", " feedWater ", "feedMilk", ""],
		"chapterId": "ch2",
		"levelId": "milkTime",
		"levelNumber": 6,
		"storyBeat": "Buddy is hungry.",
		"template": "fetchAndGive",
		"starRules": {"coreTaskIds": ["feedMilk"], "listeningTaskIds": ["feedWater"]},
	}

	var level: RefCounted = LevelDefinitionScript.create(mission)
	if level == null:
		return ["LevelDefinition.create() returned null"]

	failures.append_array(_expect(level.get_level_id(), "milkTime", "levelId"))
	failures.append_array(_expect(level.get_mission_id(), "feedingTime", "missionId"))
	failures.append_array(_expect(level.get_chapter_id(), "ch2", "chapterId"))
	failures.append_array(_expect(level.get_level_number(), 6, "levelNumber"))
	failures.append_array(_expect(level.get_template(), "fetchAndGive", "template"))
	failures.append_array(_expect(level.get_story_beat(), "Buddy is hungry.", "storyBeat"))
	failures.append_array(_expect(level.get_title(), "Feeding Time", "title"))
	failures.append_array(_expect(level.get_unlock_at_stars(), 0, "unlockAtStars"))

	if not level.is_authored_level():
		failures.append("a mission with levelId + chapterId must count as an authored level")
	if not level.has_authored_star_rules():
		failures.append("authored starRules were not detected")
	if not level.has_known_template():
		failures.append("'fetchAndGive' must be one of the six known templates")

	# taskIds are trimmed and deduplicated, and blanks dropped.
	var task_ids: PackedStringArray = level.get_task_ids()
	if task_ids.size() != 2 or task_ids[0] != "feedMilk" or task_ids[1] != "feedWater":
		failures.append("get_task_ids() should trim/dedupe/drop blanks, got %s" % str(task_ids))
	if not level.has_task("feedWater"):
		failures.append("has_task() should find a trimmed task id")

	var rules: Dictionary = level.get_star_rules()
	if not _list_equals(rules.get("coreTaskIds", []), ["feedMilk"]):
		failures.append("authored core rules should win over derivation, got %s" % str(rules))

	return failures


func _test_legacy_mission_still_works():
	var failures: Array = []

	var level: RefCounted = LevelDefinitionScript.create(LEGACY_MISSION)
	if level == null:
		return ["LevelDefinition.create() returned null for a legacy mission"]

	# The whole point: an untagged mission is still a usable level.
	failures.append_array(_expect(level.get_level_id(), "legacyThing", "legacy levelId falls back to missionId"))
	failures.append_array(_expect(level.get_chapter_id(), "", "legacy chapterId"))
	failures.append_array(_expect(level.get_level_number(), 0, "legacy levelNumber"))
	failures.append_array(_expect(level.get_template(), "sequenceRoutine", "legacy template default"))
	failures.append_array(_expect(level.get_unlock_at_stars(), 12, "legacy unlockAtStars is preserved"))

	if level.is_authored_level():
		failures.append("an untagged mission must NOT be treated as an authored level")
	if level.has_authored_star_rules():
		failures.append("an untagged mission must not claim authored star rules")

	# With task modes available, rules are derived: findIt/sayIt are listening.
	var resolved: Array = [
		{"taskId": "feedMilk", "mode": "followInstruction"},
		{"taskId": "findBowl", "mode": "findIt"},
		{"taskId": "sayMilk", "mode": "sayIt"},
	]
	var derived: Dictionary = level.get_star_rules(resolved)
	if not _list_equals(derived.get("coreTaskIds", []), ["feedMilk"]):
		failures.append("derived core should be the non-listening tasks, got %s" % str(derived))
	if not _list_equals(derived.get("listeningTaskIds", []), ["findBowl", "sayMilk"]):
		failures.append("derived listening should be findIt+sayIt, got %s" % str(derived))

	# With no modes available, everything is core -- still rateable, never crashy.
	var blind: Dictionary = level.get_star_rules()
	if not _list_equals(blind.get("coreTaskIds", []), ["feedMilk", "findBowl", "sayMilk"]):
		failures.append("without task modes every task should be core, got %s" % str(blind))

	return failures


func _test_malformed_input():
	var failures: Array = []

	for junk: Variant in [null, 42, "mission", []]:
		var level: RefCounted = LevelDefinitionScript.create(junk)
		if level == null:
			failures.append("create(%s) must not return null" % str(junk))
			continue
		if not level.is_empty():
			failures.append("create(%s) should produce an empty definition" % str(junk))
		if level.get_level_id() != "":
			failures.append("create(%s) should have no level id" % str(junk))
		if not level.get_task_ids().is_empty():
			failures.append("create(%s) should have no tasks" % str(junk))
		if level.get_template() != "sequenceRoutine":
			failures.append("create(%s) should still report the default template" % str(junk))

	var broken: RefCounted = LevelDefinitionScript.create({"missionId": "x", "taskIds": "not-an-array"})
	if not broken.get_task_ids().is_empty():
		failures.append("a non-array taskIds must degrade to an empty list, not crash")

	return failures


func _test_does_not_mutate_the_mission():
	var failures: Array = []

	var mission: Dictionary = LEGACY_MISSION.duplicate(true)
	var level: RefCounted = LevelDefinitionScript.create(mission)

	var copy: Dictionary = level.get_mission()
	copy["title"] = "tampered"
	(copy["taskIds"] as Array).append("ghostTask")

	if level.get_title() == "tampered":
		failures.append("get_mission() leaked a live reference into the definition")
	if level.get_task_ids().size() != 3:
		failures.append("mutating the returned mission changed the definition's tasks")
	if String(mission.get("title", "")) != "Legacy Thing":
		failures.append("LevelDefinition mutated the mission dictionary it was given")

	return failures


## Every shipped level must name one of the six templates from LEVEL_MATRIX.md.
func _test_shipped_templates():
	var failures: Array = []

	var library: RefCounted = ContentLibraryScript.create()
	if library == null:
		return ["could not load the content library"]

	for mission: Variant in library.get_missions():
		var level: RefCounted = LevelDefinitionScript.create(mission)
		if not level.has_known_template():
			failures.append(
				"level '%s' uses unknown template '%s' (known: %s)"
				% [level.get_level_id(), level.get_template(), str(LevelDefinitionScript.TEMPLATES)]
			)

	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _expect(actual: Variant, expected: Variant, label: String) -> Array:
	if str(actual) != str(expected):
		return ["%s: expected '%s', got '%s'" % [label, str(expected), str(actual)]]
	return []


static func _list_equals(actual: Variant, expected: Array) -> bool:
	if typeof(actual) != TYPE_ARRAY:
		return false
	var list: Array = actual
	if list.size() != expected.size():
		return false
	for i: int in range(expected.size()):
		if String(list[i]) != String(expected[i]):
			return false
	return true
