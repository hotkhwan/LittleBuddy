extends RefCounted

## Proximity affordances: the rules, the `affordable` contract on
## `ActivityTarget`, and the layer that polls it.
##
## Everything runs without `_ready()`, without the scene tree and without a
## camera, because the headless `--script` runner provides none of them. The
## layer is fed its candidates directly (`set_candidate_sources()`), which is
## the same code path the tree group feeds in a live scene.

const Rules := preload("res://scripts/interaction/affordance_rules.gd")
const LayerScript := preload("res://scripts/interaction/affordance_layer.gd")
const ActivityTarget := preload("res://scripts/navigation/activity_target.gd")
const NavigationController := preload("res://scripts/navigation/navigation_controller.gd")
const KitchenState := preload("res://scripts/kitchen/kitchen_state.gd")
const Palette := preload("res://scripts/ui/palette.gd")


## A node that speaks the contract with a fixed answer.
class FakeAffordable extends Node3D:
	var offer: Dictionary = {}
	var performed: int = 0
	var handles: bool = false

	func get_affordance(_actor: Node3D) -> Dictionary:
		return offer.duplicate()

	func perform_affordance(_actor: Node3D) -> bool:
		performed += 1
		return handles


## A router that records what the layer routed.
class FakeNav extends Node:
	var taps_enabled: bool = true
	var taps: Array = []

	func apply_tap(tap: Dictionary) -> bool:
		taps.append(tap.duplicate())
		return true


class FakeActor extends Node3D:
	var state: String = "idle"

	func get_state_name() -> String:
		return state


class FakeWorld extends Node:
	var kitchen: RefCounted = null
	var character: Node3D = null

	func get_character() -> Node:
		return character

	func get_kitchen_state() -> RefCounted:
		return kitchen

	func get_current_room() -> Node:
		return null


func test_name() -> String:
	return "affordance"


func run():
	var failures: Array = []
	failures.append_array(_test_verb_vocabulary_and_colours())
	failures.append_array(_test_verb_rules())
	failures.append_array(_test_pick_orders_by_relevance_priority_distance())
	failures.append_array(_test_activity_target_speaks_the_contract())
	failures.append_array(_test_layer_shows_and_hides_with_distance())
	failures.append_array(_test_layer_priority_and_mission_relevance())
	failures.append_array(_test_layer_tap_falls_through_or_is_handled())
	failures.append_array(_test_layer_stands_down_when_input_is_off())
	failures.append_array(_test_default_context_reads_the_kitchen())
	return failures


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

func _test_verb_vocabulary_and_colours():
	var failures: Array = []
	var expected: Array = ["OPEN", "TAKE", "PLACE", "ENTER", "HUG", "CARRY", "FEED"]
	for verb: String in expected:
		if not Rules.is_verb(verb):
			failures.append("affordance: '%s' is not in the verb vocabulary" % verb)
		var color: Color = Rules.verb_color(verb)
		if Palette.is_red(color) or Palette.is_black(color) or Palette.is_grey(color):
			failures.append("affordance: %s is drawn in %s, which is red, black or grey" % [verb, color])
	if Rules.is_verb("QUIT"):
		failures.append("affordance: an unknown word passed as a verb")
	# The verb tokens are aliases of locked palette tokens, never new colours.
	if Palette.VERB_OPEN != Palette.PEACH or Palette.VERB_ENTER != Palette.LAVENDER \
			or Palette.VERB_TAKE != Palette.MINT or Palette.VERB_PLACE != Palette.DUSTY_BLUE \
			or Palette.VERB_HUG != Palette.SOFT_PINK or Palette.VERB_FEED != Palette.STAR_EARNED:
		failures.append("affordance: a verb colour drifted from the locked token it aliases")
	return failures


