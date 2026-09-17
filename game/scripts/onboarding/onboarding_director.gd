extends Node

## First run: the half-minute in which a four-year-old who has never seen this
## game finds out that the screen can be touched.
##
## ## What the child actually gets
##
## A mint ring pulses around Little Buddy and he waves: "Hi! I am Little Buddy."
## A cream pointing hand then falls onto a mint ring on an empty patch of floor
## and a ripple runs out from it -- "Tap the floor. I will walk!" -- and he walks
## there. The hand moves onto a real piece of furniture and names it: "Now tap
## the bed!" The child taps, he walks over and uses it. The hand then drags a
## peach token across the screen leaving a dotted trail: "You can move things."
## "Now let's play!" -- and everything fades.
##
## Thirty-two seconds if the child touches nothing at all; less if they don't.
##
## There is no Skip button, because Skip is a word. `onboarding_plan.gd` explains
## the escape hatches: every step times out, an early success advances
## immediately, and world input is **never** switched off, so a child who ignores
## the whole thing is simply playing already.
##
## ## Where it runs, and why not at launch
##
## On the first entry to the **house**, in either Story or Free Play -- not on the
## title screen and not in the Baby Room. Two of the three things being taught
## (tap-to-walk, tap-an-object) only exist where there is a character who walks,
## and that is Chapter 3. A brand new profile (`currentChapter: "ch1"`) routes to
## the Baby Room first, so in practice first-run plays the first time a child
## presses **Free Play**, or the first time Story reaches Chapter 3. Teaching
## tap-to-walk over a scene that has no walking would be a lie about the game.
##
## ## Composition, not an autoload
##
## `HouseWorld` builds this on its first frame and hands itself in, exactly as it
## does for the level director. Everything else -- TTS, the save file -- is
## duck-typed and optional, and can be injected for a test.
##
## ## Headless
##
## `_ready()` never fires for a node added to the root in the `--script` runner,
## so all the work is behind `bind()`, `start()` and `step(delta)`, and
## `_process()` does nothing but forward to `step()`. A test drives an entire
## first run by calling `step()` in a loop, with no frames and no input.

