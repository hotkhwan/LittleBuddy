extends RefCounted

## The real Parent Corner scene, driven headlessly: it never traps, it has a
## way out in both modes, the sliders reach the mixer and the profile, and the
## language selector agrees with `Localization`.
##
## The Grown-ups freeze of 2026-09-20 is pinned here: a panel pushed as the
## current scene must show a gate card a grown-up can see and pass, and Done
## must not leave them on an empty screen.

const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
const L10n := preload("res://scripts/localization/localization.gd")
const AudioDirectorScript := preload("res://scripts/audio/audio_director.gd")


class FakeSaveService:
	extends Node
	var settings: Dictionary = {}
	var stars: int = 3

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value

	func get_stars() -> int:
		return stars

	func reset_profile() -> void:
		settings.clear()
		stars = 0


func test_name() -> String:
	return "parent_settings_screen"


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	failures.append_array(_test_standalone_mode(tree))
	failures.append_array(_test_overlay_mode(tree))
	failures.append_array(_test_sliders_and_language(tree))
	failures.append_array(_test_slider_db_mapping())
	failures.append_array(_test_selector_matches_localization())
	L10n.set_helper_language(L10n.DEFAULT_HELPER_LANGUAGE)
	return failures


func _instantiate(tree: SceneTree, standalone: bool) -> Control:
	var packed: PackedScene = load(PARENT_SCENE) as PackedScene
	if packed == null:
		return null
	var panel: Control = packed.instantiate() as Control
	if standalone:
		tree.root.add_child(panel)
	else:
		var host := CanvasLayer.new()
		host.name = "FakeHostLayer"
		tree.root.add_child(host)
		host.add_child(panel)
	# `_ready()` does not fire for nodes added under the `--script` runner.
	panel.call("_ready")
	return panel


func _teardown(panel: Node) -> void:
	if panel == null:
		return
	var parent: Node = panel.get_parent()
	if parent != null:
		parent.remove_child(panel)
	panel.free()
	if parent != null and parent.name == "FakeHostLayer":
		parent.get_parent().remove_child(parent)
		parent.free()


## Pushed as the current scene, like the title's Grown-ups button does.
func _test_standalone_mode(tree: SceneTree):
	var failures: Array = []
	var panel: Control = _instantiate(tree, true)
	if panel == null:
		return ["cannot instantiate %s" % PARENT_SCENE]

	if not bool(panel.call("is_standalone")):
		failures.append("a panel added under the root must know it is standalone")
	if not bool(panel.call("is_gate_card_visible")):
		failures.append("standalone: the gate card must be on screen, not an 84 px gear on a bare background")
	if bool(panel.call("is_panel_visible")):
		failures.append("standalone: the settings must still be gated")
	var gear: Control = panel.get_node_or_null("SafeArea/EntryGate") as Control
	if gear != null and gear.visible:
		failures.append("standalone: the corner gear must not compete with the gate card")

	# The hold bar is a real 3 s gate with visible progress.
	var hold: Control = panel.find_child("GateHold", true, false) as Control
	if hold == null:
		failures.append("no GateHold on the gate card")
	else:
		if absf(float(hold.get("hold_duration")) - 3.0) > 0.01:
			failures.append("the gate card hold is %.1f s, expected 3.0" % float(hold.get("hold_duration")))
		var opened: Array = [false]
		panel.connect("opened", func() -> void: opened[0] = true)
		hold.call("begin_hold")
		hold.call("advance", 1.5)
		if absf(float(hold.call("get_progress")) - 0.5) > 0.05:
			failures.append("half-way through the hold the progress is %.2f" % float(hold.call("get_progress")))
		if opened[0]:
			failures.append("the panel opened before the hold completed")
		hold.call("advance", 1.6)
		if not opened[0]:
			failures.append("a completed 3 s hold did not open the settings")
		if not bool(panel.call("is_panel_visible")) or bool(panel.call("is_gate_card_visible")):
			failures.append("after the hold the panel must show and the gate card must hide")

	# Close puts the gate card back (and, in the real game, goes home; the
	# scripted runner owns navigation so nothing changes scene here).
	var closed: Array = [0]
	panel.connect("closed", func() -> void: closed[0] += 1)
	var close_button: Button = panel.find_child("CloseButton", true, false) as Button
	if close_button == null:
		failures.append("no CloseButton in the header")
	else:
		close_button.pressed.emit()
	if closed[0] != 1:
		failures.append("Close emitted closed() %d time(s), expected 1" % closed[0])
	if bool(panel.call("is_panel_visible")):
		failures.append("the panel is still showing after Close")
	if not bool(panel.call("is_gate_card_visible")):
		failures.append("standalone: after Close the gate card must be back, never an empty screen")
	if tree.current_scene == panel:
		failures.append("the scripted runner must not have its current scene swapped by the panel")

	# The gate card's Back is a way out without opening anything.
	var back_requested: Array = [0]
	panel.connect("back_requested", func() -> void: back_requested[0] += 1)
	var back: Button = panel.find_child("GateBackButton", true, false) as Button
	if back == null:
		failures.append("no GateBackButton on the gate card")
	else:
		back.pressed.emit()
		if back_requested[0] != 1:
			failures.append("Back on the gate card did not request to leave")

	# Done also closes.
	panel.call("open_settings")
	var done: Button = panel.find_child("DoneButton", true, false) as Button
	if done == null:
		failures.append("no DoneButton")
	else:
		done.pressed.emit()
		if closed[0] != 2 or bool(panel.call("is_panel_visible")):
			failures.append("Done did not close the panel")

	_teardown(panel)
	return failures


