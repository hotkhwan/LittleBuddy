class_name LessonEngine
extends RefCounted
## Deterministic owner of the Aliz Tutor educational progression.
##
## Contract: docs/ALIZ_TUTOR_CONTRACTS.md, section "LessonEngine (Agent A)"
## plus the evening addendum (choose, sound, reactions, interjections).
## Pure GDScript, no nodes, no 3D types, no network. Everything the child sees
## as pass/fail, progression, routing and reward comes from lesson JSON plus
## this file. An LLM (when the cloud flag is ever on) may rephrase a line; it
## may never change `expectedAnswers`, the step order, or the stars.
##
## ## Lifecycle, as the scene drives it
##
##     var engine := LessonEngine.new()
##     engine.load_lesson(LessonEngine.entry_lesson_id())   # "welcome_choose": Aliz asks what to learn
##     while not engine.is_complete():
##         var step := engine.current_step()
##         match step.kind:
##             "teach", "celebrate": speak(step.teachText); engine.advance()
##             "ask", "sound", "choose":
##                 speak(step.questionText); show(step.visualAssetId)
##                 var result := engine.evaluate(transcript)
##                 speak(result.line)               # success / encouragement / hint / answer line
##                 play(result.reaction)            # {gesture, sfx, alizSound} on a matched sound step
##                 match result.lessonAction:
##                     "next_question", "complete": engine.advance()
##                     "switch_lesson": engine.switch_lesson(result.nextLessonId, SaveService)
##                     # "retry" and "give_hint" stay on the same step: listen again
##                 # Tap fallback (speech off/denied): evaluate(step.expectedAnswers[0])
##         engine.save_progress(SaveService)        # cheap; also grants the completion reward once
##
## Barge-in (the child speaks while Aliz speaks): call
## `handle_interjection(transcript)` first. `{handled: false}` means "not a
## topic change": if `isAnswer` is true, pass the transcript to `evaluate()`,
## otherwise repeat the question. `jump_step` has already moved the engine;
## `switch_lesson` and `end_session` are for the caller to act on.
##
## ## Retry policy (never a fail state)
##
## Per ask/sound step, attempts are counted from 1:
## - match            -> `correct`,   `next_question` (or `complete` when no question remains)
## - 1st miss         -> `incorrect`/`unclear`, `retry`         with `encouragement`
## - 2nd miss         -> `incorrect`/`unclear`, `give_hint`     with `hint`
## - 3rd miss or more -> `unclear`,   `next_question` with the answer taught
##                       ("It's an apple! Say apple.") -- the child moves on.
## On a choose step a match is `switch_lesson` + `nextLessonId`; the third
## miss routes to `defaultLessonId` with `defaultLine`.
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
const KIND_SOUND: String = "sound"
const KIND_CELEBRATE: String = "celebrate"
const KIND_CHOOSE: String = "choose"
## Kinds that wait for the child's answer.
const QUESTION_KINDS: Array[String] = ["ask", "sound", "choose"]
## Kinds that count towards correctFirstTry / ask_count().
const SCORED_KINDS: Array[String] = ["ask", "sound"]

const OUTCOME_CORRECT: String = "correct"
const OUTCOME_INCORRECT: String = "incorrect"
const OUTCOME_UNCLEAR: String = "unclear"

const ACTION_NEXT: String = "next_question"
const ACTION_RETRY: String = "retry"
const ACTION_HINT: String = "give_hint"
const ACTION_COMPLETE: String = "complete"
const ACTION_SWITCH: String = "switch_lesson"
const ACTION_JUMP: String = "jump_step"
const ACTION_END: String = "end_session"

## Attempts before the answer is taught and the lesson moves on.
const MAX_ATTEMPTS: int = 3

