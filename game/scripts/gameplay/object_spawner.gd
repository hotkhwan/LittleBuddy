class_name ObjectSpawner
extends RefCounted

## Builds a playable 3D pickup at runtime from ONE record in
## `content/objects.json` -- nothing else. Adding content is therefore a JSON
## edit, never a new scene or script.
##
## Constraints (see CLAUDE.md / INTEGRATION_CONTRACT.md):
##   - a bundled CC0 mesh, or a mesh generated here, when the record names one,
##     otherwise a built-in primitive mesh -- a `StandardMaterial3D` either way,
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

## Where the GRAB COLLIDER's centre sits above the object's origin.
##
## ## This used to be where the VISUAL's centre sat, and that is the bug
##
## The comment here read *"so it rests on the floor/table plane rather than being
## half-buried"*, and for the one primitive it was tuned against -- a 16 cm
## sphere, half of it 8 cm, close enough to 10 -- it did. Every model since is
## normalised to its longest axis and then centred on this height, so how far a
## pickup floats became a function of **how tall it happens to be**:
##
## | measured in the real game, at the row's 1.8-2.3x presentation scale |
## |---|
## | a milk carton (tall, 26 cm presented) | sat 1 cm INTO the floor |
## | a bar of soap | hovered 7 cm |
## | a shape-sorter circle (a flat plate, presented face-on) | hovered 9 cm |
## | a spoon | hovered 13 cm |
## | **a banana, lying across the screen** | **hovered 18 cm** |
##
## Eighteen centimetres is a banana floating at a four-year-old's knee height,
## and it is `FOUNDER_PREVIEW_RC_CHECKLIST.md` open issue 5. It is a different
## fault from the kitchen's floating bowl, which was an ANCHOR in the wrong place
## (`kitchen_view.gd::_anchor()`); here every anchor was right and the mesh was
## hung off it by half of whatever it measured.
##
## So `model_transform()` and `build_primitive_visual()` now **stand the visual on
## the object's origin** (§6: "pivot at base centre" -- the same rule the kitchen
## props are authored to), and whoever positions the object decides the resting
## plane. This constant keeps only its second job: the middle of the grab box.
##
## **It is deliberately NOT changed**, because the grab box is the touch target
## and its size and position are what `grab_size_px()` measures and what
## `test_gameplay_object_spawner` asserts clears 220 px. A visual standing on
## y = 0 and no taller than `MODEL_MAX_SIZE_M` (0.26) still sits entirely inside
## a 0.34 box centred here, which spans -0.07 to +0.27 -- so nothing about what a
## child can hit has moved. Only the art came down to the floor.
const VISUAL_CENTRE_Y: float = 0.1

## Lifts a mesh of bounds `source` so it stands on y = 0 and is centred on x/z.
## Pure, and the one place the "props stand on their own base" rule is written.
static func base_offset(source: AABB) -> Vector3:
	var centre: Vector3 = source.get_center()
	return Vector3(-centre.x, -source.position.y, -centre.z)

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


## -- Bundled models ------------------------------------------------------------
##
## A `model` value is `"<pack>/<name>"`. A bare name with no slash resolves
## against `DEFAULT_PACK`, so content written before packs existed still works.
##
## Every pack below is CC0 -- commercial use explicit, no attribution required --
## and ships its own `License.txt` beside the models. See
## `docs/ASSET_SOURCING_PLAN.md` for the licence text and the provenance audit,
## and `test_assets_models` for the assertions that keep it that way.
##
##   `kenney-food-kit`      apple, banana, bowl, spoon, cup, glass, carton
##   `kenney-cube-pets`     the teddy (`animal-polar`)
##   `kenney-minigolf-kit`  the ball
##   `kenney-furniture-kit` the lamp and the toy box
##   `proc`                 meshes generated by this file -- see
##                          `PROCEDURAL_MODELS`. Used where a real object would
##                          have to be faked anyway: a shape sorter's shapes are
##                          trivial geometry, building blocks are deliberately
##                          NOT sourced from a studded brick pack (trade dress),
##                          and clothing/bath props have NO coherent CC0 source
##                          anywhere (ASSET_SOURCING_PLAN.md section 7).
const MODEL_ROOT: String = "res://assets/models/"
const MODEL_EXTENSION: String = ".glb"
const DEFAULT_PACK: String = "kenney-food-kit"
const PROCEDURAL_PACK: String = "proc"

