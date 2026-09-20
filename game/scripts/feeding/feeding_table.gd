extends Node3D

## THE HIGHCHAIR. Chapter 2's feeding tasks, played close up.
##
## `feedApple`, `feedBanana`, `feedMilk` and `feedWater` used to be a row of
## primitives dragged onto an invisible zone; the owner called the result a
## tap-through shell. This stage is the concept frame
## (`assets/uiGenerated/minigame/feedingConcept.png`) built for real: Bunny in
## a lavender highchair behind a wooden tray, a peeled banana, a plate, a cup,
## the prompt bar above, and a camera that looks at his face.
##
## ## What it is NOT
##
## It is not a second mission system. `MissionRunner` stays the source of
## truth: this node only tells the room *which object reached the mouth*
## (`item_delivered` / `wrong_item`) and the room forwards that to
## `MissionRunner.on_object_chosen()` -- the same call a drop zone makes -- so
## `RewardManager`, `RewardLedger`, stars and stickers behave exactly as before.
## The room passes the task in with `set_task()` and the star total with
## `set_star_count()`; nothing here reads a save file or awards anything.
##
## ## Gestures (see `feeding_rules.gd` for the numbers)
##
##   * APPLE  -- drag to the mouth. On arrival it snaps, Bunny bites three times,
##               sparkle lines, then celebrates.
##   * BANANA -- first tap / drag-down PEELS it (three strips fold down); only a
##               peeled banana can be dragged. Then as the apple.
##   * CUP / BOTTLE -- drag up and HOLD. The cup tips, Bunny drinks, the level
##               drops. Let go early and it glides home, full again.
##   * WRONG ITEM -- Bunny turns his head away with an unhappy face, the item
##               glides back, "Try the apple!". The first mistake halves the
##               task's star; the second switches to guided mode (the right item
##               glows, an arrow points to the mouth). Never a red X.
##   * TOUCH FALLBACK -- after two idle nudges a plain tap on the right item
##               carries it to the mouth. No child is ever stuck on a drag.
##
## ## Bunny
##
## The REAL Bunny (`baby_little_buddy.gd`): life clips `idle` / `fuss` / `eat` /
## `drink` / `celebrate` through his `AnimationPlayer`, faces through
## `set_face_mood()`, the mouth through `get_mouth_position()`. Nothing in the
## character scripts is edited. If the model is not in a build the procedural
## `BabyView3D` sits in the chair instead and every gesture still works.
##
## ## Headless
##
## `build()` is idempotent and runs before `_ready()`, every gesture has a
## programmatic entry point (`begin_drag()`, `drag_to_mouth()`, `end_drag()`,
## `tap_item()`, `advance_hold()`, `nudge()`), and `set_instant(true)` collapses
## every animated sequence to a synchronous call -- which is how the tests prove
## each gesture completes its task exactly once through the runner.

signal item_delivered(object_id: String)
signal wrong_item(object_id: String)
signal half_star(task_id: String)
signal guided_started(task_id: String)
signal task_finished(task_id: String)
signal home_requested()
signal back_requested()
signal encouragement(text: String)

const Rules := preload("res://scripts/feeding/feeding_rules.gd")
const Props := preload("res://scripts/feeding/feeding_props.gd")
const HudScript := preload("res://scripts/feeding/feeding_hud.gd")
const _Palette := preload("res://scripts/ui/palette.gd")
const BabyAvatarScript := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
const BabyViewScript := preload("res://scripts/baby/baby_view_3d.gd")
## The voice pack (2026-09-20): Aliz asks with her learning line, Bunny answers
## with "Yummy!", "More, please!", "Thank you, Aliz!" and sulks with "Hmph!" on
## a wrong item. Every cue is a null-guarded one-liner through `VoiceBridge`;
## without the `Voice` autoload the highchair speaks exactly as it did before.
const VoiceBridge := preload("res://scripts/voice/voice_bridge.gd")
const VoiceCues := preload("res://scripts/voice/voice_cues.gd")

## Stage layout, metres, local. Bunny's mouth sits ~0.45 m up (measured from the
## rig's socket), so the tray is just under his chin and hides his legs.
const BUNNY_POSITION: Vector3 = Vector3(0.0, 0.0, 0.0)
const TRAY_POSITION: Vector3 = Vector3(0.0, 0.22, 0.44)
const TRAY_SIZE: Vector2 = Vector2(1.0, 0.42)
const SLOT_X: Dictionary = {"left": -0.3, "centre": 0.0, "right": 0.3}
const SLOT_Z: float = 0.03
const CAMERA_POSITION: Vector3 = Vector3(0.0, 0.84, 1.36)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.4, 0.08)
const CAMERA_FOV: float = 40.0

## If the socket has not been updated yet (first frame, headless), aim here.
const FALLBACK_MOUTH_LOCAL: Vector3 = Vector3(0.0, 0.452, 0.161)

