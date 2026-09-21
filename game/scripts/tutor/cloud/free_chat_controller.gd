extends RefCounted

## FreeChatController -- lesson <-> free-conversation mode for the classroom
## (`docs/ALIZ_TUTOR_FREE_CHAT.md`). Development/QA only: it is reachable only
## while `TutorFlags.cloud_enabled()` is true (the bridge exists), and the
## Worker itself answers `403 feature_disabled` unless it runs in DEV_MODE
## with `FREE_CHAT_ENABLED`; then the controller drops straight back to the
## lesson. Pure logic: no network class (the REST calls go through the
## `CloudTutorApi` the bridge already built), no 3D types, no I/O.
##
## ## How it plugs in (the lead's one-line hook)
##
## The classroom keeps ONE presentation path: `tutor_scene._on_turn_ready()`
## -> `_speak_turn()`, connected to the bound provider's `turn_ready`. This
## controller never forks it: every chat reply is emitted THROUGH that same
## `turn_ready` (`_presenter.emit_signal("turn_ready", turn)`), so face,
## gesture, card, subtitle, voice and the listening state are the scene's own.
## The transcript reaches the controller at the scene's single provider entry,
## `_request_turn(transcript, phase)`, via one line the lead adds there:
##
##   if _cloud_bridge != null and _cloud_bridge.has_meta(FREE_CHAT_META) and bool(_cloud_bridge.get_meta(FREE_CHAT_META).call("intercept_turn", transcript, phase)): return
##
## (`FREE_CHAT_META` is the literal "freeChat".) With no controller attached,
## or in lesson mode, the line is a no-op and the lesson provider answers as
## before. `attach_to_bridge(bridge)` (idempotent) stores the controller as
## that meta entry and takes the API, the bound provider and the lesson
## session from the bridge's public getters.
##
## ## Modes
##
##   enter_free_chat()   ends nothing on the lesson side; opens a chat session
##                       (`create_session("", "chat")`), then greets through
##                       `turn_ready`. `feature_disabled` / any refusal ->
##                       `chat_unavailable(code)`, back to lesson, a kind
##                       local line re-opens the current step.
##   intercept_turn()    chat mode: the child's words go to
##                       `submit_chat_turn()`; the Worker's gated TutorTurn
##                       (`lessonAction: "none"`) comes back and is presented
##                       with `lessonAction: "retry"` ("keep listening"). An
##                       empty transcript (silence / together) is answered
##                       locally; after MAX_SILENT_PROMPTS the lesson resumes.
##   return_to_lesson()  ends the chat session (`return_to_lesson`), presents
##                       a bridge line with `lessonAction: "jump_step"`, which
##                       the scene handles by re-opening the CURRENT step (the
##                       engine has not moved), so the question is asked again.
##
## ## Privacy
##
## The transcript is held only while its request is in flight; `turn_log()`
## carries counts, provider names and flags, never words. Nothing here
## persists anything. Synthetic/adult text only in every test.

signal mode_changed(mode: String)
signal chat_ready(info: Dictionary)
signal chat_turn(turn: Dictionary, meta: Dictionary)
signal chat_unavailable(code: String)
signal chat_ended(reason: String)

const ApiScript := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")

const FREE_CHAT_META: String = "freeChat"

const MODE_LESSON: String = "lesson"
const MODE_CHAT: String = "chat"

const STATE_IDLE: String = "idle"
const STATE_OPENING: String = "opening"
const STATE_READY: String = "ready"
const STATE_WAITING: String = "waiting"
const STATE_CLOSING: String = "closing"

const REASON_RETURN: String = "return_to_lesson"
const REASON_SILENT: String = "chat_silent"
const REASON_SCENE: String = "scene"

## The only lessonAction the scene applies as "listen again, same step".
const ACTION_LISTEN: String = "retry"
## Handled by the scene as "open the step the engine is on" (unchanged here).
const ACTION_REOPEN_STEP: String = "jump_step"
const MAX_SILENT_PROMPTS: int = 3
const MAX_TRANSCRIPT_CHARS: int = 500

const GREETING: String = "Hi! Let's chat! What do you want to talk about?"
const LISTENING_PROMPT: String = "I am listening! Tell me anything."
const BACK_TO_LESSON: String = "Okay! Back to our lesson!"
const NOT_AVAILABLE: String = "Let's keep going with our lesson!"
const TROUBLE_LINE: String = "Let's try together! Tell me again?"

