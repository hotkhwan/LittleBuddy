extends RefCounted

## ============================================================================
## BUNNY'S FACE -- repainted, because it cannot be animated.
## ============================================================================
##
## **There are no facial bones.** The rigged export's skeleton ends at
## `headfront`; there is no jaw, no brow and no eyelid, and `baby_life_clips.gd`
## says so at length. Everything a player reads as Bunny's expression -- the
## eyes, the lashes, the brows, the mouth, the blush -- is PAINTED INTO THE
## ALBEDO. A 1024x1024 atlas, one material, one UV island for the face.
##
## So the honest routes to an expression are exactly two: body language through
## the rig, which is what the clips do, and **redrawing the face region of the
## albedo**, which is what this file does. It is the second one nobody had tried.
##
## ## What this is, precisely
##
## Four variants of one texture, differing only inside the eye and mouth
## islands. No shader, no UV animation, no per-frame work of any kind, nothing in
## `_process`. A mood change is a texture upload and happens a handful of times
## per session -- when the need changes, when Bunny is fed, when he is put to
## bed. It is closer to swapping a decal than to animating anything, and it is
## described that way in `docs/BUNNY_EXPRESSION_PASS.md` rather than as
## "expression animation".
##
## | mood        | eyes                        | mouth                  |
## |-------------|-----------------------------|------------------------|
## | `content`   | the shipped face, untouched | untouched              |
## | `unhappy`   | upper lids drawn down       | a small downturned line|
## | `delighted` | closed, arched UP           | open, a wide smile     |
## | `asleep`    | closed, curved DOWN         | untouched              |
##
## ## Why it is painted rather than shipped as four PNGs
##
## Four 1024x1024 atlases on disk would be 4 MB of near-identical pixels in a
## repository that already carries the model, and every one of them would go
## stale the day the character is re-exported. Painting from whatever albedo is
## actually in the build means a re-export gets moods for free -- or, if the
## re-export moves the face, gets NONE, loudly, which is the next section.
##
## ## The guard, and why refusing is the right answer
##
## The feature positions are atlas coordinates. They were measured off the
## shipping texture by cropping it and looking (`tools/png_edit.py`), and they
## are stored as FRACTIONS of the texture size so a 512 or 2048 re-bake of the
## same layout still lands. What they cannot survive is a re-unwrap that moves
## the face somewhere else -- and the failure mode of getting that wrong is a
## child with a smile painted across his ear.
##
## So `can_paint()` checks the shipped face is where this file thinks it is: the
## pixel at the eye's centre must be dark, the pixel above it must be skin, and
## the pixel at the mouth must be pinker than the skin. Fail any of those and the
## whole mood system stands down and Bunny keeps the one face he was exported
## with. That is a visibly smaller feature, not a broken character.
##
## ## Units
##
## Everything in this file is in PIXELS OF THE ALBEDO, resolved from the
## fractions below against the actual image size. For scale: at the framing the
## game actually composes -- `camera_framing.gd` will not go closer than 1.9 m --
## Bunny's whole face is about 85 px on a 1334-wide screen and one eye is about
## 12 px, so a stroke has to be ~8 atlas pixels thick before it survives at all.

## The face features, as fractions of the atlas width/height:
## `[x0, y0, x1, y1]`, inclusive, origin top-left (glTF's UV convention, and
## Godot's `Image` convention, which is why no flip appears anywhere below).
##
## **THERE ARE THREE EYE BOXES FOR TWO EYES, and that is not a mistake.**
##
## The generator unwrapped the front of this head into two overlapping charts:
## one covering the whole face (u 261-460, v 533-701) and a second covering the
## LEFT half again (u 405-518, v 860-1011). Different triangles of the same
## surface sample different charts, so the character's left eye is painted in two
## places at once and both have to be repainted or half of it stays open. Found
## by rendering the sleeping pose, seeing one eye shut and one eye wide open, and
## then reading the mesh's own `TEXCOORD_0` against its `POSITION` to find out
## why: the verts behind the second eye sit at x -0.187..-0.009, which is the
## same left eye as `EYE_FAR`'s x -0.157..-0.086.
##
## `EYE_MAIN`  -- the right eye, nearly front-on, geometry at x +0.08..+0.24.
## `EYE_FAR`   -- the left eye in the main chart, foreshortened at its edge.
## `EYE_LEFT_B`-- the left eye AGAIN, in the second chart.
##
## There is no second mouth: the duplicate chart carries cheek and nose there,
## not lips, so one mouth box is the whole mouth.
const EYE_MAIN: Array[float] = [357.0 / 1024.0, 569.0 / 1024.0, 433.0 / 1024.0, 634.0 / 1024.0]
const EYE_FAR: Array[float] = [265.0 / 1024.0, 570.0 / 1024.0, 303.0 / 1024.0, 635.0 / 1024.0]
const EYE_LEFT_B: Array[float] = [431.0 / 1024.0, 886.0 / 1024.0, 488.0 / 1024.0, 950.0 / 1024.0]
const MOUTH: Array[float] = [298.0 / 1024.0, 663.0 / 1024.0, 356.0 / 1024.0, 696.0 / 1024.0]