## A dragged item floats this much toward the camera so a finger never hides it.
const DRAG_LIFT: float = 0.06
## Where a cup sits while a sip is held: base below and in front of the mouth,
## so the tipped spout lands on the lips.
const DRINK_POSE_OFFSET: Vector3 = Vector3(0.0, -0.08, 0.10)
const EAT_POSE_OFFSET: Vector3 = Vector3(0.0, -0.02, 0.05)
const SNAP_SECONDS: float = 0.16
const RETURN_SECONDS: float = 0.42
const TURN_AWAY_DEG: float = 28.0
const TURN_AWAY_SECONDS: float = 1.3
const CELEBRATE_SECONDS: float = 1.4
const AUTO_GLIDE_SECONDS: float = 0.55
const HOP_HEIGHT: float = 0.05

## The bite that is half-way through the meal: Bunny asks for "More, please!".
const HALFWAY_BITE: int = int(ceil(float(Rules.BITES) / 2.0))
const SFX_POP: String = "soft_pop"
const SFX_PICKUP: String = "pickup"
const SFX_RETURN: String = "drop_return"
const SFX_PLACE: String = "place_soft"

var _task: Dictionary = {}
var _target_id: String = ""
var _target_name: String = ""
var _mistakes: int = 0
var _nudges: int = 0
var _delivered: bool = false
var _finished: bool = false
var _active: bool = false
var _generation: int = 0
var _instant: bool = false

var _items: Dictionary = {}
var _slots: Dictionary = {}
var _colors: Dictionary = {}

var _drag_item: Node3D = null
var _drag_plane: Plane = Plane(Vector3.FORWARD, 0.0)
var _drag_pointer: int = -1
var _press_item: Node3D = null
var _press_screen: Vector2 = Vector2.ZERO
var _press_moved: bool = false
var _hold: float = 0.0
var _holding: bool = false
var _idle: float = 0.0

var _bunny: Node3D = null
var _player: AnimationPlayer = null
var _bunny_yaw: float = 0.0
var _camera: Camera3D = null
var _hud: CanvasLayer = null
var _built: bool = false
var _turn_tween: Tween = null


func _ready() -> void:
	build()
	set_active(_active)


## Idempotent. Builds the stage, the camera and the HUD.
func build() -> void:
	if _built:
		return
	_built = true

	add_child(Props.backdrop())
	var chair: Node3D = Props.highchair()
	chair.position = BUNNY_POSITION
	add_child(chair)
	_build_bunny()

	var tray: Node3D = Props.tray(TRAY_SIZE.x, TRAY_SIZE.y)
	tray.position = TRAY_POSITION
	add_child(tray)
	var rims: Dictionary = {
		Rules.SLOT_LEFT: _Palette.STAR_NEXT,
		Rules.SLOT_CENTRE: _Palette.SOFT_PINK,
		Rules.SLOT_RIGHT: _Palette.DUSTY_BLUE,
	}
	for slot: String in SLOT_X.keys():
		var plate: Node3D = Props.plate(rims[slot], "Plate_" + slot)
		plate.position = TRAY_POSITION + Vector3(float(SLOT_X[slot]), 0.006, SLOT_Z)
		add_child(plate)
		_slots[slot] = plate.position + Vector3(0.0, 0.012, 0.0)

	_camera = Camera3D.new()
	_camera.name = "FeedingCamera"
	_camera.fov = CAMERA_FOV
	add_child(_camera)
	# LOCAL, deliberately: `look_at_from_position()` works in global space and
	# would park the camera in the nursery when this stage sits at the room's
	# `FEEDING_TABLE_OFFSET`.
	_camera.transform = Transform3D(
			Basis.looking_at(CAMERA_TARGET - CAMERA_POSITION, Vector3.UP), CAMERA_POSITION)

	_hud = HudScript.new()
	add_child(_hud)
	_hud.call("build")
	_hud.connect("home_pressed", func() -> void: home_requested.emit())
	_hud.connect("back_pressed", func() -> void: back_requested.emit())


func _build_bunny() -> void:
	if BabyAvatarScript.is_enabled():
		var avatar: Node3D = BabyAvatarScript.new()
		avatar.name = "Bunny"
		add_child(avatar)
		avatar.call("build")
		if bool(avatar.call("is_model_available")):
			avatar.position = BUNNY_POSITION
			# The wrapper faces -Z; the camera sits on +Z. Named in the wrapper.
			_bunny_yaw = deg_to_rad(BabyAvatarScript.CHAPTER_2_YAW_DEG)
			avatar.rotation.y = _bunny_yaw
			_bunny = avatar
			_player = avatar.call("get_animation_player") as AnimationPlayer
			_play_clip("idle")
			_set_face("content")
			return
		avatar.free()
	var view: Node3D = BabyViewScript.new()
	view.name = "Bunny"
	view.position = BUNNY_POSITION
	add_child(view)
	_bunny = view


