extends "res://scripts/entitlement/store/store_gateway.gd"

## Google Play adapter: a thin shim over the Play Billing plugin singleton.
##
## TARGET PLUGIN: godotengine/godot-google-play-billing, the Godot 4 line
## (v2.x / v3.x, wrapping Play Billing Library 6-7; the singleton name below is
## the one those releases register). Subscriptions only (`"subs"`).
##
## THE PLUGIN IS NOT IN THIS REPOSITORY, so `Engine.has_singleton()` is false in
## every current build and this adapter reports `store_unavailable`. Adding it
## to the Android export is on the activation checklist in
## `docs/FAMILY_CLUB_BILLING.md`. `purchase()` stays behind
## `little_days/billing/purchases_enabled` regardless (base class).
##
## Plugin API used (verify against the exact plugin build at activation):
##   startConnection() / endConnection() / isReady()
##   queryProductDetails(PackedStringArray ids, "subs")
##   purchase(String product_id)                 (also purchaseSubscription in v2)
##   queryPurchases("subs")
##   acknowledgePurchase(String purchase_token)
## Signals:
##   connected, disconnected, connect_error(code, message)
##   product_details_query_completed(Array products)
##   product_details_query_error(code, message, PackedStringArray ids)
##   purchases_updated(Array purchases), purchase_error(code, message)
##   query_purchases_response(Dictionary {status, purchases | debug_message})
##   purchase_acknowledged(token), purchase_acknowledgement_error(code, message, token)
## A purchase Dictionary carries `order_id`, `package_name`, `purchase_token`,
## `purchase_state` (1 = purchased, 2 = pending), `product_ids`,
## `is_acknowledged`, `signature`, `original_json`.
##
## Acknowledgement: Play refunds an unacknowledged subscription after three
## days. The backend acknowledges server side after it has verified the token
## (`cloud/src/billing/google.ts`), so this adapter never acknowledges on its own
## -- an acknowledged-but-unverified purchase would be a grant the server did not
## make.

const SINGLETON_NAME: String = "GodotGooglePlayBilling"
const STORE_ID: String = "google"
const PRODUCT_TYPE_SUBS: String = "subs"

var _billing: Object = null
var _connected: bool = false
var _wired: bool = false


func gateway_id() -> String:
	return STORE_ID


func is_available() -> bool:
	return _singleton() != null


## Opens the connection. Idempotent; the `connected` signal flips `_connected`.
func connect_to_store() -> bool:
	var billing: Object = _singleton()
	if billing == null:
		return false
	billing.call("startConnection")
	return true


func is_connected_to_store() -> bool:
	return _connected


# -- hooks ---------------------------------------------------------------------

func _query_products(product_ids: PackedStringArray) -> Dictionary:
	if not _ensure_connected():
		return _result(STATUS_UNAVAILABLE)
	_singleton().call("queryProductDetails", product_ids, PRODUCT_TYPE_SUBS)
	return _result(STATUS_STARTED)


func _start_purchase(product_id: String) -> Dictionary:
	if not _ensure_connected():
		return _result(STATUS_UNAVAILABLE)
	var outcome: Variant = _singleton().call("purchase", product_id)
	if typeof(outcome) == TYPE_DICTIONARY and int((outcome as Dictionary).get("status", 0)) != 0:
		_emit_error("purchase_not_started", String((outcome as Dictionary).get("debug_message", "")))
		return _result(STATUS_UNAVAILABLE)
	return _result(STATUS_STARTED)


func _restore_purchases() -> Dictionary:
	if not _ensure_connected():
		return _result(STATUS_UNAVAILABLE)
	_singleton().call("queryPurchases", PRODUCT_TYPE_SUBS)
	return _result(STATUS_STARTED)


# -- plugin signals ------------------------------------------------------------

func _on_connected() -> void:
	_connected = true


func _on_disconnected() -> void:
	_connected = false


func _on_connect_error(code: int, message: String) -> void:
	_connected = false
	_emit_error("connect_error_%d" % code, message)


