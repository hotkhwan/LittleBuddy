extends "res://tests/shots_classroom_v3.gd"

## Identical deterministic lesson states at both requested screenshot sizes.
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var phase: String = args[0] if args.size() else "after"
	for frame: Vector2i in [Vector2i(1334, 750), Vector2i(2340, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = frame
		viewport.size_2d_override = Vector2i(int(round(float(frame.x) * 1024.0 / frame.y)), 1024)
		viewport.size_2d_override_stretch = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var scene: Node = load("res://scenes/tutor/classroom.tscn").instantiate()
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
		if scene.board_asset_id() != "apple_red":
			_failures.append("Screenshot failed to reach apple lesson")
		await create_timer(0.3).timeout
		scene.hud().set_banner("")
		await _shot(viewport, phase, "classroom", frame)
		scene.hud().show_answer_cards(["apple_red", "banana_yellow", "orange_orange"])
		scene.hud().set_banner("info", "What is this?")
		await _shot(viewport, phase, "answers", frame)
		scene.hud().hide_answer_cards()
		for state: String in ["listening", "thinking", "success"]:
			scene.hud().set_banner(state)
			await _shot(viewport, phase, "classroom_" + state, frame)
		scene.hud().set_subtitle("มาเรียนรู้ด้วยกันนะ หนูเห็นผลไม้อะไรบ้าง")
		await _shot(viewport, phase, "classroom_thai", frame)
		scene.hud().set_subtitle("")
		scene.hud().set_indicator("aliz", 0)
		scene.hud().set_banner("info", "Let's learn together!")
		await _shot(viewport, phase, "classroom_speaking", frame)
		_check_touch_margins(viewport, scene.hud())
		viewport.queue_free()
		await process_frame
	for failure: String in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _shot(viewport: SubViewport, phase: String, state: String, frame: Vector2i) -> void:
	await process_frame
	RenderingServer.force_draw(true, 0.0)
	var capture := viewport.get_texture().get_image()
	if capture == null or capture.is_empty() or capture.get_size() != frame:
		_failures.append("Invalid classroom capture: " + state)
		return
	var path := "res://../docs/shots/night/%s_%s_%dx%d.png" % [phase, state, frame.x, frame.y]
	if capture.save_png(ProjectSettings.globalize_path(path)) != OK:
		_failures.append("Cannot save " + path)
	print("Night classroom: " + path)
