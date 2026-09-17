class_name ModeHandler
extends Node

## Common base + shared interface for the three mini-game modes
## (`findIt`, `sayIt`, `followInstruction`). `MissionRunner` drives any of them
## through exactly this interface and never special-cases a mode.
##
## ## Interface
##
## ```gdscript
## func start(task: Dictionary, context: Dictionary) -> void
## func cancel() -> void
## func on_object_chosen(object_id: String) -> void   # tap OR drag delivery
## func on_transcript(text: String) -> void           # optional speech path
## func request_listen() -> void                      # Speak button pressed
## func complete_by_touch() -> void                   # guaranteed forward path
##
## signal task_started(task_id: String)
## signal task_completed(task_id: String, stars: int)
## signal task_failed_gently()
## signal prompt_changed(prompt: String, thai_hint: String)
## signal encouragement(text: String)
## signal speak_button_enabled(enabled: bool)
## ```
##
## ## Child-UX invariants enforced here, for every mode
##
##   - `complete_by_touch()` always exists and always works. No task can be
##     gated behind the microphone.
##   - A wrong choice emits `task_failed_gently()` + a short kind phrase and
##     leaves the task RUNNING. Never a red X, never a score, never a timer,
##     never a dead end.
##   - `_succeed()` is latched by `_completed`, so mashing tap+drag, or a
##     re-delivery after the reward, can never complete a task twice. (The
##     authoritative no-double-award guard is `MissionRunner._award()`; this is
##     the first of the three layers -- see that file.)
##
## ## Headless-safety
##
## Everything here works with no scene: if the context has no object anchor the
## handler simply skips spawning and stays fully drivable through
## `on_object_chosen()`. That is what makes the whole mission loop unit-testable
## without a renderer, and is why the tests can prove "no mission dead-ends".

const OBJECT_SPAWNER_SCRIPT_PATH: String = "res://scripts/gameplay/object_spawner.gd"

## Context dictionary keys (all optional).
const CTX_LIBRARY: String = "library"          # ContentLibrary
const CTX_OBJECT_ANCHOR: String = "objectAnchor"  # Node3D to parent spawns under
const CTX_SPAWN_POINTS: String = "spawnPoints"    # Array[Vector3], local to anchor
const CTX_DROP_ZONES: String = "dropZones"        # Dictionary zoneId -> DropZone
const CTX_TTS: String = "tts"                     # Node with speak()
const CTX_SPEECH: String = "speech"               # Node with start_listening()
const CTX_THAI_HINTS: String = "thaiHints"        # bool
const CTX_REVIEW: String = "review"               # Dictionary, vocabulary review state

const VOCABULARY_REVIEW_SCRIPT_PATH: String = "res://scripts/content/vocabulary_review.gd"

## Short, kind, never a score. Rotated so repetition doesn't feel robotic.
const GENTLE_PHRASES: Array[String] = ["Try again!", "Almost!", "Have another go!"]
const SUCCESS_PHRASES: Array[String] = ["Great!", "Nice!", "Yes!", "Well done!"]

const DEFAULT_SPAWN_POINTS: Array[Vector3] = [
	Vector3(-0.72, 0.1, 0.72),
	Vector3(-0.24, 0.1, 0.72),
	Vector3(0.24, 0.1, 0.72),
	Vector3(0.72, 0.1, 0.72),
]

const MAX_CHOICES: int = 4

signal task_started(task_id: String)
signal task_completed(task_id: String, stars: int)
signal task_failed_gently()
signal prompt_changed(prompt: String, thai_hint: String)
signal encouragement(text: String)
signal speak_button_enabled(enabled: bool)

var _task: Dictionary = {}
var _context: Dictionary = {}
var _active: bool = false
var _completed: bool = false
var _attempts: int = 0
var _spawned: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Makes choice layout and phrase rotation reproducible in tests.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## -- Interface ------------------------------------------------------------------

