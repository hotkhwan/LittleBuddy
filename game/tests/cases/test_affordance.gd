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
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const CharacterScript := preload("res://scripts/character/little_buddy_character.gd")
const BuddyViewScript := preload("res://scripts/characters/buddy/pink_girl_buddy.gd")
const ChildActorScript := preload("res://scripts/care/child_actor.gd")
const NavigationProvider := preload("res://scripts/navigation/navigation_provider.gd")

const DT: float = 1.0 / 60.0


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


## Stands in for `child_actor.gd`: the two methods the layer sniffs for.
class FakeChild extends Node3D:
	func satisfy(_need: String, _amount: float) -> void:
		pass

	func attend(_point: Vector3) -> void:
		pass


## A kitchen that only answers what the layer asks, with a hand we can fill.
class FakeKitchen extends RefCounted:
	var in_hand: String = ""

	func held() -> String:
		return in_hand

	func describe(_station_id: String) -> Dictionary:
		return {"role": "", "open": false, "on": "", "inside": []}


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
	failures.append_array(_test_a_character_is_never_taken())
	failures.append_array(_test_badge_placement_avoids_keep_outs())
	failures.append_array(_test_a_visible_care_overlay_silences_the_layer())
	failures.append_array(_test_provider_verbs_are_normalised())
	failures.append_array(_test_doors_outrank_loose_props())
	failures.append_array(_test_a_character_badge_keeps_off_his_bubble())
	failures.append_array(_test_badge_is_small_and_scales_with_the_screen())
	failures.append_array(_test_the_thing_she_faces_wins())
	failures.append_array(_test_touch_mouse_twin_does_not_double_perform())
	failures.append_array(_test_rapid_taps_carry_bunny_only_once())
	failures.append_array(_test_carried_child_ranks_below_a_reachable_surface())
	failures.append_array(_test_placement_hysteresis_holds_the_badge_through_a_blink())
	failures.append_array(_test_layout_freezes_while_a_press_is_live())
	return failures


## The other half of the badge-stability fix: while a press is still being
## answered (`_press_clock` counting down from `perform()`), `_layout()` must
## not touch the hit box at all, however much `_current` changed underneath --
## a real device has no reliable moment to sneak the geometry sideways between
## the finger landing and the tap being read.
func _test_layout_freezes_while_a_press_is_live():
	var failures: Array = []
	var layer: Control = LayerScript.new()
	layer.call("build")
	var actor: FakeActor = FakeActor.new()
	layer.call("set_actor", actor)
	# No candidates at all: a fresh `evaluate()` this frame would return `{}`.
	layer.call("set_candidate_sources", [])

	# Pretend a previous frame laid the badge out and a press just landed.
	layer.set("_laid_out", true)
	layer.set("_press_clock", 0.05)
	var hit: Control = layer.get_node("AffordanceHit")
	hit.position = Vector2(111.0, 222.0)
	hit.size = Vector2(240.0, 240.0)
	hit.visible = true

	layer.call("step", 0.016)

	if hit.position != Vector2(111.0, 222.0) or hit.size != Vector2(240.0, 240.0) or not hit.visible:
		failures.append("affordance: the hit box moved or hid itself while a press was still live")
	if not bool(layer.call("is_laid_out")):
		failures.append("affordance: is_laid_out() flipped false mid-press")

	layer.free()
	actor.free()
	return failures


