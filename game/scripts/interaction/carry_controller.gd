extends Node3D

## CARRYING -- pick up, hold, put down. One per carrier.
##
## The signature interaction of the house is Aliz carrying Bunny, and the same
## mechanism carries a bottle, a bowl or a toy. Five states, in order:
##
##     in the world -> PICKING_UP -> HELD -> PLACING -> back in the world
##
## `carry()` starts the first arrow, `put_down()` the third, and `sync(delta)`
## -- called by the carrier once per physics step, AFTER it has moved -- runs
## the two animated arrows by hand and pins the held thing to its socket in
## between. Integrating by hand rather than with a `Tween` is deliberate: the
## headless runner has no frames, and a carry whose pick-up and put-down only
## happen inside a `Tween` is a carry no test can observe.
##
## ## Two kinds of thing, one controller
##
##   * **A child** (`set_carried_by()` / `release_carried()`): stays exactly where
##     it is in the scene tree -- the room, its stats, its `ActivityTarget`, its
##     bubble, everything the director looks for -- and only its TRANSFORM is
##     driven from here. Nothing is duplicated and nothing is re-parented, so
##     there is never a second Bunny and his hunger is the same number it was.
##     If the carrier changes room, the child is handed to the new room through
##     its own `room_changed()` so it cannot be hidden with the room it left.
##   * **An item** (anything else): re-parented under this node for the duration,
##     so it goes where she goes between frames too, with its input switched off,
##     and handed back to where it came from when it lands. A `SpawnedObject`
##     learns its new home so a later `reset_position()` does not fling it back.
##
## ## Where it is held
##
## By SOCKET NAME, never by bone (`LB_Rig_v1`): `carryFront` for a child,
## `itemHoldRight` for an item, asked of whichever node under the carrier answers
## `get_socket()`. Only the socket's POSITION is taken. The held thing's yaw is
## the carrier's -- a child faces out, an item stays upright -- because a bone's
## roll through a walk cycle reads as dropped, exactly as `kitchen_view.gd`
## found for the hand. Without a rig the fallback is a fixed offset in the
## carrier's own frame: on-screen and stable rather than at the origin.
##
## ## Where it is put down
##
## Only somewhere standable. `find_put_down_spot()` asks the carrier's own
## navigation provider to snap a point an arm's length ahead onto the walkable
## mesh -- which is inset by the agent radius and cut round the furniture, so a
## point that survives the snap is clear of walls and furniture -- and refuses a
## point the mesh had to move more than `PUT_DOWN_SNAP_TOLERANCE` to accept.
## Eight directions are tried, front first, so a caregiver facing a wall still
## puts the child down beside her rather than through it; and every candidate
## must clear her own body by `PUT_DOWN_MIN_CLEARANCE`.

const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")

signal carry_started(node: Node3D)
## The thing has arrived at the socket and is now simply held.
signal carry_settled(node: Node3D)
## The thing has landed and is back in the world.
signal carry_ended(node: Node3D)
signal state_changed(state: String)

const STATE_IDLE: String = "idle"
const STATE_PICKING_UP: String = "pickingUp"
const STATE_HELD: String = "held"
const STATE_PLACING: String = "placing"

const KIND_CHILD: String = "child"
const KIND_ITEM: String = "item"

const SOCKET_CHILD: String = "carryFront"
const SOCKET_ITEM: String = "itemHoldRight"

## How long lifting and setting down take. Short enough to answer a tap, long
## enough to be a movement rather than a cut.
const PICK_UP_SEC: float = 0.45
const PLACE_SEC: float = 0.40
## The lift arcs upward a little on its way rather than sliding straight, so it
## reads as picked UP.
const LIFT_ARC: float = 0.10

## Carrier-local hold points for a carrier with no sockets (the procedural
## toddler). -Z is the way the carrier faces.
const FALLBACK_OFFSETS: Dictionary = {
	KIND_CHILD: Vector3(0.0, 0.34, -0.26),
	KIND_ITEM: Vector3(-0.2, 0.6, -0.14),
}

## An arm's length ahead -- far enough that a 0.78 m child's raised knees clear
## her, close enough that she visibly set him down rather than tossed him.
const PUT_DOWN_DISTANCE: float = 0.62
## How far the navigation mesh may move a candidate before it stops being the
## spot she meant and starts being "somewhere else".
const PUT_DOWN_SNAP_TOLERANCE: float = 0.12
## No closer to her own axis than this: her capsule is 0.2 m, his is about the
## same, and the two must not share a footprint.
const PUT_DOWN_MIN_CLEARANCE: float = 0.45
## Front first, then fanning out; behind her last.
const PUT_DOWN_ANGLES_DEG: Array[float] = [0.0, -35.0, 35.0, -70.0, 70.0, -110.0, 110.0, 180.0]

