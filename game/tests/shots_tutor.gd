extends SceneTree

## THE CLASSROOM, PHOTOGRAPHED. Dev-only; nothing in the game references it.
##
##   Godot --path game --script res://tests/shots_tutor.gd -- 1334x750
##   Godot --path game --script res://tests/shots_tutor.gd -- 2340x1080
##
## Writes docs/shots/tutor_<state>_<WxH>.png for: the classroom with Aliz
## seated and the apple card on the board; Listening (mic ring); Speaking (the
## subtitle strip); the Success banner; the break card; the exit confirm.
##
## Hosted in a `SubViewport` of exactly the asked-for size -- `--resolution` is
## a request the window manager clamps, and a clamped run photographs one
## composition and files it as another. Every write prints the pixel size read
## back off the image and fails the run if it is not the size asked for. The
## whole lesson is driven through the scene's DEV simulation, which is the
## same path a recognised phrase takes; nothing here reaches into the scene's
## private state.

const OUT_DIR: String = "docs/shots/"

var _frame: Vector2i = Vector2i(1334, 750)
var _viewport: SubViewport = null
var _scene: Node = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		var wide: PackedStringArray = String(args[0]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))
	print("=== tutor classroom shots, %dx%d ===" % [_frame.x, _frame.y])
	await process_frame

	var packed: PackedScene = load("res://scenes/tutor/classroom.tscn")
	if packed == null:
		return _die("classroom.tscn will not load")
	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_scene = packed.instantiate()
	_viewport.add_child(_scene)
	await _settle(0.8)
	_scene.enable_simulation(true)

	# 1. The room, Aliz seated, the apple card on the board. The opening teach
	#    line is spoken here; the caption is cleared so the room reads alone.
	_scene.hud().set_subtitle("")
	_scene.hud().set_banner("")
	await _settle(0.3)
	await _shot("classroom_apple")
	print("     face rect: %s" % str(_scene.face_screen_rect(Vector2(_frame))))

	# 2. Listening: run the lesson forward until the mic opens.
	await _until("listening", 12.0)
	await _settle(0.35)
	await _shot("listening")

	# 3. Speaking with the subtitle: a correct answer's praise.
	_scene.simulate("correct")
	await _until("speaking", 4.0)
	await _settle(0.15)
	await _shot("speaking")

	# 4. The success banner.
	await _until("celebrate", 8.0)
	await _settle(0.1)
	await _shot("success")

	# 5. The exit confirm.
	await _until("listening", 12.0)
	_scene.hud().request_exit()
	await _settle(0.2)
	await _shot("exit_confirm")
	_scene.hud().exit_confirm().press_keep()
	await _settle(0.2)

	# 6. The break card: finish the lesson with correct answers.
	var guard: int = 0
	while not _scene.is_lesson_complete() and guard < 40:
		guard += 1
		await _until("listening", 12.0, true)
		if _scene.state() == "listening":
			_scene.simulate("correct")
	await _settle(0.3)
	await _shot("break_card")

	_report()


func _until(state: String, seconds: float, or_complete: bool = false) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _scene.state() == state:
			return
		if or_complete and _scene.is_lesson_complete():
			return
		await process_frame
	_fail.append("never reached state '%s' (at '%s')" % [state, _scene.state()])


func _shot(out_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var file_name: String = "tutor_%s_%dx%d" % [out_name, _frame.x, _frame.y]
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + file_name + ".png")
	var err: int = image.save_png(path)
	print("     %s %s.png  %dx%d  state=%s" % [
		"shot" if err == OK else "FAIL", file_name, image.get_width(), image.get_height(), _scene.state()])
	if err != OK:
		_fail.append("could not write %s.png" % file_name)
	if Vector2i(image.get_width(), image.get_height()) != _frame:
		_fail.append("%s.png is %dx%d but %dx%d was asked for"
			% [file_name, image.get_width(), image.get_height(), _frame.x, _frame.y])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _die(message: String) -> void:
	print("TUTOR SHOTS FAIL: %s" % message)
	quit(1)


func _report() -> void:
	print("")
	if _fail.is_empty():
		print("TUTOR SHOTS PASS")
		quit(0)
	else:
		print("TUTOR SHOTS FAIL")
		for f in _fail:
			print("  - %s" % str(f))
		quit(1)
