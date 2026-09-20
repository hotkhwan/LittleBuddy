extends RefCounted

## ============================================================================
## BUNNY'S LIFE CLIPS -- hand-authored keyframes on the REAL skeleton.
## ============================================================================
##
## The rigged Little Buddy export ships with a genuine `LB_Rig_v1`-mapped
## skeleton (24 bones, skinned mesh, sockets) and exactly three clips: an
## authored `walk`, an authored `run`, and a 0.3 s `Armature|clip0|baselayer`
## stub. There is **no idle**, no reaction and nothing to play when Bunny is
## standing still, which is why he read as a statue in the bedroom.
##
## (The export is named in `baby_little_buddy.gd` and nowhere else, this file
## included -- `test_baby_avatar.gd` fails the suite over a leaked filename, and
## it caught this doc comment naming one.)
##
## This file is the missing half. It builds `Animation` resources whose tracks
## are `TYPE_ROTATION_3D` / `TYPE_POSITION_3D` **bone** tracks addressed exactly
## the way the imported `walk` clip addresses them, and hands them to
## `baby_little_buddy.gd` to merge into the model's own `AnimationLibrary`.
##
## ## Say plainly what this is, and what it is not
##
## * It **is** skeletal animation: every track drives a named bone of the rig the
##   owner paid for, the mesh deforms through its real skin weights, and the
##   clips blend against `walk` through the ordinary `AnimationPlayer`.
## * It is **not** a DCC-authored clip. The keyframes were written here, in code,
##   by hand -- the same thing `toddler_view.gd` does for the procedural
##   placeholder, applied to a real rig instead of to a pile of primitives. They
##   are a programmer's keyframes and they look like a programmer's keyframes.
## * It is **not** a procedural per-frame sine driven on the model's transform.
##   Nothing here runs in `_process`, and nothing translates or tilts the whole
##   character to imply motion it is not making. That distinction is the one
##   `test_baby_avatar.gd` was written to defend, and it is deliberately kept.
##
## When real clips arrive from an animator they land in `CLIP_SOURCES` next to
## `walk` and `run`, and `merge_into()` skips any name the library already has --
## so an authored `idle` silently wins over this one, with no caller change.
##
## ## Why the angles are written in SKELETON space
##
## A bone's local frame is whatever the rig author left it in: this skeleton's
## bones run along their own local +Y, with rest rotations up to 3 radians
## (`RightShoulder` is at -3.09 about Y). Writing "tilt the head 8 degrees" as a
## local-axis rotation therefore means guessing which local axis is sideways for
## that particular bone, and getting it wrong is invisible until it is rendered --
## `toddler_view.gd`'s smile-that-shipped-as-a-frown, again.
##
## So every angle below is expressed about a SKELETON-space axis (`NOD`, `TURN`,
## `TILT`) and converted into the bone's parent frame by `_bone_pose()` using the
## bone's own global rest. "Nod 8 degrees" means the same thing for the head, the
## neck and the spine, and adding a bone to a clip costs no derivation.
##
## The axis conventions, derived from the rest pose rather than assumed:
## `LeftUpLeg` sits at x = +9.05 and `RightUpLeg` at x = -10.40, so the
## character's own left is skeleton **+X**; the export faces **+Z** (the wrapper
## turns it 180 degrees afterwards) and up is **+Y**. Therefore
##
##   * `NOD`  = +X. A positive rotation carries +Y toward +Z.
##   * `TURN` = +Y. A positive rotation carries +Z toward +X.
##   * `TILT` = +Z. A positive rotation carries +X toward +Y.
##
## What that MEANS depends on which way the bone points, and this is the one
## place in the file where a sign can be got wrong invisibly -- so it is worked
## out here once, per limb, rather than re-derived at each keyframe:
##
## | bone           | points | `NOD` positive | `TILT` positive          |
## |----------------|--------|----------------|--------------------------|
## | head, spine    | up     | nods DOWN      | tips onto the RIGHT ear  |
## | arm, forearm   | down   | swings BACK    | swings toward the LEFT   |
## | shoulder (L)   | +X     | --             | LIFTS the left shoulder  |
## | shoulder (R)   | -X     | --             | drops the right shoulder |
##
## So, as helpers for reading the clips below:
##
##   * **an arm reaches FORWARD on a NEGATIVE `NOD`.** The first pass of this file
##     had every reach positive, and rendering it showed a fussing child with both
##     arms behind him like a tiny waiter. Fixed by looking, per the art bible.
##   * `[TILT, side * n]` swings an arm ACROSS the chest (inward);
##     `[TILT, -side * n]` swings it OUT away from the body, and raises BOTH
##     shoulders when applied to the shoulder bones.
##
## ## Units
##
## This rig's bones are in CENTIMETRES under an `Armature` node carrying a 0.01
## conversion (the same trap `meshy_baby_v01.json` documents for sockets). One
## bone unit is therefore 0.01 m of model, which the wrapper then scales by
## ~0.459 to reach a 0.78 m child: **1 bone unit ~= 4.6 mm on screen.** Every
## translation below is small for that reason, not by timidity.
##
## Skeleton +Y = 0 IS THE FLOOR, exactly. Worth writing down because `_sleep()`
## depends on it: the wrapper recentres the GLB by half its own height and then
## lifts the holder by the same amount, so the two cancel and a bone at y = 0
## renders at the wrapper's origin. Measured, not assumed -- the toe bones sit at
## y = 3.75 and the hips at y = 50.05, which at 4.59 mm a unit is a 23 cm hip
## height on a 78 cm child.
##
## ## How big is legible
##
## **Every amplitude in this file was raised on 2026-09-20, after rendering the
## reactions at the real gameplay framing** (`docs/shots/bunny_*_near_before.png`
## against `_after`). The camera cannot get closer than
## `camera_framing.gd::FOCUS_MIN_DISTANCE` (1.9 m) and Bunny is 0.78 m tall, so
## in a 1334x750 frame he is about 230 px and his whole forearm is about 25 px.
## The first pass's fuss rocked the hips 3.5 degrees; at that size the difference
## between it and the idle is under two pixels, which is not a reaction, it is a
## rounding error. The rule that came out of looking:
##
##   * a rotation under about 10 degrees on a limb is invisible at this framing;
##   * a reach must actually ARRIVE -- a hand that stops at the chest reads as a
##     shrug, not as eating, and the first `eat` did exactly that;
##   * silhouette beats detail. What survives 230 px is where the arms are
##     against the background, not what the hands are doing.
##
## None of which means fast. This is a gentle game for a three-year-old: the
## poses are bigger, the timings are not, and nothing gained a shake or a jitter.

