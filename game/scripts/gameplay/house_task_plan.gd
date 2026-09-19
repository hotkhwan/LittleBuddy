extends RefCounted

## One content task, read as a plan the house can play. Pure: Dictionary in,
## Dictionary out, Strings and bools only -- no node, no `Vector3`, no navigation.
##
## This is the whole "data drives the level" story in one function. A Chapter 3
## task carries, in `content/**`:
##
## ```jsonc
## "targetId":       "bathroom.sink",      // what the beat is ABOUT
## "requiresWalkTo": "bathroom.sink",      // where Little Buddy must be standing
## "characterAction":"brushTeeth",         // the semantic action to play there
## "interaction":    "dragToMouth",        // how the child delivers the object
## "objectId":       "toothbrush"
## ```
##
## and `describe()` turns that into one of four **kinds**, which is the only
## branch the level director ever makes:
##
##   `travel`   -- `requiresWalkTo` is a door. Walking through it IS the task, so
##                 the room transition completes it. (`walkToBathroom`)
##   `goAndDo`  -- walk to a thing and act on it, no object to choose.
##                 (`sitAtTable`, `sleepInBed`)
##   `deliver`  -- walk to a thing, THEN choose an object and drag it to Little
##                 Buddy or to the thing. (`brushTeethMorning`, `stackBlocks`)
##   `choose`   -- no walk at all: pick the right object where you stand.
##                 (`findToothbrush`, `sayGoodMorning`, `wearPants`)
##
## Every kind is completable by touch alone, and `deliver`/`choose` are the two
## that carry the English listening tasks -- so the touch-only 3/3 promise is a
## property of this table, not of the microphone.
##
## Loaded by `preload()`, never by `class_name`: the headless `--script` runner
## does not build Godot's global class cache.

const HouseRoute := preload("res://scripts/house/house_route.gd")
const SemanticId := preload("res://scripts/navigation/semantic_id.gd")
const DropZoneScript := preload("res://scripts/gameplay/drop_zone.gd")

const KIND_TRAVEL: String = "travel"
const KIND_GO_AND_DO: String = "goAndDo"
const KIND_DELIVER: String = "deliver"
const KIND_CHOOSE: String = "choose"
## A hands-on care act performed ON Little Buddy at a piece of furniture:
## brushing teeth at the sink, washing a face, drying it.
##
## It is its own kind because none of the other four fit. `goAndDo` finishes the
## moment you arrive, which would make brushing a child's teeth a single tap.
## `deliver` drags one object onto one pad and is done. Care is a SUSTAINED
## gesture with progress, so it needs the walk of `goAndDo` and then a screen of
## its own -- which is the reusable semantic action type the brief asks for
## rather than a second mission engine.
const KIND_CARE: String = "care"

## The care acts, and the tool each one puts in the player's hand. Adding a
## fourth (combing hair, cleaning a nose) is a row here plus copy -- no new kind,
## no director change.
const CARE_INTERACTIONS: Dictionary = {
	"brushTeeth": "toothbrush",
	"washFace": "cloth",
	"dryFace": "towel",
	"prepareMilk": "jug",
	"giveBottle": "bottle",
}

## Interactions that put an object in the child's hand and a landing pad
## somewhere in the world. Anything else is a plain tap.
const DRAG_PREFIX: String = "dragTo"

## Zone ids that live ON Little Buddy (drag the milk to his mouth) rather than on
## a piece of furniture (drop the blocks in the toy box). The stage needs to know
## which of the two a task wants before it can place the landing pad.
const BODY_ZONE_IDS: Array[String] = [
	DropZoneScript.ZONE_MOUTH,
	DropZoneScript.ZONE_HUG,
	DropZoneScript.ZONE_DRESS,
	DropZoneScript.ZONE_HAND,
]


