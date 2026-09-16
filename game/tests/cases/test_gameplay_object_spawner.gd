extends RefCounted

## ObjectSpawner: every shipped object record must produce a valid, touchable
## pickup, and the grab area must clear the child-friendly minimum.
##
## Scripts are loaded BY PATH, never by `class_name`: `--headless --script` does
## not rebuild `.godot/global_script_class_cache.cfg`, so a brand new global class
## may not resolve yet.

const SPAWNER_PATH: String = "res://scripts/gameplay/object_spawner.gd"
const LIBRARY_PATH: String = "res://scripts/content/content_library.gd"
const OBJECTS_JSON: String = "res://content/objects.json"

## Spawn row laid out by every `res://scenes/activities/*.tscn`.
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-0.72, 0.1, 0.72),
	Vector3(-0.24, 0.1, 0.72),
	Vector3(0.24, 0.1, 0.72),
	Vector3(0.72, 0.1, 0.72),
]


func test_name() -> String:
	return "gameplay_object_spawner"


func run() -> Array:
	var failures: Array = []
	var spawner: GDScript = load(SPAWNER_PATH) as GDScript
	if spawner == null:
		return ["could not load %s" % SPAWNER_PATH]

	failures.append_array(_test_every_object_spawns(spawner))
	failures.append_array(_test_grab_area(spawner))
	failures.append_array(_test_defensive_defaults(spawner))
	failures.append_array(_test_real_node_construction(spawner))
	return failures


## Every objectId in objects.json must build a valid spec with no warnings.
func _test_every_object_spawns(spawner: GDScript) -> Array:
	var failures: Array = []
	var library_script: GDScript = load(LIBRARY_PATH) as GDScript
	if library_script == null:
		return ["could not load %s" % LIBRARY_PATH]
	var library: RefCounted = library_script.create()
	if library == null:
		return ["ContentLibrary.create() returned null"]

	var object_ids: PackedStringArray = library.get_object_ids()
	if object_ids.size() < 20:
		failures.append("expected the full object catalogue, got %d ids" % object_ids.size())

	for object_id: String in object_ids:
		var record: Dictionary = library.get_object(object_id)
		var spec: Dictionary = spawner.build_spec(record)
		if not bool(spec.get("valid", false)):
			failures.append("object '%s' did not produce a valid spec" % object_id)
		var warnings: Array = spec.get("warnings", [])
		if not warnings.is_empty():
			failures.append("object '%s' produced warnings: %s" % [object_id, str(warnings)])
		if not spawner.PRIMITIVES.has(String(spec.get("primitive", ""))):
			failures.append("object '%s' resolved to unknown primitive '%s'"
					% [object_id, str(spec.get("primitive", ""))])
		if String(spec.get("interaction", "")).is_empty():
			failures.append("object '%s' resolved to an empty interaction" % object_id)
		if spawner.build_mesh(String(spec.get("primitive", ""))) == null:
			failures.append("object '%s' produced a null mesh" % object_id)

	return failures


## The measurement that matters: the on-screen grab area at the Baby Room camera
## (fov 50, 1366x1024) must be at least 220x220 px at every spawn point.
func _test_grab_area(spawner: GDScript) -> Array:
	var failures: Array = []
	var minimum: float = float(spawner.MIN_GRAB_PX)

	for point: Vector3 in SPAWN_POINTS:
		var depth: float = spawner.camera_depth_for(point)
		if depth <= 0.0:
			failures.append("spawn point %s is behind the camera" % str(point))
			continue
		var size: Vector2 = spawner.grab_size_px(depth)
		if size.x < minimum or size.y < minimum:
			failures.append("grab area at %s is %.0fx%.0f px, below the %.0f px minimum"
					% [str(point), size.x, size.y, minimum])

	# The collider must also be meaningfully bigger than the visible mesh, so a
	# near-miss still picks the object up.
	if float(spawner.GRAB_SIZE_M) <= float(spawner.VISUAL_SIZE_M) * 1.5:
		failures.append("grab collider (%.2f m) is not generously larger than the visual (%.2f m)"
				% [float(spawner.GRAB_SIZE_M), float(spawner.VISUAL_SIZE_M)])

	# Sanity-check the projection helper itself against a hand-computed value:
	# 1 m at 1 m depth with fov 50 spans 1024 / (2 * tan(25 deg)) px.
	var expected: float = 1024.0 / (2.0 * tan(deg_to_rad(25.0)))
	var actual: float = spawner.world_size_to_screen_px(1.0, 1.0)
	if absf(actual - expected) > 0.5:
		failures.append("world_size_to_screen_px is wrong: got %.2f, expected %.2f" % [actual, expected])

	return failures


## Malformed content must degrade, never crash.
func _test_defensive_defaults(spawner: GDScript) -> Array:
	var failures: Array = []

	var empty: Dictionary = spawner.build_spec({})
	if bool(empty.get("valid", true)):
		failures.append("an empty object record was reported as valid")
	if Array(empty.get("warnings", [])).is_empty():
		failures.append("an empty object record produced no warnings")
	if not spawner.PRIMITIVES.has(String(empty.get("primitive", ""))):
		failures.append("an empty object record did not fall back to a known primitive")

	var bad: Dictionary = spawner.build_spec({
		"objectId": "weird", "word": "weird", "primitive": "dodecahedron", "color": "not-a-color",
		"defaultInteraction": "tap",
	})
	if String(bad.get("primitive", "")) != spawner.DEFAULT_PRIMITIVE:
		failures.append("an unknown primitive did not fall back to '%s'" % str(spawner.DEFAULT_PRIMITIVE))
	if spawner.build_mesh(String(bad.get("primitive", ""))) == null:
		failures.append("the fallback primitive produced a null mesh")

	# Pastel: never a fully saturated primary straight from the JSON hex.
	var red: Color = spawner.pastel(Color(1.0, 0.0, 0.0))
	if red.g < 0.2 or red.b < 0.2:
		failures.append("pastel() did not soften a pure primary: %s" % str(red))

	return failures


## Actually build a node for one record, to prove `spawn()` wires up a real,
## draggable, generously-collidable object and not just a Dictionary.
func _test_real_node_construction(spawner: GDScript) -> Array:
	var failures: Array = []
	var node: Area3D = spawner.spawn({
		"objectId": "milk", "word": "milk", "category": "feeding",
		"primitive": "capsule", "color": "#FFFFFF", "defaultInteraction": "dragToMouth",
	})
	if node == null:
		return ["spawn() returned null for a well-formed record"]

	if String(node.get("object_id")) != "milk":
		failures.append("spawned node did not carry its objectId")
	if not node.has_method("set_drop_zone"):
		failures.append("spawned node is not a DraggableObject (no set_drop_zone)")
	if not node.has_signal("chosen"):
		failures.append("spawned node has no 'chosen' signal")
	if not node.has_method("try_deliver_from_raycast"):
		failures.append("spawned node has no raycast tap fallback")

	var has_mesh: bool = false
	var grab_side: float = 0.0
	for child: Node in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			has_mesh = true
		if child is CollisionShape3D:
			var shape: Shape3D = (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				grab_side = (shape as BoxShape3D).size.x
	if not has_mesh:
		failures.append("spawned node has no visible mesh")
	if absf(grab_side - float(spawner.GRAB_SIZE_M)) > 0.001:
		failures.append("spawned collider side is %.3f m, expected %.3f m"
				% [grab_side, float(spawner.GRAB_SIZE_M)])

	node.free()
	return failures
