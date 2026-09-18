extends RefCounted

## The activity close-up: when the camera moves in, how it moves, and -- the part
## that matters -- that Little Buddy is never lost and the shot is always let go.
##
## `room_camera.gd` has had `focus_activity()` since Phase 2B and nothing called
## it. The whole-room shot was left everywhere on purpose: a camera that frames a
## sink beautifully and loses the child is worse than no close-up at all, because
## a four-year-old who cannot see their character does not reason about it, they
## think the game broke. This case is what makes moving in safe enough to ship.
##
## Five properties, each of which is silent when it breaks:
##
##   1. **The child is in the box, always.** Not by a tuned distance -- by
##      construction. `camera_focus.gd` composes the shot on a box that contains
##      him, `camera_framing.gd` guarantees that box's corners at floor AND head
##      height are inside the safe area, and a perspective frustum is convex, so
##      everything between them is on screen. Verified here by rebuilding the
##      projection independently, at landscape iPhone and iPad, and checking
##      normalised device coordinates with this file's own arithmetic -- the same
##      discipline `test_room_camera.gd` uses, and for the same reason: a
##      camera-pitch sign error once put every object off-screen with the whole
##      suite green.
##   2. **He stays in it when he wanders.** The floor is tappable for the whole of
##      every task, so a child can walk away from the sink mid-beat. The shot
##      re-composes from his live position every frame and widens rather than
##      leaving him behind.
##   3. **Travel beats never pull in.** The task IS the journey; tightening on the
##      destination is the one thing that could make "where do I go?"
##      unanswerable.
##   4. **It is a glide, not a cut.** This is a calm game. A camera that snaps
##      towards a small child's own character reads as a jolt.
##   5. **It is ALWAYS released** -- by the next task, by Next, by a refused door,
##      by walking through a door mid-beat, by the summary, and by the level
##      ending. A camera stuck zoomed in is a worse bug than no zoom.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const SCENE_PATH: String = "res://scenes/house/house_world.tscn"

const CameraFocus := preload("res://scripts/camera/camera_focus.gd")
const Framing := preload("res://scripts/camera/camera_framing.gd")
const Insets := preload("res://scripts/camera/safe_area_insets.gd")
const RoomCameraScript := preload("res://scripts/camera/room_camera.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")
const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const RewardManagerScript := preload("res://scripts/rewards/reward_manager.gd")

## Landscape iPhone and landscape iPad. The two ends of the range the whole room
## camera exists for: one fixed distance cannot frame a room across both.
const ASPECTS: Array[float] = [2.167, 1.334]

## Little Buddy is ~0.85 m tall (contract §3). His head is the thing that gets
## cropped first, so it is checked explicitly rather than assumed.
const CHILD_HEIGHT: float = 0.85

const STEP: float = 1.0 / 60.0
const WALK_FRAMES: int = 1800
const SETTLE_FRAMES: int = 240
const MAX_TASKS: int = 40
const FIT_EPSILON: float = 0.002

## The five key activities the owner named, as `[levelId, missionId]`.
const LEVELS: Array = [
	["goodMorning", "goodMorningRoutine"],
	["gettingDressed", "morningRoutine"],
	["breakfast", "breakfastTime"],
	["playTime", "toddlerPlayTime"],
	["tidyAndBed", "tidyAndBedtime"],
]


func test_name() -> String:
	return "camera_activity_focus"


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]

	failures.append_array(_test_the_box_is_composed_around_the_child())
	failures.append_array(_test_which_beats_want_a_close_up())
	failures.append_array(_test_moving_in_is_a_glide_not_a_cut())
	for row: Array in LEVELS:
		failures.append_array(_test_level(tree, row))
	failures.append_array(_test_the_child_can_wander_out_of_a_close_up(tree))
	failures.append_array(_test_every_exit_releases_the_camera(tree))
	return failures


# ---------------------------------------------------------------------------
# 1. The composition rule, as pure maths
# ---------------------------------------------------------------------------