## Skeleton-space rotation axes. See the class doc for the derivation.
const NOD := Vector3(1.0, 0.0, 0.0)
const TURN := Vector3(0.0, 1.0, 0.0)
const TILT := Vector3(0.0, 0.0, 1.0)

## Bones this file addresses. Named rather than indexed so a re-rig that reorders
## the skeleton still works, and so a missing bone is skipped instead of crashing.
const HIPS: String = "Hips"
const SPINE_LOW: String = "Spine02"    # LOWEST -- see meshy_baby_v01.json's note
const SPINE_MID: String = "Spine01"
const SPINE_TOP: String = "Spine"
const NECK: String = "neck"
const HEAD: String = "Head"
const SHOULDER_L: String = "LeftShoulder"
const SHOULDER_R: String = "RightShoulder"
const ARM_L: String = "LeftArm"
const ARM_R: String = "RightArm"
const FOREARM_L: String = "LeftForeArm"
const FOREARM_R: String = "RightForeArm"
const HAND_L: String = "LeftHand"
const HAND_R: String = "RightHand"
const THIGH_L: String = "LeftUpLeg"
const THIGH_R: String = "RightUpLeg"
const SHIN_L: String = "LeftLeg"
const SHIN_R: String = "RightLeg"

## The clips this file authors, and the semantic actions they answer to through
## `animation_player_action_driver.gd`'s `ACTION_CLIPS` table:
##
## | clip        | semantic action | when Bunny shows it                     |
## |-------------|-----------------|-----------------------------------------|
## | `idle`      | `idle`          | content, standing about                 |
## | `fuss`      | (none)          | a real unmet need -- see `child_life.gd`|
## | `eat`       | `eat`           | being fed a spoon of something          |
## | `drink`     | `drink`         | being given the bottle                  |
## | `celebrate` | `celebrate`     | just been cared for                     |
## | `sleep`     | `sleep`         | bedtime -- see `_sleep()`               |
const CLIP_IDLE: String = "idle"
const CLIP_FUSS: String = "fuss"
const CLIP_EAT: String = "eat"
const CLIP_DRINK: String = "drink"
const CLIP_CELEBRATE: String = "celebrate"
const CLIP_SLEEP: String = "sleep"
const CLIP_CARRIED: String = "carried"

const CLIP_NAMES: Array[String] = [
	CLIP_IDLE, CLIP_FUSS, CLIP_EAT, CLIP_DRINK, CLIP_CELEBRATE, CLIP_SLEEP, CLIP_CARRIED,
]

## How far the back of a sleeping child sits above the floor, in bone units
## (~4.6 mm each), so ~5.5 cm. Used by `_sleep()` together with the hips' own
## measured rest height -- the drop is DERIVED from the rig rather than typed in,
## so a re-rig with a different hip height still lands the child on the floor
## instead of sinking it through one or floating it above one.
const LYING_CLEARANCE: float = 12.0


## Adds every clip this file authors to `library`, addressed against `prefix`
## (the `AnimationPlayer`-relative path of the `Skeleton3D`, e.g.
## `Armature/Skeleton3D`).
##
## **A name already in the library always wins.** That is what makes this a
## stopgap rather than a fixture: the day an animator delivers `idle.glb` it is
## merged by `CLIP_SOURCES` first and this file quietly stops contributing one.
static func merge_into(library: AnimationLibrary, skeleton: Skeleton3D, prefix: String) -> Array:
	var added: Array = []
	if library == null or skeleton == null:
		return added
	for clip_name: String in CLIP_NAMES:
		if library.has_animation(clip_name):
			continue
		var animation: Animation = build(clip_name, skeleton, prefix)
		if animation == null:
			continue
		library.add_animation(clip_name, animation)
		added.append(clip_name)
	return added


## One clip by name, or null. Public so a test can assert the tracks without
## instantiating 14,000 triangles of baby.
static func build(clip_name: String, skeleton: Skeleton3D, prefix: String) -> Animation:
	match clip_name:
		CLIP_IDLE:
			return _idle(skeleton, prefix)
		CLIP_FUSS:
			return _fuss(skeleton, prefix)
		CLIP_EAT:
			return _eat(skeleton, prefix)
		CLIP_DRINK:
			return _drink(skeleton, prefix)
		CLIP_CELEBRATE:
			return _celebrate(skeleton, prefix)
		CLIP_SLEEP:
			return _sleep(skeleton, prefix)
		CLIP_CARRIED:
			return _carried(skeleton, prefix)
		_:
			return null


# ---------------------------------------------------------------------------
# The clips
# ---------------------------------------------------------------------------

