class_name TaskPicker
extends RefCounted

## Pure, deterministic random task selection with immediate-repetition control.
##
## Has no scene, autoload or file dependency, so it is fully unit-testable:
## seed it and the sequence is reproducible.
##
## Core guarantee: as long as the candidate pool holds more than one distinct
## `taskId`, `pick()` never returns the same task twice in a row. With a pool of
## exactly one task it returns that task rather than failing, because a child
## should never be left with nothing to do.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_task_id: String = ""


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Makes the picker reproducible. Any non-zero seed yields a fixed sequence.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Forgets the last pick without changing the random stream.
func reset() -> void:
	_last_task_id = ""


func get_last_task_id() -> String:
	return _last_task_id


## Lets a caller (e.g. a resumed mission) declare what was just played so the
## next `pick()` still avoids an immediate repeat.
func set_last_task_id(task_id: String) -> void:
	_last_task_id = task_id


## Picks a task dictionary from `tasks`. Returns `{}` for an empty/invalid pool.
func pick(tasks: Array) -> Dictionary:
	var candidates: Array = _valid_tasks(tasks)
	if candidates.is_empty():
		return {}

	var pool: Array = _without_last(candidates)
	if pool.is_empty():
		pool = candidates

	var chosen: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	_last_task_id = String(chosen.get("taskId", ""))
	return chosen.duplicate(true)


## Id-only variant, for callers that already hold their own task index.
func pick_id(task_ids: Array) -> String:
	var candidates: Array = []
	for task_id: Variant in task_ids:
		var text: String = String(task_id)
		if not text.is_empty():
			candidates.append(text)
	if candidates.is_empty():
		return ""

	var pool: Array = []
	for task_id: String in candidates:
		if task_id != _last_task_id:
			pool.append(task_id)
	if pool.is_empty():
		pool = candidates

	var chosen: String = pool[_rng.randi_range(0, pool.size() - 1)]
	_last_task_id = chosen
	return chosen


## Picks `count` tasks in a row, honouring the no-immediate-repeat rule between
## consecutive picks. Tasks may recur later in the sequence, which is what makes
## short pools replayable.
func pick_many(tasks: Array, count: int) -> Array:
	var result: Array = []
	for _i: int in range(max(0, count)):
		var task: Dictionary = pick(tasks)
		if task.is_empty():
			break
		result.append(task)
	return result


## A randomised ordering that uses every task exactly once and contains no two
## adjacent entries with the same `taskId`. Use this for mission task order.
func shuffle_sequence(tasks: Array) -> Array:
	var candidates: Array = _valid_tasks(tasks)
	if candidates.size() <= 1:
		return _duplicate_all(candidates)

	var shuffled: Array = candidates.duplicate()
	for i: int in range(shuffled.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: Variant = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap

	_separate_adjacent_duplicates(shuffled)

	if not shuffled.is_empty():
		_last_task_id = String((shuffled[shuffled.size() - 1] as Dictionary).get("taskId", ""))
	return _duplicate_all(shuffled)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _valid_tasks(tasks: Variant) -> Array:
	if typeof(tasks) != TYPE_ARRAY:
		return []
	var result: Array = []
	for entry: Variant in (tasks as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if String((entry as Dictionary).get("taskId", "")).is_empty():
			continue
		result.append(entry)
	return result


func _without_last(candidates: Array) -> Array:
	var pool: Array = []
	for task: Variant in candidates:
		if String((task as Dictionary).get("taskId", "")) != _last_task_id:
			pool.append(task)
	return pool


## Swaps any entry that repeats its predecessor towards a later, non-conflicting
## slot. Best-effort: identical ids can be unavoidable if a pool is degenerate.
static func _separate_adjacent_duplicates(shuffled: Array) -> void:
	for i: int in range(1, shuffled.size()):
		var previous_id: String = String((shuffled[i - 1] as Dictionary).get("taskId", ""))
		if String((shuffled[i] as Dictionary).get("taskId", "")) != previous_id:
			continue
		for j: int in range(i + 1, shuffled.size()):
			var candidate_id: String = String((shuffled[j] as Dictionary).get("taskId", ""))
			if candidate_id == previous_id:
				continue
			var next_id: String = ""
			if i + 1 < shuffled.size():
				next_id = String((shuffled[i + 1] as Dictionary).get("taskId", ""))
			if candidate_id == next_id:
				continue
			var swap: Variant = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = swap
			break


static func _duplicate_all(tasks: Array) -> Array:
	var result: Array = []
	for task: Variant in tasks:
		result.append((task as Dictionary).duplicate(true))
	return result
