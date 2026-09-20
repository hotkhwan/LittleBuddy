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
##
## ## Reactions, routing, barge-in (addendum)
##
## A matched `sound` step's verdict carries `reaction {gesture, sfx, alizSound}`:
## the gesture becomes the turn's gesture, the sfx name rides along as
## `wantsSfx` (client-only key; the scene may ignore it) and `alizSound` is
## said first unless the line already starts with it ("Meow! You're amazing!"
## is not doubled). A `switch_lesson` / `jump_step` verdict keeps its action
## and adds `nextLessonId` / `nextStepId`; `lesson_routed` fires first. A
## barge-in (`PHASE_INTERJECTION`) goes through `handle_interjection()` when
## the engine has it, else the step is simply asked again.

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
		PHASE_INTERJECTION:
			return interjection_turn(step, transcript)
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
	var gesture: String = "point" if not asset.is_empty() else "tilt"
	return TurnValidator.make(question, "smile", gesture, "retry", asset, question)


## Barge-in: the child spoke over Aliz. Topic change -> honoured; an answer ->
## judged; anything else -> the step is asked again (a restart of the step,
## which is also the whole behaviour when the engine has no interjection API).
func interjection_turn(step: Dictionary, transcript: String) -> Dictionary:
	if _engine.has_method("handle_interjection"):
		var result: Dictionary = _engine.call("handle_interjection", transcript)
		if bool(result.get("handled", false)):
			var action: String = String(result.get("lessonAction", ""))
			var target: String = String(result.get("nextStepId", result.get("nextLessonId", "")))
			lesson_routed.emit(action, target)
			var landed: Dictionary = _engine.call("current_step") if action == "jump_step" else step
			var line: String = _non_empty(String(result.get("line", "")), "Okay!")
			var gesture: String = "wave" if action == "end_session" else "point"
			var turn: Dictionary = TurnValidator.make(line, "happy", gesture, action, String(landed.get("visualAssetId", "")))
			if action == "switch_lesson" and not String(result.get("nextLessonId", "")).is_empty():
				turn["nextLessonId"] = String(result["nextLessonId"])
			if action == "jump_step" and not String(result.get("nextStepId", "")).is_empty():
				turn["nextStepId"] = String(result["nextStepId"])
			return turn
		if bool(result.get("isAnswer", false)):
			return turn_for_verdict(step, _engine.call("evaluate", transcript), PHASE_ANSWER)
	var again: Dictionary = open_turn(step)
	again["emotion"] = "listening"
	return again


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
	if not QUESTION_KINDS.has(kind):
		# Nothing to judge on a teach/celebrate step: present it and move on.
		var passive: Dictionary = open_turn(step)
		passive["lessonAction"] = action if TurnValidator.LESSON_ACTIONS.has(action) else "next_question"
		return passive
	var line: String = String(verdict.get("line", ""))
	if action == "switch_lesson":
		# A choose step routed the child (a match, or the default after misses).
		var routed: String = _non_empty(line, "Okay! Let's start!")
		var target: String = String(verdict.get("nextLessonId", ""))
		lesson_routed.emit(action, target)
		var route_turn: Dictionary = TurnValidator.make(routed, "happy", "clap", action, asset)
		if not target.is_empty():
			route_turn["nextLessonId"] = target
		return route_turn
	if outcome == "correct":
		var success: String = _non_empty(line, "Great job! %s!" % word.capitalize())
		var reaction: Dictionary = verdict.get("reaction", {}) if typeof(verdict.get("reaction", {})) == TYPE_DICTIONARY else {}
		var aliz_sound: String = String(reaction.get("alizSound", "")).strip_edges()
		if not aliz_sound.is_empty() and not _starts_with_sound(success, aliz_sound):
			success = "%s %s" % [aliz_sound, success]
		var speech: String = _pick(OPENERS_CORRECT, step, attempt).replace("{line}", success)
		if not aliz_sound.is_empty():
			speech = success  # the sound IS the opener; no "Yes! Meow!" on top
		var gesture: String = String(reaction.get("gesture", "clap"))
		if not TurnValidator.GESTURES.has(gesture):
			gesture = "clap"
		var turn: Dictionary = TurnValidator.make(speech, "happy", gesture, action if action != "retry" else "next_question", asset)
		var sfx: String = String(reaction.get("sfx", ""))
		if TurnValidator.is_safe_identifier(sfx):
			turn["wantsSfx"] = sfx
		return turn
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


## "Meow! You're amazing!" already begins with "Meow!" -- compare letters only.
static func _starts_with_sound(line: String, sound: String) -> bool:
	var a: String = _letters(line)
	var b: String = _letters(sound)
	return not b.is_empty() and a.begins_with(b)


static func _letters(text: String) -> String:
	var out: String = ""
	for i: int in range(text.length()):
		var code: int = text.to_lower().unicode_at(i)
		if code >= 0x61 and code <= 0x7A:
			out += text.to_lower()[i]
	return out
