extends RefCounted

## Tests for ProfileStore. Uses a temp user:// path (never the real
## profile.json) and cleans up after itself. Does not depend on autoloads.

func test_name() -> String:
	return "profile_store"


func run():
	var failures: Array = []
	var test_path := "user://test_profile_%d.json" % randi()

	_cleanup(test_path)
	failures.append_array(_test_fresh_defaults(test_path))

	_cleanup(test_path)
	failures.append_array(_test_round_trip(test_path))

	_cleanup(test_path)
	failures.append_array(_test_corrupt_json(test_path))

	_cleanup(test_path)
	failures.append_array(_test_non_dictionary_json(test_path))

	_cleanup(test_path)
	failures.append_array(_test_empty_file(test_path))

	_cleanup(test_path)
	failures.append_array(_test_partial_json(test_path))

	_cleanup(test_path)
	failures.append_array(_test_wrong_typed_values(test_path))

	_cleanup(test_path)
	failures.append_array(_test_duplicate_completed_activities(test_path))

	_cleanup(test_path)
	failures.append_array(_test_wrong_typed_v2_fields(test_path))

	_cleanup(test_path)
	failures.append_array(_test_wrong_typed_completion_map(test_path))

	_cleanup(test_path)
	return failures


func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var tmp_path := path + ".tmp"
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _test_fresh_defaults(path: String):
	var failures: Array = []
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if profile.get("profileVersion") != 4:
		failures.append("fresh load: expected profileVersion 4, got %s" % str(profile.get("profileVersion")))
	if String(profile.get("currentRoomId", "")) != "bedroom":
		failures.append("fresh load: expected currentRoomId 'bedroom', got %s"
				% str(profile.get("currentRoomId")))
	if String(profile.get("currentSpawnId", "")) != "default":
		failures.append("fresh load: expected currentSpawnId 'default', got %s"
				% str(profile.get("currentSpawnId")))
	var fresh_settings: Dictionary = profile.get("settings", {})
	if fresh_settings.has("worldState"):
		failures.append("fresh load: a v4 profile must not carry the v3 settings.worldState key; "
				+ "the compatibility mirror is preserved when present, never synthesised")
	if profile.get("stars") != 0:
		failures.append("fresh load: expected stars 0, got %s" % str(profile.get("stars")))
	if typeof(profile.get("completedActivities")) != TYPE_ARRAY or profile["completedActivities"].size() != 0:
		failures.append("fresh load: expected empty completedActivities array")

	if String(profile.get("currentChapter", "")) != "ch1":
		failures.append("fresh load: expected currentChapter 'ch1', got %s" % str(profile.get("currentChapter")))
	if String(profile.get("currentLevel", "MISSING")) != "":
		failures.append("fresh load: expected currentLevel '', got %s" % str(profile.get("currentLevel")))
	if typeof(profile.get("starsByLevel")) != TYPE_DICTIONARY or not profile["starsByLevel"].is_empty():
		failures.append("fresh load: expected empty starsByLevel dictionary")
	if typeof(profile.get("levelCompleted")) != TYPE_DICTIONARY or not profile["levelCompleted"].is_empty():
		failures.append("fresh load: expected empty levelCompleted dictionary, got %s"
				% str(profile.get("levelCompleted")))
	if typeof(profile.get("unlockedChapters")) != TYPE_ARRAY or profile["unlockedChapters"] != ["ch1"]:
		failures.append("fresh load: expected unlockedChapters == ['ch1'], got %s" % str(profile.get("unlockedChapters")))
	if typeof(profile.get("unlockedLevels")) != TYPE_ARRAY or not profile["unlockedLevels"].is_empty():
		failures.append("fresh load: expected empty unlockedLevels array")
	if typeof(profile.get("unlockedRooms")) != TYPE_ARRAY or not profile["unlockedRooms"].is_empty():
		failures.append("fresh load: expected empty unlockedRooms array")

	var settings = profile.get("settings")
	if typeof(settings) != TYPE_DICTIONARY:
		failures.append("fresh load: expected settings dictionary")
	else:
		if settings.get("speechLocale") != "en-US":
			failures.append("fresh load: expected speechLocale en-US")
		if settings.get("speechEnabled") != true:
			failures.append("fresh load: expected speechEnabled true")
		if settings.get("thaiHints") != true:
			failures.append("fresh load: expected thaiHints true")

	return failures


