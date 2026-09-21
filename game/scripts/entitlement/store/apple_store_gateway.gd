extends "res://scripts/entitlement/store/store_gateway.gd"

## Apple adapter: a thin shim over the iOS in-app purchase plugin singleton.
##
## TARGET PLUGIN: godotengine/godot-ios-plugins, plugin `inappstore`, the Godot
## 4.x branch (built for the engine version in `VERSION`/`docs/ipad-runbook.md`;
## the plugin registers the singleton named below). This is a StoreKit-1-era
## plugin: it hands back `transaction_id` and the base64 app receipt, NOT a
## StoreKit 2 signed transaction. That is fine, because the backend never takes
## the device's word for it anyway: `POST /v1/billing/verify` for `store: apple`
## looks the `transactionId` up with the App Store Server API and reads the
## signed transaction Apple returns (`cloud/src/billing/apple.ts`). If the
## plugin is later swapped for a StoreKit 2 one, put its `signedTransaction`
## JWS into `payload.signedTransaction` and the same backend path verifies it.
##
## THE PLUGIN IS NOT IN THIS REPOSITORY. `Engine.has_singleton()` is false in
## every current build, on desktop and on the iPad, so this adapter reports
## `store_unavailable` and does nothing. Adding the plugin to the export is part
## of the activation checklist in `docs/FAMILY_CLUB_BILLING.md`, after owner
## approval -- and even then `purchase()` stays behind
## `little_days/billing/purchases_enabled` (base class, not overridable).
##
## Plugin API used (names as documented by the plugin; verify against the exact
## plugin build at activation, see the checklist):
##   request_product_info({"product_ids": PackedStringArray})
##   purchase({"product_id": String})
##   restore_purchases()
##   set_auto_finish_transaction(bool)
##   get_pending_event_count() / pop_pending_event() -> Dictionary
##     {type: "product_info", ids, titles, descriptions, prices, localized_prices,
##      currency_codes, invalid_ids}
##     {type: "purchase", result: "ok"|"error"|"progress"|"unhandled",
##      product_id, transaction_id, receipt}
##     {type: "restore", result: "ok"|"error"|"completed"|"unhandled",
##      product_id, transaction_id, receipt}
## Events are queued by the plugin; the owner of this adapter calls `poll()`
## every frame while a store operation is in flight.

const SINGLETON_NAME: String = "InAppStore"
const STORE_ID: String = "apple"

var _store: Object = null
var _restoring: Array = []
var _restore_in_flight: bool = false


func gateway_id() -> String:
	return STORE_ID


func is_available() -> bool:
	return _singleton() != null


## Drains the plugin's event queue. Safe to call when unavailable.
func poll() -> void:
	var store: Object = _singleton()
	if store == null:
		return
	while int(store.call("get_pending_event_count")) > 0:
		var event: Variant = store.call("pop_pending_event")
		if typeof(event) == TYPE_DICTIONARY:
			_handle_event(event)


# -- hooks ---------------------------------------------------------------------

func _query_products(product_ids: PackedStringArray) -> Dictionary:
	_singleton().call("request_product_info", {"product_ids": product_ids})
	return _result(STATUS_STARTED)


func _start_purchase(product_id: String) -> Dictionary:
	# Only reachable when the base class found purchases enabled AND the
	# singleton present. Transactions are finished by the plugin once the event
	# is popped; the backend decides the entitlement.
	var store: Object = _singleton()
	store.call("set_auto_finish_transaction", true)
	var outcome: Variant = store.call("purchase", {"product_id": product_id})
	if typeof(outcome) == TYPE_INT and int(outcome) != OK:
		_emit_error("purchase_not_started", "The store did not accept the request.")
		return _result(STATUS_UNAVAILABLE)
	return _result(STATUS_STARTED)


