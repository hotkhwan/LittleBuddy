class_name LessonEngine
extends RefCounted
## Deterministic owner of the Aliz Tutor educational progression.
##
## Contract: docs/ALIZ_TUTOR_CONTRACTS.md, section "LessonEngine (Agent A)".
## Pure GDScript, no nodes, no 3D types, no network. Everything the child sees
## as pass/fail, progression and reward comes from lesson JSON plus this file.
## An LLM (when the cloud flag is ever on) may rephrase a line; it may never
## change `expectedAnswers`, the step order, or the stars.
##
## ## Lifecycle, as the scene drives it
##
##     var engine := LessonEngine.new()
##     engine.load_lesson("english_colors_fruits")       # false -> show "Let's try together!" and go home
##     engine.load_progress(SaveService)                 # optional resume
##     while not engine.is_complete():
##         var step := engine.current_step()
##         match step.kind:
##             "teach", "celebrate": speak(step.teachText); engine.advance()
##             "ask":
##                 speak(step.questionText); show(step.visualAssetId)
##                 var result := engine.evaluate(transcript)
##                 speak(result.line)                        # success / encouragement / hint / answer line
##                 if result.lessonAction in ["next_question", "complete"]: engine.advance()
##                 # "retry" and "give_hint" stay on the same step: listen again
##         engine.save_progress(SaveService)             # cheap; also grants the completion reward once
##
## ## Retry policy (never a fail state)
##
## Per ask step, attempts are counted from 1:
## - match            -> `correct`,   `next_question` (or `complete` when no ask step remains)
## - 1st miss         -> `incorrect`/`unclear`, `retry`         with `encouragement`
## - 2nd miss         -> `incorrect`/`unclear`, `give_hint`     with `hint`
## - 3rd miss or more -> `unclear`,   `next_question` with the answer taught
##                       ("It's an apple! Say apple.") -- the child moves on.
## `unclear` (not `incorrect`) is reported for a blank transcript, and always
## on the third attempt, so no screen can ever tell the child they got it wrong.
## Stars are never subtracted; a lesson always reaches its celebrate step.
##
## ## Rewards
##
## `completion.stars` is granted exactly once per lessonId, by
## `save_progress()` after the lesson is complete, through the save service's
## `add_stars()`. The grant is recorded in `settings.tutorProgress[lessonId]`
## `.rewardGranted`, so a restart, a replay or a second `save_progress()` call
## never pays twice. Nothing else in the tutor is allowed to call `add_stars()`.
##
## ## Persistence
##
## `settings.tutorProgress` (camelCase) is a map keyed by lessonId:
## `{stepIndex, stepCount, correctFirstTry, completed, rewardGranted}`. The
## save service is duck-typed: it needs `get_setting(key, default)`,
## `set_setting(key, value)` and `add_stars(amount)`; anything missing is skipped
## with `has_method()` so a bare stub still runs.

signal step_changed(step: Dictionary)
signal lesson_completed(lesson_id: String, stars: int, sticker_id: String)
signal reward_granted(lesson_id: String, stars: int, sticker_id: String)

const LESSONS_DIR: String = "res://content/tutor/lessons"
## Preloaded by path (not by class_name) so this runs before the global class cache is warm.
const AnswerMatcherScript := preload("res://scripts/tutor/lesson/answer_matcher.gd")
const SUBJECTS_PATH: String = "res://content/tutor/subjects.json"
const PROGRESS_SETTING_KEY: String = "tutorProgress"

const KIND_TEACH: String = "teach"
const KIND_ASK: String = "ask"
const KIND_CELEBRATE: String = "celebrate"

const OUTCOME_CORRECT: String = "correct"
const OUTCOME_INCORRECT: String = "incorrect"
const OUTCOME_UNCLEAR: String = "unclear"

const ACTION_NEXT: String = "next_question"
const ACTION_RETRY: String = "retry"
const ACTION_HINT: String = "give_hint"
const ACTION_COMPLETE: String = "complete"

## Attempts before the answer is taught and the lesson moves on.
const MAX_ATTEMPTS: int = 3

const DEFAULT_ENCOURAGEMENT: String = "Let's try together!"
const DEFAULT_HINT: String = "Listen carefully. Let's try together!"
const DEFAULT_SUCCESS: String = "Great job!"

## Answers spoken without an article in the generated answer line
## ("It's red! Say red." rather than "It's a red!").
const BARE_WORDS: Array[String] = [
	"red", "blue", "yellow", "green", "orange", "purple", "pink", "white", "black", "brown",
	"one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
]