# ---------------------------------------------------------------------------
# Lifecycle, driven by the room
# ---------------------------------------------------------------------------

## Shows the stage (camera current, input live). The room calls this when a
## feeding task starts and `set_active(false)` when the mission moves on.
func set_active(on: bool) -> void:
	build()
	_active = on
	visible = on
	_hud.visible = on
	set_process(on)
	set_process_unhandled_input(on)
	if _camera != null and is_inside_tree():
		if on:
			_camera.current = true
		elif _camera.current:
			_camera.clear_current(true)


func is_active() -> bool:
	return _active


## Animations become synchronous. For the headless tests and for a "reduce
## motion" setting; nothing about the rules changes.
func set_instant(on: bool) -> void:
	_instant = on


## Serves a new task: the tray is reset, the target marked, the prompt shown.
## `display_name` is the object's word ("apple") for "Try the apple!".
func set_task(task: Dictionary, display_name: String = "", helper: String = "") -> void:
	build()
	_generation += 1
	_task = task.duplicate(true)
	_target_id = String(_task.get("objectId", ""))
	_target_name = display_name if not display_name.is_empty() else _target_id
	_mistakes = 0
	_nudges = 0
	_delivered = false
	_finished = false
	_hold = 0.0
	_holding = false
	_idle = 0.0
	_release_drag(false)
	_kill_turn()
	if _bunny != null:
		_bunny.rotation.y = _bunny_yaw
	_play_clip("idle")
	_set_face("content")
	_lay_table()
	var english: String = String(_task.get("instruction", _task.get("prompt", ""))).strip_edges()
	set_prompt(english, helper)
	# Aliz's learning line for this item, after whatever the mission is saying
	# (never cutting the instruction); Bunny asks for a bottle when it is one.
	_cue(VoiceCues.EVENT_TASK, _target_id, {"queue": true})
	if _target_id == "milk":
		_cue(VoiceCues.EVENT_MILK_PROMPT, "", {"queue": true})
	_hud.call("set_task_credit", Rules.CREDIT_FULL)
	_hud.call("hide_hint")
	_hud.call("set_guide", Vector2.ZERO, Vector2.ZERO, false)
	if Rules.needs_peel(_target_id):
		_show_peel_hint()


func clear_task() -> void:
	_generation += 1
	_task = {}
	_target_id = ""
	_release_drag(false)
	for item: Node3D in _items.values():
		item.visible = false
	_hud.call("hide_hint")
	_hud.call("hide_task_star")
	_hud.call("set_guide", Vector2.ZERO, Vector2.ZERO, false)


## The two prompt lines. The Localization service binds here later.
func set_prompt(english: String, helper: String) -> void:
	build()
	_hud.call("set_prompt", english, helper)


func set_star_count(total: int) -> void:
	build()
	_hud.call("set_star_count", total)


## Something else finished the task (a spoken answer, a skip). Bunny still
## celebrates, so the stage never sits stiff while the room moves on.
func on_task_completed_externally(task_id: String) -> void:
	if String(_task.get("taskId", "")) != task_id or _delivered:
		return
	_delivered = true
	_lock_items()
	_celebrate()


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func get_task_id() -> String:
	return String(_task.get("taskId", ""))


func get_target_id() -> String:
	return _target_id


func get_mistakes() -> int:
	return _mistakes


func get_credit() -> String:
	return Rules.credit_for_mistakes(_mistakes)


func is_guided() -> bool:
	return Rules.is_guided(_mistakes)


func is_delivered() -> bool:
	return _delivered


func is_task_finished() -> bool:
	return _finished


func get_nudges() -> int:
	return _nudges


func is_tap_help_active() -> bool:
	return Rules.tap_helps_after(_nudges)


func is_dragging() -> bool:
	return _drag_item != null


func get_hold_seconds() -> float:
	return _hold


func get_item(item_id: String) -> Node3D:
	return _items.get(item_id, null)


func get_item_ids() -> Array:
	var ids: Array = []
	for item_id: String in _items.keys():
		if (_items[item_id] as Node3D).visible:
			ids.append(item_id)
	return ids


func is_peeled(item_id: String) -> bool:
	var item: Node3D = get_item(item_id)
	return item != null and bool(item.get("peeled"))


func get_hud() -> CanvasLayer:
	build()
	return _hud


func get_camera() -> Camera3D:
	build()
	return _camera


func get_bunny() -> Node3D:
	build()
	return _bunny


func get_bunny_face() -> String:
	if _bunny != null and _bunny.has_method("get_face_mood"):
		return String(_bunny.call("get_face_mood"))
	return ""


func get_bunny_clip() -> String:
	if _player != null:
		return _player.current_animation
	return ""


