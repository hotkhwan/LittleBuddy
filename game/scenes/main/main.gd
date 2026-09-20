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

## ## First launch (added after a real child could not find the tutorial)
##
## Onboarding lives in the house, because three of the four things it teaches
## (walk there, use that, carry this) only exist where there is a character who
## walks. But `ProfileStore.default_profile()` writes `currentChapter: "ch1"`, and
## ch1 and ch2 both route to the Baby Room -- so a brand new player was routed
## past the tutorial and never saw it once.
##
## So a profile that has never been shown the game (`settings.onboardingDone` is
## not an explicit `true`) is sent to the **house** on launch, automatically,
## before either button is pressed and before it is expected to play anything.
## First run plays, records itself, and the session continues as Free Play --
## which is the objective-free house the tutorial has just finished describing.
##
## **Chapter routing is untouched.** `CHAPTER_ROUTES` still maps ch1 and ch2 to
## the Baby Room; Chapter 2's caregiver gameplay is not involved in any of this
## and the Baby Room acquires no navigation. The second launch, with the flag
## written, behaves exactly as this file always has.

const BABY_ROOM_PATH: String = "res://scenes/baby_room/baby_room.tscn"
const HOUSE_WORLD_PATH: String = "res://scenes/house/house_world.tscn"

## Where first run is decided. `load()`ed rather than `preload()`ed, like the
## content scripts below: a build with no onboarding simply has no first launch.
const ONBOARDING_PLAN_SCRIPT_PATH: String = "res://scripts/onboarding/onboarding_plan.gd"
## Mirrors `onboarding_plan.gd::SETTING_KEY`. Duplicated rather than loaded so the
## title screen never depends on that script parsing; `test_routing_first_run.gd`
## pins the two together.
const ONBOARDING_SETTING_KEY: String = "onboardingDone"

## A beat on the title screen before first launch takes over, so the app has a
## name and a face for the adult who just installed it. Short enough that a child
## handed the iPad does not have time to wonder what to press.
const FIRST_RUN_DELAY_SEC: float = 1.4

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

## First launch is the house too, and for the same reason Chapter 3 is: it is the
## only world where the gestures being taught exist.
const FIRST_RUN_ROUTE: int = Route.HOUSE_WORLD

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

## ## The Big Buddy avatar preview -- EXPERIMENTAL, OFF BY DEFAULT
##
## `scenes/characters/buddy/PinkGirlBuddy.tscn` wraps a generator-produced adult
## caregiver the owner supplied. It is 155x over the art bible's triangle budget
## and has no rig at all, so it does **not** ship: `PinkGirlBuddy.ENABLED` is
## `false` and everything below is dead code in the shipped build. It is wired
## here, and only here, because the title screen is the one place in the game
## where a character is shown with no gameplay, no navigation and no interaction
## attached to it -- so it is the one place a broken character cannot break
## anything. See `pink_girl_buddy.gd` for the full measurement.
##
## Nothing about routing, saving, speech or the buttons is involved. With the
## flag off this scene renders byte-for-byte as it always has, including the
## camera, which is why the with-avatar framing is a separate pair of constants
## rather than an adjustment to the ones above.
const BUDDY_AVATAR_SCENE_PATH: String = "res://scenes/characters/buddy/PinkGirlBuddy.tscn"
const BUDDY_AVATAR_SCRIPT_PATH: String = "res://scripts/characters/buddy/pink_girl_buddy.gd"

## The family on the path. Aliz stands at the centre, a half step back so the
## two small ones in front of her read as "hers"; Bunny sits forward and to her
## right, Little Buddy (`main.tscn`) to her left. Art bible §4 is explicit that
## adults must never dominate the frame, and a 1.65 m adult beside a 0.78 m baby
## will do exactly that unless she is set back and the camera is aimed low.
const BUDDY_AVATAR_POSITION: Vector3 = Vector3(0.05, 0.0, -0.55)
## Yaw 0 faces -Z for every character in this project, so 180 faces the camera.
const BUDDY_AVATAR_YAW_DEG: float = 182.0

## Bunny -- the REAL baby, through the same production wrapper the house uses.
## `load()`ed like Aliz: a build without the asset comes up as a garden with one
## fewer person in it, never as an error.
const BUNNY_SCENE_PATH: String = "res://scenes/characters/little_buddy/BabyLittleBuddy.tscn"
const BUNNY_SCRIPT_PATH: String = "res://scripts/characters/little_buddy/baby_little_buddy.gd"
const BUNNY_POSITION: Vector3 = Vector3(0.82, 0.0, -0.22)
## Facing the camera and turned a little toward Aliz, who is to his left.
const BUNNY_YAW_DEG: float = 194.0

