extends Node3D
class_name NurseryProps

## Re-tints the bundled Kenney Furniture Kit models into the nursery palette.
##
## Why this exists: the Furniture Kit is CC0 and free, but it is 2018-era art --
## sharp edges, adult proportions and a saturated orange/wood palette that does
## not read as "soft pastel nursery" out of the box.
##
## The one thing that makes it usable anyway is that the kit ships **completely
## untextured**: every `.glb` has `images: 0` and each surface is a plain
## `baseColorFactor` material with a stable, human-readable name (`wood`,
## `carpet`, `metal`, `plant`, ...). So the whole kit can be pulled onto the
## nursery palette by overriding albedo per material NAME -- no texture work, no
## re-authoring, and it stays consistent if more kit models are added later.
##
## Set dressing only. This node adds no camera, no UI, no `Area3D` and no second
## light, and it never touches the play volume around the origin.

## Default palette, keyed by the Kenney material name baked into every kit
## model. Anything not listed is left exactly as the artist shipped it.
const PALETTE: Dictionary = {
	"wood": Color(0.87, 0.74, 0.58),          # pale warm nursery wood
	"woodDark": Color(0.73, 0.59, 0.44),      # shadowed wood / box interior
	"carpet": Color(0.90, 0.69, 0.71),        # soft pink
	"carpetDarker": Color(0.80, 0.56, 0.60),  # dusty rose (rug border)
	"carpetWhite": Color(0.98, 0.96, 0.93),   # warm off-white bedding
	"metal": Color(0.74, 0.83, 0.90),         # dusty blue instead of steel
	"metalDark": Color(0.58, 0.70, 0.82),
	"lamp": Color(1.0, 0.95, 0.80),           # warm cream lampshade
	"plant": Color(0.60, 0.79, 0.62),         # soft sage, not neon green
	"fur": Color(0.91, 0.78, 0.60),
}

## Everything in the nursery is flat-shaded matte; a specular highlight on these
## hard-edged low-poly meshes reads as plastic.
const ROUGHNESS: float = 1.0

## Per-instance tint overrides are read from this node metadata key, so a single
## model (e.g. `cardboardBoxOpen`) can appear as a blue toy box here and as
## something else elsewhere without duplicating the `.glb`.
const TINT_META_KEY: StringName = &"tint"

## Set `metadata/no_shadow = true` on an instance whose geometry is too flat or
## too thin to cast a clean shadow map at this resolution -- the rug lies almost
## parallel to the light and self-shadows into a scalloped band otherwise.
const NO_SHADOW_META_KEY: StringName = &"no_shadow"

## Shared material cache: identical (name, colour) pairs reuse one material so
## the retint does not multiply material switches on the mobile renderer.
var _materials: Dictionary = {}


func _ready() -> void:
	_retint(self, {}, false)


func _retint(node: Node, inherited: Dictionary, no_shadow: bool = false) -> void:
	var overrides: Dictionary = inherited
	var casts_no_shadow: bool = no_shadow or bool(node.get_meta(NO_SHADOW_META_KEY, false))
	if node.has_meta(TINT_META_KEY):
		var local: Variant = node.get_meta(TINT_META_KEY)
		if typeof(local) == TYPE_DICTIONARY:
			overrides = inherited.duplicate()
			overrides.merge(local as Dictionary, true)

	if node is MeshInstance3D:
		_retint_mesh(node as MeshInstance3D, overrides)
		if casts_no_shadow:
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for child: Node in node.get_children():
		_retint(child, overrides, casts_no_shadow)


func _retint_mesh(instance: MeshInstance3D, overrides: Dictionary) -> void:
	var mesh: Mesh = instance.mesh
	if mesh == null:
		return
	for surface: int in range(mesh.get_surface_count()):
		# A surface already carrying a hand-authored override in the scene is
		# left alone -- the procedural room shell owns its own materials.
		if instance.get_surface_override_material(surface) != null:
			continue
		var source: Material = mesh.surface_get_material(surface)
		if source == null:
			continue
		var material_name: String = source.resource_name
		var color: Variant = overrides.get(material_name, PALETTE.get(material_name))
		if color == null:
			continue
		instance.set_surface_override_material(surface, _material_for(material_name, color as Color))


func _material_for(material_name: String, color: Color) -> StandardMaterial3D:
	var key: String = "%s:%s" % [material_name, str(color)]
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = ROUGHNESS
	material.resource_name = material_name
	_materials[key] = material
	return material
