extends RefCounted

## CLICK-TO-MOVE NEVER FREEZES -- driven on the REAL house, tap by tap.
##
## Owner feedback (2026-09-20): "click-to-move freezes / stuck pose". Every
## way a tap could be swallowed that the team could think of is reproduced here
## against `house_world.tscn` in Free Play, through the router
## (`NavigationController.apply_tap`) and the body (`step_movement`), and each
## must end with Aliz having MOVED and come back to rest with no pose held:
##
##   1. a floor tap while a held pose (`sit`) is in effect;
##   2. a floor tap while a `hold` pose is in effect;
##   3. a floor tap during a one-shot action (`wave`);
##   4. a floor tap DURING a room transition (refused, and the very next tap
##      after the transition walks);
##   5. a floor tap while carrying Bunny -- she walks, he rides;
##   6. the same spot tapped twice -- one walk, one arrival, and a third tap
##      after arrival still works;
##   7. a tap on the apron in front of the room, well off the mesh -- she walks
##      as far as she can towards it instead of doing nothing;
##   8. a touch press and its emulated mouse twin count as ONE tap.
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const MODE_FREE_PLAY: int = 1
const DT: float = 1.0 / 60.0
const TAP_FLOOR: int = 2
const TAP_TARGET: int = 1


func test_name() -> String:
	return "click_to_move_freeze"


func run():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var director: Node = world.call("ensure_free_play_director")
	if director != null:
		director.call("start")
	var aliz: Node3D = world.call("get_character")
	var nav: Node = world.get_node("NavigationController")

	failures.append_array(_case_held_pose(world, aliz, nav, "sit"))
	failures.append_array(_case_held_pose(world, aliz, nav, "hold"))
	failures.append_array(_case_mid_action(world, aliz, nav))
	failures.append_array(_case_during_transition(world, aliz, nav))
	failures.append_array(_case_while_carrying(world, aliz, nav))
	failures.append_array(_case_same_spot_twice(world, aliz, nav))
	failures.append_array(_case_apron_tap(world, aliz, nav))
	failures.append_array(_case_emulated_twin(nav))

	_release(world)
	return failures


## -- Cases -----------------------------------------------------------------------

func _case_held_pose(world, aliz, nav, pose: String):
	var failures: Array = []
	world.call("place_in_room", "bedroom", "")
	aliz.call("play_action", pose)
	_walk(aliz, 120)
	if String(aliz.call("get_held_action")) != pose:
		failures.append("%s: the pose was not held after its settle time (held '%s')"
				% [pose, aliz.call("get_held_action")])
	var p: Vector3 = _floor_point(world, -0.8, 0.9)
	var before: Vector3 = SpatialUtil.world_position(aliz)
	if not _tap_floor(nav, p):
		failures.append("%s: a floor tap while the pose was held was refused" % pose)
	_walk(aliz, 20)
	if not String(aliz.call("get_held_action")).is_empty():
		failures.append("%s: the pose is still held after a walk request" % pose)
	if SpatialUtil.world_position(aliz).distance_to(before) < 0.2:
		failures.append("%s: Aliz did not move after the tap (%.2f m)" % [pose, SpatialUtil.world_position(aliz).distance_to(before)])
	_walk(aliz, 400)
	failures.append_array(_expect_arrived(aliz, p, "%s then tap" % pose))
	return failures


func _case_mid_action(world, aliz, nav):
	var failures: Array = []
	aliz.call("play_action", "wave")
	_walk(aliz, 5)
	if String(aliz.call("get_state_name")) != "interacting":
		failures.append("wave: the action did not start")
	var p: Vector3 = _floor_point(world, 0.9, 1.2)
	if not _tap_floor(nav, p):
		failures.append("wave: a floor tap during the action was refused")
	_walk(aliz, 400)
	failures.append_array(_expect_arrived(aliz, p, "tap during wave"))
	return failures


