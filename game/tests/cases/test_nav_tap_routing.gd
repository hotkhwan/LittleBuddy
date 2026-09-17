extends RefCounted

## What a tap means, and where it is sent.
##
## `NavigationController.classify_tap()` and `target_id_for()` are static and
## pure, so everything genuinely fiddly about routing a child's tap -- ancestor
## walking, disabled targets falling through to the floor, taps above the horizon
## -- is assertable without a camera, a viewport or a physics world. Only the
## raycast itself needs an engine, and it is a three-line function.
##
## Covers required behaviours 1, 2 and 4 at the input layer, and the invariant
## that keeps behaviour 3 (drag/drop) working.

const NavigationController := preload("res://scripts/navigation/navigation_controller.gd")
const ActivityTarget := preload("res://scripts/navigation/activity_target.gd")
const InteractionPoint := preload("res://scripts/navigation/interaction_point.gd")
const DraggableObjectScript := preload("res://scripts/interaction/draggable_object.gd")


## Minimal duck-typed stand-in for an `ActivityTarget`, so the routing tests do
## not drag a whole Area3D and its collision shape in with them.
class FakeTarget extends Node3D:
	var id: String = "toyBox"
	var enabled: bool = true
	var described: int = 0

	func get_activity_target_id() -> String:
		return id

	func is_target_enabled() -> bool:
		return enabled

	func describe(approach_from: Vector3) -> Dictionary:
		described += 1
		return {
			"targetId": id,
			"enabled": enabled,
			"standPosition": global_position + Vector3(0.0, 0.0, 0.6),
			"facePosition": global_position,
			"arrivalRadius": 0.22,
			"approachFrom": approach_from,
		}


## Records what the controller asked the character to do.
class FakeCharacter extends Node3D:
	var target_moves: Array = []
	var ground_moves: Array = []
	var accept: bool = true

	func move_to(target: Variant) -> bool:
		target_moves.append(String(target))
		return accept

	func move_to_ground(x: float, z: float) -> bool:
		ground_moves.append(Vector2(x, z))
		return accept

	func register_activity_target(_target: Object) -> bool:
		return true


func test_name() -> String:
	return "nav_tap_routing"


func run():
	var failures: Array = []
	failures.append_array(_test_target_id_resolution())
	failures.append_array(_test_classify_tap())
	failures.append_array(_test_apply_tap_routes_to_the_character())
	failures.append_array(_test_activity_target_node())
	failures.append_array(_test_layers_do_not_collide_with_dragging())
	return failures


func _test_target_id_resolution() -> Array:
	var failures: Array = []

	if not NavigationController.target_id_for(null).is_empty():
		failures.append("a tap that hit nothing must resolve to no target")

	var target := FakeTarget.new()
	if NavigationController.target_id_for(target) != "toyBox":
		failures.append("a target should resolve to its own id")

	# Ancestor walk: the raycast hits a collision shape or a mesh, not the target
	# node itself, so the id has to be found by walking up the tree.
	var shape := Node3D.new()
	var mesh := Node3D.new()
	target.add_child(shape)
	shape.add_child(mesh)
	if NavigationController.target_id_for(mesh) != "toyBox":
		failures.append("the id should be found on an ancestor of whatever the ray hit")

	# A disabled target is not tappable -- and importantly the tap FALLS THROUGH
	# rather than being swallowed, so a child still walks towards it.
	target.enabled = false
	if not NavigationController.target_id_for(mesh).is_empty():
		failures.append("a disabled target must not claim a tap")
	target.enabled = true

	# A target with a blank id is a scene authoring mistake, not a crash.
	target.id = "   "
	if not NavigationController.target_id_for(mesh).is_empty():
		failures.append("a blank target id must resolve to no target")

	# An unrelated node with no ancestors at all.
	var loose := Node3D.new()
	if not NavigationController.target_id_for(loose).is_empty():
		failures.append("a plain node should resolve to no target")
	loose.free()
	target.free()
	return failures


