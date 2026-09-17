extends RefCounted
## `StarRules` -- the pure 0..3 level rating.
##
## The product rule under test:
##
##   star 1 = core completion, achievable by TOUCH ALONE
##   star 2 = the level's findIt/sayIt tasks completed (touch still counts)
##   star 3 = an optional exploration / help / cleanup / free-play challenge
##
## and, above everything else: **speech is never required for any star.** That
## claim is asserted three independent ways below -- behaviourally, by
## indistinguishability, and structurally against the source file itself -- so
## it cannot quietly stop being true.

const StarRulesScript := preload("res://scripts/progression/star_rules.gd")
const StarRulesPath := "res://scripts/progression/star_rules.gd"

## Identifiers that would mean a star had started to depend on the microphone.
const SPEECH_IDENTIFIERS: Array[String] = [
	"speech",
	"transcript",
	"recogni",
	"microphone",
	"pronunc",
	"confidence",
	"utterance",
]

const RULES: Dictionary = {
	"coreTaskIds": ["feedMilk", "feedWater"],
	"listeningTaskIds": ["findBowl", "sayMilk"],
	"optionalTaskIds": ["feedBanana"],
}


func test_name() -> String:
	return "star_rules"


func run():
	var failures: Array = []
	failures.append_array(_test_truth_table())
	failures.append_array(_test_partial_progress())
	failures.append_array(_test_optional_objectives())
	failures.append_array(_test_speech_is_never_required())
	failures.append_array(_test_merge_never_subtracts())
	failures.append_array(_test_shaping_is_defensive())
	failures.append_array(_test_derivation())
	failures.append_array(_test_validate())
	return failures


# ---------------------------------------------------------------------------
# Every 0-3 combination
# ---------------------------------------------------------------------------

func _test_truth_table() -> Array:
	var failures: Array = []

	# [core done, listening done, optional done] -> expected rating.
	var table: Array = [
		[false, false, false, 0],
		[false, false, true, 0],
		[false, true, false, 0],
		[false, true, true, 0],
		[true, false, false, 1],
		[true, false, true, 1],
		[true, true, false, 2],
		[true, true, true, 3],
	]

	for row: Array in table:
		var completed: Array = []
		if bool(row[0]):
			completed.append_array(RULES["coreTaskIds"])
		if bool(row[1]):
			completed.append_array(RULES["listeningTaskIds"])
		if bool(row[2]):
			completed.append_array(RULES["optionalTaskIds"])

		var expected: int = int(row[3])
		var actual: int = StarRulesScript.evaluate(RULES, StarRulesScript.session(completed))
		if actual != expected:
			failures.append(
				"core=%s listening=%s optional=%s should rate %d, got %d"
				% [str(row[0]), str(row[1]), str(row[2]), expected, actual]
			)

	return failures


func _test_partial_progress() -> Array:
	var failures: Array = []

	# Half the core tasks is not completion.
	var half_core: int = StarRulesScript.evaluate(RULES, StarRulesScript.session(["feedMilk"]))
	if half_core != 0:
		failures.append("half the core tasks must not earn star 1, got %d" % half_core)

	# One of two listening tasks is not star 2.
	var half_listening: int = StarRulesScript.evaluate(
		RULES, StarRulesScript.session(["feedMilk", "feedWater", "findBowl"])
	)
	if half_listening != 1:
		failures.append("one of two listening tasks must stay at star 1, got %d" % half_listening)

	# Optional work without star 2 cannot skip ahead: ratings are cumulative.
	var optional_only: int = StarRulesScript.evaluate(
		RULES, StarRulesScript.session(["feedMilk", "feedWater", "feedBanana"])
	)
	if optional_only != 1:
		failures.append("optional work must not grant star 3 before star 2, got %d" % optional_only)

	# A level whose rules define no core task cannot hand out a star for nothing.
	var no_core: int = StarRulesScript.evaluate(
		{"listeningTaskIds": ["findBowl"]}, StarRulesScript.session(["findBowl"])
	)
	if no_core != 0:
		failures.append("rules with no core task must rate 0, got %d" % no_core)

	# Unknown/extra completions are ignored rather than counted.
	var noisy: int = StarRulesScript.evaluate(
		RULES, StarRulesScript.session(["feedMilk", "feedWater", "somethingElse"])
	)
	if noisy != 1:
		failures.append("unrelated completions must not change the rating, got %d" % noisy)

	return failures


func _test_optional_objectives() -> Array:
	var failures: Array = []

	# Star 3 can also come from a non-task objective (free play, tidying up).
	var rules: Dictionary = {
		"coreTaskIds": ["feedMilk"],
		"listeningTaskIds": ["findBowl"],
		"optionalObjectiveIds": ["freePlayNursery"],
	}
	var without: int = StarRulesScript.evaluate(
		rules, StarRulesScript.session(["feedMilk", "findBowl"])
	)
	if without != 2:
		failures.append("2/3 expected before the optional objective, got %d" % without)

	var with_objective: int = StarRulesScript.evaluate(
		rules, StarRulesScript.session(["feedMilk", "findBowl"], ["freePlayNursery"])
	)
	if with_objective != 3:
		failures.append("an optional objective must earn star 3, got %d" % with_objective)

	# An objective nobody declared is not a free star.
	var undeclared: int = StarRulesScript.evaluate(
		rules, StarRulesScript.session(["feedMilk", "findBowl"], ["wanderedOff"])
	)
	if undeclared != 2:
		failures.append("an undeclared objective must not earn star 3, got %d" % undeclared)

	return failures


