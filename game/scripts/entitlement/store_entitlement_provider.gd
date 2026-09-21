extends "res://scripts/entitlement/entitlement_provider.gd"

## THE STORE PROVIDER: it believes the BACKEND, and nothing else.
##
## A real store integration now has a shape (`scripts/entitlement/store/`):
## a gateway hands back a receipt, `purchase_flow.gd` posts it to
## `POST /v1/billing/verify`, and the backend answers with a DECISION:
##
##     {entitlementId: "familyClub", status: "active" | "grace" | "expired" |
##      "revoked" | "none", periodEnd: <unix s>, verifiedAt: <unix s>,
##      originalTransactionId, store, productId}
##
## `apply_backend_decision()` is the only way this provider ever grants
## anything, and it is only ever called with a decision the verify client parsed
## out of a backend reply. A store callback, a hand-edited save, a mock receipt,
## or a decision with a bad shape grants nothing. `is_active("familyClub")` is
## true only while the held decision says active-or-grace AND its `periodEnd` is
## in the future AND the backend confirmed it within
## `BillingFlags.OFFLINE_CACHE_SECONDS` (72 h). After that the family drops to
## Free Starter until the next successful verify -- bounded, never "until the
## file says otherwise".
##
## ## Persistence
##
## `export_state()` / `import_state()` round-trip the decision through
## `EntitlementService.to_dict()` (`providerState`) so a restart keeps Family
## Club without a network call, for at most those 72 hours. `trusts_cached_state()`
## stays FALSE: the service's own `active` list is never believed for this
## provider; only the re-sanitised decision, re-checked against the clock, is.
##
## ## Back-compat surface
##
## `validate_purchase()` still answers `pending_server_validation`, because that
## is still true: nothing on the device validates. `billing_available()` is true
## only when purchases are enabled in the build (they are not) AND a gateway is
## present -- so in every committed build it is false and the parent screen keeps
## saying billing is not available.

const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")
const BillingFlags := preload("res://scripts/entitlement/store/billing_flags.gd")
const StoreProducts := preload("res://scripts/entitlement/store/store_products.gd")

const PROVIDER_ID: String = "store"

const PLATFORM_GOOGLE_PLAY: String = "google_play"
const PLATFORM_APPLE: String = "apple"
const PLATFORMS: Array[String] = [PLATFORM_GOOGLE_PLAY, PLATFORM_APPLE]

const STATUS_PENDING: String = "pending_server_validation"
const STATUS_REJECTED: String = "rejected_locally"

## Decision statuses, exactly as the backend names them (cloud/src/billing).
const DECISION_ACTIVE: String = "active"
const DECISION_GRACE: String = "grace"
const DECISION_EXPIRED: String = "expired"
const DECISION_REVOKED: String = "revoked"
const DECISION_NONE: String = "none"
const DECISION_STATUSES: Array[String] = [
	DECISION_ACTIVE, DECISION_GRACE, DECISION_EXPIRED, DECISION_REVOKED, DECISION_NONE,
]
## The statuses under which the entitlement is ON.
const GRANTING_STATUSES: Array[String] = [DECISION_ACTIVE, DECISION_GRACE]

const STATE_VERSION: int = 1

var _decision: Dictionary = {}
var _gateway_available: bool = false
var _clock: Callable = Callable()


## `clock` returns unix seconds; tests inject one.
func _init(clock: Callable = Callable()) -> void:
	_clock = clock


func provider_id() -> String:
	return PROVIDER_ID


## Free Starter, plus `familyClub` while a fresh backend decision says so.
func is_active(entitlement_id: String) -> bool:
	if not EntitlementIds.is_known(entitlement_id):
		return false
	if entitlement_id == EntitlementIds.FREE_STARTER:
		return true
	if _decision.is_empty() or String(_decision.get("entitlementId", "")) != entitlement_id:
		return false
	return decision_grants(_decision, _now())


## The service's own cache is never believed for this provider. The bounded
## decision cache below is the only thing that survives a restart.
func trusts_cached_state() -> bool:
	return false


# -- the only grant path ----------------------------------------------------------

## Called by `purchase_flow.gd` with a decision the verify client parsed from
## the backend. Returns false (and changes nothing) for a malformed decision.
func apply_backend_decision(decision: Variant, now_unix: int = -1) -> bool:
	var clean: Dictionary = sanitise_decision(decision)
	if clean.is_empty():
		return false
	var now: int = now_unix if now_unix >= 0 else _now()
	# `verifiedAt` is the backend's stamp; a decision claiming to be verified in
	# the future is clamped to now so the 72 h window cannot be extended by a
	# reply with a wrong clock.
	if int(clean["verifiedAt"]) <= 0 or int(clean["verifiedAt"]) > now:
		clean["verifiedAt"] = now
	_decision = clean
	return true


