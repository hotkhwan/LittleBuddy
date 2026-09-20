extends SceneTree

## SETTINGS / LOCALISATION / SPEECH END-STATE EVIDENCE, at the pixel size it
## claims. Dev-only.
##
##   Godot --path game --script res://tests/shots_settings.gd -- ipad 1334x750
##   Godot --path game --script res://tests/shots_settings.gd -- iphone 2340x1080
##
## Writes, into docs/shots/:
##   settings_<prefix>            the grown-ups panel open: sliders, language selector, Close + Done
##   settings_gate_<prefix>       the standalone gate card (what the title's Grown-ups button opens)
##   house_helper_th_<prefix>     the real house, Mission 01 prompt, Thai helper line
##   house_helper_ja_<prefix>     ... Japanese helper line
##   house_helper_ar_<prefix>     ... Arabic helper line (RTL)
##   speech_listening_<prefix>    the speech panel listening, Speak held
##   speech_success_<prefix>      SUCCESS ("Great!")
##   speech_retry_<prefix>        RETRY ("Try again!")
##   speech_unavailable_<prefix>  UNAVAILABLE ("Voice is not ready")
##
## Same SubViewport / `size_2d_override` discipline as shots_menu.gd, so the UI
## is laid out in the 1024-tall design space the device uses. Every PNG's size
## is asserted. The real SaveService is used for the house (the director reads
## the profile); only `helperLanguage`/`thaiHints` are touched and both are put
## back afterwards.

const OUT_DIR: String = "docs/shots/"
const DESIGN_HEIGHT: int = 1024
const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const Feedback := preload("res://scripts/ui/speech_feedback.gd")
const L10n := preload("res://scripts/localization/localization.gd")