func _test_classify_tap() -> Array:
	var failures: Array = []
	var down: Vector3 = Vector3(0.0, -1.0, -1.0).normalized()
	var origin := Vector3(0.0, 4.0, 4.0)

	var target := FakeTarget.new()
	var on_target: Dictionary = NavigationController.classify_tap(target, origin, down, 0.0)
	if int(on_target["kind"]) != NavigationController.TapKind.TARGET:
		failures.append("a tap on a target should classify as TARGET")
	if String(on_target["targetId"]) != "toyBox":
		failures.append("a target tap should carry the semantic id")

	var on_floor: Dictionary = NavigationController.classify_tap(null, origin, down, 0.0)
	if int(on_floor["kind"]) != NavigationController.TapKind.FLOOR:
		failures.append("a tap that hit no target should classify as FLOOR")
	if not is_equal_approx(float(on_floor["x"]), 0.0) or not is_equal_approx(float(on_floor["z"]), 0.0):
		failures.append("the floor tap should land at the ray/floor intersection, got (%f, %f)"
				% [float(on_floor["x"]), float(on_floor["z"])])

	# GENEROUS BY DESIGN: the floor is an analytic plane, not a collider, so a tap
	# anywhere below the horizon lands on it -- there is no thin floor mesh to
	# miss and no gap between rug and floorboard.
	var far_corner: Dictionary = NavigationController.classify_tap(
		null, origin, Vector3(-0.9, -0.3, -0.3).normalized(), 0.0
	)
	if int(far_corner["kind"]) != NavigationController.TapKind.FLOOR:
		failures.append("a shallow tap towards the far corner should still land on the floor")

	# Above the horizon: nothing happens. No crash, no walk to a garbage
	# coordinate somewhere past the room.
	var sky: Dictionary = NavigationController.classify_tap(
		null, origin, Vector3(0.0, 0.4, -1.0).normalized(), 0.0
	)
	if int(sky["kind"]) != NavigationController.TapKind.NONE:
		failures.append("a tap above the horizon should classify as NONE")
	if String(sky["reason"]) != "aboveHorizon":
		failures.append("an ignored tap should say why, got '%s'" % String(sky["reason"]))

	# A disabled target does not eat the tap: it falls through to the floor
	# underneath, so the child still gets movement rather than nothing.
	target.enabled = false
	var through: Dictionary = NavigationController.classify_tap(target, origin, down, 0.0)
	if int(through["kind"]) != NavigationController.TapKind.FLOOR:
		failures.append("a tap on a disabled target should fall through to the floor")
	target.free()
	return failures


func _test_apply_tap_routes_to_the_character() -> Array:
	var failures: Array = []
	var controller: Node3D = NavigationController.new()
	var character := FakeCharacter.new()
	controller.call("bind_character", character, character)

	controller.call("apply_tap", {"kind": NavigationController.TapKind.TARGET, "targetId": "toyBox"})
	if character.target_moves != ["toyBox"]:
		failures.append("a TARGET tap should call move_to() with the id, got %s"
				% str(character.target_moves))
	if not character.ground_moves.is_empty():
		failures.append("a TARGET tap must not also trigger a floor walk")

	controller.call("apply_tap", {"kind": NavigationController.TapKind.FLOOR, "x": 1.5, "z": -2.0})
	if character.ground_moves.size() != 1 or not character.ground_moves[0].is_equal_approx(Vector2(1.5, -2.0)):
		failures.append("a FLOOR tap should call move_to_ground() with the point, got %s"
				% str(character.ground_moves))

	# `move_to_ground(x, z)` takes plain floats: the whole input path from tap to
	# character crosses no 3D type.
	controller.call("apply_tap", {"kind": NavigationController.TapKind.NONE, "reason": "aboveHorizon"})
	if character.ground_moves.size() != 1 or character.target_moves.size() != 1:
		failures.append("an ignored tap must not move the character at all")

	controller.free()
	character.free()
	return failures


