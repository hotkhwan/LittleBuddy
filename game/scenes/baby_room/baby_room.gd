extends Node3D

## The Baby Room: the one scene a child actually plays in.
##
## It runs in one of two modes, chosen once at `_ready()`:
##
##   * **Mission mode** (normal). A `MissionRunner` plays an unlocked routine of
##     5-8 data-driven tasks from `content/`, staged by an `ActivityScene`
##     (`res://scenes/activities/*.tscn`) that supplies the drop zones and the
##     spawn row. When the mission ends the session summary appears, and
##     "Play again" starts the next one -- forever, so the game never ends on a
##     dead screen.
##   * **Legacy mode** (fallback). If the content library or the mission list
##     cannot be loaded, the original hand-built `feedMilk` loop with
##     `%MilkBottle` and `%Teddy` runs instead. A bad JSON file must never make
##     the game unplayable.
##
## The two modes are mutually exclusive by construction. `feedMilk` exists both
## as a legacy activity and as a mission task, so if both ran at once one child
## action could be paid for twice. Mission mode therefore hides AND disables
## `%MilkBottle`/`%Teddy` and never starts `FeedActivity`; on top of that every
## star in the game -- from either mode -- goes through the single
## `RewardManager` / `RewardLedger` pair, which refuses to pay for the same task
## twice inside a round. See `scripts/rewards/reward_manager.gd`.
##
## Autoloads (`SaveService`, `SpeechService`, `TtsService`, `Sfx`) are all
## reached through `_autoload()` + `has_method`, so the room still runs --
## touch-only, silent -- if any of them is missing.
##
## Touch has two independent paths so a missed pick never leaves a child stuck:
##   1. `Area3D.input_event` (Godot's 3D physics picking, enabled here via
##      `Viewport.physics_object_picking`),
##   2. an explicit `Camera3D` raycast in `_unhandled_input`, which now asks any
##      collider it hits for `try_deliver_from_raycast()` /
##      `try_trigger_from_raycast()` rather than testing node identity -- so
##      objects spawned at runtime from JSON get the same belt-and-braces path.

const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const StickerBookScript := preload("res://scripts/progression/sticker_book.gd")
const CelebrationScript := preload("res://scripts/progression/celebration.gd")
const PromptSpeakerScript := preload("res://scripts/speech/prompt_speaker.gd")
const BabyAvatarScript := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
# Preloaded rather than referenced by `class_name`: global class names come from
# the editor's script-class cache, which the headless `--script` test runner does
# not build. A `class_name` reference here parse-errors the whole room there.
const LevelSystemScript := preload("res://scripts/progression/level_system.gd")
const StarRulesScript := preload("res://scripts/progression/star_rules.gd")

const ENCOURAGEMENT_GREAT: String = "Great!"
const ENCOURAGEMENT_TRY_AGAIN: String = "Try again!"
const ENCOURAGEMENT_TOUCH_HINT: String = "You can tap it too!"
const ENCOURAGEMENT_DISPLAY_SEC: float = 1.8
const RESTART_DELAY_SEC: float = 2.5
const RESET_HUNGER_VALUE: float = 80.0
const TEDDY_WORD: String = "Teddy!"
const TEDDY_LOVE_PHRASE: String = "I love my teddy!"
const TEDDY_SPEAK_GAP_SEC: float = 1.1
const TEDDY_REACTION_SEC: float = 2.6
const RAY_LENGTH: float = 30.0

## How long the baby stays in its "happy" reaction after finishing a task.
const HAPPY_REACTION_SEC: float = 1.5

## Drop-zone catch radius (metres) -- generous, matching the generous
## collision shapes on MilkBottle/Teddy, so a small child's imprecise drag
## still registers as "delivered" as soon as the object gets close.
const DROP_ZONE_RADIUS: float = 0.22

## Used only if BabyView3D is missing `get_mouth_position()`/`get_hug_position()`
## (e.g. mid-integration) so drop zones still land somewhere sensible instead
## of at the world origin.
const FALLBACK_MOUTH_POSITION: Vector3 = Vector3(0.0, 0.42, 0.15)
const FALLBACK_HUG_POSITION: Vector3 = Vector3(0.0, 0.28, 0.12)

const NURSERY_PROPS_PATH: String = "res://scenes/nursery/nursery_props.tscn"
const FALLBACK_ROOM_NODE_NAMES: Array = [
	"WorldEnvironment", "DirectionalLight3D", "Floor", "BackWall", "SideWall", "SideWallRight",
]

## Per-category staging scenes. Every one of them contains the full set of drop
## zones, so a mission whose tasks cross categories (Morning Routine feeds the
## baby, for instance) still finds every zone it needs.
const ACTIVITY_SCENES: Dictionary = {
	"feeding": "res://scenes/activities/feeding.tscn",
	"dressing": "res://scenes/activities/dressing.tscn",
	"bath": "res://scenes/activities/bath.tscn",
	"play": "res://scenes/activities/play.tscn",
	"bedtime": "res://scenes/activities/bedtime.tscn",
}
const DEFAULT_ACTIVITY_SCENE: String = "res://scenes/activities/feeding.tscn"

const STICKER_BOOK_SCENE: String = "res://scenes/progression/sticker_book.tscn"
const SESSION_SUMMARY_SCENE: String = "res://scenes/progression/session_summary.tscn"
const PARENT_SETTINGS_SCENE: String = "res://scenes/parent/parent_settings.tscn"

const SFX_GENTLE_TAP: String = "gentle_tap"

## Camera framing. Set in code with `look_at_from_position()` rather than trusting a
## hand-written `Transform3D` in the .tscn -- an inverted pitch there previously pushed
## the baby, bottle and teddy entirely below the viewport. Keep these in sync with the
## `transform` on %Camera3D (the .tscn value only drives the editor preview).
const CAMERA_POSITION: Vector3 = Vector3(0.0, 0.95, 2.075)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.315, 0.175)

enum Mode { MISSION, LEGACY }

## How mission mode chooses what to play next. Explicit rather than implicit so
## that wiring up Free Play later is a one-line change.
##
##   * `STORY` -- the authored level order from `LevelSystem`: resume the saved
##     level, else the first incomplete unlocked level, else the start of the
##     journey, advancing through `get_next_level_id()`. This is what the game
##     ships in.
##   * `FREE_PLAY` -- the original random pick (`_pick_mission_id()`), kept
##     intact and still used as Story Mode's safety net. Nothing selects it yet;
##     a Free Play entry point only has to call
##     `set_progression_mode(ProgressionMode.FREE_PLAY)`.
enum ProgressionMode { STORY, FREE_PLAY }

@onready var _camera: Camera3D = %Camera3D
@onready var _baby_view: BabyView3D = %BabyView
@onready var _milk_bottle: MilkBottle = %MilkBottle
@onready var _teddy: Teddy = %Teddy
@onready var _ui_layer: CanvasLayer = $UI
@onready var _safe_area: Control = %SafeArea

