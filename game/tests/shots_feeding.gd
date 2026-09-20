extends SceneTree

## THE HIGHCHAIR, PHOTOGRAPHED FROM THE BABY ROOM. Dev-only.
##
##   Godot --path game --script res://tests/shots_feeding.gd -- 1334x750
##   Godot --path game --script res://tests/shots_feeding.gd -- 2340x1080
##
## Every frame comes out of `scenes/baby_room/baby_room.tscn` running the real
## `feedingTime` mission through the real `MissionRunner`: the room routes the
## task to the highchair, the harness plays the gesture through the stage's
## public API with REAL frames (no instant mode), and the SubViewport is exactly
## the size asked for -- printed back off the written image, because a window
## manager clamps `--resolution` and a clamped run files the wrong composition
## as evidence (see shots_bunny.gd for the same trap).
##
## Frames, in order: apple mid-drag, Bunny biting, banana unpeeled -> peeled,
## cup tipped with Bunny drinking, a wrong item (unhappy face + half star),
## guided mode (glow + arrow), the session summary.

const OUT_DIR: String = "docs/shots/"
const MISSION_ID: String = "feedingTime"
const Rules := preload("res://scripts/feeding/feeding_rules.gd")

var _frame: Vector2i = Vector2i(1334, 750)
var _viewport: SubViewport = null
var _room: Node = null
var _runner: Node = null
var _table: Node3D = null
var _fail: Array = []
var _shots: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		var wide: PackedStringArray = String(args[0]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))
	print("=== highchair from the baby room, %dx%d ===" % [_frame.x, _frame.y])

	await process_frame
	var save: Node = root.get_node_or_null("SaveService")
	if save != null and save.has_method("reset_profile"):
		save.call("reset_profile")

	var packed: PackedScene = load("res://scenes/baby_room/baby_room.tscn")
	if packed == null:
		return _die("baby_room.tscn will not load")
	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.physics_object_picking = true
	root.add_child(_viewport)
	_room = packed.instantiate()
	_viewport.add_child(_room)
	await _settle(0.8)

	_runner = _room.get_node_or_null("MissionRunner")
	if _runner == null:
		return _die("the room did not start mission mode")

	# APPLE: mid-drag, then biting.
	if not await _reach("feedApple"):
		return _die("could not reach feedApple")
	_table.call("begin_drag", "apple")
	var from: Vector2 = _table.call("get_item_screen_position", "apple")
	var to: Vector2 = _table.call("get_mouth_screen_position")
	_table.call("drag_to_screen", from.lerp(to, 0.55))
	await _settle(0.25)
	_check_state("apple mid-drag", bool(_table.call("is_dragging")), "the apple is being dragged")
	await _shot("feeding_apple_drag")
	_table.call("drag_to_mouth")
	await _settle(0.62)
	_check_state("apple bite", bool(_table.call("is_delivered")), "the apple was delivered")
	_check_state("apple bite", String(_table.call("get_bunny_clip")) == "eat", "Bunny is playing 'eat'")
	await _shot("feeding_apple_bite")
	await _settle(1.2)

	# BANANA: unpeeled, then peeled.
	if not await _reach("feedBanana"):
		return _die("could not reach feedBanana")
	await _settle(0.3)
	_check_state("banana unpeeled", not bool(_table.call("is_peeled", "banana")), "the banana is still in its peel")
	await _shot("feeding_banana_unpeeled")
	_table.call("tap_item", "banana")
	await _settle(0.6)
	_check_state("banana peeled", bool(_table.call("is_peeled", "banana")), "the banana is peeled")
	await _shot("feeding_banana_peeled")
	_table.call("begin_drag", "banana")
	_table.call("drag_to_mouth")
	await _settle(1.8)

	# CUP: tipped, Bunny drinking.
	if not await _reach("feedWater"):
		return _die("could not reach feedWater")
	_table.call("begin_drag", "water")
	_table.call("drag_to_mouth")
	await _settle(0.7)
	_check_state("cup drinking", String(_table.call("get_bunny_clip")) == "drink", "Bunny is playing 'drink'")
	var cup: Node3D = _table.call("get_item", "water")
	_check_state("cup drinking", cup != null and float(cup.call("get_tilt")) > 0.3, "the cup is tipped")
	await _shot("feeding_cup_drink")
	await _settle(2.0)

	# The mistakes, on a fresh run of the same mission.
	if not await _reach("feedApple"):
		return _die("could not reach feedApple for the wrong-item frame")
	_table.call("tap_item", "banana")
	await _settle(0.5)
	_table.call("begin_drag", "banana")
	_table.call("drag_to_mouth")
	await _settle(0.4)
	_check_state("wrong item", int(_table.call("get_mistakes")) == 1, "one mistake counted")
	_check_state("wrong item", String(_table.call("get_bunny_face")) == "hmph", "Bunny's face is the hmph")
	_check_state("wrong item", String(_table.call("get_credit")) == Rules.CREDIT_HALF, "the task is worth a half star")
	await _shot("feeding_wrong_item")
	await _settle(1.4)
	_table.call("begin_drag", "banana")
	_table.call("drag_to_mouth")
	await _settle(1.7)
	_check_state("guided", bool(_table.call("is_guided")), "guided mode is on")
	await _shot("feeding_guided")
	_table.call("begin_drag", "apple")
	_table.call("drag_to_mouth")
	await _settle(1.5)

	# The summary: a fresh run of the whole mission, every task played -- the
	# feeding ones by their own gesture, findIt / sayIt by touch.
	_room.call("_start_next_mission", MISSION_ID)
	await _settle(0.8)
	_runner = _room.get_node_or_null("MissionRunner")
	var guard: int = 0
	var slipped: bool = false
	while bool(_runner.call("is_running")) and guard < 12:
		guard += 1
		var task: Dictionary = _runner.call("get_current_task")
		if Rules.handles_task(task):
			_table = _room.call("get_feeding_table")
			var target: String = String(task.get("objectId", ""))
			if not slipped:
				# One honest slip on the first feeding task, so the summary shows
				# its "So close!" half star.
				slipped = true
				for other: String in Rules.tray_item_ids(target):
					if other == target:
						continue
					if Rules.needs_peel(other):
						_table.call("tap_item", other)
						await _settle(0.5)
					_table.call("begin_drag", other)
					_table.call("drag_to_mouth")
					await _settle(1.8)
					break
			if Rules.needs_peel(target):
				_table.call("tap_item", target)
				await _settle(0.5)
			_table.call("begin_drag", target)
			_table.call("drag_to_mouth")
			await _settle(Rules.HOLD_SECONDS + 1.6)
		else:
			_runner.call("complete_current_by_touch")
		await _settle(1.9)
	await _settle(0.8)
	var summary: Node = _find_summary()
	_check_state("summary", summary != null and summary.visible, "the session summary is up")
	await _shot("feeding_summary")

	_report()