## Every eye box, in one place, so a mood cannot repaint two of the three.
const EYES: Array = [EYE_MAIN, EYE_FAR, EYE_LEFT_B]

## Points the guard reads, as fractions. Inside the main eye, just above it, and
## on the lower lip.
const PROBE_IRIS := Vector2(394.0 / 1024.0, 601.0 / 1024.0)
## ...and the duplicate left eye, checked separately. If the second chart moved
## and the first did not, half a face would be repainted -- which is exactly the
## defect this whole constant block was written after.
const PROBE_IRIS_B := Vector2(460.0 / 1024.0, 917.0 / 1024.0)
const PROBE_BROW_SKIN := Vector2(394.0 / 1024.0, 565.0 / 1024.0)
const PROBE_LIP := Vector2(326.0 / 1024.0, 681.0 / 1024.0)
## The lash colour is lifted from the shipped upper lash line rather than being a
## constant, so a re-skin in another palette repaints in its own ink.
const PROBE_LASH := Vector2(400.0 / 1024.0, 576.0 / 1024.0)

const MOOD_CONTENT: String = "content"
const MOOD_UNHAPPY: String = "unhappy"
const MOOD_DELIGHTED: String = "delighted"
const MOOD_ASLEEP: String = "asleep"

const MOODS: Array[String] = [MOOD_CONTENT, MOOD_UNHAPPY, MOOD_DELIGHTED, MOOD_ASLEEP]

## How far outside the features the patch reaches. `_skin_fill()` samples 5 px
## above, 5 below and 3 to either side of every box it repaints, so the patch has
## to carry that much original texture with it or the fill would read its own
## half-finished output.
const PATCH_MARGIN: int = 8


## Is this texture the face this file was measured against? See the class doc:
## a `false` here means the mood system stands down entirely, which is a smaller
## feature rather than a broken one.
static func can_paint(base: Image) -> bool:
	if base == null or base.is_compressed():
		return false
	var size: Vector2i = base.get_size()
	if size.x < 256 or size.y < 256:
		return false
	var iris: Color = _sample(base, PROBE_IRIS)
	var skin: Color = _sample(base, PROBE_BROW_SKIN)
	var lip: Color = _sample(base, PROBE_LIP)
	if iris.get_luminance() > 0.35:
		return false
	if _sample(base, PROBE_IRIS_B).get_luminance() > 0.35:
		return false
	if skin.r < 0.75 or skin.g < 0.4 or skin.g > 0.88:
		return false
	# The lip is the same hue as the skin but further from white; "pinker" is the
	# only thing that separates them and it is the only thing checked.
	return lip.g < skin.g - 0.08


