extends Node3D
## Renders the evidence shots for the runtime Little Buddy. Temporary, dev-only.
##
##   Godot --path game res://scenes/spike/runtime_character_shots.tscn
##
## Writes PNGs to docs/shots/. Needs a real rendering device, so it runs windowed
## rather than headless -- Godot's headless display server has no framebuffer to
## capture. It quits itself when the last shot is written.
##
## The project's own art history is the reason this exists rather than a list of
## assertions: ART_UPGRADE_REPORT.md records a smile that shipped as a frown
## through three render passes. Geometry checks cannot see that. Looking can.

const BabyScript := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
const OUT_DIR := "docs/shots/"

## name -> { cam position, look-at target, clip, clip time fraction, markers }
var _shots: Array = []
var _index: int = -1
var _baby: Node3D
var _camera: Camera3D
var _props: Node3D
var _settle := 0


func _ready() -> void:
	_baby = BabyScript.new()
	add_child(_baby)
	_baby.call("build")
	# The wrapper turns the model so yaw 0 faces -Z, which is the project's
	# character convention. These shots frame it from +Z, so apply the same yaw
	# Chapter 2 scenes apply -- without it every shot is the back of its head,
	# which is exactly the silent failure the wrapper's class doc warns about.
	_baby.rotation_degrees.y = BabyScript.CHAPTER_2_YAW_DEG
	_props = Node3D.new()
	add_child(_props)
	_camera = $Camera3D

	var head: Vector3 = (_baby.call("get_socket", "head") as Node3D).global_position
	var knee_y: float = 0.78 * 0.16

	_shots = [
		{"name": "runtime_baby_standing", "clip": "", "t": 0.0,
		 "cam": Vector3(0.0, 0.52, 1.15), "at": Vector3(0.0, 0.40, 0.0), "fov": 40.0},
		{"name": "runtime_baby_walk", "clip": "walk", "t": 0.25,
		 "cam": Vector3(0.85, 0.48, 0.95), "at": Vector3(0.0, 0.38, 0.0), "fov": 42.0},
		{"name": "runtime_baby_run", "clip": "run", "t": 0.35,
		 "cam": Vector3(0.85, 0.48, 0.95), "at": Vector3(0.0, 0.38, 0.0), "fov": 42.0},
		# The `head` socket is the Head BONE, which sits at the base of the skull
		# (48% of height) -- aiming the camera there frames the chin. The face
		# itself is centred around 72% of the character's height.
		{"name": "runtime_baby_face", "clip": "", "t": 0.0,
		 "cam": Vector3(0.10, 0.78 * 0.76, 0.80), "at": Vector3(0.0, 0.78 * 0.70, 0.0), "fov": 30.0},
		{"name": "runtime_baby_knees_stride", "clip": "walk", "t": 0.5,
		 "cam": Vector3(0.0, knee_y + 0.14, 0.60), "at": Vector3(0.0, knee_y + 0.02, 0.0), "fov": 34.0},
		{"name": "runtime_baby_knees_stride_front", "clip": "walk", "t": 0.75,
		 "cam": Vector3(0.42, knee_y + 0.12, 0.52), "at": Vector3(0.0, knee_y + 0.02, 0.0), "fov": 34.0},
		{"name": "runtime_baby_feeding", "clip": "", "t": 0.0, "prop": "bottle",
		 "cam": Vector3(0.0, 0.52, 0.62), "at": Vector3(0.0, 0.49, 0.0), "fov": 34.0},
		{"name": "runtime_baby_hug", "clip": "", "t": 0.0, "prop": "teddy",
		 "cam": Vector3(0.22, 0.50, 0.80), "at": Vector3(0.0, 0.42, 0.0), "fov": 36.0},
	]
	_next()


func _next() -> void:
	_index += 1
	if _index >= _shots.size():
		print("all shots written to %s" % OUT_DIR)
		get_tree().quit(0)
		return
	var shot: Dictionary = _shots[_index]

	for child in _props.get_children():
		child.queue_free()

	var player: AnimationPlayer = _baby.call("get_animation_player")
	var clip: String = String(shot.get("clip", ""))
	if player != null:
		if clip.is_empty():
			player.stop()
		elif player.has_animation(clip):
			player.play(clip)
			player.seek(player.get_animation(clip).length * float(shot["t"]), true)
			player.pause()

	if shot.has("prop"):
		_place_prop(String(shot["prop"]))

	_camera.fov = float(shot.get("fov", 40.0))
	_camera.position = shot["cam"]
	_camera.look_at(shot["at"], Vector3.UP)
	_settle = 4


## Props are placed ON the semantic socket, never at a hardcoded offset -- the
## point of the shot is that the socket is where the bottle actually goes.
##
## They are parented to the SCENE, not to the socket, and positioned from the
## socket's global transform. Parenting into the skeleton would put the prop in
## bone-local space, which on this rig is centimetres under a 0.01 armature
## scale -- a 10 cm bottle then renders half a millimetre wide and vanishes.
## That is the same units trap that collapsed the mouth offset; it bites props
## too, and world-space placement sidesteps it entirely.
func _place_prop(kind: String) -> void:
	var socket_name := "mouth" if kind == "bottle" else "hugTarget"
	var socket: Node3D = _baby.call("get_socket", socket_name)
	if socket == _baby:
		return
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	var forward: Vector3 = -_baby.global_transform.basis.z.normalized()
	var offset: Vector3
	if kind == "bottle":
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.018
		capsule.height = 0.085
		mi.mesh = capsule
		mat.albedo_color = Color(0.98, 0.95, 0.88)
		offset = forward * 0.045
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.06
		sphere.height = 0.12
		mi.mesh = sphere
		mat.albedo_color = Color(0.80, 0.52, 0.30)
		offset = forward * 0.07
	mat.roughness = 0.95
	mi.material_override = mat
	_props.add_child(mi)
	mi.global_position = socket.global_position + offset
	if kind == "bottle":
		mi.look_at(socket.global_position, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))


func _process(_delta: float) -> void:
	if _settle <= 0:
		return
	_settle -= 1
	if _settle > 0:
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = OUT_DIR + String(_shots[_index]["name"]) + ".png"
	var absolute: String = ProjectSettings.globalize_path("res://../" + path)
	var err: int = image.save_png(absolute)
	print("  %s -> %s" % ["ok " if err == OK else "FAIL", path])
	_next()
