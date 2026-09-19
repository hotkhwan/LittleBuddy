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
const CLIP_IDLE: String = "idle"
const CLIP_FUSS: String = "fuss"
const CLIP_EAT: String = "eat"
const CLIP_DRINK: String = "drink"
const CLIP_CELEBRATE: String = "celebrate"

const CLIP_NAMES: Array[String] = [
	CLIP_IDLE, CLIP_FUSS, CLIP_EAT, CLIP_DRINK, CLIP_CELEBRATE,
]


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
static func _fuss(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _looping(1.5)

	# The rock. Opposite tilts at the hips and the low spine so Bunny sways over
	# his feet instead of leaning like a felled tree.
	_hips(animation, skeleton, prefix, [
		[0.0, [-0.6, [[TILT, 3.5], [TURN, -3.0]]]],
		[0.75, [-0.6, [[TILT, -3.5], [TURN, 3.0]]]],
		[1.5, [-0.6, [[TILT, 3.5], [TURN, -3.0]]]]])
	# The lean is small on purpose. The bedroom camera looks DOWN on Bunny, so
	# every degree of forward lean is a degree of his face the player loses --
	# the first pass leaned 13 degrees across the three spine bones and rendered
	# as the top of a head. Seen in `docs/shots/`, not in an assertion.
	_bone(animation, skeleton, prefix, SPINE_LOW, [
		[0.0, [[TILT, -3.0], [NOD, 1.5]]],
		[0.75, [[TILT, 3.0], [NOD, 1.5]]],
		[1.5, [[TILT, -3.0], [NOD, 1.5]]]])
	_bone(animation, skeleton, prefix, SPINE_MID, [[0.0, [[NOD, 2.0]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [[0.0, [[NOD, 1.5]]]])

	# Chin tucked, head shaking the small unhappy shake.
	_bone(animation, skeleton, prefix, NECK, [[0.0, [[NOD, 2.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[NOD, 3.0], [TURN, -7.0], [TILT, 4.0]]],
		[0.4, [[NOD, 4.0], [TURN, 7.0], [TILT, -4.0]]],
		[0.9, [[NOD, 3.0], [TURN, -6.0], [TILT, 4.0]]],
		[1.5, [[NOD, 3.0], [TURN, -7.0], [TILT, 4.0]]]])

	# Shoulders up around the ears, both hands held in front of the TUMMY.
	#
	# They were at the chin in the first pass and had to come down, for a reason
	# that is only visible with both clips side by side: hands-at-the-chin is
	# almost exactly `celebrate`'s silhouette, and the two states a child most
	# needs to tell apart -- "I need something" and "thank you" -- read the same
	# in a still frame. Hands low and drawn in also happens to be what a hungry
	# toddler does, so the readable answer is the truthful one.
	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, _shoulder(side), [
			[0.0, [[TILT, -side * 7.0]]],
			[0.75, [[TILT, -side * 10.0]]],
			[1.5, [[TILT, -side * 7.0]]]])
		_bone(animation, skeleton, prefix, _arm(side), [
			[0.0, [[NOD, -20.0], [TILT, side * 7.0]]],
			[0.75, [[NOD, -25.0], [TILT, side * 10.0]]],
			[1.5, [[NOD, -20.0], [TILT, side * 7.0]]]])
		_bone(animation, skeleton, prefix, _forearm(side), [
			[0.0, [[NOD, -44.0], [TILT, side * 22.0]]],
			[0.75, [[NOD, -50.0], [TILT, side * 25.0]]],
			[1.5, [[NOD, -44.0], [TILT, side * 22.0]]]])
		_bone(animation, skeleton, prefix, _hand(side), [[0.0, [[NOD, -12.0]]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


## **Being fed.** Right hand up to the mouth, head dipped a little to meet it,
## two small chews, hand down. One-shot: it is an act, not a state.
static func _eat(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _once(2.0)

	_bone(animation, skeleton, prefix, _arm(1), [
		[0.0, [[NOD, -2.0], [TILT, 4.0]]],
		[0.5, [[NOD, -34.0], [TILT, 14.0]]],
		[1.5, [[NOD, -36.0], [TILT, 15.0]]],
		[2.0, [[NOD, -2.0], [TILT, 4.0]]]])
	_bone(animation, skeleton, prefix, _forearm(1), [
		[0.0, [[NOD, -6.0]]], [0.5, [[NOD, -76.0], [TILT, 22.0]]],
		[1.5, [[NOD, -80.0], [TILT, 22.0]]], [2.0, [[NOD, -6.0]]]])
	# The other hand comes half way up too. Not symmetry for its own sake: the
	# bedroom camera can be on either side of Bunny, and a one-armed reach is
	# invisible from the wrong one -- which is exactly how the first render of
	# this clip looked, a child apparently doing nothing at all.
	_bone(animation, skeleton, prefix, _arm(-1), [
		[0.0, [[NOD, -3.0], [TILT, -4.0]]],
		[0.6, [[NOD, -20.0], [TILT, -8.0]]],
		[1.5, [[NOD, -22.0], [TILT, -8.0]]],
		[2.0, [[NOD, -3.0], [TILT, -4.0]]]])
	_bone(animation, skeleton, prefix, _forearm(-1), [
		[0.0, [[NOD, -8.0]]], [0.6, [[NOD, -46.0], [TILT, -12.0]]],
		[1.5, [[NOD, -48.0], [TILT, -12.0]]], [2.0, [[NOD, -8.0]]]])

	# The chew. There is no jaw bone, so this is the head bobbing on the neck --
	# which is what a chewing toddler's head does anyway, and is the only thing
	# this rig can honestly show. It is NOT a mouth opening.
	_bone(animation, skeleton, prefix, NECK, [[0.0, [[NOD, 2.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[NOD, 0.0]]], [0.5, [[NOD, 7.0]]], [0.75, [[NOD, 2.0]]],
		[1.0, [[NOD, 7.0]]], [1.25, [[NOD, 2.0]]], [1.5, [[NOD, 6.0]]],
		[2.0, [[NOD, 0.0]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [
		[0.0, [[NOD, 0.0]]], [0.6, [[NOD, 3.0]]], [1.5, [[NOD, 3.0]]], [2.0, [[NOD, 0.0]]]])
	_hips(animation, skeleton, prefix, [[0.0, [0.0, []]], [0.9, [0.4, []]], [2.0, [0.0, []]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


## **The bottle.** Both hands up together and the head tipped BACK -- the tip is
## the one cue that separates drinking from eating at a glance, which is the same
## reasoning `toddler_view.gd` records for its own `drink`.
static func _drink(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _once(2.2)

	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, _arm(side), [
			[0.0, [[NOD, -2.0], [TILT, side * 4.0]]],
			[0.55, [[NOD, -32.0], [TILT, side * 12.0]]],
			[1.7, [[NOD, -34.0], [TILT, side * 13.0]]],
			[2.2, [[NOD, -2.0], [TILT, side * 4.0]]]])
		_bone(animation, skeleton, prefix, _forearm(side), [
			[0.0, [[NOD, -6.0]]],
			[0.55, [[NOD, -74.0], [TILT, side * 20.0]]],
			[1.7, [[NOD, -78.0], [TILT, side * 20.0]]],
			[2.2, [[NOD, -6.0]]]])

	# Negative NOD is chin up: the head tips back over the bottle.
	_bone(animation, skeleton, prefix, NECK, [
		[0.0, [[NOD, 0.0]]], [0.65, [[NOD, -6.0]]], [1.7, [[NOD, -7.0]]], [2.2, [[NOD, 0.0]]]])
	_bone(animation, skeleton, prefix, HEAD, [
		[0.0, [[NOD, 0.0]]], [0.65, [[NOD, -11.0]]], [1.7, [[NOD, -13.0]]], [2.2, [[NOD, 0.0]]]])
	_bone(animation, skeleton, prefix, SPINE_TOP, [
		[0.0, [[NOD, 0.0]]], [0.65, [[NOD, -3.0]]], [1.7, [[NOD, -3.0]]], [2.2, [[NOD, 0.0]]]])
	_hips(animation, skeleton, prefix, [[0.0, [0.0, []]], [1.1, [0.5, []]], [2.2, [0.0, []]]])

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
		_bone(animation, skeleton, prefix, _arm(side), [
			[0.0, [[NOD, -2.0], [TILT, -side * 6.0]]],
			[0.35, [[NOD, -56.0], [TILT, -side * 32.0]]],
			[0.9, [[NOD, -62.0], [TILT, -side * 36.0]]],
			[1.2, [[NOD, -56.0], [TILT, -side * 32.0]]],
			[1.8, [[NOD, -2.0], [TILT, -side * 6.0]]]])
		# Only a light elbow bend. Folding it to -56 put both hands over his own
		# face, which is peekaboo, not delight.
		_bone(animation, skeleton, prefix, _forearm(side), [
			[0.0, [[NOD, -6.0]]], [0.35, [[NOD, -18.0], [TILT, -side * 12.0]]],
			[1.2, [[NOD, -22.0], [TILT, -side * 14.0]]], [1.8, [[NOD, -6.0]]]])

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

	# Two hops. 1.6 bone units is ~7 mm of lift -- a bounce on the spot, not a
	# jump, because the feet are not animated and must not leave the floor.
	_hips(animation, skeleton, prefix, [
		[0.0, [0.0, []]], [0.25, [1.6, []]], [0.5, [0.0, []]],
		[0.75, [1.4, []]], [1.0, [0.0, []]], [1.8, [0.0, []]]])

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
## `[[time, [lift_in_bone_units, [[axis, degrees], ...]]], ...]`.
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
		animation.position_track_insert_key(moved, at,
				rest.origin + Vector3(0.0, float(spec[0]), 0.0))
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
