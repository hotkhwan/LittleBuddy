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
## same position. Nothing here is a claim about a physical device.
##
## Owner playtest bug, 2026-09-21: "Settings opens, but the contents cannot
## scroll; the last option cannot be reached." and "the Baby Room gear: a tap
## does nothing." Each scenario below is one of those, or one of the fixes'
## side conditions (a plain tap still works; a slider still drags sideways).

const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
const DESIGN_HEIGHT: int = 1024
const FRAMES: Array = [Vector2i(1334, 750), Vector2i(2340, 1080)]
## Detached for the run, as `run_tests.gd` does, so nothing here can reach a real
## profile or the mixer.
const PROJECT_AUTOLOADS: Array = ["SaveService", "SpeechService", "TtsService", "Voice", "Sfx", "Audio"]

var _fail: Array = []
var _viewport: SubViewport = null
var _last_pointer: Vector2 = Vector2.ZERO


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	for autoload_name: String in PROJECT_AUTOLOADS:
		var node: Node = root.get_node_or_null(NodePath(autoload_name))
		if node != null:
			root.remove_child(node)

	for frame: Vector2i in FRAMES:
		await _footer_reachable(frame)
	await _scroll_from_slider()
	await _scroll_from_button()
	await _taps_still_work()
	await _slider_still_drags()
	await _gear_tap_and_hold()

	if _fail.is_empty():
		print("\nINPUT SETTINGS OK")
		quit(0)
	else:
		print("\nINPUT SETTINGS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


# -- scaffolding ---------------------------------------------------------------

func _open_viewport(frame: Vector2i) -> void:
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
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = pos
	_viewport.push_input(touch, true)


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
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = pos
	drag.relative = relative
	_viewport.push_input(drag, true)


func _touch_up(pos: Vector2) -> void:
	_last_pointer = pos
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	mouse.position = pos
	mouse.global_position = pos
	_viewport.push_input(mouse, true)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
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
		_close_viewport()
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
	_close_viewport()


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
	_close_viewport()


## (a, again) A vertical drag that starts on an option BUTTON scrolls and does
## not press the button.
func _scroll_from_button() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var button: Button = panel.find_child("VoiceOffButton", true, false) as Button
	var presses: Array = [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	var was_pressed: bool = button.button_pressed
	await _swipe(_center_of(button), Vector2(0.0, -260.0))
	if scroll.scroll_vertical < 120:
		_fail.append("button swipe: the panel scrolled only %d px" % scroll.scroll_vertical)
	if presses[0] != 0 or button.button_pressed != was_pressed:
		_fail.append("button swipe: the finger scrolled away and Voice Off still fired (%d) / toggled (%s)" % [presses[0], str(button.button_pressed)])
	if button.is_pressed() != was_pressed:
		_fail.append("button swipe: the button is stuck down after the scroll")
	_close_viewport()


## (b) A plain tap still reaches a button, and still reaches a slider track.
func _taps_still_work() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], true)
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	# Voice practice: Off -- above the fold at every frame here, unselected by
	# default, and never disabled (a helper-language button can be, when the
	# machine has no font for it).
	var off: Button = panel.find_child("VoiceOffButton", true, false) as Button
	if not scroll.get_global_rect().encloses(off.get_global_rect()):
		_fail.append("tap: VoiceOffButton %s is not fully inside the scroll area %s; pick another target" % [str(off.get_global_rect()), str(scroll.get_global_rect())])
	var presses: Array = [0]
	off.pressed.connect(func() -> void: presses[0] += 1)
	await _tap(_center_of(off))
	if presses[0] != 1 or not off.button_pressed:
		_fail.append("tap: Voice Off fired %d time(s), selected=%s; a tap must still press a button" % [presses[0], str(off.button_pressed)])
	if scroll.scroll_vertical != 0:
		_fail.append("tap: a tap scrolled the panel by %d" % scroll.scroll_vertical)

	var slider: HSlider = panel.find_child("MusicSlider", true, false) as HSlider
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
	_close_viewport()


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
	_close_viewport()


## (d) The Baby Room's corner gear: a TAP opens the gate card; a hold on the
## card's bar unlocks; the hold survives finger jitter; Back and Done return to
## the gear.
func _gear_tap_and_hold() -> void:
	var panel: Control = await _fresh_panel(FRAMES[0], false)
	var gear: Control = panel.find_child("EntryGate", true, false) as Control
	if gear == null or not gear.is_visible_in_tree():
		_fail.append("gear: the corner gear is not showing in overlay mode")
		_close_viewport()
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
		_close_viewport()
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
		_close_viewport()
		return
	var hold_center: Vector2 = _center_of(hold)
	_touch_down(hold_center)
	await process_frame
	if not bool(hold.call("is_holding")):
		_fail.append("gear: a real press on the card's bar did not start the hold")
	# Real frames for a moment, then the rest of the 3 s driven directly, so the
	# harness does not spend three wall-clock seconds per run.
	await _settle(0.2)
	if not bool(hold.call("is_holding")) or float(hold.call("get_progress")) <= 0.0:
		_fail.append("gear: the hold did not advance while pressed (progress %.2f)" % float(hold.call("get_progress")))
	hold.call("advance", 3.0)
	await process_frame
	_touch_up(hold_center)
	await process_frame
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
	_close_viewport()
