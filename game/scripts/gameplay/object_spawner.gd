class_name ObjectSpawner
extends RefCounted

## Builds a playable 3D pickup at runtime from ONE record in
## `content/objects.json` -- nothing else. Adding content is therefore a JSON
## edit, never a new scene or script.
##
## Constraints (see CLAUDE.md / INTEGRATION_CONTRACT.md):
##   - a bundled Kenney Food Kit mesh (CC0) when the record names one, otherwise
##     a built-in primitive mesh -- a `StandardMaterial3D` either way,
##   - no particles, no `RigidBody3D`, no lights, no environment,
##   - soft pastel colours on the primitive path,
##   - a generously oversized collision shape so the on-screen grab area clears
##     the child-friendly minimum (see `grab_size_px()` and the
##     `test_gameplay_object_spawner` case, which asserts it).
##
## The `model` key in `objects.json` is OPTIONAL and purely additive. A record
## with no `model`, or one whose `.glb` is missing from the export, still spawns
## exactly as it did before from `primitive` + `color`. A broken model can
## therefore never produce an invisible or uninteractable object.
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


## -- Kenney Food Kit models ----------------------------------------------------
##
## CC0, no attribution required (see `assets/models/kenney-food-kit/License.txt`
## and `docs/ASSET_SOURCING_PLAN.md`). Every model in the kit is a single mesh
## with a single material that samples ONE shared 512x512 palette atlas, so the
## whole prop set costs exactly one texture no matter how many models are used.
const MODEL_DIR: String = "res://assets/models/kenney-food-kit/"
const MODEL_EXTENSION: String = ".glb"
const MODEL_TEXTURE_PATH: String = "res://assets/models/kenney-food-kit/Textures/colormap.png"

## Target size, in metres, of the model's longest axis after scaling. Kenney
## props are authored at wildly different sizes (banana 0.63 m, apple 0.20 m,
## spoon 0.48 m), so every model is normalised to an explicitly authored size
## rather than trusted at import scale.
const MODEL_DEFAULT_SIZE_M: float = 0.20

## Hard ceiling on the presented size. The visible mesh must stay INSIDE the
## grab collider -- a visual bigger than its touch target would let a child aim
## at something the picker cannot hit. `test_gameplay_object_spawner` asserts it.
const MODEL_MAX_SIZE_M: float = 0.26

## Per-model presentation.
##
##   `size`     longest-axis target in metres,
##   `rotation` authored presentation rotation in degrees, chosen against the
##              Baby Room camera (which sits 18.5 deg above the horizon) so each
##              silhouette reads as its English word rather than as an ambiguous
##              edge-on shape,
##   `tint`     multiply the atlas by the record's authored `color`. Only set for
##              models Kenney maps to the atlas' near-white swatch (tableware).
##              Those read as pale grey blobs against the room's beige floor, and
##              tinting also makes them agree with the record's `colorWord`.
##              NEVER set for a model whose own colours carry the meaning -- an
##              apple, a banana or a milk carton must keep its authored palette.
const MODEL_PRESENTATION: Dictionary = {
	# Leaf and stem turned toward the camera.
	"apple": {"size": 0.19, "rotation": Vector3(0.0, 35.0, 0.0)},
	# Authored lying along -Z, i.e. pointing away from the camera. Turned across
	# the screen so the curve -- the thing that says "banana" -- is visible.
	"banana": {"size": 0.25, "rotation": Vector3(0.0, 80.0, 0.0)},
	# A shallow bowl seen from 18.5 deg reads as a disc. Tipped toward the
	# camera so the hollow interior is visible.
	"bowl": {"size": 0.26, "rotation": Vector3(30.0, 0.0, 0.0), "tint": true},
	# Three-quarter view: gable top plus two faces, which is what makes a carton
	# read as a carton.
	"carton": {"size": 0.25, "rotation": Vector3(0.0, 25.0, 0.0)},
	# Handle turned side-on so it is not hidden behind the body.
	"cup": {"size": 0.22, "rotation": Vector3(0.0, -95.0, 0.0), "tint": true},
	"glass": {"size": 0.21, "rotation": Vector3(0.0, 0.0, 0.0), "tint": true},
	# A spoon is flat: edge-on it is just a stick. Stood up to face the camera
	# (74 deg) with a slight roll (28 deg) so the bowl separates from the handle
	# instead of sitting in line with it. See ASSET_SOURCING_PLAN.md section 2.
	# Rendered side by side against `cooking-spoon` and against several tints --
	# this was the most legible combination, and it is still the weakest-reading
	# model of the seven, because a spoon's identifying detail is small.
	"utensil-spoon": {"size": 0.26, "rotation": Vector3(74.0, 0.0, 28.0), "tint": true},
}

