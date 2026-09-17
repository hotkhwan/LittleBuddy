extends RefCounted

## The pure room-camera framing maths, at every aspect ratio the game ships on.
##
## ## Why this file is written the way it is
##
## A shipped bug once inverted a camera's pitch and pushed the baby, the bottle
## and the teddy entirely below the viewport while every automated test passed --
## because nothing tested what was on screen. So this file does not check that the
## solver agrees with itself. It rebuilds the projection with **Godot's own**
## `Projection.create_perspective()`, transforms every corner of the room through
## it by hand, and asserts the resulting normalised device coordinates land inside
## the usable window. If `camera_framing.gd` gets a sign, an axis or an aspect
## wrong, that arithmetic disagrees with it.
##
## It is still not sufficient. It cannot say whether a room LOOKS good. That needs
## a rendered image and a human, which is why this work also shipped screenshots.
##
## Covers: fit at 4:3 / 16:9 / 19.5:9 / extreme, both notch orientations, the
## min-max clamp, "as close as it can be", pitched-down, focus-in-front, activity
## focus and restore, and degenerate input.

const Framing := preload("res://scripts/camera/camera_framing.gd")
const Insets := preload("res://scripts/camera/safe_area_insets.gd")

## Every shape the game runs at. 4:3 is the iPad viewport from `project.godot`;
## 19.5:9 is a landscape iPhone; 3:1 is not a shipping device but is the extreme
## that catches a fit which only works for the ratios it was tuned on (an iPad in
## a narrow Stage Manager window is not far off it).
const ASPECTS: Dictionary = {
	"iPad 4:3": 1366.0 / 1024.0,
	"16:9": 16.0 / 9.0,
	"iPhone 19.5:9": 19.5 / 9.0,
	"extreme 3:1": 3.0,
	"extreme 1:1": 1.0,
}

## A greybox room at the contract's scale: roughly 4 x 4 m, floor at y = 0.
const ROOM: Dictionary = {
	"bounds": Rect2(-2.0, -2.0, 4.0, 4.0),
	"focus": Vector3(0.0, 0.5, 0.0),
	"angle": 37.0,
	"minDistance": 3.0,
	"maxDistance": 24.0,
}

## The toddler's height, from contract section 3. Little Buddy standing against
## the far wall is the worst case for the top of the screen.
const BUDDY_HEIGHT: float = 0.85


## What MUST be on screen, listed here rather than taken from
## `Framing.fit_points()`.
##
## This matters more than it looks. Asking the module which points it fitted and
## then checking exactly those points is circular: a fit that quietly forgot the
## head-height corners would also forget to check them, and the case would stay
## green while cropping Little Buddy at the neck. So the requirement is restated
## independently -- every floor corner, every corner at a standing child's height,
## the look-at point, and the child himself in the far corner.
func _must_be_visible() -> Array:
	var bounds: Rect2 = ROOM["bounds"]
	var points: Array = [Vector3(ROOM["focus"])]
	for corner: Vector2 in [
		bounds.position,
		bounds.position + Vector2(bounds.size.x, 0.0),
		bounds.position + Vector2(0.0, bounds.size.y),
		bounds.end,
	]:
		points.append(Vector3(corner.x, 0.0, corner.y))
		points.append(Vector3(corner.x, BUDDY_HEIGHT, corner.y))
	# Little Buddy, standing at the far wall, head included.
	points.append(Vector3(-1.5, 0.0, -1.7))
	points.append(Vector3(-1.5, BUDDY_HEIGHT, -1.7))
	return points

## A landscape iPhone 13-ish: 2532 x 1170 physical, notch on one short edge, home
## indicator along the bottom. Both notch orientations are built from these.
const PHONE_WINDOW: Vector2i = Vector2i(2532, 1170)
const PHONE_NOTCH: int = 132
const PHONE_HOME_INDICATOR: int = 21


func test_name() -> String:
	return "camera_framing"


func run():
	var failures: Array = []
	failures.append_array(_test_fits_at_every_aspect())
	failures.append_array(_test_as_close_as_possible())
	failures.append_array(_test_composition_is_constant())
	failures.append_array(_test_narrow_screens_stand_further_back())
	failures.append_array(_test_safe_area_insets())
	failures.append_array(_test_both_notch_orientations())
	failures.append_array(_test_distance_clamp())
	failures.append_array(_test_activity_focus())
	failures.append_array(_test_degenerate_input())
	return failures


