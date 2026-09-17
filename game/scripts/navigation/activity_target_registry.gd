extends RefCounted

## The lookup that turns `"kitchen.fridge"` into a target, without content ever
## touching the scene tree.
##
## ## What it is for
##
## Content data holds one string. It holds no `NodePath`, no node name and no
## `Vector3`, so moving the fridge across the kitchen is a `.tscn` edit and
## nothing else. The registry is the single place that knows both halves: a room
## registers its targets once, and from then on every lookup is by id.
##
##     var registry := ActivityTargetRegistryScript.new()
##     registry.register_all(house)               # walk the rooms once
##     registry.sync_to_character(little_buddy)   # same ids on both sides
##     registry.has("kitchen.fridge")             # content asks in strings
##
## A `RefCounted`, not an autoload: `CLAUDE.md` forbids unnecessary singletons,
## and a house that owns its own registry can be built, tested and thrown away
## twice in one test without any global state to reset.
##
## ## Duplicates are loud
##
## A duplicate semantic id is refused, recorded in `get_problems()` and reported
## through `push_error()`. The FIRST registration wins and keeps winning.
##
## Silent last-one-wins was the alternative and it is a trap: in a four-room
## house the fridge you walk to would depend on the order the scene tree happened
## to be walked in, so the bug would move when you renamed a node. First-wins is
## at least deterministic, and the error names both nodes, which turns a
## multi-hour hunt into a one-line fix.
##
## ## Uniqueness rules
##
## * `targetId` must be unique WITHIN a room. Two `"fridge"` nodes in the kitchen
##   are an authoring error.
## * The semantic id must be unique GLOBALLY. It follows from the first rule, and
##   is checked directly so a hand-rolled duck-typed target cannot dodge it.
## * The same local id in two different rooms is FINE -- `bedroom.toy` and
##   `livingRoom.toy` are different things and the ids say so.
##
## Referenced by `preload()`; the headless `--script` runner builds no
## script-class cache, so `class_name` is unavailable.

const SemanticId := preload("res://scripts/navigation/semantic_id.gd")

## semanticId -> instance id.
##
## Instance ids rather than references on purpose. A room that is unloaded
## without unregistering leaves a freed node behind, and merely READING a dangling
## reference out of a Dictionary is a script error in a debug build -- so the
## registry would be the thing that crashes on the way to reporting a clean
## "unknown target". An instance id can be tested for validity without touching
## the object, so an unloaded room degrades exactly the way the character already
## handles: `move_failed("unknownTarget")`.
##
## The trade-off: the registry does not keep a target alive. Targets are scene
## nodes owned by their room, which is where ownership belongs.
var _targets: Dictionary = {}
## roomId -> { localTargetId: semanticId }
var _rooms: Dictionary = {}
var _problems: Array = []
var _report_errors: bool = true


## -- Registration -------------------------------------------------------------

## Registers one target. Duck-typed: anything answering `get_activity_target_id()`
## and `describe()` qualifies, so a prop scene can wrap a target without
## inheriting from anything -- the same contract `little_buddy_character.gd` uses.
##
## Returns true only when the target is now in the registry under its own id.
## Re-registering the same object under the same id is idempotent and succeeds.
func register(target: Object) -> bool:
	if target == null or not is_instance_valid(target):
		return _refuse("", "a null target cannot be registered")
	if not target.has_method("get_activity_target_id") or not target.has_method("describe"):
		return _refuse("", "%s answers neither get_activity_target_id() nor describe()"
				% _label(target))

	var semantic_id: String = _semantic_id_of(target)
	if semantic_id.is_empty():
		return _refuse("", "%s has a blank target id" % _label(target))
	if not SemanticId.is_valid(semantic_id):
		var reasons: Array = SemanticId.problems(semantic_id)
		var reason: String = String(reasons[0]) if not reasons.is_empty() else "malformed id"
		return _refuse(semantic_id, "%s: %s" % [_label(target), reason])

	if _targets.has(semantic_id):
		var held: Object = _instance_of(semantic_id)
		if held == target:
			return true
		if held != null:
			return _refuse(semantic_id,
					("duplicate semantic id '%s': %s and %s. Ids must be unique within a room "
					+ "and globally; keeping the first.")
					% [semantic_id, _label(held), _label(target)])
		# The previous holder was freed -- a reloaded room, not a duplicate.
		unregister(semantic_id)

	_targets[semantic_id] = target.get_instance_id()
	var room_id: String = SemanticId.room_of(semantic_id)
	var local_id: String = SemanticId.target_of(semantic_id)
	if not _rooms.has(room_id):
		_rooms[room_id] = {}
	(_rooms[room_id] as Dictionary)[local_id] = semantic_id
	return true


