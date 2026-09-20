extends RefCounted
## Turns a backend reply (HTTP status + JSON body) into one small, typed
## Dictionary the game can act on, and maps the API's error codes to the states
## the tutor scene knows. Pure: no network, no nodes; the cloud client and the
## tests both go through here, so a recorded fixture and a live reply are read
## by the same code.
##
## API: docs/ALIZ_TUTOR_API.md (Agent D). Every reply the game keeps is one of:
##
##   {"ok": true,  "state": "ok",  "code": "ok", "quota": {...}, "sessionId": "...",
##    "turn": {...}, "endAtBoundary": false, "entitlement": "free", ...}
##   {"ok": false, "state": <one of STATES>, "code": "<api code>", "message": "...",
##    "quota": {...} (when the body carried one), "retryAfterSeconds": n}
##
## `quota` is the server's block, sanitised (numbers finite and >= 0,
## `remainingSeconds` re-derived, `entitlement` one of the two names). The client
## NEVER computes minutes remaining from its own clock when a server block is
## available; it displays this one.

const QuotaConfig := preload("res://scripts/tutor/quota/quota_config.gd")

## What the scene does with each state.
const STATE_OK: String = "ok"
## Break screen: "Great job today!". Body carries `quota.resetAtUtc`.
const STATE_EXHAUSTED: String = "exhausted"
## Back to the parental gate; the approval token is missing or stale.
const STATE_NEEDS_PARENT_APPROVAL: String = "needs_parent_approval"
## Use the local scripted tutor for the rest of this lesson. Never a hang.
const STATE_PROVIDER_UNAVAILABLE: String = "provider_unavailable"
## Wait `retryAfterSeconds`, keep the listening state, then retry once.
const STATE_RATE_LIMITED: String = "rate_limited"
## The session is gone (ended / unknown): start a new one.
const STATE_SESSION_LOST: String = "session_lost"
## A client bug (bad lessonContext, idempotency mismatch, bad request): use the
## scripted turn and log it.
const STATE_CLIENT_ERROR: String = "client_error"

const STATES: Array[String] = [
	STATE_OK, STATE_EXHAUSTED, STATE_NEEDS_PARENT_APPROVAL, STATE_PROVIDER_UNAVAILABLE,
	STATE_RATE_LIMITED, STATE_SESSION_LOST, STATE_CLIENT_ERROR,
]

## API error code -> state. Anything not listed is a client error, and a
## transport failure (no HTTP status at all) is `provider_unavailable`.
const CODE_TO_STATE: Dictionary = {
	"quota_exhausted": STATE_EXHAUSTED,
	"not_approved": STATE_NEEDS_PARENT_APPROVAL,
	"provider_unavailable": STATE_PROVIDER_UNAVAILABLE,
	"timeout": STATE_PROVIDER_UNAVAILABLE,
	"rate_limited": STATE_RATE_LIMITED,
	"session_ended": STATE_SESSION_LOST,
	"not_found": STATE_SESSION_LOST,
	"invalid_turn": STATE_CLIENT_ERROR,
	"idempotency_mismatch": STATE_CLIENT_ERROR,
	"bad_request": STATE_CLIENT_ERROR,
	"payload_too_large": STATE_CLIENT_ERROR,
	"not_implemented": STATE_CLIENT_ERROR,
}

## The transport-level "no reply" pseudo status.
const NO_HTTP_STATUS: int = 0


