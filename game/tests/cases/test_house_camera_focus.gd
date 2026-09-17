extends RefCounted

## The camera close-up, wired end to end: an activity names a target by semantic
## id, the camera moves in, and it lets go again.
##
## `room_camera.gd` already had `frame_room()`, `focus_activity()` and
## `restore_room_frame()`, and `test_room_camera.gd` proves the fitting maths.
## What did not exist was anything that could CALL them from a semantic id --
## `focus_activity()` takes a world position on purpose, because the camera knows
## nothing about rooms or ids, so somebody has to do the resolution. That is
## `HouseWorld`, and this is the case that says so.
##
## Three properties, all of which would be silent if they broke:
##
##   1. focusing moves the camera CLOSER to the named target and still looks at
##      it -- `SpatialUtil` exists because `global_position` silently reports the
##      origin outside the tree, and a focus computed from (0,0,0) would frame an
##      empty patch of floor with every assertion about "the camera moved" still
##      passing;
##   2. restoring returns the exact whole-room shot, so an activity cannot leave
##      a child staring at a fridge;
##   3. walking into another room releases the focus by itself, because an
##      activity that is interrupted never gets to call `restore_room_frame()`.
##
## And the rule from `docs/ROOM_CAMERA_SYSTEM.md` §7 -- no free camera, no
## rotation, no pinch -- restated next to the feature most likely to add one.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const ROOM_CAMERA_PATH: String = "res://scripts/camera/room_camera.gd"

## Handlers that would put a child in charge of a camera.
const FORBIDDEN_INPUT_HANDLERS: Array[String] = [
	"func _input(", "func _unhandled_input(", "func _gui_input(",
	"func _unhandled_key_input(", "func _shortcut_input(",
]


func test_name() -> String:
	return "house_camera_focus"


func run():
	var failures: Array = []
	failures.append_array(_test_focus_moves_in_on_a_semantic_id())
	failures.append_array(_test_restore_returns_the_room_shot())
	failures.append_array(_test_changing_room_releases_the_focus())
	failures.append_array(_test_an_unknown_id_changes_nothing())
	failures.append_array(_test_the_child_never_drives_the_camera())
	return failures


func _test_focus_moves_in_on_a_semantic_id():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]

	world.call("place_in_room", "kitchen", "default")
	var camera: Camera3D = world.call("get_camera")
	if camera == null:
		_release(world)
		return ["the house has no camera"]
	if not camera.has_method("focus_activity"):
		_release(world)
		return ["the room camera was never adopted; the close-up has nothing to drive"]

	var target: Node = world.call("get_target_by_semantic_id", "kitchen.fridge")
	if target == null:
		_release(world)
		return ["the house has no 'kitchen.fridge' to focus on"]
	var fridge: Vector3 = SpatialUtil.world_position(target as Node3D)
	if fridge.is_equal_approx(Vector3.ZERO):
		failures.append("the fridge resolved to the origin; `global_position` reports (0,0,0) "
				+ "outside the tree, and a focus computed from it would frame nothing")

	var room_position: Vector3 = SpatialUtil.world_position(camera)
	var room_distance: float = room_position.distance_to(fridge)

	if not bool(world.call("focus_activity", "kitchen.fridge")):
		failures.append("focusing on 'kitchen.fridge' was refused")
	if not bool(world.call("is_focused_on_activity")):
		failures.append("the camera does not report itself as focused")

	var focused_position: Vector3 = SpatialUtil.world_position(camera)
	var focused_distance: float = focused_position.distance_to(fridge)
	if focused_distance >= room_distance:
		failures.append("focusing did not move the camera closer to the fridge (%.2f m -> %.2f m)"
				% [room_distance, focused_distance])
	if focused_position.is_equal_approx(room_position):
		failures.append("the camera did not move at all")
	# Still above the floor and still pitched down: the sign error that once put
	# every object off-screen while the whole suite passed.
	if focused_position.y <= fridge.y:
		failures.append("the focused camera is at or below the target; it must look DOWN")
	var forward: Vector3 = -SpatialUtil.world_transform(camera).basis.z
	if forward.dot((fridge - focused_position).normalized()) < 0.9:
		failures.append("the focused camera is not looking at the fridge")

	_release(world)
	return failures


