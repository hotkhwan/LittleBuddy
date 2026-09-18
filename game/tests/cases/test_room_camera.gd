extends RefCounted

## `room_camera.gd`: the thin node that applies the pure framing maths.
##
## The maths itself is covered by `test_camera_framing.gd`. This file covers the
## things only a real node can get wrong: does the transform actually land on the
## `Camera3D`, does `focus_activity()` / `restore_room_frame()` round-trip, does a
## resize re-fit, does the interface a room will call defensively via `has_method`
## actually exist, and does any of it explode when the camera is not in a tree.
##
## Note the constraint this file is written under: `_ready()` does NOT fire for
## nodes added to the root in the headless `--script` runner, which is exactly why
## `room_camera.gd` wires itself lazily on first use. If that lazy path ever
## regresses, the size-changed test below stops working.

const RoomCameraScript := preload("res://scripts/camera/room_camera.gd")
const Framing := preload("res://scripts/camera/camera_framing.gd")
const Insets := preload("res://scripts/camera/safe_area_insets.gd")

const ROOM: Dictionary = {
	"bounds": Rect2(-2.0, -2.0, 4.0, 4.0),
	"focus": Vector3(0.0, 0.5, 0.0),
	"angle": 37.0,
	"minDistance": 3.0,
	"maxDistance": 24.0,
}

## What a room will call. `agentWORLD` consumes this defensively via
## `has_method()`, so removing or renaming one of these silently turns the camera
## into a no-op rather than an error -- which is the worst possible failure mode
## for something visual. Pin them.
const PUBLIC_API: Array[String] = [
	"frame_room",
	"focus_activity",
	"restore_room_frame",
	"refresh",
	"get_room_framing",
	"get_active_framing",
	"get_last_solution",
	"current_aspect",
	"current_insets",
	"is_focused_on_activity",
]


func test_name() -> String:
	return "room_camera"


func run():
	var failures: Array = []
	failures.append_array(_test_public_api())
	failures.append_array(_test_no_manual_camera_control())
	failures.append_array(_test_frames_out_of_tree())
	failures.append_array(_test_frames_in_tree())
	failures.append_array(_test_focus_and_restore())
	failures.append_array(_test_refits_on_resize())
	failures.append_array(_test_survives_nothing())
	return failures


func _test_public_api():
	var failures: Array = []
	var camera: Camera3D = _make_camera()
	for method: String in PUBLIC_API:
		if not camera.has_method(method):
			failures.append("room_camera lost %s(); a room calling it via has_method() would "
					% method + "silently do nothing")
	if not camera.has_signal("framed"):
		failures.append("room_camera lost the 'framed' signal")
	camera.free()
	return failures


## No orbit, no pinch, no drag-to-look. A four-year-old cannot operate a camera,
## and an input handler here would also steal taps from tap-to-walk.
func _test_no_manual_camera_control():
	var failures: Array = []
	var source: String = _read("res://scripts/camera/room_camera.gd")
	if source.is_empty():
		return ["could not read room_camera.gd"]
	for forbidden: String in [
		"func _input", "func _unhandled_input", "func _gui_input", "InputEventScreenDrag",
		"InputEventMagnifyGesture", "InputEventPanGesture", "set_process_input",
	]:
		if source.contains(forbidden):
			failures.append("room_camera handles input (%s); the camera must never be "
					% forbidden + "manually controllable by a child")

	# The transform must be COMPUTED, never read back from a .tscn -- an inverted
	# pitch authored in a scene file is how the baby, bottle and teddy once ended
	# up off screen with every test still green.
	if not source.contains("_set_world_transform"):
		failures.append("room_camera no longer assigns a computed transform")
	return failures


## The headless runner builds nodes without a tree, and `Node3D.global_transform`
## silently returns the identity there -- "everything is at the origin" instead of
## a loud failure. The camera must still end up where the maths says.
func _test_frames_out_of_tree():
	var failures: Array = []
	var camera: Camera3D = _make_camera()
	camera.call("frame_room", ROOM)

	var solution: Dictionary = camera.call("get_last_solution")
	if solution.is_empty():
		camera.free()
		return ["frame_room() produced no solution"]

	var expected: Vector3 = solution["position"]
	if camera.transform.origin.distance_to(expected) > 0.001:
		failures.append("the camera node is at %s but the solver said %s"
				% [str(camera.transform.origin), str(expected)])
	if not is_equal_approx(camera.fov, float(solution["fov"])):
		failures.append("the camera's field of view (%.1f) does not match the one the fit "
				% camera.fov + "was computed with (%.1f)" % float(solution["fov"]))
	if camera.keep_aspect != Camera3D.KEEP_HEIGHT:
		failures.append("the camera must stay in KEEP_HEIGHT; the whole fit assumes a fixed "
				+ "VERTICAL field of view")

	# Pitched down at the floor, looking at the room.
	var forward: Vector3 = -camera.transform.basis.z
	if forward.y >= -0.05:
		failures.append("the camera is not pitched down (forward.y = %.3f)" % forward.y)
	if camera.transform.origin.y <= 0.0:
		failures.append("the camera is below the floor")
	if (Vector3(ROOM["focus"]) - camera.transform.origin).dot(forward) <= 0.0:
		failures.append("the room's focus point is behind the camera")

	camera.free()
	return failures


