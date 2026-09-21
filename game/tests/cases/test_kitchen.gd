extends RefCounted

## The interactive kitchen, asserted as RULES.
##
## The brief's demand is that "every action must have a visible result" and, more
## sharply, "do not implement inventory-only interactions while the world objects
## remain unchanged". A test cannot see a mesh move -- but it CAN prove the thing
## that makes the mesh move honest: that taking the banana removes it from the
## fridge, that the fridge must be opened first, and that combining replaces two
## items with one. If the model cheats, no amount of animation saves it.
##
## So this walks whole recipes, and after every step checks BOTH ends: what the
## hand holds and what the world no longer has.

const Items := preload("res://scripts/kitchen/kitchen_items.gd")
const Rules := preload("res://scripts/kitchen/kitchen_rules.gd")
const State := preload("res://scripts/kitchen/kitchen_state.gd")

const FRIDGE := Rules.STATION_FRIDGE
const COUNTER := Rules.STATION_COUNTER
const TABLE := Rules.STATION_TABLE


func test_name() -> String:
	return "kitchen"


func run():
	var failures: Array = []
	failures.append_array(_test_the_fridge_must_be_opened())
	failures.append_array(_test_taking_removes_it_from_the_world())
	failures.append_array(_test_one_hand_one_item())
	failures.append_array(_test_the_whole_food_recipe())
	failures.append_array(_test_the_milk_path())
	failures.append_array(_test_putting_things_away())
	failures.append_array(_test_nothing_is_ever_refused_rudely())
	failures.append_array(_test_every_item_is_the_shape_of_a_word())
	failures.append_array(_test_the_pantry_refills())
	return failures


func _test_the_fridge_must_be_opened():
	var failures: Array = []
	var kitchen: RefCounted = State.new()
	if kitchen.is_open(FRIDGE):
		failures.append("the fridge starts open; a closed door is the point of having one")
	var early: Dictionary = kitchen.take(FRIDGE, "banana")
	if bool(early["ok"]):
		failures.append("the banana came out of a SHUT fridge")
	if String(early["say"]).is_empty():
		failures.append("a refused take said nothing; a tap that does nothing and explains "
				+ "nothing is a dead end")
	var opened: Dictionary = kitchen.set_open(FRIDGE, true)
	if not bool(opened["ok"]) or not kitchen.is_open(FRIDGE):
		failures.append("the fridge would not open")
	if not bool(kitchen.take(FRIDGE, "banana")["ok"]):
		failures.append("the banana would not come out of an OPEN fridge")
	# And a station with no door refuses to be opened, rather than pretending.
	if bool(State.new().set_open(COUNTER, true)["ok"]):
		failures.append("the counter 'opened'; only stations with doors may")
	return failures


## The rule the brief is really asking for: the world must actually change.
func _test_taking_removes_it_from_the_world():
	var failures: Array = []
	var kitchen: RefCounted = State.new()
	kitchen.set_open(FRIDGE, true)
	if not kitchen.inside(FRIDGE).has("banana"):
		failures.append("the fridge does not start with a banana in it")
	kitchen.take(FRIDGE, "banana")
	if kitchen.inside(FRIDGE).has("banana"):
		failures.append("the banana is in Aliz's hand AND still in the fridge -- this is "
				+ "exactly the inventory-only interaction the brief forbids")
	if kitchen.held() != "banana":
		failures.append("the banana was removed from the fridge but is not in the hand")

	kitchen.place(COUNTER)
	if kitchen.held() != Items.NONE:
		failures.append("the banana is on the counter AND still held")
	if kitchen.on_station(COUNTER) != "banana":
		failures.append("the banana was put down but is not on the counter")
	return failures


func _test_one_hand_one_item():
	var failures: Array = []
	var kitchen: RefCounted = State.new()
	kitchen.set_open(FRIDGE, true)
	kitchen.take(FRIDGE, "banana")
	var second: Dictionary = kitchen.take(FRIDGE, "apple")
	if bool(second["ok"]):
		failures.append("Aliz picked up a second item with full hands")
	if kitchen.inside(FRIDGE).has("apple") == false:
		failures.append("the refused apple vanished from the fridge anyway")
	if not String(second["say"]).to_lower().contains("full"):
		failures.append("the refusal did not explain that her hands are full, got '%s'"
				% String(second["say"]))
	return failures


