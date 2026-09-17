extends Node3D

## The title screen, and the only place in the game that decides WHICH WORLD a
## child is about to play in.
##
## ```
## Main menu
## ├── Play (Story) → ch2 → baby_room.tscn    (caregiver, no locomotion)
## │                → ch3 → house_world.tscn  (toddler, locomotion)
## └── Free Play    → house_world.tscn, unlocked rooms, no objective
## ```
##
## ## Why the route is decided here and nowhere else
##
## The two worlds are not two skins of one scene: Chapter 2 is a caregiver
## chapter where the baby does not walk, and Chapter 3 is a toddler chapter where
## walking is the core mechanic. `test_architecture_guard.gd` pins that apart at
## the source level -- the Baby Room may never acquire a navigation agent -- so
## the *only* way a child reaches Chapter 3 gameplay is by being sent to a
## different scene. That decision lives here.
##
## It matters that it is not left to `baby_room.gd::_pick_story_mission_id()`.
## That picker follows the authored level order across every chapter, so once
## `firstWords` is complete it hands the Chapter 3 mission `goodMorningRoutine`
## to the Baby Room, which has no locomotion and cannot play it. Routing on the
## saved chapter intercepts that before the scene is ever loaded.
##
## ## No dead ends (contract §6)
##
## A child must never press a button and get nothing. Four separate falls:
##
##   1. an UNKNOWN chapter (`""`, `"ch1"`, a chapter from a future build) routes
##      to `FALLBACK_ROUTE`, which is the Baby Room -- always playable, needs no
##      house, and is what a brand new profile (`currentChapter: "ch1"`) gets;
##   2. a route whose SCENE IS MISSING falls through to the other scene rather
##      than to a disabled button;
##   3. Free Play with no house falls back to the Baby Room's own Free Play
##      (`ProgressionMode.FREE_PLAY`), which is a no-objective mode too;
##   4. only if NEITHER scene exists does the menu say something warm and stay
##      put -- and that is a broken build, not a state a shipped game can reach.
##
## Restoring into the house has its own chain, in `HouseWorld.enter_saved_location()`:
## an unknown spawn falls to the room default, an unknown room to the bedroom.
##
## ## Why the scene is swapped by hand
##
## `change_scene_to_file()` gives no chance to configure the new scene before
## `_ready()` runs, and both worlds need their progression mode set BEFORE that:
## `baby_room.gd::_ready()` immediately starts a mission, and `HouseWorld` places
## the child on `build_world()`. So the packed scene is instantiated, configured,
## and only then added. No autoload, no singleton, no global session object --
## `CLAUDE.md` asks for composition, and this is the one hand-off that needs it.

const BABY_ROOM_PATH: String = "res://scenes/baby_room/baby_room.tscn"
const HOUSE_WORLD_PATH: String = "res://scenes/house/house_world.tscn"

## `load()`ed rather than `preload()`ed: the title screen is the first thing the
## engine parses, and a missing or broken content script must not stop the game
## from starting at all.
const CONTENT_LIBRARY_SCRIPT_PATH: String = "res://scripts/content/content_library.gd"
const LEVEL_SYSTEM_SCRIPT_PATH: String = "res://scripts/progression/level_system.gd"

## The two worlds. Not a scene path directly, so the mapping below reads as a
## product decision ("Chapter 3 is the house") rather than as a file listing.
enum Route { BABY_ROOM, HOUSE_WORLD }

## The same names `baby_room.gd` uses, and the same ordinals, so one value can be
## handed to either world without translation. A second vocabulary for one idea
## is how the two halves of a game drift apart.
enum ProgressionMode { STORY, FREE_PLAY }

## Saved `currentChapter` -> world.
##
## `ch1` is mapped explicitly even though the Prologue does not exist yet,
## because it is what `ProfileStore.default_profile()` writes: every brand new
## player starts there, and it must land somewhere playable rather than relying
## on the unknown-chapter fallback to catch it.
const CHAPTER_ROUTES: Dictionary = {
	"ch1": Route.BABY_ROOM,
	"ch2": Route.BABY_ROOM,
	"ch3": Route.HOUSE_WORLD,
}

## Where an unknown or unplayable chapter goes. The Baby Room, because it is
## complete, needs no navigation and no Chapter 3 content, and is the last thing
## in the project that would ever stop working.
const FALLBACK_ROUTE: int = Route.BABY_ROOM

## Free Play is the house: four rooms to wander with nothing to finish.
const FREE_PLAY_ROUTE: int = Route.HOUSE_WORLD

