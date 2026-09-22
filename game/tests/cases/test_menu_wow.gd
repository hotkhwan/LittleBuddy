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
##     each one PRESSED hands the tree the scene it promises;
##   * the garden MOVES (canopies, flowers, clouds, butterflies, the cat) when
##     time passes, and stands still when it does not;
##   * Start and Free Play play THE WALK HOME first -- Aliz picks Bunny up and
##     carries him to the door -- which completes inside 2.5 s, can be skipped
##     by a tap, and then runs exactly the hand-off it always ran;
##   * the version reads "v" + `GameVersion.BUILD`, bottom-right, quiet;
##   * Dress Up opens a screen that works on its own: Aliz, swatches that
##     recolour her, and a Back button that returns to this menu.

const MainScript := preload("res://scenes/main/main.gd")
const Garden := preload("res://scripts/menu/menu_garden.gd")
const Palette := preload("res://scripts/ui/palette.gd")

const MENU_SCENE: String = "res://scenes/main/main.tscn"
const DRESS_UP_SCENE: String = "res://scenes/dress_up/dress_up.tscn"
const GameVersion := preload("res://scripts/content_packs/game_version.gd")

## The walk home must be over inside this, tap or no tap.
const DEPARTURE_MAX_SEC: float = 2.5
## The cover the departure leaves under the root, swept up by every case here.
const COVER_NAME: String = "SceneCover"

## Section 10 of the art bible budgets a hero character at 4,000 triangles; the
## whole garden is allowed fifteen of those (the playtest brief of 2026-09-20
## set 60k for the richer garden: trees in layers, a blossom tree, a cat, a
## bird, butterflies, round-petalled flowers, far cottages). Still a fraction
## of what one unoptimised prop export costs.
const GARDEN_TRIANGLE_CAP: int = 60000

## The layout the scene stores, in the 1024-tall design space.
const DESIGN_HEIGHT: float = 1024.0
const TITLE_BOTTOM: float = 170.0
const BUTTON_ROW_TOP: float = DESIGN_HEIGHT - 276.0
## The narrowest shape the game ships on: a 4:3 iPad.
const NARROWEST_ASPECT: float = 4.0 / 3.0
const MIN_TOUCH_SIDE: float = 240.0

