extends SceneTree

## THE NEED BUBBLE, PHOTOGRAPHED. Dev-only; nothing in the game references it.
##
##   Godot --path game --script res://tests/shots_bubble.gd -- ipad 1366x1024
##   Godot --path game --script res://tests/shots_bubble.gd -- iphone 2340x1080
##
## Bunny's "I'm hungry!" line is a `Label3D` over his head. He is 0.78 m tall and
## Aliz is more than twice that, so at the close-up framing the bubble used to
## land on HER chest -- a line about Bunny apparently coming out of the caregiver.
## `child_actor.gd::_place_bubble()` claims to fix that by stepping the bubble to
## the side she is NOT on. Nobody had ever seen that in a frame, so this exists.
##
## ## Why it is not a room screenshot
##
## The bubble is only on screen when THREE things hold at once: Bunny has an
## active need, Aliz is next to him, and the beat's close-up is being held. So
## this drives the REAL `house_world.tscn` with the REAL `HouseLevelDirector`
## through the REAL first beat of `imHungry` (`bunnyIsHungry`, whose
## `requiresWalkTo` is `bedroom.littleBuddy`), reaches it the way arriving does,
## and then FREEZES the director so the beat cannot advance out from under the
## camera. Aliz is then moved and the director's OWN `_update_focus()` is called
## by hand -- the same function its `_process` calls every frame -- so the shot is
## composed by the game, at the game's margin, with the game's radius. The HUD is
## the shipping HUD and picks its presentation mode off the live camera radius
## with nothing forced, which is why the mode it reports is worth reading.
##
## ## Why a SubViewport
##
## `--resolution 2340x1080` is a request, not an instruction: the window manager
## clamps it (1686x935 on this machine), and the camera solves its distance from
## the aspect ratio -- so a clamped run photographs a 1.80 composition and files
## it as evidence for a 2.17 one. The world is therefore hosted in a `SubViewport`
## of exactly the asked-for size and captured from its texture. Every run prints
## the pixel size it actually wrote.
##
## ## The five stagings
##
##   `front`    -- Aliz on Bunny's own interaction point, which is where the real
##                 beat puts her: the defect's original geometry.
##   `left`     -- Aliz half a stride to Bunny's screen-left, close enough that she
##                 is genuinely in the way.
##   `right`    -- the mirror of it.
##   `abeam`    -- Aliz well clear sideways, where the step must STAND DOWN and
##                 the line belongs over Bunny's own head.
##   `longline` -- the `front` staging again with the longest need line the game
##                 has ("I need changing."), which is half as wide again as
##                 "I'm hungry!" and is what a fixed-size step would leave on her.
##
## `left` and `right` are the side-swap under test: the bubble must end up on the
## OPPOSITE side in each, and the printed `bubbleWorldDX` / `alizDX` pair says so
## numerically as well as in the picture. Every case also asserts, rather than
## only prints: bubble visible, bubble has text, bubble inside the frame with a
## margin, bubble at least 90 px from the caregiver's chest.

const OUT_DIR: String = "docs/shots/"
const LEVEL: String = "imHungry"
const BEAT: String = "bunnyIsHungry"
const Spatial := preload("res://scripts/navigation/spatial_util.gd")

## How far to either side Aliz is stood for the swap cases.
##
## Inside `child_actor._side_clearance()` (~0.71 m for "I'm hungry!"), so she is
## genuinely in the way and the line has to move -- which is the only staging in
## which "does it swap sides" is a question with an answer.
const SIDE_STEP: float = 0.40
## ...and the same depth the real beat puts her at: BEHIND Bunny, away from the
## camera. That is the half of the defect a sideways step has to survive -- she is
## the backdrop the bubble is drawn against, and she is twice his height, so every
## bubble height that clears his head lands somewhere on her.
const BEHIND: float = -0.62
## Well past `child_actor._side_clearance()`, so there is nothing left to dodge
## and the line is expected to sit over Bunny's own head.
const ABEAM_STEP: float = 1.40

