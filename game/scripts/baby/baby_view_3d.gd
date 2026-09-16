extends Node3D
class_name BabyView3D

## Baby built entirely from built-in primitive meshes (SphereMesh/CapsuleMesh)
## with plain StandardMaterial3D — zero external art dependency, mirroring
## the old 2D BabyView's "draw with primitives" approach.
##
## Keeps the exact same public API the 2D view exposed so FeedActivity
## (presentation-agnostic; only calls `set_view_state` via duck typing on a
## plain Node) needs no behavioural change:
##   set_view_state("idle" | "hungry" | "drinking" | "happy" | "hugging")
##   get_view_state_name() -> String
##
## Also exposes get_mouth_position() / get_hug_position() (GLOBAL) for
## INTERACT to place drop zones. Both are derived from real child-node
## transforms every call, so they always track restyles/animation and are
## never hardcoded constants that could drift from the mesh.
##
## Reactions are driven by a single AnimationPlayer holding five short,
## cheap, looping animations (gentle idle bob, hungry rock, drinking tilt,
## happy bounce, hugging arm-bring-in) built procedurally in code.

enum ViewState { IDLE, HUNGRY, DRINKING, HAPPY, HUGGING }

const STATE_NAMES: Dictionary = {
	"idle": ViewState.IDLE,
	"hungry": ViewState.HUNGRY,
	"drinking": ViewState.DRINKING,
	"happy": ViewState.HAPPY,
	"hugging": ViewState.HUGGING,
}

const SKIN_COLOR: Color = Color(1.0, 0.87, 0.73)
const CHEEK_COLOR: Color = Color(1.0, 0.62, 0.6)
const EYE_COLOR: Color = Color(0.25, 0.18, 0.15)
const EYE_HIGHLIGHT_COLOR: Color = Color(1.0, 1.0, 1.0)
const MOUTH_COLOR: Color = Color(0.85, 0.45, 0.42)
const OUTFIT_COLOR: Color = Color(0.6, 0.8, 0.95)
const HAIR_COLOR: Color = Color(0.55, 0.38, 0.28)

var _state: int = ViewState.IDLE
var _animation_player: AnimationPlayer = null
var _body: Node3D = null
var _head: Node3D = null
var _mouth_marker: Node3D = null
var _hug_marker: Node3D = null
var _left_arm_pivot: Node3D = null
var _right_arm_pivot: Node3D = null


func _ready() -> void:
	_build_body()
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "AnimationPlayer"
	add_child(_animation_player)
	_build_animations()
	_animation_player.play("idle")


## Accepts "idle" | "hungry" | "drinking" | "happy" | "hugging". Unknown
## values fall back to idle so a scene mistake never crashes the baby.
func set_view_state(state_name: String) -> void:
	_state = STATE_NAMES.get(state_name, ViewState.IDLE)
	if _animation_player == null:
		return
	var anim_name: String = state_name if STATE_NAMES.has(state_name) else "idle"
	if _animation_player.has_animation(anim_name) and _animation_player.current_animation != anim_name:
		_animation_player.play(anim_name)


func get_view_state_name() -> String:
	for key: String in STATE_NAMES.keys():
		if STATE_NAMES[key] == _state:
			return key
	return "idle"


## GLOBAL position of the baby's mouth. Derived live from the mouth marker's
## transform (child of the animated Head node) so it always tracks head
## tilts/restyles instead of drifting from a hardcoded constant.
func get_mouth_position() -> Vector3:
	if _mouth_marker != null:
		return _mouth_marker.global_position
	return global_position


## GLOBAL position of the baby's chest/arms. Derived live from the hug
## marker's transform (child of the animated Body node).
func get_hug_position() -> Vector3:
	if _hug_marker != null:
		return _hug_marker.global_position
	return global_position


## -- Construction (primitives only) --------------------------------------

func _make_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat


