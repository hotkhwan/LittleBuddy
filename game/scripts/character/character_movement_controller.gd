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
##
## ## Two ways to drive, one state machine
##
## Tap-to-walk gives this object a DESTINATION. The virtual thumbstick
## (`scripts/input/virtual_joystick.gd`, added after a physical-device request for
## RoV-style control) gives it a DIRECTION instead, through `set_drive()`.
##
## Direct drive enters here rather than being applied to the body behind this
## object's back, and that is the whole point: if the node wrote a velocity of its
## own, the state machine would no longer know what the character was doing and
## `Idle/Walking/Interacting/Carrying/Disabled` would stop being true. Driving is
## WALKING, exactly like a pathed walk, with `get_target_id()` empty because there
## is no destination -- and `set_disabled(true)` still refuses it, the arrival
## latch still fires at most once per request, and a drive never fires one at all.
##
## Taking the stick REPLACES a path in progress, the same way a second tap
## replaces the first: there is one `_path` and one `_drive_input`, and the two
## can never both be steering.

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

## Calm toddler pace, not an action game -- but not a slideshow either.
##
## This was 0.85 m/s, and a 4 m room took 4.7 s to cross. Played on a physical
## phone that is most of a five-second wait after every single tap, and it was
## half of why tap-to-walk was reported as "not smooth": the other half was that
## nothing acknowledged the tap at all (see `TapRipple`).
##
## The device finding stands and the speed went up. The number did not survive
## contact with the character's legs, though, and now reads 1.05 m/s.
##
## The 1.25 m/s version justified itself on the walk clip's stride, quoting
## "0.35-0.44 m" between foot plants. `toddler_view.gd`'s legs are 0.22 m long
## (the hip sits at 0.22 m on a 0.85 m child), so a +/-33 degree swing separates
## the feet by `2 * 0.22 * sin(33) = 0.24 m` -- not 0.35-0.44 m. At 1.25 m/s the
## body covered 0.40 m per step against a 0.24 m stride, so the feet skated 1.67x:
## WORSE than the 1.14x at 0.85 m/s, which is the opposite of the intent.
##
## There is also a hard biomechanical ceiling. Gait transitions from walking to
## running at a Froude number of roughly 0.5, and `Fr = v^2 / (g * legLength)`.
## For a 0.22 m leg: 0.85 m/s is Fr 0.33, 1.05 m/s is Fr 0.51, and 1.25 m/s is
## Fr 0.72 -- decisively a RUN. No walk cycle can be authored to make 1.25 m/s
## read as walking; it would look like a toddler skating across the room.
##
## 1.05 m/s is the top of the walk range: a 4 m room in 3.8 s rather than 4.7 s,
## which keeps most of the responsiveness win. The walk clip has been re-authored
## to match it exactly (45 degree swing, 0.59 s cycle, 0.311 m stride, zero
## skate), and `test_movement_controller.gd` now checks that the speed and the
## clip still agree, so neither can be changed alone again.
const WALK_SPEED: float = 1.05

## The run. Added 2026-09-20 after the owner played the thumbstick and reported
## "run is not faster than walk" -- and measured, it was not: every mode of travel
## topped out at exactly `WALK_SPEED`, and `locomotion.gd` was already playing
## the RUN clip at that speed (1.05 m/s is a jog for a 1.65 m caregiver). So the
## character LOOKED like she was running and covered the room at walking pace.
##
## 1.6 m/s is 1.52x the walk: a 4 m room in 2.5 s rather than 3.8 s, which is a
## difference a child can feel under the thumb without becoming an action game.
## The run clip's natural speed is 0.989 m/s (`locomotion.gd`), so the feet keep
## up at a 1.62x trim -- inside `Locomotion.MAX_SCALE` -- and the cadence stays
## planted. `test_run_vs_walk.gd` measures the displacement of the REAL character
## in both modes and asserts the ratio.
##
## Only the thumbstick runs. Tap-to-walk stays at `WALK_SPEED`: a tap is a calm
## instruction, a hard push is urgency, and a run to every tapped bottle would
## make the calm pace impossible to ask for.
const RUN_SPEED: float = 1.6

