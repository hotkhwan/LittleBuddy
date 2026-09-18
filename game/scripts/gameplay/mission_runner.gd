class_name MissionRunner
extends Node

## Runs one mission -- a 5-8 task routine from `content/missions/missions.json` --
## by dispatching each task to the mode handler for its `mode` and accumulating
## stars.
##
## ## Public API (what the Baby Room wires to)
##
## ```gdscript
## func start_mission(mission_id: String, library: Object, context: Dictionary = {}) -> bool
## func cancel() -> void
## func on_object_chosen(object_id: String) -> void   # tap / drag delivery
## func on_transcript(text: String) -> void           # SpeechService.recognized
## func request_listen() -> void                      # Speak button
## func complete_current_by_touch() -> void           # guaranteed forward path
## func skip_current_task() -> void                   # gentle escape hatch
##
## signal mission_started(mission_id: String, total: int)
## signal mission_progress(index: int, total: int)    # 1-based index
## signal task_started(task_id: String, mode: String)
## signal task_completed(task_id: String, stars: int)
## signal task_skipped(task_id: String)
## signal mission_completed(mission_id: String, stars_earned: int)
## signal prompt_changed(prompt: String, thai_hint: String)
## signal encouragement(text: String)
## signal speak_button_enabled(enabled: bool)
## ```
##
## ## No double awards -- three independent layers
##
##   1. `DraggableObject` latches delivery per gesture (`_delivered_this_drag`)
##      and latches the owning pointer, so mashing two fingers or re-entering the
##      drop zone inside one gesture cannot fire twice.
##   2. `ModeHandler._succeed()` latches `_completed`, so a handler emits
##      `task_completed` at most once per `start()`.
##   3. `MissionRunner._award()` -- the authoritative guard -- keys every award by
##      `taskId` in `_awarded_task_ids`. A repeat of the SAME task id, from any
##      source whatsoever, adds zero stars and re-emits nothing.
##
## Stars are deliberately NOT written to `SaveService` here: the Baby Room already
## owns persistence through `RewardManager`. Connect `task_completed` to
## `RewardManager.award(task_id, stars)` so there is exactly one writer.
##
## ## No dead ends -- by construction
##
##   - Every task is completable by touch alone (see `ModeHandler`).
##   - A task that content cannot support (unknown mode, missing object) is
##     detected by `describe_unplayable()` and skipped immediately instead of
##     being presented and then being impossible.
##   - After `MAX_GENTLE_ATTEMPTS` kind misses the runner moves on by itself with
##     "Let's try another one!" -- worth 0 stars, never a punishment.
##   - `skip_current_task()` is always available to the UI.
##   - An empty/unknown mission still emits `mission_completed`, so a caller
##     waiting on that signal can never hang.

const MODE_SCRIPTS: Dictionary = {
	"findIt": "res://scripts/gameplay/find_it_mode.gd",
	"sayIt": "res://scripts/gameplay/say_it_mode.gd",
	"followInstruction": "res://scripts/gameplay/follow_instruction_mode.gd",
}

const TASK_PICKER_SCRIPT_PATH: String = "res://scripts/content/task_picker.gd"
const DROP_ZONE_SCRIPT_PATH: String = "res://scripts/gameplay/drop_zone.gd"

## How many gentle misses before the runner offers the next task instead. Kept
## small: a stuck child disengages long before a bored one does.
const MAX_GENTLE_ATTEMPTS: int = 3

## Breathing room for the celebration / TTS before the next prompt. Bypassed
## entirely when the runner is not inside a SceneTree (unit tests), which keeps
## the whole mission loop synchronous and deterministic there.
const TASK_GAP_SEC: float = 1.6
const SKIP_GAP_SEC: float = 1.0

const MOVE_ON_PHRASE: String = "Let's try another one!"