## The plan for `task`. `current_room_id` is only used to fill in `roomId` for a
## task that names no room at all (a plain dressing task happens where you are),
## so the same task yields the same plan wherever it is read.
static func describe(task: Variant, current_room_id: String = "") -> Dictionary:
	var data: Dictionary = task if typeof(task) == TYPE_DICTIONARY else {}

	var task_id: String = _text(data.get("taskId", ""))
	var mode: String = _text(data.get("mode", ""))
	var interaction: String = _text(data.get("interaction", ""))
	var object_id: String = _text(data.get("objectId", ""))
	var action_name: String = _text(data.get("characterAction", ""))
	var walk_target: String = _text(data.get("requiresWalkTo", ""))
	var focus_target: String = _text(data.get("targetId", ""))
	if focus_target.is_empty():
		focus_target = walk_target

	var is_door: bool = HouseRoute.is_door_id(walk_target)
	var kind: String = KIND_CHOOSE
	if is_door:
		kind = KIND_TRAVEL
	elif CARE_INTERACTIONS.has(interaction):
		# Care is checked BEFORE the drag test: `dragTo*` is a delivery, but a care
		# act is a drag too and must not be mistaken for one.
		kind = KIND_CARE
	elif not walk_target.is_empty():
		kind = KIND_DELIVER if interaction.begins_with(DRAG_PREFIX) else KIND_GO_AND_DO

	var zone_id: String = String(DropZoneScript.zone_id_for_interaction(interaction))
	var room_id: String = SemanticId.room_of(walk_target)
	if room_id.is_empty():
		room_id = SemanticId.room_of(focus_target)
	if room_id.is_empty():
		room_id = _text(current_room_id)

	return {
		"taskId": task_id,
		"mode": mode,
		"kind": kind,
		"interaction": interaction,
		"objectId": object_id,
		"actionName": action_name,
		"walkTargetId": walk_target,
		"focusTargetId": focus_target,
		"roomId": room_id,
		"zoneId": zone_id,
		"isDoorWalk": is_door,
		# Where a door leads, so "the child is already there" can be recognised
		# instead of walking them back out and in again.
		"destinationRoomId": HouseRoute.door_destination(walk_target),
		"needsWalk": not walk_target.is_empty(),
		# `travel` and `goAndDo` are finished by BEING somewhere and acting, so
		# their content object (a pillow, a bowl) would just be clutter on the
		# floor; the two choosing kinds are the ones that stage objects.
		"needsChoices": kind == KIND_DELIVER or kind == KIND_CHOOSE,
		# A pad on the furniture (toy box, bath) or a pad on the toddler himself.
		"zoneFollowsCharacter": BODY_ZONE_IDS.has(zone_id),
		"zoneTargetId": focus_target,
		# "brushTeeth" | "washFace" | "dryFace", else "". The overlay reads this.
		"careKind": interaction if CARE_INTERACTIONS.has(interaction) else "",
		"careTool": String(CARE_INTERACTIONS.get(interaction, "")),
	}


## An empty plan, shaped exactly like a real one, so a caller never has to test
## for null before reading a key.
static func empty(current_room_id: String = "") -> Dictionary:
	return describe({}, current_room_id)


static func is_travel(plan: Variant) -> bool:
	return _kind_of(plan) == KIND_TRAVEL


static func is_go_and_do(plan: Variant) -> bool:
	return _kind_of(plan) == KIND_GO_AND_DO


static func is_deliver(plan: Variant) -> bool:
	return _kind_of(plan) == KIND_DELIVER


static func is_choose(plan: Variant) -> bool:
	return _kind_of(plan) == KIND_CHOOSE


static func is_care(plan: Variant) -> bool:
	return _kind_of(plan) == KIND_CARE


## Whether this beat is worth moving the camera in on.
##
## The rule, and it is a rule about children rather than about cameras:
##
##   * `travel` -- **no**. The task IS the journey. A child walking to a door
##     needs the room, both doors and the marked spot on the floor all on screen
##     at once; tightening the shot on the destination is the one thing that
##     could make "where do I go?" unanswerable.
##   * `goAndDo`, `deliver`, `choose` -- **yes**. The child is standing at the
##     beat, and what matters is the sink, the bowl, the row of clothes and Little
##     Buddy's face, not the far wall.
##
## Pure and here rather than in the level director because it is a property of the
## task, and because it is the kind of rule that is easy to get backwards and
## impossible to notice from a test that only checks the camera moved.
static func wants_close_up(plan: Variant) -> bool:
	var kind: String = _kind_of(plan)
	if kind == KIND_CARE:
		return true
	if kind.is_empty() or kind == KIND_TRAVEL:
		return false
	return true


## "" when the plan is playable as it stands; otherwise a human-readable reason.
##
## Deliberately narrow: `MissionRunner.describe_unplayable()` already owns
## "can this task be finished at all", and duplicating its rules here would be a
## second source of truth. This only answers the question the HOUSE adds -- a
## semantic id that is not a semantic id.
static func describe_unplayable_in_house(plan: Variant) -> String:
	var data: Dictionary = plan if typeof(plan) == TYPE_DICTIONARY else {}
	var task_id: String = _text(data.get("taskId", ""))
	for key: String in ["walkTargetId", "focusTargetId"]:
		var value: String = _text(data.get(key, ""))
		if value.is_empty():
			continue
		if not SemanticId.is_qualified(value):
			return "task '%s' has a '%s' of '%s', which is not a <room>.<target> id" \
					% [task_id, key, value]
	if is_travel(data) and _text(data.get("destinationRoomId", "")).is_empty():
		return "task '%s' walks to door '%s', which leads nowhere this house has" \
				% [task_id, _text(data.get("walkTargetId", ""))]
	return ""


static func _kind_of(plan: Variant) -> String:
	if typeof(plan) != TYPE_DICTIONARY:
		return ""
	return _text((plan as Dictionary).get("kind", ""))


static func _text(value: Variant) -> String:
	return String(value).strip_edges()