## pack -> its shared palette atlas, or "" when the pack has no atlas.
##
## Each Kenney pack samples exactly ONE 512x512 atlas, so a whole pack costs one
## texture however many of its models are used. The atlases are NOT
## interchangeable -- the three shipped here have three different md5s -- so each
## pack keeps its own copy next to its models, which is also where the `.glb`
## expects to find it (see `Textures/colormap.png` in the source archives).
##
## The Furniture Kit ships untextured meshes with one material per part
## ("metal", "lamp", "wood", ...); those parts are coloured from the `surfaces`
## entry in `MODEL_PRESENTATION` instead.
const PACK_TEXTURES: Dictionary = {
	"kenney-food-kit": "res://assets/models/kenney-food-kit/Textures/colormap.png",
	"kenney-cube-pets": "res://assets/models/kenney-cube-pets/Textures/colormap.png",
	"kenney-minigolf-kit": "res://assets/models/kenney-minigolf-kit/Textures/colormap.png",
	"kenney-furniture-kit": "",
	"proc": "",
}

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
##   `surfaces` material-name -> hex, for packs with no atlas. The Furniture Kit
##              names every part ("metal", "lamp", "wood"), which is what lets a
##              two-tone object stay two-tone after retinting to pastel. Any part
##              not named here falls back to the record's pastel colour.
##
## Keys are fully qualified `pack/name`.
const MODEL_PRESENTATION: Dictionary = {
	# Leaf and stem turned toward the camera.
	"kenney-food-kit/apple": {"size": 0.19, "rotation": Vector3(0.0, 35.0, 0.0)},
	# Authored lying along -Z, i.e. pointing away from the camera. Turned across
	# the screen so the curve -- the thing that says "banana" -- is visible.
	"kenney-food-kit/banana": {"size": 0.25, "rotation": Vector3(0.0, 80.0, 0.0)},
	# A shallow bowl seen from 18.5 deg reads as a disc. Tipped toward the
	# camera so the hollow interior is visible.
	"kenney-food-kit/bowl": {"size": 0.26, "rotation": Vector3(30.0, 0.0, 0.0), "tint": true},
	# Three-quarter view: gable top plus two faces, which is what makes a carton
	# read as a carton.
	"kenney-food-kit/carton": {"size": 0.25, "rotation": Vector3(0.0, 25.0, 0.0)},
	# Handle turned side-on so it is not hidden behind the body.
	"kenney-food-kit/cup": {"size": 0.22, "rotation": Vector3(0.0, -95.0, 0.0), "tint": true},
	"kenney-food-kit/glass": {"size": 0.21, "rotation": Vector3(0.0, 0.0, 0.0), "tint": true},
	# A spoon is flat: edge-on it is just a stick. Stood up to face the camera
	# (74 deg) with a slight roll (28 deg) so the bowl separates from the handle
	# instead of sitting in line with it. See ASSET_SOURCING_PLAN.md section 2.
	# Rendered side by side against `cooking-spoon` and against several tints --
	# this was the most legible combination, and it is still the weakest-reading
	# model of the seven, because a spoon's identifying detail is small.
	"kenney-food-kit/utensil-spoon": {"size": 0.26, "rotation": Vector3(74.0, 0.0, 28.0), "tint": true},

	# A Cube Pet is authored ~1.5 m tall and its parts sit at minY = -0.300 before
	# their node transforms are applied, so it needs both the explicit size and
	# the recentring `model_transform()` does. Turned a little off-axis so the
	# muzzle and one ear break the silhouette; dead straight on it is a cube with
	# a face, which reads as a dice. Its animations are switched off in the
	# `.import` -- it is a static prop, so importing eight of them is dead weight.
	# Tinted: the only bear in the pack is the POLAR bear, and a white bear reads
	# as "polar bear", not "teddy". Multiplying the atlas by the record's brown
	# turns the body brown while the black eyes and nose stay black, which is
	# exactly a teddy -- and it makes the model agree with `colorWord: brown`.
	"kenney-cube-pets/animal-polar": {
		"size": 0.25, "rotation": Vector3(0.0, -18.0, 0.0), "tint": true,
	},

	# Authored at 7 cm. Scaled up like everything else -- `model_transform()`
	# normalises the longest axis, so the source size never matters.
	"kenney-minigolf-kit/ball-red": {"size": 0.19, "rotation": Vector3(0.0, 0.0, 0.0)},

	# Furniture Kit, untextured. Turned slightly so the shade is a trapezium
	# rather than a flat-on rectangle, which is what separates a lamp from a box.
	"kenney-furniture-kit/lampRoundTable": {
		"size": 0.26,
		"rotation": Vector3(0.0, -22.0, 0.0),
		"surfaces": {"lamp": "#FFD070", "metal": "#8E7C69"},
	},
	# Tipped toward the camera so the open mouth of the box is visible -- an open
	# box seen from the side is indistinguishable from a closed one.
	"kenney-furniture-kit/cardboardBoxOpen": {
		"size": 0.26,
		"rotation": Vector3(14.0, -32.0, 0.0),
		"surfaces": {"wood": "#C08650", "woodDark": "#8E5A2A"},
	},

	# -- Procedural (see PROCEDURAL_MODELS) --
	# A loose stack, not a neat tower: the offset says "several blocks" where a
	# flush tower reads as one tall brick.
	"proc/blocks": {"size": 0.26, "rotation": Vector3(0.0, -18.0, 0.0)},
	# The shape-sorter pieces are flat plates. Presented face-on to a camera that
	# sits 18.5 deg above the horizon, so the outline -- the whole point of the
	# word being taught -- is what the child sees, with just enough tilt left to
	# show the thickness and stop it reading as a 2D sticker.
	"proc/star": {"size": 0.24, "rotation": Vector3(-64.0, 0.0, 0.0)},
	"proc/circle": {"size": 0.24, "rotation": Vector3(-64.0, 0.0, 0.0)},
	"proc/square": {"size": 0.24, "rotation": Vector3(-64.0, 0.0, 12.0)},
	# Plump, not a slab. Turned off-axis so the long edge foreshortens.
	"proc/pillow": {"size": 0.24, "rotation": Vector3(-16.0, -32.0, 0.0)},
	# Folded layers, which is the only silhouette that says "blanket" rather than
	# "cushion" or "mat".
	"proc/blanket": {"size": 0.25, "rotation": Vector3(-8.0, -30.0, 0.0)},

	# -- Clothing (procedural, see PROCEDURAL_MODELS) --
	# Garments are presented as flat cut-out silhouettes, face-on to a camera
	# that sits 18.5 deg above the horizon, exactly like the shape-sorter plates
	# above. A garment laid flat IS how clothing is drawn for pre-readers, and
	# the outline is the entire teaching signal -- a t-shirt turned edge-on, or
	# modelled as a draped 3D solid, loses the sleeves and stops reading.
	# The small Z roll stops them looking like decals pinned to the screen.
	"proc/shirt": {"size": 0.26, "rotation": Vector3(-32.0, 0.0, -7.0)},
	"proc/pants": {"size": 0.26, "rotation": Vector3(-32.0, 0.0, 6.0)},
	"proc/pajamas": {"size": 0.26, "rotation": Vector3(-32.0, 0.0, -5.0)},
	# A shoe is the one garment whose silhouette is a SIDE profile, so this pair
	# stays upright and is only turned off-axis; tipping it back would flatten
	# the sole-to-toe curve that identifies it.
	"proc/shoes": {"size": 0.26, "rotation": Vector3(-10.0, -20.0, 0.0)},
	# Crown over a wide flat brim. Tilted toward the camera so the brim reads as
	# a full ellipse under the dome rather than as a line.
	"proc/hat": {"size": 0.26, "rotation": Vector3(-16.0, 0.0, 12.0)},

	# -- Bath --
	# A bar, not a cube: the pinch and the soft corners are what separate soap
	# from the building blocks.
	"proc/soap": {"size": 0.22, "rotation": Vector3(-10.0, -28.0, 0.0)},
	# Folded layers again, but a squarer footprint and tighter folds than the
	# blanket. The two are the same kind of object -- folded cloth -- and are
	# separated by proportion, colour and the fact that they are in different
	# categories, so they never appear in the same choice row.
	"proc/towel": {"size": 0.24, "rotation": Vector3(-14.0, -28.0, 0.0)},
	# Laid diagonally across the screen: a toothbrush is long and thin, and any
	# presentation that foreshortens it costs the whole silhouette.
	"proc/toothbrush": {"size": 0.26, "rotation": Vector3(-30.0, 0.0, 30.0)},
	# Three-quarter view so the beak breaks the silhouette. Dead side-on the
	# head merges into the body.
	"proc/bath-duck": {"size": 0.24, "rotation": Vector3(-4.0, -34.0, 0.0)},
}

## Imported meshes and the shared atlas are cached per run: `load()` already
## returns the same resource, this just avoids re-instantiating the imported
## scene once per spawned object.
static var _mesh_cache: Dictionary = {}
## pack -> its atlas (or null when the pack has none / it failed to load).
static var _colormap: Dictionary = {}


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
		"modelSurfaces": presentation.get("surfaces", {}),
		"interaction": interaction,
		"valid": object_id != "" and word != "",
		"warnings": warnings,
	}