signal mission_started(mission_id: String, total: int)
signal mission_progress(index: int, total: int)
signal task_started(task_id: String, mode: String)
signal task_completed(task_id: String, stars: int)
signal task_skipped(task_id: String)
signal mission_completed(mission_id: String, stars_earned: int)
signal prompt_changed(prompt: String, thai_hint: String)
signal encouragement(text: String)
signal speak_button_enabled(enabled: bool)

var _mission_id: String = ""
var _mission: Dictionary = {}
var _tasks: Array = []
var _index: int = -1
var _running: bool = false
var _stars_earned: int = 0
var _awarded_task_ids: Dictionary = {}
var _gentle_attempts: int = 0
var _advancing: bool = false

var _library: Object = null
var _context: Dictionary = {}
var _handlers: Dictionary = {}
var _handler: Node = null
var _picker: Object = null
var _seed: int = 0


## -- Lifecycle -------------------------------------------------------------------

## Reproducible task ordering + choice layout, for tests and for a "replay this
## mission exactly" debug path.
func set_seed(seed_value: int) -> void:
	_seed = seed_value


## Starts `mission_id` from `library`. Returns false when the mission resolves to
## no playable tasks -- but still emits `mission_completed`, so a caller awaiting
## that signal is never left hanging.
func start_mission(mission_id: String, library: Object, context: Dictionary = {}) -> bool:
	cancel()

	_library = library
	_context = context.duplicate()
	if not _context.has("library") and library != null:
		_context["library"] = library

	_mission_id = mission_id
	_mission = {}
	if library != null and library.has_method("get_mission"):
		_mission = library.get_mission(mission_id)

	_tasks = _ordered_tasks(mission_id, library)
	_stars_earned = 0
	_awarded_task_ids = {}
	_index = -1
	_gentle_attempts = 0

	if _tasks.is_empty():
		_running = false
		mission_completed.emit(_mission_id, 0)
		return false

	_running = true
	mission_started.emit(_mission_id, _tasks.size())
	var intro: String = String(_mission.get("introPhrase", ""))
	if not intro.is_empty():
		prompt_changed.emit(intro, String(_mission.get("thaiTitle", "")))
	_advance()
	return true


func cancel() -> void:
	_running = false
	_advancing = false
	if _handler != null and _handler.has_method("cancel"):
		_handler.call("cancel")
	_handler = null


## -- Forwarded child input -------------------------------------------------------

func on_object_chosen(object_id: String) -> void:
	if _handler != null and _handler.has_method("on_object_chosen"):
		_handler.call("on_object_chosen", object_id)


func on_transcript(text: String) -> void:
	if _handler != null and _handler.has_method("on_transcript"):
		_handler.call("on_transcript", text)


func request_listen() -> void:
	if _handler != null and _handler.has_method("request_listen"):
		_handler.call("request_listen")


## Would `text` satisfy the task currently on screen?
##
## A pure QUERY -- it never advances anything, never awards and never speaks. It
## exists so the speech feedback panel can show "Great!" the moment a child is
## understood, instead of only echoing the words back and leaving them to guess
## whether it counted. The mode still owns what actually happens next; this only
## answers the question.
func transcript_matches_current(text: String) -> bool:
	if _handler == null or not _handler.has_method("matches_transcript"):
		return false
	return bool(_handler.call("matches_transcript", text))


## The guaranteed forward path: completes the current task with its full reward
## using touch alone. Wire this to any "I did it" affordance.
func complete_current_by_touch() -> void:
	if _handler != null and _handler.has_method("complete_by_touch"):
		_handler.call("complete_by_touch")


## Moves on without a reward and without any negative feedback.
func skip_current_task() -> void:
	if not _running or _advancing:
		return
	var task_id: String = get_current_task_id()
	if _handler != null and _handler.has_method("cancel"):
		_handler.call("cancel")
	_handler = null
	task_skipped.emit(task_id)
	_advancing = true
	_delay(SKIP_GAP_SEC, _advance)


