extends RefCounted

## Pure room-camera framing maths. No `Camera3D`, no scene tree, no viewport.
##
## Every function here takes numbers (bounds, aspect, field of view, safe-area
## insets) and returns numbers (a distance, a position, a `Transform3D`). That is
## deliberate: it is the same discipline that made `CharacterMovementController`
## testable, and it means the framing can be asserted headlessly at every aspect
## ratio the game ships on rather than eyeballed once on a Mac.
##
## `room_camera.gd` is the thin node that applies the result.
##
## ## The problem
##
## The Phase 2A spike proved a **fixed camera distance cannot frame a room from
## 1.33:1 (iPad landscape) to 2.17:1 (landscape iPhone)**. Godot's default
## `KEEP_HEIGHT` aspect mode fixes the VERTICAL field of view, so the horizontal
## field of view shrinks as the screen narrows. Frame a room snugly on a phone and
## the iPad crops its side walls; frame it for the iPad and the phone wastes half
## the screen -- or crops the far wall, because on a wide screen it is the room's
## DEPTH that runs out of vertical room first.
##
## ## The answer
##
## Pull the camera back along a FIXED viewing direction until everything fits, and
## no further. The pitch and the look-at point never move, so the composition is
## byte-identical on every device; only the tightness changes.
##
## ## Why it is closed-form rather than a search
##
## The spike stepped the distance in 5 cm increments until everything fitted. That
## works but it is a loop with a tolerance and a give-up value. It turns out the
## exact answer is one line of algebra.
##
## Put the camera at `C = focus + u * d`, where `u` is the fixed unit direction
## from the focus towards the camera, and always look back down `-u`. The camera
## basis therefore does not depend on `d` at all. For a world point `P`, write
## `q = P - focus`. Then in camera space:
##
##     depth = q . forward + d          (grows linearly with the distance)
##     x     = q . right                (CONSTANT -- `right` is perpendicular to `u`)
##     y     = q . up                   (CONSTANT -- so is `up`)
##
## A point is on screen when `x / depth` is inside the horizontal half-extent and
## `y / depth` is inside the vertical one. Since only `depth` moves, each of those
## four constraints is a simple lower bound on `d`:
##
##     d >= |x| / horizontal_limit - q . forward
##     d >= |y| / vertical_limit   - q . forward
##
## The answer is the maximum over every point and every constraint. One pass, no
## tolerance, no iteration cap, and "as close as it can be while still fitting"
## is true by construction rather than by a step size -- which matters, because
## "the whole room is visible" is also satisfied by a camera in the next postcode.
##
## `solve()` additionally reports WHICH point and WHICH axis produced that
## maximum, so "the iPad is bound by the room's width, the phone by its depth" is
## an observable fact rather than a claim in a comment.

## Vertical field of view, in degrees. Matches the spike and the Baby Room, so
## rooms read at the same "scale" as the existing game.
const DEFAULT_FOV: float = 52.0

## Pitch above the horizontal, in degrees. ~37 degrees looks down at a room seen
## from the front: enough to read the floor plan, shallow enough that characters
## are seen from the front rather than from the top of the head.
const DEFAULT_ANGLE_DEGREES: float = 37.0

## A camera that is level with the floor cannot show a floor plan, and one
## directly overhead makes `Basis.looking_at(..., Vector3.UP)` degenerate. Both
## ends are clamped rather than rejected: a room with a silly angle should look
## slightly wrong, not crash.
const MIN_ANGLE_DEGREES: float = 5.0
const MAX_ANGLE_DEGREES: float = 85.0

const DEFAULT_MIN_DISTANCE: float = 3.0
const DEFAULT_MAX_DISTANCE: float = 24.0

## The height above the floor that must also stay on screen, so a child standing
## against the far wall is not cropped at the neck. The toddler is ~0.85 m
## (contract section 3); 1.0 m leaves a little air above the head.
const DEFAULT_HEADROOM: float = 1.0

## Half-width of the box `focus_framing()` frames around a single activity.
const DEFAULT_ACTIVITY_RADIUS: float = 1.2

