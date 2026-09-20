extends RefCounted

## Meshy-generated teaching props for Aliz Tutor Mode.
##
## Every prop in `content/tutor/props_manifest.json` must be a real, importable
## GLB that instantiates headlessly and sits inside the mobile prop budget:
##
##   * <= MAX_TRIANGLES per prop (the whole model, all surfaces),
##   * one base-colour texture per material, <= MAX_TEXTURE px on its long side,
##   * no metallic, no emissive (art bible: "there is no metal"),
##   * a positive `scaleToMetres` and a non-empty Meshy task-id list, because a
##     prop with no provenance cannot be re-downloaded or audited.
##
## It also holds the ledger to the owner's numbers: the manifest's summed
## `creditsSpent` may never exceed the sprint ceiling, and every entry must carry
## the licence statement so provenance ships WITH the asset, not in a doc.
##
## Scripts are loaded BY PATH, never by `class_name`: `--headless --script` does
## not rebuild `.godot/global_script_class_cache.cfg`.

const MANIFEST_PATH: String = "res://content/tutor/props_manifest.json"
const MAX_TRIANGLES: int = 3000
const MAX_TEXTURE: int = 512
const SPRINT_CEILING_CREDITS: int = 100
const REQUIRED_LICENSE_WORD: String = "Meshy"


func test_name() -> String:
	return "tutor_props"


func run():
	var failures: Array = []
	var manifest: Dictionary = _read_manifest()
	if manifest.is_empty():
		return ["could not read %s" % MANIFEST_PATH]
	if int(manifest.get("manifestVersion", 0)) < 1:
		failures.append("manifest has no manifestVersion")
	var props: Array = manifest.get("props", [])
	if props.is_empty():
		return ["manifest lists no props"]

	var seen: Dictionary = {}
	var credits_total: int = 0
	for prop: Dictionary in props:
		var prop_id: String = String(prop.get("propId", ""))
		if prop_id.is_empty():
			failures.append("a prop has no propId")
			continue
		if seen.has(prop_id):
			failures.append("propId '%s' is listed twice" % prop_id)
		seen[prop_id] = true
		credits_total += int(prop.get("creditsSpent", 0))
		failures.append_array(_test_provenance(prop_id, prop))
		failures.append_array(_test_model(prop_id, prop))

	if credits_total > SPRINT_CEILING_CREDITS:
		failures.append("manifest claims %d credits spent, over the %d sprint ceiling"
				% [credits_total, SPRINT_CEILING_CREDITS])
	return failures


func _test_provenance(prop_id: String, prop: Dictionary):
	var failures: Array = []
	var ids: Array = prop.get("meshyTaskIds", [])
	if ids.is_empty():
		failures.append("prop '%s' has no meshyTaskIds -- it cannot be audited or re-downloaded" % prop_id)
	for id: Variant in ids:
		var s: String = String(id)
		if s == "00000000-0000-0000-0000-000000000000" or s.length() != 36:
			failures.append("prop '%s' has a bad task id '%s'" % [prop_id, s])
	if not String(prop.get("license", "")).contains(REQUIRED_LICENSE_WORD):
		failures.append("prop '%s' license statement does not name %s" % [prop_id, REQUIRED_LICENSE_WORD])
	if float(prop.get("scaleToMetres", 0.0)) <= 0.0:
		failures.append("prop '%s' has no positive scaleToMetres" % prop_id)
	if int(prop.get("creditsSpent", -1)) < 0:
		failures.append("prop '%s' has no creditsSpent" % prop_id)
	return failures


func _test_model(prop_id: String, prop: Dictionary):
	var failures: Array = []
	var file: String = String(prop.get("file", ""))
	if file.is_empty():
		return ["prop '%s' has no file" % prop_id]
	if not FileAccess.file_exists(file):
		return ["prop '%s' file is missing: %s" % [prop_id, file]]
	if not ResourceLoader.exists(file):
		return ["prop '%s' file is not importable by Godot: %s" % [prop_id, file]]
	var scene: PackedScene = load(file) as PackedScene
	if scene == null:
		return ["prop '%s' did not load as a PackedScene: %s" % [prop_id, file]]
	var root: Node = scene.instantiate()
	if root == null:
		return ["prop '%s' did not instantiate" % prop_id]

	var meshes: Array = []
	_collect_meshes(root, meshes)
	if meshes.is_empty():
		failures.append("prop '%s' has no MeshInstance3D" % prop_id)

	var triangles: int = 0
	var texture_long_side: int = 0
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for surface: int in range(mi.mesh.get_surface_count()):
			triangles += _surface_triangles(mi.mesh, surface)
			var mat: Material = mi.get_active_material(surface)
			if mat == null:
				failures.append("prop '%s' surface %d has no material" % [prop_id, surface])
				continue
			var std: BaseMaterial3D = mat as BaseMaterial3D
			if std == null:
				continue
			if std.metallic > 0.0:
				failures.append("prop '%s' has metallic %.2f; the art bible allows none" % [prop_id, std.metallic])
			if std.emission_enabled:
				failures.append("prop '%s' has emission enabled" % prop_id)
			var tex: Texture2D = std.albedo_texture
			if tex == null:
				failures.append("prop '%s' surface %d has no albedo texture" % [prop_id, surface])
			else:
				texture_long_side = maxi(texture_long_side, maxi(tex.get_width(), tex.get_height()))
	root.free()

	if triangles <= 0:
		failures.append("prop '%s' has no triangles" % prop_id)
	if triangles > MAX_TRIANGLES:
		failures.append("prop '%s' is %d tris, over the %d budget" % [prop_id, triangles, MAX_TRIANGLES])
	var declared: int = int(prop.get("triangles", -1))
	if declared != triangles:
		failures.append("prop '%s' manifest says %d tris but the file has %d" % [prop_id, declared, triangles])
	if texture_long_side > MAX_TEXTURE:
		failures.append("prop '%s' texture is %d px, over %d" % [prop_id, texture_long_side, MAX_TEXTURE])
	if int(prop.get("textureSize", -1)) != texture_long_side:
		failures.append("prop '%s' manifest says textureSize %d but the file has %d"
				% [prop_id, int(prop.get("textureSize", -1)), texture_long_side])
	return failures


func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child: Node in node.get_children():
		_collect_meshes(child, out)


func _surface_triangles(mesh: Mesh, surface: int) -> int:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices != null and (indices as PackedInt32Array).size() > 0:
		return (indices as PackedInt32Array).size() / 3
	var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
	if vertices == null:
		return 0
	return (vertices as PackedVector3Array).size() / 3


func _read_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