func start(task: Dictionary, context: Dictionary = {}) -> void:
	cancel()
	_task = task.duplicate(true)
	_context = context
	_active = true
	_completed = false
	_attempts = 0

	task_started.emit(get_task_id())
	prompt_changed.emit(get_prompt(), get_thai_hint())
	# The baby's own line first ("I'm hungry."), then the ask ("Give the baby
	# some milk."), queued so the second never cuts off the first. The label
	# shows the ask, because that is what the child has to act on.
	var baby_line: String = String(_task.get("prompt", "")).strip_edges()
	if not baby_line.is_empty() and baby_line != get_prompt():
		_speak(baby_line)
		_speak(get_prompt(), false)
	else:
		_speak(get_prompt())
	# Only the zone this task actually targets shows its landing pad.
	_set_all_markers_visible(false)
	_reveal_target_zone_marker()
	_on_start()


func cancel() -> void:
	_active = false
	_despawn_all()
	_set_all_markers_visible(false)
	speak_button_enabled.emit(false)


## Hides every landing pad. Zones are plain Area3Ds from the activity scene, so
## duck-type the call -- a zone without the method is simply skipped.
func _set_all_markers_visible(value: bool) -> void:
	var zones: Variant = _context.get(CTX_DROP_ZONES, {})
	if not (zones is Dictionary):
		return
	for key: Variant in (zones as Dictionary).keys():
		var zone: Variant = (zones as Dictionary)[key]
		if zone is Node and is_instance_valid(zone) and zone.has_method("set_marker_visible"):
			zone.call("set_marker_visible", value)


## Subclasses that deliver into a zone override `get_zone_id()`; tap-only modes
## return "" and therefore reveal nothing.
func _reveal_target_zone_marker() -> void:
	if not has_method("get_zone_id"):
		return
	var zone_id: String = String(call("get_zone_id"))
	if zone_id.is_empty():
		return
	var zones: Variant = _context.get(CTX_DROP_ZONES, {})
	if not (zones is Dictionary) or not (zones as Dictionary).has(zone_id):
		return
	var zone: Variant = (zones as Dictionary)[zone_id]
	if zone is Node and is_instance_valid(zone) and zone.has_method("set_marker_visible"):
		zone.call("set_marker_visible", true)


## Single funnel for every touch interaction: a tap on an object, or a drag that
## lands in a drop zone. Modes override `_handle_choice()`.
func on_object_chosen(object_id: String) -> void:
	if not _active or _completed:
		return
	_handle_choice(object_id)


func on_transcript(_text: String) -> void:
	pass


func request_listen() -> void:
	pass


## The always-available way forward. Every mode completes on this; it is what
## guarantees a child with no microphone (or no fine motor control for dragging)
## is never stuck.
func complete_by_touch() -> void:
	if not _active or _completed:
		return
	_succeed()


func is_active() -> bool:
	return _active and not _completed


func is_completed() -> bool:
	return _completed


func get_task() -> Dictionary:
	return _task.duplicate(true)


func get_task_id() -> String:
	return String(_task.get("taskId", ""))


func get_mode_name() -> String:
	return ""


func get_attempt_count() -> int:
	return _attempts


func get_target_object_id() -> String:
	return String(_task.get("objectId", ""))


func get_prompt() -> String:
	var instruction: String = String(_task.get("instruction", "")).strip_edges()
	if not instruction.is_empty():
		return instruction
	return String(_task.get("prompt", ""))


func get_thai_hint() -> String:
	if _context.has(CTX_THAI_HINTS) and not bool(_context[CTX_THAI_HINTS]):
		return ""
	return String(_task.get("thaiHint", ""))


func get_reward_stars() -> int:
	var reward: Variant = _task.get("reward", null)
	if typeof(reward) == TYPE_DICTIONARY:
		return int((reward as Dictionary).get("stars", 1))
	return 1


func get_spawned_objects() -> Array:
	return _spawned.duplicate()


## -- Virtual hooks ----------------------------------------------------------------

func _on_start() -> void:
	pass


func _handle_choice(object_id: String) -> void:
	if object_id == get_target_object_id():
		_succeed()
	else:
		_gentle_retry(object_id)


## -- Outcomes -----------------------------------------------------------------------