## Play with Bunny goes to the HOUSE (via the activity picker, 2026-09-21);
## it used to promise the Chapter 2 Baby Room, which was the owner's bug.
const BUTTONS: Dictionary = {
	"PlayButton": "res://scenes/house/house_world.tscn",
	"FreePlayButton": "res://scenes/house/house_world.tscn",
	"DressUpButton": "res://scenes/dress_up/dress_up.tscn",
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
	failures.append_array(_test_the_garden_moves())
	failures.append_array(_test_departure_completes())
	failures.append_array(_test_departure_can_be_skipped())
	failures.append_array(_test_version_label())
	failures.append_array(_test_dress_up_round_trip())
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
		"doors": 1, "windows": 3, "trees": 6, "flowers": 30, "clouds": 4,
		"stones": 8, "hills": 2, "fencePosts": 8, "toys": 3,
		"butterflies": 2, "cats": 1, "signs": 1, "birds": 1, "farCottages": 2, "bushes": 6,
	}
	for kind: String in minimums.keys():
		if int(counts.get(kind, 0)) < int(minimums[kind]):
			failures.append("the garden has %d %s; a storybook garden needs at least %d"
					% [int(counts.get(kind, 0)), kind, int(minimums[kind])])
	if int(counts.get("suns", 0)) != 1:
		failures.append("the garden has %d suns; there is one" % int(counts.get("suns", 0)))
	for node_name: String in ["House", "Path", "Trees", "Flowerbeds", "Fence", "Clouds", "SkyDome", "Grass",
			"Stump", "Butterflies", "CornerBushes", "Hedge", "FarCottages"]:
		if garden.get_node_or_null(node_name) == null:
			failures.append("the garden has no %s node" % node_name)
	var house: Node = garden.get_node_or_null("House")
	if house != null:
		for part: String in ["Walls", "Roof", "Door", "Window", "AtticWindow", "Chimney", "Door/Hinge/Heart"]:
			if house.get_node_or_null(part) == null:
				failures.append("the house has no %s" % part)
	if garden.get_node_or_null("Toys/Mailbox/Bird") == null:
		failures.append("there is no bluebird on the mailbox")
	if garden.get_node_or_null("Stump/Cat") == null:
		failures.append("there is no cat asleep on the stump")
	if garden.get_node_or_null("Trees/HeroTree/Sign") == null:
		failures.append("there is no sign hanging from the big tree")
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
	# Four in the row plus the wide "Learn with Aliz" banner above it (the tutor
	# entry, agentB_tutor_entry patch). The banner is not part of the row maths.
	var expected_buttons: int = BUTTONS.size() + (1 if host != null and host.get_node_or_null("LearnWithAlizButton") != null else 0)
	if buttons.size() != expected_buttons:
		failures.append("the title screen has %d buttons; it has four in the row (Play with Bunny, Free Play, Dress Up, Grown-ups) plus Learn with Aliz"
				% buttons.size())
	var learn: Button = (host.get_node_or_null("LearnWithAlizButton") if host != null else null) as Button
	if learn == null:
		failures.append("there is no LearnWithAlizButton (the tutor entry)")
	else:
		if learn.size.x + 0.5 < 240.0 or learn.size.y + 0.5 < 240.0:
			failures.append("Learn with Aliz is %s; ART_BIBLE section 8 asks 240x240 for a child-facing control" % str(learn.size))
		if learn.pressed.get_connections().is_empty():
			failures.append("Learn with Aliz does nothing when pressed")

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
	# And the primary button says what it does, in the owner's exact words.
	var play_caption: Label = host.get_node_or_null("PlayButton/PlayCaption") as Label
	if play_caption == null or play_caption.text.replace("\n", " ").strip_edges() != "Play with Baby":
		failures.append("the primary button says '%s', not 'Play with Baby'"
				% (play_caption.text if play_caption != null else ""))

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
			if button_name == "PlayButton":
				# Play with Bunny opens the activity picker first; the walk home
				# starts when a CARD is tapped. Nothing has opened yet.
				if bool(menu.call("is_departing")):
					failures.append("Play with Bunny walked home before a card was chosen")
				var picker: Control = menu.call("get_activity_picker")
				if picker == null:
					failures.append("Play with Bunny opened no activity picker")
				else:
					var ids: Array = picker.call("get_mission_ids")
					if ids.is_empty():
						failures.append("the activity picker has no cards")
					else:
						picker.call("choose", String(ids[0]))
			# Play with Bunny (once a card is tapped) and Free Play walk home
			# first; nothing must have opened yet, and a tap (skip) must open it
			# at once. The other two go straight.
			var departing: bool = bool(menu.call("is_departing"))
			var walks: bool = button_name in ["PlayButton", "FreePlayButton"]
			if walks and not departing:
				failures.append("pressing %s did not start the walk home" % button_name)
			if not walks and departing:
				failures.append("pressing %s started the walk home; only Start and Free Play do" % button_name)
			if departing:
				if _opened_scene(tree, before) != null:
					failures.append("pressing %s opened the scene before the walk home had finished" % button_name)
				menu.call("skip_departure")

		var opened: Node = _opened_scene(tree, before)
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
		_sweep_cover(tree)
		if is_instance_valid(menu):
			if menu.get_parent() == tree.root:
				tree.root.remove_child(menu)
			menu.free()
	return failures


# ---------------------------------------------------------------------------
# The garden moves
# ---------------------------------------------------------------------------

