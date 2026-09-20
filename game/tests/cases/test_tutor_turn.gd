extends RefCounted

## The TutorTurn client validator agrees with the server, case for case.
##
##   * every case in the SHARED fixture file `content/tutor/turn_fixtures.json`
##     (the same file `backend/test/validator.test.js` runs) lands where the
##     fixture says, with the fixture's reason code and normalised fields;
##   * the enum truth table the server test pins (every member accepted, one-off
##     spellings refused, `none` with a stray assetId refused);
##   * `check_text` edge cases, verbatim from the server test;
##   * the fallback turn is the contract's, and is itself valid;
##   * `make()` only ever builds a turn `validate()` accepts, even from lesson
##     text with typographic punctuation or over-length lines.

const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")

const FIXTURE_MIN_CASES: int = 30


func test_name() -> String:
	return "tutor_turn"


func run():
	var failures: Array = []
	failures.append_array(_test_fixture_parity())
	failures.append_array(_test_enum_truth_table())
	failures.append_array(_test_check_text_edges())
	failures.append_array(_test_fallback_is_the_contract())
	failures.append_array(_test_make_is_always_valid())
	failures.append_array(_test_unknown_keys_dropped())
	return failures


func _test_fixture_parity():
	var failures: Array = []
	var cases: Array = TurnValidator.load_fixtures()
	if cases.size() < FIXTURE_MIN_CASES:
		failures.append("shared fixture file has %d cases; expected at least %d" % [cases.size(), FIXTURE_MIN_CASES])
	var fallback: Dictionary = TurnValidator.fallback_turn()
	for entry: Variant in cases:
		var c: Dictionary = entry
		var label: String = String(c.get("name", "?"))
		var report: Dictionary = TurnValidator.validate(c.get("input", null))
		var expect_valid: bool = String(c.get("expect", "")) == "valid"
		if bool(report["valid"]) != expect_valid:
			failures.append("fixture '%s': expected %s, got %s (reasons %s)"
					% [label, "valid" if expect_valid else "fallback", "valid" if report["valid"] else "fallback", str(report["reasons"])])
			continue
		if expect_valid:
			var normalized: Dictionary = c.get("normalized", {})
			var turn: Dictionary = report["turn"]
			for key: String in normalized.keys():
				if not turn.has(key) or turn[key] != normalized[key]:
					failures.append("fixture '%s': normalized.%s expected %s, got %s"
							% [label, key, str(normalized[key]), str(turn.get(key, "<missing>"))])
			for key: String in turn.keys():
				if not TurnValidator.OUTPUT_KEYS.has(String(key)):
					failures.append("fixture '%s': output carries unknown key '%s'" % [label, key])
		else:
			if report["turn"] != fallback:
				failures.append("fixture '%s': an invalid turn must become the fallback, got %s" % [label, str(report["turn"])])
			var prefix: String = String(c.get("reasonPrefix", ""))
			if not prefix.is_empty():
				var found: bool = false
				for reason: Variant in report["reasons"]:
					if String(reason).begins_with(prefix):
						found = true
				if not found:
					failures.append("fixture '%s': reasons %s should include %s" % [label, str(report["reasons"]), prefix])
	return failures


func _test_enum_truth_table():
	var failures: Array = []
	var base: Dictionary = {"speech": "Hi!", "emotion": "happy", "gesture": "nod", "visual": {"type": "none"}, "lessonAction": "retry"}
	for emotion: String in TurnValidator.EMOTIONS:
		if not TurnValidator.is_valid(_with(base, "emotion", emotion)):
			failures.append("emotion %s should be accepted" % emotion)
	for gesture: String in TurnValidator.GESTURES:
		if not TurnValidator.is_valid(_with(base, "gesture", gesture)):
			failures.append("gesture %s should be accepted" % gesture)
	for action: String in TurnValidator.LESSON_ACTIONS:
		if not TurnValidator.is_valid(_with(base, "lessonAction", action)):
			failures.append("lessonAction %s should be accepted" % action)
	for id: String in TurnValidator.DEFAULT_ASSET_IDS:
		if not TurnValidator.is_valid(_with(base, "visual", {"type": "flashcard", "assetId": id})):
			failures.append("asset %s should be accepted" % id)
	if TurnValidator.allowed_asset_ids() != TurnValidator.DEFAULT_ASSET_IDS:
		failures.append("assets_allowlist.json differs from the contract list: %s" % str(TurnValidator.allowed_asset_ids()))
	if TurnValidator.is_valid(_with(base, "emotion", "Happy")):
		failures.append("'Happy' (case) must be refused")
	if TurnValidator.is_valid(_with(base, "gesture", "NOD")):
		failures.append("'NOD' (case) must be refused")
	if TurnValidator.is_valid(_with(base, "lessonAction", "next")):
		failures.append("'next' must be refused")
	if TurnValidator.is_valid(_with(base, "visual", {"type": "gif", "assetId": "cat"})):
		failures.append("visual type gif must be refused")
	if TurnValidator.is_valid(_with(base, "visual", {"type": "none", "assetId": "not_allowed"})):
		failures.append("none + stray unknown assetId must be refused")
	if TurnValidator.is_valid(_with(base, "emotion", 3)):
		failures.append("a non-string emotion must be refused")
	return failures