## Restarts the mission and skips through it until the highchair is showing
## `task_id`. A restart every time, because the picker shuffles the order and a
## task skipped on the way to one frame must still be available for the next.
func _reach(task_id: String) -> bool:
	_room.call("_start_next_mission", MISSION_ID)
	await _settle(0.6)
	_runner = _room.get_node_or_null("MissionRunner")
	if _runner == null:
		return false
	var seen: Array = []
	for _i: int in range(12):
		var task: Dictionary = _runner.call("get_current_task")
		seen.append(String(task.get("taskId", "")))
		if String(task.get("taskId", "")) == task_id:
			await _settle(0.4)
			_table = _room.call("get_feeding_table")
			if _table == null or not bool(_room.call("is_feeding_table_open")):
				_fail.append("%s started but the highchair is not open" % task_id)
				return false
			return true
		if not bool(_runner.call("is_running")):
			print("     reach %s: runner stopped after %s" % [task_id, str(seen)])
			return false
		_runner.call("skip_current_task")
		await _settle(1.3)
	print("     reach %s: gave up after %s" % [task_id, str(seen)])
	return false


func _check_state(label: String, ok: bool, what: String) -> void:
	print("     %s: %s -- %s" % [label, "ok" if ok else "NOT TRUE", what])
	if not ok:
		_fail.append("%s: expected %s" % [label, what])


func _find_summary() -> Node:
	var ui: Node = _room.get_node_or_null("UI")
	if ui == null:
		return null
	for child: Node in ui.get_children():
		if child.has_method("show_summary"):
			return child
	return null


func _shot(out_name: String) -> void:
	var full: String = "%s_%dx%d" % [out_name, _frame.x, _frame.y]
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + full + ".png")
	var err: int = image.save_png(path)
	print("     %s %s.png  %dx%d" % ["shot" if err == OK else "FAIL", full, image.get_width(), image.get_height()])
	if err != OK:
		_fail.append("could not write %s.png" % full)
	if Vector2i(image.get_width(), image.get_height()) != _frame:
		_fail.append("%s.png is %dx%d but %dx%d was asked for"
				% [full, image.get_width(), image.get_height(), _frame.x, _frame.y])
	_shots.append(full)


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _die(message: String) -> void:
	print("FEEDING SHOTS FAIL: %s" % message)
	quit(1)


func _report() -> void:
	print("")
	if _fail.is_empty():
		print("FEEDING SHOTS OK -- %d frame(s) at %dx%d." % [_shots.size(), _frame.x, _frame.y])
		quit(0)
	else:
		print("FEEDING SHOTS FAIL -- %d problem(s):" % _fail.size())
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)
