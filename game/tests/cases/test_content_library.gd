extends RefCounted

## Structural integrity of the whole bundled content set:
## everything parses, the validator is clean, ids are unique, and every
## mission -> task and task -> object reference resolves (no dead references).

const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const ContentValidatorScript := preload("res://scripts/content/content_validator.gd")


func test_name() -> String:
	return "content_library"


func run():
	var failures: Array = []

	# A compile error in a content script makes `new()` return null, and every
	# later call then aborts `run()` silently -- which the runner reports as a
	# PASS. Fail loudly instead.
	var library: Object = ContentLibraryScript.new()
	if library == null:
		return ["content_library.gd could not be instantiated"]

	library.load_all()

	# 1. Everything parses cleanly -- no missing or malformed files.
	for warning: Variant in library.get_load_warnings():
		failures.append("load warning: %s" % str(warning))

	if library.is_empty():
		failures.append("content library loaded nothing at all")
		return failures

	# 2. The validator reports zero problems (covers required keys, camelCase,
	#    empty acceptedCommands, non-int reward.stars, unknown modes, etc.).
	for problem: Variant in ContentValidatorScript.validate(library):
		failures.append("validator: %s" % str(problem))

	# 3. Ids are globally unique.
	failures.append_array(_check_unique(library.get_task_ids(), "taskId"))
	failures.append_array(_check_unique(library.get_object_ids(), "objectId"))
	failures.append_array(_check_unique(library.get_mission_ids(), "missionId"))
	failures.append_array(_check_unique(library.get_sticker_ids(), "stickerId"))
	failures.append_array(_check_unique(library.get_word_ids(), "wordId"))

	# 4. No dead references: task -> object.
	for task: Variant in library.get_tasks():
		var task_dict: Dictionary = task
		var task_id: String = String(task_dict.get("taskId", ""))
		var object_id: String = String(task_dict.get("objectId", ""))
		if not library.has_object(object_id):
			failures.append("task '%s' points at unknown objectId '%s'" % [task_id, object_id])

	# 5. No dead references: mission -> task (and order is preserved).
	for mission: Variant in library.get_missions():
		var mission_dict: Dictionary = mission
		var mission_id: String = String(mission_dict.get("missionId", ""))
		var task_ids: Array = mission_dict.get("taskIds", [])
		for entry: Variant in task_ids:
			if not library.has_task(String(entry)):
				failures.append("mission '%s' points at unknown taskId '%s'" % [mission_id, str(entry)])

		var resolved: Array = library.get_mission_tasks(mission_id)
		if resolved.size() != task_ids.size():
			failures.append(
				"mission '%s' resolved %d of %d tasks"
				% [mission_id, resolved.size(), task_ids.size()]
			)

	# 6. Every top-level key in every content record is camelCase.
	failures.append_array(_check_camel_case_keys(library.get_tasks(), "task"))
	failures.append_array(_check_camel_case_keys(library.get_objects(), "object"))
	failures.append_array(_check_camel_case_keys(library.get_missions(), "mission"))
	failures.append_array(_check_camel_case_keys(library.get_stickers(), "sticker"))
	failures.append_array(_check_camel_case_keys(library.get_words(), "word"))

	# 7. Getters return copies, so a consumer cannot corrupt the shared index.
	var tasks: Array = library.get_tasks()
	if not tasks.is_empty():
		var first_id: String = String((tasks[0] as Dictionary).get("taskId", ""))
		(tasks[0] as Dictionary)["taskId"] = "mutatedByCaller"
		if not library.has_task(first_id):
			failures.append("get_tasks() leaked a live reference into the index")

	# 8. A missing content index must degrade safely, never crash: it warns and
	#    falls back to the built-in category list rather than losing the game.
	var fallback_library: Object = ContentLibraryScript.new()
	fallback_library.load_all("res://content/__does_not_exist__.json")
	if typeof(fallback_library.get_tasks()) != TYPE_ARRAY:
		failures.append("missing index did not yield a safe task array")
	if not fallback_library.has_load_warnings():
		failures.append("missing index should have recorded a load warning")
	if not fallback_library.has_task("feedMilk"):
		failures.append("missing index should still fall back to the built-in categories")
	if not fallback_library.get_task("__does_not_exist__").is_empty():
		failures.append("unknown taskId must resolve to an empty dictionary")
	if not fallback_library.get_object("__does_not_exist__").is_empty():
		failures.append("unknown objectId must resolve to an empty dictionary")
	if not fallback_library.get_mission_tasks("__does_not_exist__").is_empty():
		failures.append("unknown missionId must resolve to an empty task list")

	# 9. The one-call convenience constructor works without the global class
	#    cache being warm (Wave 2 agents will use it).
	var created: Object = ContentLibraryScript.create()
	if created == null:
		failures.append("ContentLibrary.create() returned null")
	elif created.get_task_count() != library.get_task_count():
		failures.append("ContentLibrary.create() loaded a different task count")

	var summary: Dictionary = library.get_summary()
	for key: String in ["categories", "objects", "tasks", "missions", "stickers", "words", "phraseVariants"]:
		if not summary.has(key) or int(summary[key]) <= 0:
			failures.append("get_summary() reported nothing for '%s'" % key)

	return failures


func _check_unique(ids: PackedStringArray, label: String) -> Array:
	var failures: Array = []
	var seen: Dictionary = {}
	for id_text: String in ids:
		if id_text.is_empty():
			failures.append("found an empty %s" % label)
			continue
		if seen.has(id_text):
			failures.append("duplicate %s '%s'" % [label, id_text])
		seen[id_text] = true
	return failures


func _check_camel_case_keys(records: Array, label: String) -> Array:
	var failures: Array = []
	for record: Variant in records:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		for key: Variant in (record as Dictionary).keys():
			if not ContentValidatorScript.is_camel_case(String(key)):
				failures.append("%s has non-camelCase key '%s'" % [label, str(key)])
	return failures
