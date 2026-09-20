extends SceneTree

## THE TITLE SCREEN, PHOTOGRAPHED at the pixel size it claims. Dev-only.
##
##   Godot --path game --script res://tests/shots_menu.gd -- menu_wow_ipad 1334x750
##   Godot --path game --script res://tests/shots_menu.gd -- menu_wow_iphone 2340x1080
##   Godot --path game --script res://tests/shots_menu.gd -- menu_wow_pressed 1334x750 pressed
##   Godot --path game --script res://tests/shots_menu.gd -- menu_depart_walk 1334x750 depart 0.3
##   Godot --path game --script res://tests/shots_menu.gd -- menu_depart_carry 1334x750 depart 1.0
##   Godot --path game --script res://tests/shots_menu.gd -- menu_depart_door 1334x750 depart 2.05
##   Godot --path game --script res://tests/shots_menu.gd -- dress_up_mint 1334x750 dressup mint
##
## `depart <seconds>` presses Start and then drives the walk home by hand to
## that moment (`menu_departure.gd::advance()`), so the frame is the same one
## a child sees at that second. `dressup <swatch>` photographs the Dress Up
## screen with that swatch applied.
##
## ## Why a SubViewport, and why `size_2d_override`
##
## `--resolution 2340x1080` is a request the window manager clamps (1686x935 on
## this machine), so the generic harness cannot photograph a true iPhone frame.
## The menu is therefore hosted in a `SubViewport` of exactly the asked-for
## pixel size and captured from its texture, and the size is asserted against
## the PNG afterwards -- the same discipline as `shots_rc.gd`.
##
## The project stretches its UI (`canvas_items` / `expand`, 1366x1024 base), so
## on a real device the CanvasLayer lays out in a 1024-tall design space and is
## scaled onto the pixels. A bare SubViewport would skip that and draw the UI at
## 1:1, which is a different (and smaller) menu than the one a child sees. So
## `size_2d_override` is set to the design-space size at the frame's aspect and
## `size_2d_override_stretch` is on -- which is exactly what `Window` does.
##
## `SaveService` is detached for the run, so the menu comes up as a fresh
## family's ("Start", no first-run hand-off) and never reads or writes a real
## profile on this machine.

const OUT_DIR: String = "docs/shots/"
const DESIGN_HEIGHT: int = 1024

var _name: String = "menu_wow"
var _frame: Vector2i = Vector2i(1334, 750)
var _mode: String = ""
var _mode_arg: String = ""
var _viewport: SubViewport = null
var _menu: Node = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[0]).strip_edges().is_empty():
		_name = String(args[0]).strip_edges()
	if args.size() > 1:
		var wide: PackedStringArray = String(args[1]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))
	if args.size() > 2:
		_mode = String(args[2]).strip_edges()
	if args.size() > 3:
		_mode_arg = String(args[3]).strip_edges()
	print("=== title screen, %dx%d -> %s%s.png ===" % [_frame.x, _frame.y, OUT_DIR, _name])

	await process_frame
	# Autoloads are not on `root` until a frame has passed.
	var save: Node = root.get_node_or_null("SaveService")
	if save != null:
		root.remove_child(save)

	_viewport = SubViewport.new()
	_viewport.size = _frame
	var design_width: int = int(round(float(_frame.x) * float(DESIGN_HEIGHT) / float(_frame.y)))
	_viewport.size_2d_override = Vector2i(design_width, DESIGN_HEIGHT)
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	var scene_path: String = "res://scenes/main/main.tscn"
	if _mode == "dressup":
		scene_path = "res://scenes/dress_up/dress_up.tscn"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return _die("%s will not load" % scene_path)
	_menu = packed.instantiate()
	_viewport.add_child(_menu)
	await _settle(1.2)

	if _mode == "dressup":
		if not _mode_arg.is_empty() and _menu.has_method("apply_swatch"):
			if not bool(_menu.call("apply_swatch", _mode_arg, false)):
				_fail.append("'%s' is not a swatch" % _mode_arg)
		await _settle(0.3)
		_report_dress_up()
		await _shot(_name)
		if save != null:
			root.add_child(save)
		_finish()
		return

	if _mode == "depart":
		var play: Button = _menu.get_node_or_null("UI/SafeArea/PlayButton") as Button
		if play == null:
			_fail.append("no PlayButton to press")
		else:
			# The real press, then the walk driven by hand to the asked-for
			# second. `_process` is switched off so it does not ALSO advance it.
			_menu.set_process(false)
			play.pressed.emit()
			var departure: Node = _menu.call("get_departure") if _menu.has_method("get_departure") else null
			if departure == null:
				_fail.append("pressing Start started no departure")
			else:
				var at: float = float(_mode_arg) if _mode_arg.is_valid_float() else 1.0
				var stepped: float = 0.0
				while stepped < at:
					var step: float = minf(1.0 / 60.0, at - stepped)
					departure.call("advance", step)
					stepped += step
					if stepped >= at:
						break
				print("  departure: phase=%s elapsed=%.2f carried=%s cover=%.2f" % [
					String(departure.call("get_phase")), float(departure.call("get_elapsed")),
					str(departure.call("is_bunny_carried")), float(departure.call("get_cover_alpha"))])
				# The wrappers' animation players advance with the frames the
				# settle below gives them; the walk itself is parked at `at`.
			await _settle(0.35)

	if _mode == "pressed":
		# Hold Play down for the picture: the squish and the pressed frame are
		# the press feedback, and they have to be seen to be judged.
		var play: Button = _menu.get_node_or_null("UI/SafeArea/PlayButton") as Button
		if play == null:
			_fail.append("no PlayButton to press")
		else:
			play.button_down.emit()
			play.set_pressed_no_signal(true)
			await _settle(0.3)

	_report()
	await _shot(_name)

	if save != null:
		root.add_child(save)
	_finish()


