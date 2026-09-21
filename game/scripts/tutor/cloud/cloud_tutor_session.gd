extends RefCounted

## CloudTutorSession -- the LIFECYCLE of one cloud tutor session
## (`docs/ALIZ_TUTOR_CLOUD_CLIENT.md`). Pure logic: it owns a `CloudTutorApi`
## (REST) and a `CloudRealtimeTransport` (WebSocket), optionally a
## `CloudAudioPlayer` for the reply audio, and talks to Aliz's face through
## the same duck-typed `TutorFace` calls the scripted path uses. No network
## primitive lives here; nothing here references a 3D node type.
##
##   idle -> quota -> creating -> minting -> connecting -> ready -> ending -> ended
##                                   ^            |                  \
##                                   +-- reconnect once (fresh token) -+-> failed (fell_back)
##
##   start()                 GET /quota (0 left -> fell_back "quota_exhausted",
##                           no session), POST /sessions, POST /realtime/token,
##                           transport.connect_session(token) -> `ready`.
##   push_audio(pcm)         forwarded ONLY while ready, not muted, and the
##                           capture source (the hands-free session: capturing
##                           and not echo-gated) says yes. There is no PCM
##                           source in the game today; the path is exercised
##                           with synthetic frames.
##   send_transcript(text, lesson_context)   the on-device transcript path;
##                           ONE reply follows: text deltas (`subtitle_delta`,
##                           `subtitle_changed`), audio chunks (player +
##                           `speaking_changed(true)`, mouth from the played
##                           level), validated tool calls (`tool_applied`),
##                           then `turn_ready(turn)` at response.done and
##                           `speaking_changed(false)` when the audio drained.
##                           The RUNNING transcript is checked on every delta
##                           for a URL or a banned word: the reply is cancelled
##                           at once, playback truncated, and
##                           `reply_replaced(fallback_turn)` says what to say
##                           instead ("Let's try together!").
##   barge_in()              transport.cancel() (response.cancel + truncate at
##                           the played position) + playback dropped.
##   end(reason)             transport closed, POST /sessions/:id/end with
##                           {reason, secondsUsed, usage}, then `ended`.
##                           Reasons: parent_stop, background, quota_expired,
##                           idle, lesson_complete, scene, token_expired,
##                           session_ended, provider_failed, not_approved.
##
## Quota, both sides: the client mirror (`TutorQuota`, passed in) stays
## authoritative for the safe-point closing -- when it reports exhausted this
## session ends at the next boundary; the server's 402 also ends the session
## at the next boundary and is handed to the mirror as `exhausted`. Idle for
## `IDLE_SECONDS` ends it; the app backgrounding ends it; the token expiring
## ends it at the boundary.
##
## Provider failure: a socket error, a close, a 503 or a timeout while the
## session is up is answered ONCE by minting a fresh token and reconnecting;
## a second failure emits `fell_back(reason)` and the owner runs the local
## scripted tutor -- never a dead classroom. A reply lost to that failure is
## reported as `turn_failed(reason)` so exactly one turn still reaches the
## scene for every request.

signal state_changed(from_state: String, to_state: String)
signal ready(info: Dictionary)
signal subtitle_delta(text: String)
signal subtitle_changed(text: String)
signal speaking_changed(active: bool)
signal turn_ready(turn: Dictionary)
signal turn_failed(reason: String)
signal reply_replaced(turn: Dictionary)
signal cancelled()
signal tool_applied(name: String, args: Dictionary)
signal input_transcript(text: String)
signal child_speech_started()
signal quota_updated(quota: Dictionary)
signal fell_back(reason: String)
signal ended(reason: String, summary: Dictionary)

const ApiScript := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")

const STATE_IDLE: String = "idle"
const STATE_QUOTA: String = "quota"
const STATE_CREATING: String = "creating"
const STATE_MINTING: String = "minting"
const STATE_CONNECTING: String = "connecting"
const STATE_READY: String = "ready"
const STATE_ENDING: String = "ending"
const STATE_ENDED: String = "ended"
const STATE_FAILED: String = "failed"

const REASON_PARENT_STOP: String = "parent_stop"
const REASON_BACKGROUND: String = "background"
const REASON_QUOTA: String = "quota_expired"
const REASON_IDLE: String = "idle"
const REASON_COMPLETE: String = "lesson_complete"
const REASON_SCENE: String = "scene"
const REASON_TOKEN_EXPIRED: String = "token_expired"
const REASON_SESSION_ENDED: String = "session_ended"
const REASON_PROVIDER_FAILED: String = "provider_failed"
const REASON_NOT_APPROVED: String = "not_approved"