func _make_sphere(radius: float, color: Color, local_position: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	# Low-poly budget: the engine default (32 radial segments / 16 rings) is
	# far more geometry than these small blobby shapes need.
	mesh.radial_segments = 12
	mesh.rings = 8
	instance.mesh = mesh
	instance.material_override = _make_material(color)
	instance.position = local_position
	instance.scale = scale
	return instance


## A short capsule used as an upper-arm/forearm segment, its long axis
## rotated onto local X so it can bridge a shoulder pivot to a hand blob
## (capsules default to a vertical Y-axis).
func _make_arm_segment(radius: float, length: float, color: Color, local_position: Vector3, z_rotation_deg: float) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length
	mesh.radial_segments = 8
	mesh.rings = 2
	instance.mesh = mesh
	instance.material_override = _make_material(color)
	instance.position = local_position
	instance.rotation_degrees = Vector3(0.0, 0.0, z_rotation_deg)
	return instance


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	# Chubby, short torso.
	var torso: MeshInstance3D = MeshInstance3D.new()
	torso.name = "Torso"
	var torso_mesh: CapsuleMesh = CapsuleMesh.new()
	torso_mesh.radius = 0.17
	torso_mesh.height = 0.40
	torso_mesh.radial_segments = 12
	torso_mesh.rings = 4
	torso.mesh = torso_mesh
	torso.material_override = _make_material(OUTFIT_COLOR)
	torso.position = Vector3(0.0, 0.24, 0.0)
	_body.add_child(torso)

	# Short stubby legs peeking out from under the torso.
	_body.add_child(_make_sphere(0.075, SKIN_COLOR, Vector3(-0.085, 0.04, 0.05)))
	_body.add_child(_make_sphere(0.075, SKIN_COLOR, Vector3(0.085, 0.04, 0.05)))

	# Arms: pivots at the shoulder so the hugging animation can swing the
	# whole arm forward without hardcoding a hand position anywhere else.
	# Each arm is an upper-arm capsule (bridging the shoulder to the hand,
	# overlapping the torso on one end and the hand blob on the other) plus
	# a small hand sphere at the tip — this keeps the arm visually attached
	# to the body instead of a floating detached hand.
	_left_arm_pivot = Node3D.new()
	_left_arm_pivot.name = "LeftArmPivot"
	_left_arm_pivot.position = Vector3(-0.19, 0.32, 0.02)
	_body.add_child(_left_arm_pivot)
	_left_arm_pivot.add_child(_make_arm_segment(0.045, 0.13, SKIN_COLOR, Vector3(-0.045, 0.0, 0.0), 90.0))
	_left_arm_pivot.add_child(_make_sphere(0.065, SKIN_COLOR, Vector3(-0.09, 0.0, 0.0)))

	_right_arm_pivot = Node3D.new()
	_right_arm_pivot.name = "RightArmPivot"
	_right_arm_pivot.position = Vector3(0.19, 0.32, 0.02)
	_body.add_child(_right_arm_pivot)
	_right_arm_pivot.add_child(_make_arm_segment(0.045, 0.13, SKIN_COLOR, Vector3(0.045, 0.0, 0.0), -90.0))
	_right_arm_pivot.add_child(_make_sphere(0.065, SKIN_COLOR, Vector3(0.09, 0.0, 0.0)))

	# Hug marker: front of the chest, roughly where hugging arms would meet.
	_hug_marker = Node3D.new()
	_hug_marker.name = "HugMarker"
	_hug_marker.position = Vector3(0.0, 0.27, 0.2)
	_body.add_child(_hug_marker)

	# Big friendly head.
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 0.50, 0.0)
	_body.add_child(_head)

	var head_mesh_instance: MeshInstance3D = MeshInstance3D.new()
	head_mesh_instance.name = "HeadMesh"
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = 0.19
	head_mesh.height = 0.38
	head_mesh.radial_segments = 16
	head_mesh.rings = 10
	head_mesh_instance.mesh = head_mesh
	head_mesh_instance.material_override = _make_material(SKIN_COLOR)
	_head.add_child(head_mesh_instance)

	# A wisp of hair on top — cheap, cute, no sharp features.
	_head.add_child(_make_sphere(0.05, HAIR_COLOR, Vector3(0.0, 0.19, 0.05), Vector3(0.7, 1.1, 0.7)))

	# Soft rosy cheeks.
	_head.add_child(_make_sphere(0.035, CHEEK_COLOR, Vector3(-0.1, -0.02, 0.14)))
	_head.add_child(_make_sphere(0.035, CHEEK_COLOR, Vector3(0.1, -0.02, 0.14)))

	# Eyes with tiny highlight dots for a friendly sparkle.
	_head.add_child(_make_sphere(0.024, EYE_COLOR, Vector3(-0.075, 0.03, 0.17)))
	_head.add_child(_make_sphere(0.024, EYE_COLOR, Vector3(0.075, 0.03, 0.17)))
	_head.add_child(_make_sphere(0.008, EYE_HIGHLIGHT_COLOR, Vector3(-0.068, 0.038, 0.19)))
	_head.add_child(_make_sphere(0.008, EYE_HIGHLIGHT_COLOR, Vector3(0.082, 0.038, 0.19)))

	# Simple smiling mouth: a small flattened, widened sphere.
	_mouth_marker = _make_sphere(0.022, MOUTH_COLOR, Vector3(0.0, -0.07, 0.18), Vector3(1.4, 0.7, 0.6))
	_mouth_marker.name = "MouthMarker"
	_head.add_child(_mouth_marker)