## How close a CLOSE-UP is allowed to stand, whatever the room authored.
##
## A room's own `minDistance` (3.5 m in this house) exists to stop the WHOLE-ROOM
## shot from crawling in among its own furniture. Applied unchanged to an
## activity box it does something quite different and quite wrong: the beat's box
## is ~0.9 m of radius, it fits from 2.77 m, and the room's floor clamped it back
## out to 3.5 m -- so every "close-up" in the game was 26% further away than the
## shot it had computed, and the pull-in from the 5.1 m room shot was a barely
## perceptible 1.5x. The brief's "characters and interactions look small" was
## this clamp.
##
## It is not replaced by zero. The camera must still never end up inside the
## child's head, and `CAMERA_CLEARANCE` alone permits ~1.3 m at this pitch, which
## on a 0.85 m toddler is a nose-to-nose shot. 1.9 m is a two-shot of a standing
## child and the station in front of him, and it is a FLOOR rather than a target:
## a box larger than the minimum still fits from wherever the maths says.
const FOCUS_MIN_DISTANCE: float = 1.9

## How far the CLOSE-UP's look-at point slides toward the camera, as a fraction
## of the box's own half-depth.
##
## ## Why a close-up needs the same trick the room shot already has
##
## `HouseLayout.CAMERA_FOCUS_Z = 0.42` exists because a camera pitched 32 degrees
## down at the centre of a box spends its distance asymmetrically: the NEAR edge
## falls a long way below the look-at point while the far edge rises only a
## little above it, so the near edge binds and the far one is nowhere close.
## Measured on the real house by `tests/shots_lighting.gd -- frame`, **every shot
## in this game, in every room, at both shipped aspects, is bound by the
## VERTICAL constraint** -- the horizontal one is never within 6% of binding. The
## whole system is a vertical fit, and this asymmetry is the whole of it.
##
## The room shot buys that distance back. The close-up did not, and the
## consequence was not subtle: a `choose` beat composes a 1.88 m box, which
## fitted from **4.87 m** while the whole-room shot it replaced stood at 4.23 to
## 4.56 m. The camera "moved in" on the activity by **moving 7 to 15% further
## out**. With the lookahead it fits from **4.03 m** and is a pull-in again.
##
## On the 0.90 m `goAndDo` box the same asymmetry was wasting 0.41 m -- but that
## shot does not get it, because rendering it showed the slack was not slack:
## see `CLOSE_UP_SUBJECT_HEIGHT`. It ends up at 2.80 m against 2.77 m, unmoved.
##
## 0.21 is not a new taste: it is `CAMERA_FOCUS_Z / 2.0`, the room's own bias
## divided by the room's own half-depth, so a close-up and the room shot it
## interrupts are now composed by one rule instead of two. Expressed as a
## FRACTION rather than a distance because the box's size is the thing that
## varies -- a 0.9 m box and a 2.2 m one need proportionally different slides,
## and a fixed metre value would over-slide the small one straight past the
## clamp.
##
## ## What this deliberately does NOT change
##
## The BOX. `bounds` stays centred on the point the caller asked for, so
## everything `camera_focus.gd` guaranteed to be on screen is still on screen
## (and `room_camera.get_focus_radius()`, which the HUD reads its presentation
## mode from, reads `bounds` and is therefore untouched). Only where the camera
## AIMS moves. The near edge of the box sat exactly on the bottom safe-area
## limit before this change and sits exactly on it after -- that is what "bound
## by vertical" means -- so no new void appears at the bottom of the frame.
const FOCUS_LOOKAHEAD: float = 0.21

