class_name Localization
extends RefCounted
## The helper line, in the family's language.
##
##     Localization.set_helper_language("ja")
##     Localization.helper("time_to_drink", "Time to drink!")   # -> "のむ時間だよ！"
##     Localization.helper_line("Time to drink!", "ดื่มนมกันเถอะ") # -> same, by English text
##     Localization.is_rtl("ar")                                  # -> true
##
## ## What is, and is not, localised
##
## The game TEACHES English. The top line -- the prompt, the word, the
## encouragement -- is always English and is never touched by this file. The
## second, smaller line is the helper: a translation in the language the
## grown-up chose, Thai by default, or nothing at all when the helper is off.
##
## ## Keys
##
## Every helper is keyed by a stable string derived from the English source text
## (`key_for("Give the baby the apple.")` -> `give_the_baby_the_apple`). Deriving
## the key from the English means every existing call site that already passes
## English -- `set_prompt(english, thai)`, `show_word(word, thai)` -- gets a
## helper in any language with no id plumbing, and content JSON needs no new
## field. A caller that has a better key (a taskId, a promptId) may pass it
## directly to `helper()`.
##
## The Thai `thaiHint` / `thaiTitle` / `thai` fields in the content JSON are NOT
## replaced: for Thai, a hint the content author wrote wins over the table, and
## the table only fills in what content does not carry (UI chrome, encouragement).
##
## ## Engine-agnostic, no autoload
##
## Static, `RefCounted`, no `Node`, no 3D type, no `SaveService` reference. The
## current language is a static field set by whoever owns the setting (the
## parent settings model, the HUD on refresh via `sync_from_settings()`), and
## the tables are plain JSON under `res://content/localization/`. A test drives
## it with no tree at all.
##
## ## Fonts
##
## The project ships no font of its own: Godot's default font has
## `allow_system_fallback` on, so Thai, CJK, Arabic and Devanagari come from the
## OS font set -- present on every iPad and every Mac. That is verified by the
## rendered frames in `docs/shots/` (see the audio/settings pass report), not
## assumed: a language is listed in `LANGUAGES` only once a frame has shown its
## script rendering rather than as tofu.

const CONTENT_DIR: String = "res://content/localization"
const FILE_PATTERN: String = "helpers_%s.json"

## Setting keys (camelCase, in `settings` of the profile).
const SETTING_HELPER_LANGUAGE: String = "helperLanguage"
const SETTING_TEACHING_LANGUAGE: String = "teachingLanguage"
## The legacy boolean this supersedes. Still written, so every existing reader
## of `thaiHints` (level director, free play, baby room) keeps working:
## `helperLanguage == "off"` <=> `thaiHints == false`.
const SETTING_THAI_HINTS: String = "thaiHints"

const HELPER_OFF: String = "off"
const DEFAULT_HELPER_LANGUAGE: String = "th"
const TEACHING_LANGUAGE: String = "en"

## Every helper language the selector offers, in display order.
## `code` is what is persisted; `nativeName` is what the selector shows.
const LANGUAGES: Array[Dictionary] = [
	{"code": "th", "nativeName": "ไทย", "englishName": "Thai", "isRtl": false},
	{"code": "zh", "nativeName": "中文", "englishName": "Chinese (Simplified)", "isRtl": false},
	{"code": "ar", "nativeName": "العربية", "englishName": "Arabic", "isRtl": true},
	{"code": "hi", "nativeName": "हिन्दी", "englishName": "Hindi", "isRtl": false},
	{"code": "ja", "nativeName": "日本語", "englishName": "Japanese", "isRtl": false},
]

static var _language: String = DEFAULT_HELPER_LANGUAGE
static var _tables: Dictionary = {}


# -----------------------------------------------------------------------------
# Languages
# -----------------------------------------------------------------------------


## `[{code, nativeName, englishName, isRtl}, ...]`, copies, in selector order.
## "off" is not a language and is not listed; the selector adds it itself.
static func available_languages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in LANGUAGES:
		out.append(row.duplicate())
	return out


static func is_supported(code: String) -> bool:
	return not _row_for(code).is_empty()


static func is_rtl(code: String = "") -> bool:
	var row: Dictionary = _row_for(code if not code.is_empty() else _language)
	return bool(row.get("isRtl", false))


static func native_name(code: String) -> String:
	return String(_row_for(code).get("nativeName", ""))


static func _row_for(code: String) -> Dictionary:
	for row: Dictionary in LANGUAGES:
		if String(row["code"]) == code:
			return row
	return {}


## Normalises anything a profile might hold into a code this file understands.
## Unknown or empty -> the default (Thai); "off" stays "off".
static func normalise(code: Variant) -> String:
	if typeof(code) != TYPE_STRING:
		return DEFAULT_HELPER_LANGUAGE
	var value: String = String(code).strip_edges().to_lower()
	if value == HELPER_OFF:
		return HELPER_OFF
	if is_supported(value):
		return value
	return DEFAULT_HELPER_LANGUAGE


# -----------------------------------------------------------------------------
# Current language
# -----------------------------------------------------------------------------


## Sets the helper language for every caller from now on. Takes effect on the
## next `helper()` call -- the HUD re-reads on every prompt, so a change in the
## settings screen is visible on the very next line with no restart.
static func set_helper_language(code: String) -> void:
	_language = normalise(code)


static func helper_language() -> String:
	return _language


static func is_helper_off() -> bool:
	return _language == HELPER_OFF


