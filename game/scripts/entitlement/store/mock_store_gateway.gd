extends "res://scripts/entitlement/store/store_gateway.gd"

## A DETERMINISTIC store, for tests and desktop runs. It charges nobody.
##
## Every call is recorded in `calls` so a test can prove that a disabled build
## made NO store call at all (not "a call that failed" -- none). Purchases
## succeed only when `BillingFlags.mock_purchases_enabled()` says so or a test
## opted in with `allow_purchases_for_tests`; either way the receipt it mints is
## a mock receipt (`store: "mock"`) that the backend accepts only in DEV_MODE.
## Transaction ids are sequential (`mock-txn-1`, ...), so a scripted run is
## reproducible.
##
## `script_next_purchase(status)` lets a test play a cancelled or failed
## purchase; `restore_purchases()` replays every purchase this instance made.

const STORE_ID: String = "mock"

## Set by tests only. Never read by a real adapter.
var allow_purchases_for_tests: bool = false
## Set by tests to simulate a device with no store.
var available: bool = true
## A log of every SDK-shaped call: `[{call, args}]`.
var calls: Array = []

var _purchased: Array = []
var _counter: int = 0
var _next_status: String = RECEIPT_PURCHASED


func gateway_id() -> String:
	return STORE_ID


func is_available() -> bool:
	return available


func script_next_purchase(status: String) -> void:
	_next_status = status


func purchased_receipts() -> Array:
	return _purchased.duplicate(true)


func reset() -> void:
	calls.clear()
	_purchased.clear()
	_counter = 0
	_next_status = RECEIPT_PURCHASED


# -- hooks ---------------------------------------------------------------------

func _purchases_enabled() -> bool:
	return allow_purchases_for_tests or BillingFlags.mock_purchases_enabled()


func _query_products(product_ids: PackedStringArray) -> Dictionary:
	calls.append({"call": "query_products", "args": Array(product_ids)})
	var products: Array = []
	for id: String in product_ids:
		# No invented price: a mock store has no localized price to report.
		products.append({
			"productId": id,
			"available": true,
			"displayPrice": "",
			"currencyCode": "",
		})
	products_received.emit(products)
	return _result(STATUS_STARTED)


func _start_purchase(product_id: String) -> Dictionary:
	calls.append({"call": "purchase", "args": [product_id]})
	var status: String = _next_status
	_next_status = RECEIPT_PURCHASED
	if status != RECEIPT_PURCHASED:
		purchase_updated.emit(_receipt(status, product_id, "", {}, "mock: %s" % status))
		return _result(STATUS_STARTED)
	_counter += 1
	var transaction_id: String = "mock-txn-%d" % _counter
	var receipt: Dictionary = _receipt(RECEIPT_PURCHASED, product_id, transaction_id, {
		"mock": true,
		"productId": product_id,
		"transactionId": transaction_id,
		"originalTransactionId": transaction_id,
	})
	_purchased.append(receipt)
	purchase_updated.emit(receipt)
	return _result(STATUS_STARTED)


func _restore_purchases() -> Dictionary:
	calls.append({"call": "restore_purchases", "args": []})
	restore_finished.emit({
		"status": "ok",
		"store": STORE_ID,
		"receipts": _purchased.duplicate(true),
		"message": "",
	})
	return _result(STATUS_STARTED)
