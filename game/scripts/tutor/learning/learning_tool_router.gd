class_name LearningToolRouter
extends RefCounted

## Closed semantic surface. No tool name is converted to a method name and no
## arbitrary object, scene, file, URL, or command can be reached.

signal card_requested(asset_id: String)
signal prop_requested(asset_id: String)
signal hint_requested(level: int)
signal star_requested(reason: String)
signal lesson_completed(result: String)

const SAFE_IDS := "^[a-z0-9][a-z0-9_-]{0,47}$"
const RESULTS: Array[String] = ["completed", "mastered", "needs_practice"]

var _director: Object
var _allowed_assets: Array[String] = []
var _regex := RegEx.new()


func _init(director: Object = null, allowed_assets: Array[String] = []) -> void:
	_director = director
	_allowed_assets = allowed_assets.duplicate()
	_regex.compile(SAFE_IDS)


func apply(call: Dictionary) -> Dictionary:
	var name := String(call.get("name", ""))
	var args: Variant = call.get("arguments", {})
	if typeof(args) != TYPE_DICTIONARY:
		return _rejected("arguments:not_object")
	var values: Dictionary = args
	match name:
		"show_learning_card", "show_prop":
			if not _exact(values, ["assetId"]) or not _asset_allowed(String(values.get("assetId", ""))):
				return _rejected("asset:not_allowed")
			if name == "show_learning_card": card_requested.emit(String(values.assetId))
			else: prop_requested.emit(String(values.assetId))
		"set_emotion":
			if not _exact(values, ["emotion", "intensity"]) or _director == null or not _director.set_emotion(String(values.emotion), float(values.intensity)):
				return _rejected("emotion:invalid")
		"play_gesture":
			if not _exact(values, ["gesture", "intensity"]) or _director == null or not _director.play_gesture(String(values.gesture), float(values.intensity)):
				return _rejected("gesture:invalid")
		"look_at":
			if not _exact(values, ["target"]) or _director == null or not _director.look_at(String(values.target)):
				return _rejected("look:invalid")
		"give_hint":
			var level := int(values.get("hintLevel", 0))
			if not _exact(values, ["hintLevel"]) or level < 1 or level > 3: return _rejected("hint:invalid")
			hint_requested.emit(level)
		"award_star":
			if not _exact(values, ["reason"]) or not _safe_id(String(values.get("reason", ""))): return _rejected("reason:invalid")
			star_requested.emit(String(values.reason))
		"complete_lesson":
			if not _exact(values, ["result"]) or not RESULTS.has(String(values.get("result", ""))): return _rejected("result:invalid")
			lesson_completed.emit(String(values.result))
		_:
			return _rejected("tool:not_allowed")
	return {"accepted": true, "name": name}


func _asset_allowed(asset_id: String) -> bool:
	return _safe_id(asset_id) and (_allowed_assets.is_empty() or _allowed_assets.has(asset_id))


func _safe_id(value: String) -> bool:
	return _regex.search(value) != null


func _exact(values: Dictionary, keys: Array) -> bool:
	var actual := values.keys()
	actual.sort()
	var expected := keys.duplicate()
	expected.sort()
	return actual == expected


func _rejected(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}
