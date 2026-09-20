extends RefCounted

## The highchair minigame, driven end to end through the REAL `MissionRunner`
## and the REAL `FollowInstructionMode`, with the REAL content library's tasks.
##
## Every gesture below is the programmatic twin of a finger on the stage:
## `begin_drag()` / `drag_to_mouth()` / `end_drag()` / `tap_item()` /
## `advance_hold()` / `nudge()`. The stage runs in instant mode (animations
## collapse to calls) and the runner stays OUT of the tree (its task gap
## collapses to a call), so a whole task plays synchronously.
##
## What this file protects:
##   - each gesture completes its task EXACTLY once, through the runner;
##   - a wrong item halves the task, a second one switches to guided mode, and
##     the delivery after that completes the task for 0 stars (the honest
##     integer behind the half star -- see feeding_rules.gd);
##   - the touch fallback completes a task without a single drag;
##   - the reward ledger pays once, whatever the stage re-emits;
##   - the routing: exactly the four drag-to-mouth foods, nothing else.

const FEEDING_TABLE_SCENE: String = "res://scenes/feeding/feeding_table.tscn"
const SESSION_SUMMARY_SCENE: String = "res://scenes/progression/session_summary.tscn"
const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const RewardManagerScript := preload("res://scripts/rewards/reward_manager.gd")
const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const Rules := preload("res://scripts/feeding/feeding_rules.gd")
const RatingStar := preload("res://scripts/ui/rating_star.gd")


## Serves the runner exactly one mission built from real tasks.
class StubLibrary extends RefCounted:
	var real: RefCounted = null
	var tasks: Array = []

	func get_mission(_mission_id: String) -> Dictionary:
		return {"missionId": "stub", "category": "feeding", "introPhrase": ""}

	func get_mission_tasks(_mission_id: String) -> Array:
		return tasks.duplicate(true)

	func has_object(object_id: String) -> bool:
		return real.has_object(object_id)

	func get_object(object_id: String) -> Dictionary:
		return real.get_object(object_id)

	func get_objects() -> Array:
		return real.get_objects()

	func get_objects_in_category(category: String) -> Array:
		return real.get_objects_in_category(category)


class StubSave extends RefCounted:
	var stars: int = 0
	var completed: Array = []

	func get_stars() -> int:
		return stars

	func add_stars(amount: int) -> int:
		stars += amount
		return stars

	func mark_activity_completed(activity_id: String) -> void:
		completed.append(activity_id)


## One wired-up play: runner + stage + reward manager, recording every signal.
class Rig extends RefCounted:
	var runner: Node = null
	var table: Node3D = null
	var manager: Node = null
	var save: StubSave = StubSave.new()
	var completed: Array = []
	var half_stars: Array = []
	var guided: Array = []
	var finished: bool = false

	func on_task_started(_task_id: String, _mode: String) -> void:
		var task: Dictionary = runner.call("get_current_task")
		table.call("set_task", task, String(task.get("objectId", "")), String(task.get("thaiHint", "")))

	func on_task_completed(task_id: String, stars: int) -> void:
		completed.append([task_id, stars])
		manager.call("award", task_id, stars)

	func on_half_star(task_id: String) -> void:
		half_stars.append(task_id)

	func on_guided(task_id: String) -> void:
		guided.append(task_id)

	func on_mission_completed(_mission_id: String, _stars: int) -> void:
		finished = true

	func free_all() -> void:
		if runner != null:
			runner.call("cancel")
			runner.free()
		if manager != null:
			manager.free()
		if table != null:
			if table.is_inside_tree():
				table.get_parent().remove_child(table)
			table.free()


func test_name() -> String:
	return "feeding_table"


