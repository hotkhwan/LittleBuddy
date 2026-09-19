extends RefCounted

## WHERE BUNNY'S NEED BUBBLE GOES, and the two ways it has already gone wrong.
##
## The line ("I'm hungry!") is a billboarded `Label3D` over a 0.78 m child, and
## the caregiver who stands next to him is more than twice his height. Whether it
## LOOKS right is settled by rendering the beat and looking at it --
## `game/tests/shots_bubble.gd`, `docs/BUBBLE_VERIFICATION.md`. What is pinned
## here is the arithmetic underneath, because both of the bugs those pictures
## caught were arithmetic and both were invisible to every existing test:
##
##   1. **World in, LOCAL out.** The side was chosen by comparing world x and
##      then written into `_bubble.position`, which is the child's LOCAL frame.
##      Bunny is authored yawed 180 degrees in the bedroom, so the sign inverted
##      and the bubble stepped ONTO the caregiver. `_yawed_child_steps_the_right
##      _way()` is that case, and it fails on the old code.
##   2. **Decided once, never again.** Placement ran only from `_refresh()`, so
##      a caregiver walking across never moved it. `_it_follows_a_caregiver_who
##      _moves()` walks her from one side to the other and back.
##
## Everything here drives the real `child_actor.gd` in a real tree. The rule is
## small enough to assert exactly, so it is asserted exactly rather than sampled.

const Actor := preload("res://scripts/care/child_actor.gd")
const Spatial := preload("res://scripts/navigation/spatial_util.gd")

## Anything nearer than this to the intended metre value is the same answer.
const TOLERANCE: float = 0.01


func test_name() -> String:
	return "bubble_placement"


func run():
	var failures: Array = []
	failures.append_array(_test_it_steps_away_from_the_caregiver())
	failures.append_array(_test_a_yawed_child_steps_the_right_way())
	failures.append_array(_test_it_follows_a_caregiver_who_moves())
	failures.append_array(_test_it_stands_down_when_she_is_clear())
	failures.append_array(_test_it_clears_a_longer_line_by_more())
	failures.append_array(_test_it_survives_being_built_outside_the_tree())
	failures.append_array(_test_it_is_only_visible_when_there_is_a_need())
	return failures


## -- The rule ------------------------------------------------------------------

func _test_it_steps_away_from_the_caregiver():
	var failures: Array = []
	var rig: Dictionary = _stage(0.0)
	if rig.is_empty():
		return ["no SceneTree"]
	var child: Node3D = rig["child"]
	var caregiver: Node3D = rig["caregiver"]

	# She is on his screen-left; the line must be on his screen-right.
	_move(caregiver, Vector3(-0.40, 0.0, 0.0))
	child.call("_place_bubble")
	var right: float = _offset(child).x
	if right <= 0.0:
		failures.append("caregiver at x=-0.40: the line went to %+.2f, which is her side"
				% right)

	_move(caregiver, Vector3(0.40, 0.0, 0.0))
	child.call("_place_bubble")
	var left: float = _offset(child).x
	if left >= 0.0:
		failures.append("caregiver at x=+0.40: the line went to %+.2f, which is her side"
				% left)

	# ...and symmetric, because nothing in the rule is handed.
	if absf(absf(right) - absf(left)) > TOLERANCE:
		failures.append("the two sides are not mirror images: %+.2f and %+.2f" % [right, left])

	# The height is unchanged by any of it.
	if absf(_offset(child).y - Actor.BUBBLE_HEIGHT) > TOLERANCE:
		failures.append("the line is at y=%.2f, not BUBBLE_HEIGHT (%.2f)"
				% [_offset(child).y, Actor.BUBBLE_HEIGHT])

	_teardown(rig)
	return failures


## THE REGRESSION. A child yawed 180 degrees -- which is exactly how
## `house_world.tscn` authors Bunny in the bedroom -- must still step AWAY from
## her in world terms. The previous implementation passed the un-yawed case above
## and failed this one, which is why it shipped.
func _test_a_yawed_child_steps_the_right_way():
	var failures: Array = []
	for yaw_degrees: float in [0.0, 90.0, 180.0, -120.0]:
		var rig: Dictionary = _stage(yaw_degrees)
		if rig.is_empty():
			return ["no SceneTree"]
		var child: Node3D = rig["child"]
		var caregiver: Node3D = rig["caregiver"]
		for side: float in [-1.0, 1.0]:
			_move(caregiver, Vector3(side * 0.40, 0.0, 0.0))
			child.call("_place_bubble")
			var world_x: float = _offset(child).x
			if side * world_x >= 0.0:
				failures.append(
					"child yawed %.0f, caregiver at x=%+.2f: the line went to %+.2f -- her side"
							% [yaw_degrees, side * 0.40, world_x])
		_teardown(rig)
	return failures


