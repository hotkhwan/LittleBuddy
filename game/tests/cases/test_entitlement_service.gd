extends RefCounted

## THE ENTITLEMENT SERVICE: fails closed, and never closes the free game.
##
## Two behaviours, pulling in opposite directions, and both have to hold at once:
##
##   * **Fail CLOSED.** Anything the service cannot positively establish is a NO.
##     Unknown id, junk in the save file, no provider, a state version from a
##     later build, a cache written by a different provider: all no.
##   * **Fail OPEN for Free Starter.** Whatever else is broken, the game a family
##     already has stays open. A four-year-old must never be told the thing they
##     played yesterday is gone because a JSON file lost a brace.
##
## ## The attack that is not an attack
##
## `user://profile.json` is plain text on a device the family owns, and a parent
## with a text editor is not a threat model, they are Tuesday. So the interesting
## question is what happens when `"familyClub"` simply appears in that file. The
## answer has to be "nothing", and it has to be for a structural reason rather
## than an obfuscation one: the persisted state is a CACHE tagged with the
## provider that wrote it, and the offline provider says it does not trust a
## cache. `_test_a_hand_edited_save_grants_nothing()` is that assertion.
##
## ## Proving the seam without a store
##
## `TrustingStore` below is a fake provider: a different `provider_id()`, and
## `trusts_cached_state()` returning true, which is what a real store provider
## doing an offline grace period would look like. It exists to prove the interface
## can express a paid provider WITHOUT this build containing one -- and the
## provider-tag check is tested through it, because a cache written by
## `localOffline` must not be honoured by `fakeStore` or the other way round.
##
## Nothing in this file buys anything. There is no payment SDK in this repository.

const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")
const EntitlementService := preload("res://scripts/entitlement/entitlement_service.gd")
const LocalProvider := preload("res://scripts/entitlement/local_entitlement_provider.gd")
const BaseProvider := preload("res://scripts/entitlement/entitlement_provider.gd")
const ProfileStoreScript := preload("res://scripts/save/profile_store.gd")


## A provider that says yes to everything. Used to prove the service still
## validates ids itself rather than trusting whatever a provider is asked about.
class GenerousProvider extends RefCounted:
	func provider_id() -> String:
		return "generous"

	func is_active(_entitlement_id: String) -> bool:
		return true

	func trusts_cached_state() -> bool:
		return false


## A provider that says no to everything, including Free Starter. It must not be
## able to take the free game away.
class MeanProvider extends RefCounted:
	func provider_id() -> String:
		return "mean"

	func is_active(_entitlement_id: String) -> bool:
		return false

	func trusts_cached_state() -> bool:
		return false


## What a real store provider would look like from here: its own id, and it
## honours its own cached answer when offline. NOT a payment implementation --
## it has no purchase method, because nothing in this project does.
class TrustingStore extends RefCounted:
	var live_answer: bool = false

	func provider_id() -> String:
		return "fakeStore"

	func is_active(_entitlement_id: String) -> bool:
		return live_answer

	func trusts_cached_state() -> bool:
		return true


## An object that is not a provider at all: no methods. The service must survive
## being handed one.
class NotAProvider extends RefCounted:
	pass


## The SaveService contract this layer uses, and nothing else.
class FakeSaveService extends RefCounted:
	var settings: Dictionary = {}

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value


func test_name() -> String:
	return "entitlement_service"


func run():
	var failures: Array = []
	failures.append_array(_test_default_is_free_starter_only())
	failures.append_array(_test_unknown_is_not_entitled())
	failures.append_array(_test_the_base_provider_grants_nothing())
	failures.append_array(_test_no_provider_can_revoke_free_starter())
	failures.append_array(_test_corrupt_state_fails_closed())
	failures.append_array(_test_a_hand_edited_save_grants_nothing())
	failures.append_array(_test_the_provider_seam())
	failures.append_array(_test_it_survives_save_and_load())
	failures.append_array(_test_it_survives_the_real_profile_store())
	failures.append_array(_test_there_is_no_way_to_buy())
	return failures


# ---------------------------------------------------------------------------

