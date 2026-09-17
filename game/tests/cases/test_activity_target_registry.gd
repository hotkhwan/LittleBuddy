extends RefCounted

## Semantic lookup: `"kitchen.fridge"` -> a target, with content holding nothing
## but the string.
##
## Two things are worth more than the rest of this file:
##
## * **Content never touches the tree.** The resolution test below builds a house
##   whose nodes are not in any `SceneTree`, resolves ids through the registry,
##   and then MOVES the fridge -- and the content data is byte-identical either
##   side of the move. That is contract §1 as an executable claim.
## * **Duplicates are loud.** A second `kitchen.fridge` is refused and reported.
##   The alternative -- silent last-one-wins -- makes the fridge you walk to a
##   function of scene-tree ordering, which is a debugging nightmare in a
##   four-room house.

const Registry := preload("res://scripts/navigation/activity_target_registry.gd")
const ActivityTarget := preload("res://scripts/navigation/activity_target.gd")
const SemanticId := preload("res://scripts/navigation/semantic_id.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## The house the contract asks for, as content would describe it: strings only.
const HOUSE: Dictionary = {
	"bedroom": ["bed", "wardrobe", "toy"],
	"bathroom": ["sink", "bath", "towel"],
	"kitchen": ["fridge", "table", "counter"],
	"livingRoom": ["sofa", "toyBox", "book"],
}


## A duck-typed target that is NOT an `ActivityTarget`, to prove the registry
## couples to methods rather than to a type -- the same contract the character
## and the tap raycast use.
class WrappedTarget extends Node3D:
	var semantic: String = "kitchen.kettle"

	func get_activity_target_id() -> String:
		return semantic

	func describe(approach_from: Vector3) -> Dictionary:
		return {"targetId": semantic, "standPosition": approach_from, "arrivalRadius": 0.22}


## Stands in for `little_buddy_character.gd`'s registry with the same duck-typed
## acceptance rule, so `sync_to_character()` is tested without a physics body.
class FakeCharacter extends Node3D:
	var ids: Array = []

	func register_activity_target(target: Object) -> bool:
		if target == null or not target.has_method("get_activity_target_id"):
			return false
		if not target.has_method("describe"):
			return false
		var id: String = String(target.call("get_activity_target_id"))
		if id.strip_edges().is_empty():
			return false
		ids.append(id)
		return true


func test_name() -> String:
	return "activity_target_registry"


func run():
	var failures: Array = []
	failures.append_array(_test_registers_a_house())
	failures.append_array(_test_lookup_without_the_tree())
	failures.append_array(_test_moving_the_fridge_changes_no_content())
	failures.append_array(_test_duplicate_within_a_room_is_loud())
	failures.append_array(_test_duplicate_semantic_id_is_loud())
	failures.append_array(_test_same_local_id_in_two_rooms_is_fine())
	failures.append_array(_test_malformed_targets_are_refused())
	failures.append_array(_test_queries())
	failures.append_array(_test_unregister_and_freed_nodes())
	failures.append_array(_test_sync_to_character())
	failures.append_array(_test_legacy_unroomed_target())
	return failures


## -- Registration ----------------------------------------------------------------

func _test_registers_a_house() -> Array:
	var failures: Array = []
	var house: Node3D = _build_house()
	var registry: RefCounted = Registry.new()

	var count: int = registry.call("register_all", house)
	if count != 12:
		failures.append("the four contract rooms hold 12 targets, registered %d" % count)
	if registry.call("has_problems"):
		failures.append("a well-authored house should register cleanly, got %s"
				% str(registry.call("get_problems")))

	var summary: Dictionary = registry.call("get_summary")
	for room: String in HOUSE.keys():
		var expected: Array = (HOUSE[room] as Array).duplicate()
		expected.sort()
		if summary.get(room, []) != expected:
			failures.append("%s should hold %s, got %s" % [room, str(expected), str(summary.get(room, []))])

	# The summary is the whole house as strings. No node escapes it, so it is safe
	# to log, diff or assert against content.
	for room: Variant in summary.keys():
		for id: Variant in summary[room]:
			if typeof(id) != TYPE_STRING:
				failures.append("get_summary() must contain strings only")

	house.free()
	return failures


## Contract §1, directly: content holds an id, and resolution needs no tree, no
## `NodePath` and no coordinate.
func _test_lookup_without_the_tree() -> Array:
	var failures: Array = []
	var house: Node3D = _build_house()
	var registry: RefCounted = Registry.new()
	registry.call("register_all", house)

	if house.is_inside_tree():
		failures.append("this test is meant to run with the house OUTSIDE the SceneTree")

	var fridge: Object = registry.call("get_target", "kitchen.fridge")
	if fridge == null:
		failures.append("'kitchen.fridge' should resolve")
	elif String(fridge.call("get_local_target_id")) != "fridge":
		failures.append("'kitchen.fridge' resolved to the wrong target")

	if registry.call("get_target_in_room", "kitchen", "fridge") != fridge:
		failures.append("resolving by room + local id should find the same target")
	if not bool(registry.call("has", "bathroom.sink")):
		failures.append("'bathroom.sink' should be registered")
	if bool(registry.call("has", "kitchen.oven")):
		failures.append("an id nobody authored must not resolve")
	if registry.call("get_target", "kitchen.oven") != null:
		failures.append("an unknown id must resolve to null rather than a guess")

	# Whitespace and unknown ids degrade, they do not crash.
	if registry.call("get_target", " kitchen.fridge ") != fridge:
		failures.append("a padded id should still resolve")
	if registry.call("get_target", "") != null:
		failures.append("an empty id must resolve to null")

	# The content-validation seam: hand it the ids a content file mentions.
	var unknown: Array = registry.call("find_unknown_ids",
			["kitchen.fridge", "bedroom.bed", "kitchen.oven", ""])
	if unknown != ["kitchen.oven", ""]:
		failures.append("find_unknown_ids() should report exactly the unusable ids, got %s" % str(unknown))

	house.free()
	return failures


## Moving the fridge across the kitchen must touch zero lines of content data.
func _test_moving_the_fridge_changes_no_content() -> Array:
	var failures: Array = []
	var house: Node3D = _build_house()
	var registry: RefCounted = Registry.new()
	registry.call("register_all", house)

	# "Content", in full. One string.
	var content_task: Dictionary = {"taskId": "putMilkAway", "targetId": "kitchen.fridge"}
	var before: String = JSON.stringify(content_task)

	var fridge: Object = registry.call("get_target", String(content_task["targetId"]))
	if fridge == null:
		failures.append("the content id should resolve before the move")
		house.free()
		return failures
	var first_stand: Vector3 = fridge.call("describe", Vector3.ZERO).get("standPosition", Vector3.ZERO)

	# Move it. This is the `.tscn` edit, simulated.
	(fridge as Node3D).position += Vector3(2.5, 0.0, -1.5)
	(fridge as Node3D).name = "BigFridge"

	var after_move: Object = registry.call("get_target", String(content_task["targetId"]))
	if after_move != fridge:
		failures.append("the id must still resolve to the same target after it moved")
	var second_stand: Vector3 = fridge.call("describe", Vector3.ZERO).get("standPosition", Vector3.ZERO)
	if second_stand.is_equal_approx(first_stand):
		failures.append("the test did not actually move the fridge")
	if JSON.stringify(content_task) != before:
		failures.append("moving the fridge changed the content data; the whole point is that it cannot")

	house.free()
	return failures


## -- Duplicates ------------------------------------------------------------------

func _test_duplicate_within_a_room_is_loud() -> Array:
	var failures: Array = []
	var registry: RefCounted = Registry.new()
	registry.call("set_report_errors", false)  # the error is expected; assert it instead

	var first: Area3D = _target("kitchen", "fridge")
	first.name = "Fridge"
	var second: Area3D = _target("kitchen", "fridge")
	second.name = "FridgeCopy"

	if not bool(registry.call("register", first)):
		failures.append("the first fridge should register")
	if bool(registry.call("register", second)):
		failures.append("a second 'kitchen.fridge' must be REFUSED, not silently accepted")
	if registry.call("get_target", "kitchen.fridge") != first:
		failures.append("the first registration must keep winning; last-one-wins makes the "
				+ "resolved target depend on scene ordering")
	if int(registry.call("size")) != 1:
		failures.append("a refused duplicate must not enter the registry")

	var problems: Array = registry.call("get_problems")
	if problems.size() != 1:
		failures.append("a duplicate should record exactly one problem, got %s" % str(problems))
	else:
		var message: String = String(problems[0])
		for needle: String in ["kitchen.fridge", "Fridge", "FridgeCopy"]:
			if not message.contains(needle):
				failures.append("the duplicate report should name '%s': %s" % [needle, message])

	# Re-registering the SAME object is idempotent, so a room that registers twice
	# is not reported as an authoring error.
	if not bool(registry.call("register", first)):
		failures.append("re-registering the same object should be idempotent")
	if registry.call("get_problems").size() != 1:
		failures.append("an idempotent re-registration must not add a problem")

	first.free()
	second.free()
	return failures


func _test_duplicate_semantic_id_is_loud() -> Array:
	var failures: Array = []
	var registry: RefCounted = Registry.new()
	registry.call("set_report_errors", false)

	# The globally-unique rule, reached a different way: a hand-rolled duck-typed
	# target claiming an id an ActivityTarget already owns.
	var real: Area3D = _target("kitchen", "kettle")
	var impostor: WrappedTarget = WrappedTarget.new()
	if not bool(registry.call("register", real)):
		failures.append("the real kettle should register")
	if bool(registry.call("register", impostor)):
		failures.append("a duck-typed target must not be able to dodge the uniqueness rule")
	if registry.call("get_target", "kitchen.kettle") != real:
		failures.append("the first kettle should still own the id")

	# A duck-typed target with a free id registers normally.
	impostor.semantic = "kitchen.toaster"
	if not bool(registry.call("register", impostor)):
		failures.append("a duck-typed target with a free id should register")
	if registry.call("get_target", "kitchen.toaster") != impostor:
		failures.append("the registry should couple to methods, not to a type")
	if registry.call("get_target_ids_in_room", "kitchen") != ["kettle", "toaster"]:
		failures.append("a duck-typed target should land in its room, got %s"
				% str(registry.call("get_target_ids_in_room", "kitchen")))

	real.free()
	impostor.free()
	return failures


func _test_same_local_id_in_two_rooms_is_fine() -> Array:
	var failures: Array = []
	var registry: RefCounted = Registry.new()
	var bedroom_toy: Area3D = _target("bedroom", "toy")
	var living_toy: Area3D = _target("livingRoom", "toy")

	if not bool(registry.call("register", bedroom_toy)) or not bool(registry.call("register", living_toy)):
		failures.append("'toy' in two different rooms is legal and both should register")
	if registry.call("has_problems"):
		failures.append("two rooms owning a 'toy' is not a problem, got %s"
				% str(registry.call("get_problems")))
	if registry.call("get_target", "bedroom.toy") == registry.call("get_target", "livingRoom.toy"):
		failures.append("the two toys must resolve to different targets")

	bedroom_toy.free()
	living_toy.free()
	return failures


func _test_malformed_targets_are_refused() -> Array:
	var failures: Array = []
	var registry: RefCounted = Registry.new()
	registry.call("set_report_errors", false)

	if bool(registry.call("register", null)):
		failures.append("null must not register")

	var blank: Area3D = _target("kitchen", "   ")
	if bool(registry.call("register", blank)):
		failures.append("a target with a blank id must be refused, not registered under ''")

	var pathy: WrappedTarget = WrappedTarget.new()
	pathy.semantic = "Rooms/Kitchen/Fridge"
	if bool(registry.call("register", pathy)):
		failures.append("a NodePath-shaped id must be refused; content must never hold a path")

	var dotty: WrappedTarget = WrappedTarget.new()
	dotty.semantic = "kitchen.fridge.door"
	if bool(registry.call("register", dotty)):
		failures.append("'<room>.<target>.<extra>' is not a semantic id")

	var not_a_target: Node3D = Node3D.new()
	if bool(registry.call("register", not_a_target)):
		failures.append("a node that answers neither contract method must be refused")

	if int(registry.call("size")) != 0:
		failures.append("nothing malformed should have entered the registry")
	if registry.call("get_problems").size() != 5:
		failures.append("every refusal should be reported, got %s" % str(registry.call("get_problems")))

	blank.free()
	pathy.free()
	dotty.free()
	not_a_target.free()
	return failures


## -- Queries -----------------------------------------------------------------------

func _test_queries() -> Array:
	var failures: Array = []
	var registry: RefCounted = Registry.new()

	var fridge: Area3D = _target("kitchen", "fridge")
	fridge.call("set_supported_actions", ["open", "give"])
	fridge.set("required_object", "milk")
	var bin: Area3D = _target("kitchen", "bin")
	bin.call("set_supported_actions", ["give"])
	var door: Area3D = _target("kitchen", "doorToLivingRoom")
	door.set("to_room_id", "livingRoom")
	door.set("to_spawn_id", "fromKitchen")
	for node: Area3D in [fridge, bin, door]:
		registry.call("register", node)

	if registry.call("find_by_action", "open") != ["kitchen.fridge"]:
		failures.append("find_by_action('open') should find only the fridge, got %s"
				% str(registry.call("find_by_action", "open")))
	if registry.call("find_by_action", "give") != ["kitchen.bin", "kitchen.fridge"]:
		failures.append("find_by_action('give') should find both, sorted, got %s"
				% str(registry.call("find_by_action", "give")))
	if not Array(registry.call("find_by_action", "fly")).is_empty():
		failures.append("an action nobody supports should find nothing")
	if registry.call("find_by_required_object", "milk") != ["kitchen.fridge"]:
		failures.append("find_by_required_object('milk') should find the fridge")

	var doors: Array = registry.call("get_doors")
	if doors.size() != 1:
		failures.append("the kitchen has exactly one door, found %d" % doors.size())
	elif String(doors[0].get("toRoomId", "")) != "livingRoom" \
			or String(doors[0].get("semanticId", "")) != "kitchen.doorToLivingRoom":
		failures.append("the door description is wrong: %s" % str(doors[0]))

	# Every query answers in strings. Nothing here can hand a mission a Vector3.
	for result: Array in [registry.call("find_by_action", "give"), registry.call("get_semantic_ids")]:
		for entry: Variant in result:
			if typeof(entry) != TYPE_STRING:
				failures.append("a lookup result must be a String, got %s" % type_string(typeof(entry)))

	if registry.call("get_room_ids") != ["kitchen"]:
		failures.append("get_room_ids() should list the rooms in play")
	if registry.call("get_targets_in_room", "kitchen").size() != 3:
		failures.append("the kitchen should report its three targets")
	if not Array(registry.call("get_targets_in_room", "attic")).is_empty():
		failures.append("an unknown room should be empty, not an error")

	for node: Area3D in [fridge, bin, door]:
		node.free()
	return failures


func _test_unregister_and_freed_nodes() -> Array:
	var failures: Array = []
	var registry: RefCounted = Registry.new()
	var fridge: Area3D = _target("kitchen", "fridge")
	var bed: Area3D = _target("bedroom", "bed")
	registry.call("register", fridge)
	registry.call("register", bed)

	registry.call("unregister", "kitchen.fridge")
	if bool(registry.call("has", "kitchen.fridge")):
		failures.append("an unregistered id must stop resolving")
	if registry.call("get_room_ids") != ["bedroom"]:
		failures.append("a room with no targets left should disappear, got %s"
				% str(registry.call("get_room_ids")))
	registry.call("unregister", "kitchen.fridge")  # twice: must be harmless

	if int(registry.call("unregister_room", "bedroom")) != 1:
		failures.append("unregister_room() should report what it dropped")
	if int(registry.call("size")) != 0:
		failures.append("the registry should be empty")

	# A room unloaded without unregistering degrades to "unknown target", which
	# the character already handles as a refused move -- never a crash.
	registry.call("register", fridge)
	fridge.free()
	if registry.call("get_target", "kitchen.fridge") != null:
		failures.append("a freed target must resolve to null rather than a dangling reference")
	if bool(registry.call("has", "kitchen.fridge")):
		failures.append("a freed target should be forgotten")

	bed.free()
	return failures


func _test_sync_to_character() -> Array:
	var failures: Array = []
	var house: Node3D = _build_house()
	var registry: RefCounted = Registry.new()
	registry.call("register_all", house)

	var character: FakeCharacter = FakeCharacter.new()
	var pushed: int = registry.call("sync_to_character", character)
	if pushed != 12:
		failures.append("every registered target should reach the character, pushed %d" % pushed)

	var ids: Array = character.ids.duplicate()
	ids.sort()
	var expected: Array = registry.call("get_semantic_ids")
	if ids != expected:
		failures.append("the character must be keyed by the SAME semantic ids, got %s" % str(ids))

	# The id a mission would use is the id the character knows.
	if not ids.has("kitchen.fridge"):
		failures.append("character.move_to('kitchen.fridge') would fail: the id never reached it")

	if int(registry.call("sync_to_character", null)) != 0:
		failures.append("syncing to nothing should be a no-op, not a crash")

	house.free()
	character.free()
	return failures


## The Phase 2A spike still works: an unroomed target registers under its bare id.
func _test_legacy_unroomed_target() -> Array:
	var failures: Array = []
	var registry: RefCounted = Registry.new()
	var toy_box: Area3D = _target("", "toyBox")

	if not bool(registry.call("register", toy_box)):
		failures.append("a target with no room must still register")
	if not bool(registry.call("has", "toyBox")):
		failures.append("an unroomed target should resolve by its bare id")
	if registry.call("get_room_ids") != [""]:
		failures.append("unroomed targets should be visible under the empty room, got %s"
				% str(registry.call("get_room_ids")))
	if registry.call("has_problems"):
		failures.append("an unroomed target is legacy, not an error: %s"
				% str(registry.call("get_problems")))

	toy_box.free()
	return failures


## -- Helpers -----------------------------------------------------------------------

func _target(room_id: String, target_id: String) -> Area3D:
	var target: Area3D = ActivityTarget.new()
	target.set("room_id", room_id)
	target.set("target_id", target_id)
	return target


## The four contract rooms, built as nodes that are never added to a `SceneTree`.
func _build_house() -> Node3D:
	var house: Node3D = Node3D.new()
	house.name = "HouseWorld"
	var x: float = 0.0
	for room_id: Variant in HOUSE.keys():
		var room: Node3D = Node3D.new()
		room.name = String(room_id)
		room.position = Vector3(x, 0.0, 0.0)
		x += 5.0
		house.add_child(room)
		var z: float = 0.0
		for target_id: Variant in HOUSE[room_id]:
			var target: Area3D = _target(String(room_id), String(target_id))
			target.name = String(target_id)
			target.position = Vector3(0.0, 0.0, z)
			z += 1.2
			room.add_child(target)
	return house
