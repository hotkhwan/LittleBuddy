extends Node

## "A Day With Little Buddy" -- the Chapter 3 level loop.
##
## The house was navigable before this file existed, and completely without an
## objective: four rooms, a toddler, and nothing to do. This is the part that
## makes it a game. It is the HouseWorld's answer to `baby_room.gd`, and it is
## built from exactly the same pieces on purpose -- `MissionRunner` sequences the
## tasks, the mode handlers run them, `RewardManager`/`RewardLedger` pay for them
## and `LevelSystem` rates and records the level. Chapter 3 adds one thing:
## **the child has to go there first.**
##
## ## One task, start to finish
##
## ```
##   task_started
##     -> plan = HouseTaskPlan.describe(task)         data, not a special case
##     -> stage the row + the landing pad at the beat
##     -> the mode handler speaks the prompt
##     -> the child TAPS the target (or the floor, and then the target)
##     -> Little Buddy walks there and turns to face it     (interaction_ready)
##     -> the semantic action plays                         ("brushTeeth")
##     -> the task completes
##     -> RewardManager.award(taskId, stars)                one writer, one ledger
## ```
##
## Four task kinds come out of the content (see `house_task_plan.gd`), and the
## only difference between them is *when* the interaction unlocks:
##
##   `travel`  the door IS the task: the room transition completes it;
##   `goAndDo` arrive, act, done;
##   `deliver` arrive, THEN the objects wake up and one of them is dragged to
##             Little Buddy or to the furniture;
##   `choose`  no walking: pick the right object where you stand. These are the
##             `findIt`/`sayIt` beats, which is why **touch alone reaches 3/3**.
##
## ## Why there is no dead end
##
## Six independent ways forward, because a stuck four-year-old does not retry:
##
##   1. **Next** is on screen for the whole of every task. It completes the task
##      for zero stars and moves on -- `levelCompleted` and `starsByLevel` are
##      separate facts, so skipping can never lock a child out of the journey and
##      can never flatter them either.
##   2. **Assist**: nothing happens for `ASSIST_AFTER_SEC`, and Little Buddy
##      walks to the beat himself. Live tree only -- see `_arm_assist()`.
##   3. **Auto-routing**: a task whose target is in another room routes itself
##      through `RoomTransitionController`, door by door, round the ring. This is
##      what makes skipping the "walk to the kitchen" task harmless.
##   4. A **refused** transition restores control and re-arms the task; the child
##      is never left Disabled.
##   5. A wrong object is answered kindly by the mode handler, and `MissionRunner`
##      moves on by itself after three gentle misses.
##   6. The summary always appears; if its scene is missing the next level starts
##      instead of nothing at all.
##
## ## Lazy wiring / headless
##
## `_ready()` never fires in the headless `--script` runner, so everything is
## reached through `bind()` + `start()`, and the per-frame work lives in `step()`
## which `_process()` merely forwards to. A test drives a whole level by calling
## `step()` in the same loop it steps the character.

