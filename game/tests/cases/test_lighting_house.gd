extends RefCounted

## The house's light, pinned.
##
## `ART_BIBLE.md` §7 is already guarded by `test_art_rooms.gd`: one
## `DirectionalLight3D`, shadows off, no GI/SSAO/SSIL/SSR/glow/volumetric
## fog/DOF/colour-correction, an explicit ambient colour. **Nothing here weakens
## any of that** — every assertion below is additional, and the two files are
## expected to both pass.
##
## What this adds is the thing no existing test could see: the scene's light
## matrix was the TRANSPOSE of the one its own comment described, so the house
## was lit from 36.8° below the floor. A transposed rotation is still a valid
## rotation. It does not error, it does not warn, and a test that only counts
## lights and checks flags will report PASS on a sun shining up through the
## floorboards for as long as it stands there.
##
## So the sun's **direction** is asserted, in world terms a person can argue
## with — above the horizon, and lighting the planes a doll's-house room shows
## the camera — and the scene's numbers are asserted to be the same ones
## `scripts/house/lighting.gd` documents, so the copy in the file and the copy in
## the code cannot drift apart.

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const MENU_SCENE: String = "res://scenes/main/main.tscn"
const Lighting := preload("res://scripts/house/lighting.gd")
const Palette := preload("res://scripts/ui/palette.gd")

## Floating point in a text file, read back through a parser.
const EPSILON: float = 0.002


func test_name():
	return "lighting_house"


func run():
	var failures = []
	failures.append_array(_test_sun_is_above_the_horizon())
	failures.append_array(_test_scene_matches_lighting_module())
	failures.append_array(_test_key_and_fill_are_warm_and_in_palette())
	failures.append_array(_test_nothing_forbidden_was_introduced())
	failures.append_array(_test_menu_fill_matches_the_house())
	return failures


## The regression this file exists for.
##
## A `DirectionalLight3D` lights along `-Z` of its basis, so basis `+Z` points AT
## the sun and `basis.z.y` is the sine of its elevation. It was `-0.599`.
func _test_sun_is_above_the_horizon():
	var failures = []
	var basis: Basis = _scene_light_basis(HOUSE_SCENE)
	if basis == Basis():
		return ["could not parse the house light's transform out of %s" % HOUSE_SCENE]

	var to_sun: Vector3 = basis.z
	if to_sun.y <= 0.0:
		failures.append(("the house sun is BELOW the floor: basis.z = (%.3f, %.3f, %.3f), "
				+ "elevation %.1f degrees. `Transform3D(...)` takes its nine basis values "
				+ "ROW-major; writing them as the x/y/z axes transposes the matrix, which is "
				+ "a valid rotation and so fails silently. Every upward-facing surface in the "
				+ "house -- floor, worktop, table, bed, and the top of every head -- then gets "
				+ "zero key light. See scripts/house/lighting.gd.") % [
				to_sun.x, to_sun.y, to_sun.z, rad_to_deg(asin(to_sun.y))])
		return failures

	# Mid-morning (section 7: "permanently mid-morning"), not noon and not dusk.
	var elevation: float = rad_to_deg(asin(clampf(to_sun.y, -1.0, 1.0)))
	if elevation < 30.0 or elevation > 65.0:
		failures.append(("the house sun sits at %.1f degrees. Section 7 asks for permanently "
				+ "mid-morning: below ~30 the rooms rake into near-silhouette, above ~65 the "
				+ "walls flatten out and only the floor is lit.") % elevation)

	# The floor must be the best-lit plane -- that is what "sunlit room" means --
	# and the two side walls must NOT arrive at the same value, or the corner
	# between a side wall and the back wall disappears.
	var floor_key: float = maxf(0.0, to_sun.y)
	var back_key: float = maxf(0.0, to_sun.z)
	var lit_side: float = maxf(0.0, absf(to_sun.x))
	if floor_key <= lit_side or floor_key <= back_key:
		failures.append(("the floor is not the best-lit plane in the house (floor %.2f, lit "
				+ "side wall %.2f, back wall %.2f). A room lit less on the floor than on a "
				+ "wall does not read as sunlit.") % [floor_key, back_key, lit_side])
	if absf(lit_side - back_key) < 0.12:
		failures.append(("the lit side wall (%.2f of key) and the back wall (%.2f) are within "
				+ "0.12 of each other, so the corner between them has almost no value step and "
				+ "the two planes read as one surface. Swing the azimuth.") % [
				lit_side, back_key])
	return failures


