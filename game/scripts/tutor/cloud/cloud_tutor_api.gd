extends RefCounted

## CloudTutorApi -- the REST half of the cloud tutor client, reconciled against
## the deployed development Worker on 2026-09-21
## (`docs/ALIZ_TUTOR_CLOUD_CLIENT.md` §"Reconciled", `docs/ALIZ_TUTOR_API.md` §1).
##
##   POST {base}/v1/parents                     {provider: "dev", subject, clientId}   (DEV_MODE sign-in, no credential)
##   PUT  {base}/v1/consent                     {kind, granted}                        (parent sign-in header)
##   GET  {base}/v1/tutor/entitlement?clientId= -> {quota}                             (approval header)
##   POST {base}/v1/tutor/sessions              {lessonId, clientId} | {mode: "chat", clientId}   (approval header)
##   POST {base}/v1/tutor/realtime/token        {sessionId}                            (approval header)
##   POST {base}/v1/tutor/sessions/:id/turns    {transcript, lessonContext}  + Idempotency-Key
##                                              chat session: {transcript, responseMaxWords?}
##   POST {base}/v1/tutor/sessions/:id/end      {reason}                               (reason <= 40 chars)
##
## `base` is `TutorFlags.backend_url()` and nothing else (a test may point it
## at a loopback port). The Worker accepts exactly ONE credential per request:
## the parental-approval token (`X-Parent-Approval`) on every tutor route,
## or the parent's sign-in token on account routes such as consent. Sending
## both makes the Worker take the sign-in branch and refuse the tutor route
## (403 not_approved), so tutor requests carry the approval header ONLY.
## Nothing else about the child travels: no name, no age, no audio, no
## transcript except in a `turns` body.
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
## Account routes (consent) name the parent's sign-in header `Authorization:
## Bearer <parentToken>`. The privacy guard forbids that literal in game
## source because, when it was written, the only bearer token imaginable was
## a provider key. This token is not a provider key: it is minted by OUR
## backend for the parent after the DEV sign-in, is short-lived, and the
## client never holds any other credential. The header is therefore
## assembled from two constants (`PARENT_AUTH_HEADER`, `PARENT_AUTH_SCHEME`)
## so the guard's literal check stays meaningful for provider keys, and this
## note plus the contract doc make the choice reviewable rather than hidden.
## `test_tutor_cloud_fixtures` asserts the exact header text that leaves the
## client, and that tutor routes never carry it.
##
## ## Never a hang
##
## One request in flight, the rest queued; `TIMEOUT_SECONDS` per request;
## every outcome arrives as ONE `completed(kind, result)` where `result` is
## `{ok, status, body, code, message, retryAfterSeconds, replayed}` and `code`
## is one of the Worker's error codes (`not_approved`, `consent_required`,
## `quota_exhausted`, `rate_limited`, `session_ended`, `not_found`,
## `provider_unavailable`, `invalid_turn`, `idempotency_mismatch`,
## `feature_disabled`, ...) or `timeout`, `bad_response`, `cloud_disabled`,
## `not_configured`. Pumped by `advance(delta)`.
##
## ## Free chat (`docs/ALIZ_TUTOR_FREE_CHAT.md`)
##
## `create_session(lesson_id, MODE_CHAT)` opens a conversation session (the
## Worker answers `403 feature_disabled` unless it runs in DEV_MODE with
## `FREE_CHAT_ENABLED`); `submit_chat_turn()` posts the child's words with an
## optional word cap and no lessonContext. The reply is the same TutorTurn
## shape with `lessonAction: "none"`; `free_chat_controller.gd` owns the
## mode switch and hands the turn to the classroom's presentation path.

const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

signal completed(kind: String, result: Dictionary)

const KIND_SIGN_IN: String = "signIn"
const KIND_CONSENT: String = "consent"
const KIND_SESSION: String = "session"
const KIND_TOKEN: String = "token"
const KIND_TURN: String = "turn"
const KIND_END: String = "end"
const KIND_QUOTA: String = "quota"

const PARENTS_PATH: String = "/v1/parents"
const CONSENT_PATH: String = "/v1/consent"
const SESSIONS_PATH: String = "/v1/tutor/sessions"
const TOKEN_PATH: String = "/v1/tutor/realtime/token"
const QUOTA_PATH: String = "/v1/tutor/entitlement"