const IDLE_SECONDS: float = 120.0
const BUSY_ERROR_CODE: String = "conversation_already_has_active_response"
const MAX_RECONNECTS: int = 1
const MAX_RATE_LIMIT_RETRIES: int = 1
const RETRY_DELAY_SECONDS: float = 0.5
const RATE_LIMIT_DEFAULT_RETRY_SECONDS: float = 2.0
## The token is refreshed this many seconds before it expires (a boundary).
const TOKEN_EXPIRY_MARGIN_SECONDS: int = 5

var _api: RefCounted = null
var _transport: RefCounted = null
var _player: Node = null
var _face: Object = null
var _quota: Object = null
var _quota_source: Callable = Callable()
var _capture_source: Callable = Callable()
var _clock: Callable = Callable()

var _state: String = STATE_IDLE
var _lesson_id: String = ""
var _mode: String = "realtime"
var _session_id: String = ""
var _entitlement: String = ""
var _server_quota: Dictionary = {}
var _reconnects: int = 0
var _rate_limit_retries: int = 0
var _end_at_boundary: bool = false
var _boundary_reason: String = ""
var _end_reason: String = ""
var _idle_seconds: float = 0.0
var _active_seconds: float = 0.0
var _muted: bool = false
var _speaking: bool = false
var _reply_open: bool = false
var _reply_had_audio: bool = false
var _reply_done: bool = false
var _reply_turn: Dictionary = {}
## Set by the provider when it emitted the turn for the open reply, so the
## synthesis wrapper attaches THAT speak_turn() to the stream and no other.
var _reply_claimable: bool = false
var _streamed_text: String = ""
var _retry_left: float = -1.0
var _retry_action: String = ""
## Set while THIS object closes the transport, so its synchronous `closed`
## is not mistaken for a failure; and while a reply is replaced for safety,
## so its cancel is not reported as a barge-in.
var _closing_transport: bool = false
var _replacing: bool = false
var _wired: bool = false
var _history: Array = []
var _last_summary: Dictionary = {}


# -- wiring ------------------------------------------------------------------------------

func set_api(api: RefCounted) -> void:
	_api = api


func set_transport(transport: RefCounted) -> void:
	_transport = transport


func set_audio_player(player: Node) -> void:
	_player = player


func set_face(face: Object) -> void:
	_face = face


## The client quota mirror (`TutorQuota`) or a Callable that returns it (the
## scene builds its meter lazily).
func set_quota(quota: Object) -> void:
	_quota = quota


func set_quota_source(source: Callable) -> void:
	_quota_source = source


## `Callable() -> bool`: may microphone frames stream right now?
func set_capture_source(source: Callable) -> void:
	_capture_source = source


## Tests: unix seconds.
func set_clock(clock: Callable) -> void:
	_clock = clock


func configure(lesson_id: String, mode: String = "realtime") -> void:
	_lesson_id = lesson_id
	_mode = mode


func api() -> RefCounted:
	return _api


func transport() -> RefCounted:
	return _transport


# -- queries ------------------------------------------------------------------------------

func get_state() -> String:
	return _state


func state_history() -> Array:
	return _history.duplicate()


func is_active() -> bool:
	return _state in [STATE_QUOTA, STATE_CREATING, STATE_MINTING, STATE_CONNECTING, STATE_READY]


func is_ready() -> bool:
	return _state == STATE_READY and _transport != null and _transport.is_connected_session()


func is_speaking() -> bool:
	return _speaking


## True from `send_transcript()` until the reply finished playing, was
## cancelled, replaced or lost: the synthesis wrapper attaches to it.
func is_reply_open() -> bool:
	return _reply_open


func is_reply_done() -> bool:
	return _reply_done


## True while a reply is being replaced for safety (its cancel is not a barge-in).
func is_replacing() -> bool:
	return _replacing


func reply_had_audio() -> bool:
	return _reply_had_audio


## The conversation provider says: the next `speak_turn()` is this reply.
func offer_reply_for_speech() -> void:
	if _reply_open:
		_reply_claimable = true