## The rectangle every mood confines itself to, in pixels. The caller keeps ONE
## working copy of the albedo and blits this region into it, so four moods cost
## four small patches rather than four megabyte textures.
static func patch_rect(base: Image) -> Rect2i:
	var size: Vector2i = base.get_size()
	var x0: int = 1 << 30
	var y0: int = 1 << 30
	var x1: int = 0
	var y1: int = 0
	for box: Array in [EYE_MAIN, EYE_FAR, EYE_LEFT_B, MOUTH]:
		var pixels: Array = _box(box, size)
		x0 = mini(x0, int(pixels[0]))
		y0 = mini(y0, int(pixels[1]))
		x1 = maxi(x1, int(pixels[2]))
		y1 = maxi(y1, int(pixels[3]))
	x0 = maxi(x0 - PATCH_MARGIN, 0)
	y0 = maxi(y0 - PATCH_MARGIN, 0)
	x1 = mini(x1 + PATCH_MARGIN, size.x - 1)
	y1 = mini(y1 + PATCH_MARGIN, size.y - 1)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## **One mood, as a patch.** Returns an image the size of `patch_rect()` holding
## the repainted face, or `null` when this texture is not the one this file knows
## how to read.
##
## `MOOD_CONTENT` returns the untouched region, so the caller has one code path
## for going back to the resting face as well as for leaving it.
static func paint(base: Image, mood: String) -> Image:
	if not can_paint(base):
		return null
	var rect: Rect2i = patch_rect(base)
	# A copy of the neighbourhood, worked on in place. `RGB8` because that is
	# what the shipping albedo is and an unnecessary conversion would cost a
	# megabyte per mood for nothing.
	var patch: Image = Image.create_empty(rect.size.x, rect.size.y, false, base.get_format())
	patch.blit_rect(base, rect, Vector2i.ZERO)
	if mood == MOOD_CONTENT:
		return patch

	var size: Vector2i = base.get_size()
	var origin := Vector2i(rect.position.x, rect.position.y)
	var eyes: Array = []
	for box: Array in EYES:
		eyes.append(_shift(_box(box, size), origin))
	var mouth: Array = _shift(_box(MOUTH, size), origin)
	var lash: Color = _sample(base, PROBE_LASH)
	var lip: Color = _sample(base, PROBE_LIP)

	match mood:
		MOOD_ASLEEP:
			# Eyes closed, the curve bowing DOWN in the middle -- lashes resting.
			# The mouth is left exactly as exported: the shipped face already has
			# the small contented smile a sleeping child wants, and repainting it
			# would only be a chance to make it worse.
			_close_eyes(patch, eyes, -8.0, 7.0, lash)
		MOOD_DELIGHTED:
			# Eyes closed, arched UP, which is the one shape that cannot be
			# mistaken for the sleeping one at 12 px, plus a wide open smile.
			_close_eyes(patch, eyes, 15.0, 8.0, lash)
			_skin_fill(patch, mouth)
			_open_smile(patch, mouth, lip)
		MOOD_UNHAPPY:
			# The eyes stay OPEN -- smaller, lower, half-lidded, but open. A
			# squeezed-shut crying face was the other candidate and it is the wrong
			# one twice over: it is the same silhouette as `delighted` at this
			# size, and a game with no failure state should not have a face that
			# looks like one. A wide-eyed child with a wobbly mouth asks; it does
			# not accuse.
			_sad_eyes(patch, eyes, _sample(base, PROBE_IRIS), lash)
			_skin_fill(patch, mouth)
			_downturned_mouth(patch, mouth, lip)
	return patch


# ---------------------------------------------------------------------------
# The features
# ---------------------------------------------------------------------------

## Erases every eye box back to skin and draws a closed lid across each.
##
## `amp` is the arc's sag in pixels at the eye's own width: POSITIVE puts the
## middle of the curve HIGHER than its ends (an arch, '^', delight), negative
## puts it lower (lashes down, sleep). It is scaled by the eye's width so the
## foreshortened far eye gets a proportionate curve rather than the same one.
##
## Two passes, and the order matters: EVERY eye is erased before ANY lid is
## drawn. The boxes do not overlap today, but they are three charts of two eyes
## and a re-unwrap that made two of them adjacent would otherwise have one fill
## rub out the lid its neighbour had just drawn.
static func _close_eyes(patch: Image, eyes: Array, amp: float,
		thickness: float, ink: Color) -> void:
	for box: Array in eyes:
		_skin_fill(patch, box)
	for box: Array in eyes:
		var width: float = float(box[2] - box[0])
		_stroke(patch,
			(box[0] + box[2]) * 0.5, (box[1] + box[3]) * 0.5,
			width * 0.46, amp * width / 76.0, thickness, ink)


