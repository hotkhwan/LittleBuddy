extends RefCounted

## Sentinel case for the content layer.
##
## This file deliberately uses NO `preload` and NO global class names. Every
## other content case preloads `scripts/content/*.gd`, and a parse error in a
## preloaded script makes the *case* fail to parse -- at which point the runner
## drops it from the report entirely rather than failing the build. A broken
## content script would therefore look like "fewer tests, still green".
##
## Because this case only touches scripts through runtime `load()`, it always
## runs, and it fails loudly if any content script or content case is broken.

const CONTENT_SCRIPTS: Array[String] = [
	"res://scripts/content/content_library.gd",
	"res://scripts/content/content_validator.gd",
	"res://scripts/content/task_picker.gd",
]

## Every content case that must be present in the suite.
const CONTENT_CASES: Array[String] = [
	"res://tests/cases/test_content_counts.gd",
	"res://tests/cases/test_content_legacy.gd",
	"res://tests/cases/test_content_library.gd",
	"res://tests/cases/test_content_picker.gd",
	"res://tests/cases/test_content_schema.gd",
]

const CONTENT_FILES: Array[String] = [
	"res://content/index.json",
	"res://content/objects.json",
	"res://content/feeding/feed_milk.json",
	"res://content/feeding/tasks.json",
	"res://content/dressing/tasks.json",
	"res://content/bath/tasks.json",
	"res://content/play/tasks.json",
	"res://content/bedtime/tasks.json",
	"res://content/vocabulary/vocabulary.json",
	"res://content/missions/missions.json",
	"res://content/stickers/stickers.json",
]


func test_name() -> String:
	return "content_scripts"


func run():
	var failures: Array = []

	for path: String in CONTENT_SCRIPTS:
		failures.append_array(_check_script(path, true))

	for path: String in CONTENT_CASES:
		failures.append_array(_check_script(path, false))

	for path: String in CONTENT_FILES:
		failures.append_array(_check_json(path))

	return failures


func _check_script(path: String, must_instantiate: bool) -> Array:
	var failures: Array = []

	if not ResourceLoader.exists(path):
		failures.append("missing script: %s" % path)
		return failures

	var resource: Resource = load(path)
	if resource == null:
		failures.append("%s failed to load (parse or compile error)" % path)
		return failures

	var script: Script = resource as Script
	if script == null:
		failures.append("%s is not a Script" % path)
		return failures

	# `can_instantiate()` is false when the script (or a dependency) did not
	# compile. Called on a Script-typed variable, not on a class name.
	if not script.can_instantiate():
		failures.append("%s did not compile (can_instantiate() is false)" % path)
		return failures

	if not must_instantiate:
		# Test cases must expose the runner contract.
		var case_instance: Object = script.new()
		if case_instance == null:
			failures.append("%s could not be instantiated" % path)
			return failures
		if not case_instance.has_method("run"):
			failures.append("%s is missing run()" % path)
		if not case_instance.has_method("test_name"):
			failures.append("%s is missing test_name()" % path)

	return failures


func _check_json(path: String) -> Array:
	var failures: Array = []

	if not FileAccess.file_exists(path):
		failures.append("missing content file: %s" % path)
		return failures

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("could not open content file: %s" % path)
		return failures

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		failures.append("%s is not a valid JSON object" % path)
		return failures

	# Offline-first: bundled content must never reference a remote resource.
	var lowered: String = text.to_lower()
	for marker: String in ["http://", "https://", "ftp://", "ws://"]:
		if lowered.find(marker) != -1:
			failures.append("%s contains a network URL (%s)" % [path, marker])

	return failures
