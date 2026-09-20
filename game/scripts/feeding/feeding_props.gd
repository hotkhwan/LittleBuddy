extends RefCounted

## Primitive-mesh props for the highchair stage: the four foods, the plates, the
## tray, the chair and the backdrop. Built in code so tonight's stage needs no
## art files at all; every function returns plain `Node3D` trees that a GLB can
## replace later without touching `feeding_table.gd`.
##
## Art bible discipline: `StandardMaterial3D` only, roughness 0.9, metallic 0,
## no transparency, no emission. Colours are palette tokens or their two
## documented derivations, except the FOOD colours, which come from
## `content/objects.json` (the apple is the same red the sticker book draws it
## in). A glass cup is drawn as its liquid plus a rim: the level really drops.

const _Palette := preload("res://scripts/ui/palette.gd")
const _Item := preload("res://scripts/feeding/feeding_item.gd")

## §7: nothing in this game is shiny.
const ROUGHNESS: float = 0.9

## Where the peel strips hinge, as a fraction of the banana's height.
const BANANA_HEIGHT: float = 0.125
const BANANA_HINGE_Y: float = 0.062

const APPLE_RADIUS: float = 0.052
const CUP_LIQUID_HEIGHT: float = 0.10
const BOTTLE_LIQUID_HEIGHT: float = 0.115

const GLOW_RADIUS: float = 0.095


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = ROUGHNESS
	mat.metallic = 0.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


