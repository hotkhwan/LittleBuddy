extends RefCounted

## Every movement *decision* Little Buddy makes, with zero engine coupling.
##
## This object owns the character state machine, the path, the arrival debounce,
## the reachability verdict, path replacement and action timing. It holds no
## node, touches no `NavigationAgent3D`, and runs no physics -- it is advanced by
## hand with `advance(position, yaw, delta)` and returns what should happen next.
##
## That is deliberate, and it is the reason this spike has real test coverage:
## the headless `--script` runner has no physics frames, so anything that can
## only be observed by running a `CharacterBody3D` for a second is untestable
## there. Keeping the decisions pure moves almost all of the risk into code that
## a unit test can drive frame by frame.
##
## `LittleBuddyCharacter` is the thin `CharacterBody3D` shell that feeds this its
## real position and applies the velocity it returns.
##
## ## States
##
## Exactly five, no more: IDLE, WALKING, INTERACTING, CARRYING, DISABLED.
## CARRYING is the *resting* state while holding something -- a character that
## walks while carrying is WALKING with `is_carrying()` true, so the animation
## layer can pick a carry-walk clip without inventing a sixth state.
##
## The same trick covers held poses. Sitting and sleeping are postures, not
## events, so `request_action(name, duration, true)` runs its settle timer, ends
## it like any other action, and then parks the character in its RESTING state
## with `get_held_action()` naming the pose. There is no SITTING state and no
## SLEEPING state: a posture is not a reason to stop accepting instructions, and
## a state per action is exactly the overbuild this file exists to avoid. The
## hold is released by any new request, by `cancel()`, by `release_hold()` or by
## being disabled, so a child's next tap always works.
##
## ## The rules worth knowing
##
## * **One destination, never a queue.** A new move request replaces the path in
##   place. Ten impatient taps leave exactly one destination and one path.
## * **Arrival fires exactly once per request**, latched, and the latch only
##   clears when a new request is accepted.
## * **Unreachable never disturbs anything.** A tap on a wall or outside the room
##   returns UNREACHABLE and leaves the character doing precisely what it was
##   already doing -- it does not cancel a good walk and it never leaves a walk
##   animation playing with nowhere to go.
## * **A near-miss is forgiven.** A tap that lands just off the navigation mesh
##   (a child's thumb on the skirting board) walks to the nearest standable point
##   instead of being refused.

const NavMath := preload("res://scripts/navigation/nav_math.gd")
const NavigationProviderScript := preload("res://scripts/navigation/navigation_provider.gd")

enum State { IDLE, WALKING, INTERACTING, CARRYING, DISABLED }

## Outcome of `request_move()`.
##   ACCEPTED    -- walking to exactly where you asked.
##   SNAPPED     -- the tap was slightly off the mesh; walking to the nearest
##                  standable point instead. Still a success, still child-friendly.
##   UNREACHABLE -- too far off the mesh to guess. Nothing changed.
##   REFUSED     -- the character is DISABLED.
enum MoveResult { ACCEPTED, SNAPPED, UNREACHABLE, REFUSED }

const STATE_NAMES: Dictionary = {
	State.IDLE: "idle",
	State.WALKING: "walking",
	State.INTERACTING: "interacting",
	State.CARRYING: "carrying",
	State.DISABLED: "disabled",
}

## Calm toddler pace, not an action game. ~0.85 m/s crosses a 4 m room in five
## seconds, which reads as purposeful walking rather than sliding.
const WALK_SPEED: float = 0.85
## Radians/second. Fast enough that a child sees an immediate response to a tap,
## slow enough that the turn is visible rather than a snap.
const TURN_SPEED: float = 4.5
## How close counts as arrived. Generous on purpose -- a child taps a region, not
## a pixel, and the last centimetre of travel is invisible and worth nothing.
const ARRIVAL_RADIUS: float = 0.18
## How close counts as "this waypoint is done". Smaller than ARRIVAL_RADIUS so
## corners are still cut cleanly.
const WAYPOINT_RADIUS: float = 0.12
## Facing is "done" within ~7 degrees. Tighter than this and a character can
## chase the last fraction of a degree forever on a moving target.
const FACING_TOLERANCE: float = 0.12
## How far the path's real endpoint may sit from the requested point and still
## count as having reached it.
const REACH_TOLERANCE: float = 0.25
## How far off the navigation mesh a tap may land and still be forgiven by
## walking to the nearest standable point. Beyond this we assume the child meant
## something else entirely and do nothing.
const SNAP_RADIUS: float = 0.9
## A semantic action with no declared duration (including one whose animation
## does not exist yet) runs for this long and then ends. This is the "no stuck
## state" guarantee.
const DEFAULT_ACTION_SEC: float = 1.2