func run():
	var failures: Array = []
	var root: Node = _root()
	if root == null:
		return ["feeding_table: no SceneTree root available"]
	var library: RefCounted = ContentLibraryScript.create()
	if library == null:
		return ["feeding_table: could not load the content library"]

	failures.append_array(_test_routing(library))
	failures.append_array(_test_rules())
	failures.append_array(_test_prompt_binding(root))
	failures.append_array(_test_apple_drag_completes_once(root, library))
	failures.append_array(_test_banana_peels_then_completes_once(root, library))
	failures.append_array(_test_water_hold_completes_once(root, library))
	failures.append_array(_test_wrong_item_halves_then_guides(root, library))
	failures.append_array(_test_tap_help_completes_without_a_drag(root, library))
	failures.append_array(_test_no_double_reward(root, library))
	failures.append_array(_test_handler_credit_only_halves_on_external_stage(library))
	failures.append_array(_test_half_star_contract())
	failures.append_array(_test_summary_shows_almost(root))
	return failures


## The summary's "almost" row: one half star per halved task, capped, hidden
## when there were none, and never counted as an earned star.
func _test_summary_shows_almost(root: Node):
	var failures: Array = []
	var packed: PackedScene = load(SESSION_SUMMARY_SCENE) as PackedScene
	if packed == null:
		return ["feeding_table: %s will not load" % SESSION_SUMMARY_SCENE]
	var screen: Control = packed.instantiate() as Control
	root.add_child(screen)

	screen.call("show_summary", 2, 20, [], {"levelTitle": "Milk Time", "levelStars": 1, "bestStars": 1, "hasNextLevel": true, "almostStars": 2})
	var row: Control = screen.get_node_or_null("%AlmostRow") as Control
	if row == null or not row.visible:
		failures.append("feeding_table: the summary hides the almost row after two halved tasks")
	if int(screen.call("get_almost_count")) != 2:
		failures.append("feeding_table: the summary shows %d half stars, expected 2" % screen.call("get_almost_count"))
	var star: CanvasItem = screen.get_node_or_null("%AlmostStar1") as CanvasItem
	if star != null and (star.get("tint") as Color).a >= 1.0:
		failures.append("feeding_table: a half star on the summary must not read as an earned star")
	var label: Label = screen.get_node_or_null("%AlmostLabel") as Label
	if label != null:
		for banned: String in ["wrong", "miss", "fail", "%", "lost"]:
			if label.text.to_lower().contains(banned):
				failures.append("feeding_table: the almost line '%s' is a report card" % label.text)
	# Filled level stars are unaffected by the almost row.
	var filled: int = 0
	for index: int in range(1, 4):
		var rating: CanvasItem = screen.get_node_or_null("%%RatingStar%d" % index) as CanvasItem
		if rating != null and (rating.get("tint") as Color).a >= 0.99:
			filled += 1
	if filled != 1:
		failures.append("feeding_table: the almost row changed the level rating (%d filled, expected 1)" % filled)

	screen.call("reset")
	screen.call("show_summary", 3, 23, [])
	if row != null and row.visible:
		failures.append("feeding_table: the almost row is still up on a clean run")
	if int(screen.call("get_almost_count")) != 0:
		failures.append("feeding_table: a clean run shows half stars")

	root.remove_child(screen)
	screen.free()
	return failures


# ---------------------------------------------------------------------------
# Routing and rules
# ---------------------------------------------------------------------------

func _test_routing(library: RefCounted):
	var failures: Array = []
	for task_id: String in ["feedApple", "feedBanana", "feedMilk", "feedWater"]:
		if not Rules.handles_task(library.get_task(task_id)):
			failures.append("feeding_table: %s should play on the highchair" % task_id)
	for task_id: String in ["findBowl", "sayMilk", "findSpoon", "sayBanana", "wearRedShirt", "giveTeddy"]:
		if library.has_task(task_id) and Rules.handles_task(library.get_task(task_id)):
			failures.append("feeding_table: %s must stay in the room, not the highchair" % task_id)
	if Rules.handles_task(null) or Rules.handles_task({}):
		failures.append("feeding_table: a missing task must not be routed to the highchair")
	return failures