## The stick's walk/run boundary, as a magnitude of its 0..1 output.
##
## Up to here the thumb asks for a walk, scaled so that this deflection is
## exactly `WALK_SPEED`; past it the speed climbs linearly to `RUN_SPEED` at full
## deflection. 0.70 puts the boundary where a MOBA thumb expects it: a gentle or
## half push walks, a push out to the ring runs. Continuous and monotonic, so
## there is no step under the thumb at the boundary, and `is_running()` reports
## which side of it the character is on so the HUD can say so.
## `virtual_joystick.gd` mirrors this number to draw the boundary; `test_joystick.gd`
## asserts the two still agree.
const RUN_MAGNITUDE: float = 0.70

## Above this ground speed the character counts as running, for `is_running()`.
## A little over the walk ceiling rather than exactly on it, so a full walk at
## the boundary does not flicker the report.
const RUN_REPORT_SPEED: float = WALK_SPEED * 1.06
## Radians/second. Fast enough that a child sees an immediate response to a tap,
## slow enough that the turn is visible rather than a snap.
##
## Raised from 4.5 with the same device feedback in mind. Little Buddy TURNS
## WHILE WALKING rather than stopping to turn first -- stopping to turn would add
## latency to the very gesture that was reported as unresponsive -- so the turn
## rate is what decides how quickly he visibly commits to a new direction. At 7.0
## a typical 90-degree change of mind resolves in 0.22 s and the worst case, a
## full reversal, in 0.45 s. That is FASTER than the old rate even though he now
## moves quicker: a reversal used to drift 0.59 m sideways before he was facing
## the right way, and now drifts 0.56 m.
const TURN_SPEED: float = 7.0
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
## A `nearest` request (a plain floor tap) that would move the character less
## than this is not worth a walk cycle: it is refused as UNREACHABLE rather than
## shuffled two centimetres.
const MIN_NEAREST_TRAVEL: float = 0.15
## And how far off the mesh a `nearest` tap may land and still be walked
## towards: the apron in front of the room and a wall are inside this, another
## room across the house (10 m away, a separate island) is not -- a tap there
## stays UNREACHABLE, so the child is never marched into a wall towards a room
## she cannot see.
const NEAREST_RADIUS: float = 6.0

## -- Direct drive (the virtual thumbstick) ------------------------------------

## How quickly the driven velocity catches up with the thumb, m/s^2. At 8.0 the
## character reaches full walk in 0.13 s and stops in 0.13 s: immediate enough to
## feel like direct control, gradual enough that letting go is a stop rather than
## a freeze-frame. "Release = stop, smoothly" is this number.
const DRIVE_ACCELERATION: float = 8.0

## Below this the coast-down is over and the character rests. Small enough to be
## invisible, large enough that `move_toward` cannot leave a millimetre-per-second
## residue that keeps him in WALKING forever.
const DRIVE_STOP_SPEED: float = 0.02

## How far off the navigation mesh a driven step may stray before it is clamped.
## Tap-to-walk cannot leave the mesh -- it follows a path that was built on it --
## but direct drive points wherever a thumb points, so this is the only thing
## standing between a four-year-old and the outside of the room. A child stranded
## off the navmesh is a dead end, and this game does not have those.
##
## SMALLER THAN ONE FRAME OF TRAVEL, deliberately. At `WALK_SPEED` and 60 Hz a
## frame covers 17.5 mm (27 mm at `RUN_SPEED`), so a tolerance of 20 mm let every other frame slip past
## the mesh edge unclamped and get pulled back on the next one: rendered against
## a wall, the character sat in a 2 cm buzz with the walk velocity never settling.
## At 5 mm the edge holds still.
const DRIVE_NAV_TOLERANCE: float = 0.005

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

