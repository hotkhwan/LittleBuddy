extends RefCounted

## A MINIMAL LessonEngine with the contract's shape (`docs/ALIZ_TUTOR_CONTRACTS.md`
## "LessonEngine"), so the classroom runs end to end before Agent A's real
## engine lands. `tutor_scene.gd` prefers `res://scripts/tutor/lesson/lesson_engine.gd`
## whenever that file exists and only falls back to this stub; the lead deletes
## the fallback at merge. One hard-coded six-step apple/banana lesson, the same
## evaluate() rules as the contract: case/punctuation-insensitive, synonyms,
## second miss -> give_hint, third -> next_question with outcome "unclear".
##
## Pure GDScript: no nodes, no 3D types.

const LESSON_ID: String = "fruits_01"
const PROGRESS_KEY: String = "tutorProgress"

const STEPS: Array = [
	{"stepId": "teach_apple", "kind": "teach", "questionText": "", "teachText": "This is an apple. Apple!",
		"visualAssetId": "apple_red", "expectedAnswers": [], "objective": "name apple",
		"hint": "", "encouragement": "Apple! Say it with me.", "spokenLineId": "apple"},
	{"stepId": "ask_apple", "kind": "ask", "questionText": "What is this?", "teachText": "",
		"visualAssetId": "apple_red", "expectedAnswers": ["apple", "an apple", "it's an apple", "red apple", "a apple"],
		"objective": "name apple", "hint": "It is red and round. Ap-ple!", "encouragement": "Nice try! Listen: apple."},
	{"stepId": "teach_banana", "kind": "teach", "questionText": "", "teachText": "This is a banana. Banana!",
		"visualAssetId": "banana_yellow", "expectedAnswers": [], "objective": "name banana",
		"hint": "", "encouragement": "Banana! Say it with me.", "spokenLineId": "banana"},
	{"stepId": "ask_banana", "kind": "ask", "questionText": "What is this?", "teachText": "",
		"visualAssetId": "banana_yellow", "expectedAnswers": ["banana", "a banana", "it's a banana", "yellow banana"],
		"objective": "name banana", "hint": "It is yellow and long. Ba-na-na!", "encouragement": "Nice try! Listen: banana."},
	{"stepId": "ask_yellow", "kind": "ask", "questionText": "Which one is yellow?", "teachText": "",
		"visualAssetId": "banana_yellow", "expectedAnswers": ["banana", "the banana", "a banana", "it's the banana"],
		"objective": "colour yellow", "hint": "The banana is yellow. Banana!", "encouragement": "Almost! The yellow one."},
	{"stepId": "celebrate", "kind": "celebrate", "questionText": "", "teachText": "Great job today! Apple and banana!",
		"visualAssetId": "apple_red", "expectedAnswers": [], "objective": "", "hint": "", "encouragement": "Great job!"},
]

var _lesson_id: String = ""
var _index: int = 0
var _attempts: int = 0
var _correct_first_try: int = 0
var _completed: bool = false


func load_lesson(lesson_id: String) -> bool:
	_lesson_id = lesson_id if not lesson_id.is_empty() else LESSON_ID
	_index = 0
	_attempts = 0
	_correct_first_try = 0
	_completed = false
	return true


func lesson_id() -> String:
	return _lesson_id


func step_count() -> int:
	return STEPS.size()


func current_step() -> Dictionary:
	if _index < 0 or _index >= STEPS.size():
		return {}
	return (STEPS[_index] as Dictionary).duplicate(true)


func evaluate(transcript: String) -> Dictionary:
	var step: Dictionary = current_step()
	var expected: Array = step.get("expectedAnswers", [])
	var said: String = normalise(transcript)
	var matched: String = ""
	for answer in expected:
		var wanted: String = normalise(String(answer))
		if wanted.is_empty():
			continue
		if said == wanted or (" " + said + " ").find(" " + wanted + " ") >= 0:
			matched = String(answer)
			break
	_attempts += 1
	if not matched.is_empty():
		if _attempts == 1:
			_correct_first_try += 1
		return {"outcome": "correct", "matched": matched, "hint": "", "encouragement": String(step.get("encouragement", "")),
			"lessonAction": "next_question"}
	var outcome: String = "unclear" if said.is_empty() else "incorrect"
	if _attempts >= 3:
		return {"outcome": "unclear", "matched": "", "hint": String(step.get("hint", "")),
			"encouragement": String(step.get("encouragement", "")), "lessonAction": "next_question"}
	if _attempts == 2:
		return {"outcome": outcome, "matched": "", "hint": String(step.get("hint", "")),
			"encouragement": String(step.get("encouragement", "")), "lessonAction": "give_hint"}
	return {"outcome": outcome, "matched": "", "hint": String(step.get("hint", "")),
		"encouragement": String(step.get("encouragement", "")), "lessonAction": "retry"}


func advance() -> void:
	if _completed:
		return
	_attempts = 0
	_index += 1
	if _index >= STEPS.size():
		_index = STEPS.size()
		_completed = true


func is_complete() -> bool:
	return _completed


func progress() -> Dictionary:
	return {"lessonId": _lesson_id, "stepIndex": _index, "stepCount": STEPS.size(),
		"correctFirstTry": _correct_first_try, "completed": _completed}


func save_progress(save_service: Object) -> void:
	if save_service == null or not save_service.has_method("get_setting") or not save_service.has_method("set_setting"):
		return
	var all: Variant = save_service.call("get_setting", PROGRESS_KEY, {})
	var table: Dictionary = all if typeof(all) == TYPE_DICTIONARY else {}
	table[_lesson_id] = progress()
	save_service.call("set_setting", PROGRESS_KEY, table)


func load_progress(save_service: Object) -> void:
	if save_service == null or not save_service.has_method("get_setting"):
		return
	var all: Variant = save_service.call("get_setting", PROGRESS_KEY, {})
	if typeof(all) != TYPE_DICTIONARY:
		return
	var saved: Variant = (all as Dictionary).get(_lesson_id, null)
	if typeof(saved) != TYPE_DICTIONARY:
		return
	_correct_first_try = int((saved as Dictionary).get("correctFirstTry", 0))


static func normalise(text: String) -> String:
	var lower: String = text.to_lower().strip_edges()
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(lower.length()):
		var code: int = lower.unicode_at(i)
		var keep: bool = (code >= 0x61 and code <= 0x7A) or (code >= 0x30 and code <= 0x39) or code == 0x27
		out.append(lower[i] if keep else " ")
	var joined: String = "".join(out)
	while joined.find("  ") >= 0:
		joined = joined.replace("  ", " ")
	return joined.strip_edges()
