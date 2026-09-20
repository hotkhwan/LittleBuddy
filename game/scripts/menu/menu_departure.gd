extends Node

## THE WALK HOME -- what happens between pressing Start and being in the game.
##
## The buttons used to cut straight to the next scene. Now, on Start or Free
## Play, the buttons fade, Aliz turns and steps over to Bunny, lifts him into
## the real carry (her `carryFront` socket and the carry arm pose, exactly as
## `carry_controller.gd` does it in the house; Bunny plays his own `carried`
## clip), and the two of them head up the path to the cottage while the camera
## eases after them. The front door swings open, a soft cream cover comes up,
## and `main.gd` runs the hand-off it always ran -- the routing is untouched,
## it just happens two and a half seconds later, behind the door.
##
## ## Timeline (seconds from `begin()`)
##
##     0.00  turn      Aliz faces Bunny and steps toward him
##     0.35  pickUp    Bunny arcs up to the socket; her arms wrap
##     0.80  walkHome  both head for the door; camera follows; door opens 1.6-2.1
##     2.10  cover     cream cover fades in over the picture
##     2.50  done      `finished` -- main.gd routes; the cover reveals the new scene
##
## ## Hand-integrated, not tweened
##
## `advance(delta)` moves the whole thing by hand from `_process()`, in the
## same style as `carry_controller.gd`: the headless runner has no frames, and
## a transition a test cannot drive to completion is a transition a test cannot
## prove finishes. `skip()` jumps straight to `done`, which is what a tap does.
##
## ## Nothing here changes a character
##
## Both are driven only through their wrappers' public API -- `set_locomotion`,
## `set_carry_pose`, `get_socket`, `get_animation_player`, `play_action` -- all
## behind `has_method()` guards, so a build with fewer clips (or none) still
## completes the walk, just with less to look at.
##
## ## The cover survives the scene swap
##
## The cream cover is a `CanvasLayer` under the tree ROOT, not under the menu,
## because the menu is freed by the hand-off while the cover is still needed.
## It reveals the new scene with its own tween and frees itself. Agent A's
## `scripts/branding/scene_transition.gd` is preferred when it exists and
## answers `cover()`; this file's own cover is the fallback.

signal phase_changed(phase: String)
signal finished()

const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const Garden := preload("res://scripts/menu/menu_garden.gd")

const PHASE_IDLE: String = "idle"
const PHASE_TURN: String = "turn"
const PHASE_PICK_UP: String = "pickUp"
const PHASE_WALK_HOME: String = "walkHome"
const PHASE_COVER: String = "cover"
const PHASE_DONE: String = "done"

const TURN_SEC: float = 0.35
const PICK_UP_SEC: float = 0.45
const WALK_SEC: float = 1.7
const COVER_START_SEC: float = 2.1
const TOTAL_SEC: float = 2.5
## The door starts opening this far into the walk and is open this much later.
const DOOR_OPEN_AT: float = 1.6
const DOOR_OPEN_SEC: float = 0.5
const DOOR_OPEN_DEG: float = -95.0
## How long the cover takes to lift off the NEW scene.
const REVEAL_SEC: float = 0.55
## The lift arcs upward a little on its way rather than sliding straight, so it
## reads as picked UP -- `carry_controller.gd`'s number.
const LIFT_ARC: float = 0.12

## Where she stops beside him before lifting: a shoulder's width away.
const PICK_UP_REACH: float = 0.42
## Where the walk ends: a stride short of the doorstep, so the door is open
## and filling the frame as the cover comes up.
const ARRIVE_SHORT_OF_DOOR: float = 1.1
## The bend the pair walks through on the way to the door.
const WALK_BEND := Vector3(1.5, 0.0, -1.9)

## The camera at the end of the walk: over her shoulder, the open door ahead.
const CAMERA_END_POSITION := Vector3(1.05, 1.5, 0.75)
const CAMERA_END_TARGET := Vector3(2.35, 0.95, -4.2)

const COVER_LAYER: int = 128
const COVER_NAME: String = "SceneCover"
const SCENE_TRANSITION_SCRIPT_PATH: String = "res://scripts/branding/scene_transition.gd"

