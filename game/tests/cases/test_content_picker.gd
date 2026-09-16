extends RefCounted

## The random task picker must never hand a child the same task twice in a row,
## must stay deterministic under a fixed seed, and must degrade safely on empty
## or malformed input.

const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const TaskPickerScript := preload("res://scripts/content/task_picker.gd")

const SAMPLE_RUNS: int = 500


func test_name() -> String:
	return "content_picker"


func run() -> Array:
	var failures: Array = []

	var library: Object = ContentLibraryScript.new()
	if library == null:
		return ["content_library.gd could not be instantiated"]
	library.load_all()

	var tasks: Array = library.get_tasks()
	if tasks.size() < 2:
		failures.append("need at least 2 tasks to exercise the picker, got %d" % tasks.size())
		return failures

	# 1. Long run over the full pool: never an immediate repeat.
	var picker: Object = TaskPickerScript.new(12345)
	var previous_id: String = ""
	var distinct: Dictionary = {}
	for i: int in range(SAMPLE_RUNS):
		var task: Dictionary = picker.pick(tasks)
		if task.is_empty():
			failures.append("pick() returned nothing on iteration %d" % i)
			break
		var task_id: String = String(task.get("taskId", ""))
		if task_id == previous_id:
			failures.append("pick() repeated '%s' immediately at iteration %d" % [task_id, i])
			break
		distinct[task_id] = true
		previous_id = task_id

	# A healthy picker should reach most of the pool over 500 draws.
	if distinct.size() < int(tasks.size() * 0.75):
		failures.append(
			"pick() only produced %d of %d tasks over %d draws"
			% [distinct.size(), tasks.size(), SAMPLE_RUNS]
		)

	# 2. Same guarantee inside a single small category pool (the tight case).
	for category: String in ["feeding", "dressing", "bath", "play", "bedtime"]:
		var category_tasks: Array = library.get_tasks_in_category(category)
		if category_tasks.size() < 2:
			continue
		var category_picker: Object = TaskPickerScript.new(999)
		var last_id: String = ""
		for i: int in range(60):
			var task: Dictionary = category_picker.pick(category_tasks)
			var task_id: String = String(task.get("taskId", ""))
			if task_id == last_id:
				failures.append("pick() repeated '%s' in category '%s'" % [task_id, category])
				break
			last_id = task_id

	# 3. pick_id() honours the same rule.
	var id_picker: Object = TaskPickerScript.new(4242)
	var ids: Array = Array(library.get_task_ids())
	var last_picked: String = ""
	for i: int in range(200):
		var picked: String = id_picker.pick_id(ids)
		if picked.is_empty():
			failures.append("pick_id() returned an empty id at iteration %d" % i)
			break
		if picked == last_picked:
			failures.append("pick_id() repeated '%s' immediately" % picked)
			break
		last_picked = picked

	# 4. pick_many() produces a run with no adjacent repeats.
	var many_picker: Object = TaskPickerScript.new(777)
	var sequence: Array = many_picker.pick_many(tasks, 40)
	if sequence.size() != 40:
		failures.append("pick_many() returned %d of 40 tasks" % sequence.size())
	failures.append_array(_check_no_adjacent_repeats(sequence, "pick_many"))

	# 5. shuffle_sequence() uses every task once, in a new order, no adjacents.
	var shuffle_picker: Object = TaskPickerScript.new(2024)
	var mission_tasks: Array = library.get_mission_tasks("feedingTime")
	if mission_tasks.size() < 2:
		failures.append("mission 'feedingTime' resolved fewer than 2 tasks")
	else:
		var shuffled: Array = shuffle_picker.shuffle_sequence(mission_tasks)
		if shuffled.size() != mission_tasks.size():
			failures.append(
				"shuffle_sequence() returned %d of %d tasks"
				% [shuffled.size(), mission_tasks.size()]
			)
		failures.append_array(_check_no_adjacent_repeats(shuffled, "shuffle_sequence"))
		failures.append_array(_check_same_multiset(mission_tasks, shuffled))

	# 6. A single-task pool returns that task instead of failing.
	var single_picker: Object = TaskPickerScript.new(5)
	var single: Array = [tasks[0]]
	var first: Dictionary = single_picker.pick(single)
	var second: Dictionary = single_picker.pick(single)
	if first.is_empty() or second.is_empty():
		failures.append("a single-task pool must still return that task")

	# 7. Empty / malformed input degrades safely.
	var safe_picker: Object = TaskPickerScript.new(1)
	if not (safe_picker.pick([]) as Dictionary).is_empty():
		failures.append("pick([]) must return an empty dictionary")
	if not (safe_picker.pick([1, "nope", null]) as Dictionary).is_empty():
		failures.append("pick() must ignore entries that are not tasks")
	if safe_picker.pick_id([]) != "":
		failures.append("pick_id([]) must return an empty string")

	# 8. Determinism: the same seed replays the same sequence.
	var run_a: Array = _sequence_with_seed(tasks, 31337)
	var run_b: Array = _sequence_with_seed(tasks, 31337)
	if run_a != run_b:
		failures.append("picker is not deterministic for a fixed seed")

	return failures


func _sequence_with_seed(tasks: Array, seed_value: int) -> Array:
	var picker: Object = TaskPickerScript.new(seed_value)
	var ids: Array = []
	for i: int in range(25):
		ids.append(String((picker.pick(tasks) as Dictionary).get("taskId", "")))
	return ids


func _check_no_adjacent_repeats(sequence: Array, label: String) -> Array:
	var failures: Array = []
	for i: int in range(1, sequence.size()):
		var current: String = String((sequence[i] as Dictionary).get("taskId", ""))
		var previous: String = String((sequence[i - 1] as Dictionary).get("taskId", ""))
		if current == previous:
			failures.append("%s: '%s' repeats at position %d" % [label, current, i])
	return failures


func _check_same_multiset(expected: Array, actual: Array) -> Array:
	var expected_ids: Array = []
	for task: Variant in expected:
		expected_ids.append(String((task as Dictionary).get("taskId", "")))
	var actual_ids: Array = []
	for task: Variant in actual:
		actual_ids.append(String((task as Dictionary).get("taskId", "")))
	expected_ids.sort()
	actual_ids.sort()
	if expected_ids != actual_ids:
		return ["shuffle_sequence() changed which tasks are in the mission"]
	return []