## Hosted under a CanvasLayer, the way the pause card and the Baby Room do it.
func _test_overlay_mode(tree: SceneTree):
	var failures: Array = []
	var panel: Control = _instantiate(tree, false)
	if panel == null:
		return ["cannot instantiate %s" % PARENT_SCENE]
	if bool(panel.call("is_standalone")):
		failures.append("a panel under a CanvasLayer is an overlay, not standalone")
	if bool(panel.call("is_gate_card_visible")):
		failures.append("overlay: the full gate card must not cover the running room")
	var gear: Control = panel.get_node_or_null("SafeArea/EntryGate") as Control
	if gear == null or not gear.visible:
		failures.append("overlay: the corner gear is the entry point and must be visible")
	var backdrop: Control = panel.find_child("Backdrop", true, false) as Control
	if backdrop != null and backdrop.visible:
		failures.append("overlay: the backdrop must not cover the room while locked")
	# Gear hold opens it; Done closes it and hands the room back.
	gear.call("begin_hold")
	gear.call("advance", 3.1)
	if not bool(panel.call("is_panel_visible")):
		failures.append("overlay: the gear hold did not open the settings")
	var closed: Array = [0]
	panel.connect("closed", func() -> void: closed[0] += 1)
	panel.call("close_settings")
	if closed[0] != 1 or bool(panel.call("is_panel_visible")):
		failures.append("overlay: close_settings() must emit closed() once and hide the panel")
	if gear == null or not gear.visible:
		failures.append("overlay: the gear must come back after closing")
	_teardown(panel)
	return failures


func _test_sliders_and_language(tree: SceneTree):
	var failures: Array = []
	var save := FakeSaveService.new()
	save.name = "SaveService"
	tree.root.add_child(save)
	var audio: Node = AudioDirectorScript.new()
	audio.name = "Audio"
	audio.set("warn_on_licence_refusal", false)
	tree.root.add_child(audio)

	var panel: Control = _instantiate(tree, false)
	if panel == null:
		failures.append("cannot instantiate %s" % PARENT_SCENE)
	else:
		panel.call("open_settings")
		var music: HSlider = panel.find_child("MusicSlider", true, false) as HSlider
		var voice: HSlider = panel.find_child("VoiceVolumeSlider", true, false) as HSlider
		if music == null or voice == null:
			failures.append("the sliders are missing")
		else:
			if absf(music.value - 1.0) > 0.001:
				failures.append("music slider should start at 1.0 (manifest level), got %.2f" % music.value)
			if absf(voice.value - 0.85) > 0.001:
				failures.append("voice slider should start at 0.85 (today's TTS volume), got %.2f" % voice.value)
			_drag(music, 0.5)
			var db: float = float(audio.call("get_music_volume_db"))
			if absf(db - linear_to_db(0.5)) > 0.05:
				failures.append("music 0.5 should set the trim to %.2f dB, got %.2f" % [linear_to_db(0.5), db])
			if absf(float(save.settings.get("musicVolume", -1.0)) - 0.5) > 0.001:
				failures.append("musicVolume 0.5 was not persisted: %s" % str(save.settings))
			_drag(music, 0.0)
			if float(audio.call("get_music_volume_db")) > AudioDirectorScript.SLIDER_MUTE_DB:
				failures.append("music slider at 0 must be a mute, got %.1f dB" % float(audio.call("get_music_volume_db")))
			_drag(voice, 0.4)
			if absf(float(save.settings.get("voiceVolume", -1.0)) - 0.4) > 0.001:
				failures.append("voiceVolume 0.4 was not persisted: %s" % str(save.settings))
			var value_label: Label = panel.find_child("VoiceVolumeValue", true, false) as Label
			if value_label != null and value_label.text != "40%":
				failures.append("the voice value label reads '%s', expected 40%%" % value_label.text)

		# Language selector: a tap persists, keeps thaiHints in step and applies now.
		var ja: Button = panel.find_child("HelperJaButton", true, false) as Button
		var off: Button = panel.find_child("HelperOffButton", true, false) as Button
		if ja == null or off == null:
			failures.append("helper language buttons are missing")
		else:
			ja.pressed.emit()
			if save.settings.get("helperLanguage") != "ja" or save.settings.get("thaiHints") != true:
				failures.append("choosing Japanese must persist helperLanguage=ja and keep thaiHints=true: %s" % str(save.settings))
			if L10n.helper_language() != "ja":
				failures.append("choosing a language must apply to Localization immediately")
			var helper_label: Label = panel.find_child("MusicHelper", true, false) as Label
			if helper_label == null or not helper_label.visible or helper_label.text != "音楽の音量":
				failures.append("the row helper line did not switch to Japanese: %s"
						% (helper_label.text if helper_label != null else "no label"))
			off.pressed.emit()
			if save.settings.get("helperLanguage") != "off" or save.settings.get("thaiHints") != false:
				failures.append("Off must persist helperLanguage=off AND thaiHints=false: %s" % str(save.settings))
			if helper_label != null and helper_label.visible:
				failures.append("the row helper line must hide when the helper is off")
			# Reopening reads the profile back.
			var ar: Button = panel.find_child("HelperArButton", true, false) as Button
			ar.pressed.emit()
			panel.call("close_settings")
			panel.call("open_settings")
			if not ar.button_pressed:
				failures.append("reopening must show the persisted language selected")
			if helper_label != null and helper_label.text_direction != Control.TEXT_DIRECTION_RTL:
				failures.append("Arabic row helpers must be laid out right-to-left")
		_teardown(panel)

	tree.root.remove_child(audio)
	audio.free()
	tree.root.remove_child(save)
	save.free()
	return failures