var _lesson: Dictionary = {}
var _lesson_id: String = ""
var _steps: Array = []
var _step_index: int = 0
var _attempts: int = 0
var _correct_first_try: int = 0
var _completed: bool = false
var _reward_granted: bool = false
## Optional override used by tests and tools: a lesson dictionary source
## keyed by lessonId. When empty, lessons are read from LESSONS_DIR.
var _lesson_source: Dictionary = {}


## Point the engine at in-memory lessons (tests, editors). `{lessonId: Dictionary}`.
func set_lesson_source(lessons_by_id: Dictionary) -> void:
	_lesson_source = lessons_by_id


## Loads `res://content/tutor/lessons/<lesson_id>.json`. False when the file is
## missing, unparsable, or has no steps; the engine then holds no lesson and
## `is_complete()` is true so no caller can loop forever on it.
func load_lesson(lesson_id: String) -> bool:
	_reset_state()
	var data: Variant = null
	if _lesson_source.has(lesson_id):
		data = _lesson_source[lesson_id]
	else:
		data = _read_json("%s/%s.json" % [LESSONS_DIR, lesson_id])
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var lesson: Dictionary = data
	var steps: Variant = lesson.get("steps", null)
	if typeof(steps) != TYPE_ARRAY or (steps as Array).is_empty():
		return false
	_lesson = lesson
	_lesson_id = String(lesson.get("lessonId", lesson_id))
	_steps = steps
	step_changed.emit(current_step())
	return true


func lesson_id() -> String:
	return _lesson_id


func lesson() -> Dictionary:
	return _lesson


func has_lesson() -> bool:
	return not _steps.is_empty()


## The step the child is on, in the contract's shape. Empty when the lesson
## is complete or none is loaded.
func current_step() -> Dictionary:
	if _step_index < 0 or _step_index >= _steps.size():
		return {}
	return _public_step(_steps[_step_index])


func step_count() -> int:
	return _steps.size()


func step_index() -> int:
	return _step_index


## Attempts made on the current step so far (0 before the first evaluate()).
func attempts() -> int:
	return _attempts


## Judges one transcript against the current step. Does NOT advance; the
## caller advances on `next_question` / `complete`. Extra keys beyond the
## contract: `line` (the one thing Aliz should say now), `expected` (canonical
## answer), `attempt`, `stepId`, `teachAnswer` (true when the answer was taught).
func evaluate(transcript: String) -> Dictionary:
	var step: Dictionary = current_step()
	if step.is_empty():
		return _result(OUTCOME_UNCLEAR, "", ACTION_COMPLETE, "", DEFAULT_ENCOURAGEMENT, "", "", false)
	var kind: String = String(step.get("kind", ""))
	if kind != KIND_ASK:
		# Nothing to judge on a teach or celebrate step: acknowledge and move on.
		var action_passive: String = ACTION_COMPLETE if _is_last_ask_or_after() else ACTION_NEXT
		return _result(OUTCOME_CORRECT, "", action_passive, "", "", String(step.get("teachText", "")), "", false)

	_attempts += 1
	var expected_answers: Array = step.get("expectedAnswers", [])
	var canonical: String = String(expected_answers[0]) if not expected_answers.is_empty() else ""
	var encouragement: String = _non_empty(String(step.get("encouragement", "")), DEFAULT_ENCOURAGEMENT)
	var hint: String = _non_empty(String(step.get("hint", "")), DEFAULT_HINT)
	var matched: Dictionary = AnswerMatcherScript.match_answer(transcript, expected_answers)

	if not String(matched.get("matched", "")).is_empty():
		if _attempts == 1:
			_correct_first_try += 1
		var success: String = _non_empty(String(step.get("successLine", "")), DEFAULT_SUCCESS)
		var action: String = ACTION_COMPLETE if _is_last_ask_or_after() else ACTION_NEXT
		return _result(OUTCOME_CORRECT, String(matched["matched"]), action, hint, encouragement, success, canonical, false)

	var blank: bool = AnswerMatcherScript.is_blank(transcript)
	if _attempts >= MAX_ATTEMPTS:
		var answer_line: String = String(step.get("answerLine", ""))
		if answer_line.is_empty():
			answer_line = _generated_answer_line(canonical)
		var action_taught: String = ACTION_COMPLETE if _is_last_ask_or_after() else ACTION_NEXT
		return _result(OUTCOME_UNCLEAR, "", action_taught, hint, encouragement, answer_line, canonical, true)
	var outcome: String = OUTCOME_UNCLEAR if blank else OUTCOME_INCORRECT
	if _attempts == 1:
		return _result(outcome, "", ACTION_RETRY, hint, encouragement, encouragement, canonical, false)
	return _result(outcome, "", ACTION_HINT, hint, encouragement, hint, canonical, false)


