extends Node3D

## The storybook garden behind the title screen.
##
## The menu used to be a green plane under a blue sky with the characters stood
## on a rug, which is a colour test, not a place. This builds the place, after
## the owner's concept (`assets/uiGenerated/menu/mainMenuConcept.png`): a
## pastel cottage with a warm pink roof and a heart on its yellow door, a
## stepping-stone path down to the camera, dense flowerbeds in three colours
## with round petals, a big leafy tree on the left with a wooden sign hanging
## from its branch, a pink blossom tree on the right, a stump with a sleeping
## cat, butterflies, a bluebird on the mailbox, a picket fence, soft hills with
## two far cottages, and big soft clouds. Everything is a built-in primitive,
## coloured only from `palette.gd` tokens and the two derivations the art bible
## allows, so it can be swapped for real props later without touching a colour
## or a rule.
##
## ## Depth
##
## Three layers, so the picture has air in it: FOREGROUND (two bush corners at
## the bottom edges, the stump and cat, the front beds), MIDGROUND (the pair,
## the fence, the near trees, the mailbox), BACKGROUND (the house, the far
## trees, the hills, the cottages, the clouds).
##
## ## Ambient motion
##
## `tick(delta)` -- called from `_process()` -- sways every canopy and flower
## head a couple of degrees on a slow sine with a per-instance phase, drifts
## the clouds, flutters the butterflies round a small figure-eight, and lets
## the cat breathe. A few dozen transforms a frame, no physics, no particles.
## Tests call `tick()` by hand; the headless runner never ticks `_process()`.
##
## ## Budget
##
## Mobile renderer, one `DirectionalLight3D` (owned by `main.tscn`, not this
## file), no shadows, no GI, no post-processing. Spheres are 16x8, small ones
## 10x5, petals 8x4 -- `test_menu_wow.gd` asserts the triangle cap.
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

## How far a canopy or a flower head leans, and how slowly. Two to three
## degrees: a breeze, not a gale.
const SWAY_DEG: float = 2.5
const SWAY_PERIOD_SEC: float = 3.4
const CLOUD_DRIFT_M_PER_SEC: float = 0.12
const BUTTERFLY_PERIOD_SEC: float = 5.0
const BUTTERFLY_REACH := Vector3(0.45, 0.18, 0.25)
const CAT_BREATH_PERIOD_SEC: float = 3.0

## Ordinary trees: position, foliage radius, tint index. Behind the fence and
## along the sides; the two big framing trees are separate below.
const TREE_SPOTS: Array = [
	[Vector3(-2.6, 0.0, -7.6), 0.80, 1],
	[Vector3(-4.8, 0.0, -6.0), 0.95, 0],
	[Vector3(-7.6, 0.0, -8.2), 0.85, 2],
	[Vector3(5.6, 0.0, -8.8), 0.78, 0],
	[Vector3(8.6, 0.0, -6.4), 0.88, 1],
	[Vector3(-8.8, 0.0, -4.6), 0.72, 1],
	[Vector3(0.4, 0.0, -9.6), 0.70, 2],
	[Vector3(11.0, 0.0, -9.4), 0.90, 0],
]

## The big leafy tree, front-left, with the sign; and the blossom trees, right.
const HERO_TREE_POSITION := Vector3(-4.6, 0.0, -2.4)
const HERO_TREE_RADIUS: float = 1.4
const BLOSSOM_SPOTS: Array = [
	[Vector3(5.4, 0.0, -3.5), 1.18],
	[Vector3(7.9, 0.0, -5.4), 1.0],
]

## Flowerbeds: centre, size (x, z), flower count.
const FLOWERBED_SPOTS: Array = [
	[Vector3(1.25, 0.0, -4.3), Vector2(1.2, 0.5), 8],
	[Vector3(3.85, 0.0, -4.3), Vector2(1.0, 0.5), 7],
	[Vector3(-1.75, 0.0, 0.55), Vector2(1.3, 0.6), 9],
	[Vector3(2.6, 0.0, 0.55), Vector2(1.1, 0.55), 7],
	[Vector3(-3.4, 0.0, -3.3), Vector2(1.4, 0.6), 8],
	[Vector3(4.4, 0.0, -1.9), Vector2(1.0, 0.5), 6],
	[Vector3(-1.2, 0.0, -3.6), Vector2(1.0, 0.5), 6],
]

const CLOUD_SPOTS: Array = [
	# position, scale
	[Vector3(-7.4, 4.6, -13.0), 1.25],
	[Vector3(-2.2, 5.6, -15.0), 1.0],
	[Vector3(4.6, 4.9, -14.0), 1.35],
	[Vector3(9.8, 6.2, -17.0), 0.95],
	[Vector3(-13.5, 6.4, -18.0), 1.1],
	[Vector3(1.6, 7.2, -20.0), 0.8],
]

## Butterflies: home point and colour index.
const BUTTERFLY_SPOTS: Array = [
	[Vector3(-2.1, 1.15, -1.5), 0],
	[Vector3(3.3, 1.35, -2.3), 1],
	[Vector3(0.7, 1.7, -3.6), 2],
]

## Foreground bushes that tuck the bottom corners in.
const CORNER_BUSHES: Array = [
	[Vector3(-2.7, 0.0, 1.95), 0.62],
	[Vector3(2.75, 0.0, 2.0), 0.58],
	[Vector3(-3.3, 0.0, 1.25), 0.5],
	[Vector3(3.4, 0.0, 1.3), 0.48],
]

var _built: bool = false
var _materials: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## What was built, by kind, so a test can ask rather than count nodes by name.
var _counts: Dictionary = {}

