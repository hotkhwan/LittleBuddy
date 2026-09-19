extends Node3D

## ============================================================================
## LITTLE BUDDY, IN THE HOUSE -- the child as an inhabitant, not a prop.
## ============================================================================
##
## The thing the caregiver looks after. It owns the child's stats, decides what
## the child needs, shows the matching pose, and says so.
##
## ## Why this exists on top of the wrapper
##
## `baby_little_buddy.gd` knows how to SHOW a pose and nothing else -- by design,
## so a re-export changes one file. `child_needs.gd` knows what is TRUE and
## nothing else. Neither should own a `BabyState` or a speech bubble, so this is
## the node that joins them and is the only thing `house_world` has to find.
##
## ## The bubble is the whole point
##
## A child whose need is invisible is furniture. The floating line is how a
## player who cannot read a stat bar -- which is every player, there is no stat
## bar -- knows that Little Buddy is hungry and that going to the kitchen is the
## thing to do. It is `Label3D` so it is lit, occluded and scaled by the same
## camera as the child, and sits in the room rather than on top of it.

const WrapperScript := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
const StatsScript := preload("res://scripts/care/child_stats.gd")
const Needs := preload("res://scripts/care/child_needs.gd")
const Present := preload("res://scripts/care/child_presentation.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const Follower := preload("res://scripts/care/child_follower.gd")
const ActivityTargetScript := preload("res://scripts/navigation/activity_target.gd")
const InteractionPointScript := preload("res://scripts/navigation/interaction_point.gd")

## Emitted when the child's dominant need changes, so a mission can react without
## polling. Empty string means content.
signal need_changed(need: String)
## Emitted when the visible pose changes, so a test can assert the cut happened.
signal activity_changed(activity: String, pose: String)
## Emitted once when the child finishes walking to where it was sent.
signal arrived()

## Clear of the CAREGIVER's head, not just the child's. Buddy is 1.65 m and
## stands right next to a 0.78 m child, so a bubble sized to the child alone
## renders behind her hair -- which is where the first version put it.
const BUBBLE_HEIGHT: float = 1.12
const BUBBLE_FONT_SIZE: int = 56
const BUBBLE_PIXEL_SIZE: float = 0.0016

var _state: RefCounted = null
var _wrapper: Node3D = null
var _bubble: Label3D = null
var _activity: String = Present.ACTIVITY_IDLE
var _need: String = ""
var _built: bool = false

## -- Accompaniment -------------------------------------------------------------
var _follow_state: String = Follower.STATE_WAITING
var _following: Node3D = null
var _attend_point: Vector3 = Vector3.ZERO
var _attending: bool = false
var _player: AnimationPlayer = null


func _ready() -> void:
	build()


## Idempotent and callable before `_ready()`, for the same reason every other
## wrapper in this project is: the headless runner never fires `_ready()` for a
## node added to the root.
func build() -> void:
	if _built:
		return
	_built = true
	_state = StatsScript.new()

	_wrapper = WrapperScript.new()
	_wrapper.name = "Model"
	add_child(_wrapper)
	_wrapper.call("build")

	_bubble = Label3D.new()
	_bubble.name = "NeedBubble"
	_bubble.font_size = BUBBLE_FONT_SIZE
	_bubble.pixel_size = BUBBLE_PIXEL_SIZE
	_bubble.modulate = Palette.INK
	_bubble.outline_size = 14
	_bubble.outline_modulate = Palette.CREAM
	# Billboarded: the child is small and may be approached from any side, and a
	# line the player has to walk around to read is not a signal.
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0.0, BUBBLE_HEIGHT, 0.0)
	add_child(_bubble)

	_player = _find_player(_wrapper)
	_build_target()
	_refresh()


## The child is a place Buddy can WALK TO.
##
## Without this the caregiver can see Little Buddy and never reach him, and the
## first mission step ("go and talk to the child") has no target to name. So the
## child registers its own `ActivityTarget`, rather than the room having to know
## that a child might be standing in it.
##
## Node order matters and is not cosmetic: `ActivityTarget._ensure_resolved()`
## latches on its first call and caches whatever `InteractionPoint` exists at
## that moment, so the shape and the marker are added BEFORE any property is set.
## `room.gd::_add_target()` documents the same trap, and getting it wrong puts
## the stand position inside a wall.
const TARGET_SUFFIX: String = "littleBuddy"
## Where Buddy stands to talk to the child: in front of it, an arm's length away.
const STAND_OFFSET := Vector3(0.0, 0.0, 0.62)

