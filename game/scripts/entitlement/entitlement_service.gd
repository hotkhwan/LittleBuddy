extends RefCounted

## THE ONLY THING CALLERS TOUCH. One question: `is_active(entitlement_id)`.
##
##     var entitlements := EntitlementServiceScript.new()          # offline default
##     if entitlements.is_active(EntitlementIds.FAMILY_CLUB): ...  # false in this build
##
## The provider behind it is swappable (`set_provider()`); the question is not.
## Everything else here -- persistence, sanitising, the provider tag -- exists to
## make that one answer trustworthy across a restart and a corrupt file.
##
## ## The three rules, in the order they are applied
##
##   1. **Unknown is not entitled.** An id this build has never heard of, a
##      non-String, an empty String, a path, a URL: `false`. No exceptions.
##   2. **Free Starter is always active.** Before the provider is even asked. No
##      provider, no save file, no state version and no amount of corruption can
##      close the game a child was already playing. This is the single fail-OPEN
##      rule in the layer and it is here rather than in a provider so that no
##      provider can override it.
##   3. **Everything else is the provider's answer** -- plus, only if the provider
##      says it trusts its own cache, the persisted cache. The offline provider
##      says it does not, so in this build rule 3 is always "no".
##
## ## Persistence: a cache, not a grant
##
## `to_dict()`/`from_dict()` round-trip through the local profile under
## `settings.entitlements` (`ProfileStore` preserves unknown JSON-safe settings
## keys, so this needs no schema change and no migration). What is stored is a
## *cache tagged with the provider that wrote it*, and it is believed only when
## the provider in use is the same one AND that provider opted into trusting it.
##
## That is what stops the obvious attack, which is not an attack so much as an
## afternoon: `user://profile.json` is plain text on a device a determined parent
## owns. Adding `"familyClub"` to it grants nothing, because the provider that
## would have to confirm it says it does not trust the file. Tested.
##
## ## No billing. At all.
##
## There is no payment SDK, no StoreKit, no Play Billing, no price lookup, no
## product id, no receipt validation and no purchase call anywhere in this
## directory or this repository. Prices are shown to a PARENT as information, in
## Parent Corner, behind the parental gate, and cannot be acted on in this build.
## See `docs/FAMILY_CLUB.md` and `test_entitlement_no_purchase_guard.gd`.
##
## PURE. RefCounted, no 3D types, no network. The save service is duck-typed and
## optional, exactly like `parent_settings_model.gd`, so this works in a test run
## and a scene preview with no autoloads at all.

const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")
const LocalProviderScript := preload("res://scripts/entitlement/local_entitlement_provider.gd")
const DevProviderScript := preload("res://scripts/entitlement/dev_entitlement_provider.gd")

## Where the cache lives inside the profile's `settings` block. A single
## JSON-safe Dictionary, so `ProfileStore` carries it through untouched.
const SETTING_KEY: String = "entitlements"

## Bumped only if the cache's shape changes. A state version this build does not
## recognise is discarded rather than guessed at -- unknown is not entitled.
const STATE_VERSION: int = 1

const FIELD_VERSION: String = "stateVersion"
const FIELD_PROVIDER: String = "providerId"
const FIELD_ACTIVE: String = "active"

var _provider: Object = null
## The sanitised cache as loaded/last saved. Never consulted unless the provider
## in use says it trusts it (see `_cache_says_active()`).
var _cache: Dictionary = {}


## Defaults to the offline provider, so `EntitlementServiceScript.new()` is a
## complete, working, free-tier-granting service with no wiring.
func _init(provider: Object = null) -> void:
	set_provider(provider)
	_cache = _empty_state()


## Swap the provider. `null` restores the offline default rather than leaving the
## service without one -- a service with no provider would answer "no" to
## everything except Free Starter, which is survivable but is not what any caller
## of `set_provider(null)` means.
##
## The cache is dropped on a swap: it was tagged with the previous provider and is
## no longer about anybody.
func set_provider(provider: Object = null) -> void:
	_provider = provider if provider != null else default_provider()
	_cache = _empty_state()


## The provider a bare `new()` gets: the offline Free-Starter-only one -- unless
## the game was started with `-- --dev-entitlements`, in which case the in-memory
## developer provider (`dev_entitlement_provider.gd`), which can be told to grant
## `familyClub` for that run so the Family Club paths can be exercised. No
## exported build passes that arg, and no test run does either.
static func default_provider() -> Object:
	var dev: Object = DevProviderScript.from_environment()
	return dev if dev != null else LocalProviderScript.new()


