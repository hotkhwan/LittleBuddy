extends RefCounted

## MissionRunner: star accounting and the no-dead-end guarantee.
##
## `MissionRunner._delay()` runs its callable immediately when the runner is not
## inside a SceneTree, so an entire mission can be played out synchronously here
## with no scene, no autoloads and no timers.

const RUNNER_PATH: String = "res://scripts/gameplay/mission_runner.gd"
const LIBRARY_PATH: String = "res://scripts/content/content_library.gd"

## Guards every drive loop so a genuine dead end fails the test instead of
## hanging the whole suite.
const MAX_STEPS: int = 200


## A minimal stand-in for ContentLibrary, used to build the pathological cases
## (a mission that lists the same task twice) that shipped content does not have.
class FakeLibrary extends RefCounted:
	var missions: Dictionary = {}
	var tasks: Dictionary = {}
	var objects: Dictionary = {}

	func get_mission(mission_id: String) -> Dictionary:
		var found: Variant = missions.get(mission_id, null)
		return (found as Dictionary).duplicate(true) if typeof(found) == TYPE_DICTIONARY else {}

	func get_mission_tasks(mission_id: String) -> Array:
		var mission: Dictionary = get_mission(mission_id)
		var result: Array = []
		for task_id: Variant in mission.get("taskIds", []):
			var task: Variant = tasks.get(String(task_id), null)
			if typeof(task) == TYPE_DICTIONARY:
				result.append((task as Dictionary).duplicate(true))
		return result

	func has_object(object_id: String) -> bool:
		return objects.has(object_id)

	func get_object(object_id: String) -> Dictionary:
		var found: Variant = objects.get(object_id, null)
		return (found as Dictionary).duplicate(true) if typeof(found) == TYPE_DICTIONARY else {}

	func get_objects() -> Array:
		return objects.values().duplicate(true)

	func get_objects_in_category(category: String) -> Array:
		var result: Array = []
		for entry: Variant in objects.values():
			if String((entry as Dictionary).get("category", "")) == category:
				result.append((entry as Dictionary).duplicate(true))
		return result


func test_name() -> String:
	return "gameplay_mission_runner"


func run() -> Array:
	var failures: Array = []
	var runner_script: GDScript = load(RUNNER_PATH) as GDScript
	if runner_script == null:
		return ["could not load %s" % RUNNER_PATH]

	failures.append_array(_test_no_double_award_for_same_task(runner_script))
	failures.append_array(_test_shipped_tasks_are_all_playable(runner_script))
	failures.append_array(_test_missions_award_expected_total(runner_script))
	failures.append_array(_test_missions_never_dead_end(runner_script))
	failures.append_array(_test_empty_mission_still_finishes(runner_script))
	failures.append_array(_test_unplayable_task_is_skipped_not_presented(runner_script))
	return failures


## THE double-award test. The mission deliberately lists `dupTask` twice, so the
## runner is asked to complete the same taskId twice in one mission. It must
## award exactly one star and emit `task_completed` exactly once.
func _test_no_double_award_for_same_task(runner_script: GDScript) -> Array:
	var failures: Array = []
	var library: FakeLibrary = FakeLibrary.new()
	library.objects["milk"] = {
		"objectId": "milk", "word": "milk", "category": "feeding",
		"primitive": "capsule", "color": "#FFFFFF", "defaultInteraction": "dragToMouth",
	}
	library.tasks["dupTask"] = {
		"taskId": "dupTask", "category": "feeding", "mode": "followInstruction",
		"objectId": "milk", "targetWords": ["milk"], "prompt": "I'm hungry.",
		"instruction": "Give the baby some milk.", "acceptedCommands": ["milk"],
		"interaction": "dragToMouth", "reward": {"stars": 1},
	}
	library.missions["dupMission"] = {
		"missionId": "dupMission", "taskIds": ["dupTask", "dupTask"],
	}

	var runner: Node = runner_script.new()
	runner.call("set_seed", 4242)
	var awards: Array = []
	var finished: Array = []
	runner.connect("task_completed", func(id: String, stars: int) -> void: awards.append([id, stars]))
	runner.connect("mission_completed", func(id: String, stars: int) -> void: finished.append([id, stars]))

	runner.call("start_mission", "dupMission", library)
	if int(runner.call("get_task_count")) != 2:
		failures.append("expected the mission to hold 2 task slots, got %d"
				% int(runner.call("get_task_count")))

	# Complete every slot, and mash each one for good measure.
	var steps: int = 0
	while bool(runner.call("is_running")) and steps < MAX_STEPS:
		steps += 1
		for _mash: int in range(4):
			runner.call("on_object_chosen", "milk")
			runner.call("complete_current_by_touch")

	if awards.size() != 1:
		failures.append("the same taskId awarded %d times, expected exactly 1: %s"
				% [awards.size(), str(awards)])
	if int(runner.call("get_stars_earned")) != 1:
		failures.append("stars_earned is %d, expected 1 for one distinct task"
				% int(runner.call("get_stars_earned")))
	if finished.size() != 1:
		failures.append("mission_completed emitted %d times, expected 1" % finished.size())
	elif int((finished[0] as Array)[1]) != 1:
		failures.append("mission_completed reported %d stars, expected 1"
				% int((finished[0] as Array)[1]))
	if Array(runner.call("get_awarded_task_ids")).size() != 1:
		failures.append("the awarded-task ledger did not dedupe")

	runner.free()
	return failures


