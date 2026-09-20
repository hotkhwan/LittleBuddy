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
## - completion awards its stars exactly once, across saves and reloads;
## - the evening addendum: choose routing, sound steps with reactions, the
##   interjection table, and the owner's acceptance dialogue end to end.

const LessonEngineScript := preload("res://scripts/tutor/lesson/lesson_engine.gd")
const LessonValidatorScript := preload("res://scripts/tutor/lesson/lesson_validator.gd")
const AnswerMatcherScript := preload("res://scripts/tutor/lesson/answer_matcher.gd")

const FIRST_LESSON_ID: String = "english_colors_fruits"
const CONTRACT_ALLOWLIST: Array[String] = [
	"apple_red", "banana_yellow", "cat", "dog", "number_1", "number_2", "number_3",
	"color_blue", "color_green", "color_red", "color_yellow", "orange_orange", "grapes_purple",
]
const EXPECTED_SUBJECTS: Array[String] = ["english_basics", "numbers", "colors", "animals", "everyday_life"]
const ENTRY_LESSON_ID: String = "welcome_choose"
const ANIMALS_LESSON_ID: String = "animals_cat_dog"


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
	failures.append_array(_test_choose_routing())
	failures.append_array(_test_sound_steps())
	failures.append_array(_test_interjection_table())
	failures.append_array(_test_owner_dialogue())
	failures.append_array(_test_schema_rejects_bad_new_kinds())
	return failures


# --- content ---------------------------------------------------------------------

func _test_shipped_content_validates():
	var failures: Array = []
	var problems: Array = LessonValidatorScript.validate_shipped()
	for problem: Variant in problems:
		failures.append("shipped tutor content: %s" % str(problem))
	var ids: Array = LessonValidatorScript.shipped_lesson_ids()
	if ids.size() < 6:
		failures.append("expected at least 6 shipped lessons (menu plus one per subject), found %d" % ids.size())
	if not ids.has(ENTRY_LESSON_ID) or LessonEngineScript.entry_lesson_id() != ENTRY_LESSON_ID:
		failures.append("subjects.json must point the entry at %s" % ENTRY_LESSON_ID)
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
		if String(lesson_id) == ENTRY_LESSON_ID:
			continue  # the menu routes; _test_choose_routing covers it
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


# --- addendum: choose, sound, interjections, owner dialogue ---------------------------

