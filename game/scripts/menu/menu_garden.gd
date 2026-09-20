extends Node3D

## The storybook garden behind the title screen.
##
## The menu used to be a green plane under a blue sky with the characters stood
## on a rug, which is a colour test, not a place. This builds the place: a small
## rounded house with a bright front door, a stepping-stone path down to the
## camera, flowerbeds, round trees with fruit in them, a picket fence, soft
## hills, clouds and a sun. Everything is a built-in primitive, coloured only
## from `palette.gd` tokens and the two derivations the art bible allows, so it
## can be swapped for real props later without touching a colour or a rule.
##
## ## Budget
##
## Mobile renderer, one `DirectionalLight3D` (owned by `main.tscn`, not this
## file), no shadows, no GI, no post-processing. Spheres are 16x8, so the whole
## garden is a few thousand triangles -- `test_menu_wow.gd` asserts the cap.
##
## ## Determinism
##
## The flower colours and stone wobble come from a seeded generator, so two
## launches -- and two test runs -- build the identical garden.

const Palette := preload("res://scripts/ui/palette.gd")

## Where the house stands, feet at ground level. Right of centre so the door
## shows past Aliz's shoulder and the roof peak clears the title panel: the pair
## stands on the path in front of their home, not in front of the door.
const HOUSE_POSITION := Vector3(2.5, 0.0, -6.0)
const HOUSE_SIZE := Vector3(3.2, 2.35, 2.6)
const ROOF_HEIGHT: float = 1.3
const DOOR_SIZE := Vector2(0.72, 1.25)

## Where the path starts (the doorstep) and ends (just past the camera's feet).
const PATH_START := Vector3(2.5, 0.0, -4.65)
const PATH_END := Vector3(-0.6, 0.0, 2.6)
const PATH_BEND := Vector3(1.1, 0.0, -1.2)
const PATH_STONES: int = 13

const SEED: int = 20260920

const TREE_SPOTS: Array = [
	# position, foliage radius, foliage tint index
	[Vector3(-3.6, 0.0, -4.6), 0.85, 0],
	[Vector3(-2.4, 0.0, -7.4), 0.70, 1],
	[Vector3(5.7, 0.0, -5.0), 0.90, 1],
	[Vector3(5.2, 0.0, -8.4), 0.72, 0],
	[Vector3(-5.6, 0.0, -2.2), 0.62, 1],
	[Vector3(8.4, 0.0, -6.6), 0.80, 0],
	[Vector3(-7.4, 0.0, -7.6), 0.74, 1],
]

const FLOWERBED_SPOTS: Array = [
	# centre, size (x, z), flower count
	[Vector3(1.3, 0.0, -4.25), Vector2(1.1, 0.5), 7],
	[Vector3(3.8, 0.0, -4.25), Vector2(0.9, 0.5), 6],
	[Vector3(-2.35, 0.0, 0.35), Vector2(1.2, 0.6), 8],
	[Vector3(2.55, 0.0, 0.55), Vector2(1.0, 0.55), 6],
]

const CLOUD_SPOTS: Array = [
	# position, scale
	[Vector3(-6.2, 4.6, -13.0), 1.25],
	[Vector3(-1.4, 5.4, -15.0), 1.0],
	[Vector3(4.6, 4.9, -14.0), 1.35],
	[Vector3(8.8, 6.0, -17.0), 0.9],
]

var _built: bool = false
var _materials: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## What was built, by kind, so a test can ask rather than count nodes by name.
var _counts: Dictionary = {}


func _ready() -> void:
	build()


## Idempotent and callable before `_ready()`: the headless runner never fires
## `_ready()` for nodes added under the root.
func build() -> void:
	if _built:
		return
	_built = true
	_rng.seed = SEED
	_build_sky()
	_build_ground()
	_build_hills()
	_build_house()
	_build_path()
	_build_trees()
	_build_flowerbeds()
	_build_fence()
	_build_clouds()
	_build_toys()


