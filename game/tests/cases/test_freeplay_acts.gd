extends RefCounted

## FREE PLAY ACTS -- the decision on dictionaries, then every act on the REAL
## house with its state read before and after.
##
## Part 1 (`_test_decisions`) asks `house_freeplay_acts.gd` what happens at
## each thing, alone, with Bunny in her arms, and with a prop in her hand.
## Part 2 drives `house_freeplay_director.gd` through `interaction_ready` on
## `house_world.tscn` and asserts the world changed:
##
##   wardrobe   doors swing open, then shut          (`room.is_open`)
##   toy box    lid opens; a carried teddy goes IN   (storage model + node)
##   shelf      the living room's shelf takes a toy  (when the room is open)
##   fridge     opens; a second arrival takes food   (kitchen state)
##   counter    a combining item cooks -> the MIX close-up opens from Free Play
##   sofa       Aliz sits (held `sit`, seated pose, on the seat)
##   bed        Bunny carried there lies down (`bedtime`, on the mattress)
##   table      Bunny carried there sits at his spot
##   sink       alone: hands up for a second; with Bunny: the WASH close-up
##   bath       alone: bubbles; with Bunny: he is in the tub and the close-up opens
##   Bunny      FEED with a feedable item in hand satisfies his hunger
##   every door  opens in V1 (Little Days is free); the gate SEAM still
##              refuses, says a kind word and moves nobody when it is switched on
##
## `run()` and every `_test_*` helper are untyped on purpose (runner contract).