func _test_default_is_free_starter_only():
	var failures: Array = []
	var service: Object = EntitlementService.new()

	if not service.is_active(EntitlementIds.FREE_STARTER):
		failures.append("a fresh service does not grant Free Starter; the free game must always be "
				+ "available with no account, no network and no save file")
	if service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append(
			"a fresh service grants familyClub. NOTHING in this build may grant it: there is no "
			+ "billing, no payment SDK and no purchase path, so a yes here could only ever be a bug "
			+ "that gives away content the offline provider was never asked about.")

	var active: PackedStringArray = service.active_ids()
	if active.size() != 1 or not active.has(EntitlementIds.FREE_STARTER):
		failures.append("active_ids() is %s; it should be exactly [freeStarter]" % str(active))
	if service.provider_id() != LocalProvider.PROVIDER_ID:
		failures.append("the default provider is '%s', expected '%s'"
				% [service.provider_id(), LocalProvider.PROVIDER_ID])
	return failures


func _test_unknown_is_not_entitled():
	var failures: Array = []
	var service: Object = EntitlementService.new()

	# Every one of these is "unknown", and unknown is a NO.
	var rubbish: Array = [
		"", " ", "familyclub", "FamilyClub", "family_club", "familyClub ",
		"freeStarter2", "*", "res://content/packs/free_starter.json",
		"https://example.com", "freeStarter\n", null, 0, 1, 3.5, [], {}, true,
		"a".repeat(EntitlementIds.MAX_ID_LENGTH + 1),
	]
	for value: Variant in rubbish:
		if service.is_active(value):
			failures.append("is_active(%s) returned true; unknown must mean NOT entitled"
					% str(value))

	# ...including the id that is always active, if it is misspelt.
	if service.is_active("freestarter"):
		failures.append("id matching is case-insensitive; 'freestarter' must not match")
	return failures


## The interface's default answer is no, so a half-written future provider grants
## nothing rather than everything.
func _test_the_base_provider_grants_nothing():
	var failures: Array = []
	var provider: Object = BaseProvider.new()
	for id: String in EntitlementIds.known_ids():
		if provider.is_active(id):
			failures.append("the base provider granted '%s'; its default must be no" % id)
	if provider.trusts_cached_state():
		failures.append("the base provider trusts a cache by default; fail closed means it must not")

	var service: Object = EntitlementService.new(provider)
	if not service.is_active(EntitlementIds.FREE_STARTER):
		failures.append("with the do-nothing base provider installed, Free Starter was withheld")
	if service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the base provider granted familyClub through the service")
	return failures


## Rule 2 is enforced by the SERVICE, above every provider, so no provider -- mean,
## broken, or not a provider at all -- can close the free game.
func _test_no_provider_can_revoke_free_starter():
	var failures: Array = []
	for provider: Object in [MeanProvider.new(), NotAProvider.new(), BaseProvider.new()]:
		var service: Object = EntitlementService.new(provider)
		if not service.is_active(EntitlementIds.FREE_STARTER):
			failures.append("provider %s was able to revoke Free Starter" % provider.get_class())

	# And a provider that says yes to everything still cannot invent an id.
	var generous: Object = EntitlementService.new(GenerousProvider.new())
	if generous.is_active("bananaClub"):
		failures.append("a permissive provider was asked about an id this build does not know; the "
				+ "service must reject unknown ids before any provider sees them")
	if not generous.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a provider that grants familyClub was not believed; the seam is broken")
	return failures


func _test_corrupt_state_fails_closed():
	var failures: Array = []
	var corrupt: Array = [
		null, "", "not a dictionary", 42, [], [1, 2, 3],
		{},
		{"stateVersion": "one", "providerId": "localOffline", "active": ["familyClub"]},
		{"stateVersion": 99, "providerId": "localOffline", "active": ["familyClub"]},
		{"stateVersion": 1, "active": ["familyClub"]},
		{"stateVersion": 1, "providerId": "", "active": ["familyClub"]},
		{"stateVersion": 1, "providerId": 7, "active": ["familyClub"]},
		{"stateVersion": 1, "providerId": "localOffline", "active": "familyClub"},
		{"stateVersion": 1, "providerId": "localOffline", "active": [null, 3, {}, "nope"]},
	]
	for state: Variant in corrupt:
		var service: Object = EntitlementService.new()
		service.from_dict(state)
		if service.is_active(EntitlementIds.FAMILY_CLUB):
			failures.append("corrupt state %s granted familyClub" % str(state))
		if not service.is_active(EntitlementIds.FREE_STARTER):
			failures.append(
				("corrupt state %s took Free Starter away. Corruption must never close the game a "
				+ "child already has -- that is the one rule in this layer that fails OPEN.")
				% str(state))
	return failures