func _test_rules():
	var failures: Array = []
	if Rules.credit_for_mistakes(0) != Rules.CREDIT_FULL:
		failures.append("feeding_table: no mistakes must be full credit")
	if Rules.credit_for_mistakes(1) != Rules.CREDIT_HALF:
		failures.append("feeding_table: one mistake must be half credit")
	if Rules.credit_for_mistakes(2) != Rules.CREDIT_GUIDED or not Rules.is_guided(5):
		failures.append("feeding_table: two mistakes must switch to guided mode, and stay there")
	if Rules.stars_for_credit(Rules.CREDIT_FULL, 1) != 1:
		failures.append("feeding_table: full credit pays the task's reward")
	if Rules.stars_for_credit(Rules.CREDIT_HALF, 1) != 0 or Rules.stars_for_credit(Rules.CREDIT_GUIDED, 1) != 0:
		failures.append("feeding_table: a halved task pays 0 -- there is no fractional star to pay")
	for target: String in Rules.HANDLED_ITEMS:
		var ids: Array = Rules.tray_item_ids(target)
		if not ids.has(target):
			failures.append("feeding_table: the tray for %s does not include %s" % [target, target])
		if ids.size() != 3:
			failures.append("feeding_table: the tray for %s holds %d items, expected 3" % [target, ids.size()])
	if Rules.try_phrase("apple") != "Try the apple!":
		failures.append("feeding_table: the wrong-item phrase must point at the right item")
	for phrase: String in [Rules.try_phrase("apple"), Rules.PEEL_HINT, Rules.TAP_HELP_HINT, Rules.SUCCESS_PHRASE]:
		for banned: String in ["wrong", "no!", "fail", "oops", "%"]:
			if phrase.to_lower().contains(banned):
				failures.append("feeding_table: '%s' is not kind enough for a child" % phrase)
	if Rules.mouth_radius_px(750.0) < 89.0 or Rules.mouth_radius_px(750.0) > 91.0:
		failures.append("feeding_table: the mouth target should be ~90 px on a 750-high frame")
	return failures


func _test_prompt_binding(root: Node):
	var failures: Array = []
	var table: Node3D = _make_table(root, failures)
	if table == null:
		return failures
	table.call("set_prompt", "Give the baby the apple.", "ป้อนแอปเปิลให้น้อง")
	var hud: Node = table.call("get_hud")
	if String(hud.call("get_prompt")) != "Give the baby the apple.":
		failures.append("feeding_table: set_prompt() did not reach the English line")
	if String(hud.call("get_helper")) != "ป้อนแอปเปิลให้น้อง":
		failures.append("feeding_table: set_prompt() did not reach the helper line")
	if hud.call("get_home_button") == null or hud.call("get_back_button") == null:
		failures.append("feeding_table: the stage must have Home and Back buttons")
	root.remove_child(table)
	table.free()
	return failures


# ---------------------------------------------------------------------------
# Gestures, each through the runner
# ---------------------------------------------------------------------------

func _test_apple_drag_completes_once(root: Node, library: RefCounted):
	var failures: Array = []
	var rig: Rig = _rig(root, library, ["feedApple"], failures)
	if rig == null:
		return failures
	var table: Node3D = rig.table

	if String(table.call("get_target_id")) != "apple":
		failures.append("feeding_table: apple task did not mark the apple as the target")
	if not bool(table.call("begin_drag", "apple")):
		failures.append("feeding_table: the apple could not be picked up")
	if not bool(table.call("is_dragging")):
		failures.append("feeding_table: begin_drag() did not start a drag")
	table.call("drag_to_mouth")

	if rig.completed != [["feedApple", 1]]:
		failures.append("feeding_table: dragging the apple to the mouth completed %s, expected [[feedApple, 1]]" % str(rig.completed))
	if not bool(table.call("is_delivered")) or not bool(table.call("is_task_finished")):
		failures.append("feeding_table: the stage does not report the apple as delivered")
	if String(table.call("get_bunny_face")) not in ["delighted", ""]:
		failures.append("feeding_table: Bunny should look delighted after eating, not '%s'" % table.call("get_bunny_face"))

	# Mashing afterwards changes nothing.
	table.call("begin_drag", "apple")
	table.call("drag_to_mouth")
	table.call("tap_item", "apple")
	if rig.completed.size() != 1:
		failures.append("feeding_table: the apple task completed %d times" % rig.completed.size())
	if not rig.finished:
		failures.append("feeding_table: the one-task mission did not finish")
	rig.free_all()
	return failures


