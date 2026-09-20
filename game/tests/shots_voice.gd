extends SceneTree
## Photographs the voice pack's subtitle strip where it is mounted: the house
## (Story HUD, mid-mission) and the highchair, at 1334x750 (iPad landscape).
##
##   Godot --headless --path game --script res://tests/shots_voice.gd [WxH]
##
## A `VoiceDirector` is parked at `/root/Voice` (the lead's autoload, simulated
## when it is not registered yet) and a recorded-or-fallback line is said, so
## what is photographed is the real strip reacting to the real signal -- not a
## label set by hand. Every line still falls back to the device voice here
## (0 of 36 recordings exist); the strip does not care which.
##
## Writes docs/shots/voice_subtitle_house.png and voice_subtitle_feeding.png.

const OUT_DIR: String = "docs/shots/"
const DirectorScript := preload("res://scripts/voice/voice_director.gd")

var _frame: Vector2i = Vector2i(1334, 750)
var _viewport: SubViewport = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		var wide: PackedStringArray = String(args[0]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))
	print("=== voice subtitle strip, %dx%d ===" % [_frame.x, _frame.y])
	await process_frame
	var save: Node = root.get_node_or_null("SaveService")
	if save != null and save.has_method("reset_profile"):
		save.call("reset_profile")

	var voice: Node = root.get_node_or_null("Voice")
	if voice == null:
		voice = DirectorScript.new()
		voice.name = "Voice"
		root.add_child(voice)
		print("  Voice autoload not registered; parked a director at /root/Voice for the shot")
	print("  %s" % String(voice.call("presence_summary")))

	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	# -- The house, Story mode, first beat ---------------------------------------
	var world: Node = load("res://scenes/house/house_world.tscn").instantiate()
	_viewport.add_child(world)
	await _settle(0.8)
	var director: Node = world.call("ensure_level_director")
	director.call("start")
	await _settle(1.2)
	var hud: Control = director.call("get_hud")
	var strip: Control = hud.call("get_subtitle_strip") if hud != null and hud.has_method("get_subtitle_strip") else null
	if strip == null:
		_fail.append("the house HUD has no subtitle strip")
	else:
		voice.call("stop")
		voice.call("say", "aliz_014_milk_time", {"interrupt": true})
		await _settle(0.2)
		# The mission keeps talking ("Go to Bunny.") and may cut this line within
		# the settle; the pill lingers, and that is what is photographed.
		_check(bool(strip.call("is_pill_visible")), "house: the strip is up while Aliz speaks")
		_check(String(strip.call("get_text")) == "Let's make some milk!",
				"house: the strip shows the line's English (got '%s')" % strip.call("get_text"))
		_check_clear(hud, strip)
		await _shot("voice_subtitle_house")
	world.queue_free()
	await _settle(0.3)

	# -- The highchair --------------------------------------------------------------
	var room: Node = load("res://scenes/baby_room/baby_room.tscn").instantiate()
	_viewport.add_child(room)
	await _settle(0.8)
	room.call("_start_next_mission", "feedingTime")
	await _settle(0.6)
	var runner: Node = room.get_node_or_null("MissionRunner")
	var table: Node3D = null
	for _i: int in range(12):
		if runner == null:
			break
		var task: Dictionary = runner.call("get_current_task")
		if String(task.get("taskId", "")) == "feedApple":
			await _settle(0.4)
			table = room.call("get_feeding_table")
			break
		if not bool(runner.call("is_running")):
			break
		runner.call("skip_current_task")
		await _settle(1.3)
	if table == null:
		_fail.append("could not reach the highchair's apple task")
	else:
		var feeding_hud: Node = table.call("get_hud")
		var feeding_strip: Control = feeding_hud.call("get_subtitle_strip") if feeding_hud.has_method("get_subtitle_strip") else null
		if feeding_strip == null:
			_fail.append("the feeding HUD has no subtitle strip")
		else:
			# A wrong item: Bunny's Hmph! (and the hmph face), then Aliz.
			table.call("tap_item", "banana")
			await _settle(0.5)
			table.call("begin_drag", "banana")
			table.call("drag_to_mouth")
			await _settle(0.3)
			_check(String(table.call("get_bunny_face")) == "hmph", "feeding: the wrong item brings the hmph face (got '%s')" % table.call("get_bunny_face"))
			_check(bool(feeding_strip.call("is_pill_visible")), "feeding: the strip is up after the wrong item")
			print("  feeding strip: '%s'" % String(feeding_strip.call("get_text")))
			await _shot("voice_subtitle_feeding")
	_finish()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		print("  FAIL %s" % what)
		_fail.append(what)


## The pill must not touch Next, Speak, Home or the thumbstick's rest ring.
func _check_clear(hud: Control, strip: Control) -> void:
	var view: Vector2 = Vector2(_frame)
	var pill: Rect2 = hud.call("subtitle_rect", view)
	var buttons: Dictionary = hud.call("button_rects", view)
	for key: String in buttons.keys():
		_check(not pill.intersects(buttons[key]), "house: the strip clears %s %s" % [key, str(buttons[key])])
	_check(not pill.intersects(hud.call("home_button_rect", view)), "house: the strip clears Home")
	_check(pill.position.x >= 280.0, "house: the strip clears the thumbstick's rest ring (x=%.0f)" % pill.position.x)


func _shot(out_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + out_name + ".png")
	var err: int = image.save_png(path)
	print("  %s %s.png  %d x %d" % ["shot" if err == OK else "FAIL", out_name, image.get_width(), image.get_height()])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _finish() -> void:
	if _fail.is_empty():
		print("\nVOICE SHOTS PASS")
		quit(0)
	else:
		print("\nVOICE SHOTS FAIL:")
		for line: Variant in _fail:
			print("  - %s" % String(line))
		quit(1)