## -- The framing itself --------------------------------------------------------

## Every corner of the room, at floor level and at head height, projects inside
## the usable screen -- at every aspect, with the real device insets applied.
func _test_fits_at_every_aspect() -> Array:
	var failures: Array = []
	var insets: Vector4 = Insets.chrome_insets()

	for label: String in ASPECTS:
		var aspect: float = ASPECTS[label]
		var solution: Dictionary = Framing.solve(ROOM, aspect, insets)

		if not bool(solution["fits"]):
			failures.append("%s: no distance inside [min, max] frames the room" % label)
			continue

		var transform: Transform3D = solution["transform"]
		var forward: Vector3 = -transform.basis.z
		var focus: Vector3 = solution["focus"]

		# The pitch-sign check. The camera must be ABOVE the floor and pointing
		# DOWN at it. This is the assertion the shipped bug would have failed.
		if transform.origin.y <= 0.0:
			failures.append("%s: the camera is not above the floor (y = %.2f)"
					% [label, transform.origin.y])
		if forward.y >= -0.05:
			failures.append("%s: the camera is not pitched down (forward.y = %.3f); "
					% [label, forward.y] + "every object would be off screen")

		# The focus must be IN FRONT of the camera, never behind it.
		var focus_depth: float = (focus - transform.origin).dot(forward)
		if focus_depth <= 0.0:
			failures.append("%s: the focus point is behind the camera (depth = %.2f)"
					% [label, focus_depth])

		# And now the independent half: Godot's own projection matrix, applied to
		# the requirement rather than to whatever the module chose to fit.
		for point: Vector3 in _must_be_visible():
			var where: String = _project(point, transform, float(solution["fov"]), aspect, insets)
			if not where.is_empty():
				failures.append("%s: %s at %s" % [label, where, str(point)])
	return failures


## Correct framing is trivially satisfied by a camera a kilometre away, so the
## distance must also be the CLOSEST one that works. Anything else is a room the
## child has to squint at, which on a phone is its own kind of unplayable.
func _test_as_close_as_possible() -> Array:
	var failures: Array = []
	var insets: Vector4 = Insets.chrome_insets()
	for label: String in ASPECTS:
		var aspect: float = ASPECTS[label]
		var solution: Dictionary = Framing.solve(ROOM, aspect, insets)
		var distance: float = solution["distance"]

		if not Framing.frames_everything(ROOM, distance, aspect, insets):
			failures.append("%s: the fitted distance %.2f does not actually frame the room"
					% [label, distance])

		# Only a MINIMUM-distance clamp excuses standing further back than the fit
		# needs. A solution clamped at the far end has no excuse at all -- "always
		# return maxDistance" is a real failure mode and would otherwise hide here.
		if float(solution["required"]) <= float(ROOM["minDistance"]):
			continue
		var closer: float = distance - 0.1
		if Framing.frames_everything(ROOM, closer, aspect, insets):
			failures.append("%s: the camera stands further back than it needs to "
					% label + "(%.2f fits, so %.2f was not the closest)" % [closer, distance])

		if String(solution["binding"]) == Framing.BINDING_NONE:
			failures.append("%s: nothing bound the distance; the fit did no work" % label)
	return failures


## The composition -- pitch, yaw, look-at -- must be IDENTICAL on every device.
## Only the distance changes. A camera that also tilted on a phone would make the
## same room read as a different place.
func _test_composition_is_constant() -> Array:
	var failures: Array = []
	var reference: Basis = Framing.solve(ROOM, 4.0 / 3.0, Vector4.ZERO)["transform"].basis
	for label: String in ASPECTS:
		var solution: Dictionary = Framing.solve(ROOM, ASPECTS[label], Insets.chrome_insets())
		var basis: Basis = solution["transform"].basis
		for axis: int in range(3):
			if basis[axis].distance_to(reference[axis]) > 0.0001:
				failures.append("%s: the camera orientation changed with the aspect ratio; "
						% label + "the composition must be constant")
				break
		if Vector3(solution["focus"]).distance_to(Vector3(ROOM["focus"])) > 0.0001:
			failures.append("%s: the look-at point moved" % label)
	return failures


