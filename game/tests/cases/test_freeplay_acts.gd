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
		failures.append("acts: alone at a lidded thing with no storage behind it should toggle its lid")
	if f.call("toyBox", {"openable": true, "hasStorage": true}) != Acts.ACT_TIDY:
		failures.append("acts: alone at the toy box (a storage) should open it and tidy")
	if f.call("wardrobe", {"openable": true, "hasStorage": false}) != Acts.ACT_TOGGLE_OPEN:
		failures.append("acts: the wardrobe has no storage model and just swings its doors")
	if f.call("toyBox", {"carrying": "item", "takesDrops": true}) != Acts.ACT_DROP_IN:
		failures.append("acts: a carried toy at the living room's lidless toy box goes in")
	if f.call("bath", {"carrying": "item", "takesDrops": true}) != Acts.ACT_DROP_IN:
		failures.append("acts: a carried bath toy at the bath goes in")
	if f.call("toyBox", {"carrying": "item"}) != Acts.ACT_NONE:
		failures.append("acts: a carried toy at a box that takes no drops does nothing")
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
	if String(sink_decision.get("careKind", "")) != "brushTeeth":
		failures.append("acts: the sink's care act should be brushTeeth, got '%s'" % sink_decision.get("careKind"))
	if f.call("bath", {"carrying": "child"}) != Acts.ACT_CARE_CHILD:
		failures.append("acts: carrying Bunny to the bath should open a close-up")
	var bath_decision: Dictionary = Acts.decide({"localId": "bath", "actions": _actions_of("bath"), "carrying": "child"})
	if String(bath_decision.get("careKind", "")) != "washFace":
		failures.append("acts: the bath's care act should be washFace, got '%s'" % bath_decision.get("careKind"))
	if Acts.care_follow_up("bath", "washFace") != "dryFace":
		failures.append("acts: the bath's wash should be followed by the towel (dryFace)")
	if not Acts.care_follow_up("sink", "brushTeeth").is_empty() or not Acts.care_follow_up("bath", "dryFace").is_empty():
		failures.append("acts: brushing teeth and drying are each the last act at their basin")
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
	# The dining area with Bunny is the feeding mini-game: his food brought to
	# the table he is sitting at feeds him, rather than being set down beside him.
	var serve: Dictionary = {"role": "serve", "opens": false, "open": false, "on": "", "inside": []}
	var at_table: Dictionary = Acts.decide({"localId": "table", "actions": _actions_of("table"), "station": serve,
			"kitchenHeld": "mashedBanana", "canFeed": true, "canPlaceHere": true, "childAt": "table"})
	if String(at_table.get("act", "")) != Acts.ACT_FEED_CHILD or not bool(at_table.get("atTable", false)):
		failures.append("acts: a meal brought to the table Bunny sits at should feed him (got %s)" % str(at_table))
	if f.call("table", {"station": serve, "kitchenHeld": "mashedBanana", "canFeed": true, "canPlaceHere": true}) != Acts.ACT_KITCHEN_PLACE:
		failures.append("acts: with nobody at the table the meal is set down on it")
	if f.call("table", {"station": serve, "kitchenHeld": "banana", "canFeed": false, "canPlaceHere": false, "childAt": "table"}) == Acts.ACT_FEED_CHILD:
		failures.append("acts: a raw banana at the table is not a meal for Bunny")
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
	failures.append_array(_tidy_loop(world, director, aliz))
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