## The synthesis wrapper asks: is the turn I was handed the open reply? True
## once per offer; anything else spoken while a reply is open is a new local
## line that supersedes it.
func claim_reply_for_speech() -> bool:
	if _reply_open and _reply_claimable:
		_reply_claimable = false
		return true
	return false


func reply_turn() -> Dictionary:
	return _reply_turn.duplicate(true)


func streamed_text() -> String:
	return _streamed_text


func session_id() -> String:
	return _session_id


func entitlement() -> String:
	return _entitlement


func server_quota() -> Dictionary:
	return _server_quota.duplicate(true)


func ends_at_boundary() -> bool:
	return _end_at_boundary


func reconnect_count() -> int:
	return _reconnects


func seconds_used() -> float:
	return _active_seconds


func last_summary() -> Dictionary:
	return _last_summary.duplicate(true)


## `{tokensIn, tokensOut, audioSeconds, audioSecondsIn, audioSecondsOut, responses}`.
func usage() -> Dictionary:
	var out: Dictionary = {"tokensIn": 0, "tokensOut": 0, "audioSecondsIn": 0.0, "audioSecondsOut": 0.0, "responses": 0}
	if _transport != null and _transport.has_method("usage"):
		out = _transport.call("usage")
	out["audioSeconds"] = float(out.get("audioSecondsIn", 0.0)) + float(out.get("audioSecondsOut", 0.0))
	return out


## May microphone frames stream right now?
func is_streaming_allowed() -> bool:
	if not is_ready() or _muted:
		return false
	if _capture_source.is_valid():
		return bool(_capture_source.call())
	return true


# -- lifecycle -----------------------------------------------------------------------------

func start() -> bool:
	if _state != STATE_IDLE:
		return false
	if _api == null or _transport == null:
		_fail("not_configured")
		return false
	if not bool(_api.call("is_available")):
		_fail(ApiScript.CODE_CLOUD_DISABLED)
		return false
	_wire()
	_reconnects = 0
	_rate_limit_retries = 0
	_end_at_boundary = false
	_boundary_reason = ""
	_idle_seconds = 0.0
	_active_seconds = 0.0
	_set_state(STATE_QUOTA)
	_api.call("fetch_quota")
	return true


func push_audio(pcm: PackedByteArray) -> bool:
	if not is_streaming_allowed() or pcm.is_empty():
		return false
	_idle_seconds = 0.0
	return bool(_transport.send_audio(pcm))


func send_transcript(text: String, lesson_context: Dictionary) -> bool:
	if not is_ready() or _transport.is_responding():
		return false
	_begin_reply()
	if not bool(_transport.send_text(text, lesson_context)):
		_reply_open = false
		return false
	_idle_seconds = 0.0
	return true


## The child interrupted: cancel the reply now; what was not played is never played.
func barge_in() -> void:
	if _transport != null and _transport.is_responding():
		_transport.cancel()  # emits response_cancelled -> _on_cancelled
	else:
		_close_reply()


func mute(muted: bool) -> void:
	_muted = muted


func on_app_background() -> void:
	if is_active():
		end(REASON_BACKGROUND)


func parent_stop() -> void:
	if is_active():
		end(REASON_PARENT_STOP)


## Ends the session now. Idempotent.
func end(reason: String) -> void:
	if _state == STATE_ENDING or _state == STATE_ENDED:
		return
	_end_reason = reason
	_set_state(STATE_ENDING)
	_close_reply()
	_close_transport()
	if _session_id.is_empty() or _api == null or not bool(_api.call("is_available")):
		_finish_end({"ok": false, "code": "no_session", "body": {}})
		return
	_api.call("end_session", _session_id, reason, _active_seconds, usage())


## Asks the server for the current quota (after the session, for the break card).
func refresh_quota() -> bool:
	if _api == null or not bool(_api.call("is_available")):
		return false
	return bool(_api.call("fetch_quota"))


