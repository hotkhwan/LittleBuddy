extends SkeletonModifier3D

## THE UPPER-BODY LAYER -- plays `buddy_gesture_clips.gd`'s clips on top of
## whatever the `AnimationPlayer` is doing, and holds the listening lean-in.
##
## A `SkeletonModifier3D`, like the carry pose and the hair sway: it runs after
## the clip has posed the skeleton this frame and edits bones in place. For
## every rotation track of the playing gesture it samples the clip at the
## current time, takes that pose's DELTA FROM REST (the authored turn, in the
## parent's frame), scales the delta by the layer's blend weight, and
## pre-multiplies it onto the bone's CURRENT pose. The idle's breath keeps
## going in the spine underneath; a seated pose keeps its arms until a gesture
## asks for them and gets them back when it ends; the walk never sees a
## gesture at all because `pink_girl_buddy.gd` refuses to start one above
## 0.1 m/s and fades a running one out when she moves off.
##
## Blend: in over `FADE_IN_SEC`, out over `FADE_OUT_SEC` from the clip's end (or
## from `stop()`), so a gesture never pops. Two gestures never overlap: a
## `play()` over a running gesture hands the old one to a single OUTGOING slot
## that fades to 0 over `FADE_OUT_SEC` (its clock still running) while the new
## one fades in -- a cross-fade, not a snap to rest and back up. A third call
## inside that window drops the outgoing one on the spot; there is only ever
## one current and one outgoing. `play(name, scale)` caps the blend
## at `scale`, which is how the tutor states get a half-size nod or a small
## hand beat out of the same clips. Three more held layers ride on the same
## node, each with its own eased weight, so a nod can play over all of them:
##   * the listening posture (`set_listening()`, a lean-in);
##   * the LOOK (`set_look(yaw)`), the head and neck turned toward whoever she
##     is attending to -- barge-in turns her to the child;
##   * the TALK motion (`set_talk_motion()`), +-1 degree of head nodding on two
##     unrelated periods while she speaks, so a talking head is not a statue.
##
## Nothing here is a fixed timer or a per-frame sine on the model: the clock
## advances in the modification pass, and `step()` advances it by hand for a
## headless test.

const GestureClips := preload("res://scripts/characters/buddy/buddy_gesture_clips.gd")

const FADE_IN_SEC: float = 0.12
const FADE_OUT_SEC: float = 0.20
const POSTURE_BLEND_SEC: float = 0.35
const LOOK_BLEND_DEG_PER_SEC: float = 140.0
const LOOK_MAX_DEG: float = 35.0
const TALK_BLEND_SEC: float = 0.3
## Degrees of head nod while talking, and the two periods it rides on.
const TALK_NOD_DEG: float = 1.0
const TALK_PERIOD_A: float = 1.7
const TALK_PERIOD_B: float = 1.1

## Emitted when a gesture that started has run its length (or was stopped).
signal gesture_finished(name: String)

var _clips: Dictionary = {}
var _current: String = ""
var _time: float = 0.0
var _weight: float = 0.0
var _stopping: bool = false
var _max_weight: float = 1.0
var _posture: Dictionary = {}
var _posture_target: float = 0.0
var _posture_weight: float = 0.0
## The look: a head yaw in degrees (+ = her left), eased toward its target.
var _look_target_deg: float = 0.0
var _look_deg: float = 0.0
## Talk motion: 0..1 weight eased toward its target, and its own clock.
var _talk_target: float = 0.0
var _talk_weight: float = 0.0
var _talk_time: float = 0.0
## When true the modification pass only APPLIES; the clock moves through
## `advance()`. For the contact-sheet tool, which wants a frame at 0.2 s
## exactly rather than whenever the renderer got round to it.
var manual_clock: bool = false
## The bone poses this layer wrote last pass, so a test can read the delta.
var _last_deltas: Dictionary = {}
var _last_offsets: Dictionary = {}
## The gesture a `play()` replaced, fading out under the new one.
var _outgoing: String = ""
var _outgoing_time: float = 0.0
var _outgoing_weight: float = 0.0


## Builds the clips against the skeleton it sits under. Safe to call again.
func prepare(skeleton: Skeleton3D, prefix: String = ".") -> void:
	_clips = GestureClips.build_all(skeleton, prefix)
	_posture = GestureClips.listening_posture()


func available_gestures() -> Array:
	var out: Array = []
	for name: String in GestureClips.GESTURE_NAMES:
		if _clips.has(name):
			out.append(name)
	return out


func has_gesture(name: String) -> bool:
	return _clips.has(name)


## Starts `name` from its first frame, fading in. Returns the clip's length in
## seconds, or 0.0 when there is no such clip. A gesture already running is
## replaced (its `gesture_finished` still fires).
func play(name: String, scale: float = 1.0) -> float:
	if not _clips.has(name):
		return 0.0
	if not _current.is_empty():
		# Hand the running gesture to the outgoing slot so it fades out under
		# the new one instead of snapping to rest. A restart of the same clip
		# cross-fades from where it was too.
		var replaced: String = _current
		_outgoing = _current
		_outgoing_time = _time
		_outgoing_weight = _weight
		gesture_finished.emit(replaced)
	_current = name
	_time = 0.0
	_stopping = false
	_max_weight = clampf(scale, 0.05, 1.0)
	self.active = true
	return (_clips[name] as Animation).length


