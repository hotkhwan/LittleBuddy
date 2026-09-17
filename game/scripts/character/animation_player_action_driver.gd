extends "res://scripts/character/character_action_driver.gd"

## Semantic actions played through an `AnimationPlayer` (or, when one arrives with
## a rigged model, an `AnimationTree` -- see `bind()`).
##
## The mapping from a semantic action id to a clip name lives HERE and nowhere
## else. When the commissioned character lands with clips called `Armature|Drink`
## or a state machine with a `drink` state, only `ACTION_CLIPS` and `bind()`
## change; `play_action("drink")` keeps working untouched.
##
## An action with no clip yet returns false from `play()` and leaves the current
## animation alone -- see the base class for why that is the safe behaviour.

## Semantic action id -> candidate clip names, best first. Several candidates per
## action so a re-exported model that renames `walk` to `Walk` or `walk_cycle`
## does not silently stop animating.
const ACTION_CLIPS: Dictionary = {
	"idle": ["idle", "Idle"],
	"walk": ["walk", "Walk", "walk_cycle"],
	"eat": ["eat", "Eat"],
	"drink": ["drink", "drinking", "Drink"],
	"sit": ["sit", "Sit"],
	"sleep": ["sleep", "Sleep", "sleeping"],
	"brushTeeth": ["brushTeeth", "brush_teeth", "BrushTeeth"],
	"hug": ["hug", "hugging", "Hug"],
	"pickUp": ["pickUp", "pick_up", "PickUp"],
	"give": ["give", "Give"],
	"celebrate": ["celebrate", "happy", "Celebrate"],
}

## Played when nothing else is. `carry_idle` is tried first while holding
## something, falling back to plain idle -- so CARRYING needs no new state.
const REST_ACTION: String = "idle"
const CARRY_REST_CLIPS: Array[String] = ["carryIdle", "carry_idle", "idle"]

var _player: AnimationPlayer = null
var _current_action: String = ""


static func create(player: AnimationPlayer = null) -> RefCounted:
	var driver: RefCounted = (
		load("res://scripts/character/animation_player_action_driver.gd") as GDScript
	).new()
	driver.call("bind", player)
	return driver


func bind(player: AnimationPlayer) -> void:
	_player = player


func can_play(action_name: String) -> bool:
	return not _clip_for(action_name).is_empty()


func play(action_name: String) -> bool:
	var clip: String = _clip_for(action_name)
	if clip.is_empty():
		# No clip authored yet. Leave whatever is playing alone and say so; the
		# movement controller still times the action out, so nothing gets stuck.
		return false
	_current_action = action_name
	if _player.current_animation != clip:
		_player.play(clip)
	return true


func rest(carrying: bool = false) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if carrying:
		for candidate: String in CARRY_REST_CLIPS:
			if _player.has_animation(candidate):
				_current_action = REST_ACTION
				if _player.current_animation != candidate:
					_player.play(candidate)
				return
	play(REST_ACTION)


func get_current_action() -> String:
	return _current_action


func _clip_for(action_name: String) -> String:
	if _player == null or not is_instance_valid(_player):
		return ""
	for candidate: Variant in ACTION_CLIPS.get(action_name, [action_name]):
		if _player.has_animation(String(candidate)):
			return String(candidate)
	return ""