## Imported meshes and the shared atlas are cached per run: `load()` already
## returns the same resource, this just avoids re-instantiating the imported
## scene once per spawned object.
static var _mesh_cache: Dictionary = {}
static var _colormap: Texture2D = null


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

	# Optional, additive: a record with no 'model' -- or one whose .glb is not in
	# the build -- keeps the primitive path untouched.
	var model: String = String(object_data.get("model", "")).strip_edges()
	if not model.is_empty() and not model_available(model):
		warnings.append("object '%s' declares model '%s' but %s is missing; using primitive '%s'"
				% [object_id, model, model_path_for(model), primitive])
		model = ""
	var presentation: Dictionary = model_presentation(model)

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
		# The authored hex, un-pastelised. Used only as a model tint: the atlas
		# swatch already lightens it, so pastelising twice washes the object out
		# against the room's beige floor.
		"rawColor": color,
		"grabSize": GRAB_SIZE_M,
		"visualSize": VISUAL_SIZE_M,
		"model": model,
		"modelPath": model_path_for(model),
		"modelSize": float(presentation.get("size", MODEL_DEFAULT_SIZE_M)),
		"modelRotationDeg": presentation.get("rotation", Vector3.ZERO),
		"modelTinted": bool(presentation.get("tint", false)),
		"interaction": interaction,
		"valid": object_id != "" and word != "",
		"warnings": warnings,
	}


## -- Model resolution (pure) ---------------------------------------------------

static func model_path_for(model_name: String) -> String:
	var trimmed: String = model_name.strip_edges()
	if trimmed.is_empty():
		return ""
	return MODEL_DIR + trimmed + MODEL_EXTENSION


## True only when the `.glb` is actually present and importable in THIS build.
## Everything downstream treats a false here as "there is no model", never as an
## error the child could ever see.
static func model_available(model_name: String) -> bool:
	var path: String = model_path_for(model_name)
	if path.is_empty():
		return false
	return ResourceLoader.exists(path)


## Authored size/rotation for a model, with safe defaults for any model that has
## no entry in `MODEL_PRESENTATION`. `size` is always clamped to
## `MODEL_MAX_SIZE_M` so the visual can never outgrow the grab collider.
static func model_presentation(model_name: String) -> Dictionary:
	var entry: Dictionary = MODEL_PRESENTATION.get(model_name, {})
	var size: float = clampf(float(entry.get("size", MODEL_DEFAULT_SIZE_M)), 0.02, MODEL_MAX_SIZE_M)
	var rotation: Vector3 = entry.get("rotation", Vector3.ZERO)
	return {"size": size, "rotation": rotation, "tint": bool(entry.get("tint", false))}