## How many of each thing the garden holds: "trees", "flowers", "windows",
## "doors", "clouds", "stones", "hills", "fencePosts", "toys", "suns".
func describe() -> Dictionary:
	build()
	return _counts.duplicate()


## Every distinct colour on a mesh in the garden. For the palette test.
func colours_used() -> Array:
	build()
	var out: Array = []
	for key: Variant in _materials.keys():
		out.append((_materials[key] as StandardMaterial3D).albedo_color)
	return out


## Diagnostic: triangles across every mesh built here.
func count_triangles() -> int:
	build()
	return _count(self)


# ---------------------------------------------------------------------------
# Colours -- tokens and the two allowed derivations, nothing else
# ---------------------------------------------------------------------------

static func grass() -> Color:
	return Palette.deep(Palette.MINT)


static func soil() -> Color:
	return Palette.INK.lerp(Palette.PEACH, 0.30)


static func wood() -> Color:
	return Palette.INK.lerp(Palette.PEACH, 0.42)


static func wall() -> Color:
	return Palette.light(Palette.SOFT_PINK)


static func roof() -> Color:
	return Palette.deep(Palette.PEACH)


static func door() -> Color:
	return Palette.STAR_EARNED


static func window_pane() -> Color:
	return Palette.light(Palette.DUSTY_BLUE)


static func leaf(index: int) -> Color:
	if index == 0:
		return Palette.deep(Palette.MINT)
	return Palette.MINT.lerp(Palette.deep(Palette.MINT), 0.5)


static func flower_colours() -> Array:
	return [Palette.STAR_EARNED, Palette.SOFT_PINK, Palette.LAVENDER,
			Palette.CREAM, Palette.light(Palette.DUSTY_BLUE), Palette.deep(Palette.SOFT_PINK)]


# ---------------------------------------------------------------------------
# Sky
# ---------------------------------------------------------------------------

func _build_sky() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.30, 0.50, 1.0])
	gradient.colors = PackedColorArray([
		Palette.DUSTY_BLUE,
		Palette.light(Palette.DUSTY_BLUE),
		Palette.light(Palette.SOFT_PINK),
		Palette.light(Palette.SOFT_PINK),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 4
	texture.height = 128
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)

	var dome := SphereMesh.new()
	dome.radius = 70.0
	dome.height = 140.0
	dome.radial_segments = 24
	dome.rings = 12
	dome.flip_faces = true
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var sky := MeshInstance3D.new()
	sky.name = "SkyDome"
	sky.mesh = dome
	sky.material_override = material
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)

	# The sun: a soft disc high on the left, unlit so it reads as light itself.
	var sun := _place(self, "Sun", _sphere(1.35), Palette.STAR_NEXT,
			Vector3(-9.5, 8.6, -24.0), Vector3.ZERO, Vector3.ONE, true)
	var halo_colour: Color = Palette.STAR_NEXT
	halo_colour.a = 0.32
	_place(sun, "Halo", _sphere(1.0), halo_colour,
			Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 1.45, true)
	_bump("suns")


# ---------------------------------------------------------------------------
# Ground and hills
# ---------------------------------------------------------------------------

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(220.0, 220.0)
	_place(self, "Grass", plane, grass(), Vector3.ZERO)


func _build_hills() -> void:
	var hills := Node3D.new()
	hills.name = "Hills"
	add_child(hills)
	var spots: Array = [
		[Vector3(-9.0, -1.4, -15.0), Vector3(10.0, 3.4, 6.0), Palette.MINT],
		[Vector3(7.0, -1.2, -17.0), Vector3(12.0, 3.8, 7.0), Palette.MINT],
		[Vector3(-1.0, -1.8, -21.0), Vector3(16.0, 4.6, 8.0), Palette.light(Palette.MINT)],
		[Vector3(14.0, -2.0, -22.0), Vector3(12.0, 3.6, 8.0), Palette.light(Palette.MINT)],
		[Vector3(27.0, -2.2, -24.0), Vector3(13.0, 3.4, 8.0), Palette.light(Palette.MINT)],
		[Vector3(-23.0, -2.0, -23.0), Vector3(13.0, 3.8, 8.0), Palette.light(Palette.MINT)],
	]
	for spot: Array in spots:
		_place(hills, "Hill", _sphere(1.0), spot[2], spot[0], Vector3.ZERO, spot[1])
		_bump("hills")