func _test_the_garden_moves():
	var failures: Array = []
	var garden: Node3D = Garden.new()
	garden.build()
	if int(garden.count_moving_parts()) < 20:
		failures.append("only %d things in the garden move; a breeze touches the canopies, the flowers, the clouds, the butterflies and the cat"
				% int(garden.count_moving_parts()))
	var canopy: Node3D = garden.get_node_or_null("Trees/Tree0/Canopy") as Node3D
	var cloud: Node3D = garden.get_node_or_null("Clouds/Cloud0") as Node3D
	var butterfly: Node3D = garden.get_node_or_null("Butterflies/Butterfly0") as Node3D
	var flower: Node3D = garden.get_node_or_null("Flowerbeds/Bed0/Flower0") as Node3D
	var cat_body: Node3D = garden.get_node_or_null("Stump/Cat/Body") as Node3D
	if canopy == null or cloud == null or butterfly == null or flower == null or cat_body == null:
		garden.free()
		return ["the garden is missing a canopy, a cloud, a butterfly, a flower or the cat to move"]
	var canopy_before: Vector3 = canopy.rotation
	var cloud_before: Vector3 = cloud.position
	var fly_before: Vector3 = butterfly.position
	var flower_before: Vector3 = flower.rotation
	var cat_before: Vector3 = cat_body.scale
	# Stood still: nothing moves.
	garden.set_ambient_enabled(false)
	garden.tick(0.8)
	if canopy.rotation != canopy_before or cloud.position != cloud_before:
		failures.append("the garden moved with ambient motion switched off")
	garden.set_ambient_enabled(true)
	garden.tick(0.8)
	if canopy.rotation.is_equal_approx(canopy_before):
		failures.append("the canopy did not sway after 0.8 s")
	if cloud.position.is_equal_approx(cloud_before):
		failures.append("the cloud did not drift after 0.8 s")
	if butterfly.position.is_equal_approx(fly_before):
		failures.append("the butterfly did not flutter after 0.8 s")
	if flower.rotation.is_equal_approx(flower_before):
		failures.append("the flower did not sway after 0.8 s")
	if cat_body.scale.is_equal_approx(cat_before):
		failures.append("the cat did not breathe after 0.8 s")
	# Gentle: a sway is a few degrees, never a lurch.
	garden.tick(1.3)
	for t: int in range(40):
		garden.tick(0.1)
		if absf(rad_to_deg(canopy.rotation.z)) > 4.0 or absf(rad_to_deg(canopy.rotation.x)) > 4.0:
			failures.append("the canopy leans %.1f degrees; the breeze is two to three" % rad_to_deg(canopy.rotation.z))
			break
	garden.free()
	return failures


# ---------------------------------------------------------------------------
# The walk home
# ---------------------------------------------------------------------------