const Plan := preload("res://scripts/onboarding/onboarding_plan.gd")
const GestureHintScript := preload("res://scripts/onboarding/gesture_hint.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const HouseRoute := preload("res://scripts/house/house_route.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## The locked palette (ART_BIBLE section 3).
const CREAM: Color = Color("#FFF6E5")
const INK: Color = Color("#59422B")

## One short sentence, never a paragraph. It is there for the adult in the room
## and as reinforcement; the voice carries the meaning.
const CAPTION_FONT_SIZE: int = 40

## Fraction of a step's timeout after which Little Buddy does it himself, so the
## child SEES the gesture work even if they never touch the screen. The step
## still ends at its own timeout; this only fills the silence with a
## demonstration.
const DEMONSTRATE_AT: float = 0.6

## Where the "tap the floor" ring goes, relative to the room's centre line: well
## across the room from wherever Little Buddy is standing, and roughly level with
## him. See `_resolve_hint_points()` for why sideways rather than forwards.
const FLOOR_HINT_SIDEWAYS: float = 1.35
const FLOOR_HINT_FORWARD: float = 0.9
## Keeps that ring off the walls whatever corner he starts in.
const FLOOR_HINT_MARGIN: float = 0.6

## The demonstrated drag. Low enough to be clear of the caption, and measured
## against the screen HEIGHT so the span is the same physical gesture on a
## 4:3 iPad and on an ultra-wide landscape phone.
const DRAG_SPAN_RATIO: float = 0.44
const DRAG_HEIGHT_RATIO: float = 0.68

## Fallback screen size when there is no viewport (the headless runner).
const REFERENCE_SIZE: Vector2 = Vector2(1366.0, 1024.0)

signal step_changed(step_id: String)
signal finished()

var _world: Node = null
var _character: Node = null
var _camera: Camera3D = null
var _nav: Node = null

var _layer: Control = null
var _hint: Control = null
var _caption: Label = null

var _tts: Object = null
var _save: Object = null
var _save_injected: bool = false

var _bound: bool = false
var _running: bool = false
var _done: bool = false
var _index: int = -1
var _elapsed: float = 0.0
var _satisfied: bool = false
var _demonstrated: bool = false

## The two things the hints point at, resolved once per run from the room the
## child is really standing in.
var _floor_point: Vector3 = Vector3.ZERO
var _thing_id: String = ""
var _thing_name: String = ""

var _spoken: Array[String] = []


## -- Wiring --------------------------------------------------------------------

## The world hands itself in. Idempotent; safe against a half-built world.
func bind(world: Node) -> void:
	if _bound:
		return
	_bound = true
	_world = world
	if _world == null:
		return

	if _world.has_method("get_character"):
		_character = _world.call("get_character")
	if _world.has_method("get_camera"):
		_camera = _world.call("get_camera") as Camera3D
	_nav = _world.get_node_or_null("NavigationController")

	_build_overlay()

	if _character != null:
		if _character.has_signal("move_started"):
			_character.connect("move_started", _on_move_started)
		if _character.has_signal("interaction_ready"):
			_character.connect("interaction_ready", _on_interaction_ready)
	if _nav != null and _nav.has_signal("floor_tapped"):
		_nav.connect("floor_tapped", _on_floor_tapped)


func _build_overlay() -> void:
	_layer = Control.new()
	_layer.name = "OnboardingOverlay"
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# `set_anchors_preset()` would keep the 0x0 rect this control currently has
	# and every label inside it would wrap to one character per line. That has
	# bitten this project twice; it does not get a third time.
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_caption = Label.new()
	_caption.name = "Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", CAPTION_FONT_SIZE)
	_caption.add_theme_color_override("font_color", CREAM)
	# An ink outline rather than a shadow: readable over a cream wall and a
	# dusty-blue floor alike, and `#000000` is banned everywhere.
	_caption.add_theme_color_override("font_outline_color", INK)
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_caption.offset_left = 140.0
	_caption.offset_top = 52.0
	_caption.offset_right = -140.0
	_caption.offset_bottom = 156.0
	_layer.add_child(_caption)

	_hint = GestureHintScript.new()
	_hint.call("build")
	_layer.add_child(_hint)

	var ui: Node = _world.get_node_or_null("UI") if _world != null else null
	if ui != null:
		ui.add_child(_layer)
	else:
		add_child(_layer)


## TTS. Optional everywhere: a build with no voice still shows every gesture.
func set_tts(tts: Object) -> void:
	_tts = tts


## The save layer completion is written to. Injected by a test; resolved from
## `/root/SaveService` otherwise.
func set_save_service(save_service: Object) -> void:
	_save = save_service
	_save_injected = true


func get_save_service() -> Object:
	if not _save_injected and _save == null:
		_save = _autoload("SaveService")
	return _save


## -- The decision --------------------------------------------------------------

## Should first run play at all, for this save?
##
## **No save service means no.** Onboarding that cannot be recorded would play on
## every single launch, and a tutorial a child cannot get past by finishing it is
## worse than no tutorial. It is also what keeps the headless runner -- which
## loads no autoloads -- booting the plain, objective-free house that every
## existing case asserts against.
static func should_run(save_service: Object) -> bool:
	if save_service == null or not save_service.has_method("get_setting"):
		return false
	return Plan.should_run(save_service.call("get_setting", Plan.SETTING_KEY, null))


## The instance-level form of the same question.
func should_run_now() -> bool:
	return should_run(get_save_service())


## -- Session -------------------------------------------------------------------

## Begins first run. Returns false when there is nothing to show, in which case
## the caller should get straight on with the game.
func start() -> bool:
	if _running or _done or _world == null:
		return false
	if _tts == null:
		_tts = _autoload("TtsService")

	_resolve_hint_points()
	# One voice on screen: the world's own status line would otherwise sit above
	# the caption saying something else entirely.
	if _world.has_method("set_status_visible"):
		_world.call("set_status_visible", false)

	_running = true
	_index = -1
	_advance()
	return true


func is_running() -> bool:
	return _running


