extends "res://scripts/tutor/providers/conversation_provider.gd"

## The CLOUD conversation provider -- flag-gated, never required.
##
## Talks to Agent D's backend (`docs/ALIZ_TUTOR_API.md`) over plain HTTP:
##   POST /api/v1/tutor/sessions              (parent-approval token, lessonId, clientId)
##   POST /api/v1/tutor/sessions/{id}/turns   (Idempotency-Key = sessionId:stepId:attempt)
##   POST /api/v1/tutor/sessions/{id}/end
##
## ## What never happens here
##
##   * Nothing is sent while `TutorFlags.cloud_enabled()` is false. `begin_session`
##     fails with `cloud_disabled` before a socket is opened; `submit_turn` answers
##     with the SCRIPTED turn. The only other way in is `enable_for_tests()`,
##     which is refused on a mobile or release build and even then only allows
##     a loopback URL -- the headless suite talks to a local DEV_MODE server.
##   * No audio, ever. The request carries the transcript TEXT and the lesson
##     context (`ConversationProvider.lesson_context_for`): step id, outcome,
##     expected answers, hint, next question, asset id. No profile, no name,
##     no device identifiers; `clientId` is a random per-process id unless the
##     scene sets one.
##   * No provider secret: the server holds the key.
##   * No hang. Every request has `TIMEOUT_SECONDS` (8 s); a turn request that
##     fails for ANY reason -- HTTP error, timeout, unreachable host, invalid
##     turn, no session -- is answered with the scripted provider's turn for the
##     SAME verdict (`fallback_used(reason)` then `turn_ready(turn)`), so the
##     scene always gets exactly one `turn_ready` per `submit_turn` and the
##     child never waits on a spinner. Error codes are surfaced as the reason:
##     quota_exhausted, not_approved, provider_unavailable, rate_limited,
##     timeout, session_ended, not_found, invalid_turn, ... (`REASON_*`).
##   * Every turn the server returns goes through `tutor_turn.gd` before it is
##     emitted; an invalid one is replaced (reason `invalid_turn`).
##
## ## Which turns go to the cloud
##
## Only `PHASE_ANSWER` and `PHASE_TIMEOUT` on a scored step (there IS an
## outcome to discuss). `PHASE_OPEN`, `PHASE_TOGETHER`, `PHASE_INTERJECTION`
## and choose-step routing are built locally by the embedded scripted provider
## -- no quota spent on reading a question or honouring a topic change.
## The LessonEngine judges the answer ONCE, here, and both the request and the
## fallback turn are built from that one verdict.
##
## ## Driving it
##
## The HTTP client is polled from `advance(delta)`. While a request is in
## flight the provider hooks `SceneTree.process_frame` itself, so the scene
## does not need to pump it; a headless test calls `advance()` directly.

signal fallback_used(reason: String)
signal turn_meta(meta: Dictionary)
signal session_ended(summary: Dictionary)

const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const ScriptedProviderScript := preload("res://scripts/tutor/providers/scripted_conversation_provider.gd")

const SESSIONS_PATH: String = "/api/v1/tutor/sessions"
const TIMEOUT_SECONDS: float = 8.0
const MAX_TRANSCRIPT_CHARS: int = 500
const DEV_PARENT_APPROVAL_TOKEN: String = "dev-parent-approval"

const REASON_CLOUD_DISABLED: String = "cloud_disabled"
const REASON_NO_SESSION: String = "no_session"
const REASON_NO_ENGINE: String = "no_lesson_engine"
const REASON_NOT_APPROVED: String = "not_approved"
const REASON_QUOTA: String = "quota_exhausted"
const REASON_UNAVAILABLE: String = "provider_unavailable"
const REASON_RATE_LIMITED: String = "rate_limited"
const REASON_TIMEOUT: String = "timeout"
const REASON_INVALID_TURN: String = "invalid_turn"
const REASON_SESSION_ENDED: String = "session_ended"
const REASON_NOT_FOUND: String = "not_found"
const REASON_BAD_RESPONSE: String = "bad_response"
const REASON_CANCELLED: String = "cancelled"

const KIND_SESSION: String = "session"
const KIND_TURN: String = "turn"
const KIND_END: String = "end"


