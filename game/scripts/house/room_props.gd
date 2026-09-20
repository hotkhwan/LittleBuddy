extends RefCounted

## The twelve pieces of furniture, as geometry.
##
## One function per taught word, because `docs/ART_BIBLE.md` §6 makes that the
## rule: **one object teaches one word, and two nouns must never share a shape.**
## The greybox shipped a blue box for `bed`, an orange box for `wardrobe` and a
## yellow cube for `toy`, which is three words and one shape.
##
## ## What each shape is for
##
## Every builder below is reduced to "the minimum recognisable form" (§6) and
## then given back exactly the detail that carries recognition, and no more:
##
##   * `bed` -- an arched headboard, a pillow and a turned-down blanket. The
##     headboard is the silhouette; the pillow is what makes it a bed and not a
##     bench.
##   * `wardrobe` -- two tall doors with a visible centre gap and two knobs. A
##     tall box alone is a fridge.
##   * `toy` -- a stacking-ring toy. `toy` is a CATEGORY word, so the shape has
##     to read as "a toy" without being any other noun the game teaches: a teddy
##     would collide with `teddy`, a ball with `ball`, a cube with `blocks`.
##   * `sink`, `bath`, `toyBox` -- built from rim walls and a floor rather than as
##     solid blocks, because §6 requires a container to have **visible interior
##     depth**. A solid-topped "sink" is a cupboard.
##   * `fridge` -- two doors split high, two handles. Mint, so a cream fridge
##     cannot vanish into a cream wall.
##   * `towel` -- folded OVER a rail. Hanging cloth is the whole recognition cue.
##   * `book` -- a spine, a cover and a visible page block. Without the page block
##     it is a tile.
##
## ## Colour
##
## Nothing here invents a colour. Every value is a §3 token or one of its two
## documented steps, and the room's own dominant/accent pair (§3 "Room moods")
## comes in through `house_layout.gd`, so recolouring a room is one edit there.
##
## ## Geometry
##
## Each builder writes into one `SurfaceTool`, centred on the prop's own origin,
## and `room.gd` commits it to a single `ArrayMesh` -- one prop, one mesh, one
## draw call, one material (§7, §10). Sizes come from `house_layout.furniture()`
## so the mesh, the collider and the baked navigation mesh cannot drift.

const Palette := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/house/prop_kit.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")

const WOOD: Color = HouseLayout.WOOD_COLOR


## Builds `target_id` into `tool`, centred on the origin. Returns false for an id
## with no authored shape, so a caller can fall back rather than draw nothing.
static func build(
	tool: SurfaceTool, target_id: String, room_id: String, size: Vector3
) -> bool:
	var dominant: Color = HouseLayout.dominant_color(room_id)
	var accent: Color = HouseLayout.accent_color(room_id)
	match target_id:
		"bed":
			_bed(tool, size, accent)
		"wardrobe":
			_wardrobe(tool, size, dominant, accent)
		"toy":
			_toy(tool, size)
		"sink":
			_sink(tool, size, accent)
		"bath":
			_bath(tool, size, dominant)
		"towel":
			_towel(tool, size)
		"fridge":
			_fridge(tool, size, accent)
		"counter":
			_counter(tool, size, accent)
		"table":
			_table(tool, size)
		"sofa":
			_sofa(tool, size, dominant, accent)
		"toyBox":
			_toy_box(tool, size)
		"book":
			_book(tool, size)
		_:
			return false
	return true


## -- Bedroom -------------------------------------------------------------------

## Runs along Z with the headboard at -Z; see `house_layout.gd`'s bed section for
## why that orientation is load-bearing and not a preference.
static func _bed(tool: SurfaceTool, size: Vector3, accent: Color) -> void:
	var half_z: float = size.z * 0.5
	for x: float in [-0.36, 0.36]:
		for z: float in [-(half_z - 0.13), half_z - 0.13]:
			Kit.cylinder(tool, Kit.at(Vector3(x, -0.15, z)), 0.042, 0.15,
					Palette.deep(WOOD), 10)
	Kit.box(tool, Kit.at(Vector3(0.0, -0.03, 0.0)),
			Vector3(size.x - 0.02, 0.11, size.z - 0.02), WOOD, Kit.PROP_BEVEL)
	# The mattress, cream, a touch smaller than the frame so the frame reads.
	Kit.box(tool, Kit.at(Vector3(0.0, 0.10, 0.0)),
			Vector3(size.x - 0.06, 0.17, size.z - 0.10), Palette.CREAM, 0.035, 2)
	# Arched headboard. This is the whole silhouette of the object at 64 px.
	Kit.extrude(tool, Kit.at(Vector3(0.0, 0.12, -(half_z + 0.005))),
			Kit.rounded_rect(Vector2(size.x, 0.72), 0.18, 4), 0.08, WOOD, Kit.PROP_BEVEL)
	Kit.extrude(tool, Kit.at(Vector3(0.0, -0.09, half_z + 0.005)),
			Kit.rounded_rect(Vector2(size.x, 0.34), 0.12, 3), 0.08, WOOD, Kit.PROP_BEVEL)
	# Pillow, where a sleeping child's head actually lands.
	Kit.box(tool, Kit.at(Vector3(0.0, 0.245, -0.52)),
			Vector3(0.56, 0.13, 0.30), Palette.CREAM, 0.055, 2)
	# Blanket, turned down over the foot half. `sleep` lays the child on top of
	# it, so it has to cover his legs and stop short of his chest.
	Kit.plate(tool, Kit.at(Vector3(0.0, 0.222, 0.22)),
			Kit.rounded_rect(Vector2(size.x - 0.04, 0.86), 0.09, 3), 0.075, accent, 0.02)
	Kit.plate(tool, Kit.at(Vector3(0.0, 0.246, -0.245)),
			Kit.rounded_rect(Vector2(size.x - 0.04, 0.20), 0.07, 3), 0.075,
			Palette.light(accent), 0.02)
	# Five cream spots on the blanket, on the same argument as the rug's (see
	# `room.gd::_build_rug`): a flat plate of one colour is bedding, a patterned
	# one is bedding somebody chose for a child. The bed is the largest single
	# field of accent colour in the nursery and it was carrying nothing.
	#
	# They sit on the FOOT half only, clear of the turned-down top: `sleep` lays
	# the child down across the middle of the mattress and a pattern under him is
	# a pattern nobody sees.
	for spot: Vector2 in [
		Vector2(-0.24, 0.02), Vector2(0.22, 0.17), Vector2(-0.06, 0.34),
		Vector2(0.26, -0.13), Vector2(-0.22, 0.47),
	]:
		Kit.plate(tool, Kit.at(Vector3(spot.x, 0.266, 0.22 + spot.y)),
				Kit.circle(0.052, 12), 0.012, Palette.CREAM, 0.004)


