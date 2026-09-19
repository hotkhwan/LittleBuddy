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

## Emitted when the child's dominant need changes, so a mission can react without
## polling. Empty string means content.
signal need_changed(need: String)
## Emitted when the visible pose changes, so a test can assert the cut happened.
signal activity_changed(activity: String, pose: String)

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

	_refresh()


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
