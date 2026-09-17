extends RefCounted

## Bundled 3D models: the CC0 packs that make each teaching object read as its
## English word, plus the meshes `ObjectSpawner` generates itself.
##
## This case guards the things that are easy to get silently wrong and
## impossible to notice in a headless run:
##
##   1. **Provenance.** Every pack is CC0 and needs no attribution, but its
##      `License.txt` must ship next to its models so the repo can always answer
##      "where did this come from?" (see `docs/ASSET_SOURCING_PLAN.md`).
##   2. **The external textures.** Kenney `.glb`s are NOT self-contained -- they
##      reference `Textures/colormap.png` *relative to the model file*, and the
##      three shipped packs have three DIFFERENT atlases. Ship the models without
##      their atlas and every prop renders flat white while the project still
##      loads and every other test still passes.
##   3. **Procedural models resolve too.** `proc/...` names have no file on disk,
##      so the "is the model in the repo?" check must not demand one -- but a
##      typo'd procedural name must still be caught, not silently fall back to a
##      primitive in front of a child.
##
## It also holds the mobile budget: one shared atlas per pack, and small meshes.
##
## Scripts are loaded BY PATH, never by `class_name`: `--headless --script` does
## not rebuild `.godot/global_script_class_cache.cfg`.

const SPAWNER_PATH: String = "res://scripts/gameplay/object_spawner.gd"
const OBJECTS_JSON: String = "res://content/objects.json"
const MODEL_ROOT: String = "res://assets/models"

## Kenney props measure 44-576 tris and the generated meshes 36-588 (the heaviest
## are the pillow at 588 and the blocks at 576; the clothing cut-outs are 40-92).
## A ceiling that leaves headroom but would still catch someone dropping a
## film-resolution mesh into the mobile build.
const MAX_TRIANGLES_PER_MODEL: int = 600


func test_name() -> String:
	return "assets_models"


func run() -> Array:
	var failures: Array = []
	var spawner: GDScript = load(SPAWNER_PATH) as GDScript
	if spawner == null:
		return ["could not load %s" % SPAWNER_PATH]

	failures.append_array(_test_provenance(spawner))
	failures.append_array(_test_pack_textures(spawner))
	failures.append_array(_test_every_declared_model_exists(spawner))
	failures.append_array(_test_procedural_models(spawner))
	failures.append_array(_test_bake_keeps_every_part(spawner))
	failures.append_array(_test_mesh_budget(spawner))
	failures.append_array(_test_every_object_has_a_model(spawner))
	failures.append_array(_test_every_procedural_model_is_presented(spawner))
	return failures


## No teaching object may fall back to a bare primitive any more.
##
## Every one of the 28 objects in `objects.json` now names a `model`, and that is
## a property worth locking down rather than a coincidence: a primitive is a
## sphere, a box, a capsule, a cylinder or a torus, and NONE of those is the
## shape of an English noun a child is being taught. The clothing objects shipped
## as coloured boxes for a while -- a shirt, trousers and pyjamas were the same
## cube in three colours, while the game teaches the word "square" with another
## cube -- and nothing failed, because a box is a perfectly valid primitive.
##
## The primitive path itself is NOT being removed: it is still the fallback that
## keeps the game playable if a `.glb` goes missing from an export, and
## `_test_missing_model_falls_back` in `test_gameplay_object_spawner` covers it.
## This asserts only that no SHIPPED record relies on it.
func _test_every_object_has_a_model(_spawner: GDScript) -> Array:
	var failures: Array = []
	var records: Array = _object_records()
	if records.is_empty():
		return ["could not read any object record from %s" % OBJECTS_JSON]
	for record: Dictionary in records:
		var object_id: String = String(record.get("objectId", ""))
		if String(record.get("model", "")).strip_edges().is_empty():
			failures.append(
					"object '%s' has no 'model' -- it would spawn as a bare '%s' primitive, which is not the shape of the word '%s'"
					% [object_id, String(record.get("primitive", "?")), String(record.get("word", "?"))])
	return failures