## Start pressed: the walk runs through its phases, Bunny is lifted, the door
## opens, the cover comes up, and inside 2.5 s the promised scene is in the
## tree -- all driven by hand, frame by frame, as `_process()` would.
func _test_departure_completes():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["menu_wow: no SceneTree"]
	var menu: Node = _instantiate(failures)
	if menu == null:
		return failures
	_add_and_ready(tree, menu)
	var before: Array = tree.root.get_children().duplicate()
	var previous_scene: Node = tree.current_scene

	var play: Button = menu.get_node_or_null("UI/SafeArea/PlayButton") as Button
	play.pressed.emit()
	# Through the picker: the first card is the walk home's real trigger.
	var picker: Control = menu.call("get_activity_picker")
	if picker == null:
		_cleanup(tree, menu, previous_scene, before)
		return ["pressing Play with Bunny opened no activity picker"]
	var ids: Array = picker.call("get_mission_ids")
	if ids.is_empty() or not bool(picker.call("choose", String(ids[0]))):
		_cleanup(tree, menu, previous_scene, before)
		return ["the activity picker has no card to tap"]
	var departure: Node = menu.call("get_departure")
	if departure == null:
		_cleanup(tree, menu, previous_scene, before)
		return ["tapping a card started no walk home"]
	var phases: Array = []
	departure.phase_changed.connect(func(p: String) -> void: phases.append(p))
	phases.append(String(departure.call("get_phase")))

	var bunny: Node3D = menu.get_node_or_null("Bunny") as Node3D
	var bunny_start: Vector3 = bunny.position if bunny != null else Vector3.ZERO
	var hinge: Node3D = menu.get_node_or_null("Garden/House/Door/Hinge") as Node3D
	var safe_area: Control = menu.get_node_or_null("UI/SafeArea") as Control
	if safe_area != null and safe_area.modulate.a > 0.99:
		failures.append("the buttons are still fully visible while the walk home plays")
	if menu.get_node_or_null("UI/SkipCatcher") == null:
		failures.append("there is nothing catching the tap that skips the walk")

	var elapsed: float = 0.0
	var steps: int = 0
	var bunny_lifted_at: float = -1.0
	var cover_peak: float = 0.0
	var cover_early: float = 0.0
	while not bool(departure.call("is_done")) and steps < 400:
		departure.call("advance", 1.0 / 60.0)
		elapsed += 1.0 / 60.0
		steps += 1
		if bunny_lifted_at < 0.0 and bool(departure.call("is_bunny_carried")):
			bunny_lifted_at = elapsed
		# The cover is read WHILE the walk runs: once `finished` fires the menu
		# hands off and the departure lets go of the cover to reveal the new scene.
		cover_peak = maxf(cover_peak, float(departure.call("get_cover_alpha")))
		if elapsed < 1.5:
			cover_early = maxf(cover_early, float(departure.call("get_cover_alpha")))
	if not bool(departure.call("is_done")):
		failures.append("the walk home never finished")
	if elapsed > DEPARTURE_MAX_SEC + 0.05:
		failures.append("the walk home took %.2f s; it must be over inside %.1f s" % [elapsed, DEPARTURE_MAX_SEC])
	for wanted: String in ["turn", "pickUp", "walkHome", "cover", "done"]:
		if not phases.has(wanted):
			failures.append("the walk home never reached its '%s' phase (saw %s)" % [wanted, str(phases)])
	if bunny_lifted_at < 0.0:
		failures.append("Bunny was never picked up")
	elif bunny_lifted_at > 1.0:
		failures.append("Bunny was picked up at %.2f s; the lift starts before 0.8 s" % bunny_lifted_at)
	if bunny != null and bunny.position.distance_to(bunny_start) < 0.5:
		failures.append("Bunny is still where he started; he should have been carried toward the door")
	if bunny != null and bunny.position.y < 0.3:
		failures.append("Bunny ends at y=%.2f; carried, he rides at her chest, not on the ground" % bunny.position.y)
	if hinge != null and absf(rad_to_deg(hinge.rotation.y)) < 60.0:
		failures.append("the front door only opened %.0f degrees" % rad_to_deg(hinge.rotation.y))
	if cover_peak < 0.99:
		failures.append("the cover only reached %.2f before the walk ended; it must cover the cut" % cover_peak)
	if cover_early > 0.01:
		failures.append("the cover was already at %.2f in the first 1.5 s; the walk must be SEEN" % cover_early)

	var opened: Node = _opened_scene(tree, before)
	if opened == null:
		failures.append("the walk home finished and no scene was opened")
	else:
		if opened.scene_file_path != BUTTONS["PlayButton"]:
			failures.append("the walk home opened %s; Play with Bunny promises %s" % [opened.scene_file_path, BUTTONS["PlayButton"]])
		if tree.current_scene != opened:
			failures.append("the opened scene was not made current")
	_cleanup(tree, menu, previous_scene, before)
	return failures


