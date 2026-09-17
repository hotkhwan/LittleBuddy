extends RefCounted

## The house's geometry kit: every shape the four rooms are built from, and the
## one material they all share.
##
## ## Why this exists
##
## `docs/ART_BIBLE.md` §5 names a hard 90-degree corner as "the single strongest
## 'this is a prototype' signal", and open issue §13.7 is exactly that: the room
## geometry was harder-edged than the props. Godot's `BoxMesh` cannot bevel, so
## the rooms could not stop looking like a greybox until something in this
## repository could generate a chamfered box. That is the whole reason this file
## exists, and `BEVEL` is the number the bible asks for: ~2 cm, in world units,
## *independent of the size of the object*, which is why it is an absolute
## distance and not a percentage.
##
## ## One material, vertex colours
##
## §10 says draw calls, not triangles, are the metric to watch. Every builder
## here writes into a `SurfaceTool` and carries its colour as a VERTEX colour, so
## an entire room shell -- floor planks, walls, skirting, wainscot, window, rug --
## merges into one `ArrayMesh` with one material and costs **one draw call**. A
## room is therefore ~7 draw calls rather than ~40, and adding detail is free
## until it adds a mesh.
##
## `material()` returns a single shared `StandardMaterial3D`: roughness 0.92,
## metallic 0, no normal map, no alpha, no emission (§7). Nothing in this game is
## shiny.
##
## ## Winding is generated, not authored
##
## `_triangle()` re-orders every triangle it is given so that its winding agrees
## with the normal it was handed. That is not tidiness: with a double-sided
## material Godot FLIPS the shading normal on a back face, so a backwards-wound
## quad is not invisible, it is lit from behind -- a solid surface that simply
## never catches the sun, which is what the first pass of these rooms looked
## like. With winding guaranteed, back-face culling is on, which is both cheaper
## and louder: a future mistake here is a visible hole, not a dull room.
##
## ## Conventions
##
##   * Everything is authored in METRES, centred on its own origin, and placed by
##     a `Transform3D`.
##   * `extrude()` takes a 2D outline in the local XY plane and extrudes along
##     local Z. `cylinder()`, `plate()` and friends are that one function with an
##     outline and a rotation.
##   * Outlines are re-wound counter-clockwise on entry, so a caller never has to
##     think about it.

const Palette := preload("res://scripts/ui/palette.gd")

## ART_BIBLE §5: "Every architectural edge has a visible bevel, ~2 cm in-world."
const BEVEL: float = 0.02
## Props are softer than architecture (§6: "generous fillets").
const PROP_BEVEL: float = 0.025

## Below this a bevel is not worth the degenerate triangles it would generate.
const MIN_BEVEL: float = 0.0015

## §5: the window sky is a flat plane of this colour -- no glass, no
## transparency, no reflection. It is the cheapest warmth in the scene.
const WINDOW_SKY: Color = Color(0.722, 0.859, 0.929)  # #B8DBED

static var _material: StandardMaterial3D = null


## The one material every mesh in the house shares. §7, and one per object is
## the budget, so one per HOUSE is comfortably inside it.
static func material() -> StandardMaterial3D:
	if _material != null:
		return _material
	var made := StandardMaterial3D.new()
	made.vertex_color_use_as_albedo = true
	made.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	# 0.85-1.0 (§7). Nothing in this game is shiny.
	made.roughness = 0.92
	made.metallic = 0.0
	made.metallic_specular = 0.2
	# Safe because `_triangle()` guarantees the winding. See the class docs.
	made.cull_mode = BaseMaterial3D.CULL_BACK
	_material = made
	return made


static func begin() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool


## Hands back a finished mesh, or null if nothing was added -- an empty
## `ArrayMesh` on a `MeshInstance3D` is a Godot error at draw time, not at build
## time. Deliberately NOT indexed: welding would average the normals of the flat
## face and the chamfer that meet on every edge, which is precisely the crisp
## break the bevel exists to create.
static func commit(tool: SurfaceTool) -> ArrayMesh:
	var mesh: ArrayMesh = tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	return mesh


