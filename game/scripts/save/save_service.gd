extends Node

## Autoload wrapper around ProfileStore. Local-only persistence: stars,
## completed activities, level/chapter progression, and settings. No
## network, no cloud sync, no analytics, no accounts.
##
## Three separate facts live side by side here and are never summed or
## conflated:
##   - "stars" (get_stars/add_stars) is the lifetime TASK star total that
##     feeds sticker unlockAtStars thresholds. Unchanged by this phase.
##   - starsByLevel (get_level_stars/set_level_stars) is a per-level 0..3
##     HONEST rating. set_level_stars is max-wins: replaying a level with a
##     worse result never lowers the stored rating. A level finished entirely
##     by skipping rates 0 -- skipped tasks are not achievements.
##   - levelCompleted (is_level_completed/mark_level_completed) is "the child
##     reached the end of this level", true even when every task was skipped.
##     UNLOCKING GATES ON THIS, never on a star count, so the skip button can
##     never trap a child and a 0-star completion still opens the next level.

signal profile_changed(profile: Dictionary)
signal stars_changed(stars: int)
signal level_stars_changed(level_id: String, stars: int)
signal level_completed_changed(level_id: String)
signal world_location_changed(room_id: String, spawn_id: String)

var _store: ProfileStore
var _profile: Dictionary = {}


## `p_store` is test-only injection (e.g. a ProfileStore pointed at a temp
## user:// path and a fixture levels/missions path). The real autoload is
## always instantiated with zero arguments and gets the real ProfileStore
## pointed at user://profile.json, unchanged from before.
func _init(p_store: ProfileStore = null) -> void:
	_store = p_store if p_store != null else ProfileStore.new()
	if p_store != null:
		reload_profile()


func _ready() -> void:
	reload_profile()


func get_stars() -> int:
	return int(_profile.get("stars", 0))


## Adds (or subtracts) stars, clamped so the total never goes negative.
## Persists immediately and emits stars_changed with the new total.
func add_stars(amount: int) -> int:
	var new_total: int = get_stars() + amount
	if new_total < 0:
		new_total = 0
	_profile["stars"] = new_total
	save_profile()
	stars_changed.emit(new_total)
	profile_changed.emit(get_profile())
	return new_total


func mark_activity_completed(activity_id: String) -> void:
	if activity_id == "":
		return
	var completed: Array = _profile.get("completedActivities", [])
	if completed.has(activity_id):
		return
	completed.append(activity_id)
	_profile["completedActivities"] = completed
	save_profile()
	profile_changed.emit(get_profile())


func is_activity_completed(activity_id: String) -> bool:
	var completed: Array = _profile.get("completedActivities", [])
	return completed.has(activity_id)


## ---------------------------------------------------------------------------
## Chapter / level position
## ---------------------------------------------------------------------------

func get_current_chapter() -> String:
	return String(_profile.get("currentChapter", ""))


func set_current_chapter(chapter_id: String) -> void:
	_profile["currentChapter"] = chapter_id
	save_profile()
	profile_changed.emit(get_profile())


func get_current_level() -> String:
	return String(_profile.get("currentLevel", ""))


func set_current_level(level_id: String) -> void:
	_profile["currentLevel"] = level_id
	save_profile()
	profile_changed.emit(get_profile())


## ---------------------------------------------------------------------------
## World location (schema v4) -- WHERE IN THE HOUSE the child is, as two
## semantic ids and never a coordinate. Chapter 2 does not use this at all: the
## baby does not walk, so a Baby Room profile simply carries the bedroom
## default and ignores it.
##
## The values returned here are shape-validated only (a non-empty single
## camelCase segment). Whether `"attic"` is a room that EXISTS is a question
## about the current house layout, and is answered -- with the same
## bedroom/default fallback -- by `scripts/house/world_state.gd`. Keeping the
## two apart is what lets the save layer stay engine-agnostic.
## ---------------------------------------------------------------------------

