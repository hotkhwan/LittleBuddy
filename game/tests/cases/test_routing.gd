extends RefCounted

## The main menu, and the one decision it makes: WHICH WORLD a child enters.
##
## HouseWorld was unreachable from the game until this existed -- `main.gd` only
## ever loaded `baby_room.tscn` -- so the assertions here are the difference
## between a house that is built and a house that is played. Contract §5.
##
## The property being protected is "no dead ends" (contract §6). A four-year-old
## presses a big button; something must happen, always, whatever the save file
## says. So every fallback is asserted, not intended:
##
##   * an unknown, empty or future chapter -> a playable world;
##   * `"ch1"` -- what a BRAND NEW profile carries -- -> a playable world;
##   * a route whose scene is missing -> the other world;
##   * Free Play with no house -> the Baby Room's own Free Play.
##
## And the gap that makes routing necessary at all:
## `baby_room.gd::_pick_story_mission_id()` walks the authored level order across
## every chapter, so after `firstWords` it hands the Chapter 3 mission to the
## Baby Room, which has no locomotion and cannot play it. `ch3` must therefore
## resolve to the house BEFORE any scene is loaded, and `_test_chapter_routes()`
## says so in as many words.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const MainScript := preload("res://scenes/main/main.gd")
const LevelSystemScript := preload("res://scripts/progression/level_system.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")

const MENU_SCENE: String = "res://scenes/main/main.tscn"

## Landscape safe-area sizes in the project's 1366x1024 design space, matching
## `test_ui_chrome.gd` so both files describe the same two device shapes.
const SAFE_AREA_PHONE: Vector2 = Vector2(2170.0, 992.0)
const SAFE_AREA_TABLET: Vector2 = Vector2(1425.0, 992.0)

## The brief's floor for a menu button at the 1366x1024 reference.
const MIN_MENU_BUTTON_SIDE: float = 240.0

## Contract §7. `#000000` is banned everywhere and red is banned as a UI colour,
## so a menu colour must be neither.
const BANNED_COLOURS: Dictionary = {
	"pure black": Color(0.0, 0.0, 0.0, 1.0),
}

## A colour reads as "red" when its red channel dominates both others by this
## much. Deliberately generous -- peach and soft pink are red-ish and must pass.
const RED_DOMINANCE: float = 0.30

const MENU_CONTROLS: Array[String] = [
	"UI/SafeArea/TitlePanel",
	"UI/SafeArea/PlayButton",
	"UI/SafeArea/FreePlayButton",
]


func test_name() -> String:
	return "routing"


func run():
	var failures: Array = []
	failures.append_array(_test_chapter_routes())
	failures.append_array(_test_no_route_is_a_dead_end())
	failures.append_array(_test_free_play_route())
	failures.append_array(_test_chapter_is_recomputed_when_the_pointer_is_stale())
	failures.append_array(_test_scene_hand_off_configures_the_world())
	failures.append_array(_test_play_with_bunny_never_routes_to_the_baby_room())
	failures.append_array(_test_menu_is_child_facing())
	return failures


## -- The routing table ---------------------------------------------------------

func _test_chapter_routes():
	var failures: Array = []

	# The decision this whole file exists for.
	if MainScript.route_for_chapter("ch3") != MainScript.Route.HOUSE_WORLD:
		failures.append(
			"Chapter 3 must route to HouseWorld. It is the toddler chapter and walking is its "
			+ "core mechanic; the Baby Room has no locomotion (test_architecture_guard.gd pins "
			+ "that) and cannot play a single Chapter 3 level."
		)
	if MainScript.route_for_chapter("ch2") != MainScript.Route.BABY_ROOM:
		failures.append("Chapter 2 must route to the Baby Room; the baby does not walk")

	# `ch1` is what ProfileStore.default_profile() writes, so EVERY new player
	# starts here. The Prologue does not exist, so it must land somewhere real.
	if MainScript.route_for_chapter("ch1") != MainScript.Route.BABY_ROOM:
		failures.append(
			"a brand new profile carries currentChapter 'ch1' and the Prologue is not built; "
			+ "it must still route to a playable world"
		)

	# Unknown, empty, padded and wrongly-cased ids.
	for unknown: String in ["", "   ", "ch9", "banana", "CH3", "3"]:
		if MainScript.route_for_chapter(unknown) != MainScript.FALLBACK_ROUTE:
			failures.append("chapter '%s' should fall back to the default route, got %d"
					% [unknown, MainScript.route_for_chapter(unknown)])

	# Whitespace is forgiven rather than treated as a different chapter.
	if MainScript.route_for_chapter("  ch3  ") != MainScript.Route.HOUSE_WORLD:
		failures.append("a padded chapter id should still route to the house")

	# The table must cover the two shipped chapters, or it is decoration.
	for chapter_id: String in ["ch2", "ch3"]:
		if not MainScript.CHAPTER_ROUTES.has(chapter_id):
			failures.append("the routing table no longer mentions '%s'" % chapter_id)

	return failures