## Open fridge -> ingredient -> counter -> utensil -> combine -> transform ->
## serve. The whole of the brief's section 8, in one pass.
func _test_the_whole_food_recipe():
	var failures: Array = []
	var kitchen: RefCounted = State.new()
	var steps: Array = []

	kitchen.set_open(FRIDGE, true)
	steps.append(kitchen.take(FRIDGE, "banana"))
	steps.append(kitchen.place(COUNTER))
	steps.append(kitchen.take(COUNTER, "spoon"))
	var made: Dictionary = kitchen.place(COUNTER)
	steps.append(made)

	for i: int in range(steps.size()):
		if not bool((steps[i] as Dictionary)["ok"]):
			failures.append("recipe step %d failed: %s"
					% [i + 1, String((steps[i] as Dictionary)["say"])])

	if String(made.get("result", "")) != "mashedBanana":
		failures.append("banana + spoon made '%s', expected mashedBanana"
				% String(made.get("result", "")))
	if String(made.get("verb", "")) != "prepare":
		failures.append("combining reported verb '%s', expected 'prepare'"
				% String(made.get("verb", "")))
	if String(made.get("gesture", "")).is_empty():
		failures.append("preparing food opened no gesture, so the child only watched")
	# The two ingredients are GONE and one new thing is there.
	if kitchen.on_station(COUNTER) != "mashedBanana":
		failures.append("the counter holds '%s' after mashing, not the mashed banana"
				% kitchen.on_station(COUNTER))
	if kitchen.held() != Items.NONE:
		failures.append("the spoon is still in hand after it was used up in the dish")

	# Serve it, then feed it.
	kitchen.take(COUNTER, "mashedBanana")
	var served: Dictionary = kitchen.place(TABLE)
	if not bool(served["ok"]) or String(served["verb"]) != "serve":
		failures.append("the finished food could not be served at the table")
	kitchen.take(TABLE, "mashedBanana")
	var fed: Dictionary = kitchen.give_to_bunny()
	if not bool(fed["ok"]):
		failures.append("Bunny would not eat the mashed banana: %s" % String(fed["say"]))
	if kitchen.held() != Items.NONE:
		failures.append("the food was given to Bunny but is still in Aliz's hand")
	return failures


## Mission 01's own path, through the same system, so the two are not two systems.
func _test_the_milk_path():
	var failures: Array = []
	var kitchen: RefCounted = State.new()
	kitchen.set_open(FRIDGE, true)
	if not bool(kitchen.take(FRIDGE, "bottle")["ok"]):
		failures.append("the bottle is not in the fridge to be found")
	kitchen.place(COUNTER)
	kitchen.take(COUNTER, "bowl")
	var made: Dictionary = kitchen.place(COUNTER)
	if String(made.get("result", "")) != "bottleOfMilk":
		failures.append("preparing the bottle made '%s', expected bottleOfMilk"
				% String(made.get("result", "")))
	if String(made.get("gesture", "")) != "prepareMilk":
		failures.append("the milk must open the EXISTING prepareMilk gesture, got '%s'"
				% String(made.get("gesture", "")))
	kitchen.take(COUNTER, "bottleOfMilk")
	if not bool(kitchen.give_to_bunny()["ok"]):
		failures.append("Bunny would not take the prepared bottle")
	return failures


func _test_putting_things_away():
	var failures: Array = []
	var kitchen: RefCounted = State.new()
	kitchen.set_open(FRIDGE, true)
	kitchen.take(FRIDGE, "apple")
	var away: Dictionary = kitchen.place(FRIDGE)
	if not bool(away["ok"]) or String(away["verb"]) != "putAway":
		failures.append("the apple could not be put back in the fridge")
	if not kitchen.inside(FRIDGE).has("apple"):
		failures.append("the apple was put away but is not back inside the fridge")
	if kitchen.held() != Items.NONE:
		failures.append("the apple was put away and is somehow still held")
	return failures