func get_current_room_id() -> String:
	return String(_profile.get(ProfileStore.ROOM_FIELD, ProfileStore.FALLBACK_ROOM_ID))


func get_current_spawn_id() -> String:
	return String(_profile.get(ProfileStore.SPAWN_FIELD, ProfileStore.DEFAULT_SPAWN_ID))


func get_world_location() -> Dictionary:
	return {
		ProfileStore.ROOM_FIELD: get_current_room_id(),
		ProfileStore.SPAWN_FIELD: get_current_spawn_id(),
	}


## Records where the child is. Idempotent: setting the location it is already at
## writes nothing and emits nothing, so a room transition that re-fires cannot
## churn the save file.
##
## Writes BOTH the v4 top-level fields and the v3 `settings.worldState` mirror,
## because `scripts/house/world_state.gd` still reads the latter. That second
## write disappears with `ProfileStore.DROP_LEGACY_WORLD_STATE`.
func set_world_location(room_id: String, spawn_id: String) -> void:
	var room := room_id.strip_edges()
	var spawn := spawn_id.strip_edges()
	if room.is_empty():
		room = ProfileStore.FALLBACK_ROOM_ID
	if spawn.is_empty():
		spawn = ProfileStore.DEFAULT_SPAWN_ID
	if get_current_room_id() == room and get_current_spawn_id() == spawn:
		return

	_profile[ProfileStore.ROOM_FIELD] = room
	_profile[ProfileStore.SPAWN_FIELD] = spawn

	if not ProfileStore.DROP_LEGACY_WORLD_STATE:
		var settings: Dictionary = _profile.get("settings", {})
		settings[ProfileStore.LEGACY_WORLD_STATE_KEY] = {
			ProfileStore.ROOM_FIELD: room,
			ProfileStore.SPAWN_FIELD: spawn,
		}
		_profile["settings"] = settings

	save_profile()
	# Read back rather than echoing the arguments: ProfileStore may have refused
	# a malformed id, and a listener must be told where the child ACTUALLY is.
	# Deliberately not `reload_profile()`, which would also re-emit stars_changed
	# with an unchanged total and make a room transition look like a reward.
	_profile = _store.load_profile()
	world_location_changed.emit(get_current_room_id(), get_current_spawn_id())
	profile_changed.emit(get_profile())


## ---------------------------------------------------------------------------
## Per-level star rating (0..3), separate from the lifetime task "stars"
## total above. Never summed into it.
## ---------------------------------------------------------------------------

func get_level_stars(level_id: String) -> int:
	var stars_by_level: Dictionary = _profile.get("starsByLevel", {})
	return int(stars_by_level.get(level_id, 0))


## Max-wins: replaying a level with a worse result never lowers the stored
## rating. Clamped to 0..3. Persists immediately and emits
## level_stars_changed with the resulting (post-max) value.
func set_level_stars(level_id: String, stars: int) -> void:
	if level_id == "":
		return
	var clamped := clampi(stars, 0, 3)
	var stars_by_level: Dictionary = _profile.get("starsByLevel", {})
	var previous := int(stars_by_level.get(level_id, 0))
	var new_value := maxi(previous, clamped)
	if new_value == previous and stars_by_level.has(level_id):
		return
	stars_by_level[level_id] = new_value
	_profile["starsByLevel"] = stars_by_level
	save_profile()
	level_stars_changed.emit(level_id, new_value)
	profile_changed.emit(get_profile())


## Deep copy so callers cannot mutate internal state.
func get_stars_by_level() -> Dictionary:
	var stars_by_level: Dictionary = _profile.get("starsByLevel", {})
	return stars_by_level.duplicate(true)


func get_total_level_stars() -> int:
	var stars_by_level: Dictionary = _profile.get("starsByLevel", {})
	var total := 0
	for level_id in stars_by_level.keys():
		total += int(stars_by_level[level_id])
	return total


