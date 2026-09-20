extends SkeletonModifier3D

## ALIZ SEATED AT THE TEACHING TABLE. Her rig ships `walk`, `run` and an
## authored `idle`, and no sit clip -- so, exactly as
## `scripts/interaction/pose_modifier.gd` does for the sofa, this modifier
## bends the joints a seated pose genuinely needs inside the skeleton's own
## modification pass and leaves everything else (idle breath, blink, hair sway)
## running over it. The one addition over the sofa pose: her upper arms come a
## little forward and the forearms fold up, so her hands rest at table height
## instead of hanging through the seat.
##
## Rotations are stated about the MODEL's +X ("nod") axis and converted into
## each bone's rest frame from its global rest pose, so the numbers survive
## whatever local axes the exporter chose. Bones are `LB_Rig_v1` names; a rig
## without one of them simply does not bend that joint. `apply()` is public and
## `settle()` lands the blend at once, for a headless test or a shot harness
## with no frames to ease over.

const BLEND_SECONDS: float = 0.3

## bone -> degrees about the model's X axis; a negative turn swings forward.
const ROTATIONS: Dictionary = {
	"LeftUpLeg": -84.0, "RightUpLeg": -84.0,
	"LeftLeg": 84.0, "RightLeg": 84.0,
	"Spine02": 5.0,
	"LeftArm": -32.0, "RightArm": -32.0,
	"LeftForeArm": -58.0, "RightForeArm": -58.0,
}
## The hips drop by a thigh's length (rig units are centimetres).
const HIP_DROP: float = 26.5
const HIPS_BONE: String = "Hips"

var _influence_now: float = 0.0
var _target_influence: float = 0.0
var _axes: Dictionary = {}


func _ready() -> void:
	active = true


func set_seated(seated: bool) -> void:
	_target_influence = 1.0 if seated else 0.0
	if not is_inside_tree():
		settle()


func is_seated() -> bool:
	return _target_influence > 0.5


func settle() -> void:
	_influence_now = _target_influence
	apply(0.0)


func _process_modification() -> void:
	apply(get_process_delta_time())


func apply(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		skeleton = get_parent() as Skeleton3D
	if skeleton == null:
		return
	if delta > 0.0:
		_influence_now = move_toward(_influence_now, _target_influence, delta / BLEND_SECONDS)
	if _influence_now <= 0.0:
		return
	for bone_name: String in ROTATIONS.keys():
		var bone: int = skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var axis: Vector3 = _local_axis(skeleton, bone, Vector3.RIGHT)
		var rest: Quaternion = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var posed: Quaternion = rest * Quaternion(axis, deg_to_rad(float(ROTATIONS[bone_name])))
		var current: Quaternion = skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, current.slerp(posed, _influence_now))
	var hips: int = skeleton.find_bone(HIPS_BONE)
	if hips >= 0:
		var rest_origin: Vector3 = skeleton.get_bone_rest(hips).origin
		var lowered: Vector3 = rest_origin - Vector3(0.0, HIP_DROP, 0.0)
		var now: Vector3 = skeleton.get_bone_pose_position(hips)
		skeleton.set_bone_pose_position(hips, now.lerp(lowered, _influence_now))


func _local_axis(skeleton: Skeleton3D, bone: int, model_axis: Vector3) -> Vector3:
	var key: String = "%d/%s" % [bone, str(model_axis)]
	if _axes.has(key):
		return _axes[key]
	var global_rest: Basis = skeleton.get_bone_global_rest(bone).basis
	var local: Vector3 = (global_rest.inverse() * model_axis).normalized()
	_axes[key] = local
	return local


## Mounts (or finds) the seat modifier on `skeleton`.
static func mount(skeleton: Skeleton3D) -> SkeletonModifier3D:
	if skeleton == null:
		return null
	var existing: Node = skeleton.get_node_or_null("TutorSeatPose")
	if existing is SkeletonModifier3D:
		return existing
	var modifier: SkeletonModifier3D = (load("res://scripts/tutor/classroom/tutor_seat_pose.gd") as GDScript).new()
	modifier.name = "TutorSeatPose"
	skeleton.add_child(modifier)
	return modifier