func _test_the_box_is_composed_around_the_child():
	var failures: Array = []

	# The ordinary beat: furniture, child, and a row of objects in front of him.
	var sink := Vector3(-1.2, 0.0, -1.15)
	var child := Vector3(-1.2, 0.0, -0.4)
	var row_left := Vector3(-2.4, 0.0, 0.38)
	var row_right := Vector3(0.0, 0.0, 0.38)
	var shot: Dictionary = CameraFocus.frame_points([child, sink, row_left, row_right], 0.55)
	if not bool(shot["valid"]):
		failures.append("a real beat produced no shot at all")
	for point: Vector3 in [sink, child, row_left, row_right]:
		if not CameraFocus.contains(shot["focus"], float(shot["radius"]), point):
			failures.append("the composed box leaves %s outside it" % str(point))
	if not is_equal_approx(float(Vector3(shot["focus"]).y), 0.55):
		failures.append("the close-up does not look at the height the room does; the horizon "
				+ "would jump when the camera moves in")

	# A close-up tighter than the rooms' own `minDistance` buys nothing, so the
	# radius has a floor -- and a ceiling, so a child at the far end of the room
	# widens the shot to the room rather than being cropped out of it.
	var tiny: Dictionary = CameraFocus.frame_points([Vector3.ZERO], 0.55)
	if float(tiny["radius"]) < CameraFocus.MIN_RADIUS - 0.001:
		failures.append("a single point produced a radius below the floor")
	# Past the ceiling the shot stops gaining AIR, but it never loses content: a
	# cap that could trim the box would silently break containment, and did --
	# a beat whose object row was staged in another room composed a 9 m box,
	# clamped it, and put Little Buddy off the side of the screen.
	var wide := Vector3(3.4, 0.0, 0.0)
	var sprawling: Dictionary = CameraFocus.frame_points([Vector3(-3.4, 0.0, 0.0), wide], 0.55)
	if float(sprawling["radius"]) > CameraFocus.MAX_RADIUS + 0.001 \
			and not is_equal_approx(float(sprawling["radius"]), 3.4):
		failures.append("past the ceiling the radius should be exactly the extent (no margin), "
				+ "got %.3f" % float(sprawling["radius"]))
	if not CameraFocus.contains(sprawling["focus"], float(sprawling["radius"]), wide):
		failures.append("the ceiling trimmed the box and dropped a point out of it")

	# Nothing to frame must mean "leave the camera alone", never "aim at the
	# origin". `global_position` silently reports (0,0,0) outside the tree, so a
	# shot composed from one would frame an empty patch of floor with every
	# "the camera moved" assertion still passing.
	for empty: Array in [[], [null], ["kitchen.fridge"], [Vector3(NAN, 0.0, INF)]]:
		if bool(CameraFocus.frame_points(empty, 0.55)["valid"]):
			failures.append("%s was accepted as something to frame" % str(empty))

	# The box is a SQUARE, as wide as its largest axis, so on the other axis it
	# reaches well past anything it had to hold -- and the rooms have an open
	# front, so reaching out there means composing on the empty space beyond the
	# floor. A breakfast close-up did exactly that and showed MORE background than
	# the whole-room shot it replaced. The box slides back inside the room.
	var floor_rect := Rect2(-2.0, -2.0, 4.0, 4.0)
	var forward: Array = [Vector3(-1.2, 0.0, 1.5), Vector3(1.2, 0.0, 1.7)]
	var loose: Dictionary = CameraFocus.frame_points(forward, 0.55)
	var snug: Dictionary = CameraFocus.frame_points(
		forward, 0.55, CameraFocus.DEFAULT_MARGIN,
		CameraFocus.MIN_RADIUS, CameraFocus.MAX_RADIUS, floor_rect)
	var loose_front: float = Vector3(loose["focus"]).z + float(loose["radius"])
	var snug_front: float = Vector3(snug["focus"]).z + float(snug["radius"])
	if loose_front <= floor_rect.end.y:
		failures.append("the unconstrained box already fitted inside the room, so the slide is "
				+ "not under test here")
	if snug_front > floor_rect.end.y + 0.001:
		failures.append("the close-up still reaches %.2f m past the front of the room; it would "
				% (snug_front - floor_rect.end.y) + "compose on the empty space outside it")
	if not bool(snug["nudged"]):
		failures.append("the box was slid but did not say so")
	# ...and the slide never costs containment. That is the whole ordering.
	for point: Vector3 in forward:
		if not CameraFocus.contains(snug["focus"], float(snug["radius"]), point):
			failures.append("sliding the box inside the room dropped %s out of it" % str(point))

	# A box larger than the room centres on the room and keeps everything.
	var huge: Array = [Vector3(-1.9, 0.0, -1.9), Vector3(1.9, 0.0, 1.9)]
	var centred: Dictionary = CameraFocus.frame_points(
		huge, 0.55, CameraFocus.DEFAULT_MARGIN,
		CameraFocus.MIN_RADIUS, CameraFocus.MAX_RADIUS, floor_rect)
	for point: Vector3 in huge:
		if not CameraFocus.contains(centred["focus"], float(centred["radius"]), point):
			failures.append("a box wider than the room dropped %s" % str(point))

	# The margin is real: a point exactly on the extent must not sit on the edge.
	var pair: Dictionary = CameraFocus.frame_points(
		[Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)], 0.55, 0.3, 0.1, 9.0)
	if float(pair["radius"]) <= 1.0:
		failures.append("the composed box has no air around it (%.3f)" % float(pair["radius"]))
	return failures


