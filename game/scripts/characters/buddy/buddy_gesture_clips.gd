extends RefCounted

## ============================================================================
## ALIZ'S TUTOR GESTURES -- nod, tilt, point, clap, wave, hand-keyed on her
## REAL skeleton as ordinary `Animation`s, played on an upper-body LAYER.
## ============================================================================
##
## Same bargain as `buddy_life_clips.gd` (the idle) and `baby_life_clips.gd`:
## these ARE skeletal animation -- real rotation tracks on `Head`, `neck`, the
## arm chains -- authored by a programmer, not a DCC, and an animator's clip of
## the same name would win the day one exists.
##
## What is different is HOW they play. The idle and the walk own the whole body
## through the `AnimationPlayer`; a gesture must not. A nod while she breathes,
## a point while she stands in the classroom's seated pose, a wave that never
## has to know what the legs are doing -- that is an upper-body layer, and it is
## `buddy_gesture_layer.gd`, a `SkeletonModifier3D` that samples these clips
## each frame and pre-multiplies each keyed bone's DELTA FROM REST onto the
## bone's CURRENT pose. So a track here that sits at rest changes nothing, and a
## track that turns the head 12 degrees turns it 12 degrees from wherever the
## idle's breath had it. The layer eases its `influence` in over 0.12 s and out
## over 0.2 s, and refuses to start while locomotion is above 0.1 m/s.
##
## The clips are therefore authored as ABSOLUTE poses (rest * turns), exactly
## like the idle, so they are also valid `AnimationPlayer` clips. They are not
## merged into her library on purpose: through the player a gesture would
## replace the idle wholesale and freeze the rest of her.
##
## ## The vocabulary and its timing (the TutorTurn contract, docs/ALIZ_TUTOR_CONTRACTS.md)
##
##   nod    0.9 s   two dips of the head, 12 degrees, the neck carrying a third
##   tilt   1.2 s   12 degrees of roll (9 head + 3 neck) held, then back
##   point  1.4 s   the right arm forward and ACROSS toward camera-right (she
##                  faces the child, so camera-right is her left, where the
##                  flashcard board sits), forearm straight, head turned 12
##                  degrees the same way; held, then lowered
##   clap   1.1 s   both arms forward and bent up, hands pulsing inward twice
##   wave   1.3 s   the right arm up and out, forearm and hand swinging four
##                  times
##
## Signs, measured on this rig by turning a bone and reading where its child
## went (bone units are centimetres, model +Z is forward, +X is HER left):
##   Head  NOD +   chin down            Head TURN +   to her left
##   Arm   NOD -   forward and up       Arm  TILT     out = -1 for the right arm,
##                                                          +1 for the left
##   Arm   TURN    once the arm points forward, + swings the hand to her left
##   ForeArm NOD - elbow bends forward  Spine NOD +   lean forward

const NOD := Vector3(1.0, 0.0, 0.0)
const TURN := Vector3(0.0, 1.0, 0.0)
const TILT := Vector3(0.0, 0.0, 1.0)

const HEAD: String = "Head"
const NECK: String = "neck"
const ARM_R: String = "RightArm"
const ARM_L: String = "LeftArm"
const FOREARM_R: String = "RightForeArm"
const FOREARM_L: String = "LeftForeArm"
const HAND_R: String = "RightHand"
const HAND_L: String = "LeftHand"
const SPINE_LOW: String = "Spine02"
const SPINE_MID: String = "Spine01"
const SPINE_TOP: String = "Spine"

const GESTURE_NOD: String = "nod"
const GESTURE_TILT: String = "tilt"
const GESTURE_POINT: String = "point"
const GESTURE_CLAP: String = "clap"
const GESTURE_WAVE: String = "wave"
const GESTURE_NAMES: Array[String] = [
	GESTURE_NOD, GESTURE_TILT, GESTURE_POINT, GESTURE_CLAP, GESTURE_WAVE,
]
## The small conversational beats the `speaking` tutor state sprinkles in
## every ~3 s: not in the TutorTurn vocabulary, playable through the layer.
const MICRO_BEAT_RIGHT: String = "beatRight"
const MICRO_BEAT_LEFT: String = "beatLeft"
const MICRO_OPEN_HANDS: String = "openHands"
const MICRO_NAMES: Array[String] = [MICRO_BEAT_RIGHT, MICRO_BEAT_LEFT, MICRO_OPEN_HANDS]
## Gestures that move the arms; refused while the carry pose has them.
const ARM_GESTURES: Array[String] = [
	GESTURE_POINT, GESTURE_CLAP, GESTURE_WAVE,
	MICRO_BEAT_RIGHT, MICRO_BEAT_LEFT, MICRO_OPEN_HANDS,
]