## Owner bug: the badge's keep-outs blink every frame (a speech bubble, her own
## face keep-out sliding as she steps), so a tap landing a moment after the
## child saw the badge could find the hit box already walked to the other side
## of the ring. `_apply_placement_hysteresis()` is exercised directly (bypassing
## `step()`, which would also re-run `evaluate()`/`_layout()` with no actor
## bound and reset the very state under test) so the dwell logic is proven on
## its own, independent of any camera or viewport.
func _test_placement_hysteresis_holds_the_badge_through_a_blink():
	var failures: Array = []
	var layer: Control = LayerScript.new()
	layer.call("build")
	layer.set("_clock", 0.0)

	layer.call("_apply_placement_hysteresis", "kitchen.fridge", "OPEN",
			{"centre": Vector2(400.0, 300.0), "placement": "above"})
	if String(layer.call("get_placement")) != "above":
		failures.append("affordance: hysteresis: a brand-new target did not snap to its placement at once")
	if not (layer.call("get_badge_centre") as Vector2).is_equal_approx(Vector2(400.0, 300.0)):
		failures.append("affordance: hysteresis: a brand-new target did not snap to its position at once")

	# 50 ms later (well inside the dwell) a keep-out blinks on and the same
	# search now wants the other side: the side, and the position, must hold.
	layer.set("_clock", 0.05)
	layer.call("_apply_placement_hysteresis", "kitchen.fridge", "OPEN",
			{"centre": Vector2(120.0, 300.0), "placement": "left"})
	if String(layer.call("get_placement")) != "above":
		failures.append("affordance: hysteresis: the side flipped %.2f s into the dwell window (now '%s')"
				% [0.05, layer.call("get_placement")])
	if not (layer.call("get_badge_centre") as Vector2).is_equal_approx(Vector2(400.0, 300.0)):
		failures.append("affordance: hysteresis: the badge moved before the dwell ran out")

	# The blink passes; the object simply moved a little on the SAME side --
	# that still tracks smoothly, dwell or no dwell.
	layer.set("_clock", 0.08)
	layer.call("_apply_placement_hysteresis", "kitchen.fridge", "OPEN",
			{"centre": Vector2(410.0, 300.0), "placement": "above"})
	if not (layer.call("get_badge_centre") as Vector2).is_equal_approx(Vector2(410.0, 300.0)):
		failures.append("affordance: hysteresis: a same-side move was not tracked")

	# The other side is wanted again, and this time it is sustained past the
	# dwell: the badge is finally allowed to move.
	layer.call("_apply_placement_hysteresis", "kitchen.fridge", "OPEN",
			{"centre": Vector2(120.0, 300.0), "placement": "left"})
	layer.set("_clock", 0.08 + LayerScript.PLACEMENT_DWELL_SEC + 0.02)
	layer.call("_apply_placement_hysteresis", "kitchen.fridge", "OPEN",
			{"centre": Vector2(120.0, 300.0), "placement": "left"})
	if String(layer.call("get_placement")) != "left":
		failures.append("affordance: hysteresis: the side never changed even after wanting to for longer than the dwell")
	if not (layer.call("get_badge_centre") as Vector2).is_equal_approx(Vector2(120.0, 300.0)):
		failures.append("affordance: hysteresis: the position did not follow once the dwell ran out")

	# A genuinely different target snaps at once rather than inheriting the old
	# target's dwell clock or position.
	layer.call("_apply_placement_hysteresis", "kitchen.doorToBathroom", "ENTER",
			{"centre": Vector2(900.0, 200.0), "placement": "below"})
	if String(layer.call("get_placement")) != "below":
		failures.append("affordance: hysteresis: a new target inherited the old one's dwell")
	if not (layer.call("get_badge_centre") as Vector2).is_equal_approx(Vector2(900.0, 200.0)):
		failures.append("affordance: hysteresis: a new target did not snap to its own position at once")

	layer.free()
	return failures


## -- Owner bug regressions: "picking up Bunny works intermittently" ------------
##
## A real caregiver and a real carryable child, wired the way
## `test_carry_bunny.gd` stages them -- these three need `perform_affordance()`
## to actually flip `is_carried()`, which a `FakeAffordable`'s scripted answer
## cannot stand in for.

func _carry_stage() -> Dictionary:
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
	aliz.position = Vector3.ZERO
	aliz.call("set_navigation_provider", NavigationProvider.new())

	var bunny: Node3D = ChildActorScript.new()
	bunny.name = "LittleBuddyChild"
	room.add_child(bunny)
	bunny.position = Vector3(0.0, 0.0, -0.5)
	bunny.call("build")

	var layer: Control = LayerScript.new()
	layer.call("build")
	layer.call("set_actor", aliz)
	layer.call("set_candidate_sources", [bunny])
	layer.call("step", 0.016)
	return {"room": room, "aliz": aliz, "bunny": bunny, "layer": layer}


func _release_carry_stage(stage: Dictionary) -> void:
	(stage["layer"] as Node).free()
	(stage["room"] as Node).free()