@onready var _star_count_label: Label = %StarCountLabel
@onready var _prompt_label: Label = %PromptLabel
@onready var _thai_hint_label: Label = %ThaiHintLabel
@onready var _mic_button: Button = %MicButton
@onready var _listening_label: Label = %ListeningLabel
@onready var _encouragement_label: Label = %EncouragementLabel
@onready var _progress_dots: Control = %ProgressDots
@onready var _sticker_button: Button = %StickerButton
@onready var _next_button: Button = %NextButton
@onready var _level_chapter_label: Label = %LevelChapterLabel

var _mode: int = Mode.LEGACY
var _progression_mode: int = ProgressionMode.STORY

var _baby_state: BabyState = BabyState.new()
## Created only in legacy mode. A `Node` that is never added to the tree is
## never freed with the scene, so mission mode does not build one at all.
var _feed_activity: FeedActivity = null
var _reward_manager: RewardManager = RewardManager.new()

var _mouth_drop_zone: Area3D = null
var _hug_drop_zone: Area3D = null

var _library: Object = null
var _runner: Node = null
var _activity: Node = null
var _sticker_book: Object = null
var _celebration: Control = null

var _summary: Control = null
var _sticker_screen: Control = null
var _parent_settings: Control = null
var _parent_settings_open: bool = false

var _legacy_started: bool = false
var _last_mission_id: String = ""
## Built lazily and tolerated as null: every level feature below degrades to the
## pre-Phase-1 behaviour rather than breaking the room.
var _level_system: RefCounted = null
## Set by the summary's Next button so the next mission is the authored successor
## rather than the usual random pick. Cleared as soon as it is consumed.
var _forced_next_mission_id: String = ""
var _mission_new_stickers: Array = []
## What the chapter/level caption should read while the room is visible. Empty
## outside Story Mode's authored levels (legacy mode, or a plain mission), which
## hides the label rather than showing a blank frame.
var _level_caption: String = ""
var _task_speak_enabled: bool = false
var _happy_reaction_generation: int = 0


## Shows the Meshy baby instead of the procedural one, when it is switched on.
##
## The procedural `BabyView3D` is NOT removed -- it is hidden and kept as an
## invisible **socket proxy**. `get_mouth_position()` / `get_hug_position()` read
## `Marker3D.global_position`, and visibility does not affect a transform, so
## feeding and hugging still aim at exactly the right places while the child sees
## the new model. That matters because the Meshy baby has no rig, so it has no
## sockets of its own and could not otherwise be used for a caregiver activity at
## all.
##
## Everything else -- baby state, view states, rewards, drop zones -- keeps
## talking to `BabyView3D` exactly as before. This is a visual swap and nothing
## more, which is what makes it safe to switch on for an over-budget preview.
func _swap_in_baby_avatar() -> void:
	if not BabyAvatarScript.ENABLED:
		return
	var avatar: Node3D = BabyAvatarScript.new()
	if not bool(avatar.call("is_model_available")):
		# Not in this build (the raw exports are gitignored and excluded from
		# most iOS builds). Keep the procedural baby and say nothing to the child.
		avatar.free()
		return

	add_child(avatar)
	avatar.global_transform = _baby_view.global_transform
	if avatar.has_method("set_pose"):
		avatar.call("set_pose", "sitting")
	# Chapter 2's baby faces +Z while every other character faces -Z; the wrapper
	# names this as CHAPTER_2_YAW_DEG rather than leaving it to be rediscovered.
	if "CHAPTER_2_YAW_DEG" in BabyAvatarScript:
		avatar.rotate_y(deg_to_rad(BabyAvatarScript.CHAPTER_2_YAW_DEG))
	_baby_view.visible = false


func _ready() -> void:
	# Enables Area3D.input_event picking for touch/mouse without requiring
	# any project.godot edits (that file is owned by the foundation agent).
	get_viewport().physics_object_picking = true

	_setup_nursery_props()
	_swap_in_baby_avatar()

	# Guarantees the baby, bottle and teddy are actually framed, regardless of the
	# Transform3D stored in the scene file.
	_camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
	_camera.current = true

	add_child(_reward_manager)
	_reward_manager.star_awarded.connect(_on_star_awarded)
	_reward_manager.award_granted.connect(_on_award_granted)

	_sticker_book = StickerBookScript.create(_autoload("SaveService"))

	_celebration = CelebrationScript.new()
	_celebration.name = "Celebration"
	_safe_area.add_child(_celebration)

	_mic_button.pressed.connect(_on_mic_pressed)
	_sticker_button.pressed.connect(_on_sticker_button_pressed)
	_next_button.pressed.connect(_on_next_pressed)

	_connect_speech_service()

	_encouragement_label.visible = false
	_thai_hint_label.visible = false
	_listening_label.visible = false
	_level_chapter_label.visible = false
	_next_button.visible = false
	_progress_dots.call("clear")

	_set_star_count(_get_initial_stars())
	_setup_parent_settings()

	_library = ContentLibraryScript.create()
	if _has_playable_mission():
		_begin_mission_mode()
	else:
		push_warning("BabyRoom: no playable mission found; falling back to the legacy feedMilk loop")
		_begin_legacy_mode()


func _process(_delta: float) -> void:
	# Legacy mode only: in mission mode the ActivityScene keeps its own zones
	# glued to the baby. Cheap (two Vector3 reads/writes); keeps the drop zones
	# on the baby's mouth/chest even if BabyView3D's markers move (head tilt,
	# idle bob) instead of only ever sampling their position once at ready.
	if _mode == Mode.LEGACY:
		_update_drop_zone_positions()


## -- Mode selection -----------------------------------------------------------

func get_mode() -> int:
	return _mode


func get_progression_mode() -> int:
	return _progression_mode


## The Free Play hook. Story Mode is the default and the only thing wired to a
## button today; a Free Play entry point flips this one value and the random
## picker below takes over.
func set_progression_mode(progression_mode: int) -> void:
	_progression_mode = progression_mode


func _begin_mission_mode() -> void:
	_mode = Mode.MISSION
	_disable_legacy_objects()

	_runner = MissionRunnerScript.new()
	_runner.name = "MissionRunner"
	add_child(_runner)

	# Mission intro/outro phrases ("Good morning!", "Good night.") reach only a
	# Label otherwise -- invisible to a pre-reader, which is every player. The
	# speaker queues rather than interrupts and stays quiet for any line the
	# mode handler already spoke, so prompts never stutter or chop each other.
	PromptSpeakerScript.attach(_runner, get_node_or_null("/root/TtsService"))

	_runner.mission_started.connect(_on_mission_started)
	_runner.mission_progress.connect(_on_mission_progress)
	_runner.task_started.connect(_on_task_started)
	_runner.task_completed.connect(_on_task_completed)
	_runner.task_skipped.connect(_on_task_skipped)
	_runner.mission_completed.connect(_on_mission_completed)
	_runner.prompt_changed.connect(_on_mission_prompt_changed)
	_runner.encouragement.connect(_show_encouragement)
	_runner.speak_button_enabled.connect(_on_speak_button_enabled)

	_start_next_mission()


