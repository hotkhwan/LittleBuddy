extends SkeletonModifier3D

## HAIR SWAY -- Aliz's long hair reads as moving, without a single hair bone.
##
## Her rig is the 24-bone `LB_Rig_v1` family: no hair bones, no secondary
## chain, nothing a spring could drive. What she does have is a head bone that
## the whole mass of hair is skinned to. Rotating that bone by a fraction of a
## degree on a slow sine moves the hair tips (60 cm below the pivot) by a few
## millimetres while the face barely turns -- which is what "her hair sways"
## looks like from across a room. Vertex-free, bone-free, and honest about it.
##
## A `SkeletonModifier3D`, so it runs AFTER whatever clip has posed the
## skeleton this frame and is layered onto the CURRENT head pose rather than
## the rest -- the sway rides the idle's head bob and the walk's head motion
## alike. Two sines at unrelated periods so it never reads as a metronome.
## `influence` is the stock blend; `active = false` costs nothing.
##
## The amplitude is deliberately tiny. +-0.4 degrees of tilt is the brief's
## number and it is the right one: at +-1 degree the FACE visibly wobbles, and a
## caregiver whose head rocks is a worse thing than still hair.

const TURN := Vector3(0.0, 1.0, 0.0)
const TILT := Vector3(0.0, 0.0, 1.0)

const HEAD_BONE: String = "Head"

## Degrees and seconds.
const TILT_AMP_DEG: float = 0.4
const TILT_PERIOD_SEC: float = 2.7
const TURN_AMP_DEG: float = 0.25
const TURN_PERIOD_SEC: float = 4.1

var _time: float = 0.0


## The sway angles (tilt, turn) in degrees at `seconds`. Public so a headless
## test can check the envelope without a frame.
static func angles_at(seconds: float) -> Vector2:
	return Vector2(
		TILT_AMP_DEG * sin(TAU * seconds / TILT_PERIOD_SEC),
		TURN_AMP_DEG * sin(TAU * seconds / TURN_PERIOD_SEC))


func get_time() -> float:
	return _time


func _process_modification_with_delta(delta: float) -> void:
	_time += delta
	apply()


## Older callback name, for a runtime that has not adopted the delta form.
func _process_modification() -> void:
	_time += 1.0 / 60.0
	apply()


## Advances the clock by `seconds` and applies -- for tests and for anything
## that wants to sample the sway outside the modification pass.
func step(seconds: float) -> void:
	_time += seconds
	apply()


## One pass: the current head pose, tilted and turned by the sines, in the
## parent's current frame (so "sideways" is sideways however the spine leans).
func apply() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		skeleton = get_parent() as Skeleton3D
	if skeleton == null:
		return
	var index: int = skeleton.find_bone(HEAD_BONE)
	if index == -1:
		return
	var sway: Vector2 = angles_at(_time)
	var parent: int = skeleton.get_bone_parent(index)
	var to_parent: Basis = Basis()
	if parent != -1:
		to_parent = skeleton.get_bone_global_pose(parent).basis.orthonormalized().inverse()
	var tilt := Quaternion((to_parent * TILT).normalized(), deg_to_rad(sway.x))
	var turn := Quaternion((to_parent * TURN).normalized(), deg_to_rad(sway.y))
	var current: Quaternion = skeleton.get_bone_pose_rotation(index)
	skeleton.set_bone_pose_rotation(index, (turn * tilt * current).normalized())