## Aimed in code rather than relying on a hand-written Transform3D in the .tscn,
## which previously had an inverted pitch and framed the backdrop off-screen.
##
## Framed on Little Buddy, who stands at the origin. The art bible calls the
## character the most memorable subject a title screen can have, and this one
## used to be three pastel spheres on an empty field -- correct colours, nobody
## home. The numbers: he is 0.85 m tall, the vertical FOV is 50 degrees, and at
## 2.23 m the visible slice is about 2.08 m, so he stands roughly 41% of the
## frame high, head a quarter of the way down and feet just above the two
## buttons. The camera sits above the aim point, which gives the constrained
## three-quarter, slightly-down view §5 asks for -- never top-down, which kills
## faces, and a face is the whole point of putting him here.
const CAMERA_POSITION: Vector3 = Vector3(0.72, 0.80, 2.05)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.44, 0.0)

@onready var _play_button: Button = %PlayButton
@onready var _free_play_button: Button = %FreePlayButton
@onready var _coming_soon_label: Label = %ComingSoonLabel


func _ready() -> void:
	var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
		camera.current = true

	_coming_soon_label.visible = false
	_play_button.pressed.connect(_on_play_pressed)
	_free_play_button.pressed.connect(_on_free_play_pressed)


# ---------------------------------------------------------------------------
# Routing -- pure, static, and testable without a tree
# ---------------------------------------------------------------------------

## The world a saved chapter belongs to. Never fails: an unknown, empty or
## future chapter id resolves to `FALLBACK_ROUTE`.
static func route_for_chapter(chapter_id: String) -> int:
	var key: String = chapter_id.strip_edges()
	if CHAPTER_ROUTES.has(key):
		return int(CHAPTER_ROUTES[key])
	return FALLBACK_ROUTE


static func scene_path_for_route(route: int) -> String:
	if route == Route.HOUSE_WORLD:
		return HOUSE_WORLD_PATH
	return BABY_ROOM_PATH


## The scene Story Mode should open for `chapter_id`.
##
## Guaranteed to name a scene that is actually on disk, or `""` when the build
## has neither world in it. Never returns a path that would fail to load.
static func story_scene_path(chapter_id: String) -> String:
	return _first_existing([
		scene_path_for_route(route_for_chapter(chapter_id)),
		scene_path_for_route(FALLBACK_ROUTE),
		BABY_ROOM_PATH,
		HOUSE_WORLD_PATH,
	])


## The scene Free Play should open. The house, or the Baby Room's own Free Play
## if this build has no house.
static func free_play_scene_path() -> String:
	return _first_existing([
		scene_path_for_route(FREE_PLAY_ROUTE),
		BABY_ROOM_PATH,
		HOUSE_WORLD_PATH,
	])


static func _first_existing(paths: Array) -> String:
	for path: Variant in paths:
		var candidate: String = String(path)
		if not candidate.is_empty() and ResourceLoader.exists(candidate):
			return candidate
	return ""


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _on_play_pressed() -> void:
	_enter_scene(story_scene_path(resolve_story_chapter_id()), ProgressionMode.STORY)


func _on_free_play_pressed() -> void:
	_enter_scene(free_play_scene_path(), ProgressionMode.FREE_PLAY)


## The chapter the profile says the child is on, or `""` when there is no save
## service at all (the headless runner loads no autoloads). `""` routes to the
## fallback, so a missing save can never strand the menu.
func get_saved_chapter() -> String:
	var save_service: Node = _autoload("SaveService")
	if save_service != null and save_service.has_method("get_current_chapter"):
		return String(save_service.call("get_current_chapter"))
	return ""


## The chapter Story Mode should actually open, and the value the profile is
## brought up to date with.
##
## `currentChapter` is a RESUME POINTER, and nothing in the game advances it yet:
## a fresh profile is written as `"ch1"` and stays `"ch1"` forever. Routing on it
## alone would mean Chapter 3 could never be reached however much of Chapter 2 a
## child finished -- the house would stay unreachable, which is the exact gap
## this work exists to close. So the saved value is TRUSTED when it still names
## an unlocked, unfinished chapter, and RECOMPUTED from `levelCompleted`
## otherwise, using the same unlock rules `LevelSystem` gives the rest of the
## game.
##
## Returns "" only when there is no save service and no content, which routes to
## the fallback world.
func resolve_story_chapter_id() -> String:
	var save_service: Node = _autoload("SaveService")
	var saved: String = get_saved_chapter()
	if save_service == null or not save_service.has_method("get_level_completed"):
		return saved

	var completed: Dictionary = save_service.call("get_level_completed")
	var resolved: String = pick_chapter_id(_level_system(), completed, saved)
	if resolved.is_empty():
		return saved
	if resolved != saved and save_service.has_method("set_current_chapter"):
		# Move the resume pointer forward so the next launch does not have to
		# recompute, and so anything else reading `currentChapter` agrees.
		save_service.call("set_current_chapter", resolved)
	return resolved


