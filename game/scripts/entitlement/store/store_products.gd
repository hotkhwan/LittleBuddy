extends RefCounted

## The store product ids, and which entitlement each one is FOR. No prices.
##
## Two products, both mapping to the one paid entitlement (`familyClub`, a bigger
## daily AI-tutor allowance; see `content/tutor/quota_config.json`). The ids are
## the ones to create in App Store Connect and the Play Console
## (`docs/FAMILY_CLUB_BILLING.md`); the backend's `cloud/src/billing/config.ts`
## carries the same two strings and is the authority on what they grant.
##
## There is deliberately no price, currency or display string here. The app
## never invents a number: a store's localized price arrives from the store at
## runtime (if a gateway is ever available) and the PROPOSED price a grown-up
## reads today lives in the quota config, labelled "proposed".

const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

const FAMILY_MONTHLY: String = "little_days_family_monthly"
const FAMILY_YEARLY: String = "little_days_family_yearly"

const ALL: Array[String] = [FAMILY_MONTHLY, FAMILY_YEARLY]

## Product id -> entitlement id. Closed; anything else is not a product.
const ENTITLEMENT_FOR: Dictionary = {
	FAMILY_MONTHLY: EntitlementIds.FAMILY_CLUB,
	FAMILY_YEARLY: EntitlementIds.FAMILY_CLUB,
}


static func is_known(product_id: Variant) -> bool:
	return typeof(product_id) == TYPE_STRING and ALL.has(String(product_id))


## The entitlement a product grants, or "" for an unknown product.
static func entitlement_for(product_id: Variant) -> String:
	if not is_known(product_id):
		return ""
	return String(ENTITLEMENT_FOR[String(product_id)])


static func product_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: String in ALL:
		out.append(id)
	return out
