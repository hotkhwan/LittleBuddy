extends Node3D

## ============================================================================
## TEMPORARY ENGINEERING ART. NOT THE TODDLER.
## ============================================================================
##
## A primitive stand-in for Little Buddy as a toddler: eight boxes, spheres and
## capsules, roughly 0.85 m tall, with exactly two placeholder animations --
## `idle` and `walk`. It exists to prove the SEAM, not to look like a child.
## The real model comes from the art pipeline later; when it arrives this node is
## deleted and **nothing above it changes**, because:
##
##   * `LittleBuddyCharacter` finds an `AnimationPlayer` anywhere in its subtree
##     and drives it only through SEMANTIC action names ("walk", "drink",
##     "brushTeeth") -- never a clip name;
##   * the movement, facing, arrival and interaction-ready behaviour all live in
##     `character_movement_controller.gd`, which holds no node at all.
##
## Do not tidy this up, do not add features to it, and do not let content or
## missions reference it. The full action vocabulary (eat, drink, sit, sleep,
## brushTeeth, hug, pickUp, give, celebrate) is deliberately NOT implemented:
## asking for one of those today is a short pause that still completes cleanly,
## which is exactly the behaviour `test_character_actions.gd` pins down.
##
## Scale is the one thing here that IS real, because the whole greybox house is
## dimensioned against it (contract §3): a toddler is ~0.85 m tall, which is why
## a door is 1.9 m and a counter is 0.9 m.

## Overall height, metres. The house is built to this.
const HEIGHT: float = 0.85

const SHIRT_COLOR: Color = Color(0.45, 0.74, 0.9)
const TROUSER_COLOR: Color = Color(0.36, 0.46, 0.68)
const SKIN_COLOR: Color = Color(1.0, 0.87, 0.74)
const EYE_COLOR: Color = Color(0.22, 0.16, 0.14)
const NOSE_COLOR: Color = Color(1.0, 0.72, 0.7)
const HAIR_COLOR: Color = Color(0.35, 0.24, 0.18)

## Toddler proportions: a big head on a short body. Wrong proportions are the
## fastest way to make a placeholder read as "small adult" instead of "toddler",
## and that would mislead every judgement about camera framing and scale.
const LEG_HEIGHT: float = 0.22
const LEG_RADIUS: float = 0.045
const TORSO_HEIGHT: float = 0.36
const TORSO_RADIUS: float = 0.115
const HEAD_RADIUS: float = 0.135
const HEAD_Y: float = 0.70

var _animation_player: AnimationPlayer = null
var _body: Node3D = null
var _built: bool = false


func _ready() -> void:
	build()


## Idempotent and callable before `_ready()` -- the headless `--script` runner
## never fires `_ready()` for nodes added to the root.
func build() -> void:
	if _built:
		return
	_built = true
	_build_body()
	_build_animations()


func get_animation_player() -> AnimationPlayer:
	build()
	return _animation_player


## -- Body ----------------------------------------------------------------------