## -- Model resolution (pure) ---------------------------------------------------

## `"pack/name"` -> `["pack", "name"]`, defaulting a bare name to `DEFAULT_PACK`.
## Returns two empty strings for an empty/blank model value.
static func split_model(model_name: String) -> PackedStringArray:
	var trimmed: String = model_name.strip_edges()
	if trimmed.is_empty():
		return PackedStringArray(["", ""])
	var slash: int = trimmed.rfind("/")
	if slash < 0:
		return PackedStringArray([DEFAULT_PACK, trimmed])
	return PackedStringArray([trimmed.substr(0, slash), trimmed.substr(slash + 1)])


## The fully-qualified form, so `"apple"` and `"kenney-food-kit/apple"` hit the
## same `MODEL_PRESENTATION` entry and the same mesh-cache slot.
static func canonical_model(model_name: String) -> String:
	var parts: PackedStringArray = split_model(model_name)
	if parts[1].is_empty():
		return ""
	return "%s/%s" % [parts[0], parts[1]]


static func model_pack(model_name: String) -> String:
	return split_model(model_name)[0]


static func is_procedural(model_name: String) -> bool:
	return model_pack(model_name) == PROCEDURAL_PACK


## Where the `.glb` lives. Empty for procedural models, which have no file.
static func model_path_for(model_name: String) -> String:
	var parts: PackedStringArray = split_model(model_name)
	if parts[1].is_empty() or parts[0] == PROCEDURAL_PACK:
		return ""
	return MODEL_ROOT + parts[0] + "/" + parts[1] + MODEL_EXTENSION


## True only when the model can actually be built in THIS build -- the `.glb` is
## present and importable, or the procedural builder exists. Everything
## downstream treats a false here as "there is no model", never as an error the
## child could ever see.
static func model_available(model_name: String) -> bool:
	var parts: PackedStringArray = split_model(model_name)
	if parts[1].is_empty():
		return false
	if parts[0] == PROCEDURAL_PACK:
		return PROCEDURAL_MODELS.has(parts[1])
	var path: String = model_path_for(model_name)
	if path.is_empty():
		return false
	return ResourceLoader.exists(path)


## Authored size/rotation for a model, with safe defaults for any model that has
## no entry in `MODEL_PRESENTATION`. `size` is always clamped to
## `MODEL_MAX_SIZE_M` so the visual can never outgrow the grab collider.
static func model_presentation(model_name: String) -> Dictionary:
	var entry: Dictionary = MODEL_PRESENTATION.get(canonical_model(model_name), {})
	var size: float = clampf(float(entry.get("size", MODEL_DEFAULT_SIZE_M)), 0.02, MODEL_MAX_SIZE_M)
	var rotation: Vector3 = entry.get("rotation", Vector3.ZERO)
	return {
		"size": size,
		"rotation": rotation,
		"tint": bool(entry.get("tint", false)),
		"surfaces": entry.get("surfaces", {}),
	}


## The presentation transform for a model of bounds `source`: authored rotation,
## uniform scale onto the authored longest-axis size, then a translation that
## STANDS the resulting shape on the object's origin, centred on x and z. Pure,
## so the test can assert both the grounding and the containment without a
## renderer. See `VISUAL_CENTRE_Y` for why this used to centre instead.
static func model_transform(source: AABB, size_m: float, rotation_deg: Vector3) -> Transform3D:
	var basis: Basis = Basis.from_euler(Vector3(
		deg_to_rad(rotation_deg.x), deg_to_rad(rotation_deg.y), deg_to_rad(rotation_deg.z)))
	var longest: float = maxf(source.size.x, maxf(source.size.y, source.size.z))
	var factor: float = 1.0 if longest <= 0.0 else size_m / longest
	var oriented: Transform3D = Transform3D(basis.scaled(Vector3(factor, factor, factor)), Vector3.ZERO)
	var presented: AABB = oriented * source
	oriented.origin = base_offset(presented)
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
	# the model path `albedo_color` multiplies the atlas (or the vertex colour),
	# so dimming works the same way for textured, untextured and procedural
	# objects. A two-tone model has one material per part and registers both,
	# otherwise half the lamp would stay bright while the other half dimmed.
	for material: StandardMaterial3D in visual_materials(visual):
		node.call("register_material", material)

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
	# Standing on the object's origin, exactly like the model path: a `torus` is
	# 3 cm thick and used to hover 8 cm, a `sphere` 2 cm, and the difference was
	# invisible in code and obvious on the floor.
	visual.position = base_offset(visual.mesh.get_aabb())
	return visual


## A bundled or procedural mesh, presented at its authored size/rotation and
## centred in the grab collider. Returns `null` -- never a half-built node -- if
## the record names no model, or the model is absent, or the imported scene holds
## no mesh.
static func build_model_visual(spec: Dictionary) -> MeshInstance3D:
	var model_name: String = String(spec.get("model", "")).strip_edges()
	if model_name.is_empty():
		return null
	var mesh: Mesh = load_model_mesh(model_name)
	if mesh == null:
		return null

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	apply_model_materials(visual, spec)
	visual.transform = model_transform(
		mesh.get_aabb(),
		float(spec.get("modelSize", MODEL_DEFAULT_SIZE_M)),
		spec.get("modelRotationDeg", Vector3.ZERO))
	return visual


## Colours a model visual, by one of three routes:
##
##   atlas pack -> ONE `material_override` sampling the pack's shared colormap;
##                 the model's own palette already carries the meaning, so the
##                 tint stays white unless `MODEL_PRESENTATION` asks for it,
##   no atlas   -> one material PER SURFACE, coloured from the presentation's
##                 `surfaces` map, so a two-tone object stays two-tone,
##   procedural -> one material whose vertex colour shades the record's own
##                 pastel, so `color`/`colorWord` stay the source of truth.
static func apply_model_materials(visual: MeshInstance3D, spec: Dictionary) -> void:
	var model_name: String = String(spec.get("model", ""))
	var mesh: Mesh = visual.mesh
	var pastel_color: Color = spec.get("color", FALLBACK_COLOR)

	if is_procedural(model_name):
		visual.material_override = build_procedural_material(pastel_color)
		return

	if pack_texture_path(model_pack(model_name)) != "":
		var tint: Color = Color(1.0, 1.0, 1.0, 1.0)
		if bool(spec.get("modelTinted", false)):
			tint = spec.get("rawColor", pastel_color)
		visual.material_override = build_model_material(model_name, tint)
		return

	var surfaces: Dictionary = spec.get("modelSurfaces", {})
	for surface: int in range(mesh.get_surface_count() if mesh != null else 0):
		var surface_name: String = ""
		if mesh is ArrayMesh:
			surface_name = (mesh as ArrayMesh).surface_get_name(surface)
		var color: Color = pastel_color
		if surfaces.has(surface_name):
			# Authored as-is: `surfaces` hexes are already chosen against the room,
			# and pastelising them a second time washes the part out to near-white.
			color = parse_color(String(surfaces[surface_name]))
		visual.set_surface_override_material(surface, build_untextured_material(color))