## The door leaf `room.gd` hangs on each wardrobe hinge: a rounded slab in the
## room's dominant colour with a cream knob, built at the hinge's origin and
## extending `side` (+1 right, -1 left) so the hinge is its outer edge.
static func wardrobe_door(tool: SurfaceTool, size: Vector3, side: float, dominant: Color) -> void:
	var width: float = WARDROBE_DOOR_WIDTH
	Kit.extrude(tool, Kit.at(Vector3(-side * width * 0.5, 0.0, 0.0)),
			Kit.rounded_rect(Vector2(width, 1.42), 0.06, 3), 0.05, dominant, 0.018)
	Kit.sphere(tool, Kit.at(Vector3(-side * (width - 0.07), 0.0, 0.05)), 0.036, Palette.CREAM, 10, 5)


## Leaf width, the hinge's height above the wardrobe's centre and how far the
## hinge stands proud of the front face. Shared with `room.gd`.
const WARDROBE_DOOR_WIDTH: float = 0.40
const WARDROBE_DOOR_Y: float = 0.03
const WARDROBE_HINGE_X: float = 0.415
const WARDROBE_DOOR_OPEN_DEGREES: float = 100.0


static func _wardrobe(
	tool: SurfaceTool, size: Vector3, dominant: Color, accent: Color
) -> void:
	var bottom: float = -size.y * 0.5
	for x: float in [-0.34, 0.34]:
		for z: float in [-0.21, 0.21]:
			Kit.cylinder(tool, Kit.at(Vector3(x, bottom + 0.065, z)), 0.045, 0.13,
					Palette.deep(WOOD), 10)
	Kit.box(tool, Kit.at(Vector3(0.0, 0.02, 0.0)),
			Vector3(size.x - 0.02, size.y - 0.22, size.z - 0.02), WOOD, Kit.PROP_BEVEL)
	# A cornice. Furniture with a top edge that is merely the top of the box is
	# the thing that reads as "a primitive with a texture on it".
	Kit.box(tool, Kit.at(Vector3(0.0, size.y * 0.5 - 0.06, 0.0)),
			Vector3(size.x + 0.06, 0.09, size.z + 0.06), WOOD, Kit.BEVEL)
	# The two DOORS are not written here: `room.gd::_build_wardrobe_doors()`
	# hangs each on its own hinge node so OPEN can swing them (Free Play,
	# 2026-09-20). What stays in the shell is the dark inside they reveal -- a
	# shallow recess with a rail and two hanging things, so an open wardrobe is
	# a wardrobe and not a hole.
	var inside: Color = Palette.deep(WOOD)
	Kit.box(tool, Kit.at(Vector3(0.0, 0.03, size.z * 0.5 - 0.06)),
			Vector3(0.84, 1.42, 0.02), inside)
	Kit.cylinder(tool, Kit.at_rotated(Vector3(0.0, 0.62, size.z * 0.5 - 0.16), Vector3(0.0, 0.0, 90.0)),
			0.014, 0.80, Palette.CREAM, 8)
	for x: float in [-0.20, 0.12]:
		Kit.box(tool, Kit.at(Vector3(x, 0.30, size.z * 0.5 - 0.16)),
				Vector3(0.22, 0.60, 0.05), Palette.light(accent) if x < 0.0 else Palette.light(dominant), 0.03, 2)
	# Tidy but lived-in (§5): two folded things left on top.
	Kit.box(tool, Kit.at(Vector3(-0.12, size.y * 0.5 + 0.06, 0.0)),
			Vector3(0.28, 0.10, 0.24), Palette.light(accent), 0.025, 2)
	Kit.box(tool, Kit.at(Vector3(-0.10, size.y * 0.5 + 0.145, 0.01)),
			Vector3(0.22, 0.08, 0.19), Palette.CREAM, 0.025, 2)


