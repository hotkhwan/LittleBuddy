extends Node3D

## The title screen, and the only place in the game that decides WHICH WORLD a
## child is about to play in.
##
## ```
## Main menu
## ├── Play with Bunny → activity picker → house_world.tscn, STORY, that mission
## │                     (every Bunny-care level, always, with its 0..3 stars)
## ├── Learn with Aliz → classroom.tscn
## ├── Free Play       → house_world.tscn, unlocked rooms, no objective
## ├── Dress Up        → dress_up.tscn
## └── Grown-ups       → parent_settings.tscn
## ```
##
## ## Play with Bunny (owner playtest, 2026-09-21)
##
## The primary button used to say Start/Continue and route on the saved chapter,
## which for almost every real profile meant the Chapter 2 Baby Room -- not the
## house with Bunny the button implied -- and once a house level was finished
## there was no way back to it. Now the button says exactly "Play with Bunny",
## opens `scenes/activities_menu/activity_picker.gd` over this screen, and the
## card the child taps becomes `build_scene(house, STORY, mission_id)`. The
## picker is built from content (`ActivityPicker.entries_for()`), lists finished
## levels like any other, and shows their rating. Play with Bunny NEVER opens
## the Baby Room: `bunny_scene_path()` has no Baby Room fallback.
##
## First launch is unchanged: a profile that has never been shown the game still
## goes to the house tutorial (below). After that, Play with Bunny always shows
## the picker -- a brand-new family sees seven cards with "I'm Hungry!" first
## and its next star breathing, rather than being dropped into a level with no
## way to choose. One behaviour, no hidden rule. If the picker has nothing to
## list (a build with no house content) the button goes straight into the house
## and the director picks, so it is never a dead end.
##
## The chapter routing below (`CHAPTER_ROUTES`, `story_scene_path()`,
## `resolve_story_chapter_id()`) is kept as the pure, tested description of
## which world each chapter is -- the Baby Room remains Chapter 2's world -- but
## no title-screen button routes through it any more.
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
## The activity picker. `load()`ed like every optional script here: a build
## without it sends Play with Bunny straight into the house.
const ACTIVITY_PICKER_SCRIPT_PATH: String = "res://scenes/activities_menu/activity_picker.gd"

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

## The pair on the path: Aliz a little left of centre and half a step back,
## Bunny at her right side and a little forward, so he reads as "hers" and the
## front door shows past her shoulder. Art bible §4 is explicit that adults must
## never dominate the frame, and a 1.65 m adult beside a 0.78 m baby will do
## exactly that unless she is set back and the camera is aimed low.
const BUDDY_AVATAR_POSITION: Vector3 = Vector3(-0.38, 0.0, -0.55)
## Yaw 0 faces -Z for every character in this project, so 180 faces the camera.
const BUDDY_AVATAR_YAW_DEG: float = 182.0

## Bunny -- the REAL baby, through the same production wrapper the house uses.
## `load()`ed like Aliz: a build without the asset comes up as a garden with one
## fewer person in it, never as an error.
const BUNNY_SCENE_PATH: String = "res://scenes/characters/little_buddy/BabyLittleBuddy.tscn"
const BUNNY_SCRIPT_PATH: String = "res://scripts/characters/little_buddy/baby_little_buddy.gd"
const BUNNY_POSITION: Vector3 = Vector3(0.46, 0.0, -0.20)
## Facing the camera and turned a little toward Aliz, who is to his left.
const BUNNY_YAW_DEG: float = 194.0

## The framing used ONLY when the avatar is on: pulled back and aimed at chest
## height, so a 1.65 m figure and a 0.78 m one both sit between the title and
## the button row with the house behind them. Off, `CAMERA_POSITION`/
## `CAMERA_TARGET` are used unchanged.
const CAMERA_POSITION_WITH_BUDDY: Vector3 = Vector3(0.0, 1.60, 4.45)
const CAMERA_TARGET_WITH_BUDDY: Vector3 = Vector3(0.05, 0.70, -0.70)

