extends RefCounted

## PICK UP / PLACE, for props: bottle, toy, food, bowl -- the same carry that
## holds Bunny, holding a `SpawnedObject` in the hand and setting it down on a
## `DropZone`.
##
## Asserted, on real spawned objects from `content/objects.json`:
##   1. `take`: the object visibly leaves its row (its parent changes, it rises
##      to the hand socket) and rides in her `itemHoldRight` socket as she walks;
##   2. its own drag input is off while carried and back afterwards;
##   3. `place` on a zone: it lands AT the zone, is handed back to the world,
##      remembers the new spot as home, and delivers through the same `chosen`
##      funnel a drag would -- once, and only to the zone it was assigned;
##   4. the affordance contract on both, including the refusals (hands full,
##      a child in her arms, nothing carried);
##   5. four categories of object all carry.
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const CharacterScript := preload("res://scripts/character/little_buddy_character.gd")
const BuddyViewScript := preload("res://scripts/characters/buddy/pink_girl_buddy.gd")
const ChildActorScript := preload("res://scripts/care/child_actor.gd")
const CarryScript := preload("res://scripts/interaction/carry_controller.gd")
const SpawnerScript := preload("res://scripts/gameplay/object_spawner.gd")
const DropZoneScript := preload("res://scripts/gameplay/drop_zone.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

const DT: float = 1.0 / 60.0
const OBJECTS_PATH: String = "res://content/objects.json"


func test_name() -> String:
	return "carry_props"


func run():
	var failures: Array = []
	failures.append_array(_test_take_carry_place())
	failures.append_array(_test_affordance_refusals())
	failures.append_array(_test_every_category_carries())
	return failures


func _objects() -> Dictionary:
	var file: FileAccess = FileAccess.open(OBJECTS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var rows: Array = parsed.get("objects", []) if parsed is Dictionary else (parsed as Array)
	var by_id: Dictionary = {}
	for row: Variant in rows:
		if row is Dictionary:
			by_id[String(row.get("objectId", ""))] = row
	return by_id


func _stage() -> Dictionary:
	var room: Node3D = Node3D.new()
	var aliz: CharacterBody3D = CharacterScript.new()
	aliz.name = "LittleBuddy"
	aliz.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var view: Node3D = BuddyViewScript.new()
	view.name = "BuddyView"
	aliz.add_child(view)
	view.call("build")
	room.add_child(aliz)
	var row: Node3D = Node3D.new()
	row.name = "ObjectRow"
	room.add_child(row)
	row.position = Vector3(0.0, 0.0, -0.9)
	return {"room": room, "aliz": aliz, "view": view, "row": row}


func _spawn(stage: Dictionary, object_id: String, interaction: String = "dragToToyBox") -> Area3D:
	var data: Dictionary = _objects().get(object_id, {})
	if data.is_empty():
		return null
	var object: Area3D = SpawnerScript.spawn(data, interaction)
	(stage["row"] as Node).add_child(object)
	object.call("set_home_position", Vector3(0.3, 0.0, 0.0))
	return object


func _step(aliz: Node, frames: int) -> void:
	for _i: int in range(frames):
		aliz.call("step_movement", DT)


## -- 1..3 The whole loop on a toy -------------------------------------------------

func _test_take_carry_place():
	var failures: Array = []
	var stage: Dictionary = _stage()
	var aliz: CharacterBody3D = stage["aliz"]
	var room: Node3D = stage["room"]
	var toy: Area3D = _spawn(stage, "teddy")
	if toy == null:
		(stage["room"] as Node).free()
		return ["could not spawn 'teddy' from %s" % OBJECTS_PATH]
	var zone: Area3D = DropZoneScript.create(DropZoneScript.ZONE_TOY_BOX, 0.3)
	room.add_child(zone)
	zone.position = Vector3(1.2, 0.0, -0.4)
	toy.call("set_drop_zone", zone, 0.3)
	var chosen: Array = []
	toy.connect("chosen", func(id: String) -> void: chosen.append(id))
	var delivered: Array = []
	zone.connect("object_delivered", func(id: String) -> void: delivered.append(id))

	var source_parent: Node = toy.get_parent()
	var start: Vector3 = SpatialUtil.world_position(toy)

	# TAKE.
	var offer: Dictionary = toy.call("get_affordance", aliz)
	if String(offer.get("verb", "")) != "take":
		failures.append("a spawned toy offers '%s', not 'take'" % offer.get("verb", ""))
	if not toy.is_in_group("affordable"):
		failures.append("the spawned object is not in the 'affordable' group")
	if not bool(toy.call("perform_affordance", aliz)):
		failures.append("perform_affordance(take) returned false")
		(stage["room"] as Node).free()
		return failures
	if toy.get_parent() == source_parent:
		failures.append("the toy is still in its row after being taken")
	if bool(toy.get("drag_enabled")) or toy.input_ray_pickable:
		failures.append("a carried toy is still draggable / pickable")
	_step(aliz, int(CarryScript.PICK_UP_SEC / DT) + 3)
	if String(aliz.call("get_carry_state")) != CarryScript.STATE_HELD:
		failures.append("state after the lift is '%s'" % aliz.call("get_carry_state"))
	var controller: Node = aliz.call("get_carry_controller")
	if String(controller.call("get_socket_name")) != "itemHoldRight":
		failures.append("the toy is held at '%s', not itemHoldRight" % controller.call("get_socket_name"))
	if not bool(controller.call("is_using_socket")):
		failures.append("the toy is on the fallback offset, not her hand socket")
	var held: Vector3 = SpatialUtil.world_position(toy)
	if held.distance_to(start) < 0.2:
		failures.append("the toy barely moved (%.2f m) when taken; it should be in her hand"
				% held.distance_to(start))
	if held.y < 0.35:
		failures.append("held toy's origin is %.2f m up; that is on the floor, not in a hand" % held.y)
	# She faces -Z, so her right is +X.
	var local: Vector3 = SpatialUtil.world_transform(aliz).affine_inverse() * held
	if local.x < 0.05:
		failures.append("the toy is not in her RIGHT hand (local x %.2f)" % local.x)

	# CARRY: she walks, it comes.
	for _i: int in range(45):
		aliz.call("drive", 0.0, 1.0)
		aliz.call("step_movement", DT)
	aliz.call("stop_driving")
	_step(aliz, 20)
	if SpatialUtil.world_position(toy).distance_to(held) < 0.4:
		failures.append("she walked and the toy stayed behind")
	if not chosen.is_empty():
		failures.append("the toy delivered itself while merely being carried")

	# PLACE on the zone.
	var place: Dictionary = zone.call("get_affordance", aliz)
	if String(place.get("verb", "")) != "place":
		failures.append("a zone offers '%s' to a caregiver holding a toy, not 'place'"
				% place.get("verb", ""))
	if not zone.is_in_group("affordable"):
		failures.append("the drop zone is not in the 'affordable' group")
	if not bool(zone.call("perform_affordance", aliz)):
		failures.append("perform_affordance(place) returned false")
	if not chosen.is_empty():
		failures.append("delivered before landing: the reaction would fire with the toy in the air")
	_step(aliz, int(CarryScript.PLACE_SEC / DT) + 3)
	var landed: Vector3 = SpatialUtil.world_position(toy)
	if landed.distance_to(SpatialUtil.world_position(zone)) > 0.02:
		failures.append("the toy landed %.2f m from the zone" % landed.distance_to(SpatialUtil.world_position(zone)))
	if toy.get_parent() != source_parent:
		failures.append("after landing the toy was not handed back to where it came from")
	if not bool(toy.get("drag_enabled")) or not toy.input_ray_pickable:
		failures.append("a placed toy did not get its drag input back")
	if (toy.call("get_home_position") as Vector3).distance_to(toy.position) > 0.001:
		failures.append("the toy's home is still its old row slot; reset_position() would fling it back")
	if chosen != ["teddy"]:
		failures.append("landing on its zone delivered %s; expected exactly ['teddy']" % str(chosen))
	if delivered != ["teddy"]:
		failures.append("the zone reported %s delivered" % str(delivered))
	if bool(aliz.call("is_carrying_node")):
		failures.append("her hands are still full after placing")
	if aliz.call("get_state_name") != "idle":
		failures.append("her state is '%s' after placing, not idle" % aliz.call("get_state_name"))

	# Placing on a zone that is NOT the object's does not deliver.
	var other: Area3D = DropZoneScript.create(DropZoneScript.ZONE_BATH, 0.3)
	room.add_child(other)
	other.position = Vector3(-1.0, 0.0, -0.5)
	toy.call("perform_affordance", aliz)
	_step(aliz, 40)
	other.call("perform_affordance", aliz)
	_step(aliz, 40)
	if chosen.size() != 1:
		failures.append("placing on a foreign zone delivered (%s)" % str(chosen))
	if SpatialUtil.world_position(toy).distance_to(SpatialUtil.world_position(other)) > 0.02:
		failures.append("the toy did not land on the foreign zone it was placed on")
	(stage["room"] as Node).free()
	return failures


## -- 4. Refusals ----------------------------------------------------------------------

func _test_affordance_refusals():
	var failures: Array = []
	var stage: Dictionary = _stage()
	var aliz: CharacterBody3D = stage["aliz"]
	var room: Node3D = stage["room"]
	var bowl: Area3D = _spawn(stage, "bowl", "tap")
	var spoon: Area3D = _spawn(stage, "spoon", "tap")
	var zone: Area3D = DropZoneScript.create(DropZoneScript.ZONE_HAND, 0.3)
	room.add_child(zone)
	zone.position = Vector3(0.8, 0.0, -0.6)
	if bowl == null or spoon == null:
		room.free()
		return ["could not spawn bowl/spoon"]

	if not zone.call("get_affordance", aliz).is_empty():
		failures.append("a zone offered 'place' to empty hands")
	if not bowl.call("get_affordance", null).is_empty():
		failures.append("a null actor was offered 'take'")
	var stranger: Node3D = Node3D.new()
	room.add_child(stranger)
	if not bowl.call("get_affordance", stranger).is_empty():
		failures.append("a node that cannot carry was offered 'take'")

	bowl.call("perform_affordance", aliz)
	_step(aliz, 40)
	if not spoon.call("get_affordance", aliz).is_empty():
		failures.append("'take' offered on the spoon while the bowl is in her hand")
	if not bool(spoon.call("perform_affordance", aliz)) == false:
		failures.append("a second take with full hands succeeded")
	if not bowl.call("get_affordance", aliz).is_empty():
		failures.append("the bowl offers 'take' while already in her hand")

	# A child in her arms is not placed on a pad.
	aliz.call("put_down_carried", Vector3(0.0, 0.0, -1.4))
	_step(aliz, 40)
	var bunny: Node3D = ChildActorScript.new()
	room.add_child(bunny)
	bunny.position = Vector3(0.0, 0.0, -0.6)
	bunny.call("build")
	aliz.call("carry_node", bunny)
	_step(aliz, 40)
	if not zone.call("get_affordance", aliz).is_empty():
		failures.append("a zone offered 'place' for a CHILD in her arms")
	if not spoon.call("get_affordance", aliz).is_empty():
		failures.append("'take' offered while carrying the child")
	room.free()
	return failures


## -- 5. Bottle, toy, food, bowl ---------------------------------------------------

func _test_every_category_carries():
	var failures: Array = []
	for object_id: String in ["milk", "teddy", "banana", "bowl"]:
		var stage: Dictionary = _stage()
		var aliz: CharacterBody3D = stage["aliz"]
		var object: Area3D = _spawn(stage, object_id, "tap")
		if object == null:
			failures.append("could not spawn '%s'" % object_id)
			(stage["room"] as Node).free()
			continue
		if not bool(aliz.call("carry_node", object)):
			failures.append("'%s' could not be picked up" % object_id)
		_step(aliz, 40)
		var held: Vector3 = SpatialUtil.world_transform(aliz).affine_inverse() \
				* SpatialUtil.world_position(object)
		if held.y < 0.35 or held.y > 1.0:
			failures.append("'%s' is held %.2f m up" % [object_id, held.y])
		if not bool(aliz.call("put_down_carried")):
			failures.append("'%s' could not be put down" % object_id)
		_step(aliz, 40)
		if absf(SpatialUtil.world_position(object).y) > 0.005:
			failures.append("'%s' landed %.3f m off the floor" % [object_id, SpatialUtil.world_position(object).y])
		(stage["room"] as Node).free()
	return failures
