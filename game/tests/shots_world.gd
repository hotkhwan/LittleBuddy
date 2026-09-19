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
const Rules := preload("res://scripts/kitchen/kitchen_rules.gd")

## The director's own margin (`house_level_director.gd::FOCUS_MARGIN`).
const FOCUS_MARGIN: float = 0.3

var _world: Node = null
var _suffix: String = "ipad"

## The frame the polish set is photographed in, when the window cannot BE that
## frame.
##
## `--resolution 2340x1080` is a request, not an instruction: the window manager
## clamps it to the display, and on this machine every "wide iPhone" shot in the
## repository is really 1686 x 935 -- a 1.80 aspect filed as evidence for a 2.17
## one. That is not a rounding error, it is a different composition: the camera
## solves its distance from the aspect ratio, so the shot being judged is not the
## shot the device gets.
##
## So the world is hosted in a `SubViewport` of exactly the asked-for size and
## photographed from ITS texture. The camera inside sees that viewport's aspect
## and nothing else, so the framing is the device's framing. `Vector2i.ZERO`
## keeps the old behaviour of shooting the window.
var _frame: Vector2i = Vector2i.ZERO
var _viewport: SubViewport = null


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_suffix = args[0] if args.size() > 0 else "ipad"

	# `-- polish <suffix>` photographs the WORLD POLISH set instead of the camera
	# set: the same rooms, plus the interactive kitchen driven through its real
	# state so the counter, the open fridge and the carried item are all real.
	if _suffix == "polish":
		_suffix = String(args[1]) if args.size() > 1 else "ipad"
		if args.size() > 2:
			var wide: PackedStringArray = String(args[2]).split("x")
			if wide.size() == 2:
				_frame = Vector2i(int(wide[0]), int(wide[1]))
		await _run_polish()
		return

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


## -- The world-polish set ------------------------------------------------------
##
## Everything below drives the SHIPPING kitchen (`kitchen_state.gd`) rather than
## posing a mockup, so a picture can only ever show a state the game can really
## be in. The room shots are the same exploration shots the camera pass uses, so
## a before/after pair is comparable pixel for pixel.
func _run_polish() -> void:
	await process_frame
	var packed: PackedScene = load("res://scenes/house/house_world.tscn")
	_world = packed.instantiate()
	var host: Node = root
	if _frame != Vector2i.ZERO:
		_viewport = SubViewport.new()
		_viewport.size = _frame
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport.transparent_bg = false
		root.add_child(_viewport)
		host = _viewport
	host.add_child(_world)
	await _settle(0.5)

	_world.call("place_in_room", HouseLayout.KITCHEN, "default")
	await _settle(0.6)
	_report(HouseLayout.KITCHEN)
	await _shot("world_kitchen_%s" % _suffix)

	var state: RefCounted = _world.call("get_kitchen_state")
	if state == null:
		print("  WARN: the kitchen has no interactive state")
	else:
		# Fridge open: can a child spot the banana, the apple and the bottle?
		state.call("set_open", Rules.STATION_FRIDGE, true)
		# The door is TWEENED (`kitchen_view.gd::DOOR_SWING_SEC`), so a shot taken
		# on the next frame photographs a closed fridge and files it as evidence
		# that the fridge opens. Wait it out.
		await _settle(0.6)
		await _shot("world_kitchen_open_%s" % _suffix)

		# Ingredient on the worktop, ingredient in her hands -- the two questions
		# the brief asks about visibility, in one frame.
		_apply(state.call("take", Rules.STATION_FRIDGE, "banana"), "take the banana")
		_apply(state.call("place", Rules.STATION_COUNTER), "put the banana down")
		_apply(state.call("take", Rules.STATION_FRIDGE, "bottle"), "take the bottle")
		await _settle(0.3)
		await _shot("world_kitchen_counter_%s" % _suffix)

		# And the same moment close up, which is where a floating or sunk held
		# item shows.
		await _focus_shot("kitchen.counter", Vector3(-0.8, 0.0, -1.0),
				"world_carry_%s" % _suffix)

	_world.call("place_in_room", HouseLayout.BEDROOM, "default")
	await _settle(0.6)
	_report(HouseLayout.BEDROOM)
	await _shot("world_nursery_%s" % _suffix)
	await _focus_shot("bedroom.littleBuddy", Vector3.ZERO, "world_nursery_focus_%s" % _suffix)

	# The other two rooms are not the brief's subject, but the rug treatment is
	# shared by all four, so they are photographed to prove nothing regressed in
	# the rooms this pass was not looking at.
	for room_id: String in [HouseLayout.BATHROOM, HouseLayout.LIVING_ROOM]:
		_world.call("place_in_room", room_id, "default")
		await _settle(0.6)
		await _shot("world_room_%s_%s" % [room_id, _suffix])

	print("\nPOLISH SHOTS DONE (%s)" % _suffix)
	quit(0)


## A kitchen verb, with its refusal printed rather than swallowed: a shot must
## never quietly photograph a step that did not happen.
func _apply(report: Variant, what: String) -> void:
	var dictionary: Dictionary = report if report is Dictionary else {}
	if not bool(dictionary.get("ok", false)):
		print("  WARN: could not %s (%s)" % [what, String(dictionary.get("say", ""))])


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
	var source: Viewport = _viewport if _viewport != null else root.get_viewport()
	var image: Image = source.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + out_name + ".png")
	var err: int = image.save_png(path)
	print("  %s %s.png" % ["shot" if err == OK else "FAIL", out_name])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
