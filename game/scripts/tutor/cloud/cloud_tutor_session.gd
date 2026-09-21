extends RefCounted

## CloudTutorSession -- the LIFECYCLE of one cloud tutor session
## (`docs/ALIZ_TUTOR_CLOUD_CLIENT.md`). Pure logic: it owns a `CloudTutorApi`
## (REST) and a `CloudRealtimeTransport` (WebSocket), optionally a
## `CloudAudioPlayer` for the reply audio, and talks to Aliz's face through
## the same duck-typed `TutorFace` calls the scripted path uses. No network
## primitive lives here; nothing here references a 3D node type.
##
##   idle -> [signing_in -> consenting] -> quota -> creating -> minting -+-> connecting -> ready(realtime)
##                                                                      |        ^     |
##                                                   token 503 ---------+        +-----+ reconnect once
##                                                        v                          |
##                                                   ready(turns) ----------------> ending -> ended
##                                                                                  (failed -> fell_back)
##
##   start()                 DEV sign-in + consent when no approval token is
##                           held yet (POST /v1/parents, PUT /v1/consent),
##                           GET /tutor/entitlement (0 left -> fell_back
##                           "quota_exhausted", no session), POST /sessions,
##                           POST /realtime/token, transport.connect_session
##                           -> `ready`. When the token endpoint answers
##                           503 provider_unavailable (or any other
##                           non-fatal error: the deployed Worker has no
##                           realtime provider) the session is READY on the
##                           TURNS path instead: `send_transcript()` posts
##                           each answer to /sessions/:id/turns and the
##                           validated TutorTurn drives the classroom.
##   push_audio(pcm)         forwarded ONLY while ready on the realtime
##                           path, not muted, and the capture source (the
##                           hands-free session: capturing and not
##                           echo-gated) says yes. There is no PCM source in
##                           the game today; the path is exercised with
##                           synthetic frames. Never on the turns path.
##   send_transcript(text, lesson_context)   the on-device transcript path;
##                           ONE reply follows: realtime -> text deltas,
##                           audio chunks, tool calls, then `turn_ready`;
##                           turns -> `subtitle_changed`, `tool_applied`
##                           (`show_card`) and `turn_ready` at once from the
##                           server's validated turn, voiced locally.
##   barge_in()              realtime: transport.cancel() + playback dropped;
##                           turns: the in-flight request is dropped.
##   end(reason)             transport closed, POST /sessions/:id/end
##                           {reason} ONCE, then `ended`. Reasons:
##                           parent_stop, background, quota_expired, idle,
##                           lesson_complete, scene, token_expired,
##                           session_ended, provider_failed, not_approved.
##
## Quota, both sides: the client mirror (`TutorQuota`, passed in) stays
## authoritative for the safe-point closing -- when it reports exhausted this
## session ends at the next boundary. The server's word only ever shortens a
## session: a `quota` block with nothing left, a turn's `endAtBoundary`, or a
## 429 quota_exhausted is handed to the mirror as `exhausted`, the current
## reply finishes, the session ends and no further turn is sent.
##
## Provider failure: a socket error, a close, or a timeout while the realtime
## session is up is answered ONCE by minting a fresh token and reconnecting;
## if the mint then fails the session continues on the turns path; a turn
## request that fails transiently is retried once with the SAME
## Idempotency-Key (the server replays, never charges twice); two lost
## turns in a row emit `fell_back(reason)` and the owner runs the local
## scripted tutor -- never a dead classroom. A reply lost to any failure is
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
const STATE_SIGNING_IN: String = "signing_in"
const STATE_CONSENTING: String = "consenting"
const STATE_QUOTA: String = "quota"
const STATE_CREATING: String = "creating"
const STATE_MINTING: String = "minting"
const STATE_CONNECTING: String = "connecting"
const STATE_READY: String = "ready"
const STATE_ENDING: String = "ending"
const STATE_ENDED: String = "ended"
const STATE_FAILED: String = "failed"

