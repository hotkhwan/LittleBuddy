extends RefCounted

## The splash shows the logo, never blocks, never traps, and hands over to the
## menu by path.
##
##   * `should_leave()` -- the whole timing contract as a pure function: not
##     before `MIN_SHOW_SEC` even when loaded, as soon as loaded after that, at
##     `MAX_SHOW_SEC` regardless, and at once on a tap;
##   * the scene itself, stepped by hand: it requests a THREADED load of
##     `main.tscn` (never `load()` on the main thread from `_ready`), leaves
##     through the cream curtain, and hands the injected changer either the
##     loaded `PackedScene` or the path -- always `res://scenes/main/main.tscn`,
##     which is the path every menu test already loads;
##   * a tap skips ahead;
##   * the logo node is the drop-in `logo_title.gd` with the shipped texture,
##     and the sway respects `is_processing()`;
##   * nothing on the splash is black.

const SplashScript := preload("res://scripts/branding/splash.gd")
const LogoTitle := preload("res://scripts/branding/logo_title.gd")
const Transition := preload("res://scripts/branding/scene_transition.gd")
const Palette := preload("res://scripts/ui/palette.gd")

const SPLASH_SCENE: String = "res://scenes/splash/splash.tscn"
const MENU_SCENE: String = "res://scenes/main/main.tscn"
const STEP: float = 0.1


func test_name() -> String:
	return "branding_splash"


func run():
	var failures: Array = []
	failures.append_array(_test_timing_contract())
	failures.append_array(_test_scene_hands_over_to_the_menu())
	failures.append_array(_test_tap_skips_ahead())
	failures.append_array(_test_logo_title_drop_in())
	failures.append_array(_test_no_black())
	return failures


func _test_timing_contract():
	var failures: Array = []
	var min_show: float = SplashScript.MIN_SHOW_SEC
	var max_show: float = SplashScript.MAX_SHOW_SEC
	if max_show + Transition.DURATION_IN > 3.0:
		failures.append("MAX_SHOW_SEC %.2f + curtain %.2f is over the 3 s ceiling" % [max_show, Transition.DURATION_IN])
	if min_show < 0.8 or min_show > 1.6:
		failures.append("MIN_SHOW_SEC is %.2f; the logo should hold about 1.2 s" % min_show)
	if SplashScript.should_leave(min_show - 0.01, true, false):
		failures.append("leaves before MIN_SHOW_SEC although loaded; the logo would strobe")
	if not SplashScript.should_leave(min_show, true, false):
		failures.append("loaded and past MIN_SHOW_SEC but does not leave")
	if SplashScript.should_leave(max_show - 0.01, false, false):
		failures.append("leaves before MAX_SHOW_SEC while still loading")
	if not SplashScript.should_leave(max_show, false, false):
		failures.append("still loading at MAX_SHOW_SEC and does not leave; that is a splash that never ends")
	if not SplashScript.should_leave(0.05, false, true):
		failures.append("a tap at 0.05 s does not skip ahead")
	return failures


func _test_scene_hands_over_to_the_menu():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree in the runner"]
	_sweep(tree)
	var splash: Control = _open(failures)
	if splash == null:
		return failures

	var handed: Array = []
	splash.set("scene_changer", func(packed: PackedScene, path: String) -> void:
		handed.append({"packed": packed, "path": path}))

	# The threaded request must be in flight (or already done) right after ready.
	var status: int = ResourceLoader.load_threaded_get_status(MENU_SCENE)
	if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS and status != ResourceLoader.THREAD_LOAD_LOADED:
		failures.append("after _ready() no threaded load of main.tscn is in flight (status %d)" % status)

	# Step until the decision deadline. The curtain goes up first; then the
	# hand-over happens once it is covered.
	var elapsed: float = 0.0
	while elapsed < SplashScript.MAX_SHOW_SEC + 0.2 and Transition.current(tree) == null:
		splash.call("_process", STEP)
		elapsed += STEP
	var curtain: Node = Transition.current(tree)
	if curtain == null:
		failures.append("the splash never raised the curtain by %.1f s" % elapsed)
	else:
		if elapsed < SplashScript.MIN_SHOW_SEC - STEP:
			failures.append("the splash left at %.1f s, before MIN_SHOW_SEC" % elapsed)
		var curtain_steps: int = int(ceil(Transition.DURATION_IN / 0.05)) + 2
		for _i in range(curtain_steps):
			curtain.call("_process", 0.05)
	if handed.size() != 1:
		failures.append("the scene changer was called %d times; expected exactly once" % handed.size())
	else:
		var call: Dictionary = handed[0]
		if String(call["path"]) != MENU_SCENE:
			failures.append("the splash hands over '%s'; the menu is %s" % [call["path"], MENU_SCENE])
		if call["packed"] != null and not (call["packed"] is PackedScene):
			failures.append("the splash handed something that is not a PackedScene")
		if call["packed"] != null and (call["packed"] as PackedScene).resource_path != MENU_SCENE:
			failures.append("the loaded scene is %s, not the menu" % (call["packed"] as PackedScene).resource_path)
	if not bool(splash.call("has_left")):
		failures.append("has_left() is false after the hand-over")
	# Stepping on after leaving must not hand over twice.
	for _i in range(5):
		splash.call("_process", STEP)
	if handed.size() > 1:
		failures.append("the splash handed over %d times" % handed.size())
	_close(splash)
	_sweep(tree)
	return failures


