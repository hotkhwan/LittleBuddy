extends RefCounted

## Store receipt -> backend verdict -> entitlement. The one orchestration.
##
##   begin_purchase(product_id, parent_gate_open)
##     -> gateway.purchase()            (returns `disabled` in every committed build)
##     -> purchase_updated(receipt)     (a store callback: NOT an entitlement)
##     -> verify_client.verify(receipt) (POST /v1/billing/verify)
##     -> decision_received(decision)   (the backend's answer)
##     -> provider.apply_backend_decision(decision, now)
##     -> entitlement_applied(decision)
##
##   restore(parent_gate_open) does the same for every receipt the store account
##   already owns, one verify per receipt, in order.
##
## Rules this file enforces so no screen has to remember them:
##   * NOTHING starts unless the caller says the parental gate is open. A child
##     tapping anything cannot reach a store, because there is no call path that
##     omits the flag.
##   * A store callback alone changes no entitlement. The provider is only ever
##     written from a parsed backend decision; a failed or missing verify leaves
##     the family exactly where they were.
##   * One operation at a time. A second `begin_purchase()` while busy is refused.
##
## Signals: `flow_finished(outcome)` with
##   {outcome: "disabled" | "unavailable" | "gate_closed" | "busy" | "cancelled"
##             | "failed" | "verified" | "restored" | "nothing_to_restore",
##    message, decision?}
## and `entitlement_applied(decision)` whenever the provider was written.

const StoreGateway := preload("res://scripts/entitlement/store/store_gateway.gd")
const VerifyClient := preload("res://scripts/entitlement/store/billing_verify_client.gd")

signal flow_finished(outcome: Dictionary)
signal entitlement_applied(decision: Dictionary)

const OUTCOME_DISABLED: String = "disabled"
const OUTCOME_UNAVAILABLE: String = "unavailable"
const OUTCOME_GATE_CLOSED: String = "gate_closed"
const OUTCOME_BUSY: String = "busy"
const OUTCOME_CANCELLED: String = "cancelled"
const OUTCOME_FAILED: String = "failed"
const OUTCOME_VERIFIED: String = "verified"
const OUTCOME_RESTORED: String = "restored"
const OUTCOME_NOTHING_TO_RESTORE: String = "nothing_to_restore"

var _gateway: RefCounted = null
var _verify: RefCounted = null
var _provider: RefCounted = null
var _clock: Callable = Callable()

var _busy: bool = false
var _restoring: bool = false
var _restore_queue: Array = []
var _restore_applied: int = 0
var _restore_last_decision: Dictionary = {}


## `clock` returns unix seconds; tests inject one. Defaults to the wall clock.
func _init(gateway: RefCounted, verify_client: RefCounted, provider: RefCounted, clock: Callable = Callable()) -> void:
	_gateway = gateway
	_verify = verify_client
	_provider = provider
	_clock = clock
	if _gateway != null:
		_gateway.connect("purchase_updated", _on_purchase_updated)
		_gateway.connect("restore_finished", _on_restore_finished)
		_gateway.connect("store_error", _on_store_error)
	if _verify != null:
		_verify.connect("decision_received", _on_decision)
		_verify.connect("verify_failed", _on_verify_failed)


func is_busy() -> bool:
	return _busy


## A grown-up, past the gate, asked to buy `product_id`.
func begin_purchase(product_id: String, parent_gate_open: bool) -> Dictionary:
	if not parent_gate_open:
		return _finish(OUTCOME_GATE_CLOSED, "Purchases are only offered behind the parental gate.")
	if _busy:
		return _finish(OUTCOME_BUSY, "Another store operation is in progress.")
	_busy = true
	_restoring = false
	var started: Dictionary = _gateway.purchase(product_id)
	var status: String = String(started.get("status", ""))
	if status == StoreGateway.STATUS_STARTED:
		return started
	_busy = false
	match status:
		StoreGateway.STATUS_DISABLED:
			return _finish(OUTCOME_DISABLED, "Billing is not available in this build.")
		StoreGateway.STATUS_INVALID_PRODUCT:
			return _finish(OUTCOME_FAILED, "Unknown product.")
		_:
			return _finish(OUTCOME_UNAVAILABLE, "The store is not available on this device.")