## The scene file and `lighting.gd::AFTER` are two copies of one decision. The
## scene needs them so it looks right in the editor with no script running; the
## module needs them so the benchmark can photograph a before and an after in one
## run. This is the guard that stops them drifting.
func _test_scene_matches_lighting_module():
	var failures = []
	var text: String = _read(HOUSE_SCENE)
	if text.is_empty():
		return ["%s could not be read" % HOUSE_SCENE]
	var values: Dictionary = Lighting.AFTER

	var expected: Basis = Lighting.key_basis(
			float(values["elevation"]), float(values["azimuth"]))
	var actual: Basis = _scene_light_basis(HOUSE_SCENE)
	if (actual.z - expected.z).length() > EPSILON * 4.0:
		failures.append(("the house light points (%.3f, %.3f, %.3f) but lighting.gd's AFTER "
				+ "says elevation %.1f / azimuth %.1f, which is (%.3f, %.3f, %.3f). One of "
				+ "the two was changed without the other.") % [
				actual.z.x, actual.z.y, actual.z.z,
				float(values["elevation"]), float(values["azimuth"]),
				expected.z.x, expected.z.y, expected.z.z])

	for pair: Array in [
		["ambient_light_energy", float(values["ambientEnergy"])],
		["light_energy", float(values["keyEnergy"])],
		["light_angular_distance", float(values["angularDistance"])],
	]:
		var found: float = _scene_float(text, String(pair[0]))
		if absf(found - float(pair[1])) > EPSILON:
			failures.append("%s is %.3f in the scene and %.3f in lighting.gd" % [
					pair[0], found, float(pair[1])])

	for pair: Array in [
		["ambient_light_color", values["ambientColor"]],
		["background_color", values["backgroundColor"]],
		["light_color", values["keyColor"]],
	]:
		var found: Color = _scene_color(text, String(pair[0]))
		if not _close(found, pair[1]):
			failures.append("%s is %s in the scene and %s in lighting.gd" % [
					pair[0], found.to_html(false), (pair[1] as Color).to_html(false)])
	return failures


## Section 3: the fill is what colours every shaded surface in the game, so it is
## as much a palette decision as an albedo is. `cream` fill on `cream` walls can
## only ever produce more cream, which is the "milky" look; the rule is "never
## darken by reducing value alone -- always mix toward `ink`", and a fill mixed
## toward `peach` is that rule applied to light instead of paint.
func _test_key_and_fill_are_warm_and_in_palette():
	var failures = []
	var values: Dictionary = Lighting.AFTER
	for pair: Array in [
		["the ambient fill", values["ambientColor"]],
		["the key light", values["keyColor"]],
		["the background void", values["backgroundColor"]],
	]:
		var color: Color = pair[1]
		if Palette.is_black(color):
			failures.append("%s is pure black; section 3 bans #000000 everywhere" % pair[0])
		if Palette.is_red(color):
			failures.append("%s reads as red; section 3 bans it" % pair[0])
		if Palette.is_grey(color):
			failures.append(("%s has no warmth left in it (%s). Section 7 wants a warm fill: "
					+ "a neutral one is what makes a pastel room look grubby.") % [
					pair[0], color.to_html(false)])
		if color.b > color.r:
			failures.append("%s is cooler than it is warm (%s); the house is permanently "
					% [pair[0], color.to_html(false)] + "mid-morning")

	# The fill must be WARMER than the key, not the other way round: that is what
	# puts warmth into the shadows rather than into the highlights.
	var fill_warmth: float = float(values["ambientColor"].r) - float(values["ambientColor"].b)
	var key_warmth: float = float(values["keyColor"].r) - float(values["keyColor"].b)
	if fill_warmth <= key_warmth:
		failures.append(("the fill (%.3f) is not warmer than the key (%.3f). Shadows here are "
				+ "lit by the fill alone, and section 3 wants them warm, not pale.") % [
				fill_warmth, key_warmth])

	# Not brighter. The brief for this pass was explicit about it, and the
	# failure mode of every "make it pop" change is more energy.
	var before_total: float = float(Lighting.BEFORE["ambientEnergy"]) \
			+ float(Lighting.BEFORE["keyEnergy"])
	var after_total: float = float(values["ambientEnergy"]) + float(values["keyEnergy"])
	if after_total > before_total:
		failures.append(("total light energy went UP, %.2f -> %.2f. This pass is about the "
				+ "ratio between fill and key, not the level.") % [before_total, after_total])
	return failures


