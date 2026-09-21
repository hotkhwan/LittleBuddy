extends "res://scripts/tutor/providers/conversation_provider.gd"

## CloudTutorProvider -- the ConversationProvider face of a `CloudTutorSession`,
## so the classroom scene binds it exactly like the scripted provider
## (`begin_session` / `submit_turn` / `end_session` / `cancel`, one
## `turn_ready` per `submit_turn`). Selected by `tutor_scene.gd` ONLY while
## `TutorFlags.cloud_enabled()` is true (`cloud_tutor_bridge.gd`).
##
## ## Which turns go to the cloud
##
## Only `PHASE_ANSWER` on a scored step. Reading a question (`open`), the
## barge-in interjection (routed by the LessonEngine), `timeout`, `together`
## and choose-step routing are built locally by the embedded scripted
## provider: no quota spent, no words of the child sent, and the engine judges
## the answer ONCE, here, before the transcript leaves the device.
##
## ## One turn per request, and when it is emitted
##
## The realtime reply streams. On its FIRST delta this provider emits the turn
## EARLY: the local verdict's emotion / gesture / visual / lessonAction (what
## the scripted tutor would have shown for the same verdict) with the streamed
## words so far as its speech. The scene then runs its normal `_speak_turn()`
## -- face, gesture, card, subtitle, state -- and the `CloudSynthesisProvider`
## attaches to the stream, so the classroom behaves identically whichever
## provider speaks; the bridge keeps the subtitle growing. The final validated
## turn at response.done arrives as `turn_meta({final})`.
##
## A reply that never starts within `FIRST_DELTA_SECONDS`, is lost to a
## reconnect, or arrives while the cloud is down is answered with the scripted
## turn for the SAME verdict (`fallback_used(reason)` then `turn_ready`). A
## reply the session had to replace mid-stream (URL, banned word) is voiced as
## "Let's try together!" by the synthesis wrapper; the turn already emitted
## keeps the engine's action.

signal fallback_used(reason: String)
signal turn_meta(meta: Dictionary)

const ScriptedProviderScript := preload("res://scripts/tutor/providers/scripted_conversation_provider.gd")

const FIRST_DELTA_SECONDS: float = 6.0

var _scripted: RefCounted = ScriptedProviderScript.new()
var _cloud: RefCounted = null
var _pending: Dictionary = {}
var _first_delta_left: float = -1.0
var _wired: bool = false
var _log: Array = []


func provider_name() -> String:
	return "cloud_realtime"


func is_available() -> bool:
	return _cloud != null and bool(_cloud.call("is_ready"))


func set_engine(engine: Object) -> void:
	super.set_engine(engine)
	_scripted.set_engine(engine)
	if not _scripted.lesson_routed.is_connected(_on_scripted_routed):
		_scripted.lesson_routed.connect(_on_scripted_routed)


func set_cloud_session(session: RefCounted) -> void:
	_cloud = session
	_wire()


func cloud_session() -> RefCounted:
	return _cloud


func scripted_provider() -> RefCounted:
	return _scripted


## `{kind, reason}` rows: early / final / fallback, for tests.
func turn_log() -> Array:
	return _log.duplicate(true)


func has_pending_turn() -> bool:
	return not _pending.is_empty()


# -- ConversationProvider ----------------------------------------------------------------------

func begin_session(lesson_id_value: String) -> void:
	_lesson_id = lesson_id_value
	_active = true
	_scripted.begin_session(lesson_id_value)
	if _cloud != null:
		_cloud.call("configure", lesson_id_value, "realtime")
		if String(_cloud.call("get_state")) == "idle":
			_cloud.call("start")
	session_ready.emit({"sessionId": "cloud-pending", "provider": provider_name(), "lessonId": lesson_id_value})


func submit_turn(transcript: String, lesson_context: Dictionary) -> void:
	var phase: String = String(lesson_context.get("phase", PHASE_ANSWER))
	if not has_engine():
		provider_failed.emit("no_lesson_engine")
		return
	var step: Dictionary = _engine.call("current_step")
	if phase != PHASE_ANSWER or step.is_empty() or bool(_engine.call("is_complete")) \
			or String(step.get("kind", "")) == "choose":
		turn_ready.emit(TurnValidator.coerce(_scripted.build_turn(transcript, phase)))
		return
	var said: String = transcript.strip_edges().left(500)
	if not _pending.is_empty() and String(_pending.get("stepId", "")) == String(step.get("stepId", "")) \
			and String(_pending.get("phase", "")) == phase and String(_pending.get("said", "")) == said:
		# The scene asks again every frame while it waits (harmless with a
		# synchronous provider): one reply is already on its way, and the
		# engine must not judge the same attempt twice.
		return
	var verdict: Dictionary = _engine.call("evaluate", said)
	var local_turn: Dictionary = TurnValidator.coerce(_scripted.turn_for_verdict(step, verdict, phase))
	if _cloud == null or not bool(_cloud.call("is_ready")):
		_fallback("cloud_not_ready", local_turn)
		return
	var context: Dictionary = lesson_context_for(step, verdict)
	context["phase"] = phase
	if not bool(_cloud.call("send_transcript", said, context)):
		_fallback("busy", local_turn)
		return
	_pending = {"localTurn": local_turn, "answered": false, "phase": phase, "stepId": String(step.get("stepId", "")), "said": said}
	_first_delta_left = FIRST_DELTA_SECONDS