## The build number, bottom-right and quiet. This is the ONLY place the version
## is shown to a player: `GameVersion.BUILD` is the single source, and the
## in-game HUD no longer repeats it.
const GAME_VERSION_SCRIPT_PATH: String = "res://scripts/content_packs/game_version.gd"
const VERSION_FONT_SIZE: int = 15
const VERSION_ALPHA: float = 0.55
const VERSION_MARGIN: Vector2 = Vector2(14.0, 10.0)

## THE LOGO SLOT. Agent A's `scripts/branding/logo_title.gd` draws the owner's
## logo as a Control; when it is in the build it takes the title panel's exact
## place and the text panel is hidden. Without it the text panel stays -- the
## fallback is what shipped before.
const LOGO_TITLE_SCRIPT_PATH: String = "res://scripts/branding/logo_title.gd"
const LOGO_HALF_WIDTH: float = 220.0
const LOGO_TOP: float = 4.0
const LOGO_BOTTOM: float = 222.0

## The walk home (`scripts/menu/menu_departure.gd`): what Start and Free Play
## play before the hand-off. `load()`ed like everything optional here.
const DEPARTURE_SCRIPT_PATH: String = "res://scripts/menu/menu_departure.gd"
const UI_FADE_SEC: float = 0.25

@onready var _play_button: Button = %PlayButton
@onready var _free_play_button: Button = %FreePlayButton
@onready var _dress_button: Button = %DressUpButton
@onready var _parent_button: Button = %ParentButton
## "Learn with Aliz" -- the tutor classroom. Shown only while a grown-up has
## the local tutor switched on (`aiTutorEnabled`, default on) and the scene
## is in this build; never a dead button.
@onready var _tutor_button: Button = %LearnWithAlizButton
@onready var _coming_soon_label: Label = %ComingSoonLabel

## Set once the menu has handed off, so the first-launch timer can never fire
## into a scene the child has already left.
var _handed_off: bool = false

## The walk home in progress, or null. While it runs the buttons are gone, the
## first-run timer stands down (the walk routes to first run itself), and a tap
## anywhere skips to the hand-off.
var _departure: Node = null
var _departure_route: Callable = Callable()

## The voice pack (2026-09-20): Aliz welcomes once per launch and says "Let's
## go home!" when Start / Free Play is pressed. `static` so returning to the
## title from the house does not welcome the child a second time.
static var _welcomed_this_launch: bool = false
const VoiceBridge := preload("res://scripts/voice/voice_bridge.gd")
const VoiceCues := preload("res://scripts/voice/voice_cues.gd")
const SubtitleStripScript := preload("res://scripts/voice/subtitle_strip.gd")
## The subtitle pill sits above the Learn with Aliz banner (which ends 404 px
## up; the button row ends at 292).
const SUBTITLE_BOTTOM_MARGIN: float = 420.0
var _skip_catcher: Control = null
## The activity picker while it is open over the menu, or null.
var _picker: Control = null


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
	_tutor_button.pressed.connect(_on_learn_with_aliz_pressed)
	_tutor_button.visible = tutor_available()
	_dress_button.pressed.connect(_on_dress_up_pressed)
	_parent_button.pressed.connect(_on_parent_pressed)
	_label_play_button()
	_dress_buttons()
	_place_logo()
	_add_version_label()
	_add_subtitle_strip()

	_arm_first_run()
	_welcome_once()


func _process(delta: float) -> void:
	if _departure != null and is_instance_valid(_departure) and _departure.has_method("advance"):
		_departure.call("advance", delta)


# ---------------------------------------------------------------------------
# Play with Bunny
# ---------------------------------------------------------------------------

## The primary button's caption, exactly. It names what the button does -- the
## house, with Bunny -- rather than whether a save exists ("Start"/"Continue"
## told a parent that, and told the child nothing). Fifteen characters: the card
## wraps it onto two lines, which is fine; what may not change is the wording,
## because the owner reads it aloud and `test_menu_start_continue.gd` pins it.
const LABEL_PLAY_WITH_BUNNY: String = "Play with Bunny"