# ---------------------------------------------------------------------------
# The house
# ---------------------------------------------------------------------------

func _build_house() -> void:
	var house := Node3D.new()
	house.name = "House"
	house.position = HOUSE_POSITION
	add_child(house)

	var body := BoxMesh.new()
	body.size = HOUSE_SIZE
	_place(house, "Walls", body, wall(), Vector3(0.0, HOUSE_SIZE.y * 0.5, 0.0))

	# A cream skirt at the base and under the eaves: the two bands are what make
	# a box read as a cottage rather than as a crate.
	var skirt := BoxMesh.new()
	skirt.size = Vector3(HOUSE_SIZE.x + 0.12, 0.22, HOUSE_SIZE.z + 0.12)
	_place(house, "Skirt", skirt, Palette.CREAM, Vector3(0.0, 0.11, 0.0))

	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(HOUSE_SIZE.x + 0.55, ROOF_HEIGHT, HOUSE_SIZE.z + 0.5)
	_place(house, "Roof", roof_mesh, roof(),
			Vector3(0.0, HOUSE_SIZE.y + ROOF_HEIGHT * 0.5 - 0.02, 0.0))
	# The eave: a thin cream slab between wall and roof, so the roof floats on a
	# light line instead of sitting hard on the pink.
	var eave := BoxMesh.new()
	eave.size = Vector3(HOUSE_SIZE.x + 0.55, 0.12, HOUSE_SIZE.z + 0.5)
	_place(house, "Eave", eave, Palette.CREAM, Vector3(0.0, HOUSE_SIZE.y + 0.02, 0.0))

	var chimney := BoxMesh.new()
	chimney.size = Vector3(0.42, 0.9, 0.42)
	# Tall enough to clear the ridge, so it reads as a chimney from the path
	# rather than hiding on the far slope.
	_place(house, "Chimney", chimney, Palette.deep(Palette.LAVENDER),
			Vector3(HOUSE_SIZE.x * 0.28, HOUSE_SIZE.y + ROOF_HEIGHT * 0.55 + 0.32, -0.3))
	var chimney_cap := BoxMesh.new()
	chimney_cap.size = Vector3(0.52, 0.12, 0.52)
	_place(house, "ChimneyCap", chimney_cap, Palette.CREAM,
			Vector3(HOUSE_SIZE.x * 0.28, HOUSE_SIZE.y + ROOF_HEIGHT * 0.55 + 0.82, -0.3))

	var front_z: float = HOUSE_SIZE.z * 0.5
	_build_door(house, Vector3(0.0, 0.0, front_z))
	_build_window(house, Vector3(-HOUSE_SIZE.x * 0.31, 1.32, front_z), 0.62)
	_build_window(house, Vector3(HOUSE_SIZE.x * 0.31, 1.32, front_z), 0.62)
	_build_round_window(house, Vector3(0.0, HOUSE_SIZE.y + ROOF_HEIGHT * 0.36, front_z + 0.02))

	# Two round bushes tuck the corners into the ground.
	for side: float in [-1.0, 1.0]:
		var bush := _place(house, "Bush", _sphere(0.42), leaf(1),
				Vector3(side * (HOUSE_SIZE.x * 0.5 + 0.25), 0.28, front_z - 0.15),
				Vector3.ZERO, Vector3(1.0, 0.75, 1.0))
		bush.name = "BushLeft" if side < 0.0 else "BushRight"