## Section 7's forbidden list, plus the two things this pass could plausibly have
## been tempted into: a second light, and switching the directional shadows back
## on to buy contact darkening. Neither is available. The mitigation section 7
## names for floaty objects is a contact-shadow DECAL, not this light.
func _test_nothing_forbidden_was_introduced():
	var failures = []
	for scene: String in [HOUSE_SCENE, MENU_SCENE]:
		var text: String = _read(scene)
		if text.is_empty():
			failures.append("%s could not be read" % scene)
			continue
		if text.count('type="DirectionalLight3D"') != 1:
			failures.append("%s must hold exactly one DirectionalLight3D (section 7)" % scene)
		for banned: String in ['type="OmniLight3D"', 'type="SpotLight3D"',
				'type="ReflectionProbe"', 'type="VoxelGI"', 'type="LightmapGI"',
				"sdfgi_enabled = true", "ssao_enabled = true", "ssil_enabled = true",
				"ssr_enabled = true", "glow_enabled = true",
				"volumetric_fog_enabled = true", "fog_enabled = true",
				"dof_blur_far_enabled = true", "dof_blur_near_enabled = true",
				"adjustment_enabled = true"]:
			if text.contains(banned):
				failures.append("%s has `%s`; section 7 forbids it" % [scene, banned])
	var house: String = _read(HOUSE_SCENE)
	if not house.contains("shadow_enabled = false"):
		failures.append("the house light casts directional shadows again. They were turned "
				+ "off after a device review (section 7 amendment, 2026-09-18) and this "
				+ "lighting pass did not earn the right to undo that.")
	# Ambient must stay an explicit colour: `test_art_rooms.gd` asserts the same
	# thing, and a sky-based fill would be a different (and costlier) answer.
	if not house.contains("ambient_light_source = 2"):
		failures.append("the house lost its explicit ambient colour (section 7)")
	return failures


## One house, one colour temperature. The menu is a different scene with its own
## sun and its own framing, and this does not try to make it the same shot -- but
## its FILL is what a child sees a second before the house appears, and the two
## reading as different times of day is a seam.
func _test_menu_fill_matches_the_house():
	var failures = []
	var text: String = _read(MENU_SCENE)
	if text.is_empty():
		return ["%s could not be read" % MENU_SCENE]
	var menu_fill: Color = _scene_color(text, "ambient_light_color")
	if not _close(menu_fill, Lighting.AFTER["ambientColor"]):
		failures.append("the menu's fill is %s and the house's is %s; pressing Play is a jump "
				% [menu_fill.to_html(false),
				(Lighting.AFTER["ambientColor"] as Color).to_html(false)]
				+ "in colour temperature")
	# The menu's sun is its own, but it must also be above the horizon.
	var basis: Basis = _scene_light_basis(MENU_SCENE)
	if basis != Basis() and basis.z.y <= 0.0:
		failures.append("the menu sun is below the horizon too (basis.z.y = %.3f)" % basis.z.y)
	return failures


## -- Helpers -------------------------------------------------------------------

## Parses the FIRST `transform = Transform3D(...)` that belongs to the scene's
## `DirectionalLight3D`, and builds the basis the way the engine does: the nine
## values are ROW-major. Getting this wrong in the test as well as in the scene
## would make the test agree with the bug, so it is spelled out.
func _scene_light_basis(scene_path: String) -> Basis:
	var text: String = _read(scene_path)
	var at: int = text.find('type="DirectionalLight3D"')
	if at < 0:
		return Basis()
	var line_at: int = text.find("transform = Transform3D(", at)
	if line_at < 0:
		return Basis()
	var open_at: int = text.find("(", line_at)
	var close_at: int = text.find(")", open_at)
	if open_at < 0 or close_at < 0:
		return Basis()
	var parts: PackedStringArray = text.substr(
			open_at + 1, close_at - open_at - 1).split(",")
	if parts.size() < 9:
		return Basis()
	var numbers: Array[float] = []
	for part: String in parts:
		numbers.append(float(part.strip_edges()))
	var basis := Basis()
	basis.x = Vector3(numbers[0], numbers[3], numbers[6])
	basis.y = Vector3(numbers[1], numbers[4], numbers[7])
	basis.z = Vector3(numbers[2], numbers[5], numbers[8])
	return basis


func _scene_float(text: String, key: String) -> float:
	var at: int = text.find("\n%s = " % key) + 1
	if at < 1:
		return NAN
	var from: int = at + key.length() + 3
	var to: int = text.find("\n", from)
	return float(text.substr(from, to - from).strip_edges())


func _scene_color(text: String, key: String) -> Color:
	var at: int = text.find("\n%s = Color(" % key) + 1
	if at < 1:
		return Color(0, 0, 0, 0)
	var open_at: int = text.find("(", at)
	var close_at: int = text.find(")", open_at)
	var parts: PackedStringArray = text.substr(
			open_at + 1, close_at - open_at - 1).split(",")
	if parts.size() < 3:
		return Color(0, 0, 0, 0)
	return Color(float(parts[0].strip_edges()), float(parts[1].strip_edges()),
			float(parts[2].strip_edges()))


func _close(a: Color, b: Color) -> bool:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) <= EPSILON


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
