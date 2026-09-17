extends RefCounted

## What a four-year-old is shown the first time they reach the house, as data.
##
## The player cannot read. So the plan below is not a script of paragraphs; it is
## a list of **gestures to animate and sentences to say**, and each step names the
## one thing the child could do to finish it early. Nothing here is a wall: every
## step carries a `timeoutSec`, and a step that times out simply moves on.
##
## ## Pure domain
##
## RefCounted, Strings and floats only -- no `Node`, no `Vector3`, no TTS, no
## save file. That is what lets the whole shape of first-run be asserted in the
## headless runner, where `_ready()` never fires and no frame is ever drawn.
##
## ## The five beats
##
## ```
##   meet      Little Buddy waves.  "Hi! I am Little Buddy."
##   tapFloor  a hand taps a pulsing ripple on the floor.  He walks there.
##   tapThing  the hand moves to a real object.  He walks to it and uses it.
##   drag      the hand DEMONSTRATES a drag, left to right, with a trail.
##   go        "Let's play!"  Everything fades and the child is playing.
## ```
##
## `tapThing` is the one the child actually completes -- the brief's "one easy
## action". `drag` is shown rather than demanded on purpose: requiring a
## four-year-old's first drag before they are allowed to play is exactly the dead
## end `SLICE_CONTRACT` section 6 forbids, and the gesture reads perfectly well as
## a demonstration.
##
## ## Skipping
##
## There is no Skip button, because a Skip button is a word. Instead:
##
##   * every step advances by itself after `timeoutSec`;
##   * a child who does the thing early advances immediately;
##   * world input is never disabled, so a child who ignores all of it is simply
##     playing the game already;
##   * and the whole run is under half a minute even if nobody touches anything.

## Where completion is remembered. A plain `settings` key, so no save-schema
## change was needed: `ProfileStore._sanitize()` preserves unknown JSON-safe
## settings values verbatim, and `SaveService.set_setting()` writes through to
## disk. See `test_onboarding.gd`.
const SETTING_KEY: String = "onboardingDone"

const STEP_MEET: String = "meet"
const STEP_TAP_FLOOR: String = "tapFloor"
const STEP_TAP_THING: String = "tapThing"
const STEP_DRAG: String = "drag"
const STEP_GO: String = "go"

## What the hint overlay animates for a step.
const GESTURE_NONE: String = "none"
## A pulsing ring around Little Buddy and **no pointing hand**: he is not
## tappable, and a hand there sits squarely over the one face in the game.
const GESTURE_MEET: String = "meet"
const GESTURE_TAP_FLOOR: String = "tapFloor"
const GESTURE_TAP_TARGET: String = "tapTarget"
const GESTURE_DRAG: String = "drag"

## What the child can do to finish a step early. "" means "nothing; it is a
## beat, not a task".
const REQUIRES_NOTHING: String = ""
const REQUIRES_WALK: String = "walked"
const REQUIRES_ARRIVAL: String = "arrivedAtTarget"

## No step may ever be longer than this, however it is edited later. A tutorial a
## child cannot get out of is a dead end with a friendly voice.
const MAX_STEP_SECONDS: float = 14.0

## `"%s"` is filled in with the display name of a real object in the room the
## child is actually standing in, so the line is never a lie about the scene.
const TAP_THING_TEMPLATE: String = "Now tap the %s!"
## Used when the room somehow has nothing tappable in it.
const TAP_THING_FALLBACK: String = "Now tap something!"


## The whole first-run sequence, in order. A fresh Array every call, so a caller
## may mutate the result freely.
static func steps() -> Array:
	return [
		{
			"stepId": STEP_MEET,
			"speech": "Hi! I am Little Buddy.",
			"gesture": GESTURE_MEET,
			"requires": REQUIRES_NOTHING,
			"timeoutSec": 3.6,
			"characterAction": "wave",
		},
		{
			"stepId": STEP_TAP_FLOOR,
			"speech": "Tap the floor. I will walk!",
			"gesture": GESTURE_TAP_FLOOR,
			"requires": REQUIRES_WALK,
			"timeoutSec": 9.0,
			"characterAction": "",
		},
		{
			"stepId": STEP_TAP_THING,
			"speech": TAP_THING_FALLBACK,
			"gesture": GESTURE_TAP_TARGET,
			"requires": REQUIRES_ARRIVAL,
			"timeoutSec": 12.0,
			"characterAction": "",
		},
		{
			"stepId": STEP_DRAG,
			"speech": "You can move things. Drag them with your finger.",
			"gesture": GESTURE_DRAG,
			"requires": REQUIRES_NOTHING,
			"timeoutSec": 5.0,
			"characterAction": "",
		},
		{
			"stepId": STEP_GO,
			"speech": "Now let's play!",
			"gesture": GESTURE_NONE,
			"requires": REQUIRES_NOTHING,
			"timeoutSec": 2.4,
			"characterAction": "celebrate",
		},
	]


static func total() -> int:
	return steps().size()


## The step at `index`, or an empty Dictionary past the end. Shaped like a real
## step either way, so a caller never has to test for null before reading a key.
static func step_at(index: int) -> Dictionary:
	var all: Array = steps()
	if index < 0 or index >= all.size():
		return {
			"stepId": "",
			"speech": "",
			"gesture": GESTURE_NONE,
			"requires": REQUIRES_NOTHING,
			"timeoutSec": 0.0,
			"characterAction": "",
		}
	return all[index]


static func step_ids() -> Array:
	var ids: Array = []
	for step: Variant in steps():
		ids.append(String((step as Dictionary).get("stepId", "")))
	return ids


static func is_last(index: int) -> bool:
	return index >= steps().size() - 1


## How long the whole run takes if the child never touches the screen. The
## guarantee that first-run is a moment, not a lesson.
static func total_seconds() -> float:
	var seconds: float = 0.0
	for step: Variant in steps():
		seconds += float((step as Dictionary).get("timeoutSec", 0.0))
	return seconds


## Should first-run play, given whatever `settings.onboardingDone` held?
##
## **Only an explicit `true` counts as done.** A missing key, a `null`, a
## `false`, a string, a number written by a future build -- every one of them
## means "this child has not been shown the game yet", which is the safe way
## round: showing a short intro twice is a small cost, never showing it at all is
## a child staring at a house with no idea that it can be tapped.
static func should_run(setting_value: Variant) -> bool:
	if typeof(setting_value) == TYPE_BOOL:
		return not bool(setting_value)
	return true


## The line for the "tap a thing" step, given the display name of a real object
## in the child's room.
static func tap_thing_speech(display_name: String) -> String:
	var name: String = display_name.strip_edges()
	if name.is_empty():
		return TAP_THING_FALLBACK
	return TAP_THING_TEMPLATE % name
