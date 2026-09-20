extends RefCounted

## Aliz Tutor Mode: the deterministic lesson system (Agent A).
##
## Covers, against the shipped content and the LessonEngine contract in
## docs/ALIZ_TUTOR_CONTRACTS.md:
## - every shipped lesson validates against lesson_schema.json;
## - the visual asset allowlist is exactly the contract's list and is enforced;
## - the first lesson fits the 5-minute budget;
## - evaluate() truth table (correct / synonym / slip / wrong / unclear / empty);
## - retry escalation: retry -> give_hint -> next_question, never a fail;
## - progress save/load round trip under settings.tutorProgress;
## - completion awards its stars exactly once, across saves and reloads.

const LessonEngineScript := preload("res://scripts/tutor/lesson/lesson_engine.gd")
const LessonValidatorScript := preload("res://scripts/tutor/lesson/lesson_validator.gd")
const AnswerMatcherScript := preload("res://scripts/tutor/lesson/answer_matcher.gd")

const FIRST_LESSON_ID: String = "english_colors_fruits"
const CONTRACT_ALLOWLIST: Array[String] = [
	"apple_red", "banana_yellow", "cat", "dog", "number_1", "number_2", "number_3",
	"color_blue", "color_green", "color_red", "color_yellow", "orange_orange", "grapes_purple",
]
const EXPECTED_SUBJECTS: Array[String] = ["english_basics", "numbers", "colors", "animals", "everyday_life"]


## Stand-in for the SaveService autoload (detached under the runner). Counts
## add_stars calls so a double payment shows as a wrong count AND total.
class FakeSave extends RefCounted:
	var stars: int = 0
	var add_calls: int = 0
	var settings: Dictionary = {}

	func add_stars(amount: int) -> int:
		add_calls += 1
		stars = maxi(stars + amount, 0)
		return stars

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		if settings.has(key):
			return settings[key]
		return default_value

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value


func test_name() -> String:
	return "tutor_lesson"


func run():
	var failures: Array = []
	failures.append_array(_test_shipped_content_validates())
	failures.append_array(_test_allowlist_is_the_contract_and_enforced())
	failures.append_array(_test_schema_rejects_bad_lessons())
	failures.append_array(_test_first_lesson_shape_and_budget())
	failures.append_array(_test_matcher_truth_table())
	failures.append_array(_test_evaluate_truth_table())
	failures.append_array(_test_retry_escalation_never_fails())
	failures.append_array(_test_generated_answer_lines())
	failures.append_array(_test_progress_round_trip())
	failures.append_array(_test_completion_awards_exactly_once())
	failures.append_array(_test_every_lesson_completes_both_ways())
	failures.append_array(_test_engine_edge_cases())
	return failures


# --- content ---------------------------------------------------------------------

func _test_shipped_content_validates():
	var failures: Array = []
	var problems: Array = LessonValidatorScript.validate_shipped()
	for problem: Variant in problems:
		failures.append("shipped tutor content: %s" % str(problem))
	var ids: Array = LessonValidatorScript.shipped_lesson_ids()
	if ids.size() < 5:
		failures.append("expected at least 5 shipped lessons (one per subject), found %d" % ids.size())
	if not ids.has(FIRST_LESSON_ID):
		failures.append("first lesson %s is not shipped" % FIRST_LESSON_ID)
	var subjects: Array = LessonEngineScript.load_subjects()
	var subject_ids: Array = []
	for subject: Variant in subjects:
		subject_ids.append(String((subject as Dictionary).get("subjectId", "")))
	for expected: String in EXPECTED_SUBJECTS:
		if not subject_ids.has(expected):
			failures.append("subjects.json is missing subject '%s'" % expected)
	if subjects.size() != 5:
		failures.append("subjects.json should list exactly 5 subjects, found %d" % subjects.size())
	return failures


