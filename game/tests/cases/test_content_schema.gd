extends RefCounted

const FEED_MILK_PATH := "res://content/feeding/feed_milk.json"

const REQUIRED_KEYS := [
	"activityId",
	"category",
	"prompt",
	"instruction",
	"repeatPrompt",
	"targetWords",
	"acceptedCommands",
	"reward",
]

const REQUIRED_ACCEPTED_COMMANDS := [
	"milk",
	"give milk",
	"give baby milk",
	"give the baby milk",
	"give the baby some milk",
	"baby wants milk",
]

func test_name() -> String:
	return "content_schema"

func run():
	var failures: Array = []

	if not FileAccess.file_exists(FEED_MILK_PATH):
		failures.append("Missing file: %s" % FEED_MILK_PATH)
		return failures

	var file := FileAccess.open(FEED_MILK_PATH, FileAccess.READ)
	if file == null:
		failures.append("Could not open file: %s" % FEED_MILK_PATH)
		return failures

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		failures.append("Failed to parse valid JSON object from: %s" % FEED_MILK_PATH)
		return failures

	var data: Dictionary = parsed

	for key in REQUIRED_KEYS:
		if not data.has(key):
			failures.append("Missing required key: %s" % key)

	if data.has("activityId") and data["activityId"] != "feedMilk":
		failures.append("activityId expected 'feedMilk', got: %s" % str(data.get("activityId")))

	if data.has("acceptedCommands"):
		var accepted = data["acceptedCommands"]
		if typeof(accepted) != TYPE_ARRAY:
			failures.append("acceptedCommands must be an array")
		else:
			for phrase in REQUIRED_ACCEPTED_COMMANDS:
				if not accepted.has(phrase):
					failures.append("acceptedCommands missing required phrase: %s" % phrase)

	if data.has("reward"):
		var reward = data["reward"]
		if typeof(reward) != TYPE_DICTIONARY or not reward.has("stars") or reward["stars"] != 1:
			failures.append("reward.stars must equal 1")

	for key in data.keys():
		if _is_snake_case(key):
			failures.append("Top-level key must be camelCase, found snake_case: %s" % key)

	return failures

func _is_snake_case(key: String) -> bool:
	return key.find("_") != -1