## The mouth, in world space, read live from the rig's socket.
func get_mouth_world() -> Vector3:
	if not is_inside_tree():
		# No global transforms outside the tree (the headless runner). Local is
		# the honest answer there, and every consumer only compares distances.
		return position + BUNNY_POSITION + FALLBACK_MOUTH_LOCAL
	if _bunny == null:
		return to_global(BUNNY_POSITION + FALLBACK_MOUTH_LOCAL)
	if _bunny.has_method("get_mouth_position"):
		var mouth: Vector3 = _bunny.call("get_mouth_position")
		# A socket that has not been updated yet reads as the character origin.
		if mouth.distance_to(_bunny.global_position) > 0.05:
			return mouth
	return _bunny.to_global(Vector3(0.0, FALLBACK_MOUTH_LOCAL.y, FALLBACK_MOUTH_LOCAL.z))


## The mouth in this node's own space, safe outside the tree.
func _mouth_local() -> Vector3:
	if not is_inside_tree():
		return BUNNY_POSITION + FALLBACK_MOUTH_LOCAL
	return to_local(get_mouth_world())


func get_mouth_screen_position() -> Vector2:
	return _to_canvas(get_mouth_world())


func get_item_screen_position(item_id: String) -> Vector2:
	var item: Node3D = get_item(item_id)
	if item == null or not is_inside_tree():
		return Vector2.ZERO
	return _to_canvas(item.global_position + Vector3(0.0, 0.05, 0.0))


func get_mouth_radius_px() -> float:
	return Rules.mouth_radius_px(_canvas_size().y)


# ---------------------------------------------------------------------------
# Gesture API -- what a finger does, callable without one
# ---------------------------------------------------------------------------

## A tap on an item. Peels a banana, wiggles a wrong item in guided mode, and
## -- once the idle nudges have offered it -- carries the right item to Bunny.
func tap_item(item_id: String) -> bool:
	var item: Node3D = get_item(item_id)
	if item == null or not _can_touch(item):
		return false
	_idle = 0.0
	if bool(item.call("needs_peel")):
		_peel(item)
		return true
	if item_id == _target_id and is_tap_help_active():
		_auto_deliver(item)
		return true
	_hop(item)
	return true


## Picks an item up. False when it cannot be dragged right now (unpeeled banana,
## a wrong item in guided mode, mid-celebration).
func begin_drag(item_id: String) -> bool:
	var item: Node3D = get_item(item_id)
	if item == null or not _can_touch(item) or bool(item.call("needs_peel")):
		return false
	_idle = 0.0
	_release_drag(false)
	_drag_item = item
	_hud.call("hide_hint")
	if is_inside_tree() and _camera != null:
		var forward: Vector3 = -_camera.global_transform.basis.z
		_drag_plane = Plane(forward, item.global_position + (-forward) * DRAG_LIFT)
	_play_sfx(SFX_PICKUP)
	return true


## Moves the dragged item under a canvas-space point.
func drag_to_screen(canvas_pos: Vector2) -> void:
	if _drag_item == null or _camera == null:
		return
	if _holding:
		# The cup is pinned to the lips while the sip is held; the finger only
		# has to stay near the mouth.
		_check_mouth(canvas_pos)
		return
	var window_pos: Vector2 = _to_window(canvas_pos)
	var origin: Vector3 = _camera.project_ray_origin(window_pos)
	var direction: Vector3 = _camera.project_ray_normal(window_pos)
	var hit: Variant = _drag_plane.intersects_ray(origin, direction)
	if hit == null:
		return
	_drag_item.global_position = hit
	_check_mouth(canvas_pos)


## Convenience for tests and the tap-help path: the item goes straight to the
## mouth's screen position.
func drag_to_mouth() -> void:
	if _drag_item == null:
		return
	var target: Vector3 = get_mouth_world() + Vector3(0.0, -0.02, 0.06)
	if is_inside_tree():
		_drag_item.global_position = target
		_check_mouth(get_mouth_screen_position())
	else:
		_drag_item.position = target - position
		_check_mouth()


## Lets go. A drink released before the sip is done glides home, full again.
func end_drag() -> void:
	if _drag_item == null:
		return
	var item: Node3D = _drag_item
	_release_drag(false)
	if _delivered:
		return
	_return_home(item)


## For a held sip: time passes. Real frames do this in `_process`.
func advance_hold(seconds: float) -> void:
	if not _holding or _drag_item == null:
		return
	_hold += seconds
	_apply_hold_visuals()
	if _hold >= Rules.HOLD_SECONDS:
		_arrive(_drag_item)


