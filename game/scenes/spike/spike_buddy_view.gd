extends Node3D

## Placeholder Little Buddy body for the navigation spike: primitives only, no
## art dependency, and exactly two animations -- `idle` and `walk`.
##
## This exists to prove the *seam*, not to look like anything. The point is that
## `LittleBuddyCharacter` finds an `AnimationPlayer` anywhere in its subtree and
## drives it exclusively through semantic action names, so when a rigged model
## with a real walk cycle arrives, this node is deleted and nothing above it
## changes.
##
## The action vocabulary the game will eventually need (eat, drink, sit, sleep,
## brushTeeth, hug, pickUp, give, celebrate) is deliberately NOT implemented here.
## Asking for one of those today is a no-op that still completes -- which is the
## behaviour `test_character_actions.gd` pins down.

const BODY_COLOR: Color = Color(0.45, 0.74, 0.9)
const SKIN_COLOR: Color = Color(1.0, 0.87, 0.74)
const EYE_COLOR: Color = Color(0.22, 0.16, 0.14)
const NOSE_COLOR: Color = Color(1.0, 0.72, 0.7)

const BODY_HEIGHT: float = 0.34
const BODY_RADIUS: float = 0.15
const HEAD_RADIUS: float = 0.16
const HEAD_Y: float = 0.62

var _animation_player: AnimationPlayer = null
var _body: Node3D = null
var _built: bool = false


func _ready() -> void:
	build()


## Idempotent and callable before `_ready()` -- the headless runner never fires
## `_ready()` for nodes added to the root.
func build() -> void:
	if _built:
		return
	_built = true
	_build_body()
	_build_animations()


func get_animation_player() -> AnimationPlayer:
	build()
	return _animation_player


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = BODY_RADIUS
	torso_mesh.height = BODY_HEIGHT + BODY_RADIUS * 2.0
	torso.mesh = torso_mesh
	torso.material_override = _material(BODY_COLOR)
	torso.position = Vector3(0.0, 0.3, 0.0)
	_body.add_child(torso)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = HEAD_RADIUS
	head_mesh.height = HEAD_RADIUS * 2.0
	head.mesh = head_mesh
	head.material_override = _material(SKIN_COLOR)
	head.position = Vector3(0.0, HEAD_Y, 0.0)
	_body.add_child(head)

	# A nose, purely so a reviewer can tell at a glance which way Little Buddy is
	# facing. Turning to face an object is a required behaviour; without a visible
	# front you cannot see whether it happened.
	var nose := MeshInstance3D.new()
	nose.name = "Nose"
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = 0.045
	nose_mesh.height = 0.09
	nose.mesh = nose_mesh
	nose.material_override = _material(NOSE_COLOR)
	nose.position = Vector3(0.0, HEAD_Y - 0.01, -HEAD_RADIUS)
	_body.add_child(nose)

	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "EyeLeft" if side < 0.0 else "EyeRight"
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.028
		eye_mesh.height = 0.056
		eye.mesh = eye_mesh
		eye.material_override = _material(EYE_COLOR)
		eye.position = Vector3(side * 0.06, HEAD_Y + 0.045, -HEAD_RADIUS * 0.86)
		_body.add_child(eye)


func _build_animations() -> void:
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "AnimationPlayer"
	add_child(_animation_player)

	var library := AnimationLibrary.new()
	library.add_animation("idle", _make_idle())
	library.add_animation("walk", _make_walk())
	_animation_player.add_animation_library("", library)
	_animation_player.play("idle")


## Gentle breathing bob.
func _make_idle() -> Animation:
	var animation := Animation.new()
	animation.length = 2.4
	animation.loop_mode = Animation.LOOP_LINEAR
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, "Body:position")
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, 1.2, Vector3(0.0, 0.018, 0.0))
	animation.track_insert_key(track, 2.4, Vector3.ZERO)
	return animation


## A stride: a bouncing step plus a slight lean. Placeholder, but it reads as
## walking rather than sliding, which is the one thing the spike needs to judge
## whether the movement speed feels calm enough for a small child.
func _make_walk() -> Animation:
	var animation := Animation.new()
	animation.length = 0.72
	animation.loop_mode = Animation.LOOP_LINEAR
	var bob: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(bob, "Body:position")
	animation.track_insert_key(bob, 0.0, Vector3.ZERO)
	animation.track_insert_key(bob, 0.18, Vector3(0.0, 0.05, 0.0))
	animation.track_insert_key(bob, 0.36, Vector3.ZERO)
	animation.track_insert_key(bob, 0.54, Vector3(0.0, 0.05, 0.0))
	animation.track_insert_key(bob, 0.72, Vector3.ZERO)

	var lean: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(lean, "Body:rotation")
	animation.track_insert_key(lean, 0.0, Vector3(0.0, 0.0, deg_to_rad(-4.0)))
	animation.track_insert_key(lean, 0.36, Vector3(0.0, 0.0, deg_to_rad(4.0)))
	animation.track_insert_key(lean, 0.72, Vector3(0.0, 0.0, deg_to_rad(-4.0)))
	return animation


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