## THE gate. Read before any network primitive appears in this file (the
## privacy guard proves the source order): nothing below constructs a client
## unless this, or the loopback-only test override, says yes.
static func flag_enabled() -> bool:
	return TutorFlags.cloud_enabled()


var _scripted: RefCounted = ScriptedProviderScript.new()
var _base_url: String = ""
var _token: String = ""
var _client_id: String = ""
var _dev_override: bool = false
var _timeout_seconds: float = TIMEOUT_SECONDS
var _session: Dictionary = {}
var _last_session: Dictionary = {}

var _http = null  # HTTPClient, constructed only inside the guarded branch
var _request: Dictionary = {}
var _queue: Array[Dictionary] = []
var _frame_hooked: bool = false
var _request_serial: int = 0
## Diagnostics for tests and the dev panel: what left, what came back.
var _log: Array[Dictionary] = []


func provider_name() -> String:
	return "backend"


func is_available() -> bool:
	return _cloud_allowed()


func set_engine(engine: Object) -> void:
	super.set_engine(engine)
	_scripted.set_engine(engine)
	if not _scripted.lesson_routed.is_connected(_on_scripted_routed):
		_scripted.lesson_routed.connect(_on_scripted_routed)


func _on_scripted_routed(action: String, target_id: String) -> void:
	lesson_routed.emit(action, target_id)


## The parent-approval token from the parental gate flow. For a DEV_MODE server
## `use_dev_token()` sets the literal the server accepts; production mints one
## via the consent endpoint (follow-up).
func set_parent_approval_token(token: String) -> void:
	_token = token.strip_edges()


func use_dev_token() -> void:
	_token = DEV_PARENT_APPROVAL_TOKEN


## A stable, pseudonymous per-install id for quota. Never a name or a device
## serial: the scene/quota layer decides what to persist.
func set_client_id(client_id: String) -> void:
	_client_id = client_id.strip_edges()


func client_id() -> String:
	if _client_id.is_empty():
		_client_id = "ld-%08x%08x" % [randi(), randi()]
	return _client_id


## Overrides `TutorFlags.backend_url()` (a test's spawned server on a free port).
func set_base_url(url: String) -> void:
	_base_url = url.strip_edges().trim_suffix("/")


func base_url() -> String:
	return _base_url if not _base_url.is_empty() else TutorFlags.backend_url()


func set_timeout_seconds(seconds: float) -> void:
	_timeout_seconds = maxf(seconds, 0.05)


## Arms the provider WITHOUT the project flag, for the headless suite and the
## dev sim panel only. Refused -- returns false, nothing changes -- on a mobile
## or release-template build, mirroring `SpeechService`'s mock guard; and a
## provider armed this way only ever talks to a loopback address.
func enable_for_tests(enabled: bool = true) -> bool:
	if enabled and (OS.has_feature("mobile") or OS.has_feature("template_release")):
		_dev_override = false
		return false
	_dev_override = enabled
	return _dev_override


func session() -> Dictionary:
	return _session.duplicate(true)


func request_log() -> Array:
	return _log.duplicate(true)


func has_request_in_flight() -> bool:
	return not _request.is_empty() or not _queue.is_empty()


# ---------------------------------------------------------------------------
# ConversationProvider
# ---------------------------------------------------------------------------

func begin_session(lesson_id_value: String) -> void:
	_lesson_id = lesson_id_value
	_scripted.begin_session(lesson_id_value)
	if not _cloud_allowed():
		provider_failed.emit(REASON_CLOUD_DISABLED)
		return
	if not has_engine():
		provider_failed.emit(REASON_NO_ENGINE)
		return
	if _token.is_empty():
		provider_failed.emit(REASON_NOT_APPROVED)
		return
	_session = {}
	_active = true
	var body: Dictionary = {"lessonId": lesson_id_value, "parentApprovalToken": _token, "clientId": client_id()}
	_enqueue(KIND_SESSION, HTTPClient.METHOD_POST, SESSIONS_PATH, [], body, {})


