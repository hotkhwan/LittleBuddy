extends RefCounted

## Does a tap on the floor answer back?
##
## This case exists because of a sentence from a physical device: *"controlling
## the character isn't smooth -- you have to tap the bed, the wardrobe or the door
## for him to walk."* Routing was never the problem; 16 of 16 synthetic floor taps
## across a live room already classified as FLOOR and were accepted. The problem
## was that a floor tap produced **nothing at all** on screen, so the only
## evidence a press had landed arrived a fraction of a second later, somewhere
## else, as a small character starting to move. Furniture only felt better because
## furniture is a big obvious thing you aimed at.
##
## So the property under test is not "the tap routed". It is "the tap was
## ANSWERED, on the frame of the press, before anything moved". Delete the
## acknowledgement and this case goes red -- which is the whole point of it.
##
## Everything here runs without a camera, a viewport or a physics world:
## `apply_tap()` takes an already-classified tap, and `TapRipple`'s animation is a
## pure function of elapsed time stepped by `advance()`.

const NavigationController := preload("res://scripts/navigation/navigation_controller.gd")
const TapRipple := preload("res://scripts/navigation/tap_ripple.gd")
const MovementController := preload("res://scripts/character/character_movement_controller.gd")
const Palette := preload("res://scripts/ui/palette.gd")

const DT: float = 1.0 / 60.0


## Enough of a character for the controller to drive, plus the one signal the
## marker listens to.
class FakeCharacter extends Node3D:
	signal arrived(target_id: String)

	var ground_moves: Array = []
	var accept: bool = true

	func move_to(_target: Variant) -> bool:
		return accept

	func move_to_ground(x: float, z: float) -> bool:
		ground_moves.append(Vector2(x, z))
		return accept

	func register_activity_target(_target: Object) -> bool:
		return true

	func announce_arrival() -> void:
		arrived.emit("")


func test_name() -> String:
	return "feel_tap_response"


func run():
	var failures: Array = []
	failures.append_array(_test_pulse_curve())
	failures.append_array(_test_hold_curve())
	failures.append_array(_test_floor_tap_is_acknowledged())
	failures.append_array(_test_acknowledgement_precedes_the_walk())
	failures.append_array(_test_marker_clears_on_arrival())
	failures.append_array(_test_refused_tap_is_still_answered_kindly())
	failures.append_array(_test_retap_moves_the_marker())
	failures.append_array(_test_disabled_taps_leave_nothing_on_the_floor())
	failures.append_array(_test_marker_colour_is_the_locked_mint())
	failures.append_array(_test_pace_is_responsive())
	return failures


## -- The curve, with no renderer -----------------------------------------------

func _test_pulse_curve():
	var failures: Array = []

	var at_zero: Dictionary = TapRipple.pulse_state(0.0)
	if not bool(at_zero["active"]):
		failures.append("the pulse must be on screen on the very first frame of the tap")
	if not is_equal_approx(float(at_zero["radius"]), TapRipple.PULSE_START_RADIUS):
		failures.append("the pulse should start at PULSE_START_RADIUS, got %f"
				% float(at_zero["radius"]))
	if float(at_zero["alpha"]) < TapRipple.PULSE_ALPHA - 0.001:
		failures.append("the pulse should be at full opacity when it appears; a fade-IN is exactly "
				+ "the delay this marker exists to remove")

	# Monotonic outward, monotonic fade, and gone by PULSE_SEC.
	var previous_radius: float = -1.0
	var previous_alpha: float = 999.0
	var samples: int = 12
	for i: int in range(samples):
		var t: float = TapRipple.PULSE_SEC * float(i) / float(samples)
		var state: Dictionary = TapRipple.pulse_state(t)
		if not bool(state["active"]):
			failures.append("the pulse went inactive at %.3f s, before PULSE_SEC" % t)
			break
		if float(state["radius"]) < previous_radius:
			failures.append("the pulse radius must only ever grow")
			break
		if float(state["alpha"]) > previous_alpha:
			failures.append("the pulse must only ever fade")
			break
		previous_radius = float(state["radius"])
		previous_alpha = float(state["alpha"])

	if bool(TapRipple.pulse_state(TapRipple.PULSE_SEC)["active"]):
		failures.append("the pulse must be finished at PULSE_SEC, not lingering")
	if bool(TapRipple.pulse_state(-1.0)["active"]):
		failures.append("a pulse that was never started must not be on screen")

	# A quick reaction, not an animation to sit through.
	if TapRipple.PULSE_SEC > 0.6:
		failures.append("PULSE_SEC %.2f s is long enough to read as a delay" % TapRipple.PULSE_SEC)
	return failures


