extends SceneTree

## Photographs every Meshy teaching prop in `content/tutor/props_manifest.json`.
##
##   Godot --path game --script res://tests/shots_tutor_props.gd
##
## One 512x512 render per prop on a plain pastel background, plus one combined
## "shelf" render with every prop side by side at its manifest scale. This is the
## look-at-it half of `test_tutor_props.gd`: the test proves the file loads and
## sits inside budget, and these pictures are how a human decides whether it is
## a table or a grey blob. Same single `DirectionalLight3D`, no post-processing,
## so what is on screen here is what the Mobile renderer will show on the iPad.
##
## Renders go to `docs/shots/tutor_prop_<propId>.png` and `tutor_props_shelf.png`.

const MANIFEST_PATH: String = "res://content/tutor/props_manifest.json"
const OUT_DIR: String = "docs/shots/"
const SIZE: int = 512
const BACKGROUND: Color = Color(0.965, 0.945, 0.905)

var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(manifest) != TYPE_DICTIONARY:
		push_error("could not read %s" % MANIFEST_PATH)
		quit(1)
		return
	var props: Array = (manifest as Dictionary).get("props", [])
	for prop: Dictionary in props:
		await _shoot_one(prop)
	await _shoot_shelf(props)
	for f: String in _fail:
		push_error(f)
	quit(0 if _fail.is_empty() else 1)


func _spawn(prop: Dictionary) -> Node3D:
	var scene: PackedScene = load(String(prop.get("file", ""))) as PackedScene
	if scene == null:
		_fail.append("could not load %s" % String(prop.get("file", "")))
		return null
	var node: Node3D = scene.instantiate() as Node3D
	var s: float = float(prop.get("scaleToMetres", 1.0))
	node.scale = Vector3(s, s, s)
	node.rotation_degrees.y = float(prop.get("yawDegrees", 0.0))
	return node


func _aabb_of(node: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = n
			var local: AABB = mi.mesh.get_aabb()
			var xf: Transform3D = mi.global_transform
			for i: int in range(8):
				var p: Vector3 = xf * local.get_endpoint(i)
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
		for c: Node in n.get_children():
			stack.append(c)
	return box


func _make_stage(width: int, height: int) -> Dictionary:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(width, height)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)

	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.55
	env.environment = e
	vp.add_child(env)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	vp.add_child(sun)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	cam.current = true
	return {"viewport": vp, "camera": cam}


func _frame(cam: Camera3D, box: AABB) -> void:
	var centre: Vector3 = box.get_center()
	var radius: float = box.size.length() * 0.5
	var dist: float = radius / sin(deg_to_rad(cam.fov) * 0.5) * 1.08
	var dir: Vector3 = Vector3(0.62, 0.48, 1.0).normalized()
	cam.global_position = centre + dir * dist
	cam.look_at(centre, Vector3.UP)


func _shoot_one(prop: Dictionary) -> void:
	var stage: Dictionary = _make_stage(SIZE, SIZE)
	var vp: SubViewport = stage["viewport"]
	var node: Node3D = _spawn(prop)
	if node == null:
		vp.queue_free()
		return
	vp.add_child(node)
	await process_frame
	_frame(stage["camera"], _aabb_of(node))
	await _settle(0.3)
	await _save(vp, "tutor_prop_%s" % String(prop.get("propId", "prop")))
	vp.queue_free()
	await process_frame


func _shoot_shelf(props: Array) -> void:
	var stage: Dictionary = _make_stage(1334, 616)
	var vp: SubViewport = stage["viewport"]
	var x: float = 0.0
	var nodes: Array = []
	for prop: Dictionary in props:
		var node: Node3D = _spawn(prop)
		if node == null:
			continue
		vp.add_child(node)
		nodes.append(node)
	await process_frame
	var whole: AABB = AABB()
	var first: bool = true
	for node: Node3D in nodes:
		var box: AABB = _aabb_of(node)
		node.position.x = x - box.position.x
		node.position.y = -box.position.y
		x += box.size.x + 0.25
		await process_frame
		var placed: AABB = _aabb_of(node)
		whole = placed if first else whole.merge(placed)
		first = false
	# Shelf board under everything.
	var board: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(whole.size.x + 0.6, 0.06, maxf(whole.size.z, 0.8) + 0.4)
	board.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.72, 0.56)
	mat.roughness = 0.9
	board.material_override = mat
	board.position = Vector3(whole.get_center().x, -0.03, whole.get_center().z)
	vp.add_child(board)
	await process_frame
	var cam: Camera3D = stage["camera"]
	cam.fov = 30.0
	var centre: Vector3 = whole.get_center()
	var dist: float = (whole.size.x * 0.5) / tan(deg_to_rad(cam.fov) * 0.5) * (616.0 / 1334.0) * 1.35 + whole.size.z
	dist = maxf(dist, whole.size.length() * 0.9)
	cam.global_position = centre + Vector3(0.0, 0.45, 1.0).normalized() * dist
	cam.look_at(centre, Vector3.UP)
	await _settle(0.3)
	await _save(vp, "tutor_props_shelf")
	vp.queue_free()
	await process_frame


func _save(vp: SubViewport, name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = vp.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + name + ".png")
	if image.save_png(path) != OK:
		_fail.append("could not write %s" % path)
		return
	print("  shot %s  %dx%d" % [path, image.get_width(), image.get_height()])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