func provider_id() -> String:
	if _provider != null and _provider.has_method("provider_id"):
		return String(_provider.call("provider_id"))
	return "none"


## THE question. Total, side-effect free, safe to call from UI every frame.
func is_active(entitlement_id: Variant) -> bool:
	# Rule 1: unknown is not entitled.
	if not EntitlementIds.is_known(entitlement_id):
		return false
	var id: String = String(entitlement_id)

	# Rule 2: the child is never locked out of what they already have.
	if id == EntitlementIds.ALWAYS_ACTIVE:
		return true

	# Rule 3: the provider's answer, then -- only if it opted in -- its cache.
	if _provider != null and _provider.has_method("is_active"):
		if bool(_provider.call("is_active", id)):
			return true
	return _cache_says_active(id)


## Every active id, cheapest honest implementation: ask about each known id.
## Used by `to_dict()` and by Parent Corner's read-only summary.
func active_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: String in EntitlementIds.KNOWN:
		if is_active(id):
			out.append(id)
	return out


# -- persistence ---------------------------------------------------------------

## The cache to store, tagged with the provider that computed it.
func to_dict() -> Dictionary:
	var active: Array = []
	for id: String in active_ids():
		active.append(id)
	return {
		FIELD_VERSION: STATE_VERSION,
		FIELD_PROVIDER: provider_id(),
		FIELD_ACTIVE: active,
	}


## Restores a cache, discarding anything that is not exactly the right shape.
##
## Returns true when a usable cache was accepted. A `false` return is not an
## error worth reporting to a parent: the service is fully functional without a
## cache, it simply has nothing extra to believe.
func from_dict(raw: Variant) -> bool:
	_cache = _empty_state()
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var source: Dictionary = raw

	var version: Variant = source.get(FIELD_VERSION, null)
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return false
	if int(version) != STATE_VERSION:
		return false

	var written_by: Variant = source.get(FIELD_PROVIDER, null)
	if typeof(written_by) != TYPE_STRING or String(written_by).is_empty():
		return false

	var active: Array = []
	var raw_active: Variant = source.get(FIELD_ACTIVE, null)
	if typeof(raw_active) == TYPE_ARRAY:
		for entry: Variant in (raw_active as Array):
			# Every id is validated individually: one junk entry drops itself, not
			# the whole cache, and an unknown id is dropped rather than stored.
			if EntitlementIds.is_known(entry) and not active.has(String(entry)):
				active.append(String(entry))

	_cache = {
		FIELD_VERSION: STATE_VERSION,
		FIELD_PROVIDER: String(written_by),
		FIELD_ACTIVE: active,
	}
	return true


## Reads the cache out of a duck-typed save service (the `SaveService` autoload,
## or any object with `get_setting`). Missing or junk data is simply no cache.
func load_from(save_service: Object) -> bool:
	if save_service == null or not save_service.has_method("get_setting"):
		_cache = _empty_state()
		return false
	return from_dict(save_service.call("get_setting", SETTING_KEY, {}))


## Writes the cache into a duck-typed save service. Writes ONE settings key and
## never touches stars, levels or any other part of the profile.
func save_to(save_service: Object) -> bool:
	if save_service == null or not save_service.has_method("set_setting"):
		return false
	var state: Dictionary = to_dict()
	save_service.call("set_setting", SETTING_KEY, state)
	_cache = state.duplicate(true)
	return true


## Read-only snapshot for Parent Corner and for a device with no console. Flags
## and ids only -- there is no receipt, no account and no price in here.
func describe() -> Dictionary:
	return {
		"providerId": provider_id(),
		"active": active_ids(),
		"trustsCachedState": _provider != null
				and _provider.has_method("trusts_cached_state")
				and bool(_provider.call("trusts_cached_state")),
		"purchasingAvailable": false,  # nothing in this build can buy anything
	}


# -- internals -----------------------------------------------------------------

func _empty_state() -> Dictionary:
	return {
		FIELD_VERSION: STATE_VERSION,
		FIELD_PROVIDER: "",
		FIELD_ACTIVE: [],
	}


## The cache is believed only when the provider in use both opted in and is the
## same provider that wrote it.
func _cache_says_active(entitlement_id: String) -> bool:
	if _provider == null or not _provider.has_method("trusts_cached_state"):
		return false
	if not bool(_provider.call("trusts_cached_state")):
		return false
	if String(_cache.get(FIELD_PROVIDER, "")) != provider_id():
		return false
	var active: Variant = _cache.get(FIELD_ACTIVE, [])
	if typeof(active) != TYPE_ARRAY:
		return false
	return (active as Array).has(entitlement_id)
