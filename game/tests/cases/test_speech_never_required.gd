extends RefCounted
## The microphone is never a gate.
##
## Speech recognition on this project is optional, on-device and frozen. What
## must be defended forever is the other half of that promise: a child whose
## microphone is unavailable, denied, broken, or who is simply too shy to speak,
## must be able to finish **every** task and **every** mission by touch alone,
## for the same reward.
##
## Every task in the shipped content is driven here with NO speech service at
## all, and then again with a speech service that reports itself unavailable and
## permission denied -- the two shapes of "no microphone" that exist on a real
## device.

const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")

const MODE_SCRIPTS: Dictionary = {
	"findIt": "res://scripts/gameplay/find_it_mode.gd",
	"sayIt": "res://scripts/gameplay/say_it_mode.gd",
	"followInstruction": "res://scripts/gameplay/follow_instruction_mode.gd",
}


## Stands in for a device where the mic is unusable: permission denied, nothing
## available, and every listen attempt fails rather than hanging.
class DeadSpeechService:
	extends RefCounted
	signal recognition_failed(reason: String)

	var listen_attempts: int = 0

	func is_available() -> bool:
		return false

	func has_permission() -> bool:
		return false

	func start_listening(_locale: String = "en-US") -> void:
		listen_attempts += 1
		recognition_failed.emit("unavailable")

	func stop_listening() -> void:
		pass

	func is_listening() -> bool:
		return false


func test_name() -> String:
	return "speech_never_required"


func run():
	var failures: Array = []
	var library = ContentLibraryScript.create()
	if library == null:
		return ["could not create ContentLibrary"]

	failures.append_array(_test_content_never_demands_speech(library))
	failures.append_array(_test_every_task_completes_by_touch(library))
	failures.append_array(_test_every_mission_completes_by_touch(library))
	failures.append_array(_test_dead_microphone_is_not_a_dead_end(library))
	return failures


## Content-level guard: no shipped task may declare speech mandatory.
func _test_content_never_demands_speech(library):
	var failures: Array = []
	var checked: int = 0
	for task in library.get_tasks():
		if typeof(task) != TYPE_DICTIONARY:
			continue
		checked += 1
		var required: Variant = (task as Dictionary).get("speechRequired", false)
		if bool(required):
			failures.append(
				"%s: speechRequired is true -- speech may never gate a task"
				% String((task as Dictionary).get("taskId", "?"))
			)
	if checked == 0:
		failures.append("no tasks were checked for speechRequired")
	return failures


## Each task, with no speech service in the context at all.
func _test_every_task_completes_by_touch(library):
	var failures: Array = []
	var checked: int = 0

	for task in library.get_tasks():
		if typeof(task) != TYPE_DICTIONARY:
			continue
		var task_dict: Dictionary = task
		var mode: String = String(task_dict.get("mode", ""))
		if not MODE_SCRIPTS.has(mode):
			continue
		var script: GDScript = load(String(MODE_SCRIPTS[mode])) as GDScript
		if script == null:
			failures.append("could not load handler for mode '%s'" % mode)
			continue

		var task_id: String = String(task_dict.get("taskId", "?"))
		var expected_stars: int = 1
		if typeof(task_dict.get("reward", null)) == TYPE_DICTIONARY:
			expected_stars = int((task_dict["reward"] as Dictionary).get("stars", 1))

		# a) tapping the right object
		var handler: Node = script.new()
		handler.set_seed(7)
		var completions: Array = []
		handler.task_completed.connect(
			func(id: String, stars: int) -> void: completions.append([id, stars])
		)
		handler.start(task_dict, {"library": library})
		handler.on_object_chosen(String(task_dict.get("objectId", "")))
		if completions.size() != 1:
			failures.append(
				"%s (%s): tapping the target did not complete the task without speech"
				% [task_id, mode]
			)
		elif int(completions[0][1]) != expected_stars:
			failures.append(
				"%s: touch paid %d stars, content promises %d"
				% [task_id, int(completions[0][1]), expected_stars]
			)
		handler.cancel()
		handler.free()

		# b) the explicit "I did it" affordance
		var second: Node = script.new()
		second.set_seed(7)
		var touch_completions: Array = []
		second.task_completed.connect(
			func(id: String, stars: int) -> void: touch_completions.append([id, stars])
		)
		second.start(task_dict, {"library": library})
		second.complete_by_touch()
		if touch_completions.size() != 1:
			failures.append("%s (%s): complete_by_touch() did not finish the task" % [task_id, mode])
		elif int(touch_completions[0][1]) != expected_stars:
			failures.append("%s: complete_by_touch() paid a different reward" % task_id)
		second.cancel()
		second.free()

		checked += 1

	if checked == 0:
		failures.append("no tasks were driven by touch -- the guarantee proved nothing")
	return failures