var _carrier: Node3D = null
var _socket_source: Node = null
var _provider: RefCounted = null

var _node: Node3D = null
var _kind: String = ""
var _socket_name: String = ""
var _state: String = STATE_IDLE
var _elapsed: float = 0.0
var _from: Transform3D = Transform3D.IDENTITY
var _to: Transform3D = Transform3D.IDENTITY
var _original_parent: Node = null
## World-up lift that puts an item's centre, rather than its base, at the socket.
var _item_lift: float = 0.0
var _was_pickable: bool = false
var _was_drag_enabled: bool = true


## `carrier` is the body this rides on; `socket_source` anything under it that
## answers `get_socket()` (null for a carrier with no rig); `provider` the
## navigation provider used to test put-down spots (re-asked of the carrier at
## put-down time when it can be, so a provider bound later is still honoured).
func bind(carrier: Node3D, socket_source: Node = null, provider: RefCounted = null) -> void:
	_carrier = carrier
	_socket_source = socket_source
	_provider = provider
	_watch_skeleton()


## The socket is a bone. Bones move in the skeleton's own update, AFTER the
## physics step that pinned the held thing to where the bone WAS -- one frame
## of lag, which on a walking arm reads as the bottle floating behind the hand.
## So the pin is re-applied the moment the skeleton reports its bones settled.
var _skeleton: Skeleton3D = null


func _watch_skeleton() -> void:
	if _socket_source == null or not is_instance_valid(_socket_source):
		return
	var skeleton: Skeleton3D = _find_skeleton(_socket_source)
	if skeleton == null or skeleton == _skeleton:
		return
	_skeleton = skeleton
	if skeleton.has_signal("skeleton_updated") \
			and not skeleton.is_connected("skeleton_updated", _on_skeleton_updated):
		skeleton.connect("skeleton_updated", _on_skeleton_updated)


func _on_skeleton_updated() -> void:
	pin()


## Re-pins a HELD thing to its socket without advancing any timer. Safe to
## call any number of times per frame.
func pin() -> void:
	if _node == null or not is_instance_valid(_node) or _state != STATE_HELD:
		return
	if _shake_left > 0.0:
		return
	_apply(held_transform())


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func set_socket_source(socket_source: Node) -> void:
	_socket_source = socket_source


func set_provider(provider: RefCounted) -> void:
	_provider = provider


## -- Requests ----------------------------------------------------------------

## Starts carrying `node`. False (and nothing changes) when something is
## already being carried, when `node` is null, or when it is the carrier itself.
func carry(node: Node3D, socket_name: String = "") -> bool:
	if node == null or not is_instance_valid(node) or node == _carrier or node == self:
		return false
	if _node != null:
		return false
	_kind = KIND_CHILD if node.has_method("set_carried_by") else KIND_ITEM
	_socket_name = socket_name
	if _socket_name.is_empty():
		_socket_name = SOCKET_CHILD if _kind == KIND_CHILD else SOCKET_ITEM
	_node = node
	_from = SpatialUtil.world_transform(node)
	_original_parent = node.get_parent()
	_item_lift = 0.0

	if _kind == KIND_CHILD:
		node.call("set_carried_by", _carrier)
	else:
		_take_item(node)

	_elapsed = 0.0
	_set_state(STATE_PICKING_UP)
	carry_started.emit(node)
	return true


## Sets the carried thing down at `point` (world), or -- with no point -- at the
## first standable spot `find_put_down_spot()` offers. False when nothing is
## carried, when already placing, when the lift has not finished yet, or when
## there is nowhere to put it. `yaw` (radians, the project's -Z-facing
## convention) turns the thing as it lands -- a child laid on the bed faces the
## pillow, not the way she happened to face; null keeps her heading.
##
## Refusing mid-`STATE_PICKING_UP` matters more than it looks: one tap on the
## carry badge can reach `perform_affordance()` twice in the same instant (an
## emulated touch/mouse twin, or a fast double tap) and `child_actor.gd`
## re-derives CARRY-or-PLACE from `is_carried()` each time -- once he is
## `set_carried_by()`'d the second call already reads "carrying" and asks to be
## put straight back down before he has even reached the socket. Refusing here
## is the state machine's own backstop for that, independent of whatever
## caught (or missed) the twin upstream.
func put_down(point: Variant = null, yaw: Variant = null) -> bool:
	if _node == null or _state == STATE_PLACING or _state == STATE_IDLE or _state == STATE_PICKING_UP:
		return false
	var target: Variant = point if point is Vector3 else find_put_down_spot()
	if target == null:
		# Nowhere to put him -- a wall, a piece of furniture, her own feet. He
		# stays in her arms and the arms say so with a small sway.
		shake()
		return false
	_from = SpatialUtil.world_transform(_node)
	var basis: Basis = _carrier_yaw_basis()
	if yaw is float or yaw is int:
		basis = Basis(Vector3.UP, float(yaw))
	_to = Transform3D(basis, target as Vector3)
	_elapsed = 0.0
	_shake_left = 0.0
	_set_state(STATE_PLACING)
	return true


