extends RefCounted

## Story Mode: how the Baby Room chooses what the child plays next.
##
## Before this, mission mode picked RANDOMLY among whatever the legacy
## `unlockAtStars` listing happened to unlock, deliberately avoiding an immediate
## repeat. Story Mode replaces that choice with the authored level order from
## `LevelSystem`, gated on level COMPLETION rather than on any star count:
##
##   1. resume the saved `currentLevel`, if it is unlocked and playable;
##   2. otherwise the first incomplete unlocked level, in authored order;
##   3. otherwise the first unlocked level (the journey is finished).
##
## The random picker is deliberately still there, unchanged, as Free Play's
## picker and as Story Mode's safety net -- so this file also pins down that it
## still exists and still behaves randomly.
##
## The room is instantiated but never added to the tree (its `_ready()` loads
## content and starts a mission, which needs the full autoload set). A tiny
## subclass supplies the saved-level seam that would normally come from the
## `SaveService` autoload.

const BABY_ROOM_SCRIPT: String = "res://scenes/baby_room/baby_room.gd"

const LevelSystemScript := preload("res://scripts/progression/level_system.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")

## The authored Chapter 2 order: [levelId, missionId].
const CHAPTER_2: Array = [
	["milkTime", "feedingTime"],
	["bathTime", "bathTime"],
	["bedtime", "bedtimeRoutine"],
	["toysAndSmiles", "playTime"],
	["firstWords", "colorsAndShapes"],
]


class StubSaveService extends RefCounted:
	var level_completed: Dictionary = {}

	func get_level_completed() -> Dictionary:
		return level_completed.duplicate(true)

	func get_stars_by_level() -> Dictionary:
		return {}


## The room, with the two `SaveService` touch points stubbed. Everything else --
## the picker, the level system, the playability check -- is the real code.
class StoryRoom extends "res://scenes/baby_room/baby_room.gd":
	var saved_level: String = ""
	var remembered: Array = []

	func _saved_current_level() -> String:
		return saved_level

	func _remember_current_level(level_id: String) -> void:
		remembered.append(level_id)


var _library: RefCounted = null


func test_name() -> String:
	return "progression_story"


func run():
	var failures: Array = []

	_library = ContentLibraryScript.create()
	if _library == null:
		return ["could not load the content library"]

	failures.append_array(_test_starts_at_the_first_level())
	failures.append_array(_test_follows_the_authored_order())
	failures.append_array(_test_ignores_the_legacy_star_gate())
	failures.append_array(_test_resumes_the_saved_level())
	failures.append_array(_test_never_resumes_into_a_locked_level())
	failures.append_array(_test_finished_journey_still_has_something_to_play())
	failures.append_array(_test_free_play_picker_is_preserved())
	failures.append_array(_test_mode_switch_is_explicit())

	return failures


# ---------------------------------------------------------------------------
# Authored order
# ---------------------------------------------------------------------------

func _test_starts_at_the_first_level() -> Array:
	var failures: Array = []
	var room: Node = _room({})

	# Deterministic, unlike the random picker it replaces: the same state must
	# give the same answer every time, or "continue the story" means nothing.
	var seen: Dictionary = {}
	for _i: int in range(20):
		seen[String(room.call("_pick_story_mission_id"))] = true
	if seen.keys() != ["feedingTime"]:
		failures.append(
			"a fresh profile must start at the first authored level ('milkTime' -> mission "
			+ "'feedingTime') every single time, got %s" % str(seen.keys())
		)

	if not bool(room.call("_has_playable_mission")):
		failures.append("a fresh profile must have a playable story mission")

	room.free()
	return failures


func _test_follows_the_authored_order() -> Array:
	var failures: Array = []

	var completed: Dictionary = {}
	for i: int in range(CHAPTER_2.size()):
		var room: Node = _room(completed)
		var expected: String = String(CHAPTER_2[i][1])
		var picked: String = String(room.call("_pick_story_mission_id"))
		if picked != expected:
			failures.append("after %d completed level(s) story mode should play '%s', got '%s'"
					% [i, expected, picked])
		room.free()
		completed[String(CHAPTER_2[i][0])] = true

	return failures


## `bathTime` carries the legacy `unlockAtStars: 10`, and a child who finished
## `milkTime` by skipping every task has 0 task stars. Story Mode must still hand
## them Bath Time: authored levels gate on completion, never on a star count.
func _test_ignores_the_legacy_star_gate() -> Array:
	var failures: Array = []
	var room: Node = _room({"milkTime": true})

	var picked: String = String(room.call("_pick_story_mission_id"))
	if picked != "bathTime":
		failures.append(
			"finishing 'milkTime' with no task stars must still open 'bathTime'; story mode "
			+ "picked '%s' instead" % picked
		)

	# The legacy listing really would have hidden it, so the assertion above is
	# doing work rather than restating a default.
	if room.call("_all_playable_mission_ids").has("bathTime"):
		failures.append("the legacy unlockAtStars listing was expected to still hide 'bathTime' at 0 task stars")

	room.free()
	return failures


