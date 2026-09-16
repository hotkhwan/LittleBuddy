extends RefCounted


func test_name() -> String:
	return "intent_matcher"


func run() -> Array:
	var failures: Array = []

	const ACCEPTED_COMMANDS := [
		"milk",
		"give milk",
		"give baby milk",
		"give the baby milk",
		"give the baby some milk",
		"baby wants milk",
	]
	const TARGET_WORDS := ["milk"]

	# normalize()
	if IntentMatcher.normalize("  Give the baby some MILK!  ") != "give the baby some milk":
		failures.append("normalize() did not lowercase/strip/collapse/trim as expected")

	if IntentMatcher.normalize("") != "":
		failures.append("normalize('') should return ''")

	if IntentMatcher.normalize("Milk?!") != "milk":
		failures.append("normalize() did not strip trailing punctuation")

	# All six spec phrases must resolve to feedMilk via matches().
	for phrase in ACCEPTED_COMMANDS:
		if not IntentMatcher.matches(phrase, ACCEPTED_COMMANDS, TARGET_WORDS):
			failures.append("expected accepted phrase to match: '%s'" % phrase)

	# Case/punctuation variants.
	var variants := [
		"Give the baby some MILK!",
		"MILK.",
		"  milk  ",
		"Milk, please?",
		"Can I have some milk?",
	]
	for variant in variants:
		if not IntentMatcher.matches(variant, ACCEPTED_COMMANDS, TARGET_WORDS):
			failures.append("expected variant to match: '%s'" % variant)

	# Unrelated phrase must not match.
	if IntentMatcher.matches("banana", ACCEPTED_COMMANDS, TARGET_WORDS):
		failures.append("'banana' should not match milk phrases")

	if IntentMatcher.matches("I want to play outside", ACCEPTED_COMMANDS, TARGET_WORDS):
		failures.append("unrelated sentence should not match milk phrases")

	# Empty/null-ish input must not match or crash.
	if IntentMatcher.matches("", ACCEPTED_COMMANDS, TARGET_WORDS):
		failures.append("empty transcript should not match")

	if IntentMatcher.matches("milk", [], []):
		failures.append("empty accepted/target lists should not match anything")

	# match_activity_id()
	var activities := [
		{
			"activityId": "feedMilk",
			"acceptedCommands": ACCEPTED_COMMANDS,
			"targetWords": TARGET_WORDS,
		},
	]

	if IntentMatcher.match_activity_id("Give the baby some MILK!", activities) != "feedMilk":
		failures.append("match_activity_id() should resolve normalized phrase to feedMilk")

	if IntentMatcher.match_activity_id("banana", activities) != "":
		failures.append("match_activity_id() should return '' for unrelated phrase")

	if IntentMatcher.match_activity_id("", activities) != "":
		failures.append("match_activity_id() should return '' for empty transcript")

	if IntentMatcher.match_activity_id("milk", []) != "":
		failures.append("match_activity_id() should return '' when there are no activities")

	return failures
