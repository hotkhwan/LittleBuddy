extends RefCounted

## The data-to-gameplay translation, asserted against the SHIPPED Chapter 3
## content rather than against a fixture.
##
## `HouseTaskPlan.describe()` is the only branch the level loop makes: every one
## of the 38 tasks in the five levels becomes one of four kinds, and the loop then
## plays that kind. So the two things that can go wrong are (a) a task that does
## not classify the way the beat reads -- "walk to the bathroom" coming out as
## something other than a room change -- and (b) a kind that no longer has a way
## to be finished by touch.
##
## Pure: no scene, no navigation, no `Node3D`. If this case needed one, the
## question would be about the wrong layer.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const TaskPlan := preload("res://scripts/gameplay/house_task_plan.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const LevelSystemScript := preload("res://scripts/progression/level_system.gd")

const LEVEL_IDS: Array[String] = [
	"goodMorning", "gettingDressed", "breakfast", "playTime", "tidyAndBed",
]

## The beats whose classification is the level design, spelled out so a content
## edit that quietly turns a room change into a tap has to change this file too.
## `[taskId, kind, walkTargetId, characterAction]`.
const PINNED: Array = [
	["wakeUpBuddy", "choose", "", "wake"],
	["walkToBathroom", "travel", "bedroom.doorToBathroom", "walk"],
	["findToothbrush", "choose", "", "point"],
	["brushTeethMorning", "deliver", "bathroom.sink", "brushTeeth"],
	["sitAtTable", "goAndDo", "kitchen.table", "sit"],
	["drinkMilkAtTable", "deliver", "kitchen.table", "drink"],
	["stackBlocks", "deliver", "livingRoom.toyBox", "pickUp"],
	["walkHomeToKitchen", "travel", "livingRoom.doorToKitchen", "walk"],
	["walkHomeToBedroom", "travel", "kitchen.doorToBedroom", "walk"],
	["sleepInBed", "goAndDo", "bedroom.bed", "sleep"],
	["wearPants", "choose", "", ""],
]

var _library: Object = null
var _system: RefCounted = null


func test_name() -> String:
	return "house_task_plan"


func run():
	var failures: Array = []
	_library = ContentLibraryScript.create()
	_system = LevelSystemScript.create(_library)
	if _library == null or _system == null:
		return ["could not load the content library"]

	failures.append_array(_test_pinned_beats())
	failures.append_array(_test_every_slice_task_classifies())
	failures.append_array(_test_travel_tasks_lead_somewhere_real())
	failures.append_array(_test_drag_tasks_know_where_the_pad_goes())
	failures.append_array(_test_an_empty_plan_is_shaped_like_a_real_one())
	failures.append_array(_test_nonsense_is_reported_not_played())
	return failures


func _test_pinned_beats():
	var failures: Array = []
	for row: Array in PINNED:
		var task_id: String = String(row[0])
		var task: Dictionary = _library.get_task(task_id)
		if task.is_empty():
			failures.append("content no longer has task '%s'" % task_id)
			continue
		var plan: Dictionary = TaskPlan.describe(task, "bedroom")
		if String(plan.get("kind", "")) != String(row[1]):
			failures.append("task '%s' should play as '%s', plans as '%s'"
					% [task_id, row[1], plan.get("kind", "")])
		if String(plan.get("walkTargetId", "")) != String(row[2]):
			failures.append("task '%s' should walk to '%s', plans '%s'"
					% [task_id, row[2], plan.get("walkTargetId", "")])
		if String(plan.get("actionName", "")) != String(row[3]):
			failures.append("task '%s' should play the action '%s', plans '%s'"
					% [task_id, row[3], plan.get("actionName", "")])
	return failures


## Every task in the slice must classify, and every classification must have a
## way to be finished: walking (travel/goAndDo) or choosing (deliver/choose).
func _test_every_slice_task_classifies():
	var failures: Array = []
	var seen: int = 0
	var kinds: Dictionary = {}
	for level_id: String in LEVEL_IDS:
		for task_id: String in _system.get_level_task_ids(level_id):
			var task: Dictionary = _library.get_task(task_id)
			if task.is_empty():
				failures.append("level '%s' names unknown task '%s'" % [level_id, task_id])
				continue
			seen += 1
			var plan: Dictionary = TaskPlan.describe(task, "")
			var kind: String = String(plan.get("kind", ""))
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			var problem: String = String(TaskPlan.describe_unplayable_in_house(plan))
			if not problem.is_empty():
				failures.append("level '%s': %s" % [level_id, problem])
			var walks: bool = bool(plan.get("needsWalk", false))
			var chooses: bool = bool(plan.get("needsChoices", false))
			if not walks and not chooses:
				failures.append(
					"task '%s' plans as '%s' with nothing to walk to and nothing to touch; it "
					% [task_id, kind] + "would be a dead end on screen")
			if String(plan.get("taskId", "")) != task_id:
				failures.append("the plan for '%s' reports the wrong task id" % task_id)

	if seen < 30:
		failures.append("only %d slice tasks were classified; the scan is too small to be real"
				% seen)
	# All four kinds have to be exercised by the shipped content, or three
	# quarters of the loop is dead code nobody is testing.
	for kind: String in ["travel", "goAndDo", "deliver", "choose"]:
		if int(kinds.get(kind, 0)) <= 0:
			failures.append("no shipped task plays as '%s'; that branch of the level loop is "
					% kind + "never exercised")
	return failures


