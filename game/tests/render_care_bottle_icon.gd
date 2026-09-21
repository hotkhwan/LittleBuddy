extends SceneTree

## Free deterministic raster of the accepted gameplay GLB, not concept art.
const Registry := preload("res://scripts/house/prop_registry.gd")
const Palette := preload("res://scripts/ui/palette.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(Palette.CREAM, 0.0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Palette.CREAM
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 0.8
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.292
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.025, 0.18, 0.85), Vector3(0, 0.125, 0))
	camera.current = true
	var bottle: MeshInstance3D = Registry.instance("babyBottle", 0.25)
	assert(bottle != null)
	world.add_child(bottle)
	for frame: int in range(4):
		await process_frame
	RenderingServer.force_draw(true, 0)
	var shot: Image = viewport.get_texture().get_image()
	assert(shot != null and shot.get_size() == Vector2i(256, 256))
	assert(shot.get_pixel(0, 0).a == 0.0)
	assert(shot.save_png("res://assets/ui/icons/pictures/care_bottle.png") == OK)
	print("CARE BOTTLE ICON PASS: accepted GLB, transparent 256px, zero generation credits")
	quit(0)