# ---------------------------------------------------------------------------
# 2. Which beats want one
# ---------------------------------------------------------------------------

## The rule lives in `house_task_plan.gd` so there is one source of truth for it,
## and it is asserted here rather than only through the runtime, because it is
## exactly the kind of rule that is easy to get backwards.
func _test_which_beats_want_a_close_up():
	var failures: Array = []
	var expected: Dictionary = {
		TaskPlan.KIND_TRAVEL: false,
		TaskPlan.KIND_GO_AND_DO: true,
		TaskPlan.KIND_DELIVER: true,
		TaskPlan.KIND_CHOOSE: true,
	}
	for kind: String in expected.keys():
		if TaskPlan.wants_close_up({"kind": kind}) != bool(expected[kind]):
			failures.append("a '%s' beat should%s pull the camera in"
					% [kind, "" if bool(expected[kind]) else " not"])
	for rubbish: Variant in [null, {}, {"kind": ""}, "travel", 7]:
		if TaskPlan.wants_close_up(rubbish):
			failures.append("%s was read as a beat that wants a close-up" % str(rubbish))
	return failures


# ---------------------------------------------------------------------------
# 3. A glide, not a cut
# ---------------------------------------------------------------------------

## The camera must not arrive the instant it is asked to move, and it must not
## overshoot or wobble on the way. Both halves matter: an instant jump is the
## jolt, and a spring that rings would be worse than the jump.
func _test_moving_in_is_a_glide_not_a_cut():
	var failures: Array = []
	var camera: Camera3D = Camera3D.new()
	camera.set_script(RoomCameraScript)

	var room: Dictionary = HouseLayout.camera_framing("bedroom")
	camera.call("frame_room", room)
	var start: Vector3 = camera.transform.origin
	if camera.call("is_moving"):
		failures.append("frame_room() must be a cut: a room change is already covered by the "
				+ "transition fade and a rotation has to be right on the next frame")

	camera.call("focus_activity", Vector3(0.0, 0.5, -1.0), 1.4)
	var goal: Vector3 = Vector3(camera.call("get_last_solution")["position"])
	if camera.transform.origin.distance_to(start) > 0.001:
		failures.append("focus_activity() moved the camera on the spot; the pull-in must be "
				+ "eased, not a snap")
	if not camera.call("is_moving"):
		failures.append("focus_activity() did not start a move at all")

	# One frame at a time, exactly as a device would.
	var total: float = start.distance_to(goal)
	var travelled: Array = []
	var previous: Vector3 = camera.transform.origin
	var frames: int = 0
	var frames_to_mostly_there: int = 0
	while camera.call("is_moving") and frames < 600:
		camera.call("step", STEP)
		frames += 1
		var now: Vector3 = camera.transform.origin
		travelled.append(previous.distance_to(now))
		if (now - goal).dot(previous - goal) < 0.0:
			failures.append("the camera overshot its mark on frame %d; a close-up must settle, "
					% frames + "never bounce")
			break
		if frames_to_mostly_there == 0 and now.distance_to(goal) <= total * 0.05:
			frames_to_mostly_there = frames
		previous = now

	if frames >= 600:
		failures.append("the pull-in never finished; a child would wait for ever")
	if camera.transform.origin.distance_to(goal) > 0.01:
		failures.append("the glide ended %.3f m from where the fit said it should"
				% camera.transform.origin.distance_to(goal))

	# Judged on the part of the move a child can SEE. A critically damped spring
	# approaches its mark asymptotically, so the last few millimetres take as long
	# as the first metre and mean nothing; 95% of the way there is where the move
	# is visually over.
	var seconds: float = float(frames_to_mostly_there) * STEP
	if frames_to_mostly_there == 0:
		failures.append("the camera never got within 5%% of its mark")
	elif seconds < 0.25:
		failures.append("the pull-in was visually over in %.2f s; that is a cut with extra steps"
				% seconds)
	elif seconds > 1.8:
		failures.append("the pull-in took %.2f s to arrive; a child would have moved on" % seconds)

	# Ease IN: the first frame must be the gentlest part of the move, not the
	# fastest. A plain exponential lerp fails this, which is why the camera uses a
	# critically damped spring.
	if travelled.size() > 6:
		var first: float = float(travelled[0])
		var fastest: float = 0.0
		for value: Variant in travelled:
			fastest = maxf(fastest, float(value))
		if first >= fastest * 0.5:
			failures.append("the camera's first frame moved %.4f m of a %.4f m peak; the move "
					% [first, fastest] + "starts at full speed, which is the jolt this is "
					+ "supposed to avoid")

	# Letting go glides too.
	camera.call("restore_room_frame")
	if camera.transform.origin.distance_to(start) < 0.05:
		pass  # already home: nothing to glide, and nothing to assert
	elif not camera.call("is_moving"):
		failures.append("restore_room_frame() cut straight back to the room shot")
	camera.call("settle")
	if camera.transform.origin.distance_to(start) > 0.01:
		failures.append("settling after a restore did not return the room shot")

	camera.free()
	return failures