## A tap during the walk goes straight to the game: the scene is in the tree
## the moment `skip()` returns.
func _test_departure_can_be_skipped():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["menu_wow: no SceneTree"]
	var menu: Node = _instantiate(failures)
	if menu == null:
		return failures
	_add_and_ready(tree, menu)
	var before: Array = tree.root.get_children().duplicate()
	var previous_scene: Node = tree.current_scene

	var free_play: Button = menu.get_node_or_null("UI/SafeArea/FreePlayButton") as Button
	free_play.pressed.emit()
	var departure: Node = menu.call("get_departure")
	if departure == null:
		_cleanup(tree, menu, previous_scene, before)
		return ["pressing Free Play started no walk home"]
	departure.call("advance", 0.5)
	if _opened_scene(tree, before) != null:
		failures.append("the scene opened half a second into the walk, before any skip")
	# The tap, as the catcher would deliver it.
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	var catcher: Control = menu.get_node_or_null("UI/SkipCatcher") as Control
	if catcher == null:
		failures.append("no SkipCatcher to tap")
		menu.call("skip_departure")
	else:
		catcher.gui_input.emit(tap)
	if not bool(departure.call("is_done")):
		failures.append("a tap did not end the walk home")
	var opened: Node = _opened_scene(tree, before)
	if opened == null:
		failures.append("a tap ended the walk and no scene was opened")
	elif opened.scene_file_path != BUTTONS["FreePlayButton"]:
		failures.append("the skipped walk opened %s; Free Play promises %s" % [opened.scene_file_path, BUTTONS["FreePlayButton"]])
	# A second press while walking is a skip, never a second scene.
	_cleanup(tree, menu, previous_scene, before)
	return failures


# ---------------------------------------------------------------------------
# The version, and Dress Up
# ---------------------------------------------------------------------------

func _test_version_label():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["menu_wow: no SceneTree"]
	var menu: Node = _instantiate(failures)
	if menu == null:
		return failures
	_add_and_ready(tree, menu)
	var label: Label = menu.get_node_or_null("UI/SafeArea/VersionLabel") as Label
	if label == null:
		failures.append("the title screen shows no version")
	else:
		var expected: String = "v" + GameVersion.BUILD
		if label.text != expected:
			failures.append("the version reads '%s'; GameVersion.BUILD says '%s'" % [label.text, expected])
		var size: int = label.get_theme_font_size("font_size")
		if size < 14 or size > 16:
			failures.append("the version is %d px; it is quiet, 14-16" % size)
		var colour: Color = label.get_theme_color("font_color")
		if absf(colour.a - 0.55) > 0.06:
			failures.append("the version is at %.0f%% alpha; it is ink at 55%%" % (colour.a * 100.0))
		if not colour.is_equal_approx(Color(Palette.INK, colour.a)):
			failures.append("the version is not ink")
		if label.anchor_right < 0.99 or label.anchor_bottom < 0.99:
			failures.append("the version is not anchored bottom-right")
		if label.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			failures.append("the version label eats touches")
	if String(MainScript.build_version()) != GameVersion.BUILD:
		failures.append("main.gd reads the build as '%s', not GameVersion.BUILD" % MainScript.build_version())
	tree.root.remove_child(menu)
	menu.free()
	return failures


