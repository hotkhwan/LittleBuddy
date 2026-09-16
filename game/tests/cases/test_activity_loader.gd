extends RefCounted


func test_name() -> String:
	return "activity_loader"


func run() -> Array:
	var failures: Array = []

	# Force the "missing/malformed file" fallback path deterministically —
	# this must never depend on the content agent's file actually existing.
	var data: Dictionary = ActivityLoader.load_activity("res://content/feeding/__does_not_exist__.json")

	if not data.has("activityId") or String(data.get("activityId", "")) != "feedMilk":
		failures.append("expected default activityId 'feedMilk', got %s" % data.get("activityId"))

	if not data.has("prompt") or String(data.get("prompt", "")).is_empty():
		failures.append("expected a non-empty default prompt")

	if not data.has("repeatPrompt") or String(data.get("repeatPrompt", "")).is_empty():
		failures.append("expected a non-empty default repeatPrompt")

	if not data.has("instruction"):
		failures.append("expected default data to include an instruction field")

	var target_words: Array = data.get("targetWords", [])
	if not target_words.has("milk"):
		failures.append("expected default targetWords to include 'milk'")

	var accepted: Array = data.get("acceptedCommands", [])
	var expected_commands: Array = [
		"milk",
		"give milk",
		"give baby milk",
		"give the baby milk",
		"give the baby some milk",
		"baby wants milk",
	]
	for command: String in expected_commands:
		if not accepted.has(command):
			failures.append("expected acceptedCommands to include '%s'" % command)

	var reward: Dictionary = data.get("reward", {})
	if int(reward.get("stars", 0)) != 1:
		failures.append("expected default reward.stars == 1, got %s" % reward.get("stars"))

	# Loading with the default argument must never crash even if the content
	# file is missing or malformed; it should always return a valid Dictionary.
	var default_call: Dictionary = ActivityLoader.load_activity()
	if not default_call.has("activityId"):
		failures.append("expected load_activity() with default path to return a valid dictionary")

	return failures
