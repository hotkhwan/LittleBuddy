class_name ObjectSpawner
extends RefCounted

## Builds a playable 3D pickup at runtime from ONE record in
## `content/objects.json` -- nothing else. Adding content is therefore a JSON
## edit, never a new scene or script.
##
## Constraints (see CLAUDE.md / INTEGRATION_CONTRACT.md):
##   - built-in primitive meshes + plain `StandardMaterial3D` only,
##   - no particles, no `RigidBody3D`, no lights, no environment,
##   - soft pastel colours,
##   - a generously oversized collision shape so the on-screen grab area clears
##     the child-friendly minimum (see `grab_size_px()` and the
##     `test_gameplay_object_spawner` case, which asserts it).
##
## The class is split in two halves on purpose:
##   `build_spec()` is PURE (Dictionary in, Dictionary out) and is what the tests
##   drive, so content can be validated headlessly without a renderer;
##   `spawn()` materialises that spec into a `SpawnedObject` node.

const SPAWNED_OBJECT_SCRIPT_PATH: String = "res://scripts/gameplay/spawned_object.gd"

const PRIMITIVES: Array[String] = ["sphere", "box", "capsule", "cylinder", "torus"]
const DEFAULT_PRIMITIVE: String = "sphere"

## Edge length of the (cube) grab collider, in metres. Sized from the Baby Room
## camera so it projects to >= 220x220 px -- see `grab_size_px()`.
const GRAB_SIZE_M: float = 0.34

## Roughly how big the *visible* mesh is. Deliberately ~2x smaller than the grab
## collider: the collider is forgiving, the art stays cute and uncluttered.
const VISUAL_SIZE_M: float = 0.16

## Height of the object's centre above its origin, so it rests on the floor/table
## plane rather than being half-buried.
const VISUAL_CENTRE_Y: float = 0.1

## How far each colour is pushed toward white. Keeps everything soft and pastel
## even when the authored hex is a strong primary.
const PASTEL_MIX: float = 0.3
const FALLBACK_COLOR: Color = Color(0.86, 0.86, 0.9)

## Baby Room camera framing, used by the grab-area measurement. Kept in sync with
## `baby_room.gd` CAMERA_POSITION/CAMERA_TARGET and `baby_room.tscn` `fov`.
const CAMERA_FOV_DEG: float = 50.0
const VIEWPORT_HEIGHT_PX: float = 1024.0
const CAMERA_POSITION: Vector3 = Vector3(0.0, 0.95, 2.075)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.315, 0.175)
## Distance along the camera's forward axis to the spawn row laid out by
## `ActivityScene` (x, 0.10, 0.72). Derived, not guessed -- `camera_depth_for()`
## recomputes it and `test_gameplay_object_spawner` asserts the resulting pixel
## size clears `MIN_GRAB_PX`.
const SPAWN_DEPTH_M: float = 1.5548
## Child-friendly minimum on-screen touch target, per side.
const MIN_GRAB_PX: float = 220.0


## -- Pure spec building --------------------------------------------------------

## Normalises one `objects.json` record into everything `spawn()` needs.
## Never fails: unusable fields fall back to safe defaults and are reported in
## `warnings`, mirroring `ContentLibrary`'s defensive loading policy.
static func build_spec(object_data: Dictionary, interaction_override: String = "") -> Dictionary:
	var warnings: Array = []

	var object_id: String = String(object_data.get("objectId", "")).strip_edges()
	if object_id.is_empty():
		warnings.append("object record has no 'objectId'")

	var primitive: String = String(object_data.get("primitive", "")).strip_edges()
	if not PRIMITIVES.has(primitive):
		if not primitive.is_empty():
			warnings.append("object '%s' has unknown primitive '%s'" % [object_id, primitive])
		else:
			warnings.append("object '%s' has no 'primitive'" % object_id)
		primitive = DEFAULT_PRIMITIVE

	var color: Color = parse_color(String(object_data.get("color", "")))
	if color == FALLBACK_COLOR and String(object_data.get("color", "")).strip_edges().is_empty():
		warnings.append("object '%s' has no 'color'" % object_id)

	var word: String = String(object_data.get("word", "")).strip_edges()
	if word.is_empty():
		warnings.append("object '%s' has no 'word'" % object_id)

	var interaction: String = interaction_override
	if interaction.is_empty():
		interaction = String(object_data.get("defaultInteraction", "")).strip_edges()
	if interaction.is_empty():
		warnings.append("object '%s' has no 'defaultInteraction'" % object_id)

	return {
		"objectId": object_id,
		"word": word,
		"shapeWord": String(object_data.get("shapeWord", "")),
		"colorWord": String(object_data.get("colorWord", "")),
		"displayName": String(object_data.get("displayName", word)),
		"category": String(object_data.get("category", "")),
		"thaiHint": String(object_data.get("thaiHint", "")),
		"primitive": primitive,
		"color": pastel(color),
		"grabSize": GRAB_SIZE_M,
		"visualSize": VISUAL_SIZE_M,
		"interaction": interaction,
		"valid": object_id != "" and word != "",
		"warnings": warnings,
	}