## Reads the helper language out of a settings-holding object (`SaveService` or
## anything with `get_setting(key, default)`), honouring a profile written before
## `helperLanguage` existed: such a profile has only `thaiHints`, and
## `thaiHints == false` means "off". Never touches the object otherwise.
static func helper_language_from(settings: Object) -> String:
	if settings == null or not settings.has_method("get_setting"):
		return DEFAULT_HELPER_LANGUAGE
	var stored: Variant = settings.call("get_setting", SETTING_HELPER_LANGUAGE, null)
	if typeof(stored) == TYPE_STRING and not String(stored).is_empty():
		return normalise(stored)
	var thai: Variant = settings.call("get_setting", SETTING_THAI_HINTS, true)
	if typeof(thai) == TYPE_BOOL and not bool(thai):
		return HELPER_OFF
	return DEFAULT_HELPER_LANGUAGE


## `set_helper_language(helper_language_from(settings))`. Returns the language.
static func sync_from_settings(settings: Object) -> String:
	set_helper_language(helper_language_from(settings))
	return _language


## Writes the choice to a settings-holding object (`set_setting(key, value)`),
## keeping the legacy `thaiHints` boolean in step so nothing downstream changes.
static func store_helper_language(settings: Object, code: String) -> void:
	var value: String = normalise(code)
	set_helper_language(value)
	if settings == null or not settings.has_method("set_setting"):
		return
	settings.call("set_setting", SETTING_HELPER_LANGUAGE, value)
	settings.call("set_setting", SETTING_THAI_HINTS, value != HELPER_OFF)
	settings.call("set_setting", SETTING_TEACHING_LANGUAGE, TEACHING_LANGUAGE)


# -----------------------------------------------------------------------------
# Lookup
# -----------------------------------------------------------------------------


## The stable key for an English source string:
## lower-case, apostrophes dropped, every other run of non-alphanumerics -> "_".
##   "I'm hungry."            -> "im_hungry"
##   "Give the baby the apple." -> "give_the_baby_the_apple"
static func key_for(english: String) -> String:
	var text: String = english.strip_edges().to_lower()
	text = text.replace("'", "").replace("’", "")
	var out: String = ""
	var last_underscore: bool = true
	for character: String in text:
		var code: int = character.unicode_at(0)
		var alnum: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if alnum:
			out += character
			last_underscore = false
		elif not last_underscore:
			out += "_"
			last_underscore = true
	return out.trim_suffix("_")


## The helper for `key` in the current language, or `english_fallback` when the
## language has no entry. Returns "" when the helper is off.
##
## `language` overrides the current language for one call.
static func helper(key: String, english_fallback: String = "", language: String = "") -> String:
	var code: String = normalise(language) if not language.is_empty() else _language
	if code == HELPER_OFF:
		return ""
	var table: Dictionary = _table(code)
	if table.has(key):
		return String(table[key])
	return english_fallback


## True when the current (or given) language has its own words for `key`.
static func has_helper(key: String, language: String = "") -> bool:
	var code: String = normalise(language) if not language.is_empty() else _language
	if code == HELPER_OFF:
		return false
	return _table(code).has(key)


## The second line for a prompt whose English is `english` and whose content
## row carried `thai_hint` (may be empty). This is what the HUD calls.
##
##   * helper off               -> ""
##   * Thai                     -> the content's own hint when it has one, else the table
##   * any other language       -> the table entry for `key_for(english)`, else ""
##
## It never returns the English again: a helper line identical to the teaching
## line is noise, not help, so "no translation" shows nothing.
static func helper_line(english: String, thai_hint: String = "", language: String = "") -> String:
	var code: String = normalise(language) if not language.is_empty() else _language
	if code == HELPER_OFF:
		return ""
	var key: String = key_for(english)
	if code == DEFAULT_HELPER_LANGUAGE:
		var authored: String = thai_hint.strip_edges()
		if not authored.is_empty():
			return authored
	var found: String = helper(key, "", code)
	if found.strip_edges() == english.strip_edges():
		return ""
	return found


# -----------------------------------------------------------------------------
# Tables
# -----------------------------------------------------------------------------


## The helper table for `code`, loaded once. A missing or malformed file is an
## empty table -- every lookup then falls back, nothing errors.
static func _table(code: String) -> Dictionary:
	if _tables.has(code):
		return _tables[code]
	var loaded: Dictionary = load_table(code)
	_tables[code] = loaded
	return loaded


## Reads `res://content/localization/helpers_<code>.json` and returns its
## `helpers` dictionary. Public so a test can assert a shipped file's shape.
static func load_table(code: String) -> Dictionary:
	var path: String = table_path(code)
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	var helpers: Variant = (parsed as Dictionary).get("helpers", null)
	if not (helpers is Dictionary):
		return {}
	var out: Dictionary = {}
	for key: Variant in (helpers as Dictionary).keys():
		var value: Variant = (helpers as Dictionary)[key]
		if typeof(key) == TYPE_STRING and typeof(value) == TYPE_STRING:
			out[String(key)] = String(value)
	return out


static func table_path(code: String) -> String:
	return "%s/%s" % [CONTENT_DIR, FILE_PATTERN % code]


## Drops every cached table. Tests, and a content reload.
static func clear_cache() -> void:
	_tables.clear()


## Number of entries the shipped table for `code` holds. Diagnostics and tests.
static func entry_count(code: String) -> int:
	return _table(code).size()