func _test_choose_routing():
	var failures: Array = []
	var table: Array = [
		# transcript, expected nextLessonId, expected outcome
		["Animals!", ANIMALS_LESSON_ID, "correct"],
		["I want the cat", ANIMALS_LESSON_ID, "correct"],
		["dog", ANIMALS_LESSON_ID, "correct"],
		["fruits", FIRST_LESSON_ID, "correct"],
		["colours please", FIRST_LESSON_ID, "correct"],
		["numbers", "numbers_one_two_three", "correct"],
		["I want to count", "numbers_one_two_three", "correct"],
		["everyday things", "everyday_cup_spoon", "correct"],
		["red and blue", "colors_red_blue", "correct"],
		["anything", FIRST_LESSON_ID, "correct"],
		["you choose", FIRST_LESSON_ID, "correct"],
		["I don't know", FIRST_LESSON_ID, "correct"],
	]
	for row: Variant in table:
		var engine: RefCounted = LessonEngineScript.new()
		if not engine.load_lesson(ENTRY_LESSON_ID):
			return ["could not load %s" % ENTRY_LESSON_ID]
		var step: Dictionary = engine.current_step()
		if String(step.get("kind", "")) != "choose" or String(step.get("questionText", "")) != "Hi! What would you like to learn today?":
			failures.append("entry lesson should open with the choose question, got %s" % str(step))
			break
		var result: Dictionary = engine.evaluate(String(row[0]))
		if String(result.get("lessonAction", "")) != "switch_lesson":
			failures.append("choose('%s') expected switch_lesson, got %s" % [str(row[0]), str(result.get("lessonAction"))])
		if String(result.get("nextLessonId", "")) != String(row[1]):
			failures.append("choose('%s') expected %s, got %s" % [str(row[0]), str(row[1]), str(result.get("nextLessonId"))])
		if String(result.get("outcome", "")) != String(row[2]):
			failures.append("choose('%s') outcome expected %s, got %s" % [str(row[0]), str(row[2]), str(result.get("outcome"))])
		if String(result.get("line", "")).is_empty():
			failures.append("choose('%s') must give Aliz a line" % str(row[0]))
		# The engine can load the target and continue.
		if not engine.switch_lesson(String(result.get("nextLessonId", ""))):
			failures.append("switch_lesson(%s) failed" % str(result.get("nextLessonId")))
		elif engine.lesson_id() != String(row[1]) or engine.is_complete():
			failures.append("after switch the engine should be at the start of %s" % str(row[1]))

	# Escalation on the menu: retry -> hint (lists the subjects) -> default lesson.
	var stuck: RefCounted = LessonEngineScript.new()
	stuck.load_lesson(ENTRY_LESSON_ID)
	var first: Dictionary = stuck.evaluate("zebra")
	var second: Dictionary = stuck.evaluate("")
	var third: Dictionary = stuck.evaluate("zebra")
	if String(first.get("lessonAction", "")) != "retry" or String(second.get("lessonAction", "")) != "give_hint":
		failures.append("menu escalation should be retry then give_hint, got %s then %s" % [str(first.get("lessonAction")), str(second.get("lessonAction"))])
	if not String(second.get("line", "")).contains("animals") or not String(second.get("line", "")).contains("numbers"):
		failures.append("the menu hint should list the subjects, got '%s'" % str(second.get("line")))
	if String(third.get("lessonAction", "")) != "switch_lesson" or String(third.get("nextLessonId", "")) != FIRST_LESSON_ID or String(third.get("outcome", "")) != "unclear":
		failures.append("third unclear on the menu should route to the default lesson as unclear, got %s" % str(third))
	if String(third.get("line", "")) != "Okay! Let's start with fruits and colours!":
		failures.append("default route should speak defaultLine, got '%s'" % str(third.get("line")))
	# The menu pays nothing, ever.
	var save: FakeSave = FakeSave.new()
	stuck.advance()
	if stuck.save_progress(save) != 0 or save.add_calls != 0:
		failures.append("the menu lesson must never grant stars")
	# Options for the subject cards.
	var menu: RefCounted = LessonEngineScript.new()
	menu.load_lesson(ENTRY_LESSON_ID)
	var options: Array = menu.choose_options()
	if options.size() != 5:
		failures.append("choose_options() should list the five subjects, got %d" % options.size())
	var expected_union: Array = menu.current_step().get("expectedAnswers", [])
	if not expected_union.has("animals") or not expected_union.has("anything"):
		failures.append("a choose step's expectedAnswers should be the union of routes and defaults")
	# switch_lesson with a save service resumes; a completed lesson restarts without paying again.
	var progress_save: FakeSave = FakeSave.new()
	var played: RefCounted = LessonEngineScript.new()
	played.load_lesson(ANIMALS_LESSON_ID)
	played.advance()
	played.advance()
	played.save_progress(progress_save)
	var resume: RefCounted = LessonEngineScript.new()
	resume.load_lesson(ENTRY_LESSON_ID)
	resume.evaluate("animals")
	resume.switch_lesson(ANIMALS_LESSON_ID, progress_save)
	if resume.step_index() != 2:
		failures.append("switch_lesson with a save service should resume at the saved step, got %d" % resume.step_index())
	while not played.is_complete():
		played.advance()
	played.save_progress(progress_save)
	var replay: RefCounted = LessonEngineScript.new()
	replay.switch_lesson(ANIMALS_LESSON_ID, progress_save)
	if replay.is_complete() or replay.step_index() != 0:
		failures.append("switching into a completed lesson should restart it")
	while not replay.is_complete():
		replay.advance()
	replay.save_progress(progress_save)
	if progress_save.add_calls != 1:
		failures.append("a replay reached through switch_lesson must not pay twice (%d)" % progress_save.add_calls)
	return failures