## The original hand-built feeding loop. Used when content/missions cannot be
## loaded, and as the destination if mission mode ever runs out of missions --
## either way the child still has a complete, rewarding game.
func _begin_legacy_mode() -> void:
	_mode = Mode.LEGACY
	_teardown_mission_mode()
	# Legacy mode is not part of the authored journey, so there is no chapter or
	# level to name. Cleared before the early return below, which is reached when
	# mission mode falls back a second time.
	_show_level_caption("")

	if _legacy_started:
		# Already wired (the mission system fell back to it a second time).
		# Re-connecting the signals would make every prompt and every star fire
		# twice, so just restart the loop.
		_restart_activity()
		return
	_legacy_started = true

	_feed_activity = FeedActivity.new()
	_feed_activity.name = "FeedActivity"

	_milk_bottle.visible = true
	_teddy.visible = true
	_milk_bottle.collision_layer = 1
	_teddy.collision_layer = 1

	add_child(_feed_activity)

	_mouth_drop_zone = _create_drop_zone("MouthDropZone")
	_hug_drop_zone = _create_drop_zone("HugDropZone")
	_update_drop_zone_positions()
	_milk_bottle.set_drop_zone(_mouth_drop_zone, DROP_ZONE_RADIUS)
	_teddy.set_drop_zone(_hug_drop_zone, DROP_ZONE_RADIUS)

	_milk_bottle.delivered.connect(_on_milk_delivered)
	_teddy.comforted.connect(_on_teddy_comforted)

	_feed_activity.setup(_baby_state, _baby_view)
	_feed_activity.state_changed.connect(_on_activity_state_changed)
	_feed_activity.activity_completed.connect(_on_activity_completed)
	_feed_activity.prompt_changed.connect(_on_legacy_prompt_changed)

	_progress_dots.call("clear")
	_next_button.visible = false
	_update_mic_visual()

	RewardManager.begin_round()
	_feed_activity.start()


func _teardown_mission_mode() -> void:
	# Order matters: the activity scene must go while the runner (and therefore
	# its mode handlers) is still alive to let go of the objects it spawned
	# under that scene.
	_free_activity_scene()
	if _runner != null:
		if _runner.has_method("cancel"):
			_runner.call("cancel")
		_runner.queue_free()
		_runner = null


## Mission mode owns the whole room, so the hand-placed bottle and teddy step
## aside completely: hidden, un-draggable, and off the physics layer the
## raycast fallback queries. That is the structural half of "feedMilk can never
## pay twice" -- the legacy loop simply is not there to report a completion.
func _disable_legacy_objects() -> void:
	for node: Node in [_milk_bottle, _teddy]:
		if node == null:
			continue
		if node.has_method("set_enabled"):
			node.call("set_enabled", false)
		node.set("visible", false)
		node.set("collision_layer", 0)
		node.set("input_ray_pickable", false)


## -- Missions -------------------------------------------------------------------

func _all_playable_mission_ids() -> Array:
	if _library == null or not _library.has_method("get_unlocked_missions"):
		return []

	var stars: int = _get_initial_stars()
	var ids: Array = []
	for entry: Variant in _library.call("get_unlocked_missions", stars):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var mission_id: String = String((entry as Dictionary).get("missionId", ""))
		if mission_id.is_empty():
			continue
		if _playable_task_count(mission_id) > 0:
			ids.append(mission_id)
	return ids


func _first_playable_mission_id() -> String:
	var ids: Array = _all_playable_mission_ids()
	if ids.is_empty():
		return ""
	return String(ids[0])


## Mission mode needs *something* to play. An authored Story level counts even
## when the legacy `unlockAtStars` listing would hide its mission, because
## Story Mode gates on level completion instead; a legacy-unlocked mission counts
## when the level layer is unavailable. Neither -> the legacy feeding loop.
func _has_playable_mission() -> bool:
	if not _pick_story_mission_id().is_empty():
		return true
	return not _first_playable_mission_id().is_empty()


## Tasks in `mission_id` that a child could actually finish by touch. Mirrors
## exactly what `MissionRunner` will accept, so the room never starts a mission
## that would immediately end with nothing to do.
func _playable_task_count(mission_id: String) -> int:
	if _library == null or not _library.has_method("get_mission_tasks"):
		return 0
	var count: int = 0
	for task: Variant in _library.call("get_mission_tasks", mission_id):
		if String(MissionRunnerScript.describe_unplayable(task, _library)).is_empty():
			count += 1
	return count


## FREE PLAY's picker: random among the unlocked ones, avoiding an immediate
## repeat so a child does not get the same routine twice in a row.
##
## Story Mode does not use this to choose a level -- it follows the authored
## order in `_pick_story_mission_id()` -- but it is still the safety net for when
## the authored order yields nothing playable, so the room can never come up
## empty. Free Play itself is not built yet; see `ProgressionMode`.
func _pick_mission_id() -> String:
	var ids: Array = _all_playable_mission_ids()
	if ids.is_empty():
		return ""

	var choices: Array = []
	for mission_id: Variant in ids:
		if String(mission_id) != _last_mission_id:
			choices.append(mission_id)
	if choices.is_empty():
		choices = ids

	return String(choices[randi() % choices.size()])


## STORY MODE's picker: the authored level order, never a random choice.
##
## Resume order:
##   1. the saved `currentLevel`, if it is unlocked and actually playable;
##   2. otherwise the first INCOMPLETE unlocked level, in authored order;
##   3. otherwise the first unlocked level, in authored order (the journey is
##      finished -- start it again rather than showing nothing).
##
## The unlocked set is derived from `levelCompleted`, so a child who skipped
## their way through a level still moves on. A level whose mission has no
## playable tasks is passed over rather than started, and "" means "no authored
## level can be played", which sends the caller to the Free Play picker and then
## to legacy mode -- never to an empty room.
func _pick_story_mission_id() -> String:
	var system: RefCounted = _ensure_level_system()
	if system == null:
		return ""

	var completed: Dictionary = system.call("load_completed_levels")
	var unlocked: PackedStringArray = system.call("compute_unlocks", completed)["levels"]
	if unlocked.is_empty():
		return ""

	var saved_level_id: String = _saved_current_level()
	if unlocked.has(saved_level_id):
		var resumed: String = _playable_mission_for_level(saved_level_id)
		if not resumed.is_empty():
			return resumed

	for level_id: String in unlocked:
		if bool(system.call("is_level_complete", level_id, completed)):
			continue
		var mission_id: String = _playable_mission_for_level(level_id)
		if not mission_id.is_empty():
			return mission_id

	for level_id: String in unlocked:
		var mission_id: String = _playable_mission_for_level(level_id)
		if not mission_id.is_empty():
			return mission_id

	return ""