func submit_turn(transcript: String, lesson_context: Dictionary) -> void:
	var phase: String = String(lesson_context.get("phase", PHASE_ANSWER))
	if not has_engine():
		provider_failed.emit(REASON_NO_ENGINE)
		return
	var step: Dictionary = _engine.call("current_step")
	if phase != PHASE_ANSWER and phase != PHASE_TIMEOUT or step.is_empty() or bool(_engine.call("is_complete")) \
			or String(step.get("kind", "")) == "choose":
		# Lesson data, routing and barge-in are local: no quota spent on
		# reading a question or honouring "I want a dog!".
		turn_ready.emit(TurnValidator.coerce(_scripted.build_turn(transcript, phase)))
		return
	var said: String = "" if phase == PHASE_TIMEOUT else transcript.strip_edges().left(MAX_TRANSCRIPT_CHARS)
	var verdict: Dictionary = _engine.call("evaluate", said)
	var local_turn: Dictionary = TurnValidator.coerce(_scripted.turn_for_verdict(step, verdict, phase))
	if not _cloud_allowed():
		_fallback(REASON_CLOUD_DISABLED, local_turn)
		return
	if not _active or _session.is_empty():
		if _active and _has_pending(KIND_SESSION):
			# The session request is still on the wire: queue behind it.
			pass
		else:
			_fallback(REASON_NO_SESSION, local_turn)
			return
	var context: Dictionary = lesson_context_for(step, verdict, _peek_next_step())
	var key: String = "%s:%s:%d" % ["pending", String(step.get("stepId", "")), int(verdict.get("attempt", 0))]
	_enqueue(KIND_TURN, HTTPClient.METHOD_POST, "", ["Idempotency-Key: %s" % key],
		{"transcript": said, "lessonContext": context}, {"localTurn": local_turn, "stepId": String(step.get("stepId", "")),
			"attempt": int(verdict.get("attempt", 0))})


func end_session() -> void:
	var had_session: bool = not _session.is_empty()
	var session_id: String = String(_session.get("sessionId", ""))
	_active = false
	_scripted.end_session()
	# A queued turn has nothing to be spoken into any more; drop it (its
	# fallback turn is not emitted either: the scene asked to end).
	_queue = _queue.filter(func(entry: Dictionary) -> bool: return String(entry["kind"]) == KIND_END)
	if not _request.is_empty() and String(_request["kind"]) != KIND_END:
		_abort_request()
	if had_session and _cloud_allowed():
		_enqueue(KIND_END, HTTPClient.METHOD_POST, "%s/%s/end" % [SESSIONS_PATH, session_id], [], {"reason": "scene"}, {})
	_last_session = _session
	_session = {}


## Drops whatever is in flight. No turn follows a cancelled request.
func cancel() -> void:
	_queue.clear()
	if not _request.is_empty():
		_abort_request()
	_unhook_frame()


# ---------------------------------------------------------------------------
# HTTP pump
# ---------------------------------------------------------------------------

## Polls the HTTP client; `delta` seconds count against the request timeout.
## `_process`-driven through `SceneTree.process_frame` while busy; a test
## calls it directly.
func advance(delta: float) -> void:
	if _request.is_empty():
		if _queue.is_empty():
			_unhook_frame()
			return
		_start_next()
		if _request.is_empty():
			return
	_request["elapsed"] = float(_request["elapsed"]) + maxf(delta, 0.0)
	if float(_request["elapsed"]) >= _timeout_seconds:
		_finish_request(0, {}, REASON_TIMEOUT)
		return
	_http.poll()
	var status: int = _http.get_status()
	match status:
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
			return
		HTTPClient.STATUS_CONNECTED:
			if not bool(_request["sent"]):
				_send()
				return
			if _http.has_response():
				_read_response()
			elif bool(_request.get("bodyStarted", false)):
				_complete_body()
			return
		HTTPClient.STATUS_REQUESTING:
			return
		HTTPClient.STATUS_BODY:
			_request["bodyStarted"] = true
			_read_response()
			return
		HTTPClient.STATUS_DISCONNECTED:
			if bool(_request.get("bodyStarted", false)):
				_complete_body()
			else:
				_finish_request(0, {}, REASON_UNAVAILABLE)
			return
		_:
			# CANT_RESOLVE, CANT_CONNECT, CONNECTION_ERROR, TLS_HANDSHAKE_ERROR
			_finish_request(0, {}, REASON_UNAVAILABLE)


