extends RefCounted

## Where a task's objects end up, measured in the real house.
##
## The device note was one sentence: *"the items we are given to choose should be
## placed at their positions in the room."* Before this, `HouseStage` laid every
## choice out in a straight row a fixed 0.78 m in front of the CHILD, wherever he
## happened to be standing -- so a toothbrush, a bar of soap and a towel appeared
## in the middle of the bathroom floor, and a shirt and a pair of shoes appeared
## in exactly the same spot in the bedroom. The file said as much in its own
## comments.
##
## Four properties are asserted here, for **every choice-bearing task the game
## ships**, walked in mission order through the real `house_world.tscn` with live
## `ActivityTarget` nodes:
##
##   1. **Objects are at the furniture they belong to.** A `findIt`/`sayIt`/
##      dressing beat -- the ones the child does not walk for, and the ones that
##      looked worst -- lays its objects out near its own target.
##   2. **Nothing is inside a wall.** Every object is on the walkable floor, with
##      more clearance than the navigation agent's own radius.
##   3. **Nothing is inside the furniture.** A toy half-sunk in the bath is a toy
##      a child aims at and misses.
##   4. **Nothing overlaps anything else.** Two grab colliders must never share a
##      pixel, or a tap is ambiguous and the wrong object answers.
##
## Plus the one structural fact the whole design rests on: the mission context
## and the stage share ONE spawn-point array, so a task can move its objects
## without `build_context()` changing shape and without the level director -- a
## different agent's file -- changing at all.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract section 8).