# -- the frame -----------------------------------------------------------------------------

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	if _api != null:
		_api.call("advance", delta)
	if _transport != null:
		_transport.advance(delta)
	if _player != null and is_instance_valid(_player) and not _player.is_inside_tree():
		_player.call("advance", delta)
	if _retry_left >= 0.0:
		_retry_left -= delta
		if _retry_left < 0.0:
			_retry_left = -1.0
			_run_retry()
	if _state != STATE_READY:
		return
	_active_seconds += delta
	if not _reply_open and not _transport.is_responding():
		_idle_seconds += delta
		if _idle_seconds >= IDLE_SECONDS:
			end(REASON_IDLE)
			return
	var expires: int = int(_transport.call("token_expires_unix")) if _transport.has_method("token_expires_unix") else 0
	if expires > 0 and _now() >= expires - TOKEN_EXPIRY_MARGIN_SECONDS:
		_arm_boundary(REASON_TOKEN_EXPIRED)
	var mirror: Object = _quota_now()
	if mirror != null and mirror.has_method("is_exhausted") and bool(mirror.call("is_exhausted")):
		_arm_boundary(REASON_QUOTA)
	if _end_at_boundary and not _reply_open and not _transport.is_responding():
		end(_boundary_reason)


# -- api replies ------------------------------------------------------------------------------

func _on_api_completed(kind: String, result: Dictionary) -> void:
	var ok: bool = bool(result.get("ok", false))
	var code: String = String(result.get("code", ""))
	var body: Dictionary = result.get("body", {})
	match kind:
		ApiScript.KIND_QUOTA:
			if ok:
				_apply_quota(body, String(body.get("entitlement", _entitlement)))
			if _state != STATE_QUOTA:
				return
			if ok and bool(_server_quota.get("known", false)) and float(_server_quota.get("remainingSeconds", 1.0)) <= 0.0:
				_on_quota_exhausted(body)
				return
			if not ok and code in [ApiScript.CODE_NOT_APPROVED, ApiScript.CODE_QUOTA_EXHAUSTED, ApiScript.CODE_CLOUD_DISABLED]:
				_on_api_error(code, body, result)
				return
			# Unreachable quota is not fatal on its own: the session call decides.
			_set_state(STATE_CREATING)
			_api.call("create_session", _lesson_id, _mode)
		ApiScript.KIND_SESSION:
			if _state != STATE_CREATING:
				return
			if not ok:
				_on_api_error(code, body, result)
				return
			_session_id = String(body.get("sessionId", ""))
			if _session_id.is_empty():
				_fail(ApiScript.CODE_BAD_RESPONSE)
				return
			_apply_quota(body.get("quota", {}), String(body.get("entitlement", "")))
			_set_state(STATE_MINTING)
			_api.call("mint_token", _session_id)
		ApiScript.KIND_TOKEN:
			if _state != STATE_MINTING:
				return
			if not ok:
				_on_api_error(code, body, result)
				return
			_set_state(STATE_CONNECTING)
			if not bool(_transport.connect_session(body)):
				_on_transport_trouble(String(_transport.call("last_error")))
		ApiScript.KIND_END:
			_finish_end(result)
		_:
			pass


func _on_api_error(code: String, body: Dictionary, result: Dictionary) -> void:
	match code:
		ApiScript.CODE_QUOTA_EXHAUSTED:
			_on_quota_exhausted(body)
		ApiScript.CODE_NOT_APPROVED:
			_fail(REASON_NOT_APPROVED)
		ApiScript.CODE_SESSION_ENDED:
			_fail(REASON_SESSION_ENDED)
		ApiScript.CODE_RATE_LIMITED:
			if _rate_limit_retries < MAX_RATE_LIMIT_RETRIES:
				_rate_limit_retries += 1
				var wait: float = float(result.get("retryAfterSeconds", 0.0))
				_schedule_retry(_state, wait if wait > 0.0 else RATE_LIMIT_DEFAULT_RETRY_SECONDS)
			else:
				_fail(code)
		ApiScript.CODE_CLOUD_DISABLED:
			_fail(code)
		_:
			# provider_unavailable, timeout, bad_response, not_configured, http_*
			_on_transport_trouble(code)


## One reconnect with a fresh token; the second failure falls back.
func _on_transport_trouble(reason: String) -> void:
	if not is_active():
		return
	var lost_reply: bool = _reply_open
	if _reconnects >= MAX_RECONNECTS or _session_id.is_empty():
		if lost_reply:
			_close_reply()
			turn_failed.emit(reason)
		_fail(reason)
		return
	_reconnects += 1
	if lost_reply:
		_close_reply()
		turn_failed.emit(reason)
	if not is_active():
		return  # the boundary closed the session while the reply was dropped
	_close_transport()
	_set_state(STATE_MINTING)
	_schedule_retry(STATE_MINTING, RETRY_DELAY_SECONDS)


