extends RefCounted

## The three mini-game mode handlers, driven purely through their common
## interface. No scene, no autoloads: handlers with no object anchor in their
## context skip spawning and stay fully drivable via `on_object_chosen()`.

const FIND_IT_PATH: String = "res://scripts/gameplay/find_it_mode.gd"
const SAY_IT_PATH: String = "res://scripts/gameplay/say_it_mode.gd"
const FOLLOW_PATH: String = "res://scripts/gameplay/follow_instruction_mode.gd"
const MODE_HANDLER_PATH: String = "res://scripts/gameplay/mode_handler.gd"
const LIBRARY_PATH: String = "res://scripts/content/content_library.gd"

var find_task: Dictionary = {
	"taskId": "findTeddy", "category": "play", "mode": "findIt", "objectId": "teddy",
	"targetWords": ["teddy"], "prompt": "Where is the teddy?", "instruction": "Find the teddy.",
	"repeatPrompt": "Can you say teddy?", "acceptedCommands": ["teddy"],
	"interaction": "tap", "reward": {"stars": 1},
}

var say_task: Dictionary = {
	"taskId": "sayMilk", "category": "feeding", "mode": "sayIt", "objectId": "milk",
	"targetWords": ["milk"], "prompt": "This is milk.", "instruction": "Say milk.",
	"repeatPrompt": "Can you say milk?",
	"acceptedCommands": ["milk", "this is milk", "i say milk"],
	"interaction": "tap", "reward": {"stars": 1},
}

var follow_task: Dictionary = {
	"taskId": "feedMilk", "category": "feeding", "mode": "followInstruction", "objectId": "milk",
	"targetWords": ["milk"], "prompt": "I'm hungry.", "instruction": "Give the baby some milk.",
	"repeatPrompt": "Can you say milk?", "acceptedCommands": ["milk", "give the baby some milk"],
	"interaction": "dragToMouth", "reward": {"stars": 1},
}


func test_name() -> String:
	return "gameplay_modes"


func run():
	var failures: Array = []
	failures.append_array(_test_find_it_wrong_choice_is_kind())
	failures.append_array(_test_no_double_completion_on_mash())
	failures.append_array(_test_say_it_completes_by_touch_without_speech())
	failures.append_array(_test_say_it_speech_path())
	failures.append_array(_test_follow_instruction_zone_and_tap())
	failures.append_array(_test_choice_set_always_contains_target())
	failures.append_array(_test_every_shipped_task_has_a_touch_path())
	failures.append_array(_test_spawning_into_an_anchor())
	return failures


## End-to-end wiring: with an object anchor in the context, a handler really does
## build touchable objects from `objects.json` and completes when the target
## reports it was chosen.
func _test_spawning_into_an_anchor() -> Array:
	var failures: Array = []
	var library_script: GDScript = load(LIBRARY_PATH) as GDScript
	if library_script == null:
		return ["could not load %s" % LIBRARY_PATH]
	var library: RefCounted = library_script.create()
	if library == null:
		return ["ContentLibrary.create() returned null"]

	var anchor: Node3D = Node3D.new()
	var zone: Area3D = load("res://scripts/gameplay/drop_zone.gd").create("mouth", 0.26)
	var handler: Node = _make(FOLLOW_PATH)
	var completed: Array = []
	handler.connect("task_completed", func(id: String, _s: int) -> void: completed.append(id))

	var task: Dictionary = library.get_task("feedMilk")
	if task.is_empty():
		anchor.free()
		zone.free()
		handler.free()
		return ["ContentLibrary has no 'feedMilk' task to stage"]

	handler.call("start", task, {
		"library": library,
		"objectAnchor": anchor,
		"dropZones": {"mouth": zone},
		"spawnPoints": [Vector3(-0.72, 0.1, 0.72), Vector3(-0.24, 0.1, 0.72),
				Vector3(0.24, 0.1, 0.72), Vector3(0.72, 0.1, 0.72)],
	})

	var spawned: Array = handler.call("get_spawned_objects")
	if spawned.size() < 2:
		failures.append("expected the target plus distractors, got %d objects" % spawned.size())

	var target_found: bool = false
	var positions: Dictionary = {}
	for node: Variant in spawned:
		var object_node: Node3D = node
		var object_id: String = String(object_node.get("object_id"))
		if object_id == "milk":
			target_found = true
		if not object_node.has_signal("chosen"):
			failures.append("spawned '%s' has no 'chosen' signal" % object_id)
		if object_node.get_parent() != anchor:
			failures.append("spawned '%s' was not parented to the anchor" % object_id)
		var key: String = str(object_node.position)
		if positions.has(key):
			failures.append("two objects were spawned on top of each other at %s" % key)
		positions[key] = true
	if not target_found:
		failures.append("the task's own object was not spawned -- the task is unwinnable")

	# Firing the object's own signal is exactly what a tap or a drag delivery does.
	for node: Variant in spawned:
		if String((node as Node3D).get("object_id")) == "milk":
			(node as Node3D).emit_signal("chosen", "milk")
	if completed.size() != 1:
		failures.append("delivering the spawned target did not complete the task")

	handler.call("cancel")
	if not Array(handler.call("get_spawned_objects")).is_empty():
		failures.append("cancel() left spawned objects behind")

	handler.free()
	zone.free()
	anchor.free()
	return failures