## Total triangles of a finished mesh. Diagnostic, so the §10 budget can be
## asserted rather than assumed.
static func triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		# `commit()` does not index, so `ARRAY_INDEX` is null rather than empty.
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices != null and (indices as PackedInt32Array).size() > 0:
			total += (indices as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


## -- Transforms ------------------------------------------------------------

static func at(position: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, position)


static func at_rotated(position: Vector3, euler_degrees: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(
		deg_to_rad(euler_degrees.x), deg_to_rad(euler_degrees.y), deg_to_rad(euler_degrees.z)
	)), position)


## -- Rounded box -------------------------------------------------------------

## A box with every one of its twelve edges chamfered (`steps` = 1) or rounded
## (`steps` > 1) by `bevel` metres. This is the workhorse: floors, walls,
## skirting, cabinet bodies, mattresses, cushions.
##
## The bevel is clamped so it can never exceed half the shortest side, which is
## what lets a caller pass the same 2 cm to a 4 m floor and to a 9 cm skirting
## board without thinking about it.
static func box(
	tool: SurfaceTool,
	transform: Transform3D,
	size: Vector3,
	color: Color,
	bevel: float = BEVEL,
	steps: int = 1
) -> void:
	var smallest: float = minf(size.x, minf(size.y, size.z))
	var radius: float = clampf(bevel, 0.0, smallest * 0.5 - 0.0005)
	if radius < MIN_BEVEL:
		_plain_box(tool, transform, size, color)
		return
	var half := Vector3(
		size.x * 0.5 - radius, size.y * 0.5 - radius, size.z * 0.5 - radius
	)
	var count: int = maxi(steps, 1)

	# Six flat faces, inset by the bevel on all four sides.
	for axis: int in range(3):
		for sign_value: float in [-1.0, 1.0]:
			var b: int = (axis + 1) % 3
			var c: int = (axis + 2) % 3
			var normal: Vector3 = _axis(axis) * sign_value
			var centre: Vector3 = normal * (half[axis] + radius)
			var corners: Array = []
			for pair: Array in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				var point: Vector3 = centre
				point += _axis(b) * (half[b] * float(pair[0]))
				point += _axis(c) * (half[c] * float(pair[1]))
				corners.append(point)
			_quad(tool, transform, color, corners[0], corners[1], corners[2], corners[3],
					normal, normal, normal, normal)

	# Twelve edge fillets, each a quarter cylinder running along one axis.
	for axis: int in range(3):
		var b: int = (axis + 1) % 3
		var c: int = (axis + 2) % 3
		for sign_b: float in [-1.0, 1.0]:
			for sign_c: float in [-1.0, 1.0]:
				var spine: Vector3 = _axis(b) * (half[b] * sign_b) + _axis(c) * (half[c] * sign_c)
				var along: Vector3 = _axis(axis) * half[axis]
				for step: int in range(count):
					var n0: Vector3 = _arc_normal(b, c, sign_b, sign_c, float(step) / float(count))
					var n1: Vector3 = _arc_normal(
							b, c, sign_b, sign_c, float(step + 1) / float(count))
					_quad(tool, transform, color,
							spine - along + n0 * radius, spine - along + n1 * radius,
							spine + along + n1 * radius, spine + along + n0 * radius,
							n0, n1, n1, n0)

	# Eight corner octants.
	for sign_x: float in [-1.0, 1.0]:
		for sign_y: float in [-1.0, 1.0]:
			for sign_z: float in [-1.0, 1.0]:
				var centre := Vector3(half.x * sign_x, half.y * sign_y, half.z * sign_z)
				for u: int in range(count):
					for v: int in range(count):
						var a0: Vector3 = _octant_normal(sign_x, sign_y, sign_z,
								float(u) / float(count), float(v) / float(count))
						var a1: Vector3 = _octant_normal(sign_x, sign_y, sign_z,
								float(u + 1) / float(count), float(v) / float(count))
						var a2: Vector3 = _octant_normal(sign_x, sign_y, sign_z,
								float(u + 1) / float(count), float(v + 1) / float(count))
						var a3: Vector3 = _octant_normal(sign_x, sign_y, sign_z,
								float(u) / float(count), float(v + 1) / float(count))
						_quad(tool, transform, color,
								centre + a0 * radius, centre + a1 * radius,
								centre + a2 * radius, centre + a3 * radius,
								a0, a1, a2, a3)