## The claim the whole system exists for: `KEEP_HEIGHT` fixes the VERTICAL field
## of view, so a narrow screen has less horizontal room and the camera must stand
## further back. If that ordering ever inverts, the aspect term is wrong.
func _test_narrow_screens_stand_further_back() -> Array:
	var failures: Array = []
	var wide_room: Dictionary = {
		"bounds": Rect2(-3.5, -2.0, 7.0, 4.0),  # wider than deep: width binds hard
		"focus": Vector3(0.0, 0.5, 0.0),
		"angle": 37.0,
		"minDistance": 3.0,
		"maxDistance": 30.0,
	}
	var tablet: Dictionary = Framing.solve(wide_room, 4.0 / 3.0, Vector4.ZERO)
	var phone: Dictionary = Framing.solve(wide_room, 19.5 / 9.0, Vector4.ZERO)

	if float(tablet["distance"]) <= float(phone["distance"]):
		failures.append("a 4:3 screen must need MORE distance than a 19.5:9 one for a wide "
				+ "room (got %.2f vs %.2f)" % [tablet["distance"], phone["distance"]])
	if String(tablet["binding"]) != Framing.BINDING_HORIZONTAL:
		failures.append("a wide room on a 4:3 screen should be bound by its WIDTH, was bound "
				+ "by '%s'" % tablet["binding"])

	# And the binding axis must actually SWITCH somewhere between the two, which
	# is the thing a fixed distance cannot serve. For a square-ish room the iPad
	# runs out of width while the phone runs out of depth.
	if String(Framing.solve(ROOM, 4.0 / 3.0, Vector4.ZERO)["binding"]) \
			!= Framing.BINDING_HORIZONTAL:
		failures.append("a 4 x 4 room on a 4:3 screen should be bound by its width")
	if String(Framing.solve(ROOM, 19.5 / 9.0, Vector4.ZERO)["binding"]) \
			!= Framing.BINDING_VERTICAL:
		failures.append("a 4 x 4 room on a 19.5:9 screen should be bound by its depth "
				+ "(vertically); that switch is why one fixed distance cannot work")

	# Past the point where width stops binding, a wider screen cannot help: the
	# depth constraint has no aspect term in it, so the distance must level off
	# rather than keep shrinking.
	var wide: float = Framing.solve(ROOM, 16.0 / 9.0, Vector4.ZERO)["distance"]
	var wider: float = Framing.solve(ROOM, 3.0, Vector4.ZERO)["distance"]
	if not is_equal_approx(wide, wider):
		failures.append("once depth binds, a wider screen must not change the distance "
				+ "(%.3f vs %.3f)" % [wide, wider])

	# A deep, narrow room flips it: now depth binds even on the tablet.
	var deep_room: Dictionary = wide_room.duplicate(true)
	deep_room["bounds"] = Rect2(-1.5, -4.0, 3.0, 8.0)
	if String(Framing.solve(deep_room, 4.0 / 3.0, Vector4.ZERO)["binding"]) \
			!= Framing.BINDING_VERTICAL:
		failures.append("a deep, narrow room should be bound by its depth at every aspect")
	return failures


