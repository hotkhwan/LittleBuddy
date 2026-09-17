extends RefCounted

## The movement state machine, driven frame by frame.
##
## `CharacterMovementController` is pure by design -- it holds no node and runs
## no physics -- precisely so this file can exist. The headless `--script` runner
## has no physics frames, so a state machine living inside `_physics_process`
## would be untestable; this one is advanced by hand and its position integrated
## here, which makes tap-to-walk, path replacement, arrival debounce, unreachable
## handling and cancel all assertable properties rather than hopes.
##
## Covers required behaviours 1, 2, 4, 5, 6, 7 and 8.

const MovementController := preload("res://scripts/character/character_movement_controller.gd")
const NavigationProvider := preload("res://scripts/navigation/navigation_provider.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")

const DT: float = 1.0 / 60.0
## 20 s at 60 fps. Far longer than any walk in a 6 x 5 m room, so a run that hits
## this limit has genuinely failed to arrive rather than merely being slow.
const MAX_FRAMES: int = 1200


## Emulates `NavigationServer3D.map_get_path()` over a rectangular room: a target
## inside the room produces a path that ends exactly there, and a target outside
## it produces a path that silently stops at the boundary. That silent
## stop-short, not an error or an empty path, is precisely what the real server
## does, and it is what the reachability rule has to cope with.
class RectProvider extends NavigationProvider:
	var bounds: Rect2 = Rect2(-3.0, -3.0, 6.0, 6.0)
	var calls: int = 0

	func is_navigation_ready() -> bool:
		return true

	func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		calls += 1
		return PackedVector3Array([from, _clamp_to_bounds(to)])

	func snap_to_navigable(point: Vector3) -> Vector3:
		return _clamp_to_bounds(point)

	func _clamp_to_bounds(point: Vector3) -> Vector3:
		return Vector3(
			clampf(point.x, bounds.position.x, bounds.end.x),
			point.y,
			clampf(point.z, bounds.position.y, bounds.end.y)
		)


func test_name() -> String:
	return "movement_controller"


func run():
	var failures: Array = []
	failures.append_array(_test_tap_to_walk())
	failures.append_array(_test_calm_speed())
	failures.append_array(_test_path_replacement())
	failures.append_array(_test_impatient_tapping_does_not_queue())
	failures.append_array(_test_repeat_tap_on_same_spot_is_ignored())
	failures.append_array(_test_unreachable())
	failures.append_array(_test_near_miss_is_forgiven())
	failures.append_array(_test_activity_target_arrival())
	failures.append_array(_test_no_duplicate_arrival())
	failures.append_array(_test_interaction_during_movement())
	failures.append_array(_test_unauthored_action_never_sticks())
	failures.append_array(_test_cancel())
	failures.append_array(_test_carrying_and_disabled())
	failures.append_array(_test_state_names())
	return failures


## -- 1. Tap floor -> walk there -> stop cleanly -> Idle ------------------------

func _test_tap_to_walk() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()
	var destination := Vector3(2.0, 0.0, 1.0)

	if int(controller.call("request_move", destination)) != MovementController.MoveResult.ACCEPTED:
		failures.append("a tap inside the room should be ACCEPTED")
	if String(controller.call("get_state_name")) != "walking":
		failures.append("the character should be walking straight after a tap")

	var run: Dictionary = _run_to_rest(controller, Vector3.ZERO, 0.0)

	if int(run["arrived"]) != 1:
		failures.append("expected exactly one arrival, got %d" % int(run["arrived"]))
	if String(controller.call("get_state_name")) != "idle":
		failures.append("the character should return to idle, got '%s'"
				% String(controller.call("get_state_name")))
	if not NavMath.is_within(run["position"], destination, MovementController.ARRIVAL_RADIUS):
		failures.append("expected to stop at the destination, stopped at %s" % str(run["position"]))
	if int(controller.call("get_path_size")) != 0:
		failures.append("the path should be cleared once the walk is over")
	if not (run["finalVelocity"] as Vector3).is_equal_approx(Vector3.ZERO):
		failures.append("the character should stop dead, not drift")
	return failures


