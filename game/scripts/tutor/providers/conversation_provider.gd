extends RefCounted

## ConversationProvider -- the base of the two tutor "brains"
## (`docs/ALIZ_TUTOR_CONTRACTS.md`). A provider turns what the child said into
## the next validated TutorTurn. Two implementations:
##
##   * `ScriptedConversationProvider` -- local, deterministic, ALWAYS available.
##     Builds every turn from the LessonEngine's verdict and the lesson data.
##     This is what ships while `TutorFlags.cloud_enabled()` is false, and the
##     path every other provider falls back to.
##   * `BackendConversationProvider` -- flag-gated. Posts the transcript TEXT and
##     the lesson context to Agent D's backend and speaks its turn. Never runs
##     while the flag is off; on any failure the scripted turn is used.
##
## Interface (every implementation, same signal shape, so the scene binds once):
##   begin_session(lesson_id)              -> signal session_ready(session)
##   submit_turn(transcript, lesson_context) -> signal turn_ready(turn)   exactly once per submit
##   end_session()                         (idempotent)
##   cancel()                              (drops anything in flight; no turn follows)
##   signal provider_failed(reason)        (a session-level failure: no turn will follow)
##
## `lesson_context.phase` says what the scene wants (`PHASE_*`):
##   "open"     present the current step (question / teach line / celebration);
##   "answer"   the child said `transcript`; evaluate it;
##   "timeout"  the child said nothing in time -- an unclear answer, voiced as
##              "Let's try together!";
##   "together" recognition is not available here: say the word with the child
##              and move on. Never a dead end.
##
## The LessonEngine is the only owner of progression: a provider never calls
## `advance()`; the scene applies `lessonAction` after the turn is spoken.
## Every emitted turn has been through `tutor_turn.gd`.

signal session_ready(session: Dictionary)
signal turn_ready(turn: Dictionary)
signal provider_failed(reason: String)

const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")

const PHASE_OPEN: String = "open"
const PHASE_ANSWER: String = "answer"
const PHASE_TIMEOUT: String = "timeout"
const PHASE_TOGETHER: String = "together"
const PHASES: Array[String] = [PHASE_OPEN, PHASE_ANSWER, PHASE_TIMEOUT, PHASE_TOGETHER]

var _engine: Object = null
var _lesson_id: String = ""
var _active: bool = false


func set_engine(engine: Object) -> void:
	_engine = engine


func engine() -> Object:
	return _engine


func has_engine() -> bool:
	return _engine != null and _engine.has_method("current_step") and _engine.has_method("evaluate")


func is_active() -> bool:
	return _active


func lesson_id() -> String:
	return _lesson_id


func provider_name() -> String:
	return "base"


## Always false here; the backend provider answers from the flag.
func is_available() -> bool:
	return false


func begin_session(_lesson_id_value: String) -> void:
	provider_failed.emit("not_implemented")


func submit_turn(_transcript: String, _lesson_context: Dictionary) -> void:
	provider_failed.emit("not_implemented")


func end_session() -> void:
	_active = false


func cancel() -> void:
	pass


## The lesson context the backend contract asks for (`docs/ALIZ_TUTOR_API.md`
## "LessonContext"), built from the engine's step and verdict. Only lesson
## data and the verdict: no transcript, no profile, no device fields.
static func lesson_context_for(step: Dictionary, verdict: Dictionary, next_step: Dictionary = {}) -> Dictionary:
	var context: Dictionary = {
		"stepId": String(step.get("stepId", verdict.get("stepId", ""))),
		"outcome": String(verdict.get("outcome", "unclear")),
		"expectedAnswers": step.get("expectedAnswers", []).duplicate(),
		"lessonAction": String(verdict.get("lessonAction", "retry")),
	}
	var hint: String = String(verdict.get("hint", step.get("hint", "")))
	if not hint.is_empty():
		context["hint"] = hint
	var matched: String = String(verdict.get("matched", ""))
	if not matched.is_empty():
		context["matched"] = matched
	var asset: String = String(step.get("visualAssetId", ""))
	if not asset.is_empty():
		context["visualAssetId"] = asset
	var next_question: String = String(next_step.get("questionText", ""))
	if not next_question.is_empty():
		context["nextQuestionText"] = next_question
	return context