var _aliz: Node3D = null
var _bunny: Node3D = null
var _garden: Node = null
var _camera: Camera3D = null

var _phase: String = PHASE_IDLE
var _elapsed: float = 0.0
var _finished_emitted: bool = false

var _aliz_start: Transform3D = Transform3D.IDENTITY
var _aliz_beside: Vector3 = Vector3.ZERO
var _aliz_yaw_start: float = 0.0
var _aliz_yaw_to_bunny: float = 0.0
var _aliz_yaw_to_door: float = 0.0
var _walk_from: Vector3 = Vector3.ZERO
var _walk_to: Vector3 = Vector3.ZERO
var _bunny_floor: Transform3D = Transform3D.IDENTITY
var _bunny_lifted: bool = false
var _turn_landed: bool = false
var _camera_start: Transform3D = Transform3D.IDENTITY
var _camera_end: Transform3D = Transform3D.IDENTITY
var _cover: CanvasLayer = null
var _cover_rect: ColorRect = null
var _branding: Node = null


# ---------------------------------------------------------------------------
# Requests
# ---------------------------------------------------------------------------

## Starts the walk. `aliz` and `bunny` are the two wrapper nodes on the title
## screen (either may be null: the walk degrades to whatever is there), `garden`
## the `menu_garden.gd` node (for the door hinge), `camera` the menu camera.
## False, and nothing happens, when already running or finished.
func begin(aliz: Node3D, bunny: Node3D, garden: Node, camera: Camera3D) -> bool:
	if _phase != PHASE_IDLE:
		return false
	_aliz = aliz
	_bunny = bunny
	_garden = garden
	_camera = camera
	_elapsed = 0.0
	_finished_emitted = false
	_turn_landed = false
	_bunny_lifted = false

	if _aliz != null:
		_aliz_start = _aliz.transform
		_aliz_yaw_start = _aliz.rotation.y
		var beside_target: Vector3 = _aliz_start.origin
		if _bunny != null:
			var to_bunny: Vector3 = _bunny.position - _aliz_start.origin
			to_bunny.y = 0.0
			if to_bunny.length() > PICK_UP_REACH:
				beside_target = _bunny.position - to_bunny.normalized() * PICK_UP_REACH
			beside_target.y = _aliz_start.origin.y
			_aliz_yaw_to_bunny = _yaw_toward(_aliz_start.origin, _bunny.position)
		else:
			_aliz_yaw_to_bunny = _aliz_yaw_start
		_aliz_beside = beside_target
		var door: Vector3 = Garden.doorstep_position()
		_walk_from = _aliz_beside
		_walk_to = door + Vector3(0.0, 0.0, ARRIVE_SHORT_OF_DOOR)
		_aliz_yaw_to_door = _yaw_toward(_walk_from, _walk_to)
	if _bunny != null:
		_bunny_floor = _bunny.transform
	if _camera != null:
		_camera_start = _camera.transform
		_camera_end = Transform3D.IDENTITY.looking_at(
				CAMERA_END_TARGET - CAMERA_END_POSITION, Vector3.UP)
		_camera_end.origin = CAMERA_END_POSITION

	_make_cover()
	_set_phase(PHASE_TURN)
	_apply(0.0)
	return true


## Jumps to the end: cover fully up, `finished` emitted now. What a tap does.
func skip() -> void:
	if _phase == PHASE_IDLE or _phase == PHASE_DONE:
		return
	_elapsed = TOTAL_SEC
	_apply(_elapsed)
	_finish()


## Advances the walk by `delta` seconds. Called from the menu's `_process()`,
## and by tests.
func advance(delta: float) -> void:
	if _phase == PHASE_IDLE or _phase == PHASE_DONE:
		return
	_elapsed += maxf(delta, 0.0)
	_apply(_elapsed)
	if _elapsed >= TOTAL_SEC:
		_finish()