## **Eyes redrawn small and low, with a heavy upper lid.**
##
## The first version of this kept the exported eye and simply painted skin over
## its top third. It looked right in the atlas and wrong on the model, for a
## reason only a render shows: the shipped eye's white sclera is a crescent
## running down the OUTER corner, well below any believable lid line, so every
## lid left a white wedge at the edge of each eye. Pushing the lid down far
## enough to swallow it swallowed the eye as well.
##
## So the eye is erased and redrawn instead: a smaller iris, dropped towards the
## bottom of the socket, one highlight so it is not a dead dot, and a lash line
## sitting across the top of it. Small and low is what "downcast" IS, and at this
## size it is the only part of it a player can see.
static func _sad_eyes(patch: Image, eyes: Array, iris: Color, lash: Color) -> void:
	for box: Array in eyes:
		_skin_fill(patch, box)
	for box: Array in eyes:
		var width: float = float(box[2] - box[0])
		var height: float = float(box[3] - box[1])
		var cx: float = (box[0] + box[2]) * 0.5
		var cy: float = float(box[1]) + height * 0.60
		var rx: float = width * 0.30
		var ry: float = height * 0.23
		_ellipse(patch, cx, cy, rx, ry, iris)
		# The highlight. A toddler's eye without one reads as a button.
		_ellipse(patch, cx - rx * 0.36, cy - ry * 0.40, rx * 0.26, ry * 0.26,
			Color(0.97, 0.96, 0.95, 1.0))
		# ...and the lid, heavy, across the top of it.
		_stroke(patch, cx, cy - ry * 0.95, rx * 1.22, height * 0.10, height * 0.13, lash)


## A wide open smile: a lens that closes to nothing at the corners, with a lip
## rim under it so the shape reads as a mouth rather than as a hole.
static func _open_smile(patch: Image, box: Array, lip: Color) -> void:
	var cx: float = (box[0] + box[2]) * 0.5
	var cy: float = float(box[1]) + (box[3] - box[1]) * 0.33
	var half: float = (box[2] - box[0]) * 0.40
	var depth: float = (box[3] - box[1]) * 0.46
	var dark := Color(lip.r * 0.42, lip.g * 0.42, lip.b * 0.42, 1.0)
	for x: int in range(int(cx - half), int(cx + half) + 1):
		var u: float = (float(x) - cx) / half
		var s: float = maxf(0.0, 1.0 - u * u)
		var top: float = cy - 2.0 * s
		var bottom: float = cy + depth * s
		if bottom - top < 1.0:
			continue
		for y: int in range(int(top) - 1, int(bottom) + 3):
			if float(y) < top - 0.5:
				continue
			if float(y) <= bottom:
				_blend(patch, x, y, dark,
					clampf(minf(float(y) - top + 1.0, bottom - float(y) + 1.0), 0.0, 1.0))
			else:
				_blend(patch, x, y, lip,
					clampf(2.5 - (float(y) - bottom), 0.0, 1.0) * 0.9)


## The corners of the mouth turned down. One stroke, in the lip's own colour
## darkened a little so it holds against the blush; no tears, no open wail.
static func _downturned_mouth(patch: Image, box: Array, lip: Color) -> void:
	_stroke(patch,
		(box[0] + box[2]) * 0.5, float(box[1]) + (box[3] - box[1]) * 0.39,
		(box[2] - box[0]) * 0.34, 9.0, 6.5,
		Color(lip.r * 0.78, lip.g * 0.78, lip.b * 0.78, 1.0))


## A soft filled ellipse. `_stroke()` draws lines; this is the only other shape
## the face needs, and between them they draw every feature in the file.
static func _ellipse(patch: Image, cx: float, cy: float, rx: float, ry: float,
		ink: Color) -> void:
	var edge: float = maxf(minf(rx, ry), 1.0)
	for y: int in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x: int in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx: float = (float(x) - cx) / maxf(rx, 0.5)
			var dy: float = (float(y) - cy) / maxf(ry, 0.5)
			var distance: float = sqrt(dx * dx + dy * dy)
			_blend(patch, x, y, ink, clampf((1.0 - distance) * edge + 0.5, 0.0, 1.0))


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