## Latched: only the FIRST call per task ever emits. Everything else -- a second
## finger, a re-drag into the zone, a tap during the celebration -- is swallowed.
func _succeed() -> void:
	if _completed:
		return
	_completed = true
	_active = false
	speak_button_enabled.emit(false)
	_set_objects_enabled(false)
	encouragement.emit(_pick(SUCCESS_PHRASES))
	task_completed.emit(get_task_id(), get_reward_stars())


## A wrong answer is NOT a failure state: the task stays active, the object goes
## home, and the child gets a short kind phrase. `MissionRunner` counts these and
## opens an escape hatch after a few, so this can never become a dead end.
func _gentle_retry(object_id: String = "") -> void:
	if _completed:
		return
	_attempts += 1
	_return_object_home(object_id)
	encouragement.emit(_pick(GENTLE_PHRASES))
	_repeat_prompt()
	# Emitted LAST on purpose: `MissionRunner` may respond by moving to the next
	# task, and the outgoing task must not then overwrite the new task's prompt.
	task_failed_gently.emit()


func _repeat_prompt() -> void:
	var repeat: String = String(_task.get("repeatPrompt", "")).strip_edges()
	if repeat.is_empty():
		repeat = get_prompt()
	prompt_changed.emit(repeat, get_thai_hint())
	_speak(repeat)


## -- Spawning ------------------------------------------------------------------------

## Builds the touchable choice set. A no-op when the context has no anchor
## (headless/unit-test use) -- the mode stays drivable via `on_object_chosen()`.
func _spawn_choices(object_ids: Array, zone_id: String = "") -> void:
	var anchor: Node = _context.get(CTX_OBJECT_ANCHOR, null)
	if anchor == null or not (anchor is Node3D):
		return

	var spawner: GDScript = load(OBJECT_SPAWNER_SCRIPT_PATH) as GDScript
	if spawner == null:
		return

	var library: Object = _context.get(CTX_LIBRARY, null)
	var points: Array = _spawn_points_for(object_ids.size())
	var zone: Node = _zone_for(zone_id)

	for i: int in range(object_ids.size()):
		var object_id: String = String(object_ids[i])
		var record: Dictionary = {}
		if library != null and library.has_method("get_object"):
			record = library.get_object(object_id)
		if record.is_empty():
			continue

		var node: Area3D = spawner.spawn(record, String(_task.get("interaction", "")))
		if node == null:
			continue
		node.set("is_target", object_id == get_target_object_id())
		node.call("set_home_position", points[i % points.size()])
		if zone != null and node.has_method("set_drop_zone"):
			var radius: float = 0.26
			if zone.has_method("get_radius"):
				radius = float(zone.call("get_radius"))
			node.call("set_drop_zone", zone, radius)
		node.connect("chosen", on_object_chosen)
		(anchor as Node3D).add_child(node)
		_spawned.append(node)


func _spawn_points_for(count: int) -> Array:
	var configured: Variant = _context.get(CTX_SPAWN_POINTS, null)
	var points: Array = []
	if typeof(configured) == TYPE_ARRAY and not (configured as Array).is_empty():
		points = (configured as Array).duplicate()
	else:
		points = DEFAULT_SPAWN_POINTS.duplicate()

	# Centre a small choice set instead of leaving a lopsided gap on one side.
	if count > 0 and count < points.size():
		var start: int = int(floor(float(points.size() - count) * 0.5))
		points = points.slice(start, start + count)
	return points


func _zone_for(zone_id: String) -> Node:
	if zone_id.is_empty():
		return null
	var zones: Variant = _context.get(CTX_DROP_ZONES, null)
	if typeof(zones) != TYPE_DICTIONARY:
		return null
	var zone: Variant = (zones as Dictionary).get(zone_id, null)
	if zone is Node:
		return zone as Node
	return null


func _despawn_all() -> void:
	for node: Variant in _spawned:
		if not (node is Node) or not is_instance_valid(node):
			continue
		var spawned_node: Node = node
		if spawned_node.is_inside_tree():
			spawned_node.queue_free()
		else:
			# Deferred deletion only runs on an idle frame, which never arrives
			# in the headless test runner -- free detached nodes immediately so
			# they cannot leak.
			spawned_node.free()
	_spawned = []


