extends RefCounted

## The animation seam, and the semantic action vocabulary.
##
## `LittleBuddyCharacter.play_action("drink")` asks one of these to show a
## semantic action. Nothing above this line ever names an animation clip, an
## `AnimationPlayer`, an `AnimationTree` or a state-machine node -- which is what
## lets the placeholder primitive character be swapped for a rigged, commissioned
## model without touching a line of mission or content code.
##
## ## Why there is no AnimationTree
##
## An `AnimationTree` earns its place when you need *continuous blending driven
## by parameters*: a locomotion blend-space, additive upper-body layering, or a
## state machine whose transitions carry conditions. This game has none of that.
## Every action is a discrete pose swap, one clip at a time, and the semantic
## layer that decides *which* one already exists above this class. An
## `AnimationTree` would add a second naming surface (state-machine node names)
## on top of the clip names, a resource to author per character family, and --
## decisively -- it would break the graceful-degradation rule below, because
## `travel()` to a state that does not exist is an error rather than a polite
## `false`. `AnimationPlayer.play(clip, blend)` gives the cross-fade, which was
## the only thing actually wanted. See `ACTION_BLEND_SEC` in the subclass.
##
## ## Graceful degradation is the whole point
##
## `play()` returns **false** for an action it cannot show and does nothing else:
## no error, no push_error, no exception, and crucially no state change.
## `CharacterMovementController` runs its action timer regardless, so an
## unauthored action is a brief pause and the character always returns to rest. A
## missing clip must never be able to strand a child in front of a frozen
## character.
##
## This base class is the null driver (nothing is playable), which is also the
## honest fallback when a character has no animation player at all.
##
## ## One-shot actions versus held poses
##
## The vocabulary splits in two, and the split is semantic rather than technical:
##
## * **One-shot** -- `wave`, `clap`, `eat`, `drink`, `pickUp`, `give`,
##   `brushTeeth`, `celebrate`, `stand`, `wake`, `point`, `walk`, `idle`.
##   Something *happens*, it takes a while, then it is over. The character
##   returns to its resting look by itself.
## * **Held** -- `hold`, `sit`, `sleep`. These are **postures**, not events. A
##   toddler who sat down is still sitting a minute later. They still start, still
##   report `action_started`, and still report `action_finished` once the
##   character has *finished getting into* the pose -- so a mission can await them
##   exactly like any other action and can never dead-end waiting -- but the pose
##   then persists until something releases it.
##
## A held pose deliberately resolves to a **resting** state (idle, or carrying),
## not to a permanently busy one. That is the same trick `CARRYING` already uses:
## a posture is not a reason to stop accepting instructions. Walking, a new
## action, `stop()`, `release_action()` or being disabled all release the hold, so
## a child's next tap always works. `sit`/`stand`, `sleep`/`wake` and
## `hold`/`give` are the natural release pairs (`HOLD_RELEASES`), but *any* new
## instruction releases -- the pairs are vocabulary, not a required protocol.

## Every semantic action the game recognises. Declared here so a typo in mission
## content can be caught by a test rather than by a child staring at a character
## that does nothing. Contract §3 lists exactly these sixteen.
const KNOWN_ACTIONS: Array[String] = [
	"idle", "walk", "wave", "point", "clap",
	"pickUp", "hold", "give",
	"eat", "drink", "brushTeeth",
	"sit", "stand", "hug", "sleep", "wake", "celebrate",
]

## Postures, not events. See the class doc. Everything else is a one-shot.
const HOLD_ACTIONS: Array[String] = ["hold", "sit", "sleep"]

## The natural release for each held pose. Documentation and a test fixture --
## *any* new instruction releases a hold, so content is never obliged to use
## these. They exist so the vocabulary reads as pairs rather than as a pile.
const HOLD_RELEASES: Dictionary = {
	"hold": "give",
	"sit": "stand",
	"sleep": "wake",
}

## Actions that change whether Little Buddy has something in his hands, applied
## when the action *finishes* -- hands are empty while reaching for a thing and
## full only once it has been picked up. `pickUp` -> carry -> `give` composes
## without content ever calling `set_carrying()` itself.
const CARRY_EFFECT: Dictionary = {
	"pickUp": true,
	"hold": true,
	"give": false,
}

## How long each action reads for when no clip length is available, in seconds.
## For a held pose this is the *settle* time -- how long getting into the pose
## takes -- not how long the pose lasts, which is until it is released.
##
## These are tuned for a small child watching: long enough to be noticed and
## narrated over, short enough that nothing feels like waiting. Contract §6 bans
## timers and failure pressure; these are pacing, not a clock.
const ACTION_DURATIONS: Dictionary = {
	"idle": 0.6,
	"walk": 1.0,
	"wave": 1.4,
	"point": 1.2,
	"clap": 1.4,
	"pickUp": 1.1,
	"hold": 0.6,
	"give": 1.2,
	"eat": 1.6,
	"drink": 1.8,
	"brushTeeth": 2.4,
	"sit": 0.9,
	"stand": 0.9,
	"hug": 2.0,
	"sleep": 1.4,
	"wake": 1.2,
	"celebrate": 1.6,
}

## Fallback for an action that is not in `ACTION_DURATIONS` at all.
const FALLBACK_DURATION_SEC: float = 1.2


## Is `action_name` a name the game recognises at all? Separate from `can_play()`:
## an action can be known (valid vocabulary) but not yet animated.
static func is_known_action(action_name: String) -> bool:
	return KNOWN_ACTIONS.has(action_name)


## True for a posture that persists until released, false for a one-shot.
## An unknown name is treated as a one-shot -- the safe default, because a
## one-shot always ends by itself.
static func is_hold_action(action_name: String) -> bool:
	return HOLD_ACTIONS.has(action_name)


## The action that most naturally ends `action_name`, or "" if it is not a hold.
static func release_action_for(action_name: String) -> String:
	return String(HOLD_RELEASES.get(action_name, ""))


## `true` (now carrying), `false` (no longer carrying), or `null` (no effect).
## Deliberately a three-valued answer: "no opinion" is not the same as "empty
## handed", and collapsing them would make every `wave` put down the teddy.
static func carry_effect(action_name: String) -> Variant:
	return CARRY_EFFECT.get(action_name, null)


## How long `action_name` should read for, before any clip length is consulted.
static func default_duration(action_name: String) -> float:
	return float(ACTION_DURATIONS.get(action_name, FALLBACK_DURATION_SEC))


## Can this driver actually show `action_name` right now?
func can_play(_action_name: String) -> bool:
	return false


## The natural length of `action_name` as this driver would play it, or a
## negative number when the driver has no opinion (which is the normal case, and
## means "use the semantic default"). Lets an authored clip time its own action,
## so a two-second drink animation is not cut off after 1.2 s.
func get_action_duration(_action_name: String) -> float:
	return -1.0


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


## How fast the character is actually travelling, as a fraction of
## `CharacterMovementController.WALK_SPEED`.
##
## The walk clip and the walk speed are ONE decision: the cycle was authored so
## that at 1.05 m/s the stride exactly matches the ground covered and the feet do
## not skate. The virtual thumbstick broke that pairing by introducing speeds
## BETWEEN zero and the walk speed -- at half deflection the clip would play at
## full rate while the body moved half as far, and the feet would slide.
##
## So the locomotion clip is played at the speed the body is really going. A
## driver with no clips has nothing to scale and ignores this.
func set_locomotion_scale(_scale: float) -> void:
	pass
