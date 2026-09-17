extends RefCounted

## Fallback room framing: the smallest camera distance that fits a whole room on
## screen at the CURRENT aspect ratio.
##
## ## Why this exists at all
##
## The room camera itself (`scripts/camera/room_camera.gd`) is owned by another
## agent and may not be present. `HouseWorld` duck-types it: if a camera node
## answers `frame_room()`, that camera wins and this file is never used. If it
## does not, the world must still be playable, renderable and reviewable rather
## than showing a black screen -- so this is the minimum honest fallback.
##
## ## Why the distance is fitted rather than fixed
##
## Godot's default `KEEP_HEIGHT` fixes the VERTICAL field of view, so one fixed
## distance cannot frame a 4 x 4 m room on both a 1.33:1 iPad (where the room's
## width binds) and a 2.17:1 landscape iPhone (where its depth binds). The pitch
## and the look-at point are fixed -- that is the composition, and it must not
## change between devices -- and only the distance moves.
##
## Pure and static: no node, no viewport, no tree. The whole thing is assertable.

## Landmarks must land inside this fraction of the half-screen, so a notch, a
## rounded corner or a safe-area inset cannot clip the room.
const SAFE_MARGIN: float = 0.09
const FIT_STEP: float = 0.05
## Head height of the toddler, plus a little. The child must always be able to
## see Little Buddy, including when standing at the very back of the room.
const CHARACTER_HEIGHT: float = 1.0


## Direction from the focus point towards the camera, for a pitch of
## `angle_degrees` above the horizontal. The camera always sits on the +Z side,
## looking towards -Z, which is the same read as the Baby Room's camera.
static func offset_direction(angle_degrees: float) -> Vector3:
	var angle: float = deg_to_rad(clampf(angle_degrees, 5.0, 85.0))
	return Vector3(0.0, sin(angle), cos(angle)).normalized()


static func camera_position(framing: Dictionary, distance: float) -> Vector3:
	var focus: Vector3 = framing.get("focus", Vector3.ZERO)
	return focus + offset_direction(float(framing.get("angle", 38.0))) * distance


## Every point that must be on screen: the four floor corners, and the same four
## corners at head height (a character standing in any corner must be visible).
static func landmarks(framing: Dictionary) -> Array:
	var bounds: Rect2 = framing.get("bounds", Rect2())
	var focus: Vector3 = framing.get("focus", Vector3.ZERO)
	var points: Array = []
	for corner: Vector2 in [
		bounds.position,
		bounds.position + Vector2(bounds.size.x, 0.0),
		bounds.position + Vector2(0.0, bounds.size.y),
		bounds.end,
	]:
		points.append(Vector3(corner.x, 0.0, corner.y))
		points.append(Vector3(corner.x, CHARACTER_HEIGHT, corner.y))
	points.append(focus)
	return points


## True when every landmark projects inside `limit` of the half-screen and in
## front of the camera.
static func frames_everything(
	framing: Dictionary, distance: float, half_width: float, half_height: float, limit: float
) -> bool:
	var focus: Vector3 = framing.get("focus", Vector3.ZERO)
	var position: Vector3 = camera_position(framing, distance)
	var to_focus: Vector3 = focus - position
	if to_focus.length_squared() <= 0.000001:
		return false
	var basis: Basis = Basis.looking_at(to_focus, Vector3.UP)
	var forward: Vector3 = -basis.z

	for point: Vector3 in landmarks(framing):
		var offset: Vector3 = point - position
		var depth: float = offset.dot(forward)
		if depth <= 0.01:
			return false
		if absf((offset.dot(basis.x) / depth) / half_width) > limit:
			return false
		if absf((offset.dot(basis.y) / depth) / half_height) > limit:
			return false
	return true


## The closest distance that still shows the whole room at `aspect`.
static func fit_distance(framing: Dictionary, aspect: float, fov_degrees: float) -> float:
	var half_height: float = tan(deg_to_rad(fov_degrees) * 0.5)
	var half_width: float = half_height * maxf(aspect, 0.1)
	var limit: float = 1.0 - SAFE_MARGIN
	var minimum: float = float(framing.get("minDistance", 3.5))
	var maximum: float = float(framing.get("maxDistance", 18.0))

	var distance: float = minimum
	while distance < maximum:
		if frames_everything(framing, distance, half_width, half_height, limit):
			return distance
		distance += FIT_STEP
	return maximum