func _test_verb_rules():
	var failures: Array = []
	var door: Dictionary = {"isDoor": true, "supportedActions": ["open", "goThrough"], "enabled": true}
	if Rules.verb_for_target(door) != Rules.VERB_ENTER:
		failures.append("affordance: a door does not offer ENTER")
	if not Rules.verb_for_target({"isDoor": true, "enabled": false}).is_empty():
		failures.append("affordance: a disabled target still offers a verb")

	var fridge: Dictionary = {"isDoor": false, "supportedActions": ["open", "give"], "enabled": true}
	if Rules.verb_for_target(fridge) != Rules.VERB_OPEN:
		failures.append("affordance: a target that supports 'open' with no context does not offer OPEN")
	var shut: Dictionary = {"station": {"opens": true, "isOpen": false, "inside": ["banana"], "on": "", "canPlace": false}}
	if Rules.verb_for_target(fridge, shut) != Rules.VERB_OPEN:
		failures.append("affordance: a shut fridge does not offer OPEN")
	var open_full: Dictionary = {"station": {"opens": true, "isOpen": true, "inside": ["banana"], "on": "", "canPlace": false}}
	if Rules.verb_for_target(fridge, open_full) != Rules.VERB_TAKE:
		failures.append("affordance: an open fridge with food in it does not offer TAKE")
	var open_empty: Dictionary = {"station": {"opens": true, "isOpen": true, "inside": [], "on": "", "canPlace": false}}
	if not Rules.verb_for_target(fridge, open_empty).is_empty():
		failures.append("affordance: an open EMPTY fridge with empty hands offers %s" % Rules.verb_for_target(fridge, open_empty))
	var holding_at_counter: Dictionary = {"held": "banana", "station": {"opens": false, "isOpen": false, "inside": [], "on": "", "canPlace": true}}
	var counter: Dictionary = {"isDoor": false, "supportedActions": ["wash", "give"], "enabled": true}
	if Rules.verb_for_target(counter, holding_at_counter) != Rules.VERB_PLACE:
		failures.append("affordance: holding an item at a counter does not offer PLACE")
	var holding_at_shut_fridge: Dictionary = {"held": "banana", "station": {"opens": true, "isOpen": false, "inside": [], "on": "", "canPlace": true}}
	if Rules.verb_for_target(fridge, holding_at_shut_fridge) != Rules.VERB_OPEN:
		failures.append("affordance: holding an item at a shut fridge should offer OPEN first")
	var counter_with_spoon: Dictionary = {"station": {"opens": false, "isOpen": false, "inside": ["bowl", "spoon"], "on": "", "canPlace": false}}
	if Rules.verb_for_target(counter, counter_with_spoon) != Rules.VERB_TAKE:
		failures.append("affordance: a counter holding a spoon does not offer TAKE")

	var toy_box: Dictionary = {"isDoor": false, "supportedActions": ["open", "putAway"], "enabled": true}
	if Rules.verb_for_target(toy_box, {"storage": {"isOpen": true}}) != Rules.VERB_OPEN:
		failures.append("affordance: a container lid does not offer OPEN")
	var book: Dictionary = {"isDoor": false, "supportedActions": ["read", "pickUp"], "enabled": true}
	if Rules.verb_for_target(book) != Rules.VERB_TAKE:
		failures.append("affordance: a pick-up-able prop does not offer TAKE")
	var bed: Dictionary = {"isDoor": false, "supportedActions": ["sleep", "sit"], "enabled": true}
	if not Rules.verb_for_target(bed).is_empty():
		failures.append("affordance: a bed offers '%s'; nothing in the vocabulary fits it" % Rules.verb_for_target(bed))

	var bunny: Dictionary = {"isDoor": false, "supportedActions": [], "enabled": true}
	if Rules.verb_for_target(bunny, {"character": {"canHug": true}}) != Rules.VERB_HUG:
		failures.append("affordance: a huggable character does not offer HUG")
	if Rules.verb_for_target(bunny, {"character": {"canHug": true, "canCarry": true}}) != Rules.VERB_CARRY:
		failures.append("affordance: CARRY does not outrank HUG when both are allowed")
	if Rules.verb_for_target(bunny, {"held": "bottleOfMilk", "character": {"canHug": true, "canFeed": true}}) != Rules.VERB_FEED:
		failures.append("affordance: holding food near a feedable character does not offer FEED")
	return failures