## The mission a level runs, but only if it currently has something to play.
func _playable_mission_for_level(level_id: String) -> String:
	var system: RefCounted = _ensure_level_system()
	if system == null or level_id.is_empty():
		return ""
	var mission_id: String = String(system.call("get_mission_id_for_level", level_id))
	if mission_id.is_empty() or _playable_task_count(mission_id) <= 0:
		return ""
	return mission_id


func _saved_current_level() -> String:
	var save_service: Node = _autoload("SaveService")
	if save_service != null and save_service.has_method("get_current_level"):
		return String(save_service.call("get_current_level"))
	return ""


## Moves the resume pointer. Called when a story level starts (so closing the
## app mid-level comes back to it) and again when one finishes (so the pointer
## follows the authored order instead of parking on a level already played).
func _remember_current_level(level_id: String) -> void:
	if level_id.is_empty():
		return
	var save_service: Node = _autoload("SaveService")
	if save_service == null or not save_service.has_method("set_current_level"):
		return
	if save_service.has_method("get_current_level") \
			and String(save_service.call("get_current_level")) == level_id:
		return
	save_service.call("set_current_level", level_id)


## `preferred_mission_id` lets the summary drive the choice -- the authored next
## level, or the same level again for a replay. Empty falls back to whichever
## picker the current `ProgressionMode` owns. A preferred mission that turns out
## to be unplayable is ignored rather than started, so the child can never be
## dropped into an empty room.
func _start_next_mission(preferred_mission_id: String = "") -> void:
	if _mode != Mode.MISSION or _runner == null:
		return

	var mission_id: String = ""
	if not preferred_mission_id.is_empty() and _playable_task_count(preferred_mission_id) > 0:
		mission_id = preferred_mission_id
	elif _progression_mode == ProgressionMode.STORY:
		mission_id = _pick_story_mission_id()
		# The authored order came up empty (content missing, or every level
		# unplayable). Fall through to the random picker rather than stalling.
		if mission_id.is_empty():
			mission_id = _pick_mission_id()
	else:
		mission_id = _pick_mission_id()
	if mission_id.is_empty():
		# Content vanished under us. Rather than showing an empty room, hand the
		# child back the legacy feeding loop, which needs no content at all.
		push_warning("BabyRoom: no playable mission left; falling back to the legacy feedMilk loop")
		_begin_legacy_mode()
		return

	RewardManager.begin_round()
	var ledger: RefCounted = RewardManager.shared_ledger()
	if ledger != null and ledger.has_method("begin_session"):
		# Zeroes the session counters the summary reads. Claims are KEPT, so a
		# completion that already paid cannot pay again just because a new
		# mission started.
		ledger.call("begin_session")

	_mission_new_stickers = []
	_task_speak_enabled = false
	_hide_summary()
	_swap_activity_scene(_category_for_mission(mission_id))
	_set_baby_view_state("idle")
	_show_level_caption(mission_id)
	# Resume pointer: coming back to the app lands on the level being played now.
	_remember_current_level(_level_id_for_mission(mission_id))

	# Services are handed over explicitly rather than left to the handlers'
	# `/root/...` fallback, so a mode never depends on where it sits in the tree.
	var context: Dictionary = {
		"thaiHints": _thai_hints_enabled(),
		"tts": _autoload("TtsService"),
		"speech": _autoload("SpeechService"),
	}
	if _activity != null and _activity.has_method("build_context"):
		context = _activity.call("build_context", context)

	_last_mission_id = mission_id
	_runner.call("start_mission", mission_id, _library, context)


## -- Story Mode chapter/level caption ------------------------------------------
##
## The whole of Story Mode's UI, deliberately: a small label saying where the
## child is in the journey. No level-select map, no journey screen, no locked
## padlocks to stare at. It sits in the one free corner of the SafeArea, clear of
## the prompt bubble, the star counter, the sticker/next/speak buttons and the
## grown-up gear, and it is hidden whenever there is no authored level to name
## (legacy mode, or a plain mission) rather than showing an empty frame.

func _show_level_caption(mission_id: String) -> void:
	_level_caption = _level_caption_for_mission(mission_id)
	_refresh_level_caption()


func _refresh_level_caption() -> void:
	if _level_chapter_label == null:
		return
	_level_chapter_label.text = _level_caption
	_level_chapter_label.visible = not _level_caption.is_empty() and not _is_overlay_open()


func _level_caption_for_mission(mission_id: String) -> String:
	var level: RefCounted = _level_for_mission(mission_id)
	if level == null:
		return ""
	var level_title: String = String(level.call("get_title")).strip_edges()
	if level_title.is_empty():
		return ""
	var system: RefCounted = _ensure_level_system()
	var chapter_title: String = ""
	if system != null:
		var chapter: Dictionary = system.call("get_chapter", String(level.call("get_chapter_id")))
		chapter_title = String(chapter.get("title", "")).strip_edges()
	if chapter_title.is_empty():
		return level_title
	return "%s\n%s" % [chapter_title, level_title]


## The `LevelDefinition` behind a mission, but only when it is a real authored
## level. Null for anything else, which is what hides the caption.
func _level_for_mission(mission_id: String) -> RefCounted:
	var system: RefCounted = _ensure_level_system()
	if system == null or mission_id.is_empty():
		return null
	var level: RefCounted = system.call("get_level_for_mission", mission_id)
	if level == null or not bool(level.call("is_authored_level")):
		return null
	return level


func _level_id_for_mission(mission_id: String) -> String:
	var level: RefCounted = _level_for_mission(mission_id)
	if level == null:
		return ""
	return String(level.call("get_level_id"))


func _category_for_mission(mission_id: String) -> String:
	if _library == null or not _library.has_method("get_mission"):
		return ""
	var mission: Dictionary = _library.call("get_mission", mission_id)
	return String(mission.get("category", ""))


func _swap_activity_scene(category: String) -> void:
	_free_activity_scene()

	var path: String = String(ACTIVITY_SCENES.get(category, DEFAULT_ACTIVITY_SCENE))
	if not ResourceLoader.exists(path):
		path = DEFAULT_ACTIVITY_SCENE
	if not ResourceLoader.exists(path):
		return

	var packed: Resource = load(path)
	if packed == null or not (packed is PackedScene):
		return

	var scene: Node = (packed as PackedScene).instantiate()
	if scene == null:
		return
	add_child(scene)
	_activity = scene
	if _activity.has_method("attach_baby"):
		_activity.call("attach_baby", _baby_view)


