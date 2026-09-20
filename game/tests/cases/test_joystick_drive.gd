extends RefCounted

## What the thumbstick does to the character -- and what it must never do to
## tap-to-walk.
##
## The stick is direct analog input added on a physical-device request for
## RoV-style control. The risk it carries is not that it fails to move anybody;
## it is that it quietly damages the three things the movement layer already
## guarantees:
##
##   * **the state machine stays true.** Direct drive enters through
##     `CharacterMovementController.set_drive()`, not by writing a velocity to
##     the body behind the controller's back. If it did the latter, the
##     controller would no longer know what the character was doing and
##     `Idle/Walking/Interacting/Carrying/Disabled` would stop meaning anything.
##   * **the arrival latch, destination replacement, the unreachable refusal and
##     `set_disabled(true)`** all still behave exactly as they did.
##   * **tap-to-walk still works, in the same session, on the same finger-by-
##     finger basis.** Grabbing the stick cancels a walk in progress cleanly; the
##     two never both steer.
##
## And two rules the stick brings with it:
##
##   * it may never exceed `RUN_SPEED` at full deflection, nor `WALK_SPEED` inside
##     the walk band (1.05 m/s, the top of the walk range for
##     a 0.22 m leg at Froude ~ 0.51 -- past it no walk cycle reads as walking);
##   * it may never put the child somewhere the level cannot recover from. Direct
##     drive points wherever a thumb points, so it is clamped to the navigation
##     mesh. Being stranded outside the walkable area is a dead end, and this
##     game does not have those.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const MovementController := preload("res://scripts/character/character_movement_controller.gd")
const CharacterScript := preload("res://scripts/character/little_buddy_character.gd")
const NavigationController := preload("res://scripts/navigation/navigation_controller.gd")
const Joystick := preload("res://scripts/input/virtual_joystick.gd")
const HouseWorldScript := preload("res://scripts/house/house_world.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")

const DT: float = 1.0 / 60.0
const SPEED_EPSILON: float = 0.0005


## A 4 x 4 m room with walls, as the navigation layer sees it. `snap_to_navigable`
## is the only part the drive clamp uses, and clamping to the rectangle is exactly
## what a real navigation mesh does at a wall.
class RoomProvider extends RefCounted:
	var bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)
	var snaps: int = 0

	func is_navigation_ready() -> bool:
		return true

	func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		return PackedVector3Array([from, snap_to_navigable(to)])

	func snap_to_navigable(point: Vector3) -> Vector3:
		snaps += 1
		return Vector3(
			clampf(point.x, bounds.position.x, bounds.end.x),
			point.y,
			clampf(point.z, bounds.position.y, bounds.end.y)
		)


func test_name() -> String:
	return "joystick_drive"


func run():
	var failures: Array = []
	failures.append_array(_test_drive_is_walking_not_a_side_channel())
	failures.append_array(_test_drive_never_exceeds_walk_speed())
	failures.append_array(_test_release_stops_and_returns_to_idle())
	failures.append_array(_test_grabbing_the_stick_cancels_a_tap_walk())
	failures.append_array(_test_they_never_both_steer())
	failures.append_array(_test_a_drive_never_fires_an_arrival())
	failures.append_array(_test_tap_to_walk_still_works_afterwards())
	failures.append_array(_test_disabled_refuses_the_stick())
	failures.append_array(_test_the_room_is_a_room())
	failures.append_array(_test_a_wall_is_slid_along_not_through())
	failures.append_array(_test_the_body_really_moves())
	failures.append_array(_test_screen_direction_becomes_world_direction())
	failures.append_array(_test_the_tap_router_yields_inside_the_zone())
	failures.append_array(_test_the_walk_clip_follows_the_real_speed())
	return failures


## -- The seam ------------------------------------------------------------------

