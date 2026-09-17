extends RefCounted

## `res://content/feeding/feed_milk.json` is consumed by the live, working
## iPhone build through `ActivityLoader.load_activity()`.
##
## Its original top-level keys and its six accepted phrases are a frozen
## contract: content may only ADD to this file. This case fails if anything is
## removed or renamed, and also checks the new `feedMilk` task stays consistent
## with it so scenes and content cannot drift apart.

const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const ContentValidatorScript := preload("res://scripts/content/content_validator.gd")

const FEED_MILK_PATH := "res://content/feeding/feed_milk.json"

const FROZEN_KEYS: Array[String] = [
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

const FROZEN_ACCEPTED_COMMANDS: Array[String] = [
	"milk",
	"give milk",
	"give baby milk",
	"give the baby milk",
	"give the baby some milk",
	"baby wants milk",
]


func test_name() -> String:
	return "content_legacy"


func run():
	var failures: Array = []

	# The validator owns the canonical contract check.
	for problem: Variant in ContentValidatorScript.validate_legacy_activity():
		failures.append(str(problem))

	var data: Dictionary = _read_json(FEED_MILK_PATH)
	if data.is_empty():
		failures.append("could not read %s" % FEED_MILK_PATH)
		return failures

	# Belt and braces: assert the frozen keys here too, independent of the
	# validator, so a validator regression cannot hide a content regression.
	for key: String in FROZEN_KEYS:
		if not data.has(key):
			failures.append("feed_milk.json lost frozen key '%s'" % key)

	var accepted: Variant = data.get("acceptedCommands", null)
	if typeof(accepted) != TYPE_ARRAY:
		failures.append("feed_milk.json acceptedCommands must be an array")
	else:
		var accepted_list: Array = accepted
		for phrase: String in FROZEN_ACCEPTED_COMMANDS:
			if not accepted_list.has(phrase):
				failures.append("feed_milk.json lost accepted phrase '%s'" % phrase)
		if accepted_list.size() < FROZEN_ACCEPTED_COMMANDS.size():
			failures.append(
				"feed_milk.json must keep all %d accepted phrases, has %d"
				% [FROZEN_ACCEPTED_COMMANDS.size(), accepted_list.size()]
			)

	if String(data.get("prompt", "")) != "I'm hungry.":
		failures.append("feed_milk.json prompt changed")
	if String(data.get("instruction", "")) != "Give the baby some milk.":
		failures.append("feed_milk.json instruction changed")
	if String(data.get("repeatPrompt", "")) != "Can you say milk?":
		failures.append("feed_milk.json repeatPrompt changed")
	if String(data.get("thankYouPhrase", "")) != "Thank you!":
		failures.append("feed_milk.json thankYouPhrase changed")

	var reward: Variant = data.get("reward", null)
	if typeof(reward) != TYPE_DICTIONARY or (reward as Dictionary).get("stars", 0) != 1:
		failures.append("feed_milk.json reward.stars must equal 1")

	# `ActivityLoader` must still resolve the file to the live activity.
	var loaded: Dictionary = ActivityLoader.load_activity(FEED_MILK_PATH)
	if String(loaded.get("activityId", "")) != "feedMilk":
		failures.append("ActivityLoader no longer resolves feed_milk.json to 'feedMilk'")
	if String(loaded.get("prompt", "")) != "I'm hungry.":
		failures.append("ActivityLoader returned an unexpected prompt")

	# The new task index must agree with the legacy file, or the room scene and
	# the mission system would teach two different things.
	var library: Object = ContentLibraryScript.new()
	library.load_all()
	var task: Dictionary = library.get_task("feedMilk")
	if task.is_empty():
		failures.append("task index is missing 'feedMilk'")
	else:
		for key: String in ["prompt", "instruction", "repeatPrompt", "category", "thaiHint"]:
			if String(task.get(key, "")) != String(data.get(key, "")):
				failures.append("task 'feedMilk' %s differs from feed_milk.json" % key)
		var task_accepted: Array = task.get("acceptedCommands", [])
		for phrase: String in FROZEN_ACCEPTED_COMMANDS:
			if not task_accepted.has(phrase):
				failures.append("task 'feedMilk' is missing accepted phrase '%s'" % phrase)
		if String(task.get("objectId", "")) != "milk":
			failures.append("task 'feedMilk' must use objectId 'milk'")
		if String(task.get("interaction", "")) != "dragToMouth":
			failures.append("task 'feedMilk' must use interaction 'dragToMouth'")

	# `feedMilk` must appear exactly once in the task index, not twice via the
	# legacy file being indexed as well.
	var feed_milk_count: int = 0
	for indexed: Variant in library.get_tasks():
		if String((indexed as Dictionary).get("taskId", "")) == "feedMilk":
			feed_milk_count += 1
	if feed_milk_count != 1:
		failures.append("'feedMilk' appears %d times in the task index, expected 1" % feed_milk_count)

	return failures


func _read_json(path: String) -> Dictionary:
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
