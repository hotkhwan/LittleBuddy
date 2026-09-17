extends SceneTree

# THROWAWAY. Renders the toddler placeholder so a human can look at it.
const OUT := "/Users/hotkhwan/Projects/little-buddy/render_out"

var _view: Node3D
var _player: AnimationPlayer
var _camera: Camera3D
var _shots: Array = []
var _index: int = 0
var _warm: int = 0
var _phase: int = 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(1.0, 0.965, 0.898)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.92, 0.91, 0.87)
	e.ambient_light_energy = 0.95
	env.environment = e
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0.0)
	light.light_energy = 1.1
	world.add_child(light)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.839, 0.729, 0.588)
	fm.roughness = 1.0
	floor_mesh.material_override = fm
	world.add_child(floor_mesh)

	_view = load("res://scripts/character/toddler_view.gd").new()
	world.add_child(_view)
	_view.call("build")
	_player = _view.call("get_animation_player")

	_camera = Camera3D.new()
	_camera.fov = 50.0
	world.add_child(_camera)
	_camera.current = true

	# name, clip, seek time, camera pos, look at
	var body_cam := Vector3(0.62, 0.66, -1.42)
	var body_at := Vector3(0.0, 0.44, 0.0)
	var front_cam := Vector3(0.0, 0.62, -1.45)
	_shots = [
		["face",      "idle",      0.4,  Vector3(0.06, 0.735, -0.44), Vector3(0.0, 0.70, 0.0)],
		["face_flat", "idle",      0.4,  Vector3(0.0, 0.70, -0.42),   Vector3(0.0, 0.70, 0.0)],
		["idle",      "idle",      0.6,  body_cam, body_at],
		["idle_front","idle",      0.6,  front_cam, body_at],
		["walk_a",    "walk",      0.0,  body_cam, body_at],
		["walk_b",    "walk",      0.32, body_cam, body_at],
		["eat",       "eat",       0.62, body_cam, body_at],
		["eat_front", "eat",       0.62, front_cam, body_at],
		["drink",     "drink",     0.95, body_cam, body_at],
		["drink_front","drink",    0.95, front_cam, body_at],
		["hug",       "hug",       1.25, body_cam, body_at],
		["hug_front", "hug",       1.25, front_cam, body_at],
		["sleep",     "sleep",     1.0,  Vector3(0.05, 0.95, -1.30), Vector3(0.0, 0.10, 0.0)],
		["sit",       "sit",       1.0,  Vector3(0.45, 0.55, -1.20), Vector3(0.0, 0.22, 0.0)],
		["carryIdle", "carryIdle", 1.0,  body_cam, body_at],
		["celebrate", "celebrate", 0.7,  body_cam, body_at],
		["blink",     "idle",      2.05, Vector3(0.0, 0.70, -0.42), Vector3(0.0, 0.70, 0.0)],
	]

func _process(_delta: float) -> bool:
	_warm += 1
	if _warm < 4:
		return false
	if _index >= _shots.size():
		print("done: %d shots" % _shots.size())
		return true
	var shot: Array = _shots[_index]
	if _phase == 0:
		_camera.position = shot[3]
		_camera.look_at(shot[4], Vector3.UP)
		_player.play(String(shot[1]))
		_player.seek(float(shot[2]), true)
		_phase = 1
		return false
	if _phase < 3:
		_phase += 1
		return false
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT, String(shot[0])])
	_index += 1
	_phase = 0
	return false