## The presentation transform for a model of bounds `source`: authored rotation,
## uniform scale onto the authored longest-axis size, then a translation that
## centres the resulting shape inside the grab collider. Pure, so the test can
## assert containment without a renderer.
static func model_transform(source: AABB, size_m: float, rotation_deg: Vector3) -> Transform3D:
	var basis: Basis = Basis.from_euler(Vector3(
		deg_to_rad(rotation_deg.x), deg_to_rad(rotation_deg.y), deg_to_rad(rotation_deg.z)))
	var longest: float = maxf(source.size.x, maxf(source.size.y, source.size.z))
	var factor: float = 1.0 if longest <= 0.0 else size_m / longest
	var oriented: Transform3D = Transform3D(basis.scaled(Vector3(factor, factor, factor)), Vector3.ZERO)
	var presented: AABB = oriented * source
	oriented.origin = Vector3(0.0, VISUAL_CENTRE_Y, 0.0) - presented.get_center()
	return oriented


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

	# Model first, primitive as the fallback. `build_model_visual()` returns null
	# for anything it cannot fully resolve, so a missing/corrupt .glb degrades to
	# the object the game already shipped instead of to an invisible one.
	var visual: MeshInstance3D = build_model_visual(spec)
	if visual == null:
		visual = build_primitive_visual(spec)

	# Registered so `SpawnedObject.set_enabled()` can still dim this object -- on
	# the model path `albedo_color` multiplies the atlas, so dimming works the
	# same way for textured and untextured objects.
	node.call("register_material", visual.material_override)

	node.add_child(visual)
	node.add_child(build_grab_collision(float(spec.get("grabSize", GRAB_SIZE_M))))
	return node


## The original path: a built-in primitive tinted with the record's pastel colour.
static func build_primitive_visual(spec: Dictionary) -> MeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = spec.get("color", FALLBACK_COLOR)
	material.roughness = 0.65
	material.metallic = 0.0

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = build_mesh(String(spec.get("primitive", DEFAULT_PRIMITIVE)))
	visual.material_override = material
	visual.position = Vector3(0.0, VISUAL_CENTRE_Y, 0.0)
	return visual


## A Kenney Food Kit mesh, presented at its authored size/rotation and centred in
## the grab collider. Returns `null` -- never a half-built node -- if the record
## names no model, or the model is absent, or the imported scene holds no mesh.
static func build_model_visual(spec: Dictionary) -> MeshInstance3D:
	var model_name: String = String(spec.get("model", "")).strip_edges()
	if model_name.is_empty():
		return null
	var mesh: Mesh = load_model_mesh(model_name)
	if mesh == null:
		return null

	var tint: Color = Color(1.0, 1.0, 1.0, 1.0)
	if bool(spec.get("modelTinted", false)):
		tint = spec.get("rawColor", spec.get("color", FALLBACK_COLOR))

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	visual.material_override = build_model_material(tint)
	visual.transform = model_transform(
		mesh.get_aabb(),
		float(spec.get("modelSize", MODEL_DEFAULT_SIZE_M)),
		spec.get("modelRotationDeg", Vector3.ZERO))
	return visual


## The single material used by every model. One `StandardMaterial3D` per spawned
## object (so per-object dimming stays independent) but all of them point at the
## SAME imported atlas resource -- one texture for the whole prop set.
static func build_model_material(tint: Color = Color(1.0, 1.0, 1.0, 1.0)) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = load_colormap()
	# The atlas is a grid of flat colour patches and the source glTF asks for
	# NEAREST; linear filtering bleeds neighbouring swatches across a silhouette.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# Matches `"doubleSided": true` in the source glTF -- the bowl and the spoon
	# are open shells and would show holes with backface culling on.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.65
	material.metallic = 0.0
	return material


static func load_colormap() -> Texture2D:
	if _colormap != null:
		return _colormap
	if ResourceLoader.exists(MODEL_TEXTURE_PATH):
		_colormap = ResourceLoader.load(MODEL_TEXTURE_PATH) as Texture2D
	return _colormap


## Pulls the single mesh out of an imported Kenney `.glb`. Every model in the kit
## is one node with one mesh and one material; the search is still recursive so a
## differently-nested model would not silently vanish.
static func load_model_mesh(model_name: String) -> Mesh:
	if _mesh_cache.has(model_name):
		return _mesh_cache[model_name]

	var mesh: Mesh = null
	var path: String = model_path_for(model_name)
	if not path.is_empty() and ResourceLoader.exists(path):
		var packed: PackedScene = ResourceLoader.load(path) as PackedScene
		if packed != null:
			var root: Node = packed.instantiate()
			if root != null:
				mesh = _find_first_mesh(root)
				root.free()

	_mesh_cache[model_name] = mesh
	return mesh


static func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child: Node in node.get_children():
		var found: Mesh = _find_first_mesh(child)
		if found != null:
			return found
	return null


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