## The stick drives the state machine, and the state machine still tells the
## truth about what the character is doing.
func _test_drive_is_walking_not_a_side_channel():
	var failures: Array = []
	var controller: RefCounted = MovementController.create(null)

	if controller.call("get_state_name") != "idle":
		failures.append("a fresh controller should be idle")
	if bool(controller.call("is_driving")):
		failures.append("nobody is touching the stick yet")

	controller.call("set_drive", 0.0, -1.0)
	if controller.call("get_state_name") != "walking":
		failures.append("driving IS walking; the state machine said '%s'"
				% controller.call("get_state_name"))
	if not bool(controller.call("is_driving")):
		failures.append("is_driving() should be true while a thumb is down")
	if not bool(controller.call("is_busy")):
		failures.append("a driven character is busy, like any other walking one")
	if String(controller.call("get_target_id")) != "":
		failures.append("a direction is not a destination; target id should be empty, got '%s'"
				% String(controller.call("get_target_id")))

	# Carrying stays orthogonal, exactly as it does for a pathed walk: no sixth
	# state was invented for "driving while carrying".
	controller.call("set_carrying", true)
	controller.call("advance", Vector3.ZERO, 0.0, DT)
	if controller.call("get_state_name") != "walking":
		failures.append("driving while carrying must still be WALKING, got '%s'"
				% controller.call("get_state_name"))
	if not bool(controller.call("is_carrying")):
		failures.append("the carry flag was lost")
	return failures


## The ceilings, from every angle and from an input that is over-length on
## purpose (a caller that forgot to normalise must not become a sprint).
##
## Two of them since the run landed: a stick held INSIDE the walk band may never
## exceed `WALK_SPEED`, and a stick held anywhere may never exceed `RUN_SPEED`.
## Full deflection must actually reach the run, and the boundary itself must be
## exactly a full walk -- continuous, so there is no step under the thumb.
func _test_drive_never_exceeds_walk_speed():
	var failures: Array = []
	var top: float = MovementController.RUN_SPEED
	var walk: float = MovementController.WALK_SPEED
	var reached: float = 0.0
	var reached_walking: float = 0.0

	for step: int in range(16):
		var angle: float = TAU * float(step) / 16.0
		var controller: RefCounted = MovementController.create(null)
		# Over-length: magnitude 2.0, not 1.0.
		controller.call("set_drive", cos(angle) * 2.0, sin(angle) * 2.0)
		for _frame: int in range(90):
			var result: Dictionary = controller.call("advance", Vector3.ZERO, 0.0, DT)
			var speed: float = (result["velocity"] as Vector3).length()
			reached = maxf(reached, speed)
			if speed > top + SPEED_EPSILON:
				failures.append("the stick reached %.4f m/s at %.0f degrees; RUN_SPEED is %.2f "
						% [speed, rad_to_deg(angle), top]
						+ "and it is a ceiling, not a suggestion")
				break
		# The same angle, held exactly at the walk/run boundary: a full walk and
		# not a metre per second more.
		var walker: RefCounted = MovementController.create(null)
		var band: float = MovementController.RUN_MAGNITUDE
		walker.call("set_drive", cos(angle) * band, sin(angle) * band)
		for _frame: int in range(90):
			var result: Dictionary = walker.call("advance", Vector3.ZERO, 0.0, DT)
			var speed: float = (result["velocity"] as Vector3).length()
			reached_walking = maxf(reached_walking, speed)
			if speed > walk + SPEED_EPSILON:
				failures.append("inside the walk band the stick reached %.4f m/s at %.0f degrees; "
						% [speed, rad_to_deg(angle)]
						+ "WALK_SPEED %.2f is the ceiling there" % walk)
				break
			if bool(walker.call("is_running")):
				failures.append("is_running() answered true at the walk/run boundary (%.3f m/s)"
						% speed)
				break

	if reached < top - 0.01:
		failures.append("full deflection only ever reached %.3f m/s of a possible %.2f; the "
				% [reached, top] + "stick cannot ask for the run it is supposed to ask for")
	if reached_walking < walk - 0.01:
		failures.append("the walk/run boundary only reached %.3f m/s; it must be a full walk (%.2f)"
				% [reached_walking, walk])
	# The mapping is continuous and monotonic across the boundary.
	var previous: float = -1.0
	for i: int in range(101):
		var speed: float = MovementController.drive_speed_for(float(i) / 100.0)
		if speed < previous - 0.0001:
			failures.append("drive_speed_for() went backwards at magnitude %.2f" % (float(i) / 100.0))
			break
		previous = speed
	if not is_equal_approx(MovementController.drive_speed_for(MovementController.RUN_MAGNITUDE), walk):
		failures.append("the walk band does not end at exactly WALK_SPEED")
	if not is_equal_approx(MovementController.drive_speed_for(1.0), top):
		failures.append("full deflection is not exactly RUN_SPEED")

	# ...and a half-push really is slower than a full one, in proportion: the
	# stick is analog, not a run button. Half deflection sits inside the walk
	# band, so it is half of the way to the boundary's full walk -- and the body
	# actually reaches exactly what the mapping promises.
	var half: RefCounted = MovementController.create(null)
	half.call("set_drive", 0.0, -0.5)
	for _frame: int in range(90):
		half.call("advance", Vector3.ZERO, 0.0, DT)
	var half_speed: float = (half.call("get_drive_velocity") as Vector3).length()
	var promised: float = MovementController.drive_speed_for(0.5)
	if absf(half_speed - promised) > 0.01:
		failures.append("half deflection gave %.3f m/s, not the %.3f the mapping promises"
				% [half_speed, promised])
	if not is_equal_approx(promised, walk * 0.5 / MovementController.RUN_MAGNITUDE):
		failures.append("half deflection is not proportional inside the walk band (%.3f)" % promised)
	if half_speed >= walk - 0.01:
		failures.append("half deflection (%.3f m/s) is already a full walk; the stick is binary"
				% half_speed)
	return failures