## A stacking-ring toy. See the class docs for why it is not a teddy, a ball or
## a block: every one of those is already a word this game teaches.
static func _toy(tool: SurfaceTool, size: Vector3) -> void:
	var bottom: float = -size.y * 0.5
	Kit.plate(tool, Kit.at(Vector3(0.0, bottom + 0.023, 0.0)),
			Kit.circle(0.152, 18), 0.046, Palette.CREAM, 0.018)
	Kit.cylinder(tool, Kit.at(Vector3(0.0, bottom + 0.19, 0.0)), 0.017, 0.30, WOOD, 10, 0.008)
	var rings: Array = [
		[0.126, 0.031, bottom + 0.072, Palette.DUSTY_BLUE],
		[0.107, 0.029, bottom + 0.132, Palette.MINT],
		[0.088, 0.027, bottom + 0.189, Palette.SOFT_PINK],
		[0.069, 0.025, bottom + 0.243, Palette.PEACH],
	]
	for ring: Array in rings:
		Kit.torus(tool, Kit.at(Vector3(0.0, float(ring[2]), 0.0)),
				float(ring[0]), float(ring[1]), ring[3] as Color, 14, 7)
	Kit.sphere(tool, Kit.at(Vector3(0.0, bottom + 0.315, 0.0)), 0.038, Palette.LAVENDER, 12, 6)


## -- Bathroom ------------------------------------------------------------------

static func _sink(tool: SurfaceTool, size: Vector3, accent: Color) -> void:
	var bottom: float = -size.y * 0.5
	Kit.box(tool, Kit.at(Vector3(0.0, bottom + 0.24, 0.0)),
			Vector3(0.22, 0.48, 0.20), Palette.CREAM, 0.04, 2)
	# The basin, as four rim walls and a floor. §6: a container must have visible
	# interior depth, or it teaches "cupboard".
	var top: float = size.y * 0.5
	Kit.plate(tool, Kit.at(Vector3(0.0, top - 0.175, 0.0)),
			Kit.rounded_rect(Vector2(0.50, 0.35), 0.07, 3), 0.06, Palette.CREAM, 0.02)
	for z: float in [-0.19, 0.19]:
		Kit.box(tool, Kit.at(Vector3(0.0, top - 0.105, z)),
				Vector3(size.x, 0.20, 0.07), Palette.CREAM, 0.022)
	for x: float in [-0.265, 0.265]:
		Kit.box(tool, Kit.at(Vector3(x, top - 0.105, 0.0)),
				Vector3(0.07, 0.20, size.z), Palette.CREAM, 0.022)
	# A pale basin floor, so the hollow reads at a glance.
	Kit.plate(tool, Kit.at(Vector3(0.0, top - 0.138, 0.0)),
			Kit.rounded_rect(Vector2(0.44, 0.29), 0.06, 3), 0.026, Palette.light(accent), 0.01)
	_tap(tool, Vector3(0.0, top - 0.01, -0.15), 0.0)


## A stem, a spout and a soft round handle. The spout points along +Z (the tap
## faces the room) unless `yaw_degrees` turns it.
static func _tap(tool: SurfaceTool, at: Vector3, yaw_degrees: float) -> void:
	var metal: Color = Palette.DUSTY_BLUE
	var frame: Transform3D = Kit.at_rotated(at, Vector3(0.0, yaw_degrees, 0.0))
	Kit.cylinder(tool, frame * Kit.at(Vector3(0.0, 0.07, 0.0)), 0.026, 0.16, metal, 10)
	Kit.cylinder(tool, frame * Kit.at_rotated(Vector3(0.0, 0.135, 0.07), Vector3(90.0, 0.0, 0.0)),
			0.020, 0.15, metal, 10)
	Kit.sphere(tool, frame * Kit.at(Vector3(0.0, 0.165, -0.005)), 0.030, Palette.CREAM, 10, 5)


## A bath is the hardest object in this house to make read, and the first three
## passes all failed the same way: a cream box, 0.5 m tall, with its water filling
## the whole top face right out to a blue rim of the same colour. That is a
## lunchbox. Cold, on a phone, it read as a chest, a bench or a bed.
##
## Four things fix it, and every one of them is necessary:
##
##   1. **Feet.** A tub raised 11 cm on four ball feet is the only object in the
##      house with daylight under it, and "you can see the floor underneath" is
##      what stops a thing being built-in furniture. It is also the single most
##      illustrated bath silhouette there is.
##   2. **Height, not length.** 0.68 m over 1.26 m, not 0.5 m over 1.4 m. At 0.5 m
##      a tub is coffee-table height and reads as a surface to put things on.
##   3. **A rounded PLAN.** `Kit.vessel()` takes a stadium outline -- the corner
##      radius is half the depth -- so the tub is an oval seen from above, which
##      no box in this house is. Four rim boxes could never do this.
##   4. **Water recessed 18 cm below the rim**, not flush with it. The cream inner
##      wall left visible along the near side IS the depth cue (§6: a container
##      must have visible interior depth). Flush water is a painted lid.
static func _bath(tool: SurfaceTool, size: Vector3, dominant: Color) -> void:
	var base: float = -size.y * 0.5
	var foot: float = 0.11
	var body: float = size.y - foot
	var body_centre: float = base + foot + body * 0.5
	var foot_colour: Color = Palette.deep(Palette.CREAM)

	for x: float in [-(size.x * 0.5 - 0.20), size.x * 0.5 - 0.20]:
		for z: float in [-(size.z * 0.5 - 0.15), size.z * 0.5 - 0.15]:
			Kit.sphere(tool, Kit.at(Vector3(x, base + foot * 0.5, z)), 0.058,
					foot_colour, 8, 4)

	# A stadium in plan: corner radius is half the depth, so the ends are true
	# half-circles and the tub is an oval from above.
	Kit.vessel(
		tool,
		Kit.at(Vector3(0.0, body_centre, 0.0)),
		Kit.rounded_rect(Vector2(size.x, size.z), size.z * 0.5, 5),
		body,
		0.075,
		0.11,
		Palette.CREAM,
		Palette.CREAM
	)
	# Clean water, in the room's own dominant colour, 18 cm down. It is a big
	# saturated oval sitting inside a pale hollow -- the one thing in the object
	# that says "this is full of water" rather than "this has a blue lid".
	var water_top: float = base + size.y - 0.095
	Kit.plate(tool, Kit.at(Vector3(0.0, water_top - 0.14, 0.0)),
			Kit.rounded_rect(Vector2(size.x - 0.19, size.z - 0.19), (size.z - 0.19) * 0.5, 4),
			0.28, dominant, 0.012)
	# Suds, clustered at the FAR end -- never dirt, and never a second taught noun
	# (§6): soap is a word this game teaches and it is a BAR, not a cloud of foam.
	# Far end, because the near rim hides the first ~25 cm of the water from a
	# camera that is both above and in front of the tub.
	for blob: Array in [
		[Vector3(0.30, 0.02, -0.11), 0.090], [Vector3(0.41, 0.00, 0.02), 0.068],
		[Vector3(0.19, 0.01, -0.15), 0.062], [Vector3(0.33, 0.05, -0.02), 0.058],
		[Vector3(0.14, 0.00, -0.04), 0.050],
	]:
		Kit.sphere(tool, Kit.at((blob[0] as Vector3) + Vector3(0.0, water_top, 0.0)),
				float(blob[1]), Palette.CREAM, 8, 4)
	_tap(tool, Vector3(-(size.x * 0.5 - 0.09), base + size.y - 0.03, 0.0), -90.0)