## Fades the running gesture out over `FADE_OUT_SEC`. Idempotent.
func stop() -> void:
	if _current.is_empty():
		return
	_stopping = true


func is_playing() -> bool:
	return not _current.is_empty()


## The gesture fading out under the current one, or "" when none is.
func outgoing_gesture() -> String:
	return _outgoing


func outgoing_weight() -> float:
	return _outgoing_weight


func current_gesture() -> String:
	return _current


func time() -> float:
	return _time


func weight() -> float:
	return _weight


## Leans in (true) or straightens up (false), eased over `POSTURE_BLEND_SEC`.
func set_listening(active: bool) -> void:
	_posture_target = 1.0 if active else 0.0
	if active:
		self.active = true


func is_listening() -> bool:
	return _posture_target > 0.5


func posture_weight() -> float:
	return _posture_weight


## Turns the head (70 %) and neck (30 %) `yaw_deg` toward her left (+) or
## right (-), clamped to `LOOK_MAX_DEG`, eased at `LOOK_BLEND_DEG_PER_SEC`.
## 0 looks straight ahead again.
func set_look(yaw_deg: float) -> void:
	_look_target_deg = clampf(yaw_deg, -LOOK_MAX_DEG, LOOK_MAX_DEG)
	if not is_zero_approx(_look_target_deg):
		self.active = true


func look_deg() -> float:
	return _look_deg


func look_target_deg() -> float:
	return _look_target_deg


## +-1 degree head nodding on two periods while she talks; eased in and out.
func set_talk_motion(active: bool) -> void:
	_talk_target = 1.0 if active else 0.0
	if active:
		self.active = true


func talk_weight() -> float:
	return _talk_weight


## The talk nod in degrees at `seconds` on the talk clock. Public for tests.
static func talk_nod_at(seconds: float) -> float:
	return TALK_NOD_DEG * (0.65 * sin(TAU * seconds / TALK_PERIOD_A)
			+ 0.45 * sin(TAU * seconds / TALK_PERIOD_B))


## Jumps the eased weights to their targets -- for a node outside the tree,
## where no modification pass will ever move them.
func settle() -> void:
	_posture_weight = _posture_target
	_look_deg = _look_target_deg
	_talk_weight = _talk_target
	if not _current.is_empty() and not _stopping:
		_weight = _max_weight


## The rotation this layer applied to `bone_name` in its last pass (identity
## when it did not touch it). For tests.
func last_delta(bone_name: String) -> Quaternion:
	return _last_deltas.get(bone_name, Quaternion.IDENTITY)


## The position offset this layer applied to `bone_name` in its last pass
## (zero when it did not move it). For tests.
func last_offset(bone_name: String) -> Vector3:
	return _last_offsets.get(bone_name, Vector3.ZERO)


func _process_modification_with_delta(delta: float) -> void:
	if manual_clock:
		apply()
	else:
		step(delta)


## Older callback name, for a runtime that has not adopted the delta form.
func _process_modification() -> void:
	if manual_clock:
		apply()
	else:
		step(1.0 / 60.0)


## Advances the clocks by `seconds` and applies. Public for headless tests.
func step(seconds: float) -> void:
	advance(seconds)
	apply()


## Advances the clocks by `seconds` without applying.
func advance(seconds: float) -> void:
	# The held layers ease toward their targets on their own clocks.
	_posture_weight = move_toward(_posture_weight, _posture_target,
			seconds / maxf(POSTURE_BLEND_SEC, 0.01))
	_look_deg = move_toward(_look_deg, _look_target_deg, seconds * LOOK_BLEND_DEG_PER_SEC)
	_talk_weight = move_toward(_talk_weight, _talk_target, seconds / TALK_BLEND_SEC)
	if _talk_weight > 0.0:
		_talk_time += seconds
	if not _outgoing.is_empty():
		_outgoing_time += seconds
		_outgoing_weight = move_toward(_outgoing_weight, 0.0, seconds / FADE_OUT_SEC)
		if _outgoing_weight <= 0.0 \
				or _outgoing_time >= (_clips[_outgoing] as Animation).length:
			_outgoing = ""
			_outgoing_time = 0.0
			_outgoing_weight = 0.0
	if _current.is_empty():
		if self.active and _outgoing.is_empty() \
				and _posture_weight <= 0.0 and _posture_target <= 0.0 \
				and is_zero_approx(_look_deg) and is_zero_approx(_look_target_deg) \
				and _talk_weight <= 0.0 and _talk_target <= 0.0:
			self.active = false
		return
	_time += seconds
	var length: float = (_clips[_current] as Animation).length
	# Fade out from the clip's end (the last FADE_OUT_SEC of it), or from stop().
	var fading_out: bool = _stopping or _time >= length - FADE_OUT_SEC
	if fading_out:
		_weight = move_toward(_weight, 0.0, seconds / FADE_OUT_SEC)
	else:
		_weight = move_toward(_weight, _max_weight, seconds / FADE_IN_SEC)
	if _time >= length or (_stopping and _weight <= 0.0):
		var done: String = _current
		_current = ""
		_time = 0.0
		_weight = 0.0
		_stopping = false
		_last_deltas.clear()
		_last_offsets.clear()
		gesture_finished.emit(done)


