extends RefCounted

## THE STORE GATEWAY INTERFACE: the only shape the game talks to a store through.
##
## A gateway wraps one platform's in-app purchase SDK (or a mock of one) behind
## three calls and three signals. It knows nothing about entitlements: a
## completed purchase or a restore is a RECEIPT (`store`, `productId`,
## `transactionId`, `payload`), which `purchase_flow.gd` forwards to the backend.
## The backend's answer -- and only the backend's answer -- ever becomes an
## entitlement (`store_entitlement_provider.gd`). A store callback on its own
## grants nothing; `test_store_gateway.gd` pins that.
##
## ## The hard disable lives HERE, in the base class
##
## `purchase()` is not virtual. It checks `BillingFlags` first and returns
## `{status: "disabled"}` without calling the subclass hook `_start_purchase()`,
## so no adapter can forget the rule and no adapter can be reached while
## `little_days/billing/purchases_enabled` is false (committed false). Product
## queries and restores are read-only and are allowed to be unavailable rather
## than disabled: they never charge anybody.
##
## ## Result and signal shapes (Dictionaries, camelCase, JSON-safe)
##
##   purchase()/restore_purchases()/query_products() return immediately:
##     {status: "started" | "disabled" | "unavailable" | "invalid_product" | "busy"}
##   purchase_updated(receipt):
##     {status: "purchased" | "cancelled" | "failed" | "pending",
##      store, productId, transactionId, payload: Dictionary, message}
##   restore_finished(result):
##     {status: "ok" | "failed", store, receipts: Array[receipt], message}
##   products_received(products):
##     [{productId, available: bool, displayPrice: String, currencyCode: String}]
##     (displayPrice is whatever the store said, verbatim, or "" -- never invented)
##   store_error(error):
##     {code: String, message: String, store}
##
## Adapters are RefCounted with no node; a caller that needs per-frame polling
## (the iOS plugin queues events) calls `poll()` from its own `_process`.

const BillingFlags := preload("res://scripts/entitlement/store/billing_flags.gd")
const StoreProducts := preload("res://scripts/entitlement/store/store_products.gd")

signal purchase_updated(receipt: Dictionary)
signal restore_finished(result: Dictionary)
signal products_received(products: Array)
signal store_error(error: Dictionary)

const STATUS_STARTED: String = "started"
const STATUS_DISABLED: String = "disabled"
const STATUS_UNAVAILABLE: String = "unavailable"
const STATUS_INVALID_PRODUCT: String = "invalid_product"
const STATUS_BUSY: String = "busy"

const RECEIPT_PURCHASED: String = "purchased"
const RECEIPT_CANCELLED: String = "cancelled"
const RECEIPT_FAILED: String = "failed"
const RECEIPT_PENDING: String = "pending"

const ERROR_STORE_UNAVAILABLE: String = "store_unavailable"

const STORE_MOCK: String = "mock"
const STORE_APPLE: String = "apple"
const STORE_GOOGLE: String = "google"
const STORES: Array[String] = [STORE_MOCK, STORE_APPLE, STORE_GOOGLE]


## A stable id for the receipt's `store` field and for logs.
func gateway_id() -> String:
	return "none"


## Is the platform SDK actually present and connected? False here; adapters
## answer from `Engine.has_singleton()` and their connection state.
func is_available() -> bool:
	return false


## Read-only. Emits `products_received` (or `store_error`). Never charges.
func query_products(product_ids: Array) -> Dictionary:
	var ids: PackedStringArray = _known_only(product_ids)
	if ids.is_empty():
		return _result(STATUS_INVALID_PRODUCT)
	if not is_available():
		_emit_unavailable()
		return _result(STATUS_UNAVAILABLE)
	return _query_products(ids)


## THE ONE CALL THAT COULD COST MONEY. Not overridable: the flag is checked
## before anything else, and a disabled build returns without touching the SDK.
func purchase(product_id: Variant) -> Dictionary:
	if not _purchases_enabled():
		return _result(STATUS_DISABLED)
	if not StoreProducts.is_known(product_id):
		return _result(STATUS_INVALID_PRODUCT)
	if not is_available():
		_emit_unavailable()
		return _result(STATUS_UNAVAILABLE)
	return _start_purchase(String(product_id))


## Read-only. Re-emits every receipt the store account already owns through
## `purchase_updated`-shaped entries inside `restore_finished`. Never charges.
func restore_purchases() -> Dictionary:
	if not is_available():
		_emit_unavailable()
		return _result(STATUS_UNAVAILABLE)
	return _restore_purchases()


## For adapters whose SDK queues events (iOS). No-op by default.
func poll() -> void:
	pass


# -- hooks for subclasses ------------------------------------------------------

## Real adapters read the project setting only. The mock may also honour the
## developer arg (`BillingFlags.mock_purchases_enabled()`), see its override.
func _purchases_enabled() -> bool:
	return BillingFlags.purchases_enabled()


func _query_products(_product_ids: PackedStringArray) -> Dictionary:
	return _result(STATUS_UNAVAILABLE)


func _start_purchase(_product_id: String) -> Dictionary:
	return _result(STATUS_UNAVAILABLE)


func _restore_purchases() -> Dictionary:
	return _result(STATUS_UNAVAILABLE)


# -- helpers for subclasses ----------------------------------------------------

func _result(status: String, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"status": status, "store": gateway_id()}
	for key: Variant in extra.keys():
		out[key] = extra[key]
	return out


func _receipt(status: String, product_id: String, transaction_id: String,
		payload: Dictionary, message: String = "") -> Dictionary:
	return {
		"status": status,
		"store": gateway_id(),
		"productId": product_id,
		"transactionId": transaction_id,
		"payload": payload,
		"message": message,
	}


func _emit_error(code: String, message: String) -> void:
	store_error.emit({"code": code, "message": message, "store": gateway_id()})


func _emit_unavailable() -> void:
	_emit_error(ERROR_STORE_UNAVAILABLE, "The store is not available on this device.")


static func _known_only(product_ids: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: Variant in product_ids:
		if StoreProducts.is_known(id) and not out.has(String(id)):
			out.append(String(id))
	return out
