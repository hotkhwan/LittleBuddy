extends SceneTree
## Aliz from the angles the OWNER sees her, through the shipping wrapper, with
## the house's own light rig -- standing front, three-quarter (as when walking),
## and from behind -- at the real gameplay camera distance. Lives in tools/ so
## it does not touch any scene file another agent owns.
##
##   Godot --path game --script ../tools/aliz_shots.gd -- <prefix> [W H]
##       writes docs/shots/<prefix>_front.png, _threeq.png, _back.png
##
##   Godot --path game --script ../tools/aliz_shots.gd -- <prefix> mood
##       every face mood plus the blink frame, twice each: a head close-up
##       (`<prefix>_mood_<name>_close.png`) and the gameplay-distance front view
##       (`<prefix>_mood_<name>_far.png`); `tools/aliz_face_strip.py` tiles them.
##
##   Godot --path game --script ../tools/aliz_shots.gd -- <prefix> idle
##       three front frames of the authored idle 1.5 s apart
##       (`<prefix>_idle_<n>.png`), with the hair sway running.
##
## Blinking is switched OFF for the still shots (a 120 ms blink landing on the
## capture frame would be a lie about the mood) and forced ON for the blink
## frame.

var _prefix: String = "aliz_view"
var _size: Vector2i = Vector2i(1334, 750)
var _job: String = "views"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = String(args[0])
	if args.size() > 1 and not String(args[1]).is_valid_int():
		_job = String(args[1])
	elif args.size() > 2:
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
	if girl.has_method("set_blinking"):
		girl.call("set_blinking", false)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	# The house camera pitch, roughly: above and in front, looking down a little,
	# framed so the head is ~130 px tall at 1334x750 -- the bedroom framing.
	cam.fov = 50.0

	await process_frame
	await process_frame

	match _job:
		"mood":
			await _moods(girl, cam)
		"idle":
			await _idle(girl, cam)
		_:
			await _views(girl, cam)
	quit()


func _far(cam: Camera3D) -> void:
	cam.fov = 50.0
	cam.position = Vector3(0.0, 2.35, -3.6)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)


func _close(cam: Camera3D) -> void:
	cam.fov = 34.0
	cam.position = Vector3(0.0, 1.24, -1.05)
	cam.look_at(Vector3(0.0, 1.24, 0.0), Vector3.UP)


func _views(girl: Node3D, cam: Camera3D) -> void:
	# Yaw 0 faces -Z, and this camera sits on -Z, so 0 is face-on, 180 is her
	# back. (The menu's 180/200 is because ITS camera sits on +Z.)
	for view: Array in [["front", 0.0], ["threeq", 40.0], ["back", 180.0]]:
		girl.rotation = Vector3(0.0, deg_to_rad(float(view[1])), 0.0)
		_far(cam)
		await _shot("%s_%s" % [_prefix, String(view[0])])


func _moods(girl: Node3D, cam: Camera3D) -> void:
	girl.rotation = Vector3.ZERO
	# Hold the idle at a fixed frame so every tile is the same pose.
	var player: AnimationPlayer = girl.call("get_animation_player")
	if player != null and player.has_animation("idle"):
		player.play("idle")
		player.seek(0.2, true)
		player.pause()
	var moods: Array = girl.call("available_faces") if girl.has_method("available_faces") else []
	print("  moods: %s" % str(moods))
	var cells: Array = []
	for mood: String in moods:
		cells.append([mood, mood, false])
	cells.append(["blink", "content", true])
	for cell: Array in cells:
		girl.call("set_face", String(cell[1]))
		if bool(cell[2]):
			girl.call("set_blinking", true)
			girl.call("blink_now")
		else:
			girl.call("set_blinking", false)
		_close(cam)
		await _shot("%s_mood_%s_close" % [_prefix, String(cell[0])])
		_far(cam)
		await _shot("%s_mood_%s_far" % [_prefix, String(cell[0])])
		if bool(cell[2]):
			girl.call("set_blinking", false)
	girl.call("set_face", "content")


func _idle(girl: Node3D, cam: Camera3D) -> void:
	girl.rotation = Vector3.ZERO
	_far(cam)
	if girl.has_method("play_action"):
		girl.call("play_action", "idle")
	var player: AnimationPlayer = girl.call("get_animation_player")
	if player == null or not player.has_animation("idle"):
		print("  no idle clip")
		return
	print("  current: %s" % player.current_animation)
	for n: int in range(3):
		player.seek(0.3 + 1.5 * float(n), true)
		await _shot("%s_idle_%d" % [_prefix, n])


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = get_root().get_texture().get_image()
	var path := "res://../docs/shots/%s.png" % name
	var err := img.save_png(path)
	print("  %s  %s" % ["ok " if err == OK else "ERR", ProjectSettings.globalize_path(path)])
