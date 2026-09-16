extends Node3D

## Wires the 3D Baby Room scene together: baby state, the feedMilk activity,
## reward manager, the teddy comfort object, and the star/prompt/mic UI
## (a CanvasLayer overlay). Connects to autoloads (`SaveService`,
## `SpeechService`, `TtsService`) defensively via get_node_or_null so the
## scene still runs -- touch-only -- even if an autoload is missing or
## incomplete.
##
## Interaction has two independent paths so a missed pick never leaves the
## child stuck:
##   1. Built-in Area3D `input_event` (3D physics picking), enabled here via
##      `Viewport.physics_object_picking = true`. `MilkBottle`/`Teddy` (both
##      `DraggableObject`) use this to start a drag or a tap.
##   2. An explicit `_unhandled_input` raycast fallback using
##      `Camera3D.project_ray_origin/normal` + `intersect_ray`, funnelled into
##      the same tap-delivery latch so it can never double-deliver.

const ENCOURAGEMENT_GREAT: String = "Great!"
const ENCOURAGEMENT_TRY_AGAIN: String = "Try again!"
const ENCOURAGEMENT_DISPLAY_SEC: float = 1.8
const RESTART_DELAY_SEC: float = 2.5
const RESET_HUNGER_VALUE: float = 80.0
const TEDDY_WORD: String = "Teddy!"
const TEDDY_LOVE_PHRASE: String = "I love my teddy!"
const TEDDY_SPEAK_GAP_SEC: float = 1.1
const TEDDY_REACTION_SEC: float = 2.6
const RAY_LENGTH: float = 30.0

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

## Camera framing. Set in code with `look_at_from_position()` rather than trusting a
## hand-written `Transform3D` in the .tscn -- an inverted pitch there previously pushed
## the baby, bottle and teddy entirely below the viewport. Keep these in sync with the
## `transform` on %Camera3D (the .tscn value only drives the editor preview).
const CAMERA_POSITION: Vector3 = Vector3(0.0, 0.95, 2.075)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.315, 0.175)

@onready var _camera: Camera3D = %Camera3D
@onready var _baby_view: BabyView3D = %BabyView
@onready var _milk_bottle: MilkBottle = %MilkBottle
@onready var _teddy: Teddy = %Teddy

@onready var _star_count_label: Label = %StarCountLabel
@onready var _prompt_label: Label = %PromptLabel
@onready var _thai_hint_label: Label = %ThaiHintLabel
@onready var _mic_button: Button = %MicButton
@onready var _listening_label: Label = %ListeningLabel
@onready var _encouragement_label: Label = %EncouragementLabel

var _baby_state: BabyState = BabyState.new()
var _feed_activity: FeedActivity = FeedActivity.new()
var _reward_manager: RewardManager = RewardManager.new()

var _mouth_drop_zone: Area3D = null
var _hug_drop_zone: Area3D = null


func _ready() -> void:
	# Enables Area3D.input_event picking for touch/mouse without requiring
	# any project.godot edits (that file is owned by the foundation agent).
	get_viewport().physics_object_picking = true

	_setup_nursery_props()

	# Guarantees the baby, bottle and teddy are actually framed, regardless of the
	# Transform3D stored in the scene file.
	_camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
	_camera.current = true

	add_child(_feed_activity)
	add_child(_reward_manager)

	_mouth_drop_zone = _create_drop_zone("MouthDropZone")
	_hug_drop_zone = _create_drop_zone("HugDropZone")
	_update_drop_zone_positions()
	_milk_bottle.set_drop_zone(_mouth_drop_zone, DROP_ZONE_RADIUS)
	_teddy.set_drop_zone(_hug_drop_zone, DROP_ZONE_RADIUS)

	_milk_bottle.delivered.connect(_on_milk_delivered)
	_teddy.comforted.connect(_on_teddy_comforted)

	_mic_button.pressed.connect(_on_mic_pressed)

	_feed_activity.setup(_baby_state, _baby_view)
	_feed_activity.state_changed.connect(_on_activity_state_changed)
	_feed_activity.activity_completed.connect(_on_activity_completed)
	_feed_activity.prompt_changed.connect(_on_prompt_changed)

	_reward_manager.star_awarded.connect(_on_star_awarded)

	_connect_speech_service()

	_encouragement_label.visible = false
	_thai_hint_label.visible = false
	_listening_label.visible = false

	_set_star_count(_get_initial_stars())
	_update_mic_visual()

	_feed_activity.start()


func _process(_delta: float) -> void:
	# Cheap (two Vector3 reads/writes); keeps the drop zones glued to the
	# baby's mouth/chest even if BabyView3D's markers move (head tilt, idle
	# bob, etc.) instead of only ever sampling their position once at ready.
	_update_drop_zone_positions()