## How tall the thing standing in a close-up box is assumed to be, in metres
## above the floor.
##
## ## The bug this exists for, found by rendering the close-up and looking at it
##
## `DEFAULT_HEADROOM` is 1.0 m and its comment says "the toddler is ~0.85 m".
## That describes the BABY. The character the child drives is Aliz, whose
## collision capsule in `scenes/house/house_world.tscn` is **1.5 m tall**, and
## her hair reaches higher still. The fit therefore believed it had a metre of
## air above her head when it had 0.12 in normalised device coordinates: at the
## old 2.77 m standoff the top of her hair already sat at ndc_y **0.88**, past
## the top safe-area limit of 0.80 and a hand's breadth from the edge of the
## screen. It survived only because nothing had ever moved the camera in.
##
## `FOCUS_LOOKAHEAD` moved the camera in, and the first render cropped the top
## of her head. The honest repair is not to back the camera off again but to
## stop the solver believing a false height.
##
## **Why not simply raise `DEFAULT_HEADROOM`.** Measured: 1.0 -> 1.55 demands
## that much air above all FOUR corners of the box, most of which is empty
## floor, and the far pair then bind. The 0.90 m close-up goes 2.37 m -> **3.26
## m** -- further out than it was before any of this, with `fillX` falling to
## 0.44 on a phone. Raising the headroom to fix a cropped head makes the shot
## wider than the shot that did not crop it.
##
## So the subject is named as a POINT instead: one extra fit point, at the box's
## centre (which is where `camera_focus.frame_points()` centres the extent
## between the child and the station he is walking to), at this height. It costs
## distance only when the character would really have been cropped.
##
## 1.55 m is `LittleBuddy/CollisionShape3D`'s capsule in
## `scenes/house/house_world.tscn` -- `height = 1.5`, centred at `y = 0.75`, so
## it spans the floor to 1.5 m -- plus five centimetres of air. It is held inside
## the TOP CHROME inset (0.80 of the half-height, not the screen edge), and her
## hair, measured off the render at **1.66 m above the floor**, then lands just
## inside the screen with the same margin it has today.
##
## ## This constant is a GUARD, not a tightener, and the distinction is the
## finding
##
## Calibrated: at 1.55 m the `goAndDo` close-up solves to **2.80 m** against the
## 2.77 m it ships at. It does not move the shot. That is the honest result --
## **the tight close-up cannot be tightened at all.** `FOCUS_LOOKAHEAD` recovers
## 0.41 m of standoff that the near-bottom corner was wasting, and rendering it
## showed where all of that 0.41 m was already going: into the 16 cm of Aliz's
## head that the solver could not see. The first render at 2.37 m cut the top of
## her hair clean off.
##
## So the value of naming her here is not scale. It is that the number is now a
## constraint instead of a coincidence: before this, "the player character's head
## is on screen during a close-up" was true only because two unrelated numbers
## happened to cancel, and the next person to tighten the camera by 15 cm would
## have cropped her with every test still green.
##
## The `choose` close-up is where the pass is actually worth something: its 1.88
## m box is bound by its own near floor corner, not by her, so it takes the whole
## of the lookahead -- **4.87 m -> 4.03 m**, and for the first time it is closer
## than the whole-room shot it interrupts (4.23 to 4.56 m) rather than further
## out.
##
## ## Why not simply raise `DEFAULT_HEADROOM`
##
## Measured: 1.0 -> 1.55 demands that much air above all FOUR corners of the box,
## most of which is empty floor, and the far pair then bind. The 0.90 m close-up
## goes to **3.26 m** -- wider than it has ever been, with `fillX` falling to
## 0.44 on a phone. Raising the headroom to protect a head makes the shot wider
## than the shot that was cropping it.
const CLOSE_UP_SUBJECT_HEIGHT: float = 1.55

## The feeding portrait -- see `portrait_framing()`. Half a metre of radius is a
## toddler's shoulders with a hand's width of air; 1.05 m above the floor clears
## the top of Bunny's head (0.85 m standing, less when seated) by the same
## margin `CLOSE_UP_SUBJECT_HEIGHT` gives Aliz; 1.2 m is just under the ~1.3 m
## that `CAMERA_CLEARANCE` permits at this pitch, so the clearance rule -- not
## this number -- is what actually decides the standoff.
const PORTRAIT_RADIUS: float = 0.42
const PORTRAIT_SUBJECT_HEIGHT: float = 1.05
const PORTRAIT_MIN_DISTANCE: float = 1.2
const PORTRAIT_HEADROOM: float = 0.45