func _test_banana_peels_then_completes_once(root: Node, library: RefCounted):
	var failures: Array = []
	var rig: Rig = _rig(root, library, ["feedBanana"], failures)
	if rig == null:
		return failures
	var table: Node3D = rig.table
	var hud: Node = table.call("get_hud")

	if bool(table.call("is_peeled", "banana")):
		failures.append("feeding_table: the banana is served already peeled")
	if not bool(hud.call("is_hint_visible")) or String(hud.call("get_hint_text")) != Rules.PEEL_HINT:
		failures.append("feeding_table: the banana task should open with the '%s' hint" % Rules.PEEL_HINT)
	if bool(table.call("begin_drag", "banana")):
		failures.append("feeding_table: an unpeeled banana must not be draggable")
	if not bool(table.call("tap_item", "banana")):
		failures.append("feeding_table: tapping the banana did nothing")
	if not bool(table.call("is_peeled", "banana")):
		failures.append("feeding_table: a tap did not peel the banana")
	if not rig.completed.is_empty():
		failures.append("feeding_table: peeling alone completed the task")
	if not bool(table.call("begin_drag", "banana")):
		failures.append("feeding_table: a peeled banana could not be picked up")
	table.call("drag_to_mouth")
	if rig.completed != [["feedBanana", 1]]:
		failures.append("feeding_table: the banana completed %s, expected [[feedBanana, 1]]" % str(rig.completed))
	table.call("begin_drag", "banana")
	table.call("drag_to_mouth")
	if rig.completed.size() != 1:
		failures.append("feeding_table: the banana task completed %d times" % rig.completed.size())
	rig.free_all()
	return failures


func _test_water_hold_completes_once(root: Node, library: RefCounted):
	var failures: Array = []
	var rig: Rig = _rig(root, library, ["feedWater"], failures)
	if rig == null:
		return failures
	var table: Node3D = rig.table
	var cup: Node3D = table.call("get_item", "water")

	table.call("begin_drag", "water")
	table.call("drag_to_mouth")
	if not rig.completed.is_empty():
		failures.append("feeding_table: the cup completed the task on arrival; a sip must be HELD")
	if String(table.call("get_bunny_clip")) not in ["drink", ""]:
		failures.append("feeding_table: Bunny should start drinking while the cup is held, not '%s'" % table.call("get_bunny_clip"))
	table.call("advance_hold", 0.5)
	if cup != null and float(cup.call("get_liquid_level")) >= 1.0:
		failures.append("feeding_table: the water level did not drop while the sip was held")
	if cup != null and float(cup.call("get_tilt")) <= 0.0:
		failures.append("feeding_table: the cup did not tip while the sip was held")
	# Let go early: nothing lost.
	table.call("end_drag")
	if not rig.completed.is_empty():
		failures.append("feeding_table: releasing the cup early completed the task")
	if cup != null and (float(cup.call("get_liquid_level")) < 1.0 or float(cup.call("get_tilt")) > 0.0):
		failures.append("feeding_table: a cup released early must return full and upright")
	if float(table.call("get_hold_seconds")) != 0.0:
		failures.append("feeding_table: the hold did not reset on release")

	table.call("begin_drag", "water")
	table.call("drag_to_mouth")
	table.call("advance_hold", 0.6)
	if not rig.completed.is_empty():
		failures.append("feeding_table: the sip completed before %.1f s" % Rules.HOLD_SECONDS)
	table.call("advance_hold", 0.7)
	if rig.completed != [["feedWater", 1]]:
		failures.append("feeding_table: holding the cup completed %s, expected [[feedWater, 1]]" % str(rig.completed))
	table.call("advance_hold", 5.0)
	table.call("begin_drag", "water")
	table.call("drag_to_mouth")
	table.call("advance_hold", 5.0)
	if rig.completed.size() != 1:
		failures.append("feeding_table: the water task completed %d times" % rig.completed.size())
	rig.free_all()
	return failures