var _suffix: String = "ipad"
var _frame: Vector2i = Vector2i(1366, 1024)
var _viewport: SubViewport = null
var _world: Node = null
var _director: Node = null
var _child: Node = null
var _aliz: Node3D = null
var _bubble: Node3D = null
var _notes: Array = []
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[0]).strip_edges().is_empty():
		_suffix = String(args[0]).strip_edges()
	if args.size() > 1:
		var wide: PackedStringArray = String(args[1]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))
	print("=== need bubble, %s, %dx%d ===" % [_suffix, _frame.x, _frame.y])

	await process_frame
	# A clean profile, for the same reason `smoke_mission01.gd` resets one: the
	# first-run tour and the mission picker both read it, and a developer's own
	# saved progress would quietly change what is on screen. AFTER a frame --
	# autoloads are not on `root` yet when a `--script` SceneTree initialises.
	var save: Node = root.get_node_or_null("SaveService")
	if save != null and save.has_method("reset_profile"):
		save.call("reset_profile")

	var packed: PackedScene = load("res://scenes/house/house_world.tscn")
	if packed == null:
		return _die("house_world.tscn will not load")
	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_world = packed.instantiate()
	_viewport.add_child(_world)
	await _settle(0.6)

	# The first-run tour and a mission never run together in the game; a harness
	# that forces a level onto a fresh profile gets both, and the tour's caption
	# then photographs itself into the evidence. `shot_harness.gd` documents the
	# same trap.
	if _world.has_method("is_onboarding_active") and bool(_world.call("is_onboarding_active")):
		var tour: Node = _world.call("get_onboarding_director")
		if tour != null and tour.has_method("finish"):
			tour.call("finish")
			await process_frame
		else:
			_fail.append("the first-run tour is running and will be in every shot")

	if not _world.call("place_in_room", "bedroom", "default"):
		return _die("could not enter the bedroom")
	await _settle(0.5)

	_director = _world.call("ensure_level_director")
	if _director == null:
		return _die("this build has no level director")
	_director.call("_start_level", LEVEL)
	await _settle(0.8)

	_child = _find_child_actor()
	if _child == null:
		return _die("no ChildActor in the bedroom -- Bunny is not present")
	_bubble = _child.get_node_or_null("NeedBubble") as Node3D
	if _bubble == null:
		return _die("Bunny has no NeedBubble node")
	# Unambiguously hungry, so the need cannot be something else and the line
	# under test is the line in the picture. 70 is well past `HUNGRY_AT` (40) and
	# deliberately short of `CRYING_SEVERITY` (85): 90 tips the dominant need over
	# to `crying`, and the harness then photographs a perfectly correct "Waah!"
	# and files it as the hunger shot.
	var stats: Object = _child.get("_state")
	if stats != null:
		stats.call("set_stat", "hunger", 70.0)
	# ...and re-derived. `set_activity("idle")` is a no-op when the activity is
	# already idle, so it does NOT republish the need -- the actor's own
	# `_refresh()` is the call that does, and it is the one the game makes every
	# time a stat moves.
	_child.call("_refresh")
	await process_frame

	_aliz = _world.call("get_character") as Node3D
	if _aliz == null:
		return _die("no caregiver in the world")

	# REACH THE BEAT the way arriving does: stand Aliz where the walk would have
	# ended, then let the director open its own close-up.
	var plan: Dictionary = _director.call("get_current_plan")
	if String(plan.get("taskId", "")) != BEAT:
		_fail.append("expected beat '%s', got '%s'" % [BEAT, String(plan.get("taskId", ""))])
	var stand: Variant = _director.call("_beat_stand_position")
	if stand is Vector3:
		Spatial.set_world_position(_aliz, stand)
		await process_frame
	_director.call("_reach_beat")
	await _settle(0.6)
	if not bool(_director.call("is_camera_focused")):
		return _die("the beat never opened a close-up -- there is nothing to judge")

	# FREEZE. `step()` would flush the tap-beat's completion, release the close-up
	# and move the mission on; the shot would then be of the next beat. The
	# composition is still the director's -- `_update_focus()` is called by hand
	# below, which is exactly what its `_process` does.
	_director.set_process(false)
	_director.set_physics_process(false)
	if _aliz.has_method("set_disabled"):
		_aliz.call("set_disabled", true)

	var bunny: Vector3 = Spatial.world_position(_child as Node3D)
	# `front` is the REAL beat's staging, taken from the target rather than
	# invented: `bedroom.littleBuddy`'s own `InteractionPoint`, which is where the
	# game sends Aliz to talk to him. An earlier draft of this file guessed a
	# position 0.62 m the OTHER way and photographed her back filling the frame --
	# a perfectly sharp picture of a situation the game never composes.
	var here: Vector3 = stand if stand is Vector3 else Vector3(bunny.x, bunny.y, bunny.z + BEHIND)
	print("\n  beat stand position (from the target): (%.2f, %.2f)" % [here.x, here.z])
	await _case("front", here)
	await _case("left", Vector3(
		bunny.x - SIDE_STEP, bunny.y, bunny.z + BEHIND))
	await _case("right", Vector3(
		bunny.x + SIDE_STEP, bunny.y, bunny.z + BEHIND))
	# And the case the step has to STAND DOWN for: she is already well clear
	# sideways, so pushing the line further out would park it over bare floor with
	# the child nowhere near it. It belongs over his own head here.
	await _case("abeam", Vector3(
		bunny.x - ABEAM_STEP, bunny.y, bunny.z + BEHIND), "centred")

	# THE LONGEST LINE, in the tightest staging. "I need changing." is half as wide
	# again as "I'm hungry!", and a step sized for the short one leaves the long one
	# lying across her. The step is derived from the rendered width for exactly this
	# case, so the case is photographed rather than argued about.
	var long_stats: Object = _child.get("_state")
	if long_stats != null:
		long_stats.call("set_stat", "hunger", 5.0)
		long_stats.call("set_stat", "thirst", 5.0)
		long_stats.call("set_stat", "freshness", 5.0)
		_child.call("_refresh")
	await process_frame
	await _case("longline", here)

	_report()


