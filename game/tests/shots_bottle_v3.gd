extends SceneTree

## Dev-only comparison: the exact 0.1.1 procedural bottle versus the shipping
## kitchen factory. Identical camera/light/pixel dimensions for both captures.
const Kit := preload("res://scripts/house/prop_kit.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const Items := preload("res://scripts/kitchen/kitchen_items.gd")
const Kitchen := preload("res://scripts/kitchen/kitchen_view.gd")
var viewport: SubViewport
var stand: Node3D

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
	camera.size = 0.47
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0, 0.29, 0.85), Vector3(0, 0.12, 0))
	camera.current = true
	var canvas := CanvasLayer.new()
	world.add_child(canvas)
	for i: int in range(2):
		var label := Label.new()
		label.text = "Bottle" if i == 0 else "Milk"
		label.position = Vector2(318 + i * 448, 635)
		label.size = Vector2(250, 65)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 38)
		label.add_theme_color_override("font_color", Palette.INK)
		canvas.add_child(label)
	var kitchen := Kitchen.new()
	for legacy: bool in [true, false]:
		stand = Node3D.new()
		world.add_child(stand)
		for i: int in range(2):
			var id: String = "bottle" if i == 0 else "bottleOfMilk"
			var item: MeshInstance3D = _legacy_item(id) if legacy else kitchen.call("_make_item", id, Vector3.ZERO)
			item.position.x = -0.14 if i == 0 else 0.14
			stand.add_child(item)
			print("%s %s: %s surfaces=%d" % ["before" if legacy else "after", id, str(item.mesh.get_aabb()), item.mesh.get_surface_count()])
		for frame: int in range(4):
			await process_frame
		RenderingServer.force_draw(true, 0)
		var shot: Image = viewport.get_texture().get_image()
		var path: String = "res://../docs/shots/v3_%s_bottle.png" % ("before" if legacy else "after")
		assert(shot.get_size() == Vector2i(1334, 750))
		assert(shot.save_png(ProjectSettings.globalize_path(path)) == OK)
		stand.free()
	kitchen.free()
	print("BOTTLE V3 SHOTS PASS")
	quit(0)

## Copied from commit 2a702e kitchen_view.gd::_draw_bottle, unchanged geometry.
func _legacy_item(id: String) -> MeshInstance3D:
	var size: float = Items.size_for(id)
	var color: Color = Items.color_for(id)
	var tool: SurfaceTool = Kit.begin()
	var body_top: float = size * 1.44
	Kit.cylinder(tool, Kit.at(Vector3(0.0, body_top * 0.5, 0.0)),
			size * 0.62, body_top, color, 10, size * 0.16)
	if id == "bottleOfMilk":
		var fill: float = body_top * 0.62
		Kit.cylinder(tool, Kit.at(Vector3(0.0, fill * 0.5, 0.0)),
				size * 0.645, fill, Palette.deep(color), 10, size * 0.10)
	Kit.cylinder(tool, Kit.at(Vector3(0.0, body_top + size * 0.11, 0.0)),
			size * 0.46, size * 0.22, color, 8, size * 0.07)
	Kit.cylinder(tool, Kit.at(Vector3(0.0, body_top + size * 0.30, 0.0)),
			size * 0.38, size * 0.16, Palette.SOFT_PINK, 8, size * 0.05)
	Kit.sphere(tool, Transform3D(Basis.from_scale(Vector3(1.0, 1.45, 1.0)),
			Vector3(0.0, body_top + size * 0.50, 0.0)),
			size * 0.21, Palette.SOFT_PINK, 8, 3)
	var item := MeshInstance3D.new()
	item.mesh = Kit.commit(tool)
	item.material_override = Kit.material()
	return item