func _label_play_button() -> void:
	if _play_button == null:
		return
	# The word lives in a CHILD `Label` ("PlayCaption"), not in the button's own
	# `text` -- the button carries an icon above a caption, and setting `text`
	# draws a second, smaller word behind the icon instead of replacing the
	# visible one. Found by rendering the menu and looking at it.
	var caption: Label = _play_button.get_node_or_null("PlayCaption") as Label
	if caption != null:
		caption.text = LABEL_PLAY_WITH_BUNNY
	else:
		_play_button.text = LABEL_PLAY_WITH_BUNNY


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
## Dress Up is its own small screen (`scenes/dress_up/dress_up.tscn`): the real
## Aliz on a stage with colour swatches and a Back button. It used to open
## `scenes/activities/dressing.tscn`, an `ActivityScene` that needs the Baby
## Room's director around it and, opened bare, showed a grey dead screen -- the
## one thing a title-screen button must never do.
const DRESS_UP_SCENE: String = "res://scenes/dress_up/dress_up.tscn"
const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
## Aliz Tutor Mode's classroom (`scripts/tutor/tutor_scene.gd`). Opened in
## FREE_PLAY mode: a lesson is no chapter and grants its own stars through the
## LessonEngine, never story progress.
const TUTOR_SCENE: String = "res://scenes/tutor/classroom.tscn"
const TutorFlagsScript := preload("res://scripts/tutor/tutor_flags.gd")
const AI_TUTOR_ENABLED_SETTING: String = "aiTutorEnabled"

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
	for button: Button in [_play_button, _free_play_button, _dress_button, _parent_button, _tutor_button]:
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


## Learn with Aliz. The classroom starts the hands-free voice session itself,
## after this hand-off -- the microphone is never opened from the title screen.
func _on_learn_with_aliz_pressed() -> void:
	if not tutor_available() or not _enter_scene(TUTOR_SCENE, ProgressionMode.FREE_PLAY):
		_show_unavailable()


## The local scripted tutor is always allowed by the flag; a grown-up may still
## switch "Learn with Aliz" off in Grown-ups, and a build may ship without it.
func tutor_available() -> bool:
	if not TutorFlagsScript.local_tutor_enabled() or not ResourceLoader.exists(TUTOR_SCENE):
		return false
	var save_service: Node = _autoload("SaveService")
	if save_service != null and save_service.has_method("get_setting"):
		return bool(save_service.call("get_setting", AI_TUTOR_ENABLED_SETTING, true))
	return true


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
	if _handed_off or _departure != null or not is_inside_tree():
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
	# Her idle -- a breathing sway -- when the wrapper has one. Guarded rather
	# than assumed: the clip is being authored in parallel, and a wrapper
	# without it simply holds her pose. Nothing here fakes a motion.
	if placed.has_method("can_play_action") and placed.has_method("play_action") \
			and bool(placed.call("can_play_action", "idle")):
		placed.call("play_action", "idle")
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

## Play with Bunny. First launch still walks straight home to the tutorial;
## every later press opens the picker over this screen. The walk home and Aliz's
## "Let's go home!" happen when a CARD is tapped, not here -- the child has not
## chosen anything yet.
func _on_play_pressed() -> void:
	if _departure != null:
		skip_departure()
		return
	if is_first_launch():
		VoiceBridge.cue(self, VoiceCues.EVENT_START_PRESSED, "", {"interrupt": true})
		_depart(_route_first_run)
		return
	if not _open_activity_picker():
		# No picker in this build, or nothing to list: never a dead button.
		VoiceBridge.cue(self, VoiceCues.EVENT_START_PRESSED, "", {"interrupt": true})
		_depart(_route_bunny.bind(""))


func _on_free_play_pressed() -> void:
	if _departure == null:
		VoiceBridge.cue(self, VoiceCues.EVENT_FREE_PLAY_PRESSED, "", {"interrupt": true})
	_depart(_route_free_play)


## "Welcome to Little Days!" then "Let's play together!" -- once per launch,
## never on a return to the title. Nothing without the `Voice` autoload.
func _welcome_once() -> void:
	if _welcomed_this_launch:
		return
	if VoiceBridge.cue(self, VoiceCues.EVENT_MENU_READY):
		_welcomed_this_launch = true


## Test hook: lets a case check the once-per-launch rule from a clean state.
static func reset_welcome_for_tests() -> void:
	_welcomed_this_launch = false