const DEFAULT_ENCOURAGEMENT: String = "Let's try together!"
const DEFAULT_HINT: String = "Listen carefully. Let's try together!"
const DEFAULT_SUCCESS: String = "Great job!"
const DEFAULT_LESSON_ID: String = "english_colors_fruits"
const END_SESSION_LINE: String = "Okay! Great job today! Bye bye!"

## Answers spoken without an article in the generated answer line
## ("It's red! Say red." rather than "It's a red!").
const BARE_WORDS: Array[String] = [
	"red", "blue", "yellow", "green", "orange", "purple", "pink", "white", "black", "brown",
	"one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
]

## A barge-in that means "I want to stop". Matched without fuzz.
const STOP_PHRASES: Array[String] = [
	"stop", "i'm done", "im done", "all done", "i am done", "bye", "bye bye", "goodbye",
	"finished", "i'm finished", "no more", "go home", "i want to stop", "i want to go home",
	"i don't want to play", "enough",
]

var _lesson: Dictionary = {}
var _lesson_id: String = ""
var _steps: Array = []
var _step_index: int = 0
var _attempts: int = 0
var _correct_first_try: int = 0
var _completed: bool = false
var _reward_granted: bool = false
## Step indices already passed (answered, taught, or spoken). After an
## interjection jump, `advance()` skips these and, before the celebrate,
## returns to any question the jump left behind.
var _resolved: Dictionary = {}
## Optional override used by tests and tools: a lesson dictionary source
## keyed by lessonId. When empty, lessons are read from LESSONS_DIR.
var _lesson_source: Dictionary = {}
## Optional override of subjects.json for tests. Empty = read the file.
var _subjects_override: Dictionary = {}
var _subjects_cache: Dictionary = {}


## Point the engine at in-memory lessons (tests, editors). `{lessonId: Dictionary}`.
func set_lesson_source(lessons_by_id: Dictionary) -> void:
	_lesson_source = lessons_by_id


## Point the engine at an in-memory subjects document (tests).
func set_subjects_source(subjects_doc: Dictionary) -> void:
	_subjects_override = subjects_doc
	_subjects_cache = {}


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


## Leaves the current lesson for `lesson_id` (a choose step's route or an
## interjection). With a save service, resumes that lesson's saved step; a
## lesson already completed starts over so the child can play it again
## (its reward stays granted). False when the target does not load.
func switch_lesson(lesson_id: String, save_service: Object = null) -> bool:
	if not load_lesson(lesson_id):
		return false
	if save_service != null:
		load_progress(save_service)
		if is_complete():
			restart()
	return true


func lesson_id() -> String:
	return _lesson_id


func lesson() -> Dictionary:
	return _lesson


func has_lesson() -> bool:
	return not _steps.is_empty()


## The step the child is on, in the contract's shape. Empty when the lesson
## is complete or none is loaded. A choose step's `expectedAnswers` is the
## union of every route's answers (for the tap fallback: tapping a subject
## card sends that subject's first keyword).
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


## The routes out of the current choose step, for the scene's subject cards:
## `[{lessonId, subjectId, title, answers, line}]`. Empty on other steps.
func choose_options() -> Array:
	var step: Dictionary = current_step()
	if String(step.get("kind", "")) != KIND_CHOOSE:
		return []
	return _resolved_choices(_steps[_step_index])


