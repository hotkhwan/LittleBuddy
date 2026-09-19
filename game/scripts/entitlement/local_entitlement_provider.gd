extends "res://scripts/entitlement/entitlement_provider.gd"

## The default provider, and the only one that exists: offline, local, free.
##
## It grants the Free Starter entitlement and **nothing else**, to everybody,
## forever, with no account, no receipt, no network call and no way to change its
## answer. `is_active("familyClub")` is `false` here and there is no code path in
## this repository that can make it true -- that is not an oversight, it is the
## deliverable. This build cannot sell anything.
##
## ## Why it is a class and not three lines inline
##
## Because the shape is the product decision. When a store provider is written it
## will sit beside this file, implement the same three methods, and be handed to
## `EntitlementService.set_provider()` at startup -- one line, in one place, and
## every caller in the game keeps working unchanged. Writing the free case inline
## as `if id == "freeStarter"` scattered through the callers is exactly the design
## that makes that impossible later.
##
## ## It never trusts a cache
##
## `trusts_cached_state()` stays `false` (inherited). This provider recomputes its
## answer from compiled-in data in microseconds, so a cache buys nothing -- and
## believing one would mean a hand-edited `user://profile.json` could grant
## `familyClub`. Fail closed.

const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

const PROVIDER_ID: String = "localOffline"


func provider_id() -> String:
	return PROVIDER_ID


## Free Starter: yes. Everything else: no.
##
## Note the id is validated before it is compared, so a tampered save or a
## malformed pack cannot match by way of an odd string.
func is_active(entitlement_id: String) -> bool:
	if not EntitlementIds.is_known(entitlement_id):
		return false
	return entitlement_id == EntitlementIds.FREE_STARTER