## Nothing may sit closer to the camera plane than this. Also what stops the
## "behind the focus" case: the focus itself sits at `depth == d`, so a positive
## distance already puts it in front, and this guards every other point too.
const MIN_DEPTH: float = 0.05

## Guards against a caller handing us a zero-size or non-finite viewport.
const MIN_ASPECT: float = 0.2
const MAX_ASPECT: float = 6.0
const MIN_FOV: float = 10.0
const MAX_FOV: float = 120.0

## Insets may never eat so much of the screen that the usable window collapses,
## because the fit divides by it.
const MIN_NDC_LIMIT: float = 0.15

## The 4:3 iPad viewport from `project.godot`. Only used when no viewport can be
## seen -- everything real passes the live aspect in.
const REFERENCE_ASPECT: float = 1366.0 / 1024.0

const FIT_EPSILON: float = 0.001

## `solve()["binding"]` is one of these: which constraint the distance came from.
const BINDING_HORIZONTAL: String = "horizontal"
const BINDING_VERTICAL: String = "vertical"
const BINDING_DEPTH: String = "depth"
const BINDING_CLEARANCE: String = "clearance"
const BINDING_NONE: String = "none"

## The camera must always end up this far above the tallest thing the room asked
## to keep on screen. Cheap insurance against "never place the camera inside
## geometry": whatever the bounds and the angle, the camera looks down from above
## the room's contents rather than sitting at head height inside a wall.
const CAMERA_CLEARANCE: float = 0.25


## -- Framing metadata ----------------------------------------------------------

## The per-room framing dictionary, with every optional key filled in.
##
## Taken and returned as a plain `Dictionary` on purpose: a room declares its
## framing as data and never imports a type from this directory, so the camera
## can be replaced wholesale without touching a single room.
##
## | key | meaning |
## |---|---|
## | `bounds` | `Rect2`, world XZ. What must be visible. |
## | `focus` | `Vector3`. The look-at point. |
## | `angle` | degrees above the horizontal. |
## | `yaw` | degrees, 0 = the camera sits on the +Z side looking towards -Z. |
## | `minDistance` / `maxDistance` | metres, the distance is clamped into this. |
## | `floorY` | the floor height the bounds live at. |
## | `headroom` | metres above the floor that must also stay on screen. |
## | `fov` | vertical field of view, degrees. |
## | `chromeInsets` | extra `Vector4(l, t, r, b)` screen fractions this room's HUD covers. |
## | `extraPoints` | `Array` of extra `Vector3` that must stay on screen. |
static func normalise_framing(framing: Dictionary) -> Dictionary:
	var bounds: Rect2 = _rect(framing.get("bounds", Rect2()))
	var focus: Vector3 = _vec3(framing.get("focus", Vector3.ZERO), Vector3.ZERO)

	var min_distance: float = maxf(
		_number(framing.get("minDistance", DEFAULT_MIN_DISTANCE), DEFAULT_MIN_DISTANCE), MIN_DEPTH
	)
	# A room that authors max < min gets a usable camera rather than an assertion:
	# the minimum wins, because "too far away" is survivable and "inside the wall"
	# is not.
	var max_distance: float = maxf(
		_number(framing.get("maxDistance", DEFAULT_MAX_DISTANCE), DEFAULT_MAX_DISTANCE), min_distance
	)

	var extra: Array = []
	var raw_extra: Variant = framing.get("extraPoints", [])
	if raw_extra is Array:
		for point: Variant in (raw_extra as Array):
			if point is Vector3:
				extra.append(_vec3(point, Vector3.ZERO))

	return {
		"bounds": bounds,
		"focus": focus,
		"angle": clampf(
			_number(framing.get("angle", DEFAULT_ANGLE_DEGREES), DEFAULT_ANGLE_DEGREES),
			MIN_ANGLE_DEGREES,
			MAX_ANGLE_DEGREES
		),
		"yaw": _number(framing.get("yaw", 0.0), 0.0),
		"minDistance": min_distance,
		"maxDistance": max_distance,
		"floorY": _number(framing.get("floorY", 0.0), 0.0),
		"headroom": maxf(_number(framing.get("headroom", DEFAULT_HEADROOM), DEFAULT_HEADROOM), 0.0),
		"fov": clampf(_number(framing.get("fov", DEFAULT_FOV), DEFAULT_FOV), MIN_FOV, MAX_FOV),
		"chromeInsets": _vec4(framing.get("chromeInsets", Vector4.ZERO)),
		"extraPoints": extra,
	}