## A wrong tap must NOT award, must NOT end the task, and must produce a short
## kind phrase -- never a score, never a red X.
func _test_find_it_wrong_choice_is_kind() -> Array:
	var failures: Array = []
	var handler: Node = _make(FIND_IT_PATH)
	if handler == null:
		return ["could not instantiate %s" % FIND_IT_PATH]

	var completed: Array = []
	var gentle: Array = []
	var phrases: Array = []
	handler.connect("task_completed", func(id: String, stars: int) -> void: completed.append([id, stars]))
	handler.connect("task_failed_gently", func() -> void: gentle.append(true))
	handler.connect("encouragement", func(text: String) -> void: phrases.append(text))

	handler.call("start", find_task, {})
	handler.call("on_object_chosen", "ball")
	handler.call("on_object_chosen", "block")

	if not completed.is_empty():
		failures.append("a wrong choice awarded stars: %s" % str(completed))
	if gentle.size() != 2:
		failures.append("expected 2 gentle responses, got %d" % gentle.size())
	if not bool(handler.call("is_active")):
		failures.append("a wrong choice ended the task -- the child is stuck")
	if int(handler.call("get_attempt_count")) != 2:
		failures.append("attempt count did not track the two misses")
	for phrase: Variant in phrases:
		var text: String = String(phrase)
		if text.contains("%") or text.contains("X") or text.to_lower().contains("wrong"):
			failures.append("discouraging feedback shown to the child: '%s'" % text)

	# ...and the task is still winnable afterwards.
	handler.call("on_object_chosen", "teddy")
	if completed.size() != 1:
		failures.append("the task was not completable after two misses")

	handler.free()
	return failures


## Mashing tap + re-delivery must complete a task exactly once (layer 2 of the
## three no-double-award layers; `MissionRunner._award` is the authoritative one).
func _test_no_double_completion_on_mash() -> Array:
	var failures: Array = []
	for path: String in [FIND_IT_PATH, SAY_IT_PATH, FOLLOW_PATH]:
		var task: Dictionary = find_task
		if path == SAY_IT_PATH:
			task = say_task
		elif path == FOLLOW_PATH:
			task = follow_task

		var handler: Node = _make(path)
		if handler == null:
			failures.append("could not instantiate %s" % path)
			continue
		var completed: Array = []
		handler.connect("task_completed", func(id: String, stars: int) -> void: completed.append([id, stars]))

		handler.call("start", task, {})
		var target: String = String(task.get("objectId", ""))
		for _i: int in range(6):
			handler.call("on_object_chosen", target)
		handler.call("complete_by_touch")
		handler.call("on_transcript", "milk")

		if completed.size() != 1:
			failures.append("%s completed %d times under mashing, expected exactly 1"
					% [path, completed.size()])
		handler.free()
	return failures