func _test_pick_orders_by_relevance_priority_distance():
	var failures: Array = []
	var near_door: Dictionary = {"verb": "ENTER", "anchor": Vector3(1.0, 0.0, 0.0), "radius": 2.0, "priority": 1, "targetId": "kitchen.door"}
	var far_fridge: Dictionary = {"verb": "OPEN", "anchor": Vector3(1.6, 0.0, 0.0), "radius": 2.0, "priority": 2, "targetId": "kitchen.fridge"}
	var out_of_reach: Dictionary = {"verb": "TAKE", "anchor": Vector3(9.0, 0.0, 0.0), "radius": 1.0, "priority": 9, "targetId": "kitchen.table"}
	var actor: Vector3 = Vector3.ZERO

	var picked: Dictionary = Rules.pick([near_door, far_fridge, out_of_reach], actor)
	if String(picked.get("targetId", "")) != "kitchen.fridge":
		failures.append("affordance: priority did not beat distance (got %s)" % str(picked.get("targetId")))
	picked = Rules.pick([near_door, far_fridge], actor, ["kitchen.door"])
	if String(picked.get("targetId", "")) != "kitchen.door":
		failures.append("affordance: the mission's own target did not win")
	var same_priority_far: Dictionary = {"verb": "OPEN", "anchor": Vector3(1.8, 0.0, 0.0), "radius": 3.0, "priority": 2, "targetId": "b"}
	var same_priority_near: Dictionary = {"verb": "OPEN", "anchor": Vector3(0.5, 0.0, 0.0), "radius": 3.0, "priority": 2, "targetId": "a"}
	picked = Rules.pick([same_priority_far, same_priority_near], actor)
	if String(picked.get("targetId", "")) != "a":
		failures.append("affordance: with equal priority the nearer offer did not win")
	if not Rules.pick([out_of_reach], actor).is_empty():
		failures.append("affordance: an out-of-range offer was picked")
	if not Rules.pick([{"verb": "", "anchor": Vector3.ZERO, "radius": 5.0}], actor).is_empty():
		failures.append("affordance: an empty verb was picked")
	# Height never counts: a handle 1 m up is as reachable as its foot.
	var tall: Dictionary = {"verb": "OPEN", "anchor": Vector3(0.5, 4.0, 0.0), "radius": 1.0, "priority": 2, "targetId": "tall"}
	if Rules.pick([tall], actor).is_empty():
		failures.append("affordance: a tall anchor was treated as far away")
	return failures


# ---------------------------------------------------------------------------
# ActivityTarget implements the contract
# ---------------------------------------------------------------------------

func _make_target(id: String, room: String, actions: Array, box: Vector3, at: Vector3) -> Area3D:
	var target: Area3D = ActivityTarget.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = box
	shape.shape = box_shape
	target.add_child(shape)
	target.position = at
	target.set("target_id", id)
	target.set("room_id", room)
	target.call("set_supported_actions", actions)
	return target