func _test_sound_steps():
	var failures: Array = []
	var cat_sounds: Array = ["meow", "Meow!", "miaow", "mew", "meow meow", "um meow", "MEOW"]
	for sound: Variant in cat_sounds:
		var engine: RefCounted = _engine_at_step(ANIMALS_LESSON_ID, "s03_cat_sound")
		if engine == null:
			return ["could not reach the cat sound step"]
		var result: Dictionary = engine.evaluate(String(sound))
		if String(result.get("outcome", "")) != "correct":
			failures.append("cat sound '%s' should be accepted, got %s" % [str(sound), str(result.get("outcome"))])
			continue
		if String(result.get("line", "")) != "Meow! You're amazing!":
			failures.append("cat sound success line wrong: '%s'" % str(result.get("line")))
		var reaction: Dictionary = result.get("reaction", {})
		if String(reaction.get("gesture", "")) != "clap" or String(reaction.get("sfx", "")) != "laugh" or String(reaction.get("alizSound", "")) != "Meow!":
			failures.append("cat sound reaction expected clap/laugh/Meow!, got %s" % str(reaction))
	var dog_sounds: Array = ["woof", "bark", "ruff", "arf", "bow wow", "woof woof"]
	for sound: Variant in dog_sounds:
		var engine: RefCounted = _engine_at_step(ANIMALS_LESSON_ID, "s05_dog_sound")
		var result: Dictionary = engine.evaluate(String(sound))
		if String(result.get("outcome", "")) != "correct" or String(result.get("reaction", {}).get("alizSound", "")) != "Woof!":
			failures.append("dog sound '%s' should be accepted with Woof!, got %s" % [str(sound), str(result)])
	# A wrong animal sound is a miss, not a fail, and no reaction plays.
	var wrong: RefCounted = _engine_at_step(ANIMALS_LESSON_ID, "s03_cat_sound")
	var miss: Dictionary = wrong.evaluate("woof")
	if String(miss.get("lessonAction", "")) != "retry" or not (miss.get("reaction", {}) as Dictionary).is_empty():
		failures.append("a dog sound on the cat step should retry with no reaction, got %s" % str(miss))
	wrong.evaluate("woof")
	var taught: Dictionary = wrong.evaluate("woof")
	if String(taught.get("line", "")) != "A cat says meow! Say meow." or String(taught.get("lessonAction", "")) != "next_question":
		failures.append("third miss on a sound step teaches the sound, got %s" % str(taught))
	# Sound steps are scored like asks and the current_step() exposes the reaction.
	var step: Dictionary = _engine_at_step(ANIMALS_LESSON_ID, "s03_cat_sound").current_step()
	if String(step.get("kind", "")) != "sound" or String((step.get("reaction", {}) as Dictionary).get("gesture", "")) != "clap":
		failures.append("current_step() on a sound step should expose kind and reaction: %s" % str(step))
	var animals: Dictionary = _load_lesson_dict(ANIMALS_LESSON_ID)
	var estimate: int = LessonValidatorScript.estimate_duration_seconds(animals, LessonValidatorScript.load_schema())
	if estimate > 90:
		failures.append("animals lesson estimate %d s exceeds the 90 s budget" % estimate)
	var kinds: Array = []
	for raw: Variant in animals.get("steps", []):
		kinds.append(String((raw as Dictionary).get("kind", "")))
	if kinds != ["teach", "ask", "sound", "ask", "sound", "celebrate"]:
		failures.append("animals lesson should be teach/ask/sound/ask/sound/celebrate, got %s" % str(kinds))
	if String((animals["steps"][0] as Dictionary).get("teachText", "")) != "Yay! Let's learn about animals!":
		failures.append("animals lesson must open with the owner's line")
	return failures