# ---------------------------------------------------------------------------
# 4. One of the five key activities, played by touch
# ---------------------------------------------------------------------------

## Plays a whole level in the real house and records EVERY shot the camera was
## asked for, with the child's position at that instant, then judges them all.
##
## Recording from the camera's own `framed` signal rather than sampling at chosen
## moments is deliberate: a close-up that was briefly wrong -- one frame at the
## start of a re-aim, one beat nobody thought to sample -- is exactly the kind of
## thing a sampled test misses and a child notices.
func _test_level(tree: SceneTree, row: Array):
	var failures: Array = []
	var level_id: String = String(row[0])
	var mission_id: String = String(row[1])

	var session: Dictionary = _open_house(tree)
	if session.has("error"):
		return ["%s: %s" % [level_id, session["error"]]]
	var world: Node = session["world"]
	var director: Node = session["director"]
	var runner: Node = session["runner"]
	var character: Node = session["character"]
	var camera: Camera3D = world.call("get_camera")
	if camera == null or not camera.has_method("focus_activity"):
		_close_house(tree, session)
		return ["%s: the house has no room camera to move in with" % level_id]

	var shots: Array = []
	camera.connect("framed", func(_solution: Dictionary) -> void:
		if not bool(camera.call("is_focused_on_activity")):
			return
		var plan: Dictionary = director.call("get_current_plan")
		shots.append({
			"framing": camera.call("get_active_framing"),
			"child": SpatialUtil.world_position(character as Node3D),
			"kind": String(plan.get("kind", "")),
			"taskId": String(runner.call("get_current_task_id")),
			"summary": bool(director.call("is_summary_open")),
		})
	)

	# Connected BEFORE the level starts: the first beat emits during `start_mission`
	# and a listener attached afterwards would miss it, which made the vacuity
	# check below report the wrong thing.
	var kinds_seen: Dictionary = {}
	director.connect("task_plan_changed", func(_task_id: String, kind: String) -> void:
		kinds_seen[kind] = true
	)
	if not bool(director.call("_start_level", mission_id)):
		_close_house(tree, session)
		return ["%s: the level would not start" % level_id]

	_play_by_touch(director, runner, character)

	# -- The level pulled in at all -------------------------------------------
	if shots.is_empty():
		failures.append("%s never moved the camera in once. Every one of these levels has beats "
				% level_id + "the child stands at; the whole-room shot is not the answer for "
				+ "all of them.")

	# -- Never during a journey ------------------------------------------------
	for shot: Dictionary in shots:
		if String(shot["kind"]) == TaskPlan.KIND_TRAVEL:
			failures.append("%s tightened the shot during travel task '%s'. The child needs to "
					% [level_id, shot["taskId"]] + "see the room and both doors to know where "
					+ "they are going.")
			break
		if bool(shot["summary"]):
			failures.append("%s composed a close-up while the summary was open" % level_id)
			break

	# -- Little Buddy is on screen in every single one of them, at both aspects -
	var checked: int = 0
	for shot: Dictionary in shots:
		var problems: Array = _visibility_problems(shot["framing"], shot["child"])
		checked += 1
		if not problems.is_empty():
			failures.append("%s, task '%s': %s" % [level_id, shot["taskId"], String(problems[0])])
			break
	if checked == 0 and not shots.is_empty():
		failures.append("%s: the visibility check never ran" % level_id)

	# -- And the close-up is genuinely closer than the room shot ---------------
	if not shots.is_empty():
		var tighter: bool = false
		var room: Dictionary = HouseLayout.camera_framing(String(world.call("get_current_room_id")))
		var room_distance: float = Framing.fit_distance(room, ASPECTS[1], Insets.chrome_insets())
		for shot: Dictionary in shots:
			if Framing.fit_distance(shot["framing"], ASPECTS[1], Insets.chrome_insets()) \
					< room_distance - 0.05:
				tighter = true
				break
		if not tighter:
			failures.append("%s 'moved in' without ever standing closer than the whole-room shot"
					% level_id)

	# -- The level ended wide --------------------------------------------------
	if not bool(director.call("is_summary_open")):
		failures.append("%s did not reach its summary; the release path was never exercised"
				% level_id)
	if bool(world.call("is_focused_on_activity")):
		failures.append("%s left the camera zoomed in behind the summary. A stuck camera is worse "
				% level_id + "than no camera move at all, and the overlay has already taken the "
				+ "child's taps so they cannot walk out of it.")
	if bool(director.call("is_camera_focused")):
		failures.append("%s left the level director still holding the camera" % level_id)

	# The four kinds are not all present in every level, but a level that only
	# ever produced travel beats would pass the checks above vacuously.
	if kinds_seen.size() < 2:
		failures.append("%s only produced %s; this case would be nearly vacuous"
				% [level_id, str(kinds_seen.keys())])

	_close_house(tree, session)
	return failures