## Every `StandardMaterial3D` a visual actually renders with, whichever route
## `apply_model_materials()` took. Used to register them all for dimming.
static func visual_materials(visual: MeshInstance3D) -> Array:
	var materials: Array = []
	var override: StandardMaterial3D = visual.material_override as StandardMaterial3D
	if override != null:
		materials.append(override)
	for surface: int in range(visual.get_surface_override_material_count()):
		var material: StandardMaterial3D = \
				visual.get_surface_override_material(surface) as StandardMaterial3D
		if material != null:
			materials.append(material)
	return materials


## The material used by every atlas-backed model. One `StandardMaterial3D` per
## spawned object (so per-object dimming stays independent) but all of them point
## at the SAME imported atlas resource -- one texture per pack, however many of
## that pack's models are on screen.
static func build_model_material(
	model_name: String = "",
	tint: Color = Color(1.0, 1.0, 1.0, 1.0)
) -> StandardMaterial3D:
	var material: StandardMaterial3D = base_material()
	material.albedo_color = tint
	material.albedo_texture = load_colormap(model_pack(model_name))
	# The atlas is a grid of flat colour patches and the source glTF asks for
	# NEAREST; linear filtering bleeds neighbouring swatches across a silhouette.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return material


## One part of an untextured model (Kenney Furniture Kit).
static func build_untextured_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = base_material()
	material.albedo_color = color
	return material


## Procedural meshes carry a greyscale vertex colour used as a SHADE, so a stack
## of blocks separates into distinct blocks without the mesh having to know the
## record's colour -- which is what lets one cached mesh serve any colour.
static func build_procedural_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = base_material()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	return material


static func base_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	# Matches `"doubleSided": true` in the source glTF -- the bowl and the spoon
	# are open shells and would show holes with backface culling on.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.65
	material.metallic = 0.0
	return material


static func pack_texture_path(pack: String) -> String:
	return String(PACK_TEXTURES.get(pack, ""))


static func load_colormap(pack: String = DEFAULT_PACK) -> Texture2D:
	if _colormap.has(pack):
		return _colormap[pack]
	var texture: Texture2D = null
	var path: String = pack_texture_path(pack)
	if path != "" and ResourceLoader.exists(path):
		texture = ResourceLoader.load(path) as Texture2D
	_colormap[pack] = texture
	return texture


## The mesh for a model name, built once per run.
##
## Imported `.glb`s are BAKED: every `MeshInstance3D` in the imported scene is
## flattened into one `ArrayMesh`, with its node transform applied and its
## surfaces grouped by source material name. Kenney is not consistent about this
## -- a Food Kit apple is one mesh, but a Cube Pet is five (body plus four legs)
## and a Furniture Kit lamp is one mesh with two materials. Taking only the first
## mesh, as this used to, would have spawned a legless bear.
static func load_model_mesh(model_name: String) -> Mesh:
	var key: String = canonical_model(model_name)
	if key.is_empty():
		return null
	if _mesh_cache.has(key):
		return _mesh_cache[key]

	var mesh: Mesh = null
	if is_procedural(model_name):
		mesh = build_procedural_mesh(split_model(model_name)[1])
	else:
		var path: String = model_path_for(model_name)
		if not path.is_empty() and ResourceLoader.exists(path):
			var packed: PackedScene = ResourceLoader.load(path) as PackedScene
			if packed != null:
				var root: Node = packed.instantiate()
				if root != null:
					mesh = bake_scene_mesh(root)
					root.free()

	_mesh_cache[key] = mesh
	return mesh


## Flattens an imported model scene into a single `ArrayMesh`, one surface per
## distinct source material, each surface named after that material so
## `apply_model_materials()` can colour the parts individually.
static func bake_scene_mesh(root: Node) -> Mesh:
	var groups: Dictionary = {}
	var order: Array = []
	_collect_surfaces(root, Transform3D.IDENTITY, groups, order)
	if order.is_empty():
		return null

	var baked: ArrayMesh = ArrayMesh.new()
	for surface_name: String in order:
		var tool: SurfaceTool = groups[surface_name]
		tool.commit(baked)
		baked.surface_set_name(baked.get_surface_count() - 1, surface_name)
	return baked


static func _collect_surfaces(
	node: Node,
	parent_transform: Transform3D,
	groups: Dictionary,
	order: Array
) -> void:
	var here: Transform3D = parent_transform
	if node is Node3D and node.get_parent() != null:
		here = parent_transform * (node as Node3D).transform

	var instance: MeshInstance3D = node as MeshInstance3D
	if instance != null and instance.mesh != null:
		var mesh: Mesh = instance.mesh
		for surface: int in range(mesh.get_surface_count()):
			var material: Material = mesh.surface_get_material(surface)
			var surface_name: String = "surface"
			if material != null and not material.resource_name.is_empty():
				surface_name = material.resource_name
			if not groups.has(surface_name):
				var tool: SurfaceTool = SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[surface_name] = tool
				order.append(surface_name)
			(groups[surface_name] as SurfaceTool).append_from(mesh, surface, here)

	for child: Node in node.get_children():
		_collect_surfaces(child, here, groups, order)


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