## Registers every target beneath `root`, `root` itself included. Returns how
## many were registered; `get_problems()` holds anything that was refused, so a
## room's own test can assert it authored no duplicates.
func register_all(root: Node) -> int:
	if root == null:
		return 0
	var count: int = 0
	for node: Node in collect(root):
		if register(node):
			count += 1
	return count


## Every duck-typed activity target beneath `root`, depth-first, `root` included.
## Static so a caller can count what a room contains without building a registry.
static func collect(root: Node) -> Array:
	var found: Array = []
	if root == null:
		return found
	if root.has_method("get_activity_target_id") and root.has_method("describe"):
		found.append(root)
	for child: Node in root.get_children():
		found.append_array(collect(child))
	return found


func unregister(semantic_id: String) -> void:
	var id: String = SemanticId.normalize(semantic_id)
	if not _targets.has(id):
		return
	_targets.erase(id)
	var room: String = SemanticId.room_of(id)
	if _rooms.has(room):
		(_rooms[room] as Dictionary).erase(SemanticId.target_of(id))
		if (_rooms[room] as Dictionary).is_empty():
			_rooms.erase(room)


## Drops a whole room, for a world that unloads one. Returns how many went.
func unregister_room(room_id: String) -> int:
	var room: String = SemanticId.normalize(room_id)
	var ids: Array = get_semantic_ids_in_room(room)
	for id: String in ids:
		unregister(id)
	return ids.size()


func clear() -> void:
	_targets.clear()
	_rooms.clear()
	_problems.clear()


## -- Lookup (strings in, nothing spatial out unless you ask for the node) ------

func has(semantic_id: String) -> bool:
	return get_target(semantic_id) != null


## The registered target, or null. Never returns a freed node: a room that was
## unloaded without unregistering degrades to "unknown target", which the
## character already handles as a refused move rather than a crash.
func get_target(semantic_id: String) -> Object:
	var id: String = SemanticId.normalize(semantic_id)
	var target: Object = _instance_of(id)
	if target == null:
		unregister(id)
	return target


## Resolves a room and a local id without the caller composing the string.
func get_target_in_room(room_id: String, target_id: String) -> Object:
	return get_target(SemanticId.compose(room_id, target_id))


func size() -> int:
	return _targets.size()


func get_semantic_ids() -> Array:
	var ids: Array = _targets.keys()
	ids.sort()
	return ids


## Room ids that have at least one target. `""` is a real key here and holds the
## unroomed legacy targets, so they are visible rather than quietly dropped.
func get_room_ids() -> Array:
	var ids: Array = _rooms.keys()
	ids.sort()
	return ids


func get_semantic_ids_in_room(room_id: String) -> Array:
	var room: Dictionary = _rooms.get(SemanticId.normalize(room_id), {})
	var ids: Array = room.values()
	ids.sort()
	return ids


## The unqualified ids in a room: `["bed", "toy", "wardrobe"]`.
func get_target_ids_in_room(room_id: String) -> Array:
	var room: Dictionary = _rooms.get(SemanticId.normalize(room_id), {})
	var ids: Array = room.keys()
	ids.sort()
	return ids


func get_targets_in_room(room_id: String) -> Array:
	var targets: Array = []
	for id: String in get_semantic_ids_in_room(room_id):
		var target: Object = get_target(id)
		if target != null:
			targets.append(target)
	return targets


## Semantic ids of every target that supports `action_name`. Strings only, so a
## mission can ask "where can I 'open' something?" without holding a node.
func find_by_action(action_name: String) -> Array:
	var found: Array = []
	for id: String in get_semantic_ids():
		var target: Object = get_target(id)
		if target != null and target.has_method("supports_action") \
				and bool(target.call("supports_action", action_name)):
			found.append(id)
	return found