## The save file is editable, and editing it must achieve nothing.
func _test_a_hand_edited_save_grants_nothing():
	var failures: Array = []
	var save: Object = FakeSaveService.new()
	# Exactly what a parent with a text editor would write: the right shape, the
	# right provider tag, the extra entitlement.
	save.settings[EntitlementService.SETTING_KEY] = {
		"stateVersion": EntitlementService.STATE_VERSION,
		"providerId": LocalProvider.PROVIDER_ID,
		"active": [EntitlementIds.FREE_STARTER, EntitlementIds.FAMILY_CLUB],
	}
	var service: Object = EntitlementService.new()
	service.load_from(save)

	if service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append(
			"a hand-edited profile granted familyClub. The persisted state is a CACHE, and the "
			+ "offline provider reports trusts_cached_state() == false precisely so that editing "
			+ "user://profile.json cannot become the purchase path this build does not have.")
	if not service.is_active(EntitlementIds.FREE_STARTER):
		failures.append("a hand-edited profile broke Free Starter")
	return failures


## The seam a real store provider would use, exercised with a fake one.
func _test_the_provider_seam():
	var failures: Array = []

	# A live yes from the provider is believed.
	var store: Object = TrustingStore.new()
	store.live_answer = true
	var service: Object = EntitlementService.new(store)
	if not service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a provider's live yes was ignored; a real store could not be slotted in")

	# Its own cache is believed when it says it trusts it...
	store.live_answer = false
	var cached: Object = EntitlementService.new(store)
	cached.from_dict({
		"stateVersion": EntitlementService.STATE_VERSION,
		"providerId": "fakeStore",
		"active": [EntitlementIds.FAMILY_CLUB],
	})
	if not cached.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a trusting provider's own cache was not honoured; an offline grace period "
				+ "would be impossible to implement without changing the service")

	# ...and a cache written by a DIFFERENT provider never is.
	var foreign: Object = EntitlementService.new(store)
	foreign.from_dict({
		"stateVersion": EntitlementService.STATE_VERSION,
		"providerId": LocalProvider.PROVIDER_ID,
		"active": [EntitlementIds.FAMILY_CLUB],
	})
	if foreign.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a cache tagged 'localOffline' was honoured by 'fakeStore'; the provider tag "
				+ "is what stops one provider's answers being read as another's")

	# Swapping the provider drops the cache: it was about somebody else.
	cached.set_provider(LocalProvider.new())
	if cached.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the cache survived a provider swap")
	if cached.provider_id() != LocalProvider.PROVIDER_ID:
		failures.append("set_provider() did not take effect")

	# null means "back to the offline default", not "no provider".
	cached.set_provider(null)
	if cached.provider_id() != LocalProvider.PROVIDER_ID:
		failures.append("set_provider(null) left the service without the offline default")
	if not cached.is_active(EntitlementIds.FREE_STARTER):
		failures.append("set_provider(null) broke Free Starter")
	return failures


