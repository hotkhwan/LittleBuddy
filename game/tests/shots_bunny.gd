extends SceneTree

## BUNNY'S REACTIONS, PHOTOGRAPHED. Dev-only; nothing in the game references it.
##
##   Godot --path game --script res://tests/shots_bunny.gd -- before 1334x750
##   Godot --path game --script res://tests/shots_bunny.gd -- after  1334x750
##
## `docs/BUNNY_LIFE_PASS.md` §4 asked for exactly this file: there was no way to
## photograph Bunny from the shipping harness, so the evidence for that pass
## needed a throwaway script which was then deleted, and the next person had to
## write it again. This is that request, answered.
##
## ## It drives the REAL house, not a lit turntable
##
## Every frame below comes out of `scenes/house/house_world.tscn`, in the real
## bedroom, with the real lights, the real `ChildActor` and the real
## `RoomCamera`. The only things forced are the child's own STATS -- which is
## what the game itself moves -- and where Aliz is standing.
##
## Two framings per state, because they answer different questions:
##
##   * `_room` -- the shipping bedroom shot, unchanged. "Does this read from
##     where the player actually sits?" is the only question that matters, and it
##     is the one a turntable render cannot answer.
##   * `_near` -- the game's OWN close-up, opened through
##     `RoomCamera.focus_activity()` exactly as a care beat opens it. Note that
##     `camera_framing.gd::FOCUS_MIN_DISTANCE` is 1.9 m, so even this is a real
##     gameplay distance and not a macro lens.
##
## ## Why a SubViewport
##
## `--resolution` is a REQUEST. The window manager clamps it (1686x935 on this
## machine), the camera solves its distance from the aspect ratio, and a clamped
## run then photographs one composition and files it as evidence for another.
## `shots_bubble.gd` documents the same trap. So the world is hosted in a
## `SubViewport` of exactly the asked-for size, and every write prints the pixel
## size read back off the image.
##
## ## Why each state is FROZEN at a phase
##
## A reaction is a motion, and a screenshot is not. Sampling `celebrate` at t=0
## photographs a child standing still with its arms down -- a true frame of a
## clip that is nothing like what it reads as. So each case names the phase of
## its clip that carries the pose, the actor's `_process` is switched off so it
## cannot re-apply, and the `AnimationPlayer` is paused and seeked there.

const OUT_DIR: String = "docs/shots/"
const Spatial := preload("res://scripts/navigation/spatial_util.gd")
const Needs := preload("res://scripts/care/child_needs.gd")
const Present := preload("res://scripts/care/child_presentation.gd")

## How far to park Aliz when she is not the subject. Well outside
## `child_life.gd::ATTEND_FAR` (2.7 m), so Bunny faces the camera.
const ALIZ_AWAY := Vector3(3.4, 0.0, 2.6)
## ...and where to put her when she is. Inside `ATTEND_NEAR` (2.1 m).
const ALIZ_NEAR_SIDE: float = 1.1

var _suffix: String = "before"
var _frame: Vector2i = Vector2i(1334, 750)
var _viewport: SubViewport = null
var _world: Node = null
var _child: Node = null
var _aliz: Node3D = null
var _camera: Camera3D = null
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
	print("=== bunny reactions, %s, %dx%d ===" % [_suffix, _frame.x, _frame.y])

	await process_frame
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

	# The first-run tour and a forced state never run together in the game; a
	# harness that skips this photographs the tour's caption into every frame.
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

	_child = _find_child_actor()
	if _child == null:
		return _die("no ChildActor in the bedroom -- Bunny is not present")
	_aliz = _world.call("get_character") as Node3D
	_camera = _world.call("get_camera") as Camera3D
	if _camera == null:
		return _die("the house has no camera")

	# CONTENT -- nothing wrong, standing about.
	await _case("content", {"hunger": 5.0, "thirst": 5.0, "happiness": 90.0},
		Present.ACTIVITY_IDLE, "", 2.4, false)
	# HUNGRY -- the state the game opens in.
	await _case("hungry", {"hunger": 70.0}, Present.ACTIVITY_IDLE, "", 0.4, false)
	# ...and the far end of the same axis, which drives the fuss FASTER.
	await _case("crying", {"hunger": 95.0}, Present.ACTIVITY_IDLE, "", 0.4, false)
	# ATTENTION -- Aliz walks up and Bunny turns to watch her.
	await _case("attention", {"hunger": 70.0}, Present.ACTIVITY_IDLE, "", 0.4, true)
	# FED -- a bottle, then a spoon. Two different motions on purpose.
	await _case("drinking", {"hunger": 30.0, "thirst": 70.0},
		Present.ACTIVITY_FEEDING, "giveBottle", 1.2, false)
	await _case("eating", {"hunger": 70.0, "thirst": 10.0},
		Present.ACTIVITY_FEEDING, "giveSnack", 1.1, false)
	# HAPPY -- the only "you did it" this game has.
	await _case("happy", {"hunger": 8.0, "happiness": 95.0},
		Present.ACTIVITY_IDLE, "", 0.9, false, true)
	# SLEEPY -- the last pose cut in the game, or not, depending on the build.
	await _case("sleepy", {"hunger": 10.0, "thirst": 10.0, "energy": 8.0},
		Present.ACTIVITY_BEDTIME, "", 1.6, false)

	_report()


