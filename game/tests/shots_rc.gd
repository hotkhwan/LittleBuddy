extends SceneTree

## RELEASE-CANDIDATE EVIDENCE, at the viewport sizes it CLAIMS.
##
##   Godot --path game --script res://tests/shots_rc.gd -- <prefix> <W> <H>
##
## ## Why this exists rather than `--resolution`
##
## `--resolution 2340x1080` is a REQUEST. The window manager clamps it -- on this
## machine to 1686x935 -- and the resulting PNG is a **1.80 aspect filed as
## evidence for a 2.17 one**. That is not a rounding error: `camera_framing.solve()`
## fits the camera distance FROM the aspect ratio, so a clamped shot is a
## different composition of a different game. An audit of `docs/shots/` found 18
## images in exactly that state, 8 of them the evidence for the HUD fix.
##
## So the world is hosted in a `SubViewport` of exactly the asked-for size and
## photographed from ITS texture. The camera inside sees that viewport's aspect
## and nothing else. The size is asserted against the saved PNG afterwards, so
## this file cannot make the same mistake quietly.
##
## It drives the REAL `house_world.tscn` and the REAL director to a REAL beat --
## a close-up with both characters, which is the frame every remaining visual
## question is about: the HUD, the need bubble, and the lighting all have to be
## judged there or not at all.

const OUT_DIR: String = "docs/shots/"

var _prefix: String = "rc"
var _frame := Vector2i(1334, 750)
var _viewport: SubViewport = null
var _world: Node = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = String(args[0])
	if args.size() > 2:
		_frame = Vector2i(int(args[1]), int(args[2]))
	await process_frame

	var save: Node = root.get_node_or_null("SaveService")
	if save != null and save.has_method("reset_profile"):
		save.call("reset_profile")
		# END THE FIRST-RUN TOUR BEFORE FORCING A MISSION.
		#
		# The real game can never show both: `house_world._ready()` is
		# `if _begin_onboarding(): return`, so a mission does not start until the
		# tour is done. This harness calls the director directly and bypasses
		# that guard -- which put "You can move things. Drag them with your
		# finger." on top of the care overlay's own title and made a HARNESS
		# artifact look like a shipping text collision. Marking the tour seen
		# reproduces the state a real player is in by the time a mission runs.
		var plan: GDScript = load("res://scripts/onboarding/onboarding_plan.gd")
		if plan != null and save.has_method("set_setting"):
			save.call("set_setting", plan.SETTING_KEY, true)

	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	_world = load("res://scenes/house/house_world.tscn").instantiate()
	_viewport.add_child(_world)
	await _settle(0.8)

	# Run the real mission, and walk it to the FEEDING beat -- the close-up where
	# the HUD, the bubble and the character all compete for the same pixels.
	var director: Node = _world.call("ensure_level_director")
	director.call("start")
	await _settle(1.0)
	var runner: Node = director.get("_runner")

	var reached: String = ""
	for _i in range(14):
		var plan: Dictionary = director.call("get_current_plan")
		var care: String = String(plan.get("careKind", ""))
		if care == "giveBottle":
			director.call("_open_care", plan)
			reached = String(plan.get("taskId", ""))
			break
		if runner != null and runner.has_method("skip_current_task"):
			runner.call("skip_current_task")
		await _settle(1.9)   # the runner's real inter-task gap is 1.6 s

	await _settle(0.8)
	print("  beat reached: '%s'" % reached)
	if reached.is_empty():
		_fail.append("never reached the feeding close-up; the shot would prove nothing")
	await _shot("%s_feed" % _prefix)

	if _fail.is_empty():
		print("\nRC SHOTS OK")
		quit(0)
	else:
		print("\nRC SHOTS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


func _shot(name: String) -> void:
	await _settle(0.4)
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + name + ".png")
	if image.save_png(path) != OK:
		_fail.append("could not write %s.png" % name)
		return
	# ASSERT the size, rather than trusting that asking produced it. This is the
	# entire point of the file.
	if image.get_width() != _frame.x or image.get_height() != _frame.y:
		_fail.append("%s.png is %dx%d but %dx%d was asked for"
				% [name, image.get_width(), image.get_height(), _frame.x, _frame.y])
		return
	print("  shot %s.png  %dx%d  aspect %.2f"
			% [name, image.get_width(), image.get_height(),
				float(image.get_width()) / float(image.get_height())])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