## Ambient motion registers. Each entry: [node, phase, amplitude scale].
var _swaying: Array = []
var _clouds: Array = []
var _butterflies: Array = []
var _cat_chest: Node3D = null
var _cat_chest_scale: Vector3 = Vector3.ONE
var _time: float = 0.0
var _ambient_enabled: bool = true


func _ready() -> void:
	build()


func _process(delta: float) -> void:
	tick(delta)


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
	_build_far_cottages()
	_build_house()
	_build_path()
	_build_trees()
	_build_hero_tree()
	_build_blossom_trees()
	_build_hedge()
	_build_flowerbeds()
	_build_fence()
	_build_clouds()
	_build_stump_and_cat()
	_build_butterflies()
	_build_toys()
	_build_corner_bushes()


## How many of each thing the garden holds: "trees", "flowers", "windows",
## "doors", "clouds", "stones", "hills", "fencePosts", "toys", "suns",
## "butterflies", "cats", "signs", "birds", "farCottages", "bushes".
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
# Ambient motion
# ---------------------------------------------------------------------------

## Advances the breeze by `delta` seconds. Public so a test can move time by
## hand and see the garden change; `_process()` just calls it.
func tick(delta: float) -> void:
	if not _ambient_enabled or not _built:
		return
	_time += maxf(delta, 0.0)
	var w: float = TAU / SWAY_PERIOD_SEC
	for entry: Array in _swaying:
		var node: Node3D = entry[0]
		var phase: float = float(entry[1])
		var amount: float = float(entry[2])
		var lean: float = deg_to_rad(SWAY_DEG) * amount
		node.rotation = Vector3(
				lean * 0.5 * sin(_time * w * 0.8 + phase * 1.7),
				node.rotation.y,
				lean * sin(_time * w + phase))
	for entry: Array in _clouds:
		var cloud: Node3D = entry[0]
		var home: Vector3 = entry[1]
		var pace: float = float(entry[2])
		var x: float = home.x + fmod(_time * CLOUD_DRIFT_M_PER_SEC * pace, 30.0)
		# Off the right edge, back in from the left: the sky never empties.
		if x > home.x + 15.0:
			x -= 30.0
		cloud.position = Vector3(x, home.y + 0.08 * sin(_time * 0.3 + pace), home.z)
	var bw: float = TAU / BUTTERFLY_PERIOD_SEC
	for entry: Array in _butterflies:
		var fly: Node3D = entry[0]
		var home: Vector3 = entry[1]
		var phase: float = float(entry[2])
		var t: float = _time * bw + phase
		# A lemniscate in x/z with a gentle bob in y.
		fly.position = home + Vector3(
				BUTTERFLY_REACH.x * sin(t),
				BUTTERFLY_REACH.y * sin(t * 2.0 + 0.5),
				BUTTERFLY_REACH.z * sin(t * 2.0))
		var heading := Vector3(cos(t) * BUTTERFLY_REACH.x, 0.0, 2.0 * cos(t * 2.0) * BUTTERFLY_REACH.z)
		if heading.length_squared() > 0.0001:
			fly.rotation.y = atan2(-heading.x, -heading.z)
		var flap: float = deg_to_rad(48.0) * sin(_time * 14.0 + phase)
		var left: Node3D = fly.get_node_or_null("WingLeft") as Node3D
		var right: Node3D = fly.get_node_or_null("WingRight") as Node3D
		if left != null:
			left.rotation.z = flap
		if right != null:
			right.rotation.z = -flap
	if _cat_chest != null:
		var breath: float = 1.0 + 0.04 * sin(_time * TAU / CAT_BREATH_PERIOD_SEC)
		_cat_chest.scale = _cat_chest_scale * Vector3(1.0, breath, 1.0)


func set_ambient_enabled(enabled: bool) -> void:
	_ambient_enabled = enabled


func is_ambient_enabled() -> bool:
	return _ambient_enabled


## Seconds of breeze so far. A test asserts this moves, and that things moved.
func get_ambient_time() -> float:
	return _time


## How many things move each frame: canopies + flower heads + bushes + the
## sign, clouds, butterflies, and the cat's chest.
func count_moving_parts() -> int:
	build()
	return _swaying.size() + _clouds.size() + _butterflies.size() + (1 if _cat_chest != null else 0)


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


## Warmer than the peach it used to be: the concept's roof is rose tiles.
static func roof() -> Color:
	return Palette.deep(Palette.SOFT_PINK)


static func door() -> Color:
	return Palette.STAR_EARNED


static func heart() -> Color:
	return Palette.deep(Palette.SOFT_PINK)


static func window_pane() -> Color:
	return Palette.light(Palette.DUSTY_BLUE)


static func leaf(index: int) -> Color:
	match index:
		0:
			return Palette.deep(Palette.MINT)
		1:
			return Palette.MINT.lerp(Palette.deep(Palette.MINT), 0.5)
		_:
			return Palette.MINT.lerp(Palette.deep(Palette.MINT), 0.78)


static func blossom(index: int) -> Color:
	match index:
		0:
			return Palette.SOFT_PINK
		1:
			return Palette.light(Palette.SOFT_PINK)
		_:
			return Palette.SOFT_PINK.lerp(Palette.deep(Palette.SOFT_PINK), 0.5)


static func flower_colours() -> Array:
	return [Palette.STAR_EARNED, Palette.SOFT_PINK, Palette.LAVENDER,
			Palette.CREAM, Palette.light(Palette.DUSTY_BLUE), Palette.deep(Palette.SOFT_PINK)]