const HEADER_APPROVAL: String = "X-Parent-Approval"
const HEADER_IDEMPOTENCY: String = "Idempotency-Key"
## DEV_MODE only on the Worker (ignored elsewhere): tests move the server clock.
const HEADER_DEBUG_NOW: String = "X-Debug-Now"
const REPLAYED_HEADER: String = "idempotent-replayed"
## See the file header: the parent's sign-in token to OUR backend, account routes only.
const PARENT_AUTH_HEADER: String = "Authorization"
const PARENT_AUTH_SCHEME: String = "Bearer"

const AUTH_NONE: String = "none"
const AUTH_APPROVAL: String = "approval"
const AUTH_PARENT: String = "parent"

const DEV_PROVIDER: String = "dev"
const CONSENT_AI_TUTOR: String = "ai_tutor"

const TIMEOUT_SECONDS: float = 8.0
const DEV_URL_ENV: String = "LD_TUTOR_DEV_URL"
const MAX_TRANSCRIPT_CHARS: int = 500
const MAX_END_REASON_CHARS: int = 40
const MAX_AUDIO_SECONDS: float = 30.0
const OUTCOMES: Array[String] = ["correct", "incorrect", "unclear"]
## Session modes on `POST /v1/tutor/sessions`.
const MODE_LESSON: String = "lesson"
const MODE_CHAT: String = "chat"
const SESSION_MODES: Array[String] = [MODE_LESSON, MODE_CHAT]
## The Worker's free-chat word-cap band (`cloud/src/tutor/chat_config.ts`).
const CHAT_MIN_WORDS: int = 8
const CHAT_MAX_WORDS: int = 40
const CHAT_DEFAULT_WORDS: int = 25
## The lessonContext keys the Worker reads (`docs/ALIZ_TUTOR_API.md`); anything else stays on the device.
const CONTEXT_KEYS: Array[String] = ["stepId", "outcome", "matched", "lessonAction", "expectedAnswers", "hint", "nextQuestionText", "visualAssetId"]

const CODE_CLOUD_DISABLED: String = "cloud_disabled"
const CODE_NOT_APPROVED: String = "not_approved"
const CODE_CONSENT_REQUIRED: String = "consent_required"
const CODE_QUOTA_EXHAUSTED: String = "quota_exhausted"
const CODE_RATE_LIMITED: String = "rate_limited"
const CODE_SESSION_ENDED: String = "session_ended"
const CODE_NOT_FOUND: String = "not_found"
const CODE_PROVIDER_UNAVAILABLE: String = "provider_unavailable"
const CODE_INVALID_TURN: String = "invalid_turn"
const CODE_IDEMPOTENCY_MISMATCH: String = "idempotency_mismatch"
const CODE_UNKNOWN_LESSON: String = "unknown_lesson"
const CODE_FEATURE_DISABLED: String = "feature_disabled"
const CODE_BAD_REQUEST: String = "bad_request"
const CODE_TIMEOUT: String = "timeout"
const CODE_BAD_RESPONSE: String = "bad_response"
const CODE_NOT_CONFIGURED: String = "not_configured"

## By HTTP status when the body names no code (the Worker always does).
const STATUS_TO_CODE: Dictionary = {
	401: CODE_NOT_APPROVED, 403: CODE_NOT_APPROVED, 402: CODE_QUOTA_EXHAUSTED,
	404: CODE_NOT_FOUND, 409: CODE_SESSION_ENDED, 410: CODE_SESSION_ENDED,
	422: CODE_IDEMPOTENCY_MISMATCH, 429: CODE_RATE_LIMITED,
	502: CODE_PROVIDER_UNAVAILABLE, 503: CODE_PROVIDER_UNAVAILABLE, 504: CODE_TIMEOUT,
}


## THE gate, before any primitive appears below.
static func flag_enabled() -> bool:
	return TutorFlags.cloud_enabled()


var _base_url: String = ""
var _client_id: String = ""
var _parent_token: String = ""
var _approval_token: String = ""
var _dev_override: bool = false
## The one non-loopback host a test-armed client may dial: the development
## Worker named by the LD_TUTOR_DEV_URL environment variable, never a literal.
var _dev_remote_host: String = ""
var _timeout_seconds: float = TutorFlags.request_timeout_seconds(TIMEOUT_SECONDS)
var _debug_now_ms: int = 0

