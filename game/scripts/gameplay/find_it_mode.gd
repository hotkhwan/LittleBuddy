class_name FindItMode
extends "res://scripts/gameplay/mode_handler.gd"

## Mini-game A -- "Find It".
##
## The baby asks for one object ("Find the teddy.", "Where is the milk?"). The
## target is spawned alongside 2-3 distractors drawn from the same category, and
## the child taps (or drags) the one they think is right.
##
## Child-UX rules, enforced here:
##   - a wrong choice is answered with a short kind phrase and the prompt is
##     repeated; the object slides home and the task stays RUNNING,
##   - no red X, no score, no percentage, no timer, no "you lose",
##   - the target is always on screen (see `ModeHandler.build_choice_ids`), so
##     the task is always winnable,
##   - after a few gentle misses `MissionRunner` opens a way forward, so even a
##     child who never finds it moves on happily.

const MODE_NAME: String = "findIt"

## 3 distractors + the target = 4 touch targets, which is what the Baby Room's
## spawn row is sized for. Fewer if the category is small.
const DISTRACTOR_COUNT: int = 3


func get_mode_name() -> String:
	return MODE_NAME


func _on_start() -> void:
	var target_id: String = get_target_object_id()
	if target_id.is_empty():
		return
	var choices: Array = build_review_choice_ids(target_id, _distractor_pool(), DISTRACTOR_COUNT)
	# Tap-only mode: no drop zone, so a tap is the whole interaction and a drag
	# that goes nowhere simply springs back.
	_spawn_choices(choices)


## `ModeHandler._handle_choice()` already implements exactly the right
## behaviour (target -> `_succeed()`, anything else -> `_gentle_retry()`);
## spelled out here so the mode reads as a complete mini-game on its own.
func _handle_choice(object_id: String) -> void:
	if object_id == get_target_object_id():
		_succeed()
		return
	_gentle_retry(object_id)