func _test_release_stops_and_returns_to_idle():
	var failures: Array = []
	var controller: RefCounted = MovementController.create(null)
	controller.call("set_drive", 1.0, 0.0)
	for _frame: int in range(60):
		controller.call("advance", Vector3.ZERO, 0.0, DT)

	controller.call("clear_drive")
	if bool(controller.call("is_driving")):
		failures.append("is_driving() survived the release")

	# Smoothly: still moving on the very next frame, stopped soon after.
	var next: Dictionary = controller.call("advance", Vector3.ZERO, 0.0, DT)
	if (next["velocity"] as Vector3).length() <= 0.0:
		failures.append("the character stopped dead on the frame the thumb left; 'release = stop, "
				+ "SMOOTHLY' is the whole of DRIVE_ACCELERATION")

	var frames_to_stop: int = 0
	for frame: int in range(120):
		var result: Dictionary = controller.call("advance", Vector3.ZERO, 0.0, DT)
		if (result["velocity"] as Vector3).is_zero_approx():
			frames_to_stop = frame + 1
			break
	if frames_to_stop == 0:
		failures.append("the character never stopped after the thumb left. A stick that keeps "
				+ "driving after release is the worst bug this control scheme can have.")
	elif float(frames_to_stop) * DT > 0.35:
		failures.append("it took %.2f s to stop, which reads as the controls sticking"
				% (float(frames_to_stop) * DT))

	if controller.call("get_state_name") != "idle":
		failures.append("after the coast down the character must be idle, not '%s'"
				% controller.call("get_state_name"))
	var after: Dictionary = controller.call("advance", Vector3.ZERO, 0.0, DT)
	if not (after["velocity"] as Vector3).is_zero_approx():
		failures.append("a stopped character started moving again on its own")
	return failures