func _test_interjection_table():
	var failures: Array = []
	# On the cat question of the animals lesson.
	var table: Array = [
		# transcript, handled, lessonAction, target (stepId or lessonId), isAnswer
		["Wait! I want a dog!", true, "jump_step", "s04_dog", false],
		["puppy", true, "jump_step", "s04_dog", false],
		["I want numbers", true, "switch_lesson", "numbers_one_two_three", false],
		["can we do fruits", true, "switch_lesson", FIRST_LESSON_ID, false],
		["stop", true, "end_session", "", false],
		["I'm done", true, "end_session", "", false],
		["bye bye Aliz", true, "end_session", "", false],
		["cat", false, "", "", true],
		["it's a kitty", false, "", "", true],
		["zebra", false, "", "", false],
		["", false, "", "", false],
		["step", false, "", "", false],
	]
	for row: Variant in table:
		var engine: RefCounted = _engine_at_step(ANIMALS_LESSON_ID, "s02_cat")
		if engine == null:
			return ["could not reach the cat step"]
		var result: Dictionary = engine.handle_interjection(String(row[0]))
		if bool(result.get("handled", false)) != bool(row[1]):
			failures.append("interjection('%s') handled expected %s, got %s" % [str(row[0]), str(row[1]), str(result)])
			continue
		if String(result.get("lessonAction", "")) != String(row[2]):
			failures.append("interjection('%s') action expected '%s', got '%s'" % [str(row[0]), str(row[2]), str(result.get("lessonAction"))])
		var target: String = String(result.get("nextStepId", result.get("nextLessonId", "")))
		if target != String(row[3]):
			failures.append("interjection('%s') target expected '%s', got '%s'" % [str(row[0]), str(row[3]), target])
		if bool(result.get("isAnswer", false)) != bool(row[4]):
			failures.append("interjection('%s') isAnswer expected %s" % [str(row[0]), str(row[4])])
		if bool(row[1]) and String(result.get("line", "")).is_empty():
			failures.append("interjection('%s') needs a line" % str(row[0]))
		if String(row[2]) == "jump_step":
			if String(engine.current_step().get("stepId", "")) != String(row[3]):
				failures.append("jump_step should have moved the engine to %s" % str(row[3]))
			if String(result.get("line", "")) != "Okay! Let's see the dog!":
				failures.append("jump line expected 'Okay! Let's see the dog!', got '%s'" % str(result.get("line")))
		else:
			if String(engine.current_step().get("stepId", "")) != "s02_cat":
				failures.append("interjection('%s') must not move the engine" % str(row[0]))
		if engine.attempts() != 0:
			failures.append("interjections never count as attempts")
		if String(result.get("lessonAction", "")).contains("fail") or String(result.get("outcome", "")) == "incorrect":
			failures.append("interjections never fail")
	# In the fruits lesson: another fruit jumps; an animal switches; the current answer is an answer.
	var fruits: RefCounted = _engine_at_step(FIRST_LESSON_ID, "s03_apple_colour")
	var banana: Dictionary = fruits.handle_interjection("I want the banana")
	if String(banana.get("lessonAction", "")) != "jump_step" or String(banana.get("nextStepId", "")) != "s05_banana_name" or String(banana.get("line", "")) != "Okay! Let's see the banana!":
		failures.append("fruits interjection should jump to the banana: %s" % str(banana))
	var red: Dictionary = _engine_at_step(FIRST_LESSON_ID, "s03_apple_colour").handle_interjection("red")
	if bool(red.get("handled", true)) or not bool(red.get("isAnswer", false)):
		failures.append("'red' during the red question is an answer, not a topic switch: %s" % str(red))
	var to_animals: Dictionary = _engine_at_step(FIRST_LESSON_ID, "s03_apple_colour").handle_interjection("I want a dog")
	if String(to_animals.get("lessonAction", "")) != "switch_lesson" or String(to_animals.get("nextLessonId", "")) != ANIMALS_LESSON_ID:
		failures.append("naming an animal in the fruits lesson should switch to animals: %s" % str(to_animals))
	# Jumping back keeps the lesson completable and paid once.
	var back: RefCounted = _engine_at_step(ANIMALS_LESSON_ID, "s04_dog")
	back.handle_interjection("I want the cat")
	if String(back.current_step().get("stepId", "")) != "s02_cat":
		failures.append("interjection should jump back to the cat")
	var save: FakeSave = FakeSave.new()
	while not back.is_complete():
		var step: Dictionary = back.current_step()
		if step.get("kind", "") in ["ask", "sound"]:
			back.evaluate(String((step.get("expectedAnswers", []) as Array)[0]))
		back.advance()
	back.save_progress(save)
	back.save_progress(save)
	if save.add_calls != 1:
		failures.append("after a jump the lesson still pays exactly once")
	return failures


