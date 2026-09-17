extends Node

## Free Play: the house with no objective, and enough to do that a child never
## notices there isn't one.
##
## Before this file, Free Play routed into `house_world.tscn` and produced four
## walkable rooms, no HUD, no prompt and nothing that reacted to being touched.
## A four-year-old with no goal and no feedback puts the iPad down. So Free Play
## gets one loop, and it is the loop the whole product is about:
##
## ```
##   the child taps the fridge
##     -> "fridge"            spoken, and on screen in letters bigger than
##                            anything else in the game
##     -> Little Buddy walks to it
##     -> he opens it, and says "Nice!"
##   the child LONG-PRESSES the fridge
##     -> "ตู้เย็น" appears under the English word   (ART_BIBLE section 9)
## ```
##
## **No objective, no score, no dots, no Next, no Speak.** `house_hud.gd`'s
## `set_free_play_mode()` takes all of that away in one call. What is left is the
## star total, which only ever goes up, and the word.
##
## ## The idle nudge
##
## A child who has stopped touching the screen is shown a picture, never told off
## and never timed: the same pointing hand and pulsing ring that first run uses,
## moved onto a real object in the room. It appears a few seconds after arriving
## in a room and again after a quiet spell, and it vanishes the instant anything
## is touched.
##
## ## Unlocked rooms
##
## Free Play never locks a room by accident: `HouseWorld.get_unlocked_room_ids()`
## treats an empty list as "all of them", because a fresh profile carries
## `unlockedRooms: []` and reading that as "nothing is unlocked" would shut a
## child out of their own house. This file relies on that and adds nothing of its
## own.
##
## ## Headless
##
## `bind()` + `step(delta)`, and `_process()` forwards to `step()`. `_ready()`
## never fires for a node added to the root in the `--script` runner.

