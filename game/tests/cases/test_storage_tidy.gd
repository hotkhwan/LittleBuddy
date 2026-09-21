extends RefCounted

## Storage and the tidy activity: the rules a cabinet obeys.
##
## What is worth pinning here is not "does an array append" -- it is the handful
## of decisions that make this a children's game rather than an inventory system:
##
##   1. **A refusal is always a redirection.** Dropping a shirt on a closed
##      wardrobe, a full one, and the toy box are three different situations and
##      each gets its own gentle sentence. None of them says no, wrong or fail.
##   2. **The reason is the most USEFUL one.** Aiming at the wrong cabinet is
##      reported before "it is closed", because opening it would not have helped.
##   3. **Semantic ids and tags, never node paths.** A new drawer must be a row
##      of data. If this file can be satisfied without a scene, so can a cabinet.
##   4. **Child-sized.** Three to six items, clamped, whatever is asked for.
##   5. **Praise does not repeat six times.** "Great!" said identically six times
##      stops being praise.

const Storage := preload("res://scripts/gameplay/storage_model.gd")
const Tidy := preload("res://scripts/gameplay/tidy_plan.gd")

## Words a children's game must never say about a misplaced toy.
const BANNED: Array[String] = ["wrong", "no.", "incorrect", "fail", "bad", "error"]


func test_name() -> String:
	return "storage_tidy"


func run():
	var failures: Array = []
	failures.append_array(_test_a_cabinet_obeys_its_tags())
	failures.append_array(_test_refusal_reasons_are_ordered_by_usefulness())
	failures.append_array(_test_nothing_reads_as_a_failure())
	failures.append_array(_test_capacity_and_open_state())
	failures.append_array(_test_the_plan_is_child_sized())
	failures.append_array(_test_a_full_tidy_completes())
	failures.append_array(_test_it_is_data_not_code())
	failures.append_array(_test_a_plan_for_one_box())
	return failures


func _toy_box() -> RefCounted:
	var box: RefCounted = Storage.create("bedroom.toyBox", ["toy"], 3)
	box.call("open")
	return box


func _test_a_cabinet_obeys_its_tags():
	var failures: Array = []
	var box: RefCounted = _toy_box()
	if not bool(box.call("can_store", "teddy", ["toy"])):
		failures.append("an open toy box refused a toy")
	if bool(box.call("can_store", "shirt", ["clothes"])):
		failures.append("the toy box accepted a shirt; tags are the whole point")
	# an empty tag list means "takes anything" -- the generic shelf case
	var shelf: RefCounted = Storage.create("livingRoom.shelf", [], 4)
	shelf.call("open")
	if not bool(shelf.call("can_store", "anything", ["mystery"])):
		failures.append("a storage with no tag filter should accept anything")
	return failures


func _test_refusal_reasons_are_ordered_by_usefulness():
	var failures: Array = []
	# closed AND wrong place -> must report the wrong place, because opening it
	# would not have helped.
	var box: RefCounted = Storage.create("bedroom.toyBox", ["toy"], 3)
	var reason: String = String(box.call("why_refused", "shirt", ["clothes"]))
	if reason != Storage.REFUSED_WRONG_PLACE:
		failures.append(("a closed cabinet that is ALSO the wrong place must report the wrong "
				+ "place first -- 'open it' would send the child to open a cabinet that still "
				+ "will not take it. Got '%s'") % reason)

	# right place but shut -> "closed", which IS actionable
	var shut: String = String(box.call("why_refused", "teddy", ["toy"]))
	if shut != Storage.REFUSED_CLOSED:
		failures.append("a shut toy box should report 'closed' for a toy, got '%s'" % shut)

	# already inside -> its own reason, not "full" and not "wrong"
	var open_box: RefCounted = _toy_box()
	open_box.call("store", "teddy", ["toy"])
	if String(open_box.call("why_refused", "teddy", ["toy"])) != Storage.REFUSED_ALREADY:
		failures.append("an item already inside should say so rather than be re-stored")
	if int(open_box.call("count")) != 1:
		failures.append("storing the same item twice changed the count")
	return failures


