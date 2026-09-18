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

## The locomotion clip whose playback rate follows the body's real speed. Only
## this one: every other action has a length of its own and must never be
## stretched by how fast the character happened to be walking beforehand.
const LOCOMOTION_ACTION: String = "walk"

## Bounds on that rate. A floor because a walk cycle crawling at 5% reads as a
## freeze rather than as a slow walk, and a ceiling because nothing should ever
## be sped up past the pace the cycle was authored at.
const MIN_LOCOMOTION_SCALE: float = 0.35
const MAX_LOCOMOTION_SCALE: float = 1.0

var _player: AnimationPlayer = null
var _current_action: String = ""
var _locomotion_scale: float = 1.0


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
## longer `drink` automatically gives the character longer to drink.
##
## Two clips have no useful length. A held pose loops for as long as the pose
## lasts, so its "duration" is only how long settling into it takes. And ANY
## looping clip's length is one arbitrary cycle of something that repeats -- a
## 2.6 s idle loop is not a 2.6 s action. Both fall back to the semantic default.
func get_action_duration(action_name: String) -> float:
	if is_hold_action(action_name):
		return -1.0
	var clip: String = _clip_for(action_name)
	if clip.is_empty():
		return -1.0
	var animation: Animation = _player.get_animation(clip)
	if animation == null or animation.length < MIN_MEANINGFUL_CLIP_SEC:
		return -1.0
	if animation.loop_mode != Animation.LOOP_NONE:
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
	_apply_locomotion_scale()
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
				_apply_locomotion_scale()
				return
	play(REST_ACTION)


func get_current_action() -> String:
	return _current_action


## Plays the walk cycle at the speed the body is really travelling, so a
## thumbstick held halfway over does not produce skating feet. See the base
## class for why this exists; anything that is not the walk runs at 1.0.
func set_locomotion_scale(scale: float) -> void:
	var wanted: float = clampf(scale, MIN_LOCOMOTION_SCALE, MAX_LOCOMOTION_SCALE)
	if is_equal_approx(wanted, _locomotion_scale):
		return
	_locomotion_scale = wanted
	_apply_locomotion_scale()


func get_locomotion_scale() -> float:
	return _locomotion_scale


func _apply_locomotion_scale() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# `speed_scale` is a property of the whole player, so it is set back to 1.0
	# for everything that is not locomotion -- otherwise a slow walk would leave
	# the next `drink` running at 45% for no reason anybody could trace.
	_player.speed_scale = _locomotion_scale if _current_action == LOCOMOTION_ACTION else 1.0


func _clip_for(action_name: String) -> String:
	if _player == null or not is_instance_valid(_player):
		return ""
	for candidate: Variant in ACTION_CLIPS.get(action_name, [action_name]):
		if _player.has_animation(String(candidate)):
			return String(candidate)
	return ""