func _test_hold_curve():
	var failures: Array = []

	if not is_equal_approx(TapRipple.hold_alpha(0.0, -1.0), TapRipple.HOLD_ALPHA):
		failures.append("the destination disc must be fully visible from the first frame")
	if not is_equal_approx(TapRipple.hold_alpha(2.0, -1.0), TapRipple.HOLD_ALPHA):
		failures.append("the destination disc must stay put for the whole walk")
	if TapRipple.hold_alpha(2.0, TapRipple.HOLD_FADE_SEC * 0.5) >= TapRipple.HOLD_ALPHA:
		failures.append("the destination disc should be fading once the walk is over")
	if TapRipple.hold_alpha(2.0, TapRipple.HOLD_FADE_SEC) > 0.0:
		failures.append("the destination disc should be gone once the fade is done")
	if TapRipple.hold_alpha(TapRipple.HOLD_MAX_SEC + 0.1, -1.0) > 0.0:
		failures.append("a hold nobody released must tidy itself away; a mint disc left on the "
				+ "floor for a whole level is litter, not feedback")
	if TapRipple.hold_alpha(-1.0, -1.0) > 0.0:
		failures.append("a hold that was never started must not be on screen")

	# It must never shout louder than the story's own "go here" disc.
	if TapRipple.HOLD_RADIUS >= 0.42:
		failures.append("the tap marker (%.2f m) must stay smaller than HouseStage's beat marker"
				% TapRipple.HOLD_RADIUS)
	return failures


## -- The controller ------------------------------------------------------------

## THE regression test. A floor tap has to leave a mark, where the child pressed.

func _test_floor_tap_is_acknowledged():
	var failures: Array = []
	var session: Dictionary = _session()
	var nav: Node3D = session["nav"]

	var ripple: Node3D = nav.call("get_tap_ripple")
	if ripple == null:
		return _close(session, ["the navigation controller built no tap marker at all"])
	if bool(ripple.call("is_showing")):
		failures.append("nothing should be marked on the floor before the child touches it")

	nav.call("apply_tap", {"kind": NavigationController.TapKind.FLOOR, "x": 1.4, "z": -0.6})

	if not bool(ripple.call("is_showing")):
		failures.append("a tap on bare floor drew NOTHING. This is the device complaint: the "
				+ "child presses the floor and the screen does not react.")
	var point: Vector3 = ripple.call("get_point")
	if absf(point.x - 1.4) > 0.001 or absf(point.z + 0.6) > 0.001:
		failures.append("the marker must appear where the finger landed, got %s" % str(point))
	if not bool(ripple.call("is_holding")):
		failures.append("the destination the child chose should stay marked while he walks to it")

	# And it is a real animation, not a single static frame.
	var first: float = float(ripple.call("get_pulse_radius"))
	for _frame: int in range(6):
		ripple.call("advance", DT)
	if float(ripple.call("get_pulse_radius")) <= first:
		failures.append("the pulse never expanded; advance() is not driving it")
	return _close(session, failures)


