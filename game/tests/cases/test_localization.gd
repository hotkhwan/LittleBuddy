extends RefCounted

## The helper-line localisation service: keys, fallbacks, RTL, the shipped
## tables, and the legacy `thaiHints` bridge. No tree, no autoload.

const L10n := preload("res://scripts/localization/localization.gd")

## Every helper language must carry at least these, in its own script: the core
## of Mission 01, feeding, and the UI chrome the child and the parent see.
const CORE_KEYS: Array[String] = [
	"im_hungry", "lets_make_some_milk", "time_to_drink", "thank_you", "great",
	"try_again", "next", "home", "continue", "grown_ups", "start", "free_play",
	"dress_up", "milk", "apple", "banana", "water", "give_the_baby_the_apple",
	"peel_it", "well_done", "take_a_break", "you_can_tap_it_too",
	"music_volume", "voice_volume", "helper_language", "voice_practice",
	"go_to_bunny", "walk_to_the_kitchen", "give_bunny_the_bottle",
]


class FakeSettings:
	extends RefCounted
	var settings: Dictionary = {}

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value


func test_name() -> String:
	return "localization"


func run():
	var failures: Array = []
	L10n.clear_cache()
	failures.append_array(_test_keys_are_stable())
	failures.append_array(_test_languages_and_rtl())
	failures.append_array(_test_shipped_tables_cover_the_core())
	failures.append_array(_test_fallbacks())
	failures.append_array(_test_helper_line_rules())
	failures.append_array(_test_settings_bridge())
	failures.append_array(_test_scripts_are_really_in_their_script())
	L10n.set_helper_language(L10n.DEFAULT_HELPER_LANGUAGE)
	return failures


func _test_keys_are_stable():
	var failures: Array = []
	var cases: Dictionary = {
		"I'm hungry.": "im_hungry",
		"Give the baby the apple.": "give_the_baby_the_apple",
		"  Let's make some milk!  ": "lets_make_some_milk",
		"Grown-ups": "grown_ups",
		"Take a break?": "take_a_break",
		"Can you say milk?": "can_you_say_milk",
		"milk": "milk",
		"": "",
	}
	for english: String in cases.keys():
		var got: String = L10n.key_for(english)
		if got != String(cases[english]):
			failures.append("key_for(\"%s\") = \"%s\", expected \"%s\"" % [english, got, cases[english]])
	return failures


func _test_languages_and_rtl():
	var failures: Array = []
	var languages: Array = L10n.available_languages()
	var codes: Array = []
	for row: Dictionary in languages:
		codes.append(String(row["code"]))
		for field: String in ["code", "nativeName", "englishName", "isRtl"]:
			if not row.has(field):
				failures.append("language row %s lacks %s" % [str(row), field])
		if String(row["nativeName"]).is_empty():
			failures.append("language %s has no native name for the selector" % row["code"])
	for expected: String in ["th", "zh", "ar", "hi", "ja"]:
		if not codes.has(expected):
			failures.append("helper language %s is not offered" % expected)
	if codes.has("off"):
		failures.append("\"off\" is listed as a language; it is the absence of one")
	if not L10n.is_rtl("ar"):
		failures.append("Arabic must be flagged RTL")
	for ltr: String in ["th", "zh", "hi", "ja"]:
		if L10n.is_rtl(ltr):
			failures.append("%s is flagged RTL and is not" % ltr)
	# The current-language form.
	L10n.set_helper_language("ar")
	if not L10n.is_rtl():
		failures.append("is_rtl() with no argument must answer for the current language")
	L10n.set_helper_language("th")
	# Normalisation never lets garbage through.
	for junk in ["", "xx", "Thai", null, 3, "OFF"]:
		var got: String = L10n.normalise(junk)
		if got != "th" and got != "off":
			failures.append("normalise(%s) = %s; expected th or off" % [str(junk), got])
	if L10n.normalise("OFF") != "off" or L10n.normalise(" JA ") != "ja":
		failures.append("normalise() must be case- and whitespace-insensitive")
	return failures


func _test_shipped_tables_cover_the_core():
	var failures: Array = []
	for row: Dictionary in L10n.available_languages():
		var code: String = String(row["code"])
		if not FileAccess.file_exists(L10n.table_path(code)):
			failures.append("%s is missing" % L10n.table_path(code))
			continue
		var table: Dictionary = L10n.load_table(code)
		if table.size() < 25:
			failures.append("%s holds only %d helpers; ~25 core strings were promised" % [code, table.size()])
		for key: String in CORE_KEYS:
			if not table.has(key):
				failures.append("%s has no helper for %s" % [code, key])
			elif String(table[key]).strip_edges().is_empty():
				failures.append("%s: helper for %s is blank" % [code, key])
	return failures