var _provider: RefCounted = null

var _state: int = State.IDLE
var _carrying: bool = false
var _disabled: bool = false

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _destination: Vector3 = Vector3.ZERO
var _target_id: String = ""
## Vector3 to face on arrival, or null for "keep whatever heading you finish on"
## (a plain floor tap).
var _facing_point: Variant = null
var _arrival_radius: float = ARRIVAL_RADIUS

var _arrived_emitted: bool = false
var _interaction_ready_emitted: bool = false
## Increments once per *accepted, path-replacing* request. Lets a caller (and a
## test) prove that a second tap replaced the first rather than queueing behind it.
var _move_serial: int = 0

var _action_name: String = ""
var _action_remaining: float = 0.0
## True while the action currently running is a posture that will persist once
## its settle timer ends, rather than a one-shot that returns to rest.
var _action_holds: bool = false
## The posture currently being held ("sit", "sleep", "hold"), or "" for none.
## Orthogonal to `_state` on purpose -- see the class doc.
var _held_action: String = ""


static func create(provider: RefCounted = null) -> RefCounted:
	var controller: RefCounted = (
		load("res://scripts/character/character_movement_controller.gd") as GDScript
	).new()
	controller.call("set_provider", provider)
	return controller


static func state_name(state: int) -> String:
	return String(STATE_NAMES.get(state, "idle"))


## Never leaves `_provider` null: a missing provider degrades to the
## straight-line fallback rather than to a crash or a character that refuses to
## move.
func set_provider(provider: RefCounted) -> void:
	_provider = provider if provider != null else NavigationProviderScript.new()


func get_provider() -> RefCounted:
	return _provider


## -- Requests ----------------------------------------------------------------

## Walks to `destination`.
##
## `options` (all optional):
##   `targetId`      String -- the semantic id reported back on arrival.
##   `facePoint`     Vector3 -- turn to face this on arrival, then report
##                   interaction-ready. Omit for a plain floor tap.
##   `arrivalRadius` float -- override the default arrival generosity.
##
## Returns a `MoveResult`. See the enum for what each one means; UNREACHABLE and
## REFUSED both leave the character exactly as it was.
func request_move(destination: Vector3, options: Dictionary = {}) -> int:
	if _disabled:
		return MoveResult.REFUSED
	if _provider == null:
		set_provider(null)

	var from: Vector3 = _last_known_position
	var path: PackedVector3Array = _provider.call("query_path", from, destination)
	var endpoint: Vector3 = NavMath.path_endpoint(path, from)

	var result: int = MoveResult.ACCEPTED
	var effective: Vector3 = destination
	if not NavMath.path_reaches(path, destination, REACH_TOLERANCE):
		# `map_get_path()` never says "no" -- it silently returns a path that stops
		# short. The distance between what was asked for and where the path really
		# ends IS the reachability signal.
		if NavMath.flat_distance(endpoint, destination) <= SNAP_RADIUS:
			result = MoveResult.SNAPPED
			effective = endpoint
		else:
			return MoveResult.UNREACHABLE

	# Anti-jitter: a second tap essentially on top of the current destination is
	# honoured by doing nothing at all, rather than by rebuilding the path and
	# restarting the walk animation. Ten taps in the same spot = one smooth walk.
	if _state == State.WALKING and NavMath.is_within(effective, _destination, ARRIVAL_RADIUS):
		return result

	_adopt_path(path, effective, options)
	return result