## The other regression: she WALKS. Placement that only runs when the child's
## need or activity changes never sees her move, so the side is fixed forever at
## whatever was true when the actor was built.
func _test_it_follows_a_caregiver_who_moves():
	var failures: Array = []
	var rig: Dictionary = _stage(180.0)
	if rig.is_empty():
		return ["no SceneTree"]
	var child: Node3D = rig["child"]
	var caregiver: Node3D = rig["caregiver"]

	# Nothing below touches the need or the activity -- only her position and the
	# actor's own per-frame `live()`, which is what `_process()` calls.
	_move(caregiver, Vector3(-0.40, 0.0, 0.0))
	child.call("live", 0.016)
	var first: float = _offset(child).x

	_move(caregiver, Vector3(0.40, 0.0, 0.0))
	child.call("live", 0.016)
	var second: float = _offset(child).x

	if first * second >= 0.0:
		failures.append("she crossed from x=-0.40 to x=+0.40 and the line stayed at %+.2f"
				% second)
	_teardown(rig)
	return failures


## Past the clearance there is nothing to dodge, and a line parked out to one
## side belongs to the floor rather than to the child. It must come home.
func _test_it_stands_down_when_she_is_clear():
	var failures: Array = []
	var rig: Dictionary = _stage(180.0)
	if rig.is_empty():
		return ["no SceneTree"]
	var child: Node3D = rig["child"]
	var caregiver: Node3D = rig["caregiver"]

	_move(caregiver, Vector3(-3.0, 0.0, 0.0))
	child.call("live", 0.016)
	if absf(_offset(child).x) > TOLERANCE:
		failures.append("she is 3 m away and the line is still stepped aside by %+.2f"
				% _offset(child).x)

	# ...and the step grows smoothly as she closes, rather than snapping on.
	var previous: float = 0.0
	for distance: float in [1.2, 0.9, 0.6, 0.3, 0.0]:
		_move(caregiver, Vector3(-distance, 0.0, 0.0))
		child.call("live", 0.016)
		var step: float = _offset(child).x
		if step < previous - TOLERANCE:
			failures.append("the step shrank from %+.2f to %+.2f as she came closer (%.1f m)"
					% [previous, step, distance])
		previous = step
	_teardown(rig)
	return failures


## The need lines are not all one width. A step sized for "I'm hungry!" leaves
## "I need changing." lying across her, so the step is derived from the rendered
## width and a longer line must move further.
func _test_it_clears_a_longer_line_by_more():
	var failures: Array = []
	var rig: Dictionary = _stage(0.0)
	if rig.is_empty():
		return ["no SceneTree"]
	var child: Node3D = rig["child"]
	var caregiver: Node3D = rig["caregiver"]
	var bubble: Label3D = child.call("get_need_bubble")
	if bubble == null:
		_teardown(rig)
		return ["the actor exposes no bubble"]
	_move(caregiver, Vector3(0.0, 0.0, -0.6))

	bubble.text = "I'm hungry!"
	child.call("_place_bubble")
	var short_step: float = absf(_offset(child).x)

	bubble.text = "I need changing."
	child.call("_place_bubble")
	var long_step: float = absf(_offset(child).x)

	if long_step <= short_step + TOLERANCE:
		failures.append("a longer line stepped %.2f m, no further than the short one's %.2f m"
				% [long_step, short_step])
	# Both must actually clear her, which is the reason the rule exists.
	for pair: Array in [["I'm hungry!", short_step], ["I need changing.", long_step]]:
		if float(pair[1]) < Actor.CAREGIVER_HALF_WIDTH:
			failures.append("'%s' steps only %.2f m, inside her own half-width (%.2f m)"
					% [String(pair[0]), float(pair[1]), Actor.CAREGIVER_HALF_WIDTH])
	_teardown(rig)
	return failures