static func _plain_box(
	tool: SurfaceTool, transform: Transform3D, size: Vector3, color: Color
) -> void:
	var half: Vector3 = size * 0.5
	for axis: int in range(3):
		for sign_value: float in [-1.0, 1.0]:
			var b: int = (axis + 1) % 3
			var c: int = (axis + 2) % 3
			var normal: Vector3 = _axis(axis) * sign_value
			var centre: Vector3 = normal * half[axis]
			var corners: Array = []
			for pair: Array in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				corners.append(centre
						+ _axis(b) * (half[b] * float(pair[0]))
						+ _axis(c) * (half[c] * float(pair[1])))
			_quad(tool, transform, color, corners[0], corners[1], corners[2], corners[3],
					normal, normal, normal, normal)


static func _axis(index: int) -> Vector3:
	match index:
		0:
			return Vector3.RIGHT
		1:
			return Vector3.UP
		_:
			return Vector3.BACK


static func _arc_normal(b: int, c: int, sign_b: float, sign_c: float, t: float) -> Vector3:
	var angle: float = t * PI * 0.5
	return _axis(b) * (sign_b * cos(angle)) + _axis(c) * (sign_c * sin(angle))


static func _octant_normal(
	sign_x: float, sign_y: float, sign_z: float, u: float, v: float
) -> Vector3:
	var azimuth: float = u * PI * 0.5
	var elevation: float = v * PI * 0.5
	return Vector3(
		sign_x * cos(elevation) * cos(azimuth),
		sign_y * sin(elevation),
		sign_z * cos(elevation) * sin(azimuth)
	)


## -- Extruded outlines -------------------------------------------------------

## A 2D outline in the local XY plane, extruded `thickness` metres along local Z
## and centred on it, with a chamfered rim on both faces.
##
## This is what makes a rug have rounded corners, a door have a rounded top and a
## cylinder be a cylinder: the corner radius lives in the OUTLINE, where it is
## not limited by the object's thickness, which is the one thing `box()` above
## cannot do.
static func extrude(
	tool: SurfaceTool,
	transform: Transform3D,
	outline: PackedVector2Array,
	thickness: float,
	color: Color,
	bevel: float = BEVEL
) -> void:
	var points: PackedVector2Array = _counter_clockwise(outline)
	if points.size() < 3:
		return
	var rim: float = clampf(bevel, 0.0, thickness * 0.5 - 0.0005)
	var inner: PackedVector2Array = points
	if rim >= MIN_BEVEL:
		inner = _inset(points, rim)
	else:
		rim = 0.0

	var half: float = thickness * 0.5
	var normals: PackedVector2Array = _edge_normals(points)

	# Caps.
	_cap(tool, transform, inner, color, half, Vector3.BACK)
	_cap(tool, transform, inner, color, -half, Vector3.FORWARD)

	var count: int = points.size()
	for index: int in range(count):
		var next: int = (index + 1) % count
		var na := Vector3(normals[index].x, normals[index].y, 0.0)
		var nb := Vector3(normals[next].x, normals[next].y, 0.0)
		var a_out := Vector3(points[index].x, points[index].y, 0.0)
		var b_out := Vector3(points[next].x, points[next].y, 0.0)
		var a_in := Vector3(inner[index].x, inner[index].y, 0.0)
		var b_in := Vector3(inner[next].x, inner[next].y, 0.0)
		var span: float = half - rim
		# The straight rim.
		_quad(tool, transform, color,
				a_out + Vector3(0, 0, -span), b_out + Vector3(0, 0, -span),
				b_out + Vector3(0, 0, span), a_out + Vector3(0, 0, span),
				na, nb, nb, na)
		if rim <= 0.0:
			continue
		# The two chamfers back to the caps.
		var front_a: Vector3 = (na + Vector3.BACK).normalized()
		var front_b: Vector3 = (nb + Vector3.BACK).normalized()
		_quad(tool, transform, color,
				a_out + Vector3(0, 0, span), b_out + Vector3(0, 0, span),
				b_in + Vector3(0, 0, half), a_in + Vector3(0, 0, half),
				front_a, front_b, front_b, front_a)
		var back_a: Vector3 = (na + Vector3.FORWARD).normalized()
		var back_b: Vector3 = (nb + Vector3.FORWARD).normalized()
		_quad(tool, transform, color,
				a_in + Vector3(0, 0, -half), b_in + Vector3(0, 0, -half),
				b_out + Vector3(0, 0, -span), a_out + Vector3(0, 0, -span),
				back_a, back_b, back_b, back_a)