## The thumbstick's direction, magnitude 0..1. Zero while nobody is driving.
var _drive_input: Vector3 = Vector3.ZERO
## True while a thumb is actually on the stick. Stays false through the coast to
## a stop after release, which is why both are needed.
var _drive_active: bool = false
## The smoothed velocity direct drive is currently applying, m/s.
var _drive_velocity: Vector3 = Vector3.ZERO

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
##   `nearest`       bool -- a FLOOR tap: when the point is off the mesh by more
##                   than `SNAP_RADIUS`, walk to the nearest standable point in
##                   that direction anyway (SNAPPED) instead of refusing. A child
##                   who taps the apron in front of the room, or a wall, has
##                   said "over there", and a character who does nothing at all
##                   reads as frozen (owner feedback, 2026-09-20). A TARGET move
##                   never sets it: a sink in another room must still fail.
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
		elif bool(options.get("nearest", false)) \
				and NavMath.flat_distance(endpoint, destination) <= NEAREST_RADIUS \
				and NavMath.flat_distance(endpoint, from) >= MIN_NEAREST_TRAVEL:
			result = MoveResult.SNAPPED
			effective = endpoint
		else:
			return MoveResult.UNREACHABLE

	# Anti-jitter: a second tap essentially on top of the current destination is
	# honoured by doing nothing at all, rather than by rebuilding the path and
	# restarting the walk animation. Ten taps in the same spot = one smooth walk.
	if not _drive_active and _state == State.WALKING \
			and NavMath.is_within(effective, _destination, ARRIVAL_RADIUS):
		return result

	# A destination replaces a direction, exactly as a second tap replaces the
	# first. The stick re-asserts itself on the next frame if a thumb is still on
	# it, so whichever the child touched last is what steers -- and the two are
	# never both steering, which is the thing that would make the destination
	# fight the thumb.
	_drive_active = false
	_drive_input = Vector3.ZERO
	# The coast-down is dropped as well, or `advance()` would keep taking the
	# driven branch and quietly ignore the path it had just been handed.
	_drive_velocity = Vector3.ZERO
	_adopt_path(path, effective, options)
	return result


## -- Direct drive --------------------------------------------------------------

## Steers by DIRECTION rather than by destination: `(x, z)` is a horizontal
## vector with magnitude 0..1. The magnitude picks the pace through
## `drive_speed_for()`: a walk up to `RUN_MAGNITUDE`, a run beyond it.
##
## Re-asserted every frame while a thumb is on the stick, so it is deliberately
## cheap and idempotent: only the FIRST call of a gesture tears down whatever the
## character was doing. That teardown is the "grabbing the stick cancels any
## in-progress tap-to-walk path cleanly" guarantee -- the path is dropped, no
## arrival is emitted (a cancelled walk did not arrive), the arrival latches are
## closed so a stale one can never fire later, and a held posture is released
## because you cannot walk while asleep.
##
## Refused while DISABLED, like every other request. Returns true when the
## character is now under direct drive.
func set_drive(x: float, z: float) -> bool:
	if _disabled:
		return false
	var input: Vector3 = Vector3(x, 0.0, z)
	var magnitude: float = input.length()
	if magnitude <= 0.0:
		clear_drive()
		return false
	if magnitude > 1.0:
		# A ceiling, not a suggestion: full deflection is `RUN_SPEED` and an
		# over-length input from a caller that forgot to normalise must not become
		# a sprint past what the run clip can cover.
		input /= magnitude

	if not _drive_active:
		_clear_path()
		_action_name = ""
		_action_remaining = 0.0
		_action_holds = false
		_held_action = ""
		_arrived_emitted = true
		_interaction_ready_emitted = true

	_drive_active = true
	_drive_input = input
	_state = State.WALKING
	return true


## The thumb left. The character keeps its momentum for a fraction of a second
## and then rests -- see `DRIVE_ACCELERATION`.
func clear_drive() -> void:
	_drive_active = false
	_drive_input = Vector3.ZERO


## True while a thumb is on the stick. False during the coast to a stop, which is
## why `is_moving()` is the question to ask about motion and this is the question
## to ask about input.
func is_driving() -> bool:
	return _drive_active


## The velocity direct drive is applying right now, m/s. Never longer than
## `RUN_SPEED`.
func get_drive_velocity() -> Vector3:
	return _drive_velocity


## The ground speed a stick magnitude asks for. Static and pure, so the walk/run
## mapping is assertable without a controller.
static func drive_speed_for(magnitude: float) -> float:
	var m: float = clampf(magnitude, 0.0, 1.0)
	if m <= RUN_MAGNITUDE:
		return WALK_SPEED * m / RUN_MAGNITUDE
	return lerpf(WALK_SPEED, RUN_SPEED, (m - RUN_MAGNITUDE) / (1.0 - RUN_MAGNITUDE))


## True while the character is travelling faster than a walk. Only the stick
## can make that true; a pathed walk never runs.
func is_running() -> bool:
	return _drive_velocity.length() > RUN_REPORT_SPEED