func _test_nothing_reads_as_a_failure():
	var failures: Array = []
	for reason: String in [Storage.REFUSED_CLOSED, Storage.REFUSED_FULL,
			Storage.REFUSED_WRONG_PLACE, Storage.REFUSED_ALREADY]:
		var line: String = Tidy.refusal_line(reason, "wardrobe")
		if line.strip_edges().is_empty():
			failures.append("refusal '%s' has no sentence; silence is the worst answer" % reason)
		for banned: String in BANNED:
			if line.to_lower().contains(banned):
				failures.append("refusal '%s' says '%s' in \"%s\"; a misplaced toy is never a "
						% [reason, banned, line] + "failure in this game")
	# and the closed line must name the thing to open, or it is not actionable
	if not Tidy.refusal_line(Storage.REFUSED_CLOSED, "wardrobe").to_lower().contains("wardrobe"):
		failures.append("the 'closed' line should name what to open")
	return failures


func _test_capacity_and_open_state():
	var failures: Array = []
	var box: RefCounted = _toy_box()  # capacity 3
	box.call("store", "a", ["toy"])
	box.call("store", "b", ["toy"])
	box.call("store", "c", ["toy"])
	if not bool(box.call("is_full")):
		failures.append("a 3-capacity box holding 3 is not reporting full")
	if String(box.call("why_refused", "d", ["toy"])) != Storage.REFUSED_FULL:
		failures.append("a full box should say full")
	if not bool(box.call("remove", "a")):
		failures.append("remove() failed for an item that is inside")
	if bool(box.call("remove", "zzz")):
		failures.append("remove() claimed success for an item that was never inside")
	if bool(box.call("is_full")):
		failures.append("the box is still full after one item came out")

	# closing does not empty it
	box.call("close")
	if int(box.call("count")) != 2:
		failures.append("closing a cabinet lost its contents")
	if bool(box.call("toggle")) != true:
		failures.append("toggle() on a closed cabinet should open it and report true")
	return failures


func _test_the_plan_is_child_sized():
	var failures: Array = []
	for asked: int in [0, 1, 3, 5, 6, 12]:
		var plan: RefCounted = Tidy.build(asked, 7)
		var got: int = int(plan.call("total"))
		if got < Tidy.MIN_ITEMS or got > Tidy.MAX_ITEMS:
			failures.append(("asking for %d items produced %d; the activity must stay between "
					+ "%d and %d or it stops being a game and becomes chores")
					% [asked, got, Tidy.MIN_ITEMS, Tidy.MAX_ITEMS])
	# deterministic for a given seed, so a room can be handed out twice
	var a: Array = Tidy.build(4, 99).get("items")
	var b: Array = Tidy.build(4, 99).get("items")
	if str(a) != str(b):
		failures.append("the same seed produced two different plans")
	return failures


func _test_a_full_tidy_completes():
	var failures: Array = []
	var plan: RefCounted = Tidy.build(3, 5)
	# one storage per tag, all open, roomy
	var boxes: Dictionary = {
		"toy": Storage.create("room.toyBox", ["toy"], 9),
		"book": Storage.create("room.shelf", ["book"], 9),
		"clothes": Storage.create("room.wardrobe", ["clothes"], 9),
	}
	for key: String in boxes.keys():
		boxes[key].call("open")

	var said: Array = []
	var guard: int = 0
	while not bool(plan.call("is_complete")) and guard < 20:
		guard += 1
		var row: Dictionary = plan.call("next_item")
		if row.is_empty():
			break
		var item_id: String = String(row["itemId"])
		var tag: String = String((row["tags"] as Array)[0])
		var result: Dictionary = plan.call("place", item_id, boxes[tag], "box")
		if not bool(result["accepted"]):
			failures.append("placing '%s' in the right box was refused: %s"
					% [item_id, String(result["reason"])])
			break
		said.append(String(result["say"]))

	if not bool(plan.call("is_complete")):
		failures.append("a correctly-played tidy did not complete (%d left)"
				% int(plan.call("remaining")))
	if not said.is_empty() and not said[said.size() - 1].to_lower().contains("tidy"):
		failures.append("the last thing said should celebrate the room being tidy, got '%s'"
				% said[said.size() - 1])
	# praise must vary
	if said.size() >= 3 and said[0] == said[1]:
		failures.append("praise repeated verbatim ('%s'); identical praise stops reading as praise"
				% said[0])
	return failures