## The insets must actually do something, and must push the camera BACK rather
## than crop harder. A fit that ignored them would return the same distance.
func _test_safe_area_insets() -> Array:
	var failures: Array = []
	var aspect: float = 19.5 / 9.0
	var bare: float = Framing.solve(ROOM, aspect, Vector4.ZERO)["distance"]
	var inset: float = Framing.solve(ROOM, aspect, Insets.chrome_insets())["distance"]
	if inset <= bare + 0.01:
		failures.append("safe-area / chrome insets did not push the camera back "
				+ "(%.2f with insets vs %.2f without)" % [inset, bare])

	# A 132 px notch on a 2532 px-wide landscape phone is ~5.2% of the screen.
	var notch: Vector4 = Insets.insets_from_pixels(
		Rect2i(PHONE_NOTCH, 0, PHONE_WINDOW.x - PHONE_NOTCH, PHONE_WINDOW.y - PHONE_HOME_INDICATOR),
		PHONE_WINDOW
	)
	if absf(notch.x - float(PHONE_NOTCH) / float(PHONE_WINDOW.x)) > 0.001:
		failures.append("the left inset should be the notch as a fraction of the window, got %f"
				% notch.x)
	if absf(notch.w - float(PHONE_HOME_INDICATOR) / float(PHONE_WINDOW.y)) > 0.001:
		failures.append("the bottom inset should be the home indicator, got %f" % notch.w)
	if notch.z > 0.001 or notch.y > 0.001:
		failures.append("an edge with no unsafe area should have no inset, got %s" % str(notch))

	# Never negative, never large enough to collapse the usable window.
	var absurd: Vector4 = Insets.sanitise(Vector4(-1.0, 9.0, NAN, INF))
	for value: float in [absurd.x, absurd.y, absurd.z, absurd.w]:
		if not is_finite(value) or value < 0.0 or value > Insets.MAX_INSET:
			failures.append("an absurd inset was not sanitised: %s" % str(absurd))
			break

	var limits: Vector4 = Framing.ndc_limits(Vector4(0.45, 0.45, 0.45, 0.45))
	for value: float in [limits.x, limits.y, limits.z, limits.w]:
		if value < Framing.MIN_NDC_LIMIT - 0.0001:
			failures.append("insets were allowed to collapse the usable window to %s" % str(limits))
			break
	return failures


## The same phone, turned the other way round. The notch moves from the left edge
## to the right edge, and nothing important may be under it in either case.
func _test_both_notch_orientations() -> Array:
	var failures: Array = []
	var aspect: float = float(PHONE_WINDOW.x) / float(PHONE_WINDOW.y)
	var chrome: Vector4 = Insets.chrome_insets()

	var orientations: Dictionary = {
		"notch left": Insets.insets_from_pixels(
			Rect2i(PHONE_NOTCH, 0, PHONE_WINDOW.x - PHONE_NOTCH,
					PHONE_WINDOW.y - PHONE_HOME_INDICATOR),
			PHONE_WINDOW
		),
		"notch right": Insets.insets_from_pixels(
			Rect2i(0, 0, PHONE_WINDOW.x - PHONE_NOTCH, PHONE_WINDOW.y - PHONE_HOME_INDICATOR),
			PHONE_WINDOW
		),
	}

	for label: String in orientations:
		var insets: Vector4 = Insets.combine(orientations[label], chrome)
		var solution: Dictionary = Framing.solve(ROOM, aspect, insets)
		if not bool(solution["fits"]):
			failures.append("%s: the room does not fit" % label)
			continue
		for point: Vector3 in _must_be_visible():
			var where: String = _project(
				point, solution["transform"], float(solution["fov"]), aspect, insets
			)
			if not where.is_empty():
				failures.append("%s: %s at %s" % [label, where, str(point)])

	# Left-notch and right-notch insets are mirror images, so the fitted distance
	# must match: turning the phone over may not change how big the room looks.
	var left: float = Framing.solve(
		ROOM, aspect, Insets.combine(orientations["notch left"], chrome)
	)["distance"]
	var right: float = Framing.solve(
		ROOM, aspect, Insets.combine(orientations["notch right"], chrome)
	)["distance"]
	if absf(left - right) > 0.01:
		failures.append("turning the phone over changed the framing (%.2f vs %.2f)"
				% [left, right])
	return failures


## -- Clamps, focus and bad input -----------------------------------------------

