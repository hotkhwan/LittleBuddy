extends RefCounted

## Tests for ProfileStore. Uses a temp user:// path (never the real
## profile.json) and cleans up after itself. Does not depend on autoloads.

func test_name() -> String:
	return "profile_store"


func run() -> Array:
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


func _test_fresh_defaults(path: String) -> Array:
	var failures: Array = []
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if profile.get("profileVersion") != 1:
		failures.append("fresh load: expected profileVersion 1, got %s" % str(profile.get("profileVersion")))
	if profile.get("stars") != 0:
		failures.append("fresh load: expected stars 0, got %s" % str(profile.get("stars")))
	if typeof(profile.get("completedActivities")) != TYPE_ARRAY or profile["completedActivities"].size() != 0:
		failures.append("fresh load: expected empty completedActivities array")

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


func _test_round_trip(path: String) -> Array:
	var failures: Array = []
	var store := ProfileStore.new(path)
	var profile := store.default_profile()
	profile["stars"] = 7
	profile["completedActivities"] = ["feedMilk"]
	profile["settings"]["speechEnabled"] = false
	profile["settings"]["thaiHints"] = false
	profile["settings"]["speechLocale"] = "th-TH"

	if not store.save_profile(profile):
		failures.append("round trip: save_profile returned false")
		return failures

	var reload_store := ProfileStore.new(path)
	var reloaded := reload_store.load_profile()

	if reloaded.get("stars") != 7:
		failures.append("round trip: expected stars 7, got %s" % str(reloaded.get("stars")))
	if reloaded.get("completedActivities") != ["feedMilk"]:
		failures.append("round trip: expected completedActivities [feedMilk], got %s" % str(reloaded.get("completedActivities")))

	var settings: Dictionary = reloaded.get("settings", {})
	if settings.get("speechEnabled") != false:
		failures.append("round trip: expected speechEnabled false")
	if settings.get("thaiHints") != false:
		failures.append("round trip: expected thaiHints false")
	if settings.get("speechLocale") != "th-TH":
		failures.append("round trip: expected speechLocale th-TH")

	return failures


func _test_corrupt_json(path: String) -> Array:
	var failures: Array = []
	_write_raw(path, "{not json")
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if profile.get("stars") != 0 or profile.get("completedActivities") != []:
		failures.append("corrupt json: expected safe defaults, got %s" % str(profile))

	return failures


func _test_non_dictionary_json(path: String) -> Array:
	var failures: Array = []
	_write_raw(path, "[1, 2, 3]")
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if profile.get("stars") != 0:
		failures.append("non-dictionary json: expected default stars, got %s" % str(profile.get("stars")))
	if typeof(profile.get("settings")) != TYPE_DICTIONARY:
		failures.append("non-dictionary json: expected settings dictionary default")

	return failures


func _test_empty_file(path: String) -> Array:
	var failures: Array = []
	_write_raw(path, "")
	var store := ProfileStore.new(path)
	var profile := store.load_profile()

	if profile.get("stars") != 0:
		failures.append("empty file: expected default stars, got %s" % str(profile.get("stars")))

	return failures


func _test_partial_json(path: String) -> Array:
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


func _test_wrong_typed_values(path: String) -> Array:
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


func _test_duplicate_completed_activities(path: String) -> Array:
	var failures: Array = []
	_write_raw(path, "{\"completedActivities\": [\"feedMilk\", \"feedMilk\", \"feedMilk\"]}")
	var store := ProfileStore.new(path)
	var profile := store.load_profile()
	var completed: Array = profile.get("completedActivities", [])

	if completed.count("feedMilk") != 1:
		failures.append("duplicate completed activities: expected de-duplication, got %s" % str(completed))

	return failures
