extends RefCounted

## The `"<roomId>.<targetId>"` id, as pure string algebra.
##
## This tiny file is the whole reason content can say `"kitchen.fridge"` and never
## know that a fridge is an `Area3D` sitting at (1.4, 0, -1.9) under
## `Rooms/Kitchen`. Moving the fridge across the kitchen edits a `.tscn` and
## changes zero lines of content data, because content never held a position, a
## `NodePath` or a node name in the first place.
##
## Deliberately free of every engine type -- no `Node`, no `Vector3`, no
## `SceneTree`. `ContentValidator` and any JSON-shaped data can use it to check an
## id is well formed without instantiating a scene, and it is trivially testable
## headlessly. The same reasoning as `nav_math.gd`: everything that CAN be pure is
## pure.
##
## Referenced by `preload()` rather than `class_name` -- global class names come
## from the editor's script-class cache, which the headless `--script` runner does
## not build.

const SEPARATOR: String = "."

## The rooms the house has, per the Phase 2B contract §1. Advisory rather than
## enforced: `is_known_room()` lets a caller warn about a typo, but composing an
## id for a room that does not exist yet is not an error, so adding a room never
## requires editing this file first.
const KNOWN_ROOM_IDS: Array[String] = ["bedroom", "bathroom", "kitchen", "livingRoom"]


## `compose("kitchen", "fridge") -> "kitchen.fridge"`.
##
## An empty room composes to the bare target id. That is not a special case for
## its own sake: it is what keeps every pre-room target (the Phase 2A spike's
## `"toyBox"`) addressable by exactly the string it has always used.
static func compose(room_id: Variant, target_id: Variant) -> String:
	var room: String = _clean(room_id)
	var target: String = _clean(target_id)
	if target.is_empty():
		return ""
	if room.is_empty():
		return target
	return room + SEPARATOR + target


## `split("kitchen.fridge") -> {"roomId": "kitchen", "targetId": "fridge"}`.
## An unqualified id splits to an empty room and itself.
static func split(semantic_id: Variant) -> Dictionary:
	var id: String = _clean(semantic_id)
	var at: int = id.find(SEPARATOR)
	if at == -1:
		return {"roomId": "", "targetId": id}
	return {"roomId": id.substr(0, at), "targetId": id.substr(at + 1)}


static func room_of(semantic_id: Variant) -> String:
	return String(split(semantic_id)["roomId"])


static func target_of(semantic_id: Variant) -> String:
	return String(split(semantic_id)["targetId"])


## True when the id names a room. `"kitchen.fridge"` yes, `"toyBox"` no.
static func is_qualified(semantic_id: Variant) -> bool:
	return not room_of(semantic_id).is_empty()


## One half of an id: a camelCase word. No dots, no slashes, no spaces, no
## `res://`, nothing that could be a `NodePath` in disguise -- which is exactly
## the failure this rejects, because a `NodePath` that leaked into a JSON file
## would work right up until somebody renamed a node.
static func is_part_valid(part: Variant) -> bool:
	var text: String = _clean(part)
	if text.is_empty():
		return false
	for index: int in range(text.length()):
		var code: int = text.unicode_at(index)
		var is_letter: bool = (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_digit: bool = code >= 48 and code <= 57
		var is_underscore: bool = code == 95
		if index == 0:
			if not (is_letter or is_underscore):
				return false
		elif not (is_letter or is_digit or is_underscore):
			return false
	return true


## A well-formed id: one valid part, or two separated by exactly one dot.
static func is_valid(semantic_id: Variant) -> bool:
	var id: String = _clean(semantic_id)
	if id.is_empty():
		return false
	# A leading or trailing dot would otherwise split into a silently empty half.
	if id.begins_with(SEPARATOR) or id.ends_with(SEPARATOR):
		return false
	if id.count(SEPARATOR) > 1:
		return false
	var parts: Dictionary = split(id)
	var room: String = String(parts["roomId"])
	if not is_part_valid(parts["targetId"]):
		return false
	if room.is_empty():
		return true
	return is_part_valid(room)


static func is_known_room(room_id: Variant) -> bool:
	return KNOWN_ROOM_IDS.has(_clean(room_id))


## Human-readable reasons `semantic_id` is unusable, or an empty array. Written
## for an authoring mistake found in a test, so the message names the id and says
## what is wrong with it rather than just failing.
static func problems(semantic_id: Variant) -> Array:
	var found: Array = []
	var id: String = _clean(semantic_id)
	if id.is_empty():
		return ["semantic id is empty"]
	if id.begins_with(SEPARATOR) or id.ends_with(SEPARATOR):
		return ["'%s' starts or ends with '%s'; one half of it is empty" % [id, SEPARATOR]]
	if id.count(SEPARATOR) > 1:
		found.append("'%s' has more than one '%s'; the shape is '<roomId>.<targetId>'" % [id, SEPARATOR])
		return found
	var parts: Dictionary = split(id)
	var room: String = String(parts["roomId"])
	var target: String = String(parts["targetId"])
	if not is_part_valid(target):
		found.append("'%s' has an invalid target id '%s' (camelCase word expected)" % [id, target])
	if not room.is_empty() and not is_part_valid(room):
		found.append("'%s' has an invalid room id '%s' (camelCase word expected)" % [id, room])
	return found


## Trimmed text for anything -- null, int, String. Every entry point runs input
## through this so a stray space in a `.tscn` field cannot produce a second,
## invisible id that looks identical in a log.
static func normalize(semantic_id: Variant) -> String:
	return _clean(semantic_id)


static func _clean(value: Variant) -> String:
	if value == null:
		return ""
	return String(value).strip_edges()