const MODE_REALTIME: String = "realtime"
const MODE_TURNS: String = "turns"

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
## A turn request that fails transiently is re-sent once with the same key.
const MAX_TURN_RETRIES: int = 1
## Consecutive lost turns before the session falls back to the scripted tutor.
const MAX_TURN_FAILURES: int = 2
const RETRY_DELAY_SECONDS: float = 0.5
const RATE_LIMIT_DEFAULT_RETRY_SECONDS: float = 2.0
const RETRY_TURN: String = "turn"
## The token is refreshed this many seconds before it expires (a boundary).
const TOKEN_EXPIRY_MARGIN_SECONDS: int = 5
## Token errors that mean "no realtime here, use the turns path".
const TURNS_FALLBACK_CODES: Array[String] = [ApiScript.CODE_PROVIDER_UNAVAILABLE, ApiScript.CODE_TIMEOUT, ApiScript.CODE_BAD_RESPONSE]
const TRANSIENT_CODES: Array[String] = [ApiScript.CODE_PROVIDER_UNAVAILABLE, ApiScript.CODE_TIMEOUT, ApiScript.CODE_BAD_RESPONSE]

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
var _requested_mode: String = MODE_REALTIME
## "" until ready; then MODE_REALTIME or MODE_TURNS.
var _transport_mode: String = ""
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
## Turns path: the request in flight `{key, text, context, retries}`.
var _turn_request: Dictionary = {}
var _turn_serial: int = 0
var _turn_failures: int = 0
var _turn_log: Array = []
var _end_posted: bool = false
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


func configure(lesson_id: String, mode: String = MODE_REALTIME) -> void:
	_lesson_id = lesson_id
	_requested_mode = mode


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
	return _state in [STATE_SIGNING_IN, STATE_CONSENTING, STATE_QUOTA, STATE_CREATING, STATE_MINTING, STATE_CONNECTING, STATE_READY]


func is_ready() -> bool:
	if _state != STATE_READY:
		return false
	if _transport_mode == MODE_TURNS:
		return true
	return _transport != null and _transport.is_connected_session()


## "" before ready, then "realtime" or "turns".
func transport_mode() -> String:
	return _transport_mode


func is_turns_mode() -> bool:
	return _transport_mode == MODE_TURNS


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


## Turns path: one row per served turn
## `{turnIndex, chargedSeconds, replayed, endAtBoundary, provider, fallback, usedSeconds, usedTurns}`.
func turn_log() -> Array:
	return _turn_log.duplicate(true)


func has_turn_in_flight() -> bool:
	return not _turn_request.is_empty()


## `{tokensIn, tokensOut, audioSeconds, audioSecondsIn, audioSecondsOut, responses, turns}`.
func usage() -> Dictionary:
	var out: Dictionary = {"tokensIn": 0, "tokensOut": 0, "audioSecondsIn": 0.0, "audioSecondsOut": 0.0, "responses": 0}
	if _transport != null and _transport.has_method("usage"):
		out = _transport.call("usage")
	out["audioSeconds"] = float(out.get("audioSecondsIn", 0.0)) + float(out.get("audioSecondsOut", 0.0))
	out["turns"] = _turn_log.size()
	return out


## May microphone frames stream right now? Never on the turns path.
func is_streaming_allowed() -> bool:
	if not is_ready() or _muted or _transport_mode != MODE_REALTIME:
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
	_turn_failures = 0
	_end_at_boundary = false
	_boundary_reason = ""
	_idle_seconds = 0.0
	_active_seconds = 0.0
	_transport_mode = ""
	_end_posted = false
	if _api.has_method("has_approval") and not bool(_api.call("has_approval")):
		# No parental-approval token yet: the DEV sign-in mints one (DEV_MODE
		# Worker only; the Parent Corner flow replaces this later).
		_set_state(STATE_SIGNING_IN)
		_api.call("sign_in_dev", "")
		return true
	_set_state(STATE_QUOTA)
	_api.call("fetch_quota")
	return true


