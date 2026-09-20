extends "res://scripts/tutor/providers/conversation_provider.gd"

## The ALWAYS-AVAILABLE conversation provider (canonical, Agent E; same method
## names as Agent B's first draft so `tutor_scene.gd` binds unchanged).
##
## Every TutorTurn is built from the LessonEngine's verdict and the lesson
## data and nothing else: no network, no model, no child data leaves the
## device. It ships while `TutorFlags.cloud_enabled()` is false and stays in
## the product as the turn the backend provider falls back to.
##
## ## Wording: varied but reproducible
##
## Each outcome has a small table of three phrasings. The one used is picked by
## a SEEDED index -- `hash(lessonId + stepId) + attempt` (or `set_seed()`), so
## the same lesson plays the same way every time (a test can pin a transcript
## of the whole lesson) while a child hears "Yes!", "Wonderful!" and the plain
## line across a session instead of one robotic phrase. The lesson's own text
## (question, hint, success line, answer line) is always the substance; the
## variants only frame it.
##
## `build_turn(transcript, phase)` evaluates through the engine (once per
## answer -- the engine counts attempts). `turn_for_verdict(step, verdict,
## phase)` builds the turn for a verdict already obtained, which is how the
## backend provider falls back for ONE turn without judging the child twice.

const VARIANTS: int = 3

## Framing per outcome; `{line}` is the lesson's text, `{word}` the canonical
## answer. Kept ASCII and short so the validator never touches them.
const OPENERS_CORRECT: Array[String] = ["{line}", "Yes! {line}", "Wonderful! {line}"]
const OPENERS_RETRY: Array[String] = ["{line}", "Good try! {line}", "Almost! {line}"]
const OPENERS_HINT: Array[String] = ["Here is a hint. {line}", "Let me help. {line}", "Listen. {line}"]
const OPENERS_TAUGHT: Array[String] = ["{line}", "Let's say it together. {line}", "Together now! {line}"]
const OPENERS_TIMEOUT: Array[String] = ["Let's try together! {line}", "Let's try together! {line}", "Let's try together! Listen. {line}"]
const OPENERS_TOGETHER: Array[String] = ["Let's try together! {word}!", "Say it with me: {word}!", "Together now: {word}!"]
const COMPLETE_LINE: String = "Great job today!"

var _seed_override: int = -1
var _turn_count: int = 0


func provider_name() -> String:
	return "scripted"


func is_available() -> bool:
	return true


## Pins the variant index for tests; -1 restores the lesson/step seed.
func set_seed(seed_value: int) -> void:
	_seed_override = seed_value


func begin_session(lesson_id_value: String) -> void:
	if not has_engine():
		provider_failed.emit("no_lesson_engine")
		return
	_lesson_id = lesson_id_value
	_active = true
	_turn_count = 0
	session_ready.emit({"sessionId": "local-%s" % lesson_id_value, "provider": provider_name(), "lessonId": lesson_id_value})


func submit_turn(transcript: String, lesson_context: Dictionary) -> void:
	if not _active:
		provider_failed.emit("no_session")
		return
	if not has_engine():
		provider_failed.emit("no_lesson_engine")
		return
	var phase: String = String(lesson_context.get("phase", PHASE_ANSWER))
	var turn: Dictionary = build_turn(transcript, phase)
	_turn_count += 1
	turn_ready.emit(TurnValidator.coerce(turn))


func end_session() -> void:
	_active = false


func cancel() -> void:
	pass  # synchronous: nothing is ever in flight


## The turn for `phase`, before validation (public so a test reads it back
## without signals). Evaluates through the engine for answer/timeout phases.
func build_turn(transcript: String, phase: String) -> Dictionary:
	var step: Dictionary = _engine.call("current_step")
	if step.is_empty() or (bool(_engine.call("is_complete")) and phase != PHASE_OPEN):
		return TurnValidator.make(COMPLETE_LINE, "happy", "clap", "complete")
	match phase:
		PHASE_OPEN:
			return open_turn(step)
		PHASE_TOGETHER:
			return together_turn(step)
		PHASE_TIMEOUT:
			return turn_for_verdict(step, _engine.call("evaluate", ""), PHASE_TIMEOUT)
		_:
			return turn_for_verdict(step, _engine.call("evaluate", transcript), PHASE_ANSWER)


