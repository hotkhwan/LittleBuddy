extends RefCounted

## ============================================================================
## ALIZ'S IDLE -- hand-keyed on her REAL skeleton, the way Bunny's life clips are.
## ============================================================================
##
## Her rigged export ships `walk` and `run` and nothing else, so at rest the
## `AnimationPlayer` used to STOP: a frozen frame of whatever the last clip
## was, which reads as a statue the moment she arrives anywhere. This file
## authors the missing `idle` as an ordinary `Animation` with bone tracks on
## the same `LB_Rig_v1`-family skeleton (`Hips`, `Spine02/01`, `Spine`,
## `neck`, `Head`, the arm chain), merged into the player's library by
## `pink_girl_buddy.gd::_merge_clips()` -- so `play_action("idle")` resolves
## through the ordinary action driver and locomotion returns to it at rest.
##
## Same bargain as `baby_life_clips.gd`, restated so nobody has to read both:
##
##   * it IS skeletal animation -- real bone tracks, real skin weights, blends
##     against `walk` through the ordinary player;
##   * it is NOT DCC-authored -- these are a programmer's keyframes;
##   * it is NOT a per-frame sine on the model node. Nothing here runs in
##     `_process`, nothing translates the whole character.
##   * **an authored clip always wins.** `merge_into()` skips any name already
##     in the library, so the day an animator delivers `idle.glb` this file
##     stops contributing without a caller changing.
##
## ## What the idle does, and how big it is
##
## Two breaths per 7.6 s loop, spread across the three spine bones so the
## torso swells rather than hinging (about a degree at each joint), a head bob
## of +-0.6 degrees riding the breath, and a WEIGHT SHIFT every 3.8 s: the hips
## tilt 2 degrees over one foot and the thighs counter-tilt by the same
## amount, so the torso leans and the feet stay planted -- a translation of
## the hips would slide her shoes across the floor. That lean moves the head
## about 1.3 cm (measured by `test_aliz_life.gd`, which prints the bone deltas
## at 1.5 s intervals): visible as life at gameplay distance, never a sway.
## The arms hang and follow a beat behind.
##
## Angles are in SKELETON space (`NOD` about +X, `TURN` about +Y, `TILT` about
## +Z) and converted per bone by `_bone_pose()` -- see `baby_life_clips.gd`'s
## class doc for the derivation and the sign table; this rig is the same
## family, in the same centimetre units under a 0.01 armature.

const NOD := Vector3(1.0, 0.0, 0.0)
const TURN := Vector3(0.0, 1.0, 0.0)
const TILT := Vector3(0.0, 0.0, 1.0)

const HIPS: String = "Hips"
const SPINE_LOW: String = "Spine02"
const SPINE_MID: String = "Spine01"
const SPINE_TOP: String = "Spine"
const NECK: String = "neck"
const HEAD: String = "Head"
const ARM_L: String = "LeftArm"
const ARM_R: String = "RightArm"
const FOREARM_L: String = "LeftForeArm"
const FOREARM_R: String = "RightForeArm"
const THIGH_L: String = "LeftUpLeg"
const THIGH_R: String = "RightUpLeg"

const CLIP_IDLE: String = "idle"
const CLIP_NAMES: Array[String] = [CLIP_IDLE]

## The loop, and the beats inside it. Two breaths; the weight shifts at the
## half-way point and again at the wrap.
const IDLE_LENGTH: float = 7.6
const BREATH: float = 3.8
## Degrees. The head bob the brief asks for, and the lean that carries the shift.
const HEAD_BOB_DEG: float = 0.6
const SHIFT_TILT_DEG: float = 2.0


## Adds every clip this file authors to `library`, addressed against `prefix`
## (the player-root-relative path of the `Skeleton3D`). A name already present
## always wins.
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


static func build(clip_name: String, skeleton: Skeleton3D, prefix: String) -> Animation:
	match clip_name:
		CLIP_IDLE:
			return _idle(skeleton, prefix)
		_:
			return null


