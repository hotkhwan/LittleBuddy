extends RefCounted

## THE MESHY PROP REGISTRY: generated GLB props for the house, behind one seam.
##
## `object_spawner.gd` already owns the Baby Room's bundled models (Kenney
## packs + procedural meshes, keyed `pack/name`), and the tutor classroom
## owns its own manifest (`content/tutor/props_manifest.json`). The HOUSE --
## the kitchen's drawn items, the room furniture in `room_props.gd` -- had no
## seam at all: every shape is `SurfaceTool` code. This file is that seam.
##
## ## What it does
##
## `res://assets/models/meshy-props/manifest.json` names a GLB per prop id,
## with its real-world size, its provenance (Meshy task ids, credits, licence)
## and its triangle gate. A consumer asks for a prop by id and gets back an
## `ArrayMesh` that is
##
##   * BAKED: every `MeshInstance3D` of the imported scene flattened into one
##     mesh with node transforms applied, materials kept per surface (the
##     base-colour texture is the whole look of a Meshy prop -- unlike a
##     Kenney atlas model there is no shared colormap to override it with);
##   * IN METRES, scaled so its longest axis is the requested size (or the
##     manifest's `longestAxisMetres` when the caller passes none);
##   * STANDING ON ITS OWN ORIGIN, base at Y = 0, centred on X/Z -- ART_BIBLE
##     section 6's "pivot at base centre", which is what `kitchen_view.gd`'s
##     anchors, its hand offset and `test_kitchen_view_placement.gd` assume.
##
## A missing manifest, a missing file, a file that fails to import or a mesh
## with no triangles all return `null`, and the caller keeps its drawn
## primitive. Nothing here can take a shape away from a child; it can only
## put a better one in its place.
##
## ## Budget
##
## One draw call per prop (one surface), one 512 texture per prop, and a
## per-prop `maxTriangles` gate read from the manifest and asserted by
## `test_assets_models.gd`. Section 7 material policy is applied on bake:
## metallic 0, roughness >= 0.85, no emission, back-face culling.
##
## Static and cached: an imported scene is instantiated once per run, and a
## sized mesh once per (prop, size). Nothing here touches a `SceneTree`.

const MANIFEST_PATH: String = "res://assets/models/meshy-props/manifest.json"

## The gate applied when a manifest entry names none. Matches the tutor
## props' gate (`test_tutor_props.gd`); most house props sit far under it.
const DEFAULT_MAX_TRIANGLES: int = 3000

## Section 7: nothing in this game is shiny.
const MIN_ROUGHNESS: float = 0.85

static var _manifest: Dictionary = {}
static var _manifest_loaded: bool = false
## propId -> baked source mesh (metres as authored, transforms applied).
static var _source_cache: Dictionary = {}
## "propId@size" -> sized, grounded mesh.
static var _sized_cache: Dictionary = {}


## -- Manifest -----------------------------------------------------------------

## propId -> entry, from the manifest. Empty when there is no manifest, which is
## a legitimate state (a fresh clone before any prop was generated).
static func props() -> Dictionary:
	if _manifest_loaded:
		return _manifest
	_manifest_loaded = true
	_manifest = {}
	if not FileAccess.file_exists(MANIFEST_PATH):
		return _manifest
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("prop_registry: %s is not a JSON object; no Meshy props" % MANIFEST_PATH)
		return _manifest
	var rows: Variant = (parsed as Dictionary).get("props", [])
	if typeof(rows) == TYPE_ARRAY:
		for row: Variant in rows:
			if typeof(row) == TYPE_DICTIONARY:
				var prop_id: String = String((row as Dictionary).get("propId", "")).strip_edges()
				if not prop_id.is_empty():
					_manifest[prop_id] = row
	elif typeof(rows) == TYPE_DICTIONARY:
		for key: Variant in (rows as Dictionary).keys():
			var row: Variant = (rows as Dictionary)[key]
			if typeof(row) == TYPE_DICTIONARY:
				_manifest[String(key)] = row
	return _manifest


static func entry(prop_id: String) -> Dictionary:
	return (props().get(prop_id, {}) as Dictionary).duplicate(true)


