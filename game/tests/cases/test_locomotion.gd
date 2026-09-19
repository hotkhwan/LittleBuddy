extends RefCounted

## The character must not float.
##
## The report from live play was "Alice slides/floats instead of walking". The
## cause was arithmetic, so the fix is asserted as arithmetic: at the speed the
## game actually moves her, the feet must deliver very nearly that same speed.
##
## Measured from the shipping clips (`tools/glb_deform_check.py`):
##
##   walk  1.067 s cycle, 0.498 m stride -> 0.467 m/s at 1.0x
##   run   0.667 s cycle, 0.659 m stride -> 0.989 m/s at 1.0x
##   CharacterMovementController.WALK_SPEED = 1.05 m/s
##
## Driving `walk` at 1.0x while travelling 1.05 m/s meant the body outran its own
## legs by 2.25x. That number is what "floating" was.

const Locomotion := preload("res://scripts/character/locomotion.gd")
const Movement := preload("res://scripts/character/character_movement_controller.gd")

## How much foot/ground disagreement still reads as planted. 15% is generous --
## the fix lands far inside it -- and anything above it is visible sliding.
const MAX_SLIP: float = 0.15


func test_name() -> String:
	return "locomotion"


func run():
	var failures: Array = []
	failures.append_array(_test_the_float_is_gone_at_the_real_speed())
	failures.append_array(_test_no_slip_across_the_whole_range())
	failures.append_array(_test_standing_still_plays_nothing())
	failures.append_array(_test_the_right_clip_is_chosen())
	failures.append_array(_test_scale_is_trimmed_not_stretched())
	return failures


func _test_the_float_is_gone_at_the_real_speed():
	var failures: Array = []
	var speed: float = Movement.WALK_SPEED
	var slip: float = Locomotion.slip_ratio(speed)
	if slip > MAX_SLIP:
		failures.append(("at the game's own WALK_SPEED (%.2f m/s) the feet deliver %.3f m/s -- "
				+ "a %.0f%% mismatch. This is the float that was reported.")
				% [speed, Locomotion.resulting_foot_speed(speed), slip * 100.0])
	# And the naive fix must still be rejected: walk at 1.0x here is the bug.
	var naive: float = absf(Locomotion.WALK_CLIP_SPEED - speed) / speed
	if naive <= MAX_SLIP:
		failures.append(("the walk clip at 1.0x now matches WALK_SPEED, so this test no longer "
				+ "describes the bug it was written for -- re-measure the clips."))
	return failures


func _test_no_slip_across_the_whole_range():
	var failures: Array = []
	# Every speed the character can actually travel at, not just the top one.
	var speed: float = Locomotion.IDLE_SPEED
	while speed <= Movement.WALK_SPEED + 0.001:
		var slip: float = Locomotion.slip_ratio(speed)
		if slip > MAX_SLIP:
			failures.append("at %.2f m/s the feet slip %.0f%% (clip '%s' at %.2fx)"
					% [speed, slip * 100.0, Locomotion.clip_for_speed(speed),
						Locomotion.scale_for_speed(speed)])
		speed += 0.05
	return failures


func _test_standing_still_plays_nothing():
	var failures: Array = []
	if not Locomotion.clip_for_speed(0.0).is_empty():
		failures.append("a stationary character is playing '%s'; stopping must settle into idle"
				% Locomotion.clip_for_speed(0.0))
	if not Locomotion.clip_for_speed(Locomotion.IDLE_SPEED * 0.5).is_empty():
		failures.append("a barely-moving character is still stepping; that is the other half "
				+ "of looking wrong")
	if Locomotion.slip_ratio(0.0) != 0.0:
		failures.append("a stationary character reports slip")
	return failures


func _test_the_right_clip_is_chosen():
	var failures: Array = []
	# Slow -> walk, fast -> run. Each clip used where its own stride is closest.
	if Locomotion.clip_for_speed(Locomotion.WALK_CLIP_SPEED) != Locomotion.CLIP_WALK:
		failures.append("the walk clip's own natural speed does not select the walk clip")
	if Locomotion.clip_for_speed(Locomotion.RUN_CLIP_SPEED) != Locomotion.CLIP_RUN:
		failures.append("the run clip's own natural speed does not select the run clip")
	if Locomotion.clip_for_speed(Movement.WALK_SPEED) != Locomotion.CLIP_RUN:
		failures.append(("the game moves at %.2f m/s, which is a jog -- the run clip matches it "
				+ "to within 6%% and should be selected, got '%s'")
				% [Movement.WALK_SPEED, Locomotion.clip_for_speed(Movement.WALK_SPEED)])
	return failures


func _test_scale_is_trimmed_not_stretched():
	var failures: Array = []
	# The whole point of choosing by speed is that the correction stays small.
	var speed: float = Locomotion.IDLE_SPEED
	while speed <= Movement.WALK_SPEED + 0.001:
		var scale: float = Locomotion.scale_for_speed(speed)
		if scale < Locomotion.MIN_SCALE or scale > Locomotion.MAX_SCALE:
			failures.append("at %.2f m/s playback is %.2fx, outside the legible range"
					% [speed, scale])
		speed += 0.05
	# describe() must never disagree with the two accessors.
	for probe: float in [0.0, 0.3, 0.6, 1.05]:
		var described: Dictionary = Locomotion.describe(probe)
		if String(described["clip"]) != Locomotion.clip_for_speed(probe):
			failures.append("describe() and clip_for_speed() disagree at %.2f" % probe)
		if not is_equal_approx(float(described["scale"]), Locomotion.scale_for_speed(probe)):
			failures.append("describe() and scale_for_speed() disagree at %.2f" % probe)
	return failures