var _target: Area3D = null


func _build_target() -> void:
	_target = Area3D.new()
	_target.name = TARGET_SUFFIX
	_target.set_script(ActivityTargetScript)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	# Generous: a four-year-old taps a region, and the child is only 0.78 m tall.
	box.size = Vector3(0.66, 0.9, 0.66)
	shape.shape = box
	shape.position = Vector3(0.0, 0.45, 0.0)
	_target.add_child(shape)

	var point := Marker3D.new()
	point.name = "InteractionPoint"
	point.set_script(InteractionPointScript)
	point.position = STAND_OFFSET
	_target.add_child(point)

	# LOCAL id only. `ActivityTarget` prefixes `room_id` itself to build the
	# semantic id, so passing "bedroom.littleBuddy" here yields
	# "bedroom.bedroom.littleBuddy" -- which is what the first version did.
	var room_id: String = _room_id_of(self)
	_target.set("target_id", TARGET_SUFFIX)
	_target.set("display_name", "Little Buddy")
	_target.set("arrival_radius", 0.3)
	if "room_id" in _target:
		_target.set("room_id", room_id)
	if _target.has_method("set_supported_actions"):
		_target.call("set_supported_actions", ["talkTo", "comfort", "pickUp"])
	add_child(_target)


func get_activity_target() -> Area3D:
	build()
	return _target


func _room_id_of(node: Node) -> String:
	var walker: Node = node.get_parent()
	while walker != null:
		if walker.has_method("get_room_id"):
			return String(walker.call("get_room_id"))
		walker = walker.get_parent()
	return ""


## -- Accompaniment ---------------------------------------------------------------

## Start walking after `buddy`. Passing null stops.
##
## Following, not carrying: the rigged child has real walk and run clips, so this
## is honest. Carrying would need a hold pose on Buddy and an attach point on her
## rig, and she has neither -- so it is not faked.
func follow(buddy: Node3D) -> void:
	build()
	_following = buddy
	_attending = false
	if buddy == null and _follow_state != Follower.STATE_ATTENDING:
		_follow_state = Follower.STATE_WAITING
		_play_clip("")


## Stand at a fixed world point and face it -- a sink, a bed. Wins over
## following, so a child placed for a care act stays put while Buddy shuffles.
func attend(world_point: Vector3) -> void:
	build()
	_attend_point = world_point
	_attending = true
	_follow_state = Follower.STATE_ATTENDING
	global_position = Vector3(world_point.x, global_position.y, world_point.z)
	_play_clip("")


func stop_attending() -> void:
	_attending = false
	_follow_state = Follower.STATE_WAITING


func get_follow_state() -> String:
	return _follow_state


## Advances the walk. Split out of `_process` so a headless smoke test drives
## exactly the same code a device does.
func step(delta: float) -> void:
	if not _built or _attending or _following == null:
		return
	var target: Vector3 = Follower.follow_point(
		_following.global_position, -_following.global_transform.basis.z)

	# Stranded: only ever resolved while a transition covers the screen, so the
	# child never pops in front of the camera. `room_changed()` is that moment.
	var previous: String = _follow_state
	_follow_state = Follower.next_state(
		previous, global_position, target, true, false)

	if _follow_state == Follower.STATE_FOLLOWING:
		global_position = Follower.step_towards(global_position, target, delta)
		var facing: Vector3 = Follower.facing_for(_follow_state, global_position, target)
		if facing.length_squared() > 0.0001:
			# The model faces -Z, so look along the travel direction.
			look_at(global_position - facing, Vector3.UP)
		_play_clip(Follower.clip_for(_follow_state))
	else:
		_play_clip("")

	if _follow_state == Follower.STATE_ARRIVING and previous != Follower.STATE_ARRIVING:
		arrived.emit()