## The mic must never be a gate: with no speech service in the context, touch
## still finishes the task with the full reward.
func _test_say_it_completes_by_touch_without_speech() -> Array:
	var failures: Array = []
	var handler: Node = _make(SAY_IT_PATH)
	if handler == null:
		return ["could not instantiate %s" % SAY_IT_PATH]

	var completed: Array = []
	var speak_button: Array = []
	var phrases: Array = []
	handler.connect("task_completed", func(id: String, stars: int) -> void: completed.append([id, stars]))
	handler.connect("speak_button_enabled", func(enabled: bool) -> void: speak_button.append(enabled))
	handler.connect("encouragement", func(text: String) -> void: phrases.append(text))

	handler.call("start", say_task, {})
	if speak_button.is_empty() or bool(speak_button[speak_button.size() - 1]):
		failures.append("Speak button was offered with no speech backend available")

	# Pressing it anyway must point at the touch path, not dead-end.
	handler.call("request_listen")
	if not phrases.has(String(load(SAY_IT_PATH).TOUCH_HINT)):
		failures.append("pressing an unavailable Speak button gave no touch hint")

	handler.call("on_object_chosen", "milk")
	if completed.size() != 1:
		failures.append("tapping the object did not complete the sayIt task")
	elif int((completed[0] as Array)[1]) != 1:
		failures.append("touch completion paid a different reward than the speech path")

	handler.free()

	# And the explicit forward path works too.
	var second: Node = _make(SAY_IT_PATH)
	var second_completed: Array = []
	second.connect("task_completed", func(id: String, stars: int) -> void: second_completed.append(id))
	second.call("start", say_task, {})
	second.call("complete_by_touch")
	if second_completed.size() != 1:
		failures.append("complete_by_touch() did not finish the sayIt task")
	second.free()

	return failures


## Tolerant matching, and a non-match that is a nudge rather than a score.
func _test_say_it_speech_path() -> Array:
	var failures: Array = []
	var say_it: GDScript = load(SAY_IT_PATH) as GDScript
	if say_it == null:
		return ["could not load %s" % SAY_IT_PATH]

	for phrase: String in ["milk", "Milk.", "this is milk", "I say milk"]:
		if not bool(say_it.matches_task(phrase, say_task)):
			failures.append("accepted phrase '%s' did not match sayMilk" % phrase)
	if bool(say_it.matches_task("banana", say_task)):
		failures.append("an unrelated word matched sayMilk")

	var handler: Node = _make(SAY_IT_PATH)
	var completed: Array = []
	var gentle: Array = []
	handler.connect("task_completed", func(id: String, _s: int) -> void: completed.append(id))
	handler.connect("task_failed_gently", func() -> void: gentle.append(true))

	handler.call("start", say_task, {})
	handler.call("on_transcript", "elephant")
	if not completed.is_empty():
		failures.append("a non-matching transcript completed the task")
	if gentle.size() != 1:
		failures.append("a non-matching transcript gave no gentle response")
	if not bool(handler.call("is_active")):
		failures.append("a non-matching transcript ended the task -- the child is stuck")

	handler.call("on_transcript", "milk")
	if completed.size() != 1:
		failures.append("a matching transcript did not complete the task")
	handler.free()
	return failures


