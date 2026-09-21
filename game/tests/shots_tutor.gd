extends SceneTree

## THE CLASSROOM, PHOTOGRAPHED. Dev-only; nothing in the game references it.
##
##   Godot --path game --script res://tests/shots_tutor.gd -- 1334x750
##   Godot --path game --script res://tests/shots_tutor.gd -- 2340x1080
##
## Writes docs/shots/tutor_<state>_<WxH>.png:
##   classroom_apple  the room, Aliz seated, the apple card on the board
##   listening        the mic indicator live while the child may answer
##   hearing          a partial transcript, the indicator's arc up
##   speaking         Aliz's subtitle while she speaks
##   success          the Great job! banner
##   muted            the Mute toggle on, the indicator saying Muted
##   interrupted      the child barged in: "I'm listening!"
##   after_switch     the barge-in honoured: the banana on the board, its question up
##   exit_confirm     "Stop the lesson?"
##   fallback         no recogniser: Tap to talk and the answer cards
##   break_card       the lesson finished with time left
##   quota_closing    the day's minutes used: the closing card
##
## Hosted in a `SubViewport` of exactly the asked-for size -- `--resolution` is
## a request the window manager clamps. Every write prints the pixel size read
## back off the image and fails the run if it is not the size asked for. The
## lesson is driven through the scene's DEV simulation (the voice session's
## test hook), the same path a recognised utterance takes.

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
	var save: Node = root.get_node_or_null("SaveService")

	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	# -- The hands-free lesson -------------------------------------------------
	_open_scene(true)
	# A shot harness must never spend the child's real minutes.
	if _scene.quota() != null and _scene.quota().has_method("pause_for"):
		_scene.quota().pause_for("shots")
	await _settle(0.8)

	# Welcome -> choose fruits -> the first question, with the apple card.
	await _until_ready(12.0)
	_scene.simulate("correct")
	await _until_ready(20.0)
	_scene.hud().set_banner("")
	await _settle(0.3)
	await _shot("classroom_apple")
	print("     face rect: %s" % str(_scene.face_screen_rect(Vector2(_frame))))

	_scene.hud().set_banner("listening")
	await _settle(0.5)
	await _shot("listening")

	# A partial: the child has started talking.
	_scene.simulate("pause_then_finish")
	await _until_banner("hearing", 4.0)
	await _settle(0.15)
	await _shot("hearing")

	# Speaking with the subtitle: the praise for that answer.
	await _until_state("speaking", 6.0)
	await _settle(0.15)
	await _shot("speaking")
	await _until_state("celebrate", 10.0)
	await _settle(0.1)
	await _shot("success")

	# Muted.
	await _until_ready(20.0)
	_scene.hud().press("mute")
	await _settle(0.3)
	await _shot("muted")
	_scene.hud().press("mute")

	# Interrupted: Aliz repeats the question, the child talks over her.
	_scene.hud().press("repeat")
	await _settle(0.4)
	_scene.simulate("interrupt", "Wait! I want the banana!")
	await _until_banner("interrupted", 4.0)
	await _settle(0.1)
	await _shot("interrupted")
	# ...and the request is honoured: the board and the question move to the
	# banana (QA B1 on a8a2e1f showed the old build staying on the apple).
	await _until_ready(30.0)
	if not String(_scene.board_asset_id()).contains("banana") if _scene.has_method("board_asset_id") else false:
		_fail.append("after 'I want the banana' the board shows %s" % str(_scene.board_asset_id()))
	await _shot("after_switch")

	# Exit confirm.
	await _until_ready(20.0)
	_scene.hud().request_exit()
	await _settle(0.2)
	await _shot("exit_confirm")
	_scene.hud().exit_confirm().press_keep()

	# The break card: finish the lesson with correct answers.
	var guard: int = 0
	while not _scene.is_lesson_complete() and guard < 80:
		guard += 1
		await _until_ready(20.0, true)
		if _scene.state() == "listening":
			_scene.simulate("correct")
	await _until_state("break", 15.0)
	await _settle(0.3)
	await _shot("break_card")

	# -- No recogniser, no simulation: the touch fallback --------------------
	_close_scene()
	_open_scene(false)
	_scene.force_no_recogniser(true)
	if _scene.quota() != null and _scene.quota().has_method("pause_for"):
		_scene.quota().pause_for("shots")
	await _until_state("awaitMic", 15.0)
	await _settle(0.3)
	await _shot("fallback")

	# -- The day's minutes used: Aliz's closing, then the card ---------------
	_close_scene()
	_open_scene(true)
	await _until_ready(12.0)
	if _scene.quota() != null and _scene.quota().has_method("tick"):
		_scene.quota().tick(400.0)
	_scene.simulate("correct")
	await _until_state("break", 30.0)
	await _settle(0.3)
	await _shot("quota_closing")
	_close_scene()

	# Leave the child's profile as we found it.
	if save != null and save.has_method("reload_profile"):
		save.call("reload_profile")
	_report()


func _open_scene(sim: bool) -> void:
	var packed: PackedScene = load("res://scenes/tutor/classroom.tscn")
	if packed == null:
		_die("classroom.tscn will not load")
		return
	_scene = packed.instantiate()
	_scene.ignore_desktop_focus = true  # the window behind the terminal is not a backgrounded phone
	_scene.build()
	# The harness owns the profile: a memory-only save keeps the real one clean.
	_scene.set_save_service(MemorySave.new())
	_scene.enable_simulation(sim)
	if not sim:
		_scene.force_no_recogniser(true)
	_viewport.add_child(_scene)


func _close_scene() -> void:
	if _scene != null:
		_viewport.remove_child(_scene)
		_scene.free()
		_scene = null


class MemorySave extends RefCounted:
	var settings: Dictionary = {}
	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value
	func save_profile() -> bool:
		return true
	func add_stars(_amount: int) -> int:
		return 0
	func get_profile() -> Dictionary:
		return {"settings": settings, "unlockedRooms": []}


func _ready_to_answer() -> bool:
	if _scene.state() != "listening":
		return false
	var session: Object = _scene.voice_session()
	if session != null and session.has_method("is_simulating") and bool(session.call("is_simulating")):
		return false
	return _scene.hud().banner_kind() == "listening"


func _until_ready(seconds: float, or_complete: bool = false) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _ready_to_answer():
			return
		if or_complete and _scene.is_lesson_complete():
			return
		await process_frame
	_fail.append("never ready to answer (at '%s')" % _scene.state())


func _until_state(state: String, seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _scene.state() == state:
			return
		await process_frame
	_fail.append("never reached state '%s' (at '%s')" % [state, _scene.state()])


func _until_banner(kind: String, seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _scene.hud().banner_kind() == kind:
			return
		await process_frame
	_fail.append("never showed banner '%s' (at '%s')" % [kind, _scene.hud().banner_kind()])


func _shot(out_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var file_name: String = "tutor_%s_%dx%d" % [out_name, _frame.x, _frame.y]
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + file_name + ".png")
	var err: int = image.save_png(path)
	print("     %s %s.png  %dx%d  state=%s banner=%s indicator=%s" % [
		"shot" if err == OK else "FAIL", file_name, image.get_width(), image.get_height(),
		_scene.state(), _scene.hud().banner_kind(), _scene.hud().indicator_state()])
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
