extends RefCounted
## The daily AI-tutor allowances and the PROPOSED price, read from ONE file:
## `res://content/tutor/quota_config.json`.
##
## Nothing in gameplay hard-codes a price. The number lives here, is read only
## by the grown-up screen behind the parental gate, and is always labelled with
## its `status` ("proposed"). Allowances are seconds of ACTIVE tutor time per
## UTC day; Family Club is a bigger number, never "unlimited".
##
## Read with `FileAccess` + `JSON` (never `load()`), and every field is type
## checked and falls back to the compiled-in default, so a missing or edited
## file can only ever change a number within sane bounds -- it cannot grant an
## entitlement, and it cannot make the free allowance zero.

const CONFIG_PATH: String = "res://content/tutor/quota_config.json"

const DEFAULT_FREE_DAILY_SECONDS: int = 300
const DEFAULT_FAMILY_CLUB_DAILY_SECONDS: int = 1800
const DEFAULT_WARN_AT_SECONDS: int = 60
const DEFAULT_CLOUD_TIMEOUT_SECONDS: int = 10
## Guard rails: a config that says 0 (or a day and a half) is a typo, not a plan.
const MIN_DAILY_SECONDS: int = 60
const MAX_DAILY_SECONDS: int = 4 * 3600

const ENTITLEMENT_FREE: String = "free"
const ENTITLEMENT_FAMILY_CLUB: String = "family_club"

static var _cache: Dictionary = {}
static var _loaded: bool = false


## The whole config, sanitised. Cached after the first read.
static func load_config(force_reload: bool = false) -> Dictionary:
	if _loaded and not force_reload:
		return _cache.duplicate(true)
	var raw: Variant = _read_json(CONFIG_PATH)
	_cache = sanitise(raw)
	_loaded = true
	return _cache.duplicate(true)


## Pure: any Variant in, a complete, bounded config out. Tests feed it junk.
static func sanitise(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var out: Dictionary = {
		"freeDailySeconds": _bounded_int(source.get("freeDailySeconds", null),
				DEFAULT_FREE_DAILY_SECONDS, MIN_DAILY_SECONDS, MAX_DAILY_SECONDS),
		"familyClubDailySeconds": _bounded_int(source.get("familyClubDailySeconds", null),
				DEFAULT_FAMILY_CLUB_DAILY_SECONDS, MIN_DAILY_SECONDS, MAX_DAILY_SECONDS),
		"standardDailySeconds": _bounded_int(source.get("standardDailySeconds", source.get("freeDailySeconds", null)),
				DEFAULT_FREE_DAILY_SECONDS, MIN_DAILY_SECONDS, MAX_DAILY_SECONDS),
		"premiumLiveDailySeconds": _bounded_int(source.get("premiumLiveDailySeconds", source.get("familyClubDailySeconds", null)),
				DEFAULT_FAMILY_CLUB_DAILY_SECONDS, MIN_DAILY_SECONDS, MAX_DAILY_SECONDS),
		"warnAtSeconds": _bounded_int(source.get("warnAtSeconds", null),
				DEFAULT_WARN_AT_SECONDS, 10, 600),
		"cloudTimeoutSeconds": _bounded_int(source.get("cloudTimeoutSeconds", null),
				DEFAULT_CLOUD_TIMEOUT_SECONDS, 2, 30),
		"pricingProposed": {"currency": "", "monthly": 0, "status": "proposed"},
	}
	var pricing: Variant = source.get("pricingProposed", null)
	if typeof(pricing) == TYPE_DICTIONARY:
		var block: Dictionary = pricing
		var currency: Variant = block.get("currency", "")
		if typeof(currency) == TYPE_STRING and String(currency).length() <= 8:
			out["pricingProposed"]["currency"] = String(currency).strip_edges().to_upper()
		out["pricingProposed"]["monthly"] = _bounded_int(block.get("monthly", null), 0, 0, 100000)
		var status: Variant = block.get("status", "proposed")
		# Whatever the file says, a price this build cannot charge is "proposed".
		out["pricingProposed"]["status"] = "proposed" if typeof(status) != TYPE_STRING \
				or String(status).is_empty() else String(status)
	return out


static func free_daily_seconds() -> int:
	return int(load_config()["freeDailySeconds"])


static func family_club_daily_seconds() -> int:
	return int(load_config()["familyClubDailySeconds"])


static func standard_daily_seconds() -> int:
	return int(load_config()["standardDailySeconds"])


static func premium_live_daily_seconds() -> int:
	return int(load_config()["premiumLiveDailySeconds"])


static func warn_at_seconds() -> int:
	return int(load_config()["warnAtSeconds"])


static func cloud_timeout_seconds() -> int:
	return int(load_config()["cloudTimeoutSeconds"])


## Seconds per UTC day for an entitlement name ("free" | "family_club").
static func daily_allowance_for(entitlement: String) -> int:
	if entitlement == ENTITLEMENT_FAMILY_CLUB:
		return family_club_daily_seconds()
	return free_daily_seconds()


## `{currency, monthly, status}`. `monthly` is 0 when no price is configured.
static func pricing_proposed() -> Dictionary:
	return (load_config()["pricingProposed"] as Dictionary).duplicate(true)


## One grown-up line, "<currency> <monthly> / month (proposed)", or "" when no price is
## configured. The word "proposed" is never dropped.
static func pricing_line() -> String:
	var pricing: Dictionary = pricing_proposed()
	var monthly: int = int(pricing.get("monthly", 0))
	var currency: String = String(pricing.get("currency", ""))
	if monthly <= 0 or currency.is_empty():
		return ""
	return "%s %d / month (%s)" % [currency, monthly, String(pricing.get("status", "proposed"))]


## Tests: forget the cached file so a following read sees the disk again.
static func reset_cache() -> void:
	_cache = {}
	_loaded = false


# -- internals -----------------------------------------------------------------

static func _bounded_int(value: Variant, default_value: int, low: int, high: int) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return default_value
	if not is_finite(float(value)):
		return default_value
	return clampi(int(round(float(value))), low, high)


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text)