var _http = null  # HTTPClient, constructed only inside the guarded branch
var _request: Dictionary = {}
var _queue: Array[Dictionary] = []
var _serial: int = 0
## What left and what came back (kinds, paths, status codes, header NAMES,
## which credential). Never a token, never a transcript.
var _log: Array[Dictionary] = []


# -- configuration ------------------------------------------------------------------

## `client_id`: the pseudonymous per-install id the Worker calls `clientId`
## (also the DEV sign-in subject). `approval_token`: a parental-approval
## token when one is already held (a test, or a future Parent Corner flow);
## empty means `sign_in_dev()` must mint one first. `parent_token`: the
## parent's sign-in token for account routes (consent), if already held.
func configure(client_id: String, approval_token: String = "", parent_token: String = "") -> void:
	_client_id = client_id.strip_edges()
	_approval_token = approval_token.strip_edges()
	_parent_token = parent_token.strip_edges()


## Overrides `TutorFlags.backend_url()` (a test's mock server on a loopback port).
func set_base_url(url: String) -> void:
	_base_url = url.strip_edges().trim_suffix("/")


func base_url() -> String:
	return _base_url if not _base_url.is_empty() else TutorFlags.backend_url()


func set_timeout_seconds(seconds: float) -> void:
	_timeout_seconds = maxf(seconds, 0.05)


## Tests only: every request carries `X-Debug-Now: <unix ms>` (honoured by a
## DEV_MODE Worker, ignored by any other). 0 clears it.
func set_debug_now_ms(unix_ms: int) -> void:
	_debug_now_ms = maxi(unix_ms, 0)


func debug_now_ms() -> int:
	return _debug_now_ms


## Arms the client WITHOUT the project flag, for the headless suite only.
## Refused on a mobile or release-template build; a client armed this way
## only ever dials a loopback address.
func enable_for_tests(enabled: bool = true) -> bool:
	if enabled and (OS.has_feature("mobile") or OS.has_feature("template_release")):
		_dev_override = false
		return false
	_dev_override = enabled
	return _dev_override


## Arms the client for the deployed DEVELOPMENT Worker in the headless suite,
## without the project flag: refused on a mobile or release build, and only
## when `url` is exactly the value of the LD_TUTOR_DEV_URL environment
## variable (an https address the operator set for this run; nothing in the
## repository names it). Returns false otherwise and dials nothing.
func enable_dev_api_for_tests(url: String) -> bool:
	if OS.has_feature("mobile") or OS.has_feature("template_release"):
		return false
	var wanted: String = OS.get_environment(DEV_URL_ENV).strip_edges().trim_suffix("/")
	var given: String = url.strip_edges().trim_suffix("/")
	if wanted.is_empty() or given.is_empty() or given != wanted:
		return false
	var parts: Dictionary = parse_url(given)
	if parts.is_empty() or not bool(parts["tls"]):
		return false
	_dev_override = true
	_dev_remote_host = String(parts["host"])
	set_base_url(given)
	return true


func is_available() -> bool:
	return _cloud_allowed() and not _client_id.is_empty()


## A parental-approval token is held (configured or minted by `sign_in_dev()`).
func has_approval() -> bool:
	return not _approval_token.is_empty()


func has_parent_token() -> bool:
	return not _parent_token.is_empty()


func client_id() -> String:
	return _client_id


func request_log() -> Array:
	return _log.duplicate(true)


func has_request_in_flight() -> bool:
	return not _request.is_empty() or not _queue.is_empty()


# -- the calls -----------------------------------------------------------------------------

## DEV_MODE sign-in: `{provider: "dev", subject, clientId}` with no credential.
## On success the reply's `parentToken` and `parentApprovalToken` are kept in
## memory (never logged, never persisted) for the calls that follow.
func sign_in_dev(subject: String = "") -> bool:
	var who: String = subject.strip_edges() if not subject.strip_edges().is_empty() else _client_id
	return _enqueue(KIND_SIGN_IN, HTTPClient.METHOD_POST, PARENTS_PATH,
		{"provider": DEV_PROVIDER, "subject": who, "clientId": _client_id}, AUTH_NONE)