func _schedule_retry(action: String, seconds: float) -> void:
	_retry_action = action
	_retry_left = maxf(seconds, 0.0)


func _run_retry() -> void:
	var action: String = _retry_action
	_retry_action = ""
	if not is_active():
		return
	match action:
		STATE_QUOTA:
			_api.call("fetch_quota")
		STATE_CREATING:
			_api.call("create_session", _lesson_id, _mode)
		STATE_MINTING:
			_set_state(STATE_MINTING)
			_api.call("mint_token", _session_id)
		_:
			pass


func _on_quota_exhausted(body: Dictionary) -> void:
	if body.has("quota"):
		_apply_quota(body["quota"], _entitlement)
	var mirror: Object = _quota_now()
	if mirror != null and mirror.has_method("apply_server_failure"):
		var failure: Dictionary = {"ok": false, "state": "exhausted", "code": ApiScript.CODE_QUOTA_EXHAUSTED}
		if not _server_quota.is_empty():
			failure["quota"] = _server_quota_for_mirror()
		mirror.call("apply_server_failure", failure)
	if _state in [STATE_QUOTA, STATE_CREATING, STATE_MINTING, STATE_CONNECTING]:
		_fail(ApiScript.CODE_QUOTA_EXHAUSTED)
		return
	_arm_boundary(REASON_QUOTA)
	if not _reply_open and not _transport.is_responding():
		end(REASON_QUOTA)


func _arm_boundary(reason: String) -> void:
	if _end_at_boundary:
		return
	_end_at_boundary = true
	_boundary_reason = reason


func _apply_quota(raw: Variant, entitlement_name: String) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var block: Dictionary = raw
	if block.has("quota") and typeof(block["quota"]) == TYPE_DICTIONARY:
		block = block["quota"]
	var allowance: float = _number(block.get("allowanceSeconds", block.get("dailyAllowanceSeconds", 0.0)))
	var used: float = _number(block.get("usedSeconds", 0.0))
	var known: bool = block.has("allowanceSeconds") or block.has("dailyAllowanceSeconds")
	if not known and _server_quota.is_empty():
		return  # a reply without a quota block tells us nothing
	if not known:
		return
	_server_quota = {
		"allowanceSeconds": allowance, "usedSeconds": used, "remainingSeconds": maxf(allowance - used, 0.0),
		"resetAtUtc": String(block.get("resetAtUtc", "")),
		"entitlement": entitlement_name if not entitlement_name.is_empty() else String(block.get("entitlement", "free")),
		"known": true,
	}
	if not entitlement_name.is_empty():
		_entitlement = entitlement_name
	var mirror: Object = _quota_now()
	if mirror != null and mirror.has_method("apply_server_quota"):
		mirror.call("apply_server_quota", _server_quota_for_mirror(), false)
	quota_updated.emit(server_quota())


## `TutorQuota` reads `dailyAllowanceSeconds`; the contract says `allowanceSeconds`.
func _server_quota_for_mirror() -> Dictionary:
	return {
		"entitlement": String(_server_quota.get("entitlement", "free")),
		"dailyAllowanceSeconds": float(_server_quota.get("allowanceSeconds", 0.0)),
		"usedSeconds": float(_server_quota.get("usedSeconds", 0.0)),
		"remainingSeconds": float(_server_quota.get("remainingSeconds", 0.0)),
		"resetAtUtc": String(_server_quota.get("resetAtUtc", "")),
	}


# -- transport events --------------------------------------------------------------------------

func _on_connected(info: Dictionary) -> void:
	if _state != STATE_CONNECTING:
		return
	_idle_seconds = 0.0
	_set_state(STATE_READY)
	if _transport.has_method("set_played_ms_source") and _player != null:
		_transport.call("set_played_ms_source", Callable(_player, "played_ms"))
	ready.emit({"sessionId": _session_id, "entitlement": _entitlement, "quota": server_quota(),
		"transport": String(info.get("transport", "")), "reconnects": _reconnects})


func _on_text_delta(text: String) -> void:
	if not _reply_open and not _open_server_reply():
		return
	_streamed_text += text
	_idle_seconds = 0.0
	# Safety on the running words: a URL or a banned word cancels the reply
	# before the next delta can play.
	var reasons: Array = TurnValidator.check_text(_streamed_text, "speech", 100000, true)
	for reason: String in reasons:
		if reason.ends_with(":url") or reason.ends_with(":banned_word"):
			_replace_reply(reason)
			return
	subtitle_delta.emit(text)
	subtitle_changed.emit(_streamed_text.strip_edges())