## -- Queries ---------------------------------------------------------------------

func is_running() -> bool:
	return _running


func get_mission_id() -> String:
	return _mission_id


func get_task_count() -> int:
	return _tasks.size()


## 1-based position in the mission, or 0 before the first task.
func get_current_index() -> int:
	return _index + 1


func get_current_task() -> Dictionary:
	if _index < 0 or _index >= _tasks.size():
		return {}
	return (_tasks[_index] as Dictionary).duplicate(true)


func get_current_task_id() -> String:
	return String(get_current_task().get("taskId", ""))


func get_stars_earned() -> int:
	return _stars_earned


func get_awarded_task_ids() -> Array:
	return _awarded_task_ids.keys()


func get_handler() -> Node:
	return _handler


func get_tasks() -> Array:
	var copy: Array = []
	for task: Variant in _tasks:
		copy.append((task as Dictionary).duplicate(true))
	return copy


## Total stars a flawless run of this mission is worth. Counts each DISTINCT
## `taskId` once, matching `_award()`'s guarantee exactly.
static func expected_stars(tasks: Array) -> int:
	var seen: Dictionary = {}
	var total: int = 0
	for entry: Variant in tasks:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var task: Dictionary = entry
		var task_id: String = String(task.get("taskId", ""))
		if task_id.is_empty() or seen.has(task_id):
			continue
		seen[task_id] = true
		total += _reward_stars(task)
	return total


## -- Playability -------------------------------------------------------------------

## "" when the task can be played to completion by touch alone; otherwise a
## human-readable reason. Pure, so the tests can sweep every shipped mission.
static func describe_unplayable(task: Variant, library: Object = null) -> String:
	if typeof(task) != TYPE_DICTIONARY:
		return "task is not a dictionary"
	var task_dict: Dictionary = task

	var task_id: String = String(task_dict.get("taskId", ""))
	if task_id.is_empty():
		return "task has no 'taskId'"

	var mode: String = String(task_dict.get("mode", ""))
	if not MODE_SCRIPTS.has(mode):
		return "task '%s' has unknown mode '%s'" % [task_id, mode]

	var object_id: String = String(task_dict.get("objectId", ""))
	if object_id.is_empty():
		return "task '%s' has no 'objectId' to touch" % task_id
	if library != null and library.has_method("has_object") and not library.has_object(object_id):
		return "task '%s' references unknown object '%s'" % [task_id, object_id]

	var interaction: String = String(task_dict.get("interaction", ""))
	var drop_zone: GDScript = load(DROP_ZONE_SCRIPT_PATH) as GDScript
	if drop_zone != null and not bool(drop_zone.is_known_interaction(interaction)):
		return "task '%s' uses interaction '%s', which maps to no drop zone" % [task_id, interaction]

	if _reward_stars(task_dict) < 0:
		return "task '%s' has a negative reward" % task_id

	return ""


## -- Internals ---------------------------------------------------------------------

func _ordered_tasks(mission_id: String, library: Object) -> Array:
	var raw: Array = []
	if library != null and library.has_method("get_mission_tasks"):
		raw = library.get_mission_tasks(mission_id)

	var playable: Array = []
	for task: Variant in raw:
		if describe_unplayable(task, library).is_empty():
			playable.append(task)

	var picker: Object = _get_picker()
	if picker != null and picker.has_method("shuffle_sequence"):
		var shuffled: Array = picker.call("shuffle_sequence", playable)
		if not shuffled.is_empty():
			return shuffled
	return playable


func _get_picker() -> Object:
	if _picker != null:
		return _picker
	var script: GDScript = load(TASK_PICKER_SCRIPT_PATH) as GDScript
	if script == null:
		return null
	_picker = script.new(_seed)
	return _picker