## Forgets the decision (a "Delete learning history"-style reset, or a test).
func clear_decision() -> void:
	_decision = {}


## A copy of the held decision, or {}.
func decision() -> Dictionary:
	return _decision.duplicate(true)


## What the grown-up screen can print: the status of the paid entitlement.
## `{entitlementId, status, periodEnd, verifiedAt, source}`; `status` is "none"
## when nothing was ever verified, and "expired" when the decision aged out.
func subscription_status() -> Dictionary:
	if _decision.is_empty():
		return {"entitlementId": "", "status": DECISION_NONE, "periodEnd": 0, "verifiedAt": 0,
				"source": PROVIDER_ID}
	var status: String = String(_decision["status"])
	if GRANTING_STATUSES.has(status) and not decision_grants(_decision, _now()):
		status = DECISION_EXPIRED
	return {
		"entitlementId": String(_decision["entitlementId"]),
		"status": status,
		"periodEnd": int(_decision["periodEnd"]),
		"verifiedAt": int(_decision["verifiedAt"]),
		"source": PROVIDER_ID,
	}


## Purchases enabled in the build AND a store present. False in every
## committed build, whatever the device.
func billing_available() -> bool:
	return BillingFlags.purchases_enabled() and _gateway_available


func set_gateway_available(available: bool) -> void:
	_gateway_available = available


# -- persistence (through EntitlementService.to_dict()/from_dict()) --------------

func export_state() -> Dictionary:
	if _decision.is_empty():
		return {}
	return {"stateVersion": STATE_VERSION, "decision": _decision.duplicate(true)}


## Accepts only a well-formed decision; anything else leaves the provider empty.
## The clock is re-checked on every `is_active()`, so an old file cannot revive
## an expired entitlement -- it is simply an expired decision.
func import_state(raw: Variant) -> bool:
	_decision = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var source: Dictionary = raw
	if int(source.get("stateVersion", -1)) != STATE_VERSION:
		return false
	var clean: Dictionary = sanitise_decision(source.get("decision", null))
	if clean.is_empty():
		return false
	_decision = clean
	return true


# -- back-compat: the device never validates --------------------------------------

func validate_purchase(platform: String, receipt: Variant) -> Dictionary:
	var well_formed: bool = PLATFORMS.has(platform) \
			and typeof(receipt) == TYPE_DICTIONARY and not (receipt as Dictionary).is_empty()
	return {
		"status": STATUS_PENDING if well_formed else STATUS_REJECTED,
		"platform": platform,
		"entitlement": "",
		"validatedBy": "server",
		"message": "Receipts are validated by the Little Days server, never on this device. "
				+ BillingFlags.STATUS_TEXT_UNAVAILABLE,
	}


# -- pure helpers ---------------------------------------------------------------------

## A decision from the wire, checked field by field. {} when unusable. Only
## known entitlement ids, known statuses and known product ids survive; a
## decision naming a product this build does not sell is not a decision.
static func sanitise_decision(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = raw
	var entitlement_id: Variant = source.get("entitlementId", "")
	if not EntitlementIds.is_known(entitlement_id) or String(entitlement_id) == EntitlementIds.FREE_STARTER:
		return {}
	var status: Variant = source.get("status", "")
	if typeof(status) != TYPE_STRING or not DECISION_STATUSES.has(String(status)):
		return {}
	var product_id: Variant = source.get("productId", "")
	if not StoreProducts.is_known(product_id):
		return {}
	if StoreProducts.entitlement_for(product_id) != String(entitlement_id):
		return {}
	return {
		"entitlementId": String(entitlement_id),
		"status": String(status),
		"periodEnd": _int_or_zero(source.get("periodEnd", 0)),
		"verifiedAt": _int_or_zero(source.get("verifiedAt", 0)),
		"originalTransactionId": _short_string(source.get("originalTransactionId", "")),
		"store": _short_string(source.get("store", "")),
		"productId": String(product_id),
	}


## Does this decision grant its entitlement at `now`? Status must be granting,
## the period must not have ended, and the backend must have confirmed it
## within the offline cache window.
static func decision_grants(decision: Dictionary, now: int) -> bool:
	if not GRANTING_STATUSES.has(String(decision.get("status", ""))):
		return false
	var period_end: int = int(decision.get("periodEnd", 0))
	if period_end <= now:
		return false
	var verified_at: int = int(decision.get("verifiedAt", 0))
	if verified_at <= 0 or now - verified_at > BillingFlags.OFFLINE_CACHE_SECONDS:
		return false
	return true


static func _int_or_zero(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	if not is_finite(float(value)) or float(value) < 0.0:
		return 0
	return int(value)


static func _short_string(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	return String(value).left(128)


func _now() -> int:
	if _clock.is_valid():
		return int(_clock.call())
	return int(Time.get_unix_time_from_system())
