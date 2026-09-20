extends RefCounted

## CARRY BUNNY -- the signature interaction, driven headless from pick-up to
## put-down on the real nodes.
##
## What has to be true, and is asserted rather than hoped:
##
##   1. the five states run in order: in world -> pickingUp -> held -> placing
##      -> back in world, each reported through `state_changed`;
##   2. while held, Bunny's root sits ON Aliz's `carryFront` socket -- a real
##      rig socket, from the profile, resolved on her skeleton -- and moves with
##      her when she walks, facing the way she faces;
##   3. there is exactly one Bunny throughout: same node, same parent, never a
##      second actor with `satisfy()`;
##   4. his stats persist through the whole thing to the number;
##   5. the follower is paused (his `step()` does not move him) and his tap
##      target is disabled while he is in her arms, and both come back;
##   6. put-down lands him on the floor (her y), at least a body's clearance
##      from her, on a point the navigation provider accepts -- never through
##      a wall: with a provider whose walkable area ends in front of her, the
##      spot moves to a side rather than out of the room, and with no walkable
##      spot at all the put-down is refused and he stays in her arms;
##   7. the affordance contract: `get_affordance()` says `carry` when he is
##      free, `place` when he is in THIS actor's arms, `{}` for anybody else,
##      `hug` when he needs comfort, and `perform_affordance()` does each.
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const CharacterScript := preload("res://scripts/character/little_buddy_character.gd")
const BuddyViewScript := preload("res://scripts/characters/buddy/pink_girl_buddy.gd")
const ChildActorScript := preload("res://scripts/care/child_actor.gd")
const CarryScript := preload("res://scripts/interaction/carry_controller.gd")
const NavigationProvider := preload("res://scripts/navigation/navigation_provider.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const Present := preload("res://scripts/care/child_presentation.gd")
const Needs := preload("res://scripts/care/child_needs.gd")

const DT: float = 1.0 / 60.0


## A provider whose walkable floor is a rectangle: the snap clamps to it. This
## is how "inside the room, not through a wall" is asserted without a baked mesh.
class BoxProvider extends NavigationProvider:
	var walkable: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)
	func is_navigation_ready() -> bool:
		return true
	func snap_to_navigable(point: Vector3) -> Vector3:
		return Vector3(
			clampf(point.x, walkable.position.x, walkable.end.x),
			point.y,
			clampf(point.z, walkable.position.y, walkable.end.y))


## A provider with NO standable floor: everything snaps a long way away.
class NowhereProvider extends NavigationProvider:
	func is_navigation_ready() -> bool:
		return true
	func snap_to_navigable(_point: Vector3) -> Vector3:
		return Vector3(50.0, 0.0, 50.0)


func test_name() -> String:
	return "carry_bunny"


func run():
	var failures: Array = []
	failures.append_array(_test_aliz_has_the_sockets())
	failures.append_array(_test_pick_up_hold_put_down())
	failures.append_array(_test_put_down_respects_the_room())
	failures.append_array(_test_affordances())
	return failures


## -- The room, built by hand ---------------------------------------------------------

## `{"room", "aliz", "view", "bunny"}`. Aliz is the real `CharacterBody3D`
## shell with the real rigged view under it; Bunny the real actor, a child of
## the room like the bedroom's. Nothing is in the tree (headless), so every
## position below is read through `SpatialUtil`.
func _stage(provider: RefCounted = null) -> Dictionary:
	var room: Node3D = Node3D.new()
	room.name = "Room"
	var aliz: CharacterBody3D = CharacterScript.new()
	aliz.name = "LittleBuddy"
	aliz.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var view: Node3D = BuddyViewScript.new()
	view.name = "BuddyView"
	aliz.add_child(view)
	view.call("build")
	room.add_child(aliz)
	aliz.position = Vector3(0.0, 0.0, 0.0)
	aliz.call("set_navigation_provider", provider if provider != null else BoxProvider.new())

	var bunny: Node3D = ChildActorScript.new()
	bunny.name = "LittleBuddyChild"
	room.add_child(bunny)
	bunny.position = Vector3(0.0, 0.0, -0.62)
	bunny.call("build")
	return {"room": room, "aliz": aliz, "view": view, "bunny": bunny}