## One finger, one tap: `pointing/emulate_mouse_from_touch` delivers an
## `InputEventScreenTouch` AND a synthetic `InputEventMouseButton` at the same
## spot to whatever `Control` the finger landed on. Fed straight into the
## layer's hit box exactly as Godot would, this must carry Bunny up ONCE, not
## carry-then-immediately-place him back down.
func _test_touch_mouse_twin_does_not_double_perform():
	var failures: Array = []
	var stage: Dictionary = _carry_stage()
	var aliz: CharacterBody3D = stage["aliz"]
	var bunny: Node3D = stage["bunny"]
	var layer: Control = stage["layer"]

	var performed: Array = []
	layer.connect("affordance_performed", func(verb: String, id: String, handled: bool) -> void:
		performed.append([verb, id, handled]))

	if String(layer.call("get_current_verb")) != "CARRY":
		failures.append("precondition: the layer should offer CARRY on a free Bunny (got %s)"
				% str(layer.call("get_current_verb")))

	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(600.0, 400.0)
	layer.call("_on_hit_input", touch)

	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(601.0, 400.0)
	layer.call("_on_hit_input", mouse)

	if performed.size() != 1:
		failures.append("affordance: a touch/mouse twin fired affordance_performed %d times, not once"
				% performed.size())
	if not bool(bunny.call("is_carried")):
		failures.append("affordance: Bunny was not carried after the tap")
	for _i: int in range(60):
		aliz.call("step_movement", DT)
	if not bool(bunny.call("is_carried")):
		failures.append("affordance: Bunny was dropped again within 60 physics steps of being picked up")

	_release_carry_stage(stage)
	return failures


## Five presses 50 ms apart on the badge (no synthetic twin this time, just a
## fast finger): still one carry, not carry-place-carry-place-carry.
func _test_rapid_taps_carry_bunny_only_once():
	var failures: Array = []
	var stage: Dictionary = _carry_stage()
	var aliz: CharacterBody3D = stage["aliz"]
	var bunny: Node3D = stage["bunny"]
	var layer: Control = stage["layer"]

	var performed: Array = []
	layer.connect("affordance_performed", func(verb: String, id: String, handled: bool) -> void:
		performed.append([verb, id, handled]))

	for i: int in range(5):
		var touch := InputEventScreenTouch.new()
		touch.pressed = true
		touch.position = Vector2(600.0, 400.0)
		layer.call("_on_hit_input", touch)
		if i < 4:
			layer.call("step", 0.05)

	if performed.size() != 1:
		failures.append("affordance: five taps 50 ms apart fired affordance_performed %d times, not once"
				% performed.size())
	if not bool(bunny.call("is_carried")):
		failures.append("affordance: Bunny is not carried after five rapid taps")
	for _i: int in range(30):
		aliz.call("step_movement", DT)
	if not bool(bunny.call("is_carried")):
		failures.append("affordance: Bunny was dropped after the rapid-tap burst settled")

	_release_carry_stage(stage)
	return failures