func _test_fallbacks():
	var failures: Array = []
	L10n.set_helper_language("ja")
	if L10n.helper("time_to_drink", "Time to drink!") != "のむ時間だよ！":
		failures.append("ja time_to_drink = %s" % L10n.helper("time_to_drink", "Time to drink!"))
	if L10n.helper("no_such_key_anywhere", "English stays") != "English stays":
		failures.append("a missing key must return the English fallback")
	if L10n.has_helper("no_such_key_anywhere"):
		failures.append("has_helper() claims a key that does not exist")
	L10n.set_helper_language("off")
	if L10n.helper("time_to_drink", "Time to drink!") != "":
		failures.append("helper() must be empty when the helper is off")
	if not L10n.is_helper_off():
		failures.append("is_helper_off() disagrees with the language")
	# One-call override.
	if L10n.helper("great", "Great!", "hi") != "बहुत बढ़िया!":
		failures.append("the language override on helper() did not apply: %s" % L10n.helper("great", "Great!", "hi"))
	# Unknown language -> default, never an error.
	L10n.set_helper_language("klingon")
	if L10n.helper_language() != "th":
		failures.append("an unknown language must fall back to Thai, got %s" % L10n.helper_language())
	return failures


func _test_helper_line_rules():
	var failures: Array = []
	# Thai: the content author's hint wins over the table.
	L10n.set_helper_language("th")
	if L10n.helper_line("Time to drink!", "ดื่มนมกันเถอะ") != "ดื่มนมกันเถอะ":
		failures.append("for Thai the authored thaiHint must win")
	if L10n.helper_line("Great!", "") != "เยี่ยมมาก!":
		failures.append("for Thai the table fills in what content does not carry")
	# Another language ignores the Thai and uses its own table.
	L10n.set_helper_language("ar")
	var arabic: String = L10n.helper_line("Time to drink!", "ดื่มนมกันเถอะ")
	if arabic != "حان وقت الشرب!":
		failures.append("Arabic helper_line returned %s" % arabic)
	# No translation -> nothing, never the English repeated, never the Thai.
	L10n.set_helper_language("zh")
	var missing: String = L10n.helper_line("Some brand new sentence nobody translated.", "ข้อความไทย")
	if not missing.is_empty():
		failures.append("an untranslated line must show nothing, got %s" % missing)
	# Off -> nothing, even with an authored Thai hint.
	L10n.set_helper_language("off")
	if L10n.helper_line("Time to drink!", "ดื่มนมกันเถอะ") != "":
		failures.append("helper off must suppress the authored hint too")
	return failures


func _test_settings_bridge():
	var failures: Array = []
	var settings := FakeSettings.new()
	# A profile from before helperLanguage existed.
	if L10n.helper_language_from(settings) != "th":
		failures.append("an empty profile must default to Thai")
	settings.settings["thaiHints"] = false
	if L10n.helper_language_from(settings) != "off":
		failures.append("legacy thaiHints=false must read as off")
	settings.settings["thaiHints"] = true
	settings.settings["helperLanguage"] = "hi"
	if L10n.helper_language_from(settings) != "hi":
		failures.append("helperLanguage must win over thaiHints")
	# Storing keeps the legacy boolean in step and records the teaching language.
	L10n.store_helper_language(settings, "off")
	if settings.settings.get("helperLanguage") != "off" or settings.settings.get("thaiHints") != false:
		failures.append("store(off) must write helperLanguage=off AND thaiHints=false, got %s" % str(settings.settings))
	if settings.settings.get("teachingLanguage") != "en":
		failures.append("teachingLanguage must be recorded as en")
	L10n.store_helper_language(settings, "ja")
	if settings.settings.get("thaiHints") != true:
		failures.append("store(ja) must turn thaiHints back on so downstream hint readers keep working")
	if L10n.helper_language() != "ja":
		failures.append("store() must also apply the language immediately")
	if L10n.sync_from_settings(settings) != "ja":
		failures.append("sync_from_settings() must return what it applied")
	# Null-safe.
	if L10n.helper_language_from(null) != "th":
		failures.append("helper_language_from(null) must default")
	L10n.store_helper_language(null, "zh")
	if L10n.helper_language() != "zh":
		failures.append("store(null, zh) must still set the language")
	return failures


## A table claiming to be Thai must contain Thai letters, and so on: catches a
## copy-paste of one language's file over another's.
func _test_scripts_are_really_in_their_script():
	var failures: Array = []
	var ranges: Dictionary = {
		"th": [0x0E00, 0x0E7F],
		"zh": [0x4E00, 0x9FFF],
		"ar": [0x0600, 0x06FF],
		"hi": [0x0900, 0x097F],
		"ja": [0x3040, 0x30FF],
	}
	for code: String in ranges.keys():
		var table: Dictionary = L10n.load_table(code)
		var low: int = int(ranges[code][0])
		var high: int = int(ranges[code][1])
		var in_script: int = 0
		for key: String in table.keys():
			var text: String = String(table[key])
			for character: String in text:
				var point: int = character.unicode_at(0)
				if point >= low and point <= high:
					in_script += 1
					break
		if in_script < table.size() * 0.9:
			failures.append("%s: only %d of %d helpers contain the %s script" % [code, in_script, table.size(), code])
	return failures
