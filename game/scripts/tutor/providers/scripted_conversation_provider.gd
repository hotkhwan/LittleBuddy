extends RefCounted

## The ALWAYS-AVAILABLE conversation provider: builds every TutorTurn from the
## LessonEngine's output and nothing else. No network, no model, no child data
## leaves the device. It is what ships while `TutorFlags.cloud_enabled()` is
## false, and it stays in the product as the path the scene falls back to when
## the backend provider fails.
##
## Interface (`docs/ALIZ_TUTOR_CONTRACTS.md` "ConversationProvider"):
##   begin_session(lesson_id) -> signal session_ready(session)
##   submit_turn(transcript, lesson_context) -> signal turn_ready(turn)
##   end_session(), cancel(), signal provider_failed(reason)
##
## `lesson_context.phase` tells the provider what the scene is asking for:
##   "open"     -- present the current step (question, teach line or celebration);
##   "answer"   -- the child said `transcript`; evaluate it;
##   "timeout"  -- the child said nothing in time; counts as an unclear answer
##                 and is voiced as "Let's try together!";
##   "together" -- recognition is not available on this device: say the word
##                 with the child and move on, never a dead end.
## The engine is the owner of progression: the provider never calls advance();
## the scene applies `lessonAction` after the turn has been spoken.
##
## Every turn is passed through the validator before it is emitted, so the
## scripted path obeys exactly the rules the backend path will.

signal session_ready(session: Dictionary)
signal turn_ready(turn: Dictionary)
signal provider_failed(reason: String)

const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")

const PHASE_OPEN: String = "open"
const PHASE_ANSWER: String = "answer"
const PHASE_TIMEOUT: String = "timeout"
const PHASE_TOGETHER: String = "together"

const PRAISE: Array[String] = ["Great job!", "Yes! Well done!", "Nice! That's right!", "Super!"]

var _engine: Object = null
var _lesson_id: String = ""
var _active: bool = false
var _praise_index: int = 0


func set_engine(engine: Object) -> void:
	_engine = engine


func engine() -> Object:
	return _engine


func is_active() -> bool:
	return _active


func provider_name() -> String:
	return "scripted"


func begin_session(lesson_id: String) -> void:
	if _engine == null or not _engine.has_method("current_step"):
		provider_failed.emit("no lesson engine")
		return
	_lesson_id = lesson_id
	_active = true
	_praise_index = 0
	session_ready.emit({"sessionId": "local-%s" % lesson_id, "provider": provider_name(), "lessonId": lesson_id})


func submit_turn(transcript: String, lesson_context: Dictionary) -> void:
	if not _active:
		provider_failed.emit("no session")
		return
	if _engine == null:
		provider_failed.emit("no lesson engine")
		return
	var phase: String = String(lesson_context.get("phase", PHASE_ANSWER))
	var turn: Dictionary = build_turn(transcript, phase)
	turn_ready.emit(TurnValidator.coerce(turn))


func end_session() -> void:
	_active = false


func cancel() -> void:
	# Nothing is in flight in a synchronous provider; kept for the interface.
	pass


## The turn for `phase`, before validation. Public so a test can read it back
## without signals.
func build_turn(transcript: String, phase: String) -> Dictionary:
	var step: Dictionary = _engine.call("current_step")
	if step.is_empty() or (bool(_engine.call("is_complete")) and phase != PHASE_OPEN):
		return TurnValidator.make("Great job today!", "happy", "clap", "complete")
	var asset: String = String(step.get("visualAssetId", ""))
	var kind: String = String(step.get("kind", "ask"))
	var word: String = _answer_word(step)
	match phase:
		PHASE_OPEN:
			if kind == "teach":
				return TurnValidator.make(String(step.get("teachText", "")), "smile", "point", "next_question", asset)
			if kind == "celebrate":
				var text: String = String(step.get("teachText", ""))
				return TurnValidator.make(text if not text.is_empty() else "Great job today!", "happy", "clap", "complete", asset)
			return TurnValidator.make(String(step.get("questionText", "")), "listening", "tilt", "retry", asset,
				String(step.get("questionText", "")))
		PHASE_TOGETHER:
			return TurnValidator.make("Let's try together! %s!" % word.capitalize(), "encouraging", "point", "next_question", asset)
		PHASE_TIMEOUT:
			var verdict: Dictionary = _engine.call("evaluate", "")
			return _turn_for_verdict(verdict, step, asset, word, true)
		_:
			var verdict: Dictionary = _engine.call("evaluate", transcript)
			return _turn_for_verdict(verdict, step, asset, word, false)


func _turn_for_verdict(verdict: Dictionary, step: Dictionary, asset: String, word: String, timed_out: bool) -> Dictionary:
	var outcome: String = String(verdict.get("outcome", "unclear"))
	var action: String = String(verdict.get("lessonAction", "retry"))
	var hint: String = String(verdict.get("hint", step.get("hint", "")))
	var encouragement: String = String(verdict.get("encouragement", step.get("encouragement", "")))
	# The engine's own line for this verdict (the lesson author's words) wins
	# over anything composed here; the composition is the fallback for an
	# engine that returns none.
	var authored: String = String(verdict.get("line", "")).strip_edges()
	if outcome == "correct":
		if not authored.is_empty():
			return TurnValidator.make(authored, "happy", "clap", action if action != "retry" else "next_question", asset)
		var praise: String = PRAISE[_praise_index % PRAISE.size()]
		_praise_index += 1
		return TurnValidator.make("%s %s!" % [praise, word.capitalize()], "happy", "clap", "next_question", asset)
	var lead: String = "Let's try together!" if timed_out else encouragement
	if lead.is_empty():
		lead = "Let's try together!"
	if not authored.is_empty():
		var spoken: String = authored
		if timed_out and not authored.begins_with("Let's try together"):
			spoken = ("Let's try together! " + authored).left(TurnValidator.MAX_SPEECH)
		var gesture: String = "point" if action == "give_hint" else ("nod" if action != "retry" else "tilt")
		return TurnValidator.make(spoken, "encouraging", gesture, action, asset)
	match action:
		"give_hint":
			var hint_text: String = hint if not hint.is_empty() else "%s!" % word.capitalize()
			return TurnValidator.make("%s %s" % [lead, hint_text], "encouraging", "point", "give_hint", asset)
		"next_question", "complete":
			return TurnValidator.make("%s %s! Let's do the next one." % [lead, word.capitalize()], "encouraging", "nod",
				action, asset)
		_:
			return TurnValidator.make(lead, "encouraging", "tilt", "retry", asset)


static func _answer_word(step: Dictionary) -> String:
	var answers: Array = step.get("expectedAnswers", [])
	if not answers.is_empty():
		return String(answers[0])
	var asset: String = String(step.get("visualAssetId", ""))
	var head: String = asset.split("_")[0]
	if head == "number" and asset.split("_").size() > 1:
		return ["", "one", "two", "three"][clampi(int(asset.split("_")[1]), 0, 3)]
	if head == "color" and asset.split("_").size() > 1:
		return asset.split("_")[1]
	return head