## A generated mesh with no `MODEL_PRESENTATION` entry silently spawns at
## `MODEL_DEFAULT_SIZE_M` and zero rotation. That is never what is wanted -- the
## rotation is what turns a silhouette into a recognisable word, and every one of
## these was chosen against a render -- but it is invisible headlessly, because
## the object still spawns and is still the right size.
func _test_every_procedural_model_is_presented(spawner: GDScript) -> Array:
	var failures: Array = []
	for model: String in spawner.PROCEDURAL_MODELS:
		var qualified: String = "%s/%s" % [String(spawner.PROCEDURAL_PACK), model]
		if not (spawner.MODEL_PRESENTATION as Dictionary).has(qualified):
			failures.append(
					"'%s' has no MODEL_PRESENTATION entry, so it would spawn unrotated at the default size"
					% qualified)
	return failures


## The packs actually used by the shipped content, as `pack -> true`. Derived
## from `objects.json` rather than hard-coded, so adding a pack does not need
## this file edited -- and so a pack that stops being used stops being asserted.
func _packs_in_use(spawner: GDScript) -> Dictionary:
	var packs: Dictionary = {}
	for model_name: String in _declared_models().values():
		var pack: String = String(spawner.model_pack(model_name))
		if pack != String(spawner.PROCEDURAL_PACK):
			packs[pack] = true
	return packs


## CC0 requires no attribution, but the licence file is what makes that
## checkable later. Losing it turns a known-clean asset into an unknown one.
func _test_provenance(spawner: GDScript) -> Array:
	var failures: Array = []
	var packs: Dictionary = _packs_in_use(spawner)
	if packs.is_empty():
		failures.append("no object in %s uses a bundled model pack" % OBJECTS_JSON)
		return failures

	for pack: String in packs.keys():
		var license_path: String = "%s/%s/License.txt" % [MODEL_ROOT, pack]
		if not FileAccess.file_exists(license_path):
			failures.append("%s is missing -- asset provenance must ship with the assets"
					% license_path)
			continue
		var text: String = FileAccess.get_file_as_string(license_path)
		if not text.to_lower().contains("creative commons zero"):
			failures.append("%s no longer states the CC0 licence" % license_path)
	return failures


## The gotcha that renders a whole pack flat white if it regresses. Checked per
## pack, because the atlases are NOT interchangeable: the three bundled packs
## ship three different 512x512 colormaps.
func _test_pack_textures(spawner: GDScript) -> Array:
	var failures: Array = []
	for pack: String in _packs_in_use(spawner).keys():
		var texture_path: String = String(spawner.pack_texture_path(pack))
		if texture_path.is_empty():
			# A pack with no atlas (Kenney Furniture Kit) colours its parts from
			# `MODEL_PRESENTATION.surfaces` instead, so there is nothing to check.
			continue
		if not texture_path.begins_with("%s/%s/" % [MODEL_ROOT, pack]):
			failures.append("pack '%s' points at an atlas outside its own folder: %s"
					% [pack, texture_path])
		if not ResourceLoader.exists(texture_path):
			failures.append("the atlas %s is missing -- '%s' models would render untextured"
					% [texture_path, pack])
			continue

		# One atlas per pack is the mobile budget. More than one file here means
		# someone imported a per-model texture copy.
		var dir: DirAccess = DirAccess.open("%s/%s/Textures" % [MODEL_ROOT, pack])
		if dir == null:
			failures.append("could not open %s/%s/Textures" % [MODEL_ROOT, pack])
			continue
		var textures: Array = []
		for file_name: String in dir.get_files():
			if file_name.ends_with(".import") or file_name.ends_with(".remap"):
				continue
			textures.append(file_name)
		if textures.size() != 1:
			failures.append("pack '%s' should have exactly one shared atlas, found %d: %s"
					% [pack, textures.size(), str(textures)])

		var texture: Texture2D = ResourceLoader.load(texture_path) as Texture2D
		if texture == null:
			failures.append("%s did not load as a Texture2D" % texture_path)
		elif texture.get_width() > 1024 or texture.get_height() > 1024:
			failures.append("the '%s' atlas is %dx%d -- too large for the mobile budget"
					% [pack, texture.get_width(), texture.get_height()])
	return failures


