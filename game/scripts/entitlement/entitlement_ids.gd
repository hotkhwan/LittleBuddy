extends RefCounted

## The entitlement vocabulary. Two ids, and the rules for what an id may look like.
##
## An "entitlement" here is a **name for a right**, never a product, never a
## price, never a receipt. Nothing in this directory can buy anything: the whole
## layer answers exactly one question -- *is this entitlement active?* -- and a
## real store provider can be slotted in later (see `entitlement_provider.gd`)
## without a single caller changing.
##
## ## Why the id set is closed
##
## `is_known()` is the first half of failing CLOSED. A save file is a plain JSON
## document in `user://` that a curious grown-up can edit, so "any string the
## save file happens to contain is an entitlement" would be the whole
## entitlement system. Only the ids below exist, and only `FREE_STARTER` is ever
## granted by this build.
##
## ## Why FREE_STARTER is special
##
## It is the one id that is active unconditionally -- corrupt save, missing
## provider, unknown state version, no matter what. A four-year-old must never
## open the app and find the game they were playing yesterday closed to them
## because a JSON file lost a brace. Everything else fails closed; Free Starter
## fails OPEN, deliberately, and `test_entitlement_service.gd` pins both halves.

## Everything a family has without paying anything, ever. See `free_starter.gd`
## for what it contains, and `res://content/packs/free_starter.json` for the data.
const FREE_STARTER: String = "freeStarter"

## The name of the *proposed* subscription, present so the interface has a second
## id to be honest about. NOTHING IN THIS BUILD CAN GRANT IT. There is no billing
## code, no payment SDK and no purchase path anywhere in this repository
## (`test_entitlement_no_purchase_guard.gd` enforces that), so this id exists to
## be reported as inactive and to give a future store provider something to name.
const FAMILY_CLUB: String = "familyClub"

## The closed set. An id outside this list is not an entitlement, it is a typo or
## a tampered save.
const KNOWN: Array[String] = [FREE_STARTER, FAMILY_CLUB]

## The one id that is never withheld. Named rather than inlined so the rule is
## searchable from either side.
const ALWAYS_ACTIVE: String = FREE_STARTER

const MAX_ID_LENGTH: int = 64


## A plain camelCase id: letters and digits, starting with a lower-case letter.
##
## Checked before the id is ever compared or stored, so a Dictionary key, an
## array element or a pack's `entitlementId` read off disk cannot smuggle a path,
## a URL or a wildcard into the entitlement layer.
static func is_well_formed(entitlement_id: Variant) -> bool:
	if typeof(entitlement_id) != TYPE_STRING:
		return false
	var id: String = String(entitlement_id)
	if id.is_empty() or id.length() > MAX_ID_LENGTH:
		return false
	var first: String = id[0]
	if first < "a" or first > "z":
		return false
	for index: int in range(id.length()):
		var character: String = id[index]
		var is_lower: bool = character >= "a" and character <= "z"
		var is_upper: bool = character >= "A" and character <= "Z"
		var is_digit: bool = character >= "0" and character <= "9"
		if not (is_lower or is_upper or is_digit):
			return false
	return true


## True only for an id this build has heard of. Unknown means NOT entitled.
static func is_known(entitlement_id: Variant) -> bool:
	if not is_well_formed(entitlement_id):
		return false
	return KNOWN.has(String(entitlement_id))


## The known ids, as a fresh copy (`const Array` is read-only in Godot 4.7).
static func known_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: String in KNOWN:
		out.append(id)
	return out
