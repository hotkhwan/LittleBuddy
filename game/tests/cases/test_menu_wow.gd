extends RefCounted

## The title screen is a place, its buttons work, and it stays inside the budget.
##
## The owner's note on the real build was that the menu "does not feel like a
## children's game world" -- a green plane and a blue sky. This pins what
## replaced it, at the level a test can hold:
##
##   * the garden is BUILT (house with a door and windows, trees, flowers,
##     clouds, a path, one sun) from primitives, in palette colours only --
##     never black, never red;
##   * the render budget holds: one `DirectionalLight3D`, no shadows, no other
##     light, nothing from section 7's forbidden list, a triangle cap;
##   * the TWO characters -- Aliz and Bunny, through their production wrappers
##     and nobody else -- are in the scene and FRAMED: feet above the button
##     row, heads below the title, inside the narrowest iPad frame;
##   * all four buttons -- Start, Free Play, Dress Up, Grown-ups -- are big
##     enough, carry a picture and a word, get a shadow and press feedback, and
##     each one PRESSED hands the tree the scene it promises.

const MainScript := preload("res://scenes/main/main.gd")
const Garden := preload("res://scripts/menu/menu_garden.gd")
const Palette := preload("res://scripts/ui/palette.gd")

const MENU_SCENE: String = "res://scenes/main/main.tscn"

## Section 10 of the art bible budgets a hero character at 4,000 triangles; the
## whole garden is allowed ten of those, which is generous for a menu and still
## a tenth of what one unoptimised prop export costs.
const GARDEN_TRIANGLE_CAP: int = 40000

## The layout the scene stores, in the 1024-tall design space.
const DESIGN_HEIGHT: float = 1024.0
const TITLE_BOTTOM: float = 170.0
const BUTTON_ROW_TOP: float = DESIGN_HEIGHT - 292.0
## The narrowest shape the game ships on: a 4:3 iPad.
const NARROWEST_ASPECT: float = 4.0 / 3.0
const MIN_TOUCH_SIDE: float = 240.0

const BUTTONS: Dictionary = {
	"PlayButton": "res://scenes/baby_room/baby_room.tscn",
	"FreePlayButton": "res://scenes/house/house_world.tscn",
	"DressUpButton": "res://scenes/activities/dressing.tscn",
	"ParentButton": "res://scenes/parent/parent_settings.tscn",
}


func test_name() -> String:
	return "menu_wow"


func run():
	var failures: Array = []
	failures.append_array(_test_the_garden_is_built())
	failures.append_array(_test_garden_colours_are_palette())
	failures.append_array(_test_render_budget())
	failures.append_array(_test_characters_are_framed())
	failures.append_array(_test_four_buttons_dressed())
	failures.append_array(_test_each_button_opens_its_scene())
	return failures


# ---------------------------------------------------------------------------
# The garden
# ---------------------------------------------------------------------------

func _test_the_garden_is_built():
	var failures: Array = []
	var garden: Node3D = Garden.new()
	garden.build()
	var counts: Dictionary = garden.describe()
	var minimums: Dictionary = {
		"doors": 1, "windows": 3, "trees": 3, "flowers": 12, "clouds": 3,
		"stones": 8, "hills": 2, "fencePosts": 8, "toys": 3,
	}
	for kind: String in minimums.keys():
		if int(counts.get(kind, 0)) < int(minimums[kind]):
			failures.append("the garden has %d %s; a storybook garden needs at least %d"
					% [int(counts.get(kind, 0)), kind, int(minimums[kind])])
	if int(counts.get("suns", 0)) != 1:
		failures.append("the garden has %d suns; there is one" % int(counts.get("suns", 0)))
	for node_name: String in ["House", "Path", "Trees", "Flowerbeds", "Fence", "Clouds", "SkyDome", "Grass"]:
		if garden.get_node_or_null(node_name) == null:
			failures.append("the garden has no %s node" % node_name)
	var house: Node = garden.get_node_or_null("House")
	if house != null:
		for part: String in ["Walls", "Roof", "Door", "Window", "AtticWindow", "Chimney"]:
			if house.get_node_or_null(part) == null:
				failures.append("the house has no %s" % part)
	# Built twice, built once: the second call must be a no-op.
	var before: int = garden.get_child_count()
	garden.build()
	if garden.get_child_count() != before:
		failures.append("build() is not idempotent; calling it again added nodes")
	garden.free()
	return failures