var _api: RefCounted = null
var _presenter: Object = null
var _lesson_session: RefCounted = null
var _mode: String = MODE_LESSON
var _state: String = STATE_IDLE
var _session_id: String = ""
var _response_max_words: int = 0
var _serial: int = 0
var _awaiting: String = ""  # api kind expected next ("session" | "turn" | "end")
var _pending: Dictionary = {}
var _silent_prompts: int = 0
var _server_quota: Dictionary = {}
var _chat_config: Dictionary = {}
var _log: Array = []
var _wired: bool = false


# -- wiring -------------------------------------------------------------------------------

## Idempotent: builds (or returns) the controller stored on `bridge` under
## `FREE_CHAT_META`, wired to the bridge's API, bound provider and session.
static func attach_to_bridge(bridge: Object) -> RefCounted:
	if bridge == null:
		return null
	if bridge.has_meta(FREE_CHAT_META):
		var existing: Variant = bridge.get_meta(FREE_CHAT_META)
		if existing is RefCounted:
			return existing
	var script: GDScript = load("res://scripts/tutor/cloud/free_chat_controller.gd")
	var controller: RefCounted = script.new()
	if bridge.has_method("api"):
		controller.set_api(bridge.call("api"))
	if bridge.has_method("provider"):
		controller.set_presenter(bridge.call("provider"))
	if bridge.has_method("session"):
		controller.set_lesson_session(bridge.call("session"))
	bridge.set_meta(FREE_CHAT_META, controller)
	return controller


func set_api(api: RefCounted) -> void:
	if _api == api:
		return
	if _api != null and _wired and _api.has_signal("completed"):
		_api.completed.disconnect(_on_api_completed)
	_api = api
	_wired = false
	_wire()


## The object whose `turn_ready` the scene is connected to (the bound
## ConversationProvider). Every chat reply is emitted through it.
func set_presenter(presenter: Object) -> void:
	_presenter = presenter


## Optional: the lesson's `CloudTutorSession`, so chat is refused while that
## session is mid-handshake (the two share one serial REST queue).
func set_lesson_session(session: RefCounted) -> void:
	_lesson_session = session


## 0 = the Worker's session default (25); otherwise clamped into 8..40.
func set_response_max_words(words: int) -> void:
	_response_max_words = 0 if words <= 0 else clampi(words, ApiScript.CHAT_MIN_WORDS, ApiScript.CHAT_MAX_WORDS)


func response_max_words() -> int:
	return _response_max_words


# -- queries ------------------------------------------------------------------------------

func mode() -> String:
	return _mode


func is_chat_mode() -> bool:
	return _mode == MODE_CHAT


func get_state() -> String:
	return _state


func session_id() -> String:
	return _session_id


func server_quota() -> Dictionary:
	return _server_quota.duplicate(true)


func chat_config() -> Dictionary:
	return _chat_config.duplicate(true)


func has_turn_in_flight() -> bool:
	return _state == STATE_WAITING


## `{kind, provider, fallback, redirected, capped, words}` rows; never a transcript.
func turn_log() -> Array:
	return _log.duplicate(true)


# -- the mode switch ------------------------------------------------------------------------

## Opens the chat session; returns false (and stays in lesson mode) when the
## cloud client is unusable or the lesson session is mid-handshake.
func enter_free_chat() -> bool:
	if _mode == MODE_CHAT and _state in [STATE_OPENING, STATE_READY, STATE_WAITING]:
		return true
	if _api == null or _presenter == null or not bool(_api.call("is_available")):
		chat_unavailable.emit(ApiScript.CODE_CLOUD_DISABLED)
		return false
	if _api.has_method("has_approval") and not bool(_api.call("has_approval")):
		chat_unavailable.emit(ApiScript.CODE_NOT_APPROVED)
		return false
	if _lesson_session != null and bool(_lesson_session.call("is_active")) and not bool(_lesson_session.call("is_ready")):
		chat_unavailable.emit("lesson_session_busy")
		return false
	_wire()
	_session_id = ""
	_server_quota = {}
	_chat_config = {}
	_silent_prompts = 0
	_pending = {}
	_set_mode(MODE_CHAT)
	_state = STATE_OPENING
	_awaiting = ApiScript.KIND_SESSION
	_api.call("create_session", "", ApiScript.MODE_CHAT)
	return true


