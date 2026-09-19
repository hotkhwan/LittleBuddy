extends RefCounted

## ============================================================================
## CHILD ACCOMPANIMENT -- Little Buddy goes with Buddy, visibly.
## ============================================================================
##
## Pure logic. It owns no node, does no navigation and never touches the scene
## tree: it takes positions in, and returns where the child should be and what
## the child should be doing. `child_actor.gd` applies the answer.
##
## That split is what makes the rules below assertable without a room, a
## navigation mesh or a frame loop -- and the rules are the part that matters,
## because every one of them is a way a following child goes wrong.
##
## ## The five states
##
##   WAITING    -- the child stays put. The default, and where it returns to.
##   FOLLOWING  -- the child trails Buddy at a polite distance.
##   ARRIVING   -- Buddy has stopped; the child closes the last gap and stops.
##   ATTENDING  -- the child stands at an activity target, facing it.
##   IDLE       -- back to waiting, having arrived.
##
## ## Following, not carrying
##
## The brief says prefer following and do not fake a carry we do not have. We
## have walk and run clips for the rigged child, so following is honest. Carrying
## would need a hold pose on Buddy and an attach point on her rig, and she has
## neither -- so it is not attempted.
##
## ## What must never happen (each is a rule below, not a hope)
##
##   * **Teleporting in front of the camera.** A child further than
##     `TELEPORT_DISTANCE` is re-placed, but only BEHIND Buddy and only during a
##     room change, when the screen is covered by the transition fade.
##   * **Disappearing after a room transition.** `room_changed()` moves the child
##     to the new room explicitly rather than leaving it to walk through a wall.
##   * **Blocking a door.** The follow point is offset to Buddy's side and behind,
##     never into the doorway she just used.
##   * **Trapping the player.** The child never pushes; `desired_position()` is
##     advisory and the child's body has no collision with Buddy.
##   * **Getting stuck in a previous room.** `room_changed()` is the only way the
##     child's room changes, and it always sets one.

const STATE_WAITING: String = "waiting"
const STATE_FOLLOWING: String = "following"
const STATE_ARRIVING: String = "arriving"
const STATE_ATTENDING: String = "attending"
const STATE_IDLE: String = "idle"

## How far behind Buddy the child walks. Far enough not to clip through her,
## close enough to read as together.
const FOLLOW_DISTANCE: float = 0.62
## Sideways offset, so the child walks beside-and-behind rather than in her
## shadow -- and, critically, never in the doorway she is standing in.
const FOLLOW_SIDE_OFFSET: float = 0.34
## Closer than this and the child stops walking; it has arrived.
const ARRIVE_DISTANCE: float = 0.30
## Further than this and following has failed -- a wall, a bad path, a room
## change. Only ever resolved while the screen is covered.
const TELEPORT_DISTANCE: float = 6.0
## Child walking speed, metres/second, matched to the walk clip's stride so the
## feet do not skate. See docs/MESHY_RIG_VALIDATION.md section 7.
const WALK_SPEED: float = 0.42

var state: String = STATE_WAITING
var room_id: String = ""


## Where the child should stand, given where Buddy is and which way she faces.
##
## `buddy_forward` is her facing as a unit vector on the XZ plane. The follow
## point is BEHIND her along it and offset to one side, which is what keeps the
## child out of the doorway she is standing in.
static func follow_point(buddy_position: Vector3, buddy_forward: Vector3) -> Vector3:
	var forward: Vector3 = buddy_forward
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	return buddy_position - forward * FOLLOW_DISTANCE + side * FOLLOW_SIDE_OFFSET


## The state the child should be in. Pure: same inputs, same answer.
##
## `attending` wins over everything, because a child placed at a sink for a care
## act must stay there even if Buddy shuffles.
static func next_state(
	current: String,
	child_position: Vector3,
	target_position: Vector3,
	following: bool,
	attending: bool
) -> String:
	if attending:
		return STATE_ATTENDING
	if not following:
		return STATE_WAITING
	var gap: float = _flat_distance(child_position, target_position)
	if gap <= ARRIVE_DISTANCE:
		# Already there: `arriving` only once, then idle, so a caller can react to
		# the arrival exactly once rather than every frame.
		return STATE_IDLE if current == STATE_ARRIVING or current == STATE_IDLE \
				else STATE_ARRIVING
	return STATE_FOLLOWING


## One step of movement towards `target`, capped by speed. Returns the new
## position. Never overshoots, so the child cannot jitter around the point.
static func step_towards(from: Vector3, target: Vector3, delta: float) -> Vector3:
	var to_target: Vector3 = target - from
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance <= 0.0001:
		return from
	var travel: float = minf(WALK_SPEED * maxf(delta, 0.0), distance)
	return from + to_target.normalized() * travel


## Has the child lost Buddy badly enough that walking will not fix it?
##
## Only ever acted on during a covered transition -- see the class doc. This
## returns the FACT; the caller decides whether it is allowed to act on it.
static func is_stranded(child_position: Vector3, buddy_position: Vector3) -> bool:
	return _flat_distance(child_position, buddy_position) > TELEPORT_DISTANCE


## Which way the child should face: towards what it is attending, else the way it
## is walking, else leave it alone (Vector3.ZERO).
static func facing_for(state_name: String, child_position: Vector3,
		target_position: Vector3) -> Vector3:
	if state_name == STATE_WAITING or state_name == STATE_IDLE:
		return Vector3.ZERO
	var to_target: Vector3 = target_position - child_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return Vector3.ZERO
	return to_target.normalized()


## The LOCOMOTION clip the child's model should be playing. `walk` and `run` are
## the only two the export ships with, so nothing else is claimed here.
##
## Standing still is deliberately "" rather than `idle`: this file's business is
## going places, and what a child does when it is not going anywhere -- breathe,
## fuss, be fed, be pleased -- is `child_life.gd`'s decision, not the follower's.
static func clip_for(state_name: String) -> String:
	return "walk" if state_name == STATE_FOLLOWING else ""


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