## Carrying Bunny, a reachable surface's PLACE must outrank the floor put-down
## she is always offering on the child in her own arms; with nothing else in
## reach, his own put-down is still there as the fallback. Uses the REAL
## `child_actor.get_affordance()` while carried, not a scripted stand-in, so
## this regresses against `child_actor.gd`'s own priority, not just the rule.
func _test_carried_child_ranks_below_a_reachable_surface():
	var failures: Array = []
	var stage: Dictionary = _carry_stage()
	var aliz: CharacterBody3D = stage["aliz"]
	var bunny: Node3D = stage["bunny"]
	if not bool(aliz.call("carry_node", bunny, "carryFront")):
		failures.append("precondition: could not carry Bunny")
		_release_carry_stage(stage)
		return failures

	var own_place: Dictionary = bunny.call("get_affordance", aliz)
	if Rules.normalize_verb(own_place.get("verb", "")) != "PLACE":
		failures.append("precondition: carrying him he should offer PLACE, got %s" % str(own_place.get("verb")))
	own_place["verb"] = "PLACE"
	own_place["targetId"] = "bedroom.littleBuddy"
	var bed: Dictionary = {"verb": "PLACE", "anchor": Vector3(0.0, 0.4, -0.8), "radius": 1.6,
			"priority": Rules.PRIORITY_FURNITURE, "targetId": "bedroom.bed"}
	var facing_forward: Vector3 = Vector3(0.0, 0.0, -1.0)

	var with_bed: Dictionary = Rules.pick([own_place, bed], Vector3.ZERO, [], facing_forward)
	if String(with_bed.get("targetId", "")) != "bedroom.bed":
		failures.append("affordance: carrying him, a reachable bed lost to his own floor put-down (got %s)"
				% str(with_bed.get("targetId")))

	var alone: Dictionary = Rules.pick([own_place], Vector3.ZERO, [], facing_forward)
	if String(alone.get("targetId", "")) != "bedroom.littleBuddy":
		failures.append("affordance: with nothing else in reach, his own put-down should still be offered")

	_release_carry_stage(stage)
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
	if Rules.verb_for_target(bed) != Rules.VERB_SIT:
		failures.append("affordance: a bed offers '%s'; a seat says SIT" % Rules.verb_for_target(bed))
	# Bunny in her arms: every seat becomes a place to put HIM, and a basin a
	# place to wash him; a wardrobe has nothing for him.
	if Rules.verb_for_target(bed, {"carrying": "child"}) != Rules.VERB_PLACE:
		failures.append("affordance: carrying Bunny to the bed does not offer PLACE")
	var sink: Dictionary = {"isDoor": false, "supportedActions": ["wash", "brushTeeth"], "enabled": true}
	if Rules.verb_for_target(sink) != Rules.VERB_WASH:
		failures.append("affordance: a sink does not offer WASH")
	if Rules.verb_for_target(sink, {"carrying": "child"}) != Rules.VERB_WASH:
		failures.append("affordance: carrying Bunny to the sink does not offer WASH")
	var wardrobe: Dictionary = {"isDoor": false, "supportedActions": ["open", "dress"], "enabled": true}
	if not Rules.verb_for_target(wardrobe, {"carrying": "child"}).is_empty():
		failures.append("affordance: a wardrobe offers '%s' to a caregiver with Bunny in her arms"
				% Rules.verb_for_target(wardrobe, {"carrying": "child"}))
	# A loose prop in hand: an open box takes it, a shut one opens first, and
	# the table takes it too.
	if Rules.verb_for_target(toy_box, {"carrying": "item", "storage": {"isOpen": true, "canPlace": true}}) != Rules.VERB_PLACE:
		failures.append("affordance: carrying a toy to an open toy box does not offer PLACE")
	if Rules.verb_for_target(toy_box, {"carrying": "item", "storage": {"isOpen": false}}) != Rules.VERB_OPEN:
		failures.append("affordance: carrying a toy to a shut toy box does not offer OPEN first")
	var table: Dictionary = {"isDoor": false, "supportedActions": ["eat", "sit"], "enabled": true}
	if Rules.verb_for_target(table, {"carrying": "item", "station": {"opens": false, "isOpen": false, "inside": [], "on": "", "canPlace": false}}) != Rules.VERB_PLACE:
		failures.append("affordance: carrying a toy to the table does not offer PLACE")
	# Cooking: what is in the hand combines with what is on the counter.
	var cook: Dictionary = {"held": "bowl", "station": {"opens": false, "isOpen": false, "inside": [], "on": "bottle", "canPlace": true, "canCook": true}}
	if Rules.verb_for_target(counter, cook) != Rules.VERB_COOK:
		failures.append("affordance: a combining item at the counter does not offer COOK")
	# A locked door says SOON, kindly; an open one ENTER.
	if Rules.verb_for_target(door, {"door": {"locked": true}}) != Rules.VERB_SOON:
		failures.append("affordance: a locked door does not offer SOON")
	if Rules.label_for(Rules.VERB_SOON).find("grown-up") < 0:
		failures.append("affordance: SOON's label does not ask for a grown-up")
	if Rules.label_for(Rules.VERB_SOON).to_lower().find("pay") >= 0:
		failures.append("affordance: SOON's label talks about paying")

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
	if int(door_offer.get("priority", 0)) != Rules.PRIORITY_DOOR or int(offer.get("priority", 0)) != Rules.PRIORITY_FURNITURE:
		failures.append("affordance: door/furniture priorities are %s/%s; expected %d/%d"
				% [str(door_offer.get("priority")), str(offer.get("priority")), Rules.PRIORITY_DOOR, Rules.PRIORITY_FURNITURE])
	if Rules.PRIORITY_DOOR <= Rules.PRIORITY_PROP or Rules.PRIORITY_FURNITURE <= Rules.PRIORITY_PROP:
		failures.append("affordance: fixed targets do not sit in a band above loose props")

	if String((bed.call("get_affordance", actor) as Dictionary).get("verb", "")) != Rules.VERB_SIT:
		failures.append("affordance: a bed target offers '%s'; a seat says SIT"
				% str((bed.call("get_affordance", actor) as Dictionary).get("verb", "")))

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
	var door: FakeAffordable = _fake("kitchen.doorToBathroom", "ENTER", Vector3(1.4, 0.0, 0.0), 2.0, Rules.PRIORITY_DOOR)
	var fridge: FakeAffordable = _fake("kitchen.fridge", "OPEN", Vector3(0.6, 0.0, 0.0), 2.0, Rules.PRIORITY_FURNITURE)
	layer.call("set_candidate_sources", [door, fridge])

	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "ENTER":
		failures.append("affordance: the nearer fridge outranked the door (got %s)" % str(layer.call("get_current_verb")))
	layer.call("set_preferred_target_ids", ["kitchen.fridge"])
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "OPEN":
		failures.append("affordance: the mission's fridge did not win once preferred")
	layer.call("set_preferred_target_ids", [], true)
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "ENTER":
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

	# A target that handles its own tap keeps the router out of it. Stepped past
	# `PRESS_SEC` first: this is a second, later press, not the debounced twin
	# of the one just above (see `test_carry_bunny.gd`'s pick-up-then-put-down
	# case for that).
	fridge.handles = true
	layer.call("step", LayerScript.PRESS_SEC + 0.05)
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

	# Put the banana on the counter, take the bowl: bowl in hand over a banana
	# on the counter COMBINES, and the word for that is COOK.
	world.kitchen.call("place", "counter")
	world.kitchen.call("take", "counter", "bowl")
	actor.position = Vector3(-0.8, 0.0, -1.0)
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "COOK":
		failures.append("affordance: a bowl over the banana on the counter says %s, not COOK"
				% str(layer.call("get_current_verb")))

	world.free()
	return failures