func _test_activity_target_speaks_the_contract():
	var failures: Array = []
	var actor: Node3D = Node3D.new()
	var fridge: Area3D = _make_target("fridge", "kitchen", ["open", "give"], Vector3(0.7, 1.7, 0.65), Vector3(1.4, 0.85, -1.6))
	var door: Area3D = _make_target("doorToBathroom", "kitchen", ["open", "goThrough"], Vector3(0.3, 1.9, 0.9), Vector3(-2.0, 0.95, 0.6))
	door.set("to_room_id", "bathroom")
	var bed: Area3D = _make_target("bed", "bedroom", ["sleep", "sit"], Vector3(1.0, 0.5, 2.0), Vector3.ZERO)

	if not fridge.is_in_group("affordable") or not door.is_in_group("affordable"):
		failures.append("affordance: ActivityTarget did not join the 'affordable' group")

	var offer: Dictionary = fridge.call("get_affordance", actor)
	if String(offer.get("verb", "")) != "OPEN":
		failures.append("affordance: the fridge target offers '%s', expected OPEN" % str(offer.get("verb")))
	for key: String in ["verb", "anchor", "radius", "priority", "target", "targetId", "extent"]:
		if not offer.has(key):
			failures.append("affordance: the fridge's offer lacks '%s'" % key)
	if String(offer.get("targetId", "")) != "kitchen.fridge":
		failures.append("affordance: offer targetId is %s" % str(offer.get("targetId")))
	if offer.get("target", null) != fridge:
		failures.append("affordance: offer target is not the node itself")
	var anchor: Vector3 = offer.get("anchor", Vector3.ZERO)
	if not is_equal_approx(anchor.x, 1.4) or not is_equal_approx(anchor.z, -1.6) or anchor.y <= 0.85:
		failures.append("affordance: the fridge anchor %s is not above its centre" % str(anchor))
	var radius: float = float(offer.get("radius", 0.0))
	if radius < 1.2 or radius > 2.2:
		failures.append("affordance: fridge radius %.2f is not a sensible reach" % radius)
	if not is_equal_approx(float(offer.get("extent", 0.0)), 0.35):
		failures.append("affordance: fridge extent should be half its footprint (0.35), got %s" % str(offer.get("extent")))
	fridge.set("affordance_radius", 3.0)
	if not is_equal_approx(float(fridge.call("get_affordance_radius")), 3.0):
		failures.append("affordance: an authored affordance_radius is ignored")

	var door_offer: Dictionary = door.call("get_affordance", actor)
	if String(door_offer.get("verb", "")) != "ENTER":
		failures.append("affordance: a door target offers '%s', expected ENTER" % str(door_offer.get("verb")))
	if int(door_offer.get("priority", 99)) >= int(offer.get("priority", 0)):
		failures.append("affordance: a door does not rank below furniture")

	if not (bed.call("get_affordance", actor) as Dictionary).is_empty():
		failures.append("affordance: a bed offers something; it has no verb in the vocabulary")

	fridge.call("set_target_enabled", false)
	if not (fridge.call("get_affordance", actor) as Dictionary).is_empty():
		failures.append("affordance: a disabled target still offers")
	fridge.call("set_target_enabled", true)

	# The context provider decides the verb when installed.
	fridge.call("set_affordance_context_provider", func(_target: Node, _who: Node3D) -> Dictionary:
		return {"station": {"opens": true, "isOpen": true, "inside": ["banana"], "on": "", "canPlace": false}})
	if String((fridge.call("get_affordance", actor) as Dictionary).get("verb", "")) != "TAKE":
		failures.append("affordance: the context provider did not turn OPEN into TAKE")
	fridge.call("clear_affordance_context_provider")
	if String((fridge.call("get_affordance", actor) as Dictionary).get("verb", "")) != "OPEN":
		failures.append("affordance: clearing the provider did not restore the default")

	if fridge.has_method("perform_affordance"):
		failures.append("affordance: ActivityTarget must NOT define perform_affordance(); taps fall through to routing")

	fridge.free()
	door.free()
	bed.free()
	actor.free()
	return failures


# ---------------------------------------------------------------------------
# The layer
# ---------------------------------------------------------------------------

func _fake(id: String, verb: String, at: Vector3, radius: float, priority: int) -> FakeAffordable:
	var node: FakeAffordable = FakeAffordable.new()
	node.name = id
	node.offer = {"verb": verb, "anchor": at, "radius": radius, "priority": priority, "targetId": id}
	return node


func _test_layer_shows_and_hides_with_distance():
	var failures: Array = []
	var layer: Control = LayerScript.new()
	layer.call("build")
	var actor: FakeActor = FakeActor.new()
	layer.call("set_actor", actor)
	var fridge: FakeAffordable = _fake("kitchen.fridge", "OPEN", Vector3(3.0, 0.5, 0.0), 1.5, 2)
	layer.call("set_candidate_sources", [fridge])

	var shown: Array = []
	var hidden: Array = [0]
	layer.connect("affordance_shown", func(verb: String, id: String) -> void: shown.append([verb, id]))
	layer.connect("affordance_hidden", func() -> void: hidden[0] += 1)

	actor.position = Vector3.ZERO
	layer.call("step", 0.016)
	if bool(layer.call("is_showing")):
		failures.append("affordance: the badge shows from 3 m away with a 1.5 m radius")
	actor.position = Vector3(2.0, 0.0, 0.0)
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "OPEN":
		failures.append("affordance: walking within range did not show OPEN")
	if String(layer.call("get_current_target_id")) != "kitchen.fridge":
		failures.append("affordance: the badge names %s" % str(layer.call("get_current_target_id")))
	if shown.size() != 1:
		failures.append("affordance: affordance_shown fired %d times for one appearance" % shown.size())
	layer.call("step", 0.016)
	if shown.size() != 1:
		failures.append("affordance: affordance_shown re-fires every frame")
	if bool(layer.call("is_laid_out")) or (layer.call("get_hit_rect") as Rect2).size != Vector2.ZERO:
		failures.append("affordance: with no camera the layer still laid out a tap target")
	actor.position = Vector3(0.0, 0.0, 0.0)
	layer.call("step", 0.016)
	if bool(layer.call("is_showing")):
		failures.append("affordance: walking away did not hide the badge")
	if hidden[0] != 1:
		failures.append("affordance: affordance_hidden fired %d times" % hidden[0])

	layer.free()
	fridge.free()
	actor.free()
	return failures