func _teardown(stage: Dictionary) -> void:
	(stage["room"] as Node).free()


func _count_bunnies(root: Node) -> int:
	var count: int = 0
	if root.has_method("satisfy") and root.has_method("set_carried_by"):
		count += 1
	for child: Node in root.get_children():
		count += _count_bunnies(child)
	return count


func _step(aliz: Node, frames: int) -> void:
	for _i: int in range(frames):
		aliz.call("step_movement", DT)


## -- 1. The rig profile resolves on her skeleton -------------------------------------

func _test_aliz_has_the_sockets():
	var failures: Array = []
	var view: Node3D = BuddyViewScript.new()
	view.call("build")
	if not bool(view.call("is_model_available")):
		view.free()
		return failures  # a build without the asset has nothing to resolve
	for socket_name: String in ["carryFront", "itemHoldRight", "itemHoldLeft", "chest", "rightHand"]:
		if not bool(view.call("has_socket", socket_name)):
			failures.append("Aliz's rig profile did not resolve the '%s' socket" % socket_name)
	var carry: Node3D = view.call("get_socket", "carryFront")
	if carry == view:
		failures.append("get_socket('carryFront') fell back to the whole character")
	else:
		# In her frame: in front (-Z), off the floor, roughly centred. Read
		# through the wrapper's own transform chain, out of the tree.
		var local: Vector3 = SpatialUtil.world_transform(view).affine_inverse() \
				* SpatialUtil.world_position(carry)
		if local.z > -0.12 or local.z < -0.40:
			failures.append("carryFront is %.2f m along -Z; a chest carry sits in FRONT of her (0.12..0.40)"
					% -local.z)
		if local.y < 0.20 or local.y > 0.60:
			failures.append("carryFront is %.2f m up; a 0.78 m child held there would have his "
					% local.y + "head in her face or his feet on the floor")
		if absf(local.x) > 0.08:
			failures.append("carryFront is %.2f m off her centre line" % local.x)
	var hand: Node3D = view.call("get_socket", "itemHoldRight")
	if hand != view:
		var local: Vector3 = SpatialUtil.world_transform(view).affine_inverse() \
				* SpatialUtil.world_position(hand)
		if local.y < 0.45 or local.y > 0.85:
			failures.append("itemHoldRight is %.2f m up; her hands hang at about 0.6 m" % local.y)
	if view.call("get_socket", "nothingOfTheSort") != view:
		failures.append("an unknown socket must degrade to the character, never to null")
	if view.call("get_carry_pose") == null:
		failures.append("no carry arm pose was built on the rigged model")
	view.free()
	return failures


## -- 2. Pick up, hold, walk, put down --------------------------------------------