## Moves to the next step. Passing the last step completes the lesson (once)
## and emits `lesson_completed`; the star grant itself waits for
## `save_progress()` so it is recorded in the same write.
func advance() -> void:
	if _steps.is_empty():
		return
	if _step_index >= _steps.size():
		return
	_step_index += 1
	_attempts = 0
	if _step_index >= _steps.size():
		_step_index = _steps.size()
		if not _completed:
			_completed = true
			var reward: Dictionary = completion_reward()
			lesson_completed.emit(_lesson_id, int(reward.get("stars", 0)), String(reward.get("stickerId", "")))
	else:
		step_changed.emit(current_step())


func is_complete() -> bool:
	if _steps.is_empty():
		return true
	return _completed or _step_index >= _steps.size()


func progress() -> Dictionary:
	return {
		"lessonId": _lesson_id,
		"stepIndex": mini(_step_index, _steps.size()),
		"stepCount": _steps.size(),
		"askCount": ask_count(),
		"correctFirstTry": _correct_first_try,
		"completed": is_complete() and not _steps.is_empty(),
		"rewardGranted": _reward_granted,
	}


func ask_count() -> int:
	var total: int = 0
	for step: Variant in _steps:
		if String((step as Dictionary).get("kind", "")) == KIND_ASK:
			total += 1
	return total


## `{stars, stickerId, celebrationLine}` from the lesson's completion block.
func completion_reward() -> Dictionary:
	var completion: Variant = _lesson.get("completion", {})
	if typeof(completion) != TYPE_DICTIONARY:
		return {"stars": 0, "stickerId": "", "celebrationLine": ""}
	var block: Dictionary = completion
	return {
		"stars": maxi(int(block.get("stars", 0)), 0),
		"stickerId": String(block.get("stickerId", "")),
		"celebrationLine": String(block.get("celebrationLine", "")),
	}


## Start the same lesson over from step 0. The reward stays granted: replaying
## is welcome, paying twice is not.
func restart() -> void:
	_step_index = 0
	_attempts = 0
	_correct_first_try = 0
	_completed = false
	if not _steps.is_empty():
		step_changed.emit(current_step())


## Writes `settings.tutorProgress[lessonId]` and, when the lesson is complete
## and the reward has not been paid, calls `add_stars(completion.stars)` once.
## Returns the stars granted by THIS call (0 on every other call).
func save_progress(save_service: Object) -> int:
	if save_service == null or _lesson_id.is_empty():
		return 0
	var granted_now: int = 0
	var reward: Dictionary = completion_reward()
	if is_complete() and not _reward_granted:
		_reward_granted = true
		var stars: int = int(reward.get("stars", 0))
		if stars > 0 and save_service.has_method("add_stars"):
			save_service.call("add_stars", stars)
		granted_now = stars
		reward_granted.emit(_lesson_id, stars, String(reward.get("stickerId", "")))
	if save_service.has_method("get_setting") and save_service.has_method("set_setting"):
		var all_progress: Dictionary = _read_progress_map(save_service)
		all_progress[_lesson_id] = {
			"stepIndex": mini(_step_index, _steps.size()),
			"stepCount": _steps.size(),
			"correctFirstTry": _correct_first_try,
			"completed": is_complete(),
			"rewardGranted": _reward_granted,
		}
		save_service.call("set_setting", PROGRESS_SETTING_KEY, all_progress)
	return granted_now


## Restores this lesson's entry from `settings.tutorProgress`. Returns true
## when an entry was applied. A saved entry whose stepCount no longer matches
## the lesson (content changed) restarts from step 0 but keeps `rewardGranted`.
## A saved `completed` lesson resumes as complete (no second celebrate loop)
## -- call `restart()` to replay it.
func load_progress(save_service: Object) -> bool:
	if save_service == null or _lesson_id.is_empty():
		return false
	if not save_service.has_method("get_setting"):
		return false
	var all_progress: Dictionary = _read_progress_map(save_service)
	var raw: Variant = all_progress.get(_lesson_id, null)
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var entry: Dictionary = raw
	_reward_granted = bool(entry.get("rewardGranted", false))
	var saved_count: int = int(entry.get("stepCount", -1))
	if saved_count != _steps.size():
		_step_index = 0
		_attempts = 0
		_correct_first_try = 0
		_completed = false
		return true
	_step_index = clampi(int(entry.get("stepIndex", 0)), 0, _steps.size())
	_correct_first_try = clampi(int(entry.get("correctFirstTry", 0)), 0, ask_count())
	_completed = bool(entry.get("completed", false)) or _step_index >= _steps.size()
	if _completed:
		_step_index = _steps.size()
	_attempts = 0
	return true