## `CLAUDE.md`: no red X, no failure language. A refusal is guidance.
func _test_nothing_is_ever_refused_rudely():
	var failures: Array = []
	var banned: Array = ["wrong", "no!", "fail", "bad", "can't", "cannot", "error", "invalid"]
	var kitchen: RefCounted = State.new()
	var refusals: Array = [
		kitchen.take(FRIDGE, "banana"),          # shut door
		kitchen.give_to_bunny(),                 # empty hands
		kitchen.place(COUNTER),                  # empty hands
	]
	kitchen.set_open(FRIDGE, true)
	kitchen.take(FRIDGE, "banana")
	refusals.append(kitchen.take(FRIDGE, "apple"))   # full hands
	refusals.append(kitchen.give_to_bunny())         # Bunny does not eat a raw banana

	for refusal: Variant in refusals:
		var say: String = String((refusal as Dictionary)["say"])
		if say.strip_edges().is_empty():
			failures.append("a refusal ('%s') said nothing at all"
					% String((refusal as Dictionary)["verb"]))
			continue
		for word: String in banned:
			if say.to_lower().contains(word):
				failures.append("refusal '%s' uses failure language ('%s')" % [say, word])
	return failures


## `assets_models`: every object is the shape of a word.
func _test_every_item_is_the_shape_of_a_word():
	var failures: Array = []
	for item_id: Variant in Items.ids():
		var id: String = String(item_id)
		if Items.word_for(id).strip_edges().is_empty():
			failures.append("item '%s' teaches no English word" % id)
		if Items.thai_for(id).strip_edges().is_empty():
			failures.append("item '%s' has no Thai hint" % id)
		if Items.size_for(id) <= 0.0:
			failures.append("item '%s' has no size, so it cannot be drawn" % id)
	# Every combination must produce a real item, or the kitchen promises a dish
	# it cannot make.
	for key: Variant in Rules.COMBINATIONS.keys():
		var result: String = String(Rules.COMBINATIONS[key])
		if not Items.exists(result):
			failures.append("combination '%s' makes '%s', which is not an item"
					% [String(key), result])
	for item_id: Variant in Rules.FEEDABLE:
		if not Items.exists(String(item_id)):
			failures.append("Bunny can be fed '%s', which is not an item" % String(item_id))
	return failures


## Free Play's replay rule: after Bunny has eaten, every raw ingredient the meal
## used up is back where it started the day -- and nothing that is still in the
## kitchen is duplicated.
func _test_the_pantry_refills():
	var failures: Array = []
	var kitchen: RefCounted = State.new()
	kitchen.set_open("fridge", true)
	kitchen.take("fridge", "bottle")
	kitchen.place("counter")
	kitchen.take("counter", "bowl")
	kitchen.place("counter")
	kitchen.take("counter", "bottleOfMilk")
	if not bool(kitchen.give_to_bunny().get("ok", false)):
		return ["restock: precondition -- could not feed the milk"]
	var back: Array = kitchen.restock()
	var ids: Array = []
	for row: Dictionary in back:
		ids.append("%s/%s" % [row["station"], row["item"]])
	ids.sort()
	if ids != ["counter/bowl", "fridge/bottle"]:
		failures.append("restock: expected the bottle and the bowl back, got %s" % str(ids))
	if not (kitchen.inside("fridge") as Array).has("bottle") or not (kitchen.inside("counter") as Array).has("bowl"):
		failures.append("restock: the returned items are not inside their stations")
	if (kitchen.inside("fridge") as Array).count("banana") != 1 or (kitchen.inside("counter") as Array).count("spoon") != 1:
		failures.append("restock: items that never left were duplicated (%s / %s)" % [kitchen.inside("fridge"), kitchen.inside("counter")])
	# A second restock with nothing missing returns nothing.
	if not kitchen.restock().is_empty():
		failures.append("restock: a full kitchen restocked something")
	# An ingredient that is merely in her hand or on the counter is not missing.
	kitchen.take("fridge", "apple")
	if not kitchen.restock().is_empty():
		failures.append("restock: the apple in her hand was treated as gone")
	return failures
