extends RefCounted

## `"<roomId>.<targetId>"` -- the string algebra everything else depends on.
##
## Pure, so every case here is a real assertion with no scene, no tree and no
## physics. The point of these tests is not the happy path; it is that the
## malformed shapes a human will eventually type into a `.tscn` or a JSON file --
## a `NodePath`, a trailing dot, a name with a space in it -- are rejected as data
## rather than discovered at runtime as "the child walks to the wrong room".

const SemanticId := preload("res://scripts/navigation/semantic_id.gd")


func test_name() -> String:
	return "semantic_id"


func run():
	var failures: Array = []
	failures.append_array(_test_compose())
	failures.append_array(_test_split())
	failures.append_array(_test_validity())
	failures.append_array(_test_content_data_can_never_hold_a_node_path())
	failures.append_array(_test_rooms())
	return failures


func _test_compose() -> Array:
	var failures: Array = []

	if SemanticId.compose("kitchen", "fridge") != "kitchen.fridge":
		failures.append("compose() should join with a dot, got '%s'"
				% SemanticId.compose("kitchen", "fridge"))

	# The backward-compatibility rule, stated as an assertion: no room means the
	# id is the bare target id, exactly as the Phase 2A spike has always used it.
	if SemanticId.compose("", "toyBox") != "toyBox":
		failures.append("an unroomed target must compose to its bare id, got '%s'"
				% SemanticId.compose("", "toyBox"))

	# Whitespace from a hand-edited scene file must not create a second,
	# invisible id that prints identically in a log.
	if SemanticId.compose("  kitchen ", " fridge  ") != "kitchen.fridge":
		failures.append("compose() should trim both halves")

	if not SemanticId.compose("kitchen", "").is_empty():
		failures.append("a target with no id cannot compose to anything addressable")
	if not SemanticId.compose(null, null).is_empty():
		failures.append("compose(null, null) must be empty, not crash")

	return failures


func _test_split() -> Array:
	var failures: Array = []

	var parts: Dictionary = SemanticId.split("kitchen.fridge")
	if String(parts["roomId"]) != "kitchen" or String(parts["targetId"]) != "fridge":
		failures.append("split() should return both halves, got %s" % str(parts))

	var bare: Dictionary = SemanticId.split("toyBox")
	if String(bare["roomId"]) != "" or String(bare["targetId"]) != "toyBox":
		failures.append("an unqualified id should split to an empty room, got %s" % str(bare))

	if SemanticId.room_of("bathroom.sink") != "bathroom":
		failures.append("room_of() should read the room half")
	if SemanticId.target_of("bathroom.sink") != "sink":
		failures.append("target_of() should read the target half")
	if not SemanticId.is_qualified("livingRoom.sofa"):
		failures.append("a roomed id should report as qualified")
	if SemanticId.is_qualified("toyBox"):
		failures.append("a bare id must not report as qualified")

	return failures


func _test_validity() -> Array:
	var failures: Array = []

	for good: String in [
		"kitchen.fridge", "bathroom.sink", "bedroom.bed", "livingRoom.toyBox", "toyBox", "milkBottle",
	]:
		if not SemanticId.is_valid(good):
			failures.append("'%s' should be a valid semantic id" % good)
		if not SemanticId.problems(good).is_empty():
			failures.append("'%s' should report no problems, got %s" % [good, str(SemanticId.problems(good))])

	for bad: Variant in [
		"", "   ", ".", ".fridge", "kitchen.", "kitchen..fridge", "kitchen.fridge.door",
		"kitchen fridge", "kitchen.fridge door", "1kitchen.fridge", "kitchen.fridge!", null,
	]:
		if SemanticId.is_valid(bad):
			failures.append("'%s' must not be a valid semantic id" % str(bad))
		if SemanticId.problems(bad).is_empty():
			failures.append("'%s' is invalid and must say why" % str(bad))

	return failures


## The rule from contract §1, as a test: an id is a semantic name, and the things
## it must never be are the things that break when somebody renames a node or
## moves a fridge.
func _test_content_data_can_never_hold_a_node_path() -> Array:
	var failures: Array = []
	var not_ids: Array[String] = [
		"Rooms/Kitchen/Fridge",
		"../Fridge",
		"res://scenes/house/kitchen.tscn",
		"%Fridge",
		"(1.4, 0, -1.9)",
		"Fridge:position",
	]
	for junk: String in not_ids:
		if SemanticId.is_valid(junk):
			failures.append("'%s' is a path/coordinate, not a semantic id, and must be rejected" % junk)
	return failures


func _test_rooms() -> Array:
	var failures: Array = []
	for room: String in ["bedroom", "bathroom", "kitchen", "livingRoom"]:
		if not SemanticId.is_known_room(room):
			failures.append("'%s' is one of the four contract rooms" % room)
	if SemanticId.is_known_room("Kitchen"):
		failures.append("room ids are camelCase; 'Kitchen' is a typo, not a room")
	if SemanticId.is_known_room("garage"):
		failures.append("'garage' is not a room in this house")
	if SemanticId.KNOWN_ROOM_IDS.size() != 4:
		failures.append("the contract fixes four rooms, this lists %d"
				% SemanticId.KNOWN_ROOM_IDS.size())

	# Advisory, NOT enforcing: composing an id for a room that does not exist yet
	# must still work, or adding a fifth room would mean editing this file first.
	if SemanticId.compose("garage", "car") != "garage.car":
		failures.append("an unknown room must still compose; the room list is advisory")
	if not SemanticId.is_valid("garage.car"):
		failures.append("an unknown room id must still be structurally valid")
	return failures