## A tighter framing on one activity, keeping the room's composition.
##
## Same pitch, same yaw, same clamps -- only the box being fitted shrinks, so
## moving in on the fridge is the same shot from closer, never a different angle.
## The box is centred on `focus`, so a character standing at the activity stays in
## frame, which is the whole point of moving in.
static func focus_framing(
	framing: Dictionary, focus: Vector3, radius: float = DEFAULT_ACTIVITY_RADIUS
) -> Dictionary:
	return _fit_framing(framing, focus, radius, CLOSE_UP_SUBJECT_HEIGHT, FOCUS_MIN_DISTANCE)


## A PORTRAIT: the same pitch, yaw and clamps as `focus_framing()`, fitted to a
## box small enough to be one child's head and shoulders.
##
## `focus_framing()` is deliberately a two-shot -- it keeps the caregiver's 1.55 m
## head and a 1.9 m standoff, because every beat it frames has Aliz standing in
## it. The feeding close-up is the one beat that does not: Aliz is behind the
## camera holding the bottle, and the subject is a 0.85 m toddler whose head the
## player has to be able to aim at. Fitting HIM with HER constraints leaves him a
## third of the frame, which is exactly the shot the flat placeholder face was
## papering over.
##
## `subject_height` is the tallest point that must stay on screen, above the
## room's floor, and `min_distance` the closest the camera may stand. Both are
## floors, never targets: a box that needs more air still gets it, and
## `CAMERA_CLEARANCE` still keeps the camera out of the child's head.
static func portrait_framing(
	framing: Dictionary, focus: Vector3, radius: float = PORTRAIT_RADIUS,
	subject_height: float = PORTRAIT_SUBJECT_HEIGHT, min_distance: float = PORTRAIT_MIN_DISTANCE
) -> Dictionary:
	var fitted: Dictionary = _fit_framing(
		framing, focus, radius,
		maxf(_number(subject_height, PORTRAIT_SUBJECT_HEIGHT), 0.2),
		maxf(_number(min_distance, PORTRAIT_MIN_DISTANCE), MIN_DEPTH)
	)
	# The room's headroom (1.0 m) is demanded above all FOUR corners of the box,
	# and on a half-metre box around a toddler's mouth that air -- not the child --
	# is what binds: measured at 1.80 m with the far-top corner as the binding
	# point, and Bunny a third of the frame. The subject point already guarantees
	# the top of his head; the corners only need enough to keep the shot from
	# composing on his shoes.
	fitted["headroom"] = minf(float(fitted["headroom"]), PORTRAIT_HEADROOM)
	return fitted


static func _fit_framing(
	framing: Dictionary, focus: Vector3, radius: float,
	subject_height: float, min_distance: float
) -> Dictionary:
	var base: Dictionary = normalise_framing(framing)
	var safe_radius: float = maxf(_number(radius, DEFAULT_ACTIVITY_RADIUS), 0.1)
	var centre: Vector3 = _vec3(focus, base["focus"])
	base["bounds"] = Rect2(
		centre.x - safe_radius, centre.z - safe_radius, safe_radius * 2.0, safe_radius * 2.0
	)
	# The box is centred on what the caller asked for; the AIM slides toward the
	# camera. See `FOCUS_LOOKAHEAD`. Along the view direction's horizontal
	# component rather than along world `+Z`, so a room that ever authored a yaw
	# gets the slide in its own forward rather than in the world's.
	var toward_camera: Vector3 = view_direction(base)
	var along := Vector3(toward_camera.x, 0.0, toward_camera.z)
	if along.length() < 0.0001:
		along = Vector3(0.0, 0.0, 1.0)
	base["focus"] = centre + along.normalized() * (safe_radius * FOCUS_LOOKAHEAD)
	# The room's own extra "must be visible" points are a room-scale concern; an
	# activity close-up deliberately does not have to keep the far wall on screen.
	# What it DOES have to keep on screen is the person standing in it, whom the
	# generic 1.0 m headroom under-measures by more than half a metre. See
	# `CLOSE_UP_SUBJECT_HEIGHT`.
	base["extraPoints"] = [Vector3(
		centre.x, float(base["floorY"]) + subject_height, centre.z
	)]
	# ...and for the same reason it is not held out at the room's own standoff.
	# See `FOCUS_MIN_DISTANCE`: this one line is the difference between a close-up
	# and a slightly-less-wide shot.
	base["minDistance"] = maxf(
		minf(float(base["minDistance"]), min_distance), MIN_DEPTH
	)
	base["maxDistance"] = maxf(float(base["maxDistance"]), float(base["minDistance"]))
	return base