func _enqueue(kind: String, method: int, path: String, headers: Array, body: Dictionary, extra: Dictionary) -> void:
	_request_serial += 1
	var entry: Dictionary = {
		"serial": _request_serial, "kind": kind, "method": method, "path": path,
		"headers": headers, "body": body, "extra": extra, "elapsed": 0.0, "sent": false,
	}
	_queue.append(entry)
	_hook_frame()
	# Kick off immediately so a synchronous refusal (bad URL) is reported now.
	if _request.is_empty():
		_start_next()


func _start_next() -> void:
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		if String(entry["kind"]) == KIND_TURN:
			if _session.is_empty():
				_fallback(REASON_NO_SESSION, entry["extra"]["localTurn"])
				continue
			var session_id: String = String(_session.get("sessionId", ""))
			entry["path"] = "%s/%s/turns" % [SESSIONS_PATH, session_id]
			var headers: Array = []
			for header: String in entry["headers"]:
				headers.append(header.replace("Idempotency-Key: pending:", "Idempotency-Key: %s:" % session_id))
			entry["headers"] = headers
		var parts: Dictionary = parse_url(base_url())
		if parts.is_empty() or (_dev_override and not flag_enabled() and not _is_loopback(String(parts["host"]))):
			_request = entry
			_finish_request(0, {}, REASON_UNAVAILABLE)
			continue
		_http = HTTPClient.new()
		var tls: TLSOptions = TLSOptions.client() if bool(parts["tls"]) else null
		var err: int = _http.connect_to_host(String(parts["host"]), int(parts["port"]), tls)
		_request = entry
		_request["prefix"] = String(parts["prefix"])
		if err != OK:
			_finish_request(0, {}, REASON_UNAVAILABLE)
			continue
		return


func _send() -> void:
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	for header: String in _request["headers"]:
		headers.append(header)
	var body: String = JSON.stringify(_request["body"])
	_request["sent"] = true
	_log.append({"kind": _request["kind"], "path": _request["path"], "body": _request["body"], "headers": Array(headers)})
	var err: int = _http.request(int(_request["method"]), String(_request.get("prefix", "")) + String(_request["path"]), headers, body)
	if err != OK:
		_finish_request(0, {}, REASON_UNAVAILABLE)


func _read_response() -> void:
	if not _request.has("statusCode"):
		_request["statusCode"] = _http.get_response_code()
		_request["bytes"] = PackedByteArray()
	if _http.get_status() == HTTPClient.STATUS_BODY:
		_request["bodyStarted"] = true
		var chunk: PackedByteArray = _http.read_response_body_chunk()
		if chunk.size() > 0:
			# Packed arrays copy out of a Dictionary: append to a local, store it back.
			var bytes: PackedByteArray = _request["bytes"]
			bytes.append_array(chunk)
			_request["bytes"] = bytes
		return
	# STATUS_CONNECTED with has_response(): a body-less response, or the body is
	# already complete.
	_complete_body()