## Child-friendly pacing: calm, never an action game. A 4 m walk must take at
## least a few seconds, and the character must never exceed its walk speed.
func _test_calm_speed() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()
	controller.call("set_position", Vector3(-2.0, 0.0, 0.0))
	controller.call("request_move", Vector3(2.0, 0.0, 0.0))
	var run: Dictionary = _run_to_rest(controller, Vector3(-2.0, 0.0, 0.0), 0.0)

	if float(run["maxSpeed"]) > MovementController.WALK_SPEED + 0.001:
		failures.append("the character exceeded its walk speed (%f)" % float(run["maxSpeed"]))
	var seconds: float = float(int(run["frames"])) * DT
	if seconds < 3.5:
		failures.append("a 4 m walk took only %.2f s -- too fast for a small child" % seconds)
	if MovementController.WALK_SPEED > 1.2:
		failures.append("WALK_SPEED %f is action-game fast for a toddler"
				% MovementController.WALK_SPEED)
	return failures


## -- 5. Repeated taps while walking: path REPLACED, never queued --------------

func _test_path_replacement() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()
	controller.call("request_move", Vector3(2.0, 0.0, 0.0))
	var first_serial: int = int(controller.call("get_move_serial"))

	# Walk part of the way, then change your mind.
	var position := Vector3.ZERO
	for _frame: int in range(20):
		var step: Dictionary = controller.call("advance", position, 0.0, DT)
		position += (step["velocity"] as Vector3) * DT

	controller.call("set_position", position)
	var second := Vector3(-2.0, 0.0, 1.5)
	controller.call("request_move", second)

	if int(controller.call("get_move_serial")) != first_serial + 1:
		failures.append("a new destination should replace the path exactly once")
	if not (controller.call("get_destination") as Vector3).is_equal_approx(second):
		failures.append("the destination should be the new tap, got %s"
				% str(controller.call("get_destination")))
	if String(controller.call("get_state_name")) != "walking":
		failures.append("replacing a path must not drop out of the walking state (no animation flicker)")

	var run: Dictionary = _run_to_rest(controller, position, 0.0)
	if int(run["arrived"]) != 1:
		failures.append("expected exactly one arrival after a replacement, got %d" % int(run["arrived"]))
	if not NavMath.is_within(run["position"], second, MovementController.ARRIVAL_RADIUS):
		failures.append("expected to arrive at the SECOND destination, got %s" % str(run["position"]))
	return failures


## An impatient four-year-old taps ten times. There must be exactly one
## destination and one path at the end of it, not a queue of ten.
func _test_impatient_tapping_does_not_queue() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()

	var taps: Array = [
		Vector3(2.0, 0.0, 0.0), Vector3(-2.0, 0.0, 0.0), Vector3(0.0, 0.0, 2.0),
		Vector3(1.0, 0.0, -2.0), Vector3(-1.5, 0.0, 1.5), Vector3(2.5, 0.0, 2.5),
		Vector3(-2.5, 0.0, -2.5), Vector3(0.5, 0.0, 0.5), Vector3(2.0, 0.0, -1.0),
		Vector3(-1.0, 0.0, 2.0),
	]
	var position := Vector3.ZERO
	for tap: Vector3 in taps:
		controller.call("set_position", position)
		controller.call("request_move", tap)
		# Two frames between taps: fast, but not so fast that nothing moves.
		for _frame: int in range(2):
			var step: Dictionary = controller.call("advance", position, 0.0, DT)
			position += (step["velocity"] as Vector3) * DT

	# Two points -- start and end. A queue would show up as a growing path.
	if int(controller.call("get_path_size")) > 2:
		failures.append("ten taps left a path of %d points; destinations are queueing"
				% int(controller.call("get_path_size")))
	if not (controller.call("get_destination") as Vector3).is_equal_approx(taps[taps.size() - 1]):
		failures.append("only the LAST tap should survive, got %s"
				% str(controller.call("get_destination")))

	var run: Dictionary = _run_to_rest(controller, position, 0.0)
	if int(run["arrived"]) != 1:
		failures.append("ten taps must still produce exactly one arrival, got %d" % int(run["arrived"]))
	if not NavMath.is_within(run["position"], taps[taps.size() - 1], MovementController.ARRIVAL_RADIUS):
		failures.append("expected to end at the last tap, ended at %s" % str(run["position"]))
	return failures