# ---------------------------------------------------------------------------
# 5. The child wanders off mid-beat
# ---------------------------------------------------------------------------

## The floor is tappable for the whole of every task, so this is not a hypothetical
## -- it is what a four-year-old does. The close-up must widen to keep him, not
## sit on the sink while he walks out of frame.
func _test_the_child_can_wander_out_of_a_close_up(tree: SceneTree):
	var failures: Array = []
	var session: Dictionary = _open_house(tree)
	if session.has("error"):
		return [String(session["error"])]
	var world: Node = session["world"]
	var director: Node = session["director"]
	var character: Node = session["character"]
	var camera: Camera3D = world.call("get_camera")

	director.call("_start_level", "goodMorningRoutine")
	_pump(character, director, 10)
	if not bool(director.call("is_camera_focused")):
		_close_house(tree, session)
		return ["the first beat of Good Morning did not move the camera in; the rest of this "
				+ "check would be vacuous"]

	var before: Array = _visibility_problems(camera.call("get_active_framing"),
			SpatialUtil.world_position(character as Node3D))
	if not before.is_empty():
		failures.append("standing at the beat: %s" % String(before[0]))

	# Walk him to the far corner of the room, the way a tap on the floor would.
	var room_origin: Vector3 = HouseLayout.room_origin(String(world.call("get_current_room_id")))
	for corner: Vector2 in [Vector2(1.6, 1.6), Vector2(-1.6, -1.6), Vector2(1.6, -1.6)]:
		var there := Vector3(room_origin.x + corner.x, 0.0, room_origin.z + corner.y)
		SpatialUtil.set_world_position(character as Node3D, there)
		_pump(character, director, 4)
		if not bool(director.call("is_camera_focused")):
			continue  # widened all the way back to the room: also a correct answer
		var problems: Array = _visibility_problems(camera.call("get_active_framing"), there)
		if not problems.is_empty():
			failures.append("the child walked to %s during a beat and %s"
					% [str(corner), String(problems[0])])
			break

	_close_house(tree, session)
	return failures