## Plays a semantic action ("drink", "brushTeeth", "celebrate"...).
##
## The controller neither knows nor cares whether an animation for `action_name`
## exists, nor what the word means. It always runs a timer and always ENDS the
## action, so an action whose clip has not been authored yet is a short pause,
## never a stuck character. Walking is cancelled first -- the child asked for
## something else -- and any posture already being held is released, because you
## cannot start brushing your teeth while still asleep.
##
## `hold` is the one-shot/posture distinction, passed in rather than looked up:
## the vocabulary lives in `character_action_driver.gd` and this object stays a
## pure timer and state machine. When true, the action still finishes normally
## after `duration`, and the character then rests *in* the pose --
## `get_held_action()` reports it until something releases it.
func request_action(action_name: String, duration: float = -1.0, hold: bool = false) -> bool:
	if _disabled:
		return false
	if action_name.strip_edges().is_empty():
		return false
	_clear_path()
	_held_action = ""
	_action_name = action_name
	_action_holds = hold
	_action_remaining = duration if duration > 0.0 else DEFAULT_ACTION_SEC
	_state = State.INTERACTING
	return true


## Ends a held posture and returns to rest. Returns the posture that was
## released, or "" if there was nothing to release -- so a caller can tell the
## difference between "stood up" and "was already standing" without asking first.
func release_hold() -> String:
	var released: String = _held_action
	_held_action = ""
	return released


## The posture currently held ("sit", "sleep", "hold"), or "".
func get_held_action() -> String:
	return _held_action


func is_holding() -> bool:
	return not _held_action.is_empty()


## Stops whatever is happening and returns to rest. Emits no arrival: a cancelled
## walk did not arrive.
func cancel() -> void:
	_clear_path()
	_action_name = ""
	_action_remaining = 0.0
	_action_holds = false
	_held_action = ""
	if not _disabled:
		_state = _resting_state()


func set_carrying(carrying: bool) -> void:
	_carrying = carrying
	if _state == State.IDLE or _state == State.CARRYING:
		_state = _resting_state()


func is_carrying() -> bool:
	return _carrying


## DISABLED is the hard stop: a cutscene, an overlay, a summary screen. Every
## request is refused until it is cleared, and clearing it returns the character
## to rest rather than to whatever it was doing an hour ago.
func set_disabled(disabled: bool) -> void:
	if disabled == _disabled:
		return
	_disabled = disabled
	if disabled:
		_clear_path()
		_action_name = ""
		_action_remaining = 0.0
		_action_holds = false
		_held_action = ""
		_state = State.DISABLED
	else:
		_state = _resting_state()


func is_disabled() -> bool:
	return _disabled


## -- Per-frame advance --------------------------------------------------------

## The whole simulation step, as a pure function of (position, yaw, delta).
##
## Returns:
##   `state`            int          -- a `State`
##   `stateName`        String
##   `velocity`         Vector3      -- horizontal; Y is the body's business
##   `yaw`              float        -- the heading to apply this frame
##   `arrived`          bool         -- true on exactly ONE frame per request
##   `interactionReady` bool         -- true on exactly ONE frame per request,
##                                      after the turn-to-face completes
##   `actionFinished`   bool
##   `targetId`         String
##   `actionName`       String
##   `heldAction`       String       -- the posture being held, or ""
func advance(position: Vector3, yaw: float, delta: float) -> Dictionary:
	_last_known_position = position

	var step: Dictionary = {
		"state": _state,
		"stateName": state_name(_state),
		"velocity": Vector3.ZERO,
		"yaw": yaw,
		"arrived": false,
		"interactionReady": false,
		"actionFinished": false,
		"targetId": _target_id,
		"actionName": _action_name,
		"heldAction": _held_action,
	}
	if _disabled:
		return step

	match _state:
		State.WALKING:
			_advance_walking(position, yaw, delta, step)
		State.INTERACTING:
			_advance_interacting(delta, step)
		_:
			pass

	step["state"] = _state
	step["stateName"] = state_name(_state)
	# Only refresh the name for an action still running. An action that finished
	# this frame already cleared `_action_name`, and overwriting the reported name
	# with "" here would make `action_finished` fire with no name at all.
	if not bool(step["actionFinished"]):
		step["actionName"] = _action_name
	step["heldAction"] = _held_action
	return step