func _test_activity_target_node() -> Array:
	var failures: Array = []
	var target: Area3D = ActivityTarget.new()
	target.set("target_id", "toyBox")
	target.set("stand_distance", 0.5)
	target.position = Vector3(2.0, 0.0, -2.0)

	# Everything must work WITHOUT `_ready()` -- the headless runner never fires it.
	if target.call("get_activity_target_id") != "toyBox":
		failures.append("an activity target must work before _ready() runs")
	if int(target.get("collision_layer")) != ActivityTarget.ACTIVITY_TARGET_LAYER:
		failures.append("an activity target should put itself on the activity layer")
	if bool(target.get("input_ray_pickable")):
		failures.append("an activity target must not take part in viewport picking, or it "
				+ "could swallow a press a draggable needed")

	# With no InteractionPoint, the stand position is computed on the side the
	# character approaches from.
	var from_south: Vector3 = target.call("get_stand_position", Vector3(2.0, 0.0, 2.0))
	if from_south.z <= target.position.z:
		failures.append("without an interaction point, the stand position should be on the "
				+ "approach side, got %s" % str(from_south))

	var from_north: Vector3 = target.call("get_stand_position", Vector3(2.0, 0.0, -6.0))
	if from_north.z >= target.position.z:
		failures.append("the computed stand position should follow the approach direction")

	# With an authored InteractionPoint, that wins outright.
	var point: Marker3D = InteractionPoint.new()
	point.name = "InteractionPoint"
	point.position = Vector3(0.0, 0.0, 0.9)
	target.add_child(point)
	# The lazy resolve already ran, so force a fresh instance for the authored case.
	var authored: Area3D = ActivityTarget.new()
	authored.set("target_id", "sink")
	authored.position = Vector3(2.0, 0.0, -2.0)
	var authored_point: Marker3D = InteractionPoint.new()
	authored_point.name = "InteractionPoint"
	authored_point.position = Vector3(0.0, 0.0, 0.9)
	authored.add_child(authored_point)

	var described: Dictionary = authored.call("describe", Vector3(0.0, 0.0, 5.0))
	if String(described.get("targetId", "")) != "sink":
		failures.append("describe() should report the semantic id")
	var stand: Vector3 = described.get("standPosition", Vector3.ZERO)
	if not stand.is_equal_approx(Vector3(2.0, 0.0, -1.1)):
		failures.append("an authored interaction point should win over the computed one, got %s"
				% str(stand))
	var face: Vector3 = described.get("facePosition", Vector3.ZERO)
	if not face.is_equal_approx(Vector3(2.0, 0.0, -2.0)):
		failures.append("the facing position should default to the object itself, got %s" % str(face))

	authored.call("set_target_enabled", false)
	if bool(authored.call("describe", Vector3.ZERO).get("enabled", true)):
		failures.append("a disabled target should say so")

	target.free()
	authored.free()
	return failures


## The invariant behind required behaviour 3. Activity targets and draggable
## pickups must never share a collision layer, or tap-to-walk raycasts and drag
## picking would fight over the same objects.
func _test_layers_do_not_collide_with_dragging() -> Array:
	var failures: Array = []
	var draggable_layer: int = 1  # set in DraggableObject._ready()
	if ActivityTarget.ACTIVITY_TARGET_LAYER & draggable_layer != 0:
		failures.append("the activity-target layer (%d) overlaps the draggable layer (%d)"
				% [ActivityTarget.ACTIVITY_TARGET_LAYER, draggable_layer])

	# And the assumption about the draggable layer is checked against the real
	# source, so a change there breaks this test rather than breaking dragging.
	var source: String = _read("res://scripts/interaction/draggable_object.gd")
	if not source.contains("collision_layer = 1"):
		failures.append("draggable_object.gd no longer sets collision_layer = 1; the "
				+ "activity-target layer choice needs revisiting")
	if DraggableObjectScript == null:
		failures.append("could not load draggable_object.gd")
	return failures


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