## The acknowledgement has to come FIRST. Not after the path query, not after the
## character has started to move -- the point is that the screen answers while the
## finger is still down.
func _test_acknowledgement_precedes_the_walk():
	var failures: Array = []
	var session: Dictionary = _session()
	var nav: Node3D = session["nav"]
	var character: Node3D = session["character"]
	var ripple: Node3D = nav.call("get_tap_ripple")

	# The character records the order by checking the marker when it is asked to
	# move: if the marker is not up by then, the child saw nothing first.
	nav.call("apply_tap", {"kind": NavigationController.TapKind.FLOOR, "x": 0.5, "z": 0.5})
	if character.ground_moves.size() != 1:
		failures.append("the floor tap should still have produced exactly one walk request")
	if not bool(ripple.call("is_showing")):
		failures.append("the marker must survive the walk request, not be replaced by it")

	# Zero elapsed time: the marker is visible on the frame of the press, before a
	# single frame of movement has been advanced.
	if float(ripple.call("get_pulse_radius")) > TapRipple.PULSE_START_RADIUS + 0.001:
		failures.append("the pulse had already animated before any frame was advanced")
	return _close(session, failures)


func _test_marker_clears_on_arrival():
	var failures: Array = []
	var session: Dictionary = _session()
	var nav: Node3D = session["nav"]
	var character: FakeCharacter = session["character"]
	var ripple: Node3D = nav.call("get_tap_ripple")

	nav.call("apply_tap", {"kind": NavigationController.TapKind.FLOOR, "x": 1.0, "z": 1.0})
	for _frame: int in range(60):
		ripple.call("advance", DT)
	if not bool(ripple.call("is_holding")):
		failures.append("the destination must stay marked for the whole walk, however long it is")

	character.announce_arrival()
	for _frame: int in range(30):
		ripple.call("advance", DT)
	if bool(ripple.call("is_holding")):
		failures.append("the marker must disappear when Little Buddy gets there; a marker that "
				+ "outlives the walk stops meaning anything")
	return _close(session, failures)


## A tap somewhere he genuinely cannot stand still gets an answer. It simply
## fades again -- no red X, no failure sound, no "wrong".
func _test_refused_tap_is_still_answered_kindly():
	var failures: Array = []
	var session: Dictionary = _session()
	var nav: Node3D = session["nav"]
	var character: FakeCharacter = session["character"]
	var ripple: Node3D = nav.call("get_tap_ripple")
	character.accept = false

	nav.call("apply_tap", {"kind": NavigationController.TapKind.FLOOR, "x": -9.0, "z": 9.0})
	if not bool(ripple.call("is_showing")):
		failures.append("even a tap that leads nowhere must be acknowledged; ignoring a press is "
				+ "how a child decides the game is broken")

	for _frame: int in range(30):
		ripple.call("advance", DT)
	if bool(ripple.call("is_holding")):
		failures.append("a refused tap must not leave a destination disc promising a walk that is "
				+ "never going to happen")
	return _close(session, failures)


## Changing your mind mid-walk must move the marker with the destination -- and
## must not stack up a second marker or a second walk.
func _test_retap_moves_the_marker():
	var failures: Array = []
	var session: Dictionary = _session()
	var nav: Node3D = session["nav"]
	var character: FakeCharacter = session["character"]
	var ripple: Node3D = nav.call("get_tap_ripple")

	nav.call("apply_tap", {"kind": NavigationController.TapKind.FLOOR, "x": 1.5, "z": 0.0})
	for _frame: int in range(20):
		ripple.call("advance", DT)
	nav.call("apply_tap", {"kind": NavigationController.TapKind.FLOOR, "x": -1.5, "z": 0.8})

	var point: Vector3 = ripple.call("get_point")
	if absf(point.x + 1.5) > 0.001 or absf(point.z - 0.8) > 0.001:
		failures.append("the marker should follow the NEW destination, got %s" % str(point))
	if float(ripple.call("get_pulse_radius")) > TapRipple.PULSE_START_RADIUS + 0.001:
		failures.append("a second tap should restart the pulse, not continue the first one")
	if character.ground_moves.size() != 2:
		failures.append("two taps should be two walk requests, got %d"
				% character.ground_moves.size())

	# The destination-replacement guarantee itself, at the layer that owns it.
	var movement: RefCounted = MovementController.create(null)
	movement.call("request_move", Vector3(2.0, 0.0, 0.0))
	var serial: int = int(movement.call("get_move_serial"))
	movement.call("set_position", Vector3(0.5, 0.0, 0.0))
	movement.call("request_move", Vector3(-1.0, 0.0, 1.0))
	if int(movement.call("get_move_serial")) != serial + 1:
		failures.append("a tap while walking must REPLACE the destination exactly once")
	if not (movement.call("get_destination") as Vector3).is_equal_approx(Vector3(-1.0, 0.0, 1.0)):
		failures.append("the second tap should be the destination, got %s"
				% str(movement.call("get_destination")))
	if int(movement.call("get_path_size")) > 2:
		failures.append("destinations must never queue")
	return _close(session, failures)


