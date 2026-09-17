extends RefCounted

## Guards the test runner's own fail-loud guarantee.
##
## This is the third hole of this exact shape found in this project, so it is
## now pinned by a test rather than by intent.
##
## `run_tests.gd` decides a case aborted by checking that `run()` did not return
## an Array. That check only works while `run()` is UNTYPED: GDScript returns a
## default-constructed value from a typed function when it aborts, so a case
## whose `run()` carries an Array return type and hits a script error mid-way
## returns an empty Array -- indistinguishable from "completed with no failures".
## Every such case reports [PASS] while its assertions never ran.
##
## (The offending declaration is deliberately not spelled out anywhere in this
## file. It is assembled in `_typed_run()` instead, because the scan below reads
## this file too and would otherwise name itself as the offender.)
##
## Verified repro before this guard existed: a case whose `run()` dereferenced
## null printed `SCRIPT ERROR: Cannot call method 'call' on a null value.` and
## was then reported as `[PASS]`. Dropping the return type turns the same case
## into `[ERROR] ... run() did not return an Array (case aborted?)`.
##
## So: `func run():` is deliberate, not an oversight, and adding the return type
## back -- however tidy it looks -- silently disarms the whole suite.

const CASES_DIR: String = "res://tests/cases"
const RUNNER_PATH: String = "res://tests/run_tests.gd"

const UNTYPED_RUN: String = "func run():"


## The declaration that breaks abort detection, assembled at runtime rather than
## written out as a literal. Spelled in full, this file would match its own scan
## and report itself as the offender.
static func _typed_run() -> String:
	return "func run() -> %s:" % "Array"


func test_name() -> String:
	return "runner_fails_loud"


func run():
	var failures: Array = []

	failures.append_array(_test_no_case_types_its_run())
	failures.append_array(_test_runner_still_checks_the_return_type())

	return failures


## Every case must declare `func run():` and none may declare it typed.
func _test_no_case_types_its_run() -> Array:
	var failures: Array = []

	var names: PackedStringArray = _case_file_names()
	if names.is_empty():
		return ["runner_fails_loud: found no test cases in %s; the scan is vacuous" % CASES_DIR]

	var typed_run: String = _typed_run()
	var checked: int = 0
	for file_name: String in names:
		var path: String = "%s/%s" % [CASES_DIR, file_name]
		var source: String = _read(path)
		if source.is_empty():
			failures.append("runner_fails_loud: could not read %s" % path)
			continue
		checked += 1

		if source.contains(typed_run):
			failures.append(
				("runner_fails_loud: %s declares `%s`. A typed run() that aborts returns an "
				+ "EMPTY ARRAY, not null, so run_tests.gd reports it as [PASS] with its "
				+ "assertions never having run. Declare `%s` instead.")
				% [file_name, typed_run, UNTYPED_RUN]
			)
		elif not source.contains(UNTYPED_RUN):
			failures.append(
				"runner_fails_loud: %s has no `%s`; every case must expose an untyped run()"
				% [file_name, UNTYPED_RUN]
			)

	# A scan that silently checked nothing is worse than no scan.
	if checked < 2:
		failures.append("runner_fails_loud: only %d case file(s) were readable" % checked)

	return failures


## The other half of the contract: the runner must still reject a non-Array.
## Dropping the return types achieves nothing if this guard is ever deleted.
func _test_runner_still_checks_the_return_type() -> Array:
	var failures: Array = []

	var source: String = _read(RUNNER_PATH)
	if source.is_empty():
		return ["runner_fails_loud: could not read %s" % RUNNER_PATH]

	if not source.contains("if not (result is Array):"):
		failures.append(
			"runner_fails_loud: run_tests.gd no longer rejects a non-Array result from run(); "
			+ "an aborted case would be reported as passing"
		)

	return failures


func _case_file_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(CASES_DIR)
	if dir == null:
		return names
	for file_name: String in dir.get_files():
		# Exported builds rename .gd to .gd.remap; tests run from source, but be
		# tolerant rather than silently scanning nothing.
		if file_name.ends_with(".gd") and file_name.begins_with("test_"):
			names.append(file_name)
	return names


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