## **Repaints a box with the skin that surrounds it**, which is the operation the
## whole file rests on: you cannot draw a new eye without first removing the old
## one, and the old one is 76x65 px of black pupil in the middle of a cheek.
##
## Vertically it is a straight blend between the rows just above and just below
## the box, per column. That is exact at those two edges and it follows the blush
## gradient running down the cheek, which a flat fill does not -- the first
## version was a flat fill and it read as a sticking plaster.
##
## The left and right edges are then corrected to MEET the real pixels beside the
## box. Without that the patch shows as a rectangle, faintly but unmistakably,
## and a rectangle on a face is worse than an eye in the wrong mood.
##
## `lid`, when given, stops the fill part way down on a curve, leaving the rest
## of the eye showing underneath -- a lowered eyelid rather than a removed eye.
static func _skin_fill(patch: Image, box: Array, lid: Array = []) -> void:
	var x0: int = int(box[0])
	var y0: int = int(box[1])
	var x1: int = int(box[2])
	var y1: int = int(box[3])
	var height: float = float(maxi(y1 - y0, 1))
	var width: float = float(maxi(x1 - x0, 1))

	# The two bands the fill interpolates between, sampled once per column.
	#
	# A band that is not skin is the UV GUTTER -- the second chart's lower edge
	# runs into black a few columns wide -- and interpolating towards black would
	# draw a shadow down the cheek. Such a column falls back to the band at the
	# other end, and a column with skin at neither end is left alone entirely:
	# there is nothing to repaint it with, and the old eye is a better answer than
	# an invented colour.
	var tops: Array = []
	var bottoms: Array = []
	var usable: Array = []
	for x: int in range(x0, x1 + 1):
		var top: Color = _band(patch, x, y0 - 6, y0 - 2)
		var bottom: Color = _band(patch, x, y1 + 2, y1 + 6)
		var top_ok: bool = _is_skin(top)
		var bottom_ok: bool = _is_skin(bottom)
		if top_ok and not bottom_ok:
			bottom = top
		elif bottom_ok and not top_ok:
			top = bottom
		tops.append(top)
		bottoms.append(bottom)
		usable.append(top_ok or bottom_ok)
	# Smoothed ACROSS columns as well. Without it, the faint vertical marks that
	# the shipped texture already has above the eye -- a hair shadow, an airbrush
	# stroke -- are each carried the full height of the fill and the patch reads
	# as a set of stripes. Five columns is enough to lose them and short enough
	# that the blush gradient going sideways across the cheek is untouched.
	tops = _smooth(tops, usable)
	bottoms = _smooth(bottoms, usable)

	for y: int in range(y0, y1 + 1):
		var t: float = (float(y) - float(y0)) / height
		var left: Color = _band(patch, x0 - 3, y, y)
		var right: Color = _band(patch, x1 + 3, y, y)
		# The edge corrections are `Vector3`, not `Color`, and deliberately: they
		# are signed differences that are routinely negative and frequently zero,
		# and a zero one written as a colour is a `#000000` literal -- which
		# `test_ui_palette.gd` rightly refuses to have in this project. A delta is
		# not a colour.
		var dl := Vector3.ZERO
		var dr := Vector3.ZERO
		# A neighbour that is not skin is a DIFFERENT UV island -- the far eye has
		# a white one hard against it -- and correcting towards it would drag that
		# island's colour across the face. Ignored rather than trusted.
		if _is_skin(left):
			dl = _difference(left, (tops[0] as Color).lerp(bottoms[0] as Color, t))
		if _is_skin(right):
			var last: int = tops.size() - 1
			dr = _difference(right, (tops[last] as Color).lerp(bottoms[last] as Color, t))
		for x: int in range(x0, x1 + 1):
			if not usable[x - x0]:
				continue
			if not lid.is_empty():
				var u: float = (float(x) - (float(x0) + float(x1)) * 0.5) / (width * 0.5)
				if float(y) > float(lid[0]) + float(lid[1]) * u * u:
					continue
			var s: float = (float(x) - float(x0)) / width
			var value: Color = (tops[x - x0] as Color).lerp(bottoms[x - x0] as Color, t)
			var fixed: Vector3 = dl * (1.0 - s) + dr * s
			patch.set_pixel(x, y, Color(
				clampf(value.r + fixed.x, 0.0, 1.0),
				clampf(value.g + fixed.y, 0.0, 1.0),
				clampf(value.b + fixed.z, 0.0, 1.0), 1.0))


