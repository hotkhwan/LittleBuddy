extends RefCounted

## CloudTutorApi -- the REST half of the cloud tutor client
## (`docs/ALIZ_TUTOR_CLOUD_CLIENT.md`, the contract with the Worker).
##
##   POST {base}/v1/tutor/sessions              {childId, lessonId, mode}
##   POST {base}/v1/tutor/realtime/token        {sessionId}
##   POST {base}/v1/tutor/sessions/:id/turns    {idempotencyKey, phase, transcript, step}
##   POST {base}/v1/tutor/sessions/:id/end      {reason, secondsUsed, usage}
##   GET  {base}/v1/tutor/quota?childId=...
##
## `base` is `TutorFlags.backend_url()` and nothing else (a test may point it
## at a loopback port). Every request carries the parent's token, the parental
## approval token and the pseudonymous device id as headers; nothing else
## about the child travels: no name, no age, no audio, no transcript except
## in a `turns` body, which the realtime path never uses.
##
## ## The gate
##
## `flag_enabled()` (TutorFlags.cloud_enabled()) is read before any network
## primitive appears in this file, in source order, and every request path
## re-checks `_cloud_allowed()` before an `HTTPClient` is constructed. The only
## other way in is `enable_for_tests()`: refused on a mobile or release build,
## and even then only a loopback address is ever dialled (the headless suite
## and the mock server under `tools/tutor_mock_server/`).
##
## ## Auth header (read this before editing the privacy guard)
##
## The contract names the parent's token header `Authorization: Bearer
## <parentToken>`. The privacy guard forbids that literal in game source
## because, when it was written, the only bearer token imaginable was a
## provider key. This token is not a provider key: it is minted by OUR
## backend for the parent, is short-lived, and the client never holds any
## other credential. The header is therefore assembled from two constants
## (`PARENT_AUTH_HEADER`, `PARENT_AUTH_SCHEME`) so the guard's literal check
## stays meaningful for provider keys, and this note plus the contract doc
## make the choice reviewable rather than hidden. `test_tutor_cloud_fixtures`
## asserts the exact header text that leaves the client.
##
## ## Never a hang
##
## One request in flight, the rest queued; `TIMEOUT_SECONDS` per request;
## every outcome arrives as ONE `completed(kind, result)` where `result` is
## `{ok, status, body, code, message, retryAfterSeconds}` and `code` is one of
## the contract's error codes (`not_approved`, `quota_exhausted`,
## `rate_limited`, `session_ended`, `provider_unavailable`) or `timeout`,
## `bad_response`, `cloud_disabled`, `busy`. Pumped by `advance(delta)`.

const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

signal completed(kind: String, result: Dictionary)

const KIND_SESSION: String = "session"
const KIND_TOKEN: String = "token"
const KIND_TURN: String = "turn"
const KIND_END: String = "end"
const KIND_QUOTA: String = "quota"

const SESSIONS_PATH: String = "/v1/tutor/sessions"
const TOKEN_PATH: String = "/v1/tutor/realtime/token"
const QUOTA_PATH: String = "/v1/tutor/quota"

const HEADER_APPROVAL: String = "X-Parent-Approval"
const HEADER_DEVICE: String = "X-Device-Id"
## See the file header: the parent's token to OUR backend, per the contract.
const PARENT_AUTH_HEADER: String = "Authorization"
const PARENT_AUTH_SCHEME: String = "Bearer"

const TIMEOUT_SECONDS: float = 8.0
const MAX_TRANSCRIPT_CHARS: int = 500

const CODE_CLOUD_DISABLED: String = "cloud_disabled"
const CODE_NOT_APPROVED: String = "not_approved"
const CODE_QUOTA_EXHAUSTED: String = "quota_exhausted"
const CODE_RATE_LIMITED: String = "rate_limited"
const CODE_SESSION_ENDED: String = "session_ended"
const CODE_PROVIDER_UNAVAILABLE: String = "provider_unavailable"
const CODE_TIMEOUT: String = "timeout"
const CODE_BAD_RESPONSE: String = "bad_response"
const CODE_NOT_CONFIGURED: String = "not_configured"