var _prefix: String = "ipad"
var _frame: Vector2i = Vector2i(1334, 750)
var _viewport: SubViewport = null
var _fail: Array = []
var _saved_language: Variant = null
var _saved_thai: Variant = null


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = String(args[0]).strip_edges()
	if args.size() > 1:
		var wide: PackedStringArray = String(args[1]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))
	print("=== settings / l10n / speech evidence, %dx%d -> %s*_%s.png ===" % [_frame.x, _frame.y, OUT_DIR, _prefix])
	await process_frame

	var save: Node = root.get_node_or_null("SaveService")
	if save != null and save.has_method("get_setting"):
		_saved_language = save.call("get_setting", "helperLanguage", null)
		_saved_thai = save.call("get_setting", "thaiHints", null)

	_viewport = SubViewport.new()
	_viewport.size = _frame
	var design_width: int = int(round(float(_frame.x) * float(DESIGN_HEIGHT) / float(_frame.y)))
	_viewport.size_2d_override = Vector2i(design_width, DESIGN_HEIGHT)
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	await _settings_frames(save)
	await _house_frames(save)

	# Put the profile back exactly as found.
	if save != null and save.has_method("set_setting"):
		if _saved_language == null:
			save.call("set_setting", "helperLanguage", "th")
		else:
			save.call("set_setting", "helperLanguage", _saved_language)
		save.call("set_setting", "thaiHints", true if _saved_thai == null else _saved_thai)

	if _fail.is_empty():
		print("\nSETTINGS SHOTS OK")
		quit(0)
	else:
		print("\nSETTINGS SHOTS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


func _set_language(save: Node, code: String) -> void:
	if save != null and save.has_method("set_setting"):
		save.call("set_setting", "helperLanguage", code)
		save.call("set_setting", "thaiHints", code != "off")
	L10n.set_helper_language(code)


func _settings_frames(save: Node) -> void:
	_set_language(save, "th")
	var panel: Control = (load(PARENT_SCENE) as PackedScene).instantiate()
	_viewport.add_child(panel)
	await _settle(0.3)

	# The standalone gate card, as the title's Grown-ups button shows it.
	panel.call("set_standalone", true)
	await _settle(0.3)
	if not bool(panel.call("is_gate_card_visible")):
		_fail.append("settings_gate: the gate card is not showing")
	await _shot("settings_gate_%s" % _prefix)

	# The panel itself, half-way through a hold would be nice but a still cannot
	# show it; open it and photograph the controls.
	panel.call("open_settings")
	await _settle(0.4)
	for node_name: String in ["MusicSlider", "VoiceVolumeSlider", "HelperJaButton", "HelperArButton", "CloseButton", "DoneButton"]:
		var node: Control = panel.find_child(node_name, true, false) as Control
		if node == null or not node.is_visible_in_tree():
			_fail.append("settings: %s is not visible" % node_name)
	await _shot("settings_%s" % _prefix)
	# Scrolled to the bottom: Done must be reachable.
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 100000
		await _settle(0.3)
		var done: Control = panel.find_child("DoneButton", true, false) as Control
		if done != null:
			var rect: Rect2 = done.get_global_rect()
			var visible_h: float = float(_viewport.size_2d_override.y)
			if rect.position.y < 0.0 or rect.end.y > visible_h:
				_fail.append("settings: after scrolling to the bottom Done is at %s, outside the %d-tall frame" % [str(rect), int(visible_h)])
		await _shot("settings_bottom_%s" % _prefix)

	_viewport.remove_child(panel)
	panel.free()


func _house_frames(save: Node) -> void:
	var world: Node = (load(HOUSE_SCENE) as PackedScene).instantiate()
	_viewport.add_child(world)
	await _settle(0.8)
	var director: Node = world.call("ensure_level_director")
	if director == null:
		_fail.append("house: no level director")
		return
	director.call("start")
	await _settle(1.2)
	var hud: Control = director.call("get_hud")
	if hud == null:
		_fail.append("house: no HUD")
		return
	if director.has_method("_quieten_nudge"):
		director.call("_quieten_nudge")
	var tts: Node = root.get_node_or_null("TtsService")
	if tts != null and tts.has_method("stop"):
		tts.call("stop")

	var prompt: String = String(hud.call("get_prompt"))
	print("  prompt on screen: '%s'" % prompt)
	for code: String in ["th", "ja", "ar"]:
		_set_language(save, code)
		hud.call("refresh_helper_language")
		await _settle(0.3)
		var hint: Label = hud.find_child("ThaiHint", true, false) as Label
		if hint == null or not hint.visible or hint.text.is_empty():
			_fail.append("house_helper_%s: the helper line is not showing under '%s'" % [code, prompt])
		else:
			print("  %s helper: '%s' (rtl=%s)" % [code, hint.text, str(hint.text_direction == Control.TEXT_DIRECTION_RTL)])
			if code == "ar" and hint.text_direction != Control.TEXT_DIRECTION_RTL:
				_fail.append("house_helper_ar: the label is not right-to-left")
		await _shot("house_helper_%s_%s" % [code, _prefix])
	_set_language(save, "th")
	hud.call("refresh_helper_language")

	# The speech panel in every state the child can end on.
	var panel: Control = hud.call("get_speech_feedback")
	if panel == null:
		_fail.append("speech: the HUD has no speech panel")
	else:
		hud.call("set_speak_visible", true)
		var speak: Button = hud.find_child("SpeakButton", true, false) as Button
		panel.call("set_state", Feedback.State.LISTENING, "mil")
		if speak != null:
			speak.disabled = true
		await _settle(0.3)
		await _shot("speech_listening_%s" % _prefix)
		if speak != null:
			speak.disabled = false
		var faces: Dictionary = {
			"success": [Feedback.State.MATCHED, "milk"],
			"retry": [Feedback.State.NOT_UNDERSTOOD, "banana"],
			"unavailable": [Feedback.State.UNAVAILABLE, ""],
		}
		for face: String in faces.keys():
			panel.call("set_state", faces[face][0], faces[face][1])
			await _settle(0.3)
			var got: String = Feedback.terminal_class(int(panel.call("get_state")))
			if got != face:
				_fail.append("speech_%s: the panel is in the '%s' face" % [face, got])
			print("  speech %s: '%s' / '%s'" % [face, panel.call("get_title_text"), panel.call("get_detail_text")])
			await _shot("speech_%s_%s" % [face, _prefix])
		panel.call("set_state", Feedback.State.IDLE)

	_viewport.remove_child(world)
	world.free()


func _shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw(true, 0.0)
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