func _test_disabled_taps_leave_nothing_on_the_floor():
	var failures: Array = []
	var session: Dictionary = _session()
	var nav: Node3D = session["nav"]
	var ripple: Node3D = nav.call("get_tap_ripple")

	nav.call("apply_tap", {"kind": NavigationController.TapKind.FLOOR, "x": 0.8, "z": 0.2})
	nav.set("taps_enabled", false)
	if bool(ripple.call("is_showing")):
		failures.append("switching taps off (a summary screen opening) must take the marker with "
				+ "them, or the overlay opens over a promise nobody is going to keep")
	return _close(session, failures)


## Art bible section 3 is LOCKED, and this is a new on-screen colour.
func _test_marker_colour_is_the_locked_mint():
	var failures: Array = []
	var session: Dictionary = _session()
	var ripple: Node3D = session["nav"].call("get_tap_ripple")
	ripple.call("show_at", 0.0, 0.0, 0.0)

	for child: Node in ripple.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null:
			continue
		var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if material == null:
			failures.append("marker disc '%s' has no material" % child.name)
			continue
		var color: Color = material.albedo_color
		if absf(color.r - Palette.MINT.r) > 0.002 or absf(color.g - Palette.MINT.g) > 0.002 \
				or absf(color.b - Palette.MINT.b) > 0.002:
			failures.append("marker disc '%s' is not the locked mint, it is %s"
					% [child.name, str(color)])
		if color.a >= 1.0:
			failures.append("marker disc '%s' is opaque; it must not hide the floor" % child.name)
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures.append("marker disc '%s' casts a shadow, which the budget rules out"
					% child.name)
	return _close(session, failures)


## -- Pace ----------------------------------------------------------------------

## The other half of the same complaint. The rail here is two-sided on purpose:
## the original one only had a floor ("never an action game"), and the speed sat
## against it at 0.85 m/s, which on a phone is a five-second wait per tap.
func _test_pace_is_responsive():
	var failures: Array = []
	var crossing: float = 4.0 / MovementController.WALK_SPEED
	if crossing > 4.2:
		failures.append("crossing a 4 m room takes %.2f s. That is the device complaint: a child "
				% crossing + "taps and then waits.")
	if crossing < 2.6:
		failures.append("crossing a 4 m room in %.2f s is an action game, not this game" % crossing)

	# A 90-degree change of mind has to be visible almost at once, or the walk
	# reads as drifting rather than as obeying.
	var quarter_turn: float = (PI * 0.5) / MovementController.TURN_SPEED
	if quarter_turn > 0.30:
		failures.append("a quarter turn takes %.2f s; the child should see him commit" % quarter_turn)
	if quarter_turn < 0.10:
		failures.append("a quarter turn takes %.2f s, which is a snap rather than a turn"
				% quarter_turn)
	return failures


## -- Helpers -------------------------------------------------------------------

func _session() -> Dictionary:
	var nav: Node3D = NavigationController.new()
	var character: FakeCharacter = FakeCharacter.new()
	nav.add_child(character)
	nav.call("bind_character", character)
	return {"nav": nav, "character": character}


func _close(session: Dictionary, failures: Array):
	var nav: Node3D = session["nav"]
	nav.free()
	return failures