## Hangs on the -X wall, so everything is built projecting along +X.
##
## The failure this replaces was a 0.52 m soft-pink rectangle: on a wall the
## camera sees at a steep angle, lit by nothing but ambient, it measured 25 px
## across on a landscape iPhone and read as a poster. Cloth needs three things to
## read as cloth at that size -- a FAT fold rolled over the rail, a bottom edge
## that is wider than the top, and a second, different-coloured towel beside it,
## because two of a thing is what tells a child the thing is not a panel.
static func _towel(tool: SurfaceTool, size: Vector3) -> void:
	var top: float = size.y * 0.5
	var rail_y: float = top - 0.05
	var facing: Vector3 = Vector3(0.0, 90.0, 0.0)
	var rail: Color = Palette.deep(Palette.CREAM)

	Kit.cylinder(tool, Kit.at_rotated(Vector3(0.05, rail_y, 0.0), Vector3(90.0, 0.0, 0.0)),
			0.020, size.z + 0.06, rail, 10, 0.008)
	for z: float in [-(size.z * 0.5 + 0.015), size.z * 0.5 + 0.015]:
		Kit.box(tool, Kit.at(Vector3(0.012, rail_y, z)),
				Vector3(0.09, 0.045, 0.045), rail, 0.014)
		Kit.sphere(tool, Kit.at(Vector3(0.062, rail_y, z)), 0.026, rail, 10, 5)

	_hanging_cloth(tool, Vector3(0.062, rail_y, -size.z * 0.18), facing,
			size.z * 0.58, size.y * 0.82, Palette.SOFT_PINK, true)
	# Saturated, not `light()`. A pale blue towel on a cream wall, on the one wall
	# the sun never reaches, disappears -- the first pass of this pair proved it.
	_hanging_cloth(tool, Vector3(0.072, rail_y, size.z * 0.31),
			facing, size.z * 0.34, size.y * 0.56, Palette.DUSTY_BLUE, false)


## One towel over a rail: a rolled fold, a panel that flares toward its hem, and
## a woven band. `banded` is false for the small hand towel, which is too narrow
## to carry a stripe without it turning into a pattern (§4).
static func _hanging_cloth(
	tool: SurfaceTool,
	at: Vector3,
	facing: Vector3,
	width: float,
	drop: float,
	color: Color,
	banded: bool
) -> void:
	# The fold: a fat roll OVER the rail, proud of the cloth on both sides. This
	# is the whole cue. Without it a towel is a rectangle stuck to a wall.
	Kit.cylinder(tool, Kit.at_rotated(at - Vector3(0.022, 0.0, 0.0), Vector3(90.0, 0.0, 0.0)),
			0.055, width, Palette.light(color), 12, 0.014)
	# Hem wider than shoulder, so the silhouette tapers outward the way cloth does
	# and never reads as a rigid panel.
	var hem: float = width + 0.06
	Kit.extrude(tool, Kit.at_rotated(at + Vector3(0.0, -drop * 0.5 - 0.02, 0.0), facing),
			PackedVector2Array([
				Vector2(-width * 0.5, drop * 0.5), Vector2(width * 0.5, drop * 0.5),
				Vector2(hem * 0.5 - 0.03, -drop * 0.5 + 0.03),
				Vector2(hem * 0.5 - 0.06, -drop * 0.5),
				Vector2(-hem * 0.5 + 0.06, -drop * 0.5),
				Vector2(-hem * 0.5 + 0.03, -drop * 0.5 + 0.03),
			]), 0.055, color, 0.018)
	if not banded:
		return
	# One woven band. §4's "no stripes under ~4 px" is about pattern; this is a
	# single 7 cm band and reads at phone size.
	# +0.032 in x, and that is not arbitrary: the panel is 0.055 thick and centred
	# on `at`, so anything less than half of that is BURIED inside it. The first
	# pass offset it by 0.011 and the band simply never appeared.
	Kit.extrude(tool, Kit.at_rotated(at + Vector3(0.032, -drop * 0.72, 0.0), facing),
			Kit.rounded_rect(Vector2(hem - 0.09, 0.075), 0.03, 2), 0.030,
			Palette.CREAM, 0.012)


