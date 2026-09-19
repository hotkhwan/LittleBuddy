extends RefCounted

## The QA replay button must not be able to delete a child's progress.
##
## This is the whole reason `mission_replay.gd` is pure: the dangerous version of
## this feature (`reset_profile()`) and the safe version look identical from the
## outside -- both make the mission playable again -- and differ only in what
## ELSE they destroy. So the test is written as a blast radius: build a profile
## with a child's real progress in it, arm a replay, and check every key that
## must not have moved, by name.

const Replay := preload("res://scripts/qa/mission_replay.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const LevelSystemScript := preload("res://scripts/progression/level_system.gd")

const LEVEL: String = "imHungry"


func test_name() -> String:
	return "mission_replay"


func run():
	var failures: Array = []
	failures.append_array(_test_the_level_becomes_playable_again())
	failures.append_array(_test_nothing_else_moves())
	failures.append_array(_test_other_levels_survive())
	failures.append_array(_test_it_is_idempotent_and_safe_on_junk())
	failures.append_array(_test_the_button_targets_a_real_first_level())
	return failures


## A child who has played for a fortnight: stars, several finished levels,
## settings they chose, and unlocks they earned.
func _profile() -> Dictionary:
	return {
		"profileVersion": 1,
		"stars": 47,
		"completedActivities": ["feedMilk", "bathTime"],
		"currentLevel": "playTime",
		"levelCompleted": {LEVEL: true, "goodMorning": true, "gettingDressed": true},
		"starsByLevel": {LEVEL: 3, "goodMorning": 2, "gettingDressed": 3},
		"unlockedLevels": [LEVEL, "goodMorning", "gettingDressed", "breakfast"],
		"unlockedChapters": ["ch2", "ch3"],
		"unlockedRooms": ["bedroom", "bathroom", "kitchen"],
		"settings": {"speechLocale": "en-US", "speechEnabled": false, "thaiHints": true},
	}


func _test_the_level_becomes_playable_again():
	var failures: Array = []
	var after: Dictionary = Replay.armed(_profile(), LEVEL)
	if bool((after["levelCompleted"] as Dictionary).get(LEVEL, false)):
		failures.append("'%s' is still marked completed, so the director would skip it" % LEVEL)
	if (after["starsByLevel"] as Dictionary).has(LEVEL):
		failures.append("'%s' kept its old rating; a replay must be rated on its own merits" % LEVEL)
	if String(after.get("currentLevel", "")) != LEVEL:
		failures.append("the resume pointer is '%s', not '%s' -- the replay would not open"
				% [String(after.get("currentLevel", "")), LEVEL])
	return failures


func _test_nothing_else_moves():
	var failures: Array = []
	var before: Dictionary = _profile()
	var after: Dictionary = Replay.armed(before, LEVEL)

	# The one that matters most: a grown-up pressing a test button must never
	# cost a child the stars they collected.
	if int(after.get("stars", -1)) != int(before["stars"]):
		failures.append("the child's star total changed from %d to %d -- a QA button took a child's stars"
				% [int(before["stars"]), int(after.get("stars", -1))])

	for key: String in Replay.PROTECTED_KEYS:
		if not after.has(key):
			failures.append("protected key '%s' was dropped from the profile" % key)
		elif str(after[key]) != str(before[key]):
			failures.append("protected key '%s' changed: %s -> %s" % [key, str(before[key]), str(after[key])])

	# And no key may vanish, protected or not.
	for key: Variant in before.keys():
		if not after.has(key):
			failures.append("key '%s' disappeared from the profile" % str(key))

	# The input must not be mutated either -- a caller that decides not to save
	# has to still be holding the original.
	if not bool((before["levelCompleted"] as Dictionary).get(LEVEL, false)):
		failures.append("armed() mutated the profile it was handed")
	return failures


func _test_other_levels_survive():
	var failures: Array = []
	var after: Dictionary = Replay.armed(_profile(), LEVEL)
	var completed: Dictionary = after["levelCompleted"]
	var rated: Dictionary = after["starsByLevel"]
	for other: String in ["goodMorning", "gettingDressed"]:
		if not bool(completed.get(other, false)):
			failures.append("replaying '%s' un-completed '%s'" % [LEVEL, other])
		if int(rated.get(other, 0)) == 0:
			failures.append("replaying '%s' erased '%s' rating" % [LEVEL, other])
	return failures


func _test_it_is_idempotent_and_safe_on_junk():
	var failures: Array = []
	var once: Dictionary = Replay.armed(_profile(), LEVEL)
	var twice: Dictionary = Replay.armed(once, LEVEL)
	if str(once) != str(twice):
		failures.append("arming a replay twice is not the same as arming it once")

	# A corrupt or empty profile must not crash the panel.
	for junk: Variant in [null, {}, {"levelCompleted": "not a dictionary"}, 7]:
		var out: Dictionary = Replay.armed(junk, LEVEL)
		if typeof(out) != TYPE_DICTIONARY:
			failures.append("armed() returned a non-dictionary for %s" % str(junk))
	# An empty level id is a no-op, not a wipe.
	var untouched: Dictionary = Replay.armed(_profile(), "")
	if not bool((untouched["levelCompleted"] as Dictionary).get(LEVEL, false)):
		failures.append("an empty level id cleared something")
	return failures


## The button must point at a level that exists and is actually first -- the
## panel asks content for it, so this asserts content can answer.
func _test_the_button_targets_a_real_first_level():
	var failures: Array = []
	var library: Object = ContentLibraryScript.new()
	library.load_all()
	var system: Object = LevelSystemScript.new()
	system.load_all(library)
	var chain: PackedStringArray = system.get_chapter_chain("ch3")
	if chain.size() == 0:
		return ["chapter 3 chains no levels, so the QA button has nothing to target"]
	if String(chain[0]) != LEVEL:
		failures.append(("chapter 3 now opens with '%s', not '%s'. That is allowed, but this "
				+ "test and the QA button's label both name Mission 01 -- update them together.")
				% [String(chain[0]), LEVEL])
	if String(system.get_mission_id_for_level(String(chain[0]))).is_empty():
		failures.append("the first ch3 level maps to no mission, so replaying it opens nothing")
	return failures