# ---------------------------------------------------------------------------
# Speech is never required -- proved three ways
# ---------------------------------------------------------------------------

func _test_speech_is_never_required() -> Array:
	var failures: Array = []

	# 1. Behavioural. A child on a device where recognition is unavailable or
	#    denied completes every task by touch and still reaches 3/3.
	var touch_only: Array = []
	touch_only.append_array(RULES["coreTaskIds"])
	touch_only.append_array(RULES["listeningTaskIds"])
	touch_only.append_array(RULES["optionalTaskIds"])
	var touch_rating: int = StarRulesScript.evaluate(RULES, StarRulesScript.session(touch_only))
	if touch_rating != 3:
		failures.append(
			"a touch-only player must be able to reach 3/3; got %d" % touch_rating
		)

	# 2. Indistinguishability. Two sessions that differ ONLY in what the
	#    microphone did must rate identically -- including the sayIt task, which
	#    is the one a naive implementation would gate.
	var silent: Dictionary = {
		"completedTaskIds": touch_only,
		"speechEnabled": false,
		"speechAvailable": false,
		"transcripts": [],
		"recognizedTaskIds": [],
	}
	var spoken: Dictionary = {
		"completedTaskIds": touch_only,
		"speechEnabled": true,
		"speechAvailable": true,
		"transcripts": ["milk"],
		"recognizedTaskIds": ["sayMilk"],
	}
	var silent_rating: int = StarRulesScript.evaluate(RULES, silent)
	var spoken_rating: int = StarRulesScript.evaluate(RULES, spoken)
	if silent_rating != spoken_rating:
		failures.append(
			"speech must not change a rating: silent=%d spoken=%d" % [silent_rating, spoken_rating]
		)
	if silent_rating != 3:
		failures.append("the silent player must still rate 3/3, got %d" % silent_rating)

	# 3. Structural. The evaluator must not so much as mention speech. This is
	#    what catches a FUTURE edit that adds a microphone condition, long before
	#    anyone thinks to write a behavioural test for it.
	var source: String = _read_code_without_comments(StarRulesPath)
	if source.is_empty():
		failures.append("could not read %s to check it for speech dependencies" % StarRulesPath)
	else:
		var lowered: String = source.to_lower()
		for identifier: String in SPEECH_IDENTIFIERS:
			if lowered.find(identifier) != -1:
				failures.append(
					("star_rules.gd executable code mentions '%s'. Star rating must stay a "
					+ "pure function of which tasks were completed -- speech is never "
					+ "required for any star.") % identifier
				)

	return failures


# ---------------------------------------------------------------------------
# Never subtract a star
# ---------------------------------------------------------------------------

func _test_merge_never_subtracts() -> Array:
	var failures: Array = []

	if StarRulesScript.merge(3, 1) != 3:
		failures.append("a worse replay must not lower a 3-star rating")
	if StarRulesScript.merge(1, 3) != 3:
		failures.append("a better replay must raise the rating to 3")
	if StarRulesScript.merge(2, 2) != 2:
		failures.append("repeating the same result must not stack")
	if StarRulesScript.merge(0, 0) != 0:
		failures.append("0 merged with 0 must stay 0")
	if StarRulesScript.merge(3, -5) != 3:
		failures.append("a negative award must never subtract from a rating")
	if StarRulesScript.merge(1, 99) != 3:
		failures.append("a rating must be clamped to the 3-star maximum")

	if StarRulesScript.clamp_stars(-1) != 0:
		failures.append("clamp_stars must floor at 0")
	if StarRulesScript.clamp_stars(7) != 3:
		failures.append("clamp_stars must cap at 3")
	if StarRulesScript.clamp_stars(2.0) != 2:
		failures.append("clamp_stars must accept JSON floats")
	if StarRulesScript.clamp_stars("nonsense") != 0:
		failures.append("clamp_stars must treat junk as 0")

	if not StarRulesScript.is_passing(2):
		failures.append("2/3 must pass the level")
	if StarRulesScript.is_passing(1):
		failures.append("1/3 must not count as passing")
	if not StarRulesScript.grants_bonus_sticker(3):
		failures.append("3/3 must grant the bonus sticker")
	if StarRulesScript.grants_bonus_sticker(2):
		failures.append("2/3 must not grant the bonus sticker")
	if StarRulesScript.is_complete(0):
		failures.append("0 stars must not count as completion")
	if not StarRulesScript.is_complete(1):
		failures.append("1 star must count as completion -- that is the unlock gate")

	return failures


# ---------------------------------------------------------------------------
# Defensiveness
# ---------------------------------------------------------------------------