## Seconds. Read by the tests and by `play_gesture()`'s return value.
const DURATIONS: Dictionary = {
	GESTURE_NOD: 0.9, GESTURE_TILT: 1.2, GESTURE_POINT: 1.4,
	GESTURE_CLAP: 1.1, GESTURE_WAVE: 1.3,
	MICRO_BEAT_RIGHT: 0.9, MICRO_BEAT_LEFT: 0.9, MICRO_OPEN_HANDS: 1.0,
}

## Degrees.
const NOD_DEG: float = 12.0
const TILT_DEG: float = 12.0
## Forward and across for the point. For the wave the upper arm goes forward
## AND out (a hand raised in class) and the forearm up to vertical, so the
## hand is at face height in front of the shoulder -- beside the head it
## vanishes behind her hair, which is most of her silhouette from the front.
const POINT_FORWARD_DEG: float = 82.0
const POINT_ACROSS_DEG: float = 58.0
const WAVE_FORWARD_DEG: float = 60.0
const WAVE_OUT_DEG: float = 45.0
const WAVE_ELBOW_DEG: float = 75.0

## The listening lean-in, applied by the layer as a held posture (not a clip):
## bone -> [[axis, degrees], ...]. The head counter-nods so the eyes stay on
## the child; the head ends up ~4 cm forward of where the idle had it.
static func listening_posture() -> Dictionary:
	return {
		SPINE_LOW: [[NOD, 2.5]],
		SPINE_MID: [[NOD, 2.0]],
		SPINE_TOP: [[NOD, 1.5]],
		HEAD: [[NOD, -3.0]],
	}


## A name the layer can play: the five contract gestures or a micro beat.
static func is_gesture(name: String) -> bool:
	return GESTURE_NAMES.has(name) or MICRO_NAMES.has(name)


static func is_micro(name: String) -> bool:
	return MICRO_NAMES.has(name)


static func duration_of(name: String) -> float:
	return float(DURATIONS.get(name, 0.0))


## Every gesture, built against `skeleton`. Track paths are `prefix:bone`, the
## form the player's own clips use, so a clip here could be handed to the
## `AnimationPlayer` unchanged.
static func build_all(skeleton: Skeleton3D, prefix: String = ".") -> Dictionary:
	var clips: Dictionary = {}
	if skeleton == null:
		return clips
	for name: String in GESTURE_NAMES + MICRO_NAMES:
		var animation: Animation = build(name, skeleton, prefix)
		if animation != null:
			clips[name] = animation
	return clips


static func build(name: String, skeleton: Skeleton3D, prefix: String) -> Animation:
	match name:
		GESTURE_NOD:
			return _nod(skeleton, prefix)
		GESTURE_TILT:
			return _tilt(skeleton, prefix)
		GESTURE_POINT:
			return _point(skeleton, prefix)
		GESTURE_CLAP:
			return _clap(skeleton, prefix)
		GESTURE_WAVE:
			return _wave(skeleton, prefix)
		MICRO_BEAT_RIGHT:
			return _beat(skeleton, prefix, -1)
		MICRO_BEAT_LEFT:
			return _beat(skeleton, prefix, 1)
		MICRO_OPEN_HANDS:
			return _open_hands(skeleton, prefix)
		_:
			return null


# ---------------------------------------------------------------------------
# the clips
# ---------------------------------------------------------------------------