## Judges one transcript against the current step. Does NOT advance; the
## caller advances on `next_question` / `complete`, and calls
## `switch_lesson(result.nextLessonId)` on `switch_lesson`. Extra keys beyond
## the contract: `line` (the one thing Aliz should say now), `expected`
## (canonical answer), `attempt`, `stepId`, `teachAnswer` (true when the
## answer was taught), `reaction` (`{gesture, sfx, alizSound}` or `{}`),
## `nextLessonId` (choose steps).
func evaluate(transcript: String) -> Dictionary:
	var step: Dictionary = current_step()
	if step.is_empty():
		return _result(OUTCOME_UNCLEAR, "", ACTION_COMPLETE, "", DEFAULT_ENCOURAGEMENT, "", "", false)
	var kind: String = String(step.get("kind", ""))
	if kind == KIND_CHOOSE:
		return _evaluate_choose(transcript, step)
	if not SCORED_KINDS.has(kind):
		# Nothing to judge on a teach or celebrate step: acknowledge and move on.
		var action_passive: String = ACTION_COMPLETE if _is_last_question_or_after() else ACTION_NEXT
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
		var action: String = ACTION_COMPLETE if _is_last_question_or_after() else ACTION_NEXT
		var result: Dictionary = _result(OUTCOME_CORRECT, String(matched["matched"]), action, hint, encouragement, success, canonical, false)
		result["reaction"] = _reaction_of(step)
		return result

	var blank: bool = AnswerMatcherScript.is_blank(transcript)
	if _attempts >= MAX_ATTEMPTS:
		var answer_line: String = String(step.get("answerLine", ""))
		if answer_line.is_empty():
			answer_line = _generated_answer_line(canonical)
		var action_taught: String = ACTION_COMPLETE if _is_last_question_or_after() else ACTION_NEXT
		return _result(OUTCOME_UNCLEAR, "", action_taught, hint, encouragement, answer_line, canonical, true)
	var outcome: String = OUTCOME_UNCLEAR if blank else OUTCOME_INCORRECT
	if _attempts == 1:
		return _result(outcome, "", ACTION_RETRY, hint, encouragement, encouragement, canonical, false)
	return _result(outcome, "", ACTION_HINT, hint, encouragement, hint, canonical, false)


## A barge-in utterance while Aliz is speaking. Returns
## `{handled, lessonAction, nextStepId | nextLessonId, line, isAnswer}`:
## - names another item of this lesson ("Wait! I want a dog!") -> jumps there
##   now, `lessonAction: "jump_step"`, line "Okay! Let's see the dog!";
## - names another subject ("I want numbers") -> `switch_lesson` + `nextLessonId`
##   (the caller loads it with `switch_lesson()`);
## - "stop" / "I'm done" / "bye" -> `end_session`;
## - anything else -> `handled: false`; `isAnswer` is true when the words
##   answer the current question, so the caller evaluates instead of repeating.
## Never a fail, never an attempt counted.
func handle_interjection(transcript: String) -> Dictionary:
	var unhandled: Dictionary = {"handled": false, "lessonAction": "", "line": "", "isAnswer": false}
	if _steps.is_empty() or AnswerMatcherScript.is_blank(transcript):
		return unhandled
	if not String(AnswerMatcherScript.match_answer(transcript, STOP_PHRASES, false).get("matched", "")).is_empty():
		return {"handled": true, "lessonAction": ACTION_END, "line": END_SESSION_LINE, "isAnswer": false}

	var step: Dictionary = current_step()
	var kind: String = String(step.get("kind", ""))
	if QUESTION_KINDS.has(kind):
		var answers: Array = step.get("expectedAnswers", [])
		if not String(AnswerMatcherScript.match_answer(transcript, answers).get("matched", "")).is_empty():
			unhandled["isAnswer"] = true
			return unhandled

	var current_item: String = String(step.get("itemId", ""))
	for item: Variant in _items():
		var entry: Dictionary = item
		var item_id: String = String(entry["itemId"])
		if item_id == current_item:
			continue
		if String(AnswerMatcherScript.match_answer(transcript, entry["names"], false).get("matched", "")).is_empty():
			continue
		_step_index = int(entry["stepIndex"])
		_attempts = 0
		_completed = false
		step_changed.emit(current_step())
		return {
			"handled": true,
			"lessonAction": ACTION_JUMP,
			"nextStepId": String(entry["stepId"]),
			"line": "Okay! Let's see %s!" % String(entry["label"]),
			"isAnswer": false,
		}

	var current_subject: String = String(_lesson.get("subjectId", ""))
	for subject: Variant in subjects():
		var data: Dictionary = subject
		var subject_id: String = String(data.get("subjectId", ""))
		if subject_id == current_subject:
			continue
		var keywords: Array = data.get("keywords", [])
		if String(AnswerMatcherScript.match_answer(transcript, keywords, false).get("matched", "")).is_empty():
			continue
		var target: String = _first_lesson_of(data)
		if target.is_empty() or target == _lesson_id:
			continue
		return {
			"handled": true,
			"lessonAction": ACTION_SWITCH,
			"nextLessonId": target,
			"line": "Okay! Let's learn about %s!" % String(data.get("title", subject_id)).to_lower(),
			"isAnswer": false,
		}
	return unhandled