## Grabbing the stick mid-walk has to take the destination away cleanly, or the
## path and the thumb spend the rest of the gesture pulling in two directions.
func _test_grabbing_the_stick_cancels_a_tap_walk():
	var failures: Array = []
	var controller: RefCounted = MovementController.create(null)
	controller.call("set_position", Vector3.ZERO)
	controller.call("request_move", Vector3(0.0, 0.0, -3.0), {"targetId": "bedroom.bed"})
	for _frame: int in range(10):
		controller.call("advance", Vector3.ZERO, 0.0, DT)
	if int(controller.call("get_path_size")) == 0:
		failures.append("the tap-to-walk path never existed, so this proves nothing")

	controller.call("set_drive", 1.0, 0.0)
	if int(controller.call("get_path_size")) != 0:
		failures.append("the tap-to-walk path survived the stick grab (%d points left); the two "
				% int(controller.call("get_path_size")) + "would now fight over the destination")
	if String(controller.call("get_target_id")) != "":
		failures.append("the old destination's target id is still '%s'"
				% String(controller.call("get_target_id")))
	if not bool(controller.call("is_driving")):
		failures.append("the stick did not take over")

	# And the cancelled walk did NOT arrive -- not now, and not later when the
	# character happens to drive over where it was going.
	for _frame: int in range(240):
		var result: Dictionary = controller.call("advance",
				controller.call("get_destination") as Vector3, 0.0, DT)
		if bool(result["arrived"]):
			failures.append("a walk the child cancelled by grabbing the stick reported an ARRIVAL")
			break
		if bool(result["interactionReady"]):
			failures.append("a cancelled walk reported interaction-ready")
			break
	return failures


## Last input wins, and only one of them is ever steering.
func _test_they_never_both_steer():
	var failures: Array = []
	var controller: RefCounted = MovementController.create(null)
	controller.call("set_position", Vector3.ZERO)

	controller.call("set_drive", 1.0, 0.0)
	var serial: int = int(controller.call("get_move_serial"))

	# A tap while a thumb is down: the destination takes over...
	controller.call("request_move", Vector3(0.0, 0.0, -2.0))
	if bool(controller.call("is_driving")):
		failures.append("a tap was accepted and the stick was still driving too")
	if int(controller.call("get_move_serial")) != serial + 1:
		failures.append("the tap should have replaced the drive exactly once")
	if int(controller.call("get_path_size")) == 0:
		failures.append("the tap produced no path")

	# ...and the thumb, still down, takes it straight back on the next frame.
	controller.call("set_drive", 1.0, 0.0)
	if int(controller.call("get_path_size")) != 0:
		failures.append("the destination outlived the thumb that replaced it")
	if not bool(controller.call("is_driving")):
		failures.append("the stick could not take control back")

	# Ten frames of a held thumb are ONE gesture, not ten cancellations.
	var before: int = int(controller.call("get_move_serial"))
	for _frame: int in range(10):
		controller.call("set_drive", 1.0, 0.0)
		controller.call("advance", Vector3.ZERO, 0.0, DT)
	if int(controller.call("get_move_serial")) != before:
		failures.append("re-asserting the stick each frame churned the move serial")
	return failures


func _test_a_drive_never_fires_an_arrival():
	var failures: Array = []
	var controller: RefCounted = MovementController.create(null)
	controller.call("set_drive", 0.0, -1.0)
	var position: Vector3 = Vector3.ZERO
	for _frame: int in range(300):
		var result: Dictionary = controller.call("advance", position, 0.0, DT)
		position += (result["velocity"] as Vector3) * DT
		if bool(result["arrived"]):
			failures.append("driving with a thumb reported an arrival; there is no destination "
					+ "to arrive at, and a mission awaiting one would fire on nothing")
			break
	return failures


## The other half of "do not remove tap-to-walk": after a stick gesture, a tap
## must behave exactly as it always did -- including arriving exactly once.
func _test_tap_to_walk_still_works_afterwards():
	var failures: Array = []
	var provider: RoomProvider = RoomProvider.new()
	var controller: RefCounted = MovementController.create(provider)
	controller.call("set_position", Vector3.ZERO)

	controller.call("set_drive", 1.0, 0.0)
	for _frame: int in range(30):
		controller.call("advance", Vector3.ZERO, 0.0, DT)
	controller.call("clear_drive")
	for _frame: int in range(30):
		controller.call("advance", Vector3.ZERO, 0.0, DT)

	var result: int = int(controller.call("request_move", Vector3(0.0, 0.0, -1.5)))
	if result != MovementController.MoveResult.ACCEPTED:
		failures.append("a tap after a stick gesture returned %d, not ACCEPTED" % result)

	var arrivals: int = 0
	var position: Vector3 = Vector3.ZERO
	for _frame: int in range(400):
		var step: Dictionary = controller.call("advance", position, 0.0, DT)
		position += (step["velocity"] as Vector3) * DT
		if bool(step["arrived"]):
			arrivals += 1
	if arrivals != 1:
		failures.append("tap-to-walk arrived %d times after a stick gesture; the latch must "
				% arrivals + "still fire exactly once")

	# And the unreachable refusal is untouched.
	controller.call("set_position", Vector3.ZERO)
	if int(controller.call("request_move", Vector3(40.0, 0.0, 40.0))) \
			!= MovementController.MoveResult.UNREACHABLE:
		failures.append("a tap far outside the room is no longer refused")
	return failures


