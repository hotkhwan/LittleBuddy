extends RefCounted

## The unverified-music override must be unreachable in a distributed build.
##
## It is a developer preview switch for a machine whose owner has accepted that
## the rights are not yet recorded. If it could ever arm itself on a stranger's
## device, it would stop being a preview switch and become a way to perform music
## whose licence nobody has established — which is the exact thing the licence
## gate exists to prevent.
##
## ## The hole this was written for
##
## `has_cli_flag()` used to check `OS.get_cmdline_args()` as well as the user
## args, "so it works with a stripped export". Godot writes an Android preset's
## `command_line/extra_args` into `assets/_cl_` inside the APK and merges it into
## `get_cmdline_args()` at startup — and `export_presets.cfg` is a **committed
## file**. One line there would have armed unverified music in a distributed
## build, with only a device-side `push_warning` to say so.
##
## Nothing had leaked: the shipped APK's `_cl_` was decoded and holds only
## harmless engine arguments. The route simply should not exist.
##
## Asserted on the SOURCE rather than by running the check, because the answer
## depends on how the binary was launched — and the suite is launched from a
## terminal, which is the one context where the difference does not show.

const OVERRIDE_PATH: String = "res://scripts/audio/music_licence_override.gd"
const PRESETS_PATH: String = "res://../game/export_presets.cfg"


func test_name() -> String:
	return "music_override_cannot_ship"


func run():
	var failures: Array = []
	failures.append_array(_test_only_user_args_can_arm_it())
	failures.append_array(_test_no_preset_carries_the_flag())
	failures.append_array(_test_it_is_off_by_default())
	return failures


## The file with its comments stripped, so a guard cannot trip over prose.
func _executable(source: String) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var hash_at: int = line.find("#")
		kept.append(line.substr(0, hash_at) if hash_at >= 0 else line)
	return "\n".join(kept)


func _source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _test_only_user_args_can_arm_it():
	var failures: Array = []
	var source: String = _source(OVERRIDE_PATH)
	if source.is_empty():
		return ["music_licence_override.gd could not be read"]

	if not source.contains("OS.get_cmdline_user_args()"):
		failures.append("the override no longer reads `get_cmdline_user_args()`, so the "
				+ "documented `-- --allow-unverified-music` form would not work")
	# EXECUTABLE lines only. The first version of this check scanned the whole
	# file and fired on the doc comment that EXPLAINS the hole -- a guard that
	# fails because the code documents why it is safe is a guard nobody keeps.
	if _executable(source).contains("OS.get_cmdline_args()"):
		failures.append("the override reads `OS.get_cmdline_args()` again. Godot merges an "
				+ "Android preset's `command_line/extra_args` into that list, and "
				+ "`export_presets.cfg` is COMMITTED — one line there would arm "
				+ "unverified music in a distributed build.")
	return failures


## Belt and braces: even with the code correct, a preset carrying the flag is a
## thing somebody meant to do and should have to justify.
func _test_no_preset_carries_the_flag():
	var failures: Array = []
	var presets: String = _source(PRESETS_PATH)
	if presets.is_empty():
		# Not fatal — the file lives outside `res://` for some run configurations.
		return failures
	if presets.contains("allow-unverified-music"):
		failures.append("export_presets.cfg contains the unverified-music flag. A shipped "
				+ "build would play music whose rights are not established.")
	return failures


func _test_it_is_off_by_default():
	var failures: Array = []
	var source: String = _source(OVERRIDE_PATH)
	if source.is_empty():
		return failures
	# The only thing that may ever turn it on is an explicit, named check.
	if source.contains("return true") and not source.contains("func has_cli_flag"):
		failures.append("the override appears to short-circuit to true")
	var director: String = _source("res://scripts/audio/audio_director.gd")
	if not director.is_empty():
		if not director.contains("MusicLicenceOverride.is_armed()") \
				and not director.contains("is_armed()"):
			failures.append("the director no longer consults the override explicitly; "
					+ "unverified music may be reachable by another path")
	return failures