func _complete_body() -> void:
	var text: String = (_request.get("bytes", PackedByteArray()) as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else {}
	var body: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_finish_request(int(_request.get("statusCode", 0)), body, "")


func _finish_request(status_code: int, body: Dictionary, transport_reason: String) -> void:
	var entry: Dictionary = _request
	_request = {}
	if _http != null:
		_http.close()
		_http = null
	if entry.is_empty():
		return
	var reason: String = transport_reason
	if reason.is_empty() and (status_code < 200 or status_code >= 300):
		reason = _error_code(body, status_code)
	_log.append({"kind": entry["kind"], "status": status_code, "reason": reason, "response": body})
	match String(entry["kind"]):
		KIND_SESSION:
			if not reason.is_empty():
				_active = false
				_session = {}
				provider_failed.emit(reason)
			else:
				_session = body.duplicate(true)
				session_ready.emit({
					"sessionId": String(body.get("sessionId", "")), "provider": provider_name(),
					"lessonId": String(body.get("lessonId", _lesson_id)),
					"entitlement": String(body.get("entitlement", "")), "quota": body.get("quota", {}),
				})
		KIND_TURN:
			var local_turn: Dictionary = entry["extra"]["localTurn"]
			if not reason.is_empty():
				_fallback(reason, local_turn)
			else:
				var report: Dictionary = TurnValidator.validate(body.get("turn", null))
				var meta: Dictionary = {
					"quota": body.get("quota", {}), "endAtBoundary": bool(body.get("endAtBoundary", false)),
					"turnIndex": int(body.get("turnIndex", 0)), "provider": String(body.get("provider", "")),
					"serverFallback": body.get("fallback", null), "valid": bool(report["valid"]),
				}
				turn_meta.emit(meta)
				if bool(report["valid"]):
					turn_ready.emit(report["turn"])
				else:
					_fallback(REASON_INVALID_TURN, local_turn)
		KIND_END:
			session_ended.emit({"reason": reason, "usage": body.get("usage", {}), "quota": body.get("quota", {})})
	if _queue.is_empty():
		_unhook_frame()


func _abort_request() -> void:
	var entry: Dictionary = _request
	_request = {}
	if _http != null:
		_http.close()
		_http = null
	_log.append({"kind": entry.get("kind", ""), "status": 0, "reason": REASON_CANCELLED})


func _fallback(reason: String, local_turn: Dictionary) -> void:
	fallback_used.emit(reason)
	turn_ready.emit(TurnValidator.coerce(local_turn))


static func _error_code(body: Dictionary, status_code: int) -> String:
	var error: Variant = body.get("error", null)
	if typeof(error) == TYPE_DICTIONARY:
		var code: String = String((error as Dictionary).get("code", ""))
		if not code.is_empty():
			return code
	match status_code:
		403: return REASON_NOT_APPROVED
		404: return REASON_NOT_FOUND
		409: return REASON_SESSION_ENDED
		429: return REASON_RATE_LIMITED
		503: return REASON_UNAVAILABLE
		504: return REASON_TIMEOUT
	return "http_%d" % status_code


func _has_pending(kind: String) -> bool:
	if not _request.is_empty() and String(_request["kind"]) == kind:
		return true
	for entry: Dictionary in _queue:
		if String(entry["kind"]) == kind:
			return true
	return false


func _peek_next_step() -> Dictionary:
	if _engine == null or not _engine.has_method("lesson") or not _engine.has_method("step_index"):
		return {}
	var lesson: Dictionary = _engine.call("lesson")
	var steps: Variant = lesson.get("steps", [])
	var index: int = int(_engine.call("step_index")) + 1
	if typeof(steps) != TYPE_ARRAY or index < 0 or index >= (steps as Array).size():
		return {}
	var raw: Variant = (steps as Array)[index]
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func _cloud_allowed() -> bool:
	return flag_enabled() or _dev_override


static func _is_loopback(host: String) -> bool:
	return host == "127.0.0.1" or host == "localhost" or host == "::1" or host == "[::1]"


## `{host, port, tls, prefix}` for `scheme://host[:port][/prefix]` (http or https); empty when
## the URL is not one of those.
static func parse_url(url: String) -> Dictionary:
	var trimmed: String = url.strip_edges()
	var scheme_end: int = trimmed.find("://")
	if scheme_end <= 0:
		return {}
	var scheme: String = trimmed.left(scheme_end).to_lower()
	if scheme != "http" and scheme != "https":
		return {}
	var tls: bool = scheme == "https"
	var rest: String = trimmed.substr(scheme_end + 3)
	var slash: int = rest.find("/")
	var authority: String = rest if slash < 0 else rest.left(slash)
	var prefix: String = "" if slash < 0 else rest.substr(slash).trim_suffix("/")
	var host: String = authority
	var port: int = 443 if tls else 80
	var colon: int = authority.rfind(":")
	if colon > 0 and authority.find("]") < colon:
		host = authority.left(colon)
		port = int(authority.substr(colon + 1))
	if host.is_empty() or port <= 0:
		return {}
	return {"host": host, "port": port, "tls": tls, "prefix": prefix}


func _hook_frame() -> void:
	if _frame_hooked:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.process_frame.connect(_on_frame)
	_frame_hooked = true


func _unhook_frame() -> void:
	if not _frame_hooked:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_on_frame):
		tree.process_frame.disconnect(_on_frame)
	_frame_hooked = false


func _on_frame() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var delta: float = tree.root.get_process_delta_time() if tree != null and tree.root != null else 1.0 / 60.0
	advance(delta)