func _build_door(house: Node3D, at: Vector3) -> void:
	var frame := Node3D.new()
	frame.name = "Door"
	frame.position = at
	house.add_child(frame)

	var lift: float = 0.03
	var arch_radius: float = DOOR_SIZE.x * 0.5
	# The frame first, a shade wider, so the door is outlined in cream.
	var frame_slab := BoxMesh.new()
	frame_slab.size = Vector3(DOOR_SIZE.x + 0.14, DOOR_SIZE.y - arch_radius + 0.07, 0.06)
	_place(frame, "FrameSlab", frame_slab, Palette.CREAM,
			Vector3(0.0, (DOOR_SIZE.y - arch_radius + 0.07) * 0.5, lift))
	_place(frame, "FrameArch", _disc(arch_radius + 0.07, 0.06), Palette.CREAM,
			Vector3(0.0, DOOR_SIZE.y - arch_radius, lift + 0.003), Vector3(90.0, 0.0, 0.0))

	var slab := BoxMesh.new()
	slab.size = Vector3(DOOR_SIZE.x, DOOR_SIZE.y - arch_radius, 0.08)
	_place(frame, "Slab", slab, door(),
			Vector3(0.0, (DOOR_SIZE.y - arch_radius) * 0.5, lift + 0.02))
	# A hair forward of the slab, so the two yellow faces never share a plane.
	_place(frame, "Arch", _disc(arch_radius, 0.08), door(),
			Vector3(0.0, DOOR_SIZE.y - arch_radius, lift + 0.024), Vector3(90.0, 0.0, 0.0))
	# A little round window in the door and a knob, both in the pane blue.
	_place(frame, "Peep", _disc(0.11, 0.03), window_pane(),
			Vector3(0.0, DOOR_SIZE.y - arch_radius - 0.02, lift + 0.08), Vector3(90.0, 0.0, 0.0))
	_place(frame, "Knob", _sphere(0.045), Palette.INK.lerp(Palette.PEACH, 0.5),
			Vector3(DOOR_SIZE.x * 0.32, DOOR_SIZE.y * 0.42, lift + 0.09))

	var step := BoxMesh.new()
	step.size = Vector3(DOOR_SIZE.x + 0.5, 0.09, 0.42)
	_place(frame, "Step", step, Palette.deep(Palette.CREAM), Vector3(0.0, 0.045, 0.24))
	var mat := BoxMesh.new()
	mat.size = Vector3(0.62, 0.02, 0.34)
	_place(frame, "Mat", mat, Palette.PEACH, Vector3(0.0, 0.10, 0.22))
	_bump("doors")


func _build_window(house: Node3D, at: Vector3, side: float) -> void:
	var window := Node3D.new()
	window.name = "Window"
	window.position = at
	house.add_child(window)
	var frame := BoxMesh.new()
	frame.size = Vector3(side + 0.14, side + 0.14, 0.05)
	_place(window, "Frame", frame, Palette.CREAM, Vector3(0.0, 0.0, 0.025))
	var pane := BoxMesh.new()
	pane.size = Vector3(side, side, 0.05)
	_place(window, "Pane", pane, window_pane(), Vector3(0.0, 0.0, 0.045))
	# A cross of cream mullions.
	var bar_v := BoxMesh.new()
	bar_v.size = Vector3(0.05, side, 0.03)
	_place(window, "MullionV", bar_v, Palette.CREAM, Vector3(0.0, 0.0, 0.08))
	var bar_h := BoxMesh.new()
	bar_h.size = Vector3(side, 0.05, 0.03)
	_place(window, "MullionH", bar_h, Palette.CREAM, Vector3(0.0, 0.0, 0.08))
	# A window box of flowers under the sill: the thing that says somebody lives
	# here and waters them.
	var box := BoxMesh.new()
	box.size = Vector3(side + 0.2, 0.16, 0.2)
	_place(window, "Box", box, wood(), Vector3(0.0, -side * 0.5 - 0.14, 0.11))
	for i: int in range(3):
		var x: float = (float(i) - 1.0) * side * 0.36
		_place(window, "BoxFlower", _sphere(0.075), flower_colours()[(i * 2 + 1) % 6],
				Vector3(x, -side * 0.5 - 0.02, 0.14))
	_bump("windows")