## The owner's acceptance dialogue, as the scene will drive it.
func _test_owner_dialogue():
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var engine: RefCounted = LessonEngineScript.new()
	var transcript_log: Array = []
	var aliz: Callable = func(text: String) -> void:
		transcript_log.append("Aliz: %s" % text)
	var child: Callable = func(text: String) -> void:
		transcript_log.append("Child: %s" % text)

	var expect: Callable = func(condition: bool, message: String) -> void:
		if not condition:
			failures.append("owner dialogue: %s (log so far: %s)" % [message, str(transcript_log)])

	if not engine.load_lesson(LessonEngineScript.entry_lesson_id()):
		return ["owner dialogue: entry lesson did not load"]
	aliz.call(engine.current_step().get("questionText", ""))
	child.call("Animals!")
	var pick: Dictionary = engine.evaluate("Animals!")
	expect.call(String(pick.get("lessonAction", "")) == "switch_lesson" and String(pick.get("nextLessonId", "")) == ANIMALS_LESSON_ID, "'Animals!' routes to the animals lesson")
	aliz.call(pick.get("line", ""))
	engine.switch_lesson(String(pick.get("nextLessonId", "")), save)

	var greet: Dictionary = engine.current_step()
	expect.call(String(greet.get("teachText", "")) == "Yay! Let's learn about animals!", "the animals lesson greets")
	aliz.call(greet.get("teachText", ""))
	engine.advance()

	var cat: Dictionary = engine.current_step()
	expect.call(String(cat.get("questionText", "")) == "What animal is this?" and String(cat.get("visualAssetId", "")) == "cat", "cat question with the cat card")
	aliz.call(cat.get("questionText", ""))
	# The child barges in before Aliz finishes: a topic switch, not an answer.
	child.call("Wait! I want a dog!")
	var barge: Dictionary = engine.handle_interjection("Wait! I want a dog!")
	expect.call(bool(barge.get("handled", false)) and String(barge.get("lessonAction", "")) == "jump_step" and String(barge.get("nextStepId", "")) == "s04_dog", "'Wait! I want a dog!' jumps to the dog item")
	expect.call(String(barge.get("line", "")) == "Okay! Let's see the dog!", "jump line")
	aliz.call(barge.get("line", ""))

	var dog: Dictionary = engine.current_step()
	expect.call(String(dog.get("stepId", "")) == "s04_dog" and String(dog.get("visualAssetId", "")) == "dog", "dog question with the dog card")
	aliz.call(dog.get("questionText", ""))
	child.call("Dog!")
	var dog_answer: Dictionary = engine.evaluate("Dog!")
	expect.call(String(dog_answer.get("outcome", "")) == "correct" and String(dog_answer.get("line", "")) == "Great! It's a dog!", "'Dog!' is correct")
	aliz.call(dog_answer.get("line", ""))
	engine.advance()

	var dog_sound: Dictionary = engine.current_step()
	expect.call(String(dog_sound.get("questionText", "")) == "Can you make a dog sound?", "dog sound question")
	aliz.call(dog_sound.get("questionText", ""))
	child.call("Woof woof!")
	var woof: Dictionary = engine.evaluate("Woof woof!")
	expect.call(String(woof.get("line", "")) == "Woof! You're amazing!", "woof success line")
	var woof_reaction: Dictionary = woof.get("reaction", {})
	expect.call(String(woof_reaction.get("gesture", "")) == "clap" and String(woof_reaction.get("sfx", "")) == "laugh" and String(woof_reaction.get("alizSound", "")) == "Woof!", "Aliz claps, laughs and says Woof!")
	expect.call(String(woof.get("lessonAction", "")) == "next_question", "the cat is still waiting, so not complete yet")
	aliz.call("%s (%s, %s) %s" % [woof_reaction.get("alizSound", ""), woof_reaction.get("gesture", ""), woof_reaction.get("sfx", ""), woof.get("line", "")])
	engine.advance()

	# Back to the cat the jump left behind.
	var back: Dictionary = engine.current_step()
	expect.call(String(back.get("stepId", "")) == "s02_cat", "advance() returns to the skipped cat question, not the celebrate")
	aliz.call(back.get("questionText", ""))
	child.call("Cat")
	var cat_answer: Dictionary = engine.evaluate("Cat")
	expect.call(String(cat_answer.get("outcome", "")) == "correct", "'Cat' is correct")
	aliz.call(cat_answer.get("line", ""))
	engine.advance()

	var cat_sound: Dictionary = engine.current_step()
	expect.call(String(cat_sound.get("questionText", "")) == "Can you make a cat sound?", "cat sound question")
	aliz.call(cat_sound.get("questionText", ""))
	child.call("Meow")
	var meow: Dictionary = engine.evaluate("Meow")
	expect.call(String(meow.get("line", "")) == "Meow! You're amazing!", "meow success line")
	var reaction: Dictionary = meow.get("reaction", {})
	expect.call(String(reaction.get("gesture", "")) == "clap" and String(reaction.get("sfx", "")) == "laugh" and String(reaction.get("alizSound", "")) == "Meow!", "Aliz claps, laughs and says Meow!")
	expect.call(String(meow.get("lessonAction", "")) == "complete", "the last open question completes")
	aliz.call("%s (%s, %s) %s" % [reaction.get("alizSound", ""), reaction.get("gesture", ""), reaction.get("sfx", ""), meow.get("line", "")])
	engine.advance()

	var celebrate: Dictionary = engine.current_step()
	expect.call(String(celebrate.get("kind", "")) == "celebrate", "celebrate step reached")
	aliz.call(celebrate.get("teachText", ""))
	engine.advance()
	expect.call(engine.is_complete(), "lesson complete")
	var stars: int = engine.save_progress(save)
	expect.call(stars == 1 and save.add_calls == 1, "one star paid once")
	child.call("I'm done")
	var done: Dictionary = engine.handle_interjection("I'm done")
	expect.call(String(done.get("lessonAction", "")) == "end_session", "'I'm done' ends the session")
	aliz.call(done.get("line", ""))
	expect.call(engine.progress().get("correctFirstTry", 0) == 4, "every answer counted first try")
	if failures.is_empty():
		print("      owner dialogue:")
		for line: Variant in transcript_log:
			print("        %s" % str(line))
	return failures