static func has_welcomed_this_launch() -> bool:
	return _welcomed_this_launch


func _add_subtitle_strip() -> void:
	var host: Control = get_node_or_null("UI/SafeArea") as Control
	if host == null or host.get_node_or_null("SubtitleStrip") != null:
		return
	var strip: Control = SubtitleStripScript.new()
	strip.name = "SubtitleStrip"
	host.add_child(strip)
	strip.call("build")
	strip.call("set_bottom_margin", SUBTITLE_BOTTOM_MARGIN)


func get_subtitle_strip() -> Control:
	var host: Control = get_node_or_null("UI/SafeArea") as Control
	return host.get_node_or_null("SubtitleStrip") as Control if host != null else null


## A child who beats the first-launch timer to the button still gets taught:
## pressing Play with Bunny the very first time opens the house tutorial -- once,
## for one launch, and only for a profile that has never been shown the game.
## Should first run be impossible (no house), fall through to Bunny's house in
## Story, which is the same building.
func _route_first_run() -> bool:
	if _enter_first_run():
		return true
	return _route_bunny("")


## Play with Bunny's hand-off: the house, in Story, on the mission the child
## picked (or the journey's own pick for ""). Never the Baby Room.
func _route_bunny(mission_id: String) -> bool:
	return _enter_scene(bunny_scene_path(), ProgressionMode.STORY, mission_id)


## The scene Play with Bunny opens, or "" when this build has no house.
##
## **Deliberately no Baby Room fallback**, unlike `story_scene_path()`. The
## button promises Bunny's house; opening the Chapter 2 nursery instead is the
## exact bug the owner reported. A house-less build gets the warm "Back in a
## moment!" line rather than the wrong game.
static func bunny_scene_path() -> String:
	return _first_existing([scene_path_for_route(Route.HOUSE_WORLD)])


# ---------------------------------------------------------------------------
# The activity picker
# ---------------------------------------------------------------------------

## Opens the card grid over the menu. False when there is no picker script in
## the build, it will not construct, or content gives it nothing to list -- the
## caller then goes straight into the house.
func _open_activity_picker() -> bool:
	if _picker != null and is_instance_valid(_picker):
		return true
	var host: Control = get_node_or_null("UI/SafeArea") as Control
	if host == null or not ResourceLoader.exists(ACTIVITY_PICKER_SCRIPT_PATH):
		return false
	var script: Resource = load(ACTIVITY_PICKER_SCRIPT_PATH)
	if not (script is GDScript):
		return false
	var entries: Array = activity_entries()
	if entries.is_empty():
		return false
	var built: Object = (script as GDScript).new()
	if not (built is Control) or not built.has_method("build"):
		if built != null:
			built.free()
		return false
	var picker := built as Control
	picker.call("build", entries)
	if picker.has_signal("activity_chosen"):
		picker.connect("activity_chosen", _on_activity_chosen)
	if picker.has_signal("back_pressed"):
		picker.connect("back_pressed", _close_activity_picker)
	host.add_child(picker)
	_picker = picker
	return true


func _close_activity_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null


func _on_activity_chosen(mission_id: String) -> void:
	_close_activity_picker()
	if _departure == null:
		VoiceBridge.cue(self, VoiceCues.EVENT_START_PRESSED, "", {"interrupt": true})
	_depart(_route_bunny.bind(mission_id))


## The picker's cards, from content and the profile: every playable house
## level with its saved rating. `[]` without a level system or a library.
func activity_entries() -> Array:
	if not ResourceLoader.exists(ACTIVITY_PICKER_SCRIPT_PATH):
		return []
	var script: Resource = load(ACTIVITY_PICKER_SCRIPT_PATH)
	if not (script is GDScript) or not (script as GDScript).has_method("entries_for"):
		return []
	var library_script: Resource = load(CONTENT_LIBRARY_SCRIPT_PATH)
	if not (library_script is GDScript):
		return []
	var library: Object = (library_script as GDScript).call("create")
	var system: Variant = _level_system()
	return (script as GDScript).call("entries_for", system, library, _stars_by_level())