func _test_wrong_item_halves_then_guides(root: Node, library: RefCounted):
	var failures: Array = []
	var rig: Rig = _rig(root, library, ["feedApple"], failures)
	if rig == null:
		return failures
	var table: Node3D = rig.table
	var hud: Node = table.call("get_hud")

	if String(table.call("get_credit")) != Rules.CREDIT_FULL:
		failures.append("feeding_table: a fresh task should be worth full credit")
	if int(hud.call("get_task_star_state")) != RatingStar.State.EARNED:
		failures.append("feeding_table: the task star should start gold")

	# First mistake: the banana (peeled first, as a child would).
	table.call("tap_item", "banana")
	table.call("begin_drag", "banana")
	table.call("drag_to_mouth")
	if int(table.call("get_mistakes")) != 1:
		failures.append("feeding_table: a wrong item did not count as one mistake (got %d)" % table.call("get_mistakes"))
	if String(table.call("get_credit")) != Rules.CREDIT_HALF:
		failures.append("feeding_table: the first mistake should halve the task")
	if rig.half_stars != ["feedApple"]:
		failures.append("feeding_table: the first mistake did not raise half_star (got %s)" % str(rig.half_stars))
	if int(hud.call("get_task_star_state")) != RatingStar.State.HALF:
		failures.append("feeding_table: the task star should now be a half star")
	if String(table.call("get_bunny_face")) not in ["unhappy", ""]:
		failures.append("feeding_table: Bunny should look unhappy at a wrong item, not '%s'" % table.call("get_bunny_face"))
	if String(hud.call("get_encouragement")) != "Try the apple!":
		failures.append("feeding_table: the wrong item should say 'Try the apple!', not '%s'" % hud.call("get_encouragement"))
	if not rig.completed.is_empty():
		failures.append("feeding_table: a wrong item completed the task")
	if bool(table.call("is_dragging")):
		failures.append("feeding_table: the wrong item should have been let go")
	if bool(table.call("is_guided")):
		failures.append("feeding_table: guided mode arrived one mistake early")

	# Second mistake: guided mode.
	table.call("begin_drag", "banana")
	table.call("drag_to_mouth")
	if int(table.call("get_mistakes")) != 2 or not bool(table.call("is_guided")):
		failures.append("feeding_table: the second mistake should switch to guided mode")
	if rig.guided != ["feedApple"]:
		failures.append("feeding_table: guided_started was not raised exactly once (got %s)" % str(rig.guided))
	if rig.half_stars.size() != 1:
		failures.append("feeding_table: half_star must be raised once per task, got %d" % rig.half_stars.size())
	var apple: Node3D = table.call("get_item", "apple")
	if apple == null or not bool(apple.call("is_glowing")):
		failures.append("feeding_table: in guided mode the right item must glow")
	if not bool(hud.call("is_guide_visible")):
		failures.append("feeding_table: in guided mode an arrow must point to the mouth")
	if bool(table.call("begin_drag", "banana")):
		failures.append("feeding_table: in guided mode the wrong item must not be draggable")
	if bool(rig.runner.call("is_running")) == false:
		failures.append("feeding_table: two mistakes must not end the mission")

	# Delivery after guidance: complete, 0 stars, still counted as done.
	if not bool(table.call("begin_drag", "apple")):
		failures.append("feeding_table: the guided target could not be picked up")
	table.call("drag_to_mouth")
	if rig.completed != [["feedApple", 0]]:
		failures.append("feeding_table: after two mistakes the task should complete for 0 stars, got %s" % str(rig.completed))
	if not (rig.runner.call("get_awarded_task_ids") as Array).has("feedApple"):
		failures.append("feeding_table: a halved task must still count as completed for the level rating")
	if rig.save.stars != 0:
		failures.append("feeding_table: a halved task paid %d stars into the profile" % rig.save.stars)
	if not rig.finished:
		failures.append("feeding_table: the mission did not finish after the guided delivery")
	rig.free_all()
	return failures