func _advance() -> void:
	_advancing = false
	if not _running:
		return

	_index += 1
	if _index >= _tasks.size():
		_finish()
		return

	var task: Dictionary = _tasks[_index]
	var reason: String = describe_unplayable(task, _library)
	if not reason.is_empty():
		# Belt and braces: `_ordered_tasks()` already filtered these out. Never
		# present a task that cannot be finished -- move straight past it.
		push_warning("MissionRunner: skipping unplayable task -- %s" % reason)
		task_skipped.emit(String(task.get("taskId", "")))
		_advance()
		return

	_gentle_attempts = 0
	mission_progress.emit(_index + 1, _tasks.size())

	_handler = _handler_for_mode(String(task.get("mode", "")))
	if _handler == null:
		task_skipped.emit(String(task.get("taskId", "")))
		_advance()
		return

	task_started.emit(String(task.get("taskId", "")), String(task.get("mode", "")))
	_handler.call("start", task, _context)


func _finish() -> void:
	_running = false
	_handler = null
	var outro: String = String(_mission.get("outroPhrase", ""))
	if not outro.is_empty():
		prompt_changed.emit(outro, String(_mission.get("thaiTitle", "")))
	mission_completed.emit(_mission_id, _stars_earned)


func _handler_for_mode(mode: String) -> Node:
	if _handlers.has(mode):
		return _handlers[mode]
	if not MODE_SCRIPTS.has(mode):
		return null
	var script: GDScript = load(String(MODE_SCRIPTS[mode])) as GDScript
	if script == null:
		return null

	var handler: Node = script.new()
	handler.name = "%sHandler" % mode
	if _seed != 0 and handler.has_method("set_seed"):
		handler.call("set_seed", _seed)
	handler.connect("task_completed", _on_task_completed)
	handler.connect("task_failed_gently", _on_task_failed_gently)
	handler.connect("prompt_changed", _on_prompt_changed)
	handler.connect("encouragement", _on_encouragement)
	handler.connect("speak_button_enabled", _on_speak_button_enabled)
	add_child(handler)
	_handlers[mode] = handler
	return handler


func _on_task_completed(task_id: String, stars: int) -> void:
	if not _running or _advancing:
		return
	_award(task_id, stars)
	_advancing = true
	_delay(TASK_GAP_SEC, _advance)


## THE authoritative single-award guard. Everything that could ever grant a star
## goes through here, and a `taskId` can only pass once per mission.
func _award(task_id: String, stars: int) -> int:
	if task_id.is_empty():
		return 0
	if _awarded_task_ids.has(task_id):
		return 0
	_awarded_task_ids[task_id] = true
	var granted: int = maxi(0, stars)
	_stars_earned += granted
	task_completed.emit(task_id, granted)
	return granted


func _on_task_failed_gently() -> void:
	if not _running or _advancing:
		return
	_gentle_attempts += 1
	if _gentle_attempts < MAX_GENTLE_ATTEMPTS:
		return
	# The no-dead-end escape hatch: still kind, still no score, worth 0 stars.
	encouragement.emit(MOVE_ON_PHRASE)
	skip_current_task()


func _on_prompt_changed(prompt: String, thai_hint: String) -> void:
	prompt_changed.emit(prompt, thai_hint)


func _on_encouragement(text: String) -> void:
	encouragement.emit(text)


func _on_speak_button_enabled(enabled: bool) -> void:
	speak_button_enabled.emit(enabled)


## Outside a SceneTree there is no timer, so the callable runs immediately. That
## is what lets the unit tests drive an entire mission synchronously.
func _delay(seconds: float, callable: Callable) -> void:
	if not is_inside_tree():
		callable.call()
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		callable.call()
		return
	var timer: SceneTreeTimer = tree.create_timer(seconds)
	timer.timeout.connect(callable, CONNECT_ONE_SHOT)


static func _reward_stars(task: Dictionary) -> int:
	var reward: Variant = task.get("reward", null)
	if typeof(reward) == TYPE_DICTIONARY:
		return int((reward as Dictionary).get("stars", 1))
	return 1