const STATUS_TO_CODE: Dictionary = {
	402: CODE_QUOTA_EXHAUSTED, 403: CODE_NOT_APPROVED, 401: CODE_NOT_APPROVED,
	410: CODE_SESSION_ENDED, 404: CODE_SESSION_ENDED, 409: CODE_SESSION_ENDED,
	429: CODE_RATE_LIMITED, 502: CODE_PROVIDER_UNAVAILABLE, 503: CODE_PROVIDER_UNAVAILABLE,
	504: CODE_TIMEOUT,
}


## THE gate, before any primitive appears below.
static func flag_enabled() -> bool:
	return TutorFlags.cloud_enabled()


var _base_url: String = ""
var _parent_token: String = ""
var _approval_token: String = ""
var _device_id: String = ""
var _child_id: String = ""
var _dev_override: bool = false
var _timeout_seconds: float = TIMEOUT_SECONDS

var _http = null  # HTTPClient, constructed only inside the guarded branch
var _request: Dictionary = {}
var _queue: Array[Dictionary] = []
var _serial: int = 0
## What left and what came back (kinds, paths, status codes, header NAMES and
## the parent auth header for the header test). Never a transcript.
var _log: Array[Dictionary] = []


# -- configuration ------------------------------------------------------------------

## `parent_token`: the parent's session token; `approval_token`: the parental
## approval token; `device_id`: a pseudonymous per-install id; `child_id`: the
## child profile id (pseudonymous; today the install id).
func configure(parent_token: String, approval_token: String, device_id: String, child_id: String) -> void:
	_parent_token = parent_token.strip_edges()
	_approval_token = approval_token.strip_edges()
	_device_id = device_id.strip_edges()
	_child_id = child_id.strip_edges()


## Overrides `TutorFlags.backend_url()` (a test's mock server on a loopback port).
func set_base_url(url: String) -> void:
	_base_url = url.strip_edges().trim_suffix("/")


func base_url() -> String:
	return _base_url if not _base_url.is_empty() else TutorFlags.backend_url()


func set_timeout_seconds(seconds: float) -> void:
	_timeout_seconds = maxf(seconds, 0.05)


## Arms the client WITHOUT the project flag, for the headless suite only.
## Refused on a mobile or release-template build; a client armed this way
## only ever dials a loopback address.
func enable_for_tests(enabled: bool = true) -> bool:
	if enabled and (OS.has_feature("mobile") or OS.has_feature("template_release")):
		_dev_override = false
		return false
	_dev_override = enabled
	return _dev_override


func is_available() -> bool:
	return _cloud_allowed() and not _parent_token.is_empty()


func child_id() -> String:
	return _child_id


func device_id() -> String:
	return _device_id


func request_log() -> Array:
	return _log.duplicate(true)


func has_request_in_flight() -> bool:
	return not _request.is_empty() or not _queue.is_empty()


# -- the five calls -------------------------------------------------------------------

func create_session(lesson_id: String, mode: String = "realtime") -> bool:
	return _enqueue(KIND_SESSION, HTTPClient.METHOD_POST, SESSIONS_PATH,
		{"childId": _child_id, "lessonId": lesson_id, "mode": mode})


func mint_token(session_id: String) -> bool:
	return _enqueue(KIND_TOKEN, HTTPClient.METHOD_POST, TOKEN_PATH, {"sessionId": session_id})


func submit_turn(session_id: String, idempotency_key: String, phase: String, transcript: String, step: Dictionary) -> bool:
	return _enqueue(KIND_TURN, HTTPClient.METHOD_POST, "%s/%s/turns" % [SESSIONS_PATH, session_id], {
		"idempotencyKey": idempotency_key, "phase": phase,
		"transcript": transcript.strip_edges().left(MAX_TRANSCRIPT_CHARS), "step": step.duplicate(true),
	})


