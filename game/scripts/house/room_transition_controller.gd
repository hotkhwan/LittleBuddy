extends Node

## Doors. Tap one, Little Buddy walks to it, and the house changes room.
##
##     tap door -> walk to the door's InteractionPoint -> control off
##              -> spawn at the destination room's entrance -> camera reframes
##              -> control back
##
## ## Discrete rooms, not a seamless house
##
## The product decision (contract §4) is explicit tappable doors with discrete
## rooms, chosen over seamless streaming for reliability, camera framing and
## child comprehension. So a transition is a place-and-reframe, not a walk
## through a doorway.
##
## ## The three rules this file exists to guarantee
##
## 1. **An unknown destination is refused, never crashed.** The child stays
##    exactly where they were, and stays in control.
## 2. **Control is always restored.** Every exit path -- success, refusal,
##    a room that could not be placed -- ends with `set_disabled(false)`.
##    `LittleBuddyCharacter.set_disabled(true)` refuses every request while it is
##    set, so a half-finished transition would otherwise leave a child tapping a
##    screen that does nothing at all.
## 3. **Arrival fires exactly once.** `_in_transition` latches for the duration,
##    the same discipline as the movement controller's arrival latch, so a child
##    hammering the door emits one `transition_completed`, not five.
##
## Nothing here is 3D. The controller moves nobody: it validates, latches,
## toggles control and asks the world to place the child. That is why it is
## testable headlessly.

## Fired before the swap. Never shown to the child as a loading state; the
## transition is a beat, not a screen.
signal transition_started(from_room_id: String, to_room_id: String)

## Fired exactly once per accepted transition, after the child is standing in the
## new room, facing into it, with control restored.
signal transition_completed(room_id: String, spawn_id: String)

## Fired instead of `transition_completed` when a transition could not happen.
## `reason` is one of "unknownRoom", "busy", "notBound", "placementFailed".
## This is NEVER a failure state for the child -- there is no red X in this game
## and the room simply does not change.
signal transition_refused(to_room_id: String, reason: String)

var _world: Node = null
var _character: Node = null
var _in_transition: bool = false


## Composition, not an autoload: the world hands in the two things this needs.
## Also subscribes to the character's `interaction_ready`, which is the signal
## that means "standing at the door, facing it" -- the correct cue to change
## room, and the reason a door needs no special-case walking code.
func bind(world: Node, character: Node) -> void:
	if _character != null and _character.is_connected("interaction_ready", _on_interaction_ready):
		_character.disconnect("interaction_ready", _on_interaction_ready)
	_world = world
	_character = character
	if _character != null and not _character.is_connected("interaction_ready", _on_interaction_ready):
		_character.connect("interaction_ready", _on_interaction_ready)


func is_transitioning() -> bool:
	return _in_transition


## The door the child just arrived at, if it was a door at all.
func _on_interaction_ready(target_id: String) -> void:
	var door: Dictionary = _find_door(target_id)
	if door.is_empty():
		return
	request_transition(String(door.get("toRoomId", "")), String(door.get("toSpawnId", "")))


## Moves the child to `to_room_id`, landing on `to_spawn_id`.
##
## Returns true only when the child really is in the new room. Every other
## outcome emits `transition_refused` and leaves the child untouched and in
## control.
func request_transition(to_room_id: String, to_spawn_id: String) -> bool:
	if _in_transition:
		transition_refused.emit(to_room_id, "busy")
		return false
	if _world == null or _character == null:
		transition_refused.emit(to_room_id, "notBound")
		return false

	_in_transition = true
	# Control off for the whole attempt, INCLUDING the validation, so there is
	# exactly one place where it is restored and no path can skip it.
	_set_control(false)

	var from_room_id: String = String(_world.call("get_current_room_id"))
	var completed: bool = false
	var refusal: String = ""

	if not bool(_world.call("has_room", to_room_id)):
		# The whole point of rule 1: a bad id from content, a renamed room or a
		# typo must not move, freeze or crash anybody.
		refusal = "unknownRoom"
	else:
		transition_started.emit(from_room_id, to_room_id)
		if bool(_world.call("place_in_room", to_room_id, to_spawn_id)):
			completed = true
		else:
			refusal = "placementFailed"

	_set_control(true)
	_in_transition = false

	if completed:
		# Emitted after control is restored, so a listener always observes a child
		# who can be tapped at again.
		transition_completed.emit(
			String(_world.call("get_current_room_id")), String(_world.call("get_current_spawn_id"))
		)
		return true

	transition_refused.emit(to_room_id, refusal)
	return false


## -- Internals -----------------------------------------------------------------

func _find_door(target_id: String) -> Dictionary:
	if _world == null:
		return {}
	var room: Node = _world.call("get_current_room")
	if room == null or not room.has_method("get_door_for_target"):
		return {}
	return room.call("get_door_for_target", target_id)


func _set_control(enabled: bool) -> void:
	if _character != null and _character.has_method("set_disabled"):
		_character.call("set_disabled", not enabled)