func _test_pick_up_hold_put_down():
	var failures: Array = []
	var stage: Dictionary = _stage()
	var aliz: CharacterBody3D = stage["aliz"]
	var bunny: Node3D = stage["bunny"]
	var room: Node3D = stage["room"]
	var view: Node3D = stage["view"]

	var stats: RefCounted = bunny.call("get_stats")
	stats.call("set_stat", "hunger", 71.0)
	stats.call("set_stat", "happiness", 33.0)
	var bunnies_before: int = _count_bunnies(room)
	var parent_before: Node = bunny.get_parent()
	var target: Node = bunny.call("get_activity_target")

	var states: Array = []
	var controller: Node = aliz.call("get_carry_controller")
	controller.connect("state_changed", func(state: String) -> void: states.append(state))

	if bool(aliz.call("is_carrying_node")):
		failures.append("carrying something before anything was picked up")
	if not bool(aliz.call("carry_node", bunny, "carryFront")):
		failures.append("carry_node() refused Bunny")
		_teardown(stage)
		return failures
	if bool(aliz.call("carry_node", bunny)):
		failures.append("a second carry_node() while the hands are full must be refused")
	if not bool(bunny.call("is_carried")):
		failures.append("Bunny does not know he is being carried")
	if String(bunny.call("get_activity")) != Present.ACTIVITY_CARRIED:
		failures.append("Bunny's activity is '%s' in her arms, not '%s'"
				% [bunny.call("get_activity"), Present.ACTIVITY_CARRIED])
	if String(bunny.call("get_life_clip")) != "carried":
		failures.append("Bunny's body plays '%s' in her arms, not the carried pose"
				% bunny.call("get_life_clip"))
	if target.has_method("is_target_enabled") and bool(target.call("is_target_enabled")):
		failures.append("Bunny's tap target is still enabled while he is in her arms")
	if String(aliz.call("get_carry_state")) != CarryScript.STATE_PICKING_UP:
		failures.append("state after carry_node() is '%s', not pickingUp" % aliz.call("get_carry_state"))
	if not bool(view.call("is_carry_pose_active")):
		failures.append("Aliz's arms were not asked to wrap round him")

	# Lifting: after the pick-up time he is ON the socket.
	_step(aliz, int(CarryScript.PICK_UP_SEC / DT) + 3)
	if String(aliz.call("get_carry_state")) != CarryScript.STATE_HELD:
		failures.append("after %.2f s the state is '%s', not held"
				% [CarryScript.PICK_UP_SEC, aliz.call("get_carry_state")])
	var held: Transform3D = controller.call("held_transform")
	var gap: float = SpatialUtil.world_position(bunny).distance_to(held.origin)
	if gap > 0.01:
		failures.append("held, Bunny is %.3f m from the socket" % gap)
	if not bool(controller.call("is_using_socket")):
		failures.append("the hold point is the fallback offset, not her rig socket")
	# Supported in FRONT of her body, off the floor, not at her feet and not
	# on her head.
	var local: Vector3 = SpatialUtil.world_transform(aliz).affine_inverse() \
			* SpatialUtil.world_position(bunny)
	if local.z > -0.10:
		failures.append("held Bunny is not in front of her (local z %.2f)" % local.z)
	if local.y < 0.15 or local.y > 0.7:
		failures.append("held Bunny's feet are %.2f m up" % local.y)
	if aliz.call("get_state_name") != "carrying":
		failures.append("her movement state is '%s' while holding him, not carrying"
				% aliz.call("get_state_name"))

	# The follower is paused: a follow target does not move him off the socket.
	bunny.call("follow", aliz)
	bunny.call("step", 0.5)
	if SpatialUtil.world_position(bunny).distance_to(held.origin) > 0.01:
		failures.append("the follower moved Bunny while he was being carried")

	# She walks; he goes with her, facing her way.
	var before: Vector3 = SpatialUtil.world_position(bunny)
	for _i: int in range(60):
		aliz.call("drive", 1.0, 0.0)
		aliz.call("step_movement", DT)
	aliz.call("stop_driving")
	_step(aliz, 20)
	var after: Vector3 = SpatialUtil.world_position(bunny)
	if after.distance_to(before) < 0.5:
		failures.append("she walked and he moved only %.2f m; he is not riding with her"
				% after.distance_to(before))
	var yaw_gap: float = absf(wrapf(bunny.rotation.y - aliz.rotation.y, -PI, PI))
	if yaw_gap > 0.05:
		failures.append("held Bunny faces %.0f degrees off her heading" % rad_to_deg(yaw_gap))
	if SpatialUtil.world_position(bunny).distance_to((controller.call("held_transform") as Transform3D).origin) > 0.01:
		failures.append("after the walk Bunny is off the socket")

	# One Bunny, same node, same stats.
	if _count_bunnies(room) != bunnies_before or bunnies_before != 1:
		failures.append("there are %d Bunnies; there must be exactly one" % _count_bunnies(room))
	if bunny.get_parent() != parent_before:
		failures.append("Bunny was re-parented while carried; the director would lose him")
	if not is_equal_approx(float(stats.call("get_stat", "hunger")), 71.0):
		failures.append("hunger changed while carried: %.1f" % float(stats.call("get_stat", "hunger")))

	# Put down: lands on the floor, clear of her, standable; everything restored.
	if not bool(aliz.call("put_down_carried")):
		failures.append("put_down_carried() refused with a whole room to stand in")
	if String(aliz.call("get_carry_state")) != CarryScript.STATE_PLACING:
		failures.append("state after put_down is '%s', not placing" % aliz.call("get_carry_state"))
	_step(aliz, int(CarryScript.PLACE_SEC / DT) + 3)
	if String(aliz.call("get_carry_state")) != CarryScript.STATE_IDLE:
		failures.append("after %.2f s the state is '%s', not idle"
				% [CarryScript.PLACE_SEC, aliz.call("get_carry_state")])
	if bool(bunny.call("is_carried")) or bool(aliz.call("is_carrying_node")):
		failures.append("somebody still thinks he is being carried after the put-down")
	var down: Vector3 = SpatialUtil.world_position(bunny)
	var her: Vector3 = SpatialUtil.world_position(aliz)
	if absf(down.y - her.y) > 0.005:
		failures.append("put down %.3f m above/below her floor" % (down.y - her.y))
	var clearance: float = Vector2(down.x - her.x, down.z - her.z).length()
	if clearance < CarryScript.PUT_DOWN_MIN_CLEARANCE - 0.01:
		failures.append("put down %.2f m from her axis; inside her own collision" % clearance)
	if clearance > CarryScript.PUT_DOWN_DISTANCE + 0.05:
		failures.append("put down %.2f m away; that is a throw, not a set-down" % clearance)
	if target.has_method("is_target_enabled") and not bool(target.call("is_target_enabled")):
		failures.append("Bunny's tap target did not come back after the put-down")
	if String(bunny.call("get_activity")) == Present.ACTIVITY_CARRIED:
		failures.append("Bunny still thinks he is carried after landing")
	if aliz.call("get_state_name") != "idle":
		failures.append("her movement state is '%s' after the put-down, not idle"
				% aliz.call("get_state_name"))
	if bool(view.call("is_carry_pose_active")):
		failures.append("her arms are still wrapped after the put-down")
	if not is_equal_approx(float(stats.call("get_stat", "hunger")), 71.0) \
			or not is_equal_approx(float(stats.call("get_stat", "happiness")), 33.0):
		failures.append("stats did not persist through the carry (hunger %.1f, happiness %.1f)"
				% [float(stats.call("get_stat", "hunger")), float(stats.call("get_stat", "happiness"))])
	if _count_bunnies(room) != 1:
		failures.append("%d Bunnies after the put-down" % _count_bunnies(room))

	var expected: Array = [CarryScript.STATE_PICKING_UP, CarryScript.STATE_HELD,
			CarryScript.STATE_PLACING, CarryScript.STATE_IDLE]
	if states != expected:
		failures.append("states ran %s; expected %s" % [str(states), str(expected)])

	# And he can be picked up again.
	if not bool(aliz.call("carry_node", bunny)):
		failures.append("a second carry after a put-down was refused")
	_teardown(stage)
	return failures