func _test_disabled_refuses_the_stick():
	var failures: Array = []
	var controller: RefCounted = MovementController.create(null)
	controller.call("set_disabled", true)

	if bool(controller.call("set_drive", 1.0, 0.0)):
		failures.append("a disabled character accepted the stick")
	if bool(controller.call("is_driving")):
		failures.append("a disabled character is being driven")
	if controller.call("get_state_name") != "disabled":
		failures.append("the state left DISABLED: '%s'" % controller.call("get_state_name"))
	var step: Dictionary = controller.call("advance", Vector3.ZERO, 0.0, DT)
	if not (step["velocity"] as Vector3).is_zero_approx():
		failures.append("a disabled character moved")

	# And being disabled mid-gesture drops the drive rather than latching it, so
	# a thumb resting on the stick behind a summary screen walks nobody.
	var other: RefCounted = MovementController.create(null)
	other.call("set_drive", 1.0, 0.0)
	for _frame: int in range(20):
		other.call("advance", Vector3.ZERO, 0.0, DT)
	other.call("set_disabled", true)
	other.call("set_disabled", false)
	var after: Dictionary = other.call("advance", Vector3.ZERO, 0.0, DT)
	if not (after["velocity"] as Vector3).is_zero_approx():
		failures.append("the drive came back by itself after the overlay closed")
	if other.call("get_state_name") != "idle":
		failures.append("after an overlay the character should be at rest, not '%s'"
				% other.call("get_state_name"))
	return failures


## -- Containment ---------------------------------------------------------------

## The one that decides whether a four-year-old can get stuck. Push in every
## direction, for a long time, from the middle of a 4 x 4 m room: he must still
## be in the room.
func _test_the_room_is_a_room():
	var failures: Array = []
	for step: int in range(24):
		var angle: float = TAU * float(step) / 24.0
		var provider: RoomProvider = RoomProvider.new()
		var controller: RefCounted = MovementController.create(provider)
		var position: Vector3 = Vector3.ZERO
		controller.call("set_position", position)
		controller.call("set_drive", cos(angle), sin(angle))
		for _frame: int in range(600):   # ten seconds of a held thumb
			controller.call("set_drive", cos(angle), sin(angle))
			var result: Dictionary = controller.call("advance", position, 0.0, DT)
			position += (result["velocity"] as Vector3) * DT

		var inside: Rect2 = provider.bounds.grow(0.02)
		if not inside.has_point(Vector2(position.x, position.z)):
			failures.append("ten seconds of thumb at %.0f degrees drove the child to %s, outside "
					% [rad_to_deg(angle), str(position)]
					+ "the room. Off the navmesh is a dead end, and this game has none.")
			break
	return failures


## Straight at a wall: stop. Diagonally at a wall: slide along it. Both fall out
## of the same clamp, and the sliding half is what stops the control feeling
## broken in a corner.
func _test_a_wall_is_slid_along_not_through():
	var failures: Array = []

	var provider: RoomProvider = RoomProvider.new()
	var controller: RefCounted = MovementController.create(provider)
	var position: Vector3 = Vector3(1.99, 0.0, 0.0)
	controller.call("set_position", position)
	for _frame: int in range(120):
		controller.call("set_drive", 1.0, 0.0)          # straight into +x
		var result: Dictionary = controller.call("advance", position, 0.0, DT)
		position += (result["velocity"] as Vector3) * DT
	if position.x > provider.bounds.end.x + 0.02:
		failures.append("pushed straight at the wall, the child ended up at x = %.3f" % position.x)
	if absf(position.z) > 0.05:
		failures.append("pushing straight at a wall drifted sideways to z = %.3f" % position.z)

	var sliding: RoomProvider = RoomProvider.new()
	var slider: RefCounted = MovementController.create(sliding)
	var at: Vector3 = Vector3(1.99, 0.0, 0.0)
	slider.call("set_position", at)
	for _frame: int in range(120):
		slider.call("set_drive", 0.707, 0.707)          # into the wall AND along it
		var result2: Dictionary = slider.call("advance", at, 0.0, DT)
		at += (result2["velocity"] as Vector3) * DT
	if at.x > sliding.bounds.end.x + 0.02:
		failures.append("a diagonal push went through the wall to x = %.3f" % at.x)
	if at.z < 0.5:
		failures.append("a diagonal push at a wall only reached z = %.3f; the child should SLIDE "
				% at.z + "along it, not stick to it")

	if sliding.snaps == 0:
		failures.append("the navigation clamp was never consulted")
	return failures