func _test_tap_help_completes_without_a_drag(root: Node, library: RefCounted):
	var failures: Array = []
	var rig: Rig = _rig(root, library, ["feedApple"], failures)
	if rig == null:
		return failures
	var table: Node3D = rig.table
	var hud: Node = table.call("get_hud")

	table.call("tap_item", "apple")
	if not rig.completed.is_empty():
		failures.append("feeding_table: a plain tap completed the task before any nudge")
	table.call("nudge")
	if bool(table.call("is_tap_help_active")):
		failures.append("feeding_table: tap-help should wait for the second nudge")
	table.call("tap_item", "apple")
	if not rig.completed.is_empty():
		failures.append("feeding_table: a tap after ONE nudge completed the task")
	table.call("nudge")
	if not bool(table.call("is_tap_help_active")):
		failures.append("feeding_table: two nudges should offer tap-help")
	if not bool(hud.call("is_hint_visible")) or String(hud.call("get_hint_text")) != Rules.TAP_HELP_HINT:
		failures.append("feeding_table: the '%s' hint should be showing" % Rules.TAP_HELP_HINT)
	table.call("tap_item", "apple")
	if rig.completed != [["feedApple", 1]]:
		failures.append("feeding_table: tap-help completed %s, expected [[feedApple, 1]] with full credit" % str(rig.completed))
	if bool(table.call("is_dragging")):
		failures.append("feeding_table: tap-help must not leave a drag open")
	rig.free_all()
	return failures


func _test_no_double_reward(root: Node, library: RefCounted):
	var failures: Array = []
	var rig: Rig = _rig(root, library, ["feedMilk", "feedApple"], failures)
	if rig == null:
		return failures
	var table: Node3D = rig.table
	var ledger: RefCounted = RewardManagerScript.shared_ledger()

	# Whatever order the picker chose, feed both, mashing the stage in between.
	var targets: Array = []
	for _round: int in range(2):
		var target: String = String(table.call("get_target_id"))
		if target.is_empty():
			break
		targets.append(target)
		if Rules.needs_peel(target):
			table.call("tap_item", target)
		table.call("begin_drag", target)
		table.call("drag_to_mouth")
		if Rules.is_drink(target):
			table.call("advance_hold", Rules.HOLD_SECONDS + 0.1)
		# The stage is latched: a second gesture on the same task is inert.
		table.call("begin_drag", target)
		table.call("drag_to_mouth")
		table.call("advance_hold", Rules.HOLD_SECONDS + 0.1)
	# And once the mission is over, stale re-emits from anywhere pay nothing.
	for target: String in targets:
		table.emit_signal("item_delivered", target)
		rig.runner.call("on_object_chosen", target)
		rig.manager.call("award", "feed" + target.capitalize(), 1)

	if rig.completed.size() != 2:
		failures.append("feeding_table: two tasks completed %d times" % rig.completed.size())
	if int(ledger.call("get_session_completions")) != 2:
		failures.append("feeding_table: the ledger paid %d completions for two tasks" % ledger.call("get_session_completions"))
	if rig.save.stars != 2:
		failures.append("feeding_table: two clean tasks should pay 2 stars, paid %d" % rig.save.stars)
	if int(rig.runner.call("get_stars_earned")) != 2:
		failures.append("feeding_table: the runner counted %d stars for two tasks" % rig.runner.call("get_stars_earned"))
	rig.free_all()
	return failures


## The handler contract on its own: the same wrong-then-right sequence pays the
## full star WITHOUT the external stage (the room's spawn row is unchanged) and
## 0 WITH it.
func _test_handler_credit_only_halves_on_external_stage(library: RefCounted):
	var failures: Array = []
	for external: bool in [false, true]:
		var stub: StubLibrary = StubLibrary.new()
		stub.real = library
		stub.tasks = [library.get_task("feedApple")]
		var runner: Node = MissionRunnerScript.new()
		runner.call("set_seed", 3)
		var completed: Array = []
		runner.connect("task_completed", func(task_id: String, stars: int) -> void: completed.append([task_id, stars]))
		var context: Dictionary = {}
		if external:
			context["externalStage"] = Callable(Rules, "handles_task")
		runner.call("start_mission", "stub", stub, context)
		runner.call("on_object_chosen", "banana")
		runner.call("on_object_chosen", "apple")
		var expected: int = 0 if external else 1
		if completed != [["feedApple", expected]]:
			failures.append("feeding_table: with externalStage=%s a retry then success paid %s, expected [[feedApple, %d]]"
					% [str(external), str(completed), expected])
		runner.call("cancel")
		runner.free()
	return failures


