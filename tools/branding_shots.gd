extends SceneTree

## Evidence for the splash and the curtain, at the sizes it CLAIMS.
##
##   Godot --path game --script res://../tools/branding_shots.gd -- <W> <H>
##   (NOT --headless: it draws. Defaults to 1334x750.)
##
## Same approach as `tests/shots_rc.gd`: the scene is hosted in a `SubViewport`
## of exactly the asked-for size, photographed from ITS texture, and the PNG
## size is asserted afterwards, so a clamped window can never file a 1.80
## aspect as evidence for a 2.17 one.
##
## Writes docs/shots/brand_splash_<W>x<H>.png (the logo settled, dots mid-hop),
## brand_splash_intro_<W>x<H>.png (0.2 s in: the logo still fading up) and
## brand_curtain_<W>x<H>.png (the SceneTransition half-way up over the splash)
## and brand_curtain_full_<W>x<H>.png (fully covered, heart at rest).

const OUT_DIR: String = "res://../docs/shots/"
const SPLASH_SCENE: String = "res://scenes/splash/splash.tscn"
const Transition := preload("res://scripts/branding/scene_transition.gd")

var _frame := Vector2i(1334, 750)
var _viewport: SubViewport = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 1:
		_frame = Vector2i(int(args[0]), int(args[1]))
	await process_frame

	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	var splash: Control = load(SPLASH_SCENE).instantiate()
	# Never let the evidence run swap the harness's scene.
	splash.set("scene_changer", func(_packed: PackedScene, _path: String) -> void: pass)
	# The splash drives itself from _process; hold it by hand so each shot is
	# at a chosen moment rather than whatever the frame clock landed on.
	splash.set_process(false)
	_viewport.add_child(splash)
	await process_frame

	splash.call("_process", 0.2)
	await _shot("brand_splash_intro_%dx%d" % [_frame.x, _frame.y])

	# 0.9 s in: logo settled, dots mid-hop; still before the hand-over.
	for _i in range(7):
		splash.call("_process", 0.1)
	await _shot("brand_splash_%dx%d" % [_frame.x, _frame.y])

	# The curtain half-way up, over the splash: a CanvasLayer under the same
	# SubViewport so it is photographed too.
	var curtain: CanvasLayer = Transition.new()
	curtain.name = Transition.NODE_NAME
	_viewport.add_child(curtain)
	curtain.set_process(false)
	curtain.call("_begin_cover", null)
	curtain.set_process(false)
	for _i in range(4):
		curtain.call("_process", 0.05)
	await _shot("brand_curtain_%dx%d" % [_frame.x, _frame.y])
	for _i in range(8):
		curtain.call("_process", 0.05)
	await _shot("brand_curtain_full_%dx%d" % [_frame.x, _frame.y])

	if _fail.is_empty():
		print("\nBRAND SHOTS OK")
		quit(0)
	else:
		print("\nBRAND SHOTS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


func _shot(name: String) -> void:
	for _i in range(2):
		await process_frame
	RenderingServer.force_draw(true, 0.0)
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT_DIR + name + ".png")
	if image.save_png(path) != OK:
		_fail.append("could not write %s.png" % name)
		return
	if image.get_width() != _frame.x or image.get_height() != _frame.y:
		_fail.append("%s.png is %dx%d but %dx%d was asked for"
				% [name, image.get_width(), image.get_height(), _frame.x, _frame.y])
		return
	print("  shot %s.png  %dx%d  aspect %.2f"
			% [name, image.get_width(), image.get_height(),
				float(image.get_width()) / float(image.get_height())])
