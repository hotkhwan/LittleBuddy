extends RefCounted

## What the house does once the menu has routed a child into it: Story or Free
## Play, which rooms are open, and where a returning child wakes up.
##
## Two dead ends are pinned here, and both are the kind that would be invisible
## until a real profile hit them:
##
##   1. **`unlockedRooms: []` must mean "all of them".** That is what a fresh
##      profile carries. Reading it as "no room is unlocked" would lock a child
##      out of the entire house on their very first Free Play, with nothing on
##      screen to tap.
##   2. **An invalid saved room falls back to the bedroom.** A room rename, a
##      corrupt save or a profile from a future build must still put the child
##      somewhere real, standing on the navigation mesh.
##
## Also: the v4 save writes `currentRoomId` / `currentSpawnId` at the TOP LEVEL
## and `ProfileStore` never creates the old `settings.worldState` mirror, so a
## house that read only the mirror would see nothing in a fresh profile and wake
## every returning child in the bedroom -- while every test stayed green, because
## the bedroom is also the correct answer for a profile that has never been in
## the house. That one is asserted explicitly.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const HouseLayout := preload("res://scripts/house/house_layout.gd")
const WorldState := preload("res://scripts/house/world_state.gd")
const ProfileStoreScript := preload("res://scripts/save/profile_store.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"


func test_name() -> String:
	return "house_session"


func run():
	var failures: Array = []
	failures.append_array(_test_progression_mode())
	failures.append_array(_test_unlocked_rooms_are_never_all_locked())
	failures.append_array(_test_a_locked_saved_room_still_places_the_child())
	failures.append_array(_test_v4_top_level_location_is_honoured())
	return failures


## -- Story / Free Play -----------------------------------------------------------

func _test_progression_mode():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]

	# Story is the default: a world nobody configured must not silently be a
	# no-objective sandbox.
	if bool(world.call("is_free_play")):
		failures.append("an unconfigured house came up in Free Play")
	if int(world.call("get_progression_mode")) != 0:
		failures.append("the default progression mode is not STORY")

	world.call("set_progression_mode", 1)
	if not bool(world.call("is_free_play")):
		failures.append("set_progression_mode(FREE_PLAY) did not take")
	world.call("set_progression_mode", 0)
	if bool(world.call("is_free_play")):
		failures.append("set_progression_mode(STORY) did not take")

	# Anything that is not FREE_PLAY is STORY, so a stray value cannot drop a
	# child into a mode nobody wrote.
	for rubbish: int in [-1, 7, 99]:
		world.call("set_progression_mode", rubbish)
		if bool(world.call("is_free_play")):
			failures.append("mode %d was read as Free Play" % rubbish)

	_release(world)
	return failures


## -- Unlocked rooms ---------------------------------------------------------------

func _test_unlocked_rooms_are_never_all_locked():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]

	var every_room: Array = world.call("get_room_ids")
	if every_room.size() < 4:
		failures.append("the house has %d rooms, expected four" % every_room.size())

	# Unset: the whole house.
	if world.call("get_unlocked_room_ids") != every_room:
		failures.append("an unconfigured house should have every room open, got %s"
				% str(world.call("get_unlocked_room_ids")))

	# THE ONE THAT MATTERS: a fresh profile carries `unlockedRooms: []`.
	world.call("set_unlocked_room_ids", [])
	if world.call("get_unlocked_room_ids") != every_room:
		failures.append(
			"an empty unlock list left %s open. A brand new profile carries `unlockedRooms: []`, "
			% str(world.call("get_unlocked_room_ids"))
			+ "so reading it as 'no room is unlocked' locks a child out of the whole house on "
			+ "their first Free Play."
		)

	# A real subset is honoured, and the fallback room is always in it so the
	# resolver always has somewhere to land.
	world.call("set_unlocked_room_ids", ["kitchen"])
	var open: Array = world.call("get_unlocked_room_ids")
	if not open.has("kitchen"):
		failures.append("an explicitly unlocked room is not open")
	if not open.has(HouseLayout.FALLBACK_ROOM):
		failures.append("the fallback room '%s' must always be open, or the fallback chain "
				% HouseLayout.FALLBACK_ROOM + "ends nowhere")
	if open.has("bathroom"):
		failures.append("a room that was never unlocked is open anyway; the unlock list does "
				+ "nothing")

	# Every id names a room that does not exist. The list is not opened wider than
	# it was authored, but the fallback room keeps the child out of a house with
	# no doors.
	world.call("set_unlocked_room_ids", ["attic", "cellar"])
	var nonsense: Array = world.call("get_unlocked_room_ids")
	if nonsense.is_empty():
		failures.append("an unlock list of unknown rooms left the whole house locked")
	if not nonsense.has(HouseLayout.FALLBACK_ROOM):
		failures.append("an unlock list of unknown rooms left the fallback room shut, got %s"
				% str(nonsense))

	# Rubbish instead of a list is ignored, not obeyed.
	world.call("set_unlocked_room_ids", "kitchen")
	if world.call("get_unlocked_room_ids") != every_room:
		failures.append("a non-array unlock list should open the whole house")

	_release(world)
	return failures


