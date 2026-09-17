extends RefCounted

## "Which doors do I walk through to get from here to there?" -- pure, static,
## and the only place that answers it.
##
## The house is a RING (`HouseLayout.ROOM_RING`): bedroom -> bathroom ->
## livingRoom -> kitchen -> bedroom. So every room is reachable from every other
## in at most two hops, and there is no dead end anywhere in the topology. The
## level loop leans on that: the walk home at the end of the day genuinely has to
## pass through the kitchen, because the living room has no door to the bedroom.
##
## Everything here is Strings and ints -- no `Node`, no navigation, no geometry --
## so a route can be computed and asserted without a scene, and the same answer
## drives the runtime and the tests.

const HouseLayout := preload("res://scripts/house/house_layout.gd")
const SemanticId := preload("res://scripts/navigation/semantic_id.gd")

## Local ids of doors all start with this, which is how a semantic target id can
## be recognised as a door without loading the scene it lives in.
const DOOR_PREFIX: String = "doorTo"


## True for `"bedroom.doorToBathroom"` (and for the bare `"doorToBathroom"`).
static func is_door_id(semantic_id: Variant) -> bool:
	return _local_of(semantic_id).begins_with(DOOR_PREFIX)


## The room a door leads to: `"bedroom.doorToBathroom"` -> `"bathroom"`.
## "" for anything that is not a door, or for a door naming a room the house
## does not have -- never a guess.
static func door_destination(semantic_id: Variant) -> String:
	var local: String = _local_of(semantic_id)
	if not local.begins_with(DOOR_PREFIX):
		return ""
	var tail: String = local.substr(DOOR_PREFIX.length())
	if tail.is_empty():
		return ""
	var room_id: String = tail.substr(0, 1).to_lower() + tail.substr(1)
	return room_id if HouseLayout.has_room(room_id) else ""


## The doors to walk through, in order, as SEMANTIC ids -- each one addressed in
## the room the child will be standing in when they use it:
##
##     door_sequence("livingRoom", "bedroom")
##     -> ["livingRoom.doorToKitchen", "kitchen.doorToBedroom"]
##
## Empty for "already there" and for any room the house does not have, which the
## caller must read as "no route needed / no route possible" -- never as a crash.
static func door_sequence(from_room_id: String, to_room_id: String) -> Array:
	var route: Array = []
	if not HouseLayout.has_room(from_room_id) or not HouseLayout.has_room(to_room_id):
		return route
	if from_room_id == to_room_id:
		return route

	var ring: Array = HouseLayout.room_ids()
	var size: int = ring.size()
	var start: int = ring.find(from_room_id)
	var end: int = ring.find(to_room_id)
	var forward_steps: int = (end - start + size) % size
	var backward_steps: int = size - forward_steps
	# Ties (exactly opposite on a 4-room ring) go forward, so a route is stable
	# and a test can assert one answer rather than "either of two".
	var step: int = 1 if forward_steps <= backward_steps else -1
	var hops: int = forward_steps if forward_steps <= backward_steps else backward_steps

	var here: int = start
	for _hop: int in range(hops):
		var next_index: int = (here + step + size) % size
		var here_room: String = String(ring[here])
		var next_room: String = String(ring[next_index])
		route.append(SemanticId.compose(here_room, HouseLayout.door_target_id(next_room)))
		here = next_index
	return route


## How many doors lie between two rooms. 0 means "same room".
static func hop_count(from_room_id: String, to_room_id: String) -> int:
	return door_sequence(from_room_id, to_room_id).size()


## The first door of the route, or "" when none is needed.
static func next_door(from_room_id: String, to_room_id: String) -> String:
	var route: Array = door_sequence(from_room_id, to_room_id)
	if route.is_empty():
		return ""
	return String(route[0])


static func _local_of(semantic_id: Variant) -> String:
	var text: String = String(semantic_id).strip_edges()
	if text.is_empty():
		return ""
	if text.contains(SemanticId.SEPARATOR):
		return SemanticId.target_of(text)
	return text
