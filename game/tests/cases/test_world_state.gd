extends RefCounted

## World state: semantic room/spawn only, and the fallback chain that means a
## corrupt or stale save can never strand a child outside the navigation mesh.
##
## Contract §8. The fallback is the whole point of the file, so it is TESTED,
## not assumed -- including end to end through the real `ProfileStore`, on a
## throwaway `user://` path, proving the v3 schema carries world state with **no
## migration** and that the Chapter 2 baby save behaviour is untouched.
##
## `run()` is untyped on purpose.

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"
const WorldState := preload("res://scripts/house/world_state.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const ProfileStoreScript := preload("res://scripts/save/profile_store.gd")

## Every Chapter 2 fact that must survive untouched.
const CHAPTER2_KEYS: Array[String] = [
	"stars", "completedActivities", "starsByLevel", "levelCompleted", "unlockedLevels",
]


func test_name() -> String:
	return "world_state"


func run():
	var failures: Array = []
	failures.append_array(_test_resolution())
	failures.append_array(_test_dictionary_round_trip())
	failures.append_array(_test_no_coordinates_are_persisted())
	failures.append_array(_test_profile_round_trip())
	failures.append_array(_test_world_restores_and_falls_back())
	return failures


## The fallback chain, exhaustively: unknown spawn -> the room's default;
## unknown room -> the bedroom's default.
func _test_resolution() -> Array:
	var failures: Array = []

	var exact: Dictionary = WorldState.resolve("bathroom", "fromBedroom")
	if String(exact["roomId"]) != "bathroom" or String(exact["spawnId"]) != "fromBedroom":
		failures.append("a valid room/spawn was not preserved: %s" % str(exact))
	if bool(exact["roomFallback"]) or bool(exact["spawnFallback"]):
		failures.append("a valid room/spawn reported a fallback")

	# Unknown spawn, valid room.
	var bad_spawn: Dictionary = WorldState.resolve("kitchen", "fromNarnia")
	if String(bad_spawn["roomId"]) != "kitchen":
		failures.append("an unknown spawn moved the child to another room")
	if String(bad_spawn["spawnId"]) != HouseLayout.DEFAULT_SPAWN:
		failures.append("an unknown spawn should fall back to the room default, got '%s'"
				% String(bad_spawn["spawnId"]))
	if not bool(bad_spawn["spawnFallback"]):
		failures.append("an unknown spawn did not report a fallback")

	# Unknown room: all the way back to the bedroom.
	for rubbish: Array in [
		["dungeon", "default"], ["", ""], ["   ", "fromBedroom"], ["Bedroom", "default"],
		["bedroom.bed", "default"],
	]:
		var resolved: Dictionary = WorldState.resolve(String(rubbish[0]), String(rubbish[1]))
		if String(resolved["roomId"]) != HouseLayout.FALLBACK_ROOM:
			failures.append("room '%s' should fall back to the %s, got '%s'"
					% [String(rubbish[0]), HouseLayout.FALLBACK_ROOM, String(resolved["roomId"])])
		if String(resolved["spawnId"]) != HouseLayout.DEFAULT_SPAWN:
			failures.append("room '%s' should fall back to the default spawn, got '%s'"
					% [String(rubbish[0]), String(resolved["spawnId"])])
		if not bool(resolved["roomFallback"]):
			failures.append("room '%s' did not report a room fallback" % String(rubbish[0]))

	# Whitespace is forgiven rather than treated as a different room.
	var padded: Dictionary = WorldState.resolve("  kitchen  ", "  default ")
	if String(padded["roomId"]) != "kitchen":
		failures.append("a padded room id should still resolve, got '%s'"
				% String(padded["roomId"]))

	# And the fallback room must itself be real, or the whole chain is a lie.
	if not HouseLayout.has_room(HouseLayout.FALLBACK_ROOM):
		failures.append("the fallback room '%s' is not in the layout" % HouseLayout.FALLBACK_ROOM)
	if not HouseLayout.spawn_points(HouseLayout.FALLBACK_ROOM).has(HouseLayout.DEFAULT_SPAWN):
		failures.append("the fallback room has no default spawn")
	return failures


func _test_dictionary_round_trip() -> Array:
	var failures: Array = []
	var state: RefCounted = WorldState.create("livingRoom", "fromKitchen")
	var as_dict: Dictionary = state.call("to_dict")
	if as_dict != {"currentRoomId": "livingRoom", "currentSpawnId": "fromKitchen"}:
		failures.append("world state should serialise as currentRoomId/currentSpawnId, got %s"
				% str(as_dict))

	var restored: RefCounted = WorldState.from_dict(as_dict)
	if String(restored.call("get_room_id")) != "livingRoom" \
			or String(restored.call("get_spawn_id")) != "fromKitchen":
		failures.append("a round trip changed the location")

	# Rubbish in, bedroom out -- never a crash.
	for rubbish: Variant in [null, [], "bedroom", 42, {"currentRoomId": 7}] :
		var recovered: RefCounted = WorldState.from_dict(rubbish)
		if String(recovered.call("get_room_id")) != HouseLayout.FALLBACK_ROOM:
			failures.append("from_dict(%s) should recover to the bedroom" % str(rubbish))

	if bool(state.call("set_location", "nowhere", "default")):
		failures.append("set_location should report that it had to fall back")
	if String(state.call("get_room_id")) != HouseLayout.FALLBACK_ROOM:
		failures.append("set_location did not fall back to the bedroom")
	return failures


## Contract §8: never a raw `Vector3` as the only recovery mechanism. The
## persisted payload must be two strings and nothing else.
func _test_no_coordinates_are_persisted() -> Array:
	var failures: Array = []
	var stored: Dictionary = WorldState.create("kitchen", "fromBedroom").call("to_dict")
	for key: String in stored.keys():
		if typeof(stored[key]) != TYPE_STRING:
			failures.append("world state persists '%s' as %s; only semantic strings may be saved"
					% [key, type_string(typeof(stored[key]))])
	var source: String = _read("res://scripts/house/world_state.gd")
	for forbidden: String in ["Vector3(", "position", "global_position"]:
		if source.contains(forbidden):
			failures.append("world_state.gd mentions '%s'; it must stay coordinate-free"
					% forbidden)
	return failures


## End to end through the real `ProfileStore`, on a throwaway path.
func _test_profile_round_trip() -> Array:
	var failures: Array = []
	var path: String = "user://test_world_state_%d.json" % randi()
	var store: RefCounted = ProfileStoreScript.new(path)

	var profile: Dictionary = store.call("default_profile")
	# Chapter 2 facts that must come back untouched.
	profile["stars"] = 7
	profile["completedActivities"] = ["feedMilk", "bathTime"]
	profile["starsByLevel"] = {"milkTime": 3}
	profile["levelCompleted"] = {"milkTime": true}
	profile["unlockedLevels"] = ["milkTime"]

	var written: Dictionary = WorldState.create("kitchen", "fromLivingRoom").call(
		"write_into_profile", profile
	)
	if not bool(store.call("save_profile", written)):
		failures.append("could not save the profile")

	var reloaded: Dictionary = store.call("load_profile")
	var state: RefCounted = WorldState.read_from_profile(reloaded)
	if String(state.call("get_room_id")) != "kitchen":
		failures.append("the saved room did not survive a save/load round trip (got '%s'); "
				% String(state.call("get_room_id"))
				+ "world state must round-trip through the v3 schema without a migration")
	if String(state.call("get_spawn_id")) != "fromLivingRoom":
		failures.append("the saved spawn did not survive a round trip")

	# Chapter 2 save behaviour is untouched.
	for key: String in CHAPTER2_KEYS:
		if reloaded.get(key, null) != profile.get(key, null):
			failures.append("'%s' changed across the world-state round trip: %s -> %s"
					% [key, str(profile.get(key, null)), str(reloaded.get(key, null))])
	if int(reloaded.get("profileVersion", 0)) != int(ProfileStoreScript.CURRENT_VERSION):
		failures.append("the save schema version changed; world state must not require a bump")

	# A profile that has never seen the house starts in the bedroom.
	var fresh: RefCounted = WorldState.read_from_profile(store.call("default_profile"))
	if String(fresh.call("get_room_id")) != HouseLayout.FALLBACK_ROOM:
		failures.append("a profile with no world state should start in the bedroom")
	for rubbish: Variant in [null, {}, {"settings": "nonsense"}, {"settings": {"worldState": 5}}]:
		var recovered: RefCounted = WorldState.read_from_profile(rubbish)
		if String(recovered.call("get_room_id")) != HouseLayout.FALLBACK_ROOM:
			failures.append("a corrupt profile (%s) should recover to the bedroom" % str(rubbish))

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return failures


## The property that actually protects a child: an invalid saved location puts
## them somewhere real, standing on the navigation mesh, in a room that exists.
func _test_world_restores_and_falls_back() -> Array:
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var packed: Resource = load(SCENE_PATH)
	if not (packed is PackedScene):
		return ["could not load %s" % SCENE_PATH]
	var world: Node = (packed as PackedScene).instantiate()
	tree.root.add_child(world)
	world.call("_ready")

	var character: Node = world.call("get_character")

	# A good save is honoured exactly.
	var good: Dictionary = WorldState.create("livingRoom", "fromKitchen").call(
		"write_into_profile", {}
	)
	if not bool(world.call("restore_from_profile", good)):
		failures.append("a valid saved location was not restored")
	if String(world.call("get_current_room_id")) != "livingRoom":
		failures.append("restored into '%s', expected the living room"
				% String(world.call("get_current_room_id")))
	var expected: Vector3 = world.call("get_room", "livingRoom").call(
		"get_spawn_position", "fromKitchen"
	)
	if not NavMath.is_within(SpatialUtil.world_position(character as Node3D), expected, 0.05):
		failures.append("the child was not restored to the saved spawn point")

	# A room that no longer exists -- the case a room rename produces.
	var stale: Dictionary = {"settings": {"worldState": {
		"currentRoomId": "attic", "currentSpawnId": "fromCellar"
	}}}
	if not bool(world.call("restore_from_profile", stale)):
		failures.append("a stale saved room should still place the child somewhere")
	if String(world.call("get_current_room_id")) != HouseLayout.FALLBACK_ROOM:
		failures.append("a stale saved room left the child in '%s', expected the bedroom"
				% String(world.call("get_current_room_id")))
	var bedroom_default: Vector3 = world.call("get_room", "bedroom").call(
		"get_spawn_position", "default"
	)
	if not NavMath.is_within(SpatialUtil.world_position(character as Node3D), bedroom_default, 0.05):
		failures.append("a stale saved room did not put the child on the bedroom's default spawn")
	if String(character.call("get_state_name")) == "disabled":
		failures.append("the child is not in control after a fallback restore")

	# A valid room with a spawn that has gone away.
	var half_stale: Dictionary = {"settings": {"worldState": {
		"currentRoomId": "kitchen", "currentSpawnId": "fromAttic"
	}}}
	world.call("restore_from_profile", half_stale)
	if String(world.call("get_current_room_id")) != "kitchen":
		failures.append("a stale SPAWN should not move the child out of a valid room")
	var kitchen_default: Vector3 = world.call("get_room", "kitchen").call(
		"get_spawn_position", "default"
	)
	if not NavMath.is_within(SpatialUtil.world_position(character as Node3D), kitchen_default, 0.05):
		failures.append("a stale spawn did not fall back to the kitchen's default")

	# And what the world writes back is what it would read.
	var saved: Dictionary = world.call("write_into_profile", {})
	var read_back: RefCounted = WorldState.read_from_profile(saved)
	if String(read_back.call("get_room_id")) != "kitchen" \
			or String(read_back.call("get_spawn_id")) != HouseLayout.DEFAULT_SPAWN:
		failures.append("the world wrote back %s, which is not where the child is"
				% str(read_back.call("to_dict")))

	tree.root.remove_child(world)
	world.free()
	return failures


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
