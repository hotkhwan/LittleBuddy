extends "res://scripts/character/character_action_driver.gd"

## Semantic actions played through an `AnimationPlayer`.
##
## The mapping from a semantic action id to a clip name lives HERE and nowhere
## else. When the commissioned character lands with clips called `Armature|Drink`,
## only `ACTION_CLIPS` and `bind()` change; `play_action("drink")` keeps working
## untouched.
##
## An action with no clip yet returns false from `play()` and leaves the current
## animation alone -- see the base class for why that is the safe behaviour, and
## for why this is an `AnimationPlayer` rather than an `AnimationTree`.

## Semantic action id -> candidate clip names, best first. Several candidates per
## action so a re-exported model that renames `walk` to `Walk` or `walk_cycle`
## does not silently stop animating.
##
## `hold` falls through to the carry-idle clip: cradling something and resting
## while carrying it are the same pose, and authoring it twice would guarantee
## the two drift apart.
const ACTION_CLIPS: Dictionary = {
	"idle": ["idle", "Idle"],
	"walk": ["walk", "Walk", "walk_cycle"],
	"wave": ["wave", "Wave"],
	"point": ["point", "Point", "pointing"],
	"clap": ["clap", "Clap", "clapping"],
	"pickUp": ["pickUp", "pick_up", "PickUp"],
	"hold": ["hold", "Hold", "carryIdle", "carry_idle"],
	"give": ["give", "Give"],
	"eat": ["eat", "Eat", "eating"],
	"drink": ["drink", "drinking", "Drink"],
	"brushTeeth": ["brushTeeth", "brush_teeth", "BrushTeeth"],
	"sit": ["sit", "Sit", "sitting"],
	"stand": ["stand", "Stand", "standUp", "stand_up"],
	"hug": ["hug", "hugging", "Hug"],
	"sleep": ["sleep", "Sleep", "sleeping"],
	"wake": ["wake", "Wake", "wakeUp", "wake_up"],
	"celebrate": ["celebrate", "happy", "Celebrate"],
}

## Played when nothing else is. `carryIdle` is tried first while holding
## something, falling back to plain idle -- so CARRYING needs no new state.
const REST_ACTION: String = "idle"
const CARRY_REST_CLIPS: Array[String] = ["carryIdle", "carry_idle", "idle"]

## Cross-fade between clips, seconds. The one thing an `AnimationTree` would have
## bought here, for one argument instead of a graph resource. Short enough that
## an action still reads as immediate feedback to a tap.
const ACTION_BLEND_SEC: float = 0.18

## A clip shorter than this is treated as having no meaningful length of its own
## (an empty placeholder `Animation` has length 1.0 by default but zero content),
## so the semantic default is used instead.
const MIN_MEANINGFUL_CLIP_SEC: float = 0.05

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


## A one-shot action is timed by its own clip when one exists, so authoring a
## longer `drink` automatically gives the character longer to drink. A held pose
## is NOT timed by its clip -- its clip loops for as long as the pose lasts, and
## its "duration" is only how long settling into it takes.
func get_action_duration(action_name: String) -> float:
	if is_hold_action(action_name):
		return -1.0
	var clip: String = _clip_for(action_name)
	if clip.is_empty():
		return -1.0
	var animation: Animation = _player.get_animation(clip)
	if animation == null or animation.length < MIN_MEANINGFUL_CLIP_SEC:
		return -1.0
	return animation.length


func play(action_name: String) -> bool:
	var clip: String = _clip_for(action_name)
	if clip.is_empty():
		# No clip authored yet. Leave whatever is playing alone and say so; the
		# movement controller still times the action out, so nothing gets stuck.
		return false
	_current_action = action_name
	if _player.current_animation != clip:
		_player.play(clip, ACTION_BLEND_SEC)
	return true


func rest(carrying: bool = false) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if carrying:
		for candidate: String in CARRY_REST_CLIPS:
			if _player.has_animation(candidate):
				_current_action = REST_ACTION
				if _player.current_animation != candidate:
					_player.play(candidate, ACTION_BLEND_SEC)
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