## -- 3. Never through a wall, never inside furniture -----------------------------

func _test_put_down_respects_the_room():
	var failures: Array = []
	# The walkable floor ends 0.3 m in front of her: the spot she would have
	# chosen is outside the room, so the rule must pick a side instead.
	var provider: BoxProvider = BoxProvider.new()
	provider.walkable = Rect2(-2.0, -0.3, 4.0, 2.3)  # z from -0.3 to +2.0; she faces -Z
	var stage: Dictionary = _stage(provider)
	var aliz: CharacterBody3D = stage["aliz"]
	var bunny: Node3D = stage["bunny"]
	aliz.call("carry_node", bunny)
	_step(aliz, 40)
	var spot: Variant = aliz.call("find_put_down_spot")
	if spot == null:
		failures.append("no put-down spot found although the sides are wide open")
	else:
		var at: Vector3 = spot as Vector3
		if at.z < provider.walkable.position.y - 0.001:
			failures.append("the put-down spot %s is outside the walkable floor (through the wall)" % str(at))
		if Vector2(at.x, at.z).length() < CarryScript.PUT_DOWN_MIN_CLEARANCE - 0.01:
			failures.append("the put-down spot %s is inside her own footprint" % str(at))
	if not bool(aliz.call("put_down_carried")):
		failures.append("put_down refused although a side spot exists")
	_step(aliz, 40)
	var landed: Vector3 = SpatialUtil.world_position(bunny)
	if landed.z < provider.walkable.position.y - 0.001:
		failures.append("Bunny landed at %s, beyond the wall" % str(landed))
	_teardown(stage)

	# Nowhere to stand at all: refused, and he stays in her arms.
	stage = _stage(NowhereProvider.new())
	aliz = stage["aliz"]
	bunny = stage["bunny"]
	aliz.call("carry_node", bunny)
	_step(aliz, 40)
	if aliz.call("find_put_down_spot") != null:
		failures.append("a floor with nowhere standable still offered a put-down spot")
	if bool(aliz.call("put_down_carried")):
		failures.append("put_down succeeded with nowhere to put him")
	if not bool(bunny.call("is_carried")):
		failures.append("a refused put-down dropped him anyway")
	# An explicit point is still honoured (the caller vouches for it).
	if not bool(aliz.call("put_down_carried", Vector3(0.6, 0.0, -0.6))):
		failures.append("an explicit put-down point was refused")
	_teardown(stage)
	return failures