func _build_round_window(house: Node3D, at: Vector3) -> void:
	var window := Node3D.new()
	window.name = "AtticWindow"
	window.position = at
	house.add_child(window)
	_place(window, "Frame", _disc(0.30, 0.05), Palette.CREAM,
			Vector3(0.0, 0.0, 0.025), Vector3(90.0, 0.0, 0.0))
	_place(window, "Pane", _disc(0.23, 0.05), window_pane(),
			Vector3(0.0, 0.0, 0.045), Vector3(90.0, 0.0, 0.0))
	_bump("windows")


# ---------------------------------------------------------------------------
# The path
# ---------------------------------------------------------------------------

func _build_path() -> void:
	var path := Node3D.new()
	path.name = "Path"
	add_child(path)
	for i: int in range(PATH_STONES):
		var t: float = float(i) / float(PATH_STONES - 1)
		var p: Vector3 = PATH_START.bezier_interpolate(PATH_BEND, PATH_BEND, PATH_END, t)
		var wobble: float = _rng.randf_range(-0.14, 0.14)
		p.x += wobble
		var radius: float = 0.27 + _rng.randf_range(-0.03, 0.05)
		var colour: Color = Palette.deep(Palette.CREAM) if i % 2 == 0 else Palette.light(Palette.PEACH)
		var stone := _place(path, "Stone", _disc(radius, 0.035), colour,
				Vector3(p.x, 0.018, p.z), Vector3.ZERO, Vector3(1.0, 1.0, 0.82))
		stone.name = "Stone%d" % i
		_bump("stones")


# ---------------------------------------------------------------------------
# Trees, flowers, fence
# ---------------------------------------------------------------------------

func _build_trees() -> void:
	var trees := Node3D.new()
	trees.name = "Trees"
	add_child(trees)
	for i: int in range(TREE_SPOTS.size()):
		var spot: Array = TREE_SPOTS[i]
		var at: Vector3 = spot[0]
		var radius: float = spot[1]
		var tint: Color = leaf(int(spot[2]))
		var tree := Node3D.new()
		tree.name = "Tree%d" % i
		tree.position = at
		trees.add_child(tree)
		var trunk_height: float = radius * 1.15
		_place(tree, "Trunk", _cylinder(radius * 0.16, trunk_height), wood(),
				Vector3(0.0, trunk_height * 0.5, 0.0))
		var crown_y: float = trunk_height + radius * 0.75
		_place(tree, "Crown", _sphere(radius), tint, Vector3(0.0, crown_y, 0.0))
		_place(tree, "CrownTop", _sphere(radius * 0.62), tint,
				Vector3(radius * 0.15, crown_y + radius * 0.62, -radius * 0.1))
		_place(tree, "CrownSide", _sphere(radius * 0.55), tint,
				Vector3(-radius * 0.62, crown_y + radius * 0.18, radius * 0.25))
		# Fruit. Three bright dots on the front of the crown -- a toy tree.
		for f: int in range(3):
			var angle: float = deg_to_rad(-40.0 + 40.0 * float(f))
			var fruit_pos := Vector3(sin(angle) * radius * 0.85,
					crown_y + (0.3 - 0.35 * float(f % 2)) * radius, cos(angle) * radius * 0.85)
			var fruit_colour: Color = Palette.STAR_EARNED if i % 2 == 0 else Palette.deep(Palette.SOFT_PINK)
			_place(tree, "Fruit", _sphere(radius * 0.11), fruit_colour, fruit_pos)
		_bump("trees")