## Bunny's own target advertises `pickUp`; the words for a person are HUG,
## CARRY and FEED, so the default context must turn that into HUG -- and into
## FEED once Aliz is holding something he will eat.
func _test_a_character_is_never_taken():
	var failures: Array = []
	var world: FakeWorld = FakeWorld.new()
	var actor: FakeActor = FakeActor.new()
	world.character = actor
	world.kitchen = KitchenState.new()
	var layer: Control = LayerScript.new()
	world.add_child(layer)
	layer.call("bind", world)
	var bunny: FakeChild = FakeChild.new()
	bunny.position = Vector3(0.5, 0.0, 0.0)
	var target: Area3D = _make_target("littleBuddy", "bedroom", ["talkTo", "comfort", "pickUp"], Vector3(0.66, 0.9, 0.66), Vector3.ZERO)
	bunny.add_child(target)
	world.add_child(bunny)
	layer.call("set_candidate_sources", [target])

	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "HUG":
		failures.append("affordance: Bunny's target offers %s; a character is hugged, never taken"
				% str(layer.call("get_current_verb")))
	world.kitchen.call("set_open", "fridge", true)
	world.kitchen.call("take", "fridge", "banana")
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "HUG":
		failures.append("affordance: a raw banana in hand should not offer FEED (got %s)" % str(layer.call("get_current_verb")))
	# Only finished food feeds him: `kitchen_rules.FEEDABLE`, not the empty bottle.
	var pantry: FakeKitchen = FakeKitchen.new()
	pantry.in_hand = "bottleOfMilk"
	world.kitchen = pantry
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "FEED":
		failures.append("affordance: holding the bottle of milk near Bunny should offer FEED (got %s)"
				% str(layer.call("get_current_verb")))
	world.free()
	return failures


## `place_badge()` is pure: the stick, Home and Next are rects, the object is a
## point, and the answer must never cover any of them.
func _test_badge_placement_avoids_keep_outs():
	var failures: Array = []
	var view: Vector2 = Vector2(1334.0, 750.0)
	var stick: Rect2 = Rect2(24.0, 300.0, 453.0, 434.0)
	var home: Rect2 = Rect2(1194.0, 26.0, 104.0, 104.0)
	var next: Rect2 = Rect2(1074.0, 624.0, 224.0, 92.0)
	var keep_outs: Array = [stick, home, next]

	# Room above: the badge goes above, and clears everything.
	var mid: Dictionary = LayerScript.place_badge(Vector2(667.0, 500.0), 60.0, view, 0.0, 600.0, keep_outs)
	if String(mid["placement"]) != "above":
		failures.append("affordance: with room above, the badge went %s" % str(mid["placement"]))
	failures.append_array(_clear_of(LayerScript.badge_footprint(mid["centre"]), keep_outs, "mid-room"))

	# The toy box, low-left, inside the stick's zone: above would sit in the
	# zone, so the badge must end up clear of it, on the side away from the edge.
	var toy_box: Dictionary = LayerScript.place_badge(Vector2(300.0, 520.0), 70.0, view, 0.0, 420.0, keep_outs)
	var toy_rect: Rect2 = LayerScript.badge_footprint(toy_box["centre"])
	failures.append_array(_clear_of(toy_rect, keep_outs, "toy box"))
	if toy_rect.position.x < stick.end.x and toy_rect.intersects(stick.grow(1.0)):
		failures.append("affordance: the toy box badge %s is inside the thumbstick zone %s" % [str(toy_rect), str(stick)])

	# A fridge high in the frame with the prompt band above it steps beside,
	# away from Aliz (who stands to its right).
	var fridge: Dictionary = LayerScript.place_badge(Vector2(880.0, 150.0), 60.0, view, 244.0, 900.0, keep_outs)
	if String(fridge["placement"]) != "left":
		failures.append("affordance: the fridge badge should step LEFT, away from Aliz (got %s)" % str(fridge["placement"]))
	if (fridge["centre"] as Vector2).y - LayerScript.BADGE_RADIUS < 244.0 - 0.01:
		failures.append("affordance: the fridge badge %s rises into the prompt band" % str(fridge["centre"]))

	# Bottom-right, under Next: the badge must not cover Next or Home.
	var stool: Dictionary = LayerScript.place_badge(Vector2(1200.0, 600.0), 50.0, view, 0.0, 1100.0, keep_outs)
	failures.append_array(_clear_of(LayerScript.badge_footprint(stool["centre"]), keep_outs, "stool"))

	# Everything on screen, always.
	for placed: Dictionary in [mid, toy_box, fridge, stool]:
		var rect: Rect2 = LayerScript.badge_footprint(placed["centre"])
		if not Rect2(Vector2.ZERO, view).encloses(rect):
			failures.append("affordance: badge %s leaves the %s screen" % [str(rect), str(view)])
	return failures