## ---------------------------------------------------------------------------
## Level completion -- deliberately parallel to the per-level rating above and
## deliberately independent of it. Completion answers "did the child reach the
## end?"; the rating answers "how well did it go?". A level can be completed
## with 0 stars, and only completion may gate progression.
## ---------------------------------------------------------------------------

func is_level_completed(level_id: String) -> bool:
	var completed: Dictionary = _profile.get("levelCompleted", {})
	return bool(completed.get(level_id, false))


## Idempotent: marking an already-completed level again writes nothing and
## emits nothing, so a replay or a re-fired signal cannot double-apply.
func mark_level_completed(level_id: String) -> void:
	if level_id == "":
		return
	var completed: Dictionary = _profile.get("levelCompleted", {})
	if bool(completed.get(level_id, false)):
		return
	completed[level_id] = true
	_profile["levelCompleted"] = completed
	save_profile()
	level_completed_changed.emit(level_id)
	profile_changed.emit(get_profile())


## Deep copy so callers cannot mutate internal state. Keys are exactly the
## levels the child has finished; there are no `false` entries.
func get_level_completed() -> Dictionary:
	var completed: Dictionary = _profile.get("levelCompleted", {})
	return completed.duplicate(true)


## ---------------------------------------------------------------------------
## Unlocks
## ---------------------------------------------------------------------------

func is_level_unlocked(level_id: String) -> bool:
	var unlocked: Array = _profile.get("unlockedLevels", [])
	return unlocked.has(level_id)


func unlock_level(level_id: String) -> void:
	if level_id == "":
		return
	var unlocked: Array = _profile.get("unlockedLevels", [])
	if unlocked.has(level_id):
		return
	unlocked.append(level_id)
	_profile["unlockedLevels"] = unlocked
	save_profile()
	profile_changed.emit(get_profile())


func is_chapter_unlocked(chapter_id: String) -> bool:
	var unlocked: Array = _profile.get("unlockedChapters", [])
	return unlocked.has(chapter_id)


func unlock_chapter(chapter_id: String) -> void:
	if chapter_id == "":
		return
	var unlocked: Array = _profile.get("unlockedChapters", [])
	if unlocked.has(chapter_id):
		return
	unlocked.append(chapter_id)
	_profile["unlockedChapters"] = unlocked
	save_profile()
	profile_changed.emit(get_profile())


func is_room_unlocked(room_id: String) -> bool:
	var unlocked: Array = _profile.get("unlockedRooms", [])
	return unlocked.has(room_id)


func unlock_room(room_id: String) -> void:
	if room_id == "":
		return
	var unlocked: Array = _profile.get("unlockedRooms", [])
	if unlocked.has(room_id):
		return
	unlocked.append(room_id)
	_profile["unlockedRooms"] = unlocked
	save_profile()
	profile_changed.emit(get_profile())


func get_setting(key: String, default_value: Variant = null) -> Variant:
	var settings: Dictionary = _profile.get("settings", {})
	if settings.has(key):
		return settings[key]
	return default_value


func set_setting(key: String, value: Variant) -> void:
	var settings: Dictionary = _profile.get("settings", {})
	settings[key] = value
	_profile["settings"] = settings
	save_profile()
	profile_changed.emit(get_profile())


func save_profile() -> bool:
	return _store.save_profile(_profile)


func reload_profile() -> void:
	_profile = _store.load_profile()
	profile_changed.emit(get_profile())
	stars_changed.emit(get_stars())


func reset_profile() -> void:
	_profile = _store.default_profile()
	save_profile()
	profile_changed.emit(get_profile())
	stars_changed.emit(get_stars())


## Returns a deep copy so callers cannot mutate internal state.
func get_profile() -> Dictionary:
	return _profile.duplicate(true)


func _notification(what: int) -> void:
	# Save whenever the app is closed or backgrounded (important on iOS,
	# where the app is paused rather than quit). Constants are checked by
	# value rather than relied upon to exist at compile time in unusual
	# export contexts, so this stays defensive across platforms.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_profile()