## Fades the cover off whatever is on screen now, then frees it. `main.gd`
## calls this right after the hand-off. Safe to call with no cover.
func reveal() -> void:
	if _branding != null and is_instance_valid(_branding) and _branding.has_method("reveal"):
		_call_timed(_branding, "reveal", REVEAL_SEC)
		_branding = null
		return
	if _cover == null or not is_instance_valid(_cover):
		return
	var cover: CanvasLayer = _cover
	var rect: ColorRect = _cover_rect
	_cover = null
	_cover_rect = null
	if not cover.is_inside_tree() or rect == null:
		cover.queue_free()
		return
	var tween: Tween = cover.create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, REVEAL_SEC).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(cover.queue_free)


## Takes the cover down at once, without a fade. For a hand-off that did not
## happen (nothing to open), and for tests.
func discard_cover() -> void:
	if _branding != null and is_instance_valid(_branding):
		if _branding.has_method("reveal"):
			_call_timed(_branding, "reveal", 0.0)
		_branding = null
	if _cover != null and is_instance_valid(_cover):
		var parent: Node = _cover.get_parent()
		if parent != null:
			parent.remove_child(_cover)
		_cover.free()
	_cover = null
	_cover_rect = null


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func get_phase() -> String:
	return _phase


func is_running() -> bool:
	return _phase != PHASE_IDLE and _phase != PHASE_DONE


func is_done() -> bool:
	return _phase == PHASE_DONE


func get_elapsed() -> float:
	return _elapsed


## How far the cover is up, 0..1.
func get_cover_alpha() -> float:
	if _cover_rect != null and is_instance_valid(_cover_rect):
		return _cover_rect.modulate.a
	return 0.0


## The cover node under the tree root, or null.
func get_cover() -> CanvasLayer:
	return _cover if _cover != null and is_instance_valid(_cover) else null


## True once Bunny has been lifted into the socket.
func is_bunny_carried() -> bool:
	return _bunny_lifted


# ---------------------------------------------------------------------------
# The choreography, as a function of time
# ---------------------------------------------------------------------------

func _apply(t: float) -> void:
	# Phases by time, so a large delta (or a skip) lands every step in order.
	# Each earlier step is landed ONCE when it is passed, never re-applied: a
	# re-applied turn would call `set_locomotion(0)` and restart the walk clip
	# from its first frame every frame.
	if t < TURN_SEC:
		_set_phase(PHASE_TURN)
		_apply_turn(_ease(t / TURN_SEC))
		return
	if not _turn_landed:
		_apply_turn(1.0)
	if t < TURN_SEC + PICK_UP_SEC:
		_set_phase(PHASE_PICK_UP)
		_apply_pick_up(_ease((t - TURN_SEC) / PICK_UP_SEC))
		return
	if not _bunny_lifted:
		_apply_pick_up(1.0)
	var walk_t: float = clampf((t - TURN_SEC - PICK_UP_SEC) / WALK_SEC, 0.0, 1.0)
	if t < COVER_START_SEC:
		_set_phase(PHASE_WALK_HOME)
	else:
		_set_phase(PHASE_COVER)
	_apply_walk(walk_t, t)
	_apply_door(t)
	_apply_cover(t)


func _apply_turn(k: float) -> void:
	if _aliz == null:
		return
	var yaw: float = lerp_angle(_aliz_yaw_start, _aliz_yaw_to_bunny, k)
	var origin: Vector3 = _aliz_start.origin.lerp(_aliz_beside, k)
	_aliz.transform = Transform3D(Basis(Vector3.UP, yaw), origin)
	var distance: float = _aliz_start.origin.distance_to(_aliz_beside)
	if k < 1.0:
		_locomote(_aliz, distance / TURN_SEC)
	else:
		_turn_landed = true
		_locomote(_aliz, 0.0)