func _clear_of(rect: Rect2, keep_outs: Array, label: String):
	var failures: Array = []
	for blocked: Rect2 in keep_outs:
		if rect.intersects(blocked):
			failures.append("affordance: the %s badge %s covers keep-out %s" % [label, str(rect), str(blocked)])
	return failures


## The world may mount the layer itself; a visible care close-up beside it
## must silence it with no HUD in the loop at all.
func _test_a_visible_care_overlay_silences_the_layer():
	var failures: Array = []
	var ui: CanvasLayer = CanvasLayer.new()
	var layer: Control = LayerScript.new()
	ui.add_child(layer)
	layer.call("build")
	var actor: FakeActor = FakeActor.new()
	layer.call("set_actor", actor)
	var fridge: FakeAffordable = _fake("kitchen.fridge", "OPEN", Vector3(0.5, 0.0, 0.0), 2.0, 2)
	layer.call("set_candidate_sources", [fridge])
	var care: Control = Control.new()
	care.name = "CareOverlay"
	care.visible = false
	ui.add_child(care)

	layer.call("step", 0.016)
	if not bool(layer.call("is_showing")):
		failures.append("affordance: precondition -- a hidden CareOverlay should not silence the layer")
	care.visible = true
	layer.call("step", 0.016)
	if bool(layer.call("is_showing")):
		failures.append("affordance: the badge stays up under a visible CareOverlay")
	care.visible = false
	layer.call("step", 0.016)
	if not bool(layer.call("is_showing")):
		failures.append("affordance: the badge did not come back once the close-up closed")

	ui.free()
	fridge.free()
	actor.free()
	return failures


## A provider that speaks the contract in lowercase, as `spawned_object.gd`,
## `drop_zone.gd` and `child_actor.gd` do, and one that answers directly for
## the target it owns.
class FakeProviderOwner extends Node3D:
	var verb: String = "carry"

	func get_affordance(_actor: Node3D) -> Dictionary:
		return {"verb": verb, "anchor": SpatialUtil.world_position(self), "radius": 1.5, "priority": 3, "target": self}

	func perform_affordance(_actor: Node3D) -> bool:
		return true

	func get_need_bubble() -> Node3D:
		return null

	## As `child_actor.gd`: the semantic id lives on the target he carries.
	func get_activity_target() -> Node:
		return get_child(0) if get_child_count() > 0 else null