## No shipped task may be unplayable: that would be a task the child is shown and
## then cannot finish.
func _test_shipped_tasks_are_all_playable(runner_script: GDScript) -> Array:
	var failures: Array = []
	var library: RefCounted = _real_library()
	if library == null:
		return ["ContentLibrary.create() returned null"]

	for task: Variant in library.get_tasks():
		var reason: String = runner_script.describe_unplayable(task, library)
		if not reason.is_empty():
			failures.append(reason)

	# ...and the check itself actually rejects bad data.
	if runner_script.describe_unplayable({"taskId": "x", "mode": "mystery"}, null).is_empty():
		failures.append("describe_unplayable accepted an unknown mode")
	if runner_script.describe_unplayable({"taskId": "x", "mode": "findIt"}, null).is_empty():
		failures.append("describe_unplayable accepted a task with no objectId")
	if runner_script.describe_unplayable(
			{"taskId": "x", "mode": "findIt", "objectId": "milk", "interaction": "dragToMars"},
			null).is_empty():
		failures.append("describe_unplayable accepted an interaction with no drop zone")

	return failures


## A touch-only playthrough of every shipped mission must pay exactly the
## expected total -- no more (double award) and no less (unreachable task).
func _test_missions_award_expected_total(runner_script: GDScript) -> Array:
	var failures: Array = []
	var library: RefCounted = _real_library()
	if library == null:
		return ["ContentLibrary.create() returned null"]

	var mission_ids: PackedStringArray = library.get_mission_ids()
	if mission_ids.size() < 5:
		failures.append("expected the full mission set, got %d" % mission_ids.size())

	for mission_id: String in mission_ids:
		var runner: Node = runner_script.new()
		runner.call("set_seed", 987)
		var awards: Array = []
		var finished: Array = []
		var progress: Array = []
		runner.connect("task_completed", func(id: String, stars: int) -> void: awards.append([id, stars]))
		runner.connect("mission_completed", func(id: String, stars: int) -> void: finished.append([id, stars]))
		runner.connect("mission_progress", func(index: int, total: int) -> void: progress.append([index, total]))

		if not bool(runner.call("start_mission", mission_id, library)):
			failures.append("mission '%s' did not start" % mission_id)
			runner.free()
			continue

		var tasks: Array = runner.call("get_tasks")
		var expected: int = runner_script.expected_stars(tasks)
		if tasks.size() < 5 or tasks.size() > 8:
			failures.append("mission '%s' has %d tasks, expected 5-8" % [mission_id, tasks.size()])

		var steps: int = _drive_with_correct_answers(runner)
		if steps >= MAX_STEPS:
			failures.append("mission '%s' never finished -- possible dead end" % mission_id)

		if finished.size() != 1:
			failures.append("mission '%s' emitted mission_completed %d times"
					% [mission_id, finished.size()])
		if int(runner.call("get_stars_earned")) != expected:
			failures.append("mission '%s' paid %d stars, expected %d"
					% [mission_id, int(runner.call("get_stars_earned")), expected])
		if awards.size() != _distinct_task_count(tasks):
			failures.append("mission '%s' emitted %d task_completed for %d distinct tasks"
					% [mission_id, awards.size(), _distinct_task_count(tasks)])
		if progress.size() != tasks.size():
			failures.append("mission '%s' reported %d progress steps for %d tasks"
					% [mission_id, progress.size(), tasks.size()])

		runner.free()
	return failures