## Every world point that must land on screen.
##
## The four floor corners of `bounds`, the same four at head height, the focus,
## and anything the room added. If the floor corners and the headroom above them
## are visible then so is every square metre of the room between them, because a
## perspective frustum is convex.
static func fit_points(framing: Dictionary) -> Array:
	var f: Dictionary = normalise_framing(framing)
	var bounds: Rect2 = f["bounds"]
	var floor_y: float = f["floorY"]
	var headroom: float = f["headroom"]

	var points: Array = [f["focus"]]
	for corner: Vector2 in [
		bounds.position,
		bounds.position + Vector2(bounds.size.x, 0.0),
		bounds.position + Vector2(0.0, bounds.size.y),
		bounds.end,
	]:
		points.append(Vector3(corner.x, floor_y, corner.y))
		if headroom > 0.0:
			points.append(Vector3(corner.x, floor_y + headroom, corner.y))
	points.append_array(f["extraPoints"])
	return points


## -- Composition ---------------------------------------------------------------

## Unit vector from the focus TOWARDS the camera. Independent of distance: this
## vector IS the composition, and it is what stays constant across aspect ratios.
static func view_direction(framing: Dictionary) -> Vector3:
	var f: Dictionary = normalise_framing(framing)
	var pitch: float = deg_to_rad(float(f["angle"]))
	var yaw: float = deg_to_rad(float(f["yaw"]))
	var direction := Vector3(
		sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)
	)
	if direction.length() < 0.0001:
		direction = Vector3(0.0, sin(deg_to_rad(DEFAULT_ANGLE_DEGREES)), cos(deg_to_rad(DEFAULT_ANGLE_DEGREES)))
	return direction.normalized()


## The camera's orientation, built exactly the way `Camera3D.look_at_from_position()`
## builds it. Shared by the solver and the applier so the two cannot drift.
static func camera_basis(framing: Dictionary) -> Basis:
	return Basis.looking_at(-view_direction(framing), Vector3.UP)


static func camera_position(framing: Dictionary, distance: float) -> Vector3:
	var f: Dictionary = normalise_framing(framing)
	return Vector3(f["focus"]) + view_direction(f) * _number(distance, float(f["minDistance"]))


static func camera_transform(framing: Dictionary, distance: float) -> Transform3D:
	return Transform3D(camera_basis(framing), camera_position(framing, distance))


## -- The fit -------------------------------------------------------------------

## Half-extents of the USABLE screen, as multiples of the projection's own half
## extents, after insets. `Vector4(left, top, right, bottom)`, each in (0, 1].
##
## Screen space is 2 NDC units wide, so an inset covering a fraction `i` of the
## screen eats `2 * i` of NDC and leaves `1 - 2 * i` of that side's half-extent.
## Each side is independent, which is what makes a notch on the left and a notch
## on the right (the same phone, rotated the other way) both work without a
## special case.
static func ndc_limits(insets: Vector4) -> Vector4:
	var safe: Vector4 = _vec4(insets)
	return Vector4(
		clampf(1.0 - 2.0 * safe.x, MIN_NDC_LIMIT, 1.0),
		clampf(1.0 - 2.0 * safe.y, MIN_NDC_LIMIT, 1.0),
		clampf(1.0 - 2.0 * safe.z, MIN_NDC_LIMIT, 1.0),
		clampf(1.0 - 2.0 * safe.w, MIN_NDC_LIMIT, 1.0)
	)