## -- Procedural models ---------------------------------------------------------
##
## Fourteen objects are generated here rather than sourced, each for a reason:
##
##   `blocks`  deliberately NOT taken from a studded brick pack. Studded bricks
##             carry LEGO trade-dress exposure (ASSET_SOURCING_PLAN.md section 8)
##             and that is not a risk worth taking for one noun. Rounded studless
##             cubes teach the word just as well.
##   `star`, `circle`, `square`
##             a shape sorter's shapes ARE the geometry. Generating them gives an
##             exact, unmistakable outline; no sourced model would read better.
##   `pillow`  the Furniture Kit pillow is a flat, sharp-edged slab -- no more
##             readable than the primitive box it would have replaced. A plump
##             rounded form is what actually says "pillow".
##   `blanket` no CC0 blanket exists in any allowed pack (the nearest, Kenney's
##             `bedroll`, is brown camping canvas). Folded layers read as fabric.
##   `shirt`, `pants`, `pajamas`, `shoes`, `hat`
##             clothing is the known asset gap: no coherent CC0 clothing set
##             exists anywhere, Kenney's characters bake their clothes into the
##             character atlas, and pyjamas are absent from every source
##             (ASSET_SOURCING_PLAN.md section 7). These shipped as coloured
##             BOXES, which is an active mis-teach -- a shirt, trousers and
##             pyjamas were the same cube in three colours, and the game teaches
##             the word "square" with a cube elsewhere. A flat garment cut-out
##             is both correct and the form pre-readers already recognise.
##   `soap`, `towel`, `toothbrush`
##             the only CC0 pack that covers these (Tiny Treats "Bubbly
##             Bathroom") cannot be downloaded non-interactively. All three are
##             simple honest shapes, so generating them needs no licence and no
##             download, and a bar/fold/handle-plus-bristles cannot be wrong the
##             way a substituted "similar" model could.
##   `bath-duck`
##             "bath toy" shipped as a yellow SPHERE while "ball" ships as a red
##             sphere -- the two nouns were the same object in two colours. A
##             rubber duck is the unambiguous bath toy. Kenney Cube Pets was
##             checked for a duck: it has 24 animals and no duck, and
##             `animal-chick` would teach "chick", so it was not substituted.
##
## Meshes are authored in a roughly unit-sized space: `model_transform()`
## normalises the longest axis to the authored `size`, so only PROPORTION matters
## here. Vertex colour is a SHADE multiplied by the record's pastel colour at
## spawn time, which keeps one cached mesh usable at any colour and keeps
## `color`/`colorWord` in `objects.json` the single source of truth. It is
## greyscale everywhere except for the few ACCENTS where a second colour is what
## makes the object read at all -- a duck's orange beak and dark eyes, a
## toothbrush's pale bristles. Those are still multiplied by the record's colour,
## so a record recoloured in JSON recolours the whole object coherently.
const PROCEDURAL_MODELS: Array[String] = [
	"blocks", "star", "circle", "square", "pillow", "blanket",
	"shirt", "pants", "pajamas", "shoes", "hat",
	"soap", "towel", "toothbrush", "bath-duck",
]

## Squared-off-ness of the rounded-box generator: 2.0 is a sphere, and the shape
## approaches a hard-edged box as this grows.
const ROUNDNESS_PILLOW: float = 4.5
const ROUNDNESS_BLOCK: float = 10.0
const ROUNDNESS_FOLD: float = 5.0
## Near-spherical, for the duck's body/head and the hat's crown.
const ROUNDNESS_DUCK: float = 2.2
const ROUNDNESS_CROWN: float = 2.6
## A bar of soap keeps flat faces and soft edges, so it sits between the two.
const ROUNDNESS_SOAP: float = 4.6
## A toothbrush handle is a rounded rectangle in section, not a tube.
const ROUNDNESS_HANDLE: float = 4.0

## How much the pillow generator thins toward its rim (0 = none, 1 = flat edge).
const PILLOW_PINCH: float = 0.62

## The only non-greyscale vertex colours in the project. Each is MULTIPLIED by
## the record's pastel colour like every other shade, so they shift hue without
## ever escaping the object's authored palette: against the duck's pastel yellow
## the beak lands on orange and the eye on a near-black olive.
##
## There is no "lighter" accent, because the shade is a MULTIPLY and multiplying
## can only darken. Where a part has to look paler than the rest -- a
## toothbrush's bristles -- the surrounding parts are shaded DOWN instead.
const ACCENT_BEAK: Color = Color(1.0, 0.54, 0.22, 1.0)
const ACCENT_EYE: Color = Color(0.16, 0.16, 0.20, 1.0)


static func build_procedural_mesh(model: String) -> Mesh:
	match model:
		"blocks":
			return _build_blocks()
		"star":
			return _build_prism(_star_polygon(5, 1.0, 0.46), 0.42)
		"circle":
			return _build_prism(_regular_polygon(28, 1.0), 0.42)
		"square":
			return _build_prism(_rounded_square_polygon(0.28, 4), 0.42)
		"pillow":
			return _build_pillow()
		"blanket":
			return _build_blanket()
		"shirt":
			return _build_prism(PackedVector2Array(SHIRT_OUTLINE), 0.20)
		"pants":
			return _build_prism(PackedVector2Array(PANTS_OUTLINE), 0.20)
		"pajamas":
			return _build_prism(PackedVector2Array(PAJAMAS_OUTLINE), 0.22)
		"shoes":
			return _build_shoes()
		"hat":
			return _build_hat()
		"soap":
			return _build_soap()
		"towel":
			return _build_towel()
		"toothbrush":
			return _build_toothbrush()
		"bath-duck":
			return _build_bath_duck()
	return null


## Three blocks, offset and turned so the silhouette reads as several objects.
## Shaded apart (1.00 / 0.88 / 0.72) because three same-coloured cubes merge into
## one green lump under the room's single soft light -- the first render of this
## object read as two blobs, not as blocks.
static func _build_blocks() -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two on the floor (y = -0.60) side by side with a third stacked askew on the
	# left one. Every block rests on something: a floating block reads as a bug.
	_add_rounded_box(tool, Transform3D(
			Basis.from_euler(Vector3(0.0, deg_to_rad(-8.0), 0.0)), Vector3(-0.26, -0.37, 0.02)),
			Vector3(0.46, 0.46, 0.46), ROUNDNESS_BLOCK, 4, 1.00)
	_add_rounded_box(tool, Transform3D(
			Basis.from_euler(Vector3(0.0, deg_to_rad(34.0), 0.0)), Vector3(0.24, -0.40, -0.06)),
			Vector3(0.40, 0.40, 0.40), ROUNDNESS_BLOCK, 4, 0.72)
	_add_rounded_box(tool, Transform3D(
			Basis.from_euler(Vector3(0.0, deg_to_rad(18.0), 0.0)), Vector3(-0.17, 0.04, -0.05)),
			Vector3(0.36, 0.36, 0.36), ROUNDNESS_BLOCK, 4, 0.88)
	tool.index()
	return tool.commit()


## Plump in the middle, thin at the rim -- the `pinch` is what turns a rounded
## box into a pillow. Without it the form reads as a tile or a bar of soap from
## the Baby Room's high camera, which is exactly what the first three renders of
## this object did. Normals are regenerated because the pinch bends the surface
## away from the closed-form gradient `_add_rounded_box()` uses.
static func _build_pillow() -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_rounded_box(tool, Transform3D.IDENTITY,
			Vector3(1.0, 0.72, 0.82), ROUNDNESS_PILLOW, 7, 1.0, PILLOW_PINCH)
	tool.index()
	tool.generate_normals()
	return tool.commit()


## Three folded layers, each slightly smaller than the one below it and turned a
## few degrees. The stagger and the per-layer shading are what make it read as
## folded cloth instead of as a cushion or a mat.
static func _build_blanket() -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shades: Array[float] = [1.0, 0.88, 0.76]
	for layer: int in range(3):
		var t: float = float(layer)
		# Layer pitch is a shade under the layer thickness, so the folds touch.
		_add_rounded_box(tool, Transform3D(
				Basis.from_euler(Vector3(0.0, deg_to_rad(5.0 * t), 0.0)),
				Vector3(0.04 * t, 0.185 * t - 0.185, -0.04 * t)),
				Vector3(0.94 - 0.08 * t, 0.21, 0.62 - 0.06 * t), ROUNDNESS_FOLD, 3, shades[layer])
	tool.index()
	return tool.commit()


