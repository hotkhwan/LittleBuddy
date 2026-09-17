extends RefCounted

## The spike scene itself: structure, framing, and the drag/drop regression.
##
## ## The framing check, and why it exists
##
## A previously shipped bug inverted the camera's pitch in a .tscn and pushed the
## baby, the bottle and the teddy entirely below the viewport -- while every
## automated test passed, because nothing tested what was on screen. So this file
## unprojects every landmark through the camera's real basis and asserts it lands
## inside the visible rectangle with margin, and in front of the camera rather
## than behind it.
##
## That is necessary but NOT sufficient: it cannot tell you whether the scene
## looks any good, whether the character reads as a character, or whether the
## walk speed feels calm. Those still need a human looking at a running build.
##
## Covers required behaviour 3 (drag/drop still works) and the structural half of
## behaviours 1 and 2.

const SCENE_PATH: String = "res://scenes/spike/nav_spike.tscn"
const Layout := preload("res://scenes/spike/spike_layout.gd")
const ActivityTarget := preload("res://scripts/navigation/activity_target.gd")
const DragPlaneScript := preload("res://scripts/interaction/drag_plane.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## Every aspect ratio the game ships on: the 4:3 iPad viewport from
## project.godot, a 16:9 phone, and a tall landscape iPhone. The camera distance
## is fitted per aspect, so all three have to work from one composition.
const ASPECT_RATIOS: Array[float] = [1366.0 / 1024.0, 16.0 / 9.0, 19.5 / 9.0]
## Landmarks must sit inside the middle of the screen with room to spare, so a
## rounded corner, a notch or a safe-area inset cannot clip them. Must match
## `spike_layout.gd`, which is asserted below.
const SAFE_MARGIN: float = 0.08

## The scripts that make up the spike. None of them may reach into the rest of
## the game: the spike must be deletable in one commit.
const SPIKE_SCRIPTS: Array[String] = [
	"res://scenes/spike/nav_spike.gd",
	"res://scenes/spike/spike_layout.gd",
	"res://scenes/spike/spike_buddy_view.gd",
	"res://scenes/spike/spike_ball.gd",
]
const FORBIDDEN_DEPENDENCIES: Array[String] = [
	"scenes/baby_room", "scripts/save/", "scripts/progression/", "scripts/speech/",
	"scripts/content/", "scripts/gameplay/mission_runner", "scripts/rewards/",
	"SaveService", "SpeechService", "RewardManager",
]

## One camera, one light, one environment. The performance budget, as a test.
const SINGLE_NODE_TYPES: Array[String] = ["Camera3D", "DirectionalLight3D", "WorldEnvironment"]
const BANNED_NODE_TYPES: Array[String] = [
	"OmniLight3D", "SpotLight3D", "GPUParticles3D", "CPUParticles3D", "RigidBody3D", "ReflectionProbe",
]


func test_name() -> String:
	return "nav_spike_scene"


func run():
	var failures: Array = []
	failures.append_array(_test_scene_text())
	failures.append_array(_test_spike_is_self_contained())
	failures.append_array(_test_camera_framing())

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		failures.append("no SceneTree; the scene could not be instantiated")
		return failures

	var packed: Resource = load(SCENE_PATH)
	if packed == null or not (packed is PackedScene):
		failures.append("could not load %s as a PackedScene" % SCENE_PATH)
		return failures
	var scene: Node = (packed as PackedScene).instantiate()
	if scene == null or not (scene is Node3D):
		failures.append("%s did not instantiate as a Node3D" % SCENE_PATH)
		return failures

	tree.root.add_child(scene)
	# The headless runner never fires `_ready()`, and the whole scene is built
	# there -- navigation mesh, floor, camera framing, wiring. Call it by hand.
	scene.call("_ready")

	failures.append_array(_test_structure(scene))
	failures.append_array(_test_navigation_built(scene))
	failures.append_array(_test_targets_registered(scene))
	failures.append_array(_test_drag_and_drop_still_works(scene))

	tree.root.remove_child(scene)
	scene.free()
	return failures


## -- Static checks -------------------------------------------------------------

func _test_scene_text():
	var failures: Array = []
	var text: String = _read(SCENE_PATH)
	if text.is_empty():
		return ["the spike scene is missing or empty"]

	for node_type: String in SINGLE_NODE_TYPES:
		var count: int = text.count('type="%s"' % node_type)
		if count != 1:
			failures.append("expected exactly one %s in the spike, found %d" % [node_type, count])
	for banned: String in BANNED_NODE_TYPES:
		if text.contains('type="%s"' % banned):
			failures.append("the spike must not contain a %s (performance budget)" % banned)

	for required: String in [
		'type="NavigationRegion3D"', 'type="CharacterBody3D"', 'type="NavigationAgent3D"',
		'type="Marker3D"', 'type="CanvasLayer"',
	]:
		if not text.contains(required):
			failures.append("the spike scene has no node of %s" % required)

	if not text.contains('target_id = "%s"' % Layout.TOY_BOX_ID):
		failures.append("the interactive object declares no semantic target id")
	return failures


## The spike must be deletable in a single commit, with nothing else depending on
## it and it depending on nothing else.
func _test_spike_is_self_contained():
	var failures: Array = []
	for path: String in SPIKE_SCRIPTS:
		var source: String = _read(path)
		if source.is_empty():
			failures.append("could not read %s" % path)
			continue
		for forbidden: String in FORBIDDEN_DEPENDENCIES:
			if source.contains(forbidden):
				failures.append("%s references %s; the spike must stay standalone"
						% [path, forbidden])
	return failures


## The check the inverted-pitch bug would have failed.
##
## Computed from the camera constants rather than read back from a live viewport,
## because the constants are where that bug lived. Checked at every aspect ratio
## the game ships on, since the camera distance is fitted per aspect.
func _test_camera_framing():
	var failures: Array = []
	var distance: float = Layout.fit_camera_distance(Layout.CAMERA_REFERENCE_ASPECT)
	var position: Vector3 = Layout.camera_position(distance)
	var basis: Basis = Basis.looking_at(Layout.CAMERA_TARGET - position, Vector3.UP)
	var forward: Vector3 = -basis.z

	# Sanity: the camera must look DOWN at the floor from above it. The shipped
	# bug was exactly a sign error here.
	if position.y <= Layout.FLOOR_Y:
		failures.append("the camera is not above the floor")
	if forward.y >= 0.0:
		failures.append("the camera is pitched upwards (forward.y = %f); every object would be "
				% forward.y + "below the viewport")
	if forward.z >= 0.0:
		failures.append("the camera is looking away from the room")

	# Every shipping aspect ratio: 4:3 iPad, 16:9, and a tall landscape iPhone.
	# `fit_camera_distance()` has to solve all three from one composition.
	for aspect: float in ASPECT_RATIOS:
		var fitted: float = Layout.fit_camera_distance(aspect)
		var half_height: float = tan(deg_to_rad(Layout.CAMERA_FOV) * 0.5)
		var half_width: float = half_height * aspect
		var limit: float = 1.0 - SAFE_MARGIN

		if fitted >= Layout.CAMERA_MAX_DISTANCE:
			failures.append("no camera distance frames the room at aspect %.2f" % aspect)
			continue
		if not bool(Layout.frames_everything(fitted, half_width, half_height, limit)):
			failures.append("the fitted distance %.2f does not frame the room at aspect %.2f"
					% [fitted, aspect])

		# And it must be the CLOSEST such distance -- otherwise the room is framed
		# but tiny, which on a phone screen is its own kind of unplayable.
		var closer: float = fitted - Layout.CAMERA_FIT_STEP * 2.0
		if closer > Layout.CAMERA_MIN_DISTANCE and bool(
			Layout.frames_everything(closer, half_width, half_height, limit)
		):
			failures.append("the camera sits further back than it needs to at aspect %.2f" % aspect)

	# A narrow screen must end up further away than a wide one: the room's width
	# is what binds on a 4:3 iPad. If that ordering ever inverts, the fit is wrong.
	var tablet: float = Layout.fit_camera_distance(4.0 / 3.0)
	var phone: float = Layout.fit_camera_distance(19.5 / 9.0)
	if tablet < phone:
		failures.append("a 4:3 screen should need MORE distance than a tall landscape phone "
				+ "(got %.2f vs %.2f)" % [tablet, phone])

	# Child-friendly framing: the whole room visible at once, no camera controls
	# to operate. If the room had to be panned, a four-year-old could not play it.
	if Layout.landmarks().size() < 8:
		failures.append("too few landmarks checked for the framing test to mean anything")
	if not is_equal_approx(Layout.CAMERA_SAFE_MARGIN, SAFE_MARGIN):
		failures.append("this test and the layout disagree about the safe margin")
	return failures


## -- Instantiated checks --------------------------------------------------------

func _test_structure(scene: Node):
	var failures: Array = []
	var expected: Dictionary = {
		"Camera3D": "Camera3D",
		"NavigationRegion3D": "NavigationRegion3D",
		"NavigationController": "Node3D",
		"LittleBuddy": "CharacterBody3D",
		"ToyBox": "Area3D",
		"Ball": "Area3D",
		"BallDropZone": "Area3D",
	}
	for unique_name: String in expected.keys():
		var node: Node = scene.get_node_or_null("%" + unique_name)
		if node == null:
			failures.append("the spike scene has no %%%s" % unique_name)
			continue
		if not node.is_class(String(expected[unique_name])):
			failures.append("%%%s should be a %s, is a %s"
					% [unique_name, String(expected[unique_name]), node.get_class()])

	var character: Node = scene.get_node_or_null("%LittleBuddy")
	if character != null:
		if character.get_node_or_null("NavigationAgent3D") == null:
			failures.append("the character has no NavigationAgent3D")
		if character.get_node_or_null("CollisionShape3D") == null:
			failures.append("the character has no collision shape")
		if not NavMath.is_within(SpatialUtil.world_position(character as Node3D), Layout.START_POSITION, 0.01):
			failures.append("the character should start at the layout's start position, is at %s"
					% str(SpatialUtil.world_position(character as Node3D)))
		if String(character.call("get_state_name")) != "idle":
			failures.append("the character should start idle")

		# The animation seam, end to end. The view builds its own body and clips in
		# its `_ready()`, which the headless runner never fires, so build it by hand
		# and then confirm the character finds the player and can drive it with
		# SEMANTIC names -- never a clip name.
		var view: Node = character.get_node_or_null("BuddyView")
		if view == null:
			failures.append("the character has no view to animate")
		else:
			view.call("build")
			for shipped: String in ["idle", "walk"]:
				if not bool(character.call("can_play_action", shipped)):
					failures.append("the character cannot play '%s'; the animation seam is not "
							% shipped + "bound to the view")
			if bool(character.call("can_play_action", "brushTeeth")):
				failures.append("'brushTeeth' is not animated yet and must not claim to be")

	var toy_box: Node = scene.get_node_or_null("%ToyBox")
	if toy_box != null:
		if not bool(toy_box.call("has_interaction_point")):
			failures.append("the interactive object has no InteractionPoint")
		if String(toy_box.call("get_activity_target_id")) != Layout.TOY_BOX_ID:
			failures.append("the interactive object has the wrong semantic id")
		var described: Dictionary = toy_box.call("describe", Layout.START_POSITION)
		if not NavMath.is_within(described.get("standPosition", Vector3.ZERO),
				Layout.TOY_BOX_STAND_POSITION, 0.05):
			failures.append("the interaction point is not where the layout says, got %s"
					% str(described.get("standPosition", Vector3.ZERO)))
	return failures


func _test_navigation_built(scene: Node):
	var failures: Array = []
	var region: Node = scene.get_node_or_null("%NavigationRegion3D")
	if region == null:
		return ["no NavigationRegion3D"]
	var mesh: NavigationMesh = region.get("navigation_mesh")
	if mesh == null:
		return ["the spike scene built no navigation mesh"]
	if mesh.get_polygon_count() < 100:
		failures.append("the navigation mesh has only %d polygons; the room is not walkable"
				% mesh.get_polygon_count())
	if not is_equal_approx(mesh.agent_radius, Layout.AGENT_RADIUS):
		failures.append("the navigation mesh does not use the layout's agent radius")
	return failures


func _test_targets_registered(scene: Node):
	var failures: Array = []
	var character: Node = scene.get_node_or_null("%LittleBuddy")
	var controller: Node = scene.get_node_or_null("%NavigationController")
	if character == null or controller == null:
		return ["the character or navigation controller is missing"]

	if not bool(character.call("has_activity_target", Layout.TOY_BOX_ID)):
		failures.append("the navigation controller did not register the toy box with the "
				+ "character; tapping it would do nothing")
	if controller.call("get_character") != character:
		failures.append("the navigation controller is not bound to the character")

	# The whole loop, with only a string: tap the toy box, walk, arrive, face it.
	var ready_ids: Array = []
	character.connect("interaction_ready", func(id: String) -> void: ready_ids.append(id))
	if not bool(character.call("move_to", Layout.TOY_BOX_ID)):
		failures.append("move_to(\"%s\") should set off from the start position" % Layout.TOY_BOX_ID)
	for _frame: int in range(2000):
		character.call("step_movement", 1.0 / 60.0)
		if String(character.call("get_state_name")) == "idle":
			break
	if ready_ids != [Layout.TOY_BOX_ID]:
		failures.append("expected exactly one interaction-ready for the toy box, got %s"
				% str(ready_ids))
	return failures


## Required behaviour 3. Navigation must not break the interaction model the game
## already ships.
func _test_drag_and_drop_still_works(scene: Node):
	var failures: Array = []
	var ball: Node = scene.get_node_or_null("%Ball")
	var zone: Node = scene.get_node_or_null("%BallDropZone")
	var character: Node = scene.get_node_or_null("%LittleBuddy")
	if ball == null or zone == null or character == null:
		return ["the draggable ball, its drop zone or the character is missing"]

	# It is an ordinary DraggableObject, with the ordinary drag API intact.
	for method: String in [
		"set_enabled", "reset_position", "animate_return_to_origin", "set_drop_zone",
		"is_interaction_active",
	]:
		if not ball.has_method(method):
			failures.append("the draggable lost DraggableObject.%s()" % method)

	# Layers: the draggable stays on layer 1, activity targets on layer 2, so a
	# tap-to-walk raycast can never steal a press the draggable needed.
	if int(ball.get("collision_layer")) != 1:
		failures.append("the draggable should stay on collision layer 1, is on %d"
				% int(ball.get("collision_layer")))
	var toy_box: Node = scene.get_node_or_null("%ToyBox")
	if toy_box != null and int(toy_box.get("collision_layer")) == int(ball.get("collision_layer")):
		failures.append("the activity target and the draggable share a collision layer")
	if int(toy_box.get("collision_layer")) != ActivityTarget.ACTIVITY_TARGET_LAYER:
		failures.append("the activity target is not on the activity layer")

	# The drop zone tracks the character -- including WHILE IT WALKS, which is the
	# case navigation could plausibly have broken.
	ball.call("update_zone_position")
	var resting: Vector3 = SpatialUtil.world_position(zone as Node3D)
	if not NavMath.is_within(resting, SpatialUtil.world_position(character as Node3D), 0.01):
		failures.append("the drop zone should sit on the character, is at %s" % str(resting))

	character.call("move_to_ground", 2.0, 1.8)
	for _frame: int in range(60):
		character.call("step_movement", 1.0 / 60.0)
		ball.call("update_zone_position")
	var moved: Vector3 = SpatialUtil.world_position(zone as Node3D)
	if NavMath.flat_distance(moved, resting) < 0.2:
		failures.append("the drop zone did not follow the walking character")
	if not NavMath.is_within(moved, SpatialUtil.world_position(character as Node3D), 0.01):
		failures.append("the drop zone drifted off the walking character")

	# And delivery into that moving zone still resolves through the same
	# unchanged DragPlane maths the Baby Room uses.
	var delivered: Array = []
	ball.connect("delivered", func() -> void: delivered.append(true))
	if not DragPlaneScript.point_in_drop_zone(moved, moved, Layout.DROP_ZONE_RADIUS):
		failures.append("a ball dropped on the zone centre should count as delivered")
	if DragPlaneScript.point_in_drop_zone(
		moved + Vector3(Layout.DROP_ZONE_RADIUS + 0.2, 0.0, 0.0), moved, Layout.DROP_ZONE_RADIUS
	):
		failures.append("a ball dropped well outside the zone should not count as delivered")

	ball.call("_on_dropped_in_zone")
	if delivered.size() != 1:
		failures.append("the draggable should emit exactly one delivery, got %d" % delivered.size())

	# Generous for a small child on a small screen.
	if Layout.DROP_ZONE_RADIUS < 0.2:
		failures.append("the drop zone is too small for a child's imprecise drag")
	character.call("stop")
	return failures


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