## The three petal colours the concept plants everywhere: pink, yellow, white.
static func petal_colours() -> Array:
	return [Palette.SOFT_PINK, Palette.STAR_NEXT, Palette.CREAM]


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
# Ground, hills, far cottages
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
		[Vector3(-16.0, -1.2, -12.5), Vector3(8.0, 2.6, 5.0), Palette.MINT],
		[Vector3(18.0, -1.0, -13.0), Vector3(9.0, 2.8, 5.5), Palette.MINT],
	]
	for spot: Array in spots:
		_place(hills, "Hill", _ball(1.0), spot[2], spot[0], Vector3.ZERO, spot[1])
		_bump("hills")


## Tiny cottages on the hills, so there is a village past the garden and the
## world does not end at the fence.
func _build_far_cottages() -> void:
	var village := Node3D.new()
	village.name = "FarCottages"
	add_child(village)
	var spots: Array = [
		[Vector3(-9.6, 1.55, -14.6), 0.9, 18.0, Palette.light(Palette.PEACH)],
		[Vector3(10.4, 1.9, -16.2), 1.0, -22.0, Palette.light(Palette.LAVENDER)],
		[Vector3(-12.2, 1.2, -13.6), 0.7, 30.0, Palette.CREAM],
	]
	for i: int in range(spots.size()):
		var spot: Array = spots[i]
		var cottage := Node3D.new()
		cottage.name = "Cottage%d" % i
		cottage.position = spot[0]
		cottage.rotation_degrees = Vector3(0.0, float(spot[2]), 0.0)
		village.add_child(cottage)
		var s: float = float(spot[1])
		var body := BoxMesh.new()
		body.size = Vector3(1.0, 0.7, 0.8) * s
		_place(cottage, "Walls", body, spot[3], Vector3(0.0, 0.35 * s, 0.0))
		var top := PrismMesh.new()
		top.size = Vector3(1.15, 0.45, 0.95) * s
		_place(cottage, "Roof", top, roof(), Vector3(0.0, 0.92 * s, 0.0))
		var door_mesh := BoxMesh.new()
		door_mesh.size = Vector3(0.2, 0.34, 0.04) * s
		_place(cottage, "Door", door_mesh, door(), Vector3(0.0, 0.17 * s, 0.41 * s))
		_bump("farCottages")


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

	# Round bushes tuck the corners into the ground, with roses on them like
	# the concept's climbing rose.
	for side: float in [-1.0, 1.0]:
		var bush := _place(house, "Bush", _sphere(0.46), leaf(1),
				Vector3(side * (HOUSE_SIZE.x * 0.5 + 0.28), 0.30, front_z - 0.15),
				Vector3.ZERO, Vector3(1.0, 0.75, 1.0))
		bush.name = "BushLeft" if side < 0.0 else "BushRight"
		_bump("bushes")
		for i: int in range(3):
			_place(bush, "Rose", _petal(0.11), petal_colours()[i % 3],
					Vector3(-0.25 + 0.25 * float(i), 0.22 + 0.1 * float(i % 2), 0.32))


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

	# The dark doorway behind the leaf, seen only once it swings open.
	var inside := BoxMesh.new()
	inside.size = Vector3(DOOR_SIZE.x - 0.02, DOOR_SIZE.y - arch_radius, 0.02)
	_place(frame, "Doorway", inside, Palette.INK.lerp(Palette.PEACH, 0.35),
			Vector3(0.0, (DOOR_SIZE.y - arch_radius) * 0.5, lift + 0.012))
	_place(frame, "DoorwayArch", _disc(arch_radius - 0.01, 0.02), Palette.INK.lerp(Palette.PEACH, 0.35),
			Vector3(0.0, DOOR_SIZE.y - arch_radius, lift + 0.014), Vector3(90.0, 0.0, 0.0))

	# The leaf itself hangs on a HINGE pivot at its left edge, so the departure
	# can swing it open (`menu_departure.gd`) by rotating one node.
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.position = Vector3(-DOOR_SIZE.x * 0.5, 0.0, lift + 0.06)
	frame.add_child(hinge)
	var half: float = DOOR_SIZE.x * 0.5
	var slab := BoxMesh.new()
	slab.size = Vector3(DOOR_SIZE.x, DOOR_SIZE.y - arch_radius, 0.08)
	_place(hinge, "Slab", slab, door(), Vector3(half, (DOOR_SIZE.y - arch_radius) * 0.5, 0.0))
	# A hair forward of the slab, so the two yellow faces never share a plane.
	_place(hinge, "Arch", _disc(arch_radius, 0.08), door(),
			Vector3(half, DOOR_SIZE.y - arch_radius, 0.004), Vector3(90.0, 0.0, 0.0))
	# A little round window in the door, a heart under it, and a knob.
	_place(hinge, "Peep", _disc(0.11, 0.03), window_pane(),
			Vector3(half, DOOR_SIZE.y - arch_radius - 0.02, 0.06), Vector3(90.0, 0.0, 0.0))
	_build_heart(hinge, Vector3(half, DOOR_SIZE.y * 0.5, 0.07), 0.07, heart())
	_place(hinge, "Knob", _sphere(0.045), Palette.INK.lerp(Palette.PEACH, 0.5),
			Vector3(DOOR_SIZE.x * 0.82, DOOR_SIZE.y * 0.42, 0.07))

	var step := BoxMesh.new()
	step.size = Vector3(DOOR_SIZE.x + 0.5, 0.09, 0.42)
	_place(frame, "Step", step, Palette.deep(Palette.CREAM), Vector3(0.0, 0.045, 0.24))
	var mat := BoxMesh.new()
	mat.size = Vector3(0.62, 0.02, 0.34)
	_place(frame, "Mat", mat, Palette.PEACH, Vector3(0.0, 0.10, 0.22))
	_bump("doors")