## The no-dead-end guarantee, exercised the hard way: a child who only ever taps
## the wrong thing must STILL reach the end of the mission, kindly, with no stars
## and no punishment -- never stuck on a task forever.
func _test_missions_never_dead_end(runner_script: GDScript) -> Array:
	var failures: Array = []
	var library: RefCounted = _real_library()
	if library == null:
		return ["ContentLibrary.create() returned null"]

	for mission_id: String in library.get_mission_ids():
		var runner: Node = runner_script.new()
		runner.call("set_seed", 2024)
		var finished: Array = []
		var phrases: Array = []
		runner.connect("mission_completed", func(id: String, stars: int) -> void: finished.append([id, stars]))
		runner.connect("encouragement", func(text: String) -> void: phrases.append(text))
		runner.call("start_mission", mission_id, library)

		var steps: int = 0
		while bool(runner.call("is_running")) and steps < MAX_STEPS:
			steps += 1
			runner.call("on_object_chosen", "__definitely_not_the_answer__")

		if steps >= MAX_STEPS:
			failures.append("mission '%s' DEAD-ENDED on wrong answers" % mission_id)
		if finished.size() != 1:
			failures.append("mission '%s' did not finish after only wrong answers" % mission_id)
		if int(runner.call("get_stars_earned")) != 0:
			failures.append("mission '%s' paid stars for wrong answers" % mission_id)
		for phrase: Variant in phrases:
			var text: String = String(phrase)
			if text.contains("%") or text.to_lower().contains("wrong") or text.to_lower().contains("fail"):
				failures.append("mission '%s' showed discouraging feedback: '%s'" % [mission_id, text])

		runner.free()

		# The same mission must also survive a child who only ever uses the
		# explicit "skip" affordance.
		var skipper: Node = runner_script.new()
		var skipper_finished: Array = []
		skipper.connect("mission_completed", func(_id: String, _s: int) -> void: skipper_finished.append(true))
		skipper.call("start_mission", mission_id, library)
		var skip_steps: int = 0
		while bool(skipper.call("is_running")) and skip_steps < MAX_STEPS:
			skip_steps += 1
			skipper.call("skip_current_task")
		if skipper_finished.size() != 1:
			failures.append("mission '%s' could not be skipped through" % mission_id)
		skipper.free()

	return failures


## An unknown or empty mission must not hang a caller waiting on mission_completed.
func _test_empty_mission_still_finishes(runner_script: GDScript) -> Array:
	var failures: Array = []
	var runner: Node = runner_script.new()
	var finished: Array = []
	runner.connect("mission_completed", func(id: String, stars: int) -> void: finished.append([id, stars]))

	if bool(runner.call("start_mission", "noSuchMission", FakeLibrary.new())):
		failures.append("start_mission reported success for an unknown mission")
	if finished.size() != 1:
		failures.append("an unknown mission did not emit mission_completed")
	if bool(runner.call("is_running")):
		failures.append("an unknown mission left the runner running")

	# A null library must also be survivable.
	runner.call("start_mission", "anything", null)
	if bool(runner.call("is_running")):
		failures.append("a null library left the runner running")

	runner.free()
	return failures


## A task content cannot support is skipped rather than presented and then being
## impossible to finish.
func _test_unplayable_task_is_skipped_not_presented(runner_script: GDScript) -> Array:
	var failures: Array = []
	var library: FakeLibrary = FakeLibrary.new()
	library.objects["ball"] = {
		"objectId": "ball", "word": "ball", "category": "play",
		"primitive": "sphere", "color": "#FF8844", "defaultInteraction": "tap",
	}
	library.tasks["goodTask"] = {
		"taskId": "goodTask", "category": "play", "mode": "findIt", "objectId": "ball",
		"targetWords": ["ball"], "instruction": "Find the ball.", "acceptedCommands": ["ball"],
		"interaction": "tap", "reward": {"stars": 1},
	}
	library.tasks["brokenTask"] = {
		"taskId": "brokenTask", "category": "play", "mode": "teleportation",
		"objectId": "ball", "interaction": "tap", "reward": {"stars": 1},
	}
	library.missions["mixed"] = {"missionId": "mixed", "taskIds": ["brokenTask", "goodTask"]}

	var runner: Node = runner_script.new()
	var started: Array = []
	var finished: Array = []
	runner.connect("task_started", func(id: String, _mode: String) -> void: started.append(id))
	runner.connect("mission_completed", func(_id: String, stars: int) -> void: finished.append(stars))
	runner.call("start_mission", "mixed", library)

	if started.has("brokenTask"):
		failures.append("an unplayable task was presented to the child")
	var steps: int = _drive_with_correct_answers(runner)
	if steps >= MAX_STEPS:
		failures.append("a mission containing an unplayable task dead-ended")
	if finished.size() != 1 or int(finished[0]) != 1:
		failures.append("the playable half of the mission did not pay out: %s" % str(finished))

	runner.free()
	return failures


## -- Helpers --------------------------------------------------------------------

func _drive_with_correct_answers(runner: Node) -> int:
	var steps: int = 0
	while bool(runner.call("is_running")) and steps < MAX_STEPS:
		steps += 1
		var task: Dictionary = runner.call("get_current_task")
		var object_id: String = String(task.get("objectId", ""))
		if object_id.is_empty():
			runner.call("complete_current_by_touch")
		else:
			runner.call("on_object_chosen", object_id)
	return steps


func _distinct_task_count(tasks: Array) -> int:
	var seen: Dictionary = {}
	for task: Variant in tasks:
		seen[String((task as Dictionary).get("taskId", ""))] = true
	return seen.size()


func _real_library() -> RefCounted:
	var script: GDScript = load(LIBRARY_PATH) as GDScript
	if script == null:
		return null
	return script.create()
