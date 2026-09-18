extends RefCounted

## The version of record, and the three places that must agree with it.
##
## `VERSION` at the repository root is authoritative. `CHANGELOG.md`'s newest
## entry and `application/short_version` + `application/version` in
## `game/export_presets.cfg` all follow it.
##
## ## Why this is worth a test
##
## A version number is a promise that a build can be identified after the fact.
## The moment `VERSION` says 0.0.3 and the `.ipa` on the device says 0.0.1, every
## bug report against that device becomes unattributable -- and the failure is
## completely silent: the export succeeds, the app installs, nothing logs a
## warning, and you only find out when you are trying to work out which build a
## child was holding. **A version that disagrees with the build it labels is
## worse than no version at all**, which is the owner's phrasing and the reason
## this file exists.
##
## The export preset is also the file an agent is *least* likely to remember,
## because bumping a version feels like a documentation change and
## `export_presets.cfg` does not look like documentation.
##
## ## Reading outside res://
##
## `VERSION` and `CHANGELOG.md` live at the repository root, one level above the
## Godot project, so they are not addressable as `res://`. They are read through
## `ProjectSettings.globalize_path()`, which resolves for a project run from
## source -- which is the only way this suite is ever run. If they cannot be read
## that is reported as a FAILURE rather than skipped: a version guard that
## quietly does nothing is exactly the guard that lets the numbers drift.

const VERSION_PATTERN: String = "^[0-9]+\\.[0-9]+\\.[0-9]+$"
const EXPORT_PRESETS_PATH: String = "res://export_presets.cfg"
const EXPORT_KEYS: Array[String] = ["application/short_version", "application/version"]


func test_name() -> String:
	return "version"


func run():
	var failures: Array = []
	failures.append_array(_test_version_file())
	failures.append_array(_test_export_preset_agrees())
	failures.append_array(_test_changelog_agrees())
	return failures


func _test_version_file():
	var failures: Array = []
	var version: String = _version()
	if version.is_empty():
		failures.append("VERSION at the repository root is missing or empty. It is the version of "
				+ "record; nothing else in this test can mean anything without it. Looked in: %s"
				% _root_path("VERSION"))
		return failures
	var regex := RegEx.new()
	regex.compile(VERSION_PATTERN)
	if regex.search(version) == null:
		failures.append("VERSION reads '%s'; it must be MAJOR.MINOR.PATCH (see CHANGELOG.md)"
				% version)
	return failures


func _test_export_preset_agrees():
	var failures: Array = []
	var version: String = _version()
	if version.is_empty():
		return failures

	var preset: String = _read("res://export_presets.cfg")
	if preset.strip_edges().is_empty():
		failures.append("%s is missing or empty; the iOS build has no version to carry"
				% EXPORT_PRESETS_PATH)
		return failures

	for key: String in EXPORT_KEYS:
		var found: String = _preset_value(preset, key)
		if found.is_empty():
			failures.append("%s has no %s at all. The build would ship unlabelled."
					% [EXPORT_PRESETS_PATH, key])
		elif found != version:
			failures.append(
				("%s says %s=\"%s\" but VERSION says \"%s\". The .ipa would label itself with a "
				+ "version this repository does not have, and every bug report against that build "
				+ "becomes unattributable. Bump both, or neither.")
				% [EXPORT_PRESETS_PATH, key, found, version]
			)
	return failures


func _test_changelog_agrees():
	var failures: Array = []
	var version: String = _version()
	if version.is_empty():
		return failures

	var changelog: String = _read_root("CHANGELOG.md")
	if changelog.strip_edges().is_empty():
		failures.append("CHANGELOG.md at the repository root is missing or empty. Looked in: %s"
				% _root_path("CHANGELOG.md"))
		return failures

	var newest: String = _newest_changelog_version(changelog)
	if newest.is_empty():
		failures.append("CHANGELOG.md has no '## <version>' heading; there is nothing to compare "
				+ "VERSION against")
	elif newest != version:
		failures.append(
			("CHANGELOG.md's newest entry is '%s' but VERSION says '%s'. Whichever is right, the "
			+ "other is a lie about what this commit contains.") % [newest, version]
		)
	return failures


## -- Reading ------------------------------------------------------------------

func _version():
	return _read_root("VERSION").strip_edges()


## The first `## X.Y.Z ...` heading in the changelog, newest-first by convention.
func _newest_changelog_version(text: String):
	var regex := RegEx.new()
	regex.compile("^##\\s+([0-9]+\\.[0-9]+\\.[0-9]+)")
	for line: String in text.split("\n"):
		var found: RegExMatch = regex.search(line)
		if found != null:
			return found.get_string(1)
	return ""


## `key="value"` out of a .cfg, ignoring whitespace around the `=`.
func _preset_value(text: String, key: String):
	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if not line.begins_with(key):
			continue
		var rest: String = line.substr(key.length()).strip_edges()
		if not rest.begins_with("="):
			continue
		return rest.substr(1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return ""


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## The repository root is one level above `res://`.
func _root_path(file_name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(file_name).simplify_path()


func _read_root(file_name: String) -> String:
	return _read(_root_path(file_name))