func is_finished() -> bool:
	return _done


func get_step_index() -> int:
	return _index


func get_step_id() -> String:
	return String(Plan.step_at(_index).get("stepId", ""))


func get_caption() -> String:
	return _caption.text if _caption != null else ""


func get_hint() -> Control:
	return _hint


## Every line this run has spoken, in order. The tests use it to prove that a
## pre-reader is actually told what to do out loud.
func get_spoken_lines() -> Array:
	return _spoken.duplicate()


## The object the "tap a thing" step points at, as a semantic id.
func get_thing_id() -> String:
	return _thing_id


func _process(delta: float) -> void:
	step(delta)


## The per-frame work, callable by hand. `_process()` does nothing else, so a
## headless test drives exactly the same code a device does.
func step(delta: float) -> void:
	if not _running:
		return
	_elapsed += maxf(delta, 0.0)
	_follow_hint()
	if _hint != null:
		_hint.call("step", delta)

	var plan: Dictionary = Plan.step_at(_index)
	var timeout: float = minf(float(plan.get("timeoutSec", 0.0)), Plan.MAX_STEP_SECONDS)

	if _satisfied:
		_advance()
		return
	if not _demonstrated and timeout > 0.0 and _elapsed >= timeout * DEMONSTRATE_AT:
		_demonstrated = true
		_demonstrate(String(plan.get("stepId", "")))
	if timeout <= 0.0 or _elapsed >= timeout:
		# THE escape hatch. Nothing about a step is mandatory; the clock alone is
		# enough to reach the end of first run and have it recorded as done.
		_advance()


## Ends first run, however it got here -- finished, timed out, or abandoned --
## and records it so it never plays again.
func finish() -> void:
	if _done:
		return
	_done = true
	_running = false
	if _hint != null:
		_hint.call("hide_hint")
	if _caption != null:
		_caption.text = ""
	if _layer != null:
		_layer.visible = false
	_remember_done()
	finished.emit()


## -- Steps ---------------------------------------------------------------------

func _advance() -> void:
	if Plan.is_last(_index):
		finish()
		return
	_index += 1
	_elapsed = 0.0
	_satisfied = false
	_demonstrated = false

	var plan: Dictionary = Plan.step_at(_index)
	var step_id: String = String(plan.get("stepId", ""))
	if step_id.is_empty():
		finish()
		return

	var line: String = _speech_for(plan)
	if _caption != null:
		_caption.text = line
	_speak(line)

	var action: String = String(plan.get("characterAction", ""))
	if not action.is_empty() and _character != null and _character.has_method("play_action"):
		_character.call("play_action", action)

	_follow_hint()
	step_changed.emit(step_id)


## The line for a step. Only `tapThing` is dynamic: it names a piece of furniture
## that is really in the room the child is really standing in, so the instruction
## can never point at something that is not there.
func _speech_for(plan: Dictionary) -> String:
	if String(plan.get("stepId", "")) == Plan.STEP_TAP_THING:
		return Plan.tap_thing_speech(_thing_name)
	return String(plan.get("speech", ""))


## Little Buddy does the step himself. Never worth anything and never required --
## it exists so a child who is still working out that the screen responds to
## fingers sees the gesture pay off rather than watching a static picture.
func _demonstrate(step_id: String) -> void:
	if _character == null:
		return
	match step_id:
		Plan.STEP_TAP_FLOOR:
			if _character.has_method("move_to_ground"):
				_character.call("set_disabled", false)
				_character.call("move_to_ground", _floor_point.x, _floor_point.z)
		Plan.STEP_TAP_THING:
			if not _thing_id.is_empty() and _character.has_method("move_to"):
				_character.call("set_disabled", false)
				_character.call("move_to", _thing_id)
		_:
			pass


## -- What the child did --------------------------------------------------------

func _on_floor_tapped(_x: float, _z: float) -> void:
	_satisfy(Plan.REQUIRES_WALK)


func _on_move_started(_target_id: String) -> void:
	_satisfy(Plan.REQUIRES_WALK)


