extends RefCounted

## The TutorTurn validator against the shared fixture file, plus the rules the
## fixtures exercise one by one. `content/tutor/turn_fixtures.json` is the same
## truth table the backend's `turn_validator.js` runs, so a rule that drifts on
## either side goes red here or there -- never silently on both.

const Turn := preload("res://scripts/tutor/turn/tutor_turn.gd")


func test_name() -> String:
	return "tutor_turn"


func run():
	var failures: Array = []
	failures.append_array(_test_fixture_truth_table())
	failures.append_array(_test_fallback_is_the_contracts())
	failures.append_array(_test_normalisation())
	failures.append_array(_test_make_is_always_valid())
	failures.append_array(_test_allowlist())
	return failures


func _test_fixture_truth_table():
	var failures: Array = []
	var cases: Array = Turn.load_fixtures()
	if cases.size() < 12:
		failures.append("turn_fixtures.json holds %d cases; the contract asks for at least 12" % cases.size())
		return failures
	var valid_count: int = 0
	var invalid_count: int = 0
	for entry in cases:
		var fixture: Dictionary = entry
		var id: String = String(fixture.get("id", "?"))
		var expected: bool = bool(fixture.get("valid", false))
		var report: Dictionary = Turn.validate(fixture.get("turn", null))
		if bool(report["valid"]) != expected:
			failures.append("fixture '%s': expected valid=%s, got %s (%s)" % [id, expected, report["valid"], str(report["errors"])])
		if expected:
			valid_count += 1
			var turn: Dictionary = report["turn"]
			if String(turn.get("speech", "")) != String((fixture["turn"] as Dictionary).get("speech", "")).strip_edges():
				failures.append("fixture '%s': a valid turn's speech must come through unchanged" % id)
		else:
			invalid_count += 1
			if report["turn"] != Turn.fallback_turn():
				failures.append("fixture '%s': an invalid turn must coerce to the fallback" % id)
	if valid_count < 5 or invalid_count < 7:
		failures.append("fixtures should cover both sides well: %d valid, %d invalid" % [valid_count, invalid_count])
	return failures


func _test_fallback_is_the_contracts():
	var failures: Array = []
	var fallback: Dictionary = Turn.fallback_turn()
	if fallback["speech"] != "Let's try together!" or fallback["emotion"] != "encouraging" \
			or fallback["gesture"] != "tilt" or fallback["lessonAction"] != "retry" \
			or (fallback["visual"] as Dictionary).get("type") != "none":
		failures.append("fallback turn differs from the contract: %s" % str(fallback))
	if not Turn.is_valid(fallback):
		failures.append("the fallback turn must itself validate")
	return failures


func _test_normalisation():
	var failures: Array = []
	var report: Dictionary = Turn.validate({"speech": "  Say apple!  ", "emotion": "happy", "gesture": "nod", "lessonAction": "retry"})
	var turn: Dictionary = report["turn"]
	if turn.get("subtitle") != "Say apple!":
		failures.append("subtitle should default to the trimmed speech, got '%s'" % str(turn.get("subtitle")))
	if (turn.get("visual") as Dictionary).get("type") != "none":
		failures.append("visual should default to none")
	# Whole-word banned matching: 'hello' must not trip on 'hell'.
	if not Turn.is_valid({"speech": "Hello! Shell time.", "emotion": "happy", "gesture": "wave", "lessonAction": "retry"}):
		failures.append("'hello' and 'shell' must not trip the banned-word filter")
	if Turn.is_valid({"speech": "Oh hell", "emotion": "happy", "gesture": "wave", "lessonAction": "retry"}):
		failures.append("a banned word must fail")
	return failures


func _test_make_is_always_valid():
	var failures: Array = []
	for asset in ["", "apple_red", "truck_red"]:
		var turn: Dictionary = Turn.make("Great job! Apple!", "happy", "clap", "next_question", asset, "What is this?")
		if not Turn.is_valid(turn):
			failures.append("make() with asset '%s' produced an invalid turn: %s" % [asset, str(Turn.validate(turn)["errors"])])
		var wanted_type: String = "flashcard" if asset == "apple_red" else "none"
		if (turn["visual"] as Dictionary).get("type") != wanted_type:
			failures.append("make() with asset '%s' should give visual type %s" % [asset, wanted_type])
	var clipped: Dictionary = Turn.make("x".repeat(400), "bogus", "bogus", "bogus")
	if not Turn.is_valid(clipped):
		failures.append("make() must clip and default its way to a valid turn")
	return failures


func _test_allowlist():
	var failures: Array = []
	var ids: Array = Turn.allowed_asset_ids()
	for wanted in ["apple_red", "banana_yellow", "cat", "dog", "number_1", "number_2", "number_3",
			"color_blue", "color_green", "color_red", "color_yellow", "orange_orange", "grapes_purple"]:
		if not ids.has(wanted):
			failures.append("allowlist is missing '%s'" % wanted)
	return failures