func push_audio(pcm: PackedByteArray) -> bool:
	if not is_streaming_allowed() or pcm.is_empty():
		return false
	_idle_seconds = 0.0
	return bool(_transport.send_audio(pcm))


func send_transcript(text: String, lesson_context: Dictionary) -> bool:
	if not is_ready() or _is_responding():
		return false
	_begin_reply()
	if _transport_mode == MODE_TURNS:
		_turn_serial += 1
		var key: String = "%s:t%d" % [_session_id, _turn_serial]
		_turn_request = {"key": key, "text": text, "context": lesson_context.duplicate(true), "retries": 0}
		_api.call("submit_turn", _session_id, key, text, lesson_context, 0.0)
		_idle_seconds = 0.0
		return true
	if not bool(_transport.send_text(text, lesson_context)):
		_reply_open = false
		return false
	_idle_seconds = 0.0
	return true


## The child interrupted: cancel the reply now; what was not played is never played.
func barge_in() -> void:
	if _transport_mode == MODE_TURNS:
		var was_pending: bool = not _turn_request.is_empty()
		_drop_turn_request()
		_close_reply()
		if was_pending:
			cancelled.emit()
		return
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


## Ends the session now. Idempotent: `/end` is posted once.
func end(reason: String) -> void:
	if _state == STATE_ENDING or _state == STATE_ENDED:
		return
	_end_reason = reason
	_set_state(STATE_ENDING)
	_drop_turn_request()
	_close_reply()
	_close_transport()
	_post_end()


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
	var responding: bool = _is_responding()
	if not _reply_open and not responding:
		_idle_seconds += delta
		if _idle_seconds >= IDLE_SECONDS:
			end(REASON_IDLE)
			return
	if _transport_mode == MODE_REALTIME:
		var expires: int = int(_transport.call("token_expires_unix")) if _transport.has_method("token_expires_unix") else 0
		if expires > 0 and _now() >= expires - TOKEN_EXPIRY_MARGIN_SECONDS:
			_arm_boundary(REASON_TOKEN_EXPIRED)
	var mirror: Object = _quota_now()
	if mirror != null and mirror.has_method("is_exhausted") and bool(mirror.call("is_exhausted")):
		_arm_boundary(REASON_QUOTA)
	if _end_at_boundary and not _reply_open and not _is_responding():
		end(_boundary_reason)


# -- api replies ------------------------------------------------------------------------------