func _test_tap_skips_ahead():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree in the runner"]
	_sweep(tree)
	var splash: Control = _open(failures)
	if splash == null:
		return failures
	var handed: Array = []
	splash.set("scene_changer", func(_packed: PackedScene, _path: String) -> void:
		handed.append(true))
	splash.call("_process", 0.2)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	splash.call("_input", touch)
	splash.call("_process", 0.05)
	var curtain: Node = Transition.current(tree)
	if curtain == null:
		failures.append("a tap at 0.2 s did not start the exit; the splash is a trap")
	else:
		for _i in range(10):
			curtain.call("_process", 0.05)
	if handed.size() != 1:
		failures.append("after a tap the changer was called %d times; expected once" % handed.size())
	_close(splash)
	_sweep(tree)
	return failures


func _test_logo_title_drop_in():
	var failures: Array = []
	var splash: Control = _open(failures)
	if splash == null:
		return failures
	var logo: Node = splash.get_node_or_null("Logo")
	if logo == null:
		failures.append("splash.tscn has no Logo node")
	elif logo.get_script() != LogoTitle:
		failures.append("the splash's Logo does not carry logo_title.gd; the menu should get the same node")
	else:
		var rect: TextureRect = logo
		if rect.texture == null:
			failures.append("LogoTitle loaded no texture; %s is missing or not imported" % LogoTitle.TEXTURE_PATH)
		elif rect.texture.get_width() > 1024:
			failures.append("the title texture is %d wide; it should be at most 1024" % rect.texture.get_width())
		if rect.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			failures.append("LogoTitle does not keep the logo's aspect")
		if rect.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			failures.append("LogoTitle eats taps; it is decorative")
		splash.call("_apply_intro", 0.0)
		if not rect.pivot_offset.is_equal_approx(rect.size * 0.5):
			failures.append("the first intro frame scales around %s, not the centred pivot %s"
					% [str(rect.pivot_offset), str(rect.size * 0.5)])
		# Sway: 3 degrees at the peak, none at rest, and gated by is_processing().
		var peak: float = absf(float(rect.call("sway_at", LogoTitle.SWAY_PERIOD_SEC * 0.25)))
		if absf(peak - deg_to_rad(LogoTitle.SWAY_DEGREES)) > 0.001:
			failures.append("the sway peaks at %.2f degrees, not %.1f" % [rad_to_deg(peak), LogoTitle.SWAY_DEGREES])
		if LogoTitle.SWAY_DEGREES > 4.0:
			failures.append("a %.1f degree sway is busy; the brief says gentle, about 3" % LogoTitle.SWAY_DEGREES)
		rect.set_process(false)
		if rect.is_processing():
			failures.append("set_process(false) did not stop LogoTitle processing")
		rect.set_process(true)
		rect.call("set_compact", true)
		if not bool(rect.call("is_compact")):
			failures.append("set_compact(true) did not take")
		if rect.texture == null or rect.texture.get_width() > 512:
			failures.append("compact mode did not switch to the 512 texture")
		rect.call("set_compact", false)
	for node_name: String in ["Background", "Credit", "Version", "LoadingDots"]:
		if splash.get_node_or_null(node_name) == null:
			failures.append("splash.tscn has no %s" % node_name)
	var credit: Label = splash.get_node_or_null("Credit")
	if credit != null and not credit.text.contains("Godot Engine"):
		failures.append("the 'Made with Godot Engine' line is missing; the licence asks for it")
	var version: Label = splash.get_node_or_null("Version")
	if version != null and not version.text.ends_with(SplashScript.GameVersion.BUILD):
		failures.append("the version label reads '%s', not the build %s" % [version.text, SplashScript.GameVersion.BUILD])
	_close(splash)
	return failures


func _test_no_black():
	var failures: Array = []
	var splash: Control = _open(failures)
	if splash == null:
		return failures
	var colours: Array = []
	_collect_colours(splash, colours)
	for colour: Color in colours:
		if Palette.is_black(colour):
			failures.append("the splash paints pure black")
			break
	_close(splash)
	return failures


func _open(failures: Array) -> Control:
	if not ResourceLoader.exists(SPLASH_SCENE):
		failures.append("%s does not exist" % SPLASH_SCENE)
		return null
	var packed: PackedScene = load(SPLASH_SCENE)
	if packed == null:
		failures.append("%s failed to load" % SPLASH_SCENE)
		return null
	var splash: Node = packed.instantiate()
	if not (splash is Control):
		failures.append("the splash root is not a Control")
		splash.free()
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(splash)
	# The runner adds nodes before the tree is live, so `_ready()` does not fire
	# on its own here (see `test_routing_first_run.gd`); it is idempotent.
	splash.call("_ready")
	return splash


func _close(splash: Node) -> void:
	if splash == null:
		return
	if splash.get_parent() != null:
		splash.get_parent().remove_child(splash)
	splash.free()


func _sweep(tree: SceneTree) -> void:
	for child: Node in tree.root.get_children():
		if child.name == Transition.NODE_NAME:
			tree.root.remove_child(child)
			child.free()


func _collect_colours(node: Node, into: Array) -> void:
	if node is ColorRect:
		into.append((node as ColorRect).color)
	if node is Control:
		for key: String in ["font_color", "font_outline_color"]:
			if (node as Control).has_theme_color_override(key):
				into.append((node as Control).get_theme_color(key))
	for child: Node in node.get_children():
		_collect_colours(child, into)