## Puts the finished mission's props quietly away while the summary is up.
##
## Deliberately hides rather than frees: the last task's mode handler still
## holds references to the objects it spawned and will despawn them itself on
## its next `start()`. Freeing them here would leave that handler iterating
## dangling instances.
func _quiet_activity_objects() -> void:
	if _activity == null or not is_instance_valid(_activity):
		return
	_activity.set("visible", false)
	var anchor: Node = null
	if _activity.has_method("get_object_anchor"):
		anchor = _activity.call("get_object_anchor")
	if anchor == null:
		return
	for child: Node in anchor.get_children():
		if child.has_method("set_enabled"):
			child.call("set_enabled", false)


func _free_activity_scene() -> void:
	if _activity == null:
		return
	# MUST come first. `MissionRunner` caches one mode handler per mode for the
	# whole run, and each handler keeps references to the objects it spawned
	# under this scene's ObjectAnchor. Freeing the scene without letting the
	# handlers drop those references leaves them iterating dangling instances
	# the next time that mode comes round -- which is exactly the "previously
	# freed instance" crash this ordering prevents.
	_release_spawned_objects()
	if is_instance_valid(_activity):
		_activity.queue_free()
	_activity = null


func _release_spawned_objects() -> void:
	if _runner == null or not is_instance_valid(_runner):
		return
	# Mode handlers are children of the runner; `cancel()` despawns and clears.
	for child: Node in _runner.get_children():
		if child.has_method("cancel"):
			child.call("cancel")


## -- MissionRunner signals ---------------------------------------------------------

func _on_mission_started(_mission_id: String, total: int) -> void:
	_progress_dots.call("configure", total)


func _on_mission_progress(index: int, _total: int) -> void:
	_progress_dots.call("set_current", index)


func _on_task_started(_task_id: String, _mode_name: String) -> void:
	_clear_other_handlers_objects()
	_next_button.visible = true
	_hide_encouragement()
	_set_baby_view_state(_view_state_for_current_task())


## Clears the previous task's props off the table.
##
## `MissionRunner` keeps one cached handler per mode, and a handler only
## despawns its own objects when that same mode comes round again. Two
## consecutive tasks of different modes would therefore pile the old choices on
## top of the new ones at the same spawn points. Cancelling every handler except
## the one about to start leaves exactly the current task's objects on screen.
func _clear_other_handlers_objects() -> void:
	if _runner == null or not is_instance_valid(_runner):
		return
	var active: Node = null
	if _runner.has_method("get_handler"):
		active = _runner.call("get_handler")
	for child: Node in _runner.get_children():
		if child == active:
			continue
		if child.has_method("cancel"):
			child.call("cancel")


func _on_task_completed(task_id: String, stars: int) -> void:
	_progress_dots.call("mark_current_done")
	_play_happy_reaction()
	# The single writer. `RewardManager` routes this through the process-wide
	# `RewardLedger`, so a re-fired signal, a retry or a reloaded scene cannot
	# make the same task pay twice.
	_reward_manager.award(task_id, stars)


func _on_task_skipped(_task_id: String) -> void:
	# A skip looks exactly like a completion on the progress dots: the child sees
	# progress, never a mark against them.
	_progress_dots.call("mark_current_done")
	_next_button.visible = false


func _on_mission_completed(_mission_id: String, _stars_earned: int) -> void:
	# The bedtime routine ends on a calm low chime rather than the bright star
	# sound -- a gentle "good night" close instead of more excitement.
	if _mission_id.to_lower().contains("bedtime"):
		var sfx: Node = _autoload("Sfx")
		if sfx != null and sfx.has_method("play"):
			sfx.call("play", "bedtime_chime")

	_next_button.visible = false
	_task_speak_enabled = false
	_update_mic_visual()
	_progress_dots.call("clear")
	_quiet_activity_objects()
	_set_baby_view_state("happy")

	var ledger: RefCounted = RewardManager.shared_ledger()
	var session_stars: int = 0
	if ledger != null and ledger.has_method("get_session_stars"):
		session_stars = int(ledger.call("get_session_stars"))

	_show_summary(session_stars, _reward_manager.get_stars(), _mission_new_stickers, _rate_and_record_level(_mission_id))


## Rates the run that just ended, stores the level's best-ever rating and works
## out what the summary should offer next. Returns `{}` for a mission that is not
## an authored level, which leaves the summary exactly as it was before Phase 1.
##
## The two star currencies stay separate here: `RewardManager` owns lifetime task
## `stars` (stickers), and this owns per-level 0..3 (`starsByLevel`). Nothing adds
## them together -- see docs/PHASE1_CONTRACT.md.
func _rate_and_record_level(mission_id: String) -> Dictionary:
	var system: RefCounted = _ensure_level_system()
	if system == null or _runner == null:
		return {}

	var level: RefCounted = system.call("get_level_for_mission", mission_id)
	if level == null or not level.call("is_authored_level"):
		return {}
	var level_id: String = String(level.call("get_level_id"))
	if level_id.is_empty():
		return {}

	# The rating is honest: `get_awarded_task_ids()` holds only the tasks the child
	# genuinely completed -- a skipped task is never awarded -- so a level skipped
	# end to end rates 0 and is not flattered as a core success.
	var session: Dictionary = StarRulesScript.session(_runner.call("get_awarded_task_ids"))
	var rated: int = int(system.call("rate_session", level_id, session))

	# Completion is the separate fact, and it is unconditional: reaching the end
	# of the level IS completing it, however many tasks were skipped.
	# `apply_completion` records that and derives unlocks from it alone, so the
	# skip button -- the room's no-dead-end escape hatch -- can never lock a
	# child out, while a 0-star run still reads as 0 stars.
	#
	# Max-wins and idempotent inside `LevelSystem`, so a replay can only ever
	# raise a rating, and re-applying the same result changes nothing.
	var applied: Dictionary = system.call("apply_completion", level_id, rated)
	var best: int = int(applied.get("stars", rated))

	var next_level_id: String = String(system.call("get_next_level_id", level_id))
	var next_mission_id: String = ""
	if not next_level_id.is_empty():
		next_mission_id = String(system.call("get_mission_id_for_level", next_level_id))
		# An authored successor whose content cannot actually be played is worse
		# than no Next button at all.
		if _playable_task_count(next_mission_id) <= 0:
			next_mission_id = ""

	_forced_next_mission_id = next_mission_id

	# Story Mode's resume pointer follows the authored order. Without this a
	# child who closes the summary with the back button would be handed the level
	# they just played, over and over.
	if not next_mission_id.is_empty():
		_remember_current_level(next_level_id)

	return {
		"levelId": level_id,
		"levelTitle": level.call("get_title"),
		"levelStars": rated,
		"bestStars": best,
		"hasNextLevel": not next_mission_id.is_empty(),
	}


func _ensure_level_system() -> RefCounted:
	if _level_system != null:
		return _level_system
	if _library == null:
		return null
	_level_system = LevelSystemScript.create(_library)
	return _level_system