## -- Animation (single AnimationPlayer, five cheap looping clips) --------

func _make_animation(length: float) -> Animation:
	var anim: Animation = Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	return anim


func _add_track(anim: Animation, node_name: String, property: String, keys: Array) -> void:
	var track_index: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_index, NodePath("%s:%s" % [node_name, property]))
	anim.track_set_interpolation_type(track_index, Animation.INTERPOLATION_LINEAR)
	for key: Array in keys:
		anim.track_insert_key(track_index, key[0], key[1])


func _build_animations() -> void:
	var library: AnimationLibrary = AnimationLibrary.new()

	# Idle: gentle vertical bob.
	var idle_anim: Animation = _make_animation(1.6)
	_add_track(idle_anim, "Body", "position:y", [[0.0, 0.0], [0.8, 0.02], [1.6, 0.0]])
	library.add_animation("idle", idle_anim)

	# Hungry: slow side-to-side rock.
	var hungry_anim: Animation = _make_animation(0.8)
	_add_track(hungry_anim, "Body", "rotation:z", [
		[0.0, deg_to_rad(-4.0)], [0.4, deg_to_rad(4.0)], [0.8, deg_to_rad(-4.0)],
	])
	library.add_animation("hungry", hungry_anim)

	# Drinking: head tilts back briefly, repeating. Path is relative to the
	# AnimationPlayer's parent (this BabyView3D node), so "Body/Head" is the
	# correct nested path — Head lives under Body, not directly under root.
	var drinking_anim: Animation = _make_animation(0.6)
	_add_track(drinking_anim, "Body/Head", "rotation:x", [
		[0.0, 0.0], [0.3, deg_to_rad(-18.0)], [0.6, 0.0],
	])
	library.add_animation("drinking", drinking_anim)

	# Happy: quick bounce.
	var happy_anim: Animation = _make_animation(0.5)
	_add_track(happy_anim, "Body", "position:y", [[0.0, 0.0], [0.25, 0.07], [0.5, 0.0]])
	library.add_animation("happy", happy_anim)

	# Hugging: both arms swing forward/inward toward the chest and gently
	# ease back out, looping like a soft, repeated squeeze.
	var hugging_anim: Animation = _make_animation(1.1)
	_add_track(hugging_anim, "Body/LeftArmPivot", "rotation:y", [
		[0.0, 0.0], [0.3, deg_to_rad(70.0)], [0.85, deg_to_rad(70.0)], [1.1, 0.0],
	])
	_add_track(hugging_anim, "Body/RightArmPivot", "rotation:y", [
		[0.0, 0.0], [0.3, deg_to_rad(-70.0)], [0.85, deg_to_rad(-70.0)], [1.1, 0.0],
	])
	_add_track(hugging_anim, "Body", "rotation:x", [
		[0.0, 0.0], [0.3, deg_to_rad(-5.0)], [0.85, deg_to_rad(-5.0)], [1.1, 0.0],
	])
	library.add_animation("hugging", hugging_anim)

	_animation_player.add_animation_library("", library)