func _test_round_trip(path: String):
	var failures: Array = []
	var store := ProfileStore.new(path)
	var profile := store.default_profile()
	profile["stars"] = 7
	profile["completedActivities"] = ["feedMilk"]
	profile["settings"]["speechEnabled"] = false
	profile["settings"]["thaiHints"] = false
	profile["settings"]["speechLocale"] = "th-TH"
	profile["currentChapter"] = "ch2"
	profile["currentLevel"] = "milkTime"
	profile["starsByLevel"] = {"milkTime": 2}
	profile["unlockedChapters"] = ["ch1", "ch2"]
	profile["unlockedLevels"] = ["milkTime"]
	profile["unlockedRooms"] = ["nursery"]

	if not store.save_profile(profile):
		failures.append("round trip: save_profile returned false")
		return failures

	var reload_store := ProfileStore.new(path)
	var reloaded := reload_store.load_profile()

	if reloaded.get("stars") != 7:
		failures.append("round trip: expected stars 7, got %s" % str(reloaded.get("stars")))
	if reloaded.get("completedActivities") != ["feedMilk"]:
		failures.append("round trip: expected completedActivities [feedMilk], got %s" % str(reloaded.get("completedActivities")))
	if String(reloaded.get("currentChapter", "")) != "ch2":
		failures.append("round trip: expected currentChapter 'ch2', got %s" % str(reloaded.get("currentChapter")))
	if String(reloaded.get("currentLevel", "")) != "milkTime":
		failures.append("round trip: expected currentLevel 'milkTime', got %s" % str(reloaded.get("currentLevel")))
	var stars_by_level: Dictionary = reloaded.get("starsByLevel", {})
	if int(stars_by_level.get("milkTime", -1)) != 2:
		failures.append("round trip: expected starsByLevel.milkTime == 2, got %s" % str(stars_by_level.get("milkTime")))
	if reloaded.get("unlockedChapters") != ["ch1", "ch2"]:
		failures.append("round trip: expected unlockedChapters ['ch1','ch2'], got %s" % str(reloaded.get("unlockedChapters")))
	if reloaded.get("unlockedLevels") != ["milkTime"]:
		failures.append("round trip: expected unlockedLevels ['milkTime'], got %s" % str(reloaded.get("unlockedLevels")))
	if reloaded.get("unlockedRooms") != ["nursery"]:
		failures.append("round trip: expected unlockedRooms ['nursery'], got %s" % str(reloaded.get("unlockedRooms")))

	var settings: Dictionary = reloaded.get("settings", {})
	if settings.get("speechEnabled") != false:
		failures.append("round trip: expected speechEnabled false")
	if settings.get("thaiHints") != false:
		failures.append("round trip: expected thaiHints false")
	if settings.get("speechLocale") != "th-TH":
		failures.append("round trip: expected speechLocale th-TH")

	return failures


func _test_corrupt_json(path: String):
	var failures: Array = []
	_write_raw(path, "{not json")
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if profile.get("stars") != 0 or profile.get("completedActivities") != []:
		failures.append("corrupt json: expected safe defaults, got %s" % str(profile))

	return failures


func _test_non_dictionary_json(path: String):
	var failures: Array = []
	_write_raw(path, "[1, 2, 3]")
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if profile.get("stars") != 0:
		failures.append("non-dictionary json: expected default stars, got %s" % str(profile.get("stars")))
	if typeof(profile.get("settings")) != TYPE_DICTIONARY:
		failures.append("non-dictionary json: expected settings dictionary default")

	return failures


func _test_empty_file(path: String):
	var failures: Array = []
	_write_raw(path, "")
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if profile.get("stars") != 0:
		failures.append("empty file: expected default stars, got %s" % str(profile.get("stars")))

	return failures


func _test_partial_json(path: String):
	var failures: Array = []
	_write_raw(path, "{\"stars\": 5}")
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if profile.get("stars") != 5:
		failures.append("partial json: expected stars preserved as 5, got %s" % str(profile.get("stars")))
	if typeof(profile.get("completedActivities")) != TYPE_ARRAY:
		failures.append("partial json: expected completedActivities filled with default array")

	var settings = profile.get("settings")
	if typeof(settings) != TYPE_DICTIONARY or settings.get("speechLocale") != "en-US":
		failures.append("partial json: expected settings filled with defaults")

	return failures


func _test_wrong_typed_values(path: String):
	var failures: Array = []
	var raw := "{\"stars\": \"five\", \"completedActivities\": \"nope\", \"settings\": {\"speechEnabled\": \"yes\", \"thaiHints\": true}}"
	_write_raw(path, raw)
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if typeof(profile.get("stars")) != TYPE_INT or int(profile.get("stars")) < 0:
		failures.append("wrong typed values: expected stars coerced to safe non-negative int, got %s" % str(profile.get("stars")))
	if typeof(profile.get("completedActivities")) != TYPE_ARRAY:
		failures.append("wrong typed values: expected completedActivities replaced with array")

	var settings: Dictionary = profile.get("settings", {})
	if typeof(settings.get("speechEnabled")) != TYPE_BOOL:
		failures.append("wrong typed values: expected speechEnabled coerced to bool default")
	if settings.get("thaiHints") != true:
		failures.append("wrong typed values: expected valid thaiHints preserved")

	_cleanup(path)
	_write_raw(path, "{\"stars\": -10}")
	var negative_store := ProfileStore.new(path)
	var negative_profile := negative_store.load_profile()
	if negative_profile.get("stars") != 0:
		failures.append("wrong typed values: expected negative stars replaced with default 0, got %s" % str(negative_profile.get("stars")))

	return failures


