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
## from `stop()`), so a gesture never pops. The listening posture is a second,
## independent weight on the same node (`set_listening()`), eased the same way,
## so a nod can play over the lean.
##
## Nothing here is a fixed timer or a per-frame sine on the model: the clock
## advances in the modification pass, and `step()` advances it by hand for a
## headless test.

const GestureClips := preload("res://scripts/characters/buddy/buddy_gesture_clips.gd")

const FADE_IN_SEC: float = 0.12
const FADE_OUT_SEC: float = 0.20
const POSTURE_BLEND_SEC: float = 0.35

## Emitted when a gesture that started has run its length (or was stopped).
signal gesture_finished(name: String)

var _clips: Dictionary = {}
var _current: String = ""
var _time: float = 0.0
var _weight: float = 0.0
var _stopping: bool = false
var _posture: Dictionary = {}
var _posture_target: float = 0.0
var _posture_weight: float = 0.0
## When true the modification pass only APPLIES; the clock moves through
## `advance()`. For the contact-sheet tool, which wants a frame at 0.2 s
## exactly rather than whenever the renderer got round to it.
var manual_clock: bool = false
## The bone poses this layer wrote last pass, so a test can read the delta.
var _last_deltas: Dictionary = {}


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
func play(name: String) -> float:
	if not _clips.has(name):
		return 0.0
	if not _current.is_empty() and _current != name:
		gesture_finished.emit(_current)
	_current = name
	_time = 0.0
	_stopping = false
	self.active = true
	return (_clips[name] as Animation).length


## Fades the running gesture out over `FADE_OUT_SEC`. Idempotent.
func stop() -> void:
	if _current.is_empty():
		return
	_stopping = true


func is_playing() -> bool:
	return not _current.is_empty()


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


## Jumps the eased weights to their targets -- for a node outside the tree,
## where no modification pass will ever move them.
func settle() -> void:
	_posture_weight = _posture_target
	if not _current.is_empty() and not _stopping:
		_weight = 1.0


## The rotation this layer applied to `bone_name` in its last pass (identity
## when it did not touch it). For tests.
func last_delta(bone_name: String) -> Quaternion:
	return _last_deltas.get(bone_name, Quaternion.IDENTITY)


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
	# The posture eases toward its target on its own clock.
	_posture_weight = move_toward(_posture_weight, _posture_target,
			seconds / maxf(POSTURE_BLEND_SEC, 0.01))
	if _current.is_empty():
		if _posture_weight <= 0.0 and _posture_target <= 0.0 and self.active:
			self.active = false
		return
	_time += seconds
	var length: float = (_clips[_current] as Animation).length
	# Fade out from the clip's end (the last FADE_OUT_SEC of it), or from stop().
	var fading_out: bool = _stopping or _time >= length - FADE_OUT_SEC
	if fading_out:
		_weight = move_toward(_weight, 0.0, seconds / FADE_OUT_SEC)
	else:
		_weight = move_toward(_weight, 1.0, seconds / FADE_IN_SEC)
	if _time >= length or (_stopping and _weight <= 0.0):
		var done: String = _current
		_current = ""
		_time = 0.0
		_weight = 0.0
		_stopping = false
		_last_deltas.clear()
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
	if _posture_weight > 0.0:
		for bone_name: String in _posture.keys():
			var index: int = skeleton.find_bone(bone_name)
			if index == -1:
				continue
			var turned: Quaternion = _turns_in_parent(skeleton, index, _posture[bone_name] as Array)
			_apply_delta(skeleton, index, bone_name,
					Quaternion.IDENTITY.slerp(turned, _posture_weight))
	if _current.is_empty() or _weight <= 0.0:
		return
	var animation: Animation = _clips[_current]
	var at: float = clampf(_time, 0.0, animation.length)
	for track: int in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone_name: String = String(animation.track_get_path(track).get_concatenated_subnames())
		var index: int = skeleton.find_bone(bone_name)
		if index == -1:
			continue
		var sampled: Quaternion = animation.rotation_track_interpolate(track, at)
		var rest: Quaternion = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		# The authored turn, in the parent's frame: sampled = turn * rest.
		var turn: Quaternion = (sampled * rest.inverse()).normalized()
		_apply_delta(skeleton, index, bone_name, Quaternion.IDENTITY.slerp(turn, _weight))


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
