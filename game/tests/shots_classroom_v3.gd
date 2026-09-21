extends SceneTree

## Deterministic production comparison; simulation and an in-memory profile only.
const ShotBase := preload("res://tests/shots_tutor.gd")
var _failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var phase: String = args[0] if args.size() else "after"
	for frame: Vector2i in [Vector2i(1334, 750), Vector2i(2340, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = frame
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var packed: PackedScene = load("res://scenes/tutor/classroom.tscn")
		if packed == null:
			push_error("Classroom scene failed to load")
			quit(1)
			return
		var scene: Node = packed.instantiate()
		scene.ignore_desktop_focus = true
		scene.build()
		scene.set_save_service(ShotBase.MemorySave.new())
		scene.enable_simulation(true)
		viewport.add_child(scene)
		scene.set_process(false)
		scene.quota().pause_for("shots")
		for turn: int in range(2):
			for step: int in range(1000):
				scene.advance(0.1)
				if scene.state() == "listening" and scene.hud().banner_kind() == "listening" and not scene.voice_session().is_simulating() and (turn == 0 or not scene.is_choosing_subject()):
					break
			if turn == 0:
				scene.simulate("correct")
		if scene.state() != "listening" or scene.is_choosing_subject() or scene.board_asset_id() != "apple_red":
			push_error("Screenshot setup did not reach the listening apple lesson: %s / %s" % [scene.state(), scene.board_asset_id()])
			quit(1)
			return
		scene.hud().set_banner("")
		await create_timer(0.3).timeout
		await _shot(viewport, phase, "classroom", frame)
		scene.hud().show_answer_cards(["apple_red", "banana_yellow", "orange_orange"])
		scene.hud().set_banner("info", "What is this?")
		await _shot(viewport, phase, "answers", frame)
		if phase == "after":
			scene.hud().hide_answer_cards()
			scene.hud().set_subtitle("มาเรียนรู้ด้วยกันนะ หนูเห็นผลไม้อะไรบ้าง")
			await _shot(viewport, phase, "classroom_thai", frame)
			scene.hud().set_subtitle("")
			scene.hud().set_banner("success")
			await _shot(viewport, phase, "classroom_reward", frame)
			_check_touch_margins(viewport, scene.hud())
		viewport.queue_free()
		await process_frame
	for failure: String in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _shot(viewport: SubViewport, phase: String, state: String, frame: Vector2i) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var texture := viewport.get_texture()
	if texture == null:
		_failures.append("No classroom viewport texture")
		return
	var capture := texture.get_image()
	if capture == null or capture.is_empty() or capture.get_size() != frame:
		_failures.append("Classroom capture is absent or has incorrect dimensions")
		return
	var path := "res://../docs/shots/v3_%s_%s_%dx%d.png" % [phase, state, frame.x, frame.y]
	var result := capture.save_png(ProjectSettings.globalize_path(path))
	if result != OK:
		_failures.append("Cannot save %s: %s" % [path, error_string(result)])
		return
	print("V3 classroom screenshot: %s (%s)" % [path, error_string(result)])

func _check_touch_margins(viewport: SubViewport, source_hud: Control) -> void:
	# Isolate input routing from lesson callbacks so probing Replay cannot
	# start speech or change the next comparison's simulated lesson.
	var layer := CanvasLayer.new()
	layer.layer = 100
	viewport.add_child(layer)
	var hud: Control = source_hud.get_script().new()
	layer.add_child(hud)
	var observed: Array[String] = []
	hud.set_card("apple_red")
	hud.set_tap_to_talk_visible(true)
	hud.set_tap_to_talk_enabled(true)
	for key: String in ["repeat", "card", "mute", "tapToTalk"]:
		if key == "tapToTalk":
			hud.set_tap_to_talk_visible(true)
			hud.set_tap_to_talk_enabled(true)
		var button: Button = hud.buttons()[key]
		button.pressed.connect(func() -> void: observed.append(key), CONNECT_ONE_SHOT)
		var margin: float = (float(button.get("touch_size")) - button.size.x) * 0.5
		var point := button.get_global_transform_with_canvas() * Vector2(-margin * 0.5, button.size.y * 0.5)
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			viewport.push_input(event, true)
		if not observed.has(key):
			_failures.append("%s transparent touch margin failed viewport input routing" % key)
	print("Classroom expanded touch routing: %s" % str(observed))
	layer.free()