func _advance_walking(position: Vector3, yaw: float, delta: float, step: Dictionary) -> void:
	if _path.is_empty():
		# Nothing to walk along. Fail safe to rest rather than to a walk animation
		# with no destination.
		_finish_walk(step)
		return

	_path_index = NavMath.advance_path_index(_path, position, _path_index, WAYPOINT_RADIUS)
	var at_destination: bool = NavMath.is_within(position, _destination, _arrival_radius)

	if not at_destination:
		var waypoint: Vector3 = _path[_path_index]
		var velocity: Vector3 = NavMath.steer_velocity(position, waypoint, WALK_SPEED, delta)
		step["velocity"] = velocity
		if velocity.length_squared() > 0.0:
			var heading: float = NavMath.yaw_towards(position, position + velocity, yaw)
			step["yaw"] = NavMath.step_yaw(yaw, heading, TURN_SPEED * delta)
		return

	# Position is done. Report arrival once, then turn to face if asked.
	if not _arrived_emitted:
		_arrived_emitted = true
		step["arrived"] = true

	if _facing_point == null:
		_finish_walk(step)
		return

	var face_yaw: float = NavMath.yaw_towards(position, _facing_point as Vector3, yaw)
	var new_yaw: float = NavMath.step_yaw(yaw, face_yaw, TURN_SPEED * delta)
	step["yaw"] = new_yaw
	if NavMath.yaw_reached(new_yaw, face_yaw, FACING_TOLERANCE):
		if not _interaction_ready_emitted:
			_interaction_ready_emitted = true
			step["interactionReady"] = true
		_finish_walk(step)


func _advance_interacting(delta: float, step: Dictionary) -> void:
	_action_remaining -= delta
	if _action_remaining > 0.0:
		return
	step["actionFinished"] = true
	step["actionName"] = _action_name
	# A posture is now *held*: the action is genuinely over (a mission awaiting
	# `action_finished` is released, so nothing can dead-end), but the character
	# stays in the pose until something releases it.
	_held_action = _action_name if _action_holds else ""
	_action_name = ""
	_action_remaining = 0.0
	_action_holds = false
	_state = _resting_state()


## Ends the walk without touching the arrival latches -- they belong to the
## request, not to the walk, and are only cleared when a new request is accepted.
func _finish_walk(_step: Dictionary) -> void:
	_path = PackedVector3Array()
	_path_index = 0
	_state = _resting_state()


## -- Queries (used by the character shell, the spike scene and the tests) -----

func get_state() -> int:
	return _state


func get_state_name() -> String:
	return state_name(_state)


func get_destination() -> Vector3:
	return _destination


func get_target_id() -> String:
	return _target_id


func get_path() -> PackedVector3Array:
	return _path


func get_path_size() -> int:
	return _path.size()


func get_move_serial() -> int:
	return _move_serial


func get_action_name() -> String:
	return _action_name


func is_moving() -> bool:
	return _state == State.WALKING


## True while the character should not be handed a new mission instruction.
func is_busy() -> bool:
	return _state == State.WALKING or _state == State.INTERACTING or _disabled


## -- Internals ----------------------------------------------------------------

## The controller is advanced with an external position, but `request_move()` can
## be called between frames and needs a start point. Remembering the last one
## advanced (seeded by `set_position()`) keeps `request_move()` a pure function of
## known state instead of requiring the caller to pass a position it already gave us.
var _last_known_position: Vector3 = Vector3.ZERO


func set_position(position: Vector3) -> void:
	_last_known_position = position


func get_position() -> Vector3:
	return _last_known_position


func _adopt_path(path: PackedVector3Array, destination: Vector3, options: Dictionary) -> void:
	# Replacement, not a queue: there is exactly one `_path` and exactly one
	# `_destination` field in this object, so a second request cannot stack.
	_path = path
	_path_index = 0
	_destination = destination
	_target_id = String(options.get("targetId", ""))
	_arrival_radius = float(options.get("arrivalRadius", ARRIVAL_RADIUS))
	var face: Variant = options.get("facePoint", null)
	_facing_point = face if face is Vector3 else null
	_arrived_emitted = false
	_interaction_ready_emitted = false
	_action_name = ""
	_action_remaining = 0.0
	_action_holds = false
	# You cannot walk while sitting or asleep. Accepting a walk releases the pose,
	# which is why a child can never tap the character into a corner it cannot get
	# out of.
	_held_action = ""
	_move_serial += 1
	_state = State.WALKING


func _clear_path() -> void:
	_path = PackedVector3Array()
	_path_index = 0
	_facing_point = null
	_target_id = ""


func _resting_state() -> int:
	return State.CARRYING if _carrying else State.IDLE