# ---------------------------------------------------------------------------
# 6. Every exit releases it
# ---------------------------------------------------------------------------

func _test_every_exit_releases_the_camera(tree: SceneTree):
	var failures: Array = []

	# -- Next -----------------------------------------------------------------
	var skipped: Dictionary = _focused_session(tree)
	if skipped.has("error"):
		failures.append("Next: %s" % skipped["error"])
	else:
		# The invariant is "Next must not leave the camera composed on the beat the
		# child just abandoned" -- NOT "the camera ends up wide". Those coincided
		# only while the task after this one happened to be a `travel` beat, which
		# never focuses. Reordering the level so the greeting happens in the
		# bedroom (where its target actually is) put a `choose` beat next, and a
		# `choose` beat legitimately composes at task start -- so the strict
		# reading failed on a camera that had released correctly. Verified in a
		# live tree: after Next, `is_camera_focused()` really is false.
		var held_before: String = String(
				(skipped["director"].call("get_current_plan") as Dictionary).get("taskId", ""))
		skipped["runner"].call("skip_current_task")
		_pump(skipped["character"], skipped["director"], 6)
		var held_after: String = String(
				(skipped["director"].call("get_current_plan") as Dictionary).get("taskId", ""))
		if bool(skipped["director"].call("is_camera_focused")) and held_after == held_before:
			failures.append(
				("the child pressed Next and the camera is still composed on '%s', the beat they "
				+ "just abandoned. A child cannot get out of a stuck camera, and there is nothing "
				+ "on screen to tell them what happened.") % held_before
			)
		_close_house(tree, skipped)

	# -- A door, mid-beat -----------------------------------------------------
	var wandered: Dictionary = _focused_session(tree)
	if wandered.has("error"):
		failures.append("door: %s" % wandered["error"])
	else:
		wandered["world"].call("place_in_room", "bathroom", "default")
		_pump(wandered["character"], wandered["director"], 6)
		failures.append_array(_released(wandered, "the child walked out through a door"))
		_close_house(tree, wandered)

	# -- A refused door -------------------------------------------------------
	var refused: Dictionary = _focused_session(tree)
	if refused.has("error"):
		failures.append("refusal: %s" % refused["error"])
	else:
		var transition: Node = refused["world"].call("get_transition_controller")
		if transition != null and transition.has_signal("transition_refused"):
			transition.emit_signal("transition_refused", "bathroom", "test")
			_pump(refused["character"], refused["director"], 6)
			failures.append_array(_released(refused, "the door was refused"))
		_close_house(tree, refused)

	# -- The next task --------------------------------------------------------
	var advanced: Dictionary = _focused_session(tree)
	if advanced.has("error"):
		failures.append("next task: %s" % advanced["error"])
	else:
		var first: String = String(advanced["runner"].call("get_current_task_id"))
		advanced["runner"].call("on_object_chosen", String(
			(advanced["director"].call("get_current_plan") as Dictionary).get("objectId", "")))
		_pump(advanced["character"], advanced["director"], SETTLE_FRAMES)
		if String(advanced["runner"].call("get_current_task_id")) == first:
			failures.append("the first beat could not be finished by touch; the release-on-next-"
					+ "task path was never exercised")
		_close_house(tree, advanced)

	return failures