static func _nod(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _one_shot(duration_of(GESTURE_NOD))
	var head: float = NOD_DEG * 0.7
	var neck: float = NOD_DEG * 0.3
	# Two dips: down at 0.2 s and 0.65 s, up between, level at the end.
	var beats: Array = [[0.0, 0.0], [0.2, 1.0], [0.42, 0.05], [0.65, 1.0], [0.9, 0.0]]
	_bone(animation, skeleton, prefix, HEAD, _scaled(beats, NOD, head))
	_bone(animation, skeleton, prefix, NECK, _scaled(beats, NOD, neck))
	return animation


static func _tilt(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _one_shot(duration_of(GESTURE_TILT))
	var beats: Array = [[0.0, 0.0], [0.3, 1.0], [0.85, 1.0], [1.2, 0.0]]
	_bone(animation, skeleton, prefix, HEAD, _scaled(beats, TILT, TILT_DEG * 0.75))
	_bone(animation, skeleton, prefix, NECK, _scaled(beats, TILT, TILT_DEG * 0.25))
	return animation


static func _point(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _one_shot(duration_of(GESTURE_POINT))
	# Forward to shoulder height, then swung across toward her left (TURN +
	# once the arm points forward), held.
	var beats: Array = [[0.0, 0.0], [0.35, 1.0], [1.1, 1.0], [1.4, 0.0]]
	_bone(animation, skeleton, prefix, ARM_R,
			_scaled2(beats, NOD, -POINT_FORWARD_DEG, TURN, POINT_ACROSS_DEG))
	_bone(animation, skeleton, prefix, FOREARM_R, _scaled(beats, NOD, -6.0))
	_bone(animation, skeleton, prefix, HAND_R, _scaled(beats, NOD, -12.0))
	# The head follows the hand: to her left is TURN positive.
	_bone(animation, skeleton, prefix, HEAD, _scaled(beats, TURN, 12.0))
	return animation


static func _clap(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _one_shot(duration_of(GESTURE_CLAP))
	# Arms forward and bent up; the hands pulse inward at 0.35 s and 0.7 s.
	var raise: Array = [[0.0, 0.0], [0.2, 1.0], [0.9, 1.0], [1.1, 0.0]]
	var pulse: Array = [[0.0, 0.0], [0.2, 0.3], [0.35, 1.0], [0.5, 0.3], [0.7, 1.0],
			[0.85, 0.3], [1.1, 0.0]]
	for side: int in [-1, 1]:
		var arm: String = ARM_L if side > 0 else ARM_R
		var forearm: String = FOREARM_L if side > 0 else FOREARM_R
		var hand: String = HAND_L if side > 0 else HAND_R
		# Inward is -side. With the upper arm pointing FORWARD its inward swing
		# is about the vertical axis (TURN); a TILT there would only twist it.
		# The forearm points up, so its inward swing is about the forward axis
		# (TILT). Measured, not guessed: the first version tilted the arm and
		# the hands moved 1.8 cm.
		var inward: float = -float(side)
		_bone(animation, skeleton, prefix, arm, _combine(
				_scaled(raise, NOD, -58.0), _scaled(pulse, TURN, inward * 34.0)))
		_bone(animation, skeleton, prefix, forearm, _combine(
				_scaled(raise, NOD, -62.0), _scaled(pulse, TILT, inward * 22.0)))
		_bone(animation, skeleton, prefix, hand, _scaled(pulse, TILT, inward * 12.0))
	return animation


static func _wave(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _one_shot(duration_of(GESTURE_WAVE))
	var raise: Array = [[0.0, 0.0], [0.3, 1.0], [1.0, 1.0], [1.3, 0.0]]
	# Four swings while the arm is up.
	var swing: Array = [[0.0, 0.0], [0.3, 0.0], [0.42, 1.0], [0.56, -1.0], [0.70, 1.0],
			[0.84, -1.0], [0.98, 0.5], [1.1, 0.0], [1.3, 0.0]]
	# Upper arm forward and out, forearm bent up (the elbow bend of a forward
	# arm is NOD). Turn axes are expressed in the PARENT'S rest frame, so on
	# the raised arm the swing axis that sweeps the hand sideways is TURN
	# (measured: 9 cm of sweep; TILT there only twisted the forearm).
	# Turns apply in order about FIXED skeleton axes: out first, then forward,
	# because a forward-pointing arm turned about the forward axis only twists.
	_bone(animation, skeleton, prefix, ARM_R,
			_scaled2(raise, TILT, -WAVE_OUT_DEG, NOD, -WAVE_FORWARD_DEG))
	_bone(animation, skeleton, prefix, FOREARM_R, _combine(
			_scaled(raise, NOD, -WAVE_ELBOW_DEG), _scaled(swing, NOD, 24.0)))
	_bone(animation, skeleton, prefix, HAND_R, _scaled(swing, TILT, 18.0))
	return animation


## A conversational beat: one forearm lifts a little and settles. `side` -1 is
## her right arm, +1 her left.
static func _beat(skeleton: Skeleton3D, prefix: String, side: int) -> Animation:
	var animation: Animation = _one_shot(duration_of(MICRO_BEAT_RIGHT))
	var beats: Array = [[0.0, 0.0], [0.3, 1.0], [0.55, 0.85], [0.9, 0.0]]
	var arm: String = ARM_L if side > 0 else ARM_R
	var forearm: String = FOREARM_L if side > 0 else FOREARM_R
	var hand: String = HAND_L if side > 0 else HAND_R
	_bone(animation, skeleton, prefix, arm, _scaled(beats, NOD, -10.0))
	_bone(animation, skeleton, prefix, forearm, _scaled2(beats, NOD, -38.0, TILT, float(side) * 10.0))
	_bone(animation, skeleton, prefix, hand, _scaled(beats, NOD, -12.0))
	return animation


## Both forearms open outward a little, palms toward the child, and settle.
static func _open_hands(skeleton: Skeleton3D, prefix: String) -> Animation:
	var animation: Animation = _one_shot(duration_of(MICRO_OPEN_HANDS))
	var beats: Array = [[0.0, 0.0], [0.35, 1.0], [0.65, 0.9], [1.0, 0.0]]
	for side: int in [-1, 1]:
		var arm: String = ARM_L if side > 0 else ARM_R
		var forearm: String = FOREARM_L if side > 0 else FOREARM_R
		_bone(animation, skeleton, prefix, arm, _scaled2(beats, NOD, -14.0, TILT, float(side) * 6.0))
		_bone(animation, skeleton, prefix, forearm, _scaled2(beats, NOD, -30.0, TILT, float(side) * 22.0))
	return animation


# ---------------------------------------------------------------------------
# key helpers
# ---------------------------------------------------------------------------

## `[[time, weight], ...]` -> keys turning `axis` by `weight * degrees`.
static func _scaled(beats: Array, axis: Vector3, degrees: float) -> Array:
	var keys: Array = []
	for beat: Array in beats:
		keys.append([float(beat[0]), [[axis, float(beat[1]) * degrees]]])
	return keys


static func _scaled2(beats: Array, axis_a: Vector3, deg_a: float,
		axis_b: Vector3, deg_b: float) -> Array:
	var keys: Array = []
	for beat: Array in beats:
		var w: float = float(beat[1])
		keys.append([float(beat[0]), [[axis_a, w * deg_a], [axis_b, w * deg_b]]])
	return keys


## Merges two key lists with different beats into one list keyed at the union
## of their times, each turn interpolated linearly at the other's times.
static func _combine(a: Array, b: Array) -> Array:
	var times: Array = []
	for key: Array in a + b:
		if not times.has(float(key[0])):
			times.append(float(key[0]))
	times.sort()
	var out: Array = []
	for t: float in times:
		var turns: Array = []
		for key: Array in [_at(a, t), _at(b, t)]:
			for turn: Array in key:
				turns.append(turn)
		out.append([t, turns])
	return out


static func _at(keys: Array, t: float) -> Array:
	var before: Array = keys[0]
	var after: Array = keys[keys.size() - 1]
	for k: int in range(keys.size()):
		var key: Array = keys[k]
		if float(key[0]) <= t:
			before = key
		if float(key[0]) >= t:
			after = key
			break
	var t0: float = float(before[0])
	var t1: float = float(after[0])
	var w: float = 0.0 if is_equal_approx(t0, t1) else (t - t0) / (t1 - t0)
	var turns: Array = []
	var a: Array = before[1]
	var b: Array = after[1]
	for i: int in range(a.size()):
		var deg_a: float = float((a[i] as Array)[1])
		var deg_b: float = float((b[i] as Array)[1]) if i < b.size() else deg_a
		turns.append([(a[i] as Array)[0], lerpf(deg_a, deg_b, w)])
	return turns


static func _bone(animation: Animation, skeleton: Skeleton3D, prefix: String,
		bone_name: String, keys: Array) -> void:
	var index: int = skeleton.find_bone(bone_name)
	if index == -1:
		return
	var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath("%s:%s" % [prefix, bone_name]))
	# Linear between keys: a gesture has sharp beats (the claps, the swings)
	# and cubic overshoot would add a wobble nobody keyed.
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for key: Array in keys:
		animation.rotation_track_insert_key(track, float(key[0]),
				_bone_pose(skeleton, index, key[1] as Array))


## "N degrees about a skeleton-space axis" -> the bone's pose in its parent's
## frame. Identical to `buddy_life_clips.gd::_bone_pose()` on purpose: the two
## files must agree on what a degree is.
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


static func _one_shot(length: float) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_NONE
	return animation