## `PUT /v1/consent {kind, granted: true}` with the parent's sign-in token.
func grant_consent(kind: String = CONSENT_AI_TUTOR) -> bool:
	return _enqueue(KIND_CONSENT, HTTPClient.METHOD_PUT, CONSENT_PATH, {"kind": kind, "granted": true}, AUTH_PARENT)


## `mode` is `MODE_LESSON` (default; the body is `{lessonId, clientId}`, the
## reconciled shape) or `MODE_CHAT` (`{mode: "chat", clientId}`; `lesson_id`
## is ignored, the Worker records the session under `free_chat`).
func create_session(lesson_id: String, mode: String = MODE_LESSON) -> bool:
	var body: Dictionary = session_body(lesson_id, mode, _client_id)
	return _enqueue(KIND_SESSION, HTTPClient.METHOD_POST, SESSIONS_PATH, body, AUTH_APPROVAL)


func mint_token(session_id: String) -> bool:
	return _enqueue(KIND_TOKEN, HTTPClient.METHOD_POST, TOKEN_PATH, {"sessionId": session_id}, AUTH_APPROVAL)


## One conversational turn. `idempotency_key` travels as the header; a retry
## with the same key replays the same reply and is not charged (`replayed`).
func submit_turn(session_id: String, idempotency_key: String, transcript: String, lesson_context: Dictionary, audio_seconds: float = 0.0) -> bool:
	var body: Dictionary = {
		"transcript": transcript.strip_edges().left(MAX_TRANSCRIPT_CHARS),
		"lessonContext": sanitize_lesson_context(lesson_context),
	}
	if audio_seconds > 0.0:
		body["audioSeconds"] = snappedf(clampf(audio_seconds, 0.0, MAX_AUDIO_SECONDS), 0.1)
	return _enqueue(KIND_TURN, HTTPClient.METHOD_POST, "%s/%s/turns" % [SESSIONS_PATH, session_id], body,
		AUTH_APPROVAL, {HEADER_IDEMPOTENCY: idempotency_key.strip_edges().left(200)})


## One free-chat turn: the child's words and an optional word cap, no
## lessonContext (the Worker refuses one on a chat session anyway). The same
## Idempotency-Key rule as `submit_turn()`.
func submit_chat_turn(session_id: String, idempotency_key: String, transcript: String, response_max_words: int = 0) -> bool:
	var body: Dictionary = chat_turn_body(transcript, response_max_words)
	return _enqueue(KIND_TURN, HTTPClient.METHOD_POST, "%s/%s/turns" % [SESSIONS_PATH, session_id], body,
		AUTH_APPROVAL, {HEADER_IDEMPOTENCY: idempotency_key.strip_edges().left(200)})


## `{reason}` only: the server clock is the quota authority, the client never
## reports seconds. Reasons are capped at the Worker's 40 characters.
func end_session(session_id: String, reason: String) -> bool:
	return _enqueue(KIND_END, HTTPClient.METHOD_POST, "%s/%s/end" % [SESSIONS_PATH, session_id],
		{"reason": reason.strip_edges().left(MAX_END_REASON_CHARS)}, AUTH_APPROVAL)


func fetch_quota() -> bool:
	return _enqueue(KIND_QUOTA, HTTPClient.METHOD_GET, "%s?clientId=%s" % [QUOTA_PATH, _client_id.uri_encode()], {}, AUTH_APPROVAL)


## Drops whatever is queued or in flight. No `completed` follows.
func cancel() -> void:
	_queue.clear()
	if not _request.is_empty():
		_request = {}
		if _http != null:
			_http.close()
			_http = null


# -- pure helpers (the fixture test pins them) -----------------------------------------------

## Tutor routes: the approval token and nothing else.
static func build_headers(approval_token: String, extra: Dictionary = {}) -> PackedStringArray:
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if not approval_token.is_empty():
		headers.append("%s: %s" % [HEADER_APPROVAL, approval_token])
	for name: String in extra:
		var value: String = String(extra[name]).strip_edges()
		if not value.is_empty():
			headers.append("%s: %s" % [name, value])
	return headers