## Anti-jitter: tapping essentially the same spot again must not rebuild the path
## and restart the walk animation.
func _test_repeat_tap_on_same_spot_is_ignored() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()
	controller.call("request_move", Vector3(2.0, 0.0, 0.0))
	var serial: int = int(controller.call("get_move_serial"))

	controller.call("request_move", Vector3(2.02, 0.0, 0.01))
	if int(controller.call("get_move_serial")) != serial:
		failures.append("a tap on top of the current destination should not rebuild the path")

	controller.call("request_move", Vector3(2.6, 0.0, 0.0))
	if int(controller.call("get_move_serial")) != serial + 1:
		failures.append("a genuinely different tap SHOULD rebuild the path")
	return failures


## -- 4. Tap unreachable space: no crash, no stuck walk, nothing disturbed ------

func _test_unreachable() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()

	# From rest.
	var result: int = int(controller.call("request_move", Vector3(20.0, 0.0, 20.0)))
	if result != MovementController.MoveResult.UNREACHABLE:
		failures.append("a tap far outside the room should be UNREACHABLE, got %d" % result)
	if String(controller.call("get_state_name")) != "idle":
		failures.append("an unreachable tap must leave the character idle, not walking")
	if int(controller.call("get_path_size")) != 0:
		failures.append("an unreachable tap must not leave a path behind")

	# THE IMPORTANT ONE: mid-walk. A stray tap on a wall must not cancel a
	# perfectly good walk, and must not leave a walk animation with no destination.
	var good := Vector3(2.0, 0.0, 0.0)
	controller.call("request_move", good)
	var serial: int = int(controller.call("get_move_serial"))
	var position := Vector3.ZERO
	for _frame: int in range(20):
		var step: Dictionary = controller.call("advance", position, 0.0, DT)
		position += (step["velocity"] as Vector3) * DT

	controller.call("set_position", position)
	if int(controller.call("request_move", Vector3(-40.0, 0.0, 12.0))) != MovementController.MoveResult.UNREACHABLE:
		failures.append("a mid-walk unreachable tap should still report UNREACHABLE")
	if int(controller.call("get_move_serial")) != serial:
		failures.append("an unreachable tap must not disturb the path in flight")
	if not (controller.call("get_destination") as Vector3).is_equal_approx(good):
		failures.append("an unreachable tap must not change the destination")
	if String(controller.call("get_state_name")) != "walking":
		failures.append("an unreachable tap must not interrupt a walk already under way")

	var run: Dictionary = _run_to_rest(controller, position, 0.0)
	if int(run["arrived"]) != 1:
		failures.append("the original walk should still complete exactly once")
	if String(controller.call("get_state_name")) != "idle":
		failures.append("the character must end idle, never stuck in a walk animation")
	return failures


## A child's thumb lands on the skirting board. Walk to the nearest standable
## point rather than refusing -- forgiving beats correct here.
func _test_near_miss_is_forgiven() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()

	# 0.4 m outside the room: inside SNAP_RADIUS.
	var result: int = int(controller.call("request_move", Vector3(3.4, 0.0, 0.0)))
	if result != MovementController.MoveResult.SNAPPED:
		failures.append("a near-miss tap should be SNAPPED, got %d" % result)
	if not (controller.call("get_destination") as Vector3).is_equal_approx(Vector3(3.0, 0.0, 0.0)):
		failures.append("a snapped tap should walk to the nearest standable point, got %s"
				% str(controller.call("get_destination")))

	# 1.5 m outside: beyond SNAP_RADIUS, so we assume the child meant something
	# else entirely and do nothing.
	var far: RefCounted = _make()
	if int(far.call("request_move", Vector3(4.5, 0.0, 0.0))) != MovementController.MoveResult.UNREACHABLE:
		failures.append("a tap well beyond the snap radius should be UNREACHABLE")

	# Boundary sanity: the snap radius must be generous but not absurd.
	if MovementController.SNAP_RADIUS < 0.3 or MovementController.SNAP_RADIUS > 1.5:
		failures.append("SNAP_RADIUS %f is outside the useful range"
				% MovementController.SNAP_RADIUS)
	return failures


