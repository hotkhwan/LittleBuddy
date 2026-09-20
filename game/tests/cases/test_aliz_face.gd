extends RefCounted

## Aliz's face, measured on the shipped mesh: the mouth is closed and the fringe
## is solid.
##
## Both were fixed on 2026-09-20 by `tools/aliz_local_pass.py` -- see
## `docs/ALIZ_LOCAL_PASS.md`. Neither fix lives in code, so neither is protected
## by anything else in this suite: both are properties of
## `assets/characters/buddy/pinkGirl/pinkGirlBuddy_v01.glb` and its atlas, and a
## careless re-export, a re-extract of the GLB's embedded image, or a revert of
## the asset would put the gaping open-mouthed grin straight back on the player
## character with every test still green.
##
## So this case asserts the two facts that distinguish the fixed asset from the
## broken one, directly on the imported mesh.
##
## ## 1. There is no cavity behind the mouth
##
## The defect was a **modelled** 10 cm hole: down the midline the surface fell
## from z = 0.215 to z = 0.112 in a single pixel, with a tongue and a strip of
## teeth inside it. Art bible §4 is explicit -- "One filled shape... no lips, no
## lip line, no teeth, no tongue" and "**No visible teeth, ever**" -- so the
## cavity was not a style disagreement, it was a violation.
##
## The check does not need to find the cavity. It only needs to know that the
## mouth region of the face is *shallow*: every vertex there must sit within
## `MAX_MOUTH_DEPTH_M` of the front of the face at the same height. The original
## asset fails this by a factor of about eight.
##
## ## 2. The forehead is hair, not skin
##
## The fringe read as torn pink ribbons on a bald forehead because the atlas
## painted skin over the front of the hair volume. The front of the head above
## the lashes must now be overwhelmingly hair-pink rather than skin.
##
## ## Why it asserts on the mesh and not on a screenshot
##
## A screenshot comparison would be the more faithful test and is not available
## headless without a render server; the judging was done by eye on
## `docs/shots/aliz_before_*.png` against `docs/shots/aliz_after_*.png`, which is
## what art bible §12 asks for. This case is the cheap, deterministic guard that
## survives in CI underneath that.

const Buddy := preload("res://scripts/characters/buddy/pink_girl_buddy.gd")

const MODEL_PATH: String = "res://assets/characters/buddy/pinkGirl/pinkGirlBuddy_v01.glb"

## The mouth region, in the GLB's own metres. Measured, not guessed: the cavity
## spanned x in [-0.057, +0.060] and y in [1.135, 1.212] on a model 1.700 m tall
## whose face points +Z.
## y starts at 1.150 and not lower on purpose: the **underside of the jaw**
## begins at y = 1.122 and is legitimately 10 cm behind the front of the face.
## Including it would make this test fire on a perfectly good chin.
const MOUTH_X_HALF: float = 0.070
const MOUTH_Y_LO: float = 1.150
const MOUTH_Y_HI: float = 1.225

## How far behind the front of the face a mouth vertex may sit. Lips and the
## corners of the mouth are legitimately a couple of centimetres back on a
## rounded head; a throat is not. Measured in this exact box: the broken asset
## has **32** vertices past this line and its worst is **0.106 m**; the fixed one
## has **none** and its worst is **0.012 m**. The threshold sits in the middle of
## a gap an order of magnitude wide, so it is not a tuned number.
const MAX_MOUTH_DEPTH_M: float = 0.030

## The fringe band: the front of the head above the lashes, which top out at
## y = 1.381.
const FRINGE_Y: float = 1.450
const FRINGE_MIN_Z: float = 0.05

## The fringe must be at least this much hair. It is 99%+ on the fixed asset and
## was roughly half skin on the broken one.
const MIN_HAIR_FRACTION: float = 0.90


func test_name() -> String:
	return "aliz_face"


func run():
	var failures: Array = []
	if not ResourceLoader.exists(MODEL_PATH):
		# The export is gitignored in some checkouts. Say so rather than passing
		# vacuously -- a silent skip here would hide exactly what it guards.
		return ["%s is not in this checkout, so Aliz's face was not measured"
				% MODEL_PATH]
	var mesh := _find_mesh()
	if mesh == null:
		return ["could not find a MeshInstance3D inside %s" % MODEL_PATH]

	failures.append_array(_test_the_mouth_is_closed(mesh))
	failures.append_array(_test_the_fringe_is_hair(mesh))
	return failures


