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
## ## Things a child can pick up
##
## Every room also lays out three real pickups on the floor in front of the
## child -- the teddy in the bedroom, the apple in the kitchen, the ball in the
## living room -- and each one has somewhere to go:
##
## ```
##   the child drags the apple onto Little Buddy
##     -> place_soft
##     -> "apple"             spoken, and on the word card
##     -> he eats it, and says "Thank you!"
##     -> the apple slides home, ready to be dragged again
## ```
##
## This exists because first run TEACHES a drag, and a lesson with nothing to
## practise on is a hand waving over an empty floor. The staging is
## `house_stage.gd`'s -- the same anchor, the same spawn row and the same landing
## pads Story Mode uses -- so there is exactly one place in this project that
## knows where a draggable object goes, and Free Play is not a second one.
##
## Layers are untouched: a pickup is layer 1 (`DraggableObject`), an activity
## target is layer 2, and `test_architecture_guard.gd` fails the build if they
## ever mix.
##
## There is no objective here, so a successful drop is worth nothing and costs
## nothing. It is simply satisfying: a sound, a word, and Little Buddy doing
## something with the thing. Tapping the object delivers it too -- a child who
## cannot drag is never locked out (CLAUDE.md).
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
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const DropZoneScript := preload("res://scripts/gameplay/drop_zone.gd")
const HouseStageScript := preload("res://scripts/gameplay/house_stage.gd")

## `load()`ed rather than `preload()`ed, both of them, for the reason this file's
## own script is: a Free Play session that cannot read the content set must still
## be a walkable, word-teaching house. No content simply means no pickups.
const OBJECT_SPAWNER_SCRIPT_PATH: String = "res://scripts/gameplay/object_spawner.gd"
const CONTENT_LIBRARY_SCRIPT_PATH: String = "res://scripts/content/content_library.gd"

## Landed where it belongs. The one sound a successful drop makes.
const SFX_PLACE_SOFT: String = "place_soft"

## How long a delivered object rests on the landing pad before sliding home.
## Long enough to read as "it went there", short enough that a child who wants to
## do it again is not kept waiting. It always comes back: Free Play has no
## objective, so nothing is ever used up.
const RETURN_HOME_SEC: float = 1.1

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
## A pickup reached its landing pad -- by drag, or by the tap fallback.
signal object_dropped(object_id: String, word: String)

var _world: Node = null
var _character: Node = null
var _nav: Node = null

var _hud: Control = null
var _hint: Control = null
## `house_stage.gd`: the spawn row and the landing pads, shared with Story Mode.
var _stage: Node3D = null

var _tts: Object = null
var _save: Object = null
var _sfx: Object = null
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

## The pickups currently on the floor, and the room they were laid out for.
var _draggables: Array = []
var _staged_room: String = ""
var _library: Object = null
var _library_resolved: bool = false
## How many things the child has put where they belong this session. Not a score
## and never shown; it only rotates the warm line so it is not the same one four
## times running.
var _drops: int = 0
## `[{ "node": Node, "remaining": float }]` -- delivered objects waiting to slide
## home. Ticked from `step()` rather than by a `Timer`, so the headless runner
## drives exactly the same code a device does.
var _pending_returns: Array = []


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

	# The same staging Story Mode uses, not a second one. Added to the WORLD
	# rather than to this node so its pads sit in world space next to the rooms.
	_stage = HouseStageScript.new()
	_stage.name = "FreePlayStage"
	_world.add_child(_stage)
	if _character is Node3D:
		_stage.call("bind_character", _character)

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


## The sound layer. Optional like the rest: a build with no audio still shows the
## word and still plays the reaction.
func set_sfx(sfx: Object) -> void:
	_sfx = sfx
	_services_resolved = true


func get_hud() -> Control:
	return _hud


func get_hint() -> Control:
	return _hint


func get_stage() -> Node:
	return _stage


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
	# Something to pick up, before the first word is spoken: an empty floor is
	# what made first run's drag lesson a demonstration over nothing.
	ensure_draggables()
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
	# The landing pads that ride on Little Buddy have to keep up with him. The
	# stage does this from its own `_process()` in a live scene; doing it here as
	# well costs a handful of vector writes and is what makes the headless runner
	# exercise the real geometry.
	if _stage != null:
		_stage.call("update_zones")
	_step_returns(delta)
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


func _on_room_entered(room_id: String, _spawn_id: String) -> void:
	# A new room is a new set of things: offer a hand again, but not instantly.
	_quieten_nudge()
	if _hud != null:
		_hud.call("hide_word")
	# And a new set of things to pick up. Carrying the bedroom's teddy into the
	# kitchen would leave it floating in another room's floor.
	if _staged_room != room_id:
		stage_draggables(room_id)


## -- Things to pick up ----------------------------------------------------------

## Lays out the current room's pickups if they are not already there. Idempotent,
## and public so first run can ask for them BEFORE the Free Play loop starts --
## the drag it teaches has to have something real underneath it.
##
## Returns the objects now on the floor, which is `[]` for a build with no
## content set and for a room with nothing to carry. Neither is an error: Free
## Play is still a walkable, word-teaching house without a single pickup in it.
func ensure_draggables() -> Array:
	var room_id: String = _current_room_id()
	if _staged_room == room_id and not _draggables.is_empty():
		return _draggables.duplicate()
	return stage_draggables(room_id)


