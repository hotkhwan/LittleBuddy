extends RefCounted

## The navigation spike's floor plan, as data.
##
## One source of truth for the room shape, the obstacles, the tap pads and the
## camera framing. The scene builds its visible geometry from these numbers, the
## navigation mesh is cut from the same numbers, and the tests assert against the
## same numbers -- so "the wall you can see" and "the wall the navigation mesh
## knows about" cannot drift apart, which is the classic way a character ends up
## walking through furniture.

## Floor extents in the XZ plane: x from -3 to 3, z from -2.5 to 2.5.
const FLOOR_BOUNDS: Rect2 = Rect2(-3.0, -2.5, 6.0, 5.0)
const FLOOR_Y: float = 0.0
const CELL_SIZE: float = 0.2
const AGENT_RADIUS: float = 0.15
const WALL_HEIGHT: float = 0.5

## Solid, non-walkable rectangles.
##
## `Closet` is the important one: two walls that, together with the floor's own
## far corner, completely enclose a patch of floor. It exists so "tap somewhere
## Little Buddy cannot reach" is a real, on-mesh, genuinely disconnected place
## rather than just a point outside the room -- both cases are worth testing, and
## this is the one a real house will actually produce (a closed door).
const OBSTACLES: Array[Rect2] = [
	Rect2(-0.6, -0.4, 1.2, 0.8),    # Table in the middle: paths must route around it.
	Rect2(-2.5, -1.9, 0.6, 0.6),    # Toy box (the interactive object's footprint).
	Rect2(1.8, -2.5, 0.2, 1.5),     # Closet wall, running in from the far edge.
	Rect2(1.8, -1.2, 1.2, 0.2),     # Closet wall, closing the box off.
]

## Indices into `OBSTACLES`, so the scene can treat two of them specially without
## re-declaring their rectangles (and so a reordering breaks loudly, not quietly).
const TABLE_OBSTACLE_INDEX: int = 0
const TOY_BOX_OBSTACLE_INDEX: int = 1

## A point inside the sealed closet. Reachable by nothing.
const UNREACHABLE_INSIDE_ROOM: Vector3 = Vector3(2.6, 0.0, -2.0)

## A point well outside the room entirely -- the "tapped the sky / tapped the far
## wall" case.
const UNREACHABLE_OUTSIDE_ROOM: Vector3 = Vector3(9.0, 0.0, 9.0)

## Where Little Buddy starts.
const START_POSITION: Vector3 = Vector3(0.0, 0.0, 1.3)

## The four tap pads: visible, generously sized floor markers a child can aim at.
## They are decoration only -- the floor is tappable everywhere -- but a
## four-year-old needs somewhere obvious to poke first.
const TAP_PADS: Array[Vector3] = [
	Vector3(-2.2, 0.0, 1.6),
	Vector3(2.4, 0.0, 1.6),
	Vector3(0.0, 0.0, 2.0),
	Vector3(2.4, 0.0, 0.2),
]
const TAP_PAD_RADIUS: float = 0.42

## The interactive object (an `ActivityTarget` with an `InteractionPoint`).
const TOY_BOX_ID: String = "toyBox"
const TOY_BOX_POSITION: Vector3 = Vector3(-2.2, 0.15, -1.6)
const TOY_BOX_SIZE: Vector3 = Vector3(0.6, 0.3, 0.6)
## Stand here, on the open side of the box, not inside its footprint.
const TOY_BOX_STAND_POSITION: Vector3 = Vector3(-2.2, 0.0, -0.85)

## The draggable object, proving drag-and-drop still works alongside navigation.
const BALL_ID: String = "ball"
const BALL_POSITION: Vector3 = Vector3(1.0, 0.16, 1.5)
const BALL_RADIUS: float = 0.16
## Generous, matching the Baby Room's existing drop-zone radius.
const DROP_ZONE_RADIUS: float = 0.32
## Where the ball is delivered: chest height on the character, so the zone moves
## while Little Buddy walks. If dragging survives that, it survives navigation.
const CHEST_OFFSET: Vector3 = Vector3(0.0, 0.42, 0.0)