## Every vertex in the mouth region sits close to the face surface.
##
## "The face surface" is taken per height band as the frontmost vertex in that
## band, so a rounded head is not mistaken for a hole.
func _test_the_mouth_is_closed(mesh):
	var failures: Array = []
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

	# Front of the face, per 1 cm band of height.
	var front := {}
	for p: Vector3 in points:
		if absf(p.x) > 0.16 or p.z <= 0.0:
			continue
		var band := int(p.y * 100.0)
		if not front.has(band) or p.z > float(front[band]):
			front[band] = p.z

	var worst := 0.0
	var worst_at := Vector3.ZERO
	var counted := 0
	for p: Vector3 in points:
		if absf(p.x) > MOUTH_X_HALF:
			continue
		if p.y < MOUTH_Y_LO or p.y > MOUTH_Y_HI or p.z <= 0.0:
			continue
		var band := int(p.y * 100.0)
		if not front.has(band):
			continue
		counted += 1
		var depth: float = float(front[band]) - p.z
		if depth > worst:
			worst = depth
			worst_at = p
	if counted < 10:
		failures.append(
			"only %d vertices found in Aliz's mouth region -- the landmarks in "
			% counted
			+ "this test no longer match the asset, so it is checking nothing")
	elif worst > MAX_MOUTH_DEPTH_M:
		failures.append(
			("Aliz's mouth is open again: a vertex at %s sits %.3f m behind the "
			+ "front of her face, against a limit of %.3f m. ART_BIBLE.md §4: "
			+ "\"No visible teeth, ever\". Re-run tools/aliz_local_pass.py, and "
			+ "see docs/ALIZ_LOCAL_PASS.md.")
			% [worst_at, worst, MAX_MOUTH_DEPTH_M])
	return failures


## The front of the head above the lashes is painted hair, not skin.
func _test_the_fringe_is_hair(mesh):
	var failures: Array = []
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var image := _albedo_image(mesh)
	if image == null:
		return ["Aliz's albedo atlas could not be read, so the fringe was not "
				+ "measured"]

	var hair := 0
	var skin := 0
	for i in range(points.size()):
		var p: Vector3 = points[i]
		if p.y < FRINGE_Y or p.z < FRINGE_MIN_Z or absf(p.x) > 0.20:
			continue
		var uv: Vector2 = uvs[i]
		var c: Color = image.get_pixel(
			clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1),
			clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1))
		# Hair is a saturated pink; skin is a pale peach. The two are separated
		# by green: hair sits near 0.47, skin near 0.81.
		if c.r > 0.75 and c.g < 0.65:
			hair += 1
		elif c.r > 0.85 and c.g > 0.70:
			skin += 1
	var total := hair + skin
	if total < 20:
		failures.append(
			"only %d vertices found on Aliz's fringe -- the landmarks in this "
			% total
			+ "test no longer match the asset, so it is checking nothing")
		return failures
	var fraction := float(hair) / float(total)
	if fraction < MIN_HAIR_FRACTION:
		failures.append(
			("Aliz's fringe is %.0f%% hair, below the %.0f%% floor: the forehead "
			+ "is showing through her bangs again. ART_BIBLE.md §4 wants hair as "
			+ "solid rounded masses. Re-run tools/aliz_local_pass.py.")
			% [fraction * 100.0, MIN_HAIR_FRACTION * 100.0])
	return failures


func _find_mesh() -> MeshInstance3D:
	var packed: Resource = load(MODEL_PATH)
	if not (packed is PackedScene):
		return null
	var root: Node = (packed as PackedScene).instantiate()
	var found := _search(root)
	if found != null:
		# Keep the mesh alive past the tree we are about to drop.
		found = found.duplicate() as MeshInstance3D
	root.free()
	return found


func _search(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var deeper := _search(child)
		if deeper != null:
			return deeper
	return null


func _albedo_image(mesh: MeshInstance3D) -> Image:
	var material: Material = mesh.mesh.surface_get_material(0)
	if not (material is StandardMaterial3D):
		return null
	var texture: Texture2D = (material as StandardMaterial3D).albedo_texture
	if texture == null:
		return null
	return texture.get_image()
