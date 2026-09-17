extends "res://scripts/gameplay/mission_runner.gd"

## `MissionRunner`, with one thing changed: **a day happens in order.**
##
## The base runner shuffles a mission's tasks (`TaskPicker.shuffle_sequence`),
## and for the Baby Room that is right -- "give the baby some milk" and "find the
## spoon" are independent beats, and shuffling is what keeps a five-task routine
## replayable. In Chapter 3 the order IS the content:
##
##     wake up -> walk to the bathroom -> brush your teeth -> dry your face
##
## Shuffled, that becomes "rinse with the cup" in the bedroom before the child has
## ever walked to the bathroom -- a level that still technically completes, and
## teaches nothing about a morning. `missions.json` authors `taskIds` in story
## order and `docs/SLICE_CONTRACT.md` §1 lists the beats in that order, so the
## authored order is the intended one and this is the only override needed.
##
## EVERYTHING else is inherited untouched, deliberately: the single-award guard
## (`_award`), the gentle-miss escape hatch, `skip_current_task()`, the unplayable
## filter, the signals and the "an empty mission still emits `mission_completed`"
## promise all remain the base class's, with one implementation and one place to
## fix a bug. `mission_runner.gd` itself is domain code under
## `test_architecture_guard` and is not edited here -- this is a subclass, and it
## adds no 3D reference of its own either.

## The authored order, filtered exactly as the base class filters it: a task that
## cannot be finished by touch is dropped rather than presented and then found to
## be impossible.
##
## Mirrors `MissionRunner._ordered_tasks()` minus the shuffle. Kept deliberately
## small for that reason -- if the filtering rule ever changes, this needs to
## change with it, and a five-line body makes that obvious.
func _ordered_tasks(mission_id: String, library: Object) -> Array:
	var raw: Array = []
	if library != null and library.has_method("get_mission_tasks"):
		raw = library.get_mission_tasks(mission_id)

	var playable: Array = []
	for task: Variant in raw:
		if describe_unplayable(task, library).is_empty():
			playable.append(task)
	return playable