func end_session() -> void:
	_active = false
	_scripted.end_session()
	_pending = {}
	_first_delta_left = -1.0
	if _cloud != null and bool(_cloud.call("is_active")):
		_cloud.call("end", "scene")


func cancel() -> void:
	if _cloud != null:
		_cloud.call("barge_in")


## The scene pumps its synthesis provider; the wrapper forwards here.
func advance(delta: float) -> void:
	if _cloud != null:
		_cloud.call("advance", delta)
	if _first_delta_left >= 0.0:
		_first_delta_left -= delta
		if _first_delta_left < 0.0:
			_first_delta_left = -1.0
			if not _pending.is_empty() and not bool(_pending["answered"]):
				var local_turn: Dictionary = _pending["localTurn"]
				_pending = {}
				if _cloud != null:
					_cloud.call("barge_in")  # cancels the reply that never started
				_fallback("timeout", local_turn)


# -- cloud session events ------------------------------------------------------------------------

func _on_first_delta(_text: String) -> void:
	if _pending.is_empty() or bool(_pending["answered"]):
		return
	_emit_early(String(_cloud.call("streamed_text")))


func _on_speaking_changed(active: bool) -> void:
	if active:
		_on_first_delta("")


func _emit_early(words: String) -> void:
	_pending["answered"] = true
	_first_delta_left = -1.0
	var turn: Dictionary = (_pending["localTurn"] as Dictionary).duplicate(true)
	var line: String = TurnValidator.sanitize_text(words, TurnValidator.MAX_SPEECH)
	if not line.is_empty() and TurnValidator.check_text(line, "speech", TurnValidator.MAX_SPEECH, true).is_empty():
		turn["speech"] = line
		turn["subtitle"] = line
	_log.append({"kind": "early", "reason": ""})
	_cloud.call("offer_reply_for_speech")
	turn_ready.emit(TurnValidator.coerce(turn))


func _on_cloud_turn(turn: Dictionary) -> void:
	if _pending.is_empty():
		return
	var answered: bool = bool(_pending["answered"])
	var final_turn: Dictionary = TurnValidator.coerce(turn)
	if not answered:
		# No delta ever streamed (a text-less reply): this is the one turn.
		_pending["answered"] = true
		_first_delta_left = -1.0
		var local_turn: Dictionary = _pending["localTurn"]
		final_turn["lessonAction"] = String(local_turn.get("lessonAction", final_turn.get("lessonAction", "retry")))
		_log.append({"kind": "final_direct", "reason": ""})
		_cloud.call("offer_reply_for_speech")
		turn_ready.emit(final_turn)
	else:
		_log.append({"kind": "final", "reason": ""})
	turn_meta.emit({"final": final_turn, "stepId": String(_pending.get("stepId", "")), "provider": provider_name()})
	_pending = {}


func _on_cloud_turn_failed(reason: String) -> void:
	if _pending.is_empty():
		return
	var local_turn: Dictionary = _pending["localTurn"]
	var answered: bool = bool(_pending["answered"])
	_pending = {}
	_first_delta_left = -1.0
	if not answered:
		_fallback(reason, local_turn)
	else:
		fallback_used.emit(reason)


func _on_cloud_cancelled() -> void:
	if _pending.is_empty():
		return
	if not bool(_pending["answered"]):
		# Cancelled before a single word (a server-side cancel): say the
		# scripted line so the child is never left waiting.
		var local_turn: Dictionary = _pending["localTurn"]
		_pending = {}
		_first_delta_left = -1.0
		_fallback("cancelled", local_turn)
		return
	_pending = {}


func _on_cloud_replaced(_turn: Dictionary) -> void:
	if _pending.is_empty():
		return
	if not bool(_pending["answered"]):
		var local_turn: Dictionary = _pending["localTurn"]
		_pending = {}
		_first_delta_left = -1.0
		_fallback("safety", local_turn)
		return
	fallback_used.emit("safety")
	_pending = {}


func _on_cloud_fell_back(reason: String) -> void:
	if not _pending.is_empty() and not bool(_pending["answered"]):
		var local_turn: Dictionary = _pending["localTurn"]
		_pending = {}
		_fallback(reason, local_turn)
	else:
		fallback_used.emit(reason)
	_pending = {}
	_first_delta_left = -1.0


func _fallback(reason: String, local_turn: Dictionary) -> void:
	_log.append({"kind": "fallback", "reason": reason})
	fallback_used.emit(reason)
	turn_ready.emit(TurnValidator.coerce(local_turn))


func _on_scripted_routed(action: String, target_id: String) -> void:
	lesson_routed.emit(action, target_id)


func _wire() -> void:
	if _wired or _cloud == null:
		return
	_wired = true
	_cloud.subtitle_delta.connect(_on_first_delta)
	_cloud.speaking_changed.connect(_on_speaking_changed)
	_cloud.turn_ready.connect(_on_cloud_turn)
	_cloud.turn_failed.connect(_on_cloud_turn_failed)
	_cloud.cancelled.connect(_on_cloud_cancelled)
	_cloud.reply_replaced.connect(_on_cloud_replaced)
	_cloud.fell_back.connect(_on_cloud_fell_back)