## The framing used ONLY when the avatar is on: pulled back and aimed at chest
## height, so a 1.65 m figure, a 0.85 m one and a 0.78 m one all sit between the
## title and the button row with the house behind them. Off,
## `CAMERA_POSITION`/`CAMERA_TARGET` are used unchanged.
const CAMERA_POSITION_WITH_BUDDY: Vector3 = Vector3(0.10, 1.60, 4.45)
const CAMERA_TARGET_WITH_BUDDY: Vector3 = Vector3(0.15, 0.70, -0.70)

@onready var _play_button: Button = %PlayButton
@onready var _free_play_button: Button = %FreePlayButton
@onready var _dress_button: Button = %DressUpButton
@onready var _parent_button: Button = %ParentButton
@onready var _coming_soon_label: Label = %ComingSoonLabel

## Set once the menu has handed off, so the first-launch timer can never fire
## into a scene the child has already left.
var _handed_off: bool = false


func _ready() -> void:
	var showing_buddy: bool = _add_buddy_avatar()
	_add_bunny()
	var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		if showing_buddy:
			camera.look_at_from_position(
				CAMERA_POSITION_WITH_BUDDY, CAMERA_TARGET_WITH_BUDDY, Vector3.UP)
		else:
			camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
		camera.current = true

	_coming_soon_label.visible = false
	_play_button.pressed.connect(_on_play_pressed)
	_free_play_button.pressed.connect(_on_free_play_pressed)
	_dress_button.pressed.connect(_on_dress_up_pressed)
	_parent_button.pressed.connect(_on_parent_pressed)
	_label_play_button()
	_dress_buttons()

	_arm_first_run()


# ---------------------------------------------------------------------------
# Start, or Continue
# ---------------------------------------------------------------------------

## The two words a returning family looks for.
##
## The button used to say "Play" whether this was the first launch or the
## fiftieth, which loses the one piece of information a parent actually wants
## from a title screen: *is our progress still here?* A child who has played
## before is not starting; they are carrying on, and saying so is the difference
## between a menu and a front door.
##
## The choice is made from COMPLETION, not from a star count. Stars can be zero
## after a genuinely finished level -- the skip button is the room's no-dead-end
## escape hatch and rates 0 on purpose -- so a child who skipped their way
## through Monday would be greeted with "Start" on Tuesday and reasonably wonder
## where their house went.
const LABEL_START: String = "Start"
const LABEL_CONTINUE: String = "Continue"


func _label_play_button() -> void:
	if _play_button == null:
		return
	var label: String = LABEL_CONTINUE if _has_progress() else LABEL_START
	# The word lives in a CHILD `Label` ("PlayCaption"), not in the button's own
	# `text` -- the button carries an icon above a caption, and setting `text`
	# draws a second, smaller word behind the icon instead of replacing the
	# visible one. Found by rendering the menu and looking at it; the first
	# version of this function set `text` and changed nothing on screen.
	var caption: Label = _play_button.get_node_or_null("PlayCaption") as Label
	if caption != null:
		caption.text = label
	else:
		_play_button.text = label


## Has this family played before? Asked of SaveService, defensively -- a build
## without one, or an older one, answers "no" and gets "Start", which is the safe
## way to be wrong.
func _has_progress() -> bool:
	var save_service: Node = get_node_or_null("/root/SaveService")
	if save_service == null:
		return false
	if save_service.has_method("get_level_completed"):
		var completed: Variant = save_service.call("get_level_completed")
		if typeof(completed) == TYPE_DICTIONARY and not (completed as Dictionary).is_empty():
			return true
	# Mid-level counts too: a child who stopped half way through Tuesday's
	# mission has progress even though nothing is finished yet.
	if save_service.has_method("get_current_level"):
		if not String(save_service.call("get_current_level")).strip_edges().is_empty():
			return true
	return false


# ---------------------------------------------------------------------------
# The four buttons: shadow, squish, and where they go
# ---------------------------------------------------------------------------

## Dress Up and Grown-ups sit in the same row as Play and Free Play now, at the
## same size, in the same rounded frames, each with its own picture: a shirt with
## a heart, and a gear. Four equal buttons a child can tell apart by colour and
## picture beat two big ones plus two small text-only corners that nobody found.
## Grown-ups is still the quietest of the four -- lavender is the parent chrome
## colour (`Palette.PARENT_CHROME`) and its icon is the plainest.
##
## What the scene file cannot express is added here: a soft drop shadow under
## each button and a small squish on press with the gentle tap sound, so a
## finger on the glass always gets an answer even before the scene changes.
const DRESS_UP_SCENE: String = "res://scenes/activities/dressing.tscn"
const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"

const SHADOW_SIZE: int = 22
const SHADOW_OFFSET: Vector2 = Vector2(0.0, 12.0)
const SHADOW_ALPHA: float = 0.20
const SHADOW_CORNER: int = 44
const PRESS_SCALE: Vector2 = Vector2(0.92, 0.92)
const PRESS_SECONDS: float = 0.08
const TAP_SFX: String = "gentle_tap"