## Back to the lesson: ends the chat session and re-opens the current step.
func return_to_lesson(reason: String = REASON_RETURN, speak: bool = true) -> void:
	if _mode != MODE_CHAT:
		return
	var sid: String = _session_id
	_pending = {}
	_set_mode(MODE_LESSON)
	if not sid.is_empty() and _api != null and bool(_api.call("is_available")):
		_state = STATE_CLOSING
		_awaiting = ApiScript.KIND_END
		_api.call("end_session", sid, reason)
	else:
		_state = STATE_IDLE
		_awaiting = ""
	_session_id = ""
	chat_ended.emit(reason)
	if speak:
		_present(_local_turn(BACK_TO_LESSON, "happy", "nod", ACTION_REOPEN_STEP))


## The scene's `_request_turn` hook. True = consumed (chat mode); false =
## lesson mode, let the lesson provider answer.
func intercept_turn(transcript: String, _phase: String = "") -> bool:
	if _mode != MODE_CHAT:
		return false
	var said: String = transcript.strip_edges().left(MAX_TRANSCRIPT_CHARS)
	if said.is_empty():
		_silent_prompts += 1
		if _silent_prompts >= MAX_SILENT_PROMPTS:
			return_to_lesson(REASON_SILENT)
			return true
		_log.append({"kind": "local_prompt", "provider": "local", "fallback": "", "redirected": "", "capped": false, "words": 0})
		_present(_local_turn(LISTENING_PROMPT, "listening", "tilt", ACTION_LISTEN))
		return true
	_silent_prompts = 0
	if _state == STATE_OPENING:
		# The greeting is still on its way: answer this one when the session is up.
		_pending = {"text": said}
		return true
	if _state == STATE_WAITING:
		return true  # the scene asks again while it waits; one reply is coming
	if _state != STATE_READY or _session_id.is_empty():
		_present(_local_turn(TROUBLE_LINE, "encouraging", "tilt", ACTION_LISTEN))
		return true
	_send(said)
	return true


## The scene is leaving / backgrounding: end quietly, nothing spoken.
func on_scene_exiting() -> void:
	return_to_lesson(REASON_SCENE, false)


# -- internals --------------------------------------------------------------------------------

func _send(said: String) -> void:
	_serial += 1
	_state = STATE_WAITING
	_awaiting = ApiScript.KIND_TURN
	_api.call("submit_chat_turn", _session_id, "%s:c%d" % [_session_id, _serial], said, _response_max_words)


func _on_api_completed(kind: String, result: Dictionary) -> void:
	if _awaiting.is_empty() or kind != _awaiting:
		return  # the lesson session's traffic on the shared client
	var ok: bool = bool(result.get("ok", false))
	var code: String = String(result.get("code", ""))
	var body: Dictionary = result.get("body", {})
	match kind:
		ApiScript.KIND_SESSION:
			if _state != STATE_OPENING:
				return
			_awaiting = ""
			if not ok:
				_unavailable(code)
				return
			_session_id = String(body.get("sessionId", ""))
			if _session_id.is_empty() or String(body.get("mode", "")) != ApiScript.MODE_CHAT:
				_unavailable(ApiScript.CODE_BAD_RESPONSE)
				return
			_server_quota = ApiScript.quota_of(body)
			_chat_config = body.get("chat", {}) if typeof(body.get("chat", null)) == TYPE_DICTIONARY else {}
			_state = STATE_READY
			chat_ready.emit({"sessionId": _session_id, "quota": server_quota(), "chat": chat_config()})
			if _pending.is_empty():
				_present(_local_turn(GREETING, "happy", "wave", ACTION_LISTEN))
			else:
				var text: String = String(_pending.get("text", ""))
				_pending = {}
				_send(text)
		ApiScript.KIND_TURN:
			if _state != STATE_WAITING:
				return
			_awaiting = ""
			_state = STATE_READY
			if ok:
				_on_chat_reply(body, bool(result.get("replayed", false)))
				return
			match code:
				ApiScript.CODE_QUOTA_EXHAUSTED, ApiScript.CODE_SESSION_ENDED, ApiScript.CODE_NOT_FOUND, \
				ApiScript.CODE_NOT_APPROVED, ApiScript.CODE_CONSENT_REQUIRED, ApiScript.CODE_FEATURE_DISABLED, \
				ApiScript.CODE_CLOUD_DISABLED, ApiScript.CODE_NOT_CONFIGURED:
					_server_quota = ApiScript.quota_of(body) if not ApiScript.quota_of(body).is_empty() else _server_quota
					_log.append({"kind": "lost", "provider": "", "fallback": code, "redirected": "", "capped": false, "words": 0})
					_session_id = "" if code in [ApiScript.CODE_SESSION_ENDED, ApiScript.CODE_NOT_FOUND] else _session_id
					chat_unavailable.emit(code)
					return_to_lesson(code)
				_:
					# rate_limited, timeout, provider_unavailable, invalid_turn, ...: this
					# one answer is local; the chat goes on.
					_log.append({"kind": "lost", "provider": "", "fallback": code, "redirected": "", "capped": false, "words": 0})
					_present(_local_turn(TROUBLE_LINE, "encouraging", "tilt", ACTION_LISTEN))
		ApiScript.KIND_END:
			if _state != STATE_CLOSING:
				return
			_awaiting = ""
			_state = STATE_IDLE
			if ok and not ApiScript.quota_of(body).is_empty():
				_server_quota = ApiScript.quota_of(body)
		_:
			pass