func _test_garden_colours_are_palette():
	var failures: Array = []
	var garden: Node3D = Garden.new()
	garden.build()
	for colour: Color in garden.colours_used():
		if Palette.is_black(colour):
			failures.append("the garden paints pure black (#%s); ink is the only dark" % colour.to_html(false))
		if Palette.is_red(colour):
			failures.append("the garden paints #%s, which reads as red; there is no red in this game"
					% colour.to_html(false))
	# The door is the brightest thing on the house on purpose, and the house is
	# pastel on purpose: a child should find the door before the wall.
	if Garden.door().v < Garden.wall().v - 0.25 or Garden.door().s < Garden.wall().s:
		failures.append("the door is not brighter/more saturated than the wall; it should invite")
	garden.free()
	return failures


func _test_render_budget():
	var failures: Array = []
	var menu: Node = _instantiate(failures)
	if menu == null:
		return failures
	var garden: Node = menu.get_node_or_null("Garden")
	if garden == null:
		failures.append("main.tscn has no Garden node")
	else:
		garden.call("build")
		var triangles: int = int(garden.call("count_triangles"))
		if triangles > GARDEN_TRIANGLE_CAP:
			failures.append("the garden is %d triangles; the cap is %d" % [triangles, GARDEN_TRIANGLE_CAP])
		if triangles <= 0:
			failures.append("the garden counts no triangles at all; nothing was built")

	var lights: Array = []
	_collect(menu, "Light3D", lights)
	var directional: int = 0
	for light: Node in lights:
		if light is DirectionalLight3D:
			directional += 1
			if (light as DirectionalLight3D).shadow_enabled:
				failures.append("the menu sun casts shadows; they were switched off after a device review")
		else:
			failures.append("%s is a %s; the menu has one directional light and nothing else"
					% [String(light.name), light.get_class()])
	if directional != 1:
		failures.append("the menu holds %d DirectionalLight3D nodes; section 7 allows exactly one" % directional)

	for banned: String in ["ReflectionProbe", "VoxelGI", "LightmapGI", "Decal", "GPUParticles3D", "FogVolume"]:
		var found: Array = []
		_collect(menu, banned, found)
		if not found.is_empty():
			failures.append("the menu contains a %s; section 7 forbids it" % banned)

	var environment_node: WorldEnvironment = menu.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment_node == null or environment_node.environment == null:
		failures.append("the menu has no WorldEnvironment")
	else:
		var env: Environment = environment_node.environment
		if env.glow_enabled or env.ssao_enabled or env.ssr_enabled or env.ssil_enabled \
				or env.sdfgi_enabled or env.fog_enabled or env.volumetric_fog_enabled:
			failures.append("the menu environment has a post-process on; section 7 forbids them all")

	# Every mesh in the garden opts out of shadow casting, so switching the sun's
	# shadows back on could never quietly re-buy a depth pass for the props.
	var meshes: Array = []
	if garden != null:
		_collect(garden, "GeometryInstance3D", meshes)
	for mesh: Node in meshes:
		if (mesh as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures.append("%s casts shadows" % String(garden.get_path_to(mesh)))
			break
	menu.free()
	return failures


# ---------------------------------------------------------------------------
# The family, framed
# ---------------------------------------------------------------------------

func _test_characters_are_framed():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["menu_wow: no SceneTree; cannot ready the menu"]
	var menu: Node = _instantiate(failures)
	if menu == null:
		return failures
	_add_and_ready(tree, menu)

	var camera: Camera3D = menu.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		menu.free()
		return ["the menu has no Camera3D"]

	# Who is home: the pair, and only the pair. A procedural stand-in next to the
	# two real characters read as a third child nobody had met (owner review,
	# 2026-09-20); `test_buddy_avatar.gd` section 8 pins the same decision.
	if menu.get_node_or_null("LittleBuddy") != null:
		failures.append("a LittleBuddy stand-in is on the title screen; the menu shows Aliz and Bunny only")
	var people: Dictionary = {}
	for who: String in ["BigBuddy", "Bunny"]:
		var node: Node3D = menu.get_node_or_null(who) as Node3D
		if node == null:
			failures.append("%s is not on the title screen" % who)
			continue
		if node.has_method("is_model_available") and not bool(node.call("is_model_available")):
			failures.append("%s is in the scene but has no model in this checkout" % who)
		var height: float = 1.65 if who == "BigBuddy" else 0.78
		if node.has_method("get_height"):
			height = float(node.call("get_height"))
		people[who] = [node.position, height]

	# The camera is above the family and looking gently down -- never top-down,
	# which kills faces, and never level, which hides the garden.
	# LOCAL transforms throughout: the runner's root is not an active tree during
	# `_initialize()`, so `global_transform` reads back as identity there. The
	# camera, the sun and the characters are all direct children of the menu
	# root, whose own transform is identity, so local IS global.
	var forward: Vector3 = -camera.transform.basis.z
	var pitch_deg: float = rad_to_deg(asin(-forward.y))
	if pitch_deg < 3.0 or pitch_deg > 30.0:
		failures.append("the menu camera pitches %.1f degrees; a flattering view is between 3 and 30" % pitch_deg)

	# Feet above the buttons, heads below the title, everyone inside a 4:3 frame.
	for who: String in people.keys():
		var feet: Vector3 = people[who][0]
		var head: Vector3 = feet + Vector3(0.0, float(people[who][1]), 0.0)
		var feet_px: Vector2 = _project(camera, feet, NARROWEST_ASPECT)
		var head_px: Vector2 = _project(camera, head, NARROWEST_ASPECT)
		if feet_px.y > BUTTON_ROW_TOP - 6.0:
			failures.append("%s's feet land at y=%.0f, under the button row (top %.0f); the buttons would cut the character"
					% [who, feet_px.y, BUTTON_ROW_TOP])
		if head_px.y < TITLE_BOTTOM + 6.0:
			failures.append("%s's head reaches y=%.0f, under the title panel (bottom %.0f)"
					% [who, head_px.y, TITLE_BOTTOM])
		var width: float = DESIGN_HEIGHT * NARROWEST_ASPECT
		if feet_px.x < 40.0 or feet_px.x > width - 40.0:
			failures.append("%s stands at x=%.0f, off the edge of a 4:3 iPad frame (%.0f wide)"
					% [who, feet_px.x, width])
		# The character has to be worth looking at: not a speck in a garden.
		var on_screen_height: float = feet_px.y - head_px.y
		if who == "BigBuddy" and on_screen_height < DESIGN_HEIGHT * 0.28:
			failures.append("Aliz is only %.0f px tall in a 1024 px frame; the camera is too far away"
					% on_screen_height)

	# The sun lights their faces: the light travels toward -Z, the way they face
	# the camera at +Z, and comes from above.
	var sun: DirectionalLight3D = menu.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun != null:
		var light_dir: Vector3 = -sun.transform.basis.z
		if light_dir.z >= 0.0:
			failures.append("the sun shines toward the camera, so the characters' faces are in shadow")
		if light_dir.y >= 0.0:
			failures.append("the sun is below the horizon")

	tree.root.remove_child(menu)
	menu.free()
	return failures


## Where a world point lands in the design space, for a camera with a vertical
## FOV, at `aspect`. The same maths `Camera3D.unproject_position()` does, without
## needing a viewport of a chosen size.
static func _project(camera: Camera3D, world: Vector3, aspect: float) -> Vector2:
	var local: Vector3 = camera.transform.affine_inverse() * world
	if local.z >= -0.001:
		return Vector2(-1.0, -1.0)
	var half_h: float = tan(deg_to_rad(camera.fov) * 0.5)
	var ndc_y: float = (local.y / -local.z) / half_h
	var ndc_x: float = (local.x / -local.z) / (half_h * aspect)
	var height: float = DESIGN_HEIGHT
	var width: float = DESIGN_HEIGHT * aspect
	return Vector2((ndc_x + 1.0) * 0.5 * width, (1.0 - ndc_y) * 0.5 * height)


# ---------------------------------------------------------------------------
# The buttons
# ---------------------------------------------------------------------------

func _test_four_buttons_dressed():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["menu_wow: no SceneTree"]
	var menu: Node = _instantiate(failures)
	if menu == null:
		return failures
	_add_and_ready(tree, menu)

	var host: Node = menu.get_node_or_null("UI/SafeArea")
	var buttons: Array = []
	_collect(menu, "Button", buttons)
	if buttons.size() != BUTTONS.size():
		failures.append("the title screen has %d buttons; it has four: Start, Free Play, Dress Up, Grown-ups"
				% buttons.size())

	var last_top: float = -1.0
	var last_height: float = -1.0
	var lefts: Array = []
	for button_name: String in BUTTONS.keys():
		var button: Button = (host.get_node_or_null(button_name) if host != null else null) as Button
		if button == null:
			failures.append("there is no %s" % button_name)
			continue
		var w: float = button.offset_right - button.offset_left
		var h: float = button.offset_bottom - button.offset_top
		if w + 0.5 < MIN_TOUCH_SIDE or h + 0.5 < MIN_TOUCH_SIDE:
			failures.append("%s is %.0fx%.0f; ART_BIBLE.md section 8 sets a 240x240 floor" % [button_name, w, h])
		# One row, one size, one spacing.
		if last_top >= 0.0 and (not is_equal_approx(button.offset_top, last_top)
				or not is_equal_approx(h, last_height)):
			failures.append("%s is not in the same row at the same size as the others" % button_name)
		last_top = button.offset_top
		last_height = h
		lefts.append(button.offset_left)

		var caption: Label = null
		var icon: Control = null
		for child: Node in button.get_children():
			if child is Label and not (child as Label).text.strip_edges().is_empty():
				caption = child
			elif child is Control and child.get_script() != null:
				icon = child
		if caption == null:
			failures.append("%s has no caption a grown-up can read aloud" % button_name)
		elif caption.get_theme_font_size("font_size") < 27:
			failures.append("%s's caption is under the 27 pt floor" % button_name)
		if icon == null:
			failures.append("%s has no picture; a pre-reader cannot tell it from the others" % button_name)
		elif icon.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			failures.append("%s's icon eats the touch meant for the button" % button_name)

		# Dressed by `main.gd`: a soft shadow behind, and press feedback wired.
		var shadow: Control = (host.get_node_or_null("%sShadow" % button_name)) as Control
		if shadow == null:
			failures.append("%s has no soft shadow" % button_name)
		elif shadow.get_index() > button.get_index():
			failures.append("%s's shadow is drawn ON TOP of the button" % button_name)
		if button.button_down.get_connections().is_empty() or button.button_up.get_connections().is_empty():
			failures.append("%s gives no press feedback" % button_name)
		if button.pressed.get_connections().is_empty():
			failures.append("%s does nothing when pressed" % button_name)

	if lefts.size() == BUTTONS.size():
		var gaps: Array = []
		for i: int in range(1, lefts.size()):
			gaps.append(float(lefts[i]) - float(lefts[i - 1]))
		for gap: float in gaps:
			if not is_equal_approx(gap, float(gaps[0])):
				failures.append("the four buttons are not evenly spaced (%s)" % str(gaps))
		# Centred: the row's middle is the screen's middle (anchors at 0.5).
		var row_left: float = float(lefts[0])
		var row_right: float = float(lefts[lefts.size() - 1]) + last_height
		if absf(row_left + row_right) > 1.0:
			failures.append("the button row is not centred (left %.0f, right %.0f)" % [row_left, row_right])

	# Grown-ups is still the quietest: lavender is the parent chrome.
	var parent_caption: Label = host.get_node_or_null("ParentButton/ParentCaption") as Label
	if parent_caption != null and parent_caption.text != "Grown-ups":
		failures.append("the parent button says '%s', not 'Grown-ups'" % parent_caption.text)

	tree.root.remove_child(menu)
	menu.free()
	return failures


## Each button, pressed on a menu that is in the tree, puts the scene it
## promises into the tree. This is the real `_enter_scene()` hand-off, driven
## by the real `pressed` signal -- not a check that a constant names a file.
func _test_each_button_opens_its_scene():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["menu_wow: no SceneTree"]

	for button_name: String in BUTTONS.keys():
		var expected: String = String(BUTTONS[button_name])
		if not ResourceLoader.exists(expected):
			failures.append("%s should open %s, which is not in this build" % [button_name, expected])
			continue
		var menu: Node = _instantiate(failures)
		if menu == null:
			continue
		_add_and_ready(tree, menu)
		var before: Array = tree.root.get_children().duplicate()
		var previous_scene: Node = tree.current_scene

		var button: Button = menu.get_node_or_null("UI/SafeArea/%s" % button_name) as Button
		if button == null:
			failures.append("no %s to press" % button_name)
		else:
			button.pressed.emit()

		var opened: Node = null
		for child: Node in tree.root.get_children():
			if not before.has(child):
				opened = child
		if opened == null:
			failures.append("pressing %s put nothing into the tree; a child pressed a button and got nothing"
					% button_name)
		else:
			if opened.scene_file_path != expected:
				failures.append("pressing %s opened %s; it promises %s"
						% [button_name, opened.scene_file_path, expected])
			if tree.current_scene != opened:
				failures.append("pressing %s did not make the new scene current" % button_name)
			var coming_soon: Label = menu.get_node_or_null("UI/SafeArea/ComingSoonLabel") as Label
			if coming_soon != null and coming_soon.visible:
				failures.append("pressing %s showed 'Back in a moment!' although the scene opened" % button_name)
			tree.root.remove_child(opened)
			opened.free()

		tree.current_scene = previous_scene
		if is_instance_valid(menu):
			if menu.get_parent() == tree.root:
				tree.root.remove_child(menu)
			menu.free()
	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Under the root, and READIED. The headless runner never ticks a frame and its
## root is not yet active inside `_initialize()`, so `_ready()` does not fire on
## its own -- `test_ui_layout.gd` calls it by hand for the same reason. The READY
## notification is used rather than `_ready()` directly so `@onready` fields are
## resolved first, exactly as the engine does it.
func _add_and_ready(tree: SceneTree, menu: Node) -> void:
	tree.root.add_child(menu)
	if not menu.is_node_ready():
		menu.notification(Node.NOTIFICATION_READY)


func _instantiate(failures: Array) -> Node:
	if not ResourceLoader.exists(MENU_SCENE):
		failures.append("%s does not exist" % MENU_SCENE)
		return null
	var packed: PackedScene = load(MENU_SCENE) as PackedScene
	if packed == null or not packed.can_instantiate():
		failures.append("%s cannot be instantiated" % MENU_SCENE)
		return null
	return packed.instantiate()


func _collect(node: Node, type: String, into: Array) -> void:
	if node.is_class(type):
		into.append(node)
	for child: Node in node.get_children():
		_collect(child, type, into)