const Palette := preload("res://scripts/ui/palette.gd")


func _menu_buttons() -> Array:
	var buttons: Array = []
	for button: Button in [_play_button, _free_play_button, _dress_button, _parent_button]:
		if button != null:
			buttons.append(button)
	return buttons


func _dress_buttons() -> void:
	for button: Button in _menu_buttons():
		_add_soft_shadow(button)
		button.button_down.connect(_on_button_down.bind(button))
		button.button_up.connect(_on_button_up.bind(button))


## A `Panel` behind the button with only a blurred `StyleBoxFlat` shadow drawn --
## the same anchors and offsets, so it follows the button through every layout.
func _add_soft_shadow(button: Button) -> void:
	var host: Node = button.get_parent()
	if host == null:
		return
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.shadow_color = Color(Palette.INK, SHADOW_ALPHA)
	style.shadow_size = SHADOW_SIZE
	style.shadow_offset = SHADOW_OFFSET
	style.set_corner_radius_all(SHADOW_CORNER)
	var shadow := Panel.new()
	shadow.name = "%sShadow" % button.name
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.add_theme_stylebox_override("panel", style)
	host.add_child(shadow)
	host.move_child(shadow, button.get_index())
	shadow.anchor_left = button.anchor_left
	shadow.anchor_top = button.anchor_top
	shadow.anchor_right = button.anchor_right
	shadow.anchor_bottom = button.anchor_bottom
	shadow.offset_left = button.offset_left
	shadow.offset_top = button.offset_top
	shadow.offset_right = button.offset_right
	shadow.offset_bottom = button.offset_bottom
	shadow.grow_horizontal = button.grow_horizontal
	shadow.grow_vertical = button.grow_vertical


func _on_button_down(button: Button) -> void:
	_squish(button, PRESS_SCALE)
	var sfx: Node = _autoload("Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", TAP_SFX)


func _on_button_up(button: Button) -> void:
	_squish(button, Vector2.ONE)


func _squish(button: Button, to: Vector2) -> void:
	button.pivot_offset = button.size * 0.5
	if not is_inside_tree():
		button.scale = to
		return
	var tween: Tween = create_tween()
	tween.tween_property(button, "scale", to, PRESS_SECONDS).set_trans(Tween.TRANS_SINE)


func _on_dress_up_pressed() -> void:
	# Free Play mode: dressing has no objective and no chapter, exactly like
	# Free Play itself, so it must not be scored as story progress.
	if not _enter_scene(DRESS_UP_SCENE, ProgressionMode.FREE_PLAY):
		_show_unavailable()


func _on_parent_pressed() -> void:
	if not _enter_scene(PARENT_SCENE, ProgressionMode.FREE_PLAY):
		_show_unavailable()


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


## The scene first launch opens, or `""` when this build has no house.
##
## **Deliberately no Baby Room fallback.** Every other route in this file falls
## back to the Baby Room because a child must never press a button and get
## nothing; this one is not a button. A house-less build simply has no first run
## and comes up on the menu exactly as before -- whereas falling back to the Baby
## Room would mean teaching tap-to-walk in a scene where nobody walks, which is
## worse than teaching nothing.
static func first_run_scene_path() -> String:
	return _first_existing([scene_path_for_route(FIRST_RUN_ROUTE)])


## Has this profile ever been shown the game?
##
## Pure, so the whole decision can be asserted without a save file or a tree.
## `setting_value` is whatever `settings.onboardingDone` held, and **only an
## explicit `true` counts as done** -- `onboarding_plan.gd` owns that rule and
## this defers to it rather than restating it.
static func wants_first_run(setting_value: Variant, scene_path: String) -> bool:
	if scene_path.strip_edges().is_empty():
		return false
	var plan: Resource = load(ONBOARDING_PLAN_SCRIPT_PATH)
	if not (plan is GDScript):
		return false
	return bool((plan as GDScript).call("should_run", setting_value))


## The same question, against the real profile.
##
## False when there is no save service -- which is the headless runner, and any
## build where completion could not be recorded. A tutorial that cannot be
## remembered would play on every single launch, and that is worse than none.
func is_first_launch() -> bool:
	var save_service: Node = _autoload("SaveService")
	if save_service == null or not save_service.has_method("get_setting"):
		return false
	return wants_first_run(
		save_service.call("get_setting", ONBOARDING_SETTING_KEY, null), first_run_scene_path()
	)


## Starts the countdown to first launch, if this is one.
##
## A `SceneTreeTimer` rather than an `await` in `_ready()`: the buttons stay live
## throughout, so a child (or an adult) who presses one during the beat is never
## fighting the timer -- `_handed_off` makes the loser of that race a no-op.
func _arm_first_run() -> void:
	if not is_first_launch():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.create_timer(FIRST_RUN_DELAY_SEC).timeout.connect(_on_first_run_due)


