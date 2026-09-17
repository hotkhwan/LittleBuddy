extends RefCounted

## Four invariants that a mutation sweep proved nothing was actually checking.
##
## Each one below was broken on purpose, the whole suite was run, and the suite
## stayed GREEN. They are the quiet kind: nothing visible fails on the day they
## are violated, so they are pinned here with the mutation that survived recorded
## next to each.
##
##   1. `ModeHandler.on_object_chosen()` ignores a touch when no task is running.
##      Mutation: `if not _active or _completed: return` -> `if false:`. SURVIVED.
##   2. `ModeHandler._succeed()` is latched. Mutation: `if _completed: return` ->
##      `if false:`. SURVIVED -- it is layer 2 of the three-layer no-double-award
##      defence and the only untested one.
##   3. `ContentValidator`'s semantic-target scan refuses to report success when
##      it found nothing to check. Mutation: the `MIN_SEMANTIC_TARGET_REFERENCES`
##      floor removed. SURVIVED -- a validator that scans nothing passes forever,
##      which is a failure shape this project has already shipped three times.
##   4. A missing microphone is never a dead end, and never a score.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const FIND_IT_PATH: String = "res://scripts/gameplay/find_it_mode.gd"
const SAY_IT_PATH: String = "res://scripts/gameplay/say_it_mode.gd"
const VALIDATOR_PATH: String = "res://scripts/content/content_validator.gd"
const CONTENT_INDEX: String = "res://content/index.json"


## A content library with nothing in it, shaped exactly as
## `collect_semantic_target_references()` expects. Used to ask the validator the
## one question it must never answer with "fine": "you found no references at
## all -- is that a pass?"
class EmptyLibrary extends RefCounted:
	func get_tasks() -> Array:
		return []

	func get_missions() -> Array:
		return []

	func get_objects() -> Array:
		return []

	func get_stickers() -> Array:
		return []

	func get_words() -> Array:
		return []


func test_name() -> String:
	return "robust_invariants"


func run():
	var failures: Array = []
	failures.append_array(_test_a_touch_with_no_task_running_does_nothing())
	failures.append_array(_test_success_is_latched())
	failures.append_array(_test_the_semantic_scan_refuses_to_pass_vacuously())
	failures.append_array(_test_no_microphone_is_never_a_dead_end())
	return failures


## -- 1. A touch with no task running --------------------------------------------

## Between two tasks -- and after a cancel -- objects from the last task can still
## be on screen for a frame or two, and a four-year-old's finger is still coming
## down. Such a touch must be swallowed entirely.
##
## It is not enough that it cannot COMPLETE anything: if it reaches
## `_gentle_retry()` it emits `task_failed_gently`, `MissionRunner` counts it
## towards `MAX_GENTLE_ATTEMPTS`, and three stray taps between tasks would make
## the runner give up on a task the child had not even been shown yet.
func _test_a_touch_with_no_task_running_does_nothing():
	var failures: Array = []
	var script: GDScript = load(FIND_IT_PATH) as GDScript
	if script == null:
		return ["could not load %s" % FIND_IT_PATH]

	var handler: Node = script.new()
	var gentle: Array = []
	var encouragements: Array = []
	var completions: Array = []
	handler.connect("task_failed_gently", func() -> void: gentle.append(1))
	handler.connect("encouragement", func(text: String) -> void: encouragements.append(text))
	handler.connect("task_completed",
			func(task_id: String, _stars: int) -> void: completions.append(task_id))

	# (a) Never started.
	for _i: int in range(5):
		handler.call("on_object_chosen", "teddy")
	if not gentle.is_empty() or not encouragements.is_empty():
		failures.append(("a touch before any task started produced %d gentle retries and %s. "
				+ "Three of those in a row make MissionRunner abandon the NEXT task.")
				% [gentle.size(), str(encouragements)])
	if int(handler.call("get_attempt_count")) != 0:
		failures.append("a touch before any task started was counted as an attempt")
	if not completions.is_empty():
		failures.append("a touch before any task started completed something")

	# (b) After a cancel -- the state the house is in between tasks, and the state
	#     a backgrounded app comes back to.
	handler.call("start", _task(), {})
	handler.call("cancel")
	gentle.clear()
	encouragements.clear()
	for _i: int in range(5):
		handler.call("on_object_chosen", "sock")
	if not gentle.is_empty() or not encouragements.is_empty():
		failures.append("a touch after cancel() was answered as a wrong choice on a task nobody "
				+ "is playing")

	# (c) After the task is finished -- the celebration is on screen and the child
	#     is still tapping.
	handler.call("start", _task(), {})
	handler.call("on_object_chosen", "teddy")
	var after: int = completions.size()
	gentle.clear()
	for _i: int in range(5):
		handler.call("on_object_chosen", "sock")
		handler.call("on_object_chosen", "teddy")
	if completions.size() != after:
		failures.append("tapping during the celebration completed the task again")
	if not gentle.is_empty():
		failures.append("tapping during the celebration was answered as a mistake; there is no "
				+ "red X in this game")

	handler.free()
	return failures