## One pass over the keyed bones. Public so a headless test can run it without
## a frame and read the result back off the skeleton.
func apply() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		skeleton = get_parent() as Skeleton3D
	if skeleton == null:
		return
	_last_deltas.clear()
	_last_offsets.clear()
	if _posture_weight > 0.0:
		for bone_name: String in _posture.keys():
			var index: int = skeleton.find_bone(bone_name)
			if index == -1:
				continue
			var turned: Quaternion = _turns_in_parent(skeleton, index, _posture[bone_name] as Array)
			_apply_delta(skeleton, index, bone_name,
					Quaternion.IDENTITY.slerp(turned, _posture_weight))
	if not is_zero_approx(_look_deg):
		_apply_turns(skeleton, GestureClips.HEAD, [[GestureClips.TURN, _look_deg * 0.7]])
		_apply_turns(skeleton, GestureClips.NECK, [[GestureClips.TURN, _look_deg * 0.3]])
	if _talk_weight > 0.0:
		_apply_turns(skeleton, GestureClips.HEAD,
				[[GestureClips.NOD, talk_nod_at(_talk_time) * _talk_weight]])
	# The outgoing gesture first (under), then the current one (over).
	if not _outgoing.is_empty() and _outgoing_weight > 0.0:
		_apply_clip(skeleton, _clips[_outgoing], _outgoing_time, _outgoing_weight)
	if _current.is_empty() or _weight <= 0.0:
		return
	_apply_clip(skeleton, _clips[_current], _time, _weight)


## Samples `animation` at `time` and pre-multiplies each keyed bone's delta
## from rest, scaled by `weight`, onto the bone's current pose. Rotation
## tracks turn; a position track (the celebrate hop on the hips) offsets.
func _apply_clip(skeleton: Skeleton3D, animation: Animation, time_sec: float, weight: float) -> void:
	var at: float = clampf(time_sec, 0.0, animation.length)
	for track: int in range(animation.get_track_count()):
		var bone_name: String = String(animation.track_get_path(track).get_concatenated_subnames())
		var index: int = skeleton.find_bone(bone_name)
		if index == -1:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				var sampled: Quaternion = animation.rotation_track_interpolate(track, at)
				var rest: Quaternion = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
				# The authored turn, in the parent's frame: sampled = turn * rest.
				var turn: Quaternion = (sampled * rest.inverse()).normalized()
				_apply_delta(skeleton, index, bone_name, Quaternion.IDENTITY.slerp(turn, weight))
			Animation.TYPE_POSITION_3D:
				var offset: Vector3 = animation.position_track_interpolate(track, at) \
						- skeleton.get_bone_rest(index).origin
				if offset.is_zero_approx():
					continue
				skeleton.set_bone_pose_position(index,
						skeleton.get_bone_pose_position(index) + offset * weight)
				_last_offsets[bone_name] = Vector3(_last_offsets.get(bone_name, Vector3.ZERO)) + offset * weight


func _apply_turns(skeleton: Skeleton3D, bone_name: String, turns: Array) -> void:
	var index: int = skeleton.find_bone(bone_name)
	if index == -1:
		return
	_apply_delta(skeleton, index, bone_name, _turns_in_parent(skeleton, index, turns))


func _apply_delta(skeleton: Skeleton3D, index: int, bone_name: String, turn: Quaternion) -> void:
	var current: Quaternion = skeleton.get_bone_pose_rotation(index)
	skeleton.set_bone_pose_rotation(index, (turn * current).normalized())
	var so_far: Quaternion = _last_deltas.get(bone_name, Quaternion.IDENTITY)
	_last_deltas[bone_name] = (turn * so_far).normalized()


## `[[axis, degrees], ...]` about skeleton-space axes -> a rotation in the
## bone's parent's rest frame. Same arithmetic as the clips, minus the rest.
static func _turns_in_parent(skeleton: Skeleton3D, index: int, turns: Array) -> Quaternion:
	var parent: int = skeleton.get_bone_parent(index)
	var to_parent: Basis = Basis()
	if parent != -1:
		to_parent = skeleton.get_bone_global_rest(parent).basis.orthonormalized().inverse()
	var applied: Quaternion = Quaternion.IDENTITY
	for turn: Array in turns:
		var axis: Vector3 = (to_parent * (turn[0] as Vector3)).normalized()
		applied = Quaternion(axis, deg_to_rad(float(turn[1]))) * applied
	return applied.normalized()