## A rounded box, generated by pushing a subdivided cube onto the surface
## |x|^p + |y|^p + |z|^p = 1. `p` = 2 gives a sphere and larger `p` sharpens the
## corners, so one generator covers a plump pillow, a soft block and a fold.
## Normals come from the closed-form gradient rather than from averaging faces,
## so there are no poles and no degenerate triangles to produce NaN normals.
static func _add_rounded_box(
	tool: SurfaceTool,
	transform: Transform3D,
	size: Vector3,
	roundness: float,
	steps: int,
	shade: float,
	pinch: float = 0.0,
	accent: Color = Color(1.0, 1.0, 1.0, 1.0)
) -> void:
	var half: Vector3 = size * 0.5
	var color: Color = Color(shade, shade, shade, 1.0) * accent
	color.a = 1.0
	# Six cube faces. `t1 x t2 == axis`, so a quad wound (u,v) -> (u+1,v) ->
	# (u+1,v+1) -> (u,v+1) faces outward.
	var faces: Array = [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
		[Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
		[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for face: Array in faces:
		var axis: Vector3 = face[0]
		var t1: Vector3 = face[1]
		var t2: Vector3 = face[2]
		for i: int in range(steps):
			for j: int in range(steps):
				var u0: float = -1.0 + 2.0 * float(i) / float(steps)
				var u1: float = -1.0 + 2.0 * float(i + 1) / float(steps)
				var v0: float = -1.0 + 2.0 * float(j) / float(steps)
				var v1: float = -1.0 + 2.0 * float(j + 1) / float(steps)
				var a: Vector3 = axis + t1 * u0 + t2 * v0
				var b: Vector3 = axis + t1 * u1 + t2 * v0
				var c: Vector3 = axis + t1 * u1 + t2 * v1
				var d: Vector3 = axis + t1 * u0 + t2 * v1
				_add_rounded_triangle(tool, transform, half, roundness, pinch, color, a, b, c)
				_add_rounded_triangle(tool, transform, half, roundness, pinch, color, a, c, d)


static func _add_rounded_triangle(
	tool: SurfaceTool,
	transform: Transform3D,
	half: Vector3,
	roundness: float,
	pinch: float,
	color: Color,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> void:
	for point: Vector3 in [a, b, c]:
		var unit: Vector3 = _pinched(_rounded_box_point(point, roundness), pinch)
		tool.set_color(color)
		tool.set_normal((transform.basis * _rounded_box_normal(unit, roundness, half)).normalized())
		tool.add_vertex(transform * (unit * half))


## Squeezes a unit-space point toward the equator in proportion to how far out it
## sits in the XZ plane, so the middle stays full and the rim tapers.
static func _pinched(unit: Vector3, pinch: float) -> Vector3:
	if pinch <= 0.0:
		return unit
	var radial: float = minf(Vector2(unit.x, unit.z).length(), 1.0)
	return Vector3(unit.x, unit.y * lerpf(1.0, 1.0 - pinch, radial * radial), unit.z)


static func _rounded_box_point(direction: Vector3, roundness: float) -> Vector3:
	var norm: float = pow(
		pow(absf(direction.x), roundness)
		+ pow(absf(direction.y), roundness)
		+ pow(absf(direction.z), roundness), 1.0 / roundness)
	if norm <= 0.0:
		return direction
	return direction / norm


static func _rounded_box_normal(unit: Vector3, roundness: float, half: Vector3) -> Vector3:
	var exponent: float = roundness - 1.0
	var gradient: Vector3 = Vector3(
		signf(unit.x) * pow(absf(unit.x), exponent) / maxf(half.x, 0.0001),
		signf(unit.y) * pow(absf(unit.y), exponent) / maxf(half.y, 0.0001),
		signf(unit.z) * pow(absf(unit.z), exponent) / maxf(half.z, 0.0001))
	if gradient.length_squared() <= 0.0:
		return Vector3.UP
	return gradient.normalized()


## A flat plate extruded from a closed 2D outline: the shape-sorter pieces and
## the clothing cut-outs. Flat normals, so the rim stays a crisp edge and the
## outline -- the word being taught -- keeps a hard silhouette.
static func _build_prism(outline: PackedVector2Array, thickness: float) -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if not _add_prism(tool, Transform3D.IDENTITY, outline, thickness, 1.0):
		return null
	tool.index()
	return tool.commit()


## Appends one extruded outline to `tool`, so a model can be several plates (the
## pair of shoes, the hat's brim). Returns false for a degenerate outline.
##
## The caps are triangulated with `Geometry2D.triangulate_polygon()` rather than
## fanned from the origin. The fan this replaced only works for outlines that are
## star-shaped about (0,0); the shape-sorter plates are, but a t-shirt's neck
## notch and a shoe's ankle opening are not, and a fan turns those into
## overlapping inside-out triangles. Triangulating also drops the cap from N
## triangles to N-2.
static func _add_prism(
	tool: SurfaceTool,
	transform: Transform3D,
	outline: PackedVector2Array,
	thickness: float,
	shade: float,
	accent: Color = Color(1.0, 1.0, 1.0, 1.0)
) -> bool:
	var count: int = outline.size()
	if count < 3:
		return false
	var half: float = thickness * 0.5
	var color: Color = Color(shade, shade, shade, 1.0) * accent
	color.a = 1.0
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	if indices.size() < 3:
		return false

	# Caps, one triangle wound each way per source triangle. Winding is not
	# load-bearing -- `base_material()` disables backface culling for every
	# procedural model -- so the explicit per-cap NORMAL is what lights these.
	for i: int in range(0, indices.size(), 3):
		var a: Vector2 = outline[indices[i]]
		var b: Vector2 = outline[indices[i + 1]]
		var c: Vector2 = outline[indices[i + 2]]
		for point: Vector2 in [c, b, a]:
			_add_prism_vertex(tool, transform, color, Vector3.BACK, Vector3(point.x, point.y, half))
		for point: Vector2 in [a, b, c]:
			_add_prism_vertex(
					tool, transform, color, Vector3.FORWARD, Vector3(point.x, point.y, -half))

	# Rim.
	for i: int in range(count):
		var current: Vector2 = outline[i]
		var next: Vector2 = outline[(i + 1) % count]
		var edge: Vector2 = (next - current).normalized()
		var normal: Vector3 = Vector3(edge.y, -edge.x, 0.0).normalized()
		var corners: Array = [
			Vector3(current.x, current.y, half), Vector3(next.x, next.y, half),
			Vector3(next.x, next.y, -half), Vector3(current.x, current.y, half),
			Vector3(next.x, next.y, -half), Vector3(current.x, current.y, -half),
		]
		for corner: Vector3 in corners:
			_add_prism_vertex(tool, transform, color, normal, corner)
	return true


static func _add_prism_vertex(
	tool: SurfaceTool,
	transform: Transform3D,
	color: Color,
	normal: Vector3,
	point: Vector3
) -> void:
	tool.set_color(color)
	tool.set_normal((transform.basis * normal).normalized())
	tool.add_vertex(transform * point)


## -- Clothing cut-outs ---------------------------------------------------------
##
## Garment outlines, wound counter-clockwise in the XY plane (x right, y up) so
## `_add_prism()`'s rim normals point outward. Authored roughly inside
## [-1, 1]^2; `model_transform()` normalises the longest axis afterwards, so only
## the proportions here matter.
##
## The neck and collar are cut as shallow Vs rather than as square notches with
## vertical walls: a wall that happens to lie along a radius from the centre is
## what makes a garment outline ambiguous to triangulate, and a V also reads more
## like a child's drawing of a shirt.

## Short-sleeved t-shirt.
const SHIRT_OUTLINE: Array[Vector2] = [
	Vector2(0.50, -0.88),   # hem, right
	Vector2(0.50, 0.34),    # side seam up to the underarm
	Vector2(1.00, 0.30),    # sleeve hem, outer
	Vector2(0.94, 0.78),    # sleeve top, outer
	Vector2(0.46, 0.86),    # shoulder
	Vector2(0.24, 0.88),    # neck, right
	Vector2(0.10, 0.66),
	Vector2(0.00, 0.62),    # neck, bottom
	Vector2(-0.10, 0.66),
	Vector2(-0.24, 0.88),
	Vector2(-0.46, 0.86),
	Vector2(-0.94, 0.78),
	Vector2(-1.00, 0.30),
	Vector2(-0.50, 0.34),
	Vector2(-0.50, -0.88),
]

## Trousers. The crotch apex sits ABOVE y = 0 so the outline's centre stays in
## solid cloth, and the two legs taper very slightly outward, which is what
## separates trousers from a pair of bars.
const PANTS_OUTLINE: Array[Vector2] = [
	Vector2(0.17, -0.96),   # right leg hem, inner
	Vector2(0.52, -0.96),   # right leg hem, outer
	Vector2(0.58, -0.18),
	Vector2(0.62, 0.90),    # waist, right
	Vector2(-0.62, 0.90),
	Vector2(-0.58, -0.18),
	Vector2(-0.52, -0.96),
	Vector2(-0.17, -0.96),  # left leg hem, inner
	Vector2(-0.10, -0.20),
	Vector2(0.00, -0.04),   # crotch
	Vector2(0.10, -0.20),
]

## A one-piece sleepsuit: long sleeves and long legs on one body. Deliberately
## NOT a second shirt -- pyjamas share the `dressing` category with the shirts
## and the trousers, so a child can be shown both at once and the two silhouettes
## have to be tellable apart.
const PAJAMAS_OUTLINE: Array[Vector2] = [
	Vector2(0.14, -0.98),   # right foot, inner
	Vector2(0.44, -0.98),   # right foot, outer
	Vector2(0.48, -0.34),
	Vector2(0.50, 0.14),
	Vector2(0.50, 0.44),    # underarm
	Vector2(1.00, 0.36),    # long sleeve, cuff
	Vector2(0.96, 0.72),
	Vector2(0.48, 0.80),    # shoulder
	Vector2(0.26, 0.86),    # collar
	Vector2(0.10, 0.64),
	Vector2(0.00, 0.60),
	Vector2(-0.10, 0.64),
	Vector2(-0.26, 0.86),
	Vector2(-0.48, 0.80),
	Vector2(-0.96, 0.72),
	Vector2(-1.00, 0.36),
	Vector2(-0.50, 0.44),
	Vector2(-0.50, 0.14),
	Vector2(-0.48, -0.34),
	Vector2(-0.44, -0.98),
	Vector2(-0.14, -0.98),  # left foot, inner
	Vector2(-0.08, -0.30),
	Vector2(0.00, -0.16),   # crotch
	Vector2(0.08, -0.30),
]

## One shoe, in side profile: an upper with a scooped ankle opening, sitting on a
## separate SOLE. The scoop is why these caps have to be triangulated rather than
## fanned.
##
## The sole is its own outline, shaded right down, because that is what actually
## makes the form read. The first version of this object was one solid profile at
## a single shade and rendered as two brown pebbles -- a shoe is identified by the
## dark band along the bottom and the upward sweep of the toe, not by its overall
## blob, and neither survives without the tonal split.
const SHOE_UPPER_OUTLINE: Array[Vector2] = [
	Vector2(-0.86, -0.16),  # heel, sitting on the sole
	Vector2(0.90, -0.16),
	Vector2(1.00, 0.08),    # toe tip
	Vector2(0.90, 0.26),    # toe box, domed
	Vector2(0.58, 0.38),
	Vector2(0.26, 0.42),    # instep, the high point of the vamp
	Vector2(-0.02, 0.30),
	Vector2(-0.24, 0.04),   # throat: the ankle opening dips to here
	Vector2(-0.46, 0.34),
	Vector2(-0.60, 0.72),   # collar, front
	Vector2(-0.86, 0.70),   # collar, back
	Vector2(-0.94, 0.14),   # heel counter
]

## The sole: flat on the ground, standing PROUD of the upper at both ends so it
## reads as a separate dark band rather than as shading on the same lump.
const SHOE_SOLE_OUTLINE: Array[Vector2] = [
	Vector2(-0.98, -0.44),
	Vector2(0.96, -0.44),
	Vector2(1.08, -0.16),   # toe spring
	Vector2(1.02, 0.04),
	Vector2(0.92, -0.10),
	Vector2(-0.92, -0.10),
	Vector2(-1.00, -0.24),
]


## A pair, because the word is "shoes". The second shoe is set back, up and to one
## side, and shaded down: two identical shoes side by side at the same depth merge
## into one wide slab from the Baby Room's camera.
static func _build_shoes() -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var placements: Array = [
		[Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(-6.0), 0.0)),
				Vector3(-0.10, -0.34, 0.42)), 1.00],
		[Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(5.0), 0.0)),
				Vector3(0.12, 0.40, -0.42)), 0.74],
	]
	for placement: Array in placements:
		var transform: Transform3D = placement[0]
		var shade: float = placement[1]
		_add_prism(tool, transform, PackedVector2Array(SHOE_UPPER_OUTLINE), 0.42, shade)
		_add_prism(tool, transform, PackedVector2Array(SHOE_SOLE_OUTLINE), 0.48, shade * 0.42)
	tool.index()
	return tool.commit()