## `http_status`: the HTTP code, or 0 for no reply (timeout, DNS, refused).
## `body`: the parsed JSON (Dictionary), a raw String, or null.
static func parse(http_status: int, body: Variant) -> Dictionary:
	var parsed: Variant = body
	if typeof(body) == TYPE_STRING:
		var text: String = String(body).strip_edges()
		# Only something that can be JSON is parsed; an HTML error page or an
		# empty body is simply "no usable body", without an engine error.
		parsed = JSON.parse_string(text) if text.begins_with("{") or text.begins_with("[") else null
	var source: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}

	if http_status == NO_HTTP_STATUS:
		return _failure(STATE_PROVIDER_UNAVAILABLE, "no_reply",
				"The tutor service did not answer.", source)

	var error_block: Variant = source.get("error", null)
	if http_status >= 400 or typeof(error_block) == TYPE_DICTIONARY:
		var code: String = "http_%d" % http_status
		var message: String = ""
		if typeof(error_block) == TYPE_DICTIONARY:
			var block: Dictionary = error_block
			if typeof(block.get("code", null)) == TYPE_STRING:
				code = String(block["code"])
			if typeof(block.get("message", null)) == TYPE_STRING:
				message = String(block["message"])
		var state: String = state_for(code, http_status)
		var out: Dictionary = _failure(state, code, message, source)
		if typeof(error_block) == TYPE_DICTIONARY:
			var block: Dictionary = error_block
			out["retryAfterSeconds"] = _number(block.get("retryAfterSeconds", 0.0), 0.0)
			if typeof(block.get("reason", null)) == TYPE_STRING:
				out["reason"] = String(block["reason"])
			if block.has("quota") and not out.has("quota"):
				out["quota"] = normalise_quota(block["quota"])
		return out

	var ok: Dictionary = {
		"ok": true,
		"state": STATE_OK,
		"code": "ok",
		"httpStatus": http_status,
		"endAtBoundary": bool(source.get("endAtBoundary", false)),
	}
	if source.has("quota"):
		ok["quota"] = normalise_quota(source["quota"])
	for key: String in ["sessionId", "lessonId", "entitlement", "endedAt", "clientId", "provider", "fallback"]:
		if typeof(source.get(key, null)) == TYPE_STRING:
			ok[key] = String(source[key])
	if typeof(source.get("turn", null)) == TYPE_DICTIONARY:
		ok["turn"] = (source["turn"] as Dictionary).duplicate(true)
	if typeof(source.get("usage", null)) == TYPE_DICTIONARY:
		ok["usage"] = (source["usage"] as Dictionary).duplicate(true)
	if source.has("turnIndex"):
		ok["turnIndex"] = int(_number(source["turnIndex"], 0.0))
	if source.has("chargedSeconds"):
		ok["chargedSeconds"] = _number(source["chargedSeconds"], 0.0)
	if typeof(source.get("products", null)) == TYPE_ARRAY:
		ok["products"] = (source["products"] as Array).duplicate()
	# An entitlement reply carries the name at the top level; a session reply too.
	if ok.has("entitlement"):
		ok["entitlement"] = normalise_entitlement(ok["entitlement"])
	return ok


## The state for an API error code; an unknown code is decided by HTTP status.
static func state_for(code: String, http_status: int = 0) -> String:
	if CODE_TO_STATE.has(code):
		return String(CODE_TO_STATE[code])
	if http_status == 503 or http_status == 504 or http_status == 502 or http_status == 0:
		return STATE_PROVIDER_UNAVAILABLE
	if http_status == 429:
		return STATE_RATE_LIMITED
	if http_status == 403 or http_status == 401:
		return STATE_NEEDS_PARENT_APPROVAL
	if http_status == 404 or http_status == 409:
		return STATE_SESSION_LOST
	if http_status >= 500:
		return STATE_PROVIDER_UNAVAILABLE
	return STATE_CLIENT_ERROR


## The server's quota block, checked field by field. Missing numbers read as 0;
## `remainingSeconds` is re-derived from allowance and used so the two can never
## disagree on screen; `resetAtUtc` is kept only when it looks like a timestamp.
static func normalise_quota(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var entitlement: String = normalise_entitlement(source.get("entitlement", QuotaConfig.ENTITLEMENT_FREE))
	var allowance: float = _number(source.get("dailyAllowanceSeconds", 0.0), 0.0)
	var used: float = _number(source.get("usedSeconds", 0.0), 0.0)
	var remaining: float = maxf(allowance - used, 0.0)
	var reset_at: String = ""
	var raw_reset: Variant = source.get("resetAtUtc", "")
	if typeof(raw_reset) == TYPE_STRING and String(raw_reset).length() >= 19:
		reset_at = String(raw_reset)
	return {
		"entitlement": entitlement,
		"dailyAllowanceSeconds": allowance,
		"usedSeconds": used,
		"remainingSeconds": remaining,
		"resetAtUtc": reset_at,
	}


## "family_club" (also accepts the entitlement-layer id "familyClub"); else "free".
static func normalise_entitlement(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return QuotaConfig.ENTITLEMENT_FREE
	var name: String = String(raw).strip_edges()
	if name == QuotaConfig.ENTITLEMENT_FAMILY_CLUB or name == "familyClub":
		return QuotaConfig.ENTITLEMENT_FAMILY_CLUB
	return QuotaConfig.ENTITLEMENT_FREE


## Is `state` one the scene knows?
static func is_state(state: String) -> bool:
	return STATES.has(state)


# -- internals -----------------------------------------------------------------

static func _failure(state: String, code: String, message: String, source: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"state": state,
		"code": code,
		"message": message,
	}
	if source.has("quota"):
		out["quota"] = normalise_quota(source["quota"])
	return out


static func _number(value: Variant, default_value: float) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return default_value
	var number: float = float(value)
	if not is_finite(number) or number < 0.0:
		return default_value
	return number