func _on_interaction_ready(target_id: String) -> void:
	if not _running:
		return
	# Any object counts, not only the one the hand was pointing at. A child who
	# tapped the wardrobe instead of the bed has understood the lesson perfectly.
	if String(Plan.step_at(_index).get("requires", "")) != Plan.REQUIRES_ARRIVAL:
		return
	if target_id.strip_edges().is_empty():
		return
	_satisfied = true
	_react_to_arrival(target_id)


func _satisfy(requirement: String) -> void:
	if not _running:
		return
	if String(Plan.step_at(_index).get("requires", "")) != requirement:
		return
	_satisfied = true


## The reward for the one action first run asks for: the object's English word,
## and Little Buddy using it.
func _react_to_arrival(target_id: String) -> void:
	var words: Variant = _free_play_words()
	if words == null:
		return
	var described: Dictionary = words.call("describe", target_id)
	var word: String = String(described.get("word", ""))
	if not word.is_empty():
		if _caption != null:
			_caption.text = word
		_speak(word)
	var action: String = String(described.get("action", ""))
	if not action.is_empty() and _character != null and _character.has_method("play_action"):
		_character.call("play_action", action)


## -- Where the hints point -----------------------------------------------------

## Resolves the floor spot and the object this run will point at, from the room
## the child is actually in. Done once, at `start()`, so the hand does not hop
## between objects mid-step.
func _resolve_hint_points() -> void:
	var here: Vector3 = Vector3.ZERO
	if _character is Node3D:
		here = SpatialUtil.world_position(_character as Node3D)
	var room_id: String = ""
	if _world != null and _world.has_method("get_current_room_id"):
		room_id = String(_world.call("get_current_room_id"))

	# TO THE SIDE, not straight in front.
	#
	# The obvious placement -- a metre towards the camera -- renders as a ring
	# roughly eighty pixels below his feet, and the pointing hand is a hundred and
	# fifty pixels tall, so the hand lands squarely on top of the character. The
	# room is seen from a raised three-quarter angle, so depth is compressed on
	# screen and sideways distance is not: putting the ring across the room reads
	# as a *different place* at a glance. Found by rendering it.
	var point: Vector3 = Vector3(here.x, HouseLayout.FLOOR_Y, here.z + FLOOR_HINT_FORWARD)
	if HouseLayout.has_room(room_id):
		var bounds: Rect2 = HouseLayout.world_floor_bounds(room_id)
		var centre_x: float = bounds.get_center().x
		var side: float = -1.0 if here.x >= centre_x else 1.0
		point.x = clampf(centre_x + side * FLOOR_HINT_SIDEWAYS,
				bounds.position.x + FLOOR_HINT_MARGIN, bounds.end.x - FLOOR_HINT_MARGIN)
		point.z = clampf(here.z, bounds.position.y + FLOOR_HINT_MARGIN,
				bounds.end.y - FLOOR_HINT_MARGIN)
	_floor_point = point

	_thing_id = ""
	_thing_name = ""
	var room: Node = _world.call("get_current_room") if _world.has_method("get_current_room") else null
	if room == null or not room.has_method("get_activity_targets"):
		return
	for target: Variant in room.call("get_activity_targets"):
		if not (target is Node) or not (target as Node).has_method("get_activity_target_id"):
			continue
		var id: String = String((target as Node).call("get_activity_target_id"))
		# Never a door: "tap this and the whole room changes" is a confusing first
		# lesson, and it would move the child out of the room the run set up.
		if id.is_empty() or HouseRoute.is_door_id(id):
			continue
		_thing_id = id
		_thing_name = String((target as Node).get("display_name")).strip_edges()
		if _thing_name.is_empty():
			_thing_name = id
		return