func _on_mission_prompt_changed(prompt: String, thai_hint: String) -> void:
	_prompt_label.text = prompt
	var hint: String = thai_hint if _thai_hints_enabled() else ""
	_thai_hint_label.text = hint
	_thai_hint_label.visible = not hint.strip_edges().is_empty()


func _on_speak_button_enabled(enabled: bool) -> void:
	_task_speak_enabled = enabled
	_update_mic_visual()


## The always-available way forward for a child who cannot read, cannot drag, or
## simply does not want this task. Worth no stars and carrying no penalty --
## `MissionRunner` just moves on to the next task.
func _on_next_pressed() -> void:
	_play_sfx(SFX_GENTLE_TAP)
	if _mode == Mode.MISSION and _runner != null:
		_runner.call("skip_current_task")


func _view_state_for_current_task() -> String:
	if _runner == null or not _runner.has_method("get_current_task"):
		return "idle"
	var task: Dictionary = _runner.call("get_current_task")
	match String(task.get("interaction", "")):
		"dragToMouth":
			return "hungry"
		"dragToHug":
			return "idle"
		_:
			return "idle"


func _play_happy_reaction() -> void:
	_set_baby_view_state("happy")
	_happy_reaction_generation += 1
	var generation: int = _happy_reaction_generation
	var timer: SceneTreeTimer = get_tree().create_timer(HAPPY_REACTION_SEC)
	timer.timeout.connect(_end_happy_reaction.bind(generation), CONNECT_ONE_SHOT)


func _end_happy_reaction(generation: int) -> void:
	if generation != _happy_reaction_generation or _mode != Mode.MISSION:
		return
	_set_baby_view_state(_view_state_for_current_task())


## -- Rewards ----------------------------------------------------------------------

func _on_star_awarded(total: int) -> void:
	_set_star_count(total)


## Fired only when the ledger really granted stars, so a refused duplicate
## celebrates nothing and unlocks nothing.
func _on_award_granted(_completion_id: String, granted: int, previous_total: int, total: int) -> void:
	var new_stickers: Array = []
	if _sticker_book != null and _library != null and _sticker_book.has_method("register_star_change"):
		# Already de-duplicated and persisted by the book, so a replayed star
		# transition celebrates nothing.
		new_stickers = _sticker_book.call("register_star_change", previous_total, total, _library)
	if not new_stickers.is_empty():
		_mission_new_stickers.append_array(new_stickers)

	# Celebration plays the star / sticker SFX itself (`Sfx.play`), keeping the
	# sound and the visuals in step.
	if _celebration != null and _celebration.has_method("celebrate"):
		_celebration.call("celebrate", granted, new_stickers)


## -- Overlays: summary, sticker book, parent settings -------------------------------

func _show_summary(stars_earned: int, total_stars: int, new_stickers: Array, level_result: Dictionary = {}) -> void:
	var summary: Control = _ensure_summary()
	if summary == null:
		# The summary scene is missing. Never dead-end on it: go straight into
		# the next mission instead of showing nothing. Deferred because this can
		# run inside `MissionRunner`'s own `mission_completed` emission, and
		# restarting the runner from inside its own signal would be re-entrant.
		call_deferred("_start_next_mission")
		return
	summary.call("reset")
	summary.call("show_summary", stars_earned, total_stars, new_stickers, level_result)
	summary.visible = true
	_refresh_input_blocking()


func _ensure_summary() -> Control:
	if _summary != null and is_instance_valid(_summary):
		return _summary
	_summary = _instance_overlay(SESSION_SUMMARY_SCENE)
	if _summary == null:
		return null
	if _summary.has_signal("play_again"):
		_summary.connect("play_again", _on_summary_play_again)
	if _summary.has_signal("next_level"):
		_summary.connect("next_level", _on_summary_next_level)
	if _summary.has_signal("closed"):
		_summary.connect("closed", _on_summary_closed)
	return _summary


func _hide_summary() -> void:
	if _summary != null and is_instance_valid(_summary):
		_summary.visible = false
	_refresh_input_blocking()


## Replay means *this* level again, not "some other level". `_last_mission_id` is
## still the run that just finished, and it is read before `_start_next_mission`
## overwrites it.
func _on_summary_play_again() -> void:
	_hide_summary()
	var replay_id: String = _last_mission_id
	_forced_next_mission_id = ""
	_start_next_mission(replay_id)


## Next advances to the authored successor. `_forced_next_mission_id` was already
## checked for playable content when the summary was built, and is consumed here
## so a later random pick cannot inherit it.
func _on_summary_next_level() -> void:
	_hide_summary()
	var next_id: String = _forced_next_mission_id
	_forced_next_mission_id = ""
	_start_next_mission(next_id)


## The summary's back button leads forward too: there is nowhere else to go, and
## a child must never be able to close their way into an empty screen.
func _on_summary_closed() -> void:
	_hide_summary()
	_forced_next_mission_id = ""
	_start_next_mission()


func _on_sticker_button_pressed() -> void:
	_play_sfx(SFX_GENTLE_TAP)
	var screen: Control = _ensure_sticker_screen()
	if screen == null:
		return
	screen.visible = true
	if screen.has_method("refresh"):
		screen.call("refresh")
	_refresh_input_blocking()


func _ensure_sticker_screen() -> Control:
	if _sticker_screen != null and is_instance_valid(_sticker_screen):
		return _sticker_screen
	_sticker_screen = _instance_overlay(STICKER_BOOK_SCENE)
	if _sticker_screen == null:
		return null
	if _sticker_screen.has_signal("closed"):
		_sticker_screen.connect("closed", _on_sticker_screen_closed)
	return _sticker_screen


func _on_sticker_screen_closed() -> void:
	if _sticker_screen != null and is_instance_valid(_sticker_screen):
		_sticker_screen.visible = false
	_refresh_input_blocking()


func _setup_parent_settings() -> void:
	_parent_settings = _instance_overlay(PARENT_SETTINGS_SCENE, true)
	if _parent_settings == null:
		return
	if _parent_settings.has_signal("opened"):
		_parent_settings.connect("opened", _on_parent_settings_opened)
	if _parent_settings.has_signal("closed"):
		_parent_settings.connect("closed", _on_parent_settings_closed)


func _on_parent_settings_opened() -> void:
	_parent_settings_open = true
	_refresh_input_blocking()


func _on_parent_settings_closed() -> void:
	_parent_settings_open = false
	# Thai hints / voice practice may have just changed.
	_update_mic_visual()
	_refresh_input_blocking()


## Instantiates an overlay scene under the `UI` CanvasLayer, keeping the parent
## settings gear as the last (topmost) child so the grown-up escape hatch is
## always reachable.
func _instance_overlay(path: String, visible_now: bool = false) -> Control:
	if not ResourceLoader.exists(path):
		push_warning("BabyRoom: overlay scene missing: %s" % path)
		return null
	var packed: Resource = load(path)
	if packed == null or not (packed is PackedScene):
		push_warning("BabyRoom: overlay scene is not a PackedScene: %s" % path)
		return null
	var node: Node = (packed as PackedScene).instantiate()
	if node == null or not (node is Control):
		push_warning("BabyRoom: overlay scene root is not a Control: %s" % path)
		if node != null:
			node.free()
		return null

	var overlay: Control = node as Control
	overlay.visible = visible_now
	_ui_layer.add_child(overlay)
	if _parent_settings != null and is_instance_valid(_parent_settings):
		_ui_layer.move_child(_parent_settings, -1)
	return overlay


