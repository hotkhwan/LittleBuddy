extends SceneTree

## REAL INPUT through a viewport, for the grown-ups panel. Dev/test only.
##
##   Godot --headless --path game --script res://tests/input_settings_harness.gd
##
## Prints `INPUT SETTINGS OK` and exits 0, or lists every failure and exits 1.
## `test_parent_settings_screen.gd` runs it as a child process: the suite's cases
## run inside `_initialize()`, before the root is in the tree, where no layout
## happens and no GUI input can be delivered, so "a finger on a slider scrolls
## the panel" cannot be shown there. Here the panel is laid out in a SubViewport
## at the device's design size (1024 tall, the same `size_2d_override` discipline
## as `shots_settings.gd`) and driven with `Viewport.push_input`.
##
## Every touch is pushed the way `emulate_mouse_from_touch=true` delivers it on
## the iPad: the emulated mouse event first, then the touch itself, both at the
## same position. A SECOND finger arrives as a bare `InputEventScreenTouch` /
## `InputEventScreenDrag` with its own index and no mouse event at all, which is
## exactly what `Input` does while another finger is already the mouse. Nothing
## here is a claim about a physical device.
##
## Every scenario prints one `PROBE <name>: PASS|FAIL` line, so a verification
## checklist (`docs/SETTINGS_VERIFICATION.md`) can cite the exact probe.
##
## Owner playtest bug, 2026-09-21: "Settings opens, but the contents cannot
## scroll; the last option cannot be reached." and "the Baby Room gear: a tap
## does nothing." Independent QA after the fix: "a second finger can press an
## option while the first scrolls." Each scenario below is one of those, one of
## the fixes' side conditions, or one row of the settings verification list
## (close / back / home / volumes / language / tutor toggles / privacy / erase).
##
## Persistence is proven against the REAL `SaveService` + `ProfileStore`, pointed
## at a scratch file under user:// that is deleted afterwards; the project's own
## autoloads are detached for the whole run so no real profile is ever touched.