static func parse_color(hex: String) -> Color:
	var text: String = hex.strip_edges()
	if text.is_empty():
		return FALLBACK_COLOR
	if not Color.html_is_valid(text):
		return FALLBACK_COLOR
	return Color.html(text)


static func pastel(color: Color) -> Color:
	var mixed: Color = color.lerp(Color(1.0, 1.0, 1.0), PASTEL_MIX)
	mixed.a = 1.0
	return mixed


## -- Grab-area measurement (pure) ----------------------------------------------

## On-screen size, in pixels, of `world_size` metres at `depth` metres along the
## camera's forward axis. Godot's Camera3D keeps vertical FOV by default, so the
## vertical pixel scale is `viewport_height / (2 * depth * tan(fov/2))`.
static func world_size_to_screen_px(
	world_size: float,
	depth: float,
	fov_deg: float = CAMERA_FOV_DEG,
	viewport_height: float = VIEWPORT_HEIGHT_PX
) -> float:
	var half_extent: float = depth * tan(deg_to_rad(fov_deg) * 0.5)
	if half_extent <= 0.0:
		return 0.0
	return world_size * viewport_height / (2.0 * half_extent)


## Distance from the Baby Room camera to `point`, measured along the camera's
## forward axis -- which is what Godot's perspective projection actually divides
## by, so this is the honest number for a pixel-size calculation.
static func camera_depth_for(point: Vector3) -> float:
	var forward: Vector3 = (CAMERA_TARGET - CAMERA_POSITION).normalized()
	return (point - CAMERA_POSITION).dot(forward)


## Measured grab area of a spawned object, in screen pixels, at the Baby Room's
## camera framing. Square because the collider is a cube.
static func grab_size_px(depth: float = SPAWN_DEPTH_M) -> Vector2:
	var side: float = world_size_to_screen_px(GRAB_SIZE_M, depth)
	return Vector2(side, side)


## -- Node construction ---------------------------------------------------------

## Materialises a spec into a `SpawnedObject`. Returns `null` only if the
## `SpawnedObject` script itself cannot be loaded.
##
## Typed as `Area3D` rather than `SpawnedObject` so this script never depends on
## Godot's global class cache (`--headless --script` does not rebuild it).
static func spawn(object_data: Dictionary, interaction_override: String = "") -> Area3D:
	var spec: Dictionary = build_spec(object_data, interaction_override)
	return spawn_from_spec(spec)


static func spawn_from_spec(spec: Dictionary) -> Area3D:
	var script: GDScript = load(SPAWNED_OBJECT_SCRIPT_PATH) as GDScript
	if script == null:
		return null

	var node: Area3D = Area3D.new()
	node.set_script(script)
	node.call("configure", spec)

	var color: Color = spec.get("color", FALLBACK_COLOR)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	material.metallic = 0.0
	node.call("register_material", material)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = build_mesh(String(spec.get("primitive", DEFAULT_PRIMITIVE)))
	visual.material_override = material
	visual.position = Vector3(0.0, VISUAL_CENTRE_Y, 0.0)
	node.add_child(visual)

	node.add_child(build_grab_collision(float(spec.get("grabSize", GRAB_SIZE_M))))
	return node


static func build_mesh(primitive: String) -> Mesh:
	var half: float = VISUAL_SIZE_M * 0.5
	match primitive:
		"box":
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(VISUAL_SIZE_M, VISUAL_SIZE_M * 0.78, VISUAL_SIZE_M * 0.62)
			return box
		"capsule":
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = half * 0.62
			capsule.height = VISUAL_SIZE_M * 1.25
			return capsule
		"cylinder":
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = half * 0.72
			cylinder.bottom_radius = half * 0.78
			cylinder.height = VISUAL_SIZE_M
			return cylinder
		"torus":
			var torus: TorusMesh = TorusMesh.new()
			torus.inner_radius = half * 0.48
			torus.outer_radius = half
			return torus
		_:
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = half
			sphere.height = VISUAL_SIZE_M
			return sphere


## A cube collider, generously larger than every visual mesh above. Child-sized
## touch targets matter far more than visual precision, and an oversized shape
## also keeps the `input_event` pick and the `baby_room.gd` raycast fallback in
## agreement.
static func build_grab_collision(grab_size: float) -> CollisionShape3D:
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "GrabShape"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(grab_size, grab_size, grab_size)
	collision.shape = shape
	collision.position = Vector3(0.0, VISUAL_CENTRE_Y, 0.0)
	return collision