## -- Through the character ------------------------------------------------------

## End to end: the stick's numbers become a body that has actually moved. The
## character is the thin shell over the controller, and `step_movement()` exists
## precisely so that join can be observed with no physics frames.
func _test_the_body_really_moves():
	var failures: Array = []
	var character: CharacterBody3D = CharacterBody3D.new()
	character.set_script(CharacterScript)
	character.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	if not bool(character.call("drive", 0.0, -1.0)):
		failures.append("the character refused the stick")
	if character.call("get_state_name") != "walking":
		failures.append("the character should be walking, not '%s'"
				% character.call("get_state_name"))
	if not bool(character.call("is_driving")):
		failures.append("is_driving() is false while a thumb is down")

	for _frame: int in range(120):
		character.call("drive", 0.0, -1.0)
		character.call("step_movement", DT)
	if character.position.z > -1.5:
		failures.append("two seconds of full thumb only moved the body to z = %.2f; at %.2f m/s "
				% [character.position.z, MovementController.WALK_SPEED]
				+ "it should be most of a room away")
	if absf(character.position.x) > 0.02:
		failures.append("pushing straight forward drifted sideways to x = %.3f" % character.position.x)
	# Facing follows the direction of travel.
	if absf(NavMath.yaw_towards(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 0.0)
			- character.rotation.y) > 0.05:
		failures.append("the character is not facing the way the thumb pointed")

	character.call("stop_driving")
	for _frame: int in range(60):
		character.call("step_movement", DT)
	if not character.velocity.is_zero_approx():
		failures.append("the body kept its velocity after the thumb left: %s"
				% str(character.velocity))
	if character.call("get_state_name") != "idle":
		failures.append("the character did not return to idle, it is '%s'"
				% character.call("get_state_name"))
	character.free()
	return failures


## Screen axes become world axes through the camera, which is what makes "up"
## mean "away from me" whatever the room's own orientation is.
func _test_screen_direction_becomes_world_direction():
	var failures: Array = []

	# A camera looking down the -Z axis, pitched down 32 degrees like the house's.
	var pitched: Basis = Basis.from_euler(Vector3(deg_to_rad(-32.0), 0.0, 0.0))
	var forward: Vector3 = HouseWorldScript.drive_direction(pitched, Vector2(0.0, -1.0))
	if forward.z > -0.99:
		failures.append("pushing up the screen should walk away from the camera, got %s"
				% str(forward))
	if absf(forward.y) > 0.001:
		failures.append("the drive direction must be horizontal; the camera's pitch leaked in: %s"
				% str(forward))
	if absf(forward.length() - 1.0) > 0.002:
		failures.append("full deflection should be a unit direction, got %.3f" % forward.length())

	var right: Vector3 = HouseWorldScript.drive_direction(pitched, Vector2(1.0, 0.0))
	if right.x < 0.99:
		failures.append("pushing right should walk right, got %s" % str(right))

	# Half a push is half a direction: the magnitude survives the conversion, or
	# the response curve would be thrown away one layer later.
	var half: Vector3 = HouseWorldScript.drive_direction(pitched, Vector2(0.0, -0.5))
	if absf(half.length() - 0.5) > 0.002:
		failures.append("a half push became %.3f rather than 0.5" % half.length())

	# A camera rotated 90 degrees takes the stick with it.
	var turned: Basis = Basis.from_euler(Vector3(0.0, deg_to_rad(90.0), 0.0))
	var turned_forward: Vector3 = HouseWorldScript.drive_direction(turned, Vector2(0.0, -1.0))
	if turned_forward.x > -0.99:
		failures.append("the stick is not camera-relative: %s" % str(turned_forward))

	# A camera looking straight down has no heading; falling back to the world
	# axes beats handing a child a control that has silently stopped working.
	var overhead: Basis = Basis.from_euler(Vector3(deg_to_rad(-90.0), 0.0, 0.0))
	if HouseWorldScript.drive_direction(overhead, Vector2(0.0, -1.0)).length() < 0.99:
		failures.append("a top-down camera produced no direction at all")
	return failures