func _build_flowerbeds() -> void:
	var beds := Node3D.new()
	beds.name = "Flowerbeds"
	add_child(beds)
	var colours: Array = flower_colours()
	for b: int in range(FLOWERBED_SPOTS.size()):
		var spot: Array = FLOWERBED_SPOTS[b]
		var centre: Vector3 = spot[0]
		var size: Vector2 = spot[1]
		var count: int = int(spot[2])
		var bed := Node3D.new()
		bed.name = "Bed%d" % b
		bed.position = centre
		beds.add_child(bed)
		_place(bed, "Soil", _disc(0.5, 0.06), soil(), Vector3(0.0, 0.03, 0.0),
				Vector3.ZERO, Vector3(size.x, 1.0, size.y))
		for i: int in range(count):
			var t: float = (float(i) + 0.5) / float(count)
			var x: float = (t - 0.5) * size.x * 0.9
			var z: float = _rng.randf_range(-0.28, 0.28) * size.y
			var height: float = _rng.randf_range(0.20, 0.34)
			var flower := Node3D.new()
			flower.name = "Flower%d" % i
			flower.position = Vector3(x, 0.06, z)
			bed.add_child(flower)
			_place(flower, "Stem", _cylinder(0.02, height), leaf(0), Vector3(0.0, height * 0.5, 0.0))
			var head_colour: Color = colours[(i + b) % colours.size()]
			_place(flower, "Head", _sphere(0.085), head_colour, Vector3(0.0, height + 0.03, 0.0))
			if head_colour != Palette.STAR_EARNED:
				_place(flower, "Centre", _sphere(0.035), Palette.STAR_EARNED,
						Vector3(0.0, height + 0.03, 0.075))
			var leaf_mesh := _sphere(0.055)
			_place(flower, "Leaf", leaf_mesh, leaf(1), Vector3(0.05, height * 0.45, 0.0),
					Vector3.ZERO, Vector3(1.4, 0.6, 0.8))
			_bump("flowers")


func _build_fence() -> void:
	var fence := Node3D.new()
	fence.name = "Fence"
	add_child(fence)
	var z: float = -4.15
	var runs: Array = [[-9.3, 0.2], [4.7, 11.3]]
	for run: Array in runs:
		var from_x: float = run[0]
		var to_x: float = run[1]
		var length: float = to_x - from_x
		for rail_y: float in [0.22, 0.42]:
			var rail := BoxMesh.new()
			rail.size = Vector3(length, 0.055, 0.045)
			_place(fence, "Rail", rail, Palette.CREAM, Vector3(from_x + length * 0.5, rail_y, z))
		var x: float = from_x
		while x <= to_x + 0.001:
			var post := BoxMesh.new()
			post.size = Vector3(0.09, 0.58, 0.07)
			_place(fence, "Post", post, Palette.CREAM, Vector3(x, 0.29, z))
			_place(fence, "PostCap", _sphere(0.065), Palette.CREAM, Vector3(x, 0.60, z))
			_bump("fencePosts")
			x += 0.46


# ---------------------------------------------------------------------------
# Clouds and toys
# ---------------------------------------------------------------------------

func _build_clouds() -> void:
	var clouds := Node3D.new()
	clouds.name = "Clouds"
	add_child(clouds)
	for i: int in range(CLOUD_SPOTS.size()):
		var spot: Array = CLOUD_SPOTS[i]
		var at: Vector3 = spot[0]
		var s: float = float(spot[1])
		var cloud := Node3D.new()
		cloud.name = "Cloud%d" % i
		cloud.position = at
		clouds.add_child(cloud)
		_place(cloud, "PuffA", _sphere(1.0), Palette.CREAM, Vector3.ZERO,
				Vector3.ZERO, Vector3(1.25, 0.72, 1.0) * s, true)
		_place(cloud, "PuffB", _sphere(1.0), Palette.CREAM, Vector3(-1.15, -0.12, 0.0) * s,
				Vector3.ZERO, Vector3(0.85, 0.55, 0.85) * s, true)
		_place(cloud, "PuffC", _sphere(1.0), Palette.CREAM, Vector3(1.1, -0.1, 0.0) * s,
				Vector3.ZERO, Vector3(0.78, 0.52, 0.8) * s, true)
		_bump("clouds")


