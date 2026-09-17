extends RefCounted

## The extended `ActivityTarget` contract (Phase 2B §7), and above all the
## promise that extending it broke nothing.
##
## `little_buddy_character.gd` already consumes `get_activity_target_id()`,
## `is_target_enabled()` and `describe(approach_from)`, and the Phase 2A spike
## ships against them. So the first section here is not about the new fields at
## all: it pins the OLD behaviour of a target with no `room_id`, which must be
## indistinguishable from the object that shipped.
##
## Everything runs without `_ready()` and without the scene tree, because the
## headless `--script` runner provides neither.

const ActivityTarget := preload("res://scripts/navigation/activity_target.gd")
const InteractionPoint := preload("res://scripts/navigation/interaction_point.gd")
const SemanticId := preload("res://scripts/navigation/semantic_id.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const NavigationController := preload("res://scripts/navigation/navigation_controller.gd")

## The six keys `describe()` returned before Phase 2B. The character reads them
## by name; losing or renaming one is a silent break, so they are listed here.
const LEGACY_DESCRIBE_KEYS: Array[String] = [
	"targetId", "displayName", "enabled", "standPosition", "facePosition", "arrivalRadius",
]

## Everything `little_buddy_character.gd` calls on a registered target.
const CHARACTER_FACING_METHODS: Array[String] = [
	"get_activity_target_id", "is_target_enabled", "describe",
]


func test_name() -> String:
	return "activity_target_contract"


func run():
	var failures: Array = []
	failures.append_array(_test_unroomed_target_is_unchanged())
	failures.append_array(_test_semantic_id())
	failures.append_array(_test_extended_fields())
	failures.append_array(_test_facing())
	failures.append_array(_test_doors())
	failures.append_array(_test_describe_shape())
	failures.append_array(_test_layer_discipline())
	failures.append_array(_test_tap_routing_still_resolves())
	return failures


## -- Backward compatibility ----------------------------------------------------

## A target with no `room_id` must behave EXACTLY as it did in Phase 2A. This is
## the spike's `"toyBox"`, reproduced.
func _test_unroomed_target_is_unchanged():
	var failures: Array = []
	var target: Area3D = ActivityTarget.new()
	target.set("target_id", "toyBox")
	target.set("stand_distance", 0.5)
	target.position = Vector3(2.0, 0.0, -2.0)

	for method: String in CHARACTER_FACING_METHODS:
		if not target.has_method(method):
			failures.append("the character calls %s(); the target no longer answers it" % method)

	if String(target.call("get_activity_target_id")) != "toyBox":
		failures.append("an unroomed target must still answer its bare id, got '%s'"
				% String(target.call("get_activity_target_id")))
	if String(target.call("get_semantic_id")) != "toyBox":
		failures.append("an unroomed semantic id is the bare id")
	if not bool(target.call("is_target_enabled")):
		failures.append("a target should start enabled")

	# The computed stand position: still on the approach side, still the same
	# distance, still without an InteractionPoint.
	var from_south: Vector3 = target.call("get_stand_position", Vector3(2.0, 0.0, 2.0))
	if not from_south.is_equal_approx(Vector3(2.0, 0.0, -1.5)):
		failures.append("the computed stand position changed, got %s" % str(from_south))
	var from_north: Vector3 = target.call("get_stand_position", Vector3(2.0, 0.0, -6.0))
	if not from_north.is_equal_approx(Vector3(2.0, 0.0, -2.5)):
		failures.append("the computed stand position no longer follows the approach side, got %s"
				% str(from_north))

	# And the facing default: the object itself, with no arguments passed.
	if not Vector3(target.call("get_facing_position")).is_equal_approx(Vector3(2.0, 0.0, -2.0)):
		failures.append("get_facing_position() with no argument must still mean 'the object'")

	var described: Dictionary = target.call("describe", Vector3(2.0, 0.0, 2.0))
	for key: String in LEGACY_DESCRIBE_KEYS:
		if not described.has(key):
			failures.append("describe() lost the '%s' key the character reads" % key)
	if String(described.get("targetId", "")) != "toyBox":
		failures.append("describe() must still report 'toyBox' for an unroomed target")
	if not Vector3(described.get("standPosition", Vector3.ZERO)).is_equal_approx(Vector3(2.0, 0.0, -1.5)):
		failures.append("describe()'s stand position changed for an unroomed target")
	if not Vector3(described.get("facePosition", Vector3.ZERO)).is_equal_approx(Vector3(2.0, 0.0, -2.0)):
		failures.append("describe()'s face position changed for an unroomed target")

	# An authored InteractionPoint still wins outright.
	var authored: Area3D = ActivityTarget.new()
	authored.set("target_id", "sink")
	authored.position = Vector3(2.0, 0.0, -2.0)
	var point: Marker3D = InteractionPoint.new()
	point.name = "InteractionPoint"
	point.position = Vector3(0.0, 0.0, 0.9)
	authored.add_child(point)
	var authored_described: Dictionary = authored.call("describe", Vector3(0.0, 0.0, 5.0))
	if not Vector3(authored_described.get("standPosition", Vector3.ZERO)).is_equal_approx(
		Vector3(2.0, 0.0, -1.1)
	):
		failures.append("an authored interaction point no longer wins, got %s"
				% str(authored_described.get("standPosition", Vector3.ZERO)))

	target.free()
	authored.free()
	return failures


## -- Semantic ids ---------------------------------------------------------------

func _test_semantic_id():
	var failures: Array = []
	var fridge: Area3D = _make("kitchen", "fridge")

	if String(fridge.call("get_semantic_id")) != "kitchen.fridge":
		failures.append("a roomed target should compose 'kitchen.fridge', got '%s'"
				% String(fridge.call("get_semantic_id")))

	# The load-bearing one: the id the character registers and routes by IS the
	# semantic id, so two rooms can both own a "toy" without colliding in the
	# character's flat registry.
	if String(fridge.call("get_activity_target_id")) != "kitchen.fridge":
		failures.append("get_activity_target_id() must report the addressable semantic id, got '%s'"
				% String(fridge.call("get_activity_target_id")))
	if String(fridge.call("get_local_target_id")) != "fridge":
		failures.append("get_local_target_id() should report the unqualified half")
	if String(fridge.call("get_room_id")) != "kitchen":
		failures.append("get_room_id() should report the room")

	var bedroom_toy: Area3D = _make("bedroom", "toy")
	var living_toy: Area3D = _make("livingRoom", "toy")
	if String(bedroom_toy.call("get_semantic_id")) == String(living_toy.call("get_semantic_id")):
		failures.append("the same local id in two rooms must produce two different semantic ids")

	# Whitespace in a hand-edited .tscn must not create a second id.
	var messy: Area3D = _make(" kitchen ", " fridge ")
	if String(messy.call("get_semantic_id")) != "kitchen.fridge":
		failures.append("a target id should be trimmed, got '%s'"
				% String(messy.call("get_semantic_id")))

	for node: Area3D in [fridge, bedroom_toy, living_toy, messy]:
		node.free()
	return failures


func _test_extended_fields():
	var failures: Array = []
	var fridge: Area3D = _make("kitchen", "fridge")
	fridge.call("set_supported_actions", ["open", " give ", "open", ""])
	fridge.set("required_object", "milk")
	fridge.set("level_tag", "level3")
	fridge.set("mission_tag", "breakfast")

	var actions: Array = fridge.call("get_supported_actions")
	if actions != ["open", "give"]:
		failures.append("supported actions should be trimmed and de-duplicated, got %s" % str(actions))
	if not bool(fridge.call("supports_action", "open")):
		failures.append("supports_action('open') should be true")
	if bool(fridge.call("supports_action", "explode")):
		failures.append("an unlisted action must not be supported")
	if String(fridge.call("get_required_object")) != "milk":
		failures.append("the required object should round-trip")
	if not bool(fridge.call("requires_object")):
		failures.append("a target with a required object should say so")
	if String(fridge.call("get_level_tag")) != "level3" \
			or String(fridge.call("get_mission_tag")) != "breakfast":
		failures.append("the optional tags should round-trip")

	# Defaults must be inert: a plain target requires nothing and supports nothing.
	var plain: Area3D = _make("", "toyBox")
	if not Array(plain.call("get_supported_actions")).is_empty():
		failures.append("a target supports no actions until somebody authors them")
	if bool(plain.call("requires_object")):
		failures.append("a target must not require an object by default")
	if bool(plain.call("is_door")):
		failures.append("a target must not be a door by default")

	# Semantics-only view: strings and bools, nothing spatial, so a mission can
	# read it without acquiring a 3D type.
	var semantics: Dictionary = fridge.call("describe_semantics")
	for key: Variant in semantics.keys():
		var value: Variant = semantics[key]
		if typeof(value) == TYPE_VECTOR3 or typeof(value) == TYPE_TRANSFORM3D:
			failures.append("describe_semantics()['%s'] leaks a 3D type" % str(key))
	if String(semantics.get("semanticId", "")) != "kitchen.fridge":
		failures.append("describe_semantics() should carry the semantic id")

	fridge.free()
	plain.free()
	return failures


func _test_facing():
	var failures: Array = []

	# An explicit direction, resolved from where the character will stand.
	var counter: Area3D = _make("kitchen", "counter")
	counter.position = Vector3(1.0, 0.0, 1.0)
	counter.set("facing_direction", Vector3(0.0, 0.0, -1.0))
	var described: Dictionary = counter.call("describe", Vector3(1.0, 0.0, 4.0))
	var stand: Vector3 = described.get("standPosition", Vector3.ZERO)
	var face: Vector3 = described.get("facePosition", Vector3.ZERO)
	if not face.is_equal_approx(stand + Vector3(0.0, 0.0, -1.0)):
		failures.append("facing_direction should be measured from the stand position, got %s (stand %s)"
				% [str(face), str(stand)])

	# An explicit look target beats everything, including an InteractionPoint.
	var sink: Area3D = _make("bathroom", "sink")
	sink.position = Vector3(0.0, 0.0, 0.0)
	var point: Marker3D = InteractionPoint.new()
	point.name = "InteractionPoint"
	point.position = Vector3(0.0, 0.0, 0.8)
	sink.add_child(point)
	var tap: Marker3D = Marker3D.new()
	tap.name = "Tap"
	tap.position = Vector3(0.0, 0.6, -0.3)
	sink.add_child(tap)
	sink.set("look_target_path", NodePath("Tap"))
	var sink_face: Vector3 = sink.call("get_facing_position")
	if not sink_face.is_equal_approx(Vector3(0.0, 0.6, -0.3)):
		failures.append("an explicit look target should win, got %s" % str(sink_face))

	# A look target that does not exist degrades to the old behaviour rather than
	# crashing or facing the origin.
	var broken: Area3D = _make("bathroom", "towel")
	broken.position = Vector3(3.0, 0.0, -1.0)
	broken.set("look_target_path", NodePath("NoSuchNode"))
	if not Vector3(broken.call("get_facing_position")).is_equal_approx(Vector3(3.0, 0.0, -1.0)):
		failures.append("a missing look target must fall back to the object itself")

	counter.free()
	sink.free()
	broken.free()
	return failures


func _test_doors():
	var failures: Array = []
	var door: Area3D = _make("bedroom", "doorToBathroom")
	door.set("to_room_id", "bathroom")
	door.set("to_spawn_id", "fromBedroom")

	if not bool(door.call("is_door")):
		failures.append("a target with a destination room is a door")
	var destination: Dictionary = door.call("get_destination")
	if String(destination.get("toRoomId", "")) != "bathroom" \
			or String(destination.get("toSpawnId", "")) != "fromBedroom":
		failures.append("a door should report its destination as strings, got %s" % str(destination))
	for key: Variant in destination.keys():
		if typeof(destination[key]) != TYPE_STRING:
			failures.append("a destination must be strings only; '%s' is not" % str(key))

	# A door with no spawn is legal and means "the destination's default spawn" --
	# never a coordinate, which is the rule that stops a room edit stranding a child.
	var lazy: Area3D = _make("kitchen", "doorToHall")
	lazy.set("to_room_id", "livingRoom")
	if not bool(lazy.call("is_door")):
		failures.append("a door with no spawn id is still a door")
	if not String(lazy.call("get_destination").get("toSpawnId", "x")).is_empty():
		failures.append("an unset spawn id should stay empty rather than be invented")

	door.free()
	lazy.free()
	return failures


func _test_describe_shape():
	var failures: Array = []
	var fridge: Area3D = _make("kitchen", "fridge")
	fridge.call("set_supported_actions", ["open"])
	var described: Dictionary = fridge.call("describe", Vector3.ZERO)

	for key: String in [
		"targetId", "semanticId", "localTargetId", "roomId", "displayName", "enabled",
		"standPosition", "facePosition", "arrivalRadius", "supportedActions", "requiredObject",
		"levelTag", "missionTag", "isDoor", "toRoomId", "toSpawnId",
	]:
		if not described.has(key):
			failures.append("describe() is missing the '%s' key" % key)

	if String(described.get("semanticId", "")) != String(described.get("targetId", "")):
		failures.append("describe()'s targetId and semanticId must agree")
	if String(described.get("localTargetId", "")) != "fridge":
		failures.append("describe() should carry the unqualified id too")

	# camelCase keys, matching the project's JSON/dictionary convention.
	for key: Variant in described.keys():
		var text: String = String(key)
		if text.contains("_") or (not text.is_empty() and text[0] == text[0].to_upper()):
			failures.append("describe() key '%s' is not camelCase" % text)

	fridge.call("set_target_enabled", false)
	if bool(fridge.call("describe", Vector3.ZERO).get("enabled", true)):
		failures.append("a disabled target should say so")

	fridge.free()
	return failures


## The layer invariant, restated where the contract lives. Activity targets are
## layer 2, draggables layer 1, and they must never overlap -- if they did, a
## tap-to-walk raycast and a drag press would fight over the same object.
func _test_layer_discipline():
	var failures: Array = []
	if ActivityTarget.ACTIVITY_TARGET_LAYER != 2:
		failures.append("activity targets must stay on collision layer 2, found %d"
				% ActivityTarget.ACTIVITY_TARGET_LAYER)
	if ActivityTarget.ACTIVITY_TARGET_LAYER & 1 != 0:
		failures.append("the activity-target layer overlaps the draggable layer (1)")

	var fridge: Area3D = _make("kitchen", "fridge")
	# Lazy wiring: any public call resolves the node, `_ready()` or no `_ready()`.
	# That is the whole point of `_ensure_resolved()` -- the headless runner never
	# fires `_ready()` for a node added to the root.
	fridge.call("get_semantic_id")
	if int(fridge.get("collision_layer")) != ActivityTarget.ACTIVITY_TARGET_LAYER:
		failures.append("a target should put itself on the activity layer before _ready(), found %d"
				% int(fridge.get("collision_layer")))
	if int(fridge.get("collision_mask")) != 0:
		failures.append("a target should collide with nothing")
	if bool(fridge.get("input_ray_pickable")):
		failures.append("a target must stay out of viewport picking")
	fridge.free()
	return failures


## The routing path, end to end in strings: the raycast hits a child mesh, the
## controller walks up to the target, and the id it hands the character is the
## semantic one the registry and the content both use.
func _test_tap_routing_still_resolves():
	var failures: Array = []
	var fridge: Area3D = _make("kitchen", "fridge")
	var mesh: Node3D = Node3D.new()
	mesh.name = "Mesh"
	fridge.add_child(mesh)

	if NavigationController.target_id_for(mesh) != "kitchen.fridge":
		failures.append("a tap on a child mesh should resolve to the semantic id, got '%s'"
				% NavigationController.target_id_for(mesh))

	fridge.call("set_target_enabled", false)
	if not NavigationController.target_id_for(mesh).is_empty():
		failures.append("a disabled target must not claim a tap")
	fridge.call("set_target_enabled", true)

	# A target with a room but no id is an authoring mistake, not a crash, and
	# must not resolve to the room on its own.
	var nameless: Area3D = _make("kitchen", "")
	if not NavigationController.target_id_for(nameless).is_empty():
		failures.append("a target with no target_id must resolve to nothing, got '%s'"
				% NavigationController.target_id_for(nameless))
	if not String(nameless.call("get_semantic_id")).is_empty():
		failures.append("a room alone is not an addressable id")

	fridge.free()
	nameless.free()
	return failures


## -- Helpers --------------------------------------------------------------------

func _make(room_id: String, target_id: String) -> Area3D:
	var target: Area3D = ActivityTarget.new()
	target.set("room_id", room_id)
	target.set("target_id", target_id)
	return target
