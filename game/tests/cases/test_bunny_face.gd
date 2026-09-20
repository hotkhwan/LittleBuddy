extends RefCounted

## Bunny's face -- the part of "he looks unhappy" that can be asserted.
##
## The rigged model has NO facial bones. The skeleton ends at `headfront`, there
## is no jaw and no eyelid, and the eyes and mouth are painted into a 1024x1024
## albedo. So the expression is a TEXTURE, repainted by `baby_face_moods.gd`, and
## what is pinned here is everything that can go wrong with that without anybody
## noticing:
##
##   1. **Every eye is repainted.** The generator unwrapped the front of this
##      head into two overlapping charts, so the character's left eye exists in
##      the atlas TWICE. The first version of this feature painted two of the
##      three boxes; the result was a sleeping child with one eye wide open, and
##      it was invisible from the front because the front-on view happens to
##      sample the chart that WAS painted. That is the defect `_test_every_eye`
##      exists for, and it is not a hypothetical.
##   2. **Nothing bleeds outside the boxes.** A repaint that wandered would put
##      a mouth on an ear, and it would do it on one frame of one activity.
##   3. **The mood is derived from the CLIP.** One decision, in `child_life.gd`,
##      so the face cannot end up smiling through a fuss.
##   4. **It stands down rather than guessing.** Handed a texture that is not
##      this face, the painter must refuse -- a wrong repaint is much worse than
##      no repaint.
##   5. **Nothing here punishes the child.** `CLAUDE.md`, Child UX. A face is
##      exactly where a "you were too slow" would appear first.
##
## Every helper that needs the real atlas skips -- loudly, in the sense that
## `_test_the_pure_rules` still runs -- when the export is absent, the same way
## `test_bunny_life.gd` does.

const Faces := preload("res://scripts/characters/little_buddy/baby_face_moods.gd")
const Life := preload("res://scripts/care/child_life.gd")
const Present := preload("res://scripts/care/child_presentation.gd")
const Needs := preload("res://scripts/care/child_needs.gd")
const Baby := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
const Actor := preload("res://scripts/care/child_actor.gd")

## How different a box has to be before it counts as repainted: the mean
## absolute channel difference over the box, 0-1.
const REPAINTED: float = 0.02


func test_name() -> String:
	return "bunny_face"


func run():
	var failures: Array = []
	failures.append_array(_test_the_mood_vocabulary())
	failures.append_array(_test_the_mood_follows_the_clip())
	failures.append_array(_test_nothing_here_punishes_the_child())
	failures.append_array(_test_every_eye_is_repainted())
	failures.append_array(_test_the_resting_face_is_the_exported_one())
	failures.append_array(_test_it_refuses_a_face_it_does_not_know())
	failures.append_array(_test_the_actor_paints_what_the_body_says())
	return failures


# ---------------------------------------------------------------------------
# 1. The vocabulary, pure
# ---------------------------------------------------------------------------

func _test_the_mood_vocabulary():
	var failures: Array = []
	# The two files name the moods independently -- `child_life.gd` may not load
	# anything that touches an `Image` -- so they are checked against each other
	# rather than one importing the other.
	for mood: String in Life.FACE_MOODS:
		if not Faces.MOODS.has(mood):
			failures.append(("child_life.gd offers the face '%s' and baby_face_moods.gd cannot "
					+ "paint it. `set_face_mood()` would silently refuse and Bunny would keep "
					+ "whatever face he had.") % mood)
	for mood: String in Faces.MOODS:
		if not Life.FACE_MOODS.has(mood):
			failures.append("baby_face_moods.gd paints '%s' and nothing ever asks for it" % mood)
	if Faces.MOODS.size() < 4:
		failures.append("only %d faces are authored; the pass promised content, unhappy, "
				% Faces.MOODS.size() + "delighted and asleep")
	if Faces.EYES.size() != 3:
		failures.append(("%d eye boxes are listed. This head is unwrapped into two overlapping "
				+ "charts and the left eye is painted in BOTH -- three boxes for two eyes. "
				+ "Dropping one leaves half a face awake.") % Faces.EYES.size())
	return failures


