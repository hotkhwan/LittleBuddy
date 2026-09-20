extends RefCounted

## RUN IS FASTER THAN WALK -- measured on the real character, not read off a
## constant.
##
## The owner's report from the device (2026-09-20) was one line: "run is not
## faster than walk". Measured, it was true. `locomotion.gd` chose the RUN clip
## from 0.73 m/s up, so the character visibly ran at the top of the stick, and
## every mode of travel -- tap-to-walk, a full stick, an over-length stick --
## topped out at the same 1.05 m/s. The legs said run; the room said walk.
##
## So this drives `LittleBuddyCharacter` itself -- the `CharacterBody3D` shell,
## through `step_movement()`, integrating position by hand exactly as it does in
## the headless runner -- for the same wall-clock span in each mode and compares
## the DISPLACEMENT. Constants can drift from what the body does; a metre is a
## metre.
##
##   walk  = tap-to-walk to a far point (the game's calm pace, `WALK_SPEED`)
##   run   = the thumbstick at full deflection (`RUN_SPEED`)
##
## and the ratio must be at least 1.4. Both figures are printed so the pass
## report can quote them.
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const CharacterScript := preload("res://scripts/character/little_buddy_character.gd")
const Movement := preload("res://scripts/character/character_movement_controller.gd")
const Locomotion := preload("res://scripts/character/locomotion.gd")

const DT: float = 1.0 / 60.0
## Long enough to be well past the acceleration ramp, short enough that a
## tap-to-walk over 20 m never arrives inside it.
const SECONDS: float = 3.0
const MIN_RATIO: float = 1.4


func test_name() -> String:
	return "run_vs_walk"


func run():
	var failures: Array = []
	var walk: float = _measure_walk()
	var run_distance: float = _measure_run(1.0)
	var band: float = _measure_run(Movement.RUN_MAGNITUDE)
	var walk_speed: float = walk / SECONDS
	var run_speed: float = run_distance / SECONDS
	print("    measured over %.1f s: tap-to-walk %.2f m (%.2f m/s), stick at the walk/run "
			% [SECONDS, walk, walk_speed]
			+ "boundary %.2f m (%.2f m/s), full stick %.2f m (%.2f m/s), ratio %.2fx"
			% [band, band / SECONDS, run_distance, run_speed,
				run_distance / maxf(walk, 0.0001)])

	if walk <= 0.5:
		failures.append("tap-to-walk covered only %.2f m in %.1f s; the walk itself is broken"
				% [walk, SECONDS])
	if run_distance < walk * MIN_RATIO:
		failures.append(("the run covered %.2f m against the walk's %.2f m in the same %.1f s "
				+ "(%.2fx). Run must be at least %.1fx walk -- this is the owner's report, "
				+ "measured.") % [run_distance, walk, SECONDS, run_distance / maxf(walk, 0.0001),
					MIN_RATIO])
	# The boundary of the walk band IS a walk: the stick held there must not be
	# meaningfully faster than a tap-to-walk, or the "walk" half of the stick is
	# a run in disguise.
	if band > walk * 1.08:
		failures.append("the stick at the walk/run boundary covered %.2f m against tap-to-walk's "
				% band + "%.2f m; the walk band is not a walk" % walk)
	# The feet keep up at the top: the run clip's trim at RUN_SPEED is inside the
	# legible range, so a faster body did not buy sliding feet.
	if Locomotion.slip_ratio(run_speed) > 0.15:
		failures.append("at the measured run speed %.2f m/s the feet slip %.0f%%"
				% [run_speed, Locomotion.slip_ratio(run_speed) * 100.0])
	failures.append_array(_test_running_is_reported())
	failures.append_array(_test_run_stops_cleanly())
	return failures


## Tap-to-walk over a long straight, far enough that it never arrives.
func _measure_walk() -> float:
	var character: CharacterBody3D = _character()
	character.call("move_to_ground", 0.0, -40.0)
	var frames: int = int(round(SECONDS / DT))
	for _frame: int in range(frames):
		character.call("step_movement", DT)
	var covered: float = Vector2(character.position.x, character.position.z).length()
	character.free()
	return covered


## The stick, held at `magnitude`, straight ahead.
func _measure_run(magnitude: float) -> float:
	var character: CharacterBody3D = _character()
	var frames: int = int(round(SECONDS / DT))
	for _frame: int in range(frames):
		character.call("drive", 0.0, -magnitude)
		character.call("step_movement", DT)
	var covered: float = Vector2(character.position.x, character.position.z).length()
	character.free()
	return covered


## `is_running()` and `running_changed` tell the HUD which side of the boundary
## the character is on -- exactly once per crossing.
func _test_running_is_reported():
	var failures: Array = []
	var character: CharacterBody3D = _character()
	var changes: Array = []
	character.connect("running_changed", func(running: bool) -> void: changes.append(running))

	for _frame: int in range(60):
		character.call("drive", 0.0, -Movement.RUN_MAGNITUDE)
		character.call("step_movement", DT)
	if bool(character.call("is_running")):
		failures.append("a full walk on the stick reports as running")
	for _frame: int in range(60):
		character.call("drive", 0.0, -1.0)
		character.call("step_movement", DT)
	if not bool(character.call("is_running")):
		failures.append("a full stick does not report as running (%.2f m/s)"
				% float(character.call("get_speed")))
	character.call("stop_driving")
	for _frame: int in range(60):
		character.call("step_movement", DT)
	if bool(character.call("is_running")):
		failures.append("still reporting a run after the thumb left")
	if changes != [true, false]:
		failures.append("running_changed fired %s; expected exactly [true, false]" % str(changes))
	character.free()
	return failures


## Letting go at a run is a short coast to a full stop -- no sliding on, no
## freeze-frame, and the character rests rather than staying in WALKING.
func _test_run_stops_cleanly():
	var failures: Array = []
	var character: CharacterBody3D = _character()
	for _frame: int in range(90):
		character.call("drive", 0.0, -1.0)
		character.call("step_movement", DT)
	var at_release: Vector3 = character.position
	character.call("stop_driving")
	var frames_to_rest: int = 0
	while bool(character.call("is_busy")) and frames_to_rest < 120:
		character.call("step_movement", DT)
		frames_to_rest += 1
	var coasted: float = Vector2(character.position.x - at_release.x,
			character.position.z - at_release.z).length()
	if frames_to_rest >= 120:
		failures.append("the character never came to rest after a run")
	if frames_to_rest < 3:
		failures.append("a run stopped in %d frame(s); that is a freeze, not a stop" % frames_to_rest)
	if coasted > 0.35:
		failures.append("the character slid %.2f m after the thumb left a run; that is sliding"
				% coasted)
	if character.call("get_state_name") != "idle":
		failures.append("after stopping the character is '%s', not idle"
				% character.call("get_state_name"))
	character.free()
	return failures


## The shell as the house configures it: FLOATING, like `house_world.tscn`, so a
## body outside the tree is not also falling under gravity while it is measured.
func _character() -> CharacterBody3D:
	var character: CharacterBody3D = CharacterScript.new()
	character.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	character.position = Vector3.ZERO
	return character