func _restore_purchases() -> Dictionary:
	if _restore_in_flight:
		return _result(STATUS_BUSY)
	_restore_in_flight = true
	_restoring = []
	_singleton().call("restore_purchases")
	return _result(STATUS_STARTED)


# -- events --------------------------------------------------------------------

func _handle_event(event: Dictionary) -> void:
	var kind: String = String(event.get("type", ""))
	match kind:
		"product_info":
			products_received.emit(_products_from(event))
		"purchase":
			_handle_purchase(event)
		"restore":
			_handle_restore(event)
		_:
			pass


func _handle_purchase(event: Dictionary) -> void:
	var result: String = String(event.get("result", ""))
	var product_id: String = String(event.get("product_id", ""))
	var transaction_id: String = String(event.get("transaction_id", ""))
	match result:
		"ok":
			purchase_updated.emit(_receipt(RECEIPT_PURCHASED, product_id, transaction_id,
					_payload_from(event)))
		"progress":
			purchase_updated.emit(_receipt(RECEIPT_PENDING, product_id, transaction_id, {}))
		"error":
			purchase_updated.emit(_receipt(RECEIPT_FAILED, product_id, transaction_id, {},
					"The purchase did not complete."))
		_:
			purchase_updated.emit(_receipt(RECEIPT_CANCELLED, product_id, transaction_id, {}))


func _handle_restore(event: Dictionary) -> void:
	var result: String = String(event.get("result", ""))
	match result:
		"ok":
			_restoring.append(_receipt(RECEIPT_PURCHASED, String(event.get("product_id", "")),
					String(event.get("transaction_id", "")), _payload_from(event)))
		"completed":
			_restore_in_flight = false
			restore_finished.emit({"status": "ok", "store": STORE_ID,
					"receipts": _restoring.duplicate(true), "message": ""})
			_restoring = []
		"error":
			_restore_in_flight = false
			restore_finished.emit({"status": "failed", "store": STORE_ID, "receipts": [],
					"message": "Restore did not complete."})
			_restoring = []
		_:
			pass


## What the backend needs to look the transaction up: the id, and the app
## receipt if the plugin supplied one. Nothing about the account.
static func _payload_from(event: Dictionary) -> Dictionary:
	var payload: Dictionary = {
		"transactionId": String(event.get("transaction_id", "")),
		"productId": String(event.get("product_id", "")),
	}
	var receipt: Variant = event.get("receipt", "")
	if typeof(receipt) == TYPE_STRING and not String(receipt).is_empty():
		payload["appReceipt"] = String(receipt)
	var signed: Variant = event.get("signed_transaction", "")
	if typeof(signed) == TYPE_STRING and not String(signed).is_empty():
		payload["signedTransaction"] = String(signed)
	return payload


## Prices come from the store, verbatim, and are shown only to a grown-up.
static func _products_from(event: Dictionary) -> Array:
	var out: Array = []
	var ids: Variant = event.get("ids", [])
	var prices: Variant = event.get("localized_prices", [])
	var currencies: Variant = event.get("currency_codes", [])
	if typeof(ids) != TYPE_ARRAY and typeof(ids) != TYPE_PACKED_STRING_ARRAY:
		return out
	var index: int = 0
	for id: Variant in ids:
		var price: String = ""
		var currency: String = ""
		if (typeof(prices) == TYPE_ARRAY or typeof(prices) == TYPE_PACKED_STRING_ARRAY) \
				and index < prices.size():
			price = String(prices[index])
		if (typeof(currencies) == TYPE_ARRAY or typeof(currencies) == TYPE_PACKED_STRING_ARRAY) \
				and index < currencies.size():
			currency = String(currencies[index])
		out.append({"productId": String(id), "available": true,
				"displayPrice": price, "currencyCode": currency})
		index += 1
	return out


func _singleton() -> Object:
	if _store != null:
		return _store
	if Engine.has_singleton(SINGLETON_NAME):
		_store = Engine.get_singleton(SINGLETON_NAME)
	return _store