func _test_the_mood_follows_the_clip():
	var failures: Array = []
	var expected: Dictionary = {
		Life.LIFE_FUSS: Life.FACE_UNHAPPY,
		Life.LIFE_HAPPY: Life.FACE_DELIGHTED,
		Life.LIFE_SLEEP: Life.FACE_ASLEEP,
		Life.LIFE_IDLE: Life.FACE_CONTENT,
		Life.LIFE_EAT: Life.FACE_CONTENT,
		Life.LIFE_DRINK: Life.FACE_CONTENT,
		Life.LIFE_WALK: Life.FACE_CONTENT,
	}
	for clip: String in expected.keys():
		var got: String = Life.face_for(clip)
		if got != expected[clip]:
			failures.append("the '%s' clip wears the '%s' face, expected '%s'"
					% [clip, got, String(expected[clip])])
	# Total: an unknown clip must still answer, and answer with the resting face.
	if Life.face_for("somethingNobodyAuthored") != Life.FACE_CONTENT:
		failures.append("an unknown clip produced '%s'; the mapping must be total or a build "
				% Life.face_for("somethingNobodyAuthored") + "with one extra clip has no face")
	# ...and it is derived from the clip, which is what keeps the mouth and the
	# arms agreeing. A hungry child fusses, so a hungry child is unhappy-faced.
	var hungry: Dictionary = _stats(70.0)
	if Life.face_for(Life.clip_for(hungry, Present.ACTIVITY_IDLE, false, 0.0)) != Life.FACE_UNHAPPY:
		failures.append("a hungry Bunny does not wear the unhappy face")
	if Life.face_for(Life.clip_for(hungry, Present.ACTIVITY_IDLE, false, 1.0)) != Life.FACE_DELIGHTED:
		failures.append("a Bunny inside the happy window does not look pleased")
	if Life.face_for(Life.clip_for(hungry, Present.ACTIVITY_BEDTIME, false, 0.0)) != Life.FACE_ASLEEP:
		failures.append("a Bunny at bedtime does not have his eyes shut")
	return failures


## `CLAUDE.md`: no failure pressure, no score, no red X. The face is the first
## place a "you were too slow" would show up, so the same executable-code scan
## `test_bunny_life.gd` applies to the clips is applied here.
func _test_nothing_here_punishes_the_child():
	var failures: Array = []
	var source: String = _code_of(_read(
		"res://scripts/characters/little_buddy/baby_face_moods.gd")).to_lower()
	if source.strip_edges().length() < 400:
		failures.append("baby_face_moods.gd stripped to almost nothing; this scan would pass "
				+ "vacuously")
		return failures
	for banned: String in ["score", "percent", "penalt", "countdown", "angry", "cross"]:
		if source.contains(banned):
			failures.append(("baby_face_moods.gd uses '%s' in executable code. The face reacts to "
					+ "the CHILD's state, never to the player's performance.") % banned)
	# And the mood a child sees most when something is wrong is a SAD one, not an
	# angry one: `unhappy` must be reachable and `delighted` must not be the only
	# non-resting face, or the game has no way to say "I need something".
	if not Faces.MOODS.has(Faces.MOOD_UNHAPPY):
		failures.append("there is no unhappy face; a need the child cannot show is a need the "
				+ "player cannot see")
	return failures


# ---------------------------------------------------------------------------
# 2. The painting, against the real atlas
# ---------------------------------------------------------------------------

## **The regression that cost this pass an afternoon.** Every eye box must come
## back different from the exported atlas, for every mood that closes or lowers
## the eyes. Painting two of three looked completely correct from the front.
func _test_every_eye_is_repainted():
	var failures: Array = []
	var base: Image = _albedo()
	if base == null:
		return failures
	if not Faces.can_paint(base):
		failures.append("baby_face_moods.gd does not recognise the shipping albedo as a face; "
				+ "every mood would stand down and Bunny would have one expression")
		return failures

	var rect: Rect2i = Faces.patch_rect(base)
	for mood: String in [Faces.MOOD_UNHAPPY, Faces.MOOD_DELIGHTED, Faces.MOOD_ASLEEP]:
		var patch: Image = Faces.paint(base, mood)
		if patch == null:
			failures.append("the '%s' face painted nothing at all" % mood)
			continue
		for index: int in range(Faces.EYES.size()):
			var box: Array = _pixels(Faces.EYES[index], base.get_size(), rect)
			var moved: float = _difference(base, patch, box, rect)
			if moved < REPAINTED:
				failures.append(("the '%s' face left eye box %d untouched (mean change %.4f). "
						+ "This head is unwrapped twice and the left eye is in the atlas in two "
						+ "places; painting one of them renders as a child with one eye shut.")
						% [mood, index, moved])
		# ...and nothing wandered outside the boxes. A stroke that overran would
		# put a lash across a cheek on one activity only.
		var stray: Array = _stray_pixels(base, patch, rect)
		if stray.size() > 0:
			failures.append(("the '%s' face changed %d pixels outside its own eye and mouth "
					+ "boxes, first at atlas (%d, %d)") % [mood, stray.size(), stray[0], stray[1]])
	return failures