## The instruction mode must resolve its zone from content, and a plain tap must
## still finish the task (the drag-free fallback).
func _test_follow_instruction_zone_and_tap() -> Array:
	var failures: Array = []
	var handler: Node = _make(FOLLOW_PATH)
	if handler == null:
		return ["could not instantiate %s" % FOLLOW_PATH]

	var completed: Array = []
	handler.connect("task_completed", func(id: String, _s: int) -> void: completed.append(id))
	handler.call("start", follow_task, {})

	if String(handler.call("get_zone_id")) != "mouth":
		failures.append("dragToMouth resolved to zone '%s', expected 'mouth'"
				% String(handler.call("get_zone_id")))

	handler.call("on_object_chosen", "milk")
	if completed.size() != 1:
		failures.append("a tap did not complete a followInstruction task")
	handler.free()

	# Every drag interaction shipped in content resolves to a zone id.
	var expected: Dictionary = {
		"dragToMouth": "mouth", "dragToHug": "hug", "dragToBath": "bath",
		"dragToDress": "dress", "dragToToyBox": "toyBox", "tap": "hand",
	}
	for interaction: Variant in expected.keys():
		var probe: Node = _make(FOLLOW_PATH)
		var task: Dictionary = follow_task.duplicate(true)
		task["interaction"] = String(interaction)
		probe.call("start", task, {})
		if String(probe.call("get_zone_id")) != String(expected[interaction]):
			failures.append("interaction '%s' resolved to '%s', expected '%s'"
					% [str(interaction), String(probe.call("get_zone_id")), str(expected[interaction])])
		probe.free()

	return failures


## The answer must always be on screen -- otherwise the task is unwinnable.
func _test_choice_set_always_contains_target() -> Array:
	var failures: Array = []
	var base: GDScript = load(MODE_HANDLER_PATH) as GDScript
	if base == null:
		return ["could not load %s" % MODE_HANDLER_PATH]

	var pool: Array = [
		{"objectId": "ball"}, {"objectId": "block"}, {"objectId": "teddy"}, {"objectId": "star"},
	]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(1, 25):
		rng.seed = seed_value
		var choices: Array = base.build_choice_ids("teddy", pool, 3, rng)
		if not choices.has("teddy"):
			failures.append("choice set for seed %d omitted the target" % seed_value)
		if choices.size() != 4:
			failures.append("choice set for seed %d had %d entries, expected 4"
					% [seed_value, choices.size()])
		var unique: Dictionary = {}
		for id: Variant in choices:
			unique[String(id)] = true
		if unique.size() != choices.size():
			failures.append("choice set for seed %d contained a duplicate" % seed_value)

	# A category with nothing else in it still yields a playable single choice.
	var lonely: Array = base.build_choice_ids("teddy", [{"objectId": "teddy"}], 3, rng)
	if lonely != ["teddy"]:
		failures.append("an empty distractor pool did not degrade to the target alone: %s" % str(lonely))

	return failures


## Sweep the real content: every shipped task must be completable by touch alone
## through its mode handler.
func _test_every_shipped_task_has_a_touch_path() -> Array:
	var failures: Array = []
	var library_script: GDScript = load(LIBRARY_PATH) as GDScript
	if library_script == null:
		return ["could not load %s" % LIBRARY_PATH]
	var library: RefCounted = library_script.create()
	if library == null:
		return ["ContentLibrary.create() returned null"]

	var scripts: Dictionary = {
		"findIt": FIND_IT_PATH, "sayIt": SAY_IT_PATH, "followInstruction": FOLLOW_PATH,
	}
	var checked: int = 0
	for task: Variant in library.get_tasks():
		var task_dict: Dictionary = task
		var mode: String = String(task_dict.get("mode", ""))
		if not scripts.has(mode):
			failures.append("task '%s' has unknown mode '%s'"
					% [String(task_dict.get("taskId", "")), mode])
			continue
		var handler: Node = _make(String(scripts[mode]))
		if handler == null:
			failures.append("could not instantiate handler for mode '%s'" % mode)
			continue
		var completed: Array = []
		handler.connect("task_completed", func(id: String, stars: int) -> void: completed.append([id, stars]))
		handler.call("start", task_dict, {"library": library})
		handler.call("on_object_chosen", String(task_dict.get("objectId", "")))
		if completed.size() != 1:
			failures.append("task '%s' (%s) could not be completed by touch"
					% [String(task_dict.get("taskId", "")), mode])
		handler.free()
		checked += 1

	if checked < 40:
		failures.append("expected to sweep the whole task set, only checked %d" % checked)
	return failures


func _make(path: String) -> Node:
	var script: GDScript = load(path) as GDScript
	if script == null:
		return null
	var handler: Node = script.new()
	if handler.has_method("set_seed"):
		handler.call("set_seed", 12345)
	return handler
