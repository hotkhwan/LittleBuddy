extends "res://scripts/entitlement/entitlement_provider.gd"

## A DEVELOPER provider that can grant `familyClub` -- in memory, for a run.
##
## It exists so the Family Club paths (the bigger daily tutor allowance, the
## grown-up screen's "Family Club" status) can be exercised without a store, a
## receipt or a network. It is never the default: `from_environment()` returns
## one only when the game was started with the user arg `-- --dev-entitlements`,
## which no exported build's launcher passes, and tests build it directly. With
## no arg, `EntitlementService.new()` is the offline Free-Starter-only service it
## always was, and `test_entitlement_no_purchase_guard.gd` pins that.
##
## Nothing here is persisted (`trusts_cached_state()` stays false) and nothing
## here talks to a store: `grant()` is a developer typing a flag, not a purchase.

const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

const PROVIDER_ID: String = "dev"
const USER_ARG: String = "--dev-entitlements"

var _granted: Dictionary = {}


## A provider only when the developer asked for one on the command line.
static func from_environment() -> RefCounted:
	if not is_enabled_by_args():
		return null
	var script: GDScript = load("res://scripts/entitlement/dev_entitlement_provider.gd") as GDScript
	return script.new()


static func is_enabled_by_args() -> bool:
	return OS.get_cmdline_user_args().has(USER_ARG)


func provider_id() -> String:
	return PROVIDER_ID


## Free Starter, plus whatever a developer granted. Unknown ids stay unknown.
func is_active(entitlement_id: String) -> bool:
	if not EntitlementIds.is_known(entitlement_id):
		return false
	if entitlement_id == EntitlementIds.FREE_STARTER:
		return true
	return bool(_granted.get(entitlement_id, false))


## Grants a KNOWN id for this run. Returns false for anything else.
func grant(entitlement_id: String) -> bool:
	if not EntitlementIds.is_known(entitlement_id):
		return false
	_granted[entitlement_id] = true
	return true


func revoke(entitlement_id: String) -> void:
	_granted.erase(entitlement_id)


func granted_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: Variant in _granted.keys():
		if bool(_granted[id]):
			out.append(String(id))
	return out