func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	for side: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegLeft" if side < 0.0 else "LegRight"
		# Pivot at the hip, so the walk animation can swing the leg rather than
		# slide it.
		leg.position = Vector3(side * 0.055, LEG_HEIGHT, 0.0)
		_body.add_child(leg)
		var limb := MeshInstance3D.new()
		limb.name = "Mesh"
		var limb_mesh := CapsuleMesh.new()
		limb_mesh.radius = LEG_RADIUS
		limb_mesh.height = LEG_HEIGHT + LEG_RADIUS
		limb.mesh = limb_mesh
		limb.material_override = _material(TROUSER_COLOR)
		limb.position = Vector3(0.0, -LEG_HEIGHT * 0.5, 0.0)
		leg.add_child(limb)

	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = TORSO_RADIUS
	torso_mesh.height = TORSO_HEIGHT + TORSO_RADIUS
	torso.mesh = torso_mesh
	torso.material_override = _material(SHIRT_COLOR)
	torso.position = Vector3(0.0, LEG_HEIGHT + TORSO_HEIGHT * 0.5, 0.0)
	_body.add_child(torso)

	for side: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.name = "ArmLeft" if side < 0.0 else "ArmRight"
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.038
		arm_mesh.height = 0.2
		arm.mesh = arm_mesh
		arm.material_override = _material(SKIN_COLOR)
		arm.position = Vector3(side * (TORSO_RADIUS + 0.03), LEG_HEIGHT + TORSO_HEIGHT * 0.55, 0.0)
		_body.add_child(arm)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = HEAD_RADIUS
	head_mesh.height = HEAD_RADIUS * 2.0
	head.mesh = head_mesh
	head.material_override = _material(SKIN_COLOR)
	head.position = Vector3(0.0, HEAD_Y, 0.0)
	_body.add_child(head)

	var hair := MeshInstance3D.new()
	hair.name = "Hair"
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = HEAD_RADIUS * 0.96
	hair_mesh.height = HEAD_RADIUS * 1.5
	hair.mesh = hair_mesh
	hair.material_override = _material(HAIR_COLOR)
	hair.position = Vector3(0.0, HEAD_Y + HEAD_RADIUS * 0.42, 0.01)
	_body.add_child(hair)

	# A nose and two eyes, purely so a reviewer can tell at a glance which way
	# Little Buddy is facing. Turning to face a thing on arrival is a required
	# behaviour, and you cannot judge it from the back of a head.
	var nose := MeshInstance3D.new()
	nose.name = "Nose"
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = 0.028
	nose_mesh.height = 0.056
	nose.mesh = nose_mesh
	nose.material_override = _material(NOSE_COLOR)
	nose.position = Vector3(0.0, HEAD_Y - 0.01, -HEAD_RADIUS * 0.95)
	_body.add_child(nose)

	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "EyeLeft" if side < 0.0 else "EyeRight"
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.024
		eye_mesh.height = 0.048
		eye.mesh = eye_mesh
		eye.material_override = _material(EYE_COLOR)
		eye.position = Vector3(side * 0.052, HEAD_Y + 0.035, -HEAD_RADIUS * 0.88)
		_body.add_child(eye)


## -- Placeholder animations ----------------------------------------------------

func _build_animations() -> void:
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "AnimationPlayer"
	add_child(_animation_player)

	var library := AnimationLibrary.new()
	library.add_animation("idle", _make_idle())
	library.add_animation("walk", _make_walk())
	_animation_player.add_animation_library("", library)
	_animation_player.play("idle")


## Gentle breathing bob. A toddler standing still is never completely still.
func _make_idle() -> Animation:
	var animation := Animation.new()
	animation.length = 2.4
	animation.loop_mode = Animation.LOOP_LINEAR
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, "Body:position")
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, 1.2, Vector3(0.0, 0.016, 0.0))
	animation.track_insert_key(track, 2.4, Vector3.ZERO)
	return animation


## A toddler stride: short, bouncy, slightly unsteady, with the legs actually
## swinging. Placeholder, but it must read as walking rather than sliding --
## that is the one thing you cannot judge about movement speed without it.
func _make_walk() -> Animation:
	var animation := Animation.new()
	animation.length = 0.64
	animation.loop_mode = Animation.LOOP_LINEAR

	var bob: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(bob, "Body:position")
	animation.track_insert_key(bob, 0.0, Vector3.ZERO)
	animation.track_insert_key(bob, 0.16, Vector3(0.0, 0.035, 0.0))
	animation.track_insert_key(bob, 0.32, Vector3.ZERO)
	animation.track_insert_key(bob, 0.48, Vector3(0.0, 0.035, 0.0))
	animation.track_insert_key(bob, 0.64, Vector3.ZERO)

	var sway: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(sway, "Body:rotation")
	animation.track_insert_key(sway, 0.0, Vector3(0.0, 0.0, deg_to_rad(-5.0)))
	animation.track_insert_key(sway, 0.32, Vector3(0.0, 0.0, deg_to_rad(5.0)))
	animation.track_insert_key(sway, 0.64, Vector3(0.0, 0.0, deg_to_rad(-5.0)))

	var swing: float = deg_to_rad(26.0)
	for leg: String in ["LegLeft", "LegRight"]:
		var lead: float = 1.0 if leg == "LegLeft" else -1.0
		var track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, "Body/%s:rotation" % leg)
		animation.track_insert_key(track, 0.0, Vector3(swing * lead, 0.0, 0.0))
		animation.track_insert_key(track, 0.32, Vector3(-swing * lead, 0.0, 0.0))
		animation.track_insert_key(track, 0.64, Vector3(swing * lead, 0.0, 0.0))
	return animation


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
