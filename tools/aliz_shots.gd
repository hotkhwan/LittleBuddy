extends SceneTree
## Aliz from the angles the OWNER sees her, through the shipping wrapper, with
## the house's own light rig -- standing front, three-quarter (as when walking),
## and from behind -- at the real gameplay camera distance. Lives in tools/ so
## it does not touch any scene file another agent owns.
##
##   Godot --path game --script ../tools/aliz_shots.gd -- <prefix> [W H]
##
## Writes docs/shots/<prefix>_front.png, _threeq.png, _back.png.

var _prefix: String = "aliz_view"
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

	# The house's palette: a warm floor plane and a pastel wall so the hair is
	# judged against what it is actually seen against, not a flat blue field.
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
	# main.tscn's light basis, i.e. the game's one directional light.
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

	var girl: Node3D = load("res://scripts/characters/buddy/pink_girl_buddy.gd").new()
	root.add_child(girl)
	if girl.has_method("build"):
		girl.call("build")

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	# The house camera pitch, roughly: above and in front, looking down a little,
	# framed so the head is ~130 px tall at 1334x750 -- the bedroom framing.
	cam.fov = 50.0

	await process_frame
	await process_frame

	# Yaw 0 faces -Z, and this camera sits on -Z, so 0 is face-on, 180 is her
	# back. (The menu's 180/200 is because ITS camera sits on +Z.)
	for view: Array in [["front", 0.0], ["threeq", 40.0], ["back", 180.0]]:
		girl.rotation = Vector3(0.0, deg_to_rad(float(view[1])), 0.0)
		cam.position = Vector3(0.0, 2.35, -3.6)
		cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
		await process_frame
		await process_frame
		await process_frame
		var img: Image = get_root().get_texture().get_image()
		var path := "res://../docs/shots/%s_%s.png" % [_prefix, String(view[0])]
		var err := img.save_png(path)
		print("  %s  %s" % ["ok " if err == OK else "ERR", ProjectSettings.globalize_path(path)])
	quit()