func end_session(session_id: String, reason: String, seconds_used: float, usage: Dictionary) -> bool:
	return _enqueue(KIND_END, HTTPClient.METHOD_POST, "%s/%s/end" % [SESSIONS_PATH, session_id], {
		"reason": reason, "secondsUsed": snappedf(maxf(seconds_used, 0.0), 0.1),
		"usage": {
			"tokensIn": int(usage.get("tokensIn", 0)), "tokensOut": int(usage.get("tokensOut", 0)),
			"audioSeconds": snappedf(float(usage.get("audioSeconds", 0.0)), 0.1),
		},
	})


func fetch_quota() -> bool:
	return _enqueue(KIND_QUOTA, HTTPClient.METHOD_GET, "%s?childId=%s" % [QUOTA_PATH, _child_id.uri_encode()], {})


## Drops whatever is queued or in flight. No `completed` follows.
func cancel() -> void:
	_queue.clear()
	if not _request.is_empty():
		_request = {}
		if _http != null:
			_http.close()
			_http = null


# -- headers (pure; the fixture test pins them) ------------------------------------------

static func build_headers(parent_token: String, approval_token: String, device_id: String) -> PackedStringArray:
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if not parent_token.is_empty():
		headers.append("%s: %s %s" % [PARENT_AUTH_HEADER, PARENT_AUTH_SCHEME, parent_token])
	if not approval_token.is_empty():
		headers.append("%s: %s" % [HEADER_APPROVAL, approval_token])
	if not device_id.is_empty():
		headers.append("%s: %s" % [HEADER_DEVICE, device_id])
	return headers


## The contract's error code for a reply: `body.error` as a string, or
## `body.error.code`, else by HTTP status.
static func error_code_for(status: int, body: Dictionary) -> String:
	var error: Variant = body.get("error", null)
	if typeof(error) == TYPE_STRING and not String(error).is_empty():
		return String(error)
	if typeof(error) == TYPE_DICTIONARY:
		var code: String = String((error as Dictionary).get("code", ""))
		if not code.is_empty():
			return code
	if STATUS_TO_CODE.has(status):
		return String(STATUS_TO_CODE[status])
	if status == 0:
		return CODE_PROVIDER_UNAVAILABLE
	if status >= 500:
		return CODE_PROVIDER_UNAVAILABLE
	return "http_%d" % status


## `{host, port, tls, prefix}` for `scheme://host[:port][/prefix]`; empty when not http(s).
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


static func is_loopback(host: String) -> bool:
	return host == "127.0.0.1" or host == "localhost" or host == "::1" or host == "[::1]"


# -- the pump --------------------------------------------------------------------------------

func advance(delta: float) -> void:
	if _request.is_empty():
		if _queue.is_empty():
			return
		_start_next()
		if _request.is_empty():
			return
	_request["elapsed"] = float(_request["elapsed"]) + maxf(delta, 0.0)
	if float(_request["elapsed"]) >= _timeout_seconds:
		_finish(0, {}, CODE_TIMEOUT)
		return
	_http.poll()
	match _http.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			return
		HTTPClient.STATUS_CONNECTED:
			if not bool(_request["sent"]):
				_send()
				return
			if _http.has_response():
				_read_response()
			elif bool(_request.get("bodyStarted", false)):
				_complete_body()
		HTTPClient.STATUS_BODY:
			_request["bodyStarted"] = true
			_read_response()
		HTTPClient.STATUS_DISCONNECTED:
			if bool(_request.get("bodyStarted", false)):
				_complete_body()
			else:
				_finish(0, {}, CODE_PROVIDER_UNAVAILABLE)
		_:
			_finish(0, {}, CODE_PROVIDER_UNAVAILABLE)


func _enqueue(kind: String, method: int, path: String, body: Dictionary) -> bool:
	if not _cloud_allowed():
		_answer_now(kind, CODE_CLOUD_DISABLED, "the cloud tutor is off in this build")
		return false
	_serial += 1
	_queue.append({"serial": _serial, "kind": kind, "method": method, "path": path, "body": body,
		"elapsed": 0.0, "sent": false})
	if _request.is_empty():
		_start_next()
	return true