## A finger on the slider: the value moves and `value_changed` fires. Set
## programmatically outside a running tree, `Range` does not emit on its own.
static func _drag(slider: HSlider, value: float) -> void:
	slider.set_value_no_signal(value)
	slider.value_changed.emit(value)


func _test_slider_db_mapping():
	var failures: Array = []
	if AudioDirectorScript.slider_to_db(1.0) != 0.0:
		failures.append("slider 1.0 must be 0 dB trim, got %.2f" % AudioDirectorScript.slider_to_db(1.0))
	if AudioDirectorScript.slider_to_db(0.0) != AudioDirectorScript.MIN_TRIM_DB:
		failures.append("slider 0 must be the mute trim")
	if AudioDirectorScript.slider_to_db(0.005) != AudioDirectorScript.MIN_TRIM_DB:
		failures.append("anything at or under the -40 dB floor must be a mute")
	var half: float = AudioDirectorScript.slider_to_db(0.5)
	if absf(half - linear_to_db(0.5)) > 0.01:
		failures.append("slider 0.5 -> %.2f dB, expected linear_to_db(0.5)" % half)
	for value: float in [0.1, 0.25, 0.5, 0.8, 1.0]:
		var back: float = AudioDirectorScript.db_to_slider(AudioDirectorScript.slider_to_db(value))
		if absf(back - value) > 0.01:
			failures.append("slider %.2f does not round-trip through dB (got %.3f)" % [value, back])
	if AudioDirectorScript.db_to_slider(AudioDirectorScript.MIN_TRIM_DB) != 0.0:
		failures.append("the mute trim must read back as slider 0")
	return failures


func _test_selector_matches_localization():
	var failures: Array = []
	var script: GDScript = load("res://scenes/parent/parent_settings.gd")
	var mapping: Dictionary = script.HELPER_BUTTONS
	var codes: Array = mapping.values()
	if not codes.has("off"):
		failures.append("the selector has no Off")
	for row: Dictionary in L10n.available_languages():
		if not codes.has(String(row["code"])):
			failures.append("Localization offers %s but the selector has no button for it" % row["code"])
	for code: Variant in codes:
		if String(code) != "off" and not L10n.is_supported(String(code)):
			failures.append("the selector offers %s, which Localization does not support" % str(code))
	# Every button shows the language's own name, in its own script.
	var packed: PackedScene = load(PARENT_SCENE) as PackedScene
	var panel: Node = packed.instantiate()
	for node_name: String in mapping.keys():
		var button: Button = panel.find_child(node_name, true, false) as Button
		if button == null:
			failures.append("%s is not in the scene" % node_name)
			continue
		var code: String = String(mapping[node_name])
		if code != "off" and button.text != L10n.native_name(code):
			failures.append("%s reads '%s', expected the native name '%s'" % [node_name, button.text, L10n.native_name(code)])
	panel.free()
	return failures
