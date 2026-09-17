extends RefCounted

## Bundled 3D models: the Kenney Food Kit props that make each teaching object
## read as its English word.
##
## This case guards the two things that are easy to get silently wrong and
## impossible to notice in a headless run:
##
##   1. **Provenance.** The kit is CC0 and needs no attribution, but the
##      `License.txt` must ship next to the models so the repo can always answer
##      "where did this come from?" (see `docs/ASSET_SOURCING_PLAN.md`).
##   2. **The external texture.** Kenney `.glb`s are NOT self-contained -- they
##      reference `Textures/colormap.png` *relative to the model file*. Ship the
##      models without it and every prop renders flat white while the project
##      still loads and every other test still passes.
##
## It also holds the mobile budget: one shared 512x512 atlas for the whole prop
## set, and small meshes.
##
## Scripts are loaded BY PATH, never by `class_name`: `--headless --script` does
## not rebuild `.godot/global_script_class_cache.cfg`.

const SPAWNER_PATH: String = "res://scripts/gameplay/object_spawner.gd"
const OBJECTS_JSON: String = "res://content/objects.json"
const MODEL_DIR: String = "res://assets/models/kenney-food-kit"
const LICENSE_PATH: String = "res://assets/models/kenney-food-kit/License.txt"
const TEXTURE_PATH: String = "res://assets/models/kenney-food-kit/Textures/colormap.png"

## Kenney food props measure 44-136 tris. A generous ceiling that would still
## catch someone dropping a film-resolution mesh into the mobile build.
const MAX_TRIANGLES_PER_MODEL: int = 600


func test_name() -> String:
	return "assets_models"


func run() -> Array:
	var failures: Array = []
	var spawner: GDScript = load(SPAWNER_PATH) as GDScript
	if spawner == null:
		return ["could not load %s" % SPAWNER_PATH]

	failures.append_array(_test_provenance())
	failures.append_array(_test_shared_texture())
	failures.append_array(_test_every_declared_model_exists(spawner))
	failures.append_array(_test_mesh_budget(spawner))
	return failures


## CC0 requires no attribution, but the licence file is what makes that
## checkable later. Losing it turns a known-clean asset into an unknown one.
func _test_provenance() -> Array:
	var failures: Array = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(MODEL_DIR)) \
			and DirAccess.open(MODEL_DIR) == null:
		failures.append("model directory %s is missing" % MODEL_DIR)
		return failures
	if not FileAccess.file_exists(LICENSE_PATH):
		failures.append("%s is missing -- asset provenance must ship with the assets" % LICENSE_PATH)
		return failures
	var text: String = FileAccess.get_file_as_string(LICENSE_PATH)
	if not text.to_lower().contains("creative commons zero"):
		failures.append("%s no longer states the CC0 licence" % LICENSE_PATH)
	return failures


## The gotcha that renders every prop flat white if it regresses.
func _test_shared_texture() -> Array:
	var failures: Array = []
	if not ResourceLoader.exists(TEXTURE_PATH):
		failures.append("the shared colormap atlas %s is missing -- models would render untextured"
				% TEXTURE_PATH)
		return failures

	# One atlas for the whole prop set is the mobile budget. More than one file
	# here means someone imported a per-model texture copy.
	var dir: DirAccess = DirAccess.open(MODEL_DIR + "/Textures")
	if dir == null:
		failures.append("could not open %s/Textures" % MODEL_DIR)
		return failures
	var textures: Array = []
	for file_name: String in dir.get_files():
		if file_name.ends_with(".import") or file_name.ends_with(".remap"):
			continue
		textures.append(file_name)
	if textures.size() != 1:
		failures.append("expected exactly one shared atlas, found %d: %s" % [textures.size(), str(textures)])

	var texture: Texture2D = ResourceLoader.load(TEXTURE_PATH) as Texture2D
	if texture == null:
		failures.append("%s did not load as a Texture2D" % TEXTURE_PATH)
	elif texture.get_width() > 1024 or texture.get_height() > 1024:
		failures.append("the atlas is %dx%d -- too large for the mobile budget"
				% [texture.get_width(), texture.get_height()])
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
		# Source file AND imported resource. `ResourceLoader.exists()` is happy
		# with a stale `.godot/imported` entry, so a deleted `.glb` would still
		# run locally while being unrebuildable from a fresh clone.
		if not FileAccess.file_exists(spawner.model_path_for(model_name)):
			failures.append("object '%s' declares model '%s' but the source file %s is not in the repo"
					% [object_id, model_name, spawner.model_path_for(model_name)])
		if not spawner.model_available(model_name):
			failures.append("object '%s' declares model '%s' but %s is not in the build"
					% [object_id, model_name, spawner.model_path_for(model_name)])
			continue
		if spawner.load_model_mesh(model_name) == null:
			failures.append("model '%s' imported but contains no mesh" % model_name)
	return failures


func _test_mesh_budget(spawner: GDScript) -> Array:
	var failures: Array = []
	for model_name: String in _declared_models().values():
		var mesh: Mesh = spawner.load_model_mesh(model_name)
		if mesh == null:
			continue
		if mesh.get_surface_count() != 1:
			failures.append("model '%s' has %d surfaces; the kit is one-surface/one-material"
					% [model_name, mesh.get_surface_count()])
		var triangles: int = 0
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
		if triangles > MAX_TRIANGLES_PER_MODEL:
			failures.append("model '%s' is %d tris, over the %d budget"
					% [model_name, triangles, MAX_TRIANGLES_PER_MODEL])
		if mesh.get_aabb().get_volume() <= 0.0:
			failures.append("model '%s' has a degenerate bounding box" % model_name)
	return failures


## objectId -> model name, read straight from the shipped JSON.
func _declared_models() -> Dictionary:
	var models: Dictionary = {}
	if not FileAccess.file_exists(OBJECTS_JSON):
		return models
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OBJECTS_JSON))
	if typeof(parsed) != TYPE_DICTIONARY:
		return models
	for entry: Variant in (parsed as Dictionary).get("objects", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = entry
		var model_name: String = String(record.get("model", "")).strip_edges()
		if not model_name.is_empty():
			models[String(record.get("objectId", ""))] = model_name
	return models
