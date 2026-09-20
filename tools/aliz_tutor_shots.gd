extends SceneTree
## Aliz's TUTOR face and gestures, in engine, at the TUTOR camera: about 1.2 m
## from her face, head ~180 px tall at 1334x750 (the classroom framing), with
## the house's own light rig. Lives in tools/ so it touches no scene file.
##
##   Godot --path game --script ../tools/aliz_tutor_shots.gd -- <prefix> expr
##       docs/shots/<prefix>_expr_<name>.png for the six expressions
##   Godot --path game --script ../tools/aliz_tutor_shots.gd -- <prefix> mouth
##       docs/shots/<prefix>_mouth_<n>.png for the four mouth frames (over neutral)
##   Godot --path game --script ../tools/aliz_tutor_shots.gd -- <prefix> envelope
##       docs/shots/<prefix>_env_<n>.png, six frames while a two-syllable
##       synthetic envelope drives set_mouth_open() through the real smoothing
##   Godot --path game --script ../tools/aliz_tutor_shots.gd -- <prefix> gesture
##       docs/shots/<prefix>_gesture_<name>_<n>.png, five frames per gesture at
##       10/30/50/70/90 % of its length, the layer's clock stepped by hand so
##       the frame is the frame; the idle is held at one pose underneath
##
## Blinking is off for every still (a blink on the capture frame would be a
## lie about the face). `tools/aliz_tutor_sheet.py` tiles the results.

var _prefix: String = "aliz_tutor"
var _size: Vector2i = Vector2i(1334, 750)
var _job: String = "expr"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = String(args[0])
	if args.size() > 1:
		_job = String(args[1])
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

	var girl: Node3D = load("res://scripts/characters/buddy/pink_girl_buddy.gd").new()
	root.add_child(girl)
	girl.call("build")
	girl.call("set_blinking", false)
	girl.rotation = Vector3.ZERO

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	_tutor(cam)

	# Hold the idle at one pose so every tile is comparable.
	var player: AnimationPlayer = girl.call("get_animation_player")
	if player != null and player.has_animation("idle"):
		player.play("idle")
		player.seek(0.2, true)
		player.pause()

	await process_frame
	await process_frame
	match _job:
		"mouth":
			await _mouth(girl)
		"envelope":
			await _envelope(girl)
		"gesture":
			await _gesture(girl, cam)
		_:
			await _expressions(girl)
	quit()


## ~1.2 m from the face; vertical FOV chosen so a 0.28 m head is ~180 px at 750.
func _tutor(cam: Camera3D) -> void:
	cam.fov = 52.0
	cam.position = Vector3(0.0, 1.36, -1.2)
	cam.look_at(Vector3(0.0, 1.22, 0.0), Vector3.UP)


## Pulled back a little so the arms stay in frame for point / clap / wave.
func _gesture_cam(cam: Camera3D) -> void:
	cam.fov = 52.0
	cam.position = Vector3(0.0, 1.45, -2.2)
	cam.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)


func _expressions(girl: Node3D) -> void:
	for name: String in girl.get("EXPRESSIONS"):
		girl.call("set_expression", name)
		await _shot("%s_expr_%s" % [_prefix, name])
	girl.call("set_expression", "neutral")


func _mouth(girl: Node3D) -> void:
	girl.call("set_expression", "neutral")
	girl.call("set_speaking", true)
	var targets: Array = [0.0, 0.15, 0.45, 1.0]
	for n: int in range(targets.size()):
		girl.call("set_mouth_open", float(targets[n]))
		for _k: int in range(15):
			await process_frame
		print("  target %.2f -> frame %d" % [float(targets[n]), int(girl.call("get_mouth_frame"))])
		await _shot("%s_mouth_%d" % [_prefix, n])
	girl.call("set_speaking", false)


func _envelope(girl: Node3D) -> void:
	girl.call("set_expression", "smile")
	girl.call("set_speaking", true)
	# Two syllables: bumps at 0.05-0.25 s and 0.30-0.50 s, then silence.
	var shots: Array = [0.08, 0.15, 0.24, 0.32, 0.40, 0.56]
	var t: float = 0.0
	var next: int = 0
	var frames: Array = []
	while next < shots.size():
		var a: float = 0.0
		for start: float in [0.05, 0.30]:
			if t >= start and t < start + 0.2:
				a = maxf(a, 0.5 * (1.0 - cos(TAU * (t - start) / 0.2)))
		girl.call("set_mouth_open", a)
		await process_frame
		t += get_root().get_process_delta_time() if get_root().get_process_delta_time() > 0.0 else 1.0 / 60.0
		if t >= float(shots[next]):
			frames.append([t, a, int(girl.call("get_mouth_frame"))])
			await _shot("%s_env_%d" % [_prefix, next])
			next += 1
	print("  envelope frames [t, target, frame]: %s" % str(frames))
	girl.call("set_speaking", false)
	girl.call("set_expression", "neutral")


func _gesture(girl: Node3D, cam: Camera3D) -> void:
	_gesture_cam(cam)
	var layer: SkeletonModifier3D = girl.call("get_gesture_layer")
	layer.set("manual_clock", true)
	girl.call("set_expression", "encouraging")
	for name: String in ["nod", "tilt", "point", "clap", "wave"]:
		var length: float = float(girl.call("play_gesture", name))
		var at: float = 0.0
		for n: int in range(5):
			var want: float = length * (0.1 + 0.2 * float(n))
			layer.call("advance", want - at)
			at = want
			await process_frame
			await _shot("%s_gesture_%s_%d" % [_prefix, name, n])
		layer.call("advance", length)
		await process_frame
		print("  %s: %.2f s, five frames" % [name, length])
	layer.set("manual_clock", false)
	girl.call("set_expression", "neutral")


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = get_root().get_texture().get_image()
	var path := "res://../docs/shots/%s.png" % name
	var err := img.save_png(path)
	print("  %s  %s" % ["ok " if err == OK else "ERR", ProjectSettings.globalize_path(path)])