## **Alive, not busy.** A breath that lifts the chest and the hips, a head that
## drifts and then looks slowly across the room and back, and arms that follow a
## beat behind. 5.2 s so the look-around does not read as a tic.
##
## There is no blink, and there is no eyelid bone to blink with: this character's
## face is painted into the albedo and the rig ends at `headfront`. Adding one
## would mean animating a UV or swapping a texture, which is a different piece of
## work; `toddler_view.gd` blinks because it has geometry for eyes and this model
## does not. Said here rather than left for someone to discover.
static func _idle(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _looping(5.2)
	var breathe_in: float = 1.3
	var breathe_out: float = 3.9

	# The breath. Split across the three spine bones so the whole torso swells
	# slightly rather than one joint hinging.
	_bone(animation, skeleton, prefix, SPINE_LOW, [
		[0.0, [[NOD, 1.2]]], [breathe_in, [[NOD, -1.0]]],
		[breathe_out, [[NOD, 0.9]]], [5.2, [[NOD, 1.2]]]])
	_bone(animation, skeleton, prefix, SPINE_MID, [
		[0.0, [[NOD, 0.8]]], [breathe_in, [[NOD, -1.4]]],
		[breathe_out, [[NOD, 0.6]]], [5.2, [[NOD, 0.8]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [
		[0.0, [[NOD, 0.6], [TILT, 0.8]]], [breathe_in, [[NOD, -1.8], [TILT, -0.6]]],
		[breathe_out, [[NOD, 0.4], [TILT, 1.0]]], [5.2, [[NOD, 0.6], [TILT, 0.8]]]])

	# The look-around. Held at each end, because a head that sweeps continuously
	# reads as a security camera; a child looks, stops, and looks back.
	_bone(animation, skeleton, prefix, NECK, [
		[0.0, [[TURN, 0.0], [NOD, 1.0]]],
		[1.6, [[TURN, 5.0], [NOD, 0.0]]],
		[2.9, [[TURN, 4.0], [NOD, 0.0]]],
		[4.0, [[TURN, -4.0], [NOD, 1.5]]],
		[5.2, [[TURN, 0.0], [NOD, 1.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[TURN, 0.0], [TILT, 2.0], [NOD, 0.0]]],
		[1.6, [[TURN, 13.0], [TILT, -2.5], [NOD, -1.5]]],
		[2.9, [[TURN, 11.0], [TILT, -3.0], [NOD, 0.5]]],
		[4.0, [[TURN, -9.0], [TILT, 3.5], [NOD, 1.0]]],
		[5.2, [[TURN, 0.0], [TILT, 2.0], [NOD, 0.0]]]])

	# Arms hang and sway, a beat behind the breath. Small: a toddler standing
	# still does not semaphore.
	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, _arm(side), [
			[0.0, [[NOD, -1.5], [TILT, -side * 1.5]]],
			[1.9, [[NOD, -4.0], [TILT, -side * 3.5]]],
			[4.3, [[NOD, 0.5], [TILT, -side * 0.5]]],
			[5.2, [[NOD, -1.5], [TILT, -side * 1.5]]]])
		_bone(animation, skeleton, prefix, _forearm(side), [
			[0.0, [[NOD, -4.0]]], [2.3, [[NOD, -9.0]]], [5.2, [[NOD, -4.0]]]])

	# The weight shift, and the breath reaching the hips. 0.5 bone units is about
	# 2 mm on screen -- visible as life, invisible as a bounce.
	_hips(animation, skeleton, prefix, [
		[0.0, [0.0, [[TILT, 0.0]]]],
		[breathe_in, [0.5, [[TILT, -0.8]]]],
		[breathe_out, [-0.2, [[TILT, 0.9]]]],
		[5.2, [0.0, [[TILT, 0.0]]]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


## **Bunny is not comfortable.** Hands drawn up to the chest, shoulders lifted,
## chin tucked down, and a restless rock from foot to foot.
##
## Short (1.5 s) and looping, so `child_life.gd` can drive its PACE from the real
## hunger value: the same clip played faster reads as more urgent, which is a
## gradient a four-year-old understands without a bar, a number or a red X.
##
## **Doubled on 2026-09-20, because it did not read.** The first pass rocked the
## hips 3.5 degrees and shook the head 7. `docs/shots/bunny_hungry_near_before.png`
## and `bunny_content_near_before.png` are those two states at the real framing:
## put side by side they are the same picture, and "is Bunny all right?" is the
## one question the body is there to answer. Everything below is roughly twice
## the size it was, plus two things that were missing entirely -- the hips step
## sideways over the supporting foot, and the knees take the weight -- because at
## 230 px it is the SILHOUETTE that carries a reaction, and a rock that never
## moves the outline is a rock the player cannot see.
##
## What deliberately did NOT change is the timing. 1.5 s per sway is a slow,
## heavy shift, not a fidget, and the clip gained no shake, no vibration and no
## extra beat: a bigger pose at the same speed reads as unhappy, the same pose
## faster reads as agitated, and this is a game for a three-year-old.
static func _fuss(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _looping(1.5)

	# The rock. Opposite tilts at the hips and the low spine so Bunny sways over
	# his feet instead of leaning like a felled tree -- and the hips now TRANSLATE
	# with the lean (2.4 bone units, ~11 mm), which is what actually moves the
	# outline. A pure rotation about a hip joint barely moves the silhouette at
	# all; shifting the weight onto one foot moves the whole child.
	_hips(animation, skeleton, prefix, [
		[0.0, [Vector3(2.4, -1.4, 0.0), [[TILT, 7.0], [TURN, -6.0]]]],
		[0.75, [Vector3(-2.4, -1.4, 0.0), [[TILT, -7.0], [TURN, 6.0]]]],
		[1.5, [Vector3(2.4, -1.4, 0.0), [[TILT, 7.0], [TURN, -6.0]]]]])
	# The lean stays small on purpose, and this is the one number that was NOT
	# raised. The bedroom camera looks DOWN on Bunny, so every degree of forward
	# lean is a degree of his face the player loses -- an earlier pass leaned 13
	# degrees across the three spine bones and rendered as the top of a head.
	# Seen in `docs/shots/`, not in an assertion.
	_bone(animation, skeleton, prefix, SPINE_LOW, [
		[0.0, [[TILT, -6.0], [NOD, 2.0]]],
		[0.75, [[TILT, 6.0], [NOD, 2.0]]],
		[1.5, [[TILT, -6.0], [NOD, 2.0]]]])
	_bone(animation, skeleton, prefix, SPINE_MID, [
		[0.0, [[TILT, -2.5], [NOD, 2.0]]],
		[0.75, [[TILT, 2.5], [NOD, 2.0]]],
		[1.5, [[TILT, -2.5], [NOD, 2.0]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [[0.0, [[NOD, 1.0]]]])

	# The knees take the weight. Toddlers do not stand on locked legs when they
	# are unhappy about something, and a leg that bends is 30 px of silhouette
	# that the arms cannot supply. Small: the feet are not animated and must stay
	# on the floor, so the hips drop 1.4 units to pay for the bend rather than
	# the shins pushing the feet through it.
	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, _thigh(side), [
			[0.0, [[NOD, -7.0 - side * 4.0]]],
			[0.75, [[NOD, -7.0 + side * 4.0]]],
			[1.5, [[NOD, -7.0 - side * 4.0]]]])
		_bone(animation, skeleton, prefix, _shin(side), [
			[0.0, [[NOD, 13.0 + side * 6.0]]],
			[0.75, [[NOD, 13.0 - side * 6.0]]],
			[1.5, [[NOD, 13.0 + side * 6.0]]]])

	# The head shake, twice the swing it had -- and the chin now comes UP rather
	# than tucking down, which is a reversal and worth the paragraph.
	#
	# The tuck existed to tell `fuss` from `celebrate`: one looked at the floor,
	# the other at you. The FACE now tells them apart instead
	# (`baby_face_moods.gd` -- half-lidded eyes and a downturned mouth against
	# closed arches and an open smile), so the tuck is paying for nothing and
	# costing a great deal: the bedroom camera looks DOWN on a 0.78 m child, so
	# six degrees of tuck is most of the expression hidden behind a forehead.
	# Rendered at +6, at +2 and at -5; -5 is the only one where you can see what
	# he is feeling, and a hungry toddler looks UP at the person who feeds it.
	_bone(animation, skeleton, prefix, NECK, [[0.0, [[NOD, -2.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[NOD, -5.0], [TURN, -14.0], [TILT, 8.0]]],
		[0.4, [[NOD, -4.0], [TURN, 14.0], [TILT, -8.0]]],
		[0.9, [[NOD, -5.0], [TURN, -12.0], [TILT, 8.0]]],
		[1.5, [[NOD, -5.0], [TURN, -14.0], [TILT, 8.0]]]])

	# Shoulders up around the ears, both hands held in front of the TUMMY.
	#
	# They were at the chin in an earlier pass and had to come down, for a reason
	# that is only visible with both clips side by side: hands-at-the-chin is
	# almost exactly `celebrate`'s silhouette, and the two states a child most
	# needs to tell apart -- "I need something" and "thank you" -- read the same
	# in a still frame. Hands low and drawn in also happens to be what a hungry
	# toddler does, so the readable answer is the truthful one. Raising the
	# amplitude does not change that: the elbows now fold far enough to be an
	# unmistakable shape, and the hands still stop at the tummy.
	#
	# The inward `TILT` is the one number here that had to come back DOWN after a
	# render. At 19 on the arm and 34 on the forearm the hands cross far enough
	# over the belly that from the three-quarter angle the attention turn puts
	# him at, the far hand pushes through his own hip and the near one lands on
	# his cheek. Hands in FRONT of the tummy, not across it.
	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, _shoulder(side), [
			[0.0, [[TILT, -side * 10.0]]],
			[0.75, [[TILT, -side * 14.0]]],
			[1.5, [[TILT, -side * 10.0]]]])
		_bone(animation, skeleton, prefix, _arm(side), [
			[0.0, [[NOD, -32.0], [TILT, side * 9.0]]],
			[0.75, [[NOD, -39.0], [TILT, side * 12.0]]],
			[1.5, [[NOD, -32.0], [TILT, side * 9.0]]]])
		_bone(animation, skeleton, prefix, _forearm(side), [
			[0.0, [[NOD, -62.0], [TILT, side * 20.0]]],
			[0.75, [[NOD, -70.0], [TILT, side * 23.0]]],
			[1.5, [[NOD, -62.0], [TILT, side * 20.0]]]])
		_bone(animation, skeleton, prefix, _hand(side), [[0.0, [[NOD, -18.0]]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


## **Being fed.** Right hand up to the mouth, head dipped a little to meet it,
## two small chews, hand down. One-shot: it is an act, not a state.
##
## **The reach was aimed at the wrong place, and then it could not get there.**
##
## The first pass had the hand stop at chest height and it read as a shrug
## (`docs/shots/bunny_eating_near_before.png`). Raising it by eye made it worse
## -- the arm went out sideways -- so the angles below were SOLVED instead:
## forward kinematics down `Hips -> ... -> RightHand`, using this file's own
## `_bone_pose()`, searched over the four angles for the pose that gets the hand
## closest to the mouth socket.
##
## **That search turned up a fact about the model worth writing down: this
## character cannot reach its own mouth.** The shoulder-to-mouth distance is
## 41.7 bone units and the whole arm, hand socket included, is 33. It is the
## chibi head that does it -- 1:3.5 head-to-height, per
## `CHARACTER_AGE_STAGES.md` -- and no keyframe fixes it. So the clip aims for
## the mouth and stops where the arm stops: hand at chin height, 12 units off
## centre, in front of the face. The head then dips the last little way, which
## is what the original comment always claimed it was doing.
##
## The elbow goes OUT while the forearm comes IN, which looks odd written down
## and is exactly how a small child holds something up to its face.
static func _eat(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _once(2.0)

	# The leading hand. `-side` on the arm is outward, `+side` on the forearm is
	# inward across the face -- see the sign table in the class doc.
	_bone(animation, skeleton, prefix, _arm(1), [
		[0.0, [[NOD, -2.0], [TILT, 4.0]]],
		[0.5, [[NOD, -90.0], [TILT, -32.0]]],
		[1.5, [[NOD, -94.0], [TILT, -34.0]]],
		[2.0, [[NOD, -2.0], [TILT, 4.0]]]])
	_bone(animation, skeleton, prefix, _forearm(1), [
		[0.0, [[NOD, -6.0]]], [0.5, [[NOD, -32.0], [TILT, 46.0]]],
		[1.5, [[NOD, -34.0], [TILT, 48.0]]], [2.0, [[NOD, -6.0]]]])
	# The other hand comes half way up too. Not symmetry for its own sake: the
	# bedroom camera can be on either side of Bunny, and a one-armed reach is
	# invisible from the wrong one -- which is exactly how the first render of
	# this clip looked, a child apparently doing nothing at all.
	_bone(animation, skeleton, prefix, _arm(-1), [
		[0.0, [[NOD, -3.0], [TILT, -4.0]]],
		[0.6, [[NOD, -54.0], [TILT, 20.0]]],
		[1.5, [[NOD, -58.0], [TILT, 22.0]]],
		[2.0, [[NOD, -3.0], [TILT, -4.0]]]])
	_bone(animation, skeleton, prefix, _forearm(-1), [
		[0.0, [[NOD, -8.0]]], [0.6, [[NOD, -40.0], [TILT, -34.0]]],
		[1.5, [[NOD, -42.0], [TILT, -36.0]]], [2.0, [[NOD, -8.0]]]])

	# The chew. There is no jaw bone, so this is the head bobbing on the neck --
	# which is what a chewing toddler's head does anyway, and is the only thing
	# this rig can honestly show. It is NOT a mouth opening.
	#
	# The bob is small, and smaller than the first pass's, for the reason the
	# fuss's chin tuck shrank: the camera is above him and the face now carries
	# a repainted mood, so a deep dip trades an expression for a forehead.
	_bone(animation, skeleton, prefix, NECK, [[0.0, [[NOD, 1.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[NOD, 0.0]]], [0.5, [[NOD, 5.0]]], [0.75, [[NOD, 0.0]]],
		[1.0, [[NOD, 5.0]]], [1.25, [[NOD, 0.0]]], [1.5, [[NOD, 4.0]]],
		[2.0, [[NOD, 0.0]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [
		[0.0, [[NOD, 0.0]]], [0.6, [[NOD, 5.0]]], [1.5, [[NOD, 5.0]]], [2.0, [[NOD, 0.0]]]])
	_hips(animation, skeleton, prefix, [[0.0, [0.0, []]], [0.9, [0.6, []]], [2.0, [0.0, []]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


## **The bottle.** Both hands up together and the head tipped BACK -- the tip is
## the one cue that separates drinking from eating at a glance, which is the same
## reasoning `toddler_view.gd` records for its own `drink`.
static func _drink(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _once(2.2)

	# Both hands, to the same solved reach `_eat()` uses on one -- see its doc for
	# why the elbow goes out while the forearm comes in, and for the measurement
	# that says this character's arms cannot reach its own mouth.
	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, _arm(side), [
			[0.0, [[NOD, -2.0], [TILT, side * 4.0]]],
			[0.55, [[NOD, -84.0], [TILT, -side * 30.0]]],
			[1.7, [[NOD, -88.0], [TILT, -side * 32.0]]],
			[2.2, [[NOD, -2.0], [TILT, side * 4.0]]]])
		_bone(animation, skeleton, prefix, _forearm(side), [
			[0.0, [[NOD, -6.0]]],
			[0.55, [[NOD, -38.0], [TILT, side * 46.0]]],
			[1.7, [[NOD, -40.0], [TILT, side * 48.0]]],
			[2.2, [[NOD, -6.0]]]])

	# Negative NOD is chin up: the head tips back over the bottle. This is the
	# ONE cue that separates drinking from eating at a glance -- `eat` dips the
	# chin DOWN by the same sort of angle -- so it is worth being generous with.
	_bone(animation, skeleton, prefix, NECK, [
		[0.0, [[NOD, 0.0]]], [0.65, [[NOD, -9.0]]], [1.7, [[NOD, -10.0]]], [2.2, [[NOD, 0.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[NOD, 0.0]]], [0.65, [[NOD, -17.0]]], [1.7, [[NOD, -20.0]]], [2.2, [[NOD, 0.0]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [
		[0.0, [[NOD, 0.0]]], [0.65, [[NOD, -5.0]]], [1.7, [[NOD, -5.0]]], [2.2, [[NOD, 0.0]]]])
	_hips(animation, skeleton, prefix, [[0.0, [0.0, []]], [1.1, [0.8, []]], [2.2, [0.0, []]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


## **Just been looked after.** Arms up and out, chin up, and two bounces on the
## hips. The project has no failure state, so this is the only shape "you did it"
## has, and it has to be legible from across a bedroom at iPad size.
static func _celebrate(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _looping(1.8)

	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, _shoulder(side), [
			[0.0, [[TILT, -side * 4.0]]], [0.35, [[TILT, -side * 12.0]]],
			[1.2, [[TILT, -side * 12.0]]], [1.8, [[TILT, -side * 4.0]]]])
		# Out and UP, not forward: `-side` swings each arm away from the body, which
		# is what makes a raised arm read as delight rather than as a reach.
		# **Up and FORWARD, not out to the sides.** Both earlier attempts were
		# lateral, and both were rejected by looking at the render:
		#
		#   * 64 degrees folded at the elbow read as a shrug;
		#   * 88 degrees tore the shoulder open -- this rig's weights are a repaired
		#     auto-rig, and a near-horizontal lateral raise smeared the deltoid
		#     across the character's own face.
		#
		# A forward reach with a bent elbow stays inside the range the weights
		# survive, and it is the gesture a real toddler makes at the person who
		# just helped them: arms up, pick me up.
		# **Raised from -62 to -84 on 2026-09-20.** At -62 the hands come up only
		# to hip height and `docs/shots/bunny_happy_near_before.png` reads as a
		# shrug rather than as "pick me up". -84 is a near-vertical FORWARD raise,
		# which is inside what the weights survive -- the tearing the earlier pass
		# hit was a LATERAL raise (`TILT`), and the lateral component here is held
		# at 30, below the 64 that first folded badly.
		_bone(animation, skeleton, prefix, _arm(side), [
			[0.0, [[NOD, -2.0], [TILT, -side * 6.0]]],
			[0.35, [[NOD, -78.0], [TILT, -side * 26.0]]],
			[0.9, [[NOD, -84.0], [TILT, -side * 30.0]]],
			[1.2, [[NOD, -78.0], [TILT, -side * 26.0]]],
			[1.8, [[NOD, -2.0], [TILT, -side * 6.0]]]])
		# Only a light elbow bend. Folding it to -56 put both hands over his own
		# face, which is peekaboo, not delight -- and with the shoulder now 22
		# degrees higher there is even less room before that happens, so the
		# elbow OPENS here rather than closing.
		_bone(animation, skeleton, prefix, _forearm(side), [
			[0.0, [[NOD, -6.0]]], [0.35, [[NOD, -14.0], [TILT, -side * 10.0]]],
			[1.2, [[NOD, -18.0], [TILT, -side * 12.0]]], [1.8, [[NOD, -6.0]]]])

	# Chin UP, which is the other half of telling `celebrate` from `fuss` at a
	# glance: one looks at you, the other looks at the floor.
	_bone(animation, skeleton, prefix, NECK, [
		[0.0, [[NOD, 0.0]]], [0.35, [[NOD, -7.0]]], [1.2, [[NOD, -7.0]]], [1.8, [[NOD, 0.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[NOD, 0.0], [TILT, 0.0]]],
		[0.35, [[NOD, -13.0], [TILT, -5.0]]],
		[0.9, [[NOD, -11.0], [TILT, 5.0]]],
		[1.8, [[NOD, 0.0], [TILT, 0.0]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [
		[0.0, [[NOD, 0.0]]], [0.35, [[NOD, -4.0]]], [1.2, [[NOD, -4.0]]], [1.8, [[NOD, 0.0]]]])

	# Two hops. 2.8 bone units is ~13 mm of lift -- still a bounce on the spot
	# and not a jump, because the feet are not animated and must not leave the
	# floor; the knees below absorb the rest so the lift does not read as the
	# whole child being slid upward.
	_hips(animation, skeleton, prefix, [
		[0.0, [0.0, []]], [0.25, [2.8, []]], [0.5, [0.0, []]],
		[0.75, [2.4, []]], [1.0, [0.0, []]], [1.8, [0.0, []]]])
	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, _thigh(side), [
			[0.0, [[NOD, -10.0]]], [0.25, [[NOD, 0.0]]], [0.5, [[NOD, -10.0]]],
			[0.75, [[NOD, -1.0]]], [1.0, [[NOD, -10.0]]], [1.8, [[NOD, -10.0]]]])
		_bone(animation, skeleton, prefix, _shin(side), [
			[0.0, [[NOD, 18.0]]], [0.25, [[NOD, 1.0]]], [0.5, [[NOD, 18.0]]],
			[0.75, [[NOD, 3.0]]], [1.0, [[NOD, 18.0]]], [1.8, [[NOD, 18.0]]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


## **Asleep on his back -- and this is the clip that removes the last pose cut in
## the game.**
##
## Until now `bedtime` was the one activity that left the rigged model, because
## "lying down is a whole-body pose no arm animation implies" -- true, and it was
## the right call while the alternative was inventing one. What it cost is only
## obvious once it is rendered: `docs/shots/bunny_sleepy_near_before.png` is the
## unrigged supine export, and it is **not the same child**. Different hair,
## different nappy, different proportions, a 373,090-triangle statue that cannot
## breathe. A player watching Bunny go to bed watched Bunny be replaced.
##
## A whole-body pose is exactly what a root-bone rotation IS, so it turns out the
## rig can say this after all:
##
##   * `NOD -90` at the hips tips the spine from +Y to -Z: flat on his back, face
##     to the ceiling. Every bone below the hips comes with it, so this is one
##     rigid rotation of the whole child and the skin cannot tear on it.
##   * `TURN 90` then swings him about the vertical so he lies ACROSS the frame
##     rather than pointing away from a camera that is fixed at +Z. The same
##     framing decision the unrigged export's own `rotationDeg` was making.
##   * the hips then TRANSLATE down by their own measured rest height, so his
##     back is on the floor rather than his body floating at hip level. Derived
##     from `get_bone_global_rest()`, not typed in -- see `LYING_CLEARANCE`.
##
## The rest is what makes it a sleeping child rather than a felled one: knees
## dropped open the way a baby's are, arms loose and turned out, head rolled to
## one side, and a slow breath at 5.6 s a cycle -- deliberately slower than the
## idle's 5.2 s, because the one thing everybody can read across a room is that
## a sleeping thing breathes more slowly than a waking one.
##
## Looping, and a `sleep` name so `character_action_driver.gd` picks it up: the
## action vocabulary already lists `sleep` as a HOLD posture with `wake` as its
## release, and `can_play_action("sleep")` starts answering true by itself.
static func _sleep(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _looping(5.6)
	var lay: Array = [[NOD, -90.0], [TURN, 90.0]]

	# Measured off the rig. The hips sit 50.05 units up on today's skeleton; a
	# re-rig at a different height still lands because the number is read, never
	# written down.
	var hips: int = skeleton.find_bone(HIPS)
	var drop: float = 0.0
	if hips != -1:
		drop = LYING_CLEARANCE - skeleton.get_bone_global_rest(hips).origin.y
	_hips(animation, skeleton, prefix, [
		[0.0, [Vector3(0.0, drop, 0.0), lay]],
		[2.8, [Vector3(0.0, drop + 0.5, 0.0), lay]],
		[5.6, [Vector3(0.0, drop, 0.0), lay]]])

	# The breath. Three spine bones again, and smaller than the idle's: a
	# sleeping chest moves, it does not heave.
	_bone(animation, skeleton, prefix, SPINE_LOW, [
		[0.0, [[NOD, 1.0]]], [2.8, [[NOD, -0.8]]], [5.6, [[NOD, 1.0]]]])
	_bone(animation, skeleton, prefix, SPINE_MID, [
		[0.0, [[NOD, 0.8]]], [2.8, [[NOD, -1.1]]], [5.6, [[NOD, 0.8]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [
		[0.0, [[NOD, 0.6]]], [2.8, [[NOD, -1.4]]], [5.6, [[NOD, 0.6]]]])

	# Head rolled a LITTLE onto one ear. The axes are always resolved against the
	# bone's own rest, so once the body is supine `TILT` -- ear to shoulder when
	# standing -- turns the face sideways in plan view, and `TURN` rolls it about
	# the head-to-toe axis. Rendered at 13 degrees of tilt and at 4: 13 pointed
	# the face away from a camera that is above and in front of him, and a
	# sleeping face nobody can see is the whole feature thrown away.
	_bone(animation, skeleton, prefix, NECK, [[0.0, [[NOD, 2.0], [TILT, 3.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[NOD, 4.0], [TILT, 4.0], [TURN, -8.0]]],
		[2.8, [[NOD, 5.0], [TILT, 5.0], [TURN, -9.0]]],
		[5.6, [[NOD, 4.0], [TILT, 4.0], [TURN, -8.0]]]])

	# Arms loose and turned out, elbows softly bent, one a little higher than the
	# other -- a sleeping child is not symmetrical.
	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, _shoulder(side), [
			[0.0, [[TILT, -side * 5.0]]]])
		_bone(animation, skeleton, prefix, _arm(side), [
			[0.0, [[NOD, -8.0 + side * 6.0], [TILT, -side * 22.0]]],
			[2.8, [[NOD, -10.0 + side * 6.0], [TILT, -side * 24.0]]],
			[5.6, [[NOD, -8.0 + side * 6.0], [TILT, -side * 22.0]]]])
		_bone(animation, skeleton, prefix, _forearm(side), [
			[0.0, [[NOD, -30.0 - side * 8.0], [TILT, -side * 10.0]]]])
		_bone(animation, skeleton, prefix, _hand(side), [[0.0, [[NOD, -10.0]]]])

		# Knees dropped open, and only just. A negative `NOD` on a leg swings it
		# FORWARD, which once he is on his back means UPWARD -- so the same number
		# that is a relaxed stance standing up is knees-to-the-ceiling lying down.
		# 16 rendered as a child doing sit-ups; 7 is a baby asleep.
		_bone(animation, skeleton, prefix, _thigh(side), [
			[0.0, [[NOD, -7.0], [TILT, -side * 8.0]]]])
		_bone(animation, skeleton, prefix, _shin(side), [
			[0.0, [[NOD, 15.0]]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


# ---------------------------------------------------------------------------
# Track construction
# ---------------------------------------------------------------------------

## **Every clip must say something about every bone, or it inherits the last
## one.** An `AnimationPlayer` only writes the properties a clip has tracks for.
## Without this, `idle` played straight out of `walk` would idle with the legs
## frozen mid-stride -- the exact failure `toddler_view.gd::_baseline()` records,
## and it is worse here because `walk` drives all 24 bones.
##
## So every bone the clip has not already keyed gets one rest key at t = 0.
## **Held.** How a small child sits in an adult's arms, facing out: knees drawn
## up and a little apart, shins hanging, hands resting low in front, and a slow
## look from side to side at the room going past. Looping, so it can be held
## for as long as the carry lasts.
##
## Everything here is a static pose plus breath, and that is the point -- this
## clip's job is to NOT be `idle` or `fuss`: a child carried across a room in
## his standing pose, feet paddling at nothing 40 cm above the floor, is the
## single most obvious way a carry reads as fake. The knees come up 78 degrees
## because from the room camera the raised knees ARE the silhouette that says
## "carried" -- lower, and he reads as standing on her arms.
##
## Signs follow `_fuss()`: a negative NOD on a thigh swings it forward, a
## positive NOD on the shin folds the knee.
static func _carried(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _looping(3.6)
	var breathe_in: float = 1.0
	var breathe_out: float = 2.6

	# A slight lean back into the arms that hold him, and the breath.
	_hips(animation, skeleton, prefix, [
		[0.0, [0.0, [[NOD, 6.0]]]],
		[breathe_in, [0.3, [[NOD, 5.5]]]],
		[breathe_out, [-0.1, [[NOD, 6.3]]]],
		[3.6, [0.0, [[NOD, 6.0]]]]])
	_bone(animation, skeleton, prefix, SPINE_LOW, [
		[0.0, [[NOD, 1.0]]], [breathe_in, [[NOD, -0.8]]],
		[breathe_out, [[NOD, 0.8]]], [3.6, [[NOD, 1.0]]]])
	_bone(animation, skeleton, prefix, SPINE_MID, [
		[0.0, [[NOD, 0.6]]], [breathe_in, [[NOD, -1.0]]],
		[breathe_out, [[NOD, 0.5]]], [3.6, [[NOD, 0.6]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [[0.0, [[NOD, -1.5]]]])

	# Looking about, held at each end, as `_idle()` does.
	_bone(animation, skeleton, prefix, NECK, [[0.0, [[NOD, -2.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[TURN, 0.0], [NOD, -3.0]]],
		[1.1, [[TURN, 12.0], [NOD, -4.0], [TILT, -2.0]]],
		[1.9, [[TURN, 10.0], [NOD, -3.0], [TILT, -2.0]]],
		[2.9, [[TURN, -11.0], [NOD, -4.0], [TILT, 2.0]]],
		[3.6, [[TURN, 0.0], [NOD, -3.0]]]])

	for side: int in [-1, 1]:
		# Knees up and a little apart; shins hang.
		_bone(animation, skeleton, prefix, _thigh(side), [
			[0.0, [[NOD, -78.0], [TILT, -side * 10.0]]],
			[1.8, [[NOD, -76.0], [TILT, -side * 11.0]]],
			[3.6, [[NOD, -78.0], [TILT, -side * 10.0]]]])
		_bone(animation, skeleton, prefix, _shin(side), [
			[0.0, [[NOD, 82.0]]], [1.8, [[NOD, 78.0]]], [3.6, [[NOD, 82.0]]]])
		# Hands resting in front of his tummy, on the arms holding him -- inward
		# (`TILT side*`, as `_fuss()` brings them in), never out to the sides:
		# rendered with an outward tilt he read as a child cheering, arms spread
		# at shoulder height, which is not what being carried looks like.
		_bone(animation, skeleton, prefix, _shoulder(side), [[0.0, [[TILT, -side * 3.0]]]])
		_bone(animation, skeleton, prefix, _arm(side), [
			[0.0, [[NOD, -30.0], [TILT, side * 6.0]]],
			[1.8, [[NOD, -33.0], [TILT, side * 7.0]]],
			[3.6, [[NOD, -30.0], [TILT, side * 6.0]]]])
		_bone(animation, skeleton, prefix, _forearm(side), [
			[0.0, [[NOD, -48.0], [TILT, side * 16.0]]],
			[1.8, [[NOD, -52.0], [TILT, side * 17.0]]],
			[3.6, [[NOD, -48.0], [TILT, side * 16.0]]]])
		_bone(animation, skeleton, prefix, _hand(side), [[0.0, [[NOD, -14.0]]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


static func _rest_the_others(animation: Animation, skeleton: Skeleton3D, prefix: String) -> void:
	var keyed: Dictionary = {}
	for track: int in range(animation.get_track_count()):
		keyed[String(animation.track_get_path(track)).get_slice(":", 1)] = true
	for index: int in range(skeleton.get_bone_count()):
		var bone: String = skeleton.get_bone_name(index)
		if keyed.has(bone):
			continue
		var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("%s:%s" % [prefix, bone]))
		animation.rotation_track_insert_key(track, 0.0, skeleton.get_bone_rest(index).basis.get_rotation_quaternion())


## One rotation track for one bone. `keys` is `[[time, [[axis, degrees], ...]], ...]`
## with the axes in SKELETON space -- see the class doc.
static func _bone(animation: Animation, skeleton: Skeleton3D, prefix: String,
		bone_name: String, keys: Array) -> void:
	var index: int = skeleton.find_bone(bone_name)
	if index == -1:
		# A re-rig that dropped a bone loses that part of the motion and keeps the
		# rest, rather than taking the whole clip down with it.
		return
	var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath("%s:%s" % [prefix, bone_name]))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for key: Array in keys:
		animation.rotation_track_insert_key(track, float(key[0]),
				_bone_pose(skeleton, index, key[1] as Array))


## The hips carry both the breath/bounce (position) and the weight shift
## (rotation), so they get their own helper. `keys` is
## `[[time, [offset, [[axis, degrees], ...]]], ...]`, where `offset` is either a
## plain float -- a vertical lift, which is all most of these clips want -- or a
## full `Vector3` in bone units for the two that also step sideways (`fuss`) or
## lay the whole child down (`sleep`).
static func _hips(animation: Animation, skeleton: Skeleton3D, prefix: String,
		keys: Array) -> void:
	var index: int = skeleton.find_bone(HIPS)
	if index == -1:
		return
	var rest: Transform3D = skeleton.get_bone_rest(index)

	var moved: int = animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(moved, NodePath("%s:%s" % [prefix, HIPS]))
	animation.track_set_interpolation_type(moved, Animation.INTERPOLATION_CUBIC)
	var turned: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(turned, NodePath("%s:%s" % [prefix, HIPS]))
	animation.track_set_interpolation_type(turned, Animation.INTERPOLATION_CUBIC)

	for key: Array in keys:
		var at: float = float(key[0])
		var spec: Array = key[1] as Array
		var offset: Vector3 = spec[0] if spec[0] is Vector3 \
				else Vector3(0.0, float(spec[0]), 0.0)
		animation.position_track_insert_key(moved, at, rest.origin + offset)
		animation.rotation_track_insert_key(turned, at,
				_bone_pose(skeleton, index, spec[1] as Array))


## **The one derivation in this file.** Turns "8 degrees about skeleton +X" into
## the quaternion an `Animation` rotation track expects, which is the bone's pose
## *in its parent's frame*.
##
## A bone's local transform `L` gives `G = G_parent * L`. Rotating the bone by `R`
## about its own origin in SKELETON space means `G' = R * G`, so
##
##     L'.basis = G_parent.basis^-1 * R * G_parent.basis * L.basis
##
## which is the same as applying `R` expressed in the parent's frame. So the axis
## is carried into the parent's frame and the rotation is pre-multiplied onto the
## rest. Doing it the other way round -- post-multiplying a local-axis rotation --
## is the mistake that makes a head "nod" sideways on this rig, because
## `RightShoulder`'s rest is nearly a half turn about Y.
static func _bone_pose(skeleton: Skeleton3D, index: int, turns: Array) -> Quaternion:
	var rest: Quaternion = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	if turns.is_empty():
		return rest
	var parent: int = skeleton.get_bone_parent(index)
	var to_parent: Basis = Basis()
	if parent != -1:
		to_parent = skeleton.get_bone_global_rest(parent).basis.orthonormalized().inverse()
	var applied: Quaternion = Quaternion.IDENTITY
	for turn: Array in turns:
		var axis: Vector3 = (to_parent * (turn[0] as Vector3)).normalized()
		applied = Quaternion(axis, deg_to_rad(float(turn[1]))) * applied
	return (applied * rest).normalized()


static func _looping(length: float) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR
	return animation


static func _once(length: float) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_NONE
	return animation


## `side` is -1 for the character's own left, +1 for its right -- the same
## convention `toddler_view.gd` uses, so the two characters read the same way.
static func _arm(side: int) -> String:
	return ARM_L if side < 0 else ARM_R


static func _forearm(side: int) -> String:
	return FOREARM_L if side < 0 else FOREARM_R


static func _hand(side: int) -> String:
	return HAND_L if side < 0 else HAND_R


static func _shoulder(side: int) -> String:
	return SHOULDER_L if side < 0 else SHOULDER_R


static func _thigh(side: int) -> String:
	return THIGH_L if side < 0 else THIGH_R


static func _shin(side: int) -> String:
	return SHIN_L if side < 0 else SHIN_R