## A landing that was refused: the held thing sways once in her hands and
## settles, so the child sees "not there" without a word or a red X.
const SHAKE_SEC: float = 0.36
const SHAKE_AMPLITUDE: float = 0.05
var _shake_left: float = 0.0


func shake() -> void:
	if _node == null:
		return
	_shake_left = SHAKE_SEC


func is_shaking() -> bool:
	return _shake_left > 0.0


## A standable floor point an arm's length from the carrier, or null. See the
## class doc for the rule.
func find_put_down_spot(distance: float = PUT_DOWN_DISTANCE) -> Variant:
	if _carrier == null:
		return null
	var here: Vector3 = SpatialUtil.world_position(_carrier)
	var basis: Basis = _carrier_yaw_basis()
	var forward: Vector3 = -basis.z
	var provider: RefCounted = _live_provider()
	for degrees: float in PUT_DOWN_ANGLES_DEG:
		var direction: Vector3 = forward.rotated(Vector3.UP, deg_to_rad(degrees))
		var candidate: Vector3 = here + direction * distance
		var spot: Vector3 = candidate
		if provider != null and provider.has_method("snap_to_navigable"):
			spot = provider.call("snap_to_navigable", candidate)
			spot.y = here.y
			if NavMath.flat_distance(spot, candidate) > PUT_DOWN_SNAP_TOLERANCE:
				continue
		if NavMath.flat_distance(spot, here) < PUT_DOWN_MIN_CLEARANCE:
			continue
		return spot
	return null


## -- Queries -----------------------------------------------------------------

func get_carried() -> Node3D:
	return _node if _node != null and is_instance_valid(_node) else null


func is_carrying() -> bool:
	return get_carried() != null


func get_state() -> String:
	return _state


func get_kind() -> String:
	return _kind if _node != null else ""


func get_socket_name() -> String:
	return _socket_name if _node != null else ""


## Where the held thing sits this frame: the socket's position under the
## carrier's yaw. Public so a test or a screenshot harness can measure it.
func held_transform() -> Transform3D:
	var basis: Basis = _carrier_yaw_basis()
	var origin: Vector3 = Vector3.ZERO
	var socket: Node3D = _socket()
	if socket != null:
		origin = SpatialUtil.world_position(socket)
	else:
		var offset: Vector3 = FALLBACK_OFFSETS.get(_kind, FALLBACK_OFFSETS[KIND_ITEM])
		origin = SpatialUtil.world_transform(_carrier) * offset
	return Transform3D(basis, origin + Vector3.UP * _item_lift)


## True when the hold point comes from a real rig socket rather than the
## fallback offset.
func is_using_socket() -> bool:
	return _socket() != null


## -- Per-step advance ----------------------------------------------------------

## Called by the carrier after it has moved this step.
func sync(delta: float) -> void:
	if _node == null:
		return
	if not is_instance_valid(_node) or (_kind == KIND_ITEM and _node.get_parent() != self):
		# Freed, or taken away by somebody else mid-carry. Let go quietly.
		var gone: Node3D = _node if is_instance_valid(_node) else null
		_node = null
		_set_state(STATE_IDLE)
		if gone != null:
			carry_ended.emit(gone)
		return

	match _state:
		STATE_PICKING_UP:
			_elapsed += maxf(delta, 0.0)
			var k: float = _ease(_elapsed / PICK_UP_SEC)
			var target: Transform3D = held_transform()
			_apply(_blend(_from, target, k, LIFT_ARC))
			if _elapsed >= PICK_UP_SEC:
				_apply(target)
				_set_state(STATE_HELD)
				carry_settled.emit(_node)
		STATE_HELD:
			_keep_child_in_room()
			var held: Transform3D = held_transform()
			if _shake_left > 0.0:
				_shake_left = maxf(_shake_left - maxf(delta, 0.0), 0.0)
				var k: float = _shake_left / SHAKE_SEC
				held.origin += held.basis.x * (sin(k * PI * 3.0) * SHAKE_AMPLITUDE * k)
			_apply(held)
		STATE_PLACING:
			_elapsed += maxf(delta, 0.0)
			var k: float = _ease(_elapsed / PLACE_SEC)
			_apply(_blend(_from, _to, k, LIFT_ARC * 0.5))
			if _elapsed >= PLACE_SEC:
				_apply(_to)
				_land()
		_:
			pass


## -- Internals -----------------------------------------------------------------

