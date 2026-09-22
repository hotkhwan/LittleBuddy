class_name TutorCueContract
extends RefCounted

## Validates model/backend cues before they reach the classroom. The returned
## dictionaries are safe semantic commands, never arbitrary method calls.

const Director := preload("res://scripts/tutor/expression/tutor_expression_director.gd")
const ACTIONS: Array[String] = [
	"set_emotion", "play_gesture", "look_at", "show_learning_card", "award_star",
]
const ID_PATTERN: String = "^[a-z][a-zA-Z0-9_-]{0,63}$"

var _id_regex: RegEx


func _init() -> void:
	_id_regex = RegEx.new()
	_id_regex.compile(ID_PATTERN)


func validate(cue: Variant) -> Dictionary:
	if not (cue is Dictionary):
		return _failure("cue must be an object")
	var input: Dictionary = cue
	var action: String = String(input.get("action", ""))
	if not ACTIONS.has(action):
		return _failure("action is not whitelisted")
	match action:
		"set_emotion":
			return _emotion(input)
		"play_gesture":
			return _gesture(input)
		"look_at":
			var target: String = String(input.get("target", ""))
			if not Director.LOOK_TARGETS.has(target):
				return _failure("invalid look target")
			return _success(action, {"target": target})
		"show_learning_card":
			return _validated_id(action, "card_id", input)
		"award_star":
			return _validated_id(action, "reason", input)
	return _failure("invalid action")


func _emotion(input: Dictionary) -> Dictionary:
	var emotion: String = String(input.get("emotion", ""))
	if not Director.EMOTIONS.has(emotion):
		return _failure("invalid emotion")
	var intensity: Variant = input.get("intensity", 1.0)
	if not _finite_number(intensity):
		return _failure("intensity must be a finite number")
	return _success("set_emotion", {"emotion": emotion, "intensity": clampf(float(intensity), 0.0, 1.0)})


func _gesture(input: Dictionary) -> Dictionary:
	var gesture: String = String(input.get("gesture", ""))
	if not Director.GESTURES.has(gesture):
		return _failure("invalid gesture")
	var intensity: Variant = input.get("intensity", 1.0)
	if not _finite_number(intensity):
		return _failure("intensity must be a finite number")
	return _success("play_gesture", {"gesture": gesture, "intensity": clampf(float(intensity), 0.15, 1.0)})


func _validated_id(action: String, key: String, input: Dictionary) -> Dictionary:
	var value: String = String(input.get(key, ""))
	if _id_regex.search(value) == null:
		return _failure("invalid %s" % key)
	return _success(action, {key: value})


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _success(action: String, arguments: Dictionary) -> Dictionary:
	return {"valid": true, "action": action, "arguments": arguments}


func _failure(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