## A heart: two round lobes over a diamond, flat against +Z.
func _build_heart(parent: Node3D, at: Vector3, size: float, colour: Color) -> void:
	var node := Node3D.new()
	node.name = "Heart"
	node.position = at
	parent.add_child(node)
	for side: float in [-1.0, 1.0]:
		_place(node, "Lobe", _petal(size * 0.55), colour,
				Vector3(side * size * 0.5, size * 0.3, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.45))
	var diamond := BoxMesh.new()
	diamond.size = Vector3(size * 1.05, size * 1.05, size * 0.45)
	_place(node, "Point", diamond, colour, Vector3(0.0, -size * 0.12, 0.0), Vector3(0.0, 0.0, 45.0))


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
	box.size = Vector3(side + 0.24, 0.17, 0.22)
	_place(window, "Box", box, wood(), Vector3(0.0, -side * 0.5 - 0.15, 0.12))
	_place(window, "BoxLeaves", _sphere(0.1), leaf(1), Vector3(0.0, -side * 0.5 - 0.04, 0.16),
			Vector3.ZERO, Vector3(3.6, 0.7, 1.0))
	for i: int in range(4):
		var x: float = (float(i) - 1.5) * side * 0.3
		_place(window, "BoxFlower", _petal(0.065), petal_colours()[i % 3],
				Vector3(x, -side * 0.5 + 0.02 + 0.03 * float(i % 2), 0.2))
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
	var bar_v := BoxMesh.new()
	bar_v.size = Vector3(0.04, 0.44, 0.02)
	_place(window, "MullionV", bar_v, Palette.CREAM, Vector3(0.0, 0.0, 0.075))
	var bar_h := BoxMesh.new()
	bar_h.size = Vector3(0.44, 0.04, 0.02)
	_place(window, "MullionH", bar_h, Palette.CREAM, Vector3(0.0, 0.0, 0.075))
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
		var p: Vector3 = path_point(t)
		var wobble: float = _rng.randf_range(-0.14, 0.14)
		p.x += wobble
		var radius: float = 0.27 + _rng.randf_range(-0.03, 0.05)
		var colour: Color = Palette.deep(Palette.CREAM) if i % 2 == 0 else Palette.light(Palette.PEACH)
		var stone := _place(path, "Stone", _disc(radius, 0.035), colour,
				Vector3(p.x, 0.018, p.z), Vector3.ZERO, Vector3(1.0, 1.0, 0.82))
		stone.name = "Stone%d" % i
		_bump("stones")


## The point on the path `t` of the way from the doorstep (0) to the camera (1).
## `menu_departure.gd` walks the pair back up it.
static func path_point(t: float) -> Vector3:
	return PATH_START.bezier_interpolate(PATH_BEND, PATH_BEND, PATH_END, clampf(t, 0.0, 1.0))


## Where the front door is, in garden space, and the point just outside it.
static func door_position() -> Vector3:
	return HOUSE_POSITION + Vector3(0.0, 0.0, HOUSE_SIZE.z * 0.5)


static func doorstep_position() -> Vector3:
	return door_position() + Vector3(0.0, 0.0, 0.6)


## The hinge node of the front door, or null before `build()`. Rotating it
## about Y swings the door open (negative = inward, away from the camera).
func get_door_hinge() -> Node3D:
	return get_node_or_null("House/Door/Hinge") as Node3D


# ---------------------------------------------------------------------------
# Trees, hedge, flowers, fence
# ---------------------------------------------------------------------------

func _build_trees() -> void:
	var trees := Node3D.new()
	trees.name = "Trees"
	add_child(trees)
	for i: int in range(TREE_SPOTS.size()):
		var spot: Array = TREE_SPOTS[i]
		_build_leafy_tree(trees, "Tree%d" % i, spot[0], float(spot[1]), int(spot[2]), i)
		_bump("trees")


## A round tree: trunk, then a canopy pivot at the trunk's top carrying four
## overlapping spheres in two close shades, so the crown has some form to it
## rather than reading as one ball. The pivot is what sways.
func _build_leafy_tree(parent: Node3D, tree_name: String, at: Vector3, radius: float,
		tint_index: int, phase_seed: int) -> Node3D:
	var tree := Node3D.new()
	tree.name = tree_name
	tree.position = at
	parent.add_child(tree)
	var trunk_height: float = radius * 1.15
	_place(tree, "Trunk", _cylinder(radius * 0.16, trunk_height), wood(),
			Vector3(0.0, trunk_height * 0.5, 0.0))
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	canopy.position = Vector3(0.0, trunk_height, 0.0)
	tree.add_child(canopy)
	var tint: Color = leaf(tint_index)
	var lighter: Color = leaf((tint_index + 1) % 3)
	var crown_y: float = radius * 0.75
	_place(canopy, "Crown", _sphere(radius), tint, Vector3(0.0, crown_y, 0.0))
	_place(canopy, "CrownTop", _sphere(radius * 0.66), lighter,
			Vector3(radius * 0.15, crown_y + radius * 0.6, -radius * 0.1))
	_place(canopy, "CrownSide", _sphere(radius * 0.58), tint,
			Vector3(-radius * 0.62, crown_y + radius * 0.18, radius * 0.25))
	_place(canopy, "CrownFar", _sphere(radius * 0.52), lighter,
			Vector3(radius * 0.6, crown_y + radius * 0.1, radius * 0.3))
	# Fruit. Three bright dots on the front of the crown -- a toy tree.
	for f: int in range(3):
		var angle: float = deg_to_rad(-40.0 + 40.0 * float(f))
		var fruit_pos := Vector3(sin(angle) * radius * 0.85,
				crown_y + (0.3 - 0.35 * float(f % 2)) * radius, cos(angle) * radius * 0.85)
		var fruit_colour: Color = Palette.STAR_EARNED if phase_seed % 2 == 0 else Palette.deep(Palette.SOFT_PINK)
		_place(canopy, "Fruit", _petal(radius * 0.11), fruit_colour, fruit_pos)
	_register_sway(canopy, float(phase_seed) * 1.3, 1.0)
	return tree