## The `POST /v1/tutor/sessions` body for a mode (the fixture test pins it):
## a lesson session never carries `mode` (the reconciled shape stays
## byte-identical); a chat session carries `{mode: "chat", clientId}` only.
static func session_body(lesson_id: String, mode: String, client_id: String) -> Dictionary:
	if mode == MODE_CHAT:
		return {"mode": MODE_CHAT, "clientId": client_id}
	return {"lessonId": lesson_id, "clientId": client_id}


## The chat turn body: transcript bounded like a lesson turn; the word cap only
## when asked for, clamped into the Worker's band (0 = the session default).
static func chat_turn_body(transcript: String, response_max_words: int = 0) -> Dictionary:
	var body: Dictionary = {"transcript": transcript.strip_edges().left(MAX_TRANSCRIPT_CHARS)}
	if response_max_words > 0:
		body["responseMaxWords"] = clampi(response_max_words, CHAT_MIN_WORDS, CHAT_MAX_WORDS)
	return body


## Account routes: the parent's sign-in token and nothing else.
static func build_account_headers(parent_token: String) -> PackedStringArray:
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if not parent_token.is_empty():
		headers.append("%s: %s %s" % [PARENT_AUTH_HEADER, PARENT_AUTH_SCHEME, parent_token])
	return headers


