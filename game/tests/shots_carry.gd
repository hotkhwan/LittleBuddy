extends SceneTree

## CARRY AND MOVEMENT, PHOTOGRAPHED. Dev-only; nothing in the game references it.
##
##   Godot --path game --script res://tests/shots_carry.gd -- ipad 1334x750
##   Godot --path game --script res://tests/shots_carry.gd -- iphone 2340x1080
##
## The world is the REAL `house_world.tscn`, hosted in a `SubViewport` of exactly
## the asked-for size (see `shots_rc.gd` for why `--resolution` is not evidence),
## and every frame is driven through the same public API the game uses:
## `carry_node()` / `put_down_carried()` on the character, and the affordances
## on Bunny, a spawned toy and a drop zone. Frames written, each asserted at the
## exact pixel size:
##
##   carry_bunny_front_<s>.png      Bunny held, Aliz facing the camera
##   carry_bunny_quarter_<s>.png    the same, three-quarter
##   carry_bunny_placed_<s>.png     Bunny set back down on the floor
##   carry_prop_held_<s>.png        a toy taken from the floor, in her right hand
##   carry_prop_placed_<s>.png      the toy set down on its pad
##   move_walk_<s>.png / move_run_<s>.png   the stick inside / past the run ring
##
## Numbers printed alongside are the ones the pictures have to agree with:
## Bunny's root relative to her, the socket in use, one Bunny in the room, his
## hunger before and after, and the measured speed in each move frame.

const OUT_DIR: String = "docs/shots/"
const Spatial := preload("res://scripts/navigation/spatial_util.gd")
const SpawnerScript := preload("res://scripts/gameplay/object_spawner.gd")
const DropZoneScript := preload("res://scripts/gameplay/drop_zone.gd")

