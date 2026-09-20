extends "res://scripts/entitlement/entitlement_provider.gd"

## THE FUTURE STORE PROVIDER, as a stub that grants nothing and claims nothing.
##
## This file marks where a real store integration will plug in, so the shape is
## agreed before any billing code exists. Today it:
##
##   * answers `is_active()` with Free Starter only -- there is no validated
##     receipt on this device and nothing here can create one;
##   * answers `validate_purchase()` with `status: "pending_server_validation"`,
##     ALWAYS. The client never decides an entitlement from a receipt. It
##     forwards the platform's receipt to the backend
##     (`POST /api/v1/tutor/billing/validate`, docs/ALIZ_TUTOR_API.md) and the
##     server answers with the entitlement and its expiry; until that reply
##     arrives -- and in this build it never does, because billing is disabled --
##     the answer is "pending" and the family stays on Free Starter.
##
## ## Integration points (documented, not implemented)
##
## Google Play: the Play Billing library runs in the Android host (a Godot
## plugin), hands back a purchase token + product id; this provider would wrap
## them as `{platform: "google_play", receipt: {purchaseToken, productId,
## packageName}}` and call the backend. Receipts are validated by the backend
## against Google's API, never on the device.
##
## Apple: the App Store framework runs in the iOS host (a Godot plugin), hands
## back a signed transaction; this provider would wrap it as
## `{platform: "apple", receipt: {signedTransaction, productId}}` and call the
## backend, which verifies it with Apple. Never on the device.
##
## Neither platform SDK is referenced here or anywhere else in this repository;
## `test_entitlement_no_purchase_guard.gd` scans for their identifiers and fails
## the build if one appears before that review happens. There is no child-facing
## purchase UI, and this provider must never be handed to `EntitlementService`
## as a way to pretend one succeeded: it cannot, by construction.
##
## `trusts_cached_state()` stays false until a real provider bounds a grace
## period for a receipt the server already validated; fail closed until then.

const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

const PROVIDER_ID: String = "storeStub"

const PLATFORM_GOOGLE_PLAY: String = "google_play"
const PLATFORM_APPLE: String = "apple"
const PLATFORMS: Array[String] = [PLATFORM_GOOGLE_PLAY, PLATFORM_APPLE]

## The only answer this stub gives. A real provider replaces it with the
## server's verdict -- and only the server's.
const STATUS_PENDING: String = "pending_server_validation"
const STATUS_REJECTED: String = "rejected_locally"


func provider_id() -> String:
	return PROVIDER_ID


## Free Starter only. No receipt has ever been validated for this device.
func is_active(entitlement_id: String) -> bool:
	if not EntitlementIds.is_known(entitlement_id):
		return false
	return entitlement_id == EntitlementIds.FREE_STARTER


## Where a purchase result from the platform would go. NEVER returns a success:
## `entitlement` is always empty and `status` is "pending_server_validation"
## for a well-formed request, "rejected_locally" for a malformed one (unknown
## platform, empty receipt). No network call is made in this build.
func validate_purchase(platform: String, receipt: Variant) -> Dictionary:
	var well_formed: bool = PLATFORMS.has(platform) \
			and typeof(receipt) == TYPE_DICTIONARY and not (receipt as Dictionary).is_empty()
	return {
		"status": STATUS_PENDING if well_formed else STATUS_REJECTED,
		"platform": platform,
		"entitlement": "",
		"validatedBy": "server",
		"message": "Receipts are validated by the Little Days server, never on this device. "
				+ "Billing is not available in this build.",
	}


## Nothing to sell here: the product list belongs to the server's entitlement
## reply (`products`), and even that is information for a grown-up.
func billing_available() -> bool:
	return false