## Attached to the runner's root, where a viewport exists.
##
## Note what is deliberately NOT asserted here. In the headless `--script` runner
## a node added to `tree.root` is not `is_inside_tree()` and not `is_inside_world()`,
## so `global_transform` returns the identity and `is_position_in_frustum()`
## returns nothing -- the same class of silent lie `spatial_util.gd` exists for.
## Reading either would produce a test that passes for the wrong reason. The
## render pass is what covers the real-viewport case; here we check the parts that
## are honestly observable: the fit ran, it used the VIEWPORT's aspect rather than
## a constant, and the camera made itself current.
func _test_frames_in_tree():
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree available"]
	var failures: Array = []
	var camera: Camera3D = _make_camera()
	tree.root.add_child(camera)
	camera.call("frame_room", ROOM)

	var solution: Dictionary = camera.call("get_last_solution")
	if solution.is_empty():
		tree.root.remove_child(camera)
		camera.free()
		return ["frame_room() produced no solution inside the tree"]

	# The root is a Window, not a Node3D, so the world transform and the local one
	# coincide and this is a real check on where the camera ended up.
	if camera.transform.origin.distance_to(Vector3(solution["position"])) > 0.001:
		failures.append("under the root the camera landed at %s, not %s"
				% [str(camera.transform.origin), str(solution["position"])])
	if not camera.current:
		failures.append("frame_room() should make the room camera current")

	var viewport: Viewport = camera.get_viewport()
	if viewport != null:
		# The aspect it fitted at must be the viewport's REAL aspect. A fit that
		# quietly fell back to the 4:3 reference constant would crop a phone.
		var viewport_aspect: float = Framing.aspect_from_size(viewport.get_visible_rect().size)
		if not is_equal_approx(float(camera.call("current_aspect")), viewport_aspect):
			failures.append("the camera fitted at aspect %f, the viewport is %f"
					% [camera.call("current_aspect"), viewport_aspect])
		if not is_equal_approx(float(solution["aspect"]), viewport_aspect):
			failures.append("the solution was computed at a different aspect (%f) from the "
					% float(solution["aspect"]) + "viewport's (%f)" % viewport_aspect)

	tree.root.remove_child(camera)
	camera.free()
	return failures


func _test_focus_and_restore():
	var failures: Array = []
	var camera: Camera3D = _make_camera()
	camera.call("frame_room", ROOM)
	var room_transform: Transform3D = camera.transform
	var room_distance: float = float(camera.call("get_last_solution")["distance"])

	var target := Vector3(1.4, 0.4, -1.1)
	camera.call("focus_activity", target, 1.2)
	# Moving in glides; this case is about the destination. The glide itself is
	# `test_camera_activity_focus.gd`.
	camera.call("settle")
	if not bool(camera.call("is_focused_on_activity")):
		failures.append("the camera does not report that it is focused on an activity")
	var focus_distance: float = float(camera.call("get_last_solution")["distance"])
	if focus_distance >= room_distance:
		failures.append("focus_activity() did not move the camera closer (%.2f vs %.2f)"
				% [focus_distance, room_distance])
	for axis: int in range(3):
		if camera.transform.basis[axis].distance_to(room_transform.basis[axis]) > 0.0001:
			failures.append("focus_activity() changed the camera angle; it must be the same "
					+ "shot from closer")
			break

	camera.call("restore_room_frame")
	camera.call("settle")
	if bool(camera.call("is_focused_on_activity")):
		failures.append("restore_room_frame() left the camera focused")
	if camera.transform.origin.distance_to(room_transform.origin) > 0.001:
		failures.append("restore_room_frame() did not return the camera to %s, it is at %s"
				% [str(room_transform.origin), str(camera.transform.origin)])

	# The room framing must survive the round trip byte for byte -- the focused
	# framing is derived, never written back over it.
	var stored: Dictionary = camera.call("get_room_framing")
	if Rect2(stored["bounds"]) != Rect2(ROOM["bounds"]):
		failures.append("focusing an activity corrupted the stored room framing")
	camera.free()
	return failures