func _is_overlay_open() -> bool:
	if _parent_settings_open:
		return true
	if _summary != null and is_instance_valid(_summary) and _summary.visible:
		return true
	if _sticker_screen != null and is_instance_valid(_sticker_screen) and _sticker_screen.visible:
		return true
	return false


## An open overlay must not let a stray tap reach the room behind it (one of the
## overlay backdrops deliberately passes touches through), so 3D picking and the
## raycast fallback are both switched off while one is up.
func _refresh_input_blocking() -> void:
	var blocked: bool = _is_overlay_open()
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.physics_object_picking = not blocked

	var room_visible: bool = not blocked
	_progress_dots.visible = room_visible and _progress_dots.call("get_total") > 0
	_sticker_button.visible = room_visible
	_refresh_level_caption()

	# The grown-up gear sits top-right, where a full-screen child overlay puts
	# its own controls. Tuck it away while one is up (but never while the
	# settings panel itself is open, or it could not be closed).
	if _parent_settings != null and is_instance_valid(_parent_settings):
		_parent_settings.visible = _parent_settings_open or not blocked

	if blocked:
		_next_button.visible = false
		_mic_button.visible = false
	else:
		_next_button.visible = _mode == Mode.MISSION and _runner != null \
				and bool(_runner.call("is_running"))
		_update_mic_visual()