const HouseStageScript := preload("res://scripts/gameplay/house_stage.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const ObjectSpawnerScript := preload("res://scripts/gameplay/object_spawner.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const HOUSE_CHAPTER: String = "ch3"

## How near "at the sink" has to be.
##
## Calibrated against what it replaces, not picked for comfort: laid out at the
## child's feet, `findMilk`'s objects sat 3.58 m from the fridge the task is
## about, on the far side of the kitchen. Anything under 2 m is unambiguously
## "at the furniture" in a 4 m room, and 3.58 m fails it.
const NEAR_FURNITURE_M: float = 2.0

## Every object must be at least this far inside the room's floor. Larger than
## `HouseLayout.NAV_AGENT_RADIUS` (0.20), so anything visible is also standable-
## next-to.
const WALL_CLEARANCE_M: float = 0.22

## And at least this far out of any furniture footprint.
const PROP_CLEARANCE_M: float = 0.04


func test_name() -> String:
	return "house_stage_placement"


func run():
	var failures: Array = []
	failures.append_array(_test_default_row_is_unchanged())
	failures.append_array(_test_context_shares_the_live_slot_array())
	failures.append_array(_test_every_shipped_task_places_its_objects_well())
	failures.append_array(_test_a_task_with_no_target_uses_its_object_category())
	failures.append_array(_test_an_underivable_task_still_reaches_the_child())
	return failures


## The untouched row is still the row: nothing that spawns before a task has been
## staged moved, and the slot count the mode handlers rely on is the same four.
func _test_default_row_is_unchanged():
	var failures: Array = []
	var stage: Node3D = HouseStageScript.new()
	var points: Array = stage.call("get_spawn_points")
	if points.size() != HouseStageScript.SPAWN_SLOTS:
		failures.append("expected %d slots, got %d" % [HouseStageScript.SPAWN_SLOTS, points.size()])
	for i: int in range(points.size() - 1):
		var gap: float = (points[i] as Vector3).distance_to(points[i + 1] as Vector3)
		if absf(gap - HouseStageScript.SPAWN_SPACING) > 0.001:
			failures.append("default slots %d and %d are %.3f m apart, not SPAWN_SPACING"
					% [i, i + 1, gap])
	if absf(stage.call("get_object_anchor").scale.x - HouseStageScript.OBJECT_SCALE) > 0.001:
		failures.append("the anchor must still scale the row up for a phone-sized screen")
	stage.free()
	return failures


## The load-bearing structural fact.
##
## `HouseLevelDirector` builds the mission context ONCE per level and
## `MissionRunner` shallow-`duplicate()`s it, so the array the mode handler reads
## when it spawns is the stage's own. That is what lets each task place its
## objects somewhere different without touching the director's file. If anything
## upstream ever starts deep-copying the context, this goes red here rather than
## silently freezing every task's layout at whatever level one wanted.
func _test_context_shares_the_live_slot_array():
	var failures: Array = []
	var stage: Node3D = HouseStageScript.new()
	var context: Dictionary = stage.call("build_context", {})
	var shared: Array = context.get("spawnPoints", [])
	var before: Variant = shared[0] if shared.size() > 0 else null

	# A layout that cannot be derived at all still rewrites the array, so this
	# measures the sharing rather than the placement.
	stage.call("begin_task", TaskPlan.empty("bedroom"), Vector3(0.0, 0.0, -1.5),
			Vector3(0.0, 0.0, -0.8))
	if shared.size() != HouseStageScript.SPAWN_SLOTS:
		failures.append("the context's spawn point array lost its slots")
	elif shared[0] == before and stage.call("get_spawn_points")[0] != before:
		failures.append("the mission context is holding a COPY of the spawn points, so every task "
				+ "in a level would spawn into level one's layout")
	if stage.call("get_spawn_points") != shared:
		failures.append("build_context() must hand out the stage's live slot array")
	stage.free()
	return failures


## -- The real thing ------------------------------------------------------------

func _test_every_shipped_task_places_its_objects_well():
	var failures: Array = []
	var session: Dictionary = _open()
	if session.has("error"):
		return [session["error"]]

	var checked: int = 0
	var near_furniture: int = 0
	for mission_id: Variant in _house_mission_ids(session["library"]):
		for staged: Variant in _walk_mission(session, String(mission_id)):
			var entry: Dictionary = staged
			var plan: Dictionary = entry["plan"]
			if not bool(plan.get("needsChoices", false)):
				continue
			checked += 1
			var room_id: String = String(entry["roomId"])
			var label: String = "%s/%s" % [String(mission_id), String(plan.get("taskId", ""))]
			failures.append_array(_check_slots(
					entry["slots"], room_id, label, float(entry["objectScale"])))
			if not bool(plan.get("needsWalk", false)):
				var verdict: Dictionary = _check_near_furniture(session, entry, label)
				failures.append_array(verdict["failures"])
				if bool(verdict["measured"]):
					near_furniture += 1

	if checked < 10:
		failures.append("only %d choice-bearing tasks were reached; the walk-through is not "
				% checked + "covering the shipped content")
	if near_furniture < 5:
		failures.append("only %d no-walk beats were measured against their furniture; this case "
				% near_furniture + "is not testing the thing it was written for")
	_close(session)
	return failures


## Every dressing task names no target at all -- no `targetId`, no
## `requiresWalkTo`. Those were the worst offenders: a shirt, trousers, shoes and
## a hat appearing on the floor wherever the child was standing. The object's own
## `category` is what places them now.
func _test_a_task_with_no_target_uses_its_object_category():
	var failures: Array = []
	var session: Dictionary = _open()
	if session.has("error"):
		return [session["error"]]

	var world: Node = session["world"]
	var stage: Node3D = session["stage"]
	world.call("place_in_room", "bedroom", "default")

	var cases: Dictionary = {
		"pants": "bedroom.wardrobe",
		"redShirt": "bedroom.wardrobe",
		"shoes": "bedroom.wardrobe",
	}
	for object_id: Variant in cases.keys():
		var plan: Dictionary = TaskPlan.describe({
			"taskId": "probe_%s" % String(object_id),
			"mode": "followInstruction",
			"interaction": "dragToDress",
			"objectId": String(object_id),
		}, "bedroom")
		stage.call("begin_task", plan, null, null)
		var expected: String = String(cases[object_id])
		if String(stage.call("get_place_id")) != expected:
			failures.append("'%s' should be laid out at %s, was laid out at '%s'"
					% [String(object_id), expected, String(stage.call("get_place_id"))])
			continue
		failures.append_array(_check_slots(
				stage.call("get_spawn_world_positions"), "bedroom",
				"dressing/%s" % String(object_id), float(stage.call("get_object_scale"))))

	# And the category map is derived from the content, not from a list that can
	# drift: every category the library ships must have somewhere to live.
	var seen: Dictionary = {}
	for record: Variant in session["library"].call("get_objects"):
		var category: String = String((record as Dictionary).get("category", "")).strip_edges()
		if category.is_empty() or seen.has(category):
			continue
		seen[category] = true
		if not HouseStageScript.CATEGORY_HOME_TARGETS.has(category):
			failures.append("content ships objects in category '%s', which belongs nowhere in the "
					% category + "house; they would fall back to the child's feet")

	_close(session)
	return failures


## The promise that keeps this safe: when nothing can be derived, the objects go
## back to where they have always gone. There is never a task with no objects.
func _test_an_underivable_task_still_reaches_the_child():
	var failures: Array = []
	var stage: Node3D = HouseStageScript.new()
	var character: Node3D = Node3D.new()
	character.position = Vector3(0.6, 0.0, -0.4)
	stage.add_child(character)
	stage.call("bind_character", character)

	# No target, no object, no room, no focus: nothing to go on at all.
	stage.call("begin_task", TaskPlan.empty(""), null, null)
	if not String(stage.call("get_place_id")).is_empty():
		failures.append("a plan with nothing in it should derive no place")

	var slots: Array = stage.call("get_spawn_world_positions")
	if slots.size() != HouseStageScript.SPAWN_SLOTS:
		failures.append("the fallback must still lay out every slot")
	var nearest: float = 99.0
	for slot: Variant in slots:
		nearest = minf(nearest, Vector2((slot as Vector3).x, (slot as Vector3).z)
				.distance_to(Vector2(character.position.x, character.position.z)))
	if nearest > 1.6:
		failures.append("the fallback row ended up %.2f m from the child; it is supposed to be "
				% nearest + "within reach of wherever he is standing")
	stage.free()
	return failures


## -- Measurements ---------------------------------------------------------------

## Properties 2, 3 and 4, for one task's four slots.
func _check_slots(slots: Array, room_id: String, label: String, object_scale: float = HouseStageScript.OBJECT_SCALE):
	var failures: Array = []
	var grab: float = ObjectSpawnerScript.GRAB_SIZE_M * object_scale
	if slots.size() != HouseStageScript.SPAWN_SLOTS:
		return ["%s laid out %d objects, expected %d"
				% [label, slots.size(), HouseStageScript.SPAWN_SLOTS]]

	var floor_rect: Variant = null
	if HouseLayout.has_room(room_id):
		floor_rect = HouseLayout.world_floor_bounds(room_id).grow(-WALL_CLEARANCE_M)

	for i: int in range(slots.size()):
		var point: Vector3 = slots[i]
		var flat := Vector2(point.x, point.z)

		if floor_rect is Rect2 and not (floor_rect as Rect2).has_point(flat):
			failures.append("%s slot %d is at %s, outside the walkable floor of '%s'"
					% [label, i, str(flat), room_id])

		if HouseLayout.has_room(room_id):
			var origin: Vector3 = HouseLayout.room_origin(room_id)
			for prop: Variant in HouseLayout.furniture(room_id):
				var entry: Dictionary = prop
				var size: Vector3 = entry.get("size", Vector3.ONE)
				var centre: Vector3 = entry.get("position", Vector3.ZERO)
				var rect := Rect2(
					origin.x + centre.x - size.x * 0.5,
					origin.z + centre.z - size.z * 0.5,
					size.x, size.z)
				if rect.grow(PROP_CLEARANCE_M).has_point(flat):
					failures.append("%s slot %d is inside the %s"
							% [label, i, String(entry.get("displayName", "furniture"))])
				elif HouseStageScript._is_hidden_behind(flat, rect, size.y):
					failures.append("%s slot %d is hidden behind the %s: the child is asked to find "
							% [label, i, String(entry.get("displayName", "furniture"))]
							+ "something they cannot see")

		for j: int in range(i + 1, slots.size()):
			var gap: float = flat.distance_to(
					Vector2((slots[j] as Vector3).x, (slots[j] as Vector3).z))
			if gap < grab:
				failures.append("%s slots %d and %d are %.2f m apart, closer than one grab "
						% [label, i, j, gap] + "target (%.2f m): a tap between them is ambiguous"
						% grab)
	return failures


## Property 1, for a beat the child does NOT walk to. `{"failures": [...],
## "measured": bool}` -- a task whose target is not in the scene is not a
## measurement, and must not be counted as one.
func _check_near_furniture(session: Dictionary, entry: Dictionary, label: String) -> Dictionary:
	var plan: Dictionary = entry["plan"]
	var focus_id: String = String(plan.get("focusTargetId", ""))
	if focus_id.is_empty():
		return {"failures": [], "measured": false}
	var target: Node = session["world"].call("get_target_by_semantic_id", focus_id)
	if not (target is Node3D):
		return {"failures": [], "measured": false}
	if target.has_method("is_door") and bool(target.call("is_door")):
		return {"failures": [], "measured": false}

	var failures: Array = []
	var furniture: Vector3 = SpatialUtil.world_position(target as Node3D)
	var centre := Vector2.ZERO
	for slot: Variant in entry["slots"]:
		centre += Vector2((slot as Vector3).x, (slot as Vector3).z)
	centre /= float((entry["slots"] as Array).size())

	var span: float = centre.distance_to(Vector2(furniture.x, furniture.z))
	if span > NEAR_FURNITURE_M:
		failures.append("%s lays its objects %.2f m from '%s' -- they are not AT the thing the "
				% [label, span, focus_id] + "task is about, which is the whole device complaint")
	if String(entry["placeId"]) != focus_id:
		failures.append("%s derived its place from '%s' rather than from its own target '%s'"
				% [label, String(entry["placeId"]), focus_id])
	return {"failures": failures, "measured": true}


## -- Driving the shipped content -------------------------------------------------

## Stages every task of one mission in order, tracking which room the child is in
## exactly as the level director does, and returns what each one laid out.
func _walk_mission(session: Dictionary, mission_id: String) -> Array:
	var world: Node = session["world"]
	var stage: Node3D = session["stage"]
	var library: Object = session["library"]

	var mission: Dictionary = library.call("get_mission", mission_id)
	var path: Array = mission.get("roomPath", [])
	var room_id: String = String(path[0]) if not path.is_empty() else HouseLayout.FALLBACK_ROOM
	world.call("place_in_room", room_id, "default")

	var staged: Array = []
	for task: Variant in library.call("get_mission_tasks", mission_id):
		var plan: Dictionary = TaskPlan.describe(task, room_id)

		# A `travel` beat is finished by walking through the door, so the child is
		# in the next room for everything after it.
		if TaskPlan.is_travel(plan):
			var destination: String = String(plan.get("destinationRoomId", ""))
			if not destination.is_empty() and bool(world.call("has_room", destination)):
				room_id = destination
				world.call("place_in_room", room_id, "default")
			continue

		var task_room: String = String(plan.get("roomId", ""))
		if not task_room.is_empty() and task_room != room_id \
				and bool(world.call("has_room", task_room)):
			room_id = task_room
			world.call("place_in_room", room_id, "default")

		var focus: Variant = _world_position_of(world, String(plan.get("focusTargetId", "")))
		var stand: Variant = null
		if bool(plan.get("needsWalk", false)):
			stand = _stand_position_of(world, String(plan.get("walkTargetId", "")))
			if stand is Vector3:
				# The director stages a walked-to beat again on arrival, with the
				# child standing on the spot. That is the layout a child sees.
				SpatialUtil.set_world_position(world.call("get_character"), stand as Vector3)

		stage.call("begin_task", plan, focus, stand)
		staged.append({
			"plan": plan,
			"roomId": room_id,
			"placeId": String(stage.call("get_place_id")),
			"objectScale": float(stage.call("get_object_scale")),
			"slots": stage.call("get_spawn_world_positions"),
		})
	return staged


func _house_mission_ids(library: Object) -> Array:
	var ids: Array = []
	for mission: Variant in library.call("get_missions"):
		var entry: Dictionary = mission
		if String(entry.get("chapterId", "")) != HOUSE_CHAPTER:
			continue
		if (entry.get("roomPath", []) as Array).is_empty():
			continue
		ids.append(String(entry.get("missionId", "")))
	ids.sort()
	return ids


func _world_position_of(world: Node, semantic_id: String) -> Variant:
	if semantic_id.strip_edges().is_empty():
		return null
	var target: Node = world.call("get_target_by_semantic_id", semantic_id)
	if not (target is Node3D):
		return null
	return SpatialUtil.world_position(target as Node3D)


func _stand_position_of(world: Node, semantic_id: String) -> Variant:
	if semantic_id.strip_edges().is_empty():
		return null
	var target: Node = world.call("get_target_by_semantic_id", semantic_id)
	if not (target is Node3D) or not target.has_method("describe"):
		return null
	var here: Vector3 = SpatialUtil.world_position(world.call("get_character"))
	var stand: Variant = (target.call("describe", here) as Dictionary).get("standPosition", null)
	return stand if stand is Vector3 else null


## -- Session ---------------------------------------------------------------------

func _open() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return {"error": "no SceneTree; this case needs the real house"}
	if not ResourceLoader.exists(HOUSE_SCENE):
		return {"error": "missing %s" % HOUSE_SCENE}
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return {"error": "%s is not a PackedScene" % HOUSE_SCENE}
	var world: Node = (packed as PackedScene).instantiate()
	tree.root.add_child(world)
	# `_ready()` does not fire for a node added to the root in the `--script`
	# runner, so the world is built by hand (contract section 8).
	world.call("build_world")

	var library: Object = ContentLibraryScript.create()
	var stage: Node3D = HouseStageScript.new()
	stage.name = "ProbeStage"
	world.add_child(stage)
	var character: Node = world.call("get_character")
	if character is Node3D:
		stage.call("bind_character", character)
	stage.call("build_context", {"library": library})
	return {"tree": tree, "world": world, "stage": stage, "library": library}


func _close(session: Dictionary) -> void:
	var world: Node = session.get("world", null)
	if world == null:
		return
	(session["tree"] as SceneTree).root.remove_child(world)
	world.free()
