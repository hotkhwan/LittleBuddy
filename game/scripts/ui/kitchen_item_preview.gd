extends SubViewportContainer

## A photograph of the SAME mesh used on the kitchen counter. Render once
## after mounting; no rotating model or continuous offscreen rendering cost.
const KitchenView := preload("res://scripts/kitchen/kitchen_view.gd")
const Items := preload("res://scripts/kitchen/kitchen_items.gd")
const Palette := preload("res://scripts/ui/palette.gd")

func setup(item_id: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.gui_disable_input = true
	add_child(viewport)
	var factory := KitchenView.new()
	var model: MeshInstance3D = factory.call("_make_item", item_id, Vector3.ZERO)
	factory.free()
	viewport.add_child(model)
	var bounds: AABB = model.get_aabb()
	var centre: Vector3 = bounds.get_center()
	var side: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(side * 1.5, 0.1)
	viewport.add_child(camera)
	camera.position = centre + Vector3(0.55, 0.35, 1.0) * maxf(side * 3.0, 0.5)
	camera.look_at_from_position(camera.position, centre)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(Palette.CREAM, 0.0)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(1, 0.96, 0.9)
	world.environment.ambient_light_energy = 0.7
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.1
	viewport.add_child(light)
	# Container sizing can change the texture after setup; request one new frame.
	resized.connect(func() -> void: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