# ---------------------------------------------------------------------------
# Resume
# ---------------------------------------------------------------------------

func _test_resumes_the_saved_level() -> Array:
	var failures: Array = []

	var completed: Dictionary = {"milkTime": true, "bathTime": true, "bedtime": true}
	var room: Node = _room(completed)
	# `bathTime` is already finished, so "first incomplete" would say
	# 'toysAndSmiles'. The saved pointer wins: a child comes back to where they
	# left off.
	room.set("saved_level", "bathTime")
	var picked: String = String(room.call("_pick_story_mission_id"))
	if picked != "bathTime":
		failures.append("story mode should resume the saved level 'bathTime', got '%s'" % picked)
	room.free()

	# With no saved level it falls through to the first incomplete unlocked one.
	var fresh_room: Node = _room(completed)
	if String(fresh_room.call("_pick_story_mission_id")) != "playTime":
		failures.append("without a saved level story mode should play the first incomplete level "
				+ "('toysAndSmiles' -> 'playTime'), got '%s'"
				% String(fresh_room.call("_pick_story_mission_id")))
	fresh_room.free()

	return failures


## A saved pointer at a level the child has not unlocked (a hand-edited profile,
## or content re-ordered under them) must not be honoured, and must not strand
## them either.
func _test_never_resumes_into_a_locked_level() -> Array:
	var failures: Array = []
	var room: Node = _room({})
	room.set("saved_level", "firstWords")

	var picked: String = String(room.call("_pick_story_mission_id"))
	if picked != "feedingTime":
		failures.append("a locked saved level must fall back to the first playable one, got '%s'" % picked)

	room.set("saved_level", "noSuchLevel")
	if String(room.call("_pick_story_mission_id")) != "feedingTime":
		failures.append("an unknown saved level must fall back to the first playable one")

	room.free()
	return failures


## The end of the authored journey is not a dead end: there is always something
## to play.
func _test_finished_journey_still_has_something_to_play() -> Array:
	var failures: Array = []

	var completed: Dictionary = {}
	for row: Array in CHAPTER_2:
		completed[String(row[0])] = true
	completed["gettingDressed"] = true
	completed["sayItChallenge"] = true

	var room: Node = _room(completed)
	var picked: String = String(room.call("_pick_story_mission_id"))
	if picked.is_empty():
		failures.append("a child who finished every level must still be given something to play")
	elif int(room.call("_playable_task_count", picked)) <= 0:
		failures.append("story mode offered '%s', which has nothing playable in it" % picked)

	room.free()
	return failures


# ---------------------------------------------------------------------------
# Free Play
# ---------------------------------------------------------------------------

## The random picker must survive untouched, because Free Play will use it and
## because Story Mode falls back to it when the authored order yields nothing.
func _test_free_play_picker_is_preserved() -> Array:
	var failures: Array = []
	var room: Node = _room({})

	var seen: Dictionary = {}
	for _i: int in range(60):
		var picked: String = String(room.call("_pick_mission_id"))
		if picked.is_empty():
			failures.append("the free play picker returned nothing")
			break
		seen[picked] = true

	if seen.size() < 2:
		failures.append("the free play picker is no longer random; it only ever returned %s"
				% str(seen.keys()))

	room.free()
	return failures


func _test_mode_switch_is_explicit() -> Array:
	var failures: Array = []
	var room: Node = _room({})

	if int(room.call("get_progression_mode")) != room.get("ProgressionMode").get("STORY"):
		failures.append("the room must default to Story Mode")

	room.call("set_progression_mode", room.get("ProgressionMode").get("FREE_PLAY"))
	if int(room.call("get_progression_mode")) == room.get("ProgressionMode").get("STORY"):
		failures.append("set_progression_mode did not switch the room out of Story Mode")
	room.free()

	# ...and the picker really is chosen by that flag rather than by accident.
	var source: String = _read(BABY_ROOM_SCRIPT)
	if not source.contains("elif _progression_mode == ProgressionMode.STORY:"):
		failures.append("mission selection no longer branches on the progression mode")
	if not source.contains("mission_id = _pick_story_mission_id()"):
		failures.append("story mode no longer picks by authored order")

	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## A room wired to the real content library and a level system whose completion
## map is `completed`. Never added to the tree.
func _room(completed: Dictionary) -> Node:
	var system: RefCounted = LevelSystemScript.create(_library)
	var save: StubSaveService = StubSaveService.new()
	save.level_completed = completed.duplicate(true)
	system.set_save_service(save)

	var room: Node = StoryRoom.new()
	room.set("_library", _library)
	room.set("_level_system", system)
	return room


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
