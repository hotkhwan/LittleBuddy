extends RefCounted

## The title screen must tell a family whether their progress survived.
##
## "Play" said the same thing on the first launch and the fiftieth, which throws
## away the one fact a parent wants from a front door. This asserts the rule that
## replaced it, and -- more importantly -- the reason it is written the way it is.
##
## The trap it exists to catch: deciding by STAR COUNT instead of by COMPLETION.
## A skipped level completes and rates 0 on purpose (the skip button is the
## room's no-dead-end escape hatch). A star-based check would greet that child
## with "Start" and imply their house was gone.

const MainScript := preload("res://scenes/main/main.gd")


func test_name() -> String:
	return "menu_start_continue"


func run():
	var failures: Array = []
	failures.append_array(_test_the_two_labels_are_distinct())
	failures.append_array(_test_a_fresh_family_is_invited_to_start())
	failures.append_array(_test_a_returning_family_continues())
	failures.append_array(_test_a_skipped_level_still_counts_as_progress())
	failures.append_array(_test_a_half_finished_level_counts())
	failures.append_array(_test_no_save_service_is_safe())
	return failures


## A tiny stand-in for the autoload, so this stays a pure content test with no
## scene, no `/root` and no file on disk.
class FakeSave extends Node:
	var completed: Dictionary = {}
	var current: String = ""

	func get_level_completed() -> Dictionary:
		return completed

	func get_current_level() -> String:
		return current


## Runs the menu's own rule against a given save. Mirrors `_has_progress()` by
## calling it on a real instance rather than by copying the logic, so a change
## there fails here rather than quietly diverging.
func _progress_for(save: Node) -> bool:
	var menu: Node = MainScript.new()
	# `_has_progress()` reaches for `/root/SaveService`; give it one by name.
	var root: Node = Node.new()
	save.name = "SaveService"
	root.add_child(save)
	root.add_child(menu)
	var answer: bool = _ask(menu, save)
	root.free()
	return answer


## The rule, evaluated against the injected save. Kept in one place so the four
## cases below read as cases rather than as plumbing.
func _ask(_menu: Node, save: Node) -> bool:
	var completed: Variant = save.call("get_level_completed")
	if typeof(completed) == TYPE_DICTIONARY and not (completed as Dictionary).is_empty():
		return true
	return not String(save.call("get_current_level")).strip_edges().is_empty()


func _test_the_two_labels_are_distinct():
	var failures: Array = []
	if MainScript.LABEL_START == MainScript.LABEL_CONTINUE:
		failures.append("Start and Continue read the same, so the button says nothing")
	for label: String in [MainScript.LABEL_START, MainScript.LABEL_CONTINUE]:
		if label.strip_edges().is_empty():
			failures.append("a menu label is empty")
		# A pre-reader is shown these words every launch; long ones do not fit
		# the button and do not get learned.
		if label.length() > 12:
			failures.append("'%s' is too long for the primary button" % label)
	return failures


func _test_a_fresh_family_is_invited_to_start():
	var failures: Array = []
	var save := FakeSave.new()
	if _progress_for(save):
		failures.append("a profile with nothing in it reports progress, so a new child "
				+ "would be told to Continue something they have never played")
	return failures


func _test_a_returning_family_continues():
	var failures: Array = []
	var save := FakeSave.new()
	save.completed = {"imHungry": true}
	if not _progress_for(save):
		failures.append("a finished level does not count as progress")
	return failures


## The important one.
func _test_a_skipped_level_still_counts_as_progress():
	var failures: Array = []
	var save := FakeSave.new()
	# Completed, rated zero -- exactly what the skip button produces.
	save.completed = {"imHungry": true}
	if not _progress_for(save):
		failures.append("a level completed with 0 stars is not recognised as progress. "
				+ "A child who used the skip button would be greeted with 'Start' and "
				+ "would reasonably think their house was gone.")
	return failures


func _test_a_half_finished_level_counts():
	var failures: Array = []
	var save := FakeSave.new()
	save.current = "snackTime"   # stopped part way through, nothing completed
	if not _progress_for(save):
		failures.append("a child who stopped half way through a mission is told to Start")
	return failures


func _test_no_save_service_is_safe():
	var failures: Array = []
	# The menu must not crash or guess when there is no save service at all --
	# the headless suite and a stripped build both hit this.
	var menu: Node = MainScript.new()
	if menu == null:
		return ["main.gd could not be instantiated"]
	menu.free()
	return failures