## The tidy-up: empty hands at the bedroom toy box scatter a few real toys,
## each one put away is praised by name, the last is "All tidy!", and arriving
## again afterwards starts a fresh one. Both ways in are driven: the pad (a
## drag, or the tap fallback, through `chosen`) and the carry.
func _tidy_loop(world, director, aliz):
	var failures: Array = []
	world.call("place_in_room", "bedroom", "")
	var room: Node = world.call("get_current_room")
	var model: RefCounted = room.call("get_storage", "toyBox")
	# `_toy_box()` above already opened the box once (and so started a tidy);
	# start this case from a shut, empty box.
	director.call("_clear_tidy")
	room.call("set_open", "toyBox", false)
	if bool(aliz.call("is_carrying_node")):
		aliz.call("put_down_carried")
		_step(aliz, 40)
	var started_before: int = int(director.call("get_tidy_count"))
	var opened: Dictionary = director.call("_act_at", "bedroom.toyBox")
	if not bool(opened.get("handled", false)):
		return ["tidy: arriving at the toy box with empty hands was not handled"]
	if not bool(room.call("is_storage_open", "toyBox")):
		failures.append("tidy: the lid did not open")
	if not bool(director.call("is_tidy_active")):
		return failures + ["tidy: no tidy started at the toy box"]
	if int(director.call("get_tidy_count")) != started_before + 1:
		failures.append("tidy: the tidy count did not advance")
	var plan: RefCounted = director.call("get_tidy_plan")
	var nodes: Array = director.call("get_tidy_nodes")
	if nodes.size() < 3 or nodes.size() > 4:
		failures.append("tidy: %d toys scattered; wanted 3-4 (box capacity 4)" % nodes.size())
	if nodes.size() != int(plan.call("total")):
		failures.append("tidy: %d toys on the floor but the plan has %d" % [nodes.size(), plan.call("total")])
	var first: Dictionary = plan.call("next_item")
	if not String(opened.get("say", "")).begins_with("Put the "):
		failures.append("tidy: the opening line should name the first toy, got '%s'" % opened.get("say"))
	for node: Variant in nodes:
		var at: Vector3 = SpatialUtil.world_position(node as Node3D)
		if at.distance_to(SpatialUtil.world_position(aliz)) < 0.05:
			failures.append("tidy: a toy was scattered under her feet")
		if (node as Node).get_parent() != room:
			failures.append("tidy: the scattered %s is not in the bedroom" % (node as Node).get("object_id"))
		if bool(model.call("contains", String((node as Node).get("object_id")))):
			failures.append("tidy: %s starts out already in the box" % (node as Node).get("object_id"))
	var staged: Array = []
	for pickup: Variant in director.call("ensure_draggables"):
		staged.append(String((pickup as Node).get("object_id")))
	for node: Variant in nodes:
		if staged.has(String((node as Node).get("object_id"))):
			failures.append("tidy: %s was scattered although one is already staged on the floor" % (node as Node).get("object_id"))
	# Arriving again mid-tidy: the lid stays open, the next toy is named again.
	var again: Dictionary = director.call("_act_at", "bedroom.toyBox")
	if not bool(room.call("is_storage_open", "toyBox")):
		failures.append("tidy: a second arrival mid-tidy shut the lid")
	if String(again.get("say", "")) != String(opened.get("say", "")):
		failures.append("tidy: a second arrival should repeat the prompt, said '%s'" % again.get("say"))
	if int(director.call("get_tidy_count")) != started_before + 1:
		failures.append("tidy: a second arrival mid-tidy started another tidy")

	# The first toy by the pad (drag / tap fallback -> `chosen`).
	var first_node: Node = nodes[0]
	var first_id: String = String(first_node.get("object_id"))
	first_node.emit_signal("chosen", first_id)
	if not bool(model.call("contains", first_id)):
		failures.append("tidy: %s did not go into the box when it reached the pad" % first_id)
	if (plan.get("placed") as Array).size() != 1:
		failures.append("tidy: the plan did not count the first toy (%s)" % str(plan.get("placed")))
	var rest0: Vector3 = room.call("storage_rest_position", "toyBox", 0)
	if SpatialUtil.world_position(first_node as Node3D).distance_to(rest0) > 0.3:
		failures.append("tidy: %s is %.2f m from the inside of the box" % [first_id, SpatialUtil.world_position(first_node as Node3D).distance_to(rest0)])
	# The rest by carrying: each one is praised, the last one is "All tidy!".
	var lines: Array = []
	for index: int in range(1, nodes.size()):
		var node: Node = nodes[index]
		if not bool(aliz.call("carry_node", node, "itemHoldRight")):
			failures.append("tidy: could not pick up %s" % node.get("object_id"))
			continue
		_step(aliz, 40)
		var stored: Dictionary = director.call("_act_at", "bedroom.toyBox")
		_step(aliz, 40)
		lines.append(String(stored.get("say", "")))
		if not bool(model.call("contains", String(node.get("object_id")))):
			failures.append("tidy: the carried %s did not go in the box" % node.get("object_id"))
	if not bool(plan.call("is_complete")):
		failures.append("tidy: after every toy went in, the plan is not complete (%d left)" % plan.call("remaining"))
	if bool(director.call("is_tidy_active")):
		failures.append("tidy: the tidy is still active after the last toy")
	if lines.is_empty() or not lines[-1].to_lower().contains("tidy"):
		failures.append("tidy: the last toy should end with 'All tidy!', said %s" % str(lines))
	for line: String in lines.slice(0, lines.size() - 1):
		if line == "In it goes!" or line.is_empty():
			failures.append("tidy: a scattered toy got the generic line '%s' instead of praise" % line)
	# Taking one back out counts it again -- and arriving empty-handed then
	# CONTINUES this tidy rather than starting another.
	var last_node: Node = nodes[nodes.size() - 1]
	if bool(aliz.call("carry_node", last_node, "itemHoldRight")):
		_step(aliz, 40)
		if bool(model.call("contains", String(last_node.get("object_id")))):
			failures.append("tidy: the box still lists a toy that is in her hand")
		if bool(plan.call("is_complete")):
			failures.append("tidy: the plan stayed complete with a toy back in her hand")
		var floor_spot: Vector3 = SpatialUtil.world_position(aliz) + Vector3(0.3, 0.0, 0.3)
		aliz.call("put_down_carried", floor_spot)
		_step(aliz, 60)
		if bool(aliz.call("is_carrying_node")):
			failures.append("tidy: could not put the toy back on the floor")
		var resumed: Dictionary = director.call("_act_at", "bedroom.toyBox")
		if int(director.call("get_tidy_count")) != started_before + 1:
			failures.append("tidy: arriving with one toy still out started a new tidy instead of continuing")
		if not String(resumed.get("say", "")).begins_with("Put the "):
			failures.append("tidy: continuing should name the toy still out, said '%s'" % resumed.get("say"))
		# And back in it goes.
		if bool(aliz.call("carry_node", last_node, "itemHoldRight")):
			_step(aliz, 40)
			var back: Dictionary = director.call("_act_at", "bedroom.toyBox")
			_step(aliz, 40)
			if not bool(plan.call("is_complete")):
				failures.append("tidy: putting the toy back did not complete the plan again")
			if not String(back.get("say", "")).to_lower().contains("tidy"):
				failures.append("tidy: putting the last toy back should say all tidy again, said '%s'" % back.get("say"))
	# Replay: empty hands at the box again starts a fresh scatter; the old toys are gone.
	var replay: Dictionary = director.call("_act_at", "bedroom.toyBox")
	if int(director.call("get_tidy_count")) != started_before + 2:
		failures.append("tidy: arriving after the tidy did not start a new one")
	if not bool(director.call("is_tidy_active")):
		failures.append("tidy: the replayed tidy is not active")
	var fresh: Array = director.call("get_tidy_nodes")
	if fresh.size() < 1:
		failures.append("tidy: the replay scattered nothing")
	for node: Variant in nodes:
		if is_instance_valid(node) and fresh.has(node):
			failures.append("tidy: an old toy survived into the replay")
	if int(model.call("count")) != 0:
		failures.append("tidy: the box still holds %d old toys after the replay began (%s)" % [model.call("count"), model.call("describe")])
	if not String(replay.get("say", "")).begins_with("Put the "):
		failures.append("tidy: the replay did not name a toy, said '%s'" % replay.get("say"))
	# Leave it clean for the cases that follow.
	director.call("_clear_tidy")
	room.call("set_open", "toyBox", false)
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
	# Food preparation is a close-up too (owner: the counter combined silently).
	if made == "fruitBowl" or made == "mashedBanana":
		if not bool(director.call("is_care_open")):
			failures.append("kitchen: making the %s did not open the mashFood close-up" % made)
		else:
			var mash: Control = director.call("get_care_overlay")
			if String(mash.call("get_care_kind")) != "mashFood":
				failures.append("kitchen: the food close-up opened as '%s', not mashFood" % mash.call("get_care_kind"))
			# The real gesture: hold the spoon over the bowl, then stir back and forth.
			var neck: Vector2 = mash.size * 0.5 + Vector2(0.0, -120.0)
			mash.call("_set_dragging", true, neck)
			for _i: int in range(int(1.6 / DT)):
				mash.call("apply_hold", DT, neck)
			for i: int in range(24):
				mash.call("apply_stroke", neck + Vector2(40.0 if i % 2 == 0 else -40.0, 0.0))
				if bool(mash.call("is_finished")):
					break
			if not bool(mash.call("is_finished")):
				failures.append("kitchen: a hold and 24 stirs did not finish mashing (progress %.2f)" % mash.call("get_progress"))
				mash.call("complete_by_touch")
			if bool(director.call("is_care_open")):
				failures.append("kitchen: the mash close-up stayed open after completing")
			if String(aliz.call("get_state_name")) == "disabled":
				failures.append("kitchen: input was not given back after the mash close-up")
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
	# Take the milk to Bunny: FEED opens the REAL bottle close-up.
	_arrive(aliz, "kitchen.counter")
	if String(kitchen.call("held")) != "bottleOfMilk":
		failures.append("kitchen: could not take the bottle of milk off the counter (held %s)" % kitchen.call("held"))
	if bunny != null:
		var stats: RefCounted = bunny.call("get_stats")
		stats.call("adjust", "hunger", 80.0)
		bunny.call("room_changed", world.call("get_current_room"), aliz)
		failures.append_array(_feed_through_close_up(director, aliz, bunny, kitchen, "kitchen.littleBuddy", "giveBottle", "first"))
		# AGAIN, in the same session: the pantry refilled, so the milk can be made
		# and given a second time (owner: "replay feeding from Free Play").
		if not (kitchen.call("inside", "fridge") as Array).has("bottle"):
			failures.append("kitchen: the bottle did not come back to the fridge after the feed (%s)" % str(kitchen.call("inside", "fridge")))
		if not (kitchen.call("inside", "counter") as Array).has("bowl"):
			failures.append("kitchen: the bowl did not come back to the counter after the feed (%s)" % str(kitchen.call("inside", "counter")))
		kitchen.call("set_open", "fridge", true)
		kitchen.call("take", "fridge", "bottle")
		kitchen.call("place", "counter")
		kitchen.call("take", "counter", "bowl")
		_arrive(aliz, "kitchen.counter")
		if bool(director.call("is_care_open")):
			director.call("get_care_overlay").call("complete_by_touch")
		_arrive(aliz, "kitchen.counter")
		if String(kitchen.call("held")) != "bottleOfMilk":
			failures.append("kitchen: the second bottle of milk could not be made (held %s)" % kitchen.call("held"))
		stats.call("adjust", "hunger", 80.0)
		failures.append_array(_feed_through_close_up(director, aliz, bunny, kitchen, "kitchen.littleBuddy", "giveBottle", "second"))

		# The dining area: Bunny sitting at the table, his mashed banana brought
		# to him -- the spoon close-up, and afterwards he is still sitting there.
		SpatialUtil.set_world_position(aliz, SpatialUtil.world_position(bunny) + Vector3(0.0, 0.0, 0.62))
		if not bool(bunny.call("perform_affordance", aliz)):
			failures.append("table: could not pick Bunny up")
		_step(aliz, 40)
		_arrive(aliz, "kitchen.table")
		_step(aliz, 40)
		if String(director.call("child_surface_now")) != "table":
			failures.append("table: Bunny is not recorded as sitting at the table (at '%s')" % director.call("child_surface_now"))
		kitchen.call("reset")
		kitchen.call("set_open", "fridge", true)
		kitchen.call("take", "fridge", "banana")
		kitchen.call("place", "counter")
		kitchen.call("take", "counter", "spoon")
		_arrive(aliz, "kitchen.counter")
		if bool(director.call("is_care_open")):
			director.call("get_care_overlay").call("complete_by_touch")
		_arrive(aliz, "kitchen.counter")
		if String(kitchen.call("held")) != "mashedBanana":
			failures.append("table: no mashed banana in hand (held %s)" % kitchen.call("held"))
		stats.call("adjust", "hunger", 80.0)
		failures.append_array(_feed_through_close_up(director, aliz, bunny, kitchen, "kitchen.table", "giveFood", "table"))
		if String(bunny.call("get_activity")) != "carried":
			failures.append("table: after the meal Bunny should still be sitting at the table (activity '%s')" % bunny.call("get_activity"))
		if String(director.call("child_surface_now")) != "table":
			failures.append("table: after the meal Bunny is no longer recorded at the table")
		# And again, straight away: a second helping at the table.
		if bool(kitchen.call("is_open", "fridge")) or true:
			kitchen.call("set_open", "fridge", true)
		kitchen.call("take", "fridge", "banana")
		kitchen.call("place", "counter")
		kitchen.call("take", "counter", "spoon")
		_arrive(aliz, "kitchen.counter")
		if bool(director.call("is_care_open")):
			director.call("get_care_overlay").call("complete_by_touch")
		_arrive(aliz, "kitchen.counter")
		stats.call("adjust", "hunger", 80.0)
		failures.append_array(_feed_through_close_up(director, aliz, bunny, kitchen, "kitchen.table", "giveFood", "table again"))
		# Put him back on the floor for the rooms that follow.
		SpatialUtil.set_world_position(aliz, SpatialUtil.world_position(bunny) + Vector3(0.0, 0.0, 0.62))
		bunny.call("perform_affordance", aliz)
		_step(aliz, 40)
		aliz.call("put_down_carried")
		_step(aliz, 40)
		bunny.call("room_changed", world.call("get_room", "bedroom"), aliz)
	return failures