func _get_initial_stars() -> int:
	var save_service: Node = get_node_or_null("/root/SaveService")
	if save_service != null and save_service.has_method("get_stars"):
		return int(save_service.get_stars())
	return 0


func _connect_speech_service() -> void:
	var speech: Node = get_node_or_null("/root/SpeechService")
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


## -- Drop zones (positioned live from BabyView3D, never hardcoded) ---------

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


## -- Milk (tap or drag-to-mouth) ----------------------------------------

func _on_milk_delivered() -> void:
	_feed_activity.on_milk_delivered()


## -- Teddy (comfort, no stars, not an activity) ------------------------

func _on_teddy_comforted() -> void:
	_baby_view.set_view_state("hugging")
	var tts: Node = get_node_or_null("/root/TtsService")
	if tts != null and tts.has_method("speak"):
		tts.speak(TEDDY_WORD)
		var love_timer: SceneTreeTimer = get_tree().create_timer(TEDDY_SPEAK_GAP_SEC)
		love_timer.timeout.connect(_speak_teddy_love, CONNECT_ONE_SHOT)
	var timer: SceneTreeTimer = get_tree().create_timer(TEDDY_REACTION_SEC)
	timer.timeout.connect(_on_teddy_reaction_finished, CONNECT_ONE_SHOT)


func _speak_teddy_love() -> void:
	var tts: Node = get_node_or_null("/root/TtsService")
	# interrupt=false so this never cuts off "Teddy!" if a slow backend is
	# still finishing it.
	if tts != null and tts.has_method("speak"):
		tts.speak(TEDDY_LOVE_PHRASE, false)


func _on_teddy_reaction_finished() -> void:
	_baby_view.set_view_state(_view_state_for_activity_state(_feed_activity.get_state()))
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
	var speech: Node = get_node_or_null("/root/SpeechService")
	if speech == null or not speech.has_method("request_permission"):
		_show_encouragement(ENCOURAGEMENT_TRY_AGAIN)
		return
	speech.request_permission()


func _on_permission_result(granted: bool) -> void:
	var speech: Node = get_node_or_null("/root/SpeechService")
	if speech == null:
		return
	if granted and speech.has_method("start_listening"):
		speech.start_listening()
	else:
		_show_encouragement(ENCOURAGEMENT_TRY_AGAIN)


func _on_speech_recognized(text: String) -> void:
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


func _update_mic_visual() -> void:
	var speech: Node = get_node_or_null("/root/SpeechService")
	var available: bool = false
	if speech != null and speech.has_method("is_available"):
		available = bool(speech.is_available())
	_mic_button.disabled = not available
	_mic_button.modulate = Color(1.0, 1.0, 1.0, 1.0) if available else Color(1.0, 1.0, 1.0, 0.45)


## -- Feed activity wiring ----------------------------------------------

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
	var phrases: Array = _feed_activity.get_activity_data().get("successPhrases", [])
	if phrases.is_empty():
		return ENCOURAGEMENT_GREAT
	return String(phrases[randi() % phrases.size()])


func _on_prompt_changed(text: String) -> void:
	_prompt_label.text = text
	_update_thai_hint()


func _update_thai_hint() -> void:
	var thai_hints_enabled: bool = true
	var save_service: Node = get_node_or_null("/root/SaveService")
	if save_service != null and save_service.has_method("get_setting"):
		thai_hints_enabled = bool(save_service.get_setting("thaiHints", true))

	var hint_text: String = String(_feed_activity.get_activity_data().get("thaiHint", ""))
	_thai_hint_label.visible = thai_hints_enabled and not hint_text.is_empty()
	_thai_hint_label.text = hint_text


func _on_activity_completed(activity_id: String, stars: int) -> void:
	_reward_manager.award(activity_id, stars)
	var timer: SceneTreeTimer = get_tree().create_timer(RESTART_DELAY_SEC)
	timer.timeout.connect(_restart_activity, CONNECT_ONE_SHOT)


func _restart_activity() -> void:
	_baby_state.set_hunger(RESET_HUNGER_VALUE)
	_milk_bottle.reset_position()
	_feed_activity.start()


## -- Rewards -------------------------------------------------------------

func _on_star_awarded(total: int) -> void:
	_set_star_count(total)


func _set_star_count(total: int) -> void:
	_star_count_label.text = str(total)


## -- Encouragement --------------------------------------------------------

func _show_encouragement(text: String) -> void:
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
## NOT already consumed by GUI controls or by MilkBottle/Teddy's own
## input_event/_input handlers (they call set_input_as_handled() on
## success), so this never double-delivers milk or double-triggers the teddy.
func _unhandled_input(event: InputEvent) -> void:
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
	if collider == _milk_bottle and collider.has_method("try_deliver_from_raycast"):
		collider.try_deliver_from_raycast()
	elif collider == _teddy and collider.has_method("try_trigger_from_raycast"):
		collider.try_trigger_from_raycast()