## Autoload lookup that also works before the room is in the tree (absolute node
## paths are only resolvable from inside it). Everything here is optional: a
## missing autoload means a silent, touch-only room, never a crash.
func _autoload(autoload_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null(NodePath("/root/%s" % autoload_name))


func _get_initial_stars() -> int:
	var save_service: Node = _autoload("SaveService")
	if save_service != null and save_service.has_method("get_stars"):
		return int(save_service.get_stars())
	return 0


func _thai_hints_enabled() -> bool:
	var save_service: Node = _autoload("SaveService")
	if save_service != null and save_service.has_method("get_setting"):
		return bool(save_service.get_setting("thaiHints", true))
	return true


func _play_sfx(sfx_name: String) -> void:
	var sfx: Node = _autoload("Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", sfx_name)


func _set_baby_view_state(view_state: String) -> void:
	if _baby_view != null and _baby_view.has_method("set_view_state"):
		_baby_view.set_view_state(view_state)


func _connect_speech_service() -> void:
	var speech: Node = _autoload("SpeechService")
	if speech == null:
		return
	if speech.has_signal("recognized"):
		speech.recognized.connect(_on_speech_recognized)
	if speech.has_signal("recognition_failed"):
		speech.recognition_failed.connect(_on_speech_recognition_failed)
	if speech.has_signal("availability_changed"):
		speech.availability_changed.connect(_on_speech_availability_changed)
	if speech.has_signal("permission_result"):
		speech.permission_result.connect(_on_permission_result)
	if speech.has_signal("listening_started"):
		speech.listening_started.connect(_on_listening_started)
	if speech.has_signal("listening_stopped"):
		speech.listening_stopped.connect(_on_listening_stopped)


## -- Nursery set dressing (VISUAL-owned scene, loaded defensively) ---------

func _setup_nursery_props() -> void:
	if not ResourceLoader.exists(NURSERY_PROPS_PATH):
		return  # Not landed yet -- keep this scene's own fallback room geometry.
	var nursery_scene: Resource = load(NURSERY_PROPS_PATH)
	if nursery_scene == null or not (nursery_scene is PackedScene):
		return
	var nursery: Node = (nursery_scene as PackedScene).instantiate()
	add_child(nursery)
	move_child(nursery, 0)
	_remove_fallback_room_geometry()


func _remove_fallback_room_geometry() -> void:
	for node_name: String in FALLBACK_ROOM_NODE_NAMES:
		var node: Node = get_node_or_null(node_name)
		if node != null:
			node.queue_free()


## -- Drop zones (legacy mode only; positioned live from BabyView3D) ---------

func _create_drop_zone(node_name: String) -> Area3D:
	var zone: Area3D = Area3D.new()
	zone.name = node_name
	zone.input_ray_pickable = false
	zone.monitoring = false
	zone.monitorable = false
	zone.collision_layer = 0
	zone.collision_mask = 0
	add_child(zone)
	return zone


func _update_drop_zone_positions() -> void:
	var mouth: Vector3 = FALLBACK_MOUTH_POSITION
	var hug: Vector3 = FALLBACK_HUG_POSITION
	if _baby_view != null:
		if _baby_view.has_method("get_mouth_position"):
			mouth = _baby_view.get_mouth_position()
		if _baby_view.has_method("get_hug_position"):
			hug = _baby_view.get_hug_position()
	if _mouth_drop_zone != null:
		_mouth_drop_zone.global_position = mouth
	if _hug_drop_zone != null:
		_hug_drop_zone.global_position = hug


## -- Milk (legacy mode: tap or drag-to-mouth) ------------------------------

func _on_milk_delivered() -> void:
	if _feed_activity == null:
		return
	_feed_activity.on_milk_delivered()


## -- Teddy (comfort, no stars, not an activity) ------------------------

func _on_teddy_comforted() -> void:
	_set_baby_view_state("hugging")
	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("speak"):
		tts.speak(TEDDY_WORD)
		var love_timer: SceneTreeTimer = get_tree().create_timer(TEDDY_SPEAK_GAP_SEC)
		love_timer.timeout.connect(_speak_teddy_love, CONNECT_ONE_SHOT)
	var timer: SceneTreeTimer = get_tree().create_timer(TEDDY_REACTION_SEC)
	timer.timeout.connect(_on_teddy_reaction_finished, CONNECT_ONE_SHOT)


func _speak_teddy_love() -> void:
	var tts: Node = _autoload("TtsService")
	# interrupt=false so this never cuts off "Teddy!" if a slow backend is
	# still finishing it.
	if tts != null and tts.has_method("speak"):
		tts.speak(TEDDY_LOVE_PHRASE, false)


func _on_teddy_reaction_finished() -> void:
	var state: int = FeedActivity.State.IDLE if _feed_activity == null else _feed_activity.get_state()
	_set_baby_view_state(_view_state_for_activity_state(state))
	_teddy.animate_return_to_origin()


func _view_state_for_activity_state(state: int) -> String:
	match state:
		FeedActivity.State.HUNGRY, FeedActivity.State.AWAITING_INPUT, FeedActivity.State.PROMPTING_SPEECH:
			return "hungry"
		FeedActivity.State.DRINKING:
			return "drinking"
		FeedActivity.State.CELEBRATING:
			return "happy"
		_:
			return "idle"


## -- Mic (optional speech) --------------------------------------------

func _on_mic_pressed() -> void:
	var speech: Node = _autoload("SpeechService")
	if speech == null:
		_show_encouragement(ENCOURAGEMENT_TOUCH_HINT)
		return

	# Permission is only ever requested when the child taps Speak, never at
	# launch. Once granted, the mode handler does the listening so it can match
	# the transcript against the task it is actually running.
	if speech.has_method("has_permission") and bool(speech.has_permission()):
		_start_listening()
		return
	if speech.has_method("request_permission"):
		speech.request_permission()
		return
	_start_listening()


func _start_listening() -> void:
	if _mode == Mode.MISSION and _runner != null:
		_runner.call("request_listen")
		return
	var speech: Node = _autoload("SpeechService")
	if speech != null and speech.has_method("start_listening"):
		speech.start_listening()


func _on_permission_result(granted: bool) -> void:
	if granted:
		_start_listening()
	else:
		# Never a red X: point the child back at the touch path, which always works.
		_show_encouragement(ENCOURAGEMENT_TOUCH_HINT)


func _on_speech_recognized(text: String) -> void:
	if _mode == Mode.MISSION and _runner != null:
		_runner.call("on_transcript", text)
		return
	if _feed_activity == null:
		return
	_feed_activity.on_transcript(text)


func _on_speech_recognition_failed(_reason: String) -> void:
	# Never a red X / score -- just a gentle nudge. Touch remains available.
	_show_encouragement(ENCOURAGEMENT_TRY_AGAIN)


func _on_speech_availability_changed(_available: bool) -> void:
	_update_mic_visual()


func _on_listening_started() -> void:
	_listening_label.text = "I'm listening..."
	_listening_label.visible = true


func _on_listening_stopped() -> void:
	_listening_label.visible = false


## The Speak button is hidden -- not just greyed out -- whenever it would do
## nothing: no speech backend, voice practice switched off by a parent, an
## overlay on screen, or a task that has no spoken answer. A child poking a dead
## button learns the wrong lesson.
func _update_mic_visual() -> void:
	var speech: Node = _autoload("SpeechService")
	var available: bool = false
	if speech != null and speech.has_method("is_available"):
		available = bool(speech.is_available())

	var usable: bool = available and not _is_overlay_open()
	if _mode == Mode.MISSION:
		usable = usable and _task_speak_enabled

	_mic_button.visible = usable
	_mic_button.disabled = not usable
	if not usable:
		_listening_label.visible = false


## -- Legacy feed activity wiring ----------------------------------------------

func _on_activity_state_changed(state: int) -> void:
	var accepting: bool = (
		state == FeedActivity.State.HUNGRY
		or state == FeedActivity.State.AWAITING_INPUT
		or state == FeedActivity.State.PROMPTING_SPEECH
	)
	_milk_bottle.set_enabled(accepting)
	if state == FeedActivity.State.CELEBRATING:
		_show_encouragement(_pick_success_phrase())


func _pick_success_phrase() -> String:
	if _feed_activity == null:
		return ENCOURAGEMENT_GREAT
	var phrases: Array = _feed_activity.get_activity_data().get("successPhrases", [])
	if phrases.is_empty():
		return ENCOURAGEMENT_GREAT
	return String(phrases[randi() % phrases.size()])


func _on_legacy_prompt_changed(text: String) -> void:
	_prompt_label.text = text
	_update_legacy_thai_hint()


func _update_legacy_thai_hint() -> void:
	if _feed_activity == null:
		return
	var hint_text: String = String(_feed_activity.get_activity_data().get("thaiHint", ""))
	_thai_hint_label.visible = _thai_hints_enabled() and not hint_text.is_empty()
	_thai_hint_label.text = hint_text


func _on_activity_completed(activity_id: String, stars: int) -> void:
	_reward_manager.award(activity_id, stars)
	var timer: SceneTreeTimer = get_tree().create_timer(RESTART_DELAY_SEC)
	timer.timeout.connect(_restart_activity, CONNECT_ONE_SHOT)


func _restart_activity() -> void:
	if _mode != Mode.LEGACY or _feed_activity == null:
		return
	_baby_state.set_hunger(RESET_HUNGER_VALUE)
	_milk_bottle.reset_position()
	# A fresh round, so `feedMilk` can be earned again without ever reusing a
	# ledger key.
	RewardManager.begin_round()
	_feed_activity.start()


## -- Star counter ---------------------------------------------------------

func _set_star_count(total: int) -> void:
	_star_count_label.text = str(total)


## -- Encouragement --------------------------------------------------------

func _show_encouragement(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	_encouragement_label.text = text
	_encouragement_label.visible = true
	var timer: SceneTreeTimer = get_tree().create_timer(ENCOURAGEMENT_DISPLAY_SEC)
	timer.timeout.connect(_hide_encouragement, CONNECT_ONE_SHOT)


func _hide_encouragement() -> void:
	_encouragement_label.visible = false


## -- Explicit raycast fallback (belt-and-braces touch input) --------------
##
## Godot's built-in 3D physics picking (Area3D.input_event) should handle
## almost every tap, but this explicit fallback guarantees a missed pick
## never leaves the child stuck. Any event that reaches _unhandled_input was
## NOT already consumed by GUI controls or by a draggable's own
## input_event/_input handlers (they call set_input_as_handled() on success),
## so this never double-delivers.
func _unhandled_input(event: InputEvent) -> void:
	if _is_overlay_open():
		return

	var is_press: bool = false
	var screen_position: Vector2 = Vector2.ZERO

	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		is_press = mouse_event.pressed
		screen_position = mouse_event.position
	elif event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		is_press = touch_event.pressed
		screen_position = touch_event.position

	if not is_press:
		return

	_raycast_fallback(screen_position)


## Duck-typed on purpose: anything the ray hits that knows how to deliver itself
## gets the chance, so objects spawned at runtime from `content/objects.json`
## (`SpawnedObject`) are reachable through exactly the same fallback as the
## hand-placed `MilkBottle`/`Teddy`. Both guard internally against acting while
## the primary input path already owns the gesture, so this cannot double-fire.
func _raycast_fallback(screen_position: Vector2) -> void:
	if _camera == null:
		return

	var from: Vector3 = _camera.project_ray_origin(screen_position)
	var to: Vector3 = from + _camera.project_ray_normal(screen_position) * RAY_LENGTH

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return

	var collider: Object = result.get("collider")
	if collider == null:
		return
	if collider.has_method("try_deliver_from_raycast"):
		collider.call("try_deliver_from_raycast")
	elif collider.has_method("try_trigger_from_raycast"):
		collider.call("try_trigger_from_raycast")