func _test_distance_clamp() -> Array:
	var failures: Array = []
	var aspect: float = 16.0 / 9.0

	# A tiny room would be framed from inside the furniture. The minimum wins.
	var tiny: Dictionary = ROOM.duplicate(true)
	tiny["bounds"] = Rect2(-0.2, -0.2, 0.4, 0.4)
	tiny["minDistance"] = 6.0
	var near: Dictionary = Framing.solve(tiny, aspect, Vector4.ZERO)
	if not is_equal_approx(float(near["distance"]), 6.0):
		failures.append("a room smaller than minDistance should clamp to it, got %.2f"
				% near["distance"])
	if not bool(near["clamped"]):
		failures.append("a clamped solution should report that it was clamped")

	# A room too big for maxDistance must clamp and say so rather than silently
	# flying the camera into orbit.
	var huge: Dictionary = ROOM.duplicate(true)
	huge["bounds"] = Rect2(-40.0, -40.0, 80.0, 80.0)
	huge["maxDistance"] = 12.0
	var far: Dictionary = Framing.solve(huge, aspect, Vector4.ZERO)
	if not is_equal_approx(float(far["distance"]), 12.0):
		failures.append("a room larger than maxDistance should clamp to it, got %.2f"
				% far["distance"])
	if bool(far["fits"]):
		failures.append("a room that cannot fit inside maxDistance must report fits = false")

	# And at every aspect, for the normal room, the distance stays inside the
	# authored range -- that is the contract rooms rely on.
	for label: String in ASPECTS:
		var distance: float = Framing.solve(
			ROOM, ASPECTS[label], Insets.chrome_insets()
		)["distance"]
		if distance < float(ROOM["minDistance"]) - 0.0001 \
				or distance > float(ROOM["maxDistance"]) + 0.0001:
			failures.append("%s: the distance %.2f escaped [%.1f, %.1f]"
					% [label, distance, ROOM["minDistance"], ROOM["maxDistance"]])

	# The camera must never end up at head height inside the room.
	var flat: Dictionary = ROOM.duplicate(true)
	flat["minDistance"] = 0.1
	flat["headroom"] = 1.9
	var solution: Dictionary = Framing.solve(flat, aspect, Vector4.ZERO)
	if Vector3(solution["position"]).y <= 1.9 + Framing.CAMERA_CLEARANCE - 0.0001:
		failures.append("the camera sits below the room's headroom, i.e. inside its geometry "
				+ "(y = %.2f)" % Vector3(solution["position"]).y)
	return failures


## Moving in on one activity: closer, same shot, and reversible.
func _test_activity_focus() -> Array:
	var failures: Array = []
	var aspect: float = 4.0 / 3.0
	var insets: Vector4 = Insets.chrome_insets()
	var target := Vector3(1.4, 0.4, -1.1)

	var room_solution: Dictionary = Framing.solve(ROOM, aspect, insets)
	var focused: Dictionary = Framing.focus_framing(ROOM, target, 1.2)
	var focus_solution: Dictionary = Framing.solve(focused, aspect, insets)

	if float(focus_solution["distance"]) >= float(room_solution["distance"]):
		failures.append("focusing an activity should move the camera CLOSER (%.2f vs %.2f)"
				% [focus_solution["distance"], room_solution["distance"]])
	if Vector3(focus_solution["focus"]).distance_to(target) > 0.0001:
		failures.append("the focused camera does not look at the activity")

	# Same shot: only the tightness may change.
	var room_basis: Basis = room_solution["transform"].basis
	var focus_basis: Basis = focus_solution["transform"].basis
	for axis: int in range(3):
		if room_basis[axis].distance_to(focus_basis[axis]) > 0.0001:
			failures.append("focusing an activity changed the camera angle; it must be the "
					+ "same shot from closer")
			break

	# The activity itself, the ground 1.2 m around it, and a child standing there
	# all stay on screen. Listed independently, not read back from the module.
	var around: Array = [target]
	for dx: float in [-1.2, 1.2]:
		for dz: float in [-1.2, 1.2]:
			around.append(Vector3(target.x + dx, 0.0, target.z + dz))
			around.append(Vector3(target.x + dx, BUDDY_HEIGHT, target.z + dz))
	for point: Vector3 in around:
		var where: String = _project(
			point, focus_solution["transform"], float(focus_solution["fov"]), aspect, insets
		)
		if not where.is_empty():
			failures.append("activity focus: %s at %s" % [where, str(point)])

	# Restoring is exact: the room framing survives the round trip untouched.
	var restored: Dictionary = Framing.solve(ROOM, aspect, insets)
	if not is_equal_approx(float(restored["distance"]), float(room_solution["distance"])):
		failures.append("restoring the room frame did not return the original distance")
	return failures