## Replaces whatever is on the floor with `room_id`'s set. Public so a test can
## stage a room the child has not walked to.
func stage_draggables(room_id: String) -> Array:
	if _stage == null or _world == null:
		return []
	_despawn_draggables()
	_staged_room = room_id
	if not Words.DRAGGABLES.has(room_id):
		return []

	var entries: Array = Words.draggables_for(room_id)
	var library: Object = _content_library()
	if library == null or entries.is_empty():
		return []
	var spawner: GDScript = load(OBJECT_SPAWNER_SCRIPT_PATH) as GDScript
	if spawner == null:
		return []

	# The pads first, then the row: `begin_task()` is what puts the furniture pad
	# on the toy box and the row between the child and the camera, and the
	# spawner needs the anchor to already be in the right room.
	_stage.call("begin_task", {"roomId": room_id}, _focus_position(room_id), _row_anchor(room_id))
	var anchor: Node3D = _stage.call("get_object_anchor") as Node3D
	if anchor == null:
		return []
	var points: Array = _centred_spawn_points(entries.size())

	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index] as Dictionary
		var object_id: String = String(entry.get("objectId", ""))
		var record: Dictionary = {}
		if library.has_method("get_object"):
			record = library.call("get_object", object_id)
		if record.is_empty():
			continue
		var interaction: String = String(entry.get("interaction", ""))
		var node: Area3D = spawner.call("spawn", record, interaction)
		if node == null:
			continue
		node.call("set_home_position", points[index % points.size()])

		var zone: Node = _stage.call("get_drop_zone", DropZoneScript.zone_id_for_interaction(interaction))
		if zone != null and node.has_method("set_drop_zone"):
			var radius: float = 0.26
			if zone.has_method("get_radius"):
				radius = float(zone.call("get_radius"))
			node.call("set_drop_zone", zone, radius)
			# A pad on the furniture is a place on the floor a child has to be
			# shown; a pad on Little Buddy is Little Buddy, who is already the
			# most visible thing in the room.
			if zone.has_method("set_marker_visible"):
				zone.call("set_marker_visible", not _rides_on_character(interaction))
		node.connect("chosen", _on_object_chosen)
		anchor.add_child(node)
		_draggables.append(node)

	return _draggables.duplicate()


## The pickups on the floor right now.
func get_draggables() -> Array:
	return _draggables.duplicate()


func get_staged_room_id() -> String:
	return _staged_room


## How many things the child has put where they belong this session.
func get_drop_count() -> int:
	return _drops


## Where first run should animate its drag: the world position of a real pickup,
## the world position of the pad it belongs in, and the two words involved.
##
## Empty when this room has nothing to carry, in which case the caller falls back
## to a gesture drawn in screen space -- a demonstration is still better than no
## lesson, and it is exactly what this used to be everywhere.
func get_drag_demo() -> Dictionary:
	for node: Variant in _draggables:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var object_id: String = String((node as Node).get("object_id"))
		var entry: Dictionary = Words.draggable_entry(_staged_room, object_id)
		var interaction: String = String(entry.get("interaction", ""))
		var zone: Node = _stage.call("get_drop_zone", DropZoneScript.zone_id_for_interaction(interaction)) \
				if _stage != null else null
		if not (zone is Node3D):
			continue
		return {
			"objectId": object_id,
			"objectWord": String((node as Node).get("word")),
			# "" means "the pad is on Little Buddy", which reads as *me* rather
			# than as the name of a piece of furniture.
			"targetWord": "" if _rides_on_character(interaction) else \
					Words.word_for(Words.drag_focus_for(_staged_room)),
			# Both the snapshot AND the nodes. Half the landing pads RIDE ON
			# Little Buddy, and he walks: a hint drawn from the snapshot alone
			# ends up pointing at the patch of floor he was standing on when the
			# tutorial started. Found by rendering it.
			"from": SpatialUtil.world_position(node as Node3D),
			"to": SpatialUtil.world_position(zone as Node3D),
			"objectNode": node,
			"zoneNode": zone,
		}
	return {}


## The reward for a drag, and for the tap that stands in for one.
##
## No star, no score, nothing recorded: Free Play has no objective, so this is
## worth exactly what it feels like. A sound, the English word, and Little Buddy
## doing something with the thing he has just been handed.
func _on_object_chosen(object_id: String) -> void:
	_quieten_nudge()
	_play_sfx(SFX_PLACE_SOFT)

	var node: Node = _draggable_node(object_id)
	var word: String = String(node.get("word")) if node != null else ""
	if word.strip_edges().is_empty():
		word = object_id
	if _hud != null:
		_hud.call("show_word", word, "")
	# Interrupting: the word is about the thing that has just landed, and the
	# child is looking at it now.
	_speak(word, true)

	var entry: Dictionary = Words.draggable_entry(_staged_room, object_id)
	var action: String = String(entry.get("action", ""))
	if not action.is_empty() and _character != null and _character.has_method("play_action"):
		# SEMANTIC only, from the contract's action vocabulary.
		_character.call("play_action", action)

	var reaction: String = Words.drop_reaction_for(_drops)
	if _hud != null:
		_hud.call("show_encouragement", reaction)
	# Queued, not interrupting: chopping the word off with the reaction would
	# take the lesson away and leave the manners.
	_speak(reaction, false)

	_drops += 1
	if node != null:
		_pending_returns.append({"node": node, "remaining": RETURN_HOME_SEC})
	object_dropped.emit(object_id, word)