func _build_toys() -> void:
	var toys := Node3D.new()
	toys.name = "Toys"
	add_child(toys)
	var balls: Array = [
		[Vector3(1.55, 0.13, -0.45), 0.13, Palette.SOFT_PINK],
		[Vector3(-1.45, 0.11, -1.25), 0.11, Palette.LAVENDER],
		[Vector3(1.85, 0.09, -0.95), 0.09, Palette.STAR_EARNED],
	]
	for i: int in range(balls.size()):
		var ball: Array = balls[i]
		var node := _place(toys, "Ball", _sphere(float(ball[1])), ball[2], ball[0])
		node.name = "Ball%d" % i
		_bump("toys")

	# A little mailbox by the path: post, box, and a sunny flag.
	var mailbox := Node3D.new()
	mailbox.name = "Mailbox"
	mailbox.position = Vector3(3.7, 0.0, -2.9)
	toys.add_child(mailbox)
	_place(mailbox, "Post", _cylinder(0.04, 0.7), wood(), Vector3(0.0, 0.35, 0.0))
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.22, 0.36)
	_place(mailbox, "Box", box, Palette.deep(Palette.DUSTY_BLUE), Vector3(0.0, 0.81, 0.0))
	_place(mailbox, "Lid", _disc(0.13, 0.36), Palette.deep(Palette.DUSTY_BLUE),
			Vector3(0.0, 0.92, 0.0), Vector3(90.0, 0.0, 0.0))
	var flag := BoxMesh.new()
	flag.size = Vector3(0.03, 0.16, 0.09)
	_place(mailbox, "Flag", flag, Palette.STAR_EARNED, Vector3(0.15, 0.98, -0.1))
	_bump("toys")

	# A toy duck on the grass by the front bed, out of the way of the feet.
	var duck := Node3D.new()
	duck.name = "Duck"
	duck.position = Vector3(-1.62, 0.0, -0.62)
	duck.rotation_degrees = Vector3(0.0, 35.0, 0.0)
	toys.add_child(duck)
	_place(duck, "Body", _sphere(0.14), Palette.STAR_EARNED, Vector3(0.0, 0.13, 0.0),
			Vector3.ZERO, Vector3(1.0, 0.8, 1.3))
	_place(duck, "Head", _sphere(0.09), Palette.STAR_EARNED, Vector3(0.0, 0.30, -0.12))
	_place(duck, "Beak", _sphere(0.045), Palette.deep(Palette.PEACH), Vector3(0.0, 0.28, -0.21),
			Vector3.ZERO, Vector3(1.0, 0.6, 1.3))
	_place(duck, "Eye", _sphere(0.018), Palette.INK, Vector3(0.06, 0.32, -0.15))
	_bump("toys")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _place(parent: Node, node_name: String, mesh: Mesh, colour: Color, at: Vector3,
		rot_deg: Vector3 = Vector3.ZERO, scale_by: Vector3 = Vector3.ONE,
		unshaded: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material(colour, unshaded)
	instance.position = at
	instance.rotation_degrees = rot_deg
	instance.scale = scale_by
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## One material per colour: a garden of sixty meshes in nine colours should
## cost nine materials, not sixty.
func _material(colour: Color, unshaded: bool) -> StandardMaterial3D:
	var key: String = "%s|%s" % [colour.to_html(true), str(unshaded)]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.95
	material.metallic = 0.0
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if colour.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = material
	return material


## Small things (flower heads, fruit, post caps) get the coarse sphere: at
## their on-screen size 10x5 is indistinguishable from 16x8 and a third the cost.
static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var coarse: bool = radius < 0.12
	mesh.radial_segments = 10 if coarse else 16
	mesh.rings = 5 if coarse else 8
	return mesh


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8 if radius < 0.05 else 12
	mesh.rings = 1
	return mesh


## A flat round slab. Rotated 90 about X by the caller when it should face +Z.
static func _disc(radius: float, thickness: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = thickness
	mesh.radial_segments = 20
	mesh.rings = 1
	return mesh


func _bump(kind: String) -> void:
	_counts[kind] = int(_counts.get(kind, 0)) + 1


static func _count(node: Node) -> int:
	var total: int = 0
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var indices: Variant = arrays[Mesh.ARRAY_INDEX]
				if indices != null and (indices as PackedInt32Array).size() > 0:
					total += (indices as PackedInt32Array).size() / 3
				else:
					total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for child: Node in node.get_children():
		total += _count(child)
	return total