func _on_api_completed(kind: String, result: Dictionary) -> void:
	var ok: bool = bool(result.get("ok", false))
	var code: String = String(result.get("code", ""))
	var body: Dictionary = result.get("body", {})
	match kind:
		ApiScript.KIND_SIGN_IN:
			if _state != STATE_SIGNING_IN:
				return
			if not ok:
				_on_api_error(kind, code, body, result)
				return
			_set_state(STATE_CONSENTING)
			_api.call("grant_consent", ApiScript.CONSENT_AI_TUTOR)
		ApiScript.KIND_CONSENT:
			if _state != STATE_CONSENTING:
				return
			if not ok and (code in [ApiScript.CODE_NOT_APPROVED, ApiScript.CODE_CLOUD_DISABLED, ApiScript.CODE_NOT_CONFIGURED] \
					or int(result.get("status", 0)) in [400, 401, 403]):
				_on_api_error(kind, ApiScript.CODE_NOT_APPROVED, body, result)
				return
			# A transient consent failure is not fatal on its own: the session call decides.
			_set_state(STATE_QUOTA)
			_api.call("fetch_quota")
		ApiScript.KIND_QUOTA:
			if ok:
				_apply_quota(body, String(body.get("entitlement", _entitlement)))
			if _state != STATE_QUOTA:
				return
			if ok and bool(_server_quota.get("known", false)) and float(_server_quota.get("remainingSeconds", 1.0)) <= 0.0:
				_on_quota_exhausted(body)
				return
			if not ok and code in [ApiScript.CODE_NOT_APPROVED, ApiScript.CODE_CONSENT_REQUIRED, ApiScript.CODE_QUOTA_EXHAUSTED, ApiScript.CODE_CLOUD_DISABLED]:
				_on_api_error(kind, code, body, result)
				return
			# Unreachable quota is not fatal on its own: the session call decides.
			_set_state(STATE_CREATING)
			_api.call("create_session", _lesson_id)
		ApiScript.KIND_SESSION:
			if _state != STATE_CREATING:
				return
			if not ok:
				_on_api_error(kind, code, body, result)
				return
			_session_id = String(body.get("sessionId", ""))
			if _session_id.is_empty():
				_fail(ApiScript.CODE_BAD_RESPONSE)
				return
			_apply_quota(ApiScript.quota_of(body), String(body.get("entitlement", "")))
			if _requested_mode == MODE_TURNS:
				_enter_turns_mode("requested")
				return
			_set_state(STATE_MINTING)
			_api.call("mint_token", _session_id)
		ApiScript.KIND_TOKEN:
			if _state != STATE_MINTING:
				return
			if not ok:
				_on_api_error(kind, code, body, result)
				return
			_set_state(STATE_CONNECTING)
			if not bool(_transport.connect_session(body)):
				_on_transport_trouble(String(_transport.call("last_error")))
		ApiScript.KIND_TURN:
			_on_turn_completed(result)
		ApiScript.KIND_END:
			_finish_end(result)
		_:
			pass


func _on_api_error(kind: String, code: String, body: Dictionary, result: Dictionary) -> void:
	var status: int = int(result.get("status", 0))
	match code:
		ApiScript.CODE_QUOTA_EXHAUSTED:
			_on_quota_exhausted(body)
		ApiScript.CODE_NOT_APPROVED, ApiScript.CODE_CONSENT_REQUIRED:
			_fail(REASON_NOT_APPROVED)
		ApiScript.CODE_SESSION_ENDED, ApiScript.CODE_NOT_FOUND:
			_fail(REASON_SESSION_ENDED)
		ApiScript.CODE_RATE_LIMITED:
			if _rate_limit_retries < MAX_RATE_LIMIT_RETRIES:
				_rate_limit_retries += 1
				var wait: float = float(result.get("retryAfterSeconds", 0.0))
				_schedule_retry(_state, wait if wait > 0.0 else RATE_LIMIT_DEFAULT_RETRY_SECONDS)
			else:
				_fail(code)
		ApiScript.CODE_CLOUD_DISABLED, ApiScript.CODE_NOT_CONFIGURED:
			_fail(code)
		_:
			if kind == ApiScript.KIND_TOKEN and _state == STATE_MINTING:
				# No realtime on this server (503 provider_unavailable on the
				# deployed Worker, a timeout, a 5xx): the session is up, the
				# turns path carries the lesson.
				_enter_turns_mode(code)
				return
			if _is_transient(code, status):
				_on_transport_trouble(code)
			else:
				# bad_request, unknown_lesson, invalid_turn, conflict, http_4xx: a
				# client/server disagreement; the scripted tutor takes over.
				_fail(code)


static func _is_transient(code: String, status: int) -> bool:
	return code in TRANSIENT_CODES or status == 0 or status >= 500 or code.begins_with("http_5")


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
	_transport_mode = ""
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
		STATE_SIGNING_IN:
			_api.call("sign_in_dev", "")
		STATE_CONSENTING:
			_api.call("grant_consent", ApiScript.CONSENT_AI_TUTOR)
		STATE_QUOTA:
			_api.call("fetch_quota")
		STATE_CREATING:
			_api.call("create_session", _lesson_id)
		STATE_MINTING:
			_set_state(STATE_MINTING)
			_api.call("mint_token", _session_id)
		RETRY_TURN:
			if _state == STATE_READY and not _turn_request.is_empty():
				_api.call("submit_turn", _session_id, String(_turn_request["key"]), String(_turn_request["text"]), _turn_request["context"], 0.0)
		_:
			pass