## One state: set the child's real stats, let the game derive everything from
## them, freeze the clip at the phase that carries the pose, photograph twice.
func _case(label: String, stats: Dictionary, activity: String, detail: String,
		phase: float, aliz_near: bool, celebrate: bool = false) -> void:
	_child.set_process(true)
	var state: Object = _child.get("_state")
	# A clean slate every time, so a stat left over from the previous case cannot
	# quietly become the dominant need in this one.
	for key: String in ["hunger", "thirst", "energy", "cleanliness", "freshness", "happiness"]:
		state.call("set_stat", key, _rested(key))
	for key: String in stats.keys():
		state.call("set_stat", key, float(stats[key]))

	if _aliz != null:
		var bunny_at: Vector3 = Spatial.world_position(_child as Node3D)
		Spatial.set_world_position(_aliz, bunny_at + Vector3(ALIZ_NEAR_SIDE, 0.0, 0.4)
			if aliz_near else ALIZ_AWAY)
	_child.call("set_activity", activity, detail)
	_child.call("_refresh")
	if celebrate:
		# Through the real entry point: being cared for is what opens the happy
		# window, and forcing the clip by hand would photograph a code path the
		# game never takes.
		_child.call("satisfy", Needs.HUNGRY, 70.0)
	# Let the attention turn run -- it is per-frame and procedural, so it needs
	# real frames rather than a single call.
	for _i: int in range(70):
		_child.call("live", 1.0 / 60.0)
		await process_frame

	var player: AnimationPlayer = _animation_player()
	var clip: String = String(_child.call("get_life_clip"))
	_child.set_process(false)
	if player != null and player.has_animation(clip):
		player.play(clip)
		player.advance(0.0)
		player.pause()
		player.seek(phase, true)
		player.advance(0.0)
	await process_frame

	print("\n  -- %s --" % label)
	print("     need='%s' clip='%s' pose='%s' distress=%.2f watching=%s mood='%s'" % [
		String(_child.call("get_need")), clip, String(_child.call("get_pose")),
		float(_child.call("get_distress")), str(_child.call("is_watching_caregiver")),
		String(_child.call("get_face_mood")) if _child.has_method("get_face_mood") else "-"])
	if clip.is_empty() and String(_child.call("get_pose")) == Present.POSE_RIGGED:
		_fail.append("%s: the rigged Bunny is playing nothing at all" % label)

	# The shipping bedroom shot.
	_camera.call("restore_room_frame")
	_camera.call("settle")
	await _hold()
	await _shot("bunny_%s_room_%s" % [label, _suffix])

	# ...and the game's own close-up, opened the way a care beat opens it.
	var head: Vector3 = Spatial.world_position(_child as Node3D) + Vector3(0.0, 0.62, 0.0)
	_camera.call("focus_activity", head, 0.5)
	_camera.call("settle")
	await _hold()
	await _shot("bunny_%s_near_%s" % [label, _suffix])


## The value a stat holds when nothing is wrong with it.
func _rested(key: String) -> float:
	return 8.0 if key in ["hunger", "thirst"] else 95.0


## Renders a few frames without advancing the child, so the camera's own easing
## and the SubViewport both catch up before the capture.
func _hold() -> void:
	for _i: int in range(4):
		await process_frame


func _animation_player() -> AnimationPlayer:
	var model: Node = _child.get_node_or_null("Model")
	if model == null or not model.has_method("get_animation_player"):
		return null
	return model.call("get_animation_player") as AnimationPlayer


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
	print("     %s %s.png  %dx%d" % [
		"shot" if err == OK else "FAIL", out_name, image.get_width(), image.get_height()])
	if err != OK:
		_fail.append("could not write %s.png" % out_name)
	# The size WRITTEN, read back off the image -- the request is the thing that
	# has lied before.
	if Vector2i(image.get_width(), image.get_height()) != _frame:
		_fail.append("%s.png is %dx%d but %dx%d was asked for"
			% [out_name, image.get_width(), image.get_height(), _frame.x, _frame.y])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _die(message: String) -> void:
	print("BUNNY SHOTS FAIL: %s" % message)
	quit(1)


func _report() -> void:
	print("")
	for note: String in _notes:
		print("  note: %s" % note)
	if _fail.is_empty():
		print("BUNNY SHOTS OK (%s)." % _suffix)
		quit(0)
	else:
		print("BUNNY SHOTS FAIL (%s) -- %d problem(s):" % [_suffix, _fail.size()])
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)