## The boundary between the two control schemes, at the layer that owns it.
func _test_the_tap_router_yields_inside_the_zone():
	var failures: Array = []
	var viewport: Vector2 = Vector2(2217.0, 1024.0)
	var nav: Node3D = NavigationController.new()
	var stick: Control = Joystick.new()
	stick.size = viewport
	stick.call("build")

	# With no claimant, nothing changes at all: this is what keeps every other
	# scene's tap-to-walk exactly as it was.
	if bool(nav.call("is_press_claimed", Vector2(200.0, 900.0))):
		failures.append("a controller with no claimant claimed a press")

	nav.call("set_press_claimant", stick)
	var zone: Rect2 = stick.call("get_activation_rect")
	if not bool(nav.call("is_press_claimed", zone.get_center())):
		failures.append("the tap router did not yield inside the stick's zone, so one thumb would "
				+ "both grab the stick and order a walk")
	for outside: Vector2 in [
		Vector2(viewport.x * 0.5, viewport.y * 0.5),
		Vector2(viewport.x - 100.0, viewport.y - 80.0),
		Vector2(zone.end.x + 60.0, zone.end.y - 30.0),
	]:
		if bool(nav.call("is_press_claimed", outside)):
			failures.append("the stick claimed %s, and tap-to-walk lost floor it used to own"
					% str(outside))

	# A stick that has been switched off gives the floor back.
	stick.call("set_enabled", false)
	if bool(nav.call("is_press_claimed", zone.get_center())):
		failures.append("a disabled stick still claims presses")

	nav.free()
	stick.free()
	return failures


## The walk clip and the walk speed are one decision (see `WALK_SPEED`). The
## stick made every speed in between reachable, so the clip has to follow.
func _test_the_walk_clip_follows_the_real_speed():
	var failures: Array = []
	var character: CharacterBody3D = CharacterBody3D.new()
	character.set_script(CharacterScript)
	character.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	var player: AnimationPlayer = AnimationPlayer.new()
	var library: AnimationLibrary = AnimationLibrary.new()
	for clip_name: String in ["idle", "walk"]:
		var animation: Animation = Animation.new()
		animation.length = 0.59
		animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip_name, animation)
	player.add_animation_library("", library)
	character.add_child(player)

	character.call("drive", 0.0, -0.5)
	for _frame: int in range(90):
		character.call("drive", 0.0, -0.5)
		character.call("step_movement", DT)

	if player.current_animation != "walk":
		failures.append("half a thumb should still be a walk, not '%s'" % player.current_animation)
	if player.speed_scale > 0.85:
		failures.append("the walk clip is playing at %.2f while the body moves at half speed; "
				% player.speed_scale + "the feet would skate, which is the opposite of 'smooth'")

	character.call("drive", 0.0, -1.0)
	for _frame: int in range(90):
		character.call("drive", 0.0, -1.0)
		character.call("step_movement", DT)
	if absf(player.speed_scale - 1.0) > 0.02:
		failures.append("at full speed the clip must play at its authored rate, got %.3f"
				% player.speed_scale)

	# And nothing else is stretched by it.
	character.call("play_action", "idle")
	if absf(player.speed_scale - 1.0) > 0.001:
		failures.append("a slow walk left the next action running at %.2f" % player.speed_scale)
	character.free()
	return failures