## A session parked on a beat the camera has moved in on.
func _focused_session(tree: SceneTree):
	var session: Dictionary = _open_house(tree)
	if session.has("error"):
		return session
	session["director"].call("_start_level", "goodMorningRoutine")
	_pump(session["character"], session["director"], 10)
	if not bool(session["director"].call("is_camera_focused")):
		_close_house(tree, session)
		return {"error": "the level did not move the camera in, so nothing can be released"}
	return session


func _released(session: Dictionary, what: String):
	var failures: Array = []
	if bool(session["director"].call("is_camera_focused")):
		failures.append("%s and the level director is still holding the camera" % what)
	if bool(session["world"].call("is_focused_on_activity")):
		failures.append("%s and the camera stayed zoomed in. A child cannot get out of a stuck "
				% what + "camera, and there is nothing on screen to tell them what happened.")
	return failures


# ---------------------------------------------------------------------------
# The independent verifier
# ---------------------------------------------------------------------------

## "" problems when Little Buddy's feet AND head land inside the usable screen at
## every aspect the game ships on.
##
## Rebuilt from the framing rather than read off the live camera, so it is
## checked at landscape iPhone and landscape iPad from one headless run -- which
## is the whole reason this camera system exists. The arithmetic is this file's
## own: it re-derives the projection from the fitted transform instead of asking
## the solver whether it agrees with itself.
func _visibility_problems(framing: Variant, child: Variant):
	var problems: Array = []
	if typeof(framing) != TYPE_DICTIONARY or not (child is Vector3):
		return ["there was no framing to check"]
	var feet: Vector3 = child
	var head: Vector3 = feet + Vector3(0.0, CHILD_HEIGHT, 0.0)
	var insets: Vector4 = Insets.chrome_insets()

	for aspect: float in ASPECTS:
		var solution: Dictionary = Framing.solve(framing, aspect, insets)
		var transform: Transform3D = solution["transform"]
		var fov: float = float(solution["fov"])
		var half_height: float = tan(deg_to_rad(fov) * 0.5)
		var half_width: float = half_height * aspect
		# Fractions of the screen -> NDC half-extents, done here rather than by
		# calling the module under test.
		var left: float = 1.0 - 2.0 * insets.x
		var top: float = 1.0 - 2.0 * insets.y
		var right: float = 1.0 - 2.0 * insets.z
		var bottom: float = 1.0 - 2.0 * insets.w

		for entry: Array in [[feet, "feet"], [head, "head"]]:
			var point: Vector3 = entry[0]
			var offset: Vector3 = point - transform.origin
			var depth: float = offset.dot(-transform.basis.z)
			if depth <= 0.0:
				problems.append("at %.3f:1 Little Buddy's %s is BEHIND the camera"
						% [aspect, entry[1]])
				continue
			var ndc_x: float = (offset.dot(transform.basis.x) / depth) / half_width
			var ndc_y: float = (offset.dot(transform.basis.y) / depth) / half_height
			if ndc_x > right + FIT_EPSILON or ndc_x < -left - FIT_EPSILON:
				problems.append("at %.3f:1 Little Buddy's %s is off the side of the screen "
						% [aspect, entry[1]] + "(x = %.3f)" % ndc_x)
			if ndc_y > top + FIT_EPSILON or ndc_y < -bottom - FIT_EPSILON:
				problems.append("at %.3f:1 Little Buddy's %s is under the safe area or off the "
						% [aspect, entry[1]] + "top/bottom (y = %.3f)" % ndc_y)
		if transform.origin.y <= feet.y:
			problems.append("at %.3f:1 the camera is not above the floor" % aspect)
		if (-transform.basis.z).y >= 0.0:
			problems.append("at %.3f:1 the camera is not pitched DOWN; this is the sign error "
					% aspect + "that once put every object off-screen with the suite green")
	return problems