func _test_a_locked_saved_room_still_places_the_child():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]
	var character: Node = world.call("get_character")

	world.call("set_unlocked_room_ids", ["bedroom", "kitchen"])

	# A saved room that is real but locked this session.
	if not bool(world.call("enter_saved_location", "bathroom", "default")):
		failures.append("a locked saved room left the child unplaced")
	var landed: String = String(world.call("get_current_room_id"))
	if not bool(world.call("is_room_unlocked", landed)):
		failures.append("the child was placed in '%s', which is not unlocked" % landed)
	if landed == "bathroom":
		failures.append("a locked room was entered anyway; the unlock set does nothing")

	# And they are standing on a real spawn point, not at the origin.
	var expected: Vector3 = world.call("get_room", landed).call(
		"get_spawn_position", String(world.call("get_current_spawn_id"))
	)
	if character != null \
			and not NavMath.is_within(SpatialUtil.world_position(character as Node3D), expected, 0.05):
		failures.append("the child is not standing on the spawn point they were placed on")

	# A room that has never existed, with every room open: the bedroom.
	world.call("set_unlocked_room_ids", [])
	if not bool(world.call("enter_saved_location", "attic", "fromCellar")):
		failures.append("an unknown saved room left the child unplaced")
	if String(world.call("get_current_room_id")) != HouseLayout.FALLBACK_ROOM:
		failures.append("an unknown saved room put the child in '%s', expected the bedroom"
				% String(world.call("get_current_room_id")))
	if String(world.call("get_current_spawn_id")) != HouseLayout.DEFAULT_SPAWN:
		failures.append("an unknown saved room did not use the default spawn")

	# A real room with a spawn that has gone away stays in the room.
	if not bool(world.call("enter_saved_location", "kitchen", "fromAttic")):
		failures.append("a stale spawn left the child unplaced")
	if String(world.call("get_current_room_id")) != "kitchen":
		failures.append("a stale SPAWN moved the child out of a valid room")

	if character != null and String(character.call("get_state_name")) == "disabled":
		failures.append("the child is not in control after a fallback placement")

	_release(world)
	failures.append_array(_test_a_room_missing_from_the_scene())
	return failures


## A room the LAYOUT still knows but this scene does not have -- what a half-done
## room rename, or a scene edited without the layout, actually looks like.
##
## `world_state.gd::resolve()` cannot catch this: the id is perfectly valid
## layout-side, so it passes straight through and only the world itself can tell
## that there is no such node. Without this the guard in `enter_saved_location()`
## is unreachable and could be deleted with the whole suite green.
func _test_a_room_missing_from_the_scene():
	var failures: Array = []
	if not ResourceLoader.exists(HOUSE_SCENE):
		return ["%s does not exist" % HOUSE_SCENE]
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return ["could not load %s" % HOUSE_SCENE]
	var world: Node = (packed as PackedScene).instantiate()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]

	var rooms_root: Node = world.get_node_or_null(NodePath("Rooms"))
	var bathroom: Node = rooms_root.get_node_or_null(NodePath("Bathroom")) \
			if rooms_root != null else null
	if bathroom == null:
		world.free()
		return ["the house scene has no Rooms/Bathroom; this case is testing nothing"]
	# Removed BEFORE the world is built, so it is never collected at all.
	rooms_root.remove_child(bathroom)
	bathroom.free()

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	world.call("build_world")

	if bool(world.call("has_room", "bathroom")):
		failures.append("the bathroom was removed but the world still reports it")
	if not HouseLayout.has_room("bathroom"):
		failures.append("the layout no longer knows the bathroom; this case is vacuous")

	if not bool(world.call("enter_saved_location", "bathroom", "fromBedroom")):
		failures.append(
			"a saved room that the layout knows but the SCENE does not left the child unplaced. "
			+ "world_state.gd cannot catch this -- the id is valid layout-side -- so the house "
			+ "has to."
		)
	if String(world.call("get_current_room_id")) != HouseLayout.FALLBACK_ROOM:
		failures.append("a room missing from the scene put the child in '%s', expected the bedroom"
				% String(world.call("get_current_room_id")))
	if String(world.call("get_current_spawn_id")) != HouseLayout.DEFAULT_SPAWN:
		failures.append("a room missing from the scene kept the old spawn '%s'; 'fromBedroom' "
				% String(world.call("get_current_spawn_id"))
				+ "means nothing in the room it fell back to")

	_release(world)
	return failures