## -- 2. Tap an object: walk to its interaction point, TURN TO FACE IT, then
##       report interaction-ready.

func _test_activity_target_arrival() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()

	var object_at := Vector3(2.0, 0.0, -2.0)
	var stand_at := Vector3(2.0, 0.0, -1.2)
	controller.call("request_move", stand_at, {
		"targetId": "toyBox",
		"facePoint": object_at,
		"arrivalRadius": 0.22,
	})

	var position := Vector3.ZERO
	# Start facing the wrong way on purpose, so the turn is real and observable.
	var yaw: float = PI
	var arrived_frame: int = -1
	var ready_frame: int = -1
	var arrived_count: int = 0
	var ready_count: int = 0

	for frame: int in range(MAX_FRAMES):
		var step: Dictionary = controller.call("advance", position, yaw, DT)
		position += (step["velocity"] as Vector3) * DT
		yaw = float(step["yaw"])
		if bool(step["arrived"]):
			arrived_count += 1
			if arrived_frame < 0:
				arrived_frame = frame
			if String(step["targetId"]) != "toyBox":
				failures.append("arrival should report the semantic target id, got '%s'"
						% String(step["targetId"]))
		if bool(step["interactionReady"]):
			ready_count += 1
			if ready_frame < 0:
				ready_frame = frame
		if String(step["stateName"]) == "idle" and ready_frame >= 0:
			break

	if arrived_count != 1:
		failures.append("expected exactly one arrival at an activity target, got %d" % arrived_count)
	if ready_count != 1:
		failures.append("expected exactly one interaction-ready, got %d" % ready_count)
	if arrived_frame < 0 or ready_frame < 0:
		failures.append("expected both arrival and interaction-ready to fire")
	elif ready_frame < arrived_frame:
		failures.append("interaction-ready must never precede arrival")
	elif ready_frame == arrived_frame:
		# Starting at PI facing an object to the north-west, the turn cannot be
		# instant; if it were, turning to face is not really happening.
		failures.append("the turn to face should take at least one frame from this heading")

	if not NavMath.is_within(position, stand_at, 0.22):
		failures.append("expected to stand at the interaction point, stopped at %s" % str(position))
	var wanted_yaw: float = NavMath.yaw_towards(position, object_at, yaw)
	if not NavMath.yaw_reached(yaw, wanted_yaw, MovementController.FACING_TOLERANCE):
		failures.append("the character should end up facing the object")
	return failures


## -- 6. No duplicate arrival signals ------------------------------------------

func _test_no_duplicate_arrival() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()

	# With a facing point, the controller stays in WALKING for several frames
	# AFTER position arrival while it turns. That window is exactly where a
	## missing debounce latch would fire `arrived` on every single frame, so this
	# is the shape of the test that can actually catch it.
	controller.call("request_move", Vector3(1.0, 0.0, 0.0), {
		"targetId": "ball",
		"facePoint": Vector3(1.0, 0.0, -5.0),
	})

	var position := Vector3.ZERO
	var yaw: float = PI * 0.95
	var arrived_count: int = 0
	var ready_count: int = 0
	# Keep going long after the walk is over -- a debounce that only works
	# because the state machine happens to stop is not a debounce.
	for _frame: int in range(MAX_FRAMES):
		var step: Dictionary = controller.call("advance", position, yaw, DT)
		position += (step["velocity"] as Vector3) * DT
		yaw = float(step["yaw"])
		arrived_count += 1 if bool(step["arrived"]) else 0
		ready_count += 1 if bool(step["interactionReady"]) else 0

	if arrived_count != 1:
		failures.append("arrival fired %d times; it must fire exactly once per request" % arrived_count)
	if ready_count != 1:
		failures.append("interaction-ready fired %d times; it must fire exactly once" % ready_count)

	# And a brand new request re-arms both.
	controller.call("set_position", position)
	controller.call("request_move", Vector3(-1.0, 0.0, 0.0), {"targetId": "pad"})
	var second_arrivals: int = int(_run_to_rest(controller, position, yaw)["arrived"])
	if second_arrivals != 1:
		failures.append("a new request should re-arm arrival, got %d" % second_arrivals)
	return failures


