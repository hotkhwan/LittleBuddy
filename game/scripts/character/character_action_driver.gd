extends RefCounted

## The animation seam.
##
## `LittleBuddyCharacter.play_action("drink")` asks one of these to show a
## semantic action. Nothing above this line ever names an animation clip, an
## `AnimationPlayer`, an `AnimationTree` or a state-machine node -- which is what
## lets the placeholder primitive character be swapped for a rigged, commissioned
## model without touching a line of mission or content code.
##
## ## Graceful degradation is the whole point
##
## The spike ships `idle` and `walk` only. The action vocabulary the game will
## eventually need -- eat, drink, sit, sleep, brushTeeth, hug, pickUp, give,
## celebrate -- is already accepted here today. `play()` returns **false** for an
## action it cannot show and does nothing else: no error, no push_error, no
## exception, and crucially no state change. `CharacterMovementController` runs
## its action timer regardless, so an unauthored action is a brief pause and the
## character always returns to idle. A missing clip must never be able to strand
## a child in front of a frozen character.
##
## This base class is the null driver (nothing is playable), which is also the
## honest fallback when a character has no animation player at all.

## Every semantic action the game is expected to grow into. Declared here so a
## typo in mission content can be caught by a test rather than by a child staring
## at a character that does nothing.
const KNOWN_ACTIONS: Array[String] = [
	"idle", "walk",
	"eat", "drink", "sit", "sleep", "brushTeeth", "hug", "pickUp", "give", "celebrate",
]


## Is `action_name` a name the game recognises at all? Separate from `can_play()`:
## an action can be known (valid vocabulary) but not yet animated.
static func is_known_action(action_name: String) -> bool:
	return KNOWN_ACTIONS.has(action_name)


## Can this driver actually show `action_name` right now?
func can_play(_action_name: String) -> bool:
	return false


## Shows `action_name`. Returns false when it cannot -- never an error, never a
## crash, never a state change.
func play(_action_name: String) -> bool:
	return false


## Returns to the resting look. Always safe to call.
func rest(_carrying: bool = false) -> void:
	pass


## What is on screen right now, or "" if nothing.
func get_current_action() -> String:
	return ""