func _finish() -> void:
	if _fail.is_empty():
		print("\nMENU SHOT OK")
		quit(0)
	else:
		print("\nMENU SHOT FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


func _report_dress_up() -> void:
	if _menu.has_method("is_model_available"):
		print("  Aliz model available = %s" % str(_menu.call("is_model_available")))
		if not bool(_menu.call("is_model_available")):
			_fail.append("Dress Up has no Aliz model in this checkout")
	if _menu.has_method("get_current_swatch"):
		print("  swatch: %s  accent colour: %s" % [
			String(_menu.call("get_current_swatch")), str(_menu.call("get_accent_colour"))])
	var back: Button = _menu.get_node_or_null("UI/SafeArea/BackButton") as Button
	if back == null:
		_fail.append("Dress Up has no Back button")


## What is actually in the frame, printed, so the picture carries its own label.
func _report() -> void:
	var names: Array = []
	for child: Node in _menu.get_children():
		if child is Node3D and not (child is Camera3D) and not (child is Light3D):
			names.append(String(child.name))
	print("  3D children: %s" % str(names))
	var garden: Node = _menu.get_node_or_null("Garden")
	if garden != null and garden.has_method("describe"):
		print("  garden: %s" % str(garden.call("describe")))
		print("  garden triangles: %d" % int(garden.call("count_triangles")))
	for who: String in ["BigBuddy", "Bunny"]:
		var node: Node = _menu.get_node_or_null(who)
		if node == null:
			print("  %s: ABSENT" % who)
			_fail.append("%s is not in the scene" % who)
		elif node.has_method("is_model_available"):
			print("  %s: model available = %s" % [who, str(node.call("is_model_available"))])
			if not bool(node.call("is_model_available")):
				_fail.append("%s has no model in this checkout" % who)
	# The pair and nobody else (owner review, 2026-09-20).
	if _menu.get_node_or_null("LittleBuddy") != null:
		_fail.append("a LittleBuddy stand-in is on the title screen; the menu shows Aliz and Bunny only")
	var lights: int = 0
	_count_lights(_menu, [lights])
	var play: Button = _menu.get_node_or_null("UI/SafeArea/PlayButton") as Button
	if play != null:
		var caption: Label = play.get_node_or_null("PlayCaption") as Label
		print("  play caption: '%s'" % (caption.text if caption != null else play.text))


func _count_lights(node: Node, acc: Array) -> void:
	if node is DirectionalLight3D:
		acc[0] += 1
		print("  DirectionalLight3D shadow_enabled=%s" % str((node as DirectionalLight3D).shadow_enabled))
	for child: Node in node.get_children():
		_count_lights(child, acc)


func _shot(out_name: String) -> void:
	# Drawn ON DEMAND rather than awaited: macOS stops the ordinary draw loop
	# while the window is occluded and `frame_post_draw` then never fires
	# (see `shots_bubble.gd`). The SubViewport renders when asked either way.
	await process_frame
	RenderingServer.force_draw(true, 0.0)
	var image: Image = _viewport.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + out_name + ".png")
	var err: int = image.save_png(path)
	print("  %s %s.png  %dx%d" % [
		"shot" if err == OK else "FAIL", out_name, image.get_width(), image.get_height()])
	if err != OK:
		_fail.append("could not write %s.png" % out_name)
	if Vector2i(image.get_width(), image.get_height()) != _frame:
		_fail.append("%s.png is %dx%d but %dx%d was asked for"
				% [out_name, image.get_width(), image.get_height(), _frame.x, _frame.y])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _die(why: String) -> void:
	print("  FATAL: %s" % why)
	quit(1)