## Bad data must produce a slightly odd camera, never a NaN transform. Godot
## propagates a NaN transform silently until the entire scene vanishes.
func _test_degenerate_input() -> Array:
	var failures: Array = []
	var cases: Dictionary = {
		"empty dictionary": {},
		"zero-size bounds": {"bounds": Rect2(1.0, 1.0, 0.0, 0.0), "focus": Vector3(1.0, 0.0, 1.0)},
		"negative-size bounds": {"bounds": Rect2(2.0, 2.0, -4.0, -4.0)},
		"NaN bounds": {"bounds": Rect2(NAN, NAN, NAN, NAN), "focus": Vector3(NAN, NAN, NAN)},
		"infinite distances": {"minDistance": INF, "maxDistance": -INF},
		"max below min": {"minDistance": 10.0, "maxDistance": 2.0},
		"absurd angle": {"angle": 720.0},
		"zero fov": {"fov": 0.0},
		"wrong types": {"bounds": "kitchen", "focus": 7, "angle": "steep"},
	}

	for label: String in cases:
		for aspect: float in [0.0, -3.0, NAN, INF, 1.0, 2.167]:
			var solution: Dictionary = Framing.solve(cases[label], aspect, Vector4(NAN, INF, -1.0, 0.5))
			var distance: float = solution["distance"]
			var position: Vector3 = solution["position"]
			var transform: Transform3D = solution["transform"]
			if not is_finite(distance) or distance <= 0.0:
				failures.append("%s @ %f: distance is %f" % [label, aspect, distance])
			for component: float in [
				position.x, position.y, position.z,
				transform.basis.x.x, transform.basis.y.y, transform.basis.z.z,
			]:
				if not is_finite(component):
					failures.append("%s @ %f: the transform contains a non-finite value: %s"
							% [label, aspect, str(transform)])
					break
			if not is_finite(float(solution["fov"])) or float(solution["fov"]) <= 0.0:
				failures.append("%s @ %f: the field of view is %s"
						% [label, aspect, str(solution["fov"])])
			# The focus must still be in front of the camera even for nonsense input.
			var forward: Vector3 = -transform.basis.z
			if (Vector3(solution["focus"]) - transform.origin).dot(forward) <= 0.0:
				failures.append("%s @ %f: the focus ended up behind the camera" % [label, aspect])
	return failures


## -- Independent projection ----------------------------------------------------

## Projects `point` with Godot's own perspective matrix and returns a description
## of what is wrong with it, or "" when it is safely on screen.
##
## Deliberately NOT `camera_framing.gd`'s own arithmetic: this is the second
## opinion. `create_perspective(..., flip_fov = false)` is exactly what a
## `Camera3D` in `KEEP_HEIGHT` builds, so a mistake in the aspect term shows up
## here as a corner off the side of the screen.
func _project(
	point: Vector3, camera: Transform3D, fov: float, aspect: float, insets: Vector4
) -> String:
	var projection: Projection = Projection.create_perspective(fov, aspect, 0.05, 500.0, false)
	var view: Vector3 = camera.affine_inverse() * point
	var clip: Vector4 = projection * Vector4(view.x, view.y, view.z, 1.0)
	if clip.w <= 0.0:
		return "is BEHIND the camera"
	var ndc := Vector2(clip.x / clip.w, clip.y / clip.w)
	if not is_finite(ndc.x) or not is_finite(ndc.y):
		return "projects to a non-finite screen position"

	# The usable window, in normalised device coordinates. The screen is 2 NDC
	# units across, so an inset covering a fraction `i` removes `2 * i`.
	var left: float = -1.0 + 2.0 * insets.x
	var top: float = 1.0 - 2.0 * insets.y
	var right: float = 1.0 - 2.0 * insets.z
	var bottom: float = -1.0 + 2.0 * insets.w
	var slack: float = 0.002

	if ndc.x < left - slack:
		return "is off the LEFT edge / under the left inset (ndc.x = %.3f, limit %.3f)" % [ndc.x, left]
	if ndc.x > right + slack:
		return "is off the RIGHT edge / under the right inset (ndc.x = %.3f, limit %.3f)" % [ndc.x, right]
	if ndc.y > top + slack:
		return "is off the TOP / under the top inset (ndc.y = %.3f, limit %.3f)" % [ndc.y, top]
	if ndc.y < bottom - slack:
		return "is off the BOTTOM / under the bottom inset (ndc.y = %.3f, limit %.3f)" % [ndc.y, bottom]
	return ""