## Slides delivered objects home again. Nothing in Free Play is ever used up, so
## a child can do the same lovely thing as many times as they like.
func _step_returns(delta: float) -> void:
	if _pending_returns.is_empty():
		return
	var still_waiting: Array = []
	for pending: Variant in _pending_returns:
		var entry: Dictionary = pending as Dictionary
		var node: Variant = entry.get("node", null)
		if not (node is Node) or not is_instance_valid(node as Node):
			continue
		var remaining: float = float(entry.get("remaining", 0.0)) - maxf(delta, 0.0)
		if remaining > 0.0:
			entry["remaining"] = remaining
			still_waiting.append(entry)
			continue
		if (node as Node).has_method("animate_return_to_origin"):
			# Also re-arms the per-gesture delivery latch, which is what makes
			# the object draggable a second time.
			(node as Node).call("animate_return_to_origin")
	_pending_returns = still_waiting


func _despawn_draggables() -> void:
	_pending_returns = []
	for node: Variant in _draggables:
		if not (node is Node) or not is_instance_valid(node as Node):
			continue
		if (node as Node).is_inside_tree():
			(node as Node).queue_free()
		else:
			# Deferred deletion needs an idle frame, and the headless runner
			# never has one -- free a detached node outright so it cannot leak.
			(node as Node).free()
	_draggables = []


func _draggable_node(object_id: String) -> Node:
	for node: Variant in _draggables:
		if node is Node and is_instance_valid(node as Node) \
				and String((node as Node).get("object_id")) == object_id:
			return node as Node
	return null


## True for a landing pad that rides on Little Buddy rather than on furniture.
## `house_stage.gd` is the authority for which is which, so this cannot drift
## away from where the pad actually ends up.
static func _rides_on_character(interaction: String) -> bool:
	var zone_id: String = DropZoneScript.zone_id_for_interaction(interaction)
	return HouseStageScript.ZONE_BODY_OFFSETS.has(zone_id)


## Where the row of pickups is laid out: the middle of the room, so it is in the
## same place however the child walked in and does not follow them around.
func _row_anchor(room_id: String) -> Variant:
	if not HouseLayout.has_room(room_id):
		return null
	var bounds: Rect2 = HouseLayout.world_floor_bounds(room_id)
	var centre: Vector2 = bounds.get_center()
	return Vector3(centre.x, HouseLayout.FLOOR_Y, centre.y)


## The prop this room's furniture pad rides on, in world space, or null when
## everything here goes to Little Buddy instead.
func _focus_position(room_id: String) -> Variant:
	var local: String = Words.drag_focus_for(room_id)
	if local.is_empty() or not _world.has_method("get_target_by_semantic_id"):
		return null
	var target: Node = _world.call("get_target_by_semantic_id", "%s.%s" % [room_id, local])
	if not (target is Node3D):
		return null
	return SpatialUtil.world_position(target as Node3D)


## Centres a short row in the stage's four slots, rather than leaving a lopsided
## gap at one end -- exactly what `mode_handler.gd` does for a small choice set.
func _centred_spawn_points(count: int) -> Array:
	var points: Array = _stage.call("get_spawn_points")
	if points.is_empty():
		return [Vector3.ZERO]
	if count > 0 and count < points.size():
		var start: int = int(floor(float(points.size() - count) * 0.5))
		points = points.slice(start, start + count)
	return points


func _current_room_id() -> String:
	if _world != null and _world.has_method("get_current_room_id"):
		return String(_world.call("get_current_room_id"))
	return ""


## Built once, on demand. Null when the content set cannot be read, which simply
## means this house has nothing to pick up.
func _content_library() -> Object:
	if _library_resolved:
		return _library
	_library_resolved = true
	var script: Resource = load(CONTENT_LIBRARY_SCRIPT_PATH)
	if not (script is GDScript):
		return null
	_library = (script as GDScript).call("create")
	return _library


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
	if _sfx == null:
		_sfx = _autoload("Sfx")


func _speak(text: String, interrupt: bool) -> void:
	var line: String = text.strip_edges()
	if line.is_empty():
		return
	_resolve_services()
	if _tts != null and _tts.has_method("speak"):
		_tts.call("speak", line, interrupt)


## Silence is always acceptable: a build with no audio device, and every test,
## simply hears nothing.
func _play_sfx(sfx_name: String) -> void:
	_resolve_services()
	if _sfx != null and _sfx.has_method("play"):
		_sfx.call("play", sfx_name)


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