func _apply_pick_up(k: float) -> void:
	if _bunny == null:
		return
	if not _bunny_lifted:
		_bunny_lifted = true
		if _aliz != null and _aliz.has_method("set_carry_pose"):
			_aliz.call("set_carry_pose", true)
		_play_clip(_bunny, "carried")
	var held: Transform3D = _held_transform()
	if k >= 1.0:
		_set_world(_bunny, held)
		return
	var origin: Vector3 = _bunny_floor.origin.lerp(held.origin, k) + Vector3.UP * (LIFT_ARC * sin(k * PI))
	var rotation: Quaternion = _bunny_floor.basis.get_rotation_quaternion().slerp(
			held.basis.get_rotation_quaternion(), k)
	_set_world(_bunny, Transform3D(Basis(rotation).scaled(_bunny_floor.basis.get_scale()), origin))


func _apply_walk(k: float, t: float) -> void:
	if _aliz != null:
		var pos: Vector3 = _walk_from.bezier_interpolate(WALK_BEND, WALK_BEND, _walk_to, _ease_in_out_soft(k))
		# The heading follows the curve, so she turns as the path bends.
		var ahead: Vector3 = _walk_from.bezier_interpolate(WALK_BEND, WALK_BEND, _walk_to, minf(_ease_in_out_soft(k) + 0.03, 1.0))
		var yaw: float = _aliz_yaw_to_door
		if ahead.distance_squared_to(pos) > 0.000001:
			yaw = _yaw_toward(pos, ahead)
		# Ease her round from facing Bunny in the first fifth of the walk.
		var turn_k: float = clampf(k / 0.2, 0.0, 1.0)
		yaw = lerp_angle(_aliz_yaw_to_bunny, yaw, _ease(turn_k))
		_aliz.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		var total: float = _walk_from.distance_to(WALK_BEND) + WALK_BEND.distance_to(_walk_to)
		_locomote(_aliz, 0.0 if k >= 1.0 else (total / WALK_SEC) * _pace(k))
	if _bunny != null and _bunny_lifted:
		_set_world(_bunny, _held_transform())
	if _camera != null:
		var ck: float = _ease(k)
		var origin: Vector3 = _camera_start.origin.lerp(_camera_end.origin, ck)
		var rotation: Quaternion = _camera_start.basis.get_rotation_quaternion().slerp(
				_camera_end.basis.get_rotation_quaternion(), ck)
		_camera.transform = Transform3D(Basis(rotation), origin)
	if t >= TOTAL_SEC and _aliz != null:
		_locomote(_aliz, 0.0)


func _apply_door(t: float) -> void:
	if _garden == null or not _garden.has_method("get_door_hinge"):
		return
	var hinge: Node3D = _garden.call("get_door_hinge") as Node3D
	if hinge == null:
		return
	var k: float = clampf((t - DOOR_OPEN_AT) / DOOR_OPEN_SEC, 0.0, 1.0)
	hinge.rotation_degrees = Vector3(0.0, DOOR_OPEN_DEG * _ease(k), 0.0)


func _apply_cover(t: float) -> void:
	var k: float = clampf((t - COVER_START_SEC) / (TOTAL_SEC - COVER_START_SEC), 0.0, 1.0)
	if _branding != null and is_instance_valid(_branding):
		return
	if _cover_rect != null and is_instance_valid(_cover_rect):
		_cover_rect.modulate.a = _ease(k)


func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	if _cover_rect != null and is_instance_valid(_cover_rect):
		_cover_rect.modulate.a = 1.0
	if _aliz != null:
		_locomote(_aliz, 0.0)
	_set_phase(PHASE_DONE)
	finished.emit()


# ---------------------------------------------------------------------------
# Characters, through their wrappers only
# ---------------------------------------------------------------------------

## Where Bunny rides: the `carryFront` socket's world position under Aliz's
## yaw -- `carry_controller.gd::held_transform()`, with its no-rig fallback.
func _held_transform() -> Transform3D:
	if _aliz == null:
		return _bunny_floor
	var yaw_basis := Basis(Vector3.UP, _aliz.rotation.y)
	var origin: Vector3 = Vector3.ZERO
	var socket: Node3D = null
	if _aliz.has_method("has_socket") and bool(_aliz.call("has_socket", "carryFront")) \
			and _aliz.has_method("get_socket"):
		if _aliz.has_method("refresh_sockets"):
			_aliz.call("refresh_sockets")
		socket = _aliz.call("get_socket", "carryFront") as Node3D
		if socket == _aliz:
			socket = null
	if socket != null:
		origin = SpatialUtil.world_position(socket)
	else:
		origin = SpatialUtil.world_transform(_aliz) * Vector3(0.0, 0.34, -0.26)
	return Transform3D(yaw_basis.scaled(_bunny_floor.basis.get_scale()), origin)