## The resting face is the exported one, to the pixel. It is painted through the
## same code path as the others so that "go back to normal" cannot rot, and this
## is the assertion that says the path really is a no-op.
func _test_the_resting_face_is_the_exported_one():
	var failures: Array = []
	var base: Image = _albedo()
	if base == null or not Faces.can_paint(base):
		return failures
	var rect: Rect2i = Faces.patch_rect(base)
	var patch: Image = Faces.paint(base, Faces.MOOD_CONTENT)
	if patch == null:
		failures.append("the resting face painted nothing; there would be no way back to it")
		return failures
	if patch.get_size() != rect.size:
		failures.append("the resting patch is %s but patch_rect() says %s -- the blit would land "
				% [str(patch.get_size()), str(rect.size)] + "in the wrong place")
	for y: int in range(0, rect.size.y, 3):
		for x: int in range(0, rect.size.x, 3):
			if base.get_pixel(rect.position.x + x, rect.position.y + y) \
					!= patch.get_pixel(x, y):
				failures.append(("the resting face differs from the exported albedo at (%d, %d). "
						+ "It is supposed to be the untouched texture.")
						% [rect.position.x + x, rect.position.y + y])
				return failures
	return failures


## Handed something that is not this face, the painter must refuse rather than
## draw a mouth wherever the numbers happen to land.
func _test_it_refuses_a_face_it_does_not_know():
	var failures: Array = []
	var flat: Image = Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
	flat.fill(Color(0.6, 0.7, 0.8, 1.0))
	if Faces.can_paint(flat):
		failures.append("a flat blue square was accepted as Bunny's face")
	if Faces.paint(flat, Faces.MOOD_ASLEEP) != null:
		failures.append("a face the painter does not recognise was painted anyway. A repaint in "
				+ "the wrong place is far worse than no repaint.")
	if Faces.can_paint(null):
		failures.append("a null image was accepted as a face")

	# ...and the real one, with its eyes filled in with skin, is refused too --
	# which is the case that actually happens: a re-unwrap moves the features and
	# leaves the atlas looking superficially the same.
	var base: Image = _albedo()
	if base != null:
		var moved: Image = base.duplicate()
		var size: Vector2i = moved.get_size()
		var box: Array = _pixels(Faces.EYE_MAIN, size, Rect2i(0, 0, size.x, size.y))
		for y: int in range(int(box[1]), int(box[3]) + 1):
			for x: int in range(int(box[0]), int(box[2]) + 1):
				moved.set_pixel(x, y, Color(0.99, 0.75, 0.68, 1.0))
		if Faces.can_paint(moved):
			failures.append("an atlas with no eye where the eye should be was still accepted")
	return failures


# ---------------------------------------------------------------------------
# 3. Through the real actor
# ---------------------------------------------------------------------------

func _test_the_actor_paints_what_the_body_says():
	var failures: Array = []
	if not Baby.is_pose_available(Baby.PREFERRED_POSE):
		return failures
	var bunny: Node3D = Node3D.new()
	bunny.set_script(Actor)
	bunny.call("build")

	var stats: RefCounted = bunny.call("get_stats")
	stats.call("set_stat", "hunger", 5.0)
	stats.call("set_stat", "thirst", 5.0)
	bunny.call("_refresh")
	if String(bunny.call("get_face_mood")) != Life.FACE_CONTENT:
		failures.append("a content Bunny is wearing the '%s' face"
				% String(bunny.call("get_face_mood")))

	stats.call("set_stat", "hunger", 72.0)
	bunny.call("_refresh")
	if String(bunny.call("get_life_clip")) == Life.LIFE_FUSS \
			and String(bunny.call("get_face_mood")) != Life.FACE_UNHAPPY:
		failures.append(("Bunny's body is fussing and his face is '%s'. The two are decided "
				+ "together on purpose; a smile over a fuss is the statue problem with a "
				+ "different face on it.") % String(bunny.call("get_face_mood")))

	bunny.call("satisfy", Needs.HUNGRY, 70.0)
	if String(bunny.call("get_face_mood")) != Life.FACE_DELIGHTED:
		failures.append("Bunny was just fed and is wearing '%s'"
				% String(bunny.call("get_face_mood")))

	bunny.call("set_activity", Present.ACTIVITY_BEDTIME)
	if String(bunny.call("get_face_mood")) != Life.FACE_ASLEEP:
		failures.append("Bunny was put to bed with his eyes '%s'"
				% String(bunny.call("get_face_mood")))
	bunny.free()
	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _stats(hunger: float) -> Dictionary:
	return {
		"hunger": hunger, "thirst": 10.0, "happiness": 80.0,
		"energy": 90.0, "cleanliness": 90.0, "freshness": 90.0,
	}


