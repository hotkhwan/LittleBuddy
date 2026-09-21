extends RefCounted

## ============================================================================
## TutorGesturePool -- which gesture (and face) Aliz gives a lesson EVENT, with
## a little deterministic variety so two correct answers in a row never look
## the same.
## ============================================================================
##
## Pure and static: no nodes, no 3D types, no randomness, no I/O. The scene
## calls `pick(event, seed)` with the step index or turn count as the seed and
## hands the result to `play_gesture()`; the face comes from
## `expression_for(event)`. The table lives in docs/ALIZ_GESTURES.md.
##
##   event       pool (in order)              expression   note
##   correct     thumbsUp, clap, nod          happy        "nod" is nod + smile:
##                                                          the face is `happy`
##   excellent   celebrate                    happy        three correct in a row
##                                                          or the lesson done;
##                                                          `reward_hook_for()`
##                                                          names the scene's
##                                                          reward ("confetti")
##   greeting    wave                         smile
##   listening   listening                    listening
##   thinking    thinking                     thinking
##   encourage   encourage                    encouraging  wrong answer / retry
##   farewell    wave                         happy
##
## Variety rule: for an event with more than one gesture, `pick(event, seed)`
## is deterministic in the seed and NEVER returns what it returned for
## `seed - 1` -- consecutive positives differ whatever the seed sequence.
## The walk is a fixed stride through the pool: with a pool of N the stride
## is coprime with N and never 0 mod N, so seed and seed - 1 always land on
## different entries, and the sequence for 0, 1, 2, ... visits every entry.
## Single-entry pools have nothing to vary and return their one gesture.
##
## Every gesture named here is in `buddy_gesture_clips.gd::GESTURE_NAMES` and
## in the TutorTurn enum (`tutor_turn.gd::GESTURES`); the pool test keeps that
## true.

const EVENT_CORRECT: String = "correct"
const EVENT_EXCELLENT: String = "excellent"
const EVENT_GREETING: String = "greeting"
const EVENT_LISTENING: String = "listening"
const EVENT_THINKING: String = "thinking"
const EVENT_ENCOURAGE: String = "encourage"
const EVENT_FAREWELL: String = "farewell"
const EVENTS: Array[String] = [
	EVENT_CORRECT, EVENT_EXCELLENT, EVENT_GREETING, EVENT_LISTENING,
	EVENT_THINKING, EVENT_ENCOURAGE, EVENT_FAREWELL,
]

## Ordered pools. Order matters: it is the walk order for the stride.
const POOLS: Dictionary = {
	EVENT_CORRECT: ["thumbsUp", "clap", "nod"],
	EVENT_EXCELLENT: ["celebrate"],
	EVENT_GREETING: ["wave"],
	EVENT_LISTENING: ["listening"],
	EVENT_THINKING: ["thinking"],
	EVENT_ENCOURAGE: ["encourage"],
	EVENT_FAREWELL: ["wave"],
}

const EXPRESSIONS: Dictionary = {
	EVENT_CORRECT: "happy",
	EVENT_EXCELLENT: "happy",
	EVENT_GREETING: "smile",
	EVENT_LISTENING: "listening",
	EVENT_THINKING: "thinking",
	EVENT_ENCOURAGE: "encouraging",
	EVENT_FAREWELL: "happy",
}

## Correct answers in a row that turn `correct` into `excellent`.
const EXCELLENT_STREAK: int = 3
## The scene's reward hook name for `excellent` (a signal / SFX / particle
## the scene owns; nothing here plays it).
const REWARD_HOOK_EXCELLENT: String = "confetti"
const REWARD_HOOK_NONE: String = ""

## What an unknown event gets: nothing to play, a neutral face.
const NO_GESTURE: String = "none"
const NEUTRAL_EXPRESSION: String = "neutral"


static func is_event(event: String) -> bool:
	return POOLS.has(event)


## The gesture for `event` at `seed` (the step index or turn count). "none"
## for an event outside the table. Deterministic; never the same as `seed - 1`
## for a pool with more than one entry.
static func pick(event: String, seed: int) -> String:
	if not POOLS.has(event):
		return NO_GESTURE
	var pool: Array = POOLS[event]
	if pool.size() == 1:
		return String(pool[0])
	return String(pool[_index_for(seed, pool.size())])


## The whole pool for `event`, in walk order; empty for an unknown event.
static func pool_for(event: String) -> Array:
	if not POOLS.has(event):
		return []
	return (POOLS[event] as Array).duplicate()


static func expression_for(event: String) -> String:
	return String(EXPRESSIONS.get(event, NEUTRAL_EXPRESSION))


## The scene's reward hook for `event`: "confetti" for `excellent`, else "".
static func reward_hook_for(event: String) -> String:
	return REWARD_HOOK_EXCELLENT if event == EVENT_EXCELLENT else REWARD_HOOK_NONE


## Which positive event a correct answer is: `excellent` when it completes the
## lesson or makes a streak of `EXCELLENT_STREAK`, else `correct`.
static func positive_event(streak: int, lesson_complete: bool = false) -> String:
	if lesson_complete or (streak > 0 and streak % EXCELLENT_STREAK == 0):
		return EVENT_EXCELLENT
	return EVENT_CORRECT


## The pool index for `seed` in a pool of `size` (> 1). A stride that is
## coprime with `size` (so the walk visits every entry) and not 0 mod `size`
## (so `seed` and `seed - 1` always differ). Negative seeds work too.
static func _index_for(seed: int, size: int) -> int:
	var stride: int = _stride_for(size)
	return posmod(seed * stride, size)


static func _stride_for(size: int) -> int:
	# The largest stride below size that is coprime with it: for 3 that is 2,
	# for 4 it is 3, for 5 it is 4 -- a walk that skips rather than steps, so
	# the order does not read as a list being recited.
	var stride: int = size - 1
	while stride > 1 and _gcd(stride, size) != 1:
		stride -= 1
	return maxi(stride, 1)


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t: int = b
		b = a % b
		a = t
	return a
