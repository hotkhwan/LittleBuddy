extends RefCounted

## Regression guard for shipped copy. Internal compatibility identifiers such
## as taskId carryMilkToBunny, node BunnyVoiceSlider and track hungryBunny are
## intentionally outside this display-string list.

const JSON_FILES: Array[String] = [
	"res://content/localization/keys_en.json",
	"res://content/localization/helpers_th.json",
	"res://content/localization/helpers_ja.json",
	"res://content/localization/helpers_zh.json",
	"res://content/localization/helpers_hi.json",
	"res://content/localization/helpers_ar.json",
	"res://content/care/tasks.json",
	"res://content/missions/missions.json",
	"res://content/chapters/chapters.json",
	"res://content/index.json",
	"res://content/voice/voice_manifest.json",
]

const SOURCE_FILES: Array[String] = [
	"res://scenes/main/main.gd",
	"res://scenes/main/main.tscn",
	"res://scenes/activities_menu/activity_picker.gd",
	"res://scenes/parent/parent_settings.tscn",
	"res://scripts/onboarding/onboarding_plan.gd",
	"res://scripts/feeding/feeding_hud.gd",
	"res://scripts/kitchen/kitchen_state.gd",
	"res://scripts/care/care_overlay.gd",
	"res://scripts/gameplay/house_freeplay_director.gd",
	"res://scripts/tutor/tutor_scene.gd",
	"res://scripts/tutor/tutor_turn_ux.gd",
	"res://scripts/tutor/ui/tutor_break_card.gd",
]

func run():
	var failures: Array[String] = []
	var quoted_bunny := RegEx.new()
	quoted_bunny.compile("\\\"[^\\\"]*[Bb][Uu][Nn][Nn][Yy][^\\\"]*\\\"")
	for path: String in JSON_FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			failures.append("cannot inspect shipped copy: %s" % path)
			continue
		var value: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		_scan_json(value, path, "", failures)
	for path: String in SOURCE_FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			failures.append("cannot inspect UI source: %s" % path)
			continue
		var line_number := 0
		while not file.eof_reached():
			line_number += 1
			var line := file.get_line()
			if _source_line_is_display_copy(line) and quoted_bunny.search(line) != null:
				failures.append("legacy display name in %s:%d" % [path, line_number])
		file.close()
	return failures


func _scan_json(value: Variant, path: String, key: String, failures: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for child_key: Variant in value:
			_scan_json(value[child_key], path, String(child_key), failures)
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value:
			_scan_json(child, path, key, failures)
	elif typeof(value) == TYPE_STRING and "bunny" in String(value).to_lower():
		# Stable IDs and file provenance are compatibility data, not display copy.
		if key in ["taskId", "taskIds", "coreTaskIds", "optionalTaskIds", "trackId", "usage",
				"source", "licenseEvidence", "acceptedCommands", "folder", "lineId", "character", "file"]:
			return
		failures.append("legacy display name in %s key %s: %s" % [path, key, value])


func _source_line_is_display_copy(line: String) -> bool:
	var trimmed := line.strip_edges()
	if trimmed.begins_with("#") or trimmed.begins_with(";"):
		return false
	return "text =" in line or "speech\":" in line or "const LABEL_" in line \
			or "const TITLE" in line or "const CLOSING_TEXT" in line \
			or "const BANNER_OFFLINE" in line or "const OFFLINE_LINE" in line \
			or "const LINE_BUNNY" in line or "BEDTIME_GOODNIGHT" in line \
			or "\"text\":" in line or "\"hint\":" in line or "return _no" in line