static func _cap(
	tool: SurfaceTool,
	transform: Transform3D,
	outline: PackedVector2Array,
	color: Color,
	z: float,
	normal: Vector3
) -> void:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for i: int in range(0, indices.size(), 3):
		var a: Vector2 = outline[indices[i]]
		var b: Vector2 = outline[indices[i + 1]]
		var c: Vector2 = outline[indices[i + 2]]
		_triangle(tool, transform, color,
				Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z),
				normal, normal, normal)


## Per-VERTEX outward normals, averaged from the two edges that meet there, so a
## cylinder's side shades smoothly and a rounded corner does not facet.
static func _edge_normals(points: PackedVector2Array) -> PackedVector2Array:
	var count: int = points.size()
	var result := PackedVector2Array()
	for index: int in range(count):
		var previous: Vector2 = points[(index - 1 + count) % count]
		var current: Vector2 = points[index]
		var next: Vector2 = points[(index + 1) % count]
		var into: Vector2 = (current - previous).normalized()
		var out: Vector2 = (next - current).normalized()
		# Counter-clockwise winding puts the interior on the left, so the outward
		# normal of an edge running (x, y) is (y, -x).
		var normal: Vector2 = (Vector2(into.y, -into.x) + Vector2(out.y, -out.x))
		if normal.length_squared() < 0.000001:
			normal = Vector2(out.y, -out.x)
		result.append(normal.normalized())
	return result