## -- Kitchen -------------------------------------------------------------------

static func _fridge(tool: SurfaceTool, size: Vector3, accent: Color) -> void:
	var bottom: float = -size.y * 0.5
	var front: float = size.z * 0.5
	for x: float in [-0.26, 0.26]:
		for z: float in [-0.24, 0.24]:
			Kit.cylinder(tool, Kit.at(Vector3(x, bottom + 0.045, z)), 0.04, 0.09,
					Palette.deep(Palette.CREAM), 10)
	Kit.box(tool, Kit.at(Vector3(0.0, 0.04, 0.0)),
			Vector3(size.x - 0.02, size.y - 0.14, size.z - 0.02), accent, 0.045, 2)
	# Split high: a small freezer over a tall fridge is the proportion a child
	# has actually seen.
	Kit.extrude(tool, Kit.at(Vector3(0.0, 0.57, front + 0.005)),
			Kit.rounded_rect(Vector2(size.x - 0.09, 0.44), 0.06, 3), 0.045,
			Palette.light(accent), 0.018)
	Kit.extrude(tool, Kit.at(Vector3(0.0, -0.06, front + 0.005)),
			Kit.rounded_rect(Vector2(size.x - 0.09, 0.78), 0.06, 3), 0.045,
			Palette.light(accent), 0.018)
	Kit.cylinder(tool, Kit.at_rotated(Vector3(-0.17, 0.40, front + 0.045),
			Vector3(0.0, 0.0, 90.0)), 0.021, 0.24, Palette.CREAM, 10, 0.008)
	Kit.cylinder(tool, Kit.at(Vector3(-0.24, 0.10, front + 0.045)),
			0.021, 0.34, Palette.CREAM, 10, 0.008)


## The cupboard doors take the room's ACCENT, a step lighter, matching the wall
## units above them (`room.gd::_wall_cupboards`). They were `light(peach)` on a
## `deep(peach)` carcass under a `cream` worktop against a `cream` wall: four
## values of one warm neutral stacked on top of each other, and the three door
## panels could not be found in a render at all.
static func _counter(tool: SurfaceTool, size: Vector3, accent: Color) -> void:
	var bottom: float = -size.y * 0.5
	var top: float = size.y * 0.5
	var front: float = size.z * 0.5
	Kit.box(tool, Kit.at(Vector3(0.0, bottom + 0.045, 0.0)),
			Vector3(size.x - 0.10, 0.09, size.z - 0.10), Palette.deep(WOOD), 0.02)
	Kit.box(tool, Kit.at(Vector3(0.0, -0.02, 0.0)),
			Vector3(size.x - 0.04, size.y - 0.24, size.z - 0.02), WOOD, Kit.PROP_BEVEL)
	Kit.plate(tool, Kit.at(Vector3(0.0, top - 0.045, 0.0)),
			Kit.rounded_rect(Vector2(size.x + 0.04, size.z + 0.04), 0.05, 3), 0.09,
			Palette.CREAM, 0.022)
	for x: float in [-0.58, 0.0, 0.58]:
		Kit.extrude(tool, Kit.at(Vector3(x, -0.05, front + 0.005)),
				Kit.rounded_rect(Vector2(0.52, 0.50), 0.06, 3), 0.045,
				Palette.light(accent), 0.018)
		Kit.sphere(tool, Kit.at(Vector3(x, 0.14, front + 0.05)), 0.032, Palette.CREAM, 10, 5)


static func _table(tool: SurfaceTool, size: Vector3) -> void:
	var top: float = size.y * 0.5
	Kit.plate(tool, Kit.at(Vector3(0.0, top - 0.04, 0.0)),
			Kit.rounded_rect(Vector2(size.x, size.z), 0.14, 4), 0.08, WOOD, 0.022)
	Kit.box(tool, Kit.at(Vector3(0.0, top - 0.115, 0.0)),
			Vector3(size.x - 0.16, 0.07, size.z - 0.16), WOOD, 0.02)
	for x: float in [-(size.x * 0.5 - 0.10), size.x * 0.5 - 0.10]:
		for z: float in [-(size.z * 0.5 - 0.10), size.z * 0.5 - 0.10]:
			Kit.cylinder(tool, Kit.at(Vector3(x, -0.06, z)), 0.045, size.y - 0.15, WOOD, 10)


## -- Living room ---------------------------------------------------------------

static func _sofa(tool: SurfaceTool, size: Vector3, dominant: Color, accent: Color) -> void:
	var bottom: float = -size.y * 0.5
	var back_z: float = -(size.z * 0.5 - 0.10)
	for x: float in [-(size.x * 0.5 - 0.15), size.x * 0.5 - 0.15]:
		for z: float in [-(size.z * 0.5 - 0.12), size.z * 0.5 - 0.12]:
			Kit.cylinder(tool, Kit.at(Vector3(x, bottom + 0.05, z)), 0.045, 0.10,
					Palette.deep(WOOD), 10)
	# The frame is the ACCENT deepened, not the dominant deepened, and that is a
	# correction rather than a preference. `deep(peach)` is exactly the colour
	# `room.gd` paints the living room's wainscot, so the sofa's frame, its arms
	# and its back were pixel-for-pixel the wall two centimetres behind them: the
	# whole object lost its silhouette and only the cushions read. `deep(softPink)`
	# is a dusty rose that belongs to the sofa and to nothing else in the room.
	var frame: Color = Palette.deep(accent)
	Kit.box(tool, Kit.at(Vector3(0.0, bottom + 0.21, 0.0)),
			Vector3(size.x - 0.08, 0.22, size.z - 0.06), frame, 0.04, 2)
	Kit.box(tool, Kit.at(Vector3(0.0, 0.10, back_z)),
			Vector3(size.x - 0.08, 0.50, 0.20), frame, 0.05, 2)
	for side: float in [-1.0, 1.0]:
		Kit.box(tool, Kit.at(Vector3(side * (size.x * 0.5 - 0.10), -0.02, 0.02)),
				Vector3(0.20, 0.44, size.z - 0.06), frame, 0.07, 2)
		Kit.box(tool, Kit.at(Vector3(side * 0.38, 0.0, 0.04)),
				Vector3(0.72, 0.15, 0.58), accent, 0.055, 2)
		Kit.box(tool, Kit.at(Vector3(side * 0.38, 0.15, back_z + 0.16)),
				Vector3(0.70, 0.30, 0.14), Palette.light(accent), 0.05, 2)


