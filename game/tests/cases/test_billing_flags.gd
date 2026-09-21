extends RefCounted
## Purchases stay HARD-DISABLED in every committed build. Like `test_tutor_flags.gd`
## this reads the committed files, not the running settings, so a developer's
## local override can never make it green.

const BillingFlags := preload("res://scripts/entitlement/store/billing_flags.gd")
const PROJECT: String = "res://project.godot"
const PRESETS: String = "res://export_presets.cfg"
const STORE_DIR: String = "res://scripts/entitlement/store"


func test_name() -> String:
	return "billing_flags"


func run():
	var failures: Array = []
	failures.append_array(_test_committed_files())
	failures.append_array(_test_runtime_flag())
	failures.append_array(_test_no_price_in_store_code())
	return failures


func _test_committed_files():
	var failures: Array = []
	var project_text: String = _read(PROJECT)
	if not project_text.contains("billing/purchases_enabled=false"):
		failures.append("project.godot must commit little_days/billing/purchases_enabled=false")
	if project_text.contains("billing/purchases_enabled=true"):
		failures.append("project.godot enables purchases; that needs owner approval and device QA first")
	var presets_text: String = _read(PRESETS)
	for key: String in ["billing/purchases_enabled=true", BillingFlags.USER_ARG_MOCK_PURCHASES]:
		if presets_text.contains(key):
			failures.append("export_presets.cfg carries '%s'; an export must never arm purchases" % key)
	# The setting name is the one the flag reads, so the test and the code agree.
	if BillingFlags.SETTING_PURCHASES_ENABLED != "little_days/billing/purchases_enabled":
		failures.append("BillingFlags reads %s; the guarded setting is little_days/billing/purchases_enabled"
				% BillingFlags.SETTING_PURCHASES_ENABLED)
	return failures


func _test_runtime_flag():
	var failures: Array = []
	if BillingFlags.purchases_enabled():
		failures.append("BillingFlags.purchases_enabled() is true in a test run")
	if BillingFlags.mock_purchases_enabled() and not BillingFlags.mock_purchases_enabled_by_args():
		failures.append("mock purchases are enabled with no developer user arg")
	if BillingFlags.OFFLINE_CACHE_SECONDS > 7 * 24 * 3600 or BillingFlags.OFFLINE_CACHE_SECONDS < 3600:
		failures.append("OFFLINE_CACHE_SECONDS is %d; the offline grace must be bounded (1 h .. 7 d)"
				% BillingFlags.OFFLINE_CACHE_SECONDS)
	if not BillingFlags.STATUS_TEXT_UNAVAILABLE.to_lower().contains("not available"):
		failures.append("the billing status text no longer says billing is not available")
	return failures


## The store layer carries product IDS, never a price: no currency code, no
## amount, no "per month" copy. Prices live in Parent Corner and the quota
## config only (`test_entitlement_no_purchase_guard.gd`).
func _test_no_price_in_store_code():
	var failures: Array = []
	var dir: DirAccess = DirAccess.open(STORE_DIR)
	if dir == null:
		return ["%s is missing" % STORE_DIR]
	var scanned: int = 0
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		scanned += 1
		var strings: String = _strings_of(_read("%s/%s" % [STORE_DIR, file_name]))
		for fragment: String in ["THB", "USD", "$", "/ month", "per month", "/month", "2.99", "99"]:
			if strings.contains(fragment):
				failures.append("%s/%s contains the price-shaped fragment '%s'" % [STORE_DIR, file_name, fragment])
	if scanned < 6:
		failures.append("only %d store scripts were scanned; the store layer has more" % scanned)
	return failures


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


## String bodies only, comments dropped (the same technique as the guard tests).
static func _strings_of(text: String) -> String:
	var out: String = ""
	for line: String in text.split("\n"):
		var quote: String = ""
		var index: int = 0
		while index < line.length():
			var character: String = line[index]
			if quote.is_empty():
				if character == "#":
					break
				if character == "\"" or character == "'":
					quote = character
			else:
				if character == "\\":
					index += 1
				elif character == quote:
					quote = ""
					out += " "
				else:
					out += character
			index += 1
		out += "\n"
	return out
