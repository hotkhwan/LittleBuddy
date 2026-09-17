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
			_counter(tool, size, dominant)
		"table":
			_table(tool, size)
		"sofa":
			_sofa(tool, size, dominant, accent)
		"toyBox":
			_toy_box(tool, size, accent)
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
	for side: float in [-1.0, 1.0]:
		Kit.extrude(tool, Kit.at(Vector3(side * 0.215, 0.03, size.z * 0.5 + 0.005)),
				Kit.rounded_rect(Vector2(0.40, 1.42), 0.06, 3), 0.05,
				dominant, 0.018)
		Kit.sphere(tool, Kit.at(Vector3(side * 0.07, 0.03, size.z * 0.5 + 0.055)),
				0.036, Palette.CREAM, 10, 5)
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


## A bath is the hardest object in this house to make read, because a cream tub
## against a cream wall is a crate: the first pass of this room rendered it as
## exactly that. Three things fix it and all three are necessary -- a ROUNDED
## outer silhouette (four corner columns, not four square corners), a coloured
## RIM running right round the top, and a saturated interior so the hollow is
## visible from a three-quarter camera rather than inferred.
static func _bath(tool: SurfaceTool, size: Vector3, dominant: Color) -> void:
	var bottom: float = -size.y * 0.5
	var top: float = size.y * 0.5
	var corner: float = 0.17
	var wall: float = 0.09
	var height: float = size.y - 0.14
	var inset_x: float = size.x * 0.5 - corner
	var inset_z: float = size.z * 0.5 - corner

	Kit.plate(tool, Kit.at(Vector3(0.0, bottom + 0.07, 0.0)),
			Kit.rounded_rect(Vector2(size.x - 0.02, size.z - 0.02), corner + 0.03, 4), 0.14,
			Palette.CREAM, 0.03)
	for x: float in [-inset_x, inset_x]:
		for z: float in [-inset_z, inset_z]:
			Kit.cylinder(tool, Kit.at(Vector3(x, top - height * 0.5, z)),
					corner, height, Palette.CREAM, 14, 0.02)
			Kit.cylinder(tool, Kit.at(Vector3(x, top - 0.03, z)),
					corner + 0.012, 0.07, dominant, 14, 0.018)
	for z: float in [-(size.z * 0.5 - wall * 0.5), size.z * 0.5 - wall * 0.5]:
		Kit.box(tool, Kit.at(Vector3(0.0, top - height * 0.5, z)),
				Vector3(inset_x * 2.0, height, wall), Palette.CREAM, 0.026)
		Kit.box(tool, Kit.at(Vector3(0.0, top - 0.03, z)),
				Vector3(inset_x * 2.0, 0.07, wall + 0.024), dominant, 0.022)
	for x: float in [-(size.x * 0.5 - wall * 0.5), size.x * 0.5 - wall * 0.5]:
		Kit.box(tool, Kit.at(Vector3(x, top - height * 0.5, 0.0)),
				Vector3(wall, height, inset_z * 2.0), Palette.CREAM, 0.026)
		Kit.box(tool, Kit.at(Vector3(x, top - 0.03, 0.0)),
				Vector3(wall + 0.024, 0.07, inset_z * 2.0), dominant, 0.022)
	# The inside, in the room's own dominant colour: clean water-blue, filled to
	# just below the rim. An EMPTY tub shows the far inner wall and nothing else
	# from a three-quarter camera, which renders as a cream crate; a filled one
	# puts a blue plane where the eye expects the hollow to be.
	Kit.plate(tool, Kit.at(Vector3(0.0, 0.005, 0.0)),
			Kit.rounded_rect(Vector2(size.x - 0.24, size.z - 0.24), 0.13, 4), 0.37,
			dominant, 0.018)
	_tap(tool, Vector3(-(size.x * 0.5 - 0.12), top - 0.04, 0.0), -90.0)


static func _towel(tool: SurfaceTool, size: Vector3) -> void:
	var top: float = size.y * 0.5
	# The rail, and the two brackets that hold it off the wall.
	Kit.cylinder(tool, Kit.at_rotated(Vector3(0.015, top - 0.02, 0.0), Vector3(90.0, 0.0, 0.0)),
			0.018, size.z + 0.06, Palette.CREAM, 10, 0.008)
	for z: float in [-(size.z * 0.5 + 0.02), size.z * 0.5 + 0.02]:
		Kit.box(tool, Kit.at(Vector3(-0.03, top - 0.02, z)),
				Vector3(0.08, 0.04, 0.04), Palette.CREAM, 0.012)
	# Cloth, hanging. Folded over the rail at the top -- that fold is the single
	# cue that separates "towel" from "a pink rectangle on a wall".
	var facing: Vector3 = Vector3(0.0, 90.0, 0.0)
	Kit.extrude(tool, Kit.at_rotated(Vector3(0.025, -0.02, 0.0), facing),
			Kit.rounded_rect(Vector2(size.z - 0.06, size.y - 0.10), 0.05, 3), 0.05,
			Palette.SOFT_PINK, 0.018)
	Kit.extrude(tool, Kit.at_rotated(Vector3(0.015, top - 0.035, 0.0), facing),
			Kit.rounded_rect(Vector2(size.z - 0.06, 0.15), 0.05, 3), 0.075,
			Palette.light(Palette.SOFT_PINK), 0.022)
	# One woven band. §4's "no stripes under ~4 px" is about pattern; this is a
	# single 6 cm band and reads at phone size.
	Kit.extrude(tool, Kit.at_rotated(Vector3(0.033, -0.10, 0.0), facing),
			Kit.rounded_rect(Vector2(size.z - 0.08, 0.07), 0.03, 2), 0.05,
			Palette.CREAM, 0.016)


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


static func _counter(tool: SurfaceTool, size: Vector3, dominant: Color) -> void:
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
				Palette.light(dominant), 0.018)
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
	var frame: Color = Palette.deep(dominant)
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


static func _toy_box(tool: SurfaceTool, size: Vector3, accent: Color) -> void:
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


static func _book(tool: SurfaceTool, size: Vector3) -> void:
	var cover: Color = Palette.deep(Palette.DUSTY_BLUE)
	var outline: PackedVector2Array = Kit.rounded_rect(Vector2(size.x, size.z), 0.025, 2)
	for y: float in [-(size.y * 0.5 - 0.012), size.y * 0.5 - 0.012]:
		Kit.plate(tool, Kit.at(Vector3(0.0, y, 0.0)), outline, 0.024, cover, 0.008)
	# The page block, pushed out past the covers on the open side so a cream stripe
	# of paper is visible from any angle. Tucked inside them it reads as a tile.
	Kit.plate(tool, Kit.at(Vector3(0.035, 0.0, 0.0)),
			Kit.rounded_rect(Vector2(size.x - 0.01, size.z - 0.014), 0.018, 2),
			size.y - 0.052, Palette.CREAM, 0.008)
	Kit.box(tool, Kit.at(Vector3(-(size.x * 0.5 - 0.016), 0.0, 0.0)),
			Vector3(0.032, size.y - 0.006, size.z), Palette.deep(cover), 0.012)
	Kit.plate(tool, Kit.at(Vector3(0.04, size.y * 0.5 - 0.004, 0.0)),
			Kit.circle(0.052, 14), 0.018, Palette.light(Palette.SOFT_PINK), 0.006)


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