static func ids() -> Array:
	var out: Array = props().keys()
	out.sort()
	return out


static func file_for(prop_id: String) -> String:
	return String(entry(prop_id).get("file", ""))


static func max_triangles(prop_id: String) -> int:
	return int(entry(prop_id).get("maxTriangles", DEFAULT_MAX_TRIANGLES))


## True only when the prop can actually be built in THIS build: named in the
## manifest AND its GLB imports here. Everything downstream treats false as
## "keep the drawn shape", never as an error a child could see.
static func available(prop_id: String) -> bool:
	var path: String = file_for(prop_id)
	return not path.is_empty() and ResourceLoader.exists(path)


## -- Meshes -------------------------------------------------------------------

## The prop as authored: imported, flattened, materials kept. `null` if it
## cannot be built.
static func source_mesh(prop_id: String) -> ArrayMesh:
	if _source_cache.has(prop_id):
		return _source_cache[prop_id]
	var mesh: ArrayMesh = null
	if available(prop_id):
		var packed: PackedScene = ResourceLoader.load(file_for(prop_id)) as PackedScene
		if packed != null:
			var root: Node = packed.instantiate()
			if root != null:
				mesh = bake(root, Transform3D.IDENTITY)
				root.free()
	_source_cache[prop_id] = mesh
	return mesh


## Where a prop's origin sits, from the manifest's `pivot`:
##
##   `baseCentre`  base on Y = 0, footprint centred -- everything that stands
##                 on a surface (default);
##   `hingeLeft`   a door leaf hung on its -X edge: spans X in [0, w], Y and Z
##                 centred -- `room.gd::_build_wardrobe_doors()` LEFT leaf;
##   `hingeRight`  the mirror: spans X in [-w, 0] -- the RIGHT leaf;
##   `hingeBack`   a lid hung on its back edge: spans Z in [0, d] toward the
##                 camera, Y in [0, t], X centred -- `room.gd`'s storage lid.
##
## The hinge pivots are what let a split GLB door/lid replace a drawn one
## under the SAME hinge node with no change to the swing maths.
const PIVOT_BASE_CENTRE: String = "baseCentre"
const PIVOT_HINGE_LEFT: String = "hingeLeft"
const PIVOT_HINGE_RIGHT: String = "hingeRight"
const PIVOT_HINGE_BACK: String = "hingeBack"


static func pivot_for(prop_id: String) -> String:
	var pivot: String = String(entry(prop_id).get("pivot", PIVOT_BASE_CENTRE))
	if pivot in [PIVOT_HINGE_LEFT, PIVOT_HINGE_RIGHT, PIVOT_HINGE_BACK]:
		return pivot
	return PIVOT_BASE_CENTRE


## The translation that puts `placed` (the scaled, turned bounds) on its pivot.
static func pivot_offset(placed: AABB, pivot: String) -> Vector3:
	var centre: Vector3 = placed.position + placed.size * 0.5
	match pivot:
		PIVOT_HINGE_LEFT:
			return -Vector3(placed.position.x, centre.y, centre.z)
		PIVOT_HINGE_RIGHT:
			return -Vector3(placed.end.x, centre.y, centre.z)
		PIVOT_HINGE_BACK:
			return -Vector3(centre.x, placed.position.y, placed.position.z)
		_:
			return -Vector3(centre.x, placed.position.y, centre.z)


## The prop sized for use: longest axis = `longest_axis_m` metres (the
## manifest's `longestAxisMetres`, else the authored size, when <= 0), turned
## by the manifest's `yawDegrees`, on its pivot (see `pivot_for`). `null` if
## the prop cannot be built. Cached per size.
static func sized_mesh(prop_id: String, longest_axis_m: float = 0.0) -> ArrayMesh:
	var source: ArrayMesh = source_mesh(prop_id)
	if source == null:
		return null
	var bounds: AABB = source.get_aabb()
	var longest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if longest <= 0.0:
		return null
	var target: float = longest_axis_m
	if target <= 0.0:
		target = float(entry(prop_id).get("longestAxisMetres", 0.0))
	if target <= 0.0:
		target = longest
	var key: String = "%s@%.4f" % [prop_id, target]
	if _sized_cache.has(key):
		return _sized_cache[key]

	var yaw: float = deg_to_rad(float(entry(prop_id).get("yawDegrees", 0.0)))
	var factor: float = target / longest
	var oriented := Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)).scaled(Vector3.ONE * factor),
			Vector3.ZERO)
	var placed: AABB = oriented * bounds
	oriented.origin = pivot_offset(placed, pivot_for(prop_id))
	var sized: ArrayMesh = _transformed(source, oriented)
	_sized_cache[key] = sized
	return sized