## -- 4. The affordance contract ---------------------------------------------------

func _test_affordances():
	var failures: Array = []
	var stage: Dictionary = _stage()
	var aliz: CharacterBody3D = stage["aliz"]
	var bunny: Node3D = stage["bunny"]
	var stranger: Node3D = Node3D.new()
	stage["room"].add_child(stranger)

	if not bunny.is_in_group("affordable"):
		failures.append("Bunny is not in the 'affordable' group; the HUD will never ask him")
	var offer: Dictionary = bunny.call("get_affordance", aliz)
	for key: String in ["verb", "anchor", "radius", "priority", "target"]:
		if not offer.has(key):
			failures.append("the affordance is missing '%s'" % key)
	if String(offer.get("verb", "")) != "carry":
		failures.append("a free Bunny offers '%s', not 'carry'" % offer.get("verb", ""))
	if offer.get("target", null) != bunny:
		failures.append("the affordance's target is not Bunny")
	if float(offer.get("radius", 0.0)) < 0.62:
		failures.append("the reach (%.2f m) does not even cover his own interaction point"
				% float(offer.get("radius", 0.0)))
	var anchor: Vector3 = offer.get("anchor", Vector3.ZERO)
	if anchor.y < SpatialUtil.world_position(bunny).y + 0.7:
		failures.append("the icon anchor is %.2f m up; it would sit on his face" % anchor.y)
	if not bunny.call("get_affordance", null).is_empty():
		failures.append("a null actor got an affordance")

	if not bool(bunny.call("perform_affordance", aliz)):
		failures.append("perform_affordance(carry) returned false")
	if not bool(bunny.call("is_carried")):
		failures.append("perform_affordance(carry) did not pick him up")
	_step(aliz, 40)
	var while_held: Dictionary = bunny.call("get_affordance", aliz)
	if String(while_held.get("verb", "")) != "place":
		failures.append("in her arms Bunny offers '%s', not 'place'" % while_held.get("verb", ""))
	if not bunny.call("get_affordance", stranger).is_empty():
		failures.append("somebody else was offered a verb on a child in Aliz's arms")
	if not bool(bunny.call("perform_affordance", aliz)):
		failures.append("perform_affordance(place) returned false")
	_step(aliz, 40)
	if bool(bunny.call("is_carried")):
		failures.append("perform_affordance(place) did not put him down")

	# Comfort: a crying child offers a hug, and the hug answers it.
	var stats: RefCounted = bunny.call("get_stats")
	stats.call("set_stat", "hunger", 10.0)
	stats.call("set_stat", "thirst", 10.0)
	stats.call("set_stat", "happiness", 5.0)
	bunny.call("set_activity", Present.ACTIVITY_IDLE)
	bunny.call("satisfy", "", 0.0)  # refresh through the public path
	var sad: Dictionary = bunny.call("get_affordance", aliz)
	var need: String = String(bunny.call("get_need"))
	if need == Needs.NEEDS_COMFORT or need == Needs.CRYING:
		if String(sad.get("verb", "")) != "hug":
			failures.append("a child who '%s' offers '%s', not 'hug'" % [need, sad.get("verb", "")])
		var happiness_before: float = float(stats.call("get_stat", "happiness"))
		if not bool(bunny.call("perform_affordance", aliz)):
			failures.append("perform_affordance(hug) returned false")
		if float(stats.call("get_stat", "happiness")) <= happiness_before:
			failures.append("the hug did not cheer him up")
	else:
		failures.append("could not stage a comfort need (dominant need is '%s')" % need)
	_teardown(stage)
	return failures
