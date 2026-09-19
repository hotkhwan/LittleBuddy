extends SceneTree
## Headless test runner.
##
## Usage:
##   godot --headless --path game --script res://tests/run_tests.gd
##
## Discovers every `res://tests/cases/test_*.gd`, instantiates it and calls
## `run()` (array of failure strings; empty means the case passed).
##
## ## `run()` and every `_test_*` helper must be UNTYPED
##
## GDScript returns a default-constructed value from a typed function that
## aborts, so `func run() -> Array:` returns an EMPTY Array on a script error and
## the case reports [PASS] with its assertions never having executed. The same
## applies one level down: a typed `_test_*` helper's abort is swallowed by
## `append_array()` and `run()` carries on. `test_runner_fails_loud.gd` enforces
## both, and a live instance of each was found in this project.
##
## ## Autoloads ARE live here, contrary to what this file used to claim
##
## This comment previously read "cases must not depend on autoloads -- `--script`
## does not load them". That is false on Godot 4.7: `/root` really does hold
## SaveService, SpeechService, TtsService and Sfx. What does NOT happen is their
## `_ready()`, so `SaveService` starts with an empty in-memory profile -- and any
## case that completes a level reaches `save_profile()` and writes that empty
## profile over `user://profile.json`. On a device that is a real child's stars.
##
## So the autoloads are detached for the duration of the run and restored after.
## The guarantee is now enforced rather than asserted, and no case can reach a
## real save file by accident.

const CASES_DIR := "res://tests/cases"

## Detached for the run. Named explicitly rather than "every root child", so a
## scene a case leaves behind is not silently swept up with them.
const PROJECT_AUTOLOADS: Array[String] = [
	"SaveService", "SpeechService", "TtsService", "Sfx", "Audio",
]


func _initialize() -> void:
	var detached: Array[Node] = _detach_autoloads()
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

	_reattach_autoloads(detached)

	print("")
	if total_failures == 0:
		print("PASS - %d case(s), 0 failure(s)" % total_cases)
		quit(0)
	else:
		print("FAIL - %d case(s), %d failure(s)" % [total_cases, total_failures])
		quit(1)


## Takes the autoloads out of `/root` so no case can reach a real save file.
func _detach_autoloads() -> Array[Node]:
	var detached: Array[Node] = []
	for autoload_name: String in PROJECT_AUTOLOADS:
		var node: Node = root.get_node_or_null(NodePath(autoload_name))
		if node == null:
			continue
		root.remove_child(node)
		detached.append(node)
	return detached


## Put them back, so anything that inspects the tree afterwards sees it intact
## and the nodes are freed normally with the root rather than leaking.
func _reattach_autoloads(detached: Array[Node]) -> void:
	for node: Node in detached:
		if is_instance_valid(node) and node.get_parent() == null:
			root.add_child(node)


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
	# A case that aborts mid-run (script error inside run()) returns null rather than
	# an Array. Treating that as "no failures" would silently turn a red case green,
	# so anything that is not an Array is itself a failure.
	if not (result is Array):
		print("  [ERROR] %s - run() did not return an Array (case aborted?)" % label)
		return ["%s: run() returned %s instead of an Array; the case did not complete"
				% [label, type_string(typeof(result))]]

	var failures: Array = result

	if failures.is_empty():
		print("  [PASS] %s" % label)
	else:
		print("  [FAIL] %s" % label)
		for failure in failures:
			print("         - %s" % str(failure))

	return failures