## The big tree at the front left, with the wooden sign hanging from its branch.
func _build_hero_tree() -> void:
	var trees: Node3D = get_node_or_null("Trees") as Node3D
	if trees == null:
		return
	var tree := Node3D.new()
	tree.name = "HeroTree"
	tree.position = HERO_TREE_POSITION
	trees.add_child(tree)
	var radius: float = HERO_TREE_RADIUS
	var trunk_height: float = 2.1
	_place(tree, "Trunk", _cylinder(0.24, trunk_height), wood(), Vector3(0.0, trunk_height * 0.5, 0.0))
	_place(tree, "Root", _sphere(0.36), wood(), Vector3(0.0, 0.1, 0.0), Vector3.ZERO, Vector3(1.4, 0.5, 1.4))
	# The branch the sign hangs from, reaching toward the path.
	var branch_length: float = 1.7
	_place(tree, "Branch", _cylinder(0.075, branch_length), wood(),
			Vector3(branch_length * 0.5, 1.95, 0.15), Vector3(0.0, 0.0, -84.0))
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	canopy.position = Vector3(0.0, trunk_height - 0.1, 0.0)
	tree.add_child(canopy)
	var puffs: Array = [
		[Vector3(0.0, radius * 0.7, 0.0), radius, 0],
		[Vector3(radius * 0.75, radius * 0.95, -0.2), radius * 0.7, 1],
		[Vector3(-radius * 0.8, radius * 0.6, 0.1), radius * 0.72, 2],
		[Vector3(0.2, radius * 1.45, -0.1), radius * 0.62, 1],
		[Vector3(0.5, radius * 0.5, radius * 0.6), radius * 0.6, 0],
		[Vector3(-0.4, radius * 1.1, radius * 0.5), radius * 0.55, 2],
	]
	for i: int in range(puffs.size()):
		var puff: Array = puffs[i]
		_place(canopy, "Puff%d" % i, _sphere(float(puff[1])), leaf(int(puff[2])), puff[0])
	_register_sway(canopy, 0.4, 0.8)
	_bump("trees")

	# The sign: two ropes and a wooden board, hanging below the branch's end.
	var sign := Node3D.new()
	sign.name = "Sign"
	sign.position = Vector3(branch_length * 0.72, 1.35, 0.2)
	tree.add_child(sign)
	for side: float in [-1.0, 1.0]:
		_place(sign, "Rope", _cylinder(0.015, 0.55), Palette.deep(Palette.CREAM),
				Vector3(side * 0.34, 0.5, 0.0))
	var board := BoxMesh.new()
	board.size = Vector3(0.96, 0.52, 0.06)
	_place(sign, "Board", board, wood(), Vector3(0.0, 0.0, 0.0))
	var trim := BoxMesh.new()
	trim.size = Vector3(0.9, 0.46, 0.02)
	_place(sign, "Trim", trim, Palette.INK.lerp(Palette.PEACH, 0.55), Vector3(0.0, 0.0, 0.03))
	var words := Label3D.new()
	words.name = "Words"
	words.text = "Welcome!"
	words.font_size = 64
	words.pixel_size = 0.004
	words.modulate = Palette.CREAM
	words.outline_size = 0
	words.position = Vector3(0.0, 0.04, 0.045)
	sign.add_child(words)
	_build_heart(sign, Vector3(0.0, -0.15, 0.045), 0.045, Palette.light(Palette.SOFT_PINK))
	_register_sway(sign, 2.2, 1.4)
	_bump("signs")


## The blossom trees: the same build as a leafy tree, in pinks, with a scatter
## of deeper pink dots for flowers.
func _build_blossom_trees() -> void:
	var trees: Node3D = get_node_or_null("Trees") as Node3D
	if trees == null:
		return
	for i: int in range(BLOSSOM_SPOTS.size()):
		var spot: Array = BLOSSOM_SPOTS[i]
		var at: Vector3 = spot[0]
		var radius: float = float(spot[1])
		var tree := Node3D.new()
		tree.name = "BlossomTree%d" % i
		tree.position = at
		trees.add_child(tree)
		var trunk_height: float = radius * 1.35
		_place(tree, "Trunk", _cylinder(radius * 0.15, trunk_height), wood(),
				Vector3(0.0, trunk_height * 0.5, 0.0))
		var canopy := Node3D.new()
		canopy.name = "Canopy"
		canopy.position = Vector3(0.0, trunk_height - 0.1, 0.0)
		tree.add_child(canopy)
		var crown_y: float = radius * 0.7
		_place(canopy, "Crown", _sphere(radius), blossom(0), Vector3(0.0, crown_y, 0.0))
		_place(canopy, "CrownTop", _sphere(radius * 0.68), blossom(1),
				Vector3(-radius * 0.2, crown_y + radius * 0.6, 0.0))
		_place(canopy, "CrownSide", _sphere(radius * 0.6), blossom(2),
				Vector3(radius * 0.65, crown_y + radius * 0.15, radius * 0.2))
		_place(canopy, "CrownBack", _sphere(radius * 0.55), blossom(1),
				Vector3(-radius * 0.6, crown_y + radius * 0.05, -radius * 0.3))
		for f: int in range(6):
			var angle: float = deg_to_rad(-70.0 + 28.0 * float(f))
			var dot := Vector3(sin(angle) * radius * 0.88,
					crown_y + (0.35 - 0.3 * float(f % 3)) * radius, cos(angle) * radius * 0.88)
			_place(canopy, "Blossom", _petal(radius * 0.09), blossom(2) if f % 2 == 0 else Palette.CREAM, dot)
		_register_sway(canopy, 3.1 + float(i), 1.1)
		_bump("trees")


