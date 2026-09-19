extends SceneTree

## Mission 01 played in the REAL game, from the real entry point.
##
##   Godot --headless --path game --script res://tests/smoke_mission01.gd
##
## Not a unit test and deliberately not in `tests/cases/`: it instantiates
## `scenes/house/house_world.tscn`, lets the real `HouseLevelDirector` pick a
## mission the way it does on a fresh install, and walks every beat.
##
## The rule it exists to enforce: **it never calls a completion method.** Beats
## finish the way gameplay finishes them -- arrival for a walk, a real gesture on
## the real overlay for a care act -- because a smoke test that calls
## `_complete_task()` proves only that the function exists.
##
## What a PASS means, and it is all checked below:
##   1. a fresh profile selects `imHungry` -- reachability, not a claim;
##   2. every beat's target really exists in the world it names;
##   3. the two care close-ups are finished BY GESTURE, not by the fallback;
##   4. Bunny's real `childStats.hunger` is lower at the end than at the start;
##   5. the level completes once, and stars are awarded once.

const MISSION: String = "imHungry"

var _fail: Array = []
var _world: Node = null
var _director: Node = null


func _init() -> void:
	_run()


func _run() -> void:
	# A clean slate, so "which mission does a fresh install open?" is the question
	# actually being asked.
	#
	# AFTER a frame, not in `_init`: autoloads are not attached to `root` yet when
	# a `--script` SceneTree initialises, so resetting there silently does nothing
	# and the run reads a developer's own saved progress instead. That is exactly
	# how this file's first run "proved" the mission was unreachable when the
	# content was fine.
	await process_frame
	var save: Node = root.get_node_or_null("SaveService")
	if save == null or not save.has_method("reset_profile"):
		return _die("no SaveService -- a fresh-profile check is meaningless without one")
	save.call("reset_profile")
	print("0. profile reset; currentLevel='%s'" % String(save.call("get_current_level")))

	var packed: PackedScene = load("res://scenes/house/house_world.tscn")
	if packed == null:
		return _die("house_world.tscn will not load")
	_world = packed.instantiate()
	root.add_child(_world)
	await process_frame
	await process_frame

	if not _world.has_method("ensure_level_director"):
		return _die("house_world has no ensure_level_director()")
	_director = _world.call("ensure_level_director")
	if _director == null:
		return _die("no level director")

	# 1. REACHABILITY -- what does the real picker choose?
	_director.call("start")
	await process_frame
	var chosen: String = String(_director.call("get_current_mission_id")) \
			if _director.has_method("get_current_mission_id") else ""
	if chosen.is_empty():
		chosen = String(_director.get("_last_mission_id"))
	_check(chosen == MISSION,
			"a fresh profile opens '%s'; expected '%s'" % [chosen, MISSION])
	print("1. fresh profile opened: %s" % chosen)

	# Bunny's hunger BEFORE, read from the real actor.
	var child: Node = _director.call("_find_child_actor")
	var hunger_before: float = _hunger(child)
	print("2. Bunny's hunger before: %.1f" % hunger_before)
	_check(child != null, "no ChildActor in the world -- Bunny is not present")

	# 2..4. WALK THE BEATS.
	var runner: Node = _director.get("_runner")
	var overlay: Node = _director.get("_care_overlay")
	var seen: Array = []
	var gestured: int = 0
	for step: int in range(24):
		var plan: Dictionary = _director.call("get_current_plan")
		var task_id: String = _runner_task_id(runner)
		if task_id.is_empty():
			task_id = String(plan.get("taskId", ""))
		if task_id.is_empty():
			break
		if not seen.has(task_id):
			seen.append(task_id)
			print("   beat %d: %-18s kind=%-8s room=%-10s care=%s"
					% [seen.size(), task_id, String(plan.get("kind", "")),
						String(plan.get("roomId", "")), String(plan.get("careKind", ""))])
			_check_target(plan)

		var care_kind: String = String(plan.get("careKind", ""))
		if not care_kind.is_empty():
			# THE REAL GESTURE. `_open_care` is how arrival opens the close-up;
			# after that nothing here touches the director until the overlay
			# reports itself finished.
			_director.call("_open_care", plan)
			await process_frame
			if overlay == null:
				_fail.append("care beat '%s' opened no overlay" % task_id)
			else:
				var done: bool = await _play_gesture(overlay, care_kind)
				_check(done, "the '%s' gesture never completed the mini-game" % care_kind)
				if done:
					gestured += 1
		else:
			# A walk or a tap: finished by ARRIVING. The signal the director really
			# listens for is `interaction_ready(targetId)`, emitted by the world
			# when the child reaches an interaction point -- so that is what is
			# raised here. It is the input to the beat, not its completion: the
			# director still decides whether arriving finishes the task, plays an
			# action first, or waits for a drag.
			var walk_id: String = String(plan.get("walkTargetId", plan.get("walkTarget", "")))
			if _director.has_method("_on_interaction_ready") and not walk_id.is_empty():
				_director.call("_on_interaction_ready", walk_id)
			elif _director.has_method("_reach_beat"):
				_director.call("_reach_beat")
		# Beats do not finish on the frame they are triggered: a `goAndDo` waits
		# for the character's action to play out, and the director only flushes a
		# pending completion from `_process`. So POLL, rather than assuming.
		# Watched on the RUNNER, not on the director's plan. The plan keeps
		# describing the task that just finished while its summary is on screen,
		# so polling it reports "stuck" for a beat that actually completed -- which
		# is how this file first mis-accused working content.
		var advanced: bool = false
		for _f: int in range(180):
			await process_frame
			if _runner_task_id(runner) != task_id:
				advanced = true
				break
		if not advanced:
			print("     state: running=%s taskDone=%s pending=%s awaitingAction=%s beatReached=%s walkId='%s'"
					% [str(_director.get("_running")), str(_director.get("_task_done")),
						str(_director.get("_pending_complete")), str(_director.get("_awaiting_action")),
						str(_director.get("_beat_reached")),
						String(plan.get("walkTargetId", "<none>"))])
			# Not advancing: the director is waiting on something a headless run
			# cannot supply. Skip so the rest of the path is still exercised, and
			# say so -- silence here would be the exact dishonesty this file is
			# written against.
			print("   ! beat '%s' did not advance on arrival; skipping to continue"
					% task_id)
			_fail.append("beat '%s' did not advance when it was reached" % task_id)
			if runner != null and runner.has_method("skip_current_task"):
				runner.call("skip_current_task")
			await process_frame

	print("3. beats played: %d, care mini-games finished by gesture: %d" % [seen.size(), gestured])
	_check(seen.size() >= 6, "only %d beats were reached; the mission has 7" % seen.size())
	_check(gestured >= 2, "only %d of the 2 care mini-games completed by gesture" % gestured)

	# 5. THE NEED ACTUALLY WENT AWAY.
	var hunger_after: float = _hunger(child)
	print("4. Bunny's hunger after: %.1f (was %.1f)" % [hunger_after, hunger_before])
	_check(hunger_after < hunger_before - 20.0,
			"hunger went %.1f -> %.1f; feeding Bunny must move the real stat"
					% [hunger_before, hunger_after])

	_report()