## The whole answer, in one dictionary.
##
## Returns:
##   `distance`  -- clamped into [minDistance, maxDistance]
##   `required`  -- the raw closest-fitting distance, before clamping
##   `position`  -- the camera's world position
##   `transform` -- position and orientation
##   `focus`     -- the look-at point actually used
##   `fov`       -- the vertical field of view the camera must be set to
##   `fits`      -- false only when `maxDistance` is too small for the room
##   `clamped`   -- true when a clamp changed the answer
##   `binding`   -- which constraint set the distance: horizontal / vertical / depth
##   `bindingPoint` -- the world point that set it
static func solve(
	framing: Dictionary, aspect: float, insets: Vector4 = Vector4.ZERO
) -> Dictionary:
	var f: Dictionary = normalise_framing(framing)
	var safe_aspect: float = clampf(_number(aspect, REFERENCE_ASPECT), MIN_ASPECT, MAX_ASPECT)
	var fov: float = float(f["fov"])

	# KEEP_HEIGHT: the VERTICAL half-extent is what the field of view fixes, and
	# the horizontal one is derived from the aspect. This single line is why a
	# narrow screen needs a camera further back.
	var half_height: float = tan(deg_to_rad(fov) * 0.5)
	var half_width: float = half_height * safe_aspect

	var limits: Vector4 = ndc_limits(insets)
	var limit_left: float = half_width * limits.x
	var limit_top: float = half_height * limits.y
	var limit_right: float = half_width * limits.z
	var limit_bottom: float = half_height * limits.w

	var basis: Basis = camera_basis(f)
	var forward: Vector3 = -basis.z
	var right: Vector3 = basis.x
	var up: Vector3 = basis.y
	var focus: Vector3 = f["focus"]

	# Starts at "no requirement at all", NOT at `minDistance`, so `required` stays
	# the honest unclamped answer and `clamped` can tell a caller that the authored
	# range -- rather than the room's shape -- decided where the camera stands.
	var required: float = MIN_DEPTH
	var binding: String = BINDING_NONE
	var binding_point: Vector3 = focus

	# Height first: the camera rises with the distance (`position.y = focus.y +
	# sin(pitch) * d`), so "stay above everything" is just another lower bound on
	# the distance. Rarely the binding constraint for a real room, but it is what
	# keeps a wide, shallow room from being framed from inside its own furniture.
	var clearance_height: float = float(f["floorY"]) + float(f["headroom"]) + CAMERA_CLEARANCE
	var sin_pitch: float = maxf(view_direction(f).y, 0.05)
	var clearance_distance: float = (clearance_height - focus.y) / sin_pitch
	if is_finite(clearance_distance) and clearance_distance > required:
		required = clearance_distance
		binding = BINDING_CLEARANCE

	for point: Vector3 in fit_points(f):
		var q: Vector3 = point - focus
		var depth_at_zero: float = q.dot(forward)
		var x: float = q.dot(right)
		var y: float = q.dot(up)

		# Never let anything reach the camera plane. Also the reason no later
		# division can see a non-positive depth.
		var candidates: Array = [[MIN_DEPTH - depth_at_zero, BINDING_DEPTH]]
		if x > 0.0:
			candidates.append([x / limit_right - depth_at_zero, BINDING_HORIZONTAL])
		elif x < 0.0:
			candidates.append([-x / limit_left - depth_at_zero, BINDING_HORIZONTAL])
		if y > 0.0:
			candidates.append([y / limit_top - depth_at_zero, BINDING_VERTICAL])
		elif y < 0.0:
			candidates.append([-y / limit_bottom - depth_at_zero, BINDING_VERTICAL])

		for candidate: Array in candidates:
			var value: float = float(candidate[0])
			if not is_finite(value):
				continue
			if value > required:
				required = value
				binding = String(candidate[1])
				binding_point = point

	var distance: float = clampf(required, float(f["minDistance"]), float(f["maxDistance"]))
	var position: Vector3 = focus + view_direction(f) * distance

	return {
		"distance": distance,
		"required": required,
		"position": position,
		"transform": Transform3D(basis, position),
		"focus": focus,
		"fov": fov,
		"aspect": safe_aspect,
		"insets": _vec4(insets),
		"fits": required <= float(f["maxDistance"]) + FIT_EPSILON,
		"clamped": not is_equal_approx(distance, required),
		"binding": binding,
		"bindingPoint": binding_point,
	}


