extends RefCounted

## THE PROVIDER INTERFACE. Three methods, one question, no billing.
##
## This is the seam. Callers never talk to a provider directly -- they ask
## `EntitlementService` -- and a provider answers exactly one thing:
##
##     is_active(entitlement_id) -> bool
##
## That is the entire contract, and it is deliberately smaller than "what can
## this family buy", "what does it cost", "what is their receipt" or "restore
## purchases". A question this narrow is why a real store provider can be added
## later as one new file, implementing these three methods, with **no caller
## changing**: a call site that only ever asked "is this active?" cannot care how
## the answer was reached.
##
## ## The base class answers NO
##
## `is_active()` returns `false` here, for every id. A subclass that forgets to
## override it therefore grants nothing -- the safe direction. There is no
## "unknown" and no "maybe": unknown is not entitled. (Free Starter is handled one
## level up, in the service, precisely so that no provider -- including a broken
## or half-written future one -- can take it away from a child.)
##
## ## `trusts_cached_state()` and why it defaults to false
##
## `EntitlementService` can persist its last answers into the local profile so
## they survive a restart. Whether that cache may be BELIEVED is the provider's
## decision, not the service's, because it is the provider that knows where the
## truth lives:
##
##   * an offline provider that already computes the answer from local data has
##     nothing to gain from a cache and everything to lose -- believing it would
##     turn "edit `user://profile.json`" into a purchase path. So: `false`.
##   * a future store provider, which cannot reach a receipt server on a plane,
##     might honour its own cached receipt for a grace period. So: `true`, and it
##     is that provider's job to bound it.
##
## Defaulting to `false` means the fail-closed behaviour is what you get by
## saying nothing, which is the only default worth having here.
##
## ## What a provider must never do
##
## No network. No file writes. No payment SDK, no StoreKit, no Play Billing, no
## price fetch, no product list, no "buy" of any kind. There is no such code in
## this repository and `test_entitlement_no_purchase_guard.gd` fails the build if
## any appears.


## A stable, human-readable id for this provider, used to tag the persisted cache
## so a cache written by one provider is never read by a different one.
func provider_id() -> String:
	return "none"


## The one question. Returns false for everything; a subclass overrides.
##
## Must be total and side-effect free: any input, an answer, no exceptions, no
## blocking, no I/O. It is called from UI code.
func is_active(_entitlement_id: String) -> bool:
	return false


## May `EntitlementService` believe its own persisted cache for this provider?
## False by default -- see the class comment.
func trusts_cached_state() -> bool:
	return false