static func mesh_node(mesh: Mesh, color: Color, local_position: Vector3 = Vector3.ZERO,
		node_name: String = "Part", unshaded: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material(color, unshaded)
	node.position = local_position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func sphere(radius: float, color: Color, local_position: Vector3 = Vector3.ZERO,
		local_scale: Vector3 = Vector3.ONE, node_name: String = "Sphere") -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var node: MeshInstance3D = mesh_node(mesh, color, local_position, node_name)
	node.scale = local_scale
	return node


static func cylinder(top: float, bottom: float, height: float, color: Color,
		local_position: Vector3 = Vector3.ZERO, node_name: String = "Cylinder") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 28
	mesh.rings = 1
	return mesh_node(mesh, color, local_position, node_name)


static func box(size: Vector3, color: Color, local_position: Vector3 = Vector3.ZERO,
		node_name: String = "Box") -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh_node(mesh, color, local_position, node_name)


static func capsule(radius: float, height: float, color: Color,
		local_position: Vector3 = Vector3.ZERO, node_name: String = "Capsule") -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 6
	return mesh_node(mesh, color, local_position, node_name)


static func torus(inner: float, outer: float, color: Color,
		local_position: Vector3 = Vector3.ZERO, node_name: String = "Torus") -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 32
	mesh.ring_segments = 12
	return mesh_node(mesh, color, local_position, node_name)


static func color_from_hex(hex: String, fallback: Color) -> Color:
	var clean: String = hex.strip_edges().trim_prefix("#")
	if clean.length() != 6 or not clean.is_valid_hex_number():
		return fallback
	return Color.html(clean)


# ---------------------------------------------------------------------------
# The foods
# ---------------------------------------------------------------------------

## Builds the item for `item_id` with `color` (the object's own colour from the
## content library). Returns a `FeedingItem` node, or null for an unknown id.
static func build_item(item_id: String, color: Color) -> Node3D:
	match item_id:
		"apple":
			return _apple(color)
		"banana":
			return _banana(color)
		"water":
			return _cup(color)
		"milk":
			return _bottle(color)
	return null


static func _new_item(item_id: String, kind: String) -> Node3D:
	var item: Node3D = _Item.new()
	item.name = "Item_" + item_id
	item.set("item_id", item_id)
	item.set("kind", kind)
	var glow: MeshInstance3D = _glow_ring()
	item.add_child(glow)
	var pivot := Node3D.new()
	pivot.name = "TiltPivot"
	item.add_child(pivot)
	var body := Node3D.new()
	body.name = "Body"
	pivot.add_child(body)
	return item


static func _glow_ring() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = GLOW_RADIUS
	mesh.bottom_radius = GLOW_RADIUS
	mesh.height = 0.004
	mesh.radial_segments = 32
	var ring: MeshInstance3D = mesh_node(mesh, _Palette.STAR_NEXT, Vector3(0.0, 0.003, 0.0), "Glow", true)
	return ring


static func _apple(color: Color) -> Node3D:
	var item: Node3D = _new_item("apple", _Item.KIND_FRUIT)
	var pivot: Node3D = item.get_node("TiltPivot")
	var body: Node3D = pivot.get_node("Body")
	body.add_child(sphere(APPLE_RADIUS, color, Vector3(0.0, APPLE_RADIUS * 0.94, 0.0),
			Vector3(1.0, 0.94, 1.0), "Flesh"))
	# A dimple: a small skin-coloured sphere sunk into the top.
	body.add_child(sphere(APPLE_RADIUS * 0.34, _Palette.deep(color),
			Vector3(0.0, APPLE_RADIUS * 1.72, 0.0), Vector3(1.0, 0.35, 1.0), "Dimple"))
	body.add_child(cylinder(0.005, 0.006, 0.03, _Palette.INK,
			Vector3(0.0, APPLE_RADIUS * 1.86 + 0.012, 0.0), "Stem"))
	var leaf: MeshInstance3D = sphere(0.02, _Palette.deep(_Palette.MINT),
			Vector3(0.022, APPLE_RADIUS * 1.86 + 0.02, 0.0), Vector3(1.5, 0.28, 0.8), "Leaf")
	leaf.rotation.z = deg_to_rad(-18.0)
	body.add_child(leaf)
	item.call("bind_parts", body, pivot, [], null, 0.0, 0.0, item.get_node("Glow"))
	return item


static func _banana(color: Color) -> Node3D:
	var item: Node3D = _new_item("banana", _Item.KIND_FRUIT)
	var pivot: Node3D = item.get_node("TiltPivot")
	var body: Node3D = pivot.get_node("Body")
	var flesh: Color = _Palette.light(color)
	# Three capsules in a gentle bow, standing on the plate like the concept.
	var bow: Array = [
		[Vector3(0.006, 0.026, 0.0), 10.0],
		[Vector3(0.0, 0.064, 0.0), 0.0],
		[Vector3(0.006, 0.102, 0.0), -10.0],
	]
	for i: int in range(bow.size()):
		var seg: MeshInstance3D = capsule(0.02, 0.05, flesh, bow[i][0], "Flesh%d" % i)
		seg.rotation.z = deg_to_rad(float(bow[i][1]))
		body.add_child(seg)
	body.add_child(sphere(0.012, _Palette.deep(color), Vector3(0.008, 0.128, 0.0), Vector3.ONE, "Tip"))

	# Peel strips hinge at mid height and fold outward-and-down. Local +Z of each
	# hinge points AWAY from the fruit, so a positive fold about X drops the
	# strip outward -- see `feeding_item.gd::set_peel_progress()`.
	var strips: Array = []
	for i: int in range(3):
		var angle: float = deg_to_rad(90.0 + 120.0 * float(i))
		var outward: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var hinge := Node3D.new()
		hinge.name = "PeelHinge%d" % i
		hinge.position = outward * 0.024 + Vector3(0.0, BANANA_HINGE_Y, 0.0)
		hinge.rotation.y = atan2(outward.x, outward.z)
		var strip: MeshInstance3D = box(Vector3(0.03, BANANA_HEIGHT - BANANA_HINGE_Y + 0.012, 0.007),
				color, Vector3(0.0, (BANANA_HEIGHT - BANANA_HINGE_Y + 0.012) * 0.5, 0.0), "Strip")
		hinge.add_child(strip)
		body.add_child(hinge)
		strips.append(hinge)
	# The lower half of the peel stays wrapped.
	body.add_child(cylinder(0.026, 0.024, BANANA_HINGE_Y, color, Vector3(0.0, BANANA_HINGE_Y * 0.5, 0.0), "PeelBase"))
	item.call("bind_parts", body, pivot, strips, null, 0.0, 0.0, item.get_node("Glow"))
	return item


## A clear cup drawn as its water plus a blue rim, lid and handles. The water
## column is what shrinks when Bunny drinks.
static func _cup(color: Color) -> Node3D:
	var item: Node3D = _new_item("water", _Item.KIND_DRINK)
	var pivot: Node3D = item.get_node("TiltPivot")
	var body: Node3D = pivot.get_node("Body")
	var water: Color = _Palette.DUSTY_BLUE.lerp(color, 0.5)
	var liquid: MeshInstance3D = cylinder(0.04, 0.036, CUP_LIQUID_HEIGHT, water,
			Vector3(0.0, CUP_LIQUID_HEIGHT * 0.5, 0.0), "Liquid")
	body.add_child(liquid)
	body.add_child(cylinder(0.044, 0.04, 0.012, _Palette.deep(color), Vector3(0.0, 0.006, 0.0), "Base"))
	var rim: MeshInstance3D = torus(0.038, 0.048, color, Vector3(0.0, CUP_LIQUID_HEIGHT + 0.004, 0.0), "Rim")
	body.add_child(rim)
	body.add_child(cylinder(0.046, 0.046, 0.016, color, Vector3(0.0, CUP_LIQUID_HEIGHT + 0.016, 0.0), "Lid"))
	var spout: MeshInstance3D = box(Vector3(0.026, 0.018, 0.02), color,
			Vector3(0.0, CUP_LIQUID_HEIGHT + 0.032, -0.03), "Spout")
	body.add_child(spout)
	for side: int in [-1, 1]:
		var handle: MeshInstance3D = torus(0.014, 0.024, color,
				Vector3(0.056 * float(side), CUP_LIQUID_HEIGHT * 0.55, 0.0), "Handle")
		handle.rotation.x = deg_to_rad(90.0)
		body.add_child(handle)
	item.call("bind_parts", body, pivot, [], liquid, CUP_LIQUID_HEIGHT, 0.0, item.get_node("Glow"))
	return item


## A baby bottle: the milk IS the body, under a peach collar and teat.
static func _bottle(color: Color) -> Node3D:
	var item: Node3D = _new_item("milk", _Item.KIND_DRINK)
	var pivot: Node3D = item.get_node("TiltPivot")
	var body: Node3D = pivot.get_node("Body")
	var milk: Color = _Palette.CREAM.lerp(color, 0.7)
	var liquid: MeshInstance3D = cylinder(0.036, 0.036, BOTTLE_LIQUID_HEIGHT, milk,
			Vector3(0.0, BOTTLE_LIQUID_HEIGHT * 0.5, 0.0), "Liquid")
	body.add_child(liquid)
	body.add_child(cylinder(0.038, 0.036, 0.01, _Palette.deep(_Palette.PEACH), Vector3(0.0, 0.005, 0.0), "Base"))
	body.add_child(torus(0.03, 0.042, _Palette.deep(_Palette.PEACH),
			Vector3(0.0, BOTTLE_LIQUID_HEIGHT + 0.006, 0.0), "Collar"))
	body.add_child(cylinder(0.024, 0.03, 0.02, _Palette.PEACH,
			Vector3(0.0, BOTTLE_LIQUID_HEIGHT + 0.018, 0.0), "Neck"))
	body.add_child(capsule(0.012, 0.03, _Palette.PEACH,
			Vector3(0.0, BOTTLE_LIQUID_HEIGHT + 0.042, 0.0), "Teat"))
	item.call("bind_parts", body, pivot, [], liquid, BOTTLE_LIQUID_HEIGHT, 0.0, item.get_node("Glow"))
	return item


# ---------------------------------------------------------------------------
# The table
# ---------------------------------------------------------------------------

static func plate(rim_color: Color, node_name: String = "Plate") -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.add_child(cylinder(0.105, 0.095, 0.012, _Palette.CREAM, Vector3(0.0, 0.006, 0.0), "Dish"))
	var rim: MeshInstance3D = torus(0.09, 0.112, rim_color, Vector3(0.0, 0.01, 0.0), "Rim")
	rim.scale = Vector3(1.0, 0.55, 1.0)
	root.add_child(rim)
	return root


## The wooden tray with its gingham cloth, in front of the chair.
static func tray(width: float, depth: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Tray"
	var wood: Color = _Palette.PEACH.lerp(_Palette.INK, 0.28)
	var cloth: Color = _Palette.light(_Palette.PEACH)
	root.add_child(box(Vector3(width, 0.035, depth), wood, Vector3(0.0, -0.0175, 0.0), "Board"))
	root.add_child(box(Vector3(width * 0.9, 0.006, depth * 0.82), cloth, Vector3(0.0, 0.003, 0.0), "Cloth"))
	# Gingham: a few pale check lines each way, cheap and cheerful.
	var check: Color = _Palette.PEACH.lerp(_Palette.CREAM, 0.15)
	for i: int in range(5):
		var x: float = (float(i) - 2.0) * width * 0.9 / 5.0
		root.add_child(box(Vector3(width * 0.03, 0.007, depth * 0.82), check, Vector3(x, 0.0035, 0.0), "CheckX%d" % i))
	for j: int in range(3):
		var z: float = (float(j) - 1.0) * depth * 0.82 / 3.0
		root.add_child(box(Vector3(width * 0.9, 0.007, depth * 0.03), check, Vector3(0.0, 0.0035, z), "CheckZ%d" % j))
	# A rounded front lip, so the tray reads as a tray.
	var lip: MeshInstance3D = capsule(0.022, width, wood, Vector3(0.0, 0.0, depth * 0.5), "Lip")
	lip.rotation.z = deg_to_rad(90.0)
	root.add_child(lip)
	return root


## Lavender highchair: seat, back with a heart, two front posts.
static func highchair() -> Node3D:
	var root := Node3D.new()
	root.name = "Highchair"
	var lavender: Color = _Palette.LAVENDER
	var deep: Color = _Palette.deep(_Palette.LAVENDER)
	var wood: Color = _Palette.PEACH.lerp(_Palette.INK, 0.28)
	# Back: a tall rounded slab behind Bunny.
	var back: MeshInstance3D = box(Vector3(0.62, 0.86, 0.06), lavender, Vector3(0.0, 0.66, -0.22), "Back")
	root.add_child(back)
	var back_top: MeshInstance3D = capsule(0.03, 0.62, lavender, Vector3(0.0, 1.09, -0.22), "BackTop")
	back_top.rotation.z = deg_to_rad(90.0)
	root.add_child(back_top)
	# Two hearts on the back, like the concept: two spheres and a wedge each.
	for side: int in [-1, 1]:
		var hx: float = 0.19 * float(side)
		root.add_child(sphere(0.045, deep, Vector3(hx - 0.032, 0.78, -0.185), Vector3(1.0, 1.0, 0.35), "Heart"))
		root.add_child(sphere(0.045, deep, Vector3(hx + 0.032, 0.78, -0.185), Vector3(1.0, 1.0, 0.35), "Heart"))
		var wedge: MeshInstance3D = box(Vector3(0.076, 0.076, 0.03), deep, Vector3(hx, 0.735, -0.185), "HeartPoint")
		wedge.rotation.z = deg_to_rad(45.0)
		root.add_child(wedge)
	# Seat and two low side rails (kept under the tray line so they never read
	# as walls beside Bunny).
	root.add_child(box(Vector3(0.7, 0.05, 0.5), lavender, Vector3(0.0, 0.2, 0.0), "Seat"))
	for side: int in [-1, 1]:
		root.add_child(box(Vector3(0.05, 0.12, 0.46), deep, Vector3(0.335 * float(side), 0.24, -0.02), "Arm"))
		root.add_child(box(Vector3(0.045, 0.24, 0.045), wood, Vector3(0.31 * float(side), 0.12, 0.2), "Leg"))
		root.add_child(box(Vector3(0.045, 0.24, 0.045), wood, Vector3(0.31 * float(side), 0.12, -0.2), "LegBack"))
	return root


## A pastel nursery wall and a pink rug, so the stage never shows the sky.
static func backdrop() -> Node3D:
	var root := Node3D.new()
	root.name = "Backdrop"
	var wall: Color = _Palette.light(_Palette.PEACH).lerp(_Palette.SOFT_PINK, 0.25)
	var wainscot: Color = _Palette.light(_Palette.LAVENDER)
	var rug: Color = _Palette.light(_Palette.SOFT_PINK)
	var floor_color: Color = _Palette.PEACH.lerp(_Palette.CREAM, 0.3)
	root.add_child(box(Vector3(8.0, 3.2, 0.1), wall, Vector3(0.0, 1.6, -1.3), "Wall"))
	root.add_child(box(Vector3(8.0, 0.9, 0.12), wainscot, Vector3(0.0, 0.45, -1.29), "Wainscot"))
	root.add_child(box(Vector3(8.0, 0.02, 8.0), floor_color, Vector3(0.0, -0.01, 0.0), "Floor"))
	root.add_child(cylinder(1.4, 1.4, 0.01, rug, Vector3(0.0, 0.005, 0.0), "Rug"))
	# A window with a garden-green pane, high left, and pastel clouds on the wall.
	root.add_child(box(Vector3(0.9, 0.9, 0.04), _Palette.CREAM, Vector3(-1.5, 1.7, -1.24), "WindowFrame"))
	root.add_child(box(Vector3(0.76, 0.76, 0.02), _Palette.light(_Palette.MINT), Vector3(-1.5, 1.7, -1.22), "WindowPane"))
	root.add_child(box(Vector3(0.9, 0.06, 0.08), _Palette.PEACH, Vector3(-1.5, 1.22, -1.22), "Sill"))
	for cloud: Array in [[1.1, 1.9, 0.16], [1.55, 2.1, 0.12], [-0.4, 2.35, 0.1]]:
		var c: Color = _Palette.light(_Palette.DUSTY_BLUE)
		root.add_child(sphere(cloud[2], c, Vector3(cloud[0], cloud[1], -1.23), Vector3(1.6, 1.0, 0.2), "Cloud"))
		root.add_child(sphere(cloud[2] * 0.8, c, Vector3(cloud[0] + cloud[2] * 1.1, cloud[1] + cloud[2] * 0.3, -1.23),
				Vector3(1.2, 1.0, 0.2), "Cloud"))
	# A shelf with two books and a plant, right.
	root.add_child(box(Vector3(0.8, 0.05, 0.25), _Palette.PEACH.lerp(_Palette.INK, 0.2), Vector3(1.7, 1.15, -1.1), "Shelf"))
	root.add_child(box(Vector3(0.08, 0.26, 0.2), _Palette.MINT, Vector3(1.45, 1.3, -1.1), "Book"))
	root.add_child(box(Vector3(0.08, 0.22, 0.2), _Palette.SOFT_PINK, Vector3(1.55, 1.28, -1.1), "Book"))
	root.add_child(box(Vector3(0.08, 0.3, 0.2), _Palette.DUSTY_BLUE, Vector3(1.65, 1.32, -1.1), "Book"))
	root.add_child(cylinder(0.08, 0.06, 0.12, _Palette.PEACH, Vector3(1.95, 1.23, -1.1), "Pot"))
	root.add_child(sphere(0.12, _Palette.deep(_Palette.MINT), Vector3(1.95, 1.38, -1.1), Vector3(1.0, 0.8, 1.0), "Plant"))
	return root