func _on_product_details(products: Array) -> void:
	var out: Array = []
	for entry: Variant in products:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var product: Dictionary = entry
		# Subscription pricing lives in offer phases; the first phase's formatted
		# price is what the store shows, verbatim. "" when absent -- never invented.
		var price: String = ""
		var currency: String = ""
		var offers: Variant = product.get("subscription_offer_details", [])
		if typeof(offers) == TYPE_ARRAY and not (offers as Array).is_empty():
			var phases: Variant = ((offers as Array)[0] as Dictionary).get("pricing_phases", []) \
					if typeof((offers as Array)[0]) == TYPE_DICTIONARY else []
			if typeof(phases) == TYPE_ARRAY and not (phases as Array).is_empty() \
					and typeof((phases as Array)[0]) == TYPE_DICTIONARY:
				price = String(((phases as Array)[0] as Dictionary).get("formatted_price", ""))
				currency = String(((phases as Array)[0] as Dictionary).get("price_currency_code", ""))
		out.append({"productId": String(product.get("product_id", product.get("id", ""))),
				"available": true, "displayPrice": price, "currencyCode": currency})
	products_received.emit(out)


func _on_product_details_error(code: int, message: String, _ids: Variant) -> void:
	_emit_error("product_details_error_%d" % code, message)


func _on_purchases_updated(purchases: Array) -> void:
	for entry: Variant in purchases:
		if typeof(entry) == TYPE_DICTIONARY:
			purchase_updated.emit(_receipt_from(entry))


func _on_purchase_error(code: int, message: String) -> void:
	# 1 = user cancelled in the Billing Library's response codes.
	var status: String = RECEIPT_CANCELLED if code == 1 else RECEIPT_FAILED
	purchase_updated.emit(_receipt(status, "", "", {}, message))


func _on_query_purchases_response(response: Dictionary) -> void:
	var receipts: Array = []
	var ok: bool = String(response.get("status", "")) == "0" or int(response.get("status", -1)) == 0
	var purchases: Variant = response.get("purchases", [])
	if ok and typeof(purchases) == TYPE_ARRAY:
		for entry: Variant in purchases:
			if typeof(entry) == TYPE_DICTIONARY:
				receipts.append(_receipt_from(entry))
	restore_finished.emit({"status": "ok" if ok else "failed", "store": STORE_ID,
			"receipts": receipts,
			"message": "" if ok else String(response.get("debug_message", ""))})


## A Play purchase as the backend wants it: the token (what Google verifies),
## the package, the order id as a hint, and the signed original JSON.
func _receipt_from(purchase: Dictionary) -> Dictionary:
	var ids: Variant = purchase.get("product_ids", purchase.get("products", []))
	var product_id: String = ""
	if (typeof(ids) == TYPE_ARRAY or typeof(ids) == TYPE_PACKED_STRING_ARRAY) and ids.size() > 0:
		product_id = String(ids[0])
	var token: String = String(purchase.get("purchase_token", ""))
	var order_id: String = String(purchase.get("order_id", ""))
	var state: int = int(purchase.get("purchase_state", 0))
	var status: String = RECEIPT_PURCHASED if state == 1 else RECEIPT_PENDING
	return _receipt(status, product_id, order_id if not order_id.is_empty() else token, {
		"purchaseToken": token,
		"packageName": String(purchase.get("package_name", "")),
		"orderId": order_id,
		"productId": product_id,
		"originalJson": String(purchase.get("original_json", "")),
		"signature": String(purchase.get("signature", "")),
	})


func _ensure_connected() -> bool:
	if _connected:
		return true
	connect_to_store()
	if not _connected:
		_emit_error("not_connected", "The store is not connected yet; try again.")
	return _connected


func _singleton() -> Object:
	if _billing != null:
		return _billing
	if not Engine.has_singleton(SINGLETON_NAME):
		return null
	_billing = Engine.get_singleton(SINGLETON_NAME)
	_wire(_billing)
	return _billing


func _wire(billing: Object) -> void:
	if _wired or billing == null:
		return
	_wired = true
	var pairs: Array = [
		["connected", _on_connected], ["disconnected", _on_disconnected],
		["connect_error", _on_connect_error],
		["product_details_query_completed", _on_product_details],
		["product_details_query_error", _on_product_details_error],
		["purchases_updated", _on_purchases_updated], ["purchase_error", _on_purchase_error],
		["query_purchases_response", _on_query_purchases_response],
	]
	for pair: Array in pairs:
		if billing.has_signal(String(pair[0])):
			billing.connect(String(pair[0]), pair[1])