## Rotating an iPad, entering Stage Manager, or resizing a desktop window must
## re-fit, and the distance must genuinely change with the aspect.
##
## The `size_changed` CONNECTION cannot be asserted in the headless `--script`
## runner: a node added to `tree.root` there has no viewport at all, so there is
## nothing to connect to. Rather than write a test that quietly passes because it
## found nothing, this asserts the two halves that are observable -- the camera
## refuses to latch its wiring while disconnected (so it will connect the moment a
## real viewport appears), and re-fitting actually produces a different framing --
## and the connection itself is covered by the rendered screenshots.
func _test_refits_on_resize():
	var failures: Array = []
	var camera: Camera3D = _make_camera()

	var events: Array = []
	camera.connect("framed", func(solution: Dictionary) -> void: events.append(solution))
	camera.call("frame_room", ROOM)
	if events.size() != 1:
		failures.append("frame_room() should emit exactly one 'framed', got %d" % events.size())

	camera.call("refresh")
	if events.size() != 2:
		failures.append("refresh() should re-fit and emit again, got %d fits" % events.size())

	var viewport: Viewport = camera.get_viewport()
	if viewport == null:
		# The headless case. The camera must NOT have latched, or it would spend the
		# rest of the session deaf to rotation.
		if bool(camera.call("is_wired")):
			failures.append("the camera latched its wiring without a viewport; it would never "
					+ "connect to size_changed and the room would crop on rotation")
	else:
		if not bool(camera.call("is_wired")):
			failures.append("the camera saw a viewport but did not wire itself")
		if not viewport.size_changed.is_connected(Callable(camera, "_on_viewport_resized")):
			failures.append("the camera did not connect itself to size_changed; the room "
					+ "would crop when the device rotates")
		else:
			viewport.size_changed.emit()
			if events.size() != 3:
				failures.append("a size change should re-fit the camera; got %d fits"
						% events.size())
	camera.free()

	# The part that matters regardless of wiring: a re-fit at a DIFFERENT aspect
	# must actually move the camera. A "re-fit" that returned the same distance
	# everywhere would satisfy a connection test and still crop the iPad.
	var insets: Vector4 = Insets.chrome_insets()
	var portrait_ish: float = Framing.solve(ROOM, 1.0, insets)["distance"]
	var landscape: float = Framing.solve(ROOM, 19.5 / 9.0, insets)["distance"]
	if is_equal_approx(portrait_ish, landscape):
		failures.append("re-fitting at a different aspect produced the same distance; the fit "
				+ "is ignoring the aspect ratio")
	return failures


## Nothing framed, nonsense framed, framed twice -- none of it may crash or leave
## a non-finite transform on a node the whole scene is rendered through.
func _test_survives_nothing():
	var failures: Array = []
	var camera: Camera3D = _make_camera()

	camera.call("refresh")
	camera.call("restore_room_frame")
	if not camera.call("get_last_solution").is_empty():
		failures.append("a camera that was never framed should have no solution")

	camera.call("frame_room", {})
	camera.call("frame_room", {"bounds": Rect2(), "focus": Vector3.ZERO, "minDistance": INF})
	camera.call("focus_activity", Vector3(NAN, NAN, NAN), -5.0)
	camera.call("restore_room_frame")

	var origin: Vector3 = camera.transform.origin
	for component: float in [origin.x, origin.y, origin.z]:
		if not is_finite(component):
			failures.append("degenerate framing left the camera at %s" % str(origin))
			break
	if not is_finite(camera.fov) or camera.fov <= 0.0:
		failures.append("degenerate framing left the field of view at %f" % camera.fov)

	# A camera that never got a room framing still points somewhere sane after a
	# bare focus_activity(): the child must always be able to see Little Buddy.
	var fresh: Camera3D = _make_camera()
	fresh.call("focus_activity", Vector3(3.0, 0.2, -1.0))
	var solution: Dictionary = fresh.call("get_last_solution")
	if solution.is_empty():
		failures.append("focus_activity() before frame_room() did nothing at all")
	elif (Vector3(solution["focus"]) - fresh.transform.origin).dot(-fresh.transform.basis.z) <= 0.0:
		failures.append("focus_activity() before frame_room() put the target behind the camera")
	fresh.free()

	camera.free()
	return failures


func _make_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.set_script(RoomCameraScript)
	return camera


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