static func _idle(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _looping(IDLE_LENGTH)
	var t_in: float = BREATH * 0.42        # top of the breath
	var t_out: float = BREATH               # bottom of the breath

	# The breath, twice per loop, split over the spine so the torso swells.
	var breath: Array = []
	for cycle: int in range(2):
		var base: float = cycle * BREATH
		breath.append([base, 0.0])
		breath.append([base + t_in, 1.0])
	breath.append([IDLE_LENGTH, 0.0])

	_bone(animation, skeleton, prefix, SPINE_LOW, _breath_keys(breath, NOD, 0.6, -0.5))
	_bone(animation, skeleton, prefix, SPINE_MID, _breath_keys(breath, NOD, 0.5, -0.7))
	_bone(animation, skeleton, prefix, NECK, _breath_keys(breath, NOD, 0.3, -0.3))
	_bone(animation, skeleton, prefix, HEAD, _breath_keys(breath, NOD, HEAD_BOB_DEG, -HEAD_BOB_DEG))

	# The top of the spine breathes AND carries a little of the weight shift.
	_bone(animation, skeleton, prefix, SPINE_TOP, [
		[0.0, [[NOD, 0.4], [TILT, 0.0]]],
		[t_in, [[NOD, -0.8], [TILT, 0.5]]],
		[t_out, [[NOD, 0.4], [TILT, 0.5]]],
		[BREATH + 0.4, [[NOD, 0.0], [TILT, 0.0]]],
		[BREATH + t_in, [[NOD, -0.8], [TILT, -0.5]]],
		[2.0 * BREATH - 0.4, [[NOD, 0.4], [TILT, -0.5]]],
		[IDLE_LENGTH, [[NOD, 0.4], [TILT, 0.0]]]])

	# The weight shift: hips tilt over one foot, thighs counter-tilt so the feet
	# stay where they are. Held for most of each half, eased over 0.8 s.
	# Hold keys either side of each plateau: the tracks are cubic, and a long
	# flat segment next to a short ramp overshoots by more than the lean itself
	# without them (measured: 3.7 degrees for a 1.5 degree key).
	var a: float = SHIFT_TILT_DEG
	var shift: Array = [
		[0.0, 0.0], [0.4, -a], [0.9, -a], [BREATH - 0.9, -a], [BREATH - 0.4, -a],
		[BREATH + 0.4, a], [BREATH + 0.9, a], [IDLE_LENGTH - 0.9, a],
		[IDLE_LENGTH - 0.4, a], [IDLE_LENGTH, 0.0]]
	var hip_keys: Array = []
	var thigh_keys: Array = []
	for point: Array in shift:
		hip_keys.append([float(point[0]), [0.0, [[TILT, float(point[1])]]]])
		thigh_keys.append([float(point[0]), [[TILT, -float(point[1])]]])
	_hips(animation, skeleton, prefix, hip_keys)
	for thigh: String in [THIGH_L, THIGH_R]:
		_bone(animation, skeleton, prefix, thigh, thigh_keys)

	# Arms hang and follow the breath a beat behind. Small: she is standing.
	for side: int in [-1, 1]:
		_bone(animation, skeleton, prefix, ARM_L if side < 0 else ARM_R, [
			[0.0, [[NOD, -1.0], [TILT, -side * 0.8]]],
			[t_in + 0.4, [[NOD, -2.4], [TILT, -side * 1.6]]],
			[BREATH, [[NOD, -1.0], [TILT, -side * 0.8]]],
			[BREATH + t_in + 0.4, [[NOD, -2.4], [TILT, -side * 1.6]]],
			[IDLE_LENGTH, [[NOD, -1.0], [TILT, -side * 0.8]]]])
		_bone(animation, skeleton, prefix, FOREARM_L if side < 0 else FOREARM_R, [
			[0.0, [[NOD, -2.0]]], [t_in + 0.6, [[NOD, -4.0]]],
			[BREATH, [[NOD, -2.0]]], [BREATH + t_in + 0.6, [[NOD, -4.0]]],
			[IDLE_LENGTH, [[NOD, -2.0]]]])

	_rest_the_others(animation, skeleton, prefix)
	return animation


## Expands a breath envelope (`[[time, 0..1], ...]`) into keys on one axis
## between `low` (exhaled) and `high` (inhaled) degrees.
static func _breath_keys(envelope: Array, axis: Vector3, low: float, high: float) -> Array:
	var keys: Array = []
	for point: Array in envelope:
		keys.append([float(point[0]), [[axis, lerpf(low, high, float(point[1]))]]])
	return keys


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
		animation.rotation_track_insert_key(track, 0.0,
				skeleton.get_bone_rest(index).basis.get_rotation_quaternion())


static func _bone(animation: Animation, skeleton: Skeleton3D, prefix: String,
		bone_name: String, keys: Array) -> void:
	var index: int = skeleton.find_bone(bone_name)
	if index == -1:
		return
	var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath("%s:%s" % [prefix, bone_name]))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for key: Array in keys:
		animation.rotation_track_insert_key(track, float(key[0]),
				_bone_pose(skeleton, index, key[1] as Array))


static func _hips(animation: Animation, skeleton: Skeleton3D, prefix: String, keys: Array) -> void:
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
		var offset: Vector3 = spec[0] if spec[0] is Vector3 else Vector3(0.0, float(spec[0]), 0.0)
		animation.position_track_insert_key(moved, at, rest.origin + offset)
		animation.rotation_track_insert_key(turned, at, _bone_pose(skeleton, index, spec[1] as Array))


## "N degrees about a skeleton-space axis" -> the bone's pose in its parent's
## frame. See `baby_life_clips.gd::_bone_pose()`; identical on purpose.
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
