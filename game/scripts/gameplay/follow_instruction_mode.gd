class_name FollowInstructionMode
extends "res://scripts/gameplay/mode_handler.gd"

## Mini-game C -- "Follow the Instruction".
##
## "Give me the blue shirt.", "Put the teddy in the toy box.", "Give me some
## milk." The named object must reach the zone named by the task's `interaction`
## field: `dragToMouth`, `dragToHug`, `dragToBath`, `dragToDress`,
## `dragToToyBox` (and `tap`, which resolves to the baby's hands).
##
## `DropZone.zone_id_for_interaction()` is the only mapping, so content can never
## reference a zone that does not exist -- `test_gameplay_drop_zones` asserts
## that every `interaction` value shipped in `content/**` resolves.
##
## ## Tap fallback
##
## `DraggableObject` already routes a plain tap into the same delivery latch as a
## successful drag, and both arrive here through `on_object_chosen()`. A child
## who cannot drag therefore completes the task identically, with the same
## reward. Dropping the object somewhere else is not a failure: it just slides
## home and can be picked up again.

const MODE_NAME: String = "followInstruction"
const DROP_ZONE_PATH: String = "res://scripts/gameplay/drop_zone.gd"

## Smaller than Find It: this mode is about the *action*, so one or two
## alternatives keep it a real choice without crowding the drag path.
const DISTRACTOR_COUNT: int = 2


func get_mode_name() -> String:
	return MODE_NAME


func _on_start() -> void:
	var target_id: String = get_target_object_id()
	if target_id.is_empty():
		return
	var choices: Array = build_choice_ids(target_id, _distractor_pool(), DISTRACTOR_COUNT, _rng)
	# Distractors get the same drop zone on purpose: delivering the wrong thing
	# must be *possible*, so it can be answered kindly rather than ignored.
	_spawn_choices(choices, get_zone_id())


## The zone this task delivers into, or "" for a tap-only task.
func get_zone_id() -> String:
	var script: GDScript = load(DROP_ZONE_PATH) as GDScript
	if script == null:
		return ""
	return String(script.zone_id_for_interaction(String(_task.get("interaction", ""))))


func get_interaction() -> String:
	return String(_task.get("interaction", ""))


func _handle_choice(object_id: String) -> void:
	if object_id == get_target_object_id():
		_succeed()
		return
	_gentle_retry(object_id)