## A quadratic arc drawn as a soft, round-ended stroke.
##
## `amp > 0` puts the middle of the curve HIGHER than its ends; `amp < 0` lower.
## The stroke thins towards the ends (`taper`) because a closed eye that stops
## dead at full width reads as a drawn line, and a lash does not.
static func _stroke(patch: Image, cx: float, cy: float, half_w: float, amp: float,
		thickness: float, ink: Color, taper: float = 0.45) -> void:
	for x: int in range(int(cx - half_w), int(cx + half_w) + 1):
		var u: float = (float(x) - cx) / maxf(half_w, 1.0)
		var y: float = cy + amp * u * u
		var half_t: float = thickness * 0.5 * (1.0 - taper * u * u)
		for py: int in range(int(y - half_t) - 1, int(y + half_t) + 2):
			_blend(patch, x, py, ink, clampf(half_t + 0.5 - absf(float(py) - y), 0.0, 1.0))


static func _blend(patch: Image, x: int, y: int, ink: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	if x < 0 or y < 0 or x >= patch.get_width() or y >= patch.get_height():
		return
	patch.set_pixel(x, y, patch.get_pixel(x, y).lerp(ink, minf(alpha, 1.0)))


## A five-tap box filter along an array of per-column colours, skipping columns
## with nothing usable in them.
static func _smooth(values: Array, usable: Array) -> Array:
	var out: Array = []
	for index: int in range(values.size()):
		var total := Vector3.ZERO
		var count: int = 0
		for step: int in range(-2, 3):
			var at: int = index + step
			if at < 0 or at >= values.size() or not usable[at]:
				continue
			var colour: Color = values[at]
			total += Vector3(colour.r, colour.g, colour.b)
			count += 1
		if count == 0:
			out.append(values[index])
			continue
		total /= float(count)
		out.append(Color(total.x, total.y, total.z, 1.0))
	return out


## Channel-by-channel `a - b`. See `_skin_fill()` for why this is a `Vector3`.
static func _difference(a: Color, b: Color) -> Vector3:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b)


## The mean of a short vertical run, so one stray pixel cannot set a whole
## column's fill colour. Accumulated as a `Vector3` for the same reason the
## deltas are: an empty accumulator is not a black.
static func _band(patch: Image, x: int, y0: int, y1: int) -> Color:
	x = clampi(x, 0, patch.get_width() - 1)
	var total := Vector3.ZERO
	var count: int = 0
	for y: int in range(y0, y1 + 1):
		var pixel: Color = patch.get_pixel(x, clampi(y, 0, patch.get_height() - 1))
		total += Vector3(pixel.r, pixel.g, pixel.b)
		count += 1
	total /= float(maxi(count, 1))
	return Color(total.x, total.y, total.z, 1.0)


## Skin, as opposed to the white and pale-blue islands packed against the face in
## the atlas. Deliberately loose -- it only has to separate "cheek" from "sock".
static func _is_skin(colour: Color) -> bool:
	return colour.r > 0.78 and colour.g > 0.43 and colour.g < 0.86 and colour.b < 0.80


static func _sample(base: Image, at: Vector2) -> Color:
	var size: Vector2i = base.get_size()
	return base.get_pixel(
		clampi(int(at.x * float(size.x)), 0, size.x - 1),
		clampi(int(at.y * float(size.y)), 0, size.y - 1))


## A fractional box resolved against a real image size, in pixels.
static func _box(box: Array, size: Vector2i) -> Array:
	return [
		roundi(box[0] * float(size.x)), roundi(box[1] * float(size.y)),
		roundi(box[2] * float(size.x)), roundi(box[3] * float(size.y)),
	]


static func _shift(box: Array, origin: Vector2i) -> Array:
	return [box[0] - origin.x, box[1] - origin.y, box[2] - origin.x, box[3] - origin.y]