func _on_chat_reply(body: Dictionary, replayed: bool) -> void:
	var quota: Dictionary = ApiScript.quota_of(body)
	if not quota.is_empty():
		_server_quota = quota
	var raw: Dictionary = body.get("turn", {}) if typeof(body.get("turn", null)) == TYPE_DICTIONARY else {}
	# The Worker pins a chat reply to `lessonAction: "none"`; the classroom's
	# "keep listening on this step" is `retry`. Everything else is validated
	# untouched by the shared validator (a bad reply becomes the fallback).
	var candidate: Dictionary = raw.duplicate(true)
	if String(candidate.get("lessonAction", "none")) == "none":
		candidate["lessonAction"] = ACTION_LISTEN
	var turn: Dictionary = TurnValidator.coerce(candidate)
	turn["lessonAction"] = ACTION_LISTEN
	var chat_meta: Dictionary = body.get("chat", {}) if typeof(body.get("chat", null)) == TYPE_DICTIONARY else {}
	var meta: Dictionary = {
		"provider": String(body.get("provider", "")),
		"fallback": String(body.get("fallback", "")) if body.get("fallback", null) != null else "",
		"redirected": String(chat_meta.get("redirected", "")) if chat_meta.get("redirected", null) != null else "",
		"capped": bool(chat_meta.get("capped", false)),
		"responseMaxWords": int(chat_meta.get("responseMaxWords", 0)),
		"historyTurns": int(chat_meta.get("historyTurns", 0)),
		"turnIndex": int(body.get("turnIndex", 0)),
		"replayed": replayed,
		"endAtBoundary": bool(body.get("endAtBoundary", false)),
		"words": String(turn.get("speech", "")).split(" ", false).size(),
	}
	_log.append({"kind": "reply", "provider": meta["provider"], "fallback": meta["fallback"], "redirected": meta["redirected"], "capped": meta["capped"], "words": meta["words"]})
	chat_turn.emit(turn.duplicate(true), meta)
	_present(turn)
	if bool(meta["endAtBoundary"]):
		# The day's last seconds went into this reply: the lesson's own break
		# card follows; the chat session is over on the server side.
		_session_id = ""
		_state = STATE_IDLE
		chat_ended.emit(ApiScript.CODE_QUOTA_EXHAUSTED)
		_set_mode(MODE_LESSON)


func _unavailable(code: String) -> void:
	_state = STATE_IDLE
	_session_id = ""
	_pending = {}
	_set_mode(MODE_LESSON)
	chat_unavailable.emit(code)
	_present(_local_turn(NOT_AVAILABLE, "smile", "nod", ACTION_REOPEN_STEP))


## THE presentation path: the bound provider's `turn_ready`, which the scene
## already listens to. Never a second route to the face or the voice.
func _present(turn: Dictionary) -> void:
	if _presenter == null or not _presenter.has_signal("turn_ready"):
		return
	_presenter.emit_signal("turn_ready", TurnValidator.coerce(turn))


static func _local_turn(speech: String, emotion: String, gesture: String, action: String) -> Dictionary:
	return TurnValidator.coerce({"speech": speech, "subtitle": speech, "emotion": emotion, "gesture": gesture,
		"visual": {"type": "none"}, "lessonAction": action})


func _set_mode(next: String) -> void:
	if next == _mode:
		return
	_mode = next
	mode_changed.emit(next)


func _wire() -> void:
	if _wired or _api == null or not _api.has_signal("completed"):
		return
	_wired = true
	_api.completed.connect(_on_api_completed)