func _case_during_transition(world, aliz, nav):
	var failures: Array = []
	world.call("place_in_room", "bedroom", "")
	var transition: Node = world.call("get_transition_controller")
	var during: Array = []
	var probe: Callable = func(_from: String, _to: String) -> void:
		during.append(_tap_floor(nav, _floor_point(world, 0.0, 0.0)))
	transition.connect("transition_started", probe)
	nav.call("apply_tap", {"kind": TAP_TARGET, "targetId": "bedroom.doorToKitchen", "x": 0.0, "z": 0.0, "reason": ""})
	_walk(aliz, 900)
	transition.disconnect("transition_started", probe)
	if String(world.call("get_current_room_id")) != "kitchen":
		failures.append("transition: walking to the kitchen door did not change room (still %s)"
				% world.call("get_current_room_id"))
	if during.is_empty():
		failures.append("transition: the probe tap never fired")
	elif bool(during[0]):
		failures.append("transition: a tap during the transition was accepted; control is off then")
	if String(aliz.call("get_state_name")) == "disabled":
		failures.append("transition: Aliz is still disabled after the transition")
	# The very next tap walks.
	var p: Vector3 = _floor_point(world, 0.5, 0.8)
	var before: Vector3 = SpatialUtil.world_position(aliz)
	if not _tap_floor(nav, p):
		failures.append("transition: the first tap after arriving was refused")
	_walk(aliz, 400)
	if SpatialUtil.world_position(aliz).distance_to(before) < 0.2:
		failures.append("transition: Aliz did not move after the first tap in the new room")
	failures.append_array(_expect_arrived(aliz, p, "tap after transition"))
	return failures


func _case_while_carrying(world, aliz, nav):
	var failures: Array = []
	world.call("place_in_room", "bedroom", "")
	var bunny: Node = world.get_node_or_null("Rooms/Bedroom/LittleBuddyChild")
	if bunny == null:
		return ["carrying: no Bunny in the bedroom"]
	SpatialUtil.set_world_position(aliz, SpatialUtil.world_position(bunny) + Vector3(0.0, 0.0, 0.62))
	if not bool(bunny.call("perform_affordance", aliz)):
		failures.append("carrying: CARRY on Bunny was refused")
	_walk(aliz, 60)
	if String(aliz.call("get_carry_state")) != "held":
		failures.append("carrying: Bunny is not held after the lift (%s)" % aliz.call("get_carry_state"))
	var p: Vector3 = _floor_point(world, 1.2, 1.4)
	var before: Vector3 = SpatialUtil.world_position(aliz)
	if not _tap_floor(nav, p):
		failures.append("carrying: a floor tap while carrying was refused")
	var worst_gap: float = 0.0
	var carry: Node = aliz.call("get_carry_controller")
	for _frame: int in range(400):
		aliz.call("step_movement", DT)
		var wanted: Transform3D = carry.call("held_transform")
		worst_gap = maxf(worst_gap, SpatialUtil.world_position(bunny).distance_to(wanted.origin))
	if SpatialUtil.world_position(aliz).distance_to(before) < 0.2:
		failures.append("carrying: Aliz did not move with Bunny in her arms")
	if worst_gap > 0.02:
		failures.append("carrying: Bunny trailed the socket by %.3f m during the walk" % worst_gap)
	if not bool(aliz.call("is_carrying_node")):
		failures.append("carrying: Bunny was dropped by the walk")
	failures.append_array(_expect_arrived(aliz, p, "tap while carrying"))
	if not bool(aliz.call("put_down_carried")):
		failures.append("carrying: put-down after the walk was refused")
	_walk(aliz, 60)
	if bool(aliz.call("is_carrying_node")):
		failures.append("carrying: Bunny is still in her arms after put-down")
	return failures


func _case_same_spot_twice(world, aliz, nav):
	var failures: Array = []
	var controller: RefCounted = aliz.call("get_movement_controller")
	var p: Vector3 = _floor_point(world, -0.6, 0.4)
	var serial_before: int = int(controller.call("get_move_serial"))
	if not _tap_floor(nav, p):
		failures.append("twice: the first tap was refused")
	_walk(aliz, 10)
	if not _tap_floor(nav, p):
		failures.append("twice: the second tap on the same spot was refused")
	if int(controller.call("get_move_serial")) != serial_before + 1:
		failures.append("twice: the second tap restarted the walk (serial %d -> %d)"
				% [serial_before, int(controller.call("get_move_serial"))])
	_walk(aliz, 400)
	failures.append_array(_expect_arrived(aliz, p, "same spot twice"))
	# A third tap on the spot she is standing on: accepted, arrives at once,
	# nothing held, nothing stuck.
	if not _tap_floor(nav, p):
		failures.append("twice: a tap on the spot she stands on was refused")
	_walk(aliz, 30)
	failures.append_array(_expect_arrived(aliz, p, "third tap on the spot"))
	return failures