## Miter inset by `distance`, vertex for vertex, so the inset ring and the
## original ring stay in correspondence and the rim quads cannot skew. Correct
## for the convex outlines this kit generates.
static func _inset(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var normals: PackedVector2Array = _edge_normals(points)
	var count: int = points.size()
	var result := PackedVector2Array()
	for index: int in range(count):
		var previous: Vector2 = points[(index - 1 + count) % count]
		var current: Vector2 = points[index]
		var into: Vector2 = (current - previous).normalized()
		var edge_normal := Vector2(into.y, -into.x)
		# Miter length grows as the corner sharpens; clamped so a near-spike
		# cannot throw the inset vertex across the shape.
		var scale: float = distance / maxf(normals[index].dot(edge_normal), 0.34)
		result.append(current - normals[index] * scale)
	return result


static func _counter_clockwise(points: PackedVector2Array) -> PackedVector2Array:
	var area: float = 0.0
	var count: int = points.size()
	for index: int in range(count):
		var current: Vector2 = points[index]
		var next: Vector2 = points[(index + 1) % count]
		area += current.x * next.y - next.x * current.y
	if area >= 0.0:
		return points
	var reversed := PackedVector2Array()
	for index: int in range(count - 1, -1, -1):
		reversed.append(points[index])
	return reversed


## -- Outlines ----------------------------------------------------------------

## A rectangle with rounded corners, centred on the origin.
static func rounded_rect(size: Vector2, radius: float, steps: int = 3) -> PackedVector2Array:
	var half: Vector2 = size * 0.5
	var corner: float = clampf(radius, 0.0, minf(half.x, half.y) - 0.0005)
	var points := PackedVector2Array()
	if corner < MIN_BEVEL:
		points.append(Vector2(half.x, -half.y))
		points.append(Vector2(half.x, half.y))
		points.append(Vector2(-half.x, half.y))
		points.append(Vector2(-half.x, -half.y))
		return points
	var count: int = maxi(steps, 1)
	var centres: Array[Vector2] = [
		Vector2(half.x - corner, -half.y + corner),
		Vector2(half.x - corner, half.y - corner),
		Vector2(-half.x + corner, half.y - corner),
		Vector2(-half.x + corner, -half.y + corner),
	]
	for quadrant: int in range(4):
		var start: float = -PI * 0.5 + float(quadrant) * PI * 0.5
		for step: int in range(count + 1):
			var angle: float = start + PI * 0.5 * float(step) / float(count)
			points.append(centres[quadrant] + Vector2(cos(angle), sin(angle)) * corner)
	return points


## A circle, for cylinders, discs, pegs and knobs.
static func circle(radius: float, sides: int = 16) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in range(sides):
		var angle: float = TAU * float(index) / float(sides)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


## A door: square-ish at the bottom, a generous arch at the top. §5 asks for
## rounded-top doors, and the arch is most of what stops a doorway reading as a
## hole in a wall.
static func arch(size: Vector2, foot_radius: float = 0.04, steps: int = 7) -> PackedVector2Array:
	var half: Vector2 = size * 0.5
	var arch_radius: float = half.x
	var shoulder: float = half.y - arch_radius
	var points := PackedVector2Array()
	points.append(Vector2(half.x - foot_radius, -half.y))
	points.append(Vector2(half.x, -half.y + foot_radius))
	points.append(Vector2(half.x, shoulder))
	for step: int in range(steps + 1):
		var angle: float = PI * float(step) / float(steps)
		points.append(Vector2(cos(angle), sin(angle)) * arch_radius + Vector2(0.0, shoulder))
	points.append(Vector2(-half.x, -half.y + foot_radius))
	points.append(Vector2(-half.x + foot_radius, -half.y))
	return points


## -- Solids of revolution ----------------------------------------------------

## A cylinder standing on local Y, centred on the origin. Legs, pegs, rails,
## plant pots, taps.
static func cylinder(
	tool: SurfaceTool,
	transform: Transform3D,
	radius: float,
	height: float,
	color: Color,
	sides: int = 14,
	bevel: float = 0.012
) -> void:
	extrude(tool, transform * _upright(), circle(radius, sides), height, color, bevel)


## A flat plate lying in the local XZ plane: rugs, table tops, book covers.
static func plate(
	tool: SurfaceTool,
	transform: Transform3D,
	outline: PackedVector2Array,
	thickness: float,
	color: Color,
	bevel: float = BEVEL
) -> void:
	extrude(tool, transform * _upright(), outline, thickness, color, bevel)


## Turns "extruded along local Z" into "extruded along local Y".
static func _upright() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)), Vector3.ZERO)


## A UV sphere: door handles, cabinet knobs, plant foliage, soft toy shapes.
static func sphere(
	tool: SurfaceTool,
	transform: Transform3D,
	radius: float,
	color: Color,
	segments: int = 12,
	rings: int = 6
) -> void:
	for ring: int in range(rings):
		var phi0: float = PI * (float(ring) / float(rings) - 0.5)
		var phi1: float = PI * (float(ring + 1) / float(rings) - 0.5)
		for segment: int in range(segments):
			var theta0: float = TAU * float(segment) / float(segments)
			var theta1: float = TAU * float(segment + 1) / float(segments)
			var a: Vector3 = _on_sphere(phi0, theta0)
			var b: Vector3 = _on_sphere(phi0, theta1)
			var c: Vector3 = _on_sphere(phi1, theta1)
			var d: Vector3 = _on_sphere(phi1, theta0)
			_quad(tool, transform, color,
					a * radius, b * radius, c * radius, d * radius, a, b, c, d)