## Whole missions, start to finish, touch only.
func _test_every_mission_completes_by_touch(library):
	var failures: Array = []
	var missions_checked: int = 0

	for mission in library.get_missions():
		if typeof(mission) != TYPE_DICTIONARY:
			continue
		var mission_id: String = String((mission as Dictionary).get("missionId", ""))
		if mission_id.is_empty():
			continue

		var runner: Node = MissionRunnerScript.new()
		runner.set_seed(3)
		var completed: Array = []
		runner.mission_completed.connect(
			func(id: String, stars: int) -> void: completed.append([id, stars])
		)

		# No `speech` and no `tts` in the context: a device with neither.
		runner.start_mission(mission_id, library, {"library": library})

		var guard: int = 0
		while runner.is_running() and guard < 64:
			guard += 1
			var task: Dictionary = runner.get_current_task()
			if task.is_empty():
				break
			runner.on_object_chosen(String(task.get("objectId", "")))

		if completed.size() != 1:
			failures.append(
				"%s: mission did not complete by touch alone (guard %d)" % [mission_id, guard]
			)
		elif int(completed[0][1]) <= 0:
			failures.append("%s: a touch-only playthrough earned no stars" % mission_id)

		runner.cancel()
		runner.free()
		missions_checked += 1

	if missions_checked == 0:
		failures.append("no missions were driven by touch")
	return failures


## A live-but-useless speech service: the Speak button must not be offered, a
## press must not hang or crash, and touch must still finish the task.
func _test_dead_microphone_is_not_a_dead_end(library):
	var failures: Array = []
	var script: GDScript = load(String(MODE_SCRIPTS["sayIt"])) as GDScript
	if script == null:
		return ["could not load sayIt handler"]

	var say_tasks: Array = library.get_tasks_with_mode("sayIt")
	if say_tasks.is_empty():
		return ["no sayIt tasks in content -- the speech path is untested"]

	for task in say_tasks:
		if typeof(task) != TYPE_DICTIONARY:
			continue
		var task_dict: Dictionary = task
		var task_id: String = String(task_dict.get("taskId", "?"))
		var speech := DeadSpeechService.new()

		var handler: Node = script.new()
		handler.set_seed(11)
		var speak_button_states: Array = []
		var completions: Array = []
		var encouragements: Array = []
		handler.speak_button_enabled.connect(
			func(enabled: bool) -> void: speak_button_states.append(enabled)
		)
		handler.task_completed.connect(
			func(_id: String, _stars: int) -> void: completions.append(true)
		)
		handler.encouragement.connect(func(text: String) -> void: encouragements.append(text))

		handler.start(task_dict, {"library": library, "speech": speech})

		if speak_button_states.has(true):
			failures.append(
				"%s: the Speak button was offered with no usable microphone" % task_id
			)

		# Pressing it anyway (a stale button, a fast child) must be harmless.
		handler.request_listen()
		if speech.listen_attempts != 0:
			failures.append("%s: listening was started on an unavailable backend" % task_id)
		if encouragements.is_empty():
			failures.append(
				"%s: a dead Speak button should still say something kind, not nothing" % task_id
			)

		# And a failed recognition is never a failure state.
		handler.on_transcript("something completely unrelated")
		if handler.is_completed():
			failures.append("%s: an unrelated transcript should not complete the task" % task_id)
		if not handler.is_active():
			failures.append(
				"%s: the task must stay playable after a failed recognition" % task_id
			)

		handler.on_object_chosen(String(task_dict.get("objectId", "")))
		if completions.is_empty():
			failures.append("%s: touch did not complete the task after a failed recognition" % task_id)

		handler.cancel()
		handler.free()

	return failures