func _test_it_survives_save_and_load():
	var failures: Array = []
	var save: Object = FakeSaveService.new()

	var writer: Object = EntitlementService.new()
	if not writer.save_to(save):
		failures.append("save_to() reported failure with a working save service")
	var stored: Variant = save.settings.get(EntitlementService.SETTING_KEY, null)
	if typeof(stored) != TYPE_DICTIONARY:
		failures.append("nothing usable was written under settings.%s"
				% EntitlementService.SETTING_KEY)
		return failures
	if int((stored as Dictionary).get("stateVersion", -1)) != EntitlementService.STATE_VERSION:
		failures.append("the stored state has no/incorrect stateVersion")
	if String((stored as Dictionary).get("providerId", "")) != LocalProvider.PROVIDER_ID:
		failures.append("the stored state is not tagged with the provider that wrote it")
	if not (stored as Dictionary).get("active", []).has(EntitlementIds.FREE_STARTER):
		failures.append("the stored state does not record Free Starter as active")

	var reader: Object = EntitlementService.new()
	if not reader.load_from(save):
		failures.append("load_from() rejected state that save_to() had just written; the round trip "
				+ "is broken")
	if not reader.is_active(EntitlementIds.FREE_STARTER):
		failures.append("Free Starter did not survive the round trip")
	if reader.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("familyClub appeared after a round trip")

	# No save service at all is survivable, and grants the free tier anyway.
	var orphan: Object = EntitlementService.new()
	if orphan.load_from(null) or orphan.save_to(null):
		failures.append("load_from(null)/save_to(null) should report false, not succeed")
	if not orphan.is_active(EntitlementIds.FREE_STARTER):
		failures.append("with no save service, Free Starter was withheld")

	# An object that is not a save service must not crash it either.
	if orphan.load_from(NotAProvider.new()):
		failures.append("load_from() accepted an object with no get_setting()")
	return failures


## The real store, the real file, the real sanitiser. `ProfileStore` preserves
## unknown JSON-safe `settings` keys -- this proves it, because the whole
## persistence design rests on it and it is not this layer's code.
func _test_it_survives_the_real_profile_store():
	var failures: Array = []
	var path: String = "user://test_entitlement_%d.json" % randi()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var store: Object = ProfileStoreScript.new(path)
	var profile: Dictionary = store.default_profile()
	var service: Object = EntitlementService.new()
	(profile["settings"] as Dictionary)[EntitlementService.SETTING_KEY] = service.to_dict()
	if not store.save_profile(profile):
		failures.append("could not write the test profile to %s" % path)
		return failures

	var loaded: Dictionary = store.load_profile()
	var settings: Variant = loaded.get("settings", null)
	if typeof(settings) != TYPE_DICTIONARY:
		failures.append("the reloaded profile has no settings block")
		DirAccess.remove_absolute(path)
		return failures
	var state: Variant = (settings as Dictionary).get(EntitlementService.SETTING_KEY, null)
	if typeof(state) != TYPE_DICTIONARY:
		failures.append(
			("settings.%s did not survive ProfileStore's sanitiser. The entitlement cache is stored "
			+ "as an unknown-but-JSON-safe settings key precisely so that no profile schema change "
			+ "or migration is needed; if that stopped being true, this layer needs a real home in "
			+ "the profile and profile_store.gd has to grant it one.") % EntitlementService.SETTING_KEY)
	else:
		var reader: Object = EntitlementService.new()
		if not reader.from_dict(state):
			failures.append("the state that came back out of the real profile was not accepted")
		if not reader.is_active(EntitlementIds.FREE_STARTER):
			failures.append("Free Starter did not survive a real save/load cycle")
		if reader.is_active(EntitlementIds.FAMILY_CLUB):
			failures.append("familyClub appeared after a real save/load cycle")

	DirAccess.remove_absolute(path)
	return failures


## The service exposes no way to buy, and says so when asked.
func _test_there_is_no_way_to_buy():
	var failures: Array = []
	var service: Object = EntitlementService.new()
	for method: String in ["purchase", "buy", "subscribe", "restore_purchases", "start_purchase",
			"get_price", "get_products", "show_paywall"]:
		if service.has_method(method):
			failures.append("EntitlementService has a %s() method. This build must have no purchase "
					% method + "path of any kind.")
	var described: Dictionary = service.describe()
	if bool(described.get("purchasingAvailable", true)):
		failures.append("describe() claims purchasing is available; it is not, and no code exists "
				+ "that could make it so")
	if described.has("price") or described.has("receipt") or described.has("productId"):
		failures.append("describe() carries a price, a receipt or a product id; none of those "
				+ "concepts exist in this build")
	return failures