## Arrives at `target_id` with a meal in hand and plays the feeding close-up to
## the end: it must open on the real overlay as `kind`, hold the room's input,
## move his hunger only when it completes, and give the room back.
func _feed_through_close_up(director, aliz, bunny, kitchen, target_id: String, kind: String, label: String):
	var failures: Array = []
	var stats: RefCounted = bunny.call("get_stats")
	var before: float = float((stats.call("describe") as Dictionary).get("hunger", 0.0))
	_arrive(aliz, target_id)
	if not bool(director.call("is_care_open")):
		return ["feed (%s): arriving at %s with the meal did not open the feeding close-up" % [label, target_id]]
	var care: Control = director.call("get_care_overlay")
	if String(care.call("get_care_kind")) != kind:
		failures.append("feed (%s): the close-up opened as '%s', not %s" % [label, care.call("get_care_kind"), kind])
	if String(aliz.call("get_state_name")) != "disabled":
		failures.append("feed (%s): the room's input is not held while the close-up is up" % label)
	if String(kitchen.call("held")) not in ["", "none"]:
		failures.append("feed (%s): the meal is still in her hand while Bunny eats it" % label)
	if String(bunny.call("get_activity")) != "feeding":
		failures.append("feed (%s): Bunny is '%s', not feeding, under the close-up" % [label, bunny.call("get_activity")])
	var during: float = float((stats.call("describe") as Dictionary).get("hunger", 0.0))
	if during < before:
		failures.append("feed (%s): his hunger moved before the close-up completed" % label)
	# The real gesture: hold the bottle at his mouth for FEED_SECONDS.
	var at: Vector2 = care.call("get_mouth_target")
	for _i: int in range(int(2.4 / DT) + 2):
		care.call("apply_hold", DT, at)
		if bool(care.call("is_finished")):
			break
	if not bool(care.call("is_finished")):
		failures.append("feed (%s): holding at the mouth for 2.4 s did not finish the feed (progress %.2f)" % [label, care.call("get_progress")])
		care.call("complete_by_touch")
	var after: float = float((stats.call("describe") as Dictionary).get("hunger", 0.0))
	if after >= before:
		failures.append("feed (%s): the meal did not lower his hunger (%.0f -> %.0f)" % [label, before, after])
	if bool(director.call("is_care_open")):
		failures.append("feed (%s): the close-up stayed open after the feed" % label)
	if String(aliz.call("get_state_name")) == "disabled":
		failures.append("feed (%s): input was not given back after the feed" % label)
	if bool(director.call("is_portrait_on")):
		failures.append("feed (%s): the camera is still parked on his face" % label)
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
	# Bunny to the sink: the TEETH close-up, on him -- brushed with the real
	# gesture (strokes back and forth over the mouth), not a fallback.
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
		failures.append("sink: the teeth close-up did not open with Bunny in her arms")
	else:
		var care: Control = director.call("get_care_overlay")
		if String(care.call("get_care_kind")) != "brushTeeth":
			failures.append("sink: the close-up is '%s', not brushTeeth" % care.call("get_care_kind"))
		if care.get_parent() == null or care.get_parent().name != "UI":
			failures.append("sink: the close-up is not under the world's UI layer")
		var mouth: Vector2 = care.call("get_mouth_target")
		care.call("_set_dragging", true, mouth)
		for i: int in range(40):
			care.call("apply_stroke", mouth + Vector2(30.0 if i % 2 == 0 else -30.0, 0.0))
			if bool(care.call("is_finished")):
				break
		if not bool(care.call("is_finished")):
			failures.append("sink: 40 strokes over the mouth did not finish brushing (progress %.2f)" % care.call("get_progress"))
			care.call("complete_by_touch")
		var after: float = float((stats.call("describe") as Dictionary).get("cleanliness", 0.0))
		if after <= before:
			failures.append("sink: brushing did not raise cleanliness (%.0f -> %.0f)" % [before, after])
		if bool(director.call("is_care_open")):
			failures.append("sink: the close-up did not close")
	if not bool(aliz.call("is_carrying_node")):
		failures.append("sink: Bunny left her arms during the brushing")
	# The bath: he goes in the tub, the wash close-up opens, and when the wash
	# is done the TOWEL follows in the same held room -- a bath ends dry.
	stats.call("adjust", "cleanliness", -60.0)
	var grubby: float = float((stats.call("describe") as Dictionary).get("cleanliness", 0.0))
	_arrive(aliz, "bathroom.bath")
	_step(aliz, 40)
	if not bool(director.call("is_care_open")):
		failures.append("bath: no close-up opened for Bunny")
	else:
		var care: Control = director.call("get_care_overlay")
		if String(care.call("get_care_kind")) != "washFace":
			failures.append("bath: the close-up is '%s', not washFace" % care.call("get_care_kind"))
		care.call("complete_by_touch")
		if not bool(director.call("is_care_open")):
			failures.append("bath: the towel did not follow the wash; the close-up closed")
		elif String(care.call("get_care_kind")) != "dryFace":
			failures.append("bath: after the wash the close-up is '%s', not dryFace" % care.call("get_care_kind"))
		else:
			if String(aliz.call("get_state_name")) != "disabled":
				failures.append("bath: the room's input came back between the wash and the towel")
			# Dry every patch of the face: the real DRY gesture, reach not scrubbing.
			var centre: Vector2 = care.size * 0.5
			care.call("_set_dragging", true, centre)
			var step: float = 190.0 * 2.0 / 3.0
			for row: int in range(3):
				for col: int in range(3):
					care.call("apply_stroke", centre + Vector2(-190.0 + step * (float(col) + 0.5), -190.0 + step * (float(row) + 0.5)))
			if not bool(care.call("is_finished")):
				failures.append("bath: wiping all nine patches did not finish drying (progress %.2f)" % care.call("get_progress"))
				care.call("complete_by_touch")
		if bool(director.call("is_care_open")):
			failures.append("bath: the close-up is still open after the towel")
		if String(aliz.call("get_state_name")) == "disabled":
			failures.append("bath: input was not given back after the towel")
		var dried: float = float((stats.call("describe") as Dictionary).get("cleanliness", 0.0))
		if dried <= grubby:
			failures.append("bath: the bath did not raise cleanliness (%.0f -> %.0f)" % [grubby, dried])
	if bool(aliz.call("is_carrying_node")):
		failures.append("bath: Bunny is still in her arms; he should be in the tub")
	var tub: Vector3 = SpatialUtil.world_transform(world.call("get_current_room")) \
			* (HouseLayout.child_surface("bathroom", "bath")["position"] as Vector3)
	if SpatialUtil.world_position(bunny).distance_to(tub) > 0.05:
		failures.append("bath: Bunny is at %s, not in the tub at %s" % [SpatialUtil.world_position(bunny), tub])
	if String(bunny.call("get_activity")) != "bath":
		failures.append("bath: Bunny's activity is '%s', not bath" % bunny.call("get_activity"))
	# The close-up's own safety: it completes itself if the gesture never comes
	# -- at the sink, and through BOTH halves of the bath.
	SpatialUtil.set_world_position(aliz, tub + Vector3(0.0, -tub.y, 0.7))
	bunny.call("perform_affordance", aliz)
	_step(aliz, 40)
	_arrive(aliz, "bathroom.sink")
	if bool(director.call("is_care_open")):
		for _i: int in range(int(15.0 / DT)):
			director.call("step", DT)
		if bool(director.call("is_care_open")):
			failures.append("sink: the close-up never completed itself; a child who cannot drag is stuck")
	_arrive(aliz, "bathroom.bath")
	_step(aliz, 40)
	if bool(director.call("is_care_open")):
		for _i: int in range(int(30.0 / DT)):
			director.call("step", DT)
		if bool(director.call("is_care_open")):
			failures.append("bath: the wash-then-towel never completed itself (stuck on %s)" % director.call("get_care_overlay").call("get_care_kind"))
	# Replayable: out of the tub and back in opens the wash again.
	SpatialUtil.set_world_position(aliz, tub + Vector3(0.0, -tub.y, 0.7))
	bunny.call("perform_affordance", aliz)
	_step(aliz, 40)
	_arrive(aliz, "bathroom.bath")
	_step(aliz, 40)
	if not bool(director.call("is_care_open")) or String(director.call("get_care_overlay").call("get_care_kind")) != "washFace":
		failures.append("bath: a second bath did not open the wash close-up again")
	else:
		director.call("get_care_overlay").call("complete_by_touch")
		director.call("get_care_overlay").call("complete_by_touch")
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