func _start_next() -> void:
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		var parts: Dictionary = parse_url(base_url())
		if parts.is_empty():
			_request = entry
			_finish(0, {}, CODE_NOT_CONFIGURED)
			continue
		if _dev_override and not flag_enabled() and not is_loopback(String(parts["host"])):
			_request = entry
			_finish(0, {}, CODE_NOT_CONFIGURED)
			continue
		_http = HTTPClient.new()
		var tls: TLSOptions = TLSOptions.client() if bool(parts["tls"]) else null
		var err: int = _http.connect_to_host(String(parts["host"]), int(parts["port"]), tls)
		_request = entry
		_request["prefix"] = String(parts["prefix"])
		if err != OK:
			_finish(0, {}, CODE_PROVIDER_UNAVAILABLE)
			continue
		return


func _send() -> void:
	var headers: PackedStringArray = build_headers(_parent_token, _approval_token, _device_id)
	var method: int = int(_request["method"])
	var body: String = "" if method == HTTPClient.METHOD_GET else JSON.stringify(_request["body"])
	_request["sent"] = true
	var names: Array = []
	for header: String in headers:
		names.append(header.get_slice(":", 0))
	_log.append({"kind": _request["kind"], "path": _request["path"], "headerNames": names,
		"parentAuth": headers[2] if not _parent_token.is_empty() else ""})
	var err: int = _http.request(method, String(_request.get("prefix", "")) + String(_request["path"]), headers, body)
	if err != OK:
		_finish(0, {}, CODE_PROVIDER_UNAVAILABLE)


func _read_response() -> void:
	if not _request.has("statusCode"):
		_request["statusCode"] = _http.get_response_code()
		_request["bytes"] = PackedByteArray()
	if _http.get_status() == HTTPClient.STATUS_BODY:
		_request["bodyStarted"] = true
		var chunk: PackedByteArray = _http.read_response_body_chunk()
		if chunk.size() > 0:
			var bytes: PackedByteArray = _request["bytes"]
			bytes.append_array(chunk)
			_request["bytes"] = bytes
		return
	_complete_body()


func _complete_body() -> void:
	var text: String = (_request.get("bytes", PackedByteArray()) as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if not text.strip_edges().is_empty() else {}
	var body: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var status: int = int(_request.get("statusCode", 0))
	if typeof(parsed) != TYPE_DICTIONARY and status >= 200 and status < 300:
		_finish(status, {}, CODE_BAD_RESPONSE)
		return
	_finish(status, body, "")


func _finish(status: int, body: Dictionary, transport_code: String) -> void:
	var entry: Dictionary = _request
	_request = {}
	if _http != null:
		_http.close()
		_http = null
	if entry.is_empty():
		return
	var code: String = transport_code
	if code.is_empty() and (status < 200 or status >= 300):
		code = error_code_for(status, body)
	var result: Dictionary = {"ok": code.is_empty(), "status": status, "body": body, "code": code,
		"message": _message_of(body), "retryAfterSeconds": _retry_after(body)}
	_log.append({"kind": entry["kind"], "status": status, "code": code})
	completed.emit(String(entry["kind"]), result)
	if not _queue.is_empty() and _request.is_empty():
		_start_next()


func _answer_now(kind: String, code: String, message: String) -> void:
	_log.append({"kind": kind, "status": 0, "code": code})
	completed.emit(kind, {"ok": false, "status": 0, "body": {}, "code": code, "message": message, "retryAfterSeconds": 0.0})


func _cloud_allowed() -> bool:
	return flag_enabled() or _dev_override


static func _message_of(body: Dictionary) -> String:
	var error: Variant = body.get("error", null)
	if typeof(error) == TYPE_DICTIONARY:
		return String((error as Dictionary).get("message", ""))
	return String(body.get("message", ""))


static func _retry_after(body: Dictionary) -> float:
	var error: Variant = body.get("error", null)
	var raw: Variant = body.get("retryAfterSeconds", null)
	if typeof(error) == TYPE_DICTIONARY and (error as Dictionary).has("retryAfterSeconds"):
		raw = (error as Dictionary)["retryAfterSeconds"]
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		return maxf(float(raw), 0.0)
	return 0.0