func _stars_by_level() -> Dictionary:
	var save_service: Node = _autoload("SaveService")
	if save_service == null or not save_service.has_method("get_stars_by_level"):
		return {}
	var stored: Variant = save_service.call("get_stars_by_level")
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return (stored as Dictionary).duplicate(true)


## The open picker, or null. For tests and the screenshot harness.
func get_activity_picker() -> Control:
	return _picker if _picker != null and is_instance_valid(_picker) else null


func is_activity_picker_open() -> bool:
	return get_activity_picker() != null


func _route_free_play() -> bool:
	return _enter_scene(free_play_scene_path(), ProgressionMode.FREE_PLAY)


# ---------------------------------------------------------------------------
# The walk home
# ---------------------------------------------------------------------------

## Plays the departure, then runs `route`. When the walk cannot be played --
## no departure script in the build, or it refuses to start -- `route` runs at
## once, which is exactly the old behaviour. A second press while walking is
## a skip, not a second route.
func _depart(route: Callable) -> void:
	if _departure != null:
		skip_departure()
		return
	var departure: Node = _make_departure()
	if departure == null:
		route.call()
		return
	_departure = departure
	_departure_route = route
	add_child(departure)
	if departure.has_signal("finished"):
		departure.finished.connect(_on_departure_finished)
	var began: bool = bool(departure.call("begin",
			get_node_or_null("BigBuddy") as Node3D,
			get_node_or_null("Bunny") as Node3D,
			get_node_or_null("Garden"),
			get_node_or_null("Camera3D") as Camera3D))
	if not began:
		_departure = null
		departure.queue_free()
		route.call()
		return
	_hide_ui_for_departure()


func _make_departure() -> Node:
	if not ResourceLoader.exists(DEPARTURE_SCRIPT_PATH):
		return null
	var script: Resource = load(DEPARTURE_SCRIPT_PATH)
	if not (script is GDScript):
		return null
	var node: Object = (script as GDScript).new()
	if not (node is Node) or not node.has_method("begin") or not node.has_method("advance"):
		if node != null:
			node.free()
		return null
	(node as Node).name = "Departure"
	return node as Node


## A tap anywhere during the walk goes straight to the game.
func skip_departure() -> void:
	if _departure != null and is_instance_valid(_departure) and _departure.has_method("skip"):
		_departure.call("skip")


## The walk in progress, or null. For tests and the screenshot harness.
func get_departure() -> Node:
	return _departure if _departure != null and is_instance_valid(_departure) else null


func is_departing() -> bool:
	return get_departure() != null


func _on_departure_finished() -> void:
	var departure: Node = _departure
	var route: Callable = _departure_route
	_departure_route = Callable()
	var opened: bool = route.is_valid() and bool(route.call())
	if departure != null and is_instance_valid(departure):
		if opened:
			# The cover lifts off the NEW scene; it lives under the root, so it
			# outlives this menu.
			if departure.has_method("reveal"):
				departure.call("reveal")
		else:
			# Nothing to open (a broken build). Take the cover down and give the
			# buttons back, with the warm message `_show_unavailable()` shows.
			if departure.has_method("discard_cover"):
				departure.call("discard_cover")
			_show_ui_after_departure()
			departure.queue_free()
			_departure = null


func _hide_ui_for_departure() -> void:
	var safe_area: Control = get_node_or_null("UI/SafeArea") as Control
	if safe_area != null:
		if is_inside_tree():
			var tween: Tween = create_tween()
			tween.tween_property(safe_area, "modulate:a", 0.0, UI_FADE_SEC)
		else:
			safe_area.modulate.a = 0.0
	var ui: Node = get_node_or_null("UI")
	if ui != null and _skip_catcher == null:
		var catcher := Control.new()
		catcher.name = "SkipCatcher"
		catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
		catcher.mouse_filter = Control.MOUSE_FILTER_STOP
		catcher.gui_input.connect(_on_skip_catcher_input)
		ui.add_child(catcher)
		_skip_catcher = catcher


func _show_ui_after_departure() -> void:
	var safe_area: Control = get_node_or_null("UI/SafeArea") as Control
	if safe_area != null:
		safe_area.modulate.a = 1.0
	if _skip_catcher != null and is_instance_valid(_skip_catcher):
		_skip_catcher.queue_free()
	_skip_catcher = null