func _on_audio_chunk(pcm: PackedByteArray) -> void:
	if not _reply_open and not _open_server_reply():
		return
	_reply_had_audio = true
	if _player != null and is_instance_valid(_player):
		_player.call("push_pcm16", pcm)
	_set_speaking(true)


func _on_audio_level(level: float, _bytes: int) -> void:
	if not _reply_open:
		return
	if _player == null or not is_instance_valid(_player):
		_drive_mouth(level)


func _on_player_level(level: float) -> void:
	if _speaking:
		_drive_mouth(level)


func _on_player_drained() -> void:
	if _reply_open and _reply_done:
		_close_reply()


func _on_tool_call(name: String, args: Dictionary) -> void:
	if not _reply_open:
		return
	match name:
		"gesture":
			_face_call("play_gesture", String(args.get("name", "")))
		"set_emotion":
			_face_call("set_expression", String(args.get("name", "")))
		_:
			pass
	tool_applied.emit(name, args)


func _on_response_done(turn: Dictionary) -> void:
	if not _reply_open:
		return
	_reply_done = true
	_reply_turn = TurnValidator.coerce(turn)
	subtitle_changed.emit(String(_reply_turn.get("subtitle", _reply_turn.get("speech", ""))))
	turn_ready.emit(_reply_turn.duplicate(true))
	if _reply_had_audio and _player != null and is_instance_valid(_player):
		_player.call("mark_complete")
		if not bool(_player.call("is_playing_audio")):
			_close_reply()
	else:
		_close_reply()


func _on_cancelled() -> void:
	var was_open: bool = _reply_open
	_close_reply()
	if was_open and not _replacing:
		cancelled.emit()
	_after_boundary()


func _on_input_transcript(text: String) -> void:
	_idle_seconds = 0.0
	input_transcript.emit(text)


func _on_server_speech_started() -> void:
	_idle_seconds = 0.0
	child_speech_started.emit()


func _on_transport_error(code: String, _message: String) -> void:
	if _state == STATE_ENDING or _state == STATE_ENDED or _closing_transport:
		return
	if _state == STATE_READY and code == BUSY_ERROR_CODE:
		# The request raced the server's cancel of the previous reply: this
		# turn is lost (the provider says the scripted line), the socket stays.
		if _reply_open:
			_close_reply()
			turn_failed.emit(code)
		return
	if _state == STATE_READY and code == "timeout" and _reply_open:
		# The reply is lost; the socket may be fine. Count it as trouble
		# (one reconnect), which also reports the lost turn.
		_on_transport_trouble(code)
		return
	_on_transport_trouble(code)


func _on_transport_closed(reason: String) -> void:
	if _state == STATE_ENDING or _state == STATE_ENDED or _closing_transport:
		return
	_on_transport_trouble(reason)


func _close_transport() -> void:
	if _transport == null:
		return
	_closing_transport = true
	_transport.close()
	_closing_transport = false


# -- reply bookkeeping -------------------------------------------------------------------------------

## A reply the SERVER started (server VAD on streamed audio): played and
## lip-synced like any other, but no `send_transcript()` asked for it, so the
## conversation provider has nothing pending and the lesson loop is untouched.
func _open_server_reply() -> bool:
	if _state != STATE_READY or _transport == null or not _transport.is_responding():
		return false
	if _transport.has_method("is_server_initiated") and not bool(_transport.call("is_server_initiated")):
		return false
	_begin_reply()
	return true


func _begin_reply() -> void:
	_reply_open = true
	_reply_claimable = false
	_reply_done = false
	_reply_had_audio = false
	_reply_turn = {}
	_streamed_text = ""
	if _player != null and is_instance_valid(_player):
		_player.call("begin_reply")


func _close_reply() -> void:
	if _player != null and is_instance_valid(_player) and bool(_player.call("is_playing_audio")):
		_player.call("truncate")
	_reply_open = false
	_reply_claimable = false
	_set_speaking(false)
	_after_boundary()


## The running transcript failed a safety rule: cancel, truncate, replace.
func _replace_reply(reason: String) -> void:
	push_warning("cloud tutor: reply replaced (%s)" % reason)
	var fallback: Dictionary = TurnValidator.fallback_turn()
	_replacing = true
	if _transport != null and _transport.is_responding():
		_transport.cancel()
	_close_reply()
	_replacing = false
	reply_replaced.emit(fallback)