## A dome crown on a wide flat brim. The proportion is the whole message: the
## brim is two and a half times the crown's width, which is what stops the form
## reading as a lampshade or a bowl.
static func _build_hat() -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Brim: a flat disc, lying in XZ, so it is extruded along Y rather than Z.
	_add_prism(tool, Transform3D(
			Basis.from_euler(Vector3(deg_to_rad(-90.0), 0.0, 0.0)), Vector3(0.0, -0.22, 0.0)),
			_regular_polygon(24, 1.0), 0.11, 0.80)
	# Crown, sunk into the brim so the two read as one object rather than as a
	# ball balanced on a plate.
	_add_rounded_box(tool, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.04, 0.0)),
			Vector3(0.80, 0.82, 0.80), ROUNDNESS_CROWN, 4, 1.00)
	tool.index()
	return tool.commit()


## -- Bath ----------------------------------------------------------------------

## A bar of soap: a rounded box, pinched at the rim so the faces bulge. The pinch
## is what stops it reading as one of the building blocks.
static func _build_soap() -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_rounded_box(tool, Transform3D.IDENTITY,
			Vector3(1.0, 0.50, 0.72), ROUNDNESS_SOAP, 5, 1.0, 0.0)
	tool.index()
	tool.generate_normals()
	return tool.commit()


