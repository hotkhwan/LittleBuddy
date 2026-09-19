extends SceneTree

## World + camera evidence. Dev-only; nothing in the game references it.
##
##   Godot --path game --resolution 1334x750 --script res://tests/shots_world.gd -- ipad
##   Godot --path game --resolution 2340x1080 --script res://tests/shots_world.gd -- iphone
##
## Photographs the REAL `house_world.tscn` -- the rooms a child walks into, not a
## rebuilt approximation -- in the two shots that matter for framing:
##
##   * EXPLORATION: each room as the child finds it.
##   * FOCUS: a beat's close-up, composed exactly the way
##     `house_level_director.gd` composes it (`camera_focus.frame_points()` over
##     the station, the child and the room floor, then `focus_activity()`).
##
## Composing the close-up here with the director's own module is the point: a
## harness that invented its own framing would prove nothing about the shot the
## child gets.

const OUT_DIR: String = "docs/shots/"
const CameraFocus := preload("res://scripts/camera/camera_focus.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## The director's own margin (`house_level_director.gd::FOCUS_MARGIN`).
const FOCUS_MARGIN: float = 0.3

var _world: Node = null
var _suffix: String = "ipad"


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_suffix = args[0] if args.size() > 0 else "ipad"

	await process_frame
	var packed: PackedScene = load("res://scenes/house/house_world.tscn")
	_world = packed.instantiate()
	root.add_child(_world)
	await _settle(0.5)

	# Exploration: every room, as the child finds it.
	for room_id: String in HouseLayout.room_ids():
		_world.call("place_in_room", room_id, "default")
		await _settle(0.5)
		_report(room_id)
		await _shot("c_room_%s_%s" % [room_id, _suffix])

	# Focus: bottle prep at the kitchen counter.
	_world.call("place_in_room", HouseLayout.KITCHEN, "default")
	await _settle(0.4)
	await _focus_shot("kitchen.counter", Vector3(-0.8, 0.0, -1.0), "c_focus_counter_%s" % _suffix)

	# Focus: feeding, at the baby in the bedroom.
	_world.call("place_in_room", HouseLayout.BEDROOM, "default")
	await _settle(0.4)
	await _focus_shot("bedroom.littleBuddy", Vector3.ZERO, "c_focus_buddy_%s" % _suffix)

	print("\nSHOTS DONE (%s)" % _suffix)
	quit(0)


## Stages the child at `stand`, composes the beat's box with the director's own
## module, and applies it through the camera the game uses.
func _focus_shot(semantic_id: String, stand: Vector3, out_name: String) -> void:
	var target: Node = _world.call("get_target_by_semantic_id", semantic_id)
	if target == null:
		print("  WARN: no target %s" % semantic_id)
		return
	var room_id: String = semantic_id.split(".")[0]
	var origin: Vector3 = HouseLayout.room_origin(room_id)
	var station: Vector3 = SpatialUtil.world_position(target as Node3D)
	var character: Node = _world.call("get_character")
	var child: Vector3 = station
	if character is Node3D:
		if stand != Vector3.ZERO:
			SpatialUtil.set_world_position(character, origin + stand)
		child = SpatialUtil.world_position(character as Node3D)
	await _settle(0.25)

	var camera: Object = _world.call("get_camera")
	var height: float = HouseLayout.FLOOR_Y + HouseLayout.CAMERA_FOCUS_HEIGHT
	var shot: Dictionary = CameraFocus.frame_points(
		[station, child], height, FOCUS_MARGIN,
		CameraFocus.MIN_RADIUS, CameraFocus.MAX_RADIUS,
		HouseLayout.world_floor_bounds(room_id)
	)
	camera.call("focus_activity", shot["focus"], float(shot["radius"]))
	camera.call("settle")
	await _settle(0.5)
	var solution: Dictionary = camera.call("get_last_solution")
	print("  focus %-22s radius=%.2f distance=%.2f fov=%.1f binding=%s" % [
		semantic_id, float(shot["radius"]), float(solution.get("distance", 0.0)),
		float(solution.get("fov", 0.0)), String(solution.get("binding", "?"))])
	await _shot(out_name)


func _report(room_id: String) -> void:
	var camera: Object = _world.call("get_camera")
	if camera == null or not camera.has_method("get_last_solution"):
		return
	var solution: Dictionary = camera.call("get_last_solution")
	print("  room  %-22s distance=%.2f fov=%.1f binding=%s fits=%s" % [
		room_id, float(solution.get("distance", 0.0)), float(solution.get("fov", 0.0)),
		String(solution.get("binding", "?")), str(solution.get("fits", false))])


func _shot(out_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + out_name + ".png")
	var err: int = image.save_png(path)
	print("  %s %s.png" % ["shot" if err == OK else "FAIL", out_name])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