func _test_shaping_is_defensive() -> Array:
	var failures: Array = []

	for junk: Variant in [null, 42, "rules", []]:
		var shaped: Dictionary = StarRulesScript.normalize(junk)
		for key: String in ["coreTaskIds", "listeningTaskIds", "optionalTaskIds", "optionalObjectiveIds"]:
			if typeof(shaped.get(key, null)) != TYPE_ARRAY:
				failures.append("normalize(%s) must still produce '%s'" % [str(junk), key])
		if StarRulesScript.evaluate(junk, StarRulesScript.session(["feedMilk"])) != 0:
			failures.append("malformed rules must rate 0, not crash (%s)" % str(junk))
		if StarRulesScript.evaluate(RULES, junk) != 0:
			failures.append("a malformed session must rate 0, not crash (%s)" % str(junk))

	var deduped: Dictionary = StarRulesScript.normalize({"coreTaskIds": ["a", "a", " a ", "", "b"]})
	if not _same(deduped["coreTaskIds"], ["a", "b"]):
		failures.append("normalize must trim, drop blanks and dedupe: got %s" % str(deduped["coreTaskIds"]))

	var described: Dictionary = StarRulesScript.describe(RULES, StarRulesScript.session(["feedMilk"]))
	if not _same(described.get("missingCore", []), ["feedWater"]):
		failures.append("describe() must report the missing core task, got %s" % str(described.get("missingCore")))

	return failures


func _test_derivation() -> Array:
	var failures: Array = []

	# A mission with no authored rules still rates: findIt/sayIt become the
	# listening set, everything else is core.
	var tasks: Array = [
		{"taskId": "feedMilk", "mode": "followInstruction"},
		{"taskId": "findBowl", "mode": "findIt"},
		{"taskId": "sayMilk", "mode": "sayIt"},
	]
	var derived: Dictionary = StarRulesScript.derive_from_tasks(tasks)
	if not _same(derived["coreTaskIds"], ["feedMilk"]):
		failures.append("derived core should be the non-listening tasks, got %s" % str(derived["coreTaskIds"]))
	if not _same(derived["listeningTaskIds"], ["findBowl", "sayMilk"]):
		failures.append("derived listening should be findIt+sayIt, got %s" % str(derived["listeningTaskIds"]))
	if StarRulesScript.evaluate(derived, StarRulesScript.session(["feedMilk", "findBowl", "sayMilk"])) != 2:
		failures.append("a derived rule set should reach 2/3 on a full play")

	# An all-listening mission must not hand out star 1 for doing nothing.
	var all_say: Array = [
		{"taskId": "sayMilk", "mode": "sayIt"},
		{"taskId": "sayBlue", "mode": "sayIt"},
	]
	var say_rules: Dictionary = StarRulesScript.derive_from_tasks(all_say)
	if StarRulesScript.evaluate(say_rules, StarRulesScript.session([])) != 0:
		failures.append("an all-listening mission must rate 0 for an empty session")
	if StarRulesScript.evaluate(say_rules, StarRulesScript.session(["sayMilk", "sayBlue"])) != 2:
		failures.append("an all-listening mission should reach 2/3 when fully played")

	var by_ids: Dictionary = StarRulesScript.derive_from_task_ids(["a", "b"])
	if not _same(by_ids["coreTaskIds"], ["a", "b"]):
		failures.append("derive_from_task_ids must treat every task as core")

	return failures


func _test_validate() -> Array:
	var failures: Array = []

	if not StarRulesScript.validate(RULES, ["feedMilk", "feedWater", "findBowl", "sayMilk", "feedBanana"]).is_empty():
		failures.append("the sample rule set should validate cleanly")

	if StarRulesScript.validate({"listeningTaskIds": ["findBowl"]}).is_empty():
		failures.append("rules with no core task must be reported as a problem")

	if StarRulesScript.validate({"coreTaskIds": ["a"], "optionalTaskIds": ["a"]}).is_empty():
		failures.append("a task in two star buckets must be reported as a problem")

	if StarRulesScript.validate({"coreTaskIds": ["a"], "bogusKey": []}).is_empty():
		failures.append("an unknown starRules key must be reported as a problem")

	if StarRulesScript.validate({"coreTaskIds": ["ghost"]}, ["a"]).is_empty():
		failures.append("a rule pointing at an unknown task must be reported as a problem")

	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Source text with every comment stripped, so the structural check above reads
## what the code DOES, not what its documentation says about speech.
func _read_code_without_comments(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()

	var code: String = ""
	for raw_line: String in text.split("\n"):
		var comment_at: int = raw_line.find("#")
		if comment_at == -1:
			code += raw_line + "\n"
		else:
			code += raw_line.substr(0, comment_at) + "\n"
	return code


## Element-wise list comparison, so a failure prints what actually came back.
static func _same(actual: Variant, expected: Array) -> bool:
	if typeof(actual) != TYPE_ARRAY:
		return false
	var list: Array = actual
	if list.size() != expected.size():
		return false
	for i: int in range(expected.size()):
		if String(list[i]) != String(expected[i]):
			return false
	return true