## Low round bushes along the far side of the fence, between the trees, so the
## fence stands against green rather than against the lawn.
func _build_hedge() -> void:
	var hedge := Node3D.new()
	hedge.name = "Hedge"
	add_child(hedge)
	var z: float = -4.75
	var spots: Array = [-8.2, -6.9, -5.4, -2.0, -0.7, 5.6, 6.8, 8.4, 9.6, 10.7]
	for i: int in range(spots.size()):
		var x: float = float(spots[i])
		var r: float = 0.42 + 0.08 * float(i % 3)
		var bush := _place(hedge, "Hedge%d" % i, _sphere(r), leaf((i + 1) % 3),
				Vector3(x, r * 0.62, z), Vector3.ZERO, Vector3(1.25, 0.8, 1.0))
		_bump("bushes")
		if i % 2 == 0:
			_place(bush, "Bloom", _petal(0.09), petal_colours()[i % 3], Vector3(0.15, 0.55, 0.55))


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
		# A low leafy mound the flowers stand out of, so the bed reads as a bed.
		_place(bed, "Greens", _sphere(0.5), leaf(1), Vector3(0.0, 0.02, 0.0),
				Vector3.ZERO, Vector3(size.x * 0.9, 0.22, size.y * 0.9))
		for i: int in range(count):
			var t: float = (float(i) + 0.5) / float(count)
			var x: float = (t - 0.5) * size.x * 0.9
			var z: float = _rng.randf_range(-0.28, 0.28) * size.y
			var height: float = _rng.randf_range(0.22, 0.38)
			var flower := Node3D.new()
			flower.name = "Flower%d" % i
			flower.position = Vector3(x, 0.06, z)
			bed.add_child(flower)
			_place(flower, "Stem", _cylinder(0.02, height), leaf(0), Vector3(0.0, height * 0.5, 0.0))
			var head := Node3D.new()
			head.name = "Head"
			head.position = Vector3(0.0, height, 0.0)
			flower.add_child(head)
			if i % 2 == 0:
				# A round-petalled flower: five petals round a yellow eye, facing
				# the camera -- the shape the concept plants everywhere.
				var petal_colour: Color = petal_colours()[(i / 2 + b) % 3]
				for p: int in range(5):
					var a: float = deg_to_rad(90.0 + 72.0 * float(p))
					_place(head, "Petal", _petal(0.055), petal_colour,
							Vector3(cos(a) * 0.075, 0.03 + sin(a) * 0.075, 0.0),
							Vector3.ZERO, Vector3(1.0, 1.0, 0.6))
				_place(head, "Eye", _petal(0.04), Palette.STAR_EARNED, Vector3(0.0, 0.03, 0.03))
			else:
				var head_colour: Color = colours[(i + b) % colours.size()]
				_place(head, "Bud", _petal(0.085), head_colour, Vector3(0.0, 0.03, 0.0))
				if head_colour != Palette.STAR_EARNED:
					_place(head, "Centre", _petal(0.035), Palette.STAR_EARNED,
							Vector3(0.0, 0.03, 0.075))
			_place(flower, "Leaf", _petal(0.055), leaf(1), Vector3(0.05, height * 0.45, 0.0),
					Vector3.ZERO, Vector3(1.4, 0.6, 0.8))
			_register_sway(flower, float(b * 7 + i) * 0.9, 1.0 + 0.4 * float(i % 2))
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
			_place(fence, "PostCap", _petal(0.065), Palette.CREAM, Vector3(x, 0.60, z))
			_bump("fencePosts")
			x += 0.46
	# Gate posts either side of the path opening, a little taller, with a
	# flower on each: the way in is marked.
	for gx: float in [0.2, 4.7]:
		var post := BoxMesh.new()
		post.size = Vector3(0.12, 0.74, 0.1)
		_place(fence, "GatePost", post, Palette.CREAM, Vector3(gx, 0.37, z))
		_place(fence, "GateCap", _sphere(0.085), Palette.CREAM, Vector3(gx, 0.78, z))
		_place(fence, "GateFlower", _petal(0.06), petal_colours()[0 if gx < 1.0 else 1],
				Vector3(gx + (0.09 if gx < 1.0 else -0.09), 0.62, z + 0.08))


# ---------------------------------------------------------------------------
# Clouds, stump and cat, butterflies, toys, corner bushes
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
		_place(cloud, "PuffA", _ball(1.0), Palette.CREAM, Vector3.ZERO,
				Vector3.ZERO, Vector3(1.25, 0.72, 1.0) * s, true)
		_place(cloud, "PuffB", _ball(1.0), Palette.CREAM, Vector3(-1.15, -0.12, 0.0) * s,
				Vector3.ZERO, Vector3(0.85, 0.55, 0.85) * s, true)
		_place(cloud, "PuffC", _ball(1.0), Palette.CREAM, Vector3(1.1, -0.1, 0.0) * s,
				Vector3.ZERO, Vector3(0.78, 0.52, 0.8) * s, true)
		_place(cloud, "PuffD", _ball(1.0), Palette.CREAM, Vector3(0.2, 0.42, 0.1) * s,
				Vector3.ZERO, Vector3(0.7, 0.5, 0.7) * s, true)
		_clouds.append([cloud, at, 0.7 + 0.15 * float(i % 4)])
		_bump("clouds")