func _test_duplicate_completed_activities(path: String):
	var failures: Array = []
	_write_raw(path, "{\"completedActivities\": [\"feedMilk\", \"feedMilk\", \"feedMilk\"]}")
	var store := ProfileStore.new(path)
	var profile := store.load_profile()
	var completed: Array = profile.get("completedActivities", [])

	if completed.count("feedMilk") != 1:
		failures.append("duplicate completed activities: expected de-duplication, got %s" % str(completed))

	return failures


## Corruption coverage for the schema-v2 fields, mirroring the same
## never-crash, safe-defaults contract the v1 fields already have. Wrong key
## or value types are dropped individually rather than discarding the whole
## profile; out-of-range starsByLevel values are clamped to 0..3.
func _test_wrong_typed_v2_fields(path: String):
	var failures: Array = []
	var raw := JSON.stringify({
		"profileVersion": 2,
		"currentChapter": 7,
		"currentLevel": null,
		"starsByLevel": {"milkTime": 99, "bathTime": -5, "badKey": "nope", "invalidValue": {"nested": 1}, "goodLevel": 2},
		"unlockedChapters": "not an array",
		"unlockedLevels": [1, 2, "milkTime", "milkTime"],
		"unlockedRooms": {"not": "an array"},
	})
	_write_raw(path, raw)
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if typeof(profile.get("currentChapter")) != TYPE_STRING:
		failures.append("wrong typed v2 fields: expected currentChapter coerced to a string default")
	if typeof(profile.get("currentLevel")) != TYPE_STRING:
		failures.append("wrong typed v2 fields: expected currentLevel coerced to a string default")

	var stars_by_level: Dictionary = profile.get("starsByLevel", {})
	if int(stars_by_level.get("milkTime", -1)) != 3:
		failures.append("wrong typed v2 fields: expected out-of-range 99 clamped to 3, got %s" % str(stars_by_level.get("milkTime")))
	if int(stars_by_level.get("bathTime", -1)) != 0:
		failures.append("wrong typed v2 fields: expected out-of-range -5 clamped to 0, got %s" % str(stars_by_level.get("bathTime")))
	if stars_by_level.has("badKey"):
		failures.append("wrong typed v2 fields: expected non-numeric starsByLevel value dropped, got %s" % str(stars_by_level))
	if int(stars_by_level.get("goodLevel", -1)) != 2:
		failures.append("wrong typed v2 fields: expected a valid sibling entry preserved, got %s" % str(stars_by_level))

	if typeof(profile.get("unlockedChapters")) != TYPE_ARRAY or not profile["unlockedChapters"].is_empty():
		failures.append("wrong typed v2 fields: expected unlockedChapters replaced with an empty array default")

	var unlocked_levels: Array = profile.get("unlockedLevels", [])
	if unlocked_levels.count("milkTime") != 1:
		failures.append("wrong typed v2 fields: expected non-string entries dropped and 'milkTime' de-duplicated, got %s" % str(unlocked_levels))

	if typeof(profile.get("unlockedRooms")) != TYPE_ARRAY or not profile["unlockedRooms"].is_empty():
		failures.append("wrong typed v2 fields: expected unlockedRooms replaced with an empty array default")

	return failures


## Corruption coverage for the schema-v3 `levelCompleted` map. It gates
## unlocking, so a malformed entry must never be read as "completed" (which
## would skip a child forward) and a valid sibling must never be lost (which
## would lock a child out of progress they already have).
func _test_wrong_typed_completion_map(path: String):
	var failures: Array = []
	var raw := JSON.stringify({
		"profileVersion": 3,
		"levelCompleted": {
			"milkTime": true,
			"bathTime": false,
			"bedtime": "yes",
			"toysAndSmiles": {"nested": true},
			"firstWords": 1,
		},
	})
	_write_raw(path, raw)
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	var completed: Dictionary = profile.get("levelCompleted", {})
	if not bool(completed.get("milkTime", false)):
		failures.append("levelCompleted: a genuine completion was lost, got %s" % str(completed))
	if completed.has("bathTime"):
		failures.append("levelCompleted: a stored `false` must not survive as a key, got %s" % str(completed))
	for level_id: String in ["bedtime", "toysAndSmiles"]:
		if completed.has(level_id):
			failures.append("levelCompleted: wrong-typed entry '%s' was read as completed, got %s"
					% [level_id, str(completed)])
	if not bool(completed.get("firstWords", false)):
		failures.append("levelCompleted: a numeric 1 should still read as completed, got %s" % str(completed))

	return failures
