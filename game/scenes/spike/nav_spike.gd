extends Node3D

## Navigation spike. A standalone room that exists only to answer one question:
## **does child-friendly tap-to-walk work, with an architecture worth keeping?**
##
## It is deliberately NOT the Baby Room and does not touch it. Nothing here
## imports a mission, a task, a star or a save file.
##
## What is on screen:
##   * a flat floor with a navigation mesh cut from `spike_layout.gd`
##   * a table and a toy box that paths must route around
##   * a sealed closet -- floor you can see and tap but genuinely cannot reach
##   * four tap pads, so a child has something obvious to aim at
##   * one interactive object (the toy box) with an authored `InteractionPoint`
##   * one draggable ball whose drop zone follows the walking character
##
## Everything visible is generated from `spike_layout.gd`, the same constants the
## navigation mesh is cut from, so the wall a child can see and the wall the
## navigation mesh knows about cannot drift apart.

const Layout := preload("res://scenes/spike/spike_layout.gd")
const GridNavMesh := preload("res://scripts/navigation/grid_nav_mesh.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

const FLOOR_COLOR: Color = Color(0.86, 0.78, 0.64)
const WALL_COLOR: Color = Color(0.72, 0.66, 0.6)
const TABLE_COLOR: Color = Color(0.78, 0.6, 0.44)
const PAD_COLOR: Color = Color(0.62, 0.86, 0.78)
const TOY_BOX_COLOR: Color = Color(0.95, 0.75, 0.82)
const BALL_COLOR: Color = Color(0.98, 0.83, 0.45)

@onready var _camera: Camera3D = %Camera3D
@onready var _region: NavigationRegion3D = %NavigationRegion3D
@onready var _character: CharacterBody3D = %LittleBuddy
@onready var _nav_controller: Node3D = %NavigationController
@onready var _toy_box: Area3D = %ToyBox
@onready var _ball: Area3D = %Ball
@onready var _drop_zone: Area3D = %BallDropZone
@onready var _status_label: Label = %StatusLabel

## The spike owns its navigation map rather than borrowing the world default.
var _owned_map: RID = RID()


func _ready() -> void:
	# Enables Area3D picking so the draggable ball behaves exactly as it does in
	# the Baby Room. Tap-to-walk deliberately runs in `_unhandled_input`, i.e.
	# only for presses nothing else claimed.
	#
	# Null-guarded because `_ready()` is also called by hand from
	# `test_nav_spike_scene.gd` -- the headless runner never fires it -- where
	# there is no viewport.
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.physics_object_picking = true

	_build_floor()
	_build_obstacles()
	_build_tap_pads()
	_build_navigation_mesh()

	apply_camera_framing()
	if viewport != null:
		# Re-frame on rotation and on any resize, so the room never crops when the
		# device turns or the window changes shape.
		viewport.size_changed.connect(apply_camera_framing)

	# The character, the toy box and the ball are placed in the .tscn, not here --
	# placement is an authoring decision and belongs next to the art. The layout
	# constants drive the navigation mesh instead, and
	# `test_nav_spike_scene.gd` asserts that the two agree, so they cannot drift.
	SpatialUtil.set_world_position(_character, Layout.START_POSITION)
	_nav_controller.call("set_camera", _camera)
	_nav_controller.call("bind_character", _character, self)
	_nav_controller.set("floor_height", Layout.FLOOR_Y)

	_ball.call(
		"attach_to_character",
		_drop_zone,
		_character,
		Layout.CHEST_OFFSET,
		Layout.DROP_ZONE_RADIUS
	)
	_ball.connect("delivered", _on_ball_delivered)

	_character.connect("arrived", _on_arrived)
	_character.connect("interaction_ready", _on_interaction_ready)
	_character.connect("move_failed", _on_move_failed)
	_character.connect("state_changed", _on_state_changed)

	# Facing the player rather than away. Turning to face things is a required
	# behaviour and you cannot judge it from the back of a head.
	_character.rotation.y = PI

	_set_status("Tap the floor.")


func _exit_tree() -> void:
	# The spike owns its navigation map, so it must give the RID back. Leaking one
	# would leave a dead map on the server for the rest of the session.
	if _owned_map.is_valid():
		NavigationServer3D.free_rid(_owned_map)
		_owned_map = RID()


## Frames the room for the CURRENT aspect ratio.
##
## Set in code, never trusted to the .tscn's `Transform3D`: an inverted pitch
## there once pushed every object off screen while every test still passed. The
## distance is fitted rather than fixed -- see `spike_layout.gd` for why a single
## hard-coded distance cannot serve both a landscape iPhone and an iPad.
func apply_camera_framing() -> void:
	var aspect: float = Layout.CAMERA_REFERENCE_ASPECT
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var size: Vector2 = viewport.get_visible_rect().size
		if size.x > 0.0 and size.y > 0.0:
			aspect = size.x / size.y

	var distance: float = Layout.fit_camera_distance(aspect)
	_camera.fov = Layout.CAMERA_FOV
	_camera.look_at_from_position(
		Layout.camera_position(distance), Layout.CAMERA_TARGET, Vector3.UP
	)
	_camera.current = true


## -- Generated geometry --------------------------------------------------------

func _build_floor() -> void:
	var bounds: Rect2 = Layout.FLOOR_BOUNDS
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = bounds.size
	floor_mesh.mesh = plane
	floor_mesh.material_override = _material(FLOOR_COLOR)
	floor_mesh.position = Vector3(bounds.get_center().x, Layout.FLOOR_Y, bounds.get_center().y)
	add_child(floor_mesh)


func _build_obstacles() -> void:
	for index: int in range(Layout.OBSTACLES.size()):
		# The toy box cuts the same hole in the navigation mesh as the others, but
		# it draws itself: it is a scene object with an `ActivityTarget`, not scenery.
		if index == Layout.TOY_BOX_OBSTACLE_INDEX:
			continue
		var rect: Rect2 = Layout.OBSTACLES[index]
		var box := MeshInstance3D.new()
		box.name = "Obstacle%d" % index
		var mesh := BoxMesh.new()
		mesh.size = GridNavMesh.obstacle_size(rect, Layout.WALL_HEIGHT)
		box.mesh = mesh
		box.material_override = _material(
			TABLE_COLOR if index == Layout.TABLE_OBSTACLE_INDEX else WALL_COLOR
		)
		box.position = GridNavMesh.obstacle_centre(rect, Layout.FLOOR_Y, Layout.WALL_HEIGHT)
		add_child(box)


## Flat discs on the floor. Decoration: the floor is tappable everywhere, but a
## four-year-old needs somewhere obvious to poke first.
func _build_tap_pads() -> void:
	var index: int = 0
	for pad: Vector3 in Layout.TAP_PADS:
		index += 1
		var disc := MeshInstance3D.new()
		disc.name = "TapPad%d" % index
		var mesh := CylinderMesh.new()
		mesh.top_radius = Layout.TAP_PAD_RADIUS
		mesh.bottom_radius = Layout.TAP_PAD_RADIUS
		mesh.height = 0.012
		mesh.radial_segments = 16
		disc.mesh = mesh
		disc.material_override = _material(PAD_COLOR)
		disc.position = Vector3(pad.x, Layout.FLOOR_Y + 0.006, pad.z)
		add_child(disc)


## Builds the mesh AND gives the spike its own navigation map.
##
## A dedicated map rather than the world default, for two reasons. The project's
## default map cell size (0.25 m) is coarser than this floor's 0.2 m grid, which
## Godot warns about and which could merge polygon edges that should stay apart --
## and the one thing that must never merge here is the sealed closet's wall.
## Owning the map also means the spike changes no global state and can be deleted
## without trace.
func _build_navigation_mesh() -> void:
	var obstacles: Array = []
	obstacles.assign(Layout.OBSTACLES)
	var mesh: NavigationMesh = GridNavMesh.build(
		Layout.FLOOR_BOUNDS, Layout.CELL_SIZE, obstacles, Layout.FLOOR_Y, Layout.AGENT_RADIUS
	)

	_owned_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(_owned_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(_owned_map, mesh.cell_size)
	# Smaller than the thinnest wall, so an edge connection can never bridge one.
	NavigationServer3D.map_set_edge_connection_margin(_owned_map, 0.05)
	NavigationServer3D.map_set_active(_owned_map, true)

	# Map BEFORE mesh: assigning the mesh while the region is still on the world
	# default map rasterises it at that map's coarser cell size and warns about it.
	_region.set_navigation_map(_owned_map)
	_region.navigation_mesh = mesh

	var agent: NavigationAgent3D = _character.get_node_or_null("NavigationAgent3D")
	if agent != null:
		agent.set_navigation_map(_owned_map)


## -- Feedback (short, warm, never a failure) ----------------------------------

func _on_arrived(target_id: String) -> void:
	_set_status("Here!" if target_id.is_empty() else "At the %s!" % _friendly_name(target_id))


## Child-facing text for a semantic id. Falls back to the id so a target whose
## display name was never authored still reads as something rather than nothing.
func _friendly_name(target_id: String) -> String:
	if target_id == Layout.TOY_BOX_ID:
		var display: String = String(_toy_box.get("display_name"))
		if not display.strip_edges().is_empty():
			return display
	return target_id


func _on_interaction_ready(target_id: String) -> void:
	# A child is shown the display name, never the camelCase id the code uses.
	_set_status("Ready to play with the %s!" % _friendly_name(target_id))
	# Proves the semantic action seam end to end: "pickUp" has no animation yet,
	# so the driver declines, the controller times it out anyway, and Little Buddy
	# returns cleanly to idle. No crash, no stuck state.
	_character.call("play_action", "pickUp")


func _on_move_failed(_target_id: String, reason: String) -> void:
	# Never a red X. An unreachable tap simply says "let's try over here".
	if reason == "unreachable":
		_set_status("Let's go somewhere else!")


func _on_state_changed(state_name: String) -> void:
	if state_name == "walking":
		_set_status("Walking...")


func _on_ball_delivered() -> void:
	_set_status("Nice catch!")
	# Tween-driven, so it needs a live tree. The spike scene is also exercised
	# headlessly, where there is none.
	if _ball.is_inside_tree():
		_ball.call("animate_return_to_origin")


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