func _after_boundary() -> void:
	if _state == STATE_READY and _end_at_boundary and not _reply_open \
			and (_transport == null or not _transport.is_responding()):
		end(_boundary_reason)


func _set_speaking(active: bool) -> void:
	if active == _speaking:
		return
	_speaking = active
	_face_call("set_speaking", active)
	if not active:
		_drive_mouth(0.0)
	speaking_changed.emit(active)


## The mouth from the PLAYED level, unless the face's own lip sync is already
## reading the Voice bus (then it sees this audio and drives the mouth itself).
func _drive_mouth(level: float) -> void:
	if _face == null:
		return
	if _face.has_method("get_lip_sync"):
		var lip: Variant = _face.call("get_lip_sync")
		if lip != null and (lip as Object).has_method("is_capturing") and bool((lip as Object).call("is_capturing")):
			return
	_face_call("set_mouth_open", clampf(level, 0.0, 1.0))


func _face_call(method: String, arg: Variant) -> void:
	if _face != null and _face.has_method(method):
		_face.call(method, arg)


# -- ending ---------------------------------------------------------------------------------------

func _fail(reason: String) -> void:
	if _state in [STATE_ENDING, STATE_ENDED, STATE_FAILED]:
		return
	_set_state(STATE_FAILED)
	_close_reply()
	_close_transport()
	fell_back.emit(reason)
	_end_reason = "%s:%s" % [REASON_PROVIDER_FAILED, reason]
	if _session_id.is_empty() or _api == null or not bool(_api.call("is_available")):
		_finish_end({"ok": false, "code": "no_session", "body": {}})
		return
	_api.call("end_session", _session_id, _end_reason, _active_seconds, usage())


func _finish_end(result: Dictionary) -> void:
	if _state == STATE_ENDED:
		return
	_last_summary = {
		"reason": _end_reason, "secondsUsed": snappedf(_active_seconds, 0.1), "usage": usage(),
		"serverAck": bool(result.get("ok", false)), "code": String(result.get("code", "")),
		"quota": server_quota(), "reconnects": _reconnects, "sessionId": _session_id,
	}
	var body: Dictionary = result.get("body", {})
	if typeof(body.get("quota", null)) == TYPE_DICTIONARY:
		_apply_quota(body["quota"], _entitlement)
		_last_summary["quota"] = server_quota()
	_set_state(STATE_ENDED)
	ended.emit(_end_reason, _last_summary.duplicate(true))


# -- internals ------------------------------------------------------------------------------------

func _wire() -> void:
	if _wired:
		return
	_wired = true
	_api.completed.connect(_on_api_completed)
	_transport.connected.connect(_on_connected)
	_transport.response_text_delta.connect(_on_text_delta)
	_transport.response_audio_delta.connect(_on_audio_level)
	if _transport.has_signal("response_audio_chunk"):
		_transport.response_audio_chunk.connect(_on_audio_chunk)
	if _transport.has_signal("tool_call"):
		_transport.tool_call.connect(_on_tool_call)
	_transport.response_done.connect(_on_response_done)
	_transport.response_cancelled.connect(_on_cancelled)
	_transport.input_transcript.connect(_on_input_transcript)
	_transport.server_speech_started.connect(_on_server_speech_started)
	_transport.error.connect(_on_transport_error)
	_transport.closed.connect(_on_transport_closed)
	if _player != null and is_instance_valid(_player):
		if _player.has_signal("level_changed"):
			_player.level_changed.connect(_on_player_level)
		if _player.has_signal("drained"):
			_player.drained.connect(_on_player_drained)


func _quota_now() -> Object:
	if _quota != null:
		return _quota
	if _quota_source.is_valid():
		var value: Variant = _quota_source.call()
		return value if typeof(value) == TYPE_OBJECT else null
	return null


func _now() -> int:
	if _clock.is_valid():
		return int(_clock.call())
	return int(Time.get_unix_time_from_system())


func _set_state(next: String) -> void:
	if next == _state:
		return
	var previous: String = _state
	_state = next
	_history.append(next)
	state_changed.emit(previous, next)


static func _number(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0
	var number: float = float(value)
	return number if is_finite(number) and number >= 0.0 else 0.0