## A ready node: `Prop_<id>`, sized mesh, materials on the mesh itself. `null`
## when the prop cannot be built, so a caller writes
## `var node := PropRegistry.instance(id); if node == null: <draw it>`.
static func instance(prop_id: String, longest_axis_m: float = 0.0) -> MeshInstance3D:
	var mesh: ArrayMesh = sized_mesh(prop_id, longest_axis_m)
	if mesh == null:
		return null
	var node := MeshInstance3D.new()
	node.name = "Prop_%s" % prop_id
	node.mesh = mesh
	return node


## Total triangles across every surface. Diagnostic, for the gate.
static func triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices != null and typeof(indices) == TYPE_PACKED_INT32_ARRAY \
				and (indices as PackedInt32Array).size() > 0:
			total += (indices as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


## The longest side of a 2D texture on any surface material, 0 when untextured.
static func texture_long_side(mesh: Mesh) -> int:
	var longest: int = 0
	if mesh == null:
		return 0
	for surface: int in range(mesh.get_surface_count()):
		var material: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
		if material == null or material.albedo_texture == null:
			continue
		longest = maxi(longest, maxi(material.albedo_texture.get_width(),
				material.albedo_texture.get_height()))
	return longest


## -- Baking -------------------------------------------------------------------

## Flattens an imported scene into one `ArrayMesh`: node transforms applied,
## one surface per source surface, each keeping its (policy-corrected)
## material. Unlike `ObjectSpawner.bake_scene_mesh()` this does NOT regroup by
## material name: a Meshy prop is one surface already, and a split furniture
## file's parts are separate files, so there is nothing to merge.
static func bake(root: Node, parent_transform: Transform3D) -> ArrayMesh:
	var baked := ArrayMesh.new()
	_collect(root, parent_transform, baked, true)
	if baked.get_surface_count() == 0:
		return null
	return baked


static func _collect(node: Node, parent_transform: Transform3D, into: ArrayMesh, is_root: bool) -> void:
	var here: Transform3D = parent_transform
	if node is Node3D and not is_root:
		here = parent_transform * (node as Node3D).transform
	var instance_node: MeshInstance3D = node as MeshInstance3D
	if instance_node != null and instance_node.mesh != null:
		var mesh: Mesh = instance_node.mesh
		for surface: int in range(mesh.get_surface_count()):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.append_from(mesh, surface, here)
			tool.commit(into)
			var material: Material = instance_node.get_active_material(surface)
			into.surface_set_material(into.get_surface_count() - 1, _policy(material))
	for child: Node in node.get_children():
		_collect(child, here, into, false)


## Re-emits every surface of `source` through `transform`, materials kept.
static func _transformed(source: ArrayMesh, transform: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surface: int in range(source.get_surface_count()):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.append_from(source, surface, transform)
		tool.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, source.surface_get_material(surface))
	return out


## ART_BIBLE section 7 applied to an imported material: no metal, no shine, no
## emission, no double-sided overdraw. The texture is left exactly as imported.
static func _policy(material: Material) -> Material:
	var standard: StandardMaterial3D = material as StandardMaterial3D
	if standard == null:
		return material
	var fixed: StandardMaterial3D = standard.duplicate() as StandardMaterial3D
	fixed.metallic = 0.0
	fixed.roughness = maxf(fixed.roughness, MIN_ROUGHNESS)
	fixed.emission_enabled = false
	fixed.cull_mode = BaseMaterial3D.CULL_BACK
	fixed.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return fixed