## Keeps the hand on the thing it is pointing at, every frame, because the
## character moves and the camera re-frames.
func _follow_hint() -> void:
	if _hint == null or not _running:
		return
	var gesture: String = String(Plan.step_at(_index).get("gesture", Plan.GESTURE_NONE))
	match gesture:
		Plan.GESTURE_MEET:
			_point_at(_character_middle(), true)
		Plan.GESTURE_TAP_FLOOR:
			_point_at(_floor_point)
		Plan.GESTURE_TAP_TARGET:
			_point_at(_thing_world_position())
		Plan.GESTURE_DRAG:
			var size: Vector2 = _screen_size()
			# Measured off the screen HEIGHT, not its width: on an ultra-wide
			# landscape phone a width-based span puts the two ends so far apart
			# that they read as two separate things rather than one movement.
			var span: float = size.y * DRAG_SPAN_RATIO * 0.5
			var middle: Vector2 = Vector2(size.x * 0.5, size.y * DRAG_HEIGHT_RATIO)
			_hint.call("show_drag", middle - Vector2(span, 0.0), middle + Vector2(span, 0.0))
		_:
			_hint.call("hide_hint")


## Points the hint at a world position. `ring_only` draws the pulse without the
## hand, for the one beat that is about Little Buddy rather than about something
## to touch.
func _point_at(world_point: Variant, ring_only: bool = false) -> void:
	if not (world_point is Vector3):
		_hint.call("hide_hint")
		return
	var screen: Variant = _to_screen(world_point as Vector3)
	if screen == null:
		_hint.call("hide_hint")
		return
	_hint.call("show_ring" if ring_only else "show_tap", screen as Vector2)


## World to screen, or null when there is no live camera -- which is every
## headless test, and a scene that has not been framed yet.
func _to_screen(world_point: Vector3) -> Variant:
	if _camera == null and _world != null and _world.has_method("get_camera"):
		_camera = _world.call("get_camera") as Camera3D
	if _camera == null or not _camera.is_inside_tree():
		return null
	if _camera.is_position_behind(world_point):
		return null
	return _camera.unproject_position(world_point)


## The middle of Little Buddy, so the ring goes AROUND him rather than above his
## head or at his feet. He is 0.85 m tall.
func _character_middle() -> Variant:
	if not (_character is Node3D):
		return null
	return SpatialUtil.world_position(_character as Node3D) + Vector3(0.0, 0.42, 0.0)


func _thing_world_position() -> Variant:
	if _thing_id.is_empty() or _world == null or not _world.has_method("get_target_by_semantic_id"):
		return null
	var target: Node = _world.call("get_target_by_semantic_id", _thing_id)
	if not (target is Node3D):
		return null
	# `global_position` silently reports the origin for a node outside the tree,
	# which in the headless runner is every node -- `spatial_util.gd` exists for
	# exactly this.
	return SpatialUtil.world_position(target as Node3D)


func _screen_size() -> Vector2:
	if _layer != null and _layer.is_inside_tree():
		var rect: Vector2 = _layer.size
		if rect.x > 1.0 and rect.y > 1.0:
			return rect
	return REFERENCE_SIZE


## -- Services (all optional) ---------------------------------------------------

func _speak(text: String) -> void:
	var line: String = text.strip_edges()
	if line.is_empty():
		return
	_spoken.append(line)
	if _tts != null and _tts.has_method("speak"):
		# Interrupting, not queued: the voice must match the picture. A queued
		# line would still be describing the previous gesture while the hand has
		# already moved on, which for a pre-reader is worse than silence.
		_tts.call("speak", line, true)


## Writes `settings.onboardingDone`. No save-schema change was needed:
## `ProfileStore` preserves unknown JSON-safe `settings` keys verbatim, so this
## survives a load/save round trip without `profile_store.gd` knowing about it.
func _remember_done() -> void:
	var save_service: Object = get_save_service()
	if save_service == null or not save_service.has_method("set_setting"):
		return
	save_service.call("set_setting", Plan.SETTING_KEY, true)


## Loaded rather than `preload()`ed so this file still parses if Free Play's word
## table is ever moved; first run then loses the spoken word on arrival and keeps
## everything else.
func _free_play_words() -> Variant:
	var path: String = "res://scripts/gameplay/house_freeplay_words.gd"
	if not ResourceLoader.exists(path):
		return null
	var script: Resource = load(path)
	return script if script is GDScript else null


func _autoload(autoload_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null(NodePath("/root/%s" % autoload_name))
