extends Control

## The first scene: the Little Days logo, three bobbing dots, then the menu.
##
## Boot order on a device is
##
##   1. the engine boot splash (`boot_splash/image`, drawn before any script
##      runs: the same logo on the same cream, so 1 -> 2 is a continuous
##      picture, not a flash);
##   2. THIS scene, which starts loading `main.tscn` on a background thread the
##      moment it appears and never blocks the frame while it waits;
##   3. `main.tscn`, under the cream curtain of `scene_transition.gd`, which
##      lifts itself once the menu is the current scene.
##
## ## The timing contract
##
##   * the logo has `MIN_SHOW_SEC` on screen, even if the menu loads instantly,
##     so it never strobes;
##   * the menu appears as soon as it is loaded after that, and in every case
##     the decision to leave is made by `MAX_SHOW_SEC` -- if the threaded load
##     is still busy at that point the remaining load is taken on the main
##     thread, because a late menu beats a splash that never ends;
##   * **any tap, click or key skips ahead** immediately (subject to the same
##     load fallback). A splash is never a trap.
##
## `main.tscn` is loaded by PATH here, exactly as the tests load it, so nothing
## about the menu changes because a splash now precedes it.
##
## ## Testability
##
## The scene swap goes through `scene_changer`, a `Callable(packed: PackedScene,
## path: String)`. The default calls `change_scene_to_packed()` /
## `change_scene_to_file()`. `test_branding_splash.gd` injects its own, steps
## `_process()` by hand and checks the contract above without ever swapping the
## runner's scene.

const Palette := preload("res://scripts/ui/palette.gd")
const GameVersion := preload("res://scripts/content_packs/game_version.gd")

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"
## `load()`ed by path so the splash still runs if the curtain is ever removed.
const TRANSITION_SCRIPT_PATH: String = "res://scripts/branding/scene_transition.gd"

const MIN_SHOW_SEC: float = 1.2
## Decision deadline. Plus the curtain's 0.35 s that is still under 3 s.
const MAX_SHOW_SEC: float = 2.6
## Logo intro: fade and settle from 92% over half a second.
const INTRO_SEC: float = 0.5

## `func(packed: PackedScene, path: String) -> void`. Replaced by tests.
var scene_changer: Callable = Callable()

var _elapsed: float = 0.0
var _skip_requested: bool = false
var _leaving: bool = false
var _left: bool = false
var _load_requested: bool = false
var _dots: Control = null
var _ready_done: bool = false


func _ready() -> void:
	# Idempotent: the headless runner adds nodes before the tree is live, so
	# `_ready()` never fires there and `test_branding_splash.gd` calls it by hand.
	if _ready_done:
		return
	_ready_done = true
	scene_changer = _change_scene_default if not scene_changer.is_valid() else scene_changer
	_load_requested = ResourceLoader.load_threaded_request(MAIN_SCENE_PATH) == OK
	if not _load_requested:
		push_warning("Splash: threaded load of %s refused; will load on the main thread" % MAIN_SCENE_PATH)
	_build_dots()
	_apply_intro(0.0)
	var version: Label = get_node_or_null("Version")
	if version != null:
		version.text = "v%s" % GameVersion.BUILD


func _process(delta: float) -> void:
	_elapsed += delta
	_apply_intro(_elapsed)
	if _dots != null:
		_dots.set("time", _elapsed)
		_dots.queue_redraw()
	if _leaving:
		return
	if should_leave(_elapsed, is_menu_loaded(), _skip_requested):
		_go()


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	var pressed: bool = false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton:
		pressed = event.pressed
	elif event is InputEventKey:
		pressed = event.pressed and not event.echo
	if pressed:
		_skip_requested = true


# --- The contract, as a pure function ---------------------------------------------


## True when the splash should hand over now. `MIN_SHOW_SEC` holds the logo on
## screen unless the child taps; `MAX_SHOW_SEC` is the deadline no matter what.
static func should_leave(elapsed: float, loaded: bool, skip: bool) -> bool:
	if skip:
		return true
	if elapsed >= MAX_SHOW_SEC:
		return true
	return loaded and elapsed >= MIN_SHOW_SEC


func is_menu_loaded() -> bool:
	if not _load_requested:
		return false
	return ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH) == ResourceLoader.THREAD_LOAD_LOADED


func has_left() -> bool:
	return _left


func request_skip() -> void:
	_skip_requested = true


# --- Leaving ----------------------------------------------------------------------


func _go() -> void:
	_leaving = true
	var tree: SceneTree = _tree()
	var transition: GDScript = load(TRANSITION_SCRIPT_PATH) if ResourceLoader.exists(TRANSITION_SCRIPT_PATH) else null
	if tree != null and transition != null:
		await transition.call("cover", tree)
	_hand_over()


func _hand_over() -> void:
	if _left:
		return
	_left = true
	var packed: PackedScene = null
	if _load_requested:
		var status: int = ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH)
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# LOADED returns at once; IN_PROGRESS finishes on this thread. Both
			# are the right call at this point: the decision to leave is made.
			packed = ResourceLoader.load_threaded_get(MAIN_SCENE_PATH) as PackedScene
	if scene_changer.is_valid():
		scene_changer.call(packed, MAIN_SCENE_PATH)


func _change_scene_default(packed: PackedScene, path: String) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	if packed != null and tree.change_scene_to_packed(packed) == OK:
		return
	tree.change_scene_to_file(path)


## `get_tree()` errors on a node that is not inside a live tree, which is the
## headless runner's situation; the main loop is the same tree either way.
func _tree() -> SceneTree:
	if is_inside_tree():
		return get_tree()
	return Engine.get_main_loop() as SceneTree


# --- Looks ------------------------------------------------------------------------


func _apply_intro(elapsed: float) -> void:
	var logo: Control = get_node_or_null("Logo")
	if logo == null:
		return
	# `_ready()` can run before the first layout pass on a cold launch. Scaling
	# around Control's default (0, 0) made that first visible frame appear left
	# shifted even though the anchors themselves were symmetric. Recompute the
	# pivot immediately before every intro sample, including t=0.
	logo.pivot_offset = logo.size * 0.5
	var t: float = clampf(elapsed / INTRO_SEC, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	logo.modulate.a = eased
	logo.scale = Vector2.ONE * (0.92 + 0.08 * eased)


func _build_dots() -> void:
	_dots = LoadingDots.new()
	_dots.name = "LoadingDots"
	_dots.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dots.size = Vector2(160, 40)
	_dots.position = Vector2(-80, -150)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dots)


## Three pastel dots taking turns to hop. No text: the child cannot read
## "Loading", and the adult does not need to be told.
class LoadingDots extends Control:
	const COLOURS: Array[Color] = [Palette.SOFT_PINK, Palette.MINT, Palette.PEACH]
	var time: float = 0.0

	func _draw() -> void:
		var radius: float = size.y * 0.28
		var gap: float = size.x / 3.0
		for i in range(3):
			var phase: float = time * 2.4 - float(i) * 0.55
			var hop: float = maxf(0.0, sin(phase)) * radius * 0.9
			var centre := Vector2(gap * (float(i) + 0.5), size.y * 0.65 - hop)
			draw_circle(centre + Vector2(0, radius * 0.18), radius, Palette.STAR_GHOST)
			draw_circle(centre, radius, COLOURS[i])