## Every route must name a scene that is actually on disk.
func _test_no_route_is_a_dead_end():
	var failures: Array = []

	for chapter_id: String in ["ch1", "ch2", "ch3", "", "ch9", "banana"]:
		var path: String = MainScript.story_scene_path(chapter_id)
		if path.is_empty():
			failures.append("chapter '%s' resolved to no scene at all; a child pressed Play and "
					% chapter_id + "nothing can happen")
			continue
		if not ResourceLoader.exists(path):
			failures.append("chapter '%s' resolved to '%s', which is not in the build"
					% [chapter_id, path])

	# And the two routes really do lead to the two different worlds.
	if MainScript.story_scene_path("ch2") == MainScript.story_scene_path("ch3"):
		failures.append(
			"Story Mode sends Chapter 2 and Chapter 3 to the same scene ('%s'). One of the two "
			% MainScript.story_scene_path("ch2")
			+ "worlds is then unreachable, which is the exact gap this routing closes."
		)
	if MainScript.story_scene_path("ch3") != MainScript.HOUSE_WORLD_PATH:
		failures.append("Chapter 3 opens '%s', expected the house"
				% MainScript.story_scene_path("ch3"))
	if MainScript.story_scene_path("ch2") != MainScript.BABY_ROOM_PATH:
		failures.append("Chapter 2 opens '%s', expected the baby room"
				% MainScript.story_scene_path("ch2"))

	return failures


func _test_free_play_route():
	var failures: Array = []

	var path: String = MainScript.free_play_scene_path()
	if path.is_empty():
		return ["Free Play resolves to no scene at all"]
	if not ResourceLoader.exists(path):
		failures.append("Free Play opens '%s', which is not in the build" % path)
	if path != MainScript.HOUSE_WORLD_PATH:
		failures.append(
			"Free Play opens '%s', expected the house. Contract §5: Free Play is the four "
			% path + "unlocked rooms with no objective."
		)
	if MainScript.FREE_PLAY_ROUTE != MainScript.Route.HOUSE_WORLD:
		failures.append("the Free Play route no longer points at the house")

	# The menu must actually offer it -- a route nothing can reach is not a route.
	var menu: Node = _instantiate_menu()
	if menu == null:
		return failures + ["could not instantiate %s" % MENU_SCENE]
	var button: Node = menu.get_node_or_null(NodePath("UI/SafeArea/FreePlayButton"))
	if button == null or not (button is Button):
		failures.append(
			"the menu has no FreePlayButton. Free Play is one of the two entry points in "
			+ "contract §5; without a button it does not exist."
		)
	menu.free()
	return failures


## -- The resume pointer --------------------------------------------------------

