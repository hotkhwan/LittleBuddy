extends RefCounted

## Schema v4: the child's location in the house as two top-level semantic ids.
##
## `test_save_migration.gd` proves the MIGRATIONS are correct and idempotent.
## This case proves the four things that make v4 safe to ship on top of a real
## device profile:
##
##   1. the save layer's last-resort location is the same one the house actually
##      has -- the fallback chain is otherwise a lie told in two files;
##   2. the `SaveService` API round-trips, is idempotent, and reports where the
##      child ACTUALLY is rather than where a caller asked to put them;
##   3. `scripts/house/world_state.gd`, which still reads the v3
##      `settings.worldState` key, and the new v4 top-level fields never
##      disagree -- the compatibility shim is load-bearing until that file moves
##      (see `ProfileStore.DROP_LEGACY_WORLD_STATE`);
##   4. the owner's REAL 64-star profile comes through all of it with 64 stars,
##      33 completed activities and 11 stickers, exactly, even after the child
##      has walked around the house.
##
## Uses a throwaway `user://` path, never the real profile.json. Does not depend
## on autoloads -- `--script` does not load them. `run()` is untyped on purpose:
## a typed `-> Array` returns an empty Array when the case aborts, and a crashing
## case would report `[PASS]`.

const ProfileStoreScript := preload("res://scripts/save/profile_store.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const WorldState := preload("res://scripts/house/world_state.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const StickerBookScript := preload("res://scripts/progression/sticker_book.gd")

const DEVICE_FIXTURE_PATH := "res://tests/fixtures/device_profile_v1.json"
const DEVICE_STARS := 64
const DEVICE_COMPLETED_COUNT := 33
const DEVICE_STICKER_COUNT := 11


func test_name() -> String:
	return "save_world_location"


func run():
	var failures: Array = []
	var path := "user://test_world_location_%d.json" % randi()

	_cleanup(path)
	failures.append_array(_test_fallbacks_match_the_real_house())

	_cleanup(path)
	failures.append_array(_test_save_service_round_trip(path))

	_cleanup(path)
	failures.append_array(_test_save_service_refuses_nonsense(path))

	_cleanup(path)
	failures.append_array(_test_legacy_and_v4_never_disagree(path))

	_cleanup(path)
	failures.append_array(_test_device_profile_survives_a_walk_around_the_house(path))

	_cleanup(path)
	failures.append_array(_test_chapter2_is_untouched_by_movement(path))

	_cleanup(path)
	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _cleanup(path: String) -> void:
	for candidate: String in [path, path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _install_device_fixture(path: String) -> void:
	var src := FileAccess.open(DEVICE_FIXTURE_PATH, FileAccess.READ)
	var text := src.get_as_text()
	src.close()
	var dst := FileAccess.open(path, FileAccess.WRITE)
	dst.store_string(text)
	dst.close()


# ---------------------------------------------------------------------------
# 1. The two files agree about where "nowhere" resolves to
# ---------------------------------------------------------------------------

## `ProfileStore` deliberately does NOT import `house_layout.gd`: the save layer
## is domain logic and that file is full of `Vector3`/`Rect2`. The cost of that
## separation is a duplicated constant, so the duplication is asserted rather
## than trusted. Renaming the bedroom on either side fails here instead of
## quietly sending every recovering profile to a room that does not exist.
func _test_fallbacks_match_the_real_house():
	var failures: Array = []

	if ProfileStoreScript.FALLBACK_ROOM_ID != HouseLayout.FALLBACK_ROOM:
		failures.append(("the save layer falls back to room '%s' but the house's fallback room is "
				+ "'%s'; a recovering profile would be sent somewhere that does not exist")
				% [ProfileStoreScript.FALLBACK_ROOM_ID, HouseLayout.FALLBACK_ROOM])
	if ProfileStoreScript.DEFAULT_SPAWN_ID != HouseLayout.DEFAULT_SPAWN:
		failures.append("the save layer's default spawn '%s' is not the house's '%s'"
				% [ProfileStoreScript.DEFAULT_SPAWN_ID, HouseLayout.DEFAULT_SPAWN])

	# ...and the fallback must itself be real, or the chain terminates nowhere.
	if not HouseLayout.has_room(ProfileStoreScript.FALLBACK_ROOM_ID):
		failures.append("the save layer's fallback room '%s' is not in the house layout"
				% ProfileStoreScript.FALLBACK_ROOM_ID)
	if not HouseLayout.spawn_points(ProfileStoreScript.FALLBACK_ROOM_ID).has(
			ProfileStoreScript.DEFAULT_SPAWN_ID):
		failures.append("the fallback room has no '%s' spawn"
				% ProfileStoreScript.DEFAULT_SPAWN_ID)

	# The field names must match too -- world_state.gd serialises under these.
	if ProfileStoreScript.ROOM_FIELD != WorldState.ROOM_FIELD:
		failures.append("room field names disagree: save says '%s', world says '%s'"
				% [ProfileStoreScript.ROOM_FIELD, WorldState.ROOM_FIELD])
	if ProfileStoreScript.SPAWN_FIELD != WorldState.SPAWN_FIELD:
		failures.append("spawn field names disagree: save says '%s', world says '%s'"
				% [ProfileStoreScript.SPAWN_FIELD, WorldState.SPAWN_FIELD])
	if ProfileStoreScript.LEGACY_WORLD_STATE_KEY != WorldState.WORLD_STATE_KEY:
		failures.append("the compatibility shim watches settings.'%s' but world_state.gd writes "
				% ProfileStoreScript.LEGACY_WORLD_STATE_KEY
				+ "settings.'%s'; the bridge is not connected" % WorldState.WORLD_STATE_KEY)

	return failures


# ---------------------------------------------------------------------------
# 2. The SaveService API
# ---------------------------------------------------------------------------

func _test_save_service_round_trip(path: String):
	var failures: Array = []

	var store := ProfileStoreScript.new(path)
	var save: Node = SaveServiceScript.new(store)

	if save.get_current_room_id() != "bedroom" or save.get_current_spawn_id() != "default":
		failures.append("a fresh profile should start in the bedroom, got %s/%s"
				% [save.get_current_room_id(), save.get_current_spawn_id()])

	var seen: Array = []
	save.connect("world_location_changed", func(room: String, spawn: String) -> void:
		seen.append([room, spawn]))

	save.set_world_location("kitchen", "fromLivingRoom")
	if save.get_current_room_id() != "kitchen" or save.get_current_spawn_id() != "fromLivingRoom":
		failures.append("set_world_location did not stick, got %s/%s"
				% [save.get_current_room_id(), save.get_current_spawn_id()])
	if seen != [["kitchen", "fromLivingRoom"]]:
		failures.append("expected exactly one world_location_changed emission, got %s" % str(seen))

	# Idempotent: a door that re-fires must not churn the save file.
	save.set_world_location("kitchen", "fromLivingRoom")
	if seen.size() != 1:
		failures.append("re-setting the same location re-emitted, got %s" % str(seen))

	# ...and it survives a reload through a brand new store.
	var reloaded: Dictionary = ProfileStoreScript.new(path).load_profile()
	if String(reloaded.get("currentRoomId", "")) != "kitchen":
		failures.append("the location did not persist across reload, got %s"
				% str(reloaded.get("currentRoomId")))
	if String(reloaded.get("currentSpawnId", "")) != "fromLivingRoom":
		failures.append("the spawn did not persist across reload, got %s"
				% str(reloaded.get("currentSpawnId")))

	# A deep-copied snapshot cannot be used to move the child.
	var snapshot: Dictionary = save.get_profile()
	snapshot["currentRoomId"] = "bathroom"
	if save.get_current_room_id() != "kitchen":
		failures.append("get_profile() handed out a live reference to the world location")

	(save as Node).free()
	return failures


## The API reports where the child ACTUALLY is, not what it was asked for.
## Blank ids are the realistic case: an uninitialised transition, a content typo.
func _test_save_service_refuses_nonsense(path: String):
	var failures: Array = []

	var save: Node = SaveServiceScript.new(ProfileStoreScript.new(path))
	save.set_world_location("livingRoom", "fromKitchen")

	for nonsense: Array in [["", ""], ["   ", "  "], ["livingRoom.sofa", "fromKitchen"],
			["../bedroom", "default"]]:
		save.set_world_location(String(nonsense[0]), String(nonsense[1]))
		var room: String = save.get_current_room_id()
		var spawn: String = save.get_current_spawn_id()
		if room.is_empty() or spawn.is_empty():
			failures.append("%s left the child with an empty location %s/%s"
					% [str(nonsense), room, spawn])
		if room.contains(".") or room.contains("/"):
			failures.append("%s wrote a compound id '%s' through as a room" % [str(nonsense), room])
		save.set_world_location("livingRoom", "fromKitchen")

	(save as Node).free()
	return failures


# ---------------------------------------------------------------------------
# 3. The compatibility shim, from both directions
# ---------------------------------------------------------------------------

## Until `world_state.gd` moves to the top-level fields, two files write the
## child's location. They must never disagree -- a disagreement means the house
## puts the child in one room while the rest of the game believes another.
func _test_legacy_and_v4_never_disagree(path: String):
	var failures: Array = []
	var store := ProfileStoreScript.new(path)

	# Direction A: the HOUSE writes (v3 channel) -> v4 must see it.
	var profile: Dictionary = store.default_profile()
	var written: Dictionary = WorldState.create("bathroom", "fromLivingRoom").call(
		"write_into_profile", profile
	)
	if not bool(store.save_profile(written)):
		failures.append("could not save a house-written profile")
	var reloaded: Dictionary = store.load_profile()
	if String(reloaded.get("currentRoomId", "")) != "bathroom" \
			or String(reloaded.get("currentSpawnId", "")) != "fromLivingRoom":
		failures.append(("a location written through settings.worldState did not reach the v4 "
				+ "top-level fields; got %s/%s")
				% [str(reloaded.get("currentRoomId")), str(reloaded.get("currentSpawnId"))])

	# Direction B: the SAVE LAYER writes -> the house must still be able to read it.
	var save: Node = SaveServiceScript.new(store)
	save.set_world_location("kitchen", "fromBedroom")
	var after: Dictionary = ProfileStoreScript.new(path).load_profile()
	var house_view: RefCounted = WorldState.read_from_profile(after)
	if String(house_view.call("get_room_id")) != "kitchen" \
			or String(house_view.call("get_spawn_id")) != "fromBedroom":
		failures.append(("world_state.gd reads %s/%s but the save layer says %s/%s; the two "
				+ "storage locations have diverged")
				% [String(house_view.call("get_room_id")), String(house_view.call("get_spawn_id")),
				String(after.get("currentRoomId", "")), String(after.get("currentSpawnId", ""))])

	# And a STALE mirror can never survive a load claiming something else.
	var tampered: Dictionary = after.duplicate(true)
	(tampered["settings"] as Dictionary)["worldState"] = {
		"currentRoomId": "attic", "currentSpawnId": "fromCellar"
	}
	store.save_profile(tampered)
	var healed: Dictionary = store.load_profile()
	var mirror: Variant = (healed.get("settings", {}) as Dictionary).get("worldState", null)
	if typeof(mirror) == TYPE_DICTIONARY and (mirror as Dictionary) != {
		"currentRoomId": healed.get("currentRoomId"),
		"currentSpawnId": healed.get("currentSpawnId"),
	}:
		failures.append("the legacy mirror %s was left disagreeing with the top-level %s/%s"
				% [str(mirror), str(healed.get("currentRoomId")),
				str(healed.get("currentSpawnId"))])

	(save as Node).free()
	return failures


# ---------------------------------------------------------------------------
# 4. The owner's real profile
# ---------------------------------------------------------------------------

## 64 stars, 33 completed activities, 11 stickers. Not after the migration alone
## -- after the migration AND a session's worth of walking around the house,
## because that is the sequence that will actually run on the device.
func _test_device_profile_survives_a_walk_around_the_house(path: String):
	var failures: Array = []
	_install_device_fixture(path)

	var store := ProfileStoreScript.new(path)
	var save: Node = SaveServiceScript.new(store)

	var itinerary: Array = [
		["bedroom", "default"], ["bathroom", "fromBedroom"], ["livingRoom", "fromBathroom"],
		["kitchen", "fromLivingRoom"], ["bedroom", "fromKitchen"],
	]
	for stop: Array in itinerary:
		save.set_world_location(String(stop[0]), String(stop[1]))

	if save.get_current_room_id() != "bedroom" or save.get_current_spawn_id() != "fromKitchen":
		failures.append("the walk ended at %s/%s, expected bedroom/fromKitchen"
				% [save.get_current_room_id(), save.get_current_spawn_id()])

	var final_profile: Dictionary = ProfileStoreScript.new(path).load_profile()

	if int(final_profile.get("stars", -1)) != DEVICE_STARS:
		failures.append("the real device profile came out with %s stars, expected exactly %d"
				% [str(final_profile.get("stars")), DEVICE_STARS])
	var completed: Array = final_profile.get("completedActivities", [])
	if completed.size() != DEVICE_COMPLETED_COUNT:
		failures.append("the real device profile came out with %d completed activities, expected "
				% completed.size() + "exactly %d" % DEVICE_COMPLETED_COUNT)
	var settings: Dictionary = final_profile.get("settings", {})
	var stickers: Array = settings.get("unlockedStickers", [])
	if stickers.size() != DEVICE_STICKER_COUNT:
		failures.append("the real device profile came out with %d stickers, expected exactly %d"
				% [stickers.size(), DEVICE_STICKER_COUNT])
	if int(final_profile.get("profileVersion", 0)) != 4:
		failures.append("the real device profile did not reach v4, got %s"
				% str(final_profile.get("profileVersion")))

	(save as Node).free()
	return failures


# ---------------------------------------------------------------------------
# 5. Chapter 2 does not notice any of this
# ---------------------------------------------------------------------------

## Moving around the house must not disturb a single Chapter 2 fact, including
## the sticker book -- which lives in `settings`, exactly where the compatibility
## mirror also lives, so it is the plausible casualty.
func _test_chapter2_is_untouched_by_movement(path: String):
	var failures: Array = []

	var store := ProfileStoreScript.new(path)
	var save: Node = SaveServiceScript.new(store)

	save.add_stars(12)
	save.mark_activity_completed("feedMilk")
	save.mark_activity_completed("bathTime")
	save.set_level_stars("milkTime", 3)
	save.mark_level_completed("milkTime")
	save.unlock_level("bathTime")

	var book: RefCounted = StickerBookScript.create(save)
	book.call("unlock", "milkSticker")
	book.call("unlock", "teddySticker")

	var before: Dictionary = save.get_profile()

	save.set_world_location("livingRoom", "fromBathroom")
	save.set_world_location("kitchen", "fromLivingRoom")

	var after: Dictionary = ProfileStoreScript.new(path).load_profile()

	for key: String in ["stars", "completedActivities", "starsByLevel", "levelCompleted",
			"unlockedLevels", "unlockedChapters", "unlockedRooms", "currentChapter",
			"currentLevel"]:
		if after.get(key, null) != before.get(key, null):
			failures.append("'%s' changed while the child walked: %s -> %s"
					% [key, str(before.get(key)), str(after.get(key))])

	var stickers: Array = (after.get("settings", {}) as Dictionary).get("unlockedStickers", [])
	if not stickers.has("milkSticker") or not stickers.has("teddySticker"):
		failures.append("the sticker book lost entries when the world location was written to "
				+ "the same settings block, got %s" % str(stickers))

	# The sticker book still reads its own storage back through the same service.
	var reread: RefCounted = StickerBookScript.create(save)
	if not bool(reread.call("is_unlocked", "milkSticker")):
		failures.append("the sticker book could not read back 'milkSticker' after movement")

	(save as Node).free()
	return failures