## Moves on from the current step. Normally that is the next step; after an
## interjection jump it is the next step not yet done, and before the
## celebrate any question the jump skipped ("now, back to the cat!"). Passing
## the celebrate completes the lesson (once) and emits `lesson_completed`; the
## star grant itself waits for `save_progress()` so it is recorded in the same
## write.
func advance() -> void:
	if _steps.is_empty():
		return
	if _step_index >= _steps.size():
		return
	_resolved[_step_index] = true
	_attempts = 0
	var next: int = _next_unresolved_index()
	if next < 0:
		_step_index = _steps.size()
		if not _completed:
			_completed = true
			var reward: Dictionary = completion_reward()
			lesson_completed.emit(_lesson_id, int(reward.get("stars", 0)), String(reward.get("stickerId", "")))
	else:
		_step_index = next
		step_changed.emit(current_step())


## The step to visit after the current one, or -1 when the lesson is over:
## the first unresolved step after this one that is not the celebrate; else
## the first unresolved step anywhere (a jump left it behind); else the
## celebrate if it has not played.
func _next_unresolved_index() -> int:
	var last: int = _steps.size() - 1
	var celebrate_index: int = last if String((_steps[last] as Dictionary).get("kind", "")) == KIND_CELEBRATE else -1
	for i: int in range(_step_index + 1, _steps.size()):
		if i != celebrate_index and not _resolved.has(i):
			return i
	for i: int in range(0, _step_index):
		if i != celebrate_index and not _resolved.has(i):
			return i
	if celebrate_index >= 0 and not _resolved.has(celebrate_index):
		return celebrate_index
	return -1


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


## Number of scored question steps (ask + sound).
func ask_count() -> int:
	var total: int = 0
	for step: Variant in _steps:
		if SCORED_KINDS.has(String((step as Dictionary).get("kind", ""))):
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
	_resolved = {}
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
	_resolved = {}
	if saved_count != _steps.size():
		_step_index = 0
		_attempts = 0
		_correct_first_try = 0
		_completed = false
		return true
	_step_index = clampi(int(entry.get("stepIndex", 0)), 0, _steps.size())
	for i: int in range(_step_index):
		_resolved[i] = true
	_correct_first_try = clampi(int(entry.get("correctFirstTry", 0)), 0, ask_count())
	_completed = bool(entry.get("completed", false)) or _step_index >= _steps.size()
	if _completed:
		_step_index = _steps.size()
	_attempts = 0
	return true


## Convenience for the scene: `{lessonId: {stepIndex, stepCount, completed,
## rewardGranted}, ...}` for every lesson with a saved entry.
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


