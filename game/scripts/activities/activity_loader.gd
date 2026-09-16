class_name ActivityLoader
extends RefCounted

## Loads activity definitions from bundled JSON content.
## Always returns a safe, complete Dictionary even if the content file is
## missing or malformed, so gameplay never depends on the content agent's
## file existing yet.

const DEFAULT_PATH: String = "res://content/feeding/feed_milk.json"


static func _default_activity() -> Dictionary:
	return {
		"activityId": "feedMilk",
		"category": "feeding",
		"prompt": "I'm hungry.",
		"instruction": "Give the baby some milk.",
		"repeatPrompt": "Can you say milk?",
		"targetWords": ["milk"],
		"acceptedCommands": [
			"milk",
			"give milk",
			"give baby milk",
			"give the baby milk",
			"give the baby some milk",
			"baby wants milk",
		],
		"reward": {"stars": 1},
	}


## Returns true if `data` looks like a usable activity dictionary.
static func _is_valid(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("activityId") or not data.has("prompt"):
		return false
	return true


static func load_activity(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _default_activity()

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _default_activity()

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not _is_valid(parsed):
		return _default_activity()

	var result: Dictionary = _default_activity()
	for key: String in (parsed as Dictionary).keys():
		result[key] = parsed[key]

	return result
