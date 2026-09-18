extends RefCounted

## What a close-up must CONTAIN, worked out as pure maths.
##
## `camera_framing.gd` answers "where must the camera stand to fit this box".
## This answers the question one level up: **which box**. They are deliberately
## separate files, because the second question is the one with the child-safety
## rule in it and it deserves its own tests.
##
## ## The rule this file exists to enforce
##
## The whole-room shot was left in place for a long time for one reason: a pulled
## in camera that frames a sink beautifully and loses Little Buddy is worse than
## no pull-in at all. A four-year-old who cannot see their character does not
## reason about it -- they think the game broke.
##
## So a close-up is never composed on the activity alone. The caller hands over
## EVERY point the beat needs on screen -- the piece of furniture, the child, and
## the row of objects laid out in front of him -- and this returns the smallest
## square that holds all of them, plus a margin.
##
## Because the result is a box that *contains* the child's feet, and
## `camera_framing.gd` guarantees the box's four corners at both floor level and
## head height are inside the safe area, the child is inside the safe area too:
## a perspective frustum is convex, so every point between those corners is
## visible. "Little Buddy stays on screen" is therefore a property of the
## geometry rather than a value somebody tuned.
##
## ## Why a square, and why it is centred on the box
##
## `focus_framing()` takes a single `radius`, so the box is square. Centring it
## on the extent (rather than on the furniture) puts the activity and the child
## symmetrically either side of the look-at point -- the same two-shot at every
## beat, on every device. Only the tightness changes with the aspect ratio, which
## is the invariant `docs/ROOM_CAMERA_SYSTEM.md` is built around.
##
## Pure: `Vector3`s and floats in, a Dictionary out. No node, no viewport, no
## tree, so it can be asserted headlessly.

## Air kept around the outermost thing the beat needs. A child's finger is wide
## and a pickup is not a point; this is the difference between "technically on
## screen" and "reachable".
const DEFAULT_MARGIN: float = 0.3

## Below this there is nothing to gain: the rooms author `minDistance` 3.5 m, so
## a tighter box simply clamps and the shot stops changing.
const MIN_RADIUS: float = 0.9

## Where the shot stops getting any wider *for the sake of air*. A little larger
## than a room's half-extent (2.0 m), so it is only reached when the child has
## wandered to the far side of the room in the middle of a beat, and at that point
## the honest answer is "show everything".
##
## It caps the MARGIN, never the content: see `frame_points()`. A ceiling that
## could trim the box would quietly break the one guarantee this file exists for,
## and did -- a beat whose object row was staged in a different room composed a
## box spanning 9 m, clamped it to 4.4 m, and left Little Buddy off the side of
## the screen at 1.13 in normalised device coordinates.
const MAX_RADIUS: float = 2.2

## Where the close-up looks, above the floor. The rooms frame themselves at
## `floorY + 0.55`; matching it keeps the horizon in the same place when the
## camera moves in, so the pull-in reads as a move rather than a cut.
const DEFAULT_FOCUS_HEIGHT: float = 0.55