## The token endpoint said no realtime: the session carries on over REST turns.
func _enter_turns_mode(reason: String) -> void:
	_transport_mode = MODE_TURNS
	_close_transport()
	_turn_failures = 0
	_idle_seconds = 0.0
	_set_state(STATE_READY)
	ready.emit({"sessionId": _session_id, "entitlement": _entitlement, "quota": server_quota(),
		"transport": MODE_TURNS, "reconnects": _reconnects, "realtimeFallback": reason})


func _on_quota_exhausted(body: Dictionary) -> void:
	var block: Dictionary = ApiScript.quota_of(body)
	if not block.is_empty():
		_apply_quota(block, _entitlement)
	_tell_mirror_exhausted()
	if _state in [STATE_SIGNING_IN, STATE_CONSENTING, STATE_QUOTA, STATE_CREATING, STATE_MINTING, STATE_CONNECTING]:
		_fail(ApiScript.CODE_QUOTA_EXHAUSTED)
		return
	_arm_boundary(REASON_QUOTA)
	if not _reply_open and not _is_responding():
		end(REASON_QUOTA)


func _tell_mirror_exhausted() -> void:
	var mirror: Object = _quota_now()
	if mirror != null and mirror.has_method("apply_server_failure"):
		var failure: Dictionary = {"ok": false, "state": "exhausted", "code": ApiScript.CODE_QUOTA_EXHAUSTED}
		if not _server_quota.is_empty():
			failure["quota"] = _server_quota_for_mirror()
		mirror.call("apply_server_failure", failure)


func _arm_boundary(reason: String) -> void:
	if _end_at_boundary:
		return
	_end_at_boundary = true
	_boundary_reason = reason


## `end_at_boundary`: the server said this reply used the last of the day
## (a turn's `endAtBoundary`); the mirror is told so the classroom closes.
func _apply_quota(raw: Variant, entitlement_name: String, end_at_boundary: bool = false) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var block: Dictionary = raw
	if block.has("quota") and typeof(block["quota"]) == TYPE_DICTIONARY:
		block = block["quota"]
	var allowance: float = _number(block.get("dailyAllowanceSeconds", block.get("allowanceSeconds", 0.0)))
	var used: float = _number(block.get("usedSeconds", 0.0))
	var known: bool = block.has("allowanceSeconds") or block.has("dailyAllowanceSeconds")
	if not known:
		return  # a reply without a quota block tells us nothing
	var remaining: float = maxf(allowance - used, 0.0)
	if block.has("remainingSeconds"):
		remaining = minf(remaining, _number(block["remainingSeconds"]))
	_server_quota = {
		"allowanceSeconds": allowance, "usedSeconds": used, "remainingSeconds": remaining,
		"resetAtUtc": String(block.get("resetAtUtc", "")),
		"entitlement": entitlement_name if not entitlement_name.is_empty() else String(block.get("entitlement", "free")),
		"dailyTurnAllowance": int(_number(block.get("dailyTurnAllowance", 0))),
		"usedTurns": int(_number(block.get("usedTurns", 0))),
		"known": true,
	}
	if not entitlement_name.is_empty():
		_entitlement = entitlement_name
	var mirror: Object = _quota_now()
	if mirror != null and mirror.has_method("apply_server_quota"):
		mirror.call("apply_server_quota", _server_quota_for_mirror(), end_at_boundary)
	if end_at_boundary or remaining <= 0.0:
		_tell_mirror_exhausted()
	quota_updated.emit(server_quota())


## `TutorQuota` reads `dailyAllowanceSeconds`; kept under its own key names.
func _server_quota_for_mirror() -> Dictionary:
	return {
		"entitlement": String(_server_quota.get("entitlement", "free")),
		"dailyAllowanceSeconds": float(_server_quota.get("allowanceSeconds", 0.0)),
		"usedSeconds": float(_server_quota.get("usedSeconds", 0.0)),
		"remainingSeconds": float(_server_quota.get("remainingSeconds", 0.0)),
		"resetAtUtc": String(_server_quota.get("resetAtUtc", "")),
	}