const Acts := preload("res://scripts/gameplay/house_freeplay_acts.gd")
const Words := preload("res://scripts/gameplay/house_freeplay_words.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const MODE_FREE_PLAY: int = 1
const DT: float = 1.0 / 60.0


class FakeTts extends RefCounted:
	var lines: Array = []
	func speak(text: String, _interrupt: bool = true) -> void:
		lines.append(text)


class FakeSave extends RefCounted:
	var settings: Dictionary = {}
	func get_stars() -> int:
		return 0
	func get_setting(key: String, fallback: Variant = null) -> Variant:
		return settings.get(key, fallback)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value


## An entitlement double: says yes to whatever it is told to.
class FakeEntitlements extends RefCounted:
	var active: Array = []
	func is_active(id: String) -> bool:
		return active.has(id)


func test_name() -> String:
	return "freeplay_acts"


func run():
	var failures: Array = []
	failures.append_array(_test_decisions())
	failures.append_array(_test_acts_on_the_real_house())
	return failures


# ---------------------------------------------------------------------------
# Part 1: decisions
# ---------------------------------------------------------------------------

func _test_decisions():
	var failures: Array = []
	var f: Callable = func(local_id: String, extra: Dictionary = {}) -> String:
		var situation: Dictionary = {"localId": local_id, "actions": _actions_of(local_id)}
		situation.merge(extra, true)
		return String(Acts.decide(situation).get("act", ""))

	# Alone.
	if f.call("wardrobe", {"openable": true}) != Acts.ACT_TOGGLE_OPEN:
		failures.append("acts: alone at the wardrobe should toggle its doors")
	if f.call("toyBox", {"openable": true}) != Acts.ACT_TOGGLE_OPEN:
		failures.append("acts: alone at the toy box should toggle its lid")
	if f.call("sofa") != Acts.ACT_SIT:
		failures.append("acts: alone at the sofa should sit")
	if f.call("bed") != Acts.ACT_SIT:
		failures.append("acts: alone at the bed should sit on it")
	if f.call("sink") != Acts.ACT_WASH_HANDS:
		failures.append("acts: alone at the sink should wash hands")
	if f.call("bath") != Acts.ACT_BUBBLES:
		failures.append("acts: alone at the bath should make bubbles")
	if f.call("table", {"station": {"role": "serve", "open": false, "on": "", "inside": []}}) != Acts.ACT_NONE:
		failures.append("acts: alone at an empty table should do nothing (no chair for her)")

	# With Bunny in her arms: the act is his.
	if f.call("bed", {"carrying": "child"}) != Acts.ACT_PLACE_CHILD:
		failures.append("acts: carrying Bunny to the bed should lay him down")
	var bed_decision: Dictionary = Acts.decide({"localId": "bed", "actions": _actions_of("bed"), "carrying": "child"})
	if String(bed_decision.get("activity", "")) != "bedtime":
		failures.append("acts: Bunny on the bed should be put to `bedtime`, got '%s'" % bed_decision.get("activity"))
	if f.call("sofa", {"carrying": "child"}) != Acts.ACT_PLACE_CHILD:
		failures.append("acts: carrying Bunny to the sofa should seat him")
	if f.call("table", {"carrying": "child", "station": {"role": "serve"}}) != Acts.ACT_PLACE_CHILD:
		failures.append("acts: carrying Bunny to the table should seat him at his spot")
	if f.call("sink", {"carrying": "child"}) != Acts.ACT_CARE_CHILD:
		failures.append("acts: carrying Bunny to the sink should open the wash close-up")
	var sink_decision: Dictionary = Acts.decide({"localId": "sink", "actions": _actions_of("sink"), "carrying": "child"})
	if String(sink_decision.get("careKind", "")) != "washFace":
		failures.append("acts: the sink's care act should be washFace, got '%s'" % sink_decision.get("careKind"))
	if f.call("bath", {"carrying": "child"}) != Acts.ACT_CARE_CHILD:
		failures.append("acts: carrying Bunny to the bath should open a close-up")
	if f.call("wardrobe", {"carrying": "child", "openable": true}) != Acts.ACT_TOGGLE_OPEN:
		failures.append("acts: the wardrobe still opens with Bunny in her arms")

	# With a prop in her hand.
	if f.call("toyBox", {"carrying": "item", "openable": true, "isOpen": false}) != Acts.ACT_TOGGLE_OPEN:
		failures.append("acts: a toy at a shut toy box opens the box first")
	if f.call("toyBox", {"carrying": "item", "openable": true, "isOpen": true, "canStore": true}) != Acts.ACT_STORE_ITEM:
		failures.append("acts: a toy at an open toy box goes in")
	if f.call("toyBox", {"carrying": "item", "openable": true, "isOpen": true, "canStore": false}) != Acts.ACT_NONE:
		failures.append("acts: a thing the box refuses must not be forced in")
	if f.call("table", {"carrying": "item", "station": {"role": "serve"}}) != Acts.ACT_PLACE_ON_TABLE:
		failures.append("acts: a prop at the table goes on the table")

	# The kitchen.
	var shut_fridge: Dictionary = {"station": {"role": "store", "opens": true, "open": false, "on": "", "inside": ["banana", "apple"]}}
	if f.call("fridge", shut_fridge) != Acts.ACT_KITCHEN_OPEN:
		failures.append("acts: a shut fridge opens")
	var open_fridge: Dictionary = {"station": {"role": "store", "opens": true, "open": true, "on": "", "inside": ["banana", "apple"]}}
	var take: Dictionary = Acts.decide({"localId": "fridge", "actions": [], "station": open_fridge["station"]})
	if String(take.get("act", "")) != Acts.ACT_KITCHEN_TAKE or String(take.get("item", "")) != "banana":
		failures.append("acts: an open fridge with food hands over the first thing (got %s)" % str(take))
	var empty_open: Dictionary = {"station": {"role": "store", "opens": true, "open": true, "on": "", "inside": []}}
	if f.call("fridge", empty_open) != Acts.ACT_KITCHEN_CLOSE:
		failures.append("acts: an empty open fridge shuts again")
	var cook: Dictionary = {"kitchenHeld": "bowl", "canPlaceHere": true, "combines": true,
			"station": {"role": "prepare", "opens": false, "open": false, "on": "bottle", "inside": []}}
	var cooked: Dictionary = Acts.decide({"localId": "counter", "actions": [], "kitchenHeld": "bowl",
			"canPlaceHere": true, "combines": true, "station": cook["station"]})
	if String(cooked.get("act", "")) != Acts.ACT_KITCHEN_PLACE or not bool(cooked.get("combines", false)):
		failures.append("acts: a combining item at the counter should cook (got %s)" % str(cooked))
	if f.call("littleBuddy", {"isCharacter": true, "kitchenHeld": "bottleOfMilk", "canFeed": true}) != Acts.ACT_FEED_CHILD:
		failures.append("acts: a bottle of milk at Bunny feeds him")
	if f.call("littleBuddy", {"isCharacter": true, "kitchenHeld": "spoon", "canFeed": false}) != Acts.ACT_NONE:
		failures.append("acts: a spoon at Bunny is not a meal")
	# Owner bug: arriving at Bunny with truly empty hands used to be a dead end.
	if f.call("littleBuddy", {"isCharacter": true}) != Acts.ACT_CARRY_CHILD:
		failures.append("acts: empty hands at Bunny should offer to carry him")
	if f.call("littleBuddy", {"isCharacter": true, "kitchenHeld": "spoon"}) != Acts.ACT_NONE:
		failures.append("acts: a spoon in hand at Bunny should not also offer to carry him")
	if f.call("littleBuddy", {"isCharacter": true, "carrying": "item"}) != Acts.ACT_NONE:
		failures.append("acts: a prop already in her arms should not also offer to carry Bunny")

	# Every id that has no pantomime action decides a real act somewhere.
	for local_id: String in Words.HANDLED_BY_ACTS:
		var any: bool = false
		for situation: Dictionary in [
			{"openable": true}, {}, {"carrying": "child"},
			{"station": {"role": "store", "opens": true, "open": false, "on": "", "inside": ["x"]}},
		]:
			if f.call(local_id, situation) != Acts.ACT_NONE:
				any = true
		if not any:
			failures.append("acts: '%s' is listed as handled but never decides an act" % local_id)
	return failures


func _actions_of(local_id: String) -> Array:
	for room_id: String in HouseLayout.room_ids():
		for prop: Dictionary in HouseLayout.furniture(room_id):
			if String(prop["targetId"]) == local_id:
				return prop["actions"]
		for row: Dictionary in HouseLayout.storages(room_id):
			if String(row["storageId"]) == local_id:
				return ["open", "putAway"]
	return []


# ---------------------------------------------------------------------------
# Part 2: the real house
# ---------------------------------------------------------------------------

func _test_acts_on_the_real_house():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var director: Node = world.call("ensure_free_play_director")
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	var tts: FakeTts = FakeTts.new()
	director.call("set_tts", tts)
	director.call("set_save_service", FakeSave.new())
	var entitlements: FakeEntitlements = FakeEntitlements.new()
	director.call("set_entitlement_service", entitlements)
	director.call("start")
	var aliz: Node3D = world.call("get_character")
	var bunny: Node = world.get_node_or_null("Rooms/Bedroom/LittleBuddyChild")

	failures.append_array(_wardrobe(world, director, aliz))
	failures.append_array(_toy_box(world, director, aliz))
	failures.append_array(_bed_and_bunny(world, director, aliz, bunny))
	failures.append_array(_every_room_opens(world, director, aliz, tts))
	failures.append_array(_gate_seam_when_switched_on(world, director, aliz, tts))
	failures.append_array(_kitchen(world, director, aliz, bunny))
	# Open the house for the rooms behind the gate.
	entitlements.active = ["familyClub"]
	failures.append_array(_sofa(world, director, aliz, bunny))
	failures.append_array(_shelf(world, director, aliz))
	failures.append_array(_bathroom(world, director, aliz, bunny))

	_release(world)
	return failures


func _wardrobe(world, director, aliz):
	var failures: Array = []
	world.call("place_in_room", "bedroom", "")
	var room: Node = world.call("get_current_room")
	if not bool(room.call("is_openable", "wardrobe")):
		return ["wardrobe: the bedroom does not know its wardrobe opens"]
	_arrive(aliz, "bedroom.wardrobe")
	if not bool(room.call("is_open", "wardrobe")):
		failures.append("wardrobe: arriving did not open the doors")
	var hinge: Node3D = room.get_node_or_null("Geometry/WardrobeDoor_L")
	if hinge == null:
		hinge = _find_named(room, "WardrobeDoor_L")
	if hinge == null:
		failures.append("wardrobe: no hinged door node was built")
	elif absf(hinge.rotation_degrees.y) < 60.0:
		failures.append("wardrobe: the left door only swung %.0f degrees" % hinge.rotation_degrees.y)
	_arrive(aliz, "bedroom.wardrobe")
	if bool(room.call("is_open", "wardrobe")):
		failures.append("wardrobe: a second arrival did not shut the doors")
	if hinge != null and absf(hinge.rotation_degrees.y) > 1.0:
		failures.append("wardrobe: the door did not swing back")
	return failures


func _toy_box(world, director, aliz):
	var failures: Array = []
	world.call("place_in_room", "bedroom", "")
	var room: Node = world.call("get_current_room")
	room.call("set_open", "toyBox", false)
	_arrive(aliz, "bedroom.toyBox")
	if not bool(room.call("is_storage_open", "toyBox")):
		failures.append("toy box: arriving alone did not open the lid")
	# Pick the teddy up, walk it to the open box: in it goes.
	var teddy: Node = _draggable(director, "teddy")
	if teddy == null:
		return failures + ["toy box: no teddy was staged in the bedroom"]
	if not bool(aliz.call("carry_node", teddy, "itemHoldRight")):
		return failures + ["toy box: could not pick the teddy up"]
	_step(aliz, 40)
	var model: RefCounted = room.call("get_storage", "toyBox")
	_arrive(aliz, "bedroom.toyBox")
	_step(aliz, 40)
	if not bool(model.call("contains", "teddy")):
		failures.append("toy box: the model does not list the teddy after it was put in (%s)" % str(model.call("describe")))
	if bool(aliz.call("is_carrying_node")):
		failures.append("toy box: the teddy is still in her hand")
	var rest: Vector3 = room.call("storage_rest_position", "toyBox", 0)
	var where: Vector3 = SpatialUtil.world_position(teddy)
	if where.distance_to(rest) > 0.3:
		failures.append("toy box: the teddy landed %.2f m from the inside of the box (%s vs %s)" % [where.distance_to(rest), where, rest])
	# Taking it out again clears the model.
	if not bool(aliz.call("carry_node", teddy, "itemHoldRight")):
		failures.append("toy box: the teddy cannot be taken back out")
	_step(aliz, 40)
	if bool(model.call("contains", "teddy")):
		failures.append("toy box: the model still lists a teddy that is in her hand")
	if not bool(aliz.call("put_down_carried")):
		failures.append("toy box: could not put the teddy back on the floor")
	_step(aliz, 40)
	return failures


func _bed_and_bunny(world, director, aliz, bunny):
	var failures: Array = []
	if bunny == null:
		return ["bed: no Bunny"]
	world.call("place_in_room", "bedroom", "")
	# Alone: she sits on the bed.
	_arrive(aliz, "bedroom.bed")
	_step(aliz, 90)
	if not bool(director.call("is_seated")):
		failures.append("bed: arriving alone did not sit her down")
	if String(aliz.call("get_held_action")) != "sit":
		failures.append("bed: the movement machine does not hold `sit` (held '%s')" % aliz.call("get_held_action"))
	# A walk stands her up again.
	var p: Vector3 = SpatialUtil.world_position(world.call("get_current_room")) + Vector3(0.6, 0.0, 1.0)
	aliz.call("move_to_ground", p.x, p.z)
	if bool(director.call("is_seated")):
		failures.append("bed: a tap did not stand her up")
	_step(aliz, 300)

	# Carrying Bunny: he lies down on the mattress.
	SpatialUtil.set_world_position(aliz, SpatialUtil.world_position(bunny) + Vector3(0.0, 0.0, 0.62))
	if not bool(bunny.call("perform_affordance", aliz)):
		return failures + ["bed: could not pick Bunny up"]
	_step(aliz, 40)
	_arrive(aliz, "bedroom.bed")
	_step(aliz, 40)
	if bool(aliz.call("is_carrying_node")):
		failures.append("bed: Bunny is still in her arms")
	if String(bunny.call("get_activity")) != "bedtime":
		failures.append("bed: Bunny's activity is '%s', not bedtime" % bunny.call("get_activity"))
	var lie: Vector3 = SpatialUtil.world_transform(world.call("get_current_room")) \
			* (HouseLayout.child_surface("bedroom", "bed")["position"] as Vector3)
	var at: Vector3 = SpatialUtil.world_position(bunny)
	if at.distance_to(lie) > 0.05:
		failures.append("bed: Bunny landed at %s, not on the mattress at %s" % [at, lie])
	if at.y < 0.3:
		failures.append("bed: Bunny is on the floor (y %.2f), not on the bed" % at.y)
	# And he can be picked up again from the bed.
	SpatialUtil.set_world_position(aliz, lie + Vector3(0.62, -lie.y, 0.0))
	if not bool(bunny.call("perform_affordance", aliz)):
		failures.append("bed: Bunny cannot be picked up off the bed")
	_step(aliz, 40)
	# Refused landing: an unknown surface shakes and keeps him.
	if bool(director.call("_place_child_on", "wardrobe", "")):
		failures.append("bed: the wardrobe accepted Bunny as a surface")
	if not bool(aliz.call("is_carrying_node")):
		failures.append("bed: a refused landing dropped Bunny")
	var carry: Node = aliz.call("get_carry_controller")
	if not bool(carry.call("is_shaking")):
		failures.append("bed: a refused landing did not shake")
	_step(aliz, 40)
	# Put him back on the floor for the next cases.
	aliz.call("put_down_carried")
	_step(aliz, 40)

	# Owner bug regression: arriving at Bunny with empty hands used to be a dead
	# end in Free Play (`house_freeplay_acts.gd` answered `ACT_NONE`) -- the one
	# character in the house, and tapping him did nothing.
	if bool(aliz.call("is_carrying_node")):
		failures.append("precondition: her hands should be empty before the carry-on-arrival case")
	var bunny_parent_before: Node = bunny.get_parent()
	_arrive(aliz, "bedroom.littleBuddy")
	if not bool(bunny.call("is_carried")) or not bool(aliz.call("is_carrying_node")):
		failures.append("bed: arriving at Bunny with empty hands did not carry him")
	if bunny.get_parent() != bunny_parent_before:
		failures.append("bed: arriving at Bunny re-parented him instead of carrying the same node")
	# Let the lift finish (put-down is refused mid-lift, by design) before
	# putting him back down for the rooms that follow.
	_step(aliz, 40)
	aliz.call("put_down_carried")
	_step(aliz, 40)
	if bool(aliz.call("is_carrying_node")):
		failures.append("bed: could not put Bunny back down after the carry-on-arrival case")
	return failures


## Little Days V1 is FREE (owner decision, 2026-09-20): with no entitlement at
## all, every room opens, every door says ENTER, and walking through one simply
## changes the room. Nothing a child can reach says "ask a grown-up".
func _every_room_opens(world, director, aliz, tts):
	var failures: Array = []
	if not bool(director.get("ROOMS_FREE_IN_V1")):
		failures.append("free: ROOMS_FREE_IN_V1 is off; V1 ships with every room open")
	for room_id: Variant in world.call("get_room_ids"):
		if not bool(director.call("is_room_open", String(room_id))):
			failures.append("free: '%s' is not open on a free-starter profile" % room_id)
	world.call("place_in_room", "bedroom", "")
	var layer: Control = world.call("get_affordance_layer")
	var door: Node = world.call("get_target_by_semantic_id", "bedroom.doorToBathroom")
	if layer != null and door != null:
		# The first live frame hands every target the layer's context provider
		# through the `affordable` group; nothing added to the root is "inside
		# the tree" in the headless runner, so the door is handed it here.
		door.call("set_affordance_context_provider", Callable(layer, "context_for"))
		var offer: Dictionary = door.call("get_affordance", aliz)
		if String(offer.get("verb", "")) != "ENTER":
			failures.append("free: the bathroom door offers '%s', not ENTER" % offer.get("verb"))
	tts.lines.clear()
	_arrive(aliz, "bedroom.doorToBathroom")
	if String(world.call("get_current_room_id")) != "bathroom":
		failures.append("free: the bathroom door did not open (still in %s)" % world.call("get_current_room_id"))
	for line: Variant in tts.lines:
		if String(line).find("grown-up") >= 0 or String(line).find("Soon") >= 0:
			failures.append("free: an open door said '%s'" % line)
	if String(aliz.call("get_state_name")) == "disabled":
		failures.append("free: the child is left disabled after a door")
	return failures


## The gate seam is kept whole for a later product, so it is driven here with
## the constant switched OFF: the bathroom is refused without the family
## entitlement, the door says SOON kindly, arriving says so and nobody moves.
func _gate_seam_when_switched_on(world, director, aliz, tts):
	var failures: Array = []
	director.call("set_rooms_free_for_test", false)
	world.call("place_in_room", "bedroom", "")
	if bool(director.call("is_room_open", "bathroom")):
		failures.append("gate: the bathroom is open with no family entitlement")
	if not bool(director.call("is_room_open", "kitchen")) or not bool(director.call("is_room_open", "bedroom")):
		failures.append("gate: the kitchen and the bedroom must always be open")
	var layer: Control = world.call("get_affordance_layer")
	var door: Node = world.call("get_target_by_semantic_id", "bedroom.doorToBathroom")
	if layer != null and door != null:
		door.call("set_affordance_context_provider", Callable(layer, "context_for"))
		world.call("get_target_by_semantic_id", "bedroom.doorToKitchen").call(
				"set_affordance_context_provider", Callable(layer, "context_for"))
		var offer: Dictionary = door.call("get_affordance", aliz)
		if String(offer.get("verb", "")) != "SOON":
			failures.append("gate: the bathroom door offers '%s', not SOON" % offer.get("verb"))
		var kitchen_door: Node = world.call("get_target_by_semantic_id", "bedroom.doorToKitchen")
		var open_offer: Dictionary = kitchen_door.call("get_affordance", aliz)
		if String(open_offer.get("verb", "")) != "ENTER":
			failures.append("gate: the kitchen door offers '%s', not ENTER" % open_offer.get("verb"))
	tts.lines.clear()
	_arrive(aliz, "bedroom.doorToBathroom")
	if String(world.call("get_current_room_id")) != "bedroom":
		failures.append("gate: a locked door moved the child (now in %s)" % world.call("get_current_room_id"))
	if tts.lines.is_empty() or String(tts.lines[-1]).find("grown-up") < 0:
		failures.append("gate: the locked door did not say 'Soon! Ask a grown-up' (%s)" % str(tts.lines))
	if String(aliz.call("get_state_name")) == "disabled":
		failures.append("gate: the child is left disabled at a locked door")
	director.call("set_rooms_free_for_test", null)
	if not bool(director.call("is_room_open", "bathroom")):
		failures.append("gate: putting the constant back in charge did not reopen the bathroom")
	return failures


func _kitchen(world, director, aliz, bunny):
	var failures: Array = []
	world.call("place_in_room", "kitchen", "")
	var kitchen: RefCounted = world.call("get_kitchen_state")
	if kitchen == null:
		return ["kitchen: no kitchen state"]
	kitchen.call("reset")
	_arrive(aliz, "kitchen.fridge")
	if not bool(kitchen.call("is_open", "fridge")):
		failures.append("kitchen: arriving at the shut fridge did not open it")
	_arrive(aliz, "kitchen.fridge")
	var held: String = String(kitchen.call("held"))
	if held.is_empty() or held == "none":
		failures.append("kitchen: a second arrival at the open fridge took nothing")
	# Put it down on the counter, take the bowl, bring the bowl back: cook.
	_arrive(aliz, "kitchen.counter")
	if String(kitchen.call("on_station", "counter")) != held:
		failures.append("kitchen: the %s was not put down on the counter (on: %s)" % [held, kitchen.call("on_station", "counter")])
	_arrive(aliz, "kitchen.counter")
	var second: String = String(kitchen.call("held"))
	if second.is_empty() or second == "none":
		failures.append("kitchen: arriving at the counter with empty hands took nothing from it")
	_arrive(aliz, "kitchen.counter")
	var made: String = String(kitchen.call("on_station", "counter"))
	if held == "banana" and second == "bowl" and made != "fruitBowl":
		failures.append("kitchen: banana + bowl did not cook (on the counter: %s)" % made)
	# A milk bottle: the MIX close-up opens from Free Play.
	kitchen.call("reset")
	kitchen.call("set_open", "fridge", true)
	kitchen.call("take", "fridge", "bottle")
	_arrive(aliz, "kitchen.counter")
	kitchen.call("take", "counter", "bowl")
	_arrive(aliz, "kitchen.counter")
	if String(kitchen.call("on_station", "counter")) != "bottleOfMilk":
		failures.append("kitchen: bottle + bowl did not make bottleOfMilk (on: %s)" % kitchen.call("on_station", "counter"))
	if not bool(director.call("is_care_open")):
		failures.append("kitchen: preparing the milk did not open the MIX close-up")
	else:
		var care: Control = director.call("get_care_overlay")
		if String(care.call("get_care_kind")) != "prepareMilk":
			failures.append("kitchen: the close-up opened for '%s', not prepareMilk" % care.call("get_care_kind"))
		if String(aliz.call("get_state_name")) != "disabled":
			failures.append("kitchen: the room's input is not held while the close-up is up")
		care.call("complete_by_touch")
		if bool(director.call("is_care_open")):
			failures.append("kitchen: the close-up stayed open after completing")
		if String(aliz.call("get_state_name")) == "disabled":
			failures.append("kitchen: input was not given back after the close-up")
	# Take the milk to Bunny: FEED.
	_arrive(aliz, "kitchen.counter")
	if String(kitchen.call("held")) != "bottleOfMilk":
		failures.append("kitchen: could not take the bottle of milk off the counter (held %s)" % kitchen.call("held"))
	if bunny != null:
		var stats: RefCounted = bunny.call("get_stats")
		stats.call("adjust", "hunger", 80.0)
		var before: float = float((stats.call("describe") as Dictionary).get("hunger", 0.0))
		bunny.call("room_changed", world.call("get_current_room"), aliz)
		_arrive(aliz, "kitchen.littleBuddy")
		var after: float = float((stats.call("describe") as Dictionary).get("hunger", 0.0))
		if after >= before:
			failures.append("kitchen: FEED at Bunny did not lower his hunger (%.0f -> %.0f)" % [before, after])
		if String(kitchen.call("held")) not in ["", "none"]:
			failures.append("kitchen: the bottle is still in her hand after feeding")
		bunny.call("room_changed", world.call("get_room", "bedroom"), aliz)
	return failures


func _sofa(world, director, aliz, bunny):
	var failures: Array = []
	world.call("place_in_room", "livingRoom", "")
	_arrive(aliz, "livingRoom.sofa")
	_step(aliz, 90)
	if not bool(director.call("is_seated")):
		failures.append("sofa: Aliz did not sit")
	var seat: Dictionary = HouseLayout.caregiver_seat("livingRoom", "sofa")
	var spot: Vector3 = SpatialUtil.world_transform(world.call("get_current_room")) * (seat["position"] as Vector3)
	var at: Vector3 = SpatialUtil.world_position(aliz)
	if Vector2(at.x - spot.x, at.z - spot.z).length() > 0.05:
		failures.append("sofa: she sits at %s, not on the seat at %s" % [at, spot])
	var pose: Node = _find_named(aliz, "HeldPose")
	if pose == null:
		failures.append("sofa: no held-pose modifier was mounted on her skeleton")
	elif String(pose.call("get_pose")) != "sit":
		failures.append("sofa: the pose modifier holds '%s', not sit" % pose.call("get_pose"))
	director.call("_stand_up")
	if bunny == null:
		return failures
	# Bunny on the sofa: he sits.
	bunny.call("room_changed", world.call("get_current_room"), aliz)
	SpatialUtil.set_world_position(aliz, SpatialUtil.world_position(bunny) + Vector3(0.0, 0.0, 0.62))
	if not bool(bunny.call("perform_affordance", aliz)):
		return failures + ["sofa: could not pick Bunny up"]
	_step(aliz, 40)
	_arrive(aliz, "livingRoom.sofa")
	_step(aliz, 40)
	var surface: Dictionary = HouseLayout.child_surface("livingRoom", "sofa")
	var want: Vector3 = SpatialUtil.world_transform(world.call("get_current_room")) * (surface["position"] as Vector3)
	if SpatialUtil.world_position(bunny).distance_to(want) > 0.05:
		failures.append("sofa: Bunny landed at %s, not on the cushion at %s" % [SpatialUtil.world_position(bunny), want])
	if String(bunny.call("get_activity")) != "carried":
		failures.append("sofa: Bunny's seated posture is '%s'" % bunny.call("get_activity"))
	return failures


func _shelf(world, director, aliz):
	var failures: Array = []
	world.call("place_in_room", "livingRoom", "")
	var room: Node = world.call("get_current_room")
	var ball: Node = _draggable(director, "ball")
	if ball == null:
		return ["shelf: no ball was staged in the living room"]
	if not bool(aliz.call("carry_node", ball, "itemHoldRight")):
		return ["shelf: could not pick the ball up"]
	_step(aliz, 40)
	room.call("set_open", "toyShelf", false)
	_arrive(aliz, "livingRoom.toyShelf")
	if not bool(room.call("is_storage_open", "toyShelf")):
		failures.append("shelf: the shut shelf did not open first")
	if not bool(aliz.call("is_carrying_node")):
		failures.append("shelf: the ball left her hand while the shelf was shut")
	_arrive(aliz, "livingRoom.toyShelf")
	_step(aliz, 40)
	var model: RefCounted = room.call("get_storage", "toyShelf")
	if not bool(model.call("contains", "ball")):
		failures.append("shelf: the ball was not stored (%s)" % str(model.call("describe")))
	if bool(aliz.call("is_carrying_node")):
		failures.append("shelf: the ball is still in her hand")
	return failures


func _bathroom(world, director, aliz, bunny):
	var failures: Array = []
	world.call("place_in_room", "bathroom", "")
	# Alone at the sink: hands up.
	_arrive(aliz, "bathroom.sink")
	if not bool(director.call("is_washing_hands")):
		failures.append("sink: arriving alone did not start the hand wash")
	var pose: Node = _find_named(aliz, "HeldPose")
	if pose != null and String(pose.call("get_pose")) != "handsUp":
		failures.append("sink: the pose is '%s', not handsUp" % pose.call("get_pose"))
	if int(director.call("get_sparkle_count")) < 1:
		failures.append("sink: no splash")
	for _i: int in range(80):
		aliz.call("step_movement", DT)
		director.call("step", DT)
	if bool(director.call("is_washing_hands")):
		failures.append("sink: the hands stayed up past a second")
	# Alone at the bath: bubbles.
	_arrive(aliz, "bathroom.bath")
	if int(director.call("get_sparkle_count")) < 1:
		failures.append("bath: no bubbles")
	if bunny == null:
		return failures
	# Bunny to the sink: the close-up, on him.
	bunny.call("room_changed", world.call("get_current_room"), aliz)
	SpatialUtil.set_world_position(aliz, SpatialUtil.world_position(bunny) + Vector3(0.0, 0.0, 0.62))
	if not bool(bunny.call("perform_affordance", aliz)):
		return failures + ["sink: could not pick Bunny up"]
	_step(aliz, 40)
	var stats: RefCounted = bunny.call("get_stats")
	stats.call("adjust", "cleanliness", -60.0)
	var before: float = float((stats.call("describe") as Dictionary).get("cleanliness", 0.0))
	_arrive(aliz, "bathroom.sink")
	if not bool(director.call("is_care_open")):
		failures.append("sink: the wash close-up did not open with Bunny in her arms")
	else:
		var care: Control = director.call("get_care_overlay")
		if String(care.call("get_care_kind")) != "washFace":
			failures.append("sink: the close-up is '%s', not washFace" % care.call("get_care_kind"))
		if care.get_parent() == null or care.get_parent().name != "UI":
			failures.append("sink: the close-up is not under the world's UI layer")
		care.call("complete_by_touch")
		var after: float = float((stats.call("describe") as Dictionary).get("cleanliness", 0.0))
		if after <= before:
			failures.append("sink: washing did not raise cleanliness (%.0f -> %.0f)" % [before, after])
		if bool(director.call("is_care_open")):
			failures.append("sink: the close-up did not close")
	if not bool(aliz.call("is_carrying_node")):
		failures.append("sink: Bunny left her arms during the wash")
	# The bath: he goes in the tub, then the close-up.
	_arrive(aliz, "bathroom.bath")
	_step(aliz, 40)
	if not bool(director.call("is_care_open")):
		failures.append("bath: no close-up opened for Bunny")
	else:
		director.call("get_care_overlay").call("complete_by_touch")
	if bool(aliz.call("is_carrying_node")):
		failures.append("bath: Bunny is still in her arms; he should be in the tub")
	var tub: Vector3 = SpatialUtil.world_transform(world.call("get_current_room")) \
			* (HouseLayout.child_surface("bathroom", "bath")["position"] as Vector3)
	if SpatialUtil.world_position(bunny).distance_to(tub) > 0.05:
		failures.append("bath: Bunny is at %s, not in the tub at %s" % [SpatialUtil.world_position(bunny), tub])
	if String(bunny.call("get_activity")) != "bath":
		failures.append("bath: Bunny's activity is '%s', not bath" % bunny.call("get_activity"))
	# The close-up's own safety: it completes itself if the gesture never comes.
	SpatialUtil.set_world_position(aliz, tub + Vector3(0.0, -tub.y, 0.7))
	bunny.call("perform_affordance", aliz)
	_step(aliz, 40)
	_arrive(aliz, "bathroom.sink")
	if bool(director.call("is_care_open")):
		for _i: int in range(int(15.0 / DT)):
			director.call("step", DT)
		if bool(director.call("is_care_open")):
			failures.append("sink: the close-up never completed itself; a child who cannot drag is stuck")
	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Stands Aliz on the target's stand point facing it and fires the arrival, as
## the movement controller would after a walk.
func _arrive(aliz, target_id: String) -> void:
	var world: Node = aliz.get_parent()
	var target: Node = world.call("get_target_by_semantic_id", target_id)
	if target != null and target.has_method("get_stand_position"):
		var here: Vector3 = SpatialUtil.world_position(aliz)
		var stand: Vector3 = target.call("get_stand_position", here)
		SpatialUtil.set_world_position(aliz, stand)
		var face: Vector3 = target.call("get_facing_position", stand)
		var d: Vector3 = face - stand
		if Vector2(d.x, d.z).length() > 0.001:
			aliz.rotation.y = atan2(-d.x, -d.z)
	aliz.emit_signal("interaction_ready", target_id)


func _step(aliz, frames: int) -> void:
	for _i: int in range(frames):
		aliz.call("step_movement", DT)


func _draggable(director, object_id: String) -> Node:
	for node: Variant in director.call("ensure_draggables"):
		if node is Node and String((node as Node).get("object_id")) == object_id:
			return node
	return null


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_named(child, wanted)
		if found != null:
			return found
	return null


func _build_house():
	if not ResourceLoader.exists(HOUSE_SCENE):
		return null
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	world.call("set_progression_mode", MODE_FREE_PLAY)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	world.call("build_world")
	return world


func _release(world) -> void:
	if world == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()
