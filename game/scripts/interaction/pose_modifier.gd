extends SkeletonModifier3D

## A HELD POSE for a character whose rig has no clip for it.
##
## Aliz's export ships with `walk` and `run` and nothing else, so "she sits on
## the sofa" and "she washes her hands" had no body to happen in. This modifier
## bends the bones a pose needs -- thighs and shins for `sit`, upper arms and
## forearms for `handsUp` -- and eases the blend in and out, inside the
## skeleton's own modification pass, the same seam `buddy_carry_pose.gd` uses
## for her arms round Bunny. It is procedural, it is called procedural, and it
## is limited to the joints a pose genuinely needs: no bob, no sway, nothing
## that pretends to be an authored clip.
##
## ## Rig-agnostic where it can be
##
## Every rotation is stated about a MODEL axis (the rig's own +X, the "nod"
## axis) and converted into each bone's rest frame from its global rest pose,
## so the same numbers work whatever local axes the exporter chose. Bones are
## looked up by the `LB_Rig_v1` names; a rig without one of them simply does
## not bend that joint.
##
## ## Headless
##
## `apply(delta)` is the whole of the work and is public; `_process_modification()`
## only forwards to it. `settle()` lands the blend at once for a test or a
## screenshot harness with no frames to ease over.

const POSE_NONE: String = ""
const POSE_SIT: String = "sit"
const POSE_HANDS_UP: String = "handsUp"

const BLEND_SECONDS: float = 0.28

## Per pose: bone name -> degrees about the model's X axis, positive nodding
## +Y towards +Z. The thigh swings forward (negative), the shin swings back by
## the same amount so the foot hangs vertical again.
const POSE_ROTATIONS: Dictionary = {
	POSE_SIT: {
		"LeftUpLeg": -82.0, "RightUpLeg": -82.0,
		"LeftLeg": 82.0, "RightLeg": 82.0,
		"Spine02": 6.0,
	},
	POSE_HANDS_UP: {
		"LeftArm": -105.0, "RightArm": -105.0,
		"LeftForeArm": -45.0, "RightForeArm": -45.0,
	},
}
## How far the hips drop for a pose, in the rig's own units (centimetres on
## `LB_Rig_v1`): the thigh's length, so a seated pelvis sits where the knees
## used to be.
const POSE_HIP_DROP: Dictionary = {POSE_SIT: 26.5}
const HIPS_BONE: String = "Hips"

var _pose: String = POSE_NONE
var _shown: String = POSE_NONE
var _influence_now: float = 0.0
var _target_influence: float = 0.0
var _axes: Dictionary = {}
var _rest_positions: Dictionary = {}


func _ready() -> void:
	active = true


## Asks for `pose` (`"sit"`, `"handsUp"`, or `""` to stand again).
func set_pose(pose: String) -> void:
	if pose != POSE_NONE and not POSE_ROTATIONS.has(pose):
		return
	if pose == POSE_NONE:
		_target_influence = 0.0
	else:
		_pose = pose
		_shown = pose
		_target_influence = 1.0
	if not is_inside_tree():
		settle()


func get_pose() -> String:
	return _pose if _target_influence > 0.0 else POSE_NONE


func is_posed() -> bool:
	return _influence_now > 0.001


## Lands the blend at once.
func settle() -> void:
	_influence_now = _target_influence
	apply(0.0)


func _process_modification() -> void:
	apply(get_process_delta_time())


## One pass: ease the influence, then write the posed bones.
func apply(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	if delta > 0.0:
		_influence_now = move_toward(_influence_now, _target_influence, delta / BLEND_SECONDS)
	if _influence_now <= 0.0 and _target_influence <= 0.0:
		_pose = POSE_NONE
		return
	var rotations: Dictionary = POSE_ROTATIONS.get(_shown, {})
	for bone_name: String in rotations.keys():
		var bone: int = skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var axis: Vector3 = _local_axis(skeleton, bone, Vector3.RIGHT)
		var rest: Quaternion = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var posed: Quaternion = rest * Quaternion(axis, deg_to_rad(float(rotations[bone_name])))
		var current: Quaternion = skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, current.slerp(posed, _influence_now))
	var drop: float = float(POSE_HIP_DROP.get(_shown, 0.0))
	if drop > 0.0:
		var hips: int = skeleton.find_bone(HIPS_BONE)
		if hips >= 0:
			var rest_origin: Vector3 = skeleton.get_bone_rest(hips).origin
			var lowered: Vector3 = rest_origin - Vector3(0.0, drop, 0.0)
			var now: Vector3 = skeleton.get_bone_pose_position(hips)
			skeleton.set_bone_pose_position(hips, now.lerp(lowered, _influence_now))


## The model axis `model_axis` expressed in `bone`'s own rest frame, cached.
func _local_axis(skeleton: Skeleton3D, bone: int, model_axis: Vector3) -> Vector3:
	var key: String = "%d/%s" % [bone, str(model_axis)]
	if _axes.has(key):
		return _axes[key]
	var global_rest: Basis = skeleton.get_bone_global_rest(bone).basis
	var local: Vector3 = (global_rest.inverse() * model_axis).normalized()
	_axes[key] = local
	return local


## Finds (or mounts) a modifier on the first skeleton under `root`. Null when
## there is no skeleton -- the procedural toddler -- which callers treat as "no
## pose to show", never as an error.
static func for_character(root: Node) -> SkeletonModifier3D:
	var skeleton: Skeleton3D = _find_skeleton(root)
	if skeleton == null:
		return null
	var existing: Node = skeleton.get_node_or_null("HeldPose")
	if existing is SkeletonModifier3D:
		return existing
	var modifier: SkeletonModifier3D = (load("res://scripts/interaction/pose_modifier.gd") as GDScript).new()
	modifier.name = "HeldPose"
	skeleton.add_child(modifier)
	return modifier


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null