func _process(delta: float) -> void:
	step(delta)


## Called by the world when Buddy changes room. The child is MOVED, not walked:
## walking it through a wall is worse than a cut, and the transition fade is
## already covering the screen -- which is the only moment a re-place is allowed.
func room_changed(new_room: Node3D, buddy: Node3D) -> void:
	build()
	if new_room != null and get_parent() != new_room:
		var keep: Transform3D = global_transform
		get_parent().remove_child(self)
		new_room.add_child(self)
		global_transform = keep
	if buddy != null:
		global_position = Follower.follow_point(
			buddy.global_position, -buddy.global_transform.basis.z)
	_follow_state = Follower.STATE_WAITING
	_play_clip("")


func _play_clip(clip: String) -> void:
	if _player == null:
		return
	if clip.is_empty():
		if _player.is_playing():
			_player.stop()
		return
	if _player.has_animation(clip) and _player.current_animation != clip:
		_player.play(clip)


func _find_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null


## -- What the child needs -------------------------------------------------------

func get_stats() -> RefCounted:
	build()
	return _state


func get_need() -> String:
	build()
	return _need


func get_activity() -> String:
	return _activity


func get_line() -> String:
	build()
	return Needs.line_for(_need)


## Sets what the caregiver is doing with the child. An explicit activity wins
## over whatever the stats would have chosen -- that is what lets Milk Time seat
## the child even while another stat drifts, and it is the brief's "make
## transitions deliberate".
func set_activity(activity: String) -> void:
	build()
	if _activity == activity:
		return
	_activity = activity
	_refresh()


## The caregiver answered a need. Moves the stat that caused it, so the child
## stops asking -- the loop closes in the model rather than in a mission script.
func satisfy(need: String, amount: float = 60.0) -> void:
	build()
	match need:
		Needs.HUNGRY:
			_state.call("adjust", "hunger", -amount)
		Needs.THIRSTY:
			_state.call("adjust", "thirst", -amount)
		Needs.SLEEPY:
			_state.call("adjust", "energy", amount)
		Needs.DIRTY, Needs.NEEDS_BATH:
			_state.call("adjust", "cleanliness", amount)
		Needs.NEEDS_CHANGING:
			_state.call("adjust", "freshness", amount)
		Needs.NEEDS_COMFORT, Needs.WANTS_TO_PLAY, Needs.CRYING:
			_state.call("adjust", "happiness", amount)
	# Being cared for is pleasant whatever the need was.
	_state.call("adjust", "happiness", 8.0)
	_refresh()


## Convenience for the common case: answer whatever the child is asking for.
func satisfy_current(amount: float = 60.0) -> String:
	build()
	var answered: String = _need
	if answered.is_empty():
		return ""
	satisfy(answered, amount)
	return answered


## -- Presentation ---------------------------------------------------------------

func _refresh() -> void:
	if _state == null or _wrapper == null:
		return
	var described: Dictionary = Present.describe(
		_state.call("describe"), _activity)

	var new_need: String = String(described["need"])
	if new_need != _need:
		_need = new_need
		need_changed.emit(_need)

	var pose: String = String(described["pose"])
	if _wrapper.has_method("set_pose") and String(_wrapper.call("get_pose")) != pose:
		_wrapper.call("set_pose", pose)
		activity_changed.emit(String(described["activity"]), pose)

	if _bubble != null:
		# Nothing to say when content: an empty bubble is quieter than a cheerful
		# one, and the child should only interrupt when it wants something.
		_bubble.visible = not _need.is_empty()
		_bubble.text = String(described["line"])


## The pose currently shown, for tests and for the production report.
func get_pose() -> String:
	build()
	return String(_wrapper.call("get_pose")) if _wrapper != null else ""


## Where a bottle, a towel or a teddy should be aimed. Delegates to the wrapper's
## `LB_Rig_v1` sockets, so gameplay never names a bone -- and never returns null.
func get_socket(socket_name: String) -> Node3D:
	build()
	if _wrapper != null and _wrapper.has_method("get_socket"):
		return _wrapper.call("get_socket", socket_name)
	return self