const HouseHudScript := preload("res://scripts/gameplay/house_hud.gd")
const Words := preload("res://scripts/gameplay/house_freeplay_words.gd")
const GestureHintScript := preload("res://scripts/onboarding/gesture_hint.gd")
const HouseRoute := preload("res://scripts/house/house_route.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## How long a press has to last to be a long press. Comfortably longer than a
## child's tap, comfortably shorter than giving up.
const LONG_PRESS_SEC: float = 0.55

## Quiet before the pointing hand appears. The first one is soon, because a child
## opening Free Play has been given no instruction at all; later ones are slower,
## because by then they know and are probably just looking.
const FIRST_NUDGE_SEC: float = 3.0
const IDLE_NUDGE_SEC: float = 11.0

## Warm, short, never a score. Spoken once when Free Play opens.
const WELCOME_PHRASE: String = "Off you go! Tap anything you like."

signal word_spoken(semantic_id: String, word: String)
signal hint_shown(semantic_id: String)

var _world: Node = null
var _character: Node = null
var _nav: Node = null

var _hud: Control = null
var _hint: Control = null

var _tts: Object = null
var _save: Object = null
var _services_resolved: bool = false

var _bound: bool = false
var _running: bool = false

var _idle: float = 0.0
var _next_nudge: float = FIRST_NUDGE_SEC
var _nudge_id: String = ""
var _arrivals: int = 0

## Long-press bookkeeping. `_press_target_id` is filled by the navigation
## controller's `target_tapped`, which fires on PRESS; the duration is measured
## here on release. Doing it this way means no second raycast and no duplicated
## hit-testing -- there is exactly one place in the project that decides what a
## tap hit, and it is not this file.
var _press_started_msec: int = 0
var _press_target_id: String = ""


## -- Wiring --------------------------------------------------------------------

func bind(world: Node) -> void:
	if _bound:
		return
	_bound = true
	_world = world
	if _world == null:
		return

	if _world.has_method("get_character"):
		_character = _world.call("get_character")
	_nav = _world.get_node_or_null("NavigationController")

	_hud = HouseHudScript.new()
	var ui: Node = _world.get_node_or_null("UI")
	if ui != null:
		ui.add_child(_hud)
	else:
		add_child(_hud)
	_hud.call("build")
	_hud.call("set_free_play_mode", true)

	_hint = GestureHintScript.new()
	_hint.call("build")
	if ui != null:
		ui.add_child(_hint)
	else:
		add_child(_hint)

	if _nav != null:
		if _nav.has_signal("target_tapped"):
			_nav.connect("target_tapped", _on_target_tapped)
		if _nav.has_signal("floor_tapped"):
			_nav.connect("floor_tapped", _on_floor_tapped)
	if _character != null and _character.has_signal("interaction_ready"):
		_character.connect("interaction_ready", _on_interaction_ready)
	if _world.has_signal("room_entered"):
		_world.connect("room_entered", _on_room_entered)

	# Explicit rather than relying on the engine noticing `_unhandled_input`,
	# exactly as `navigation_controller.gd` does it.
	set_process_unhandled_input(true)


## Both optional, and both injectable so a headless case can watch them.
func set_tts(tts: Object) -> void:
	_tts = tts
	_services_resolved = true


func set_save_service(save_service: Object) -> void:
	_save = save_service
	_services_resolved = true


func get_hud() -> Control:
	return _hud


func get_hint() -> Control:
	return _hint


## -- Session -------------------------------------------------------------------

func start() -> bool:
	if _running or _world == null:
		return false
	_running = true
	_resolve_services()

	# One voice and one piece of text. The world's own status line would
	# otherwise say "At the sink!" at the top while the word card says "sink" at
	# the bottom, which is two of everything for a child who can read neither.
	if _world.has_method("set_status_visible"):
		_world.call("set_status_visible", false)

	_hud.call("set_free_play_mode", true)
	_hud.call("set_play_chrome_visible", true)
	_hud.call("set_stars", _stars())
	_speak(WELCOME_PHRASE, true)
	_idle = 0.0
	_next_nudge = FIRST_NUDGE_SEC
	return true


func is_running() -> bool:
	return _running


func stop() -> void:
	_running = false
	if _hint != null:
		_hint.call("hide_hint")


## How many times the child has walked up to something this session. Not a score
## and never shown -- the tests use it to prove the loop actually closes.
func get_arrival_count() -> int:
	return _arrivals


func _process(delta: float) -> void:
	step(delta)


## The per-frame work, callable by hand. `_process()` does nothing else, so a
## headless test drives exactly the same code a device does.
func step(delta: float) -> void:
	if not _running:
		return
	_idle += maxf(delta, 0.0)
	if _hint != null and _hint.visible:
		_hint.call("step", delta)
		_follow_nudge()
	elif _idle >= _next_nudge:
		_show_nudge()


## -- Taps ----------------------------------------------------------------------

## A press is recorded here and classified by `NavigationController`; all this
## needs is how long the finger stayed down.
func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return
	var pressed: Variant = _press_state(event)
	if pressed == null:
		return
	if bool(pressed):
		if _press_started_msec == 0:
			_press_started_msec = Time.get_ticks_msec()
		return

	var held_msec: int = Time.get_ticks_msec() - _press_started_msec
	var target_id: String = _press_target_id
	_press_started_msec = 0
	_press_target_id = ""
	if target_id.is_empty() or _press_started_was_never_recorded(held_msec):
		return
	if float(held_msec) * 0.001 >= LONG_PRESS_SEC:
		reveal_thai_hint(target_id)


## `true` for a press, `false` for a release, `null` for anything else.
static func _press_state(event: InputEvent) -> Variant:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return null
		return mouse.pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return null


## A release with no matching press (the press happened before Free Play started,
## or was eaten by a control) measures as an absurd duration. Never treat that as
## a long press.
func _press_started_was_never_recorded(held_msec: int) -> bool:
	return held_msec < 0 or held_msec > 60000


func _on_target_tapped(target_id: String) -> void:
	if not _running:
		return
	_press_target_id = target_id
	if _press_started_msec == 0:
		_press_started_msec = Time.get_ticks_msec()
	_quieten_nudge()
	say_word(target_id)


func _on_floor_tapped(_x: float, _z: float) -> void:
	if not _running:
		return
	_quieten_nudge()


## Says (and shows) the English word for a house object. Public so a test -- and
## anything else that wants to teach a word -- can call it without synthesising
## an `InputEvent`.
func say_word(semantic_id: String) -> bool:
	if _hud == null:
		return false
	var word: String = Words.word_for(semantic_id)
	if word.is_empty():
		return false
	_hud.call("show_word", word, "")
	# Interrupting on purpose: a child taps a lot and quickly, and eight queued
	# nouns arriving long after the fingers moved on teaches nothing. The newest
	# tap is always the one being talked about.
	_speak(word, true)
	word_spoken.emit(semantic_id, word)
	return true


## The optional Thai hint, on a long press only (ART_BIBLE section 9).
##
## Shown, never spoken: the voice is an en-US one, and a Thai string read by an
## English voice teaches a Thai child the wrong sound for their own language.
## Respects the `thaiHints` setting, exactly as the Story HUD does.
func reveal_thai_hint(semantic_id: String) -> bool:
	if _hud == null:
		return false
	var described: Dictionary = Words.describe(semantic_id)
	var word: String = String(described.get("word", ""))
	if word.is_empty():
		return false
	var thai: String = String(described.get("thai", ""))
	if not _thai_hints_enabled():
		thai = ""
	_hud.call("show_word", word, thai)
	return not thai.is_empty()


## -- Arrival -------------------------------------------------------------------

## Little Buddy is standing at the thing and facing it. This is where a tap
## becomes play: he uses the object, and says something warm.
func _on_interaction_ready(target_id: String) -> void:
	if not _running:
		return
	_arrivals += 1
	if HouseRoute.is_door_id(target_id):
		# The room is about to change; an action and a reaction here would both
		# land in the room the child has just left.
		return
	var described: Dictionary = Words.describe(target_id)
	var action: String = String(described.get("action", ""))
	if not action.is_empty() and _character != null and _character.has_method("play_action"):
		# SEMANTIC only, from the contract's action vocabulary. An action with no
		# clip yet still starts, times out and returns to idle.
		_character.call("play_action", action)
	var reaction: String = Words.reaction_for(_arrivals)
	if _hud != null:
		_hud.call("show_encouragement", reaction)
	# Queued, not interrupting: the word this reaction is about was spoken when
	# the child tapped, and chopping it off would take the lesson away.
	_speak(reaction, false)


func _on_room_entered(_room_id: String, _spawn_id: String) -> void:
	# A new room is a new set of things: offer a hand again, but not instantly.
	_quieten_nudge()
	if _hud != null:
		_hud.call("hide_word")


## -- The idle nudge ------------------------------------------------------------

## Points the hand at something real in the room the child is in. A picture, not
## a sentence: the player cannot read, and a pre-reader who is stuck needs to be
## shown, not told again.
func _show_nudge() -> void:
	_nudge_id = _pick_nudge_target()
	if _nudge_id.is_empty():
		_next_nudge = _idle + IDLE_NUDGE_SEC
		return
	_follow_nudge()
	hint_shown.emit(_nudge_id)


func _follow_nudge() -> void:
	if _hint == null or _nudge_id.is_empty():
		return
	var screen: Variant = _screen_position_of(_nudge_id)
	if screen == null:
		_hint.call("hide_hint")
		return
	_hint.call("show_tap", screen as Vector2)


func _quieten_nudge() -> void:
	_idle = 0.0
	_next_nudge = IDLE_NUDGE_SEC
	_nudge_id = ""
	if _hint != null:
		_hint.call("hide_hint")


## How close Little Buddy has to be to an object for the hand to leave it alone.
## Pointing at the thing he is already standing in front of draws a large cream
## hand over the only face in the game, and suggests doing what has just been
## done. Found by rendering it.
const NUDGE_MIN_DISTANCE: float = 1.1


## The most interesting thing in the room: never a door (a nudge that changes the
## room takes the child somewhere they did not choose), never something with no
## word, never where Little Buddy is already standing, and not the same object
## every time.
func _pick_nudge_target() -> String:
	if _world == null or not _world.has_method("get_current_room"):
		return ""
	var room: Node = _world.call("get_current_room")
	if room == null or not room.has_method("get_activity_targets"):
		return ""
	var here: Vector3 = Vector3.ZERO
	if _character is Node3D:
		here = SpatialUtil.world_position(_character as Node3D)

	var candidates: Array = []
	var crowded: Array = []
	for target: Variant in room.call("get_activity_targets"):
		if not (target is Node) or not (target as Node).has_method("get_activity_target_id"):
			continue
		var id: String = String((target as Node).call("get_activity_target_id"))
		if id.is_empty() or HouseRoute.is_door_id(id) or not Words.has_word(id):
			continue
		if target is Node3D \
				and SpatialUtil.world_position(target as Node3D).distance_to(here) < NUDGE_MIN_DISTANCE:
			crowded.append(id)
			continue
		candidates.append(id)
	if candidates.is_empty():
		# Everything in this room is within arm's reach. Better a hand over his
		# shoulder than no affordance at all.
		candidates = crowded
	if candidates.is_empty():
		return ""
	return String(candidates[_arrivals % candidates.size()])


func _screen_position_of(semantic_id: String) -> Variant:
	if _world == null or not _world.has_method("get_target_by_semantic_id"):
		return null
	var target: Node = _world.call("get_target_by_semantic_id", semantic_id)
	if not (target is Node3D):
		return null
	var camera: Camera3D = _world.call("get_camera") as Camera3D \
			if _world.has_method("get_camera") else null
	if camera == null or not camera.is_inside_tree():
		return null
	# `global_position` reports the origin for a node outside the tree, which in
	# the headless runner is every node -- hence `spatial_util.gd`.
	var point: Vector3 = SpatialUtil.world_position(target as Node3D)
	if camera.is_position_behind(point):
		return null
	return camera.unproject_position(point)


## -- Services (all optional) ---------------------------------------------------

func _resolve_services() -> void:
	if _services_resolved:
		return
	_services_resolved = true
	if _tts == null:
		_tts = _autoload("TtsService")
	if _save == null:
		_save = _autoload("SaveService")


func _speak(text: String, interrupt: bool) -> void:
	var line: String = text.strip_edges()
	if line.is_empty():
		return
	_resolve_services()
	if _tts != null and _tts.has_method("speak"):
		_tts.call("speak", line, interrupt)


func _stars() -> int:
	_resolve_services()
	if _save != null and _save.has_method("get_stars"):
		return int(_save.call("get_stars"))
	return 0


func _thai_hints_enabled() -> bool:
	_resolve_services()
	if _save != null and _save.has_method("get_setting"):
		return bool(_save.call("get_setting", "thaiHints", true))
	return true


func _autoload(autoload_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null(NodePath("/root/%s" % autoload_name))