func _test_half_star_contract():
	var failures: Array = []
	var half: Color = RatingStar.color_for(RatingStar.State.HALF)
	if half.a >= 1.0:
		failures.append("feeding_table: a half star must not paint at full alpha -- the summary counts earned stars by alpha")
	if not RatingStar.is_lit(RatingStar.State.HALF) or not RatingStar.is_lit(RatingStar.State.EARNED):
		failures.append("feeding_table: the half star and the earned star are the lit states")
	if RatingStar.is_lit(RatingStar.State.GHOST) or RatingStar.is_lit(RatingStar.State.NEXT):
		failures.append("feeding_table: ghost and next stars carry no gold")
	if RatingStar.texture_path_for(RatingStar.State.HALF) != RatingStar.STAR_OUTLINE_PATH:
		failures.append("feeding_table: the half star starts from the outline glyph")
	var polygon: PackedVector2Array = RatingStar.star_polygon(Rect2(0.0, 0.0, 100.0, 100.0))
	if polygon.size() != 40:
		failures.append("feeding_table: the glossy star polygon has %d points, expected 40" % polygon.size())
	for point: Vector2 in polygon:
		if point.x < -0.01 or point.y < -0.01 or point.x > 100.01 or point.y > 100.01:
			failures.append("feeding_table: the glossy star polygon leaves its rect")
			break
	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _rig(root: Node, library: RefCounted, task_ids: Array, failures: Array) -> Rig:
	var table: Node3D = _make_table(root, failures)
	if table == null:
		return null
	var stub: StubLibrary = StubLibrary.new()
	stub.real = library
	for task_id: String in task_ids:
		stub.tasks.append(library.get_task(task_id))

	var rig: Rig = Rig.new()
	rig.table = table
	rig.runner = MissionRunnerScript.new()
	rig.runner.call("set_seed", 11)
	rig.manager = RewardManagerScript.new()
	var ledger: RefCounted = RewardLedgerScript.new()
	# Two tasks finish inside one millisecond here; the 350 ms spam guard is a
	# real-finger guard and is not what this case is about.
	ledger.set("min_interval_ms", 0)
	RewardManagerScript.set_shared_ledger(ledger)
	RewardManagerScript.begin_round()
	rig.manager.call("set_save_service", rig.save)

	rig.runner.connect("task_started", rig.on_task_started)
	rig.runner.connect("task_completed", rig.on_task_completed)
	rig.runner.connect("mission_completed", rig.on_mission_completed)
	table.connect("item_delivered", rig.runner.on_object_chosen)
	table.connect("wrong_item", rig.runner.on_object_chosen)
	table.connect("half_star", rig.on_half_star)
	table.connect("guided_started", rig.on_guided)

	var started: bool = bool(rig.runner.call("start_mission", "stub", stub,
			{"externalStage": Callable(Rules, "handles_task")}))
	if not started:
		failures.append("feeding_table: the runner refused the stub mission %s" % str(task_ids))
		rig.free_all()
		return null
	return rig


func _make_table(root: Node, failures: Array) -> Node3D:
	if not ResourceLoader.exists(FEEDING_TABLE_SCENE):
		failures.append("feeding_table: %s does not exist" % FEEDING_TABLE_SCENE)
		return null
	var packed: PackedScene = load(FEEDING_TABLE_SCENE) as PackedScene
	if packed == null:
		failures.append("feeding_table: %s is not a PackedScene" % FEEDING_TABLE_SCENE)
		return null
	var table: Node3D = packed.instantiate() as Node3D
	if table == null:
		failures.append("feeding_table: %s did not instantiate as a Node3D" % FEEDING_TABLE_SCENE)
		return null
	root.add_child(table)
	table.call("build")
	table.call("set_instant", true)
	table.call("set_active", true)
	return table


func _root() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null
