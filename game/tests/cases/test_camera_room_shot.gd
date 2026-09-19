extends RefCounted

## The EXPLORATION shot, and the price of tightening it.
##
## `test_camera_framing.gd` proves the solver puts the camera at the closest
## distance that fits what it was given. This file is about what it is given,
## which is the part that moved:
##
##   * the room's look-at point is no longer its centre (`CAMERA_FOCUS_Z`), and
##   * a close-up is no longer held out at the room's own `minDistance`
##     (`camera_framing.FOCUS_MIN_DISTANCE`).
##
## Both make the picture bigger, and both are exactly the kind of change that
## buys scale by quietly cropping something. So the rules are asserted from the
## other end: whatever the framing says, the tall furniture and the door plaques
## must still be inside the safe area on every aspect ratio the game ships on.
##
## The failure this exists to prevent is specific and was one constant away.
## `camera_framing.solve()` fits the floor corners and the same corners at HEAD
## height -- it has never known anything about a 1.8 m wardrobe. That gap was
## invisible while the camera stood 5.1 m back and paid for it out of slack. The
## first time the look-at point moved forward, the top of the fridge left the
## frame, and nothing in the suite noticed.

const Framing := preload("res://scripts/camera/camera_framing.gd")
const Focus := preload("res://scripts/camera/camera_focus.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const Insets := preload("res://scripts/camera/safe_area_insets.gd")

## iPad 4:3 (the project's own reference), iPad landscape, 16:9, landscape iPhone.
const ASPECTS: Array[float] = [1366.0 / 1024.0, 1334.0 / 750.0, 16.0 / 9.0, 2340.0 / 1080.0]

## Anything whose top is above this has to be named in the framing's fit points
## rather than left to the generic `headroom`.
const TALL: float = HouseLayout.CAMERA_TALL_PROP_Y


func test_name() -> String:
	return "camera_room_shot"


func run():
	var failures: Array = []
	failures += _test_tall_furniture_survives_the_tighter_shot()
	failures += _test_door_plaques_stay_readable()
	failures += _test_the_forward_look_at_point_actually_earns_its_keep()
	failures += _test_a_close_up_may_stand_closer_than_the_room()
	failures += _test_but_never_inside_the_child()
	return failures


## -- 1. Nothing tall is cropped ---------------------------------------------------

## Every tall prop's top corners, at every aspect, must land inside the usable
## screen at the distance the room is actually framed from.
##
## Checked through `frames_everything()` -- the solver's independent verifier --
## rather than by re-deriving the projection, so this cannot pass by repeating
## the solver's own arithmetic back to it.
func _test_tall_furniture_survives_the_tighter_shot():
	var failures: Array = []
	var insets: Vector4 = Insets.chrome_insets()

	for room_id: String in HouseLayout.room_ids():
		var framing: Dictionary = HouseLayout.camera_framing(room_id)
		var tall: Array = _tall_props(room_id)
		if tall.is_empty():
			continue

		# The room's own framing must already claim them, or the guarantee is
		# accidental: it would hold today and break the next time a constant moves.
		var claimed: Array = framing.get("extraPoints", [])
		for prop: Dictionary in tall:
			var found: bool = false
			for point: Variant in claimed:
				if point is Vector3 and absf((point as Vector3).y - float(prop["top"])) < 0.001:
					found = true
					break
			if not found:
				failures.append(("%s's '%s' stands %.2f m tall and is not in the room's camera "
						+ "fit points. The fit only knows about the floor corners and %.2f m of "
						+ "headroom above them, so its top is kept on screen by luck.")
						% [room_id, String(prop["targetId"]), float(prop["top"]),
								Framing.DEFAULT_HEADROOM])

		for aspect: float in ASPECTS:
			var solution: Dictionary = Framing.solve(framing, aspect, insets)
			if not bool(solution["fits"]):
				failures.append("%s does not fit at %.2f:1 at all" % [room_id, aspect])
				continue
			if not Framing.frames_everything(
					framing, float(solution["distance"]), aspect, insets):
				failures.append(("%s at %.2f:1 is framed from %.2f m, and something it asked to "
						+ "keep on screen is off it")
						% [room_id, aspect, float(solution["distance"])])
	return failures


## -- 2. The plaques ---------------------------------------------------------------

## A door sign that is cropped is worse than no door sign: the child has been
## given a landmark and then had half of it taken away. Both plaques, both walls,
## every aspect.
func _test_door_plaques_stay_readable():
	var failures: Array = []
	var insets: Vector4 = Insets.chrome_insets()
	var top: float = HouseLayout.DOOR_SIGN_CENTRE_Y + HouseLayout.DOOR_SIGN_SIZE.y * 0.5

	if top >= HouseLayout.WALL_HEIGHT:
		failures.append("the door plaque's top is at %.2f m and the wall is %.2f m; it would "
				% [top, HouseLayout.WALL_HEIGHT] + "stand proud of the room")

	for room_id: String in HouseLayout.room_ids():
		var framing: Dictionary = HouseLayout.camera_framing(room_id)
		var origin: Vector3 = HouseLayout.room_origin(room_id)
		for door: Dictionary in HouseLayout.doors(room_id):
			var side: float = float(door["side"])
			var z: float = (door["position"] as Vector3).z
			for edge: float in [-0.5, 0.5]:
				var corner: Vector3 = origin + Vector3(
					side * HouseLayout.DOOR_SIGN_X + edge * HouseLayout.DOOR_SIGN_SIZE.x,
					top, z
				)
				var probe: Dictionary = framing.duplicate(true)
				probe["extraPoints"] = [corner]
				for aspect: float in ASPECTS:
					var distance: float = float(Framing.solve(framing, aspect, insets)["distance"])
					if not Framing.frames_everything(probe, distance, aspect, insets):
						failures.append(("%s's plaque for the %s corner %s is off screen at "
								+ "%.2f:1")
								% [room_id, String(door["toRoomId"]), str(corner), aspect])
						break
	return failures


## -- 3. The forward look-at point --------------------------------------------------

## The bias is not decoration: it exists because a room-centred shot at this
## pitch spends two metres of distance on the near floor edge. If someone
## "tidies" it back to zero, the shot silently loses ~11% of its scale and every
## other test still passes -- so the gain is measured here.
func _test_the_forward_look_at_point_actually_earns_its_keep():
	var failures: Array = []
	var insets: Vector4 = Insets.chrome_insets()

	if HouseLayout.CAMERA_FOCUS_Z <= 0.0:
		return ["the room shot looks at the room's centre again; see CAMERA_FOCUS_Z"]

	for room_id: String in HouseLayout.room_ids():
		var framing: Dictionary = HouseLayout.camera_framing(room_id)
		var centred: Dictionary = framing.duplicate(true)
		var focus: Vector3 = framing["focus"]
		centred["focus"] = Vector3(focus.x, focus.y, focus.z - HouseLayout.CAMERA_FOCUS_Z)

		for aspect: float in ASPECTS:
			var biased: float = float(Framing.solve(framing, aspect, insets)["distance"])
			var middle: float = float(Framing.solve(centred, aspect, insets)["distance"])
			if biased > middle + 0.001:
				failures.append(("%s at %.2f:1 is framed from %.2f m with the forward look-at "
						+ "point and %.2f m from the room's centre; the bias is costing scale "
						+ "rather than buying it")
						% [room_id, aspect, biased, middle])

		# ...and it must be worth having at the aspect the game is designed for.
		var gain: float = (
			float(Framing.solve(centred, ASPECTS[1], insets)["distance"])
			- float(Framing.solve(framing, ASPECTS[1], insets)["distance"])
		)
		if gain < 0.25:
			failures.append(("%s gains only %.2f m from the forward look-at point. Either the "
					+ "bias has been reduced to nothing or the constraint it trades against has "
					+ "changed; re-derive it rather than leaving a constant nobody can justify.")
					% [room_id, gain])
	return failures


## -- 4. The close-up ----------------------------------------------------------------

## The clamp this replaces was the whole of "characters and interactions look
## small": a beat's box fitted from 2.8 m and the room's 3.5 m floor pushed it
## back out, so the pull-in from a 5.1 m room shot was barely visible.
func _test_a_close_up_may_stand_closer_than_the_room():
	var failures: Array = []
	var insets: Vector4 = Insets.chrome_insets()
	var room_id: String = HouseLayout.KITCHEN
	var framing: Dictionary = HouseLayout.camera_framing(room_id)
	var origin: Vector3 = HouseLayout.room_origin(room_id)

	# The real thing: the counter and a child standing at its interaction point,
	# composed by the module the level director composes with.
	var counter: Dictionary = _prop(room_id, "counter")
	if counter.is_empty():
		return ["the kitchen has no counter to compose on"]
	var station: Vector3 = origin + (counter["position"] as Vector3)
	var child: Vector3 = origin + (counter["stand"] as Vector3)
	var shot: Dictionary = Focus.frame_points(
		[station, child], float((framing["focus"] as Vector3).y), 0.3,
		Focus.MIN_RADIUS, Focus.MAX_RADIUS, HouseLayout.world_floor_bounds(room_id)
	)
	if not bool(shot["valid"]):
		return ["the counter beat composed no shot at all"]

	var close_up: Dictionary = Framing.focus_framing(
		framing, shot["focus"], float(shot["radius"])
	)
	for aspect: float in ASPECTS:
		var room: float = float(Framing.solve(framing, aspect, insets)["distance"])
		var near: float = float(Framing.solve(close_up, aspect, insets)["distance"])
		if near >= room - 0.5:
			failures.append(("at %.2f:1 the counter close-up stands %.2f m out and the whole "
					+ "room shot stands %.2f m out. That is not a close-up; it is the room "
					+ "again, which is the complaint this change exists to answer.")
					% [aspect, near, room])
		# And the child is still inside it, which is the rule that outranks scale.
		if not Focus.contains(shot["focus"], float(shot["radius"]), child):
			failures.append("the counter close-up does not contain the child standing at it")

	# The mechanism, stated: the room's own floor must not be what decides.
	if float(close_up["minDistance"]) >= float(framing["minDistance"]) \
			and float(framing["minDistance"]) > Framing.FOCUS_MIN_DISTANCE:
		failures.append("a close-up is still held out at the room's own minDistance of %.2f m"
				% float(framing["minDistance"]))
	return failures


## -- 5. ...but not into his face ------------------------------------------------------

func _test_but_never_inside_the_child():
	var failures: Array = []
	var insets: Vector4 = Insets.chrome_insets()
	var framing: Dictionary = HouseLayout.camera_framing(HouseLayout.BEDROOM)
	var focus: Vector3 = framing["focus"]

	# The tightest thing anything can ask for.
	var tightest: Dictionary = Framing.focus_framing(framing, focus, 0.01)
	for aspect: float in ASPECTS:
		var distance: float = float(Framing.solve(tightest, aspect, insets)["distance"])
		if distance < Framing.FOCUS_MIN_DISTANCE - 0.001:
			failures.append(("a zero-sized close-up put the camera %.2f m from the child at "
					+ "%.2f:1; the floor is %.2f m")
					% [distance, aspect, Framing.FOCUS_MIN_DISTANCE])
	if Framing.FOCUS_MIN_DISTANCE < 1.2:
		failures.append("the close-up floor is %.2f m, which on a 0.85 m toddler is closer than "
				% Framing.FOCUS_MIN_DISTANCE + "his own height")

	# A room that authors something TIGHTER than the floor keeps its own number:
	# this is a ceiling on the room's standoff, never a new minimum.
	var snug: Dictionary = framing.duplicate(true)
	snug["minDistance"] = 0.8
	if not is_equal_approx(float(Framing.focus_framing(snug, focus, 1.0)["minDistance"]), 0.8):
		failures.append("focus_framing() raised a room's own tighter minDistance; it may only "
				+ "ever lower it")
	return failures


## -- Helpers --------------------------------------------------------------------------

## `{targetId, top}` for everything in the room taller than `TALL`.
func _tall_props(room_id: String):
	var tall: Array = []
	for row: Dictionary in HouseLayout.furniture(room_id) + HouseLayout.storages(room_id):
		var size: Vector3 = row["size"]
		var top: float = (row["position"] as Vector3).y + size.y * 0.5
		if top < TALL:
			continue
		tall.append({
			"targetId": String(row.get("targetId", row.get("storageId", "?"))),
			"top": top,
		})
	return tall


func _prop(room_id: String, target_id: String):
	for row: Dictionary in HouseLayout.furniture(room_id):
		if String(row["targetId"]) == target_id:
			return row
	return {}