## Dress Up on its own: Aliz is there, a swatch recolours her, Back returns to
## the title screen. The old target was an ActivityScene that needed the Baby
## Room's director and showed a grey screen when opened from the menu.
func _test_dress_up_round_trip():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["menu_wow: no SceneTree"]
	if not ResourceLoader.exists(DRESS_UP_SCENE):
		return ["%s does not exist" % DRESS_UP_SCENE]
	var packed: PackedScene = load(DRESS_UP_SCENE) as PackedScene
	if packed == null:
		return ["%s cannot be loaded" % DRESS_UP_SCENE]
	var screen: Node = packed.instantiate()
	var previous_scene: Node = tree.current_scene
	_add_and_ready(tree, screen)
	# Captured AFTER the screen is in, so the screen itself never reads as the
	# scene Back opened.
	var before: Array = tree.root.get_children().duplicate()

	if screen.get_node_or_null("Aliz") == null:
		failures.append("Dress Up has no Aliz")
	elif not bool(screen.call("is_model_available")):
		failures.append("Dress Up's Aliz has no model in this checkout")
	var swatches: Dictionary = screen.call("get_swatch_buttons")
	if swatches.size() < 3 or swatches.size() > 4:
		failures.append("Dress Up has %d swatches; three or four big ones" % swatches.size())
	for name: String in swatches.keys():
		var button: Button = swatches[name] as Button
		if button.custom_minimum_size.x < 120.0 or button.custom_minimum_size.y < 120.0:
			failures.append("swatch '%s' is %s; a child's finger needs 120 px" % [name, str(button.custom_minimum_size)])
		if button.pressed.get_connections().is_empty():
			failures.append("swatch '%s' does nothing" % name)
	var colour_before: Color = screen.call("get_accent_colour")
	if swatches.has("mint"):
		(swatches["mint"] as Button).pressed.emit()
		var after: Color = screen.call("get_accent_colour")
		if not after.is_equal_approx(Palette.MINT):
			failures.append("pressing the mint swatch left the accents %s" % str(after))
		if after.is_equal_approx(colour_before):
			failures.append("pressing a swatch changed nothing")
		if String(screen.call("get_current_swatch")) != "mint":
			failures.append("the current swatch is '%s' after pressing mint" % String(screen.call("get_current_swatch")))
	var hint: Label = screen.get_node_or_null("UI/SafeArea/HintLabel") as Label
	if hint == null or hint.text != "Tap a bow. Make it yours!":
		failures.append("Dress Up must explain its available bow-colour interaction")
	# One light, no shadows, no post -- the same budget as the menu.
	var lights: Array = []
	_collect(screen, "Light3D", lights)
	if lights.size() != 1 or not (lights[0] is DirectionalLight3D) or (lights[0] as DirectionalLight3D).shadow_enabled:
		failures.append("Dress Up must have exactly one DirectionalLight3D with shadows off")

	var back: Button = screen.get_node_or_null("UI/SafeArea/BackButton") as Button
	if back == null:
		failures.append("Dress Up has no Back button")
	else:
		var w: float = back.offset_right - back.offset_left
		var h: float = back.offset_bottom - back.offset_top
		if w < 240.0 or h < 120.0:
			failures.append("the Back button is %.0fx%.0f; it is big" % [w, h])
		back.pressed.emit()
		var opened: Node = _opened_scene(tree, before)
		if opened == null:
			failures.append("pressing Back opened nothing")
		else:
			if opened.scene_file_path != MENU_SCENE:
				failures.append("pressing Back opened %s, not the title screen" % opened.scene_file_path)
			if tree.current_scene != opened:
				failures.append("pressing Back did not make the title screen current")
			tree.root.remove_child(opened)
			opened.free()
		if is_instance_valid(screen) and not bool(screen.call("is_leaving")):
			failures.append("Dress Up does not know it is leaving after Back")
	tree.current_scene = previous_scene
	if is_instance_valid(screen):
		if screen.get_parent() == tree.root:
			tree.root.remove_child(screen)
		screen.free()
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


## The scene a press put under the root -- never the departure's cover, which
## is a `CanvasLayer` and not a scene.
static func _opened_scene(tree: SceneTree, before: Array) -> Node:
	for child: Node in tree.root.get_children():
		if before.has(child):
			continue
		if child is CanvasLayer and String(child.name) in [COVER_NAME, "SceneTransition"]:
			continue
		return child
	return null


static func _sweep_cover(tree: SceneTree) -> void:
	for cover_name: String in [COVER_NAME, "SceneTransition"]:
		var cover: Node = tree.root.get_node_or_null(cover_name)
		if cover != null:
			tree.root.remove_child(cover)
			cover.free()


func _cleanup(tree: SceneTree, menu: Node, previous_scene: Node, before: Array) -> void:
	var opened: Node = _opened_scene(tree, before)
	while opened != null:
		tree.root.remove_child(opened)
		opened.free()
		opened = _opened_scene(tree, before)
	_sweep_cover(tree)
	tree.current_scene = previous_scene
	if is_instance_valid(menu):
		if menu.get_parent() == tree.root:
			tree.root.remove_child(menu)
		menu.free()


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
