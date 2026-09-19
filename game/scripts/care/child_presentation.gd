extends RefCounted

## ============================================================================
## HOW A NEED LOOKS -- the one place a need becomes a pose.
## ============================================================================
##
## P2 asks that the three Meshy babies be used as ONE logical child:
##
##   standing -- movement and active interaction
##   seated   -- feeding and playing
##   sleeping -- bedtime and swaddle
##
## and that they never appear at once. This file is the mapping, kept apart from
## both the needs model and the wrapper so that:
##
##   * `child_needs.gd` decides what is TRUE without knowing any pose exists;
##   * `baby_little_buddy.gd` knows how to SHOW a pose without knowing why;
##   * this file is the only thing that has to change when a fourth pose arrives.
##
## ## Why a pose is chosen by ACTIVITY, not by need
##
## The obvious design -- one pose per need -- reads badly. A hungry child and a
## thirsty child are both fed the same way, and switching pose between them would
## make the child twitch for no reason the player can see. So the caller names
## what is HAPPENING (`feeding`, `bedtime`, `play`) and the need only decides the
## activity when nothing else has.
##
## ## A pose change is a cut, and the wrapper says so
##
## `baby_little_buddy.gd` is explicit that swapping pose is a visibility cut with
## no blend, because the exports are separate models. So this file keeps changes
## RARE and tied to a real beat -- the brief's "make transitions deliberate" --
## rather than letting a drifting stat flip the mesh mid-step.
##
## **And rarer still since the rig landed.** A pose cut now also costs the
## character its motion: only the `rigged` export has a skeleton, so every cut
## away from it is a cut to something that cannot breathe, fuss or be fed. See
## `pose_for_activity()`, which is down to one such cut.

const Needs := preload("res://scripts/care/child_needs.gd")

const POSE_STANDING: String = "standing"
const POSE_SITTING: String = "sitting"
const POSE_SLEEPING: String = "sleeping"
## The rigged runtime model. Preferred wherever a pose-locked export would do,
## because it is the only one with a skeleton, sockets and clips -- so it can be
## posed AND can move, and it is the one that ships.
const POSE_RIGGED: String = "rigged"

## What the caregiver is doing with the child right now.
const ACTIVITY_IDLE: String = "idle"
const ACTIVITY_FEEDING: String = "feeding"
const ACTIVITY_PLAY: String = "play"
const ACTIVITY_BEDTIME: String = "bedtime"
const ACTIVITY_BATH: String = "bath"
const ACTIVITY_DRESSING: String = "dressing"
const ACTIVITY_CARRIED: String = "carried"

const ACTIVITIES: Array[String] = [
	ACTIVITY_IDLE, ACTIVITY_FEEDING, ACTIVITY_PLAY, ACTIVITY_BEDTIME,
	ACTIVITY_BATH, ACTIVITY_DRESSING, ACTIVITY_CARRIED,
]


## The pose an activity calls for.
##
## **Changed 2026-09-19, and the reason matters more than the mapping.** This used
## to seat the child for `feeding` and `play`, because when it was written the
## only babies in the project were three frozen exports and *seating him was the
## only way the game had of saying "this is feeding"*.
##
## That is no longer true, and keeping it did active harm. `sitting` is an
## unrigged 398,404-triangle statue with no skeleton and no clips, so selecting it
## for feeding meant: at the exact moment the player finally does the thing the
## whole mission is about, Bunny cuts to a mesh that **cannot react at all** --
## and, because `hungry` implies `feeding` through `activity_for_need()`, that
## statue was what stood in the bedroom for the entire opening of the game. The
## "rigid statue" this pass was asked to fix was, in the largest part, this line.
##
## The rigged export now carries hand-authored `eat`, `drink`, `fuss`, `idle` and
## `celebrate` clips on its real skeleton (`baby_life_clips.gd`), so it can SHOW
## being fed rather than being posed as though it had been. So the rule is now
## the one the paragraph above always claimed: **a pose-locked export is used only
## where it says something the rigged model cannot.**
##
## That leaves exactly one: `sleeping`. Lying supine is a whole-body pose with no
## clip behind it, and no amount of arm animation implies it. `sitting` and
## `standing` stay in the vocabulary as the graceful degradation -- a build
## without the rigged export resolves `rigged` down to `sitting` inside
## `baby_little_buddy.gd::resolve_pose()`, so this mapping does not need to know
## which files shipped.
static func pose_for_activity(activity: String) -> String:
	match activity:
		ACTIVITY_BEDTIME:
			return POSE_SLEEPING
		_:
			return POSE_RIGGED


## The activity a need implies when the caregiver has not started one. Only used
## as a fallback, so a child who is sleepy in the middle of a bath does not lie
## down in the water.
static func activity_for_need(need: String) -> String:
	match need:
		Needs.HUNGRY, Needs.THIRSTY:
			return ACTIVITY_FEEDING
		Needs.SLEEPY:
			return ACTIVITY_BEDTIME
		Needs.NEEDS_BATH, Needs.DIRTY:
			return ACTIVITY_BATH
		Needs.NEEDS_CHANGING:
			return ACTIVITY_DRESSING
		Needs.WANTS_TO_PLAY:
			return ACTIVITY_PLAY
		_:
			return ACTIVITY_IDLE


## The full decision: what the child should look like, given what is happening
## and what it needs. Returns
## `{"pose", "activity", "need", "line", "mood"}`.
##
## An explicit `activity` always wins. That is what makes a mission able to seat
## the child for Milk Time even while some other stat is drifting -- the brief's
## "make transitions deliberate".
static func describe(stats: Dictionary, activity: String = ACTIVITY_IDLE) -> Dictionary:
	var need: String = Needs.dominant(stats)
	var chosen: String = activity
	if chosen == ACTIVITY_IDLE:
		chosen = activity_for_need(need)
	return {
		"pose": pose_for_activity(chosen),
		"activity": chosen,
		"need": need,
		"line": Needs.line_for(need),
		"mood": mood_for(need),
	}


## The view state the existing `BabyView3D` vocabulary already understands, so
## the procedural fallback reacts to a need too rather than only the Meshy model.
## `BabyView3D` knows: idle, hungry, drinking, happy, hugging.
static func mood_for(need: String) -> String:
	match need:
		Needs.HUNGRY, Needs.THIRSTY:
			return "hungry"
		Needs.CRYING, Needs.NEEDS_COMFORT:
			return "hugging"
		Needs.NONE:
			return "happy"
		_:
			return "idle"
