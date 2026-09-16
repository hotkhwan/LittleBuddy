class_name ProfileStore
extends RefCounted

## Pure, testable persistence logic for the child's local profile.
## Owns reading/writing user://profile.json and defending against every
## corruption/failure mode so gameplay never crashes or silently loses stars.

const DEFAULT_PATH := "user://profile.json"
const CURRENT_VERSION := 1

var path: String

func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


## Canonical default schema. Always returns a fresh Dictionary (no shared
## references) so callers can freely mutate the result.
func default_profile() -> Dictionary:
	return {
		"profileVersion": CURRENT_VERSION,
		"stars": 0,
		"completedActivities": [],
		"settings": default_settings(),
	}


func default_settings() -> Dictionary:
	return {
		"speechLocale": "en-US",
		"speechEnabled": true,
		"thaiHints": true,
		"soundEnabled": true,
		"ttsSpeed": "normal",
	}


## Loads the profile from disk, handling every failure mode safely:
## missing file, zero-byte file, invalid JSON, JSON parsing to a
## non-Dictionary, missing keys, and wrong-typed values. Never throws.
func load_profile() -> Dictionary:
	if not FileAccess.file_exists(path):
		return default_profile()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return default_profile()

	var text := file.get_as_text()
	file.close()

	if text.strip_edges() == "":
		return default_profile()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return default_profile()

	return _sanitize(parsed)


## Sanitizes/migrates an arbitrary Dictionary into the canonical schema.
## Partial or malformed data is merged over defaults rather than discarded,
## so a corrupt "settings" block never wipes a valid star count and vice versa.
func _sanitize(raw: Dictionary) -> Dictionary:
	var result := default_profile()

	# Forward-compatible migration hook keyed on profileVersion. Tonight only
	# version 1 exists; unknown/newer/malformed versions are treated
	# defensively (never crash) and simply fall through to field-by-field
	# validation below.
	var version_value = raw.get("profileVersion", CURRENT_VERSION)
	var version := CURRENT_VERSION
	if typeof(version_value) == TYPE_INT or typeof(version_value) == TYPE_FLOAT:
		version = int(version_value)
	raw = _migrate(raw, version)

	# stars: must be a non-negative number.
	if raw.has("stars"):
		var stars = raw["stars"]
		if (typeof(stars) == TYPE_INT or typeof(stars) == TYPE_FLOAT) and stars >= 0:
			result["stars"] = int(stars)

	# completedActivities: must be an array of strings, de-duplicated.
	if raw.has("completedActivities") and typeof(raw["completedActivities"]) == TYPE_ARRAY:
		var cleaned: Array = []
		for item in raw["completedActivities"]:
			if typeof(item) == TYPE_STRING and not cleaned.has(item):
				cleaned.append(item)
		result["completedActivities"] = cleaned

	# settings: merge known keys with type validation; preserve unknown
	# forward-compatible keys only if they are JSON-safe types.
	var settings_result: Dictionary = default_settings()
	if raw.has("settings") and typeof(raw["settings"]) == TYPE_DICTIONARY:
		var raw_settings: Dictionary = raw["settings"]
		for key in raw_settings.keys():
			var value = raw_settings[key]
			match key:
				"speechLocale":
					if typeof(value) == TYPE_STRING and value != "":
						settings_result[key] = value
				"speechEnabled", "thaiHints":
					if typeof(value) == TYPE_BOOL:
						settings_result[key] = value
				_:
					var safe_types := [TYPE_STRING, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_ARRAY, TYPE_DICTIONARY]
					if safe_types.has(typeof(value)):
						settings_result[key] = value
	result["settings"] = settings_result

	result["profileVersion"] = CURRENT_VERSION

	return result


## Migration hook. Tonight there is only version 1. Unknown/newer versions
## must not crash; the raw fields are still passed through field-by-field
## validation in _sanitize().
func _migrate(raw: Dictionary, _version: int) -> Dictionary:
	return raw


## Writes the profile to disk, sanitizing it first so a bad in-memory state
## can never be persisted. Writes via a temp file + rename to avoid
## corrupting the profile if the app is killed mid-write. Returns true on
## success.
func save_profile(profile: Dictionary) -> bool:
	var sanitized := _sanitize(profile)
	var json_text := JSON.stringify(sanitized, "\t")
	var tmp_path := path + ".tmp"

	var tmp_file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if tmp_file == null:
		return false
	tmp_file.store_string(json_text)
	tmp_file.close()

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var err := DirAccess.rename_absolute(tmp_path, path)
	if err == OK:
		return true

	# Fallback: atomic rename failed (e.g. platform limitation). Write
	# directly rather than losing the data entirely.
	var direct := FileAccess.open(path, FileAccess.WRITE)
	if direct == null:
		return false
	direct.store_string(json_text)
	direct.close()

	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)

	return true
