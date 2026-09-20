extends SceneTree
## Bunny's faces and reactions on the REAL rigged model, under the house's own
## light, at the feeding-portrait distance -- deterministic, no house, no
## mission, so a texture or clip edit can be judged in one run.
##
##   Godot --path game --script ../tools/bunny_shots.gd -- <prefix> [W H]
##
## Writes docs/shots/<prefix>_<cell>_far.png (the game's closest framing:
## `camera_framing.gd::FOCUS_MIN_DISTANCE` is 1.9 m, so he is ~230 px tall at
## 1334x750) and _close.png (a head portrait, for the detail), one pair per
## cell. `tools/bunny_face_strip.py` tiles them.
##
## Each cell is a mood + the clip that goes with it, frozen at the phase that
## carries the pose: a reaction is a motion and a screenshot is not.

const CELLS: Array = [
	# name        mood         clip         seek   eyes shut
	["content",   "content",   "idle",      0.2,   false],
	["hungry",    "hungry",    "fuss",      0.75,  false],
	["sleepy",    "sleepy",    "idle",      2.9,   false],
	["happy",     "delighted", "celebrate", 0.9,   false],
	["hmph",      "hmph",      "stamp",     0.35,  false],
	["hmph_land", "hmph",      "stamp",     0.55,  false],
	["blink",     "content",   "idle",      0.2,   true],
	["unhappy",   "unhappy",   "fuss",      0.0,   false],
	["asleep",    "asleep",    "sleep",     1.0,   false],
]

var _prefix: String = "bunny"
var _size: Vector2i = Vector2i(1334, 750)


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = String(args[0])
	if args.size() > 2:
		_size = Vector2i(int(args[1]), int(args[2]))
	call_deferred("_run")


func _run() -> void:
	get_root().size = _size
	var root := Node3D.new()
	get_root().add_child(root)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.83, 0.75, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.5
	env.environment = e
	root.add_child(env)
	var light := DirectionalLight3D.new()
	light.transform = Transform3D(
		Vector3(0.8296, 0.0, -0.5583), Vector3(-0.4356, 0.6248, -0.6479),
		Vector3(0.3494, 0.7808, 0.5185), Vector3(0, 3, 0))
	light.light_color = Color(1, 0.93464, 0.85752, 1)
	light.light_energy = 0.92
	light.shadow_enabled = false
	root.add_child(light)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.93, 0.80, 0.68)
	fm.roughness = 1.0
	floor.material_override = fm
	root.add_child(floor)

	var bunny: Node3D = load("res://scripts/characters/little_buddy/baby_little_buddy.gd").new()
	root.add_child(bunny)
	bunny.call("build")
	var player: AnimationPlayer = bunny.call("get_animation_player")
	print("  moods: %s  clips: %s" % [str(bunny.call("available_face_moods")),
			str(player.get_animation_list()) if player != null else "none"])

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	await process_frame
	await process_frame

	for cell: Array in CELLS:
		bunny.call("set_face_mood", String(cell[1]))
		bunny.call("set_eyes_closed", bool(cell[4]))
		if player != null and player.has_animation(String(cell[2])):
			player.play(String(cell[2]))
			player.seek(float(cell[3]), true)
			player.pause()
		# The feeding portrait: the room camera's closest focus, above and in
		# front, looking down at a 0.78 m child.
		cam.fov = 50.0
		cam.position = Vector3(0.0, 1.35, -1.9)
		cam.look_at(Vector3(0.0, 0.5, 0.0), Vector3.UP)
		await _shot("%s_%s_far" % [_prefix, String(cell[0])])
		cam.fov = 30.0
		cam.position = Vector3(0.0, 0.72, -0.9)
		cam.look_at(Vector3(0.0, 0.62, 0.0), Vector3.UP)
		await _shot("%s_%s_close" % [_prefix, String(cell[0])])
	quit()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = get_root().get_texture().get_image()
	var path := "res://../docs/shots/%s.png" % name
	var err := img.save_png(path)
	print("  %s  %s" % ["ok " if err == OK else "ERR", ProjectSettings.globalize_path(path)])