func _on_skip_catcher_input(event: InputEvent) -> void:
	var pressed: bool = false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	if pressed:
		skip_departure()


# ---------------------------------------------------------------------------
# The logo slot, and the version
# ---------------------------------------------------------------------------

## Swaps the text title panel for the owner's logo when `logo_title.gd` is in
## the build. Same anchors and offsets, same place in the draw order; the text
## panel is hidden, not removed, so a logo that fails to build costs nothing.
func _place_logo() -> void:
	var panel: Control = get_node_or_null("UI/SafeArea/TitlePanel") as Control
	if panel == null or not ResourceLoader.exists(LOGO_TITLE_SCRIPT_PATH):
		return
	var script: Resource = load(LOGO_TITLE_SCRIPT_PATH)
	if not (script is GDScript):
		return
	if not ClassDB.is_parent_class((script as GDScript).get_instance_base_type(), "Control"):
		return
	var logo: Object = (script as GDScript).new()
	if not (logo is Control):
		if logo != null:
			logo.free()
		return
	var control := logo as Control
	control.name = "LogoTitle"
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var host: Node = panel.get_parent()
	host.add_child(control)
	host.move_child(control, panel.get_index())
	control.anchor_left = panel.anchor_left
	control.anchor_top = panel.anchor_top
	control.anchor_right = panel.anchor_right
	control.anchor_bottom = panel.anchor_bottom
	# The logo is a 1024x616 picture, not a 640x142 text plaque: give it the
	# taller slot Agent A specified (see logo_title.gd) or it renders postcard
	# sized inside the panel's height. Same centre; it stays above the heads.
	control.offset_left = -LOGO_HALF_WIDTH
	control.offset_top = LOGO_TOP
	control.offset_right = LOGO_HALF_WIDTH
	control.offset_bottom = LOGO_BOTTOM
	control.grow_horizontal = panel.grow_horizontal
	control.grow_vertical = panel.grow_vertical
	panel.visible = false


## "v0.1.0", bottom-right, ink at 55%. Read from `GameVersion.BUILD` so it can
## never disagree with the content packs' idea of the build.
func _add_version_label() -> void:
	var host: Control = get_node_or_null("UI/SafeArea") as Control
	if host == null:
		return
	var label := Label.new()
	label.name = "VersionLabel"
	label.text = "v" + build_version()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", VERSION_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(Palette.INK, VERSION_ALPHA))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_left = -240.0 - VERSION_MARGIN.x
	label.offset_top = -40.0 - VERSION_MARGIN.y
	label.offset_right = -VERSION_MARGIN.x
	label.offset_bottom = -VERSION_MARGIN.y
	host.add_child(label)


## The build string, or "" when the version script is missing from the build.
static func build_version() -> String:
	if not ResourceLoader.exists(GAME_VERSION_SCRIPT_PATH):
		return ""
	var script: Resource = load(GAME_VERSION_SCRIPT_PATH)
	if not (script is GDScript):
		return ""
	var constants: Dictionary = (script as GDScript).get_script_constant_map()
	return String(constants.get("BUILD", ""))


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
func _enter_scene(path: String, mode: int, mission_id: String = "") -> bool:
	var instance: Node = build_scene(
		path, mode, get_unlocked_room_ids(), _saved_profile(), mission_id)
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
## `set_progression_mode()`, only the house answers the other three, and a world
## that answers none of them still loads and plays.
##
## `mission_id` is the activity picker's request ("Play with Bunny" -> a card).
## It is handed to `set_requested_mission_id()` when the world has one, and the
## world's own director decides whether it is playable; an empty id is Story as
## it always was.
static func build_scene(
	path: String, mode: int, unlocked_room_ids: Array = [], profile: Variant = null,
	mission_id: String = ""
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
	if not mission_id.strip_edges().is_empty() and instance.has_method("set_requested_mission_id"):
		instance.call("set_requested_mission_id", mission_id)
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


## Through `_scene_tree()`, so a menu that is not yet in an active tree (the
## headless runner's root during `_initialize()`) asks the main loop instead of
## raising an engine error; in the running game the two are the same tree.
func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = _scene_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)