func _test_layer_priority_and_mission_relevance():
	var failures: Array = []
	var layer: Control = LayerScript.new()
	layer.call("build")
	var actor: FakeActor = FakeActor.new()
	actor.position = Vector3.ZERO
	layer.call("set_actor", actor)
	var door: FakeAffordable = _fake("kitchen.doorToBathroom", "ENTER", Vector3(0.6, 0.0, 0.0), 2.0, 1)
	var fridge: FakeAffordable = _fake("kitchen.fridge", "OPEN", Vector3(1.4, 0.0, 0.0), 2.0, 2)
	layer.call("set_candidate_sources", [door, fridge])

	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "OPEN":
		failures.append("affordance: the nearer door outranked the fridge (got %s)" % str(layer.call("get_current_verb")))
	layer.call("set_preferred_target_ids", ["kitchen.doorToBathroom"])
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "ENTER":
		failures.append("affordance: the mission's door did not win once preferred")
	layer.call("set_preferred_target_ids", [], true)
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "OPEN":
		failures.append("affordance: clearing the preference did not restore priority order")

	layer.free()
	door.free()
	fridge.free()
	actor.free()
	return failures


func _test_layer_tap_falls_through_or_is_handled():
	var failures: Array = []
	if LayerScript.TAP_KIND_TARGET != NavigationController.TapKind.TARGET:
		failures.append("affordance: TAP_KIND_TARGET (%d) drifted from NavigationController.TapKind.TARGET (%d)"
				% [LayerScript.TAP_KIND_TARGET, NavigationController.TapKind.TARGET])

	var layer: Control = LayerScript.new()
	layer.call("build")
	var actor: FakeActor = FakeActor.new()
	layer.call("set_actor", actor)
	var nav: FakeNav = FakeNav.new()
	layer.call("set_navigation_controller", nav)
	var fridge: FakeAffordable = _fake("kitchen.fridge", "OPEN", Vector3(0.5, 0.0, 0.0), 2.0, 2)
	layer.call("set_candidate_sources", [fridge])
	var performed: Array = []
	layer.connect("affordance_performed", func(verb: String, id: String, handled: bool) -> void:
		performed.append([verb, id, handled]))

	if bool(layer.call("perform")):
		failures.append("affordance: perform() with nothing shown claimed success")
	layer.call("step", 0.016)
	if not bool(layer.call("perform")):
		failures.append("affordance: perform() on a shown offer returned false")
	if nav.taps.size() != 1:
		failures.append("affordance: the tap did not fall through to NavigationController.apply_tap (%d taps)" % nav.taps.size())
	else:
		var tap: Dictionary = nav.taps[0]
		if int(tap.get("kind", -1)) != NavigationController.TapKind.TARGET or String(tap.get("targetId", "")) != "kitchen.fridge":
			failures.append("affordance: the routed tap was %s" % str(tap))
	if fridge.performed != 1:
		failures.append("affordance: perform_affordance was asked %d times" % fridge.performed)
	if performed.size() != 1 or bool(performed[0][2]):
		failures.append("affordance: affordance_performed should report handled=false on fall-through")

	# A target that handles its own tap keeps the router out of it.
	fridge.handles = true
	layer.call("step", 0.016)
	layer.call("perform")
	if nav.taps.size() != 1:
		failures.append("affordance: a handled affordance still fell through to routing")
	if performed.size() != 2 or not bool(performed[1][2]):
		failures.append("affordance: affordance_performed should report handled=true")

	layer.free()
	nav.free()
	fridge.free()
	actor.free()
	return failures