## -- 2. The success latch ---------------------------------------------------------

## `_succeed()` is documented as latched, and it is the SECOND of the three
## independent no-double-award layers (`DraggableObject`'s per-gesture latch,
## this, and `MissionRunner._award()`). The other two are tested; this one was
## not, because every public route into it is already guarded by `_active` /
## `_completed` -- which is exactly what makes it worth pinning: the layer is
## invisible until the day somebody adds a fourth caller.
##
## So this reaches past the public guards deliberately, which is the only way to
## ask whether the layer is still there at all.
func _test_success_is_latched():
	var failures: Array = []
	var script: GDScript = load(FIND_IT_PATH) as GDScript
	if script == null:
		return ["could not load %s" % FIND_IT_PATH]

	var handler: Node = script.new()
	var completions: Array = []
	handler.connect("task_completed",
			func(task_id: String, stars: int) -> void: completions.append([task_id, stars]))

	handler.call("start", _task(), {})
	for _i: int in range(6):
		handler.call("_succeed")

	if completions.size() != 1:
		failures.append(("_succeed() emitted task_completed %d times. It is layer 2 of the "
				+ "no-double-award defence; without the latch a second caller pays a second star.")
				% completions.size())
	if not bool(handler.call("is_completed")):
		failures.append("the handler did not record the task as completed")
	if bool(handler.call("is_active")):
		failures.append("a completed task is still active; a stray touch would reach it")

	handler.free()
	return failures


## -- 3. The semantic scan cannot pass by finding nothing ---------------------------

## `ContentValidator.validate_semantic_targets()` checks every
## `"<roomId>.<targetId>"` in the content against the ids the world really has.
## A scan that finds NO references has checked nothing -- and "no problems" is
## then a lie, not a pass. The floor that says so was itself unprotected.
func _test_the_semantic_scan_refuses_to_pass_vacuously():
	var failures: Array = []
	var validator: GDScript = load(VALIDATOR_PATH) as GDScript
	if validator == null:
		return ["could not load %s" % VALIDATOR_PATH]

	var world_ids: Array = ["bedroom.bed", "bathroom.sink", "kitchen.fridge"]

	# A library with nothing in it yields zero references. That must be reported.
	var empty_problems: Array = validator.call(
			"validate_semantic_targets", EmptyLibrary.new(), world_ids, CONTENT_INDEX)
	if empty_problems.is_empty():
		failures.append(("a content set with no semantic target references at all was reported as "
				+ "clean. A validator that finds nothing to check reports no problems forever -- "
				+ "this project has already shipped three guards of exactly that shape."))

	var floor_value: int = int(validator.get("MIN_SEMANTIC_TARGET_REFERENCES"))
	if floor_value <= 0:
		failures.append("MIN_SEMANTIC_TARGET_REFERENCES is %d; the anti-vacuity floor is off"
				% floor_value)

	# The real content must clear that floor comfortably, or the floor is the
	# thing that will need moving and nobody will notice which.
	var library_script: GDScript = load("res://scripts/content/content_library.gd") as GDScript
	if library_script != null:
		var library: RefCounted = library_script.new()
		library.call("load_all")
		var references: Array = validator.call(
				"collect_semantic_target_references", library, null, CONTENT_INDEX)
		if references.size() < floor_value:
			failures.append("the shipped content declares %d semantic target references, below the "
					% references.size() + "floor of %d" % floor_value)

		# And the scan really does reject an id the world does not have -- the
		# positive half, so this case cannot pass by being uniformly negative.
		var bogus_problems: Array = validator.call(
				"validate_semantic_targets", library, ["nowhere.atAll"], CONTENT_INDEX)
		if bogus_problems.is_empty():
			failures.append("the validator accepted the whole content set against a world that has "
					+ "none of its targets")

	# An empty world id list is a problem, not a pass.
	if (validator.call("validate_semantic_targets", EmptyLibrary.new(), [], CONTENT_INDEX)
			as Array).is_empty():
		failures.append("an empty world target list was treated as a pass")

	return failures