func _set_objects_enabled(enabled: bool) -> void:
	for node: Variant in _spawned:
		if node is Node and is_instance_valid(node) and (node as Node).has_method("set_enabled"):
			(node as Node).call("set_enabled", enabled)


func _return_object_home(object_id: String) -> void:
	if object_id.is_empty():
		return
	for node: Variant in _spawned:
		if not (node is Node) or not is_instance_valid(node):
			continue
		if String((node as Node).get("object_id")) != object_id:
			continue
		if (node as Node).has_method("animate_return_to_origin"):
			(node as Node).call("animate_return_to_origin")


## -- Choice-set construction (pure, so the tests can prove it) --------------------

## Returns the target plus up to `distractor_count` other objects, shuffled.
## The target is ALWAYS present: a task whose answer is not on screen would be an
## unwinnable dead end.
## The same choice set as `build_choice_ids()`, biased toward words the child met
## two to five levels ago when the profile carries review history.
##
## With no history -- or with `reviewWeight` at 0.0 -- this IS `build_choice_ids()`
## draw for draw, which is asserted id-for-id across 750 seed/size combinations.
## That exactness is the point: review must be invisible, so it may not change the
## row's shape, its pool, or the order the RNG is consumed in.
func build_review_choice_ids(target_id: String, pool: Array, distractor_count: int) -> Array:
	var review: GDScript = load(VOCABULARY_REVIEW_SCRIPT_PATH) as GDScript
	var options: Variant = _context.get(CTX_REVIEW, {})
	if review == null or typeof(options) != TYPE_DICTIONARY:
		return build_choice_ids(target_id, pool, distractor_count, _rng)
	return review.build_choice_ids(target_id, pool, distractor_count, _rng, options)


static func build_choice_ids(
	target_id: String,
	pool: Array,
	distractor_count: int,
	rng: RandomNumberGenerator = null
) -> Array:
	var candidates: Array = []
	for entry: Variant in pool:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var object_id: String = String((entry as Dictionary).get("objectId", ""))
		if object_id.is_empty() or object_id == target_id:
			continue
		if candidates.has(object_id):
			continue
		candidates.append(object_id)

	var generator: RandomNumberGenerator = rng
	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()

	_shuffle(candidates, generator)
	var chosen: Array = [target_id]
	for i: int in range(mini(maxi(0, distractor_count), candidates.size())):
		chosen.append(candidates[i])
	_shuffle(chosen, generator)
	return chosen


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = values[i]
		values[i] = values[j]
		values[j] = swap


## Objects the task can draw distractors from: same category first (so "find the
## teddy" is a real choice between toys, not between a toy and a sock), falling
## back to the whole catalogue if that category is too small.
func _distractor_pool() -> Array:
	var library: Object = _context.get(CTX_LIBRARY, null)
	if library == null:
		return []
	var category: String = String(_task.get("category", ""))
	var pool: Array = []
	if not category.is_empty() and library.has_method("get_objects_in_category"):
		pool = library.get_objects_in_category(category)
	if pool.size() < 3 and library.has_method("get_objects"):
		pool = library.get_objects()
	return pool


## -- Services (all optional, all accessed defensively) ------------------------------

func _speak(text: String, interrupt: bool = true) -> void:
	if text.strip_edges().is_empty():
		return
	var tts: Object = _context.get(CTX_TTS, null)
	if tts == null and is_inside_tree():
		tts = get_node_or_null("/root/TtsService")
	if tts != null and tts.has_method("speak"):
		tts.call("speak", text, interrupt)


func _speech_service() -> Object:
	var speech: Object = _context.get(CTX_SPEECH, null)
	if speech == null and is_inside_tree():
		speech = get_node_or_null("/root/SpeechService")
	return speech


func _is_speech_available() -> bool:
	var speech: Object = _speech_service()
	if speech == null or not speech.has_method("is_available"):
		return false
	return bool(speech.call("is_available"))


func _pick(phrases: Array) -> String:
	if phrases.is_empty():
		return ""
	return String(phrases[_rng.randi_range(0, phrases.size() - 1)])