## An idle nudge: the right item hops, the ask is repeated, and after the second
## one a tap is enough. Real play triggers this from `_process`.
func nudge() -> void:
	if _delivered or _target_id.is_empty():
		return
	_idle = 0.0
	_nudges += 1
	var target: Node3D = get_item(_target_id)
	if target == null:
		return
	if bool(target.call("needs_peel")):
		_show_peel_hint()
	else:
		_hop(target)
	_speak(String(_task.get("instruction", "")))
	if is_tap_help_active():
		_hud.call("show_hint", Rules.TAP_HELP_HINT, get_item_screen_position(_target_id))
		target.call("set_glow", true)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _active or _target_id.is_empty():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if _drag_pointer == -1 and _press_at(touch.position):
				_drag_pointer = touch.index
				get_viewport().set_input_as_handled()
		elif touch.index == _drag_pointer:
			_drag_pointer = -1
			_release_at(touch.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _drag_pointer:
			_move_to(drag.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mouse: InputEventMouseButton = event
		if mouse.pressed:
			if _drag_pointer == -1 and _press_at(mouse.position):
				_drag_pointer = 1000
				get_viewport().set_input_as_handled()
		elif _drag_pointer == 1000:
			_drag_pointer = -1
			_release_at(mouse.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_pointer == 1000:
		_move_to((event as InputEventMouseMotion).position)


func _press_at(canvas_pos: Vector2) -> bool:
	var item: Node3D = _item_at(canvas_pos)
	if item == null:
		return false
	_press_item = item
	_press_screen = canvas_pos
	_press_moved = false
	_idle = 0.0
	# An unpeeled banana and a tap-help target wait for the release; everything
	# else lifts straight away.
	var item_id: String = String(item.get("item_id"))
	if bool(item.call("needs_peel")):
		return true
	if item_id == _target_id and is_tap_help_active():
		return true
	if not begin_drag(item_id):
		_hop(item)
	return true


func _move_to(canvas_pos: Vector2) -> void:
	if not _press_moved and canvas_pos.distance_to(_press_screen) > 18.0:
		_press_moved = true
	# A live drag follows the finger whatever else is remembered about the
	# press (`begin_drag()` clears `_press_item`).
	if _drag_item != null:
		drag_to_screen(canvas_pos)
		return
	if _press_item == null:
		return
	# Drag-down on the banana peels it.
	if bool(_press_item.call("needs_peel")) and canvas_pos.y - _press_screen.y > 28.0:
		_peel(_press_item)
		return
	# A tap-help target that moved is a real drag after all.
	if _press_moved and String(_press_item.get("item_id")) == _target_id and is_tap_help_active():
		if begin_drag(_target_id):
			drag_to_screen(canvas_pos)


func _release_at(_canvas_pos: Vector2) -> void:
	var item: Node3D = _press_item
	_press_item = null
	if _drag_item != null:
		end_drag()
		return
	if item == null or _press_moved:
		return
	tap_item(String(item.get("item_id")))
	_press_moved = false


func _item_at(canvas_pos: Vector2) -> Node3D:
	var radius: float = Rules.touch_radius_px(_canvas_size().y)
	var best: Node3D = null
	var best_distance: float = radius
	for item: Node3D in _items.values():
		if not item.visible:
			continue
		var distance: float = _to_canvas(item.global_position + Vector3(0.0, 0.05, 0.0)).distance_to(canvas_pos)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


func _can_touch(item: Node3D) -> bool:
	if _delivered or _target_id.is_empty() or not item.visible:
		return false
	return bool(item.get("enabled"))


# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _target_id.is_empty() or _delivered:
		return
	if _drag_item != null:
		if _holding:
			advance_hold(delta)
	else:
		_idle += delta
		if _idle >= Rules.NUDGE_IDLE_SECONDS:
			nudge()
	if _hud.call("is_hint_visible"):
		_hud.call("move_hint", get_item_screen_position(_target_id))
	if is_guided():
		var from: Vector2 = get_item_screen_position(_target_id)
		if _drag_item != null and String(_drag_item.get("item_id")) == _target_id:
			from = _to_canvas(_drag_item.global_position)
		_hud.call("set_guide", from, get_mouth_screen_position(), true)


# ---------------------------------------------------------------------------
# Arrival
# ---------------------------------------------------------------------------

## `finger` is the pointer in canvas space when there is one; otherwise the
## item's own projected position stands in for it.
func _check_mouth(finger: Vector2 = Vector2.INF) -> void:
	if _drag_item == null or _delivered:
		return
	var at_mouth: bool = false
	if is_inside_tree():
		var probe: Vector2 = finger if finger != Vector2.INF else _to_canvas(_drag_item.global_position)
		at_mouth = probe.distance_to(get_mouth_screen_position()) <= get_mouth_radius_px()
	else:
		# Metres instead of pixels when nothing can be projected.
		at_mouth = (_drag_item.position + position).distance_to(get_mouth_world()) <= 0.12
	var item_id: String = String(_drag_item.get("item_id"))
	if not at_mouth:
		if _holding:
			_stop_hold()
		return
	if item_id != _target_id:
		_arrive_wrong(_drag_item)
		return
	if Rules.is_drink(item_id):
		if not _holding:
			_start_hold()
		return
	_arrive(_drag_item)


func _start_hold() -> void:
	_holding = true
	_hold = 0.0
	_play_clip("drink")
	_set_face("content")
	if _drag_item != null:
		_animate_to(_drag_item, _mouth_local() + DRINK_POSE_OFFSET, 0.14)
	_apply_hold_visuals()


func _stop_hold() -> void:
	_holding = false
	_hold = 0.0
	if _drag_item != null:
		_drag_item.call("set_tilt", 0.0)
		_drag_item.call("set_liquid_level", 1.0)
		# Back to the finger: the next drag event moves it again.
		if is_inside_tree() and _camera != null:
			var forward: Vector3 = -_camera.global_transform.basis.z
			_drag_plane = Plane(forward, _drag_item.global_position + (-forward) * DRAG_LIFT)
	_play_clip("idle")


func _apply_hold_visuals() -> void:
	if _drag_item == null:
		return
	var t: float = clampf(_hold / Rules.HOLD_SECONDS, 0.0, 1.0)
	_drag_item.call("set_tilt", minf(1.0, t * 1.6))
	_drag_item.call("set_liquid_level", Rules.liquid_level_for_hold(_hold))


## The right item reached the mouth. Latched: once per task, whatever else
## happens afterwards.
func _arrive(item: Node3D) -> void:
	if _delivered:
		return
	_delivered = true
	var was_holding: bool = _holding
	_holding = false
	_release_drag(true)
	_lock_items()
	_hud.call("hide_hint")
	_hud.call("set_guide", Vector2.ZERO, Vector2.ZERO, false)
	item.call("set_glow", false)
	var generation: int = _generation
	if Rules.is_drink(String(item.get("item_id"))):
		_drink_sequence(item, generation, was_holding)
	else:
		_eat_sequence(item, generation)


func _eat_sequence(item: Node3D, generation: int) -> void:
	var mouth: Vector3 = _mouth_local() + EAT_POSE_OFFSET
	_animate_to(item, mouth, SNAP_SECONDS)
	_play_clip("eat")
	_set_face("content")
	for bite: int in range(1, Rules.BITES + 1):
		_after(SNAP_SECONDS + Rules.BITE_GAP_SEC * float(bite), _bite.bind(item, bite, generation))
	_after(SNAP_SECONDS + Rules.BITE_GAP_SEC * float(Rules.BITES) + 0.15, _finish_success.bind(generation))


func _bite(item: Node3D, bite: int, generation: int) -> void:
	if generation != _generation:
		return
	item.call("set_bite_scale", Rules.bite_scale(bite))
	_play_sfx(SFX_POP)
	_hud.call("sparkle_at", get_mouth_screen_position() + Vector2(70.0, -30.0))
	if bite == 1:
		_cue(VoiceCues.EVENT_FOOD_BITE)
	elif bite == HALFWAY_BITE:
		_cue(VoiceCues.EVENT_MEAL_HALFWAY)
	if bite >= Rules.BITES:
		item.visible = false


func _drink_sequence(item: Node3D, generation: int, was_holding: bool) -> void:
	var mouth: Vector3 = _mouth_local() + DRINK_POSE_OFFSET
	_animate_to(item, mouth, SNAP_SECONDS)
	item.call("set_tilt", 1.0)
	if not was_holding:
		_play_clip("drink")
	item.call("set_liquid_level", 0.35)
	_play_sfx(SFX_POP)
	_hud.call("sparkle_at", get_mouth_screen_position() + Vector2(70.0, -30.0))
	_cue(VoiceCues.EVENT_FOOD_BITE)
	_after(0.45, _gulp.bind(item, generation))
	_after(0.9, _finish_success.bind(generation))


func _gulp(item: Node3D, generation: int) -> void:
	if generation != _generation:
		return
	item.call("set_liquid_level", 0.12)
	_play_sfx(SFX_POP)
	_hud.call("sparkle_at", get_mouth_screen_position() + Vector2(-70.0, -30.0))
	_cue(VoiceCues.EVENT_MEAL_HALFWAY)


func _finish_success(generation: int) -> void:
	if generation != _generation or _finished:
		return
	_finished = true
	for item: Node3D in _items.values():
		if Rules.is_drink(String(item.get("item_id"))) and String(item.get("item_id")) == _target_id:
			_animate_to(item, item.get("home_position"), RETURN_SECONDS)
			item.call("set_tilt", 0.0)
	_celebrate()
	_hud.call("pop_task_star")
	_hud.call("show_encouragement", Rules.SUCCESS_PHRASE)
	# With the voice pack: Bunny's "Thank you, Aliz!" then Aliz's "All done!".
	# Without it: the success phrase through the device voice, as before.
	if _cue(VoiceCues.EVENT_CARE_COMPLETED):
		_cue(VoiceCues.EVENT_TASK_DONE, "", {"queue": true})
	else:
		_speak(Rules.SUCCESS_PHRASE)
	encouragement.emit(Rules.SUCCESS_PHRASE)
	# THE hand-off. The room forwards this to `MissionRunner.on_object_chosen()`.
	item_delivered.emit(_target_id)
	task_finished.emit(get_task_id())


func _celebrate() -> void:
	_play_clip("celebrate")
	_set_face("delighted")
	_after(CELEBRATE_SECONDS, _rest_after_celebrate.bind(_generation))


func _rest_after_celebrate(generation: int) -> void:
	if generation == _generation:
		_play_clip("idle")


## A wrong item reached the mouth. Kind, brief, and it costs the star the rules
## say it costs -- never a sound, a shake or a colour that means "no".
func _arrive_wrong(item: Node3D) -> void:
	if _delivered:
		return
	var item_id: String = String(item.get("item_id"))
	_release_drag(false)
	_mistakes += 1
	_return_home(item)
	_turn_away()
	var phrase: String = Rules.try_phrase(_target_name)
	_hud.call("set_task_credit", get_credit())
	_hud.call("show_encouragement", phrase)
	encouragement.emit(phrase)
	# The room forwards this to the runner too, so the mode handler counts the
	# gentle attempt and repeats the ask exactly as it does for a drop zone.
	wrong_item.emit(item_id)
	# THEN the voice: Bunny's "Hmph!" now (it cuts the repeated ask, which the
	# prompt speaker re-queues behind him), and Aliz's "Let's try again!" --
	# with "It's okay. We can do it!" on the second miss -- right after.
	if _cue(VoiceCues.EVENT_WRONG_ITEM, "", {"interrupt": true}):
		VoiceBridge.say_lines(self, VoiceCues.for_encouragement(phrase, _mistakes), {"queue": true})
	if _mistakes == 1:
		half_star.emit(get_task_id())
	if is_guided() and _mistakes == 2:
		_enter_guided()


func _enter_guided() -> void:
	for item: Node3D in _items.values():
		var is_target: bool = String(item.get("item_id")) == _target_id
		item.set("enabled", is_target)
		item.call("set_glow", is_target)
	_hud.call("set_guide", get_item_screen_position(_target_id), get_mouth_screen_position(), true)
	guided_started.emit(get_task_id())


func _turn_away() -> void:
	_kill_turn()
	_play_clip("fuss")
	# The owner's cute-angry `hmph` (brows down, puffed cheeks), not the sad face.
	_set_face(VoiceCues.face_for(VoiceCues.EVENT_WRONG_ITEM))
	if _bunny == null:
		return
	if _instant or not is_inside_tree():
		return
	var away: float = _bunny_yaw + deg_to_rad(TURN_AWAY_DEG)
	_turn_tween = create_tween()
	_turn_tween.tween_property(_bunny, "rotation:y", away, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_turn_tween.tween_interval(TURN_AWAY_SECONDS - 0.6)
	_turn_tween.tween_property(_bunny, "rotation:y", _bunny_yaw, 0.3).set_trans(Tween.TRANS_SINE)
	_turn_tween.tween_callback(_settle_after_turn.bind(_generation))


func _settle_after_turn(generation: int) -> void:
	if generation == _generation and not _delivered:
		_play_clip("idle")
		_set_face("content")


func _kill_turn() -> void:
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_turn_tween = null


# ---------------------------------------------------------------------------
# Peel, hop, glide
# ---------------------------------------------------------------------------

func _peel(item: Node3D) -> void:
	if not bool(item.call("needs_peel")):
		return
	_hud.call("hide_hint")
	_play_sfx(SFX_PLACE)
	# Peeled NOW, as a fact; the strips fold over the next 0.4 s as a picture.
	# A child who grabs the banana while it is still folding may.
	item.set("peeled", true)
	if _instant or not is_inside_tree():
		item.call("set_peel_progress", 1.0)
		return
	var tween: Tween = create_tween()
	tween.tween_method(_set_peel.bind(item), 0.0, 1.0, Rules.PEEL_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_peel(t: float, item: Node3D) -> void:
	if is_instance_valid(item):
		item.call("set_peel_progress", t)


func _show_peel_hint() -> void:
	if _target_id.is_empty():
		return
	_hud.call("show_hint", Rules.PEEL_HINT, get_item_screen_position(_target_id))


func _auto_deliver(item: Node3D) -> void:
	_hud.call("hide_hint")
	if _instant or not is_inside_tree():
		_arrive(item)
		return
	_lock_items()
	var tween: Tween = create_tween()
	tween.tween_property(item, "position", _mouth_local() + Vector3(0.0, -0.02, 0.06), AUTO_GLIDE_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_finish_auto_deliver.bind(item, _generation))


func _finish_auto_deliver(item: Node3D, generation: int) -> void:
	if generation != _generation:
		return
	for other: Node3D in _items.values():
		other.set("enabled", true)
	_arrive(item)


func _hop(item: Node3D) -> void:
	if _instant or not is_inside_tree():
		return
	var home: Vector3 = item.get("home_position")
	var tween: Tween = create_tween()
	tween.tween_property(item, "position", home + Vector3(0.0, HOP_HEIGHT, 0.0), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "position", home, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _return_home(item: Node3D) -> void:
	item.call("set_tilt", 0.0)
	item.call("set_liquid_level", 1.0)
	_play_sfx(SFX_RETURN)
	_animate_to(item, item.get("home_position"), RETURN_SECONDS)


func _animate_to(item: Node3D, local_target: Vector3, seconds: float) -> void:
	if _instant or not is_inside_tree():
		item.position = local_target
		return
	var tween: Tween = create_tween()
	tween.tween_property(item, "position", local_target, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _release_drag(_keep_position: bool) -> void:
	_drag_item = null
	_press_item = null
	_holding = false
	_hold = 0.0


func _lock_items() -> void:
	for item: Node3D in _items.values():
		item.set("enabled", false)


func _lay_table() -> void:
	var wanted: Dictionary = Rules.tray_items_for(_target_id)
	for item: Node3D in _items.values():
		item.visible = false
	# `_slots` are table-local; items are direct children, so `position` is too.
	for slot: String in wanted.keys():
		var item_id: String = String(wanted[slot])
		var item: Node3D = _ensure_item(item_id)
		if item == null:
			continue
		item.position = _slots[slot]
		item.rotation = Vector3.ZERO
		item.call("remember_home")
		item.call("reset_state")
		item.visible = true


func _ensure_item(item_id: String) -> Node3D:
	if _items.has(item_id):
		return _items[item_id]
	var color: Color = _colors.get(item_id, _default_color(item_id))
	var item: Node3D = Props.build_item(item_id, color)
	if item == null:
		return null
	add_child(item)
	_items[item_id] = item
	return item


## Food colours from the content library, so the apple on the tray is the
## apple on the sticker. Optional; the defaults below are the same values.
func set_item_colors(colors: Dictionary) -> void:
	for key: Variant in colors.keys():
		_colors[String(key)] = colors[key]


static func _default_color(item_id: String) -> Color:
	match item_id:
		"apple":
			return Props.color_from_hex("#E8453C", _Palette.SOFT_PINK)
		"banana":
			return Props.color_from_hex("#F6D743", _Palette.STAR_NEXT)
		"water":
			return Props.color_from_hex("#7FD4F5", _Palette.DUSTY_BLUE)
		_:
			return Color(1.0, 1.0, 1.0)


# ---------------------------------------------------------------------------
# Bunny
# ---------------------------------------------------------------------------

func _play_clip(clip: String) -> void:
	if _player != null:
		if _player.has_animation(clip) and _player.current_animation != clip:
			_player.play(clip, 0.22)
		return
	if _bunny != null and _bunny.has_method("set_view_state"):
		match clip:
			"eat", "drink":
				_bunny.call("set_view_state", "drinking")
			"celebrate":
				_bunny.call("set_view_state", "happy")
			"fuss":
				_bunny.call("set_view_state", "hungry")
			_:
				_bunny.call("set_view_state", "idle")


func _set_face(mood: String) -> void:
	if _bunny != null and _bunny.has_method("set_face_mood"):
		_bunny.call("set_face_mood", mood)


# ---------------------------------------------------------------------------
# Screen space, services
# ---------------------------------------------------------------------------

## Camera3D projects in the viewport's VISIBLE RECT, which under the project's
## `canvas_items` stretch is the 2D canvas (1821x1024 on a 1334x750 window) --
## the same space input events and Controls use. Measured, not assumed: an
## InputEventMouseButton at window (100, 100) arrives here as (136.5, 136.5),
## and `get_visible_rect()` reports the canvas. So there is nothing to convert.
func _to_canvas(world: Vector3) -> Vector2:
	if _camera == null or not _camera.is_inside_tree():
		return Vector2.ZERO
	return _camera.unproject_position(world)


func _to_window(canvas_pos: Vector2) -> Vector2:
	return canvas_pos


func _canvas_size() -> Vector2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2(1366.0, 1024.0)
	return viewport.get_visible_rect().size


func _after(seconds: float, callable: Callable) -> void:
	if _instant or not is_inside_tree():
		callable.call()
		return
	var timer: SceneTreeTimer = get_tree().create_timer(seconds)
	timer.timeout.connect(callable, CONNECT_ONE_SHOT)


func _autoload(autoload_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null(NodePath("/root/%s" % autoload_name))


func _play_sfx(sfx_name: String) -> void:
	var sfx: Node = _autoload("Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", sfx_name)


func _speak(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	# Through the voice pack when it exists (a recorded line for "Great!" and
	# the like, the device voice under its queue otherwise), else TtsService.
	if VoiceBridge.say_text(self, text, {"queue": true}):
		return
	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("speak"):
		tts.call("speak", text)


## A voice-pack cue. False when there is no `Voice` autoload or no line for
## the moment, so a caller can keep its old line.
func _cue(event: String, detail: String = "", opts: Dictionary = {}) -> bool:
	return VoiceBridge.cue(self, event, detail, opts)