## -- 4. No microphone, no dead end ---------------------------------------------------

## The Speak button with nothing behind it: no backend at all, and a backend that
## reports itself unavailable (permission denied). Neither may leave the child
## poking something that does nothing, and neither may block the task.
func _test_no_microphone_is_never_a_dead_end():
	var failures: Array = []
	var script: GDScript = load(SAY_IT_PATH) as GDScript
	if script == null:
		return ["could not load %s" % SAY_IT_PATH]

	for label: String in ["no backend", "permission denied"]:
		var handler: Node = script.new()
		var completions: Array = []
		var encouragements: Array = []
		var speak_enabled: Array = []
		handler.connect("task_completed",
				func(task_id: String, _stars: int) -> void: completions.append(task_id))
		handler.connect("encouragement", func(text: String) -> void: encouragements.append(text))
		handler.connect("speak_button_enabled",
				func(enabled: bool) -> void: speak_enabled.append(enabled))

		var context: Dictionary = {}
		if label == "permission denied":
			context["speech"] = DeniedSpeech.new()
		handler.call("start", _say_it_task(), context)

		if speak_enabled.is_empty() or bool(speak_enabled[speak_enabled.size() - 1]):
			failures.append("%s: the Speak button was offered with nothing behind it" % label)

		handler.call("request_listen")
		if encouragements.is_empty():
			failures.append("%s: pressing Speak did nothing at all -- the child is left poking a "
					% label + "dead button with no way forward")
		for text: Variant in encouragements:
			var message: String = String(text)
			if message.contains("%") or message.to_lower().contains("wrong") \
					or message.to_lower().contains("score"):
				failures.append("%s: the fallback message '%s' reads as a score or a correction"
						% [label, message])

		# The task is still finishable, with its full reward, by touch.
		handler.call("on_object_chosen", "teddy")
		if completions.size() != 1:
			failures.append("%s: the task could not be completed by touch (%d completions)"
					% [label, completions.size()])
		handler.free()

	return failures


## -- Helpers --------------------------------------------------------------------------

## A speech backend that exists but says no -- the denied-microphone case.
class DeniedSpeech extends RefCounted:
	func is_available() -> bool:
		return false

	func has_permission() -> bool:
		return false

	func start_listening() -> void:
		pass


func _task() -> Dictionary:
	return {
		"taskId": "findTeddy",
		"mode": "findIt",
		"objectId": "teddy",
		"instruction": "Find the teddy.",
		"reward": {"stars": 1},
	}


func _say_it_task() -> Dictionary:
	return {
		"taskId": "sayTeddy",
		"mode": "sayIt",
		"objectId": "teddy",
		"instruction": "Can you say teddy?",
		"targetWords": ["teddy"],
		"acceptedCommands": ["teddy"],
		"reward": {"stars": 1},
	}