const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
const HOUSE_HUD_SCRIPT: String = "res://scripts/gameplay/house_hud.gd"
const SAVE_SERVICE_SCRIPT: String = "res://scripts/save/save_service.gd"
const TTS_SERVICE_SCRIPT: String = "res://scripts/speech/tts_service.gd"
const VOICE_DIRECTOR_SCRIPT: String = "res://scripts/voice/voice_director.gd"
const TUTOR_SCENE_SCRIPT: String = "res://scripts/tutor/tutor_scene.gd"
const MAIN_MENU_SCRIPT: String = "res://scenes/main/main.gd"
const TUTOR_CLASSROOM_SCENE: String = "res://scenes/tutor/classroom.tscn"
const L10n := preload("res://scripts/localization/localization.gd")
const HelperFont := preload("res://scripts/localization/helper_font.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const SCRATCH_PROFILE: String = "user://input_settings_harness_profile.json"
const DESIGN_HEIGHT: int = 1024
const FRAMES: Array = [Vector2i(1334, 750), Vector2i(2340, 1080)]
## Every frame the way-back geometry is asserted at: iPad 16:9-ish, iPhone, and
## the project's own 4:3 window override.
const OVERLAY_FRAMES: Array = [Vector2i(1334, 750), Vector2i(2340, 1080), Vector2i(1024, 768)]
## Detached for the run, as `run_tests.gd` does, so nothing here can reach a real
## profile or the mixer.
const PROJECT_AUTOLOADS: Array = ["SaveService", "SpeechService", "TtsService", "Voice", "Sfx", "Audio"]
## The privacy sentence the guards depend on, verbatim.
const PRIVACY_SENTENCE: String = "The online AI tutor is switched off in this build."

var _fail: Array = []
var _viewport: SubViewport = null
var _last_pointer: Vector2 = Vector2.ZERO
## Services attached under the root for a scenario (a real SaveService on the
## scratch file, and fakes for the mixer), removed again by `_detach_services`.
var _attached: Array = []
## Set by every scenario on its last line. A scenario that a script error
## aborts half-way returns silently with nothing in `_fail`; `_probe` turns
## that into a failure rather than a PASS.
var _reached_end: bool = false


## A stand-in for the `Audio` autoload (`AudioDirector`): records the last level.
class FakeAudio extends Node:
	var music: float = -1.0
	func set_music_volume_linear(value: float) -> void:
		music = value


## A stand-in for `TtsService`: records the last voice level.
class FakeTts extends Node:
	var voice: float = -1.0
	func set_voice_volume(value: float) -> void:
		voice = value


## A stand-in for the `Voice` director: records per-character levels.
class FakeVoice extends Node:
	var levels: Dictionary = {}
	func set_character_volume(character: String, value: float) -> void:
		levels[character] = value


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	for autoload_name: String in PROJECT_AUTOLOADS:
		var node: Node = root.get_node_or_null(NodePath(autoload_name))
		if node != null:
			root.remove_child(node)

	for frame: Vector2i in FRAMES:
		await _probe("footer reachable %dx%d" % [frame.x, frame.y], _footer_reachable.bind(frame))
	await _probe("scroll from slider", _scroll_from_slider)
	await _probe("scroll from button", _scroll_from_button)
	await _probe("scroll from text, Close and language button", _scroll_from_text_and_chrome)
	await _probe("taps still work", _taps_still_work)
	await _probe("slider still drags", _slider_still_drags)
	await _probe("footer and gate card swipes are inert", _footer_and_card_swipes_are_inert)
	await _probe("two fingers", _two_fingers)
	await _probe("gear tap and hold", _gear_tap_and_hold)
	await _probe("close, Escape, Android back", _close_escape_and_android_back)
	await _probe("home from the pause card", _home_from_pause_card)
	await _probe("home from the title", _home_from_title)
	await _probe("sliders drive the mixer and persist", _sliders_apply_and_persist)
	await _probe("language updates and persists", _language_updates_and_persists)
	await _probe("tutor toggles persist and the classroom reads them", _tutor_toggles_persist)
	await _probe("privacy information is static", _privacy_is_static)
	await _probe("delete history and reset progress", _delete_history_and_reset)
	for frame: Vector2i in OVERLAY_FRAMES:
		await _probe("no dead overlay %dx%d" % [frame.x, frame.y], _no_dead_overlay.bind(frame))
	_delete_scratch_profile()

	if _fail.is_empty():
		print("\nINPUT SETTINGS OK")
		quit(0)
	else:
		print("\nINPUT SETTINGS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


## Runs one scenario and prints its verdict line.
func _probe(label: String, scenario: Callable) -> void:
	var before: int = _fail.size()
	_reached_end = false
	await scenario.call()
	if _fail.size() == before and not _reached_end:
		_fail.append("%s: the scenario did not run to its end (a script error aborted it)" % label)
	_detach_services()
	_close_viewport()
	print("PROBE %s: %s" % [label, "PASS" if _fail.size() == before else "FAIL"])


## The last line of every scenario.
func _finish() -> void:
	_reached_end = true


# -- scaffolding ---------------------------------------------------------------

func _open_viewport(frame: Vector2i) -> void:
	_close_viewport()
	_viewport = SubViewport.new()
	_viewport.size = frame
	var design_width: int = int(round(float(frame.x) * float(DESIGN_HEIGHT) / float(frame.y)))
	_viewport.size_2d_override = Vector2i(design_width, DESIGN_HEIGHT)
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_viewport)


func _close_viewport() -> void:
	if _viewport == null:
		return
	root.remove_child(_viewport)
	_viewport.free()
	_viewport = null


## A fresh panel in a fresh viewport, opened (or left locked) and laid out.
func _fresh_panel(frame: Vector2i, open: bool) -> Control:
	_open_viewport(frame)
	return await _add_panel(open)


## A fresh panel in the CURRENT viewport.
func _add_panel(open: bool) -> Control:
	var panel: Control = (load(PARENT_SCENE) as PackedScene).instantiate()
	_viewport.add_child(panel)
	await _settle(0.2)
	if open:
		panel.call("open_settings")
		await _settle(0.3)
	return panel


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _center_of(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


## Scrolls `control` into the scroll area (a control clipped out of it cannot be
## hit), then lets the layout settle.
func _bring_into_view(panel: Control, control: Control) -> void:
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	if scroll != null and control != null and scroll.is_ancestor_of(control):
		scroll.ensure_control_visible(control)
	await _settle(0.2)


## The emulated mouse press, then the touch, exactly as `Input` orders them.
func _touch_down(pos: Vector2) -> void:
	_last_pointer = pos
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
	mouse.pressed = true
	mouse.position = pos
	mouse.global_position = pos
	_viewport.push_input(mouse, true)
	_touch_down_only(pos, 0)


func _touch_move(pos: Vector2) -> void:
	var relative: Vector2 = pos - _last_pointer
	_last_pointer = pos
	var motion := InputEventMouseMotion.new()
	motion.device = InputEvent.DEVICE_ID_EMULATION
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = pos
	motion.global_position = pos
	motion.relative = relative
	_viewport.push_input(motion, true)
	_touch_move_only(pos, relative, 0)


func _touch_up(pos: Vector2) -> void:
	_last_pointer = pos
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	mouse.position = pos
	mouse.global_position = pos
	_viewport.push_input(mouse, true)
	_touch_up_only(pos, 0)


## A finger that is NOT the mouse: the bare touch event with its own index.
func _touch_down_only(pos: Vector2, index: int) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.pressed = true
	touch.position = pos
	_viewport.push_input(touch, true)


func _touch_move_only(pos: Vector2, relative: Vector2, index: int) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = pos
	drag.relative = relative
	_viewport.push_input(drag, true)


func _touch_up_only(pos: Vector2, index: int) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.pressed = false
	touch.position = pos
	_viewport.push_input(touch, true)


func _tap(pos: Vector2) -> void:
	_touch_down(pos)
	await process_frame
	_touch_up(pos)
	await process_frame


## A finger travelling from `from` by `delta`, in `steps` moves a frame apart.
func _swipe(from: Vector2, delta: Vector2, steps: int = 6) -> void:
	_touch_down(from)
	await process_frame
	for i in steps:
		_touch_move(from + delta * (float(i + 1) / float(steps)))
		await process_frame
	_touch_up(from + delta)
	await process_frame


## A key press and release, through the same viewport (Escape is `ui_cancel`).
func _press_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		_viewport.push_input(key, true)
		await process_frame


## A real press on a hold bar: pressed for a moment of real frames (so the hold
## is seen to advance under a finger), then the rest of the 3 s driven directly
## so the harness does not spend three wall-clock seconds per hold.
func _hold_for_three_seconds(hold: Control, tag: String) -> void:
	var center: Vector2 = _center_of(hold)
	_touch_down(center)
	await process_frame
	if not bool(hold.call("is_holding")):
		_fail.append("%s: a real press on the hold bar did not start the hold" % tag)
	await _settle(0.2)
	if not bool(hold.call("is_holding")) or float(hold.call("get_progress")) <= 0.0:
		_fail.append("%s: the hold did not advance while pressed (progress %.2f)" % [tag, float(hold.call("get_progress"))])
	hold.call("advance", 1.0)
	await process_frame
	_touch_up(center)
	await process_frame


## The REAL SaveService on a fresh scratch profile, plus mixer stand-ins, all
## under the root where the panel's `_autoload()` lookups find them.
func _attach_services() -> Dictionary:
	_detach_services()
	_delete_scratch_profile()
	var save: Node = _fresh_save_service()
	var audio := FakeAudio.new()
	audio.name = "Audio"
	var tts := FakeTts.new()
	tts.name = "TtsService"
	var voice := FakeVoice.new()
	voice.name = "Voice"
	for node: Node in [save, audio, tts, voice]:
		root.add_child(node)
		_attached.append(node)
	return {"save": save, "audio": audio, "tts": tts, "voice": voice}


## A SaveService that has just read the scratch file from disk: "relaunch".
func _fresh_save_service() -> Node:
	var store: ProfileStore = ProfileStore.new(SCRATCH_PROFILE)
	var save: Node = (load(SAVE_SERVICE_SCRIPT) as GDScript).new(store)
	save.name = "SaveService"
	return save


## Swaps the root's SaveService for one re-read from disk. Returns the new one.
func _relaunch_save_service() -> Node:
	var old: Node = root.get_node_or_null("SaveService")
	if old != null:
		root.remove_child(old)
		_attached.erase(old)
		old.free()
	var save: Node = _fresh_save_service()
	root.add_child(save)
	_attached.append(save)
	return save


func _detach_services() -> void:
	for node: Node in _attached:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_attached.clear()


func _delete_scratch_profile() -> void:
	for path: String in [SCRATCH_PROFILE, SCRATCH_PROFILE + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## `value` as a float setting from the profile, or -1 when absent / not a number.
static func _setting_number(save: Node, key: String) -> float:
	var value: Variant = save.call("get_setting", key, null)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return -1.0


# -- scenarios -----------------------------------------------------------------

## (c) Done, Reset and the stars are reachable WITHOUT scrolling, and the footer
## never hides the end of the scroll content.
func _footer_reachable(frame: Vector2i) -> void:
	var panel: Control = await _fresh_panel(frame, true)
	var tag: String = "%dx%d" % [frame.x, frame.y]
	var visible_rect: Rect2 = _viewport.get_visible_rect()
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var footer: Control = panel.find_child("Footer", true, false) as Control
	if scroll == null or footer == null:
		_fail.append("%s: no Center / Footer" % tag)
		return
	if scroll.scroll_vertical != 0:
		_fail.append("%s: the panel opened scrolled to %d" % [tag, scroll.scroll_vertical])
	for node_name: String in ["DoneButton", "ResetButton", "StarsLabel"]:
		var node: Control = panel.find_child(node_name, true, false) as Control
		if node == null or not node.is_visible_in_tree():
			_fail.append("%s: %s is not on screen" % [tag, node_name])
			continue
		var rect: Rect2 = node.get_global_rect()
		if not visible_rect.encloses(rect):
			_fail.append("%s: %s at %s is outside the %s frame without scrolling" % [tag, node_name, str(rect), str(visible_rect)])
		if scroll.is_ancestor_of(node):
			_fail.append("%s: %s is inside the scroll content; it must be pinned" % [tag, node_name])
	var scroll_rect: Rect2 = scroll.get_global_rect()
	var footer_rect: Rect2 = footer.get_global_rect()
	if scroll_rect.end.y > footer_rect.position.y + 0.5:
		_fail.append("%s: the scroll area (ends %.0f) runs under the footer (starts %.0f)" % [tag, scroll_rect.end.y, footer_rect.position.y])
	if scroll.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail.append("%s: Center must STOP touches so none leak to the room" % tag)

	var bar: VScrollBar = scroll.get_v_scroll_bar()
	if bar == null or not bar.is_visible_in_tree():
		_fail.append("%s: no visible vertical scrollbar" % tag)
	elif bar.size.x < 48.0:
		_fail.append("%s: the scrollbar is %.0f px wide; a finger needs 48" % [tag, bar.size.x])

	# Scrolled to the very bottom, the last of the content sits above the footer.
	scroll.scroll_vertical = 100000
	await _settle(0.2)
	var content_panel: Control = panel.find_child("Panel", true, false) as Control
	if content_panel != null and content_panel.get_global_rect().end.y > scroll_rect.end.y + 1.0:
		_fail.append("%s: scrolled to the end, the content (ends %.0f) is still cut off by the footer (scroll ends %.0f)"
				% [tag, content_panel.get_global_rect().end.y, scroll_rect.end.y])
	if scroll.scroll_vertical <= 0:
		_fail.append("%s: the content does not overflow at all (scroll_vertical %d); nothing to scroll" % [tag, scroll.scroll_vertical])
	_finish()


## (a) A vertical drag that STARTS ON A SLIDER scrolls the panel and leaves the
## slider exactly where it was.
func _scroll_from_slider() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var slider: HSlider = panel.find_child("MusicSlider", true, false) as HSlider
	var before: float = slider.value
	var settled_values: Array = []
	slider.value_changed.connect(func(v: float) -> void: settled_values.append(v))
	var start: Vector2 = _center_of(slider)
	await _swipe(start, Vector2(0.0, -300.0))
	if scroll.scroll_vertical < 150:
		_fail.append("slider swipe: the panel scrolled only %d px for a 300 px drag" % scroll.scroll_vertical)
	if absf(slider.value - before) > 0.001:
		_fail.append("slider swipe: the music slider moved from %.2f to %.2f; a scroll must never change a volume" % [before, slider.value])
	if not settled_values.is_empty() and absf(float(settled_values.back()) - before) > 0.001:
		_fail.append("slider swipe: the slider's last value_changed was %.2f, not the original %.2f" % [float(settled_values.back()), before])
	if str(panel.call("scroll_gesture")) != "NONE":
		_fail.append("slider swipe: the gesture is still %s after the finger lifted" % str(panel.call("scroll_gesture")))
	# The slider is not left grabbed: a later hover without a button does nothing.
	var hover := InputEventMouseMotion.new()
	hover.position = start + Vector2(150.0, -300.0)
	hover.global_position = hover.position
	_viewport.push_input(hover, true)
	await process_frame
	if absf(slider.value - before) > 0.001:
		_fail.append("slider swipe: the slider kept following the pointer after the finger lifted (%.2f)" % slider.value)
	_finish()


## (a, again) A vertical drag that starts on an option BUTTON scrolls and does
## not press the button.
func _scroll_from_button() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var button: Button = panel.find_child("VoiceOffButton", true, false) as Button
	await _bring_into_view(panel, button)
	var scroll_before: int = scroll.scroll_vertical
	var presses: Array = [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	var was_pressed: bool = button.button_pressed
	await _swipe(_center_of(button), Vector2(0.0, -260.0))
	if scroll.scroll_vertical - scroll_before < 120:
		_fail.append("button swipe: the panel scrolled only %d px" % (scroll.scroll_vertical - scroll_before))
	if presses[0] != 0 or button.button_pressed != was_pressed:
		_fail.append("button swipe: the finger scrolled away and Voice Off still fired (%d) / toggled (%s)" % [presses[0], str(button.button_pressed)])
	if button.is_pressed() != was_pressed:
		_fail.append("button swipe: the button is stuck down after the scroll")
	_finish()


## A vertical drag that starts on plain TEXT, on the header's Close button, or
## on a helper-language button scrolls the panel, and neither closes it nor
## changes the language.
func _scroll_from_text_and_chrome() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var closes: Array = [0]
	panel.connect("closed", func() -> void: closes[0] += 1)

	var title: Label = panel.find_child("MusicTitle", true, false) as Label
	await _swipe(_center_of(title), Vector2(0.0, -300.0))
	if scroll.scroll_vertical < 150:
		_fail.append("text swipe: a drag on the Music title scrolled only %d px" % scroll.scroll_vertical)
	scroll.scroll_vertical = 0
	await _settle(0.2)

	var close: Button = panel.find_child("CloseButton", true, false) as Button
	await _swipe(_center_of(close), Vector2(0.0, -260.0))
	if scroll.scroll_vertical < 120:
		_fail.append("close swipe: a drag starting on Close scrolled only %d px" % scroll.scroll_vertical)
	if closes[0] != 0 or not bool(panel.call("is_panel_visible")):
		_fail.append("close swipe: a drag starting on Close closed the panel (closed %d)" % closes[0])
	scroll.scroll_vertical = 0
	await _settle(0.2)

	var language_before: String = String(panel.call("model").call("get_helper_language"))
	var off: Button = panel.find_child("HelperOffButton", true, false) as Button
	await _bring_into_view(panel, off)
	var scroll_before: int = scroll.scroll_vertical
	await _swipe(_center_of(off), Vector2(0.0, -260.0))
	if scroll.scroll_vertical - scroll_before < 120:
		_fail.append("language swipe: a drag starting on Helper Off scrolled only %d px" % (scroll.scroll_vertical - scroll_before))
	if String(panel.call("model").call("get_helper_language")) != language_before:
		_fail.append("language swipe: a drag starting on Helper Off changed the language to %s" % String(panel.call("model").call("get_helper_language")))
	_finish()


## (b) A plain tap still reaches a button, and still reaches a slider track.
func _taps_still_work() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	# Voice practice now follows the Sound section; scroll it into view just as
	# a parent would. A tap must not move the scroll position it started with.
	var off: Button = panel.find_child("VoiceOffButton", true, false) as Button
	await _bring_into_view(panel, off)
	var scroll_before: int = scroll.scroll_vertical
	if not scroll.get_global_rect().encloses(off.get_global_rect()):
		_fail.append("tap: VoiceOffButton %s is not fully inside the scroll area %s; pick another target" % [str(off.get_global_rect()), str(scroll.get_global_rect())])
	var presses: Array = [0]
	off.pressed.connect(func() -> void: presses[0] += 1)
	await _tap(_center_of(off))
	if presses[0] != 1 or not off.button_pressed:
		_fail.append("tap: Voice Off fired %d time(s), selected=%s; a tap must still press a button" % [presses[0], str(off.button_pressed)])
	if scroll.scroll_vertical != scroll_before:
		_fail.append("tap: a tap scrolled the panel by %d" % (scroll.scroll_vertical - scroll_before))

	var slider: HSlider = panel.find_child("MusicSlider", true, false) as HSlider
	await _bring_into_view(panel, slider)
	var rect: Rect2 = slider.get_global_rect()
	await _tap(Vector2(rect.position.x + rect.size.x * 0.25, rect.get_center().y))
	if absf(slider.value - 0.25) > 0.1:
		_fail.append("tap: a tap a quarter of the way along the music slider set %.2f, expected about 0.25" % slider.value)

	var closes: Array = [0]
	panel.connect("closed", func() -> void: closes[0] += 1)
	var done: Button = panel.find_child("DoneButton", true, false) as Button
	await _tap(_center_of(done))
	if closes[0] != 1 or bool(panel.call("is_panel_visible")):
		_fail.append("tap: Done in the footer closed %d time(s), panel visible=%s" % [closes[0], str(panel.call("is_panel_visible"))])
	_finish()


## A mostly-horizontal drag on a slider is still a slider drag: the value
## follows the finger and the panel does not scroll.
func _slider_still_drags() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var slider: HSlider = panel.find_child("VoiceVolumeSlider", true, false) as HSlider
	slider.value = 0.5
	var rect: Rect2 = slider.get_global_rect()
	# Start on the grabber (mid-track at 0.5) and slide right with a little wobble.
	await _swipe(rect.get_center(), Vector2(rect.size.x * 0.4, 6.0))
	if slider.value < 0.75:
		_fail.append("slider drag: sliding the voice slider right from 0.5 left it at %.2f" % slider.value)
	if scroll.scroll_vertical != 0:
		_fail.append("slider drag: a horizontal slider drag scrolled the panel by %d" % scroll.scroll_vertical)
	_finish()


## A vertical drag that starts in the pinned FOOTER (Done, the erase bar) or on
## the GATE CARD (its hold bar, its Back) presses nothing, erases nothing and
## unlocks nothing. Those regions do not scroll; they must simply be inert
## under a swipe.
func _footer_and_card_swipes_are_inert() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var closes: Array = [0]
	panel.connect("closed", func() -> void: closes[0] += 1)
	var stars_before: int = int(panel.call("model").call("get_stars"))

	var done: Button = panel.find_child("DoneButton", true, false) as Button
	await _swipe(_center_of(done), Vector2(0.0, -200.0))
	if closes[0] != 0 or not bool(panel.call("is_panel_visible")):
		_fail.append("footer swipe: a drag starting on Done closed the panel")
	if scroll.scroll_vertical != 0:
		_fail.append("footer swipe: a drag on the footer scrolled the list by %d" % scroll.scroll_vertical)

	var reset: Button = panel.find_child("ResetButton", true, false) as Button
	await _tap(_center_of(reset))
	var confirm_box: Control = panel.find_child("ConfirmBox", true, false) as Control
	var hold: Control = panel.find_child("ConfirmHold", true, false) as Control
	if confirm_box == null or not confirm_box.is_visible_in_tree() or hold == null:
		_fail.append("footer swipe: Reset did not reveal the hold-to-erase bar")
		return
	await _swipe(_center_of(hold), Vector2(0.0, -200.0))
	if bool(hold.call("is_holding")):
		_fail.append("footer swipe: a drag off the erase bar left it holding")
	if bool(hold.call("has_unlocked")) or int(panel.call("model").call("get_stars")) != stars_before:
		_fail.append("footer swipe: a drag on the erase bar erased progress")
	var cancel: Button = panel.find_child("CancelResetButton", true, false) as Button
	await _tap(_center_of(cancel))
	if confirm_box.is_visible_in_tree():
		_fail.append("footer swipe: Keep my stars did not put the confirmation away")

	# The gate card, as the pause card opens it.
	var card_panel: Control = await _fresh_panel(FRAMES[0], false)
	card_panel.call("show_gate_card")
	await _settle(0.2)
	var card_closes: Array = [0]
	card_panel.connect("closed", func() -> void: card_closes[0] += 1)
	var gate_hold: Control = card_panel.find_child("GateHold", true, false) as Control
	if not bool(card_panel.call("is_gate_card_visible")) or gate_hold == null:
		_fail.append("card swipe: the gate card is not showing")
		return
	await _swipe(_center_of(gate_hold), Vector2(0.0, -200.0))
	if bool(gate_hold.call("is_holding")) or bool(card_panel.call("is_panel_visible")):
		_fail.append("card swipe: a drag off the card's hold bar left it holding / opened the settings")
	var back: Button = card_panel.find_child("GateBackButton", true, false) as Button
	await _swipe(_center_of(back), Vector2(0.0, -200.0))
	if card_closes[0] != 0 or not bool(card_panel.call("is_gate_card_visible")):
		_fail.append("card swipe: a drag starting on Back left the card (closed %d)" % card_closes[0])
	await _tap(_center_of(back))
	if card_closes[0] != 1:
		_fail.append("card swipe: a TAP on the card's Back emitted closed() %d time(s), expected 1" % card_closes[0])
	_finish()


## QA (2026-09-21): "a second finger can press an option while the first
## scrolls." While one finger's gesture is live, a second finger -- a bare touch
## with another index, which is all `Input` delivers for it -- must not start
## the hold-to-erase bar, press an option, close the panel, or move the list.
func _two_fingers() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var closes: Array = [0]
	panel.connect("closed", func() -> void: closes[0] += 1)
	var stars_before: int = int(panel.call("model").call("get_stars"))
	var reset: Button = panel.find_child("ResetButton", true, false) as Button
	await _tap(_center_of(reset))
	var hold: Control = panel.find_child("ConfirmHold", true, false) as Control
	var off: Button = panel.find_child("VoiceOffButton", true, false) as Button
	var done: Button = panel.find_child("DoneButton", true, false) as Button
	var presses: Array = [0]
	off.pressed.connect(func() -> void: presses[0] += 1)
	if hold == null or not hold.is_visible_in_tree():
		_fail.append("two fingers: no erase bar to test against")
		return

	# Finger A: a scroll in progress, on plain text.
	var start: Vector2 = _center_of(panel.find_child("MusicTitle", true, false) as Control)
	_touch_down(start)
	await process_frame
	_touch_move(start + Vector2(0.0, -40.0))
	await process_frame
	_touch_move(start + Vector2(0.0, -120.0))
	await process_frame
	if str(panel.call("scroll_gesture")) != "SCROLLING":
		_fail.append("two fingers: finger A is %s, not SCROLLING" % str(panel.call("scroll_gesture")))
	var scrolled: int = scroll.scroll_vertical

	# Finger B lands on the erase bar.
	var hold_center: Vector2 = _center_of(hold)
	_touch_down_only(hold_center, 1)
	await process_frame
	if bool(hold.call("is_holding")):
		_fail.append("two fingers: a second finger on the erase bar started the hold while the first was scrolling")
	await _settle(0.1)
	_touch_up_only(hold_center, 1)
	await process_frame
	if bool(hold.call("is_holding")) or bool(hold.call("has_unlocked")):
		_fail.append("two fingers: the erase bar is holding / unlocked after the second finger lifted")

	# Finger B lands on an option, then on Done, then drags.
	_touch_down_only(_center_of(off), 1)
	await process_frame
	_touch_up_only(_center_of(off), 1)
	await process_frame
	if presses[0] != 0 or off.button_pressed:
		_fail.append("two fingers: a second finger pressed Voice Off (%d) during a scroll" % presses[0])
	_touch_down_only(_center_of(done), 1)
	await process_frame
	_touch_up_only(_center_of(done), 1)
	await process_frame
	if closes[0] != 0 or not bool(panel.call("is_panel_visible")):
		_fail.append("two fingers: a second finger on Done closed the panel during a scroll")
	var elsewhere: Vector2 = start + Vector2(300.0, 0.0)
	_touch_down_only(elsewhere, 1)
	await process_frame
	_touch_move_only(elsewhere + Vector2(0.0, -100.0), Vector2(0.0, -100.0), 1)
	await process_frame
	if scroll.scroll_vertical != scrolled:
		_fail.append("two fingers: the second finger's drag moved the list (%d -> %d) while the first held it" % [scrolled, scroll.scroll_vertical])
	_touch_up_only(elsewhere + Vector2(0.0, -100.0), 1)
	await process_frame

	# Finger A carries on scrolling, then lifts: clean.
	_touch_move(start + Vector2(0.0, -220.0))
	await process_frame
	if scroll.scroll_vertical <= scrolled:
		_fail.append("two fingers: finger A stopped scrolling after the second finger (%d -> %d)" % [scrolled, scroll.scroll_vertical])
	_touch_up(start + Vector2(0.0, -220.0))
	await process_frame
	if str(panel.call("scroll_gesture")) != "NONE":
		_fail.append("two fingers: the gesture is still %s after both fingers lifted" % str(panel.call("scroll_gesture")))
	if int(panel.call("model").call("get_stars")) != stars_before:
		_fail.append("two fingers: progress was erased")

	# A second finger while the first is merely PRESSING (not yet moved) is
	# ignored too, and the first finger's tap still lands. (The confirmation is
	# up, so the footer is taller: the button is scrolled fully into view first.)
	var on: Button = panel.find_child("VoiceOnButton", true, false) as Button
	var on_presses: Array = [0]
	on.pressed.connect(func() -> void: on_presses[0] += 1)
	await _bring_into_view(panel, on)
	if not scroll.get_global_rect().encloses(on.get_global_rect()):
		_fail.append("two fingers: VoiceOnButton %s is not inside the scroll area %s" % [str(on.get_global_rect()), str(scroll.get_global_rect())])
	_touch_down(_center_of(on))
	await process_frame
	_touch_down_only(hold_center, 1)
	await process_frame
	if bool(hold.call("is_holding")):
		_fail.append("two fingers: a second finger on the erase bar started the hold while the first pressed a button")
	_touch_up_only(hold_center, 1)
	await process_frame
	_touch_up(_center_of(on))
	await process_frame
	if on_presses[0] != 1:
		_fail.append("two fingers: the first finger's tap on Voice On was lost (%d)" % on_presses[0])
	if bool(hold.call("is_holding")):
		_fail.append("two fingers: the erase bar is still holding after everything lifted")

	# The same with the first finger in the FOOTER (on Keep my stars): the
	# second finger cannot start the erase hold, and Keep my stars still lands.
	var cancel: Button = panel.find_child("CancelResetButton", true, false) as Button
	var confirm_box: Control = panel.find_child("ConfirmBox", true, false) as Control
	_touch_down(_center_of(cancel))
	await process_frame
	if str(panel.call("scroll_gesture")) != "OUTSIDE":
		_fail.append("two fingers: a press in the footer is tracked as %s, expected OUTSIDE" % str(panel.call("scroll_gesture")))
	_touch_down_only(hold_center, 1)
	await process_frame
	if bool(hold.call("is_holding")):
		_fail.append("two fingers: a second finger on the erase bar started the hold while the first pressed Keep my stars")
	_touch_up_only(hold_center, 1)
	await process_frame
	_touch_up(_center_of(cancel))
	await process_frame
	if confirm_box.is_visible_in_tree():
		_fail.append("two fingers: the first finger's tap on Keep my stars was lost")
	if str(panel.call("scroll_gesture")) != "NONE" or int(panel.call("model").call("get_stars")) != stars_before:
		_fail.append("two fingers: after the footer press the gesture is %s / stars changed" % str(panel.call("scroll_gesture")))
	_finish()


## (d) The Baby Room's corner gear: a TAP opens the gate card; a hold on the
## card's bar unlocks; the hold survives finger jitter; Back and Done return to
## the gear.
func _gear_tap_and_hold() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], false)
	var gear: Control = panel.find_child("EntryGate", true, false) as Control
	if gear == null or not gear.is_visible_in_tree():
		_fail.append("gear: the corner gear is not showing in overlay mode")
		return
	var closes: Array = [0]
	panel.connect("closed", func() -> void: closes[0] += 1)

	# Jitter: a held finger wandering a little past the gear's edge keeps holding.
	var gear_center: Vector2 = _center_of(gear)
	_touch_down(gear_center)
	await process_frame
	if not bool(gear.call("is_holding")):
		_fail.append("gear: a real press did not start the hold")
	_touch_move(gear_center + Vector2(60.0, 0.0))
	await process_frame
	if not bool(gear.call("is_holding")):
		_fail.append("gear: a 60 px wobble (18 px past the edge) cancelled the hold")
	_touch_move(gear_center + Vector2(200.0, 0.0))
	await process_frame
	if bool(gear.call("is_holding")):
		_fail.append("gear: sliding 200 px off the gear did not cancel the hold")
	_touch_up(gear_center + Vector2(200.0, 0.0))
	await process_frame
	if bool(panel.call("is_gate_card_visible")):
		_fail.append("gear: a slid-off press opened the gate card")

	# A tap opens the card.
	await _tap(gear_center)
	if not bool(panel.call("is_gate_card_visible")):
		_fail.append("gear: a single tap did not open the gate card")
		return
	if bool(panel.call("is_panel_visible")):
		_fail.append("gear: a single tap opened the settings; only a 3 s hold may")
	if gear.is_visible_in_tree():
		_fail.append("gear: the gear is still showing under the card")

	# Back returns to the gear without telling the host anything closed.
	var back: Button = panel.find_child("GateBackButton", true, false) as Button
	await _tap(_center_of(back))
	if bool(panel.call("is_gate_card_visible")) or not gear.is_visible_in_tree():
		_fail.append("gear: Back on the tapped card did not put the gear back")
	if closes[0] != 0:
		_fail.append("gear: Back on the tapped card emitted closed() %d time(s); the room never saw it open" % closes[0])

	# Tap again, hold the card's bar for 3 s: unlocked.
	await _tap(gear_center)
	var hold: Control = panel.find_child("GateHold", true, false) as Control
	if hold == null or not hold.is_visible_in_tree():
		_fail.append("gear: the card's hold bar is missing")
		return
	await _hold_for_three_seconds(hold, "gear")
	if not bool(panel.call("is_panel_visible")):
		_fail.append("gear: a 3 s hold on the card's bar did not open the settings")

	# Done after that: the gear is back, not the card, and the host hears closed().
	var done: Button = panel.find_child("DoneButton", true, false) as Button
	await _tap(_center_of(done))
	if closes[0] != 1:
		_fail.append("gear: Done emitted closed() %d time(s), expected 1" % closes[0])
	if bool(panel.call("is_gate_card_visible")) or bool(panel.call("is_panel_visible")) or not gear.is_visible_in_tree():
		_fail.append("gear: after Done the corner gear must be back (card=%s panel=%s gear=%s)"
				% [str(panel.call("is_gate_card_visible")), str(panel.call("is_panel_visible")), str(gear.is_visible_in_tree())])
	_finish()


## Close (header), Escape (`ui_cancel`) and the Android back request
## (`NOTIFICATION_WM_GO_BACK_REQUEST`) each leave the open panel, and each acts
## as the gate card's Back while the card is up.
func _close_escape_and_android_back() -> void:
	# Close.
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var closes: Array = [0]
	panel.connect("closed", func() -> void: closes[0] += 1)
	var close: Button = panel.find_child("CloseButton", true, false) as Button
	await _tap(_center_of(close))
	if closes[0] != 1 or bool(panel.call("is_panel_visible")):
		_fail.append("close: the header's Close closed %d time(s), panel visible=%s" % [closes[0], str(panel.call("is_panel_visible"))])
	var gear: Control = panel.find_child("EntryGate", true, false) as Control
	if gear == null or not gear.is_visible_in_tree():
		_fail.append("close: after Close in overlay mode the corner gear must be back")

	# Escape while open.
	panel.call("open_settings")
	await _settle(0.2)
	await _press_key(KEY_ESCAPE)
	if closes[0] != 2 or bool(panel.call("is_panel_visible")):
		_fail.append("escape: Escape on the open panel closed %d time(s) in total (expected 2), visible=%s" % [closes[0], str(panel.call("is_panel_visible"))])

	# Android back while open.
	panel.call("open_settings")
	await _settle(0.2)
	panel.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	if closes[0] != 3 or bool(panel.call("is_panel_visible")):
		_fail.append("android back: the go-back request on the open panel closed %d time(s) in total (expected 3), visible=%s" % [closes[0], str(panel.call("is_panel_visible"))])

	# The pause card's gate card: Escape / back = the card's Back, which tells the
	# host to take the overlay down.
	for way: String in ["escape", "android"]:
		var card_panel: Control = await _fresh_panel(FRAMES[0], false)
		card_panel.call("show_gate_card")
		await _settle(0.2)
		var card_closes: Array = [0]
		var backs: Array = [0]
		card_panel.connect("closed", func() -> void: card_closes[0] += 1)
		card_panel.connect("back_requested", func() -> void: backs[0] += 1)
		if way == "escape":
			await _press_key(KEY_ESCAPE)
		else:
			card_panel.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
			await process_frame
		if backs[0] != 1 or card_closes[0] != 1:
			_fail.append("%s on the pause card's gate card: back_requested %d, closed %d (expected 1 and 1)" % [way, backs[0], card_closes[0]])

	# The gear-tapped card: Escape puts the gear back and tells the host nothing.
	var gear_panel: Control = await _fresh_panel(FRAMES[0], false)
	var gear_closes: Array = [0]
	gear_panel.connect("closed", func() -> void: gear_closes[0] += 1)
	var gear2: Control = gear_panel.find_child("EntryGate", true, false) as Control
	await _tap(_center_of(gear2))
	if not bool(gear_panel.call("is_gate_card_visible")):
		_fail.append("escape on the gear card: the tap did not open the card")
		return
	await _press_key(KEY_ESCAPE)
	if bool(gear_panel.call("is_gate_card_visible")) or not gear2.is_visible_in_tree() or gear_closes[0] != 0:
		_fail.append("escape on the gear card: card=%s gear=%s closed=%d (expected gear back, nothing closed)"
				% [str(gear_panel.call("is_gate_card_visible")), str(gear2.is_visible_in_tree()), gear_closes[0]])

	# The locked gear alone: Escape is not ours; nothing changes and nothing closes.
	await _press_key(KEY_ESCAPE)
	if gear_closes[0] != 0 or not gear2.is_visible_in_tree():
		_fail.append("escape on the locked gear: closed %d / gear %s" % [gear_closes[0], str(gear2.is_visible_in_tree())])
	_finish()


## The house: the pause card's Grown-ups opens the gate card over the held
## room; Done (after the hold) and Back each take the overlay down and give the
## room back. Driven through the real `HouseHud` with real taps; the HUD has no
## world here, so "held" is the HUD's own `is_world_paused()`.
func _home_from_pause_card() -> void:
	_open_viewport(FRAMES[0])
	var hud: Control = (load(HOUSE_HUD_SCRIPT) as GDScript).new()
	_viewport.add_child(hud)
	await _settle(0.2)
	for round: String in ["done", "back"]:
		hud.call("open_pause_menu")
		await _settle(0.2)
		if not bool(hud.call("is_pause_menu_open")):
			_fail.append("pause card (%s): the pause card did not open" % round)
			return
		var buttons: Dictionary = hud.call("get_pause_menu").call("get_buttons")
		var settings: Button = buttons.get("settings") as Button
		if settings == null or not settings.is_visible_in_tree():
			_fail.append("pause card (%s): no Grown-ups button on the card" % round)
			return
		if not _viewport.get_visible_rect().encloses(settings.get_global_rect()):
			_fail.append("pause card (%s): Grown-ups at %s is off screen" % [round, str(settings.get_global_rect())])
		await _tap(_center_of(settings))
		if not bool(hud.call("is_grown_ups_open")):
			_fail.append("pause card (%s): a tap on Grown-ups did not open the settings overlay" % round)
			return
		if bool(hud.call("is_pause_menu_open")):
			_fail.append("pause card (%s): the pause card stayed up under the gate card" % round)
		if not bool(hud.call("is_world_paused")):
			_fail.append("pause card (%s): the room is not held while the gate card is up" % round)
		var overlay: Control = _viewport.find_child("ParentSettings", true, false) as Control
		if overlay == null or not bool(overlay.call("is_gate_card_visible")):
			_fail.append("pause card (%s): the overlay is not showing the gate card" % round)
			return
		var back: Button = overlay.find_child("GateBackButton", true, false) as Button
		if not _viewport.get_visible_rect().encloses(back.get_global_rect()):
			_fail.append("pause card (%s): the gate card's Back at %s is off screen" % [round, str(back.get_global_rect())])
		if round == "done":
			var hold: Control = overlay.find_child("GateHold", true, false) as Control
			await _hold_for_three_seconds(hold, "pause card")
			if not bool(overlay.call("is_panel_visible")):
				_fail.append("pause card: the hold did not open the settings")
				return
			if not bool(hud.call("is_world_paused")):
				_fail.append("pause card: the room came back while the settings were open")
			var done: Button = overlay.find_child("DoneButton", true, false) as Button
			await _tap(_center_of(done))
		else:
			await _tap(_center_of(back))
		await _settle(0.2)
		if bool(hud.call("is_grown_ups_open")):
			_fail.append("pause card (%s): the overlay is still open" % round)
		if is_instance_valid(overlay) and overlay.is_inside_tree():
			_fail.append("pause card (%s): the overlay is still in the tree" % round)
		if bool(hud.call("is_world_paused")):
			_fail.append("pause card (%s): the room was not given back" % round)
		if bool(hud.call("is_pause_menu_open")):
			_fail.append("pause card (%s): the pause card came back on its own" % round)
	_finish()


## The title screen's Grown-ups: the panel is pushed as the current scene, and
## Back, Close and Done each ask for the title (`is_going_home()`). The scene
## swap itself is engine navigation the scripted tree owns, so it is asserted as
## the request, not performed.
func _home_from_title() -> void:
	for way: String in ["back", "close", "done"]:
		var panel: Control = await _fresh_panel(FRAMES[0], false)
		panel.call("set_standalone", true)
		await _settle(0.2)
		if not bool(panel.call("is_gate_card_visible")):
			_fail.append("title (%s): the standalone panel does not show the gate card" % way)
			return
		var closes: Array = [0]
		var backs: Array = [0]
		panel.connect("closed", func() -> void: closes[0] += 1)
		panel.connect("back_requested", func() -> void: backs[0] += 1)
		if way == "back":
			await _tap(_center_of(panel.find_child("GateBackButton", true, false) as Control))
			if backs[0] != 1:
				_fail.append("title (back): back_requested emitted %d time(s)" % backs[0])
		else:
			await _hold_for_three_seconds(panel.find_child("GateHold", true, false) as Control, "title (%s)" % way)
			if not bool(panel.call("is_panel_visible")):
				_fail.append("title (%s): the hold did not open the settings" % way)
				return
			var button_name: String = "CloseButton" if way == "close" else "DoneButton"
			await _tap(_center_of(panel.find_child(button_name, true, false) as Control))
			if closes[0] != 1 or bool(panel.call("is_panel_visible")):
				_fail.append("title (%s): closed %d, panel visible=%s" % [way, closes[0], str(panel.call("is_panel_visible"))])
		if not bool(panel.call("is_going_home")):
			_fail.append("title (%s): the panel did not ask for the title screen" % way)
	_finish()


## Music and the three voice sliders: a real tap on the track changes the mixer
## at once (through the `Audio`, `TtsService` and `Voice` autoloads), persists
## through the real SaveService, survives a relaunch (a new SaveService reading
## the file back, a new panel showing it), and is what the consumers read.
func _sliders_apply_and_persist() -> void:
	var services: Dictionary = _attach_services()
	var save: Node = services["save"]
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var targets: Array = [
		["MusicSlider", 0.30, "musicVolume"],
		["VoiceVolumeSlider", 0.40, "voiceVolume"],
		["AlizVoiceSlider", 0.60, "alizVoiceVolume"],
		["BunnyVoiceSlider", 0.20, "bunnyVoiceVolume"],
	]
	var chosen: Dictionary = {}
	for target: Array in targets:
		var slider: HSlider = panel.find_child(String(target[0]), true, false) as HSlider
		await _bring_into_view(panel, slider)
		var rect: Rect2 = slider.get_global_rect()
		await _tap(Vector2(rect.position.x + rect.size.x * float(target[1]), rect.get_center().y))
		var value: float = slider.value
		chosen[String(target[2])] = value
		if absf(value - float(target[1])) > 0.1:
			_fail.append("sliders: a tap %.0f%% along %s set %.2f" % [float(target[1]) * 100.0, String(target[0]), value])
		var stored: float = _setting_number(save, String(target[2]))
		if absf(stored - value) > 0.001:
			_fail.append("sliders: %s shows %.2f but the profile holds %s=%.2f" % [String(target[0]), value, String(target[2]), stored])
	# The mixer, at once.
	var audio: FakeAudio = services["audio"]
	var tts: FakeTts = services["tts"]
	var voice: FakeVoice = services["voice"]
	if absf(audio.music - float(chosen["musicVolume"])) > 0.001:
		_fail.append("sliders: Audio.set_music_volume_linear got %.2f, slider %.2f" % [audio.music, float(chosen["musicVolume"])])
	if absf(tts.voice - float(chosen["voiceVolume"])) > 0.001:
		_fail.append("sliders: TtsService.set_voice_volume got %.2f, slider %.2f" % [tts.voice, float(chosen["voiceVolume"])])
	if absf(float(voice.levels.get("aliz", -1.0)) - float(chosen["alizVoiceVolume"])) > 0.001:
		_fail.append("sliders: Voice.set_character_volume(aliz) got %.2f, slider %.2f" % [float(voice.levels.get("aliz", -1.0)), float(chosen["alizVoiceVolume"])])
	if absf(float(voice.levels.get("bunny", -1.0)) - float(chosen["bunnyVoiceVolume"])) > 0.001:
		_fail.append("sliders: Voice.set_character_volume(bunny) got %.2f, slider %.2f" % [float(voice.levels.get("bunny", -1.0)), float(chosen["bunnyVoiceVolume"])])

	# Relaunch: the file read back by a new SaveService, shown by a new panel.
	if not FileAccess.file_exists(SCRATCH_PROFILE):
		_fail.append("sliders: nothing was written to %s" % SCRATCH_PROFILE)
	var relaunched: Node = _relaunch_save_service()
	for key: String in chosen.keys():
		var stored: float = _setting_number(relaunched, key)
		if absf(stored - float(chosen[key])) > 0.001:
			_fail.append("sliders: after relaunch %s reads %.2f, expected %.2f" % [key, stored, float(chosen[key])])
	_viewport.remove_child(panel)
	panel.free()
	var again: Control = await _add_panel(true)
	for target: Array in targets:
		var slider: HSlider = again.find_child(String(target[0]), true, false) as HSlider
		if absf(slider.value - float(chosen[String(target[2])])) > 0.001:
			_fail.append("sliders: after relaunch %s shows %.2f, expected %.2f" % [String(target[0]), slider.value, float(chosen[String(target[2])])])
	var music_value: Label = again.find_child("MusicValue", true, false) as Label
	var expected_label: String = "%d%%" % int(round(float(chosen["musicVolume"]) * 100.0))
	if music_value.text != expected_label:
		_fail.append("sliders: after relaunch the music value reads '%s', expected '%s'" % [music_value.text, expected_label])

	# The consumers' own readers, on a fresh instance each, as at launch.
	var tts_reader: Node = (load(TTS_SERVICE_SCRIPT) as GDScript).new()
	var tts_level: float = float(tts_reader.call("get_voice_volume"))
	if absf(tts_level - float(chosen["alizVoiceVolume"])) > 0.001:
		_fail.append("sliders: TtsService.get_voice_volume() at launch reads %.2f, expected Aliz's %.2f" % [tts_level, float(chosen["alizVoiceVolume"])])
	tts_reader.free()
	var voice_reader: Node = (load(VOICE_DIRECTOR_SCRIPT) as GDScript).new()
	var bunny_level: float = float(voice_reader.call("get_character_volume", "bunny"))
	var aliz_level: float = float(voice_reader.call("get_character_volume", "aliz"))
	if absf(bunny_level - float(chosen["bunnyVoiceVolume"])) > 0.001 or absf(aliz_level - float(chosen["alizVoiceVolume"])) > 0.001:
		_fail.append("sliders: VoiceDirector at launch reads aliz %.2f / bunny %.2f, expected %.2f / %.2f"
				% [aliz_level, bunny_level, float(chosen["alizVoiceVolume"]), float(chosen["bunnyVoiceVolume"])])
	voice_reader.free()
	_finish()


## A tap on a helper-language button changes the second line under every row
## at once, persists as `helperLanguage`, and is selected again after a relaunch.
## Off hides the lines. Thai also shows the Thai privacy block.
func _language_updates_and_persists() -> void:
	var services: Dictionary = _attach_services()
	var save: Node = services["save"]
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var code: String = ""
	for candidate: String in ["ja", "zh", "hi", "ar"]:
		if HelperFont.language_available(candidate):
			code = candidate
			break
	if code.is_empty():
		_fail.append("language: this machine can draw none of ja/zh/hi/ar; no button to tap")
		return
	var button: Button = panel.find_child("Helper%sButton" % code.capitalize(), true, false) as Button
	var music_helper: Label = panel.find_child("MusicHelper", true, false) as Label
	var speed_helper: Label = panel.find_child("SpeedHelper", true, false) as Label
	await _bring_into_view(panel, button)
	await _tap(_center_of(button))
	if String(save.call("get_setting", "helperLanguage", "")) != code:
		_fail.append("language: tapping %s stored helperLanguage=%s" % [code, str(save.call("get_setting", "helperLanguage", ""))])
	if save.call("get_setting", "thaiHints", null) != true:
		_fail.append("language: thaiHints was not kept in step (true) for %s" % code)
	var expected: String = L10n.helper("music_volume", "")
	if L10n.helper_language() != code or expected.is_empty():
		_fail.append("language: Localization is '%s' after the tap (expected %s), music line '%s'" % [L10n.helper_language(), code, expected])
	if not music_helper.visible or music_helper.text != expected:
		_fail.append("language: the Music second line reads '%s' (visible %s), expected '%s'" % [music_helper.text, str(music_helper.visible), expected])
	if not speed_helper.visible or speed_helper.text != L10n.helper("speaking_speed", ""):
		_fail.append("language: the Speed second line did not follow (%s / '%s')" % [str(speed_helper.visible), speed_helper.text])

	var thai_block: Control = panel.find_child("AlizPrivacyThai", true, false) as Control
	if thai_block != null and thai_block.visible:
		_fail.append("language: the Thai privacy block is showing under %s" % code)
	if HelperFont.language_available("th"):
		var th: Button = panel.find_child("HelperThButton", true, false) as Button
		await _tap(_center_of(th))
		if thai_block == null or not thai_block.visible:
			_fail.append("language: Thai did not show the Thai privacy block")
		if music_helper.text != L10n.helper("music_volume", "") or L10n.helper_language() != "th":
			_fail.append("language: Thai did not update the Music second line")

	var off: Button = panel.find_child("HelperOffButton", true, false) as Button
	await _tap(_center_of(off))
	if String(save.call("get_setting", "helperLanguage", "")) != "off" or save.call("get_setting", "thaiHints", null) != false:
		_fail.append("language: Off stored helperLanguage=%s thaiHints=%s" % [str(save.call("get_setting", "helperLanguage", "")), str(save.call("get_setting", "thaiHints", null))])
	if music_helper.visible or (thai_block != null and thai_block.visible):
		_fail.append("language: Off left the second line / Thai privacy block showing")

	# Relaunch with the language chosen again.
	await _tap(_center_of(button))
	_relaunch_save_service()
	_viewport.remove_child(panel)
	panel.free()
	var again: Control = await _add_panel(true)
	var again_button: Button = again.find_child("Helper%sButton" % code.capitalize(), true, false) as Button
	var again_helper: Label = again.find_child("MusicHelper", true, false) as Label
	if not again_button.button_pressed:
		_fail.append("language: after relaunch %s is not the selected button" % code)
	if not again_helper.visible or again_helper.text != expected:
		_fail.append("language: after relaunch the Music second line reads '%s', expected '%s'" % [again_helper.text, expected])
	L10n.set_helper_language(L10n.DEFAULT_HELPER_LANGUAGE)
	_finish()


## AI Tutor On/Off and Hands-free On/Off persist, come back after a relaunch,
## and are what the classroom (`tutor_scene.gd`) and the title (`main.gd`) read.
func _tutor_toggles_persist() -> void:
	var services: Dictionary = _attach_services()
	var save: Node = services["save"]
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var tutor_off: Button = panel.find_child("AiTutorOffButton", true, false) as Button
	var tutor_on: Button = panel.find_child("AiTutorOnButton", true, false) as Button
	var hands_off: Button = panel.find_child("HandsFreeOffButton", true, false) as Button
	if tutor_off == null or tutor_on == null or hands_off == null:
		_fail.append("tutor: the AI Tutor / Hands-free toggles are missing")
		return
	await _bring_into_view(panel, tutor_off)
	await _tap(_center_of(tutor_off))
	if save.call("get_setting", "aiTutorEnabled", null) != false or not tutor_off.button_pressed:
		_fail.append("tutor: AI Tutor Off stored aiTutorEnabled=%s (button pressed %s)" % [str(save.call("get_setting", "aiTutorEnabled", null)), str(tutor_off.button_pressed)])
	await _bring_into_view(panel, hands_off)
	await _tap(_center_of(hands_off))
	if save.call("get_setting", "handsFreeMode", null) != false or not hands_off.button_pressed:
		_fail.append("tutor: Hands-free Off stored handsFreeMode=%s" % str(save.call("get_setting", "handsFreeMode", null)))

	# The classroom's own reader.
	var classroom: Node = (load(TUTOR_SCENE_SCRIPT) as GDScript).new()
	if bool(classroom.call("_hands_free_setting")):
		_fail.append("tutor: the classroom still reads hands-free ON after the grown-up switched it off")
	classroom.free()
	# The title's own reader (Learn with Aliz is offered only while the tutor is on).
	var menu: Node = (load(MAIN_MENU_SCRIPT) as GDScript).new()
	if TutorFlags.local_tutor_enabled() and ResourceLoader.exists(TUTOR_CLASSROOM_SCENE):
		if bool(menu.call("tutor_available")):
			_fail.append("tutor: the title still offers Learn with Aliz after AI Tutor Off")
		await _bring_into_view(panel, tutor_on)
		await _tap(_center_of(tutor_on))
		if not bool(menu.call("tutor_available")) or save.call("get_setting", "aiTutorEnabled", null) != true:
			_fail.append("tutor: AI Tutor On did not bring Learn with Aliz back on the title")
		await _tap(_center_of(tutor_off))
	menu.free()

	# Relaunch: both Off again.
	_relaunch_save_service()
	_viewport.remove_child(panel)
	panel.free()
	var again: Control = await _add_panel(true)
	if not (again.find_child("AiTutorOffButton", true, false) as Button).button_pressed:
		_fail.append("tutor: after relaunch AI Tutor is not shown Off")
	if not (again.find_child("HandsFreeOffButton", true, false) as Button).button_pressed:
		_fail.append("tutor: after relaunch Hands-free is not shown Off")
	_finish()


## Privacy information is three static labels: the exact sentence the guards
## depend on, no link, no button, reachable by scrolling.
func _privacy_is_static() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var box: Control = panel.find_child("AlizPrivacyBox", true, false) as Control
	var title: Label = panel.find_child("AlizPrivacyTitle", true, false) as Label
	if box == null or title == null or title.text != "Privacy information":
		_fail.append("privacy: no 'Privacy information' section")
		return
	if not bool(panel.call("is_aliz_privacy_visible")):
		_fail.append("privacy: the section is not on screen while the panel is open")
	var lines: PackedStringArray = panel.call("aliz_privacy_lines")
	var shown: PackedStringArray = PackedStringArray()
	for index: int in range(lines.size()):
		var label: Label = box.find_child("AlizPrivacyLine%d" % index, false, false) as Label
		if label == null or label.text != lines[index]:
			_fail.append("privacy: line %d is missing or differs from the reviewed copy" % index)
			continue
		shown.append(label.text)
	var text: String = "\n".join(shown)
	if text.find(PRIVACY_SENTENCE) < 0:
		_fail.append("privacy: the sentence '%s' is not on screen verbatim" % PRIVACY_SENTENCE)
	for marker: String in ["http", "www.", "://"]:
		if text.find(marker) >= 0:
			_fail.append("privacy: the text contains '%s'; it must be link-free" % marker)
	for node: Node in box.find_children("*", "", true, false):
		if node is BaseButton or node is RichTextLabel:
			_fail.append("privacy: %s (%s) inside the privacy section; it must be static" % [node.name, node.get_class()])
	await _bring_into_view(panel, box)
	if not _viewport.get_visible_rect().encloses(box.get_global_rect()):
		_fail.append("privacy: scrolled into view, the section %s still does not fit the frame %s" % [str(box.get_global_rect()), str(_viewport.get_visible_rect())])
	_finish()


## Delete learning history (two taps; stars untouched) and Reset progress (the
## hold-to-erase bar; a tap does nothing, Keep my stars cancels, a 3 s hold
## erases), against the real SaveService, then read back from disk.
func _delete_history_and_reset() -> void:
	var services: Dictionary = _attach_services()
	var save: Node = services["save"]
	save.call("add_stars", 3)
	save.call("set_setting", "tutorProgress", {"lesson_a": {"completed": true, "stars": 2, "completedAt": 1758400000}})
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var status: Label = panel.find_child("StatusLabel", true, false) as Label
	var stars_label: Label = panel.find_child("StarsLabel", true, false) as Label
	if stars_label.text != "3 stars earned":
		_fail.append("erase: the footer reads '%s' with 3 stars saved" % stars_label.text)

	var delete: Button = panel.find_child("AlizDeleteHistoryButton", true, false) as Button
	await _bring_into_view(panel, delete)
	await _tap(_center_of(delete))
	if not bool(panel.call("is_aliz_delete_armed")):
		_fail.append("erase: the first tap did not arm Delete learning history")
	var progress: Variant = save.call("get_setting", "tutorProgress", {})
	if typeof(progress) != TYPE_DICTIONARY or (progress as Dictionary).is_empty():
		_fail.append("erase: the FIRST tap already deleted the learning history")
	await _tap(_center_of(delete))
	progress = save.call("get_setting", "tutorProgress", {})
	if bool(panel.call("is_aliz_delete_armed")) or typeof(progress) != TYPE_DICTIONARY or not (progress as Dictionary).is_empty():
		_fail.append("erase: the second tap did not delete the learning history (armed %s, progress %s)" % [str(panel.call("is_aliz_delete_armed")), str(progress)])
	if int(save.call("get_stars")) != 3 or stars_label.text != "3 stars earned":
		_fail.append("erase: Delete learning history touched the stars (%d, '%s')" % [int(save.call("get_stars")), stars_label.text])
	if not status.visible or status.text.find("Stars and stickers are untouched") < 0:
		_fail.append("erase: after the delete the status reads '%s'" % status.text)

	var reset: Button = panel.find_child("ResetButton", true, false) as Button
	var confirm_box: Control = panel.find_child("ConfirmBox", true, false) as Control
	var hold: Control = panel.find_child("ConfirmHold", true, false) as Control
	var cancel: Button = panel.find_child("CancelResetButton", true, false) as Button
	await _tap(_center_of(reset))
	if not confirm_box.is_visible_in_tree() or reset.is_visible_in_tree():
		_fail.append("erase: Reset did not swap in the confirmation")
	await _tap(_center_of(hold))
	if int(save.call("get_stars")) != 3:
		_fail.append("erase: a TAP on the hold-to-erase bar erased the stars")
	await _tap(_center_of(cancel))
	if confirm_box.is_visible_in_tree() or not reset.is_visible_in_tree() or int(save.call("get_stars")) != 3:
		_fail.append("erase: Keep my stars did not cancel cleanly (stars %d)" % int(save.call("get_stars")))
	await _tap(_center_of(reset))
	await _hold_for_three_seconds(hold, "erase")
	if int(save.call("get_stars")) != 0 or stars_label.text != "0 stars earned":
		_fail.append("erase: a 3 s hold left %d star(s) ('%s')" % [int(save.call("get_stars")), stars_label.text])
	if confirm_box.is_visible_in_tree() or not status.visible or status.text.find("Progress reset") < 0:
		_fail.append("erase: after the hold the confirmation/status is wrong ('%s')" % status.text)
	var relaunched: Node = _relaunch_save_service()
	if int(relaunched.call("get_stars")) != 0:
		_fail.append("erase: after relaunch the profile still has %d star(s)" % int(relaunched.call("get_stars")))
	_finish()


## No dead overlay, at phone and tablet sizes: in every state the panel can be
## in there is a way back on screen without scrolling, and while anything but
## the bare gear is showing, the world behind (a full-screen button under the
## overlay) never receives a touch. While only the gear shows, touches DO pass
## through to the world.
func _no_dead_overlay(frame: Vector2i) -> void:
	_open_viewport(frame)
	var tag: String = "%dx%d" % [frame.x, frame.y]
	var world := Button.new()
	world.name = "WorldBehind"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var world_taps: Array = [0]
	world.pressed.connect(func() -> void: world_taps[0] += 1)
	_viewport.add_child(world)
	var panel: Control = await _add_panel(false)
	var visible_rect: Rect2 = _viewport.get_visible_rect()
	var outside_card: Vector2 = Vector2(40.0, visible_rect.size.y - 40.0)
	var closes: Array = [0]
	panel.connect("closed", func() -> void: closes[0] += 1)

	# Locked gear: on screen, and the world is live.
	var gear: Control = panel.find_child("EntryGate", true, false) as Control
	if not visible_rect.encloses(gear.get_global_rect()):
		_fail.append("%s: the gear %s is off screen" % [tag, str(gear.get_global_rect())])
	await _tap(visible_rect.get_center())
	if world_taps[0] != 1:
		_fail.append("%s: with only the gear showing, a tap did not reach the world (%d)" % [tag, world_taps[0]])

	# The gear-tapped card and the standalone card (the pause card's card gets
	# its own instance below: a host takes that one down on Back / Done).
	var back: Button = panel.find_child("GateBackButton", true, false) as Button
	var world_before: int = world_taps[0]
	for way: String in ["gear", "standalone"]:
		match way:
			"gear":
				await _tap(_center_of(gear))
			"standalone":
				panel.call("set_standalone", true)
		await _settle(0.2)
		if not bool(panel.call("is_gate_card_visible")):
			_fail.append("%s: the %s gate card is not showing" % [tag, way])
			continue
		if not back.is_visible_in_tree() or not visible_rect.encloses(back.get_global_rect()):
			_fail.append("%s: the %s gate card's Back %s is off screen" % [tag, way, str(back.get_global_rect())])
		for point: Vector2 in [outside_card, Vector2(visible_rect.size.x - 40.0, 40.0), visible_rect.get_center() + Vector2(0.0, 400.0)]:
			await _tap(point)
		if world_taps[0] != world_before:
			_fail.append("%s: taps around the %s gate card reached the world (%d)" % [tag, way, world_taps[0] - world_before])
		if way == "gear":
			await _tap(_center_of(back))
			if bool(panel.call("is_gate_card_visible")):
				_fail.append("%s: Back on the gear card did not put the gear back" % tag)
	panel.call("set_standalone", false)

	# The open panel: Close and Done on screen at scroll 0 and after scrolling to
	# the end; no tap anywhere reaches the world.
	panel.call("open_settings")
	await _settle(0.3)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var close: Button = panel.find_child("CloseButton", true, false) as Button
	var done: Button = panel.find_child("DoneButton", true, false) as Button
	if scroll.scroll_vertical != 0 or not visible_rect.encloses(close.get_global_rect()):
		_fail.append("%s: Close %s is not on screen when the panel opens" % [tag, str(close.get_global_rect())])
	if not visible_rect.encloses(done.get_global_rect()):
		_fail.append("%s: Done %s is not on screen when the panel opens" % [tag, str(done.get_global_rect())])
	var stars: Control = panel.find_child("StarsLabel", true, false) as Control
	for point: Vector2 in [Vector2(8.0, 8.0), Vector2(visible_rect.size.x - 8.0, visible_rect.size.y * 0.5), _center_of(stars), _center_of(panel.find_child("MusicTitle", true, false) as Control)]:
		await _tap(point)
	if world_taps[0] != world_before:
		_fail.append("%s: taps on the open panel reached the world (%d)" % [tag, world_taps[0] - world_before])
	if closes[0] != 0 or not bool(panel.call("is_panel_visible")):
		_fail.append("%s: a tap on the panel's chrome closed it" % tag)
	scroll.scroll_vertical = 100000
	await _settle(0.2)
	if not visible_rect.encloses(done.get_global_rect()):
		_fail.append("%s: scrolled to the end, Done %s left the screen" % [tag, str(done.get_global_rect())])
	await _tap(_center_of(done))
	if closes[0] != 1:
		_fail.append("%s: Done did not close the panel (%d)" % [tag, closes[0]])
	# Back to the gear: the world is live again.
	await _tap(visible_rect.get_center())
	if world_taps[0] != world_before + 1:
		_fail.append("%s: after Done the world does not get taps again (%d)" % [tag, world_taps[0] - world_before])
	world_before = world_taps[0]

	# The pause card's card, on its own overlay instance over the same world.
	var requested: Control = await _add_panel(false)
	requested.call("show_gate_card")
	await _settle(0.2)
	var requested_closes: Array = [0]
	requested.connect("closed", func() -> void: requested_closes[0] += 1)
	var requested_back: Button = requested.find_child("GateBackButton", true, false) as Button
	if not bool(requested.call("is_gate_card_visible")):
		_fail.append("%s: the pause card's gate card is not showing" % tag)
	elif not requested_back.is_visible_in_tree() or not visible_rect.encloses(requested_back.get_global_rect()):
		_fail.append("%s: the pause card's gate card's Back %s is off screen" % [tag, str(requested_back.get_global_rect())])
	for point: Vector2 in [outside_card, Vector2(visible_rect.size.x - 40.0, 40.0), visible_rect.get_center() + Vector2(0.0, 400.0)]:
		await _tap(point)
	if world_taps[0] != world_before:
		_fail.append("%s: taps around the pause card's gate card reached the world (%d)" % [tag, world_taps[0] - world_before])
	await _tap(_center_of(requested_back))
	if requested_closes[0] != 1:
		_fail.append("%s: Back on the pause card's gate card did not tell the host (closed %d)" % [tag, requested_closes[0]])
	_finish()
