extends RefCounted

## ============================================================================
## WHY THE CHARACTER FLOATED, AND THE ARITHMETIC THAT FIXES IT.
## ============================================================================
##
## A character slides when the ground it covers and the stride its legs make
## disagree. Both numbers were measured from the shipping assets:
##
## | Clip | Cycle | Stride @1.65 m | Ground speed at 1.0x |
## |---|---|---|---|
## | `walk` | 1.067 s | 0.498 m | **0.467 m/s** |
## | `run`  | 0.667 s | 0.659 m | **0.989 m/s** |
##
## and `CharacterMovementController.WALK_SPEED` is **1.05 m/s**; since 2026-09-20
## the thumbstick's outer band runs at `RUN_SPEED`, **1.6 m/s**, which the run
## clip covers at a 1.62x trim -- still inside `MAX_SCALE`, so the feet stay
## planted at the top of the range too (`test_locomotion.gd` sweeps to it).
##
## So driving the walk clip at 1.0x while moving at 1.05 m/s meant the feet were
## delivering 0.467 m/s under a body travelling 1.05 -- the body outran its own
## legs by 2.25x, which is precisely the float that was reported. Playing walk at
## 2.25x instead would have fixed the slide and replaced it with scurrying.
##
## The honest reading of those numbers is that **1.05 m/s is a jog, not a walk**,
## and the run clip already matches it to within 6%. So the clip is chosen by
## SPEED, and the remaining error is taken up by `speed_scale` -- a small trim on
## the right clip rather than a large stretch on the wrong one.
##
## Pure and static: no node, no frame loop, so every number above is assertable.

## Measured ground speed of each clip at 1.0x playback, in metres/second, for a
## character normalised to 1.65 m. Re-measure with `tools/glb_deform_check.py`
## if the clips or the character height change.
const WALK_CLIP_SPEED: float = 0.467
const RUN_CLIP_SPEED: float = 0.989

const CLIP_IDLE: String = ""
const CLIP_WALK: String = "walk"
const CLIP_RUN: String = "run"

## Below this the character is standing still.
##
## 0.16 m/s, not 0.05. The lower figure let a barely-touched joystick creep the
## body forward at a speed no clip can match without playing at a tenth rate, and
## a clamp there reintroduced the exact slide this file exists to remove. Below
## 0.16 m/s the character is not meaningfully travelling, so it stands -- which
## is also what stops it stepping in place after it has stopped.
const IDLE_SPEED: float = 0.16

## Where walking becomes jogging. Set at the midpoint of the two clips' natural
## speeds, so each clip is used where its own stride is closest and the trim
## applied to it is smallest.
const RUN_THRESHOLD: float = (WALK_CLIP_SPEED + RUN_CLIP_SPEED) * 0.5

## How far playback may be trimmed.
##
## The floor is set so that the SLOWEST speed the character can travel
## (`IDLE_SPEED`) is still reachable by the walk clip: 0.16 / 0.467 = 0.34. Any
## higher and the clamp would bite inside the real range and put the slide back.
## Slow legs on a slow character are correct, so there is no reason to clamp
## harder than the arithmetic requires.
const MIN_SCALE: float = 0.34
const MAX_SCALE: float = 1.85


## The clip to play for a ground speed.
static func clip_for_speed(speed: float) -> String:
	if speed < IDLE_SPEED:
		return CLIP_IDLE
	return CLIP_RUN if speed >= RUN_THRESHOLD else CLIP_WALK


## The playback rate that makes that clip's feet match the ground.
##
## `speed_scale = actual / natural`: at twice a clip's natural speed the legs
## must cycle twice as fast, or the feet skate. Clamped, because a clip stretched
## far enough stops reading as the action it is.
static func scale_for_speed(speed: float) -> float:
	var clip: String = clip_for_speed(speed)
	if clip == CLIP_IDLE:
		return 1.0
	var natural: float = RUN_CLIP_SPEED if clip == CLIP_RUN else WALK_CLIP_SPEED
	if natural <= 0.0001:
		return 1.0
	return clampf(speed / natural, MIN_SCALE, MAX_SCALE)


## `{clip, scale}` in one call, so a caller cannot apply one without the other --
## which is how a clip ends up playing at the previous clip's rate.
static func describe(speed: float) -> Dictionary:
	return {"clip": clip_for_speed(speed), "scale": scale_for_speed(speed)}


## How far the feet actually travel per second, given what is being played. Used
## by the test to prove the mismatch is gone rather than assumed.
static func resulting_foot_speed(speed: float) -> float:
	var clip: String = clip_for_speed(speed)
	if clip == CLIP_IDLE:
		return 0.0
	var natural: float = RUN_CLIP_SPEED if clip == CLIP_RUN else WALK_CLIP_SPEED
	return natural * scale_for_speed(speed)


## Fraction by which the feet disagree with the ground at this speed. 0.0 is
## perfect; anything under ~0.15 reads as planted.
static func slip_ratio(speed: float) -> float:
	if speed < IDLE_SPEED:
		return 0.0
	return absf(resulting_foot_speed(speed) - speed) / maxf(speed, 0.0001)