func _test_it_is_data_not_code():
	var failures: Array = []
	# A storage must be constructible from a plain content row, with no scene.
	var built: RefCounted = Storage.from_dict({
		"storageId": "kitchen.drawer",
		"acceptedItemTags": ["cutlery"],
		"capacity": 2,
	})
	var described: Dictionary = built.call("describe")
	if String(described["storageId"]) != "kitchen.drawer":
		failures.append("from_dict() lost the storageId")
	if int(described["capacity"]) != 2:
		failures.append("from_dict() lost the capacity")
	if not (described["acceptedItemTags"] as Array).has("cutlery"):
		failures.append("from_dict() lost the accepted tags")
	# camelCase keys, per CLAUDE.md
	for key: String in ["storageId", "acceptedItemTags", "capacity", "isOpen", "storedItems"]:
		if not described.has(key):
			failures.append("describe() is missing the camelCase key '%s'" % key)

	# the vocabulary the brief asks this activity to teach
	for word: String in ["toy", "book", "shirt", "open", "close", "put away", "clean up"]:
		if not Tidy.WORDS.has(word):
			failures.append("the tidy activity no longer teaches '%s'" % word)
	return failures


## The house tidies ONE box at a time: the plan takes only what that box will
## accept, never something already on the floor, as few as one when the box is
## nearly full -- and keeps score for a storage that stores the real node itself.
func _test_a_plan_for_one_box():
	var failures: Array = []
	var plan: RefCounted = Tidy.build_for(["toy"], 4, 3, ["teddy"])
	if int(plan.call("total")) != 4:
		failures.append("build_for: asked for 4 toys, got %d" % plan.call("total"))
	for row: Dictionary in plan.get("items"):
		if not (row["tags"] as Array).has("toy"):
			failures.append("build_for: '%s' is not a toy and the toy box will not take it" % row["itemId"])
		if String(row["itemId"]) == "teddy":
			failures.append("build_for: the excluded teddy was picked")
	var two: RefCounted = Tidy.build_for(["toy"], 2, 3)
	if int(two.call("total")) != 2:
		failures.append("build_for: a box with two free slots should get a tidy of two, got %d" % two.call("total"))
	if int(Tidy.build_for(["toy"], 0, 3).call("total")) != 1:
		failures.append("build_for: a count below one should still be one toy")
	if int(Tidy.build_for(["cutlery"], 3, 3).call("total")) != 0:
		failures.append("build_for: a box that takes nothing this plan knows should get an empty plan")
	if Tidy.build_for(["toy"], 3, 11).get("items") != Tidy.build_for(["toy"], 3, 11).get("items"):
		failures.append("build_for: the same seed should give the same plan")

	# Keeping score without a storage: praise by rotation, then the tidy line.
	var ids: Array = []
	for row: Dictionary in plan.get("items"):
		ids.append(String(row["itemId"]))
	var said: Array = []
	for id: String in ids:
		var result: Dictionary = plan.call("record_placed", id)
		if not bool(result["recorded"]):
			failures.append("record_placed: '%s' was in the plan and was not recorded" % id)
		said.append(String(result["say"]))
	if not bool(plan.call("is_complete")):
		failures.append("record_placed: recording every toy did not complete the plan")
	if not said[-1].to_lower().contains("tidy"):
		failures.append("record_placed: the last line should celebrate, got '%s'" % said[-1])
	if said[0] == said[1]:
		failures.append("record_placed: praise repeated verbatim ('%s')" % said[0])
	if bool(plan.call("record_placed", "pillow")["recorded"]):
		failures.append("record_placed: a thing the plan never scattered was recorded")
	if not bool(plan.call("unplace", ids[0])) or bool(plan.call("is_complete")):
		failures.append("unplace: taking a toy back out should reopen the plan")
	if bool(plan.call("unplace", "pillow")):
		failures.append("unplace: an id that was never placed claimed success")
	return failures