## The lesson Aliz opens with (the choose menu), from subjects.json.
static func entry_lesson_id() -> String:
	var data: Variant = _read_json(SUBJECTS_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		return DEFAULT_LESSON_ID
	return _non_empty(String((data as Dictionary).get("entryLessonId", "")), DEFAULT_LESSON_ID)


## Where "anything" / "I don't know" goes, from subjects.json.
static func default_lesson_id() -> String:
	var data: Variant = _read_json(SUBJECTS_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		return DEFAULT_LESSON_ID
	return _non_empty(String((data as Dictionary).get("defaultLessonId", "")), DEFAULT_LESSON_ID)


## The subjects this engine routes with (override or subjects.json), cached.
func subjects() -> Array:
	if _subjects_cache.has("subjects"):
		return _subjects_cache["subjects"]
	var doc: Variant = _subjects_override if not _subjects_override.is_empty() else _read_json(SUBJECTS_PATH)
	var list: Array = []
	if typeof(doc) == TYPE_DICTIONARY:
		var raw: Variant = (doc as Dictionary).get("subjects", [])
		if typeof(raw) == TYPE_ARRAY:
			list = raw
	_subjects_cache["subjects"] = list
	return list


# --- internals ---------------------------------------------------------------

func _reset_state() -> void:
	_resolved = {}
	_lesson = {}
	_lesson_id = ""
	_steps = []
	_step_index = 0
	_attempts = 0
	_correct_first_try = 0
	_completed = false
	_reward_granted = false


func _evaluate_choose(transcript: String, step: Dictionary) -> Dictionary:
	_attempts += 1
	var raw_step: Dictionary = _steps[_step_index]
	var encouragement: String = _non_empty(String(step.get("encouragement", "")), DEFAULT_ENCOURAGEMENT)
	var hint: String = _non_empty(String(step.get("hint", "")), DEFAULT_HINT)
	var default_lesson: String = _non_empty(String(raw_step.get("defaultLessonId", "")), DEFAULT_LESSON_ID)
	var default_line: String = _non_empty(String(raw_step.get("defaultLine", "")), "Okay! Let's start here!")

	for choice: Variant in _resolved_choices(raw_step):
		var option: Dictionary = choice
		var matched: Dictionary = AnswerMatcherScript.match_answer(transcript, option["answers"])
		if String(matched.get("matched", "")).is_empty():
			continue
		var result: Dictionary = _result(OUTCOME_CORRECT, String(matched["matched"]), ACTION_SWITCH, hint, encouragement, String(option["line"]), String(option["lessonId"]), false)
		result["nextLessonId"] = String(option["lessonId"])
		return result
	var default_answers: Array = raw_step.get("defaultAnswers", [])
	if not String(AnswerMatcherScript.match_answer(transcript, default_answers).get("matched", "")).is_empty():
		var result_default: Dictionary = _result(OUTCOME_CORRECT, default_lesson, ACTION_SWITCH, hint, encouragement, default_line, default_lesson, false)
		result_default["nextLessonId"] = default_lesson
		return result_default

	var blank: bool = AnswerMatcherScript.is_blank(transcript)
	if _attempts >= MAX_ATTEMPTS:
		var routed: Dictionary = _result(OUTCOME_UNCLEAR, "", ACTION_SWITCH, hint, encouragement, default_line, default_lesson, true)
		routed["nextLessonId"] = default_lesson
		return routed
	var outcome: String = OUTCOME_UNCLEAR if blank else OUTCOME_INCORRECT
	if _attempts == 1:
		return _result(outcome, "", ACTION_RETRY, hint, encouragement, encouragement, default_lesson, false)
	return _result(outcome, "", ACTION_HINT, hint, encouragement, hint, default_lesson, false)


## Choices of a choose step with subject keywords merged in and lessonIds
## resolved: `[{lessonId, subjectId, title, answers, line}]`.
func _resolved_choices(raw_step: Dictionary) -> Array:
	var out: Array = []
	var raw_choices: Variant = raw_step.get("choices", [])
	if typeof(raw_choices) != TYPE_ARRAY:
		return out
	for raw: Variant in raw_choices:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = raw
		var subject: Dictionary = _subject_by_id(String(choice.get("subjectId", "")))
		var lesson_target: String = String(choice.get("lessonId", ""))
		if lesson_target.is_empty():
			lesson_target = _first_lesson_of(subject)
		if lesson_target.is_empty():
			continue
		var answers: Array = []
		for keyword: Variant in subject.get("keywords", []):
			answers.append(String(keyword))
		for extra: Variant in choice.get("answers", []):
			if not answers.has(String(extra)):
				answers.append(String(extra))
		if answers.is_empty():
			continue
		var title: String = String(subject.get("title", lesson_target.replace("_", " ")))
		out.append({
			"lessonId": lesson_target,
			"subjectId": String(subject.get("subjectId", choice.get("subjectId", ""))),
			"title": title,
			"answers": answers,
			"line": _non_empty(String(choice.get("line", "")), "Okay! Let's learn about %s!" % title.to_lower()),
		})
	return out


func _subject_by_id(subject_id: String) -> Dictionary:
	if subject_id.is_empty():
		return {}
	for subject: Variant in subjects():
		if String((subject as Dictionary).get("subjectId", "")) == subject_id:
			return subject
	return {}


static func _first_lesson_of(subject: Dictionary) -> String:
	var ids: Variant = subject.get("lessonIds", [])
	if typeof(ids) != TYPE_ARRAY or (ids as Array).is_empty():
		return ""
	return String((ids as Array)[0])


## The items of this lesson in step order: `[{itemId, label, stepId,
## stepIndex, names}]` where names are the itemId, the label and every
## expected answer of the item's ask steps.
func _items() -> Array:
	var items: Array = []
	var index_of: Dictionary = {}
	for i: int in range(_steps.size()):
		var step: Dictionary = _steps[i]
		var item_id: String = String(step.get("itemId", ""))
		if item_id.is_empty():
			continue
		if not index_of.has(item_id):
			index_of[item_id] = items.size()
			items.append({
				"itemId": item_id,
				"label": _non_empty(String(step.get("itemLabel", "")), item_id.replace("_", " ")),
				"stepId": String(step.get("stepId", "")),
				"stepIndex": i,
				"names": [item_id, item_id.replace("_", " ")],
			})
		if String(step.get("kind", "")) == KIND_ASK:
			var names: Array = (items[index_of[item_id]] as Dictionary)["names"]
			for answer: Variant in step.get("expectedAnswers", []):
				if not names.has(String(answer)):
					names.append(String(answer))
	return items


## True when no other question step is still open, i.e. resolving this step
## means the lesson's questions are done and only the celebrate remains. After
## an interjection jump a skipped question before this one still counts.
func _is_last_question_or_after() -> bool:
	for i: int in range(_steps.size()):
		if i == _step_index or _resolved.has(i):
			continue
		if QUESTION_KINDS.has(String((_steps[i] as Dictionary).get("kind", ""))):
			return false
	return true


static func _reaction_of(step: Dictionary) -> Dictionary:
	var raw: Variant = step.get("reaction", {})
	if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		return {}
	var reaction: Dictionary = raw
	return {
		"gesture": String(reaction.get("gesture", "none")),
		"sfx": String(reaction.get("sfx", "none")),
		"alizSound": String(reaction.get("alizSound", "")),
	}


func _public_step(raw: Dictionary) -> Dictionary:
	var expected: Array = []
	var raw_expected: Variant = raw.get("expectedAnswers", [])
	if typeof(raw_expected) == TYPE_ARRAY:
		for answer: Variant in raw_expected:
			expected.append(String(answer))
	var kind: String = String(raw.get("kind", ""))
	if kind == KIND_CHOOSE:
		for choice: Variant in _resolved_choices(raw):
			for answer: Variant in (choice as Dictionary)["answers"]:
				if not expected.has(String(answer)):
					expected.append(String(answer))
		for answer: Variant in raw.get("defaultAnswers", []):
			if not expected.has(String(answer)):
				expected.append(String(answer))
	return {
		"stepId": String(raw.get("stepId", "")),
		"kind": kind,
		"itemId": String(raw.get("itemId", "")),
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
		"reaction": _reaction_of(raw),
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
		"reaction": {},
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
