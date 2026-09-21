extends SceneTree

## Real ObjectSpawner pickups, identical camera/light before and after.
const Spawner := preload("res://scripts/gameplay/object_spawner.gd")
const Palette := preload("res://scripts/ui/palette.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1334, 750)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Palette.light(Palette.LAVENDER)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Palette.CREAM
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 0.9
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.5
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.05, 0.28, 0.85), Vector3(0, 0.085, 0))
	camera.current = true
	var library: RefCounted = (load("res://scripts/content/content_library.gd") as GDScript).create()
	for old: bool in [true, false]:
		var stand := Node3D.new()
		world.add_child(stand)
		for id: String in ["apple", "banana"]:
			var record: Dictionary = library.get_object(id)
			var spec: Dictionary = Spawner.build_spec(record)
			if old:
				spec.model = record.model
				var presentation: Dictionary = Spawner.model_presentation(record.model)
				spec.modelSize = presentation.size
				spec.modelRotationDeg = presentation.rotation
			var item: Area3D = Spawner.spawn_from_spec(spec)
			item.position.x = -0.15 if id == "apple" else 0.15
			stand.add_child(item)
		for frame: int in range(4):
			await process_frame
		RenderingServer.force_draw(true, 0)
		var shot: Image = viewport.get_texture().get_image()
		assert(shot != null and shot.get_size() == Vector2i(1334, 750))
		assert(shot.save_png("res://../docs/shots/night/fruit_%s.png" % ("before" if old else "after")) == OK)
		stand.free()
	print("NIGHT FRUIT PASS: real pickups, identical 1334x750 camera and lighting")
	quit(0)