## -- 7. Interaction during movement -------------------------------------------

func _test_interaction_during_movement() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()
	controller.call("request_move", Vector3(2.5, 0.0, 0.0), {"targetId": "toyBox"})

	var position := Vector3.ZERO
	for _frame: int in range(20):
		var step: Dictionary = controller.call("advance", position, 0.0, DT)
		position += (step["velocity"] as Vector3) * DT

	if not bool(controller.call("request_action", "drink", 0.4)):
		failures.append("an action requested mid-walk should be accepted")
	if String(controller.call("get_state_name")) != "interacting":
		failures.append("requesting an action should move to the interacting state")
	if int(controller.call("get_path_size")) != 0:
		failures.append("an action must abandon the path, not leave it half-walked")

	var finished: int = 0
	var arrived: int = 0
	for _frame: int in range(MAX_FRAMES):
		var step: Dictionary = controller.call("advance", position, 0.0, DT)
		position += (step["velocity"] as Vector3) * DT
		finished += 1 if bool(step["actionFinished"]) else 0
		arrived += 1 if bool(step["arrived"]) else 0
		if String(step["stateName"]) == "idle":
			break

	if arrived != 0:
		failures.append("an interrupted walk must never report an arrival")
	if finished != 1:
		failures.append("expected exactly one action-finished, got %d" % finished)
	if String(controller.call("get_state_name")) != "idle":
		failures.append("the character must return to idle after an action")
	if not controller.call("get_action_name").is_empty():
		failures.append("the action name should be cleared once it finishes")
	return failures


## The graceful-degradation guarantee: an action with no animation yet must still
## start, still end, and still leave the character idle. Never a stuck state.
func _test_unauthored_action_never_sticks() -> Array:
	var failures: Array = []
	for action: String in ["eat", "drink", "sit", "sleep", "brushTeeth", "hug", "pickUp", "give", "celebrate"]:
		var controller: RefCounted = _make()
		if not bool(controller.call("request_action", action)):
			failures.append("'%s' should be accepted even with no animation authored" % action)
			continue
		var position := Vector3.ZERO
		var finished: int = 0
		for _frame: int in range(MAX_FRAMES):
			var step: Dictionary = controller.call("advance", position, 0.0, DT)
			finished += 1 if bool(step["actionFinished"]) else 0
			if String(step["stateName"]) == "idle":
				break
		if finished != 1:
			failures.append("'%s' finished %d times; expected exactly once" % [action, finished])
		if String(controller.call("get_state_name")) != "idle":
			failures.append("'%s' left the character stuck in '%s'"
					% [action, String(controller.call("get_state_name"))])

	# An empty action name is refused rather than starting a nameless action.
	var blank: RefCounted = _make()
	if bool(blank.call("request_action", "   ")):
		failures.append("a blank action name should be refused")
	if String(blank.call("get_state_name")) != "idle":
		failures.append("a refused action must not change the state")
	return failures


## -- 8. Movement cancel --------------------------------------------------------

func _test_cancel() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()
	controller.call("request_move", Vector3(2.5, 0.0, 0.0), {"targetId": "toyBox"})

	var position := Vector3.ZERO
	for _frame: int in range(20):
		var step: Dictionary = controller.call("advance", position, 0.0, DT)
		position += (step["velocity"] as Vector3) * DT

	controller.call("cancel")
	if String(controller.call("get_state_name")) != "idle":
		failures.append("cancel() should return the character to idle")
	if int(controller.call("get_path_size")) != 0:
		failures.append("cancel() should clear the path")
	if not String(controller.call("get_target_id")).is_empty():
		failures.append("cancel() should clear the target id")

	var stopped := position
	var arrived: int = 0
	for _frame: int in range(300):
		var step: Dictionary = controller.call("advance", position, 0.0, DT)
		position += (step["velocity"] as Vector3) * DT
		arrived += 1 if bool(step["arrived"]) else 0

	if arrived != 0:
		failures.append("a cancelled walk must NEVER report an arrival")
	if not position.is_equal_approx(stopped):
		failures.append("a cancelled character must not keep drifting")
	return failures