## `build()` legitimately runs outside the tree -- `get_activity_target()` reaches
## it while the room is still being assembled -- where a global transform is
## invalid. It must not error, and it must not stay stuck on the answer it had to
## guess there.
func _test_it_survives_being_built_outside_the_tree():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]

	var child: Node3D = Actor.new()
	# The call the house really makes before the actor is parented.
	if child.call("get_activity_target") == null:
		failures.append("get_activity_target() returned nothing outside the tree")
	var bubble: Label3D = child.call("get_need_bubble")
	if bubble == null:
		child.free()
		return ["the actor built no bubble"]
	if absf(bubble.position.x) > TOLERANCE:
		failures.append("built outside the tree, the line guessed a side (%+.2f) instead of "
				% bubble.position.x + "sitting over his own head")

	# Now put it in a world with a caregiver to its left, and the side must be
	# right by the time anything can see it.
	var rig: Dictionary = _stage(180.0, child)
	if rig.is_empty():
		child.free()
		return ["no SceneTree"]
	_move(rig["caregiver"], Vector3(-0.40, 0.0, 0.0))
	child.call("live", 0.016)
	if _offset(child).x <= 0.0:
		failures.append("after entering the tree the line is at %+.2f, on her side"
				% _offset(child).x)
	_teardown(rig)
	return failures


## A content child says nothing, and a silent bubble must not cost anything to
## place either -- `live()` skips it entirely.
func _test_it_is_only_visible_when_there_is_a_need():
	var failures: Array = []
	var rig: Dictionary = _stage(0.0)
	if rig.is_empty():
		return ["no SceneTree"]
	var child: Node3D = rig["child"]
	var bubble: Label3D = child.call("get_need_bubble")
	var stats: Object = child.call("get_stats")

	stats.call("set_stat", "hunger", 90.0)
	child.call("_refresh")
	if not bubble.visible:
		failures.append("a hungry child's line is hidden")
	if bubble.text.strip_edges().is_empty():
		failures.append("a hungry child's line is empty")

	for axis: String in ["hunger", "thirst"]:
		stats.call("set_stat", axis, 0.0)
	for axis: String in ["happiness", "energy", "cleanliness", "freshness"]:
		stats.call("set_stat", axis, 100.0)
	child.call("_refresh")
	if bubble.visible:
		failures.append("a content child is still saying '%s'" % bubble.text)
	_teardown(rig)
	return failures


## -- Staging -------------------------------------------------------------------

## A child at the origin, yawed `yaw_degrees`, under a parent that answers
## `get_character()` -- which is the one thing `_find_caregiver()` looks for, so
## this is the real lookup and not a stub of it.
func _stage(yaw_degrees: float, existing: Node3D = null) -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return {}
	var host: Node3D = Node3D.new()
	host.set_script(_host_script())
	var caregiver: Node3D = Node3D.new()
	caregiver.name = "Caregiver"
	host.add_child(caregiver)
	host.set("character", caregiver)

	var child: Node3D = existing if existing != null else Actor.new()
	child.rotation.y = deg_to_rad(yaw_degrees)
	host.add_child(child)
	tree.root.add_child(host)
	child.call("build")
	# A need, so there is a line to place at all.
	child.call("get_stats").call("set_stat", "hunger", 70.0)
	child.call("_refresh")
	return {"host": host, "child": child, "caregiver": caregiver}


func _teardown(rig: Dictionary) -> void:
	var host: Node = rig.get("host")
	if host != null and is_instance_valid(host):
		host.get_parent().remove_child(host)
		host.queue_free()


## Through `SpatialUtil`, not `global_position`. The headless runner never starts
## the tree -- `_initialize()` returns before the root is inside it -- so every
## node in this case is permanently out of tree, and `global_position` would both
## log an error and silently do nothing.
func _move(caregiver: Node3D, world: Vector3) -> void:
	Spatial.set_world_position(caregiver, world)


## Where the line sits relative to the child in WORLD metres, which is the frame
## the rule is stated in and the frame the bug was in.
func _offset(child: Node3D) -> Vector3:
	return child.call("get_bubble_world_offset")


## The smallest thing that answers `get_character()`.
##
## `child_actor._find_caregiver()` walks up its ancestors looking for that one
## method and nothing else -- it learns no scene layout, by design -- so a
## stand-in that has it IS the caregiver as far as the code under test is
## concerned. Built from source here rather than kept as a fixture file so the
## whole of this case is readable in one place.
const HOST_SOURCE: String = """extends Node3D
var character: Node3D = null
func get_character() -> Node3D:
	return character
"""


func _host_script() -> GDScript:
	var script: GDScript = GDScript.new()
	script.source_code = HOST_SOURCE
	script.reload()
	return script