## MINT -- which is what `house_layout.furniture()` has always DECLARED this
## object to be, and which the builder then ignored in favour of the room's
## accent.
##
## The cost of ignoring it was visible: the living room accents on `softPink`,
## so the toy box came out the same pink as the sofa, the `toyShelf` storage, the
## rug and the curtains, and the room read as five pink objects on a brown wall.
## `toyBox` is the only piece of furniture in the room that is not upholstery, so
## it is the one that should not be.
static func _toy_box(tool: SurfaceTool, size: Vector3) -> void:
	var accent: Color = Palette.MINT
	var bottom: float = -size.y * 0.5
	Kit.plate(tool, Kit.at(Vector3(0.0, bottom + 0.035, 0.0)),
			Kit.rounded_rect(Vector2(size.x - 0.08, size.z - 0.08), 0.05, 3), 0.07,
			Palette.deep(Palette.CREAM), 0.02)
	for z: float in [-(size.z * 0.5 - 0.035), size.z * 0.5 - 0.035]:
		Kit.box(tool, Kit.at(Vector3(0.0, -0.01, z)),
				Vector3(size.x, size.y - 0.06, 0.07), accent, 0.022)
	for x: float in [-(size.x * 0.5 - 0.035), size.x * 0.5 - 0.035]:
		Kit.box(tool, Kit.at(Vector3(x, -0.01, 0.0)),
				Vector3(0.07, size.y - 0.06, size.z), accent, 0.022)
	# Something spilling over the rim, so it reads as a toy box rather than a
	# crate. Kept abstract on purpose: a ball or a block here would be a second
	# shape for a word the game already teaches elsewhere (§6).
	Kit.box(tool, Kit.at_rotated(Vector3(0.15, size.y * 0.5 - 0.02, -0.02),
			Vector3(0.0, 24.0, 12.0)), Vector3(0.18, 0.18, 0.18),
			Palette.light(Palette.PEACH), 0.035, 2)
	Kit.torus(tool, Kit.at_rotated(Vector3(-0.15, size.y * 0.5 - 0.05, 0.03),
			Vector3(62.0, 0.0, 18.0)), 0.095, 0.030, Palette.LAVENDER, 12, 6)


## An OPEN book, lying on the floor -- "a book left out" is literally the example
## §5 gives of tidy-but-lived-in clutter.
##
## This object took three passes as a CLOSED book and failed every time, for a
## reason worth writing down: a closed book is a rectangular slab, the camera is
## a three-quarter view looking DOWN, and a rectangular slab seen from above is a
## tray. Everything that makes a closed book a book -- the spine, the page block,
## the cover boards -- lives on its EDGES, which is the one part of it that view
## cannot see. The owner named it, cold, as a tray face-up on the floor.
##
## Open, the recognisable form moves onto the face the camera actually sees: two
## pale pages, a dark cover border round the outside, and a centre gutter. That
## silhouette belongs to nothing else in this house, which is what §6 asks for.
static func _book(tool: SurfaceTool, size: Vector3) -> void:
	var cover: Color = Palette.deep(Palette.DUSTY_BLUE)
	var base: float = -size.y * 0.5
	# Each half tips UP toward its outer edge, the way a page stack does when the
	# spine is flat on the floor. It is only 7 degrees, but it is what gives the
	# object a ridge down its middle and two lit planes instead of one flat top.
	var tilt: float = 7.0
	var half_width: float = size.x * 0.5

	for side: float in [-1.0, 1.0]:
		var lean: Vector3 = Vector3(0.0, 0.0, side * tilt)
		var middle: Vector3 = Vector3(side * half_width * 0.5, base + 0.035, 0.0)
		# The cover board: dark, and bigger than the pages on all three outer
		# sides, so a coloured border frames the cream. That border is what reads
		# at 60 px.
		Kit.plate(tool, Kit.at_rotated(middle, lean),
				Kit.rounded_rect(Vector2(half_width - 0.012, size.z), 0.035, 3), 0.028,
				cover, 0.010)
		# The page stack, inset, and thick enough to show a stepped cream edge.
		Kit.plate(tool, Kit.at_rotated(middle + Vector3(side * 0.012, 0.050, 0.0), lean),
				Kit.rounded_rect(Vector2(half_width - 0.070, size.z - 0.055), 0.022, 3), 0.062,
				Palette.CREAM, 0.010)
		# The top page, a whisker proud of the stack so the stack reads as MANY
		# sheets rather than one slab.
		Kit.plate(tool, Kit.at_rotated(middle + Vector3(side * 0.012, 0.086, 0.0), lean),
				Kit.rounded_rect(Vector2(half_width - 0.092, size.z - 0.080), 0.018, 3), 0.014,
				Palette.CREAM, 0.005)
		# What is ON the page. A picture book has a picture, and a single bold
		# shape survives being 40 px wide; ruled "text" lines do not, and §4 bans
		# text on art in any case.
		#
		# Both marks are `deep()`/base tokens rather than the pastel itself: a
		# `softPink` blob on a cream page at 40 px is invisible, and the first
		# pass proved it twice -- once by being too pale, and once by sitting at
		# an absolute height that buried it INSIDE the page stack. Placing it
		# relative to the page it belongs to is what stops that happening again.
		var on_page: Vector3 = middle + Vector3(side * 0.012, 0.099, 0.0)
		if side > 0.0:
			Kit.plate(tool, Kit.at_rotated(on_page + Vector3(0.0, 0.0, -0.02), lean),
					Kit.rounded_rect(Vector2(0.125, 0.115), 0.045, 3), 0.016,
					Palette.deep(Palette.SOFT_PINK), 0.005)
		else:
			for row: float in [0.055, -0.005, -0.065]:
				Kit.plate(tool, Kit.at_rotated(on_page + Vector3(0.0, 0.0, row), lean),
						Kit.rounded_rect(Vector2(0.135, 0.030), 0.014, 2), 0.016,
						Palette.DUSTY_BLUE, 0.004)

	# The spine, standing proud along the gutter. A raised ridge down the centre
	# is the difference between "an open book" and "two mats side by side".
	Kit.extrude(tool, Kit.at_rotated(Vector3(0.0, base + 0.052, 0.0), Vector3(90.0, 0.0, 0.0)),
			Kit.rounded_rect(Vector2(size.z + 0.01, 0.075), 0.034, 4), 0.062,
			Palette.DUSTY_BLUE, 0.016)

	# A ribbon bookmark, lying across the right-hand page and trailing over the
	# near edge. In the COVER's colour, not a fresh one: a `mint` ribbon in a
	# peach-and-pink room read as a green object that had landed on the book
	# rather than as part of it.
	Kit.plate(tool, Kit.at(Vector3(half_width * 0.30, base + 0.112, size.z * 0.30)),
			Kit.rounded_rect(Vector2(0.038, size.z * 0.58), 0.016, 2), 0.014,
			cover, 0.004)