func _test_check_text_edges():
	var failures: Array = []
	var checks: Array = [
		["a".repeat(160), "speech", 160, true, []],
		["a".repeat(161), "speech", 160, true, ["speech:too_long"]],
		["12345678901234567890", "speech", 160, true, []],
		["www.example.org", "speech", 160, true, ["speech:url"]],
		["Visit example.com now", "speech", 160, true, ["speech:url"]],
		["Hello. Nice, right? Yes: \"good\"!", "speech", 160, true, []],
		["tab\there", "speech", 160, true, ["speech:non_ascii"]],
		["The cat is kind.", "speech", 160, true, []],
		["hello", "speech", 160, true, []],
		["Shut  up!", "speech", 160, true, ["speech:banned_word"]],
		["What is your Last Name?", "speech", 160, true, ["speech:banned_word"]],
		["   ", "speech", 160, true, ["speech:required"]],
		["   ", "subtitle", 160, false, []],
		[null, "nextQuestion", 120, false, []],
		["", "speech", 160, true, ["speech:required"]],
		[7, "speech", 160, true, ["speech:not_string"]],
	]
	for row: Array in checks:
		var got: Array = TurnValidator.check_text(row[0], row[1], row[2], row[3])
		if got != row[4]:
			failures.append("check_text(%s, %s) -> %s, expected %s" % [str(row[0]), row[1], str(got), str(row[4])])
	return failures


func _test_fallback_is_the_contract():
	var failures: Array = []
	var fallback: Dictionary = TurnValidator.fallback_turn()
	var expected: Dictionary = {
		"speech": "Let's try together!", "subtitle": "Let's try together!", "emotion": "encouraging",
		"gesture": "tilt", "visual": {"type": "none"}, "lessonAction": "retry",
	}
	if fallback != expected:
		failures.append("fallback turn differs from the contract: %s" % str(fallback))
	if not TurnValidator.is_valid(fallback):
		failures.append("the fallback turn must itself validate")
	if TurnValidator.coerce("not a turn") != fallback:
		failures.append("coerce() of a non-dictionary must be the fallback")
	return failures


func _test_make_is_always_valid():
	var failures: Array = []
	var samples: Array = [
		["What's this?", "listening", "tilt", "retry", "apple_red", "What's this?"],
		["That’s right — an apple! “Yes”…", "happy", "clap", "next_question", "apple_red", ""],
		["Look at the picture. " .repeat(20), "encouraging", "point", "give_hint", "banana_yellow", "Question? ".repeat(30)],
		["Great job today! \U0001F34E", "smile", "wave", "complete", "dinosaur_green", ""],
		["", "bogus", "backflip", "skip", "", ""],
	]
	for s: Array in samples:
		var turn: Dictionary = TurnValidator.make(s[0], s[1], s[2], s[3], s[4], s[5])
		var report: Dictionary = TurnValidator.validate(turn)
		if s[0].is_empty():
			if bool(report["valid"]):
				failures.append("make() of empty speech cannot be valid; the caller must supply words")
			continue
		if not bool(report["valid"]):
			failures.append("make(%s) produced an invalid turn: %s" % [str(s), str(report["reasons"])])
	var apostrophe: Dictionary = TurnValidator.make("That’s right — yes!", "happy", "clap", "next_question")
	if String(apostrophe["speech"]) != "That's right - yes!":
		failures.append("typographic punctuation should be folded to ASCII, got '%s'" % apostrophe["speech"])
	var long_turn: Dictionary = TurnValidator.make("Look at the picture. ".repeat(20), "happy", "nod", "retry")
	if String(long_turn["speech"]).length() > TurnValidator.MAX_SPEECH or String(long_turn["speech"]).ends_with(" "):
		failures.append("over-length speech must be trimmed to the limit on a word boundary")
	var model: Dictionary = TurnValidator.make("A cat.", "smile", "point", "retry", "cat", "", "", "model")
	if model["visual"] != {"type": "model", "assetId": "cat"}:
		failures.append("make() should honour a model visual, got %s" % str(model["visual"]))
	var bad_asset: Dictionary = TurnValidator.make("Look!", "smile", "point", "retry", "dinosaur_green")
	if bad_asset["visual"] != {"type": "none"}:
		failures.append("make() with an unknown asset must give visual none")
	return failures


func _test_unknown_keys_dropped():
	var failures: Array = []
	var turn: Dictionary = TurnValidator.coerce({
		"speech": "Nice!", "emotion": "happy", "gesture": "clap", "visual": {"type": "none"},
		"lessonAction": "complete", "toolCall": "open_url", "debug": {"tokens": 12}, "score": 0.93,
	})
	for key: String in ["toolCall", "debug", "score"]:
		if turn.has(key):
			failures.append("unknown key %s must be dropped" % key)
	if String(turn.get("speech", "")) != "Nice!" or String(turn.get("lessonAction", "")) != "complete":
		failures.append("a turn with extra keys must otherwise pass through: %s" % str(turn))
	return failures


static func _with(base: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = base.duplicate(true)
	copy[key] = value
	return copy
