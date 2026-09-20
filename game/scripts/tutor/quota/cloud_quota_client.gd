extends Node
## A THIN client over the Aliz Tutor backend's session / turn / end /
## entitlement endpoints (docs/ALIZ_TUTOR_API.md), used only while
## `TutorFlags.cloud_enabled()` is true. The server is the authority: every
## reply's `quota` block is handed to `TutorQuota.apply_server_quota()` as truth,
## and nothing here ever claims a purchase succeeded or counts minutes itself.
##
## Never a hang: every request carries a timeout (`quota_config.json`
## `cloudTimeoutSeconds`, default 10 s, the server's own whole-request budget);
## a timeout, a refused connection, a non-JSON body or a 5xx all end as
## `request_failed(..., state = "provider_unavailable")`, and `TutorQuota`
## answers that by dropping to the local scripted tutor for the rest of the
## lesson. One request in flight at a time; a second call while busy fails
## immediately with `client_error` rather than queueing behind a slow network.
##
## Holds no provider secret. The parent-approval token is minted by the server
## after the game's parental gate and is the only credential sent.
##
## A Node (HTTPRequest needs the tree). `TutorQuota` parks one under the tree
## root on demand; tests drive `_finish()` directly with recorded fixtures.

const BackendResponse := preload("res://scripts/tutor/quota/backend_response.gd")
const QuotaConfig := preload("res://scripts/tutor/quota/quota_config.gd")

## Every reply, parsed by `BackendResponse.parse()`; `kind` is the endpoint.
signal response_received(kind: String, parsed: Dictionary)
## Any failure, already mapped to a state the scene knows.
signal request_failed(kind: String, parsed: Dictionary)
## Shortcut: every reply that carried a server `quota` block.
signal quota_updated(quota: Dictionary, end_at_boundary: bool)

const KIND_SESSION: String = "session"
const KIND_TURN: String = "turn"
const KIND_END: String = "end"
const KIND_ENTITLEMENT: String = "entitlement"

const SESSIONS_PATH: String = "/api/v1/tutor/sessions"
const ENTITLEMENT_PATH: String = "/api/v1/tutor/entitlement"

var _base_url: String = ""
var _client_id: String = ""
var _approval_token: String = ""
var _session_id: String = ""
var _request: HTTPRequest = null
var _in_flight: String = ""
var _turn_counter: int = 0
var _timeout_seconds: float = float(QuotaConfig.DEFAULT_CLOUD_TIMEOUT_SECONDS)


func _ready() -> void:
	_ensure_request_node()


## `base_url` from `TutorFlags.backend_url()`; `client_id` a per-install id;
## `approval_token` from the server after the parental gate (never invented here).
func configure(base_url: String, client_id: String, approval_token: String = "") -> void:
	_base_url = base_url.strip_edges().trim_suffix("/")
	_client_id = client_id.strip_edges()
	_approval_token = approval_token.strip_edges()
	_timeout_seconds = float(QuotaConfig.cloud_timeout_seconds())


func set_timeout_seconds(seconds: float) -> void:
	_timeout_seconds = clampf(seconds, 1.0, 30.0)


func session_id() -> String:
	return _session_id


func is_busy() -> bool:
	return not _in_flight.is_empty()


## POST /sessions. Reply: `response_received("session", {sessionId, quota, ...})`.
func begin_session(lesson_id: String) -> bool:
	return _send(KIND_SESSION, HTTPClient.METHOD_POST, SESSIONS_PATH, {
		"lessonId": lesson_id,
		"clientId": _client_id,
		"parentApprovalToken": _approval_token,
	})


## POST /sessions/{id}/turns with an Idempotency-Key, so a retry after a dropped
## reply replays the same turn and is not charged twice.
func submit_turn(transcript: String, lesson_context: Dictionary, audio_seconds: float = 0.0) -> bool:
	if _session_id.is_empty():
		_fail_now(KIND_TURN, BackendResponse.STATE_SESSION_LOST, "no_session", "No session is open.")
		return false
	_turn_counter += 1
	var body: Dictionary = {
		"transcript": transcript.left(500),
		"lessonContext": lesson_context,
	}
	if audio_seconds > 0.0:
		body["audioSeconds"] = minf(audio_seconds, 30.0)
	var key: String = "%s-%d" % [_session_id, _turn_counter]
	return _send(KIND_TURN, HTTPClient.METHOD_POST, "%s/%s/turns" % [SESSIONS_PATH, _session_id],
			body, ["Idempotency-Key: %s" % key])