func _on_first_run_due() -> void:
	if _handed_off or not is_inside_tree():
		return
	_enter_first_run()


## Opens the house for first run. Free Play, because first run has no objective
## either and because what it teaches -- walk, touch, carry -- is exactly what
## Free Play is made of. `HouseWorld` plays the tutorial on its first frame and
## begins the session itself when it ends.
func _enter_first_run() -> bool:
	var path: String = first_run_scene_path()
	if path.is_empty():
		return false
	return _enter_scene(path, ProgressionMode.FREE_PLAY)


# ---------------------------------------------------------------------------
# The Big Buddy avatar preview
# ---------------------------------------------------------------------------

## True when the avatar is switched on, present in this build and now in the
## scene. False in every other case -- including a build with the flag on but the
## asset stripped out, which must come up as an ordinary title screen rather than
## as an error.
##
## Deliberately the LAST thing that can fail in `_ready()`'s critical path: it is
## called before the camera is aimed but touches nothing else, so a missing or
## unloadable avatar costs the menu nothing at all.
func _add_buddy_avatar() -> bool:
	if not buddy_avatar_enabled():
		return false
	if not ResourceLoader.exists(BUDDY_AVATAR_SCENE_PATH):
		return false
	var packed: Resource = load(BUDDY_AVATAR_SCENE_PATH)
	if not (packed is PackedScene):
		return false
	var avatar: Node = (packed as PackedScene).instantiate()
	if not (avatar is Node3D):
		if avatar != null:
			avatar.free()
		return false
	var placed := avatar as Node3D
	placed.name = "BigBuddy"
	placed.position = BUDDY_AVATAR_POSITION
	placed.rotation = Vector3(0.0, deg_to_rad(BUDDY_AVATAR_YAW_DEG), 0.0)
	add_child(placed)
	return true


## Bunny, through `BabyLittleBuddy.tscn` -- the same wrapper `child_actor.gd`
## uses in the house, so the baby on the title screen IS the baby the child is
## about to look after. Built, then asked for his hand-authored `idle` so he
## breathes rather than stands like a statue; a wrapper without clips simply
## holds its pose. Nothing else touches him: no needs, no bubble, no walking.
func _add_bunny() -> bool:
	if not ResourceLoader.exists(BUNNY_SCENE_PATH):
		return false
	var script: Resource = load(BUNNY_SCRIPT_PATH)
	if script is GDScript and (script as GDScript).has_method("is_enabled") \
			and not bool((script as GDScript).call("is_enabled")):
		return false
	var packed: Resource = load(BUNNY_SCENE_PATH)
	if not (packed is PackedScene):
		return false
	var bunny: Node = (packed as PackedScene).instantiate()
	if not (bunny is Node3D):
		if bunny != null:
			bunny.free()
		return false
	var placed := bunny as Node3D
	placed.name = "Bunny"
	placed.position = BUNNY_POSITION
	placed.rotation = Vector3(0.0, deg_to_rad(BUNNY_YAW_DEG), 0.0)
	add_child(placed)
	if placed.has_method("build"):
		placed.call("build")
	if placed.has_method("get_animation_player"):
		var player: AnimationPlayer = placed.call("get_animation_player") as AnimationPlayer
		if player != null and player.has_animation("idle"):
			player.play("idle")
	return true


## The switch, read from the wrapper so there is exactly ONE of it in the
## project. `load()`ed rather than `preload()`ed for the same reason as every
## other optional script in this file: a build without the avatar must still
## bring the menu up.
static func buddy_avatar_enabled() -> bool:
	if not ResourceLoader.exists(BUDDY_AVATAR_SCRIPT_PATH):
		return false
	var script: Resource = load(BUDDY_AVATAR_SCRIPT_PATH)
	if not (script is GDScript):
		return false
	return bool((script as GDScript).call("is_enabled"))


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
	# A child who beats the first-launch timer to the button still gets taught.
	# Pressing Play the very first time therefore opens the house rather than
	# Chapter 2 -- once, for one launch, and only for a profile that has never
	# been shown the game.
	if is_first_launch() and _enter_first_run():
		return
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

	var tree: SceneTree = _scene_tree()
	if tree == null:
		instance.free()
		return false

	_handed_off = true
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


## The tree to hand off into. `get_tree()` is null for a node that is not in an
## ACTIVE tree -- which is every node during the headless runner's
## `_initialize()`, where `test_menu_wow.gd` presses the real buttons -- so the
## main loop is the fallback. In the running game the two are the same tree.
func _scene_tree() -> SceneTree:
	if is_inside_tree():
		return get_tree()
	return Engine.get_main_loop() as SceneTree


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