## Camera framing.
##
## Set in code with `look_at_from_position()`, never trusted to a hand-written
## `Transform3D` in the .tscn. A previously shipped inverted pitch there pushed
## every object below the viewport while every automated test still passed, so
## `test_nav_spike_scene.gd` additionally unprojects every landmark and asserts it
## lands inside the visible rect.
##
## ## Why the distance is computed rather than hard-coded
##
## The game has to run on a landscape iPhone (~2.17:1) and an iPad (1.33:1) from
## one scene. Godot's default `KEEP_HEIGHT` fixes the vertical field of view, so a
## fixed camera distance that frames a 6 x 5 m room snugly on one of those wastes
## half the screen on the other -- or, worse, crops the room on the phone.
##
## `fit_camera_distance()` therefore pulls the camera back along a FIXED viewing
## direction until every landmark fits the current aspect ratio, and no further.
## Narrow screens end up further away (the room's width is what binds); wide
## screens come closer until the room's depth binds instead. The pitch and the
## look-at target never change, so the composition is identical everywhere -- only
## the framing tightens.
##
## This is the reusable answer for `HouseWorld`, which will have the same problem
## with bigger rooms.
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.1, -0.35)
const CAMERA_FOV: float = 52.0

## Direction from the look-at target towards the camera. Fixed: this is the
## composition. Roughly 37 degrees above the horizontal, looking slightly down at
## a room seen from the front -- the same read as the Baby Room's camera.
const CAMERA_OFFSET_DIRECTION: Vector3 = Vector3(0.0, 4.8, 6.45)

## Landmarks must fall inside this fraction of the half-screen, so a notch, a
## rounded corner or a safe-area inset cannot clip the room.
const CAMERA_SAFE_MARGIN: float = 0.08
const CAMERA_MIN_DISTANCE: float = 4.0
const CAMERA_MAX_DISTANCE: float = 20.0
const CAMERA_FIT_STEP: float = 0.05

## The reference framing, for a 4:3 iPad. Only a fallback for callers that cannot
## see a viewport; everything real goes through `fit_camera_distance()`.
const CAMERA_REFERENCE_ASPECT: float = 4.0 / 3.0


static func camera_position(distance: float) -> Vector3:
	return CAMERA_TARGET + CAMERA_OFFSET_DIRECTION.normalized() * distance


## The closest the camera can sit and still show every landmark at `aspect`.
##
## Pure, deterministic and cheap (a few hundred dot products, once at load), so
## the framing is an assertable property rather than a hand-tuned constant that
## silently rots when the room changes shape.
static func fit_camera_distance(aspect: float) -> float:
	var half_height: float = tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var half_width: float = half_height * maxf(aspect, 0.1)
	var limit: float = 1.0 - CAMERA_SAFE_MARGIN

	var distance: float = CAMERA_MIN_DISTANCE
	while distance < CAMERA_MAX_DISTANCE:
		if frames_everything(distance, half_width, half_height, limit):
			return distance
		distance += CAMERA_FIT_STEP
	return CAMERA_MAX_DISTANCE


## True when every landmark projects inside `limit` of the half-screen, and in
## front of the camera. Shared by the scene and by the framing test, so the test
## cannot drift away from what the scene actually does.
static func frames_everything(
	distance: float, half_width: float, half_height: float, limit: float
) -> bool:
	var position: Vector3 = camera_position(distance)
	var basis: Basis = Basis.looking_at(CAMERA_TARGET - position, Vector3.UP)
	var forward: Vector3 = -basis.z

	for point: Vector3 in landmarks():
		var offset: Vector3 = point - position
		var depth: float = offset.dot(forward)
		if depth <= 0.01:
			return false
		if absf((offset.dot(basis.x) / depth) / half_width) > limit:
			return false
		if absf((offset.dot(basis.y) / depth) / half_height) > limit:
			return false
	return true


## Every point that must be visible on screen. Used by the framing test.
static func landmarks() -> Array:
	var points: Array = [START_POSITION, TOY_BOX_POSITION, BALL_POSITION, TOY_BOX_STAND_POSITION]
	points.append_array(TAP_PADS)
	# The four floor corners: if these are on screen, the whole playable area is.
	for corner: Vector2 in [
		FLOOR_BOUNDS.position,
		FLOOR_BOUNDS.position + Vector2(FLOOR_BOUNDS.size.x, 0.0),
		FLOOR_BOUNDS.position + Vector2(0.0, FLOOR_BOUNDS.size.y),
		FLOOR_BOUNDS.end,
	]:
		points.append(Vector3(corner.x, FLOOR_Y, corner.y))
	return points