func _case_apron_tap(world, aliz, nav):
	var failures: Array = []
	world.call("place_in_room", "bedroom", "")
	var start: Vector3 = _floor_point(world, 0.0, 0.0)
	SpatialUtil.set_world_position(aliz, start)
	aliz.call("stop")
	# 5 m in front of the room: the visible stage apron, nowhere near the mesh.
	var apron: Vector3 = _floor_point(world, 0.4, 7.0)
	if not _tap_floor(nav, apron):
		failures.append("apron: a tap on the floor in front of the room did nothing at all")
	_walk(aliz, 600)
	var here: Vector3 = SpatialUtil.world_position(aliz)
	if here.distance_to(start) < 0.8:
		failures.append("apron: Aliz only moved %.2f m towards the tap" % here.distance_to(start))
	if here.z < start.z + 0.8:
		failures.append("apron: Aliz did not walk TOWARDS the tap (z %.2f -> %.2f)" % [start.z, here.z])
	if bool(aliz.call("is_busy")):
		failures.append("apron: Aliz is still busy after walking to the room's edge")
	return failures


func _case_emulated_twin(nav):
	var failures: Array = []
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(600.0, 400.0)
	if bool(nav.call("is_emulated_twin", touch)):
		failures.append("twin: the touch press itself was called a twin")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(601.0, 400.0)
	if not bool(nav.call("is_emulated_twin", mouse)):
		failures.append("twin: the emulated mouse press right after a touch was routed as a second tap")
	var later := InputEventMouseButton.new()
	later.button_index = MOUSE_BUTTON_LEFT
	later.pressed = true
	later.position = Vector2(900.0, 100.0)
	if bool(nav.call("is_emulated_twin", later)):
		failures.append("twin: a real mouse press somewhere else was swallowed")
	return failures


## -- Helpers -------------------------------------------------------------------------

func _expect_arrived(aliz, p: Vector3, label: String):
	var failures: Array = []
	var here: Vector3 = SpatialUtil.world_position(aliz)
	if Vector2(here.x - p.x, here.z - p.z).length() > 0.3:
		failures.append("%s: Aliz stopped %.2f m from the tap" % [label, Vector2(here.x - p.x, here.z - p.z).length()])
	if bool(aliz.call("is_busy")):
		failures.append("%s: Aliz is still busy (%s) after the walk" % [label, aliz.call("get_state_name")])
	if not String(aliz.call("get_held_action")).is_empty():
		failures.append("%s: a pose ('%s') is held after a plain floor walk" % [label, aliz.call("get_held_action")])
	var player: AnimationPlayer = _find_player(aliz)
	if player != null and player.is_playing() and player.current_animation in ["walk", "run"]:
		failures.append("%s: the walk clip is still playing while she stands" % label)
	return failures


func _tap_floor(nav, p: Vector3) -> bool:
	return bool(nav.call("apply_tap", {"kind": TAP_FLOOR, "targetId": "", "x": p.x, "z": p.z, "reason": ""}))


func _floor_point(world, dx: float, dz: float) -> Vector3:
	var room: Node3D = world.call("get_current_room")
	return SpatialUtil.world_position(room) + Vector3(dx, 0.0, dz)


func _walk(aliz, frames: int) -> void:
	for _i: int in range(frames):
		aliz.call("step_movement", DT)


func _find_player(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			return child
		var deeper: AnimationPlayer = _find_player(child)
		if deeper != null:
			return deeper
	return null


func _build_house():
	if not ResourceLoader.exists(HOUSE_SCENE):
		return null
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	world.call("set_progression_mode", MODE_FREE_PLAY)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	world.call("build_world")
	return world


func _release(world) -> void:
	if world == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()