## The distance alone, for callers that do not need the rest.
static func fit_distance(
	framing: Dictionary, aspect: float, insets: Vector4 = Vector4.ZERO
) -> float:
	return float(solve(framing, aspect, insets)["distance"])


## True when every fit point lands inside the usable screen at this distance.
##
## The independent verifier for the solver: `solve()` computes a distance and this
## checks one. A test asserts both that the fitted distance passes and that
## slightly closer fails, which is what makes "as close as possible" a property
## rather than an intention.
static func frames_everything(
	framing: Dictionary, distance: float, aspect: float, insets: Vector4 = Vector4.ZERO
) -> bool:
	var f: Dictionary = normalise_framing(framing)
	var safe_aspect: float = clampf(_number(aspect, REFERENCE_ASPECT), MIN_ASPECT, MAX_ASPECT)
	var half_height: float = tan(deg_to_rad(float(f["fov"])) * 0.5)
	var half_width: float = half_height * safe_aspect
	var limits: Vector4 = ndc_limits(insets)

	var basis: Basis = camera_basis(f)
	var forward: Vector3 = -basis.z
	var position: Vector3 = camera_position(f, distance)

	for point: Vector3 in fit_points(f):
		var offset: Vector3 = point - position
		var depth: float = offset.dot(forward)
		if depth < MIN_DEPTH - FIT_EPSILON:
			return false
		var ndc_x: float = (offset.dot(basis.x) / depth) / half_width
		var ndc_y: float = (offset.dot(basis.y) / depth) / half_height
		if ndc_x > limits.z + FIT_EPSILON or ndc_x < -limits.x - FIT_EPSILON:
			return false
		if ndc_y > limits.y + FIT_EPSILON or ndc_y < -limits.w - FIT_EPSILON:
			return false
	return true


static func aspect_from_size(size: Vector2) -> float:
	if size.x <= 0.0 or size.y <= 0.0 or not is_finite(size.x) or not is_finite(size.y):
		return REFERENCE_ASPECT
	return clampf(size.x / size.y, MIN_ASPECT, MAX_ASPECT)


## -- Sanitisers ----------------------------------------------------------------
##
## A room is authored data, and authored data is occasionally wrong. Every input
## is filtered so a typo produces a slightly odd camera rather than a NaN
## transform, which Godot propagates silently until the whole scene disappears.

static func _number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var number: float = float(value)
		if is_finite(number):
			return number
	return fallback


static func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		var v: Vector3 = value
		if is_finite(v.x) and is_finite(v.y) and is_finite(v.z):
			return v
	return fallback


static func _vec4(value: Variant) -> Vector4:
	if value is Vector4:
		var v: Vector4 = value
		return Vector4(
			clampf(_number(v.x, 0.0), 0.0, 0.45),
			clampf(_number(v.y, 0.0), 0.0, 0.45),
			clampf(_number(v.z, 0.0), 0.0, 0.45),
			clampf(_number(v.w, 0.0), 0.0, 0.45)
		)
	return Vector4.ZERO


## A degenerate rectangle is legal and must not divide by zero: a zero-size room
## collapses its four corners onto one point, the fit falls back to the minimum
## distance, and the camera still points somewhere sane.
static func _rect(value: Variant) -> Rect2:
	if not (value is Rect2):
		return Rect2()
	var rect: Rect2 = value
	if not (is_finite(rect.position.x) and is_finite(rect.position.y)
			and is_finite(rect.size.x) and is_finite(rect.size.y)):
		return Rect2()
	return rect.abs()