func _test_schema_rejects_bad_new_kinds():
	var failures: Array = []
	var schema: Dictionary = LessonValidatorScript.load_schema()
	var allowlist: Array = LessonValidatorScript.load_allowlist()
	var lessons: Dictionary = LessonValidatorScript.load_shipped_lessons()
	var subjects: Variant = LessonValidatorScript.load_json(LessonValidatorScript.SUBJECTS_PATH)
	var context: Dictionary = {"lessons": lessons, "subjects": subjects}
	var animals: Dictionary = _load_lesson_dict(ANIMALS_LESSON_ID)
	var menu: Dictionary = _load_lesson_dict(ENTRY_LESSON_ID)
	if not LessonValidatorScript.validate_lesson(animals, schema, allowlist, [], context).is_empty() \
			or not LessonValidatorScript.validate_lesson(menu, schema, allowlist, [], context).is_empty():
		failures.append("baseline animals/menu lessons must validate before the negative cases mean anything")
		return failures
	var cases: Array = [
		{"base": animals, "name": "sound without reaction", "mutate": func(l: Dictionary) -> void: (l["steps"][2] as Dictionary).erase("reaction"), "expect": "reaction"},
		{"base": animals, "name": "bad gesture", "mutate": func(l: Dictionary) -> void: ((l["steps"][2] as Dictionary)["reaction"] as Dictionary)["gesture"] = "backflip", "expect": "backflip"},
		{"base": animals, "name": "bad sfx", "mutate": func(l: Dictionary) -> void: ((l["steps"][2] as Dictionary)["reaction"] as Dictionary)["sfx"] = "explosion", "expect": "explosion"},
		{"base": animals, "name": "success line without the sound", "mutate": func(l: Dictionary) -> void: (l["steps"][2] as Dictionary)["successLine"] = "Great job!", "expect": "echo the sound"},
		{"base": animals, "name": "choose inside a lesson", "mutate": func(l: Dictionary) -> void: (l["steps"] as Array).insert(1, (menu["steps"][0] as Dictionary).duplicate(true)), "expect": "menu"},
		{"base": animals, "name": "bad itemId", "mutate": func(l: Dictionary) -> void: (l["steps"][1] as Dictionary)["itemId"] = "The Cat", "expect": "itemId"},
		{"base": animals, "name": "over budget", "mutate": func(l: Dictionary) -> void: l["targetDurationSeconds"] = 300, "expect": "estimated duration"},
		{"base": menu, "name": "menu with two steps", "mutate": func(l: Dictionary) -> void: (l["steps"] as Array).append({"stepId": "x", "kind": "teach", "teachText": "Hi"}), "expect": "menu lesson"},
		{"base": menu, "name": "route to unknown subject", "mutate": func(l: Dictionary) -> void: ((l["steps"][0] as Dictionary)["choices"] as Array).append({"subjectId": "space"}), "expect": "space"},
		{"base": menu, "name": "route to missing lesson", "mutate": func(l: Dictionary) -> void: ((l["steps"][0] as Dictionary)["choices"] as Array).append({"lessonId": "ghost", "answers": ["ghost"]}), "expect": "ghost"},
		{"base": menu, "name": "ambiguous answer", "mutate": func(l: Dictionary) -> void: (((l["steps"][0] as Dictionary)["choices"] as Array)[0] as Dictionary)["answers"] = ["numbers"], "expect": "also routes"},
		{"base": menu, "name": "menu with stars", "mutate": func(l: Dictionary) -> void: (l["completion"] as Dictionary)["stars"] = 2, "expect": "stickerId"},
		{"base": menu, "name": "choose missing default", "mutate": func(l: Dictionary) -> void: (l["steps"][0] as Dictionary).erase("defaultLessonId"), "expect": "defaultLessonId"},
		{"base": menu, "name": "menu wrong subjectId", "mutate": func(l: Dictionary) -> void: l["subjectId"] = "animals", "expect": "menu"},
	]
	for entry: Variant in cases:
		var case_data: Dictionary = entry
		var tampered: Dictionary = (case_data["base"] as Dictionary).duplicate(true)
		(case_data["mutate"] as Callable).call(tampered)
		var problems: Array = LessonValidatorScript.validate_lesson(tampered, schema, allowlist, [], context)
		if problems.is_empty():
			failures.append("validator accepted '%s'" % str(case_data["name"]))
		elif not _any_contains(problems, String(case_data["expect"])):
			failures.append("'%s': expected a problem mentioning '%s', got %s" % [str(case_data["name"]), str(case_data["expect"]), str(problems)])
	# Subjects index: duplicate keyword across subjects is rejected.
	var doc: Dictionary = (subjects as Dictionary).duplicate(true)
	((doc["subjects"][0] as Dictionary)["keywords"] as Array).append("dog")
	if not _any_contains(LessonValidatorScript.validate_subjects(doc, lessons), "belongs to both"):
		failures.append("a keyword shared by two subjects must be rejected")
	var no_entry: Dictionary = (subjects as Dictionary).duplicate(true)
	no_entry.erase("entryLessonId")
	if not _any_contains(LessonValidatorScript.validate_subjects(no_entry, lessons), "entryLessonId"):
		failures.append("subjects.json without entryLessonId must be rejected")
	return failures


func _load_lesson_dict(lesson_id: String) -> Dictionary:
	var data: Variant = LessonValidatorScript.load_json("%s/%s.json" % [LessonValidatorScript.LESSONS_DIR, lesson_id])
	return data if typeof(data) == TYPE_DICTIONARY else {}


## An engine positioned on `step_id` of `lesson_id`, every earlier question answered correctly.
func _engine_at_step(lesson_id: String, step_id: String) -> RefCounted:
	var engine: RefCounted = LessonEngineScript.new()
	if not engine.load_lesson(lesson_id):
		return null
	var guard: int = 0
	while not engine.is_complete() and String(engine.current_step().get("stepId", "")) != step_id and guard < 100:
		guard += 1
		var step: Dictionary = engine.current_step()
		if step.get("kind", "") in ["ask", "sound"]:
			engine.evaluate(String((step.get("expectedAnswers", []) as Array)[0]))
		engine.advance()
	if engine.is_complete():
		return null
	return engine