## A tree stump, front left, with a cat curled asleep on it.
func _build_stump_and_cat() -> void:
	var stump := Node3D.new()
	stump.name = "Stump"
	stump.position = Vector3(-2.5, 0.0, -0.55)
	add_child(stump)
	_place(stump, "Trunk", _cylinder(0.3, 0.42), wood(), Vector3(0.0, 0.21, 0.0))
	_place(stump, "Top", _disc(0.3, 0.03), Palette.deep(Palette.PEACH), Vector3(0.0, 0.43, 0.0))
	_place(stump, "Ring", _disc(0.19, 0.01), Palette.light(Palette.PEACH), Vector3(0.0, 0.45, 0.0))
	_place(stump, "RootA", _sphere(0.12), wood(), Vector3(0.28, 0.05, 0.1), Vector3.ZERO, Vector3(1.4, 0.5, 1.0))
	_place(stump, "RootB", _sphere(0.11), wood(), Vector3(-0.22, 0.05, 0.2), Vector3.ZERO, Vector3(1.2, 0.5, 1.2))

	var cat := Node3D.new()
	cat.name = "Cat"
	cat.position = Vector3(0.0, 0.46, 0.0)
	cat.rotation_degrees = Vector3(0.0, 25.0, 0.0)
	stump.add_child(cat)
	var fur: Color = Palette.light(Palette.PEACH)
	var patch: Color = Palette.STAR_GHOST
	# The body is the chest that breathes.
	var body := _place(cat, "Body", _sphere(0.17), fur, Vector3(0.0, 0.1, 0.0),
			Vector3.ZERO, Vector3(1.35, 0.72, 1.0))
	_cat_chest = body
	_cat_chest_scale = body.scale
	_place(cat, "Patch", _sphere(0.09), patch, Vector3(-0.1, 0.17, 0.02), Vector3.ZERO, Vector3(1.2, 0.5, 1.0))
	var head := _place(cat, "Head", _sphere(0.12), fur, Vector3(0.19, 0.13, 0.08))
	for side: float in [-1.0, 1.0]:
		var ear := _place(head, "Ear", _sphere(0.045), fur, Vector3(0.03, 0.1, side * 0.07),
				Vector3.ZERO, Vector3(0.7, 1.3, 0.7))
		_place(ear, "Inner", _sphere(0.028), Palette.SOFT_PINK, Vector3(0.01, 0.0, 0.0))
		# Closed eyes: two little ink arcs on the cheeks.
		var lid := BoxMesh.new()
		lid.size = Vector3(0.012, 0.01, 0.045)
		_place(head, "Eye", lid, Palette.INK, Vector3(0.1, 0.02, side * 0.05), Vector3(0.0, 0.0, 10.0))
	_place(head, "Nose", _sphere(0.016), Palette.SOFT_PINK, Vector3(0.12, -0.01, 0.0))
	_place(cat, "Tail", _sphere(0.05), patch, Vector3(-0.2, 0.06, 0.12), Vector3.ZERO, Vector3(2.6, 0.7, 0.9))
	_place(cat, "PawA", _sphere(0.04), fur, Vector3(0.15, 0.0, -0.1))
	_place(cat, "PawB", _sphere(0.04), fur, Vector3(0.1, 0.0, -0.13))
	_bump("cats")


