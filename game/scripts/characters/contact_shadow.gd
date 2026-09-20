extends RefCounted

## ============================================================================
## CONTACT HINT -- the one soft mark that keeps a character on the floor.
## ============================================================================
##
## There are no real-time shadows in this game (`main.tscn` and
## `house_world.tscn` both run their one `DirectionalLight3D` with
## `shadow_enabled = false`, per the mobile budget), and until 2026-09-20 there
## was no fake one either: the characters stood on the floor with nothing under
## them, which at the bedroom framing reads as standing a centimetre above it.
##
## This is the smallest thing that fixes that. One quad, flat on the floor
## under the character's origin, with a radial falloff in a dark peach at
## `PEAK_ALPHA` in the middle and nothing at the rim. It is a HINT of contact,
## not a blob: the alpha ceiling is 0.18 by rule, the radius is about the
## width of a stance, and the falloff starts just past half the radius so there
## is no visible edge anywhere. Unshaded, never writes depth, no shadow of its
## own, one draw call, two triangles.
##
## `build()` returns the node; the wrapper parents it inside its own sealed
## hierarchy (`Model` for Aliz, the pose holder for Bunny) so the "direct
## children" contracts in `test_buddy_avatar.gd` and `test_baby_avatar.gd` hold.
##
##   `build(radius_m, peak_alpha) -> MeshInstance3D`
##   `feet_centre(mesh) -> Vector3`  where the feet are, in the mesh's own space
##   `NAME`  the node name, so a shot harness or a test can find and hide it
##
## The hint goes under the FEET, not under the origin. Both characters are
## centred on their bounding box, and a chibi body's belly and head reach
## further forward than its toes, so the origin sits several centimetres
## behind the heels -- a hint centred there peeks out behind the shoes and
## grounds nothing (seen in the first render, alpha forced to 1 to find it).

const NAME: String = "ContactHint"

## The rule from the brief: alpha <= 0.18, radius ~= 0.22 m for an adult.
const MAX_ALPHA: float = 0.18
const DEFAULT_RADIUS_M: float = 0.22
const DEFAULT_ALPHA: float = 0.18
## Dark peach: the floor's own family, a few steps down.
const TINT := Color(0.42, 0.26, 0.22, 1.0)
## Metres above the character's origin. Not a z-fight margin: the house rugs
## are plates 18-20 mm proud of the floor (`room.gd::_build_rug()`), and a hint
## drawn under a rug is a hint nobody sees -- the first version sat at 4 mm and
## vanished on every rug in the house. 25 mm clears them; from the room camera,
## which looks down at 30-40 degrees, that float is invisible.
const LIFT_M: float = 0.025

const SHADER: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
	ambient_light_disabled, specular_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.42, 0.26, 0.22, 1.0);
uniform float peak_alpha = 0.18;
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	ALBEDO = tint.rgb;
	ALPHA = peak_alpha * (1.0 - smoothstep(0.55, 1.0, r));
}
"""


static func build(radius_m: float = DEFAULT_RADIUS_M, peak_alpha: float = DEFAULT_ALPHA) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(radius_m * 2.0, radius_m * 2.0)
	# A QuadMesh faces +Z; this lays it flat, facing up.
	quad.orientation = PlaneMesh.FACE_Y
	var shader := Shader.new()
	shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", TINT)
	material.set_shader_parameter("peak_alpha", minf(peak_alpha, MAX_ALPHA))
	material.render_priority = -1
	var mesh := MeshInstance3D.new()
	mesh.name = NAME
	mesh.mesh = quad
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(0.0, LIFT_M, 0.0)
	return mesh


## The centroid of the lowest `fraction` of the mesh's height, in the mesh's
## own coordinates: for a standing character, the middle of the feet. Reads the
## vertex array once at build time.
static func feet_centre(mesh: Mesh, fraction: float = 0.06) -> Vector3:
	if mesh == null:
		return Vector3.ZERO
	var aabb: AABB = mesh.get_aabb()
	var cutoff: float = aabb.position.y + aabb.size.y * fraction
	var total := Vector3.ZERO
	var count: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var points: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for point: Vector3 in points:
			if point.y <= cutoff:
				total += point
				count += 1
	if count == 0:
		return aabb.position + aabb.size * 0.5
	var centre: Vector3 = total / float(count)
	centre.y = aabb.position.y
	return centre