func _test_layer_stands_down_when_input_is_off():
	var failures: Array = []
	var layer: Control = LayerScript.new()
	layer.call("build")
	var actor: FakeActor = FakeActor.new()
	layer.call("set_actor", actor)
	var nav: FakeNav = FakeNav.new()
	layer.call("set_navigation_controller", nav)
	var fridge: FakeAffordable = _fake("kitchen.fridge", "OPEN", Vector3(0.5, 0.0, 0.0), 2.0, 2)
	layer.call("set_candidate_sources", [fridge])

	layer.call("step", 0.016)
	if not bool(layer.call("is_showing")):
		failures.append("affordance: precondition -- the badge should show")
	nav.taps_enabled = false
	layer.call("step", 0.016)
	if bool(layer.call("is_showing")):
		failures.append("affordance: the badge stays up while taps are disabled (a summary is open)")
	nav.taps_enabled = true
	actor.state = "disabled"
	layer.call("step", 0.016)
	if bool(layer.call("is_showing")):
		failures.append("affordance: the badge stays up while the character is disabled")
	actor.state = "idle"
	layer.call("set_enabled", false)
	layer.call("step", 0.016)
	if bool(layer.call("is_showing")):
		failures.append("affordance: set_enabled(false) did not stand the layer down")
	layer.call("set_enabled", true)
	layer.call("step", 0.016)
	if not bool(layer.call("is_showing")):
		failures.append("affordance: set_enabled(true) did not bring the layer back")

	layer.free()
	nav.free()
	fridge.free()
	actor.free()
	return failures


## The owner's examples, end to end against the REAL kitchen model: near the
## fridge -> OPEN; fridge open -> TAKE; holding the banana at the counter ->
## PLACE.
func _test_default_context_reads_the_kitchen():
	var failures: Array = []
	var world: FakeWorld = FakeWorld.new()
	var actor: FakeActor = FakeActor.new()
	world.character = actor
	world.kitchen = KitchenState.new()
	var layer: Control = LayerScript.new()
	world.add_child(layer)
	layer.call("bind", world)
	var fridge: Area3D = _make_target("fridge", "kitchen", ["open", "give"], Vector3(0.7, 1.7, 0.65), Vector3(1.4, 0.85, -1.6))
	var counter: Area3D = _make_target("counter", "kitchen", ["wash", "give"], Vector3(1.8, 0.9, 0.6), Vector3(-0.8, 0.45, -1.65))
	var table: Area3D = _make_target("table", "kitchen", ["eat", "sit"], Vector3(1.0, 0.7, 0.8), Vector3(0.5, 0.35, 0.55))
	world.add_child(fridge)
	world.add_child(counter)
	world.add_child(table)
	layer.call("set_candidate_sources", [fridge, counter, table])

	actor.position = Vector3(1.4, 0.0, -0.9)
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "OPEN" or String(layer.call("get_current_target_id")) != "kitchen.fridge":
		failures.append("affordance: near the shut fridge the badge says %s on %s"
				% [str(layer.call("get_current_verb")), str(layer.call("get_current_target_id"))])

	world.kitchen.call("set_open", "fridge", true)
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "TAKE":
		failures.append("affordance: with the fridge open the badge says %s, not TAKE" % str(layer.call("get_current_verb")))

	world.kitchen.call("take", "fridge", "banana")
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "PLACE":
		failures.append("affordance: holding the banana at the open fridge should offer PLACE (put it back); got %s"
				% str(layer.call("get_current_verb")))

	actor.position = Vector3(-0.8, 0.0, -1.0)
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "PLACE" or String(layer.call("get_current_target_id")) != "kitchen.counter":
		failures.append("affordance: holding the banana at the counter the badge says %s on %s"
				% [str(layer.call("get_current_verb")), str(layer.call("get_current_target_id"))])

	# A table only takes finished food: a raw banana in hand offers nothing there.
	actor.position = Vector3(0.5, 0.0, 1.4)
	layer.call("step", 0.016)
	if bool(layer.call("is_showing")):
		failures.append("affordance: the table offered %s for a raw banana" % str(layer.call("get_current_verb")))

	world.free()
	return failures
