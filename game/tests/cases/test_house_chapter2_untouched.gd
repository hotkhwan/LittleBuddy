extends RefCounted

## The product decision, as a test: **the baby does not walk.**
##
## | Chapter | Stage | Interaction model | Locomotion |
## |---|---|---|---|
## | 1 | Prologue | story / light interaction | none |
## | 2 | Baby Days | caregiver: tap, drag, give, feed, bath, dress, sleep | **none** |
## | 3+ | Toddler and older | tap-to-walk, activity targets, rooms | core |
##
## Chapter 2 is finished, shipped and playable. The single most likely way Phase
## 2B could damage this game is by "helpfully" giving the baby a `CharacterBody3D`
## and a `NavigationAgent3D` -- which would add a state machine, a navigation map
## and a whole class of stuck-character bugs to gameplay that needs none of them.
##
## So: the Baby Room and the baby's own scripts must contain **zero** locomotion,
## and the house must not reach into the Baby Room either. Two directions, one
## rule: Chapter 2 and Chapter 3 share a character API, not a world.
##
## `run()` is untyped on purpose.

## Chapter 2's files. Nothing here may acquire navigation.
const CHAPTER2_DIRS: Array[String] = ["res://scenes/baby_room", "res://scripts/baby"]

const FORBIDDEN_IN_CHAPTER2: Array[String] = [
	"CharacterBody3D",
	"NavigationAgent3D",
	"NavigationRegion3D",
	"NavigationMesh",
	"NavigationServer3D",
	"navigation_controller",
	"little_buddy_character",
	"activity_target",
	"scripts/house/",
	"move_to_ground",
]

## The house's own files. None of them may reach into Chapter 2.
const HOUSE_DIRS: Array[String] = ["res://scripts/house", "res://scenes/house"]
const FORBIDDEN_IN_HOUSE: Array[String] = [
	"scenes/baby_room", "scripts/baby/", "BabyState", "baby_view_3d",
	"mission_runner", "RewardManager", "SpeechService",
]

## Chapter 2's interaction model, which must still be there afterwards: the milk
## bottle and the teddy are `DraggableObject`s and the room still runs drop zones.
const BABY_ROOM_SCENE: String = "res://scenes/baby_room/baby_room.tscn"
const BABY_ROOM_SCRIPT: String = "res://scenes/baby_room/baby_room.gd"
const REQUIRED_IN_BABY_ROOM: Array[String] = ["milk_bottle.gd", "teddy.gd", "baby_view_3d.gd"]
const REQUIRED_IN_BABY_ROOM_SCRIPT: Array[String] = ["_drop_zone", "dragToMouth"]


func test_name() -> String:
	return "house_chapter2_untouched"


func run():
	var failures: Array = []
	failures.append_array(_test_chapter2_has_no_locomotion())
	failures.append_array(_test_house_does_not_reach_into_chapter2())
	failures.append_array(_test_baby_room_still_has_its_interaction_model())
	failures.append_array(_test_the_character_api_is_shared_not_forked())
	return failures


func _test_chapter2_has_no_locomotion() -> Array:
	var failures: Array = []
	var scanned: int = 0
	for directory: String in CHAPTER2_DIRS:
		for path: String in _files_under(directory):
			scanned += 1
			var source: String = _read(path)
			for forbidden: String in FORBIDDEN_IN_CHAPTER2:
				if source.contains(forbidden):
					failures.append("%s references '%s'. The baby does not walk: Chapter 2 is "
							% [path, forbidden] + "tap/drag caregiving and must acquire no "
							+ "navigation.")
	if scanned < 6:
		failures.append("only %d Chapter 2 files were scanned; the guard is not looking at "
				% scanned + "anything and would never fail")
	return failures


func _test_house_does_not_reach_into_chapter2() -> Array:
	var failures: Array = []
	var scanned: int = 0
	for directory: String in HOUSE_DIRS:
		for path: String in _files_under(directory):
			scanned += 1
			var source: String = _read(path)
			for forbidden: String in FORBIDDEN_IN_HOUSE:
				if source.contains(forbidden):
					failures.append("%s references '%s'; HouseWorld is Chapter 3+ and must not "
							% [path, forbidden] + "depend on Chapter 2")
	if scanned < 5:
		failures.append("only %d house files were scanned; the guard is not looking at anything"
				% scanned)
	return failures


## The positive half: Chapter 2 still has the interaction model it shipped with.
## A guard that only forbids things would pass on an empty directory.
func _test_baby_room_still_has_its_interaction_model() -> Array:
	var failures: Array = []
	var text: String = _read(BABY_ROOM_SCENE)
	if text.is_empty():
		return ["the Baby Room scene is missing"]
	for required: String in REQUIRED_IN_BABY_ROOM:
		if not text.contains(required):
			failures.append("the Baby Room scene no longer uses %s; its tap/drag caregiving "
					% required + "gameplay has been changed")
	var script_source: String = _read(BABY_ROOM_SCRIPT)
	for required: String in REQUIRED_IN_BABY_ROOM_SCRIPT:
		if not script_source.contains(required):
			failures.append("baby_room.gd no longer mentions '%s'; its drag-and-drop gameplay "
					% required + "has been changed")
	var packed: Resource = load(BABY_ROOM_SCENE)
	if packed == null or not (packed is PackedScene):
		failures.append("the Baby Room scene no longer loads")
	return failures


## Chapter 2 and Chapter 3 share ONE character script. The toddler placeholder is
## a view, not a second movement implementation -- a fork would be two state
## machines to keep in step and is exactly what the contract forbids.
func _test_the_character_api_is_shared_not_forked() -> Array:
	var failures: Array = []
	var house_scene: String = _read("res://scenes/house/house_world.tscn")
	if not house_scene.contains("scripts/character/little_buddy_character.gd"):
		failures.append("the house does not use little_buddy_character.gd; the movement API "
				+ "proven by the spike was forked")
	var toddler: String = _read("res://scripts/character/toddler_view.gd")
	if toddler.is_empty():
		return failures + ["the toddler placeholder is missing"]
	for forbidden: String in ["CharacterBody3D", "NavigationAgent3D", "move_and_slide"]:
		if toddler.contains(forbidden):
			failures.append("toddler_view.gd contains '%s'; it is placeholder ART and must not "
					% forbidden + "re-implement movement")
	# And it must say, loudly, that it is temporary.
	if not toddler.to_upper().contains("TEMPORARY"):
		failures.append("the toddler placeholder does not declare itself temporary; the real "
				+ "model comes from the art pipeline and this must not quietly become the game")
	return failures


## -- Helpers -------------------------------------------------------------------

func _files_under(directory: String) -> Array:
	var paths: Array = []
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return paths
	for file_name: String in dir.get_files():
		var name: String = file_name.trim_suffix(".remap")
		if name.ends_with(".gd") or name.ends_with(".tscn"):
			paths.append("%s/%s" % [directory, name])
	for sub_dir: String in dir.get_directories():
		paths.append_array(_files_under("%s/%s" % [directory, sub_dir]))
	paths.sort()
	return paths


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