func _test_travel_tasks_lead_somewhere_real():
	var failures: Array = []
	for level_id: String in LEVEL_IDS:
		for task_id: String in _system.get_level_task_ids(level_id):
			var plan: Dictionary = TaskPlan.describe(_library.get_task(task_id), "")
			if not TaskPlan.is_travel(plan):
				continue
			var destination: String = String(plan.get("destinationRoomId", ""))
			if destination.is_empty():
				failures.append("travel task '%s' leads nowhere; the level would never advance"
						% task_id)
			if destination == String(plan.get("roomId", "")):
				failures.append("travel task '%s' leads back into the room it starts in" % task_id)
	return failures


## A `dragTo*` task needs a landing pad, and the stage needs to know whether that
## pad rides on Little Buddy or sits on the furniture. Getting that wrong puts
## "drop the blocks in the toy box" on the toddler's chest.
func _test_drag_tasks_know_where_the_pad_goes():
	var failures: Array = []
	var body: Array = ["dragToMouth", "dragToHug", "dragToDress"]
	var prop: Array = ["dragToToyBox", "dragToBath"]
	for level_id: String in LEVEL_IDS:
		for task_id: String in _system.get_level_task_ids(level_id):
			var task: Dictionary = _library.get_task(task_id)
			var plan: Dictionary = TaskPlan.describe(task, "")
			var interaction: String = String(plan.get("interaction", ""))
			if String(plan.get("zoneId", "")).is_empty():
				failures.append("task '%s' has interaction '%s', which maps to no landing pad"
						% [task_id, interaction])
			if body.has(interaction) and not bool(plan.get("zoneFollowsCharacter", false)):
				failures.append("task '%s' delivers to Little Buddy but its pad does not follow him"
						% task_id)
			if prop.has(interaction) and bool(plan.get("zoneFollowsCharacter", false)):
				failures.append("task '%s' delivers to a piece of furniture but its pad rides on "
						% task_id + "the toddler")
			if prop.has(interaction) and String(plan.get("zoneTargetId", "")).is_empty():
				failures.append("task '%s' delivers to furniture but names no target to put the "
						% task_id + "pad on")
	return failures


func _test_an_empty_plan_is_shaped_like_a_real_one():
	var failures: Array = []
	var empty: Dictionary = TaskPlan.empty("kitchen")
	for key: String in ["taskId", "kind", "walkTargetId", "needsWalk", "needsChoices", "roomId"]:
		if not empty.has(key):
			failures.append("an empty plan is missing '%s'; a caller would have to null-check" % key)
	if String(empty.get("roomId", "")) != "kitchen":
		failures.append("an empty plan should fall back to the room the child is in")
	if bool(empty.get("needsWalk", true)):
		failures.append("an empty plan must not ask for a walk")
	return failures


func _test_nonsense_is_reported_not_played():
	var failures: Array = []
	var bad_target: Dictionary = TaskPlan.describe({
		"taskId": "brokenWalk", "requiresWalkTo": "sink", "interaction": "tap",
	}, "bathroom")
	if String(TaskPlan.describe_unplayable_in_house(bad_target)).is_empty():
		failures.append("an unqualified target id ('sink' rather than 'bathroom.sink') must be "
				+ "reported; the child would tap and nothing would happen")

	var bad_door: Dictionary = TaskPlan.describe({
		"taskId": "brokenDoor", "requiresWalkTo": "bedroom.doorToGarage", "interaction": "tap",
	}, "bedroom")
	if String(TaskPlan.describe_unplayable_in_house(bad_door)).is_empty():
		failures.append("a door to a room the house does not have must be reported")

	var good: Dictionary = TaskPlan.describe({
		"taskId": "fine", "requiresWalkTo": "bathroom.sink", "interaction": "dragToMouth",
		"objectId": "toothbrush", "characterAction": "brushTeeth",
	}, "bathroom")
	if not String(TaskPlan.describe_unplayable_in_house(good)).is_empty():
		failures.append("a perfectly ordinary task was reported as unplayable: %s"
				% TaskPlan.describe_unplayable_in_house(good))
	return failures