## Convenience for the scene: `[ {lessonId, stepIndex, stepCount, completed,
## rewardGranted}, ... ]` for every lesson with a saved entry.
static func all_saved_progress(save_service: Object) -> Dictionary:
	if save_service == null or not save_service.has_method("get_setting"):
		return {}
	var raw: Variant = save_service.call("get_setting", PROGRESS_SETTING_KEY, {})
	return (raw as Dictionary).duplicate(true) if typeof(raw) == TYPE_DICTIONARY else {}


## Subject index, read once per call. `[]` when the file is missing.
static func load_subjects() -> Array:
	var data: Variant = _read_json(SUBJECTS_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var subjects: Variant = (data as Dictionary).get("subjects", [])
	return subjects if typeof(subjects) == TYPE_ARRAY else []


# --- internals ---------------------------------------------------------------

func _reset_state() -> void:
	_lesson = {}
	_lesson_id = ""
	_steps = []
	_step_index = 0
	_attempts = 0
	_correct_first_try = 0
	_completed = false
	_reward_granted = false


## True when no ask step follows the current one, i.e. resolving this step
## means the lesson's questions are done and only the celebrate remains.
func _is_last_ask_or_after() -> bool:
	for i: int in range(_step_index + 1, _steps.size()):
		if String((_steps[i] as Dictionary).get("kind", "")) == KIND_ASK:
			return false
	return true


func _public_step(raw: Dictionary) -> Dictionary:
	var expected: Array = []
	var raw_expected: Variant = raw.get("expectedAnswers", [])
	if typeof(raw_expected) == TYPE_ARRAY:
		for answer: Variant in raw_expected:
			expected.append(String(answer))
	return {
		"stepId": String(raw.get("stepId", "")),
		"kind": String(raw.get("kind", "")),
		"questionText": String(raw.get("questionText", "")),
		"teachText": String(raw.get("teachText", "")),
		"visualAssetId": String(raw.get("visualAssetId", "")),
		"expectedAnswers": expected,
		"objective": String(raw.get("objective", "")),
		"hint": String(raw.get("hint", "")),
		"encouragement": String(raw.get("encouragement", "")),
		"successLine": String(raw.get("successLine", "")),
		"answerLine": String(raw.get("answerLine", "")),
		"spokenLineId": String(raw.get("spokenLineId", "")),
		"stepIndex": _step_index,
		"stepCount": _steps.size(),
	}


func _result(outcome: String, matched: String, action: String, hint: String,
		encouragement: String, line: String, expected: String, taught: bool) -> Dictionary:
	return {
		"outcome": outcome,
		"matched": matched,
		"hint": hint,
		"encouragement": encouragement,
		"lessonAction": action,
		"line": line,
		"expected": expected,
		"attempt": _attempts,
		"stepId": String(current_step().get("stepId", "")),
		"teachAnswer": taught,
	}


static func _generated_answer_line(canonical: String) -> String:
	if canonical.is_empty():
		return DEFAULT_ENCOURAGEMENT
	var article: String = "an" if "aeiou".contains(canonical.substr(0, 1)) else "a"
	if canonical.ends_with("s") and not canonical.ends_with("ss"):
		return "They're %s! Say %s." % [canonical, canonical]
	if _is_colour_or_number(canonical):
		return "It's %s! Say %s." % [canonical, canonical]
	return "It's %s %s! Say %s." % [article, canonical, canonical]


static func _is_colour_or_number(word: String) -> bool:
	return BARE_WORDS.has(word) or word.is_valid_int()


static func _non_empty(value: String, fallback: String) -> String:
	return value if not value.strip_edges().is_empty() else fallback


func _read_progress_map(save_service: Object) -> Dictionary:
	var raw: Variant = save_service.call("get_setting", PROGRESS_SETTING_KEY, {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return (raw as Dictionary).duplicate(true)


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return null
	return JSON.parse_string(text)