## One staging: put Aliz somewhere, let the game recompose, measure, photograph.
func _case(label: String, aliz_at: Vector3, expect: String = "step") -> void:
	Spatial.set_world_position(_aliz, aliz_at)
	# Facing Bunny, because a caregiver standing beside a child with her back to
	# him is not the situation the bubble has to survive.
	var bunny: Vector3 = Spatial.world_position(_child as Node3D)
	if absf(aliz_at.x - bunny.x) + absf(aliz_at.z - bunny.z) > 0.01:
		_aliz.look_at(Vector3(bunny.x, aliz_at.y, bunny.z), Vector3.UP)
	await _settle(0.35)
	# The director's own per-frame recomposition, called by hand.
	_director.call("_update_focus")
	var camera: Camera3D = _world.call("get_camera")
	if camera != null and camera.has_method("settle"):
		camera.call("settle")
	await _settle(0.5)

	var out_name: String = "bubble_%s_%s" % [label, _suffix]
	_measure(label, out_name, bunny, expect)
	await _shot(out_name)


## Everything a reader needs to check the picture against, printed.
##
## The two numbers that decide the side-swap question are `alizDX` and
## `bubbleWorldDX`: they must have OPPOSITE signs. `bubbleLocalX` is printed
## beside them because the offset is authored in the child's LOCAL frame while the
## caregiver comparison is made in WORLD X, and in the bedroom Bunny is yawed 180
## degrees -- so the two need not agree, and that is the whole question.
func _measure(label: String, out_name: String, bunny: Vector3, expect: String) -> void:
	var aliz: Vector3 = Spatial.world_position(_aliz)
	var bubble_world: Vector3 = Spatial.world_position(_bubble)
	var local: Vector3 = _bubble.position
	var aliz_dx: float = aliz.x - bunny.x
	var bubble_dx: float = bubble_world.x - bunny.x
	var camera: Camera3D = _world.call("get_camera")
	var shot: Dictionary = _director.call("get_camera_focus")
	var hud: Node = _world.find_child("HouseHud", true, false)
	var mode: String = String(hud.call("get_presentation_mode_name")) if hud != null else "?"
	var seen: float = float(hud.call("get_seen_focus_radius")) if hud != null else -1.0

	var screen_bubble: Vector2 = Vector2(-1, -1)
	var screen_aliz_chest: Vector2 = Vector2(-1, -1)
	var screen_bunny_head: Vector2 = Vector2(-1, -1)
	if camera != null:
		screen_bubble = camera.unproject_position(bubble_world)
		screen_aliz_chest = camera.unproject_position(aliz + Vector3(0.0, 1.10, 0.0))
		screen_bunny_head = camera.unproject_position(bunny + Vector3(0.0, 0.72, 0.0))

	print("\n  -- %s --" % label)
	print("     bunny=(%.2f, %.2f) yaw=%.0f  aliz=(%.2f, %.2f)"
			% [bunny.x, bunny.z, rad_to_deg((_child as Node3D).global_rotation.y), aliz.x, aliz.z])
	print("     alizDX=%+.2f  bubbleLocalX=%+.2f  bubbleWorldDX=%+.2f  -> %s"
			% [aliz_dx, local.x, bubble_dx,
				"OPPOSITE sides (correct)" if aliz_dx * bubble_dx < 0.0
				else "SAME side as Aliz" if absf(aliz_dx) > 0.05
				else "she is head-on; no side to avoid"])
	print("     bubbleWorld=(%.2f, %.2f, %.2f)  visible=%s  text='%s'"
			% [bubble_world.x, bubble_world.y, bubble_world.z,
				str(_bubble.visible), String(_bubble.get("text"))])
	print("     screen: bubble=(%.0f, %.0f)  alizChest=(%.0f, %.0f)  bunnyHead=(%.0f, %.0f)"
			% [screen_bubble.x, screen_bubble.y, screen_aliz_chest.x, screen_aliz_chest.y,
				screen_bunny_head.x, screen_bunny_head.y])
	print("     hudMode=%s seenRadius=%.2f  beatRadius=%.2f  need='%s' life='%s'"
			% [mode, seen, float(shot.get("radius", 0.0)),
				String(_child.call("get_need")), String(_child.call("get_life_clip"))])

	# Hard checks, so a bad frame cannot pass quietly.
	if not _bubble.visible:
		_fail.append("%s: the bubble is not visible; there is nothing to judge" % label)
	if String(_bubble.get("text")).strip_edges().is_empty():
		_fail.append("%s: the bubble has no text" % label)
	if mode != "FEED":
		_notes.append("%s: HUD settled in %s, not FEED" % [label, mode])
	if expect == "centred":
		if absf(bubble_dx) > 0.05:
			_fail.append("%s: Aliz is a clear %+.2f m to one side, so the bubble should be "
					% [label, aliz_dx] + "over Bunny's head; it is %+.2f m out" % bubble_dx)
	elif absf(aliz_dx) > 0.05 and aliz_dx * bubble_dx >= 0.0:
		_fail.append("%s: Aliz is at dx=%+.2f and the bubble went to %+.2f -- the same side"
				% [label, aliz_dx, bubble_dx])
	# Inside the frame, with a margin: a line touching the edge is a cropped line.
	var margin: float = 24.0
	if screen_bubble.x < margin or screen_bubble.y < margin \
			or screen_bubble.x > float(_frame.x) - margin \
			or screen_bubble.y > float(_frame.y) - margin:
		_fail.append("%s: the bubble's anchor is at (%.0f, %.0f) in a %dx%d frame -- outside it"
				% [label, screen_bubble.x, screen_bubble.y, _frame.x, _frame.y])
	# Not on her chest: the defect, measured. The bubble's anchor is its centre.
	var apart: float = screen_bubble.distance_to(screen_aliz_chest)
	print("     bubble is %.0f px from Aliz's chest, %.0f px from Bunny's head"
			% [apart, screen_bubble.distance_to(screen_bunny_head)])
	if apart < 90.0:
		_fail.append("%s: the bubble is only %.0f px from Aliz's chest" % [label, apart])
	print("     -> %s.png" % out_name)


func _find_child_actor() -> Node:
	var room: Node = _world.call("get_current_room")
	if room == null:
		return null
	for child: Node in room.get_children():
		if child.has_method("satisfy") and child.has_method("set_activity"):
			return child
	return null


func _shot(out_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + out_name + ".png")
	var err: int = image.save_png(path)
	# The size that was WRITTEN, read back off the image rather than off the
	# request, because the request is the thing that has lied before.
	print("     %s %s.png  %dx%d" % [
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


func _die(message: String) -> void:
	print("BUBBLE SHOTS FAIL: %s" % message)
	quit(1)


func _report() -> void:
	print("")
	for note: String in _notes:
		print("  note: %s" % note)
	if _fail.is_empty():
		print("BUBBLE SHOTS OK (%s) -- every staging measured and photographed." % _suffix)
		quit(0)
	else:
		print("BUBBLE SHOTS FAIL (%s) -- %d problem(s):" % [_suffix, _fail.size()])
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)