## Semantic ids of every target that wants `object_id` brought to it.
func find_by_required_object(object_id: String) -> Array:
	var wanted: String = object_id.strip_edges()
	var found: Array = []
	for id: String in get_semantic_ids():
		var target: Object = get_target(id)
		if target != null and target.has_method("get_required_object") \
				and String(target.call("get_required_object")) == wanted:
			found.append(id)
	return found


## Semantic ids of every door, and where each one leads. Strings only.
func get_doors() -> Array:
	var doors: Array = []
	for id: String in get_semantic_ids():
		var target: Object = get_target(id)
		if target == null or not target.has_method("is_door") or not bool(target.call("is_door")):
			continue
		var destination: Dictionary = {"toRoomId": "", "toSpawnId": ""}
		if target.has_method("get_destination"):
			destination = target.call("get_destination")
		doors.append({
			"semanticId": id,
			"roomId": SemanticId.room_of(id),
			"toRoomId": String(destination.get("toRoomId", "")),
			"toSpawnId": String(destination.get("toSpawnId", "")),
		})
	return doors


## `{"kitchen": ["counter", "fridge", "table"], ...}` -- the whole house as
## strings, for a test, a log or a content check. No nodes escape.
func get_summary() -> Dictionary:
	var summary: Dictionary = {}
	for room: String in get_room_ids():
		summary[room] = get_target_ids_in_room(room)
	return summary


## -- Validation ---------------------------------------------------------------

## The ids in `semantic_ids` that nothing answers to. This is how a content file
## is checked against the world without loading a room: hand it the ids the
## content mentions and get back the ones that would fail at runtime.
func find_unknown_ids(semantic_ids: Array) -> Array:
	var unknown: Array = []
	for raw: Variant in semantic_ids:
		var id: String = SemanticId.normalize(raw)
		if id.is_empty() or not has(id):
			unknown.append(id)
	return unknown


## Authoring problems found so far: duplicates, malformed ids, blank ids.
func get_problems() -> Array:
	return _problems.duplicate()


func has_problems() -> bool:
	return not _problems.is_empty()


func clear_problems() -> void:
	_problems.clear()


## Silences `push_error()` while still recording problems. For the tests that
## deliberately register a duplicate -- they assert the refusal, and an expected
## error printed to stderr next to a passing case is just noise.
func set_report_errors(report: bool) -> void:
	_report_errors = report


## -- Character hand-off --------------------------------------------------------

## Pushes every registered target into `character.register_activity_target()`,
## so the character's own flat registry is keyed by the SAME semantic ids the
## registry validated. Returns how many the character accepted.
##
## Worth doing in this order: duplicates are caught here, loudly, before the
## character's `_targets[id] = target` would have silently overwritten one.
func sync_to_character(character: Object) -> int:
	if character == null or not is_instance_valid(character):
		return 0
	if not character.has_method("register_activity_target"):
		return 0
	var count: int = 0
	for id: String in get_semantic_ids():
		var target: Object = get_target(id)
		if target != null and bool(character.call("register_activity_target", target)):
			count += 1
	return count


## -- Internals ----------------------------------------------------------------

## The live object behind a registered id, or null if it was never registered or
## has since been freed. Never dereferences a dangling instance.
func _instance_of(semantic_id: String) -> Object:
	if not _targets.has(semantic_id):
		return null
	var instance_id: int = int(_targets[semantic_id])
	if not is_instance_id_valid(instance_id):
		return null
	return instance_from_id(instance_id)


func _semantic_id_of(target: Object) -> String:
	if target.has_method("get_semantic_id"):
		return SemanticId.normalize(target.call("get_semantic_id"))
	# Duck-typed fallback: a hand-rolled target that only knows the old method.
	return SemanticId.normalize(target.call("get_activity_target_id"))


func _refuse(semantic_id: String, message: String) -> bool:
	var text: String = message
	if not semantic_id.is_empty() and not message.contains(semantic_id):
		text = "'%s': %s" % [semantic_id, message]
	_problems.append(text)
	if _report_errors:
		push_error("ActivityTargetRegistry refused a target -- %s" % text)
	return false


func _label(target: Object) -> String:
	if target == null:
		return "<null>"
	if target is Node:
		var node: Node = target as Node
		return "%s(%s)" % [node.name, node.get_class()]
	return target.get_class()