func _build_butterflies() -> void:
	var group := Node3D.new()
	group.name = "Butterflies"
	add_child(group)
	var colours: Array = [Palette.STAR_EARNED, Palette.SOFT_PINK, Palette.LAVENDER]
	for i: int in range(BUTTERFLY_SPOTS.size()):
		var spot: Array = BUTTERFLY_SPOTS[i]
		var home: Vector3 = spot[0]
		var fly := Node3D.new()
		fly.name = "Butterfly%d" % i
		fly.position = home
		group.add_child(fly)
		var colour: Color = colours[int(spot[1]) % colours.size()]
		_place(fly, "Body", _petal(0.02), Palette.INK.lerp(Palette.PEACH, 0.5), Vector3.ZERO,
				Vector3.ZERO, Vector3(0.6, 0.6, 2.2))
		for side: float in [-1.0, 1.0]:
			var wing := Node3D.new()
			wing.name = "WingLeft" if side < 0.0 else "WingRight"
			fly.add_child(wing)
			_place(wing, "Fore", _petal(0.06), colour, Vector3(side * 0.06, 0.0, -0.015),
					Vector3.ZERO, Vector3(1.0, 0.35, 0.8))
			_place(wing, "Hind", _petal(0.045), colour, Vector3(side * 0.045, 0.0, 0.035),
					Vector3.ZERO, Vector3(1.0, 0.35, 0.8))
		_butterflies.append([fly, home, float(i) * 2.1])
		_bump("butterflies")


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
		if i == 0:
			# The beach ball by Bunny gets its stripes.
			_place(node, "Stripe", _disc(0.135, 0.05), Palette.CREAM, Vector3.ZERO, Vector3(0.0, 0.0, 90.0))
			_place(node, "Stripe2", _disc(0.135, 0.05), Palette.light(Palette.DUSTY_BLUE),
					Vector3.ZERO, Vector3(0.0, 90.0, 90.0))
		_bump("toys")

	# The mailbox by the path: post, a warm pink box with a cream heart, a
	# sunny flag, and the bluebird perched on top.
	var mailbox := Node3D.new()
	mailbox.name = "Mailbox"
	mailbox.position = Vector3(3.7, 0.0, -2.9)
	toys.add_child(mailbox)
	_place(mailbox, "Post", _cylinder(0.045, 0.72), wood(), Vector3(0.0, 0.36, 0.0))
	var box := BoxMesh.new()
	box.size = Vector3(0.28, 0.24, 0.38)
	_place(mailbox, "Box", box, heart(), Vector3(0.0, 0.83, 0.0))
	_place(mailbox, "Lid", _disc(0.14, 0.38), heart(), Vector3(0.0, 0.95, 0.0), Vector3(90.0, 0.0, 0.0))
	_build_heart(mailbox, Vector3(0.0, 0.84, 0.2), 0.055, Palette.CREAM)
	var flag := BoxMesh.new()
	flag.size = Vector3(0.03, 0.16, 0.09)
	_place(mailbox, "Flag", flag, Palette.STAR_EARNED, Vector3(0.16, 1.02, -0.1))
	_build_bird(mailbox, Vector3(-0.02, 1.09, 0.02))
	_bump("toys")

	# Bunny's teddy, sat on the grass beside him.
	var teddy := Node3D.new()
	teddy.name = "Teddy"
	teddy.position = Vector3(1.0, 0.0, -0.05)
	teddy.rotation_degrees = Vector3(0.0, 200.0, 0.0)
	toys.add_child(teddy)
	var fur: Color = Palette.INK.lerp(Palette.PEACH, 0.6)
	_place(teddy, "Body", _sphere(0.1), fur, Vector3(0.0, 0.1, 0.0), Vector3.ZERO, Vector3(1.0, 1.1, 0.9))
	_place(teddy, "Head", _sphere(0.085), fur, Vector3(0.0, 0.26, 0.0))
	_place(teddy, "Muzzle", _petal(0.04), Palette.PEACH, Vector3(0.0, 0.24, -0.07))
	for side: float in [-1.0, 1.0]:
		_place(teddy, "Ear", _petal(0.035), fur, Vector3(side * 0.07, 0.33, 0.0))
		_place(teddy, "Arm", _petal(0.035), fur, Vector3(side * 0.1, 0.12, -0.02))
		_place(teddy, "Leg", _petal(0.04), fur, Vector3(side * 0.07, 0.03, -0.06))
		_place(teddy, "Eye", _petal(0.012), Palette.INK, Vector3(side * 0.03, 0.28, -0.08))
	_place(teddy, "Bow", _petal(0.03), Palette.light(Palette.DUSTY_BLUE), Vector3(0.0, 0.18, -0.08),
			Vector3.ZERO, Vector3(1.8, 0.8, 0.8))
	_bump("toys")


## A little bluebird: body, head, beak, tail, wing. Perched, facing the path.
func _build_bird(parent: Node3D, at: Vector3) -> void:
	var bird := Node3D.new()
	bird.name = "Bird"
	bird.position = at
	bird.rotation_degrees = Vector3(0.0, -40.0, 0.0)
	parent.add_child(bird)
	var blue: Color = Palette.deep(Palette.DUSTY_BLUE)
	_place(bird, "Body", _sphere(0.07), blue, Vector3(0.0, 0.06, 0.0), Vector3.ZERO, Vector3(1.0, 0.9, 1.3))
	_place(bird, "Belly", _sphere(0.05), Palette.light(Palette.DUSTY_BLUE), Vector3(0.0, 0.04, -0.03))
	_place(bird, "Head", _sphere(0.05), blue, Vector3(0.0, 0.13, -0.05))
	_place(bird, "Beak", _petal(0.02), Palette.STAR_EARNED, Vector3(0.0, 0.12, -0.1),
			Vector3.ZERO, Vector3(0.8, 0.6, 1.6))
	_place(bird, "Eye", _petal(0.01), Palette.INK, Vector3(0.035, 0.145, -0.07))
	_place(bird, "Wing", _sphere(0.045), Palette.DUSTY_BLUE, Vector3(0.05, 0.07, 0.01),
			Vector3.ZERO, Vector3(0.5, 0.7, 1.3))
	_place(bird, "Tail", _petal(0.03), blue, Vector3(0.0, 0.07, 0.1), Vector3.ZERO, Vector3(0.8, 0.4, 2.0))
	_bump("birds")


## Bushes at the bottom corners of the frame, nearest the camera, so the
## garden has a soft foreground edge either side of the button row.
func _build_corner_bushes() -> void:
	var group := Node3D.new()
	group.name = "CornerBushes"
	add_child(group)
	for i: int in range(CORNER_BUSHES.size()):
		var spot: Array = CORNER_BUSHES[i]
		var at: Vector3 = spot[0]
		var r: float = float(spot[1])
		var bush := _place(group, "CornerBush%d" % i, _sphere(r), leaf(i % 3),
				Vector3(at.x, r * 0.55, at.z), Vector3.ZERO, Vector3(1.3, 0.85, 1.0))
		_place(bush, "Top", _sphere(r * 0.65), leaf((i + 1) % 3), Vector3(r * 0.2, r * 0.5, 0.1))
		for f: int in range(3):
			_place(bush, "Bloom", _petal(0.075), petal_colours()[(f + i) % 3],
					Vector3(-r * 0.5 + r * 0.5 * float(f), r * 0.35 + 0.1 * float(f % 2), r * 0.7))
		_register_sway(bush, 5.0 + float(i), 0.5)
		_bump("bushes")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _register_sway(node: Node3D, phase: float, amount: float) -> void:
	_swaying.append([node, phase, amount])


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
	mesh.radial_segments = 10 if coarse else 14
	mesh.rings = 5 if coarse else 7
	return mesh


## The far, soft things -- clouds and hills -- at 12x6. They are a long way
## off and have no edge a child could ever see.
static func _ball(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


## Tinier still -- petals, eyes, blossom dots. 6x3 is 36 triangles.
static func _petal(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
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
