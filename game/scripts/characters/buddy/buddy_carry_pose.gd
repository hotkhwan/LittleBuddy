extends SkeletonModifier3D

## ARMS ROUND THE CHILD -- Aliz's carry pose, applied on top of whatever clip
## her legs are playing.
##
## Aliz ships with `walk` and `run` and nothing else. Both swing the arms, and a
## caregiver whose arms swing freely through the child she is holding is the
## most obvious intersection a carry can have. There is no `carry` clip to
## author against, and writing one for a 24-bone rig by hand for tonight is the
## wrong size of job -- but the arms are four bones, and a fixed pose for four
## bones is a `SkeletonModifier3D`: it runs AFTER the animation has posed the
## skeleton each frame and overrides just those bones, so the legs keep walking
## and running while the arms stay wrapped round the child.
##
## The pose is expressed the way `baby_life_clips.gd::_bone_pose()` expresses
## Bunny's: degrees about SKELETON-space axes, pre-multiplied onto the bone's
## rest in its parent's CURRENT frame -- so "forward" stays forward while the
## torso leans through the run cycle. Same rig family, same sign convention:
## a negative turn about +X swings a limb forward.
##
## `influence` is the stock modifier blend, so the arms can be eased in and out
## rather than snapping, and `active = false` costs nothing.

## Skeleton-space axes. `NOD` is about +X (forward/back), `TILT` about +Z (in/out
## from the body's side), `TURN` about +Y.
const NOD := Vector3(1.0, 0.0, 0.0)
const TURN := Vector3(0.0, 1.0, 0.0)
const TILT := Vector3(0.0, 0.0, 1.0)

## bone -> [[axis, degrees], ...]. Upper arms forward and a little inward, the
## forearms folded up under the child's bottom, the hands turned in to cup it.
## `side` is applied by `pose_for()`: -1 is her left, +1 her right.
static func pose_for() -> Dictionary:
	var pose: Dictionary = {}
	for side: int in [-1, 1]:
		var arm: String = "LeftArm" if side < 0 else "RightArm"
		var forearm: String = "LeftForeArm" if side < 0 else "RightForeArm"
		var hand: String = "LeftHand" if side < 0 else "RightHand"
		var shoulder: String = "LeftShoulder" if side < 0 else "RightShoulder"
		pose[shoulder] = [[TILT, -side * 3.0]]
		pose[arm] = [[NOD, -27.0], [TILT, side * 8.0]]
		pose[forearm] = [[NOD, -8.0], [TILT, side * 15.0]]
		pose[hand] = [[NOD, -10.0], [TILT, side * 12.0]]
	return pose


var pose: Dictionary = pose_for()

## Where `influence` is heading (0 or 1) and how long the trip takes. The
## wrapper may run no frame loop of its own, so the easing lives here, in the
## skeleton's own modification pass.
var target_influence: float = 0.0
var blend_seconds: float = 0.35


## Asks for the arms to wrap (true) or release (false). Switches the modifier
## on so the easing can run; it switches itself off again once released.
func set_target(active: bool) -> void:
	target_influence = 1.0 if active else 0.0
	if active:
		self.active = true


## Jumps straight to the target -- for a node outside the tree, where no
## modification pass will ever ease it.
func settle() -> void:
	influence = target_influence
	self.active = target_influence > 0.0


func is_wrapped() -> bool:
	return target_influence > 0.5


func _process_modification_with_delta(delta: float) -> void:
	_ease(delta)
	apply()


## Older callback name, for a runtime that has not adopted the delta form.
func _process_modification() -> void:
	_ease(1.0 / 60.0)
	apply()


func _ease(delta: float) -> void:
	if is_equal_approx(influence, target_influence):
		if target_influence <= 0.0 and self.active:
			self.active = false
		return
	influence = move_toward(influence, target_influence, delta / maxf(blend_seconds, 0.01))


## One pass over the posed bones. Public so a headless test can run it without
## a frame and read the result back off the skeleton.
func apply() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		# Out of the tree the modifier has not bound to its parent yet (that
		# happens on entering it), and the headless runner never enters. The
		# parent IS the skeleton here, by construction.
		skeleton = get_parent() as Skeleton3D
	if skeleton == null:
		return
	for bone_name: String in pose.keys():
		var index: int = skeleton.find_bone(bone_name)
		if index == -1:
			continue
		var rest: Quaternion = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		var parent: int = skeleton.get_bone_parent(index)
		var to_parent: Basis = Basis()
		if parent != -1:
			to_parent = skeleton.get_bone_global_pose(parent).basis.orthonormalized().inverse()
		var applied: Quaternion = Quaternion.IDENTITY
		for turn: Array in pose[bone_name]:
			var axis: Vector3 = (to_parent * (turn[0] as Vector3)).normalized()
			applied = Quaternion(axis, deg_to_rad(float(turn[1]))) * applied
		skeleton.set_bone_pose_rotation(index, (applied * rest).normalized())
