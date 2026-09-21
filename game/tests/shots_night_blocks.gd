extends SceneTree

## Identical 1334x750 evidence of the shipped procedural stack and the free
## accepted-classroom reuse. Uses the real ObjectSpawner and grab collider.
const Spawner := preload("res://scripts/gameplay/object_spawner.gd")
const Registry := preload("res://scripts/house/prop_registry.gd")
const Palette := preload("res://scripts/ui/palette.gd")
var viewport: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	viewport = SubViewport.new()
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
	camera.size = 0.46
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.12, 0.28, 0.85), Vector3(0, 0.085, 0))
	camera.current = true
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/objects.json"))
	var record: Dictionary = {}
	for row: Dictionary in data.get("objects", []):
		if row.get("objectId") == "blocks":
			record = row
	assert(not record.is_empty())
	var current: Dictionary = Spawner.build_spec(record)
	assert(current.model == "meshy-props/toyBlocks")
	var before: Dictionary = current.duplicate(true)
	before.model = "proc/blocks"
	before.modelPath = ""
	var legacy: Dictionary = Spawner.model_presentation(before.model)
	before.modelSize = legacy.size
	before.modelRotationDeg = legacy.rotation
	var collision_size: Vector3
	for old: bool in [true, false]:
		var spec: Dictionary = before if old else current
		var item: Area3D = Spawner.spawn_from_spec(spec)
		world.add_child(item)
		var visual := item.get_node("Visual") as MeshInstance3D
		assert(visual != null)
		var bounds: AABB = visual.transform * visual.mesh.get_aabb()
		assert(absf(bounds.position.y) < 0.002)
		var shape: BoxShape3D
		for child: Node in item.get_children():
			if child is CollisionShape3D:
				shape = child.shape as BoxShape3D
		assert(shape != null)
		if old:
			collision_size = shape.size
		else:
			assert(shape.size == collision_size)
			assert(Registry.triangles(visual.mesh) == 2547)
			assert(visual.mesh.get_surface_count() == 1)
			assert(visual.mesh.surface_get_material(0).albedo_texture != null)
		for frame: int in range(4):
			await process_frame
		RenderingServer.force_draw(true, 0)
		var shot: Image = viewport.get_texture().get_image()
		assert(shot != null and shot.get_size() == Vector2i(1334, 750))
		var path: String = "res://../docs/shots/night/blocks_%s.png" % ("before" if old else "after")
		assert(shot.save_png(ProjectSettings.globalize_path(path)) == OK)
		print("BLOCKS %s bounds=%s collider=%s" % ["before" if old else "after", bounds, shape.size])
		item.free()
	print("NIGHT BLOCKS PASS: identical collider, grounded, 2547 triangles, textured single surface")
	quit(0)