## Every `model` named in objects.json must resolve in THIS build. The spawner
## falls back to a primitive if it does not, so the game stays playable either
## way -- but shipping a dead reference is still a bug, and only a test catches
## it, since the fallback is deliberately silent to the child.
func _test_every_declared_model_exists(spawner: GDScript) -> Array:
	var failures: Array = []
	var declared: Dictionary = _declared_models()
	if declared.is_empty():
		failures.append("no object in %s declares a 'model' -- the prop art regressed" % OBJECTS_JSON)
		return failures

	for object_id: String in declared.keys():
		var model_name: String = declared[object_id]
		var path: String = String(spawner.model_path_for(model_name))
		# Source file AND imported resource, for file-backed models.
		# `ResourceLoader.exists()` is happy with a stale `.godot/imported`
		# entry, so a deleted `.glb` would still run locally while being
		# unrebuildable from a fresh clone. Procedural models have no file.
		if not path.is_empty() and not FileAccess.file_exists(path):
			failures.append("object '%s' declares model '%s' but the source file %s is not in the repo"
					% [object_id, model_name, path])
		if not spawner.model_available(model_name):
			failures.append("object '%s' declares model '%s' which does not resolve in this build"
					% [object_id, model_name])
			continue
		if spawner.load_model_mesh(model_name) == null:
			failures.append("model '%s' resolved but produced no mesh" % model_name)
	return failures


## The procedural half of the model layer. A generated mesh has no file to go
## missing, so the failure mode is different: a builder that silently returns
## null, or a name in `PROCEDURAL_MODELS` with no `match` arm behind it.
func _test_procedural_models(spawner: GDScript) -> Array:
	var failures: Array = []
	var names: Array = spawner.PROCEDURAL_MODELS
	if names.is_empty():
		failures.append("PROCEDURAL_MODELS is empty")

	for model: String in names:
		var qualified: String = "%s/%s" % [String(spawner.PROCEDURAL_PACK), model]
		if not spawner.model_available(qualified):
			failures.append("'%s' is listed in PROCEDURAL_MODELS but is not available" % qualified)
			continue
		if not String(spawner.model_path_for(qualified)).is_empty():
			failures.append("'%s' claims a file path; procedural models have no file" % qualified)
		var mesh: Mesh = spawner.load_model_mesh(qualified)
		if mesh == null:
			failures.append("'%s' has no builder -- build_procedural_mesh() returned null" % qualified)
			continue
		if mesh.get_aabb().get_volume() <= 0.0:
			failures.append("'%s' generated a degenerate mesh" % qualified)

	# A name nobody implemented must NOT quietly become a primitive-backed
	# object: `model_available()` is the gate that turns it into a warning.
	if spawner.model_available("%s/no-such-generator" % String(spawner.PROCEDURAL_PACK)):
		failures.append("an unimplemented procedural model reported itself as available")
	return failures