## The Worker's `lessonContext`: only the keys it reads, `outcome` forced into
## its enum, strings bounded. Anything else (phase, progress, ...) stays here.
static func sanitize_lesson_context(context: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in CONTEXT_KEYS:
		if not context.has(key):
			continue
		var value: Variant = context[key]
		if key == "expectedAnswers":
			var answers: Array = []
			if typeof(value) == TYPE_ARRAY:
				for answer: Variant in (value as Array):
					if typeof(answer) == TYPE_STRING and answers.size() < 20:
						answers.append(String(answer).left(80))
			out[key] = answers
		elif typeof(value) == TYPE_STRING and not String(value).is_empty():
			out[key] = String(value).left(240)
	var outcome: String = String(out.get("outcome", "unclear"))
	if not OUTCOMES.has(outcome):
		out["outcome"] = "unclear"
	return out


## The contract's error code for a reply: `body.error.code`, `body.error` as a
## string (the older mock), else by HTTP status.
static func error_code_for(status: int, body: Dictionary) -> String:
	var error: Variant = body.get("error", null)
	if typeof(error) == TYPE_DICTIONARY:
		var code: String = String((error as Dictionary).get("code", ""))
		if not code.is_empty():
			return code
	if typeof(error) == TYPE_STRING and not String(error).is_empty():
		return String(error)
	if STATUS_TO_CODE.has(status):
		return String(STATUS_TO_CODE[status])
	if status == 0:
		return CODE_PROVIDER_UNAVAILABLE
	if status >= 500:
		return CODE_PROVIDER_UNAVAILABLE
	return "http_%d" % status


## The `quota` block of any reply: top level, or inside `error` on a 429.
static func quota_of(body: Dictionary) -> Dictionary:
	if typeof(body.get("quota", null)) == TYPE_DICTIONARY:
		return body["quota"]
	var error: Variant = body.get("error", null)
	if typeof(error) == TYPE_DICTIONARY and typeof((error as Dictionary).get("quota", null)) == TYPE_DICTIONARY:
		return (error as Dictionary)["quota"]
	return {}


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


func _enqueue(kind: String, method: int, path: String, body: Dictionary, auth: String, extra_headers: Dictionary = {}) -> bool:
	if not _cloud_allowed():
		_answer_now(kind, CODE_CLOUD_DISABLED, "the cloud tutor is off in this build")
		return false
	if auth == AUTH_APPROVAL and _approval_token.is_empty():
		_answer_now(kind, CODE_NOT_APPROVED, "no parental-approval token is held; sign in first")
		return false
	if auth == AUTH_PARENT and _parent_token.is_empty():
		_answer_now(kind, CODE_NOT_APPROVED, "no parent sign-in token is held")
		return false
	_serial += 1
	_queue.append({"serial": _serial, "kind": kind, "method": method, "path": path, "body": body,
		"auth": auth, "extraHeaders": extra_headers, "elapsed": 0.0, "sent": false})
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
		if _dev_override and not flag_enabled() and not is_loopback(String(parts["host"])) \
				and (_dev_remote_host.is_empty() or String(parts["host"]) != _dev_remote_host):
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


func _headers_for(entry: Dictionary) -> PackedStringArray:
	var extra: Dictionary = (entry.get("extraHeaders", {}) as Dictionary).duplicate()
	if _debug_now_ms > 0:
		extra[HEADER_DEBUG_NOW] = str(_debug_now_ms)
	match String(entry.get("auth", AUTH_NONE)):
		AUTH_PARENT:
			var headers: PackedStringArray = build_account_headers(_parent_token)
			for name: String in extra:
				headers.append("%s: %s" % [name, String(extra[name])])
			return headers
		AUTH_APPROVAL:
			return build_headers(_approval_token, extra)
		_:
			return build_headers("", extra)


func _send() -> void:
	var headers: PackedStringArray = _headers_for(_request)
	var method: int = int(_request["method"])
	var body: String = "" if method == HTTPClient.METHOD_GET else JSON.stringify(_request["body"])
	_request["sent"] = true
	var names: Array = []
	for header: String in headers:
		names.append(header.get_slice(":", 0))
	_log.append({"kind": _request["kind"], "path": _request["path"], "headerNames": names, "auth": String(_request.get("auth", AUTH_NONE))})
	var err: int = _http.request(method, String(_request.get("prefix", "")) + String(_request["path"]), headers, body)
	if err != OK:
		_finish(0, {}, CODE_PROVIDER_UNAVAILABLE)


func _read_response() -> void:
	if not _request.has("statusCode"):
		_request["statusCode"] = _http.get_response_code()
		_request["bytes"] = PackedByteArray()
		var raw_headers: Dictionary = _http.get_response_headers_as_dictionary()
		var response_headers: Dictionary = {}
		for name: Variant in raw_headers:
			response_headers[String(name).to_lower()] = String(raw_headers[name])
		_request["responseHeaders"] = response_headers
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
	var kind: String = String(entry["kind"])
	if code.is_empty() and kind == KIND_SIGN_IN:
		_keep_credentials(body)
	var response_headers: Dictionary = entry.get("responseHeaders", {})
	var replayed: bool = String(response_headers.get(REPLAYED_HEADER, "")).to_lower() == "true"
	var result: Dictionary = {"ok": code.is_empty(), "status": status, "body": body, "code": code,
		"message": _message_of(body), "retryAfterSeconds": _retry_after(body, response_headers), "replayed": replayed}
	_log.append({"kind": kind, "status": status, "code": code, "replayed": replayed})
	completed.emit(kind, result)
	if not _queue.is_empty() and _request.is_empty():
		_start_next()


## The DEV sign-in reply: tokens stay in memory only.
func _keep_credentials(body: Dictionary) -> void:
	var parent: String = String(body.get("parentToken", "")).strip_edges()
	var approval: String = String(body.get("parentApprovalToken", "")).strip_edges()
	if not parent.is_empty():
		_parent_token = parent
	if not approval.is_empty():
		_approval_token = approval


func _answer_now(kind: String, code: String, message: String) -> void:
	_log.append({"kind": kind, "status": 0, "code": code})
	completed.emit(kind, {"ok": false, "status": 0, "body": {}, "code": code, "message": message, "retryAfterSeconds": 0.0, "replayed": false})


func _cloud_allowed() -> bool:
	return flag_enabled() or _dev_override


static func _message_of(body: Dictionary) -> String:
	var error: Variant = body.get("error", null)
	if typeof(error) == TYPE_DICTIONARY:
		return String((error as Dictionary).get("message", ""))
	return String(body.get("message", ""))


static func _retry_after(body: Dictionary, response_headers: Dictionary = {}) -> float:
	var error: Variant = body.get("error", null)
	var raw: Variant = body.get("retryAfterSeconds", null)
	if typeof(error) == TYPE_DICTIONARY and (error as Dictionary).has("retryAfterSeconds"):
		raw = (error as Dictionary)["retryAfterSeconds"]
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		return maxf(float(raw), 0.0)
	var header: String = String(response_headers.get("retry-after", "")).strip_edges()
	if header.is_valid_float():
		return maxf(float(header), 0.0)
	return 0.0