## POST /sessions/{id}/end. Idempotent server side; safe to call twice.
func end_session(reason: String = "") -> bool:
	if _session_id.is_empty():
		return false
	var body: Dictionary = {}
	if not reason.is_empty():
		body["reason"] = reason
	return _send(KIND_END, HTTPClient.METHOD_POST, "%s/%s/end" % [SESSIONS_PATH, _session_id], body)


## GET /entitlement?clientId=...
func fetch_entitlement() -> bool:
	return _send(KIND_ENTITLEMENT, HTTPClient.METHOD_GET,
			"%s?clientId=%s" % [ENTITLEMENT_PATH, _client_id.uri_encode()], {})


## Drops the in-flight request (a scene leaving). No signal is emitted.
func cancel() -> void:
	if _request != null and not _in_flight.is_empty():
		_request.cancel_request()
	_in_flight = ""


## Forgets the session id (after `end` or a `session_lost` reply).
func forget_session() -> void:
	_session_id = ""
	_turn_counter = 0


# -- transport ------------------------------------------------------------------

func _ensure_request_node() -> void:
	if _request != null:
		return
	_request = HTTPRequest.new()
	_request.name = "Request"
	_request.use_threads = false
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)


func _send(kind: String, method: int, path: String, body: Dictionary, extra_headers: Array = []) -> bool:
	if _base_url.is_empty():
		_fail_now(kind, BackendResponse.STATE_PROVIDER_UNAVAILABLE, "not_configured",
				"The cloud tutor has no address.")
		return false
	if not _in_flight.is_empty():
		_fail_now(kind, BackendResponse.STATE_CLIENT_ERROR, "busy",
				"A request is already in flight.")
		return false
	if not is_inside_tree():
		_fail_now(kind, BackendResponse.STATE_PROVIDER_UNAVAILABLE, "not_in_tree",
				"The cloud client is not in the scene tree.")
		return false
	_ensure_request_node()
	_request.timeout = _timeout_seconds
	var headers: PackedStringArray = PackedStringArray(["content-type: application/json", "accept: application/json"])
	for header: Variant in extra_headers:
		headers.append(String(header))
	var payload: String = "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	_in_flight = kind
	var error: int = _request.request(_base_url + path, headers, method, payload)
	if error != OK:
		_in_flight = ""
		_fail_now(kind, BackendResponse.STATE_PROVIDER_UNAVAILABLE, "request_error_%d" % error,
				"The request could not be started.")
		return false
	return true


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind: String = _in_flight
	_in_flight = ""
	if kind.is_empty():
		return
	var status: int = response_code if result == HTTPRequest.RESULT_SUCCESS else BackendResponse.NO_HTTP_STATUS
	_finish(kind, status, body.get_string_from_utf8())


## The one place a reply becomes state. Public so a test can feed a recorded
## fixture through the exact path a live reply takes.
func _finish(kind: String, http_status: int, body_text: String) -> void:
	var parsed: Dictionary = BackendResponse.parse(http_status, body_text)
	parsed["kind"] = kind
	if parsed.has("quota"):
		quota_updated.emit(parsed["quota"], bool(parsed.get("endAtBoundary", false)))
	if not bool(parsed.get("ok", false)):
		if String(parsed.get("state", "")) == BackendResponse.STATE_SESSION_LOST:
			forget_session()
		request_failed.emit(kind, parsed)
		return
	match kind:
		KIND_SESSION:
			_session_id = String(parsed.get("sessionId", ""))
			_turn_counter = 0
		KIND_END:
			forget_session()
	response_received.emit(kind, parsed)


func _fail_now(kind: String, state: String, code: String, message: String) -> void:
	request_failed.emit(kind, {
		"ok": false, "state": state, "code": code, "message": message, "kind": kind,
	})