func _take_item(node: Node3D) -> void:
	# Its centre, not its base, goes to the hand: every prop in this project
	# stands on its own origin (pivot at base centre), which is right for a
	# table and wrong for a hand.
	var visual: MeshInstance3D = _find_mesh(node)
	if visual != null and visual.mesh != null:
		var bounds: AABB = visual.transform * visual.mesh.get_aabb()
		_item_lift = -(bounds.position.y + bounds.size.y * 0.5) * node.scale.y
	if node is Area3D:
		_was_pickable = (node as Area3D).input_ray_pickable
		(node as Area3D).input_ray_pickable = false
	if "drag_enabled" in node:
		_was_drag_enabled = bool(node.get("drag_enabled"))
		node.set("drag_enabled", false)
	var world: Transform3D = SpatialUtil.world_transform(node)
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	add_child(node)
	_set_world(node, world)


func _land() -> void:
	var landed: Node3D = _node
	if _kind == KIND_CHILD:
		if landed.has_method("release_carried"):
			landed.call("release_carried")
	else:
		var world: Transform3D = SpatialUtil.world_transform(landed)
		var home: Node = _original_parent
		if home == null or not is_instance_valid(home):
			home = _carrier.get_parent() if _carrier != null else null
		if home != null and home != landed.get_parent():
			landed.get_parent().remove_child(landed)
			home.add_child(landed)
			_set_world(landed, world)
		if landed is Area3D:
			(landed as Area3D).input_ray_pickable = _was_pickable
		if "drag_enabled" in landed:
			landed.set("drag_enabled", _was_drag_enabled)
		if landed.has_method("set_home_position"):
			landed.call("set_home_position", landed.position)
	_node = null
	_kind = ""
	_original_parent = null
	_set_state(STATE_IDLE)
	carry_ended.emit(landed)


## A carried child rides between rooms with the carrier. Rooms are hidden when
## left (`room.set_active(false)`), so a child left in the old room's subtree
## would vanish from her arms at the door.
func _keep_child_in_room() -> void:
	if _kind != KIND_CHILD or _carrier == null or not _node.has_method("room_changed"):
		return
	var world: Node = _carrier.get_parent()
	if world == null or not world.has_method("get_current_room"):
		return
	var room: Node = world.call("get_current_room")
	if room == null or room == _node.get_parent():
		return
	_node.call("room_changed", room, _carrier)


func _apply(world: Transform3D) -> void:
	if _node == null or not is_instance_valid(_node):
		return
	_set_world(_node, world)


## World transform in or out of the tree: `global_transform` asserts
## `is_inside_tree()`, and the headless runner keeps everything out of it.
func _set_world(node: Node3D, world: Transform3D) -> void:
	if node.is_inside_tree():
		node.global_transform = world
		return
	var parent: Node = node.get_parent()
	if parent is Node3D:
		node.transform = SpatialUtil.world_transform(parent as Node3D).affine_inverse() * world
	else:
		node.transform = world


## Position lerped with an upward arc, yaw slerped. Scale is left alone.
func _blend(from: Transform3D, to: Transform3D, k: float, arc: float) -> Transform3D:
	var origin: Vector3 = from.origin.lerp(to.origin, k) + Vector3.UP * (arc * sin(k * PI))
	var rotation: Quaternion = from.basis.get_rotation_quaternion().slerp(
			to.basis.get_rotation_quaternion(), k)
	return Transform3D(Basis(rotation).scaled(from.basis.get_scale()), origin)


static func _ease(t: float) -> float:
	var k: float = clampf(t, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


func _carrier_yaw_basis() -> Basis:
	if _carrier == null:
		return Basis.IDENTITY
	var forward: Vector3 = -SpatialUtil.world_transform(_carrier).basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return Basis.IDENTITY
	return Basis(Vector3.UP, atan2(-forward.x, -forward.z))


func _socket() -> Node3D:
	if _socket_source == null or not is_instance_valid(_socket_source):
		return null
	if _socket_source.has_method("has_socket") and not bool(_socket_source.call("has_socket", _socket_name)):
		return null
	if not _socket_source.has_method("get_socket"):
		return null
	var socket: Node3D = _socket_source.call("get_socket", _socket_name) as Node3D
	if socket == null or socket == _socket_source:
		return null
	return socket


func _live_provider() -> RefCounted:
	if _carrier != null and _carrier.has_method("get_movement_controller"):
		var controller: RefCounted = _carrier.call("get_movement_controller")
		if controller != null and controller.has_method("get_provider"):
			var provider: RefCounted = controller.call("get_provider")
			if provider != null:
				return provider
	return _provider


func _set_state(state: String) -> void:
	if state == _state:
		return
	_state = state
	state_changed.emit(state)


func _find_mesh(node: Node) -> MeshInstance3D:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		var deeper: MeshInstance3D = _find_mesh(child)
		if deeper != null:
			return deeper
	return null