## Providers say "carry"; the badge says CARRY. Every spelling lands on one
## constant and an unknown word is dropped rather than drawn as a dot.
func _test_provider_verbs_are_normalised():
	var failures: Array = []
	for pair: Array in [["carry", "CARRY"], ["place", "PLACE"], ["take", "TAKE"], [" Hug ", "HUG"], ["ENTER", "ENTER"], ["quit", ""], ["", ""]]:
		var got: String = Rules.normalize_verb(pair[0])
		if got != String(pair[1]):
			failures.append("affordance: normalize_verb('%s') = '%s', expected '%s'" % [pair[0], got, pair[1]])

	var layer: Control = LayerScript.new()
	layer.call("build")
	var actor: FakeActor = FakeActor.new()
	layer.call("set_actor", actor)
	var toy: FakeAffordable = _fake("bedroom.blocks", "take", Vector3(0.4, 0.0, 0.0), 1.0, Rules.PRIORITY_PROP)
	var odd: FakeAffordable = _fake("bedroom.odd", "juggle", Vector3(0.2, 0.0, 0.0), 1.0, 9)
	layer.call("set_candidate_sources", [toy, odd])
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "TAKE":
		failures.append("affordance: a lowercase 'take' offer shows as '%s'" % str(layer.call("get_current_verb")))
	for verb: String in ["CARRY", "PLACE", "TAKE"]:
		if Palette.is_grey(Rules.verb_color(verb)):
			failures.append("affordance: %s has no colour of its own" % verb)

	# Bunny's own ActivityTarget stays quiet once Bunny answers for himself.
	var bunny: FakeProviderOwner = FakeProviderOwner.new()
	var target: Area3D = _make_target("littleBuddy", "bedroom", ["talkTo", "comfort", "pickUp"], Vector3(0.66, 0.9, 0.66), Vector3.ZERO)
	bunny.add_child(target)
	if not (target.call("get_affordance", actor) as Dictionary).is_empty():
		failures.append("affordance: a target whose owner is a provider still offers on its own")
	layer.call("set_candidate_sources", [bunny, target])
	layer.call("step", 0.016)
	if String(layer.call("get_current_verb")) != "CARRY":
		failures.append("affordance: Bunny's lowercase 'carry' shows as '%s'" % str(layer.call("get_current_verb")))
	if String(layer.call("get_current_target_id")) != "bedroom.littleBuddy":
		failures.append("affordance: Bunny's offer lost its semantic id (got '%s'); the mission could not prefer him"
				% str(layer.call("get_current_target_id")))

	layer.free()
	toy.free()
	odd.free()
	bunny.free()
	actor.free()
	return failures


## The QA frame: a banana by the kitchen door. The door is a room; it wins.
func _test_doors_outrank_loose_props():
	var failures: Array = []
	var banana: Dictionary = {"verb": "take", "anchor": Vector3(0.3, 0.0, 0.0), "radius": 1.0, "priority": 1, "targetId": "banana"}
	var door: Dictionary = {"verb": "ENTER", "anchor": Vector3(0.9, 0.0, 0.0), "radius": 1.8, "priority": Rules.PRIORITY_DOOR, "targetId": "kitchen.doorToLivingRoom"}
	var picked: Dictionary = Rules.pick([banana, door], Vector3.ZERO)
	if String(picked.get("verb", "")) != "ENTER":
		failures.append("affordance: a banana by the door won over ENTER (got %s)" % str(picked.get("verb")))
	# ...unless the banana is what the beat is about.
	picked = Rules.pick([banana, door], Vector3.ZERO, ["banana"])
	if String(picked.get("verb", "")) != "TAKE":
		failures.append("affordance: the mission's own banana did not outrank the door")
	return failures


## A character's bubble is a keep-out and his badge prefers beside/below.
func _test_a_character_badge_keeps_off_his_bubble():
	var failures: Array = []
	var view: Vector2 = Vector2(1334.0, 750.0)
	var head: Vector2 = Vector2(760.0, 420.0)
	# The bubble hangs above his head, right where "above" would put the badge.
	var bubble: Rect2 = Rect2(640.0, 190.0, 240.0, 60.0)
	var placed: Dictionary = LayerScript.place_badge(head, 60.0, view, 0.0, 600.0, [bubble], true)
	var rect: Rect2 = LayerScript.badge_footprint(placed["centre"])
	if rect.intersects(bubble):
		failures.append("affordance: the character badge %s covers his bubble %s" % [str(rect), str(bubble)])
	if String(placed["placement"]) == "above":
		failures.append("affordance: a character badge went above him first; beside/below come first for a person")
	if String(placed["placement"]) != "right":
		failures.append("affordance: with Aliz on his left the badge should step right (got %s)" % str(placed["placement"]))
	# Without the character flag the same geometry still keeps off the bubble.
	var plain: Dictionary = LayerScript.place_badge(head, 60.0, view, 0.0, 600.0, [bubble])
	if LayerScript.badge_footprint(plain["centre"]).intersects(bubble):
		failures.append("affordance: a non-character badge covers a keep-out that sits above the object")
	# A bubble-less target is not a character.
	if LayerScript.is_character_target(null):
		failures.append("affordance: null counted as a character")
	var owner_node: FakeProviderOwner = FakeProviderOwner.new()
	if not LayerScript.is_character_target(owner_node):
		failures.append("affordance: a node with get_need_bubble() was not treated as a character")
	owner_node.free()
	return failures