## -- Save schema v4 ---------------------------------------------------------------

func _test_v4_top_level_location_is_honoured():
	var failures: Array = []

	# A real v4 profile, straight out of ProfileStore, with no legacy mirror.
	var store: RefCounted = ProfileStoreScript.new("user://test_house_session_%d.json" % randi())
	var profile: Dictionary = store.call("default_profile")
	profile[ProfileStoreScript.ROOM_FIELD] = "livingRoom"
	profile[ProfileStoreScript.SPAWN_FIELD] = "fromKitchen"
	if (profile.get("settings", {}) as Dictionary).has("worldState"):
		failures.append("default_profile() now carries a legacy settings.worldState; this case "
				+ "is testing the wrong thing")

	var state: RefCounted = WorldState.read_from_profile(profile)
	if String(state.call("get_room_id")) != "livingRoom":
		failures.append(
			"a v4 profile's top-level currentRoomId was ignored (got '%s'). ProfileStore never "
			% String(state.call("get_room_id"))
			+ "CREATES settings.worldState, so a house reading only the mirror sees nothing at "
			+ "all and wakes every returning child in the bedroom -- with the suite green, "
			+ "because the bedroom is also the right answer for a profile that has never been "
			+ "in the house."
		)
	if String(state.call("get_spawn_id")) != "fromKitchen":
		failures.append("a v4 profile's top-level currentSpawnId was ignored")

	# The legacy mirror is still read, so a v3 profile is not stranded.
	var legacy: Dictionary = {"settings": {"worldState": {
		"currentRoomId": "kitchen", "currentSpawnId": "fromBedroom"
	}}}
	var from_legacy: RefCounted = WorldState.read_from_profile(legacy)
	if String(from_legacy.call("get_room_id")) != "kitchen":
		failures.append("a v3 settings.worldState profile no longer restores")

	# The top level wins when the two disagree: the mirror can go stale, the real
	# fields cannot.
	var both: Dictionary = {
		ProfileStoreScript.ROOM_FIELD: "bathroom",
		ProfileStoreScript.SPAWN_FIELD: "default",
		"settings": {"worldState": {"currentRoomId": "kitchen", "currentSpawnId": "default"}},
	}
	if String(WorldState.read_from_profile(both).call("get_room_id")) != "bathroom":
		failures.append("a stale settings.worldState mirror overrode the authoritative v4 fields")

	# What the world writes is what the save layer reads.
	var written: Dictionary = WorldState.create("kitchen", "fromBedroom").call(
		"write_into_profile", store.call("default_profile")
	)
	if String(written.get(ProfileStoreScript.ROOM_FIELD, "")) != "kitchen":
		failures.append("write_into_profile() does not write the v4 top-level room field")
	if String(written.get(ProfileStoreScript.SPAWN_FIELD, "")) != "fromBedroom":
		failures.append("write_into_profile() does not write the v4 top-level spawn field")

	# And through the real house, end to end.
	var world: Node = _build_house()
	if world != null:
		world.call("restore_from_profile", profile)
		if String(world.call("get_current_room_id")) != "livingRoom":
			failures.append("the house did not restore a v4 profile into the living room, got '%s'"
					% String(world.call("get_current_room_id")))
		var saved: Dictionary = world.call("write_into_profile", profile)
		if String(saved.get(ProfileStoreScript.ROOM_FIELD, "")) != "livingRoom":
			failures.append("the house wrote back '%s', which is not where the child is"
					% String(saved.get(ProfileStoreScript.ROOM_FIELD, "")))
		_release(world)

	return failures


## -- Helpers -----------------------------------------------------------------------

func _build_house() -> Node:
	if not ResourceLoader.exists(HOUSE_SCENE):
		return null
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	if world == null:
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	# `_ready()` does not fire for a node added to the root in the headless
	# `--script` runner, so the world is built by hand.
	world.call("build_world")
	return world


func _release(world: Node) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()