# -- turns path --------------------------------------------------------------------------------

func _on_turn_completed(result: Dictionary) -> void:
	if _turn_request.is_empty() or _state != STATE_READY:
		return  # cancelled, superseded or ended while in flight
	var ok: bool = bool(result.get("ok", false))
	var code: String = String(result.get("code", ""))
	var body: Dictionary = result.get("body", {})
	var status: int = int(result.get("status", 0))
	if ok:
		var key: String = String(_turn_request.get("key", ""))
		_turn_request = {}
		_turn_failures = 0
		_on_turn_reply(body, bool(result.get("replayed", false)), key)
		return
	match code:
		ApiScript.CODE_RATE_LIMITED:
			if int(_turn_request["retries"]) < MAX_TURN_RETRIES:
				_turn_request["retries"] = int(_turn_request["retries"]) + 1
				var wait: float = float(result.get("retryAfterSeconds", 0.0))
				_schedule_retry(RETRY_TURN, wait if wait > 0.0 else RATE_LIMIT_DEFAULT_RETRY_SECONDS)
			else:
				_turn_lost(code)
		ApiScript.CODE_QUOTA_EXHAUSTED:
			_turn_lost(code)
			_on_quota_exhausted(body)
		ApiScript.CODE_NOT_APPROVED, ApiScript.CODE_CONSENT_REQUIRED:
			_turn_lost(code)
			_fail(REASON_NOT_APPROVED)
		ApiScript.CODE_SESSION_ENDED, ApiScript.CODE_NOT_FOUND:
			_turn_lost(code)
			_fail(REASON_SESSION_ENDED)
		_:
			if _is_transient(code, status):
				if int(_turn_request["retries"]) < MAX_TURN_RETRIES:
					# Same Idempotency-Key: a served-but-lost reply is replayed, not charged again.
					_turn_request["retries"] = int(_turn_request["retries"]) + 1
					_schedule_retry(RETRY_TURN, RETRY_DELAY_SECONDS)
					return
				_turn_lost(code)
				_turn_failures += 1
				if _turn_failures >= MAX_TURN_FAILURES:
					_fail(code)
			else:
				# invalid_turn, bad_request, idempotency_mismatch, unknown_lesson: a
				# client bug; the scripted line answers, the session stays.
				push_warning("cloud tutor: turn refused by the server (%s)" % code)
				_turn_lost(code)


## The request is gone; the provider answers with the scripted turn.
func _turn_lost(code: String) -> void:
	_turn_request = {}
	_close_reply()
	turn_failed.emit(code)


func _drop_turn_request() -> void:
	if _turn_request.is_empty():
		return
	_turn_request = {}
	if _retry_action == RETRY_TURN:
		_retry_action = ""
		_retry_left = -1.0
	if _api != null:
		_api.call("cancel")


func _on_turn_reply(body: Dictionary, replayed: bool, key: String = "") -> void:
	var block: Dictionary = ApiScript.quota_of(body)
	var at_boundary: bool = bool(body.get("endAtBoundary", false))
	_apply_quota(block, _entitlement, at_boundary)
	var turn: Dictionary = TurnValidator.coerce(body.get("turn", {}))
	_reply_done = true
	_reply_had_audio = false
	_reply_turn = turn
	_streamed_text = String(turn.get("speech", ""))
	_idle_seconds = 0.0
	_turn_log.append({
		"key": key,
		"turnIndex": int(_number(body.get("turnIndex", 0))), "chargedSeconds": _number(body.get("chargedSeconds", 0.0)),
		"replayed": replayed, "endAtBoundary": at_boundary, "provider": String(body.get("provider", "")),
		"fallback": String(body.get("fallback", "")) if body.get("fallback", null) != null else "",
		"usedSeconds": float(_server_quota.get("usedSeconds", 0.0)), "usedTurns": int(_server_quota.get("usedTurns", 0)),
	})
	subtitle_changed.emit(String(turn.get("subtitle", turn.get("speech", ""))))
	var visual: Dictionary = turn.get("visual", {})
	if String(visual.get("type", "none")) == "flashcard" and not String(visual.get("assetId", "")).is_empty():
		tool_applied.emit("show_card", {"assetId": String(visual["assetId"])})
	if at_boundary:
		_arm_boundary(REASON_QUOTA)
	turn_ready.emit(turn.duplicate(true))
	_close_reply()