## -- Shared dressing -----------------------------------------------------------

## A small potted plant. §5 asks every room to be "tidy but lived-in" and names a
## plant; this is the cheapest way to say "somebody lives here". Never a taught
## word, so it can sit anywhere without teaching a second name for something.
static func plant(tool: SurfaceTool, at: Transform3D, scale: float, pot: Color) -> void:
	var s: float = scale
	Kit.cylinder(tool, at * Kit.at(Vector3(0.0, 0.075 * s, 0.0)),
			0.085 * s, 0.15 * s, pot, 12, 0.012 * s)
	Kit.cylinder(tool, at * Kit.at(Vector3(0.0, 0.165 * s, 0.0)),
			0.098 * s, 0.05 * s, Palette.light(pot), 12, 0.012 * s)
	Kit.plate(tool, at * Kit.at(Vector3(0.0, 0.178 * s, 0.0)),
			Kit.circle(0.082 * s, 12), 0.03 * s, Palette.deep(WOOD), 0.008 * s)
	var leaves: Array = [
		[Vector3(0.0, 0.30, 0.0), 0.085, Palette.MINT],
		[Vector3(-0.075, 0.25, 0.03), 0.065, Palette.deep(Palette.MINT)],
		[Vector3(0.07, 0.255, -0.035), 0.062, Palette.MINT],
		[Vector3(0.02, 0.365, 0.045), 0.055, Palette.light(Palette.MINT)],
		[Vector3(-0.03, 0.345, -0.05), 0.05, Palette.deep(Palette.MINT)],
	]
	for leaf: Array in leaves:
		Kit.sphere(tool, at * Kit.at((leaf[0] as Vector3) * s), float(leaf[1]) * s,
				leaf[2] as Color, 10, 5)


## -- Floor dressing ------------------------------------------------------------
##
## Everything below stands on the FLOOR, in the front third of a room, and
## exists for one reason: by layout every piece of furniture in this house is
## against the back wall, so the near half of every room was bare boards and the
## composition had nothing in the foreground at all.
##
## Two hard rules govern this whole section:
##
##   * **Nothing here may be a word the game teaches.** §6 -- "one object teaches
##     one word, two nouns must never share a shape" -- and the vocabulary
##     already owns `ball`, `bowl`, `cup`, `lamp`, `pillow`, `teddy`, `blocks`,
##     `toyBox` and `soap`. A floor cushion would collide with `pillow`, a floor
##     lamp with `lamp`, a toy basket with `toyBox`. What is left, and what is
##     used here, is a plant, a woven basket, a stool and a footstool.
##   * **Everything here gets a collider and everything here is in a CORNER.**
##     Floor dressing that blocks a path the level needs is a dead end, which is
##     the one thing this game may never have. The corners are the only part of
##     the floor no authored stand point and no spawn uses.