func _test_allowlist_is_the_contract_and_enforced():
	var failures: Array = []
	var allowlist: Array = LessonValidatorScript.load_allowlist()
	if allowlist.size() != CONTRACT_ALLOWLIST.size():
		failures.append("allowlist has %d ids, contract has %d" % [allowlist.size(), CONTRACT_ALLOWLIST.size()])
	for asset_id: String in CONTRACT_ALLOWLIST:
		if not allowlist.has(asset_id):
			failures.append("allowlist is missing contract id '%s'" % asset_id)
	for asset_id: Variant in allowlist:
		if not CONTRACT_ALLOWLIST.has(String(asset_id)):
			failures.append("allowlist carries '%s' which is not in the contract" % str(asset_id))

	var schema: Dictionary = LessonValidatorScript.load_schema()
	var lesson: Dictionary = _load_first_lesson()
	var tampered: Dictionary = lesson.duplicate(true)
	(tampered["steps"][1] as Dictionary)["visualAssetId"] = "pizza_slice"
	var problems: Array = LessonValidatorScript.validate_lesson(tampered, schema, allowlist)
	if not _any_contains(problems, "pizza_slice"):
		failures.append("validator accepted a visualAssetId outside the allowlist: %s" % str(problems))
	# Every visual in every shipped lesson is on the list (belt and braces over validate_shipped).
	for lesson_id: Variant in LessonValidatorScript.shipped_lesson_ids():
		var data: Variant = LessonValidatorScript.load_json("%s/%s.json" % [LessonValidatorScript.LESSONS_DIR, lesson_id])
		if typeof(data) != TYPE_DICTIONARY:
			failures.append("%s: not a JSON object" % str(lesson_id))
			continue
		for step: Variant in (data as Dictionary).get("steps", []):
			var visual: String = String((step as Dictionary).get("visualAssetId", ""))
			if not visual.is_empty() and not CONTRACT_ALLOWLIST.has(visual):
				failures.append("%s/%s uses off-list asset '%s'" % [str(lesson_id), str((step as Dictionary).get("stepId", "")), visual])
	return failures


func _test_schema_rejects_bad_lessons():
	var failures: Array = []
	var schema: Dictionary = LessonValidatorScript.load_schema()
	var allowlist: Array = LessonValidatorScript.load_allowlist()
	var good: Dictionary = _load_first_lesson()
	if not LessonValidatorScript.validate_lesson(good, schema, allowlist).is_empty():
		failures.append("baseline first lesson must validate before the negative cases mean anything")
		return failures

	var cases: Array = [
		{"name": "missing lessonId", "mutate": func(l: Dictionary) -> void: l.erase("lessonId"), "expect": "lessonId"},
		{"name": "snake_case key", "mutate": func(l: Dictionary) -> void: l["target_duration"] = 300, "expect": "target_duration"},
		{"name": "bad kind", "mutate": func(l: Dictionary) -> void: (l["steps"][1] as Dictionary)["kind"] = "quiz", "expect": "quiz"},
		{"name": "ask without expectedAnswers", "mutate": func(l: Dictionary) -> void: (l["steps"][1] as Dictionary).erase("expectedAnswers"), "expect": "expectedAnswers"},
		{"name": "ask without hint", "mutate": func(l: Dictionary) -> void: (l["steps"][1] as Dictionary).erase("hint"), "expect": "hint"},
		{"name": "speech too long", "mutate": func(l: Dictionary) -> void: (l["steps"][0] as Dictionary)["teachText"] = "a".repeat(161), "expect": "longer than 160"},
		{"name": "banned word", "mutate": func(l: Dictionary) -> void: (l["steps"][1] as Dictionary)["encouragement"] = "Wrong! Try again.", "expect": "banned word"},
		{"name": "non-English answer", "mutate": func(l: Dictionary) -> void: (l["steps"][1] as Dictionary)["expectedAnswers"] = ["apple", "แอปเปิล"], "expect": "does not match"},
		{"name": "duplicate stepId", "mutate": func(l: Dictionary) -> void: (l["steps"][2] as Dictionary)["stepId"] = "s02_apple_name", "expect": "duplicate stepId"},
		{"name": "celebrate not last", "mutate": func(l: Dictionary) -> void: (l["steps"] as Array).reverse(), "expect": "celebrate"},
		{"name": "wrong language", "mutate": func(l: Dictionary) -> void: l["language"] = "th", "expect": "language"},
		{"name": "zero stars", "mutate": func(l: Dictionary) -> void: (l["completion"] as Dictionary)["stars"] = 0, "expect": "stars"},
		{"name": "unknown key on step", "mutate": func(l: Dictionary) -> void: (l["steps"][1] as Dictionary)["score"] = 100, "expect": "score"},
		{"name": "stale helper key", "mutate": func(l: Dictionary) -> void: (l["helperLanguageKeys"] as Array).append("buy_now"), "expect": "buy_now"},
		{"name": "duration far off target", "mutate": func(l: Dictionary) -> void: l["targetDurationSeconds"] = 600, "expect": "estimated duration"},
	]
	for entry: Variant in cases:
		var case_data: Dictionary = entry
		var tampered: Dictionary = good.duplicate(true)
		(case_data["mutate"] as Callable).call(tampered)
		var problems: Array = LessonValidatorScript.validate_lesson(tampered, schema, allowlist)
		if problems.is_empty():
			failures.append("validator accepted '%s'" % str(case_data["name"]))
		elif not _any_contains(problems, String(case_data["expect"])):
			failures.append("'%s': expected a problem mentioning '%s', got %s" % [str(case_data["name"]), str(case_data["expect"]), str(problems)])
	return failures