## `currentChapter` is written once, as `"ch1"`, and nothing in the game moves
## it. Trusting it blindly would leave Chapter 3 permanently unreachable however
## much of Chapter 2 a child finished, so the menu recomputes it from
## `levelCompleted` whenever the saved value is finished or unreachable.
func _test_chapter_is_recomputed_when_the_pointer_is_stale():
	var failures: Array = []

	var system: RefCounted = LevelSystemScript.create(ContentLibraryScript.create())
	if system == null:
		return ["could not build a LevelSystem"]

	var ch2_levels: PackedStringArray = system.call("get_chapter_chain", "ch2")
	var ch3_levels: PackedStringArray = system.call("get_chapter_chain", "ch3")
	if ch2_levels.is_empty() or ch3_levels.is_empty():
		return ["chapters.json no longer chains ch2 and ch3; the routing test is vacuous"]

	# A brand new profile: nothing finished, pointer still on the unbuilt Prologue.
	if MainScript.pick_chapter_id(system, {}, "ch1") != "ch2":
		failures.append("a fresh profile should start in Chapter 2, got '%s'"
				% MainScript.pick_chapter_id(system, {}, "ch1"))

	# Mid-Chapter-2: the saved pointer is honoured.
	var partial: Dictionary = {String(ch2_levels[0]): true}
	if MainScript.pick_chapter_id(system, partial, "ch2") != "ch2":
		failures.append("a half-finished Chapter 2 should stay in Chapter 2")

	# Chapter 2 finished: Chapter 3 unlocks and the pointer moves, which is the
	# only way the house is ever reached in Story Mode.
	var ch2_done: Dictionary = {}
	for level_id: String in ch2_levels:
		ch2_done[level_id] = true
	if MainScript.pick_chapter_id(system, ch2_done, "ch2") != "ch3":
		failures.append(
			"finishing Chapter 2 must move the child on to Chapter 3, got '%s'. Otherwise the "
			% MainScript.pick_chapter_id(system, ch2_done, "ch2")
			+ "house is unreachable no matter how much of the game is played."
		)
	if MainScript.route_for_chapter(MainScript.pick_chapter_id(system, ch2_done, "ch2")) \
			!= MainScript.Route.HOUSE_WORLD:
		failures.append("a child who finished Chapter 2 is not sent to the house")

	# A pointer running ahead of the unlocks is pulled back rather than obeyed.
	if MainScript.pick_chapter_id(system, {}, "ch3") != "ch2":
		failures.append("a saved chapter that is not unlocked yet should fall back to the "
				+ "first unlocked one")

	# The whole journey finished: replay the newest world, never nothing.
	var all_done: Dictionary = ch2_done.duplicate()
	for level_id: String in ch3_levels:
		all_done[level_id] = true
	var finished: String = MainScript.pick_chapter_id(system, all_done, "ch3")
	if finished.is_empty():
		failures.append("a completed journey resolved to no chapter at all")
	elif not ResourceLoader.exists(MainScript.story_scene_path(finished)):
		failures.append("a completed journey resolved to an unloadable scene")

	# No level system at all -> "", which the caller reads as "keep the saved id".
	if not String(MainScript.pick_chapter_id(null, {}, "ch2")).is_empty():
		failures.append("pick_chapter_id() with no system should return an empty string")

	return failures


## -- The hand-off --------------------------------------------------------------

## `change_scene_to_file()` cannot configure a world before `_ready()` runs, and
## both worlds decide what to play there. So the menu instantiates, configures,
## and only then adds -- and that is asserted here without a tree.
func _test_scene_hand_off_configures_the_world():
	var failures: Array = []

	var house: Node = MainScript.build_scene(
		MainScript.HOUSE_WORLD_PATH, MainScript.ProgressionMode.FREE_PLAY, [], null
	)
	if house == null:
		failures.append("the house did not build")
	else:
		if int(house.call("get_progression_mode")) != MainScript.ProgressionMode.FREE_PLAY:
			failures.append("Free Play did not reach the house; it came up in mode %d"
					% int(house.call("get_progression_mode")))
		if not bool(house.call("is_free_play")):
			failures.append("the house does not report itself as Free Play")
		house.free()

	var story_house: Node = MainScript.build_scene(
		MainScript.HOUSE_WORLD_PATH, MainScript.ProgressionMode.STORY, [], null
	)
	if story_house == null:
		failures.append("the house did not build in Story Mode")
	else:
		if bool(story_house.call("is_free_play")):
			failures.append("Story Mode reached the house as Free Play")
		story_house.free()

	# The Baby Room speaks the same two words, which is why `main.gd` reuses
	# `ProgressionMode` rather than inventing a second vocabulary.
	var room: Node = MainScript.build_scene(
		MainScript.BABY_ROOM_PATH, MainScript.ProgressionMode.FREE_PLAY, [], null
	)
	if room == null:
		failures.append("the baby room did not build")
	else:
		if int(room.call("get_progression_mode")) != MainScript.ProgressionMode.FREE_PLAY:
			failures.append("Free Play did not reach the baby room")
		if MainScript.ProgressionMode.STORY != 0 or MainScript.ProgressionMode.FREE_PLAY != 1:
			failures.append("main.gd's ProgressionMode ordinals no longer match baby_room.gd's; "
					+ "one value is passed straight to either world and must mean the same thing")
		room.free()

	# A missing scene is null, not a crash and not a half-built world.
	for missing: String in ["", "res://scenes/does_not_exist.tscn"]:
		var nothing: Node = MainScript.build_scene(missing, MainScript.ProgressionMode.STORY)
		if nothing != null:
			failures.append("build_scene('%s') returned a node" % missing)
			nothing.free()

	return failures