## A floor-standing plant: the same species as the one on every windowsill, grown
## up. The repetition is the point -- one plant on a sill and one on the floor of
## all four rooms is what makes four rooms read as one home.
static func floor_plant(tool: SurfaceTool, at: Transform3D, pot: Color) -> void:
	# A pot that is WIDER than it is tall. The first pass made it 0.34 m tall and
	# straight-sided to use the footprint up, and a tall straight cylinder with
	# something green on top is a wastebasket with a plant in it.
	Kit.vessel(tool, at * Kit.at(Vector3(0.0, 0.125, 0.0)),
			Kit.circle(0.150, 14), 0.25, 0.024, 0.20, pot, Palette.deep(WOOD))
	Kit.cylinder(tool, at * Kit.at(Vector3(0.0, 0.245, 0.0)),
			0.166, 0.048, Palette.light(pot), 14, 0.014)
	Kit.cylinder(tool, at * Kit.at(Vector3(0.0, 0.33, 0.0)), 0.020, 0.16, WOOD, 8, 0.008)
	# A broad, low bush rather than a column of spheres: the silhouette has to
	# spread sideways or it reads as a lollipop.
	for leaf: Array in [
		[Vector3(0.0, 0.50, 0.0), 0.150, Palette.MINT],
		[Vector3(-0.140, 0.44, 0.035), 0.108, Palette.deep(Palette.MINT)],
		[Vector3(0.132, 0.45, -0.045), 0.104, Palette.MINT],
		[Vector3(0.045, 0.63, 0.055), 0.098, Palette.light(Palette.MINT)],
		[Vector3(-0.060, 0.61, -0.070), 0.088, Palette.deep(Palette.MINT)],
		[Vector3(0.095, 0.56, 0.110), 0.074, Palette.MINT],
		[Vector3(-0.100, 0.54, 0.105), 0.070, Palette.MINT],
	]:
		Kit.sphere(tool, at * Kit.at(leaf[0] as Vector3), float(leaf[1]),
				leaf[2] as Color, 10, 5)


## A round woven basket. Deliberately ROUND and rim-rolled, because the living
## room's `toyBox` is square, open and spilling toys, and two containers in one
## house must not be the same shape.
static func basket(tool: SurfaceTool, at: Transform3D, color: Color) -> void:
	Kit.vessel(tool, at * Kit.at(Vector3(0.0, 0.19, 0.0)),
			Kit.circle(0.155, 16), 0.38, 0.030, 0.30, color, Palette.light(color))
	# A rolled rim, which is most of what says "woven" without a texture (§7 has
	# no textures to say it with).
	Kit.torus(tool, at * Kit.at(Vector3(0.0, 0.376, 0.0)), 0.148, 0.024,
			Palette.deep(color), 16, 6)
	# ONE band course, proud by 2 mm. Two of them, standing 8 mm out, turned the
	# whole thing into a stack of hoops.
	Kit.cylinder(tool, at * Kit.at(Vector3(0.0, 0.155, 0.0)), 0.158, 0.050,
			Palette.light(color), 16, 0.014)
	# Two hoop handles at the rim. Without them a round open container of this
	# size is a waste bin, and a bedroom does not want one of those in it.
	for side: float in [-1.0, 1.0]:
		Kit.torus(tool, at * Kit.at_rotated(Vector3(side * 0.150, 0.295, 0.0),
				Vector3(0.0, 0.0, 90.0)), 0.062, 0.018, Palette.deep(color), 10, 6)


## A child's step stool: two treads, and that stepped profile is the whole read.
static func step_stool(tool: SurfaceTool, at: Transform3D, color: Color) -> void:
	for step: Array in [[0.100, 0.20, -0.06], [0.235, 0.16, 0.07]]:
		Kit.plate(tool, at * Kit.at(Vector3(0.0, float(step[0]), float(step[2]))),
				Kit.rounded_rect(Vector2(0.33, float(step[1])), 0.050, 3), 0.048,
				color, 0.016)
	for x: float in [-0.135, 0.135]:
		Kit.box(tool, at * Kit.at(Vector3(x, 0.120, 0.005)),
				Vector3(0.044, 0.24, 0.30), Palette.deep(color), 0.018)


## A little round stool: a soft disc on three splayed legs.
static func stool(tool: SurfaceTool, at: Transform3D, color: Color) -> void:
	Kit.plate(tool, at * Kit.at(Vector3(0.0, 0.345, 0.0)), Kit.circle(0.165, 16), 0.058,
			color, 0.020)
	Kit.plate(tool, at * Kit.at(Vector3(0.0, 0.306, 0.0)), Kit.circle(0.138, 16), 0.030,
			Palette.deep(WOOD), 0.010)
	for index: int in range(3):
		var angle: float = TAU * float(index) / 3.0 + 0.5
		var offset := Vector3(cos(angle) * 0.105, 0.150, sin(angle) * 0.105)
		Kit.cylinder(tool, at * Kit.at(offset), 0.026, 0.30, WOOD, 8, 0.008)


## A soft round footstool. Not a cushion and not a pillow -- both of those are
## flat rectangles and `pillow` is a word this game teaches on the bed.
static func footstool(tool: SurfaceTool, at: Transform3D, color: Color) -> void:
	Kit.plate(tool, at * Kit.at(Vector3(0.0, 0.220, 0.0)), Kit.circle(0.168, 16), 0.145,
			color, 0.058)
	Kit.plate(tool, at * Kit.at(Vector3(0.0, 0.132, 0.0)), Kit.circle(0.152, 16), 0.052,
			Palette.light(color), 0.020)
	# A button in the middle of the seat, so the top is not a bare disc.
	Kit.sphere(tool, at * Kit.at(Vector3(0.0, 0.284, 0.0)), 0.032,
			Palette.deep(color), 10, 5)
	for index: int in range(4):
		var angle: float = TAU * float(index) / 4.0 + 0.7
		Kit.cylinder(tool, at * Kit.at(Vector3(cos(angle) * 0.108, 0.052, sin(angle) * 0.108)),
				0.024, 0.105, Palette.deep(WOOD), 8, 0.008)
