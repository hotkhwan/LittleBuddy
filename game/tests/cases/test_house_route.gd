extends RefCounted

## Ring routing, asserted as pure data: which doors get you from A to B.
##
## The house is a ring -- bedroom -> bathroom -> livingRoom -> kitchen -> bedroom
## -- and the living room has NO door to the bedroom. The walk home at the end of
## the day therefore genuinely has to pass through the kitchen, which is exactly
## what `tidyAndBed` authors and exactly what the level loop has to be able to do
## by itself when a child skips the walking task.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const HouseRoute := preload("res://scripts/house/house_route.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")


func test_name() -> String:
	return "house_route"


func run():
	var failures: Array = []
	failures.append_array(_test_door_ids_are_recognised())
	failures.append_array(_test_adjacent_rooms_are_one_door())
	failures.append_array(_test_opposite_rooms_are_two_doors())
	failures.append_array(_test_every_pair_is_routable())
	failures.append_array(_test_routes_use_doors_that_exist())
	failures.append_array(_test_nonsense_is_refused_not_guessed())
	return failures


func _test_door_ids_are_recognised():
	var failures: Array = []
	if not HouseRoute.is_door_id("bedroom.doorToBathroom"):
		failures.append("a semantic door id must be recognised as a door")
	if not HouseRoute.is_door_id("doorToKitchen"):
		failures.append("a bare door id must be recognised as a door")
	if HouseRoute.is_door_id("bathroom.sink"):
		failures.append("a sink is not a door; a level would teleport off it")
	if HouseRoute.door_destination("bedroom.doorToBathroom") != "bathroom":
		failures.append("bedroom.doorToBathroom must lead to the bathroom, got '%s'"
				% HouseRoute.door_destination("bedroom.doorToBathroom"))
	if HouseRoute.door_destination("livingRoom.doorToKitchen") != "kitchen":
		failures.append("livingRoom.doorToKitchen must lead to the kitchen")
	if not HouseRoute.door_destination("bathroom.sink").is_empty():
		failures.append("a non-door must lead nowhere rather than to a guess")
	if not HouseRoute.door_destination("bedroom.doorToGarage").is_empty():
		failures.append("a door to a room the house does not have must resolve to '', not to a "
				+ "plausible-looking room id")
	return failures


func _test_adjacent_rooms_are_one_door():
	var failures: Array = []
	var pairs: Array = [
		["bedroom", "bathroom", "bedroom.doorToBathroom"],
		["bathroom", "livingRoom", "bathroom.doorToLivingRoom"],
		["livingRoom", "kitchen", "livingRoom.doorToKitchen"],
		["kitchen", "bedroom", "kitchen.doorToBedroom"],
		["bathroom", "bedroom", "bathroom.doorToBedroom"],
	]
	for pair: Array in pairs:
		var route: Array = HouseRoute.door_sequence(String(pair[0]), String(pair[1]))
		if route != [String(pair[2])]:
			failures.append("%s -> %s should be one door (%s), got %s"
					% [pair[0], pair[1], pair[2], str(route)])
	return failures


## The one that matters for `tidyAndBed`: the living room cannot reach the
## bedroom directly, and the route the loop computes must be the route the
## content authors (`walkHomeToKitchen`, then `walkHomeToBedroom`).
func _test_opposite_rooms_are_two_doors():
	var failures: Array = []
	var route: Array = HouseRoute.door_sequence("livingRoom", "bedroom")
	if route != ["livingRoom.doorToKitchen", "kitchen.doorToBedroom"]:
		failures.append("the walk home must go through the kitchen, got %s" % str(route))
	if HouseRoute.hop_count("livingRoom", "bedroom") != 2:
		failures.append("the living room is two doors from the bedroom")
	if HouseRoute.next_door("livingRoom", "bedroom") != "livingRoom.doorToKitchen":
		failures.append("the first door of the walk home is the kitchen door")
	return failures


func _test_every_pair_is_routable():
	var failures: Array = []
	var rooms: Array = HouseLayout.room_ids()
	if rooms.size() < 4:
		return ["the house has %d rooms; this test would be vacuous" % rooms.size()]
	for from_room: Variant in rooms:
		for to_room: Variant in rooms:
			var route: Array = HouseRoute.door_sequence(String(from_room), String(to_room))
			if String(from_room) == String(to_room):
				if not route.is_empty():
					failures.append("%s -> itself must need no doors, got %s"
							% [from_room, str(route)])
				continue
			if route.is_empty():
				failures.append("no route from the %s to the %s; every room must be reachable "
						% [from_room, to_room] + "or a level could dead-end")
			if route.size() > 2:
				failures.append("%s -> %s takes %d doors; the ring guarantees at most 2"
						% [from_room, to_room, route.size()])
	return failures


## A route is only usable if every door in it exists IN THE ROOM the child will
## be standing in when they reach it. A route naming a door from the wrong room
## would refuse silently and strand the level.
func _test_routes_use_doors_that_exist():
	var failures: Array = []
	for from_room: Variant in HouseLayout.room_ids():
		for to_room: Variant in HouseLayout.room_ids():
			var here: String = String(from_room)
			for entry: Variant in HouseRoute.door_sequence(here, String(to_room)):
				var door_id: String = String(entry)
				var expected_prefix: String = "%s." % here
				if not door_id.begins_with(expected_prefix):
					failures.append("route %s -> %s uses '%s' while the child is in the %s"
							% [from_room, to_room, door_id, here])
					break
				if not HouseLayout.target_ids(here).has(door_id.substr(expected_prefix.length())):
					failures.append("the %s has no door '%s'" % [here, door_id])
					break
				here = HouseRoute.door_destination(door_id)
	return failures


func _test_nonsense_is_refused_not_guessed():
	var failures: Array = []
	for pair: Array in [["garage", "bedroom"], ["bedroom", "garage"], ["", ""]]:
		if not HouseRoute.door_sequence(String(pair[0]), String(pair[1])).is_empty():
			failures.append("a route involving a room this house does not have must be empty, "
					+ "never a guess (%s -> %s)" % [pair[0], pair[1]])
	return failures