## The albedo the shipping model actually renders with, or null when the export
## is not in this checkout.
func _albedo() -> Image:
	if not Baby.is_pose_available(Baby.PREFERRED_POSE):
		return null
	var wrapper: Node3D = Baby.new()
	wrapper.call("build")
	var mesh: MeshInstance3D = _find_mesh(wrapper)
	var image: Image = null
	if mesh != null:
		var material: StandardMaterial3D = \
			mesh.get_surface_override_material(0) as StandardMaterial3D
		# `_prepare_face()` has already swapped in its own working texture by now,
		# and it starts life as a pixel-for-pixel copy of the exported albedo --
		# which is what `_test_the_resting_face_is_the_exported_one()` then checks
		# from the other side.
		if material != null and material.albedo_texture != null:
			image = material.albedo_texture.get_image()
			if image != null and image.is_compressed():
				image = null
	if image != null:
		image = image.duplicate()
	wrapper.free()
	return image


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh(child)
		if found != null:
			return found
	return null


## A fractional box resolved to pixels of the PATCH.
func _pixels(box: Array, size: Vector2i, rect: Rect2i) -> Array:
	return [
		roundi(box[0] * float(size.x)) - rect.position.x,
		roundi(box[1] * float(size.y)) - rect.position.y,
		roundi(box[2] * float(size.x)) - rect.position.x,
		roundi(box[3] * float(size.y)) - rect.position.y,
	]


## Mean absolute channel change inside a box of the patch, against the same
## region of the base.
func _difference(base: Image, patch: Image, box: Array, rect: Rect2i) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(int(box[1]), int(box[3]) + 1):
		for x: int in range(int(box[0]), int(box[2]) + 1):
			var a: Color = base.get_pixel(rect.position.x + x, rect.position.y + y)
			var b: Color = patch.get_pixel(x, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			count += 3
	return total / float(maxi(count, 1))


## Every changed pixel that is not inside one of the feature boxes, as
## `[x, y, ...]` in ATLAS coordinates. Empty is the only acceptable answer.
func _stray_pixels(base: Image, patch: Image, rect: Rect2i) -> Array:
	var size: Vector2i = base.get_size()
	var boxes: Array = []
	for box: Array in Faces.EYES:
		boxes.append(_pixels(box, size, rect))
	boxes.append(_pixels(Faces.MOUTH, size, rect))
	var stray: Array = []
	for y: int in range(rect.size.y):
		for x: int in range(rect.size.x):
			var inside: bool = false
			for box: Array in boxes:
				if x >= int(box[0]) and x <= int(box[2]) \
						and y >= int(box[1]) and y <= int(box[3]):
					inside = true
					break
			if inside:
				continue
			if base.get_pixel(rect.position.x + x, rect.position.y + y) != patch.get_pixel(x, y):
				stray.append(rect.position.x + x)
				stray.append(rect.position.y + y)
				if stray.size() >= 8:
					return stray
	return stray


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Source with every comment removed and every string literal blanked, leaving
## executable code. Lifted deliberately from `test_architecture_guard.gd`, which
## documents both why it is needed and why a `#` inside a string must not be read
## as the start of a comment.
static func _code_of(text: String) -> String:
	var code: String = ""
	for raw_line: String in text.split("\n"):
		var out: String = ""
		var quote: String = ""
		var index: int = 0
		while index < raw_line.length():
			var character: String = raw_line[index]
			if quote.is_empty():
				if character == "#":
					break
				if character == "\"" or character == "'":
					quote = character
				else:
					out += character
			else:
				if character == "\\":
					index += 1
				elif character == quote:
					quote = ""
			index += 1
		code += out + "\n"
	return code