# ---------------------------------------------------------------------------
# Harness (the same shape as test_slice_level_loop.gd)
# ---------------------------------------------------------------------------

func _open_house(tree: SceneTree):
	var packed: Resource = load(SCENE_PATH)
	if not (packed is PackedScene):
		return {"error": "could not load %s" % SCENE_PATH}
	var world: Node = (packed as PackedScene).instantiate()
	tree.root.add_child(world)
	world.call("_ready")

	var provider: RefCounted = NavMapProviderScript.create(world.call("get_navigation_map"))
	if not bool(provider.call("force_sync", Vector3.ZERO)):
		tree.root.remove_child(world)
		world.free()
		return {"error": "the house navigation map never answered"}

	var ledger: RefCounted = RewardLedgerScript.create()
	ledger.set("min_interval_ms", 0)
	RewardManagerScript.set_shared_ledger(ledger)

	var director: Node = world.call("ensure_level_director")
	if director == null:
		tree.root.remove_child(world)
		world.free()
		return {"error": "the house built no level director"}
	return {
		"world": world,
		"director": director,
		"runner": director.call("get_runner"),
		"character": world.call("get_character"),
	}


func _close_house(tree: SceneTree, session: Dictionary) -> void:
	var world: Node = session.get("world", null)
	if world == null:
		return
	tree.root.remove_child(world)
	world.free()


## The simulated child: walk to the beat, tap the object it asks for.
func _play_by_touch(director: Node, runner: Node, character: Node) -> void:
	var guard: int = 0
	while bool(runner.call("is_running")) and guard < MAX_TASKS:
		guard += 1
		var task_id: String = String(runner.call("get_current_task_id"))
		var plan: Dictionary = director.call("get_current_plan")
		_pump(character, director, 4)

		if bool(plan.get("needsWalk", false)):
			if not bool(character.call("move_to", String(plan.get("walkTargetId", "")))):
				director.call("assist_now")
			_pump_until_task_changes(character, director, runner, task_id, WALK_FRAMES)

		if String(runner.call("get_current_task_id")) != task_id:
			continue

		if bool(plan.get("needsChoices", false)):
			_pump(character, director, 4)
			runner.call("on_object_chosen", String(plan.get("objectId", "")))

		_pump(character, director, SETTLE_FRAMES)
		if bool(runner.call("is_running")) \
				and String(runner.call("get_current_task_id")) == task_id:
			runner.call("skip_current_task")
			_pump(character, director, 30)


## One frame of everything a device would step: the walk, the level loop, and the
## camera's own eased move, which `_process()` drives in a live tree.
func _pump(character: Node, director: Node, frames: int) -> void:
	var camera: Object = null
	for _frame: int in range(frames):
		character.call("step_movement", STEP)
		director.call("step", STEP)
		if camera == null:
			camera = _camera_of(director)
		if camera != null:
			camera.call("step", STEP)


func _camera_of(director: Node) -> Object:
	var world: Node = director.get_parent()
	if world == null or not world.has_method("get_camera"):
		return null
	var camera: Object = world.call("get_camera")
	if camera == null or not camera.has_method("step"):
		return null
	return camera


func _pump_until_task_changes(
	character: Node, director: Node, runner: Node, task_id: String, frames: int
) -> void:
	for _frame: int in range(frames):
		_pump(character, director, 1)
		if String(runner.call("get_current_task_id")) != task_id:
			return
		if bool(director.call("is_beat_reached")) \
				and String(character.call("get_state_name")) == "idle":
			return