## Play with Bunny (2026-09-21). The button promises the house; its route has
## no Baby Room fallback, unlike Story's chapter routing, and the mission the
## child picked reaches the house through `build_scene()`.
func _test_play_with_bunny_never_routes_to_the_baby_room():
	var failures: Array = []
	var path: String = MainScript.bunny_scene_path()
	if path == MainScript.BABY_ROOM_PATH:
		failures.append("bunny_scene_path() is the Baby Room; Play with Bunny must never open it")
	if path != MainScript.HOUSE_WORLD_PATH:
		failures.append("bunny_scene_path() is '%s'; with the house in the build it is the house" % path)
	if MainScript.CHAPTER_ROUTES.get("ch2", -1) != MainScript.Route.BABY_ROOM:
		failures.append("Chapter 2 is no longer the Baby Room; the chapter table is documentation and must stay true")

	var house: Node = MainScript.build_scene(
		MainScript.HOUSE_WORLD_PATH, MainScript.ProgressionMode.STORY, [], null, "imHungry"
	)
	if house == null:
		failures.append("the house did not build with a requested mission")
	else:
		if String(house.call("get_requested_mission_id")) != "imHungry":
			failures.append("build_scene(..., 'imHungry') left the house with request '%s'"
					% String(house.call("get_requested_mission_id")))
		if bool(house.call("is_free_play")):
			failures.append("a requested mission came up as Free Play")
		house.free()
	var plain: Node = MainScript.build_scene(
		MainScript.HOUSE_WORLD_PATH, MainScript.ProgressionMode.STORY, [], null
	)
	if plain != null:
		if String(plain.call("get_requested_mission_id")) != "":
			failures.append("build_scene() with no mission still requested '%s'"
					% String(plain.call("get_requested_mission_id")))
		plain.free()
	# The Baby Room answers no such method and must still build -- duck typing.
	var room: Node = MainScript.build_scene(
		MainScript.BABY_ROOM_PATH, MainScript.ProgressionMode.STORY, [], null, "imHungry"
	)
	if room == null:
		failures.append("the Baby Room did not build when a mission id was passed")
	else:
		room.free()
	return failures


## -- The menu itself -----------------------------------------------------------

func _test_menu_is_child_facing():
	var failures: Array = []

	var menu: Node = _instantiate_menu()
	if menu == null:
		return ["could not instantiate %s" % MENU_SCENE]

	# Two entry points, both reachable, both big enough for a small finger.
	for button_path: String in ["UI/SafeArea/PlayButton", "UI/SafeArea/FreePlayButton"]:
		var button: Control = menu.get_node_or_null(NodePath(button_path)) as Control
		if button == null:
			failures.append("the menu has no %s" % button_path)
			continue
		if not (button is Button):
			failures.append("%s is not a Button" % button_path)
		var rect: Rect2 = _stored_rect(button, SAFE_AREA_TABLET)
		if rect.size.x < MIN_MENU_BUTTON_SIDE or rect.size.y < MIN_MENU_BUTTON_SIDE:
			failures.append("%s is %s; a menu button needs at least %.0f square at the 1366x1024 "
					% [button_path, str(rect.size), MIN_MENU_BUTTON_SIDE]
					+ "reference")
		# A pre-reader navigates by picture, so each button must carry one.
		var has_icon: bool = false
		for child: Node in button.get_children():
			if child is Control and child is not Label:
				has_icon = true
		if not has_icon:
			failures.append("%s has no icon; the player cannot read the caption" % button_path)

	# Nothing overlaps and nothing leaves the safe area, at either device shape.
	for area: Vector2 in [SAFE_AREA_PHONE, SAFE_AREA_TABLET]:
		var rects: Dictionary = {}
		for node_path: String in MENU_CONTROLS:
			var control: Control = menu.get_node_or_null(NodePath(node_path)) as Control
			if control == null:
				failures.append("the menu has no %s" % node_path)
				continue
			rects[node_path] = _stored_rect(control, area)
		var names: Array = rects.keys()
		for i: int in range(names.size()):
			var rect: Rect2 = rects[names[i]]
			if not Rect2(Vector2.ZERO, area).encloses(rect):
				failures.append("at %s, %s (%s) is outside the safe area"
						% [str(area), String(names[i]), str(rect)])
			for j: int in range(i + 1, names.size()):
				if rect.intersects(rects[names[j]]):
					failures.append("at %s, %s overlaps %s"
							% [str(area), String(names[i]), String(names[j])])

	failures.append_array(_check_palette(menu))
	failures.append_array(_check_no_debug_controls(menu))

	menu.free()
	return failures