## Owner feedback (2026-09-20): the badge hid the thing it pointed at. The disc
## is 12.8 % of the viewport's height -- 96 px on the iPad frame -- the word is
## 22 px there, and the invisible hit box stays at the 240 px floor regardless.
func _test_badge_is_small_and_scales_with_the_screen():
	var failures: Array = []
	var ipad: float = LayerScript.badge_diameter(750.0)
	if absf(ipad - 96.0) > 1.0:
		failures.append("affordance: the disc is %.0f px on a 750 px tall frame; 96 px was asked for" % ipad)
	var phone: float = LayerScript.badge_diameter(1080.0)
	if absf(phone - 1080.0 * 0.128) > 1.5:
		failures.append("affordance: the disc is %.0f px at 1080 px tall; it should scale with the height" % phone)
	if phone <= ipad:
		failures.append("affordance: the badge does not grow with the viewport")
	if LayerScript.LABEL_FONT_SIZE != 22:
		failures.append("affordance: the pill text is %d px at the reference; 22 was asked for" % LayerScript.LABEL_FONT_SIZE)
	if LayerScript.HIT_SIZE < 200.0:
		failures.append("affordance: the hit box floor is %.0f px; it must stay 200 px or more" % LayerScript.HIT_SIZE)
	# The footprint at the reference is the picture plus the pill, no more.
	var footprint: Rect2 = LayerScript.badge_footprint(Vector2(400.0, 300.0))
	if footprint.size.x > 130.0 or footprint.size.y > 150.0:
		failures.append("affordance: the drawn footprint %s is bigger than a 96 px disc and a 30 px pill" % str(footprint))
	# A laid-out layer in a real viewport: the hit box covers the picture and is
	# never under the 240 px floor.
	var layer: Control = LayerScript.new()
	layer.call("build")
	layer.size = Vector2(1334.0, 750.0)
	var actor: FakeActor = FakeActor.new()
	layer.call("set_actor", actor)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 2.0, 4.0)
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	# A camera needs a viewport to unproject; without one the hit box hides and
	# that path is covered elsewhere. This asserts the pure sizing only.
	if absf(float(layer.call("current_scale")) - 1.0) > 0.01:
		failures.append("affordance: a 750 px tall layer does not sit at scale 1.0 (%.2f)"
				% float(layer.call("current_scale")))
	layer.free()
	actor.free()
	camera.free()
	return failures


## Aliz at the toy box's stand point, facing it, with the kitchen door a metre
## to her side and inside its own reach: the toy box she is looking at wins,
## door band or no door band. The mission's own target still beats both.
func _test_the_thing_she_faces_wins():
	var failures: Array = []
	var toy_box: Dictionary = {"verb": "OPEN", "anchor": Vector3(0.0, 0.2, -0.6), "radius": 1.5,
			"priority": Rules.PRIORITY_FURNITURE, "targetId": "bedroom.toyBox"}
	var door: Dictionary = {"verb": "ENTER", "anchor": Vector3(-1.2, 0.9, 0.4), "radius": 1.8,
			"priority": Rules.PRIORITY_DOOR, "targetId": "bedroom.doorToKitchen"}
	var facing_box: Vector3 = Vector3(0.0, 0.0, -1.0)
	var picked: Dictionary = Rules.pick([door, toy_box], Vector3.ZERO, [], facing_box)
	if String(picked.get("targetId", "")) != "bedroom.toyBox":
		failures.append("affordance: facing the toy box, the side door still won (%s)" % str(picked.get("targetId")))
	# Turned to face the door, the door wins again.
	picked = Rules.pick([door, toy_box], Vector3.ZERO, [], Vector3(-1.0, 0.0, 0.0))
	if String(picked.get("targetId", "")) != "bedroom.doorToKitchen":
		failures.append("affordance: facing the door, the toy box behind her won (%s)" % str(picked.get("targetId")))
	# No facing given: the bands decide, as before.
	picked = Rules.pick([door, toy_box], Vector3.ZERO)
	if String(picked.get("targetId", "")) != "bedroom.doorToKitchen":
		failures.append("affordance: with no facing the door band no longer wins")
	# The beat's target beats the facing bonus from any angle.
	picked = Rules.pick([door, toy_box], Vector3.ZERO, ["bedroom.doorToKitchen"], facing_box)
	if String(picked.get("targetId", "")) != "bedroom.doorToKitchen":
		failures.append("affordance: the mission's door lost to a toy box she happened to face")
	return failures