## The smallest square close-up that holds every point in `points`.
##
## Returns:
##   `focus`  -- `Vector3`, the look-at point: the XZ centre of the extent, at
##               `focus_y`.
##   `radius` -- half-width of the square, margin included and clamped.
##   `valid`  -- false when there was nothing usable to frame, in which case the
##               caller must leave the camera alone rather than aim it at the
##               origin. A focus computed from a stray (0,0,0) would frame an
##               empty patch of floor with every "the camera moved" assertion
##               still passing, which is the failure mode `spatial_util.gd`
##               exists for.
##   `extent` -- the raw half-extent before the margin and the clamps, so a test
##               can tell "the box was already big" from "the clamp did it".
##   `nudged` -- true when the box was slid to stay inside `room`.
##
## `room` is the room's floor rectangle in world XZ. The box is slid -- never
## shrunk -- to sit inside it, so a close-up cannot end up looking past the open
## front of the room at the empty space beyond. The slide is limited to the slack
## the margin provides, so it can never push a fit point out: containment wins
## over composition, every time.
static func frame_points(
	points: Array,
	focus_y: float = DEFAULT_FOCUS_HEIGHT,
	margin: float = DEFAULT_MARGIN,
	min_radius: float = MIN_RADIUS,
	max_radius: float = MAX_RADIUS,
	room: Rect2 = Rect2()
) -> Dictionary:
	var usable: Array = []
	for entry: Variant in points:
		if entry is Vector3:
			var point: Vector3 = entry
			if is_finite(point.x) and is_finite(point.y) and is_finite(point.z):
				usable.append(point)

	if usable.is_empty():
		return {
			"focus": Vector3.ZERO, "radius": min_radius, "extent": 0.0,
			"nudged": false, "valid": false,
		}

	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for point: Vector3 in usable:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)

	var extent: float = maxf((max_x - min_x) * 0.5, (max_z - min_z) * 0.5)
	var safe_margin: float = maxf(margin, 0.0) if is_finite(margin) else DEFAULT_MARGIN
	var low: float = maxf(min_radius, 0.1) if is_finite(min_radius) else MIN_RADIUS
	var high: float = maxf(max_radius, low) if is_finite(max_radius) else MAX_RADIUS
	var height: float = focus_y if is_finite(focus_y) else DEFAULT_FOCUS_HEIGHT

	# The ceiling trims the AIR, never the content: `high` is raised to the extent
	# whenever the extent alone is larger. Containment is the whole point of this
	# file and must not be negotiable against a tuning constant.
	var radius: float = clampf(extent + safe_margin, low, maxf(high, extent))

	var centre_x: float = _slide(
		(min_x + max_x) * 0.5, radius, (max_x - min_x) * 0.5,
		room.position.x, room.end.x, room.size.x > 0.0
	)
	var centre_z: float = _slide(
		(min_z + max_z) * 0.5, radius, (max_z - min_z) * 0.5,
		room.position.y, room.end.y, room.size.y > 0.0
	)

	return {
		"focus": Vector3(centre_x, height, centre_z),
		"radius": radius,
		"extent": extent,
		"nudged": not (is_equal_approx(centre_x, (min_x + max_x) * 0.5)
				and is_equal_approx(centre_z, (min_z + max_z) * 0.5)),
		"valid": true,
	}


## Slides one axis of the box back inside the room, as far as the slack allows.
##
## The square box is as wide as its LARGEST axis, so on the other axis it sticks
## out well past anything it had to hold -- and the rooms have an open front, so
## sticking out there means composing the shot on the empty space beyond the floor
## rather than on the room. A breakfast close-up did exactly that: the look-at
## point sat 1.1 m in front of the table, the far wall receded, and the "close-up"
## showed more background than the whole-room shot it replaced.
##
## `half_span` is how far the fit points themselves reach from the centre on this
## axis, so `radius - half_span` is exactly how far the box may move before one of
## them touches the edge. Composition never costs containment.
static func _slide(
	centre: float, radius: float, half_span: float,
	low: float, high: float, enabled: bool
) -> float:
	if not enabled or not (is_finite(low) and is_finite(high)) or high <= low:
		return centre
	var wanted: float = centre
	if high - low <= radius * 2.0:
		# The box is wider than the room on this axis: centre it on the room, which
		# is the closest thing to "inside" that exists.
		wanted = (low + high) * 0.5
	else:
		wanted = clampf(centre, low + radius, high - radius)
	var slack: float = maxf(radius - maxf(half_span, 0.0), 0.0)
	return clampf(wanted, centre - slack, centre + slack)


## True when `point` is inside the square this module would have kept on screen.
##
## The independent read-back: `frame_points()` builds a box and this checks one,
## so a test can assert containment without re-deriving the arithmetic it is
## trying to verify. Y is ignored on purpose -- the box is a floor plan, and the
## camera's own `headroom` is what covers a standing child's head.
static func contains(focus: Vector3, radius: float, point: Vector3) -> bool:
	if not (is_finite(radius) and is_finite(point.x) and is_finite(point.z)):
		return false
	return absf(point.x - focus.x) <= radius and absf(point.z - focus.z) <= radius