## Contract §7: `#000000` is banned everywhere and red is banned as a UI colour.
func _check_palette(root: Node):
	var failures: Array = []
	var checked: int = 0
	for entry: Dictionary in _colours_of(root):
		var colour: Color = entry["colour"]
		checked += 1
		for label: Variant in BANNED_COLOURS.keys():
			if colour.is_equal_approx(BANNED_COLOURS[label]):
				failures.append("%s uses %s (%s); it is banned by the locked palette"
						% [String(entry["where"]), String(label), str(colour)])
		if colour.a > 0.0 and colour.r - colour.g > RED_DOMINANCE \
				and colour.r - colour.b > RED_DOMINANCE:
			failures.append("%s uses %s, which reads as red; red is banned as a UI colour "
					% [String(entry["where"]), str(colour)]
					+ "(it is the colour of a mistake, and this game never shows one)")
	if checked < 4:
		failures.append("the palette scan found only %d colour(s); it is vacuous" % checked)
	return failures


## A child-facing title screen carries no developer affordances.
func _check_no_debug_controls(root: Node):
	var failures: Array = []
	for node: Node in _walk(root):
		# `String(null)` is not a valid Godot 4 constructor and aborts the case,
		# so the type is checked rather than coerced.
		var raw: Variant = node.get("text")
		if typeof(raw) != TYPE_STRING:
			continue
		var text: String = raw
		for banned: String in ["debug", "reset", "dev", "console", "test", "cheat"]:
			if text.to_lower().contains(banned):
				failures.append("the menu shows '%s' on %s; a title screen a child sees carries "
						% [text, node.name] + "no debug controls")
	return failures


## -- Helpers -------------------------------------------------------------------

func _instantiate_menu() -> Node:
	if not ResourceLoader.exists(MENU_SCENE):
		return null
	var packed: Resource = load(MENU_SCENE)
	if not (packed is PackedScene) or not (packed as PackedScene).can_instantiate():
		return null
	# Never added to the tree: only the stored geometry and colours are needed,
	# and `_ready()` would want a viewport.
	return (packed as PackedScene).instantiate()


## Every authored colour in the scene, with the node it came from.
func _colours_of(root: Node) -> Array:
	var found: Array = []
	for node: Node in _walk(root):
		for property: Dictionary in node.get_property_list():
			var name: String = String(property.get("name", ""))
			if int(property.get("type", TYPE_NIL)) != TYPE_COLOR:
				continue
			if not (name.begins_with("theme_override_colors/") or name == "tint"
					or name == "face_color" or name == "color"):
				continue
			var value: Variant = node.get(name)
			if typeof(value) != TYPE_COLOR:
				continue
			found.append({"colour": value as Color, "where": "%s.%s" % [node.name, name]})
	return found


func _walk(node: Node) -> Array:
	var nodes: Array = [node]
	for child: Node in node.get_children():
		nodes.append_array(_walk(child))
	return nodes


## Geometry from the stored anchors and offsets, so no layout pass, no viewport
## and no autoload is needed. Same helper as `test_ui_chrome.gd`.
static func _stored_rect(control: Control, parent_size: Vector2) -> Rect2:
	var left: float = control.anchor_left * parent_size.x + control.offset_left
	var top: float = control.anchor_top * parent_size.y + control.offset_top
	var right: float = control.anchor_right * parent_size.x + control.offset_right
	var bottom: float = control.anchor_bottom * parent_size.y + control.offset_bottom
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))