## A grown-up, past the gate, asked to restore. Read-only at the store.
func restore(parent_gate_open: bool) -> Dictionary:
	if not parent_gate_open:
		return _finish(OUTCOME_GATE_CLOSED, "Restore is only offered behind the parental gate.")
	if _busy:
		return _finish(OUTCOME_BUSY, "Another store operation is in progress.")
	_busy = true
	_restoring = true
	_restore_queue = []
	_restore_applied = 0
	_restore_last_decision = {}
	var started: Dictionary = _gateway.restore_purchases()
	if String(started.get("status", "")) == StoreGateway.STATUS_STARTED:
		return started
	_busy = false
	_restoring = false
	return _finish(OUTCOME_UNAVAILABLE, "The store is not available on this device.")


# -- store callbacks -------------------------------------------------------------

func _on_purchase_updated(receipt: Dictionary) -> void:
	if not _busy or _restoring:
		return
	var status: String = String(receipt.get("status", ""))
	match status:
		StoreGateway.RECEIPT_PURCHASED:
			# The store says "bought". That is a receipt, not a grant: ask the backend.
			if not _verify.verify(receipt):
				_busy = false  # verify_failed already fired with the reason
		StoreGateway.RECEIPT_PENDING:
			pass  # deferred (Ask to Buy / pending); the store will call again
		StoreGateway.RECEIPT_CANCELLED:
			_busy = false
			_finish(OUTCOME_CANCELLED, "")
		_:
			_busy = false
			_finish(OUTCOME_FAILED, String(receipt.get("message", "The purchase did not complete.")))


func _on_restore_finished(result: Dictionary) -> void:
	if not _busy or not _restoring:
		return
	if String(result.get("status", "")) != "ok":
		_busy = false
		_restoring = false
		_finish(OUTCOME_FAILED, String(result.get("message", "Restore did not complete.")))
		return
	_restore_queue = []
	var receipts: Variant = result.get("receipts", [])
	if typeof(receipts) == TYPE_ARRAY:
		for entry: Variant in receipts:
			if typeof(entry) == TYPE_DICTIONARY \
					and String((entry as Dictionary).get("status", "")) == StoreGateway.RECEIPT_PURCHASED:
				_restore_queue.append(entry)
	_next_restore_receipt()


func _on_store_error(error: Dictionary) -> void:
	if not _busy:
		return
	if String(error.get("code", "")) == StoreGateway.ERROR_STORE_UNAVAILABLE:
		_busy = false
		_restoring = false
		_finish(OUTCOME_UNAVAILABLE, String(error.get("message", "")))


# -- backend callbacks -----------------------------------------------------------

func _on_decision(decision: Dictionary) -> void:
	# The ONLY write to the provider in this file.
	if _provider != null and _provider.has_method("apply_backend_decision"):
		_provider.call("apply_backend_decision", decision, _now())
	entitlement_applied.emit(decision)
	if _restoring:
		_restore_applied += 1
		_restore_last_decision = decision
		_next_restore_receipt()
		return
	_busy = false
	_finish(OUTCOME_VERIFIED, "", decision)


func _on_verify_failed(failure: Dictionary) -> void:
	if _restoring:
		# One bad receipt does not stop the others; nothing was granted for it.
		_next_restore_receipt()
		return
	_busy = false
	_finish(OUTCOME_FAILED, String(failure.get("message", "")))


func _next_restore_receipt() -> void:
	while not _restore_queue.is_empty():
		var receipt: Dictionary = _restore_queue.pop_front()
		if _verify.verify(receipt):
			return  # wait for the reply; the callbacks continue the loop
	_busy = false
	_restoring = false
	if _restore_applied > 0:
		_finish(OUTCOME_RESTORED, "", _restore_last_decision)
	else:
		_finish(OUTCOME_NOTHING_TO_RESTORE, "")


func _finish(outcome: String, message: String, decision: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"outcome": outcome, "message": message}
	if not decision.is_empty():
		out["decision"] = decision
	flow_finished.emit(out)
	return out


func _now() -> int:
	if _clock.is_valid():
		return int(_clock.call())
	return int(Time.get_unix_time_from_system())