func _test_first_lesson_shape_and_budget():
	var failures: Array = []
	var lesson: Dictionary = _load_first_lesson()
	var steps: Array = lesson.get("steps", [])
	if steps.size() < 14 or steps.size() > 18:
		failures.append("first lesson should have 14..18 steps, has %d" % steps.size())
	var kinds: Dictionary = {"teach": 0, "ask": 0, "celebrate": 0}
	for step: Variant in steps:
		var kind: String = String((step as Dictionary).get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	if int(kinds["ask"]) < 10:
		failures.append("first lesson should ask at least 10 questions, asks %d" % int(kinds["ask"]))
	if int(kinds["celebrate"]) != 1:
		failures.append("first lesson needs exactly one celebrate step")
	if int(lesson.get("targetDurationSeconds", 0)) != 300:
		failures.append("first lesson targetDurationSeconds must be 300")
	var schema: Dictionary = LessonValidatorScript.load_schema()
	var estimate: int = LessonValidatorScript.estimate_duration_seconds(lesson, schema)
	if estimate < 270 or estimate > 330:
		failures.append("first lesson estimate %d s is not within 10%% of 300 s" % estimate)
	if String((steps[0] as Dictionary).get("teachText", "")) != "Hello! Let's learn together!":
		failures.append("first lesson must open with 'Hello! Let's learn together!'")
	# The story beats the brief names: apple/red, banana/yellow, orange/orange, grapes/purple, a mixed review.
	var canonicals: Array = []
	for step: Variant in steps:
		var answers: Array = (step as Dictionary).get("expectedAnswers", [])
		if not answers.is_empty():
			canonicals.append(String(answers[0]))
	for needed: String in ["apple", "red", "banana", "yellow", "orange", "grapes", "purple"]:
		if not canonicals.has(needed):
			failures.append("first lesson never asks for '%s'" % needed)
	var has_review: bool = false
	for step: Variant in steps:
		if String((step as Dictionary).get("questionText", "")).begins_with("Which one is"):
			has_review = true
	if not has_review:
		failures.append("first lesson has no mixed review ('Which one is ...?')")
	var completion: Dictionary = lesson.get("completion", {})
	if int(completion.get("stars", 0)) < 1 or String(completion.get("stickerId", "")).is_empty():
		failures.append("first lesson completion must award stars and a sticker")
	for step: Variant in steps:
		var data: Dictionary = step
		if String(data.get("kind", "")) != "ask":
			continue
		if (data.get("expectedAnswers", []) as Array).size() < 2:
			failures.append("%s: ask steps need synonyms" % str(data.get("stepId", "")))
		for field: String in ["hint", "encouragement", "visualAssetId", "successLine"]:
			if String(data.get(field, "")).is_empty():
				failures.append("%s: ask step missing %s" % [str(data.get("stepId", "")), field])
	return failures


# --- matcher and evaluate ---------------------------------------------------------------

func _test_matcher_truth_table():
	var failures: Array = []
	var apple: Array = ["apple", "an apple", "it's an apple", "red apple"]
	var table: Array = [
		["Apple!", "exact"],
		["apple", "exact"],
		["an apple", "exact"],
		["It's an apple.", "exact"],
		["the apple", "exact"],
		["um it's a red apple please", "exact"],
		["I think it is an apple", "exact"],
		["it is an apple I think", "exact"],
		["a big red apple", "contains"],
		["aple", "fuzzy"],
		["appel", "fuzzy"],
		["apples", "fuzzy"],
		["banana", ""],
		["", ""],
		["...", ""],
		["ap", ""],
	]
	for row: Variant in table:
		var result: Dictionary = AnswerMatcherScript.match_answer(String(row[0]), apple)
		if String(result.get("kind", "")) != String(row[1]):
			failures.append("match('%s') kind expected '%s', got '%s'" % [str(row[0]), str(row[1]), str(result.get("kind", ""))])
	# Short words never fuzz: the slip IS another word.
	if not String(AnswerMatcherScript.match_answer("car", ["cat", "a cat"]).get("matched", "")).is_empty():
		failures.append("'car' must not match 'cat'")
	if not String(AnswerMatcherScript.match_answer("bed", ["red"]).get("matched", "")).is_empty():
		failures.append("'bed' must not match 'red'")
	if String(AnswerMatcherScript.match_answer("its a red one", ["red"]).get("kind", "")) != "contains":
		failures.append("'its a red one' should contain 'red'")
	if String(AnswerMatcherScript.match_answer("one", ["one", "1"]).get("kind", "")) != "exact":
		failures.append("'one' must match the number one exactly")
	if String(AnswerMatcherScript.match_answer("2", ["two", "2"]).get("kind", "")) != "exact":
		failures.append("digit transcripts must match")
	if not AnswerMatcherScript.is_blank("  !!  ") or AnswerMatcherScript.is_blank("a"):
		failures.append("is_blank() should be true only for transcripts with no letters or digits")
	return failures


func _test_evaluate_truth_table():
	var failures: Array = []
	var table: Array = [
		# transcript, outcome, lessonAction, matched
		["Apple!", "correct", "next_question", "apple"],
		["an apple", "correct", "next_question", "apple"],
		["it's a red apple", "correct", "next_question", "red apple"],
		["a big apple", "correct", "next_question", "apple"],
		["aple", "correct", "next_question", "apple"],
		["banana", "incorrect", "retry", ""],
		["", "unclear", "retry", ""],
		["...", "unclear", "retry", ""],
	]
	for row: Variant in table:
		var engine: RefCounted = _engine_at_first_ask()
		if engine == null:
			failures.append("could not load %s" % FIRST_LESSON_ID)
			return failures
		var result: Dictionary = engine.evaluate(String(row[0]))
		if String(result.get("outcome", "")) != String(row[1]):
			failures.append("evaluate('%s') outcome expected %s, got %s" % [str(row[0]), str(row[1]), str(result.get("outcome"))])
		if String(result.get("lessonAction", "")) != String(row[2]):
			failures.append("evaluate('%s') lessonAction expected %s, got %s" % [str(row[0]), str(row[2]), str(result.get("lessonAction"))])
		if String(result.get("matched", "")) != String(row[3]):
			failures.append("evaluate('%s') matched expected '%s', got '%s'" % [str(row[0]), str(row[3]), str(result.get("matched"))])
		for key: String in ["outcome", "matched", "hint", "encouragement", "lessonAction"]:
			if not result.has(key):
				failures.append("evaluate() result is missing contract key '%s'" % key)
		if String(result.get("outcome", "")) == "correct":
			if String(result.get("line", "")) != "Great job! It's an apple!":
				failures.append("correct answer should speak the successLine, got '%s'" % str(result.get("line", "")))
			if int(engine.progress().get("correctFirstTry", 0)) != 1:
				failures.append("a first-try correct answer must count in correctFirstTry")
		# evaluate() never advances on its own.
		if String(engine.current_step().get("stepId", "")) != "s02_apple_name":
			failures.append("evaluate('%s') must not advance the step" % str(row[0]))
	return failures


func _test_retry_escalation_never_fails():
	var failures: Array = []
	var engine: RefCounted = _engine_at_first_ask()
	if engine == null:
		return ["could not load %s" % FIRST_LESSON_ID]
	var step: Dictionary = engine.current_step()

	var first: Dictionary = engine.evaluate("banana")
	if String(first.get("lessonAction", "")) != "retry" or String(first.get("outcome", "")) != "incorrect":
		failures.append("1st miss: expected incorrect/retry, got %s/%s" % [str(first.get("outcome")), str(first.get("lessonAction"))])
	if String(first.get("line", "")) != String(step.get("encouragement", "")):
		failures.append("1st miss must speak the step's encouragement")

	var second: Dictionary = engine.evaluate("")
	if String(second.get("lessonAction", "")) != "give_hint" or String(second.get("outcome", "")) != "unclear":
		failures.append("2nd miss (blank): expected unclear/give_hint, got %s/%s" % [str(second.get("outcome")), str(second.get("lessonAction"))])
	if String(second.get("line", "")) != String(step.get("hint", "")):
		failures.append("2nd miss must speak the hint")
	if String(second.get("hint", "")) != "It's round and red. You can eat it. It's an ap-ple!":
		failures.append("hint text not carried: %s" % str(second.get("hint", "")))

	var third: Dictionary = engine.evaluate("banana")
	if String(third.get("lessonAction", "")) != "next_question":
		failures.append("3rd miss must move on with next_question, got %s" % str(third.get("lessonAction")))
	if String(third.get("outcome", "")) != "unclear":
		failures.append("3rd miss must be reported as unclear (no fail state), got %s" % str(third.get("outcome")))
	if String(third.get("line", "")) != "It's an apple! Say apple.":
		failures.append("3rd miss must teach the answer, got '%s'" % str(third.get("line", "")))
	if not bool(third.get("teachAnswer", false)):
		failures.append("3rd miss result should flag teachAnswer")
	if String(third.get("outcome", "")) == "incorrect" or String(third.get("lessonAction", "")).contains("fail"):
		failures.append("there must never be a fail action")
	if String(engine.current_step().get("stepId", "")) != "s02_apple_name":
		failures.append("evaluate() must not advance even on the 3rd miss; the scene advances")
	if int(engine.progress().get("correctFirstTry", 0)) != 0:
		failures.append("a taught answer never counts as correct")

	engine.advance()
	if String(engine.current_step().get("stepId", "")) != "s03_apple_colour":
		failures.append("advance() after the 3rd miss should reach the colour question")
	if int(engine.attempts()) != 0:
		failures.append("attempts must reset on advance")
	# Correct after one miss: still correct, not first-try.
	engine.evaluate("blue")
	var recovered: Dictionary = engine.evaluate("red")
	if String(recovered.get("outcome", "")) != "correct" or String(recovered.get("lessonAction", "")) != "next_question":
		failures.append("correct on 2nd attempt should be correct/next_question, got %s/%s" % [str(recovered.get("outcome")), str(recovered.get("lessonAction"))])
	if int(engine.progress().get("correctFirstTry", 0)) != 0:
		failures.append("a second-attempt correct answer must not count as first-try")
	return failures


func _test_generated_answer_lines():
	var failures: Array = []
	var engine: RefCounted = LessonEngineScript.new()
	engine.set_lesson_source({"mini": _mini_lesson(["red"], ["cat", "a cat"], ["grapes"])})
	if not engine.load_lesson("mini"):
		return ["mini lesson did not load"]
	engine.advance()  # past the greeting
	var expected_lines: Array = ["It's red! Say red.", "It's a cat! Say cat.", "They're grapes! Say grapes."]
	for expected: Variant in expected_lines:
		engine.evaluate("zzz")
		engine.evaluate("zzz")
		var third: Dictionary = engine.evaluate("zzz")
		if String(third.get("line", "")) != String(expected):
			failures.append("generated answer line expected '%s', got '%s'" % [str(expected), str(third.get("line", ""))])
		engine.advance()
	return failures


# --- persistence and rewards -------------------------------------------------------

func _test_progress_round_trip():
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var engine: RefCounted = LessonEngineScript.new()
	if not engine.load_lesson(FIRST_LESSON_ID):
		return ["could not load %s" % FIRST_LESSON_ID]
	engine.advance()                # s02
	engine.evaluate("apple")        # correct first try
	engine.advance()                # s03
	engine.evaluate("blue")
	engine.evaluate("red")          # correct, second attempt
	engine.advance()                # s04 (teach)
	var granted: int = engine.save_progress(save)
	if granted != 0 or save.add_calls != 0:
		failures.append("saving mid-lesson must not grant stars")
	var stored: Variant = save.get_setting("tutorProgress", null)
	if typeof(stored) != TYPE_DICTIONARY or not (stored as Dictionary).has(FIRST_LESSON_ID):
		failures.append("progress must live under settings.tutorProgress[lessonId], got %s" % str(stored))
		return failures
	var entry: Dictionary = (stored as Dictionary)[FIRST_LESSON_ID]
	for key: String in ["stepIndex", "stepCount", "correctFirstTry", "completed", "rewardGranted"]:
		if not entry.has(key):
			failures.append("tutorProgress entry missing '%s'" % key)
	for key: String in entry.keys():
		if String(key).contains("_"):
			failures.append("tutorProgress key '%s' is not camelCase" % str(key))
	if int(entry.get("stepIndex", -1)) != 3 or int(entry.get("correctFirstTry", -1)) != 1:
		failures.append("saved stepIndex/correctFirstTry expected 3/1, got %s/%s" % [str(entry.get("stepIndex")), str(entry.get("correctFirstTry"))])

	var resumed: RefCounted = LessonEngineScript.new()
	resumed.load_lesson(FIRST_LESSON_ID)
	if not resumed.load_progress(save):
		failures.append("load_progress() should report an applied entry")
	var progress: Dictionary = resumed.progress()
	if int(progress.get("stepIndex", -1)) != 3 or int(progress.get("correctFirstTry", -1)) != 1 or bool(progress.get("completed", true)):
		failures.append("resumed progress mismatch: %s" % str(progress))
	if String(resumed.current_step().get("stepId", "")) != "s04_apple_recap":
		failures.append("resumed engine should be on s04_apple_recap, is on %s" % str(resumed.current_step().get("stepId", "")))
	for key: String in ["lessonId", "stepIndex", "stepCount", "correctFirstTry", "completed"]:
		if not progress.has(key):
			failures.append("progress() missing contract key '%s'" % key)
	if String(progress.get("lessonId", "")) != FIRST_LESSON_ID or int(progress.get("stepCount", 0)) != 18:
		failures.append("progress() lessonId/stepCount wrong: %s" % str(progress))

	# A second lesson's entry does not clobber the first.
	var other: RefCounted = LessonEngineScript.new()
	other.load_lesson("animals_cat_dog")
	other.advance()
	other.save_progress(save)
	var both: Dictionary = save.get_setting("tutorProgress", {})
	if not both.has(FIRST_LESSON_ID) or not both.has("animals_cat_dog"):
		failures.append("tutorProgress must hold one entry per lessonId, got keys %s" % str(both.keys()))

	# Corrupt / foreign entries are tolerated.
	save.settings["tutorProgress"] = {FIRST_LESSON_ID: "garbage"}
	var tolerant: RefCounted = LessonEngineScript.new()
	tolerant.load_lesson(FIRST_LESSON_ID)
	if tolerant.load_progress(save):
		failures.append("a non-dictionary entry must be ignored")
	if int(tolerant.progress().get("stepIndex", -1)) != 0:
		failures.append("corrupt entry must leave the engine at step 0")
	save.settings["tutorProgress"] = {FIRST_LESSON_ID: {"stepIndex": 999, "stepCount": 18, "correctFirstTry": 99, "completed": false, "rewardGranted": false}}
	var clamped: RefCounted = LessonEngineScript.new()
	clamped.load_lesson(FIRST_LESSON_ID)
	clamped.load_progress(save)
	if not clamped.is_complete():
		failures.append("an out-of-range stepIndex clamps to complete rather than crashing")
	save.settings["tutorProgress"] = {FIRST_LESSON_ID: {"stepIndex": 5, "stepCount": 7, "correctFirstTry": 2, "completed": false, "rewardGranted": true}}
	var changed: RefCounted = LessonEngineScript.new()
	changed.load_lesson(FIRST_LESSON_ID)
	changed.load_progress(save)
	if int(changed.progress().get("stepIndex", -1)) != 0 or not bool(changed.progress().get("rewardGranted", false)):
		failures.append("a stepCount mismatch restarts the lesson but keeps rewardGranted: %s" % str(changed.progress()))
	return failures


func _test_completion_awards_exactly_once():
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var engine: RefCounted = LessonEngineScript.new()
	if not engine.load_lesson(FIRST_LESSON_ID):
		return ["could not load %s" % FIRST_LESSON_ID]
	var completed_signals: Array = []
	engine.lesson_completed.connect(func(lesson_id: String, stars: int, sticker_id: String) -> void:
		completed_signals.append({"lessonId": lesson_id, "stars": stars, "stickerId": sticker_id}))
	var reward_signals: Array = []
	engine.reward_granted.connect(func(lesson_id: String, stars: int, sticker_id: String) -> void:
		reward_signals.append({"lessonId": lesson_id, "stars": stars, "stickerId": sticker_id}))

	var last_ask_action: String = ""
	var guard: int = 0
	while not engine.is_complete() and guard < 100:
		guard += 1
		var step: Dictionary = engine.current_step()
		if String(step.get("kind", "")) == "ask":
			var result: Dictionary = engine.evaluate(String((step.get("expectedAnswers", []) as Array)[0]))
			last_ask_action = String(result.get("lessonAction", ""))
			if String(result.get("outcome", "")) != "correct":
				failures.append("%s: canonical answer judged %s" % [str(step.get("stepId")), str(result.get("outcome"))])
		engine.save_progress(save)   # saving every step, as the scene will
		engine.advance()
	if save.add_calls != 0:
		failures.append("stars were granted before the celebrate step was passed (%d calls)" % save.add_calls)
	if last_ask_action != "complete":
		failures.append("the final ask should return lessonAction 'complete', got '%s'" % last_ask_action)
	if not engine.is_complete():
		failures.append("lesson did not complete after %d steps" % guard)
	if completed_signals.size() != 1:
		failures.append("lesson_completed should fire once, fired %d" % completed_signals.size())

	var granted: int = engine.save_progress(save)
	if granted != 3 or save.add_calls != 1 or save.stars != 3:
		failures.append("completion should grant 3 stars once: granted=%d calls=%d stars=%d" % [granted, save.add_calls, save.stars])
	if reward_signals.size() != 1 or String(reward_signals[0].get("stickerId", "")) != "appleSticker":
		failures.append("reward_granted should fire once with the sticker, got %s" % str(reward_signals))
	engine.save_progress(save)
	engine.save_progress(save)
	if save.add_calls != 1:
		failures.append("repeated save_progress() paid again (%d calls)" % save.add_calls)
	if int(engine.progress().get("correctFirstTry", 0)) != engine.ask_count():
		failures.append("all-correct run should count every ask as first try")

	# Restart from disk: still paid, still not paid twice.
	var again: RefCounted = LessonEngineScript.new()
	again.load_lesson(FIRST_LESSON_ID)
	again.load_progress(save)
	if not again.is_complete():
		failures.append("reloaded completed lesson should be complete")
	again.save_progress(save)
	if save.add_calls != 1:
		failures.append("reloaded completed lesson paid again")
	# Replaying is welcome, paying twice is not.
	again.restart()
	if again.is_complete() or String(again.current_step().get("stepId", "")) != "s01_hello":
		failures.append("restart() should return to the greeting")
	while not again.is_complete():
		var step: Dictionary = again.current_step()
		if String(step.get("kind", "")) == "ask":
			again.evaluate(String((step.get("expectedAnswers", []) as Array)[0]))
		again.advance()
	again.save_progress(save)
	if save.add_calls != 1 or save.stars != 3:
		failures.append("a replay must not pay a second time (calls=%d stars=%d)" % [save.add_calls, save.stars])
	# Stars only from the completion block: the progress never carries a star count of its own.
	var entry: Dictionary = (save.get_setting("tutorProgress", {}) as Dictionary).get(FIRST_LESSON_ID, {})
	if entry.has("stars"):
		failures.append("tutorProgress must not store stars; the profile star total is the only ledger")
	return failures


func _test_every_lesson_completes_both_ways():
	var failures: Array = []
	for lesson_id: Variant in LessonValidatorScript.shipped_lesson_ids():
		# All correct.
		var save_ok: FakeSave = FakeSave.new()
		var engine: RefCounted = LessonEngineScript.new()
		if not engine.load_lesson(String(lesson_id)):
			failures.append("%s: engine could not load it" % str(lesson_id))
			continue
		var guard: int = 0
		while not engine.is_complete() and guard < 200:
			guard += 1
			var step: Dictionary = engine.current_step()
			if String(step.get("kind", "")) == "ask":
				for synonym: Variant in step.get("expectedAnswers", []):
					var probe: RefCounted = LessonEngineScript.new()
					probe.load_lesson(String(lesson_id))
					while String(probe.current_step().get("stepId", "")) != String(step.get("stepId", "")):
						probe.advance()
					if String(probe.evaluate(String(synonym)).get("outcome", "")) != "correct":
						failures.append("%s/%s: synonym '%s' not accepted" % [str(lesson_id), str(step.get("stepId")), str(synonym)])
				engine.evaluate(String((step.get("expectedAnswers", []) as Array)[0]))
			engine.advance()
		if not engine.is_complete():
			failures.append("%s: did not complete with correct answers" % str(lesson_id))
		var stars: int = engine.save_progress(save_ok)
		if stars < 1 or save_ok.add_calls != 1:
			failures.append("%s: completion should pay its stars once (stars=%d calls=%d)" % [str(lesson_id), stars, save_ok.add_calls])

		# All wrong: still reaches the celebrate step, still pays. Never a fail.
		var save_bad: FakeSave = FakeSave.new()
		var struggling: RefCounted = LessonEngineScript.new()
		struggling.load_lesson(String(lesson_id))
		var reached_celebrate: bool = false
		guard = 0
		while not struggling.is_complete() and guard < 400:
			guard += 1
			var step: Dictionary = struggling.current_step()
			if String(step.get("kind", "")) == "celebrate":
				reached_celebrate = true
			if String(step.get("kind", "")) == "ask":
				var result: Dictionary = {}
				var tries: int = 0
				while tries < 5:
					tries += 1
					result = struggling.evaluate("zebra xylophone")
					if String(result.get("outcome", "")) == "correct":
						failures.append("%s/%s: nonsense judged correct" % [str(lesson_id), str(step.get("stepId"))])
					if String(result.get("lessonAction", "")) in ["next_question", "complete"]:
						break
				if tries != 3:
					failures.append("%s/%s: expected to move on after exactly 3 misses, took %d" % [str(lesson_id), str(step.get("stepId")), tries])
			struggling.advance()
		if not reached_celebrate or not struggling.is_complete():
			failures.append("%s: a struggling child must still reach the celebrate step" % str(lesson_id))
		struggling.save_progress(save_bad)
		if save_bad.add_calls != 1:
			failures.append("%s: a struggling child still earns the completion stars once" % str(lesson_id))
		if int(struggling.progress().get("correctFirstTry", -1)) != 0:
			failures.append("%s: correctFirstTry should be 0 on an all-miss run" % str(lesson_id))
	return failures


func _test_engine_edge_cases():
	var failures: Array = []
	var engine: RefCounted = LessonEngineScript.new()
	if engine.load_lesson("no_such_lesson"):
		failures.append("load_lesson() must return false for a missing lesson")
	if not engine.is_complete():
		failures.append("an engine with no lesson is complete so no loop can spin on it")
	if not engine.current_step().is_empty():
		failures.append("current_step() must be empty with no lesson")
	var empty_result: Dictionary = engine.evaluate("apple")
	if String(empty_result.get("lessonAction", "")) != "complete":
		failures.append("evaluate() with no lesson should answer 'complete', got %s" % str(empty_result.get("lessonAction")))
	if engine.save_progress(FakeSave.new()) != 0:
		failures.append("save_progress() with no lesson must not grant stars")

	engine.load_lesson(FIRST_LESSON_ID)
	var on_teach: Dictionary = engine.evaluate("hello")
	if String(on_teach.get("lessonAction", "")) != "next_question" or String(on_teach.get("outcome", "")) != "correct":
		failures.append("evaluate() on a teach step should acknowledge with next_question, got %s" % str(on_teach))
	if engine.attempts() != 0:
		failures.append("evaluate() on a teach step must not count an attempt")
	var step: Dictionary = engine.current_step()
	for key: String in ["stepId", "kind", "questionText", "teachText", "visualAssetId", "expectedAnswers", "objective", "hint", "encouragement"]:
		if not step.has(key):
			failures.append("current_step() missing contract key '%s'" % key)
	# Save service without the optional methods: nothing crashes, nothing paid.
	var bare: RefCounted = RefCounted.new()
	engine.save_progress(bare)
	if engine.load_progress(bare):
		failures.append("load_progress() on a bare object should report nothing applied")
	# Null save service is tolerated.
	engine.save_progress(null)
	engine.load_progress(null)
	return failures


# --- helpers ------------------------------------------------------------------------

func _load_first_lesson() -> Dictionary:
	var data: Variant = LessonValidatorScript.load_json("%s/%s.json" % [LessonValidatorScript.LESSONS_DIR, FIRST_LESSON_ID])
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _engine_at_first_ask() -> RefCounted:
	var engine: RefCounted = LessonEngineScript.new()
	if not engine.load_lesson(FIRST_LESSON_ID):
		return null
	while not engine.is_complete() and String(engine.current_step().get("kind", "")) != "ask":
		engine.advance()
	return engine


func _mini_lesson(answers_a: Array, answers_b: Array, answers_c: Array) -> Dictionary:
	return {
		"schemaVersion": 1,
		"lessonId": "mini",
		"subjectId": "colors",
		"title": "Mini",
		"ageBand": "3-6",
		"targetDurationSeconds": 60,
		"language": "en",
		"helperLanguageKeys": [],
		"steps": [
			{"stepId": "s1", "kind": "teach", "teachText": "Hi!"},
			{"stepId": "s2", "kind": "ask", "questionText": "What colour?", "visualAssetId": "color_red", "expectedAnswers": answers_a, "objective": "o", "hint": "h", "encouragement": "e", "successLine": "s"},
			{"stepId": "s3", "kind": "ask", "questionText": "What animal?", "visualAssetId": "cat", "expectedAnswers": answers_b, "objective": "o", "hint": "h", "encouragement": "e", "successLine": "s"},
			{"stepId": "s4", "kind": "ask", "questionText": "What fruit?", "visualAssetId": "grapes_purple", "expectedAnswers": answers_c, "objective": "o", "hint": "h", "encouragement": "e", "successLine": "s"},
			{"stepId": "s5", "kind": "celebrate", "teachText": "Yay!"},
		],
		"completion": {"stars": 1, "stickerId": "starSticker"},
	}


func _any_contains(problems: Array, needle: String) -> bool:
	for problem: Variant in problems:
		if str(problem).contains(needle):
			return true
	return false