## -- Carrying and Disabled -----------------------------------------------------

func _test_carrying_and_disabled() -> Array:
	var failures: Array = []
	var controller: RefCounted = _make()

	controller.call("set_carrying", true)
	if String(controller.call("get_state_name")) != "carrying":
		failures.append("the resting state while holding something should be 'carrying'")

	controller.call("request_move", Vector3(1.0, 0.0, 0.0))
	if String(controller.call("get_state_name")) != "walking":
		failures.append("walking while carrying is still 'walking'")
	if not bool(controller.call("is_carrying")):
		failures.append("is_carrying() should survive a walk, so a carry-walk clip can be chosen")

	var run: Dictionary = _run_to_rest(controller, Vector3.ZERO, 0.0)
	if String(controller.call("get_state_name")) != "carrying":
		failures.append("after arriving while carrying, the resting state should be 'carrying'")
	if int(run["arrived"]) != 1:
		failures.append("carrying must not affect arrival reporting")

	controller.call("set_carrying", false)
	if String(controller.call("get_state_name")) != "idle":
		failures.append("putting something down should return to 'idle'")

	# Disabled: everything is refused, nothing moves.
	controller.call("request_move", Vector3(2.0, 0.0, 0.0))
	controller.call("set_disabled", true)
	if String(controller.call("get_state_name")) != "disabled":
		failures.append("set_disabled(true) should enter the disabled state")
	if int(controller.call("request_move", Vector3(1.0, 0.0, 0.0))) != MovementController.MoveResult.REFUSED:
		failures.append("a disabled character must refuse move requests")
	if bool(controller.call("request_action", "drink")):
		failures.append("a disabled character must refuse actions")

	var position := Vector3.ZERO
	var arrived: int = 0
	for _frame: int in range(200):
		var step: Dictionary = controller.call("advance", position, 0.0, DT)
		if not (step["velocity"] as Vector3).is_equal_approx(Vector3.ZERO):
			failures.append("a disabled character must not move")
			break
		arrived += 1 if bool(step["arrived"]) else 0
	if arrived != 0:
		failures.append("a disabled character must not report arrivals")

	controller.call("set_disabled", false)
	if String(controller.call("get_state_name")) != "idle":
		failures.append("re-enabling should return to rest, not to the interrupted walk")
	return failures


## Exactly five states, no more, and every one of them has a name.
func _test_state_names() -> Array:
	var failures: Array = []
	var expected: Array = ["idle", "walking", "interacting", "carrying", "disabled"]
	var seen: Array = []
	for state: Variant in MovementController.State.values():
		seen.append(MovementController.state_name(int(state)))
	seen.sort()
	var wanted: Array = expected.duplicate()
	wanted.sort()
	if seen != wanted:
		failures.append("expected exactly the states %s, got %s" % [str(wanted), str(seen)])
	return failures


## -- Helpers -------------------------------------------------------------------

func _make() -> RefCounted:
	return MovementController.create(RectProvider.new())


## Advances until the controller comes to rest, integrating the position exactly
## as `LittleBuddyCharacter` does with `move_and_slide()`.
func _run_to_rest(controller: RefCounted, start: Vector3, start_yaw: float) -> Dictionary:
	var position := start
	var yaw := start_yaw
	var arrived: int = 0
	var ready: int = 0
	var max_speed: float = 0.0
	var frames: int = 0
	var final_velocity := Vector3.ZERO

	for frame: int in range(MAX_FRAMES):
		frames = frame + 1
		var step: Dictionary = controller.call("advance", position, yaw, DT)
		var velocity: Vector3 = step["velocity"]
		final_velocity = velocity
		max_speed = maxf(max_speed, velocity.length())
		position += velocity * DT
		yaw = float(step["yaw"])
		arrived += 1 if bool(step["arrived"]) else 0
		ready += 1 if bool(step["interactionReady"]) else 0
		var state_name: String = String(step["stateName"])
		if state_name == "idle" or state_name == "carrying":
			break

	return {
		"position": position,
		"yaw": yaw,
		"arrived": arrived,
		"interactionReady": ready,
		"maxSpeed": max_speed,
		"frames": frames,
		"finalVelocity": final_velocity,
	}