## Presents the step: the question (the scene then listens), a teach line, or
## the celebration.
func open_turn(step: Dictionary) -> Dictionary:
	var asset: String = String(step.get("visualAssetId", ""))
	var kind: String = String(step.get("kind", "ask"))
	if kind == "teach":
		return TurnValidator.make(_non_empty(String(step.get("teachText", "")), "Look!"), "smile", "point", "next_question", asset)
	if kind == "celebrate":
		return TurnValidator.make(_non_empty(String(step.get("teachText", "")), COMPLETE_LINE), "happy", "clap", "complete", asset)
	var question: String = _non_empty(String(step.get("questionText", "")), "What is this?")
	return TurnValidator.make(question, "smile", "point", "retry", asset, question)


## No recognition on this device: say the word with the child and move on.
func together_turn(step: Dictionary) -> Dictionary:
	var word: String = answer_word(step)
	var text: String = _pick(OPENERS_TOGETHER, step, 0).replace("{word}", word.capitalize())
	return TurnValidator.make(text, "encouraging", "point", "next_question", String(step.get("visualAssetId", "")))


## The turn for a verdict the engine already gave (no second evaluate()).
func turn_for_verdict(step: Dictionary, verdict: Dictionary, phase: String) -> Dictionary:
	var asset: String = String(step.get("visualAssetId", ""))
	var outcome: String = String(verdict.get("outcome", "unclear"))
	var action: String = String(verdict.get("lessonAction", "retry"))
	var attempt: int = int(verdict.get("attempt", 0))
	var word: String = _non_empty(String(verdict.get("expected", "")), answer_word(step))
	var kind: String = String(step.get("kind", "ask"))
	if kind != "ask":
		# Nothing to judge on a teach/celebrate step: present it and move on.
		var passive: Dictionary = open_turn(step)
		passive["lessonAction"] = action if TurnValidator.LESSON_ACTIONS.has(action) else "next_question"
		return passive
	var line: String = String(verdict.get("line", ""))
	if outcome == "correct":
		var success: String = _non_empty(line, "Great job! %s!" % word.capitalize())
		var speech: String = _pick(OPENERS_CORRECT, step, attempt).replace("{line}", success)
		return TurnValidator.make(speech, "happy", "clap", action if action != "retry" else "next_question", asset)
	var timed_out: bool = phase == PHASE_TIMEOUT
	match action:
		"give_hint":
			var hint: String = _non_empty(String(verdict.get("hint", "")), _non_empty(line, "%s!" % word.capitalize()))
			var table: Array[String] = OPENERS_TIMEOUT if timed_out else OPENERS_HINT
			return TurnValidator.make(_pick(table, step, attempt).replace("{line}", hint), "encouraging", "point", "give_hint", asset)
		"next_question", "complete":
			var taught: String = _non_empty(line, "%s! Say %s." % [word.capitalize(), word])
			var table_taught: Array[String] = OPENERS_TIMEOUT if timed_out else OPENERS_TAUGHT
			return TurnValidator.make(_pick(table_taught, step, attempt).replace("{line}", taught), "encouraging", "nod", action, asset)
		_:
			var encouragement: String = _non_empty(String(verdict.get("encouragement", "")), _non_empty(line, "Let's try together!"))
			var table_retry: Array[String] = OPENERS_TIMEOUT if timed_out else OPENERS_RETRY
			return TurnValidator.make(_pick(table_retry, step, attempt).replace("{line}", encouragement), "encouraging", "tilt", "retry", asset)


## The variant index this turn uses: reproducible per lesson/step/attempt.
func variant_index(step: Dictionary, attempt: int) -> int:
	if _seed_override >= 0:
		return (_seed_override + attempt) % VARIANTS
	var key: String = "%s:%s" % [_lesson_id, String(step.get("stepId", ""))]
	return absi(key.hash() + attempt) % VARIANTS


func _pick(table: Array[String], step: Dictionary, attempt: int) -> String:
	return table[variant_index(step, attempt)]


## The canonical answer for a step, or a readable word from its asset id.
static func answer_word(step: Dictionary) -> String:
	var answers: Array = step.get("expectedAnswers", [])
	if not answers.is_empty():
		return String(answers[0])
	var asset: String = String(step.get("visualAssetId", ""))
	var parts: PackedStringArray = asset.split("_")
	if parts.is_empty() or parts[0].is_empty():
		return "this"
	if parts[0] == "number" and parts.size() > 1:
		return ["", "one", "two", "three"][clampi(int(parts[1]), 0, 3)]
	if parts[0] == "color" and parts.size() > 1:
		return parts[1]
	return parts[0]


static func _non_empty(value: String, fallback: String) -> String:
	return value if not value.strip_edges().is_empty() else fallback