## A folded towel: three tight folds, squarer in plan and thinner per fold than
## the blanket, and staggered so the layered EDGE -- the thing that says "cloth
## that has been folded" -- faces the camera.
static func _build_towel() -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shades: Array[float] = [1.0, 0.86, 0.72]
	for layer: int in range(3):
		var t: float = float(layer)
		_add_rounded_box(tool, Transform3D(
				Basis.from_euler(Vector3(0.0, deg_to_rad(7.0 * t), 0.0)),
				Vector3(0.05 * t, 0.155 * t - 0.155, -0.05 * t)),
				Vector3(0.88 - 0.07 * t, 0.17, 0.80 - 0.07 * t), ROUNDNESS_FOLD, 3, shades[layer])
	tool.index()
	return tool.commit()


## Handle, head and a pale block of bristles. Nothing else is needed: a long thin
## stick with a brush on one end is unambiguous, and it is the one bath object
## whose identifying feature is a second colour rather than a shape.
static func _build_toothbrush() -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Handle and neck, shaded DOWN so the bristles can be the pale part.
	_add_rounded_box(tool, Transform3D(Basis.IDENTITY, Vector3(-0.38, 0.0, 0.0)),
			Vector3(1.22, 0.19, 0.16), ROUNDNESS_HANDLE, 3, 0.72)
	_add_rounded_box(tool, Transform3D(Basis.IDENTITY, Vector3(0.45, 0.0, 0.0)),
			Vector3(0.52, 0.13, 0.12), ROUNDNESS_HANDLE, 2, 0.64)
	# Head.
	_add_rounded_box(tool, Transform3D(Basis.IDENTITY, Vector3(0.80, 0.01, 0.0)),
			Vector3(0.44, 0.16, 0.20), ROUNDNESS_HANDLE, 2, 0.78)
	# Bristles: the palest block, which is the cue that says "brush".
	_add_rounded_box(tool, Transform3D(Basis.IDENTITY, Vector3(0.80, 0.16, 0.0)),
			Vector3(0.40, 0.17, 0.17), ROUNDNESS_BLOCK, 1, 1.00)
	tool.index()
	return tool.commit()


## A rubber duck. Body, head, beak, tail and two eyes -- the minimum set that
## reads as a duck rather than as a blob with a bump. The beak and the eyes are
## the only ACCENT-coloured geometry in the game; without the beak this is a
## snowman, and without the eyes it is a gourd.
static func _build_bath_duck() -> Mesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body: a fat egg sitting low, pinched so it flattens where it would float.
	_add_rounded_box(tool, Transform3D(Basis.IDENTITY, Vector3(-0.04, -0.22, 0.0)),
			Vector3(1.10, 0.68, 0.86), ROUNDNESS_DUCK, 4, 1.00, 0.18)
	# Head, set forward and high enough that a neck gap is visible from the side.
	# Sunk into the body it reads as one lump, which was the first render.
	_add_rounded_box(tool, Transform3D(Basis.IDENTITY, Vector3(0.24, 0.42, 0.0)),
			Vector3(0.56, 0.54, 0.52), ROUNDNESS_DUCK, 3, 1.00)
	# Tail, tipped up.
	_add_rounded_box(tool, Transform3D(
			Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(34.0))), Vector3(-0.56, 0.00, 0.0)),
			Vector3(0.36, 0.26, 0.28), ROUNDNESS_DUCK, 2, 0.88)
	# Beak.
	_add_rounded_box(tool, Transform3D(
			Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(-10.0))), Vector3(0.60, 0.36, 0.0)),
			Vector3(0.38, 0.15, 0.23), ROUNDNESS_BLOCK, 1, 1.0, 0.0, ACCENT_BEAK)
	# Eyes.
	for side: float in [1.0, -1.0]:
		_add_rounded_box(tool, Transform3D(Basis.IDENTITY, Vector3(0.40, 0.52, 0.19 * side)),
				Vector3(0.14, 0.14, 0.14), ROUNDNESS_DUCK, 1, 1.0, 0.0, ACCENT_EYE)
	tool.index()
	return tool.commit()


## A point-up star. The first vertex sits at 90 deg so the star always presents
## a point upward, which is what a child draws when asked for a star.
static func _star_polygon(points: int, outer: float, inner: float) -> PackedVector2Array:
	var outline: PackedVector2Array = PackedVector2Array()
	var step: float = PI / float(points)
	for i: int in range(points * 2):
		var radius: float = outer if i % 2 == 0 else inner
		var angle: float = PI * 0.5 + float(i) * step
		outline.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return outline


static func _regular_polygon(sides: int, radius: float) -> PackedVector2Array:
	var outline: PackedVector2Array = PackedVector2Array()
	for i: int in range(sides):
		var angle: float = TAU * float(i) / float(sides)
		outline.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return outline


## A square with rounded corners -- still unmistakably a square in silhouette,
## but without the sharp points that make a child-held toy look like a hazard.
static func _rounded_square_polygon(corner: float, segments: int) -> PackedVector2Array:
	var outline: PackedVector2Array = PackedVector2Array()
	var inner: float = 1.0 - corner
	var centres: Array[Vector2] = [
		Vector2(inner, inner), Vector2(-inner, inner),
		Vector2(-inner, -inner), Vector2(inner, -inner),
	]
	for index: int in range(4):
		var start: float = TAU * 0.25 * float(index)
		for step: int in range(segments + 1):
			var angle: float = start + TAU * 0.25 * float(step) / float(segments)
			outline.append(centres[index] + Vector2(cos(angle), sin(angle)) * corner)
	return outline


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
