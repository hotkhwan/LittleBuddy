extends SceneTree
## Headless test runner.
##
## Usage:
##   godot --headless --path game --script res://tests/run_tests.gd
##
## Discovers every `res://tests/cases/test_*.gd`, instantiates it and calls
## `run() -> Array` (array of failure strings; empty means the case passed).
## Cases must not depend on autoloads -- `--script` does not load them.

const CASES_DIR := "res://tests/cases"


func _initialize() -> void:
	var case_paths := _discover_cases()
	if case_paths.is_empty():
		print("No test cases found in %s" % CASES_DIR)
		quit(1)
		return

	var total_failures := 0
	var total_cases := 0

	for path in case_paths:
		total_cases += 1
		var failures := _run_case(path)
		total_failures += failures.size()

	print("")
	if total_failures == 0:
		print("PASS - %d case(s), 0 failure(s)" % total_cases)
		quit(0)
	else:
		print("FAIL - %d case(s), %d failure(s)" % [total_cases, total_failures])
		quit(1)


func _discover_cases() -> PackedStringArray:
	var paths := PackedStringArray()
	var dir := DirAccess.open(CASES_DIR)
	if dir == null:
		return paths
	for file_name in dir.get_files():
		# Exported projects rename scripts to .gdc/.remap; tolerate both.
		var name := file_name.trim_suffix(".remap")
		if name.begins_with("test_") and (name.ends_with(".gd") or name.ends_with(".gdc")):
			paths.append("%s/%s" % [CASES_DIR, name])
	paths.sort()
	return paths


func _run_case(path: String) -> Array:
	var script: Resource = load(path)
	if script == null or not (script is GDScript):
		print("  [ERROR] %s - could not load script" % path)
		return ["%s: could not load script" % path]

	# A case whose script (or anything it preloads) fails to parse must be a LOUD
	# failure, never a silently skipped case -- otherwise a broken subsystem can
	# make the suite look green simply by removing its own tests from the run.
	var gdscript := script as GDScript
	if not gdscript.can_instantiate():
		print("  [ERROR] %s - script has parse errors (cannot instantiate)" % path)
		return ["%s: script has parse errors; the case never ran" % path]

	var instance: Object = gdscript.new()
	if instance == null:
		print("  [ERROR] %s - could not instantiate" % path)
		return ["%s: could not instantiate" % path]

	var label := path
	if instance.has_method("test_name"):
		label = str(instance.call("test_name"))

	if not instance.has_method("run"):
		print("  [ERROR] %s - missing run()" % label)
		return ["%s: missing run()" % label]

	var result: Variant = instance.call("run")
	var failures: Array = result if result is Array else []

	if failures.is_empty():
		print("  [PASS] %s" % label)
	else:
		print("  [FAIL] %s" % label)
		for failure in failures:
			print("         - %s" % str(failure))

	return failures