## The ground speed being applied this frame, m/s -- the driven velocity while
## the stick (or its coast-down) is steering, else the last pathed step.
func get_speed() -> float:
	if _drive_active or not _drive_velocity.is_zero_approx():
		return _drive_velocity.length()
	return _last_speed


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
	clear_drive()
	_drive_velocity = Vector3.ZERO
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
	clear_drive()
	_drive_velocity = Vector3.ZERO
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
		# The stick, too. A thumb still resting on a live joystick behind a summary
		# screen must not keep walking Little Buddy into a wall nobody can see.
		clear_drive()
		_drive_velocity = Vector3.ZERO
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

	if _drive_active or not _drive_velocity.is_zero_approx():
		# Direct drive takes precedence over the match below rather than living
		# inside it, because the coast-down after the thumb leaves still has to be
		# integrated on frames when `_state` has already fallen back to resting.
		_advance_driven(position, yaw, delta, step)
	else:
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

	_last_speed = 0.0
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


## One frame of thumbstick control.
##
## Three things happen here and all three are load-bearing:
##
##   1. the wanted velocity is approached rather than snapped to, so a grab
##      accelerates and a release decelerates (`DRIVE_ACCELERATION`);
##   2. the result is hard-clamped to `RUN_SPEED`, because the stick may never
##      make the character faster than the run cycle she is animated with;
##   3. the resulting STEP is clamped to the navigation mesh, so a thumb pointed
##      at a wall slides along it and a thumb pointed out of the room does
##      nothing at all.
func _advance_driven(position: Vector3, yaw: float, delta: float, step: Dictionary) -> void:
	var wanted: Vector3 = Vector3.ZERO
	if _drive_active and _drive_input.length_squared() > 0.0:
		wanted = _drive_input.normalized() * drive_speed_for(_drive_input.length())
	_drive_velocity = _drive_velocity.move_toward(wanted, DRIVE_ACCELERATION * maxf(delta, 0.0))
	if _drive_velocity.length() > RUN_SPEED:
		_drive_velocity = _drive_velocity.normalized() * RUN_SPEED
	if not _drive_active and _drive_velocity.length() <= DRIVE_STOP_SPEED:
		_drive_velocity = Vector3.ZERO

	var velocity: Vector3 = _clamp_to_navigable(position, _drive_velocity, delta)
	step["velocity"] = velocity
	if velocity.length_squared() > 0.0:
		# Turns WHILE moving, exactly as a pathed walk does -- stopping to turn
		# would put latency back into the gesture the stick exists to make
		# immediate.
		var heading: float = NavMath.yaw_towards(position, position + velocity, yaw)
		step["yaw"] = NavMath.step_yaw(yaw, heading, TURN_SPEED * delta)

	_state = State.WALKING if not _drive_velocity.is_zero_approx() else _resting_state()


## Keeps a driven step on the navigation mesh.
##
## `map_get_closest_point()` is the whole trick: propose where this frame would
## land, ask the mesh for the nearest point that is actually standable, and if
## the two differ meaningfully, go THERE instead. Pushed straight at a wall the
## nearest point is directly behind the wall face and the character stops; pushed
## diagonally it is further along the wall and the character slides. Both fall
## out of the same two lines, and neither can put him outside the room.
##
## A provider with no live map (the straight-line fallback, and every headless
## test that does not ask for one) returns the point unchanged, so this is a
## no-op there rather than a refusal to move.
func _clamp_to_navigable(position: Vector3, velocity: Vector3, delta: float) -> Vector3:
	if velocity.length_squared() <= 0.0 or delta <= 0.0:
		return velocity
	if _provider == null or not _provider.has_method("snap_to_navigable"):
		return velocity

	var proposed: Vector3 = position + velocity * delta
	var snapped: Vector3 = _provider.call("snap_to_navigable", proposed)
	snapped.y = proposed.y
	if NavMath.flat_distance(snapped, proposed) <= DRIVE_NAV_TOLERANCE:
		return velocity

	var corrected: Vector3 = (snapped - position) / delta
	corrected.y = 0.0
	if corrected.length() > RUN_SPEED:
		corrected = corrected.normalized() * RUN_SPEED
	return corrected


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
	_last_speed = 0.0
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
## The pathed step's ground speed, for `get_speed()`.
var _last_speed: float = 0.0


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