const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")
## The same runner, playing the day in the order it was authored. See the file.
const HouseMissionRunnerScript := preload("res://scripts/gameplay/house_mission_runner.gd")
const PromptSpeakerScript := preload("res://scripts/speech/prompt_speaker.gd")
const VocabularyReviewScript := preload("res://scripts/content/vocabulary_review.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const LevelSystemScript := preload("res://scripts/progression/level_system.gd")
const StarRulesScript := preload("res://scripts/progression/star_rules.gd")
const StickerBookScript := preload("res://scripts/progression/sticker_book.gd")
const RewardManagerScript := preload("res://scripts/rewards/reward_manager.gd")
const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")
const HouseStageScript := preload("res://scripts/gameplay/house_stage.gd")
const HouseHudScript := preload("res://scripts/gameplay/house_hud.gd")
const HouseRoute := preload("res://scripts/house/house_route.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

const SESSION_SUMMARY_SCENE: String = "res://scenes/progression/session_summary.tscn"

## The chapter this world plays. Chapters 1-2 are the Baby Room's and never come
## here; anything past 3 is not authored yet.
const HOUSE_CHAPTER_ID: String = "ch3"

## How long a child may do nothing before Little Buddy sets off by himself.
## Long enough not to steal the moment, short enough that a stuck child is not
## stuck for long.
const ASSIST_AFTER_SEC: float = 9.0

## The one semantic action the director never replays; see `_play_task_action()`.
const ACTION_WALK: String = "walk"

const PHRASE_LETS_GO: String = "Let's go!"
const PHRASE_THIS_WAY: String = "This way!"
const PHRASE_HERE_WE_ARE: String = "Here we are!"

signal level_started(level_id: String, mission_id: String, task_count: int)
signal task_plan_changed(task_id: String, kind: String)
signal level_finished(level_id: String, stars: int)

var _world: Node = null
var _character: Node = null
var _transition: Node = null
var _nav: Node = null

var _library: Object = null
var _system: RefCounted = null
var _sticker_book: Object = null
var _runner: Node = null
var _rewards: Node = null
var _stage: Node3D = null
var _hud: Control = null
var _summary: Control = null

var _bound: bool = false
var _running: bool = false
var _mission_id: String = ""
var _level_id: String = ""
var _last_mission_id: String = ""
var _forced_next_mission_id: String = ""
var _new_stickers: Array = []

var _plan: Dictionary = {}
## True once Little Buddy is standing where the task happens, which is what
## unlocks the objects. Always true for a task that needs no walk.
var _beat_reached: bool = false
var _task_done: bool = false
var _awaiting_action: bool = false
## Deferred completion. `task_started` is emitted BEFORE the mode handler starts,
## so a task that is already satisfied the moment it begins (the child is
## standing in the destination room already) cannot be completed inline -- the
## handler would not be listening yet. `step()` flushes it.
var _pending_complete: bool = false
var _route: Array = []
var _assist_generation: int = 0
var _summary_open: bool = false


## Stands in for `SaveService` where there is no tree to find it in -- a scene
## preview, or the headless test runner. Implements only the three methods the
## reward path actually calls, and keeps the total in memory so a star still
## counts on screen.
class DetachedSave extends RefCounted:
	var _stars: int = 0
	var _activities: Array = []

	func get_stars() -> int:
		return _stars

	func add_stars(amount: int) -> int:
		_stars = maxi(_stars + amount, 0)
		return _stars

	func mark_activity_completed(activity_id: String) -> void:
		if not _activities.has(activity_id):
			_activities.append(activity_id)

	func get_completed_activities() -> Array:
		return _activities.duplicate()


## -- Wiring --------------------------------------------------------------------

## Composition, not an autoload: the world hands itself in and this builds the
## rest. Idempotent.
func bind(world: Node) -> void:
	if _bound:
		return
	_bound = true
	_world = world
	if _world == null:
		return

	_character = _world.call("get_character")
	_transition = _world.call("get_transition_controller")
	_nav = _world.get_node_or_null("NavigationController")

	_library = ContentLibraryScript.create()
	_system = LevelSystemScript.create(_library)
	_sticker_book = StickerBookScript.create(_autoload("SaveService"))

	_stage = HouseStageScript.new()
	_stage.name = "HouseStage"
	_world.add_child(_stage)
	if _character is Node3D:
		_stage.call("bind_character", _character)

	_hud = HouseHudScript.new()
	var ui: Node = _world.get_node_or_null("UI")
	if ui != null:
		ui.add_child(_hud)
	else:
		add_child(_hud)
	_hud.call("build")
	_hud.connect("skip_pressed", _on_skip_pressed)
	_hud.connect("speak_pressed", _on_speak_pressed)

	_rewards = RewardManagerScript.new()
	_rewards.name = "RewardManager"
	add_child(_rewards)
	if not is_inside_tree():
		# A preview or the headless runner: there is no `/root/SaveService` to
		# resolve, and an absolute node path cannot even be LOOKED UP from outside
		# the active tree. Pin an in-memory stand-in so the star counter still
		# counts and the reward path stays quiet. A real run never takes this
		# branch, and must not -- it would silently stop persisting stars.
		_rewards.call("set_save_service", DetachedSave.new())
	_rewards.connect("star_awarded", _on_star_awarded)
	_rewards.connect("award_granted", _on_award_granted)
	_hud.call("set_stars", _rewards.call("get_stars"))

	_runner = HouseMissionRunnerScript.new()
	_runner.name = "MissionRunner"
	add_child(_runner)

	# Mission intro/outro phrases ("Good morning!", "Good night.") reach only a
	# Label otherwise -- invisible to a pre-reader, which is every player. The
	# speaker queues rather than interrupts and stays quiet for any line the
	# mode handler already spoke, so prompts never stutter or chop each other.
	PromptSpeakerScript.attach(_runner, get_node_or_null("/root/TtsService"))
	_runner.connect("mission_started", _on_mission_started)
	_runner.connect("mission_progress", _on_mission_progress)
	_runner.connect("task_started", _on_task_started)
	_runner.connect("task_completed", _on_task_completed)
	_runner.connect("task_skipped", _on_task_skipped)
	_runner.connect("mission_completed", _on_mission_completed)
	_runner.connect("prompt_changed", _on_prompt_changed)
	_runner.connect("encouragement", _on_encouragement)
	_runner.connect("speak_button_enabled", _on_speak_button_enabled)

	if _character != null:
		_character.connect("interaction_ready", _on_interaction_ready)
		_character.connect("action_finished", _on_action_finished)
		_character.connect("move_failed", _on_move_failed)
	if _transition != null:
		_transition.connect("transition_completed", _on_transition_completed)
		_transition.connect("transition_refused", _on_transition_refused)


func _process(delta: float) -> void:
	step(delta)


## The per-frame work, callable by hand. `_process()` does nothing else, so a
## headless test drives exactly the same code a device does.
func step(_delta: float = 0.0) -> void:
	if _stage != null:
		_stage.call("update_zones")
	_flush_pending_complete()
	_reconcile_objects()


## -- Session -------------------------------------------------------------------

## Starts (or resumes) the Chapter 3 journey. Safe to call twice.
func start() -> bool:
	if _world == null:
		return false
	if _running:
		return true
	return _start_level(_pick_story_mission_id())


func is_running() -> bool:
	return _running


func get_mission_id() -> String:
	return _mission_id


func get_level_id() -> String:
	return _level_id


func get_current_plan() -> Dictionary:
	return _plan.duplicate(true)


func get_runner() -> Node:
	return _runner


func get_stage() -> Node:
	return _stage


func get_hud() -> Control:
	return _hud


func get_reward_manager() -> Node:
	return _rewards


func get_level_system() -> RefCounted:
	return _system


func get_library() -> Object:
	return _library


func is_summary_open() -> bool:
	return _summary_open


## True once Little Buddy is standing where the current task happens.
func is_beat_reached() -> bool:
	return _beat_reached


## -- Level start -----------------------------------------------------------------

func _start_level(mission_id: String) -> bool:
	if mission_id.is_empty() or _runner == null:
		# Nothing authored is playable. The house stays walkable and warm rather
		# than showing an empty objective -- never a failure screen.
		if _hud != null:
			_hud.call("set_prompt", "Let's explore!", "")
			_hud.call("set_skip_visible", false)
		return false

	_mission_id = mission_id
	_last_mission_id = mission_id
	_level_id = _level_id_for_mission(mission_id)
	_new_stickers = []
	_task_done = false
	_beat_reached = false
	_pending_complete = false
	_route.clear()
	_plan = TaskPlan.empty(String(_world.call("get_current_room_id")))

	# A new scoring round, so the same task ids can pay again on a replay without
	# ever reusing a ledger key; the session counters the summary reads are zeroed
	# but the CLAIMS are kept, which is what stops a re-run paying twice.
	RewardManagerScript.begin_round()
	var ledger: RefCounted = RewardManagerScript.shared_ledger()
	if ledger != null and ledger.has_method("begin_session"):
		ledger.call("begin_session")

	_hide_summary()
	_place_at_level_start(mission_id)
	# One voice: the level's prompt. See `HouseWorld.set_status_visible()`.
	if _world.has_method("set_status_visible"):
		_world.call("set_status_visible", false)
	_hud.call("set_caption", _level_caption(mission_id))
	_hud.call("set_stars", _rewards.call("get_stars"))
	_hud.call("set_play_chrome_visible", true)
	_remember_current_level(_level_id)

	var context: Dictionary = _stage.call("build_context", {
		"library": _library,
		"thaiHints": _thai_hints_enabled(),
		"tts": _autoload("TtsService"),
		"speech": _autoload("SpeechService"),
		"review": _review_context(),
	})

	_running = true
	var started: bool = bool(_runner.call("start_mission", mission_id, _library, context))
	if not started:
		_running = false
	return started


## Puts the child where the level begins, using the mission's authored
## `roomPath` -- semantic room ids, never a coordinate. Getting Dressed starts in
## the bathroom because that is where Good Morning left him.
func _place_at_level_start(mission_id: String) -> void:
	var mission: Dictionary = {}
	if _library != null and _library.has_method("get_mission"):
		mission = _library.call("get_mission", mission_id)
	var path: Variant = mission.get("roomPath", [])
	if typeof(path) != TYPE_ARRAY or (path as Array).is_empty():
		return
	var room_id: String = String((path as Array)[0])
	if not bool(_world.call("has_room", room_id)):
		return
	_world.call("place_in_room", room_id, "default")
	if _character != null:
		_character.call("set_disabled", false)


## -- Per task ---------------------------------------------------------------------

func _on_mission_started(_mission_id_value: String, total: int) -> void:
	_hud.call("configure_progress", total)
	level_started.emit(_level_id, _mission_id, total)


func _on_mission_progress(index: int, _total: int) -> void:
	_hud.call("set_current", index)


## Runs BEFORE the mode handler starts, which is exactly what the stage needs:
## the choice row has to be in the right room before anything spawns into it.
func _on_task_started(task_id: String, _mode: String) -> void:
	var task: Dictionary = _runner.call("get_current_task")
	_plan = TaskPlan.describe(task, String(_world.call("get_current_room_id")))
	_task_done = false
	_beat_reached = not bool(_plan.get("needsWalk", false))
	_awaiting_action = false
	_pending_complete = false
	_route.clear()

	var focus_id: String = String(_plan.get("focusTargetId", ""))
	_stage.call("begin_task", _plan, _world_position_of(focus_id), _beat_stand_position())
	_hud.call("set_skip_visible", true)
	_hud.call("hide_encouragement")

	task_plan_changed.emit(task_id, String(_plan.get("kind", "")))
	_arm_task()


## Decides what the child has to do next, and is safe to call again at any time
## -- after a transition, after a refusal, after a stray walk. It never completes
## anything inline; it only ever asks for a walk or waits for a tap.
func _arm_task() -> void:
	if not _running or _task_done:
		return
	var walk_target: String = String(_plan.get("walkTargetId", ""))
	if walk_target.is_empty():
		_beat_reached = true
		return

	var here: String = String(_world.call("get_current_room_id"))
	_refresh_beat_marker()

	# Already in the room the door leads to: the journey the task asked for has
	# happened, however the child got there. Walking them back out through the
	# door and in again would be a pointless round trip.
	if TaskPlan.is_travel(_plan):
		if String(_plan.get("destinationRoomId", "")) == here:
			_pending_complete = true
			return

	var target_room: String = String(_plan.get("roomId", ""))
	if not target_room.is_empty() and target_room != here:
		_begin_route(target_room)
		return

	# The target is in this room. The child taps it; assist covers the rest.
	_arm_assist()


## Walks Little Buddy round the ring to `room_id`, one door at a time, through
## the SAME transition controller a tapped door uses. This is the recovery path
## for a task whose target is somewhere else -- after a skipped walk, or after
## the child wandered off through a door of their own choosing.
func _begin_route(room_id: String) -> void:
	var here: String = String(_world.call("get_current_room_id"))
	_route = HouseRoute.door_sequence(here, room_id)
	if _route.is_empty():
		_arm_assist()
		return
	_walk_to_next_door()


func _walk_to_next_door() -> void:
	if _route.is_empty():
		_arm_task()
		return
	var door_id: String = String(_route[0])
	if _character == null:
		return
	_character.call("set_disabled", false)
	if not bool(_character.call("move_to", door_id)):
		# The door is not registered (the child is not in that room after all).
		# Re-derive the route rather than standing still.
		_route.clear()
		_arm_assist()


## Little Buddy is standing at the beat, facing it.
func _reach_beat() -> void:
	if _beat_reached or _task_done:
		return
	_beat_reached = true
	_cancel_assist()
	_stage.call("show_beat_marker", null)
	var focus_id: String = String(_plan.get("focusTargetId", ""))
	_stage.call("begin_task", _plan, _world_position_of(focus_id), _beat_stand_position())

	if TaskPlan.is_go_and_do(_plan):
		# Nothing to choose: being here and doing it IS the task.
		if _play_task_action():
			_awaiting_action = true
		else:
			_pending_complete = true
		return
	# `deliver`: the objects wake up (see `_reconcile_objects`) and the prompt is
	# repeated so a child who walked a long way hears what to do again.
	_hud.call("show_encouragement", PHRASE_HERE_WE_ARE)


## Marks the spot the current task wants on the floor -- and only while the child
## still has to get there. A four-year-old cannot read "Walk to the bathroom" and
## the two doors of a room are identical from across it; this is the difference
## between an instruction and a puzzle.
func _refresh_beat_marker() -> void:
	if _stage == null:
		return
	if _task_done or _beat_reached or not bool(_plan.get("needsWalk", false)):
		_stage.call("show_beat_marker", null)
		return
	var walk_target: String = String(_plan.get("walkTargetId", ""))
	if String(_plan.get("roomId", "")) != String(_world.call("get_current_room_id")):
		# The beat is in another room: the loop is routing there, and a disc in a
		# room nobody can see would be nothing but a stray object in the distance.
		_stage.call("show_beat_marker", null)
		return
	_stage.call("show_beat_marker", _stand_position_of(walk_target))


func _play_task_action() -> bool:
	var action_name: String = String(_plan.get("actionName", ""))
	if action_name.is_empty() or _character == null:
		return false
	if action_name == ACTION_WALK:
		# The walk tasks declare `"characterAction": "walk"`, and walking is what
		# the child just did -- replaying it as a standing action would be a
		# toddler marching on the spot.
		return false
	# SEMANTIC only. Never an animation filename, never `set_target_position` --
	# `test_architecture_guard` is what keeps that true.
	return bool(_character.call("play_action", action_name))


## -- Character / world signals ------------------------------------------------------

func _on_interaction_ready(target_id: String) -> void:
	if not _running:
		return
	if _route.has(target_id):
		# A door on the auto-route: the transition controller is already acting on
		# this same signal. `_on_transition_completed` picks the route back up.
		return
	if TaskPlan.is_travel(_plan):
		return
	if target_id != String(_plan.get("walkTargetId", "")):
		return
	_reach_beat()


func _on_action_finished(action_name: String) -> void:
	if not _running or not _awaiting_action:
		return
	if action_name != String(_plan.get("actionName", "")):
		return
	_awaiting_action = false
	_pending_complete = true


## An unknown target usually means the child tapped something in a room they are
## no longer in, or content named a target that lives elsewhere. Route to it
## instead of doing nothing.
func _on_move_failed(target_id: String, reason: String) -> void:
	if not _running or _task_done:
		return
	if reason == "disabled":
		return
	if target_id == String(_plan.get("walkTargetId", "")):
		var target_room: String = String(_plan.get("roomId", ""))
		if not target_room.is_empty() and target_room != String(_world.call("get_current_room_id")):
			_begin_route(target_room)


func _on_transition_completed(room_id: String, _spawn_id: String) -> void:
	if not _running:
		return
	if not _route.is_empty():
		_route.remove_at(0)
		if not _route.is_empty():
			_walk_to_next_door()
			return
		_arm_task()
		return
	if TaskPlan.is_travel(_plan) and String(_plan.get("destinationRoomId", "")) == room_id:
		# The door WAS the task.
		if _play_task_action():
			# `walk` has no clip yet and simply times out; either way the task is
			# finished by arriving, so do not wait on the action.
			pass
		_pending_complete = true
		return
	# The child went somewhere of their own accord mid-task. Work out what the
	# task needs from here; never leave them in a room where nothing can happen.
	_arm_task()


## A refused transition is never a failure state for the child: the controller
## has already restored control on every exit path, and this re-arms the task so
## there is still something to do.
func _on_transition_refused(_room_id: String, _reason: String) -> void:
	if not _running:
		return
	_route.clear()
	if _character != null:
		_character.call("set_disabled", false)
	_hud.call("show_encouragement", PHRASE_THIS_WAY)
	_arm_task()


## -- Runner signals ------------------------------------------------------------------

func _on_prompt_changed(prompt: String, thai_hint: String) -> void:
	_hud.call("set_prompt", prompt, thai_hint if _thai_hints_enabled() else "")


func _on_encouragement(text: String) -> void:
	_hud.call("show_encouragement", text)


func _on_speak_button_enabled(enabled: bool) -> void:
	_hud.call("set_speak_visible", enabled and _speech_available() and not _summary_open)


## THE single writer. `MissionRunner` has already de-duplicated by task id;
## `RewardManager` routes this through the one process-wide `RewardLedger`, which
## refuses an id it has already paid for. There is no second reward path in the
## house -- a star can only arrive here.
func _on_task_completed(task_id: String, stars: int) -> void:
	_task_done = true
	_cancel_assist()
	_stage.call("show_beat_marker", null)
	_hud.call("mark_current_done")
	_rewards.call("award", task_id, stars)
	# Recorded BEFORE the action plays, while the handler's spawns are still
	# alive -- the exposure is "which objects were on screen", and after the
	# reaction they are gone.
	_record_vocabulary_exposure()
	if not _awaiting_action:
		# `goAndDo` already played its action on arrival; everything else plays it
		# now, as the reaction to what the child just did.
		_play_task_action()


## A skip fills its dot exactly like a completion and pays nothing at all. It
## must also leave a character who is not mid-walk, or the next task would start
## with Little Buddy sliding across the room on his own.
func _on_task_skipped(_task_id: String) -> void:
	_task_done = true
	_stage.call("show_beat_marker", null)
	_awaiting_action = false
	_pending_complete = false
	_route.clear()
	_cancel_assist()
	_hud.call("mark_current_done")
	if _character != null:
		_character.call("stop")
		_character.call("set_disabled", false)


func _on_mission_completed(mission_id: String, _stars_earned: int) -> void:
	_running = false
	_task_done = true
	_cancel_assist()
	_route.clear()
	_hud.call("set_skip_visible", false)
	_hud.call("set_speak_visible", false)
	_hud.call("clear_progress")
	_stage.call("clear_markers")
	if _character != null:
		_character.call("play_action", "celebrate")

	var level_result: Dictionary = _rate_and_record_level(mission_id)
	var session_stars: int = 0
	var ledger: RefCounted = RewardManagerScript.shared_ledger()
	if ledger != null and ledger.has_method("get_session_stars"):
		session_stars = int(ledger.call("get_session_stars"))

	level_finished.emit(String(level_result.get("levelId", _level_id)),
			int(level_result.get("levelStars", 0)))
	_show_summary(session_stars, int(_rewards.call("get_stars")), _new_stickers, level_result)


func _on_skip_pressed() -> void:
	if _running and _runner != null:
		_runner.call("skip_current_task")


func _on_speak_pressed() -> void:
	if not _running or _runner == null:
		return
	var speech: Node = _autoload("SpeechService")
	if speech != null and speech.has_method("has_permission") and not bool(speech.call("has_permission")):
		if speech.has_method("request_permission"):
			speech.call("request_permission")
			return
	_runner.call("request_listen")


func _on_star_awarded(total: int) -> void:
	_hud.call("set_stars", total)


func _on_award_granted(_completion_id: String, _granted: int, previous_total: int, total: int) -> void:
	if _sticker_book == null or _library == null:
		return
	if not _sticker_book.has_method("register_star_change"):
		return
	var earned: Array = _sticker_book.call("register_star_change", previous_total, total, _library)
	if not earned.is_empty():
		_new_stickers.append_array(earned)


## -- Objects --------------------------------------------------------------------------

## Keeps the mode handler's spawned objects in step with the plan.
##
## The handlers spawn a choice row for every task, because in the Baby Room every
## task has one. Here, `travel` and `goAndDo` beats are finished by walking and
## acting, so their objects are put away rather than left lying on the floor --
## and a `deliver` beat's objects stay asleep until Little Buddy has actually
## arrived, so "bring the toothbrush to the sink" cannot be answered from the
## other side of the house.
##
## Nothing is freed here: the handler owns its spawns and despawns them itself.
func _reconcile_objects() -> void:
	if _runner == null:
		return
	var handler: Node = _runner.call("get_handler")
	if handler == null or not is_instance_valid(handler):
		return
	if not handler.has_method("get_spawned_objects"):
		return
	var wanted_visible: bool = _running and bool(_plan.get("needsChoices", false))
	var wanted_enabled: bool = wanted_visible and _beat_reached and not _task_done
	for entry: Variant in handler.call("get_spawned_objects"):
		if not (entry is Node) or not is_instance_valid(entry):
			continue
		var node: Node = entry
		if bool(node.get("visible")) != wanted_visible:
			node.set("visible", wanted_visible)
		if node.has_method("set_enabled") and bool(node.get("drag_enabled")) != wanted_enabled:
			node.call("set_enabled", wanted_enabled)


func _flush_pending_complete() -> void:
	if not _pending_complete:
		return
	if _runner == null or not bool(_runner.call("is_running")):
		_pending_complete = false
		return
	var handler: Node = _runner.call("get_handler")
	if handler == null or not is_instance_valid(handler):
		return
	if handler.has_method("is_active") and not bool(handler.call("is_active")):
		# Already finished (or not started yet) -- try again next frame rather
		# than dropping the completion on the floor.
		if handler.has_method("is_completed") and bool(handler.call("is_completed")):
			_pending_complete = false
		return
	_pending_complete = false
	# The full reward, by touch. This is the same call the Baby Room's Next-style
	# affordance uses, and it is what guarantees no star anywhere needs a voice.
	_runner.call("complete_current_by_touch")


## -- Assist ----------------------------------------------------------------------------

## Arms the "nothing has happened for a while" walk.
##
## Deliberately a no-op outside a live tree: the headless runner has no frames,
## so a timer there would either never fire or (if it were made synchronous)
## rob every test of the manual path it is trying to prove. Tests call
## `assist_now()`.
func _arm_assist() -> void:
	_assist_generation += 1
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var generation: int = _assist_generation
	tree.create_timer(ASSIST_AFTER_SEC).timeout.connect(
		func() -> void:
			if generation == _assist_generation:
				assist_now(),
		CONNECT_ONE_SHOT
	)


func _cancel_assist() -> void:
	_assist_generation += 1


## Little Buddy goes to the beat by himself. Worth exactly the same as walking
## there after a tap -- this is a way forward, not a shortcut, and it only ever
## moves him: it never chooses an object and never answers a question.
func assist_now() -> void:
	if not _running or _task_done or _beat_reached:
		return
	var walk_target: String = String(_plan.get("walkTargetId", ""))
	if walk_target.is_empty() or _character == null:
		return
	var target_room: String = String(_plan.get("roomId", ""))
	if not target_room.is_empty() and target_room != String(_world.call("get_current_room_id")):
		_begin_route(target_room)
		return
	_hud.call("show_encouragement", PHRASE_LETS_GO)
	_character.call("set_disabled", false)
	_character.call("move_to", walk_target)


## -- Level rating and the summary --------------------------------------------------------

## The honest 0-3: only tasks the child genuinely completed count, so a level
## skipped end to end rates 0 -- while `apply_completion` still records it as
## COMPLETE, which is what keeps the skip button from ever becoming a lock.
func _rate_and_record_level(mission_id: String) -> Dictionary:
	if _system == null or _runner == null:
		return {}
	var level: RefCounted = _system.call("get_level_for_mission", mission_id)
	if level == null or not bool(level.call("is_authored_level")):
		return {}
	var level_id: String = String(level.call("get_level_id"))
	if level_id.is_empty():
		return {}

	var session: Dictionary = StarRulesScript.session(_runner.call("get_awarded_task_ids"))
	var rated: int = int(_system.call("rate_session", level_id, session))
	var applied: Dictionary = _system.call("apply_completion", level_id, rated)

	var next_level_id: String = String(_system.call("get_next_level_id", level_id))
	var next_mission_id: String = ""
	if not next_level_id.is_empty():
		next_mission_id = String(_system.call("get_mission_id_for_level", next_level_id))
		if _playable_task_count(next_mission_id) <= 0 or not _is_house_level(next_level_id):
			# An authored successor that this world cannot play is worse than no
			# Next button at all.
			next_mission_id = ""
	_forced_next_mission_id = next_mission_id
	if not next_mission_id.is_empty():
		_remember_current_level(next_level_id)

	return {
		"levelId": level_id,
		"levelTitle": level.call("get_title"),
		"levelStars": rated,
		"bestStars": int(applied.get("stars", rated)),
		"hasNextLevel": not next_mission_id.is_empty(),
	}


func _show_summary(stars_earned: int, total_stars: int, new_stickers: Array, level_result: Dictionary) -> void:
	var summary: Control = _ensure_summary()
	if summary == null:
		# Never dead-end on a missing overlay: go straight into the next level.
		_forced_next_mission_id = ""
		_start_next_level("")
		return
	_summary_open = true
	_set_world_input_enabled(false)
	_hud.call("set_play_chrome_visible", false)
	summary.call("reset")
	summary.call("show_summary", stars_earned, total_stars, new_stickers, level_result)
	summary.visible = true


func _ensure_summary() -> Control:
	if _summary != null and is_instance_valid(_summary):
		return _summary
	if not ResourceLoader.exists(SESSION_SUMMARY_SCENE):
		return null
	var packed: Resource = load(SESSION_SUMMARY_SCENE)
	if packed == null or not (packed is PackedScene):
		return null
	var node: Node = (packed as PackedScene).instantiate()
	if node == null or not (node is Control):
		if node != null:
			node.free()
		return null
	_summary = node as Control
	_summary.visible = false
	var ui: Node = _world.get_node_or_null("UI")
	if ui != null:
		ui.add_child(_summary)
	else:
		add_child(_summary)
	if _summary.has_signal("play_again"):
		_summary.connect("play_again", _on_summary_play_again)
	if _summary.has_signal("next_level"):
		_summary.connect("next_level", _on_summary_next_level)
	if _summary.has_signal("closed"):
		_summary.connect("closed", _on_summary_closed)
	return _summary


func _hide_summary() -> void:
	_summary_open = false
	if _summary != null and is_instance_valid(_summary):
		_summary.visible = false
	_set_world_input_enabled(true)


## The summary's back button, as an API. The overlay is another agent's scene, so
## anything that needs to dismiss it -- a parent leaving the app, a test -- says
## so here rather than reaching in and pressing a button by node path.
func dismiss_summary() -> void:
	if _summary_open:
		_on_summary_closed()


## The summary's Next, as an API. Same reason.
func advance_to_next_level() -> void:
	if _summary_open:
		_on_summary_next_level()


func _on_summary_play_again() -> void:
	# Latched on `_summary_open`. The three summary buttons emit once per press
	# with no debounce of their own, so two fast taps -- trivially easy for a
	# child -- otherwise ran `_start_next_level()` twice, calling
	# `begin_round()` and `start_mission()` again and restarting the level that
	# had just started. Not a dead end, but a wasted restart a child can trigger
	# in under a second.
	if not _summary_open:
		return
	var replay_id: String = _last_mission_id
	_forced_next_mission_id = ""
	_start_next_level(replay_id)


func _on_summary_next_level() -> void:
	# Latched on `_summary_open`. The three summary buttons emit once per press
	# with no debounce of their own, so two fast taps -- trivially easy for a
	# child -- otherwise ran `_start_next_level()` twice, calling
	# `begin_round()` and `start_mission()` again and restarting the level that
	# had just started. Not a dead end, but a wasted restart a child can trigger
	# in under a second.
	if not _summary_open:
		return
	var next_id: String = _forced_next_mission_id
	_forced_next_mission_id = ""
	_start_next_level(next_id)


## The back button leads forward too: there is nowhere else to go from here, and
## a child must never be able to close their way into an empty screen.
func _on_summary_closed() -> void:
	# Latched on `_summary_open`. The three summary buttons emit once per press
	# with no debounce of their own, so two fast taps -- trivially easy for a
	# child -- otherwise ran `_start_next_level()` twice, calling
	# `begin_round()` and `start_mission()` again and restarting the level that
	# had just started. Not a dead end, but a wasted restart a child can trigger
	# in under a second.
	if not _summary_open:
		return
	_forced_next_mission_id = ""
	_start_next_level("")


func _start_next_level(preferred_mission_id: String) -> void:
	_hide_summary()
	var mission_id: String = preferred_mission_id
	if mission_id.is_empty() or _playable_task_count(mission_id) <= 0:
		mission_id = _pick_story_mission_id()
	if mission_id.is_empty():
		mission_id = _last_mission_id
	_start_level(mission_id)


## While the summary is up, nothing in the room may be tapped and the child may
## not be walked -- and both are restored the moment it closes, which is why this
## is one function rather than two scattered calls.
func _set_world_input_enabled(enabled: bool) -> void:
	if _nav != null:
		_nav.set("taps_enabled", enabled)
	if _character != null:
		_character.call("set_disabled", not enabled)


## -- Level selection ------------------------------------------------------------------

## The authored Chapter 3 order, never a random pick:
##   1. the saved `currentLevel`, when it is a playable house level AND resuming
##      it does not skip the day (see below);
##   2. otherwise the first INCOMPLETE unlocked house level, chain before bonus;
##   3. otherwise the first unlocked house level (the day is done -- play it again).
##
## **The chapter's CHAIN comes before its bonus levels, and the resume pointer
## cannot override that.** `sayItChallenge` is tagged `ch3` but is not part of the
## day, so `LevelSystem` treats it as a bonus level that unlocks with the chapter.
## A saved pointer left on it -- which a real profile had -- opened Chapter 3 on
## eight "say the word" cards instead of on waking up, and because a bonus level
## has no successor in any chain, Next handed the same level back afterwards: the
## journey could never start. Caught by rendering the game, not by a test.
func _pick_story_mission_id() -> String:
	if _system == null:
		return ""
	var completed: Dictionary = _system.call("load_completed_levels")
	var unlocked: Array = []
	for level_id: String in (_system.call("compute_unlocks", completed)["levels"] as PackedStringArray):
		unlocked.append(level_id)

	var chain: Array = []
	for level_id: String in (_system.call("get_chapter_chain", HOUSE_CHAPTER_ID) as PackedStringArray):
		chain.append(level_id)
	var bonus: Array = []
	for level_id: String in (_system.call("get_levels_in_chapter", HOUSE_CHAPTER_ID) as PackedStringArray):
		if not chain.has(level_id):
			bonus.append(level_id)

	for level_id: Variant in resume_order(chain, bonus, unlocked, completed, _saved_current_level()):
		var mission_id: String = _playable_mission_for_level(String(level_id))
		if not mission_id.is_empty():
			return mission_id
	return ""


## The order the journey tries its levels in. PURE -- ids, an unlock list and a
## completion map -- so the rule can be asserted without a save file, a scene or
## a frame.
##
## The rule, in priority order:
##   1. the saved `currentLevel`, but ONLY if it is part of the day, or the whole
##      day is already finished;
##   2. the first level not yet completed, **chain before bonus**;
##   3. anything else that is open, so the house is never empty.
##
## Rule 1's condition is the interesting one. `sayItChallenge` is tagged `ch3` but
## is not in the chapter's chain, so `LevelSystem` unlocks it with the chapter as
## a bonus. A real profile had the resume pointer parked on it, which opened
## Chapter 3 on eight "say the word" cards instead of on waking up -- and since a
## bonus level has no successor in any chain, Next handed the same level straight
## back. The day could never start. Found by looking at a render, which is why it
## is now a rule with a test rather than an accident of ordering.
static func resume_order(
	chain: Array, bonus: Array, unlocked: Array, completed: Dictionary, saved_level_id: String
) -> Array:
	var ordered: Array = []
	for level_id: Variant in chain:
		if not ordered.has(String(level_id)):
			ordered.append(String(level_id))
	for level_id: Variant in bonus:
		if not ordered.has(String(level_id)):
			ordered.append(String(level_id))

	var open: Array = []
	for level_id: Variant in ordered:
		if unlocked.is_empty() or unlocked.has(String(level_id)):
			open.append(String(level_id))
	if open.is_empty():
		# A corrupt or empty unlock set. Opening the chapter beats an empty house.
		open = ordered.duplicate()

	var day_is_done: bool = true
	for level_id: Variant in chain:
		if not _is_completed(completed, String(level_id)):
			day_is_done = false
			break

	var priority: Array = []
	var saved: String = saved_level_id.strip_edges()
	# A pointer at a level that is already FINISHED is not a resume, it is a
	# repeat: with the whole day done it would hand the child the same level for
	# ever. Falling through starts the day again from the beginning, which is what
	# "play it again" should mean for a journey, not "replay level 15".
	if open.has(saved) and (chain.has(saved) or day_is_done) \
			and not _is_completed(completed, saved):
		priority.append(saved)
	for level_id: Variant in open:
		if not _is_completed(completed, String(level_id)) and not priority.has(String(level_id)):
			priority.append(String(level_id))
	for level_id: Variant in open:
		if not priority.has(String(level_id)):
			priority.append(String(level_id))
	return priority


## Matches `LevelSystem`'s own truthiness rule: `true`, or a v2-era star count.
static func _is_completed(completed: Dictionary, level_id: String) -> bool:
	if not completed.has(level_id):
		return false
	var value: Variant = completed[level_id]
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return float(value) >= 1.0
		_:
			return false


func _playable_mission_for_level(level_id: String) -> String:
	if _system == null or level_id.is_empty():
		return ""
	var mission_id: String = String(_system.call("get_mission_id_for_level", level_id))
	if mission_id.is_empty() or _playable_task_count(mission_id) <= 0:
		return ""
	return mission_id


func _is_house_level(level_id: String) -> bool:
	if _system == null:
		return false
	return (_system.call("get_levels_in_chapter", HOUSE_CHAPTER_ID) as PackedStringArray).has(level_id)


## Tasks a child could actually finish, mirroring exactly what `MissionRunner`
## will accept plus the house's own semantic-id rule, so a level is never started
## that would immediately end with nothing to do.
func _playable_task_count(mission_id: String) -> int:
	if _library == null or not _library.has_method("get_mission_tasks"):
		return 0
	var count: int = 0
	for task: Variant in _library.call("get_mission_tasks", mission_id):
		if not String(MissionRunnerScript.describe_unplayable(task, _library)).is_empty():
			continue
		var plan: Dictionary = TaskPlan.describe(task, "")
		if not String(TaskPlan.describe_unplayable_in_house(plan)).is_empty():
			continue
		count += 1
	return count


func _level_id_for_mission(mission_id: String) -> String:
	if _system == null:
		return ""
	var level: RefCounted = _system.call("get_level_for_mission", mission_id)
	if level == null:
		return ""
	return String(level.call("get_level_id"))


func _level_caption(mission_id: String) -> String:
	if _system == null:
		return ""
	var level: RefCounted = _system.call("get_level_for_mission", mission_id)
	if level == null or not bool(level.call("is_authored_level")):
		return ""
	var level_title: String = String(level.call("get_title")).strip_edges()
	if level_title.is_empty():
		return ""
	var chapter: Dictionary = _system.call("get_chapter", String(level.call("get_chapter_id")))
	var chapter_title: String = String(chapter.get("title", "")).strip_edges()
	if chapter_title.is_empty():
		return level_title
	return "%s\n%s" % [chapter_title, level_title]


## -- Services (all optional) --------------------------------------------------------

func _saved_current_level() -> String:
	var save_service: Node = _autoload("SaveService")
	if save_service != null and save_service.has_method("get_current_level"):
		return String(save_service.call("get_current_level"))
	return ""


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


func _thai_hints_enabled() -> bool:
	var save_service: Node = _autoload("SaveService")
	if save_service != null and save_service.has_method("get_setting"):
		return bool(save_service.call("get_setting", "thaiHints", true))
	return true


func _speech_available() -> bool:
	var speech: Node = _autoload("SpeechService")
	if speech == null or not speech.has_method("is_available"):
		return false
	return bool(speech.call("is_available"))


## Review state for the level being played. Built once per level, read by
## `ModeHandler.build_review_choice_ids()` through the mission context.
func _review_context() -> Dictionary:
	var save_service: Node = _autoload("SaveService")
	var profile: Dictionary = {}
	if save_service != null and save_service.has_method("get_profile"):
		profile = save_service.call("get_profile")
	var ordinal: int = 0
	if _system != null:
		ordinal = int(_system.call("get_level_ordinal", _level_id))
	return {
		"progress": VocabularyReviewScript.read_progress(profile),
		"levelOrdinal": ordinal,
		"reviewWeight": VocabularyReviewScript.read_review_weight(profile),
	}


## Every object that was on screen counts as an exposure; the one the child chose
## counts as a success. This is the entire data model -- three numbers per word,
## deliberately not a leech algorithm, because drilling a word a child struggles
## with is exactly how a game starts to feel like a test.
func _record_vocabulary_exposure() -> void:
	var save_service: Node = _autoload("SaveService")
	if save_service == null or not save_service.has_method("get_profile") \
			or not save_service.has_method("set_setting"):
		return
	if _runner == null or not is_instance_valid(_runner):
		return
	var handler: Node = _runner.call("get_handler")
	if handler == null or not is_instance_valid(handler) \
			or not handler.has_method("get_spawned_objects"):
		return

	var shown: Array = []
	for node: Variant in handler.call("get_spawned_objects"):
		if node is Node and is_instance_valid(node):
			shown.append(String((node as Node).get("object_id")))
	if shown.is_empty():
		return

	var ordinal: int = 0
	if _system != null:
		ordinal = int(_system.call("get_level_ordinal", _level_id))
	var chosen: Array = []
	if handler.has_method("get_target_object_id"):
		chosen.append(String(handler.call("get_target_object_id")))

	var profile: Dictionary = save_service.call("get_profile")
	var updated: Dictionary = VocabularyReviewScript.record_row(
			VocabularyReviewScript.read_progress(profile), shown, ordinal, chosen)
	save_service.call("set_setting", VocabularyReviewScript.PROGRESS_KEY, updated)


func _autoload(autoload_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null(NodePath("/root/%s" % autoload_name))


## -- Spatial lookups (the ONE place the director touches the scene) -----------------
##
## Semantic id in, world position out. The plan, the runner and the content never
## see a `Vector3`; the stage needs one to lay a row of objects out, and this is
## the only bridge between the two.

func _world_position_of(semantic_id: String) -> Variant:
	var target: Node = _target_node(semantic_id)
	if target == null:
		return null
	return SpatialUtil.world_position(target as Node3D)


## Where the child will be standing when this task's beat happens, or null for
## "wherever he already is" -- which is the right answer for a task that asks for
## no walk, and is what puts a dressing row at the toddler's own feet instead of
## across the room at the wardrobe.
func _beat_stand_position() -> Variant:
	if not bool(_plan.get("needsWalk", false)):
		return null
	return _stand_position_of(String(_plan.get("walkTargetId", "")))


func _stand_position_of(semantic_id: String) -> Variant:
	var target: Node = _target_node(semantic_id)
	if target == null or not target.has_method("describe"):
		return null
	var here: Vector3 = Vector3.ZERO
	if _character is Node3D:
		here = SpatialUtil.world_position(_character as Node3D)
	var info: Dictionary = target.call("describe", here)
	var stand: Variant = info.get("standPosition", null)
	return stand if stand is Vector3 else null


func _target_node(semantic_id: String) -> Node:
	if semantic_id.strip_edges().is_empty() or _world == null:
		return null
	var target: Node = _world.call("get_target_by_semantic_id", semantic_id)
	if target is Node3D:
		return target
	return null