func _locomote(who: Node3D, speed: float) -> void:
	if who != null and who.has_method("set_locomotion"):
		who.call("set_locomotion", speed)


func _play_clip(who: Node3D, clip: String) -> void:
	if who == null or not who.has_method("get_animation_player"):
		return
	var player: AnimationPlayer = who.call("get_animation_player") as AnimationPlayer
	if player == null or not player.has_animation(clip):
		return
	if player.current_animation != clip or not player.is_playing():
		player.play(clip, 0.22)


## World transform in or out of the tree, like `carry_controller.gd`.
func _set_world(node: Node3D, world: Transform3D) -> void:
	var parent: Node = node.get_parent()
	if parent is Node3D:
		node.transform = SpatialUtil.world_transform(parent as Node3D).affine_inverse() * world
	else:
		node.transform = world


# ---------------------------------------------------------------------------
# The cover
# ---------------------------------------------------------------------------

func _make_cover() -> void:
	var tree: SceneTree = _scene_tree()
	if tree == null or tree.root == null:
		return
	# Agent A's transition, when it is in the build and speaks `cover()`.
	# Expected shape: a Node-derived script with `cover(seconds)` and
	# `reveal(seconds)` (either arity 0 or 1). Anything else falls through to
	# the plain cream cover below.
	if ResourceLoader.exists(SCENE_TRANSITION_SCRIPT_PATH):
		var script: Resource = load(SCENE_TRANSITION_SCRIPT_PATH)
		if script is GDScript and ClassDB.is_parent_class((script as GDScript).get_instance_base_type(), "Node"):
			var candidate: Object = (script as GDScript).new()
			if candidate is Node and candidate.has_method("cover") and candidate.has_method("reveal"):
				_branding = candidate as Node
				_branding.name = "SceneTransition"
				tree.root.add_child(_branding)
				_call_timed(_branding, "cover", TOTAL_SEC - COVER_START_SEC)
				return
			elif candidate != null:
				candidate.free()

	var layer := CanvasLayer.new()
	layer.name = COVER_NAME
	layer.layer = COVER_LAYER
	var rect := ColorRect.new()
	rect.name = "Cover"
	rect.color = Palette.CREAM
	rect.modulate.a = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	tree.root.add_child(layer)
	_cover = layer
	_cover_rect = rect


## Calls `method` with `seconds` if it takes an argument, bare otherwise.
static func _call_timed(target: Object, method: String, seconds: float) -> void:
	if target.get_method_argument_count(method) >= 1:
		target.call(method, seconds)
	else:
		target.call(method)


func _scene_tree() -> SceneTree:
	if is_inside_tree():
		return get_tree()
	return Engine.get_main_loop() as SceneTree


# ---------------------------------------------------------------------------
# Small maths
# ---------------------------------------------------------------------------

static func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var d: Vector3 = to - from
	d.y = 0.0
	if d.length_squared() < 0.000001:
		return 0.0
	# Yaw 0 faces -Z for every character in this project.
	return atan2(-d.x, -d.z)


static func _ease(t: float) -> float:
	var k: float = clampf(t, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## A gentler start than a smoothstep, so she leaves at a walk and is only
## hurrying by the middle.
static func _ease_in_out_soft(t: float) -> float:
	var k: float = clampf(t, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k) * 0.7 + k * 0.3


## The pace multiplier at `k` (derivative of the easing, roughly), so the legs
## match the ground speed at each moment rather than the average.
static func _pace(t: float) -> float:
	var k: float = clampf(t, 0.0, 1.0)
	return 0.3 + 0.7 * 6.0 * k * (1.0 - k)


func _set_phase(phase: String) -> void:
	if phase == _phase:
		return
	_phase = phase
	phase_changed.emit(phase)