var _suffix: String = "ipad"
var _frame: Vector2i = Vector2i(1334, 750)
var _viewport: SubViewport = null
var _world: Node = null
var _aliz: Node3D = null
var _bunny: Node3D = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[0]).strip_edges().is_empty():
		_suffix = String(args[0]).strip_edges()
	if args.size() > 1:
		var wide: PackedStringArray = String(args[1]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))
	print("=== carry + movement, %s, %dx%d ===" % [_suffix, _frame.x, _frame.y])

	await process_frame
	var save: Node = root.get_node_or_null("SaveService")
	if save != null and save.has_method("reset_profile"):
		save.call("reset_profile")
		var plan: GDScript = load("res://scripts/onboarding/onboarding_plan.gd")
		if plan != null and save.has_method("set_setting"):
			save.call("set_setting", plan.SETTING_KEY, true)

	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_world = load("res://scenes/house/house_world.tscn").instantiate()
	# Free Play: no director walks the character anywhere while we stage.
	if _world.has_method("set_progression_mode"):
		_world.call("set_progression_mode", 1)
	_viewport.add_child(_world)
	await _settle(0.8)

	_aliz = _world.call("get_character")
	var room: Node = _world.call("get_current_room")
	for child: Node in room.get_children():
		if child.has_method("set_carried_by"):
			_bunny = child
	if _aliz == null or _bunny == null:
		return _die("no caregiver or no Bunny in the current room")
	var stats: RefCounted = _bunny.call("get_stats")
	var hunger_before: float = float(stats.call("get_stat", "hunger"))

	# Stand her on his interaction point, facing the camera-side of the room.
	var him: Vector3 = _bunny.global_position
	_aliz.global_position = him + Vector3(0.0, 0.0, 0.62)
	_aliz.rotation.y = 0.0
	_aliz.call("stop")
	await _settle(0.4)

	# -- Carry: pick him up through his own affordance.
	var offer: Dictionary = _bunny.call("get_affordance", _aliz)
	print("  affordance before: %s" % String(offer.get("verb", "")))
	if String(offer.get("verb", "")) != "carry":
		_fail.append("Bunny offered '%s', not 'carry'" % offer.get("verb", ""))
	if not bool(_bunny.call("perform_affordance", _aliz)):
		_fail.append("perform_affordance(carry) failed")
	await _settle(0.9)
	_report_hold("held")
	# Front: she faces the camera (+Z is towards the camera in every room).
	_aliz.rotation.y = PI
	await _settle(0.5)
	await _shot("carry_bunny_front_%s" % _suffix)
	# Three-quarter.
	_aliz.rotation.y = PI * 0.72
	await _settle(0.5)
	await _shot("carry_bunny_quarter_%s" % _suffix)
	# Walk a step with him so the frame is a carry in motion, not a pose.
	for _i: int in range(30):
		_aliz.call("drive", -0.5, 0.0)
		await process_frame
	_aliz.call("stop_driving")
	await _settle(0.4)
	_report_hold("after a walk")
	if _count_bunnies(_world) != 1:
		_fail.append("%d Bunnies in the world while carried" % _count_bunnies(_world))

	# -- Put down.
	var placed: Dictionary = _bunny.call("get_affordance", _aliz)
	if String(placed.get("verb", "")) != "place":
		_fail.append("held Bunny offered '%s', not 'place'" % placed.get("verb", ""))
	_aliz.rotation.y = PI * 0.85
	if not bool(_bunny.call("perform_affordance", _aliz)):
		_fail.append("perform_affordance(place) failed")
	await _settle(0.9)
	var floor_gap: float = absf(_bunny.global_position.y - _aliz.global_position.y)
	var clearance: float = Vector2(_bunny.global_position.x - _aliz.global_position.x,
			_bunny.global_position.z - _aliz.global_position.z).length()
	print("  placed: floor gap %.3f m, %.2f m from her, carried=%s, state=%s"
			% [floor_gap, clearance, str(_bunny.call("is_carried")), _aliz.call("get_carry_state")])
	if floor_gap > 0.005:
		_fail.append("Bunny put down %.3f m off the floor" % floor_gap)
	if clearance < 0.44:
		_fail.append("Bunny put down %.2f m from her -- inside her" % clearance)
	if bool(_bunny.call("is_carried")):
		_fail.append("Bunny still carried after the put-down")
	await _shot("carry_bunny_placed_%s" % _suffix)
	var hunger_after: float = float(stats.call("get_stat", "hunger"))
	print("  hunger before %.1f, after %.1f" % [hunger_before, hunger_after])
	if not is_equal_approx(hunger_before, hunger_after):
		_fail.append("Bunny's hunger changed across the carry")

	# -- A prop: a toy on the floor, taken, carried, placed on its pad.
	var data: Dictionary = _object_data("teddy")
	if data.is_empty():
		_fail.append("no 'teddy' in content/objects.json")
	else:
		var toy: Area3D = SpawnerScript.spawn(data, "dragToToyBox")
		room.add_child(toy)
		toy.global_position = _aliz.global_position + Vector3(0.7, 0.0, 0.2)
		toy.call("set_home_position", toy.position)
		var zone: Area3D = DropZoneScript.create(DropZoneScript.ZONE_TOY_BOX, 0.3)
		zone.set("show_marker", true)
		room.add_child(zone)
		zone.global_position = _aliz.global_position + Vector3(-0.9, 0.0, 0.3)
		zone.call("set_marker_visible", true)
		toy.call("set_drop_zone", zone, 0.3)
		await _settle(0.3)
		var take: Dictionary = toy.call("get_affordance", _aliz)
		if String(take.get("verb", "")) != "take":
			_fail.append("the toy offered '%s', not 'take'" % take.get("verb", ""))
		_aliz.rotation.y = PI
		if not bool(toy.call("perform_affordance", _aliz)):
			_fail.append("perform_affordance(take) failed")
		await _settle(0.9)
		var controller: Node = _aliz.call("get_carry_controller")
		var hand_local: Vector3 = _aliz.global_transform.affine_inverse() * toy.global_position
		print("  toy held at %s in her frame, socket %s, using socket %s"
				% [str(hand_local), controller.call("get_socket_name"), str(controller.call("is_using_socket"))])
		if hand_local.y < 0.35:
			_fail.append("the toy is held %.2f m up; not in a hand" % hand_local.y)
		if toy.get_parent() == room:
			_fail.append("the toy never left the room's floor")
		await _shot("carry_prop_held_%s" % _suffix)
		var place: Dictionary = zone.call("get_affordance", _aliz)
		if String(place.get("verb", "")) != "place":
			_fail.append("the pad offered '%s', not 'place'" % place.get("verb", ""))
		if not bool(zone.call("perform_affordance", _aliz)):
			_fail.append("perform_affordance(place) on the pad failed")
		await _settle(0.9)
		var to_zone: float = toy.global_position.distance_to(zone.global_position)
		print("  toy placed %.3f m from its pad, parent %s" % [to_zone, toy.get_parent().name])
		if to_zone > 0.03:
			_fail.append("the toy landed %.2f m from its pad" % to_zone)
		await _shot("carry_prop_placed_%s" % _suffix)

	# -- Movement: the stick inside the walk band, then past the run ring.
	await _move_shot("move_walk_%s" % _suffix, 0.6)
	await _move_shot("move_run_%s" % _suffix, 1.0)

	if _fail.is_empty():
		print("\nCARRY SHOTS OK")
		quit(0)
	else:
		print("\nCARRY SHOTS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


func _move_shot(name: String, magnitude: float) -> void:
	_aliz.global_position = _bunny.global_position + Vector3(-1.2, 0.0, 0.9)
	_aliz.call("stop")
	await _settle(0.3)
	var start: Vector3 = _aliz.global_position
	var started: int = Time.get_ticks_msec()
	for _i: int in range(40):
		_aliz.call("drive", magnitude, 0.0)
		await process_frame
	var seconds: float = float(Time.get_ticks_msec() - started) * 0.001
	var covered: float = (_aliz.global_position - start).length()
	print("  %s: %.2f m in %.2f s = %.2f m/s, running=%s, speed=%.2f"
			% [name, covered, seconds, covered / maxf(seconds, 0.001),
				str(_aliz.call("is_running")), float(_aliz.call("get_speed"))])
	_aliz.call("drive", magnitude, 0.0)
	await _shot(name)
	_aliz.call("stop_driving")
	await _settle(0.4)


func _report_hold(label: String) -> void:
	var controller: Node = _aliz.call("get_carry_controller")
	var local: Vector3 = _aliz.global_transform.affine_inverse() * _bunny.global_position
	print("  %s: Bunny root at %s in her frame, state=%s, socket=%s, clip=%s, activity=%s"
			% [label, str(local), _aliz.call("get_carry_state"),
				str(controller.call("is_using_socket")), _bunny.call("get_life_clip"),
				_bunny.call("get_activity")])
	if String(_aliz.call("get_carry_state")) != "held":
		_fail.append("%s: carry state is '%s', not held" % [label, _aliz.call("get_carry_state")])
	if local.y < 0.15 or local.y > 0.7:
		_fail.append("%s: Bunny's feet are %.2f m up" % [label, local.y])
	if local.z > -0.08:
		_fail.append("%s: Bunny is not in front of her" % label)
	if not bool(controller.call("is_using_socket")):
		_fail.append("%s: the hold is the fallback offset, not her rig socket" % label)
	if String(_bunny.call("get_life_clip")) != "carried":
		_fail.append("%s: Bunny plays '%s', not the carried pose" % [label, _bunny.call("get_life_clip")])


func _count_bunnies(node: Node) -> int:
	var count: int = 1 if node.has_method("set_carried_by") and node.has_method("satisfy") else 0
	for child: Node in node.get_children():
		count += _count_bunnies(child)
	return count


func _object_data(object_id: String) -> Dictionary:
	var file: FileAccess = FileAccess.open("res://content/objects.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var rows: Array = parsed.get("objects", []) if parsed is Dictionary else (parsed as Array)
	for row: Variant in rows:
		if row is Dictionary and String(row.get("objectId", "")) == object_id:
			return row
	return {}


func _shot(name: String) -> void:
	await _settle(0.3)
	RenderingServer.force_draw(true, 0.0)
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + name + ".png")
	if image.save_png(path) != OK:
		_fail.append("could not write %s.png" % name)
		return
	if image.get_width() != _frame.x or image.get_height() != _frame.y:
		_fail.append("%s.png is %dx%d but %dx%d was asked for"
				% [name, image.get_width(), image.get_height(), _frame.x, _frame.y])
		return
	print("  shot %s.png  %dx%d" % [name, image.get_width(), image.get_height()])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _die(reason: String) -> void:
	print("CARRY SHOTS FAIL: %s" % reason)
	quit(1)