func _test_restore_returns_the_room_shot():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]

	world.call("place_in_room", "livingRoom", "default")
	var camera: Camera3D = world.call("get_camera")
	if camera == null or not camera.has_method("restore_room_frame"):
		_release(world)
		return ["the room camera was never adopted"]

	var room_transform: Transform3D = SpatialUtil.world_transform(camera)
	world.call("focus_activity", "livingRoom.sofa")
	if SpatialUtil.world_transform(camera).is_equal_approx(room_transform):
		failures.append("focusing changed nothing, so restoring proves nothing")

	world.call("restore_room_frame")
	if bool(world.call("is_focused_on_activity")):
		failures.append("the camera still reports itself as focused after restoring")
	if not SpatialUtil.world_transform(camera).is_equal_approx(room_transform):
		failures.append(
			"restoring did not return the whole-room shot (%s -> %s). An activity that moves the "
			% [str(room_transform.origin), str(SpatialUtil.world_transform(camera).origin)]
			+ "camera in and cannot move it back leaves a child staring at a sofa."
		)

	# Restoring when nothing was focused is a no-op, not a jump.
	var settled: Transform3D = SpatialUtil.world_transform(camera)
	world.call("restore_room_frame")
	if not SpatialUtil.world_transform(camera).is_equal_approx(settled):
		failures.append("a second restore moved the camera")

	_release(world)
	return failures


## An activity interrupted by a door never calls `restore_room_frame()`, so the
## room change has to do it.
func _test_changing_room_releases_the_focus():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]

	world.call("place_in_room", "kitchen", "default")
	if not bool(world.call("focus_activity", "kitchen.fridge")):
		_release(world)
		return ["could not focus; the rest of this check would be vacuous"]

	world.call("place_in_room", "bedroom", "default")
	if bool(world.call("is_focused_on_activity")):
		failures.append(
			"walking into another room left the camera focused on the room the child just left. "
			+ "An activity cut short by a door never gets to release it."
		)

	_release(world)
	return failures


func _test_an_unknown_id_changes_nothing():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]

	world.call("place_in_room", "bedroom", "default")
	var camera: Camera3D = world.call("get_camera")
	if camera == null:
		_release(world)
		return ["the house has no camera"]
	var before: Transform3D = SpatialUtil.world_transform(camera)

	for unknown: String in ["", "bed", "attic.telescope", "bedroom", "bedroom.bed.extra"]:
		if bool(world.call("focus_activity", unknown)):
			failures.append("focusing on '%s' was accepted" % unknown)
		if not SpatialUtil.world_transform(camera).is_equal_approx(before):
			failures.append("focusing on '%s' moved the camera anyway" % unknown)

	# A target in ANOTHER room is not focusable from here either: only the
	# current room's targets are live, which is what makes "walk to the bathroom
	# sink from the bedroom" correctly refused rather than a walk through a wall.
	if bool(world.call("is_focused_on_activity")):
		failures.append("a refused focus still latched")

	_release(world)
	return failures


## `docs/ROOM_CAMERA_SYSTEM.md` §7. A four-year-old cannot operate a camera and
## must never be asked to.
func _test_the_child_never_drives_the_camera():
	var failures: Array = []
	var source: String = _read(ROOM_CAMERA_PATH)
	if source.length() < 200:
		return ["could not read %s" % ROOM_CAMERA_PATH]
	for handler: String in FORBIDDEN_INPUT_HANDLERS:
		if source.contains(handler):
			failures.append("room_camera.gd declares `%s`. There is no free camera, no orbit and "
					% handler + "no pinch: composition is authored per room and identical on "
					+ "every device.")
	for gesture: String in ["InputEventPanGesture", "InputEventMagnifyGesture", "set_orbit"]:
		if source.contains(gesture):
			failures.append("room_camera.gd mentions %s" % gesture)
	return failures


## -- Helpers -----------------------------------------------------------------------

func _build_house() -> Node:
	if not ResourceLoader.exists(HOUSE_SCENE):
		return null
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	if world == null:
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	world.call("build_world")
	return world


func _release(world: Node) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