## Pure chapter selection, split out so it can be asserted without a save file.
##
##   1. the saved chapter, if it is unlocked and not already finished;
##   2. otherwise the first unlocked chapter that is not finished;
##   3. otherwise the LAST unlocked chapter -- the journey is complete, so send
##      the child to the newest world rather than to nothing;
##   4. "" when the level system knows no chapters at all.
static func pick_chapter_id(system: Variant, completed: Dictionary, saved_chapter: String) -> String:
	if system == null or not system.has_method("compute_unlocks"):
		return ""
	var unlocked: PackedStringArray = system.call("compute_unlocks", completed)["chapters"]
	if unlocked.is_empty():
		return ""

	var saved: String = saved_chapter.strip_edges()
	if unlocked.has(saved) and not bool(system.call("is_chapter_complete", saved, completed)):
		return saved

	for chapter_id: String in unlocked:
		if not bool(system.call("is_chapter_complete", chapter_id, completed)):
			return chapter_id

	return unlocked[unlocked.size() - 1]


## Built on demand rather than at `_ready()`: the menu should come up instantly,
## and this costs a content load. Null when the content set cannot be read, which
## `resolve_story_chapter_id()` treats as "keep the saved chapter".
func _level_system() -> Variant:
	var library_script: Resource = load(CONTENT_LIBRARY_SCRIPT_PATH)
	if not (library_script is GDScript):
		return null
	var system_script: Resource = load(LEVEL_SYSTEM_SCRIPT_PATH)
	if not (system_script is GDScript):
		return null
	return (system_script as GDScript).call("create", (library_script as GDScript).call("create"))


## Room ids Free Play may use. An empty list is handed straight through and means
## "all of them" to `HouseWorld` -- a fresh profile carries `unlockedRooms: []`
## and must not be read as "no room is open".
func get_unlocked_room_ids() -> Array:
	var save_service: Node = _autoload("SaveService")
	if save_service == null or not save_service.has_method("get_profile"):
		return []
	var profile: Dictionary = save_service.call("get_profile")
	var rooms: Variant = profile.get("unlockedRooms", null)
	if typeof(rooms) != TYPE_ARRAY:
		return []
	return (rooms as Array).duplicate()


# ---------------------------------------------------------------------------
# Scene hand-off
# ---------------------------------------------------------------------------

## Instantiates `path`, configures it for `mode`, and swaps it in for the menu.
## Returns false only when there is nothing loadable to swap to, in which case
## the menu stays up with a friendly message rather than a black screen.
func _enter_scene(path: String, mode: int) -> bool:
	var instance: Node = build_scene(path, mode, get_unlocked_room_ids(), _saved_profile())
	if instance == null:
		_show_unavailable()
		return false

	var tree: SceneTree = get_tree()
	if tree == null:
		instance.free()
		return false

	var previous: Node = tree.current_scene
	tree.root.add_child(instance)
	tree.current_scene = instance
	if previous != null and previous != instance:
		previous.queue_free()
	return true


## Loads and configures a world WITHOUT touching the tree, so the whole hand-off
## can be asserted headlessly. Returns null when `path` holds no scene.
##
## Configuration is duck-typed throughout: both worlds answer
## `set_progression_mode()`, only the house answers the other two, and a world
## that answers none of them still loads and plays.
static func build_scene(
	path: String, mode: int, unlocked_room_ids: Array = [], profile: Variant = null
) -> Node:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed: Resource = load(path)
	if not (packed is PackedScene):
		return null
	var instance: Node = (packed as PackedScene).instantiate()
	if instance == null:
		return null

	if instance.has_method("set_progression_mode"):
		instance.call("set_progression_mode", mode)
	if mode == ProgressionMode.FREE_PLAY and instance.has_method("set_unlocked_room_ids"):
		instance.call("set_unlocked_room_ids", unlocked_room_ids)
	# Put the child back where they were. An invalid, stale or corrupt saved
	# location resolves inside the house to the room default and ultimately to the
	# bedroom, so this can only ever improve on the default start.
	if profile != null and instance.has_method("restore_from_profile"):
		instance.call("restore_from_profile", profile)
	return instance


func _saved_profile() -> Variant:
	var save_service: Node = _autoload("SaveService")
	if save_service == null or not save_service.has_method("get_profile"):
		return null
	return save_service.call("get_profile")


## Both worlds are missing. A broken build rather than a reachable state, but the
## child still gets a warm sentence instead of a frozen screen -- and the buttons
## stay pressable, because a disabled control a child keeps tapping is worse than
## one that keeps saying the same friendly thing.
func _show_unavailable() -> void:
	_coming_soon_label.visible = true


func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)
