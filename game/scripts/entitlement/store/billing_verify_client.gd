extends RefCounted

## Sends a store receipt to the backend and parses the backend's entitlement
## answer. PURE CLIENT LOGIC: no network primitive lives in this file.
##
## The transport is injected: a `Callable(method: String, path: String,
## body: Dictionary, on_done: Callable)` where `on_done(http_status: int,
## body_text: String)` is invoked exactly once. Tests pass a fake that replays
## recorded replies; the game will pass a one-line adapter over the flag-gated
## tutor cloud client (the only file allowed to hold an `HTTPRequest`, see
## `test_tutor_privacy_guards.gd`) when billing is activated. With no transport
## configured -- every current build -- `verify()` fails immediately with
## `backend_unavailable` and nothing is sent anywhere.
##
## Request  (POST /v1/billing/verify):
##   {store, productId, transactionId, payload, clientId}
## Reply (200):
##   {ok: true, decision: {entitlementId, status, periodEnd, verifiedAt,
##                         originalTransactionId, store, productId},
##    quota: {...}}                       -- see cloud/src/billing/handlers.ts
## Anything else (4xx/5xx, no HTTP status, junk JSON) is a failure the caller
## maps to "keep what you had"; a failure NEVER grants and NEVER revokes -- only a
## parsed decision does.

const StoreEntitlementProvider := preload("res://scripts/entitlement/store_entitlement_provider.gd")

signal decision_received(decision: Dictionary)
signal verify_failed(failure: Dictionary)

const VERIFY_PATH: String = "/v1/billing/verify"
const METHOD_POST: String = "POST"
const NO_HTTP_STATUS: int = 0

const FAIL_BACKEND_UNAVAILABLE: String = "backend_unavailable"
const FAIL_BAD_REPLY: String = "bad_reply"
const FAIL_REJECTED: String = "rejected"
const FAIL_BUSY: String = "busy"
const FAIL_BAD_RECEIPT: String = "bad_receipt"

var _transport: Callable = Callable()
var _client_id: String = ""
var _in_flight: bool = false


func configure(transport: Callable, client_id: String) -> void:
	_transport = transport
	_client_id = client_id.strip_edges()


func is_configured() -> bool:
	return _transport.is_valid()


func is_busy() -> bool:
	return _in_flight


## Forwards one receipt. Returns false (and emits `verify_failed`) when nothing
## was sent. Exactly one of the two signals follows a `true` return.
func verify(receipt: Dictionary) -> bool:
	if _in_flight:
		_fail(FAIL_BUSY, "A verification is already in flight.")
		return false
	var body: Dictionary = request_body(receipt, _client_id)
	if body.is_empty():
		_fail(FAIL_BAD_RECEIPT, "The receipt is missing its store, product or transaction.")
		return false
	if not _transport.is_valid():
		_fail(FAIL_BACKEND_UNAVAILABLE, "No backend is configured in this build.")
		return false
	_in_flight = true
	_transport.call(METHOD_POST, VERIFY_PATH, body, Callable(self, "_on_reply"))
	return true


## The exact JSON the backend receives. Empty when the receipt is unusable.
## Pure and static so a test can pin the wire shape.
static func request_body(receipt: Dictionary, client_id: String) -> Dictionary:
	var store: String = String(receipt.get("store", ""))
	var product_id: String = String(receipt.get("productId", ""))
	var transaction_id: String = String(receipt.get("transactionId", ""))
	var payload: Variant = receipt.get("payload", {})
	if store.is_empty() or product_id.is_empty() or transaction_id.is_empty():
		return {}
	if typeof(payload) != TYPE_DICTIONARY:
		return {}
	return {
		"store": store,
		"productId": product_id,
		"transactionId": transaction_id,
		"payload": (payload as Dictionary).duplicate(true),
		"clientId": client_id,
	}


## The one place a reply becomes a decision. Public so a test can feed a
## recorded reply through the exact path a live one takes.
func _on_reply(http_status: int, body_text: String) -> void:
	_in_flight = false
	# A JSON instance rather than `JSON.parse_string()`: a 5xx body that is not
	# JSON is a normal failure here, not an engine error worth a log line.
	var json: JSON = JSON.new()
	var parsed: Variant = json.get_data() if not body_text.is_empty() and json.parse(body_text) == OK else null
	if http_status == NO_HTTP_STATUS or http_status >= 500:
		_fail(FAIL_BACKEND_UNAVAILABLE, "The backend did not answer.", http_status)
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail(FAIL_BAD_REPLY, "The backend's reply was not readable.", http_status)
		return
	var reply: Dictionary = parsed
	if http_status >= 400 or not bool(reply.get("ok", false)):
		_fail(FAIL_REJECTED, String(reply.get("message", reply.get("code", "rejected"))), http_status,
				String(reply.get("code", "")))
		return
	var decision: Dictionary = StoreEntitlementProvider.sanitise_decision(reply.get("decision", null))
	if decision.is_empty():
		_fail(FAIL_BAD_REPLY, "The backend's decision was malformed.", http_status)
		return
	decision_received.emit(decision)


func _fail(code: String, message: String, http_status: int = NO_HTTP_STATUS, api_code: String = "") -> void:
	verify_failed.emit({
		"code": code,
		"message": message,
		"httpStatus": http_status,
		"apiCode": api_code,
	})
