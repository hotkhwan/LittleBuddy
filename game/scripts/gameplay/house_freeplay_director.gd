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
const VoiceBridge := preload("res://scripts/voice/voice_bridge.gd")
const Words := preload("res://scripts/gameplay/house_freeplay_words.gd")
const GestureHintScript := preload("res://scripts/onboarding/gesture_hint.gd")
const HouseRoute := preload("res://scripts/house/house_route.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const DropZoneScript := preload("res://scripts/gameplay/drop_zone.gd")
const HouseStageScript := preload("res://scripts/gameplay/house_stage.gd")
const PoseModifierScript := preload("res://scripts/interaction/pose_modifier.gd")
const AffordanceLayerScript := preload("res://scripts/interaction/affordance_layer.gd")
const HouseActs := preload("res://scripts/gameplay/house_freeplay_acts.gd")
## The break card's host (`break_host.gd`): holds the room, shows the card,
## gives the room back. See "The break card" below.
const BreakHostScript := preload("res://scripts/session/break_host.gd")

## The care close-up (`care_overlay.gd`) is the lead's and is CALLED, never
## edited: Free Play mounts its own instance under the world's `UI` layer.
const CARE_OVERLAY_SCRIPT_PATH: String = "res://scripts/care/care_overlay.gd"
## The entitlement service, read-only: which rooms Free Play may open today.
const ENTITLEMENT_SERVICE_PATH: String = "res://scripts/entitlement/entitlement_service.gd"
const ENTITLEMENT_IDS_PATH: String = "res://scripts/entitlement/entitlement_ids.gd"

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

## -- Free Play acts (see `_act_at()`) --
## Free Play's own care close-up, built on first use under the world's UI.
var _care: Control = null
var _care_child: Node = null
var _care_kind: String = ""
var _care_elapsed: float = 0.0
## The feeding portrait -- the camera on Bunny's real face -- is on; undone the
## moment the close-up closes, so nothing can leave the shot parked on his nose.
var _portrait_on: bool = false
## What Bunny was doing before a close-up took him (sitting at the table,
## standing about), handed back to him afterwards.
var _care_prev_activity: String = ""
## The surface the open close-up is happening at ("bath", "sink", ""), so the
## bath can be followed by the towel.
var _care_surface: String = ""
## The surface Bunny was last set down on ("table", "bed", "sofa", "bath") and
## the node that is him. Cleared the moment he is picked up again. This is how
## the table knows he is sitting at it when his food arrives.
var _child_at: String = ""
var _child_at_node: Node = null
## Aliz's held pose (sit, hands up), a modifier on her skeleton. Null without a rig.
var _pose: SkeletonModifier3D = null
## While she sits: where to stand her back up, and her saved collision mask.
var _seat: Dictionary = {}
var _hands_up_left: float = 0.0
## A landing in flight onto furniture: what to do with the thing when it lands.
var _pending_landing: Dictionary = {}
## Props recorded inside a storage model: node instance id -> local storage id.
var _stored: Dictionary = {}
## Transient bubbles / drops, ticked from `step()`.
var _sparkles: Array = []
## Rooms the entitlement says are open; empty means "all of them".
var _entitlements: Object = null
var _entitlements_resolved: bool = false
## The break card's host, and how long Aliz has been calm since the clock said
## it was time. See "The break card".
var _break: Node = null
var _calm_seconds: float = 0.0


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
	if _character != null and _character.has_signal("move_started"):
		_character.connect("move_started", _on_move_started)
	if _world.has_signal("room_entered"):
		_world.connect("room_entered", _on_room_entered)
	_install_room_gate()
	_break = BreakHostScript.new()
	_break.name = "BreakHost"
	add_child(_break)
	_break.call("bind", _world, _hud)
	if _character != null and _character.has_method("get_carry_controller"):
		var carry: Node = _character.call("get_carry_controller")
		if carry != null:
			if not carry.is_connected("carry_started", _on_object_taken):
				carry.connect("carry_started", _on_object_taken)
			if not carry.is_connected("carry_ended", _on_landed):
				carry.connect("carry_ended", _on_landed)

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
	_step_acts(delta)
	_step_break(delta)
	if _break != null and bool(_break.call("is_open")):
		# A pointing hand over the break card would ask for a tap the card is
		# there to take a break from.
		_idle = 0.0
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
		# land in the room the child has just left. Unless the door is one this
		# session keeps for later -- then the transition controller has refused
		# it and the kind word is the whole event.
		_say_soon_if_locked(target_id)
		return
	var done: Dictionary = _act_at(target_id)
	if bool(done.get("handled", false)):
		var line: String = String(done.get("say", ""))
		if not line.is_empty():
			if _hud != null:
				_hud.call("show_encouragement", line)
			_speak(line, false)
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


## Opens or shuts a container the child has just walked up to.
##
## Asks the ROOM, by semantic id, and does nothing at all when the target is not
## a container -- so this stays one branch rather than a list of cabinet names,
## and a new drawer added to `HouseLayout.storages()` works here with no edit.
func _toggle_storage_if_container(target_id: String) -> bool:
	if _world == null or not _world.has_method("get_current_room"):
		return false
	var room: Node = _world.call("get_current_room")
	if room == null or not room.has_method("is_openable"):
		return false
	var local_id: String = _local_of(target_id)
	if not bool(room.call("is_openable", local_id)):
		return false
	var now_open: bool = bool(room.call("toggle_open", local_id))
	if _hud != null:
		_hud.call("show_encouragement", "Open!" if now_open else "Closed!")
	_speak("open" if now_open else "close", false)
	return true


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
	# No pad discs on the floor in Free Play. They read as flat grey shadows
	# under the toy box and the bath (owner feedback, 2026-09-20), and the one
	# for a room with no focus prop hovered in the middle of the NEXT room. The
	# zones stay -- a drag still lands in them -- and the PLACE badge now says
	# where a carried thing goes.
	if _stage.has_method("clear_markers"):
		_stage.call("clear_markers")
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
			if zone.has_method("set_marker_visible"):
				zone.call("set_marker_visible", false)
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
	var kept: Array = []
	var in_hand: Node = _character.call("get_carried_node") \
			if _character != null and _character.has_method("get_carried_node") else null
	for node: Variant in _draggables:
		if not (node is Node) or not is_instance_valid(node as Node):
			continue
		if node == in_hand:
			# It travels with her. Freeing the thing in her hand at the door is
			# how a teddy vanished between the bedroom and the shelf it was
			# being carried to.
			kept.append(node)
			continue
		_forget_stored(node as Node)
		if (node as Node).is_inside_tree():
			(node as Node).queue_free()
		else:
			# Deferred deletion needs an idle frame, and the headless runner
			# never has one -- free a detached node outright so it cannot leak.
			(node as Node).free()
	_draggables = kept


## A prop that is about to be freed leaves the storage model it was in, so the
## box does not keep counting a teddy that no longer exists.
func _forget_stored(node: Node) -> void:
	var id: int = node.get_instance_id()
	if not _stored.has(id):
		return
	var local_id: String = String(_stored[id])
	_stored.erase(id)
	if _world == null or not _world.has_method("get_room"):
		return
	for room_id: String in HouseLayout.room_ids():
		var room: Node = _world.call("get_room", room_id)
		if room == null or not room.has_method("get_storage"):
			continue
		var model: RefCounted = room.call("get_storage", local_id)
		if model != null and model.has_method("remove"):
			var object_id: Variant = node.get("object_id")
			model.call("remove", String(object_id) if object_id != null else node.name)


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


## -- Free Play acts ---------------------------------------------------------------
##
## What actually happens when Aliz reaches a thing. The DECISION is
## `house_freeplay_acts.gd`'s (pure, tested on dictionaries); this is the doing:
## doors swing, the fridge opens, a prop goes into the box, Bunny is laid on the
## bed, the care close-up opens, she sits, she washes her hands. Every act has a
## visible result and a kind word, and none of them can strand the child: the
## close-up times out into its touch fallback, the seat lets go on the next tap,
## a refused landing shakes softly and keeps the thing in her hand.

## How long the hands-up wash lasts, and how long the close-up may sit unplayed
## before it completes itself (the touch fallback `CLAUDE.md` requires: a child
## who cannot manage the gesture is never stuck behind a card).
const WASH_HANDS_SEC: float = 1.0
const CARE_FALLBACK_SEC: float = 14.0
const SPARKLE_SEC: float = 1.6

## The situation at `target_id`, in the acts model's vocabulary.
func describe_situation(target_id: String) -> Dictionary:
	var local_id: String = _local_of(target_id)
	var room: Node = _world.call("get_current_room") if _world != null and _world.has_method("get_current_room") else null
	var target: Node = _world.call("get_target_by_semantic_id", target_id) \
			if _world != null and _world.has_method("get_target_by_semantic_id") else null
	var actions: Array = []
	if target != null and target.has_method("get_supported_actions"):
		actions = target.call("get_supported_actions")
	var situation: Dictionary = {
		"localId": local_id,
		"actions": actions,
		"carrying": AffordanceLayerScript.carrying_kind(_character),
		"isCharacter": target != null and target.get_parent() != null
				and target.get_parent().has_method("satisfy"),
		"openable": room != null and room.has_method("is_openable") and bool(room.call("is_openable", local_id)),
		"isOpen": room != null and room.has_method("is_open") and bool(room.call("is_open", local_id)),
		"canStore": false,
		"station": {},
		"kitchenHeld": "",
		"canFeed": false,
		"canPlaceHere": false,
		"combines": false,
		"childAt": child_surface_now(),
	}
	if bool(situation["openable"]) and String(situation["carrying"]) == "item" and room.has_method("can_store_node"):
		situation["canStore"] = bool(room.call("can_store_node", local_id, _character.call("get_carried_node")))
	var kitchen: RefCounted = _kitchen()
	if kitchen != null and _current_room_id() == HouseLayout.KITCHEN:
		var described: Dictionary = kitchen.call("describe", local_id)
		var held: String = String(kitchen.call("held"))
		situation["kitchenHeld"] = held
		if not String(described.get("role", "")).is_empty():
			described["opens"] = _kitchen_rules().opens(local_id)
			situation["station"] = described
			if not held.is_empty() and held != "none":
				var resting: String = String(described.get("on", ""))
				if resting == "none":
					resting = ""
				var rules: GDScript = _kitchen_rules()
				var combo: String = String(rules.combination(local_id, resting, held))
				situation["combines"] = not combo.is_empty() and combo != "none"
				situation["canPlaceHere"] = bool(rules.can_place(local_id, held, resting)) or bool(situation["combines"])
	if kitchen != null:
		var held_now: String = String(kitchen.call("held"))
		if not held_now.is_empty() and held_now != "none":
			situation["kitchenHeld"] = held_now
			situation["canFeed"] = bool(_kitchen_rules().is_feedable(held_now))
	return situation


## Does the thing at `target_id`. Returns `{"handled": bool, "say": String}`.
func _act_at(target_id: String) -> Dictionary:
	if _world == null:
		return {"handled": false}
	var situation: Dictionary = describe_situation(target_id)
	var decision: Dictionary = HouseActs.decide(situation)
	var act: String = String(decision.get("act", HouseActs.ACT_NONE))
	var local_id: String = String(situation["localId"])
	match act:
		HouseActs.ACT_TOGGLE_OPEN:
			return {"handled": _toggle_storage_if_container(target_id), "say": ""}
		HouseActs.ACT_STORE_ITEM:
			return {"handled": _store_carried_in(local_id), "say": "In it goes!"}
		HouseActs.ACT_PLACE_ON_TABLE:
			return {"handled": _place_carried_on_table(target_id), "say": "On the table!"}
		HouseActs.ACT_PLACE_CHILD:
			return {"handled": _place_child_on(local_id, String(decision.get("activity", ""))),
					"say": "There you go!"}
		HouseActs.ACT_CARE_CHILD:
			return {"handled": _care_for_child(local_id, String(decision.get("careKind", ""))), "say": ""}
		HouseActs.ACT_SIT:
			return {"handled": _sit_on(target_id), "say": "Sitting down!"}
		HouseActs.ACT_WASH_HANDS:
			return {"handled": _wash_hands(target_id), "say": "Splash!"}
		HouseActs.ACT_BUBBLES:
			return {"handled": _bubbles_at(target_id), "say": "Bubbles!"}
		HouseActs.ACT_KITCHEN_OPEN, HouseActs.ACT_KITCHEN_CLOSE, HouseActs.ACT_KITCHEN_TAKE, \
				HouseActs.ACT_KITCHEN_PLACE:
			return _kitchen_act(act, local_id, decision)
		HouseActs.ACT_FEED_CHILD:
			return _feed_child(target_id, decision)
		HouseActs.ACT_CARRY_CHILD:
			return {"handled": _carry_child_at(target_id), "say": "Up you come!"}
		_:
			return {"handled": false, "say": ""}


## Per-frame bookkeeping for the acts: the hands-up timer, the close-up's
## fallback, the sparkles, the seated pose staying put.
func _step_acts(delta: float) -> void:
	var dt: float = maxf(delta, 0.0)
	if _hands_up_left > 0.0:
		_hands_up_left -= dt
		if _hands_up_left <= 0.0 and _pose != null and is_instance_valid(_pose) \
				and String(_pose.call("get_pose")) == PoseModifierScript.POSE_HANDS_UP:
			_pose.call("set_pose", PoseModifierScript.POSE_NONE)
	if is_care_open():
		_care_elapsed += dt
		if _care_elapsed >= CARE_FALLBACK_SEC and _care.has_method("complete_by_touch"):
			_care.call("complete_by_touch")
	if not _sparkles.is_empty():
		var alive: Array = []
		for entry: Dictionary in _sparkles:
			var node: Node3D = entry["node"]
			if not is_instance_valid(node):
				continue
			var left: float = float(entry["left"]) - dt
			if left <= 0.0:
				if node.is_inside_tree():
					node.queue_free()
				else:
					node.free()
				continue
			entry["left"] = left
			var age: float = SPARKLE_SEC - left
			for child: Node in node.get_children():
				if child is Node3D:
					var rise: float = float((child as Node3D).get_meta("rise", 0.3))
					(child as Node3D).position.y = float((child as Node3D).get_meta("baseY", 0.0)) + rise * age
					var fade: float = clampf(1.0 - age / SPARKLE_SEC, 0.0, 1.0)
					(child as Node3D).scale = Vector3.ONE * maxf(fade, 0.05)
			alive.append(entry)
		_sparkles = alive


## -- Doors this session keeps for later ---------------------------------------------

## **Little Days V1 is FREE (owner decision, 2026-09-20).** Every room opens in
## Free Play whatever the entitlement says: no subscription lock, no blocked
## activity, no payment between a child and a finished room. `is_room_open()`
## answers true for every room while this is true. The seam underneath -- the
## entitlement read, the gate installed on the affordance layer and the
## transition controller, the SOON badge in `affordance_rules.gd`, the kind
## "Soon! Ask a grown-up" -- is kept whole and comes back the day this flips,
## which is why `test_freeplay_acts.gd` still drives it with the constant off.
const ROOMS_FREE_IN_V1: bool = true

## Which rooms Free Play may enter with the gate ON, from the entitlement service
## (read only): the bedroom, the kitchen and the feeding loop are always open;
## the bathroom and the living room open with the family entitlement. No
## service, or a broken one, opens everything -- a missing file must never lock
## a child out of her own house.
const ALWAYS_OPEN_ROOMS: Array[String] = ["bedroom", "kitchen"]

## A test seam for the gate's own logic: null follows `ROOMS_FREE_IN_V1`.
var _rooms_free_override: Variant = null


func is_room_open(room_id: String) -> bool:
	if _rooms_free():
		return true
	if ALWAYS_OPEN_ROOMS.has(room_id):
		return true
	var service: Object = _entitlement_service()
	if service == null:
		return true
	var ids: GDScript = load(ENTITLEMENT_IDS_PATH) as GDScript
	if ids == null:
		return true
	return bool(service.call("is_active", ids.FAMILY_CLUB))


func _rooms_free() -> bool:
	if _rooms_free_override != null:
		return bool(_rooms_free_override)
	return ROOMS_FREE_IN_V1


## Tests only: drives the gate seam as if `ROOMS_FREE_IN_V1` were `free_rooms`.
## Null puts the constant back in charge.
func set_rooms_free_for_test(free_rooms: Variant) -> void:
	_rooms_free_override = free_rooms


## A test seam, and the hook a parent-side unlock would use: hand in the
## service to read. Null restores the default (a fresh local service).
func set_entitlement_service(service: Object) -> void:
	_entitlements = service
	_entitlements_resolved = service != null


func _entitlement_service() -> Object:
	if _entitlements_resolved:
		return _entitlements
	_entitlements_resolved = true
	if not ResourceLoader.exists(ENTITLEMENT_SERVICE_PATH):
		return null
	var script: GDScript = load(ENTITLEMENT_SERVICE_PATH) as GDScript
	if script == null:
		return null
	_entitlements = script.new()
	_resolve_services()
	if _save != null and _entitlements.has_method("load_from"):
		_entitlements.call("load_from", _save)
	return _entitlements


func _install_room_gate() -> void:
	var gate: Callable = Callable(self, "is_room_open")
	# The WORLD's layer is the one that lives: the HUD adopts it on its first
	# refresh and frees its own copy, so a gate installed on the HUD's copy at
	# bind time would go with it.
	for layer: Control in [_world_layer(), _affordance_layer()]:
		if layer != null and layer.has_method("set_room_gate"):
			layer.call("set_room_gate", gate)
	var transition: Node = _world.call("get_transition_controller") \
			if _world.has_method("get_transition_controller") else null
	if transition != null and transition.has_method("set_room_gate"):
		transition.call("set_room_gate", gate)


func _world_layer() -> Control:
	if _world != null and _world.has_method("get_affordance_layer"):
		return _world.call("get_affordance_layer")
	return null


func _affordance_layer() -> Control:
	if _hud != null and _hud.has_method("get_affordance_layer"):
		var mine: Control = _hud.call("get_affordance_layer")
		if mine != null:
			return mine
	if _world != null and _world.has_method("get_affordance_layer"):
		return _world.call("get_affordance_layer")
	return null


func _say_soon_if_locked(target_id: String) -> void:
	var room: Node = _world.call("get_current_room") if _world.has_method("get_current_room") else null
	if room == null or not room.has_method("get_door_for_target"):
		return
	var door: Dictionary = room.call("get_door_for_target", target_id)
	var to_room: String = String(door.get("toRoomId", ""))
	if to_room.is_empty() or is_room_open(to_room):
		return
	if _hud != null:
		_hud.call("show_encouragement", "Soon!")
	_speak("Soon! Ask a grown-up.", true)


## -- The break card ----------------------------------------------------------------------
##
## The play-session clock (`play_session.gd`) says when; this says WHERE: only
## when Aliz is calm -- standing still, holding nobody, no close-up, no finger
## on a pickup, no door in flight, not sat on the sofa -- and has been for
## `BREAK_CALM_SEC`. Bunny in her arms means wait: the card never drops him.
## `break_host.gd` then holds the room, shows the card and gives the room back.
const BREAK_CALM_SEC: float = 2.0


func _step_break(delta: float) -> void:
	if _break == null:
		return
	_break.call("step", delta)
	if not bool(_break.call("is_due")):
		_calm_seconds = 0.0
		return
	if not is_calm():
		_calm_seconds = 0.0
		return
	_calm_seconds += maxf(delta, 0.0)
	if _calm_seconds >= BREAK_CALM_SEC:
		_calm_seconds = 0.0
		if bool(_break.call("show")):
			# The pointing hand goes away with the room; it would otherwise sit
			# under the card and come back pointing at the scrim.
			_quieten_nudge()


## True when nothing is mid-way: a safe moment to put a card over the room.
func is_calm() -> bool:
	if is_care_open() or is_seated() or is_washing_hands() or not _pending_landing.is_empty():
		return false
	if _press_started_msec != 0:
		return false
	if _character != null and is_instance_valid(_character):
		if AffordanceLayerScript.carrying_kind(_character) == "child":
			return false
		if _character.has_method("get_state_name"):
			var state: String = String(_character.call("get_state_name"))
			if state == "walking" or state == "disabled":
				return false
			if state == "interacting" and _character.has_method("get_held_action") \
					and String(_character.call("get_held_action")).is_empty():
				return false
	var transition: Node = _world.call("get_transition_controller") \
			if _world != null and _world.has_method("get_transition_controller") else null
	if transition != null and transition.has_method("is_transitioning") \
			and bool(transition.call("is_transitioning")):
		return false
	for node: Variant in _draggables:
		if node is Node and is_instance_valid(node as Node) \
				and (node as Node).has_method("is_interaction_active") \
				and bool((node as Node).call("is_interaction_active")):
			return false
	return true


func get_break_host() -> Node:
	return _break


func get_calm_seconds() -> float:
	return _calm_seconds


## -- Opening, storing, placing -----------------------------------------------------

## Puts the carried prop INTO storage `local_id`: the model records it, the
## carry controller lands it on the container's floor, and it stays draggable
## so it can come out again.
func _store_carried_in(local_id: String) -> bool:
	var room: Node = _world.call("get_current_room")
	var item: Node = _character.call("get_carried_node")
	if room == null or item == null or not room.has_method("store_node"):
		return false
	var slot: int = _stored.size()
	var rest: Variant = room.call("storage_rest_position", local_id, slot)
	if not (rest is Vector3):
		return false
	if not bool(_character.call("put_down_carried", rest)):
		_refuse_landing()
		return false
	var reason: String = String(room.call("store_node", local_id, item))
	if not reason.is_empty():
		return false
	_stored[item.get_instance_id()] = local_id
	_pending_landing = {"node": item, "kind": "item"}
	_watch_landing()
	_play_sfx(SFX_PLACE_SOFT)
	return true


## Sets the carried prop on the table top.
func _place_carried_on_table(target_id: String) -> bool:
	var target: Node = _world.call("get_target_by_semantic_id", target_id)
	var item: Node = _character.call("get_carried_node")
	if not (target is Node3D) or item == null:
		return false
	var top: Vector3 = SpatialUtil.world_position(target as Node3D)
	var box: Vector3 = Vector3(1.0, 0.7, 0.8)
	for child: Node in target.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			box = ((child as CollisionShape3D).shape as BoxShape3D).size
	# The tap box is centred on the prop; its top face is the table top.
	var spot: Vector3 = Vector3(top.x - 0.22 + 0.18 * float(_drops % 3), top.y + box.y * 0.5 + 0.005, top.z + 0.1)
	if not bool(_character.call("put_down_carried", spot)):
		_refuse_landing()
		return false
	_pending_landing = {"node": item, "kind": "item"}
	_watch_landing()
	_play_sfx(SFX_PLACE_SOFT)
	return true


## Picks Bunny up into her arms. Arriving at him with empty hands used to be a
## dead end in Free Play (`house_freeplay_acts.gd` answered `ACT_NONE`): a
## child taps the one character in the house and nothing happens is worse than
## no badge at all. False when her hands are already full, or the target
## cannot be resolved to an actual carryable child.
func _carry_child_at(target_id: String) -> bool:
	if _character == null or not _character.has_method("carry_node") \
			or bool(_character.call("is_carrying_node")):
		return false
	var target: Node = _world.call("get_target_by_semantic_id", target_id) \
			if _world != null and _world.has_method("get_target_by_semantic_id") else null
	if target == null:
		return false
	var child: Node = (target as Node).get_parent() if target is Node else null
	if child == null or not child.has_method("set_carried_by"):
		return false
	return bool(_character.call("carry_node", child, "carryFront"))


## Sets Bunny down on a SURFACE -- the bed, the sofa, the table's front -- and
## poses him for it when he lands. Refused (with a soft shake, and he stays in
## her arms) when the surface is unknown.
func _place_child_on(local_id: String, activity: String) -> bool:
	var child: Node = _character.call("get_carried_node")
	if child == null or not child.has_method("set_carried_by"):
		return false
	var surface: Dictionary = HouseLayout.child_surface(_current_room_id(), local_id)
	if surface.is_empty():
		_refuse_landing()
		return false
	var room: Node3D = _world.call("get_current_room")
	var world_point: Vector3 = SpatialUtil.world_transform(room) * (surface["position"] as Vector3)
	if not bool(_character.call("put_down_carried", world_point, float(surface.get("yaw", 0.0)))):
		_refuse_landing()
		return false
	_pending_landing = {"node": child, "kind": "child", "surface": local_id,
			"activity": activity if not activity.is_empty() else String(surface.get("activity", "idle"))}
	_watch_landing()
	_play_sfx(SFX_PLACE_SOFT)
	return true


func _watch_landing() -> void:
	var carry: Node = _character.call("get_carry_controller")
	if carry != null and not carry.is_connected("carry_ended", _on_landed):
		carry.connect("carry_ended", _on_landed)


func _on_landed(node: Node) -> void:
	if _pending_landing.is_empty() or _pending_landing.get("node", null) != node:
		return
	var landing: Dictionary = _pending_landing
	_pending_landing = {}
	if String(landing.get("kind", "")) == "child" and node.has_method("set_activity"):
		node.call("set_activity", String(landing.get("activity", "idle")))
		_child_at = String(landing.get("surface", ""))
		_child_at_node = node
	elif node.has_method("set_home_position") and node is Node3D:
		# It lives here now: a later slide-home returns it to the shelf, not to
		# the floor it was picked up from.
		node.call("set_home_position", (node as Node3D).position)


## A landing that could not happen: the thing stays in her hand and says so
## with a small shake rather than a word (there is no red X in this game).
func _refuse_landing() -> void:
	var carry: Node = _character.call("get_carry_controller")
	if carry != null and carry.has_method("shake"):
		carry.call("shake")
	if _hud != null:
		_hud.call("show_encouragement", "Not there -- try again!")


## The surface Bunny is sitting or lying on right now, or "" when he is in
## someone's arms, elsewhere, or gone.
func child_surface_now() -> String:
	if _child_at.is_empty() or _child_at_node == null or not is_instance_valid(_child_at_node):
		return ""
	if _child_at_node.has_method("is_carried") and bool(_child_at_node.call("is_carried")):
		return ""
	return _child_at


## Picking a stored prop back up takes it out of the model; picking Bunny up
## takes him off whatever he was set down on.
func _on_object_taken(node: Node) -> void:
	if node == null:
		return
	if node == _child_at_node:
		_child_at = ""
		_child_at_node = null
	var id: int = node.get_instance_id()
	if not _stored.has(id):
		return
	var local_id: String = String(_stored[id])
	_stored.erase(id)
	var room: Node = _world.call("get_current_room")
	if room != null and room.has_method("get_storage"):
		var model: RefCounted = room.call("get_storage", local_id)
		if model != null and model.has_method("remove"):
			var object_id: Variant = node.get("object_id")
			model.call("remove", String(object_id) if object_id != null else node.name)


## -- Sitting, washing, bubbles ------------------------------------------------------

## Aliz sits on the sofa or the bed: the seated pose on her rig, her body
## moved onto the seat, and the movement machine told it is a held `sit` so
## the state reads true. Any new walk request stands her up again.
func _sit_on(target_id: String) -> bool:
	var local_id: String = _local_of(target_id)
	var seat: Dictionary = HouseLayout.caregiver_seat(_current_room_id(), local_id)
	if seat.is_empty() or not (_character is Node3D):
		return false
	_stand_up()
	var room: Node3D = _world.call("get_current_room")
	var stand: Vector3 = SpatialUtil.world_position(_character)
	var spot: Vector3 = SpatialUtil.world_transform(room) * (seat["position"] as Vector3)
	spot.y = maxf(float(seat.get("seatHeight", 0.45)) - HouseLayout.HIP_SEATED_HEIGHT, HouseLayout.FLOOR_Y)
	_seat = {"targetId": target_id, "stand": stand, "mask": _character.get("collision_mask")}
	# Through the sofa's front, not against it: the body is inside the collider
	# while she sits, and must not be pushed out of it every physics step.
	_character.set("collision_mask", 0)
	SpatialUtil.set_world_position(_character, spot)
	_character.rotation.y = float(seat.get("yaw", 0.0))
	_character.call("play_action", "sit")
	var pose: SkeletonModifier3D = _pose_modifier()
	if pose != null:
		pose.call("set_pose", PoseModifierScript.POSE_SIT)
	return true


func is_seated() -> bool:
	return not _seat.is_empty()


func _stand_up() -> void:
	if _seat.is_empty():
		return
	var seat: Dictionary = _seat
	_seat = {}
	if _character is Node3D:
		_character.set("collision_mask", seat.get("mask", 0))
		SpatialUtil.set_world_position(_character, seat["stand"] as Vector3)
		if _character.has_method("release_action"):
			_character.call("release_action")
	var pose: SkeletonModifier3D = _pose_modifier()
	if pose != null and String(pose.call("get_pose")) == PoseModifierScript.POSE_SIT:
		pose.call("set_pose", PoseModifierScript.POSE_NONE)


func _on_move_started(_target_id: String) -> void:
	if not _running:
		return
	_stand_up()
	if _hands_up_left > 0.0:
		_hands_up_left = 0.0
		var pose: SkeletonModifier3D = _pose_modifier()
		if pose != null:
			pose.call("set_pose", PoseModifierScript.POSE_NONE)


## Hands up under the tap for a second, and a splash of drops.
func _wash_hands(target_id: String) -> bool:
	_hands_up_left = WASH_HANDS_SEC
	var pose: SkeletonModifier3D = _pose_modifier()
	if pose != null:
		pose.call("set_pose", PoseModifierScript.POSE_HANDS_UP)
	_character.call("play_action", "brushTeeth", WASH_HANDS_SEC)
	var target: Node = _world.call("get_target_by_semantic_id", target_id)
	if target is Node3D:
		_sparkle_at(SpatialUtil.world_position(target as Node3D) + Vector3(0.0, 0.55, 0.15), 4, 0.02)
	return true


func is_washing_hands() -> bool:
	return _hands_up_left > 0.0


## Soap bubbles rise out of the bath.
func _bubbles_at(target_id: String) -> bool:
	var target: Node = _world.call("get_target_by_semantic_id", target_id)
	if not (target is Node3D):
		return false
	_sparkle_at(SpatialUtil.world_position(target as Node3D) + Vector3(0.0, 0.55, 0.0), 6, 0.05)
	_character.call("play_action", "clap")
	return true


func get_sparkle_count() -> int:
	return _sparkles.size()


## A puff of cream spheres that rise and fade. Transient, unlit-cheap, never a
## light or a particle system.
func _sparkle_at(where: Vector3, count: int, radius: float) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Sparkle"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.965, 0.898, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	for index: int in range(count):
		var bubble := MeshInstance3D.new()
		bubble.mesh = mesh
		bubble.material_override = material
		var angle: float = TAU * float(index) / float(maxi(count, 1))
		bubble.position = Vector3(cos(angle) * 0.12, 0.02 * float(index), sin(angle) * 0.08)
		bubble.set_meta("baseY", bubble.position.y)
		bubble.set_meta("rise", 0.25 + 0.05 * float(index % 3))
		bubble.scale = Vector3.ONE * (0.7 + 0.15 * float(index % 3))
		root.add_child(bubble)
	var room: Node = _world.call("get_current_room")
	if room != null:
		room.add_child(root)
		SpatialUtil.set_world_position(root, where)
	else:
		add_child(root)
		root.position = where
	_sparkles.append({"node": root, "left": SPARKLE_SEC})


func _pose_modifier() -> SkeletonModifier3D:
	if _pose != null and is_instance_valid(_pose):
		return _pose
	if _character == null:
		return null
	_pose = PoseModifierScript.for_character(_character)
	return _pose


## -- The care close-up, from Free Play ---------------------------------------------

## Opens the lead's care overlay on Bunny for `care_kind` at `surface`. For
## the bath he is first set down IN the tub. The room's input is held while
## the card is up and given back when it closes, and the close-up completes
## itself after `CARE_FALLBACK_SEC` if the gesture never comes.
func _care_for_child(surface: String, care_kind: String) -> bool:
	var child: Node = _character.call("get_carried_node")
	if child == null or not child.has_method("satisfy"):
		return false
	var care: Control = _ensure_care_overlay()
	if care == null:
		return false
	if surface == "bath":
		_place_child_on(surface, "bath")
	_care_child = child
	_care_kind = care_kind
	_care_surface = surface
	_care_elapsed = 0.0
	_care_prev_activity = String(child.call("get_activity")) if child.has_method("get_activity") else ""
	if child.has_method("set_bubble_suppressed"):
		child.call("set_bubble_suppressed", true)
	if surface != "bath" and child.has_method("set_activity"):
		child.call("set_activity", "bath")
	if _hud != null and _hud.has_method("set_narration_covered"):
		_hud.call("set_narration_covered", true)
	_set_room_input(false)
	care.visible = true
	care.call("begin", care_kind)
	_speak(String(care.call("word_for", care_kind)) if care.has_method("word_for") else "wash", true)
	return true


func is_care_open() -> bool:
	return _care != null and is_instance_valid(_care) and _care.visible


func get_care_overlay() -> Control:
	return _care


func _ensure_care_overlay() -> Control:
	if _care != null and is_instance_valid(_care):
		return _care
	if not ResourceLoader.exists(CARE_OVERLAY_SCRIPT_PATH):
		return null
	var script: GDScript = load(CARE_OVERLAY_SCRIPT_PATH) as GDScript
	if script == null:
		return null
	var care: Control = script.new()
	var ui: Node = _world.get_node_or_null("UI")
	if ui != null:
		ui.add_child(care)
		# Same rule as the level director (owner playtest 2026-09-21): the
		# HUD stays above the full-rect close-up so Home keeps working.
		if _hud != null and is_instance_valid(_hud) and _hud.get_parent() == ui:
			ui.move_child(_hud, ui.get_child_count() - 1)
	else:
		add_child(care)
	care.call("build")
	care.visible = false
	care.connect("care_completed", _on_care_completed)
	_care = care
	return care


func _on_care_completed(care_kind: String) -> void:
	# Out of the bath, the towel: the same child, the same held room, straight
	# into the next act, so a bath never ends with a wet Bunny.
	var follow_up: String = HouseActs.care_follow_up(_care_surface, care_kind)
	if not follow_up.is_empty() and _care_child != null and is_instance_valid(_care_child) \
			and _care != null and is_instance_valid(_care):
		_care_kind = follow_up
		_care_elapsed = 0.0
		if _care_child.has_method("satisfy"):
			_care_child.call("satisfy", "dirty", 40.0)
		_care.visible = true
		_care.call("begin", follow_up)
		_speak(String(_care.call("word_for", follow_up)) if _care.has_method("word_for") else follow_up, true)
		return
	if _care != null:
		_care.visible = false
	_end_portrait()
	var child: Node = _care_child
	var previous: String = _care_prev_activity
	_care_child = null
	_care_kind = ""
	_care_surface = ""
	_care_prev_activity = ""
	if _hud != null and _hud.has_method("set_narration_covered"):
		_hud.call("set_narration_covered", false)
	_set_room_input(true)
	if child != null and is_instance_valid(child):
		if child.has_method("set_bubble_suppressed"):
			child.call("set_bubble_suppressed", false)
		# His REAL stats move, so the need goes away rather than a line
		# claiming it did. Free Play awards nothing for it.
		if child.has_method("satisfy"):
			match care_kind:
				"giveBottle", "giveFood":
					child.call("satisfy", "hungry", 70.0)
				"brushTeeth", "washFace", "dryFace":
					child.call("satisfy", "dirty", 40.0)
		if child.has_method("set_activity"):
			var carried: bool = child.has_method("is_carried") and bool(child.call("is_carried"))
			if carried:
				# Back in her arms he stays carried.
				child.call("set_activity", "carried")
			elif care_kind == "giveBottle" or care_kind == "giveFood":
				# Fed where he sat: back to sitting at the table, or standing
				# about, whichever he was doing when the food arrived.
				child.call("set_activity", previous if not previous.is_empty() else "idle")
			# In the tub he stays in the bath.
	if care_kind == "giveBottle" or care_kind == "giveFood":
		# The pantry refills: what the meal was made from is back in the fridge
		# and on the counter, so the child can do the whole thing again.
		var kitchen: RefCounted = _kitchen()
		if kitchen != null and kitchen.has_method("restock"):
			kitchen.call("restock")
	var line: String = "So fresh!"
	match care_kind:
		"brushTeeth":
			line = "All clean!"
		"dryFace":
			line = "Nice and dry!"
		"giveBottle", "giveFood":
			line = "Yum! Thank you!"
	if _hud != null:
		_hud.call("show_encouragement", line)
	_speak(line, false)
	_play_sfx(SFX_PLACE_SOFT)


## -- The feeding portrait ---------------------------------------------------------
##
## The bottle and the spoon are the acts performed on Bunny's REAL face, so they
## are the ones that put the camera on him: `focus_portrait()` fits his head and
## the overlay is handed `_mouth_world_point` so its hold target is his actual
## mouth, projected, every frame -- the same arrangement `house_level_director.gd`
## uses for Mission 01. Both are undone when the close-up closes. Nothing here is
## required for the act to be playable: with no rig, no socket or no camera the
## overlay falls back to its drawn mouth and the camera stays where it was.
const PORTRAIT_RADIUS: float = 0.42
const PORTRAIT_HEAD_CLEARANCE: float = 0.30


func _begin_portrait(care: Control) -> void:
	_portrait_on = false
	if care != null and care.has_method("set_mouth_provider"):
		care.call("set_mouth_provider", Callable(self, "_mouth_world_point"))
	var mouth: Variant = _mouth_world_point()
	var camera: Object = _world.call("get_camera") if _world != null and _world.has_method("get_camera") else null
	if camera == null or not camera.has_method("focus_portrait") or not (mouth is Vector3):
		return
	var floor_y: float = 0.0
	if camera.has_method("get_room_framing"):
		floor_y = float((camera.call("get_room_framing") as Dictionary).get("floorY", 0.0))
	var subject_height: float = maxf(float((mouth as Vector3).y) - floor_y + PORTRAIT_HEAD_CLEARANCE, 0.45)
	camera.call("focus_portrait", mouth, PORTRAIT_RADIUS, subject_height)
	_portrait_on = true


func _end_portrait() -> void:
	if _care != null and is_instance_valid(_care) and _care.has_method("clear_mouth_provider"):
		_care.call("clear_mouth_provider")
	if not _portrait_on:
		return
	_portrait_on = false
	if _world != null and _world.has_method("restore_room_frame"):
		_world.call("restore_room_frame")


func is_portrait_on() -> bool:
	return _portrait_on


## Bunny's mouth in world space, or null when the character cannot answer (no
## rig, no socket). Bound into the overlay as a `Callable`, re-asked every frame.
func _mouth_world_point() -> Variant:
	var child: Node = _care_child
	if child == null or not is_instance_valid(child):
		return null
	var model: Node = child.get_node_or_null("Model")
	if model == null or not model.has_method("get_mouth_position"):
		return null
	if model.has_method("has_socket") and not bool(model.call("has_socket", "mouth")):
		return null
	var at: Vector3 = model.call("get_mouth_position")
	if not (is_finite(at.x) and is_finite(at.y) and is_finite(at.z)):
		return null
	return at


func _set_room_input(enabled: bool) -> void:
	if _nav != null and _nav.get("taps_enabled") != null:
		_nav.set("taps_enabled", enabled)
	if _character != null and _character.has_method("set_disabled"):
		_character.call("set_disabled", not enabled)


## -- The kitchen, in Free Play -----------------------------------------------------

func _kitchen() -> RefCounted:
	if _world == null or not _world.has_method("get_kitchen_state"):
		return null
	return _world.call("get_kitchen_state")


func _kitchen_rules() -> GDScript:
	return load("res://scripts/kitchen/kitchen_rules.gd") as GDScript


func _kitchen_act(act: String, station: String, decision: Dictionary) -> Dictionary:
	var kitchen: RefCounted = _kitchen()
	if kitchen == null:
		return {"handled": false, "say": ""}
	var report: Dictionary = {}
	match act:
		HouseActs.ACT_KITCHEN_OPEN:
			report = kitchen.call("set_open", station, true)
		HouseActs.ACT_KITCHEN_CLOSE:
			report = kitchen.call("set_open", station, false)
		HouseActs.ACT_KITCHEN_TAKE:
			report = kitchen.call("take", station, String(decision.get("item", "")))
			if bool(report.get("ok", false)):
				_character.call("play_action", "pickUp")
		HouseActs.ACT_KITCHEN_PLACE:
			report = kitchen.call("place", station)
			if bool(report.get("ok", false)):
				_character.call("play_action", "give")
				var gesture: String = String(report.get("gesture", ""))
				if not gesture.is_empty():
					_open_mix(gesture, String(report.get("result", "")))
	_play_sfx(SFX_PLACE_SOFT)
	return {"handled": true, "say": String(report.get("say", ""))}


## The counter's preparation opens the same close-up the mission uses (`MIX`),
## when the overlay knows the gesture; a gesture it does not have is simply the
## combining, already done.
func _open_mix(gesture: String, result: String) -> void:
	var care: Control = _ensure_care_overlay()
	if care == null:
		return
	var known: Variant = care.get("COPY")
	if not (known is Dictionary) or not (known as Dictionary).has(gesture):
		return
	_care_child = null
	_care_kind = gesture
	_care_elapsed = 0.0
	if _hud != null and _hud.has_method("set_narration_covered"):
		_hud.call("set_narration_covered", true)
	_set_room_input(false)
	care.visible = true
	care.call("begin", gesture)
	if not result.is_empty():
		var word: String = String((load("res://scripts/kitchen/kitchen_items.gd") as GDScript).word_for(result))
		if _hud != null:
			_hud.call("show_word", word, "")


## Bunny's meal, from Free Play: the REAL feeding close-up (`giveBottle` for
## the milk, `giveFood` for a spoon-fed dish), on his real face, exactly the one
## Mission 01 ends with. Reached two ways: Aliz arrives at Bunny with a meal in
## her hand, or she brings the meal to the table he is sitting at. The kitchen
## hands the food over first, so the close-up can never open for a meal that
## was not made; his hunger moves when the close-up completes, in
## `_on_care_completed()`, and the pantry refills so it can happen again.
func _feed_child(target_id: String, decision: Dictionary = {}) -> Dictionary:
	var kitchen: RefCounted = _kitchen()
	if kitchen == null:
		return {"handled": false, "say": ""}
	var child: Node = null
	if bool(decision.get("atTable", false)):
		child = _child_at_node if child_surface_now() == "table" else null
	else:
		var target: Node = _world.call("get_target_by_semantic_id", target_id)
		child = target.get_parent() if target != null else null
	if child == null or not child.has_method("satisfy"):
		return {"handled": false, "say": ""}
	var care: Control = _ensure_care_overlay()
	if care == null:
		# No close-up to open: the meal is still given, and still counts.
		var plain: Dictionary = kitchen.call("give_to_bunny")
		if bool(plain.get("ok", false)):
			child.call("satisfy", "hungry", 70.0)
			if kitchen.has_method("restock"):
				kitchen.call("restock")
		return {"handled": true, "say": String(plain.get("say", ""))}
	var report: Dictionary = kitchen.call("give_to_bunny")
	if not bool(report.get("ok", false)):
		return {"handled": true, "say": String(report.get("say", ""))}
	var item: String = String(report.get("item", ""))
	var kind: String = "giveBottle"
	var known: Variant = care.get("COPY")
	if item != "bottleOfMilk" and known is Dictionary and (known as Dictionary).has("giveFood"):
		kind = "giveFood"
	_care_child = child
	_care_kind = kind
	_care_elapsed = 0.0
	_care_prev_activity = String(child.call("get_activity")) if child.has_method("get_activity") else ""
	if child.has_method("set_bubble_suppressed"):
		child.call("set_bubble_suppressed", true)
	if child.has_method("set_activity"):
		child.call("set_activity", "feeding", kind)
	if _hud != null and _hud.has_method("set_narration_covered"):
		_hud.call("set_narration_covered", true)
	_set_room_input(false)
	_begin_portrait(care)
	care.visible = true
	care.call("begin", kind)
	_character.call("play_action", "give")
	_play_sfx(SFX_PLACE_SOFT)
	_speak(String(care.call("word_for", kind)) if care.has_method("word_for") else "eat", true)
	return {"handled": true, "say": ""}


static func _local_of(target_id: String) -> String:
	return target_id.get_slice(".", target_id.get_slice_count(".") - 1)


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
	# The voice pack first (2026-09-20): a line that is one of the 36 recorded
	# lines ("Thank you!", "Let's tidy up!") plays the recording, anything else
	# is the device voice under the pack's queue. `interrupt` keeps its meaning;
	# a non-interrupting line is a reaction that queues and is protected.
	# Without the `Voice` autoload this is the TtsService call it always was.
	if VoiceBridge.say_text(self, line, {"interrupt": interrupt, "queue": not interrupt, "reaction": not interrupt}):
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