## The bake must keep EVERY part of a model, not just the first one it finds.
##
## Kenney is not consistent about this: a Food Kit apple is a single mesh, but a
## Cube Pet is five (body plus four legs) and a Furniture Kit lamp is one mesh
## with two materials. An earlier version of the loader took only the first mesh
## it found, which spawned a legless bear -- and nothing failed, because the
## object was still visible, still touchable and still roughly the right size.
## Comparing the baked triangle count against the source scene is what makes
## that silent, plausible-looking loss detectable.
func _test_bake_keeps_every_part(spawner: GDScript) -> Array:
	var failures: Array = []
	for object_id: String in _declared_models().keys():
		var model_name: String = _declared_models()[object_id]
		var path: String = String(spawner.model_path_for(model_name))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var packed: PackedScene = ResourceLoader.load(path) as PackedScene
		if packed == null:
			failures.append("model '%s' did not load as a PackedScene" % model_name)
			continue
		var root: Node = packed.instantiate()
		if root == null:
			failures.append("model '%s' could not be instantiated" % model_name)
			continue
		# Triangles, part count and combined bounds, measured by walking the
		# imported scene here rather than by asking the loader -- a second,
		# independent implementation, which is the only way this can disagree
		# with the loader when the loader is wrong.
		var source: Array = [0, 0, AABB()]
		_measure_source_meshes(root, Transform3D.IDENTITY, source)
		root.free()

		if int(source[1]) <= 0:
			failures.append("model '%s' has no mesh in its imported scene" % model_name)
			continue
		var baked: Mesh = spawner.load_model_mesh(model_name)
		if baked == null:
			failures.append("model '%s' baked to nothing" % model_name)
			continue
		if _triangles(baked) != int(source[0]):
			failures.append("model '%s' baked %d tris from %d source part(s) totalling %d -- parts were dropped"
					% [model_name, _triangles(baked), int(source[1]), int(source[0])])
		# Bounds catch what a triangle count cannot: parts that survived the
		# bake but lost their node transform and collapsed onto the origin.
		var expected: AABB = source[2]
		var actual: AABB = baked.get_aabb()
		if not actual.position.is_equal_approx(expected.position) \
				or not actual.size.is_equal_approx(expected.size):
			failures.append("model '%s' baked to bounds %s but its source parts span %s -- a part lost its transform"
					% [model_name, str(actual), str(expected)])
	return failures


func _measure_source_meshes(node: Node, parent_transform: Transform3D, totals: Array) -> void:
	var here: Transform3D = parent_transform
	if node is Node3D and node.get_parent() != null:
		here = parent_transform * (node as Node3D).transform

	var instance: MeshInstance3D = node as MeshInstance3D
	if instance != null and instance.mesh != null:
		totals[0] = int(totals[0]) + _triangles(instance.mesh)
		var bounds: AABB = here * instance.mesh.get_aabb()
		totals[2] = bounds if int(totals[1]) == 0 else (totals[2] as AABB).merge(bounds)
		totals[1] = int(totals[1]) + 1

	for child: Node in node.get_children():
		_measure_source_meshes(child, here, totals)


func _test_mesh_budget(spawner: GDScript) -> Array:
	var failures: Array = []
	for model_name: String in _declared_models().values():
		var mesh: Mesh = spawner.load_model_mesh(model_name)
		if mesh == null:
			continue
		# One surface per source material. Two is the most any bundled model
		# needs (a Furniture Kit lamp is shade + metal); more than that means
		# the bake stopped grouping and every part became its own draw call.
		if mesh.get_surface_count() > 2:
			failures.append("model '%s' baked to %d surfaces; at most 2 are expected"
					% [model_name, mesh.get_surface_count()])
		var triangles: int = _triangles(mesh)
		if triangles <= 0:
			failures.append("model '%s' baked to an empty mesh" % model_name)
		if triangles > MAX_TRIANGLES_PER_MODEL:
			failures.append("model '%s' is %d tris, over the %d budget"
					% [model_name, triangles, MAX_TRIANGLES_PER_MODEL])
		if mesh.get_aabb().get_volume() <= 0.0:
			failures.append("model '%s' has a degenerate bounding box" % model_name)
	return failures


func _triangles(mesh: Mesh) -> int:
	var total: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices == null:
			total += int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
		else:
			total += int((indices as PackedInt32Array).size() / 3)
	return total


## objectId -> model name, read straight from the shipped JSON.
func _declared_models() -> Dictionary:
	var models: Dictionary = {}
	for record: Dictionary in _object_records():
		var model_name: String = String(record.get("model", "")).strip_edges()
		if not model_name.is_empty():
			models[String(record.get("objectId", ""))] = model_name
	return models


func _object_records() -> Array:
	var records: Array = []
	if not FileAccess.file_exists(OBJECTS_JSON):
		return records
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OBJECTS_JSON))
	if typeof(parsed) != TYPE_DICTIONARY:
		return records
	for entry: Variant in (parsed as Dictionary).get("objects", []):
		if typeof(entry) == TYPE_DICTIONARY:
			records.append(entry)
	return records