static func _on_sphere(phi: float, theta: float) -> Vector3:
	return Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta))


## A torus lying in the local XZ plane: the rings of the stacking toy.
static func torus(
	tool: SurfaceTool,
	transform: Transform3D,
	major: float,
	minor: float,
	color: Color,
	major_segments: int = 14,
	minor_segments: int = 7
) -> void:
	for i: int in range(major_segments):
		var u0: float = TAU * float(i) / float(major_segments)
		var u1: float = TAU * float(i + 1) / float(major_segments)
		for j: int in range(minor_segments):
			var v0: float = TAU * float(j) / float(minor_segments)
			var v1: float = TAU * float(j + 1) / float(minor_segments)
			var n0: Vector3 = _torus_normal(u0, v0)
			var n1: Vector3 = _torus_normal(u1, v0)
			var n2: Vector3 = _torus_normal(u1, v1)
			var n3: Vector3 = _torus_normal(u0, v1)
			_quad(tool, transform, color,
					_torus_point(u0, v0, major, minor), _torus_point(u1, v0, major, minor),
					_torus_point(u1, v1, major, minor), _torus_point(u0, v1, major, minor),
					n0, n1, n2, n3)


static func _torus_normal(u: float, v: float) -> Vector3:
	return Vector3(cos(u) * cos(v), sin(v), sin(u) * cos(v))


static func _torus_point(u: float, v: float, major: float, minor: float) -> Vector3:
	var ring := Vector3(cos(u), 0.0, sin(u))
	return ring * major + _torus_normal(u, v) * minor


## -- Primitive writers -------------------------------------------------------

static func _quad(
	tool: SurfaceTool,
	transform: Transform3D,
	color: Color,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3
) -> void:
	_triangle(tool, transform, color, a, b, c, na, nb, nc)
	_triangle(tool, transform, color, a, c, d, na, nc, nd)


static func _triangle(
	tool: SurfaceTool,
	transform: Transform3D,
	color: Color,
	a: Vector3, b: Vector3, c: Vector3,
	na: Vector3, nb: Vector3, nc: Vector3
) -> void:
	# Winding, made automatic rather than reasoned about per primitive.
	#
	# Godot's front faces are CLOCKWISE seen from outside, so a correctly wound
	# triangle's geometric normal points AGAINST its shading normal. A double-sided
	# material FLIPS the shading normal on a back face, so a backwards-wound
	# triangle is not invisible -- it is lit from behind, which is far worse,
	# because it renders as a perfectly solid surface that simply never catches the
	# sun. Every flat face of every box in this house was wound backwards on the
	# first pass: the rooms came back uniformly ambient-lit and dusty, with the
	# bevels and the spheres (wound the other way) the only things that lit at all.
	# Nothing in a test could see it. Now it cannot happen.
	var geometric: Vector3 = (b - a).cross(c - a)
	var shading: Vector3 = na + nb + nc
	if geometric.dot(shading) > 0.0:
		var swap_point: Vector3 = b
		b = c
		c = swap_point
		var swap_normal: Vector3 = nb
		nb = nc
		nc = swap_normal

	var basis: Basis = transform.basis
	# sRGB -> linear, and this is not optional. `albedo_color` on a
	# `StandardMaterial3D` is converted by the engine; a VERTEX colour is not, so
	# it is read as though it were already linear. The first render of these rooms
	# had every §3 token land 15-20% pale and visibly desaturated -- a lavender
	# wardrobe came out beige -- and nothing in the palette test can see it,
	# because the palette in the source was correct the whole time.
	var linear: Color = color.srgb_to_linear()
	for pair: Array in [[a, na], [b, nb], [c, nc]]:
		tool.set_color(linear)
		tool.set_normal((basis * (pair[1] as Vector3)).normalized())
		tool.add_vertex(transform * (pair[0] as Vector3))