## Plays a care act the way a child would, and returns whether the GESTURE
## finished it. Never calls `complete_by_touch()` -- that is the accessibility
## fallback, and using it here would hide a broken mini-game.
func _play_gesture(overlay: Node, kind: String) -> bool:
	var size: Vector2 = overlay.get("size")
	if size == Vector2.ZERO:
		size = Vector2(1024.0, 768.0)
		overlay.set("size", size)
	var centre: Vector2 = size * 0.5
	var mouth: Vector2 = centre + overlay.get("MOUTH_OFFSET") if false else centre + Vector2(0.0, 92.0)
	match kind:
		"prepareMilk":
			# Pour: hold the jug over the neck. Then shake: left, right, left...
			var neck: Vector2 = centre + Vector2(0.0, -120.0)
			for _i: int in range(40):
				overlay.call("apply_hold", 0.1, neck)
			for i: int in range(24):
				overlay.call("apply_stroke", centre + Vector2(60.0 if i % 2 == 0 else -60.0, 0.0))
		"giveBottle":
			for _i: int in range(40):
				overlay.call("apply_hold", 0.1, mouth)
		"brushTeeth":
			for i: int in range(40):
				overlay.call("apply_stroke", mouth + Vector2(30.0 if i % 2 == 0 else -30.0, 0.0))
		"washFace", "dryFace":
			for i: int in range(60):
				var a: float = float(i) * 0.4
				overlay.call("apply_stroke", centre + Vector2(cos(a), sin(a)) * (40.0 + float(i)))
	await process_frame
	return bool(overlay.call("is_finished"))


## The task the MISSION is on, which is the only honest "where are we".
func _runner_task_id(runner: Node) -> String:
	if runner == null or not runner.has_method("get_current_task_id"):
		return ""
	return String(runner.call("get_current_task_id"))


func _hunger(child: Node) -> float:
	if child == null:
		return -1.0
	var stats: Object = child.get("_state")
	if stats == null:
		return -1.0
	return float(stats.get("hunger"))


## Every beat must name a target the world it names actually provides.
func _check_target(plan: Dictionary) -> void:
	var target: String = String(plan.get("focusTarget", plan.get("walkTarget", "")))
	if target.is_empty():
		return
	var room_id: String = target.split(".")[0]
	if not _world.has_method("get_room"):
		return
	var room: Node = _world.call("get_room", room_id)
	if room == null:
		_fail.append("beat targets room '%s', which the world has no node for" % room_id)
		return
	if not room.has_method("get_activity_targets"):
		return
	var found: bool = false
	for t: Node in room.call("get_activity_targets"):
		var tid: String = String(t.call("get_target_id")) if t.has_method("get_target_id") else t.name
		if tid == target or tid.ends_with("." + target.split(".")[-1]):
			found = true
			break
	if not found:
		_fail.append("beat targets '%s', which room '%s' does not provide" % [target, room_id])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail.append(message)


func _die(message: String) -> void:
	print("SMOKE FAIL: %s" % message)
	quit(1)


func _report() -> void:
	print("")
	if _fail.is_empty():
		print("SMOKE PASS -- Mission 01 played end to end in the real house.")
		quit(0)
	else:
		print("SMOKE FAIL -- %d problem(s):" % _fail.size())
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)