# -- transport events --------------------------------------------------------------------------

func _on_connected(info: Dictionary) -> void:
	if _state != STATE_CONNECTING:
		return
	_idle_seconds = 0.0
	_transport_mode = MODE_REALTIME
	_set_state(STATE_READY)
	if _transport.has_method("set_played_ms_source") and _player != null:
		_transport.call("set_played_ms_source", Callable(_player, "played_ms"))
	ready.emit({"sessionId": _session_id, "entitlement": _entitlement, "quota": server_quota(),
		"transport": String(info.get("transport", MODE_REALTIME)), "reconnects": _reconnects})


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
	if _state == STATE_ENDING or _state == STATE_ENDED or _closing_transport or _transport_mode == MODE_TURNS:
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
	if _state == STATE_ENDING or _state == STATE_ENDED or _closing_transport or _transport_mode == MODE_TURNS:
		return
	_on_transport_trouble(reason)


func _close_transport() -> void:
	if _transport == null:
		return
	_closing_transport = true
	_transport.close()
	_closing_transport = false


# -- reply bookkeeping -------------------------------------------------------------------------------

func _is_responding() -> bool:
	if _transport_mode == MODE_TURNS:
		return not _turn_request.is_empty()
	return _transport != null and _transport.is_responding()


## A reply the SERVER started (server VAD on streamed audio): played and
## lip-synced like any other, but no `send_transcript()` asked for it, so the
## conversation provider has nothing pending and the lesson loop is untouched.
func _open_server_reply() -> bool:
	if _state != STATE_READY or _transport_mode != MODE_REALTIME or _transport == null or not _transport.is_responding():
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
	if _state == STATE_READY and _end_at_boundary and not _reply_open and not _is_responding():
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
	_drop_turn_request()
	_close_reply()
	_close_transport()
	fell_back.emit(reason)
	_end_reason = "%s:%s" % [REASON_PROVIDER_FAILED, reason]
	_post_end()


## `/end` leaves exactly once per session, with `{reason}` only.
func _post_end() -> void:
	if _session_id.is_empty() or _api == null or not bool(_api.call("is_available")) or _end_posted:
		_finish_end({"ok": false, "code": "no_session", "body": {}})
		return
	_end_posted = true
	_api.call("end_session", _session_id, _end_reason)


func _finish_end(result: Dictionary) -> void:
	if _state == STATE_ENDED:
		return
	_last_summary = {
		"reason": _end_reason, "secondsUsed": snappedf(_active_seconds, 0.1), "usage": usage(),
		"serverAck": bool(result.get("ok", false)), "code": String(result.get("code", "")),
		"quota": server_quota(), "reconnects": _reconnects, "sessionId": _session_id,
		"transport": _transport_mode, "turns": _turn_log.size(),
	}
	var body: Dictionary = result.get("body", {})
	if typeof(body.get("quota", null)) == TYPE_DICTIONARY:
		_apply_quota(body["quota"], _entitlement)
		_last_summary["quota"] = server_quota()
	if typeof(body.get("usage", null)) == TYPE_DICTIONARY:
		_last_summary["serverUsage"] = (body["usage"] as Dictionary).duplicate(true)
	if body.has("endedAt"):
		_last_summary["endedAt"] = String(body["endedAt"])
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
