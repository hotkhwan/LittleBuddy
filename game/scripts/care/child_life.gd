extends RefCounted

## ============================================================================
## WHAT BUNNY IS DOING WITH HIS BODY -- derived, like everything else about him.
## ============================================================================
##
## `child_needs.gd` decides what is TRUE. `child_presentation.gd` decides which
## MESH to show. Neither answers the question this file answers: given the same
## mesh and the same need, **what should the character be doing right now** --
## breathing, fussing, being fed, or pleased with you.
##
## It is pure: Strings, floats and Dictionaries. No node, no clip resource, no
## `AnimationPlayer`. `child_actor.gd` takes the answer and plays it. That split
## is what lets `test_bunny_life.gd` assert "a hungry Bunny fusses, and fusses
## harder the hungrier he is" without instantiating 14,000 triangles of baby.
##
## ## The hunger gradient is the point
##
## The brief asks for a visible distress cue "tied to the REAL ChildStats hunger
## axis", and the trap is to make it a switch: below 40, serene; at 40, fussing.
## A switch tells a child nothing about *getting worse*, and it makes the moment
## of feeding feel arbitrary because the state that preceded it had no shape.
##
## So `distress()` is continuous across the same two numbers `child_needs.gd`
## already uses -- `HUNGRY_AT` (the point Bunny starts asking) and
## `CRYING_SEVERITY` (the point asking nicely has stopped working) -- and
## `fuss_pace()` turns it into the speed of the fuss clip. Same motion, more
## urgency. No bar, no number, no percentage, and nothing a four-year-old has to
## read (`CLAUDE.md`, Child UX).
##
## ## Attention is a courtesy, not a mechanic
##
## `should_attend()` decides whether Bunny turns to look at Aliz. It is distance
## only, with a hysteresis band, because a character that snaps round the instant
## the caregiver crosses an exact radius -- and snaps back when she wobbles over
## it again -- reads as broken rather than attentive.

const Needs := preload("res://scripts/care/child_needs.gd")
const Present := preload("res://scripts/care/child_presentation.gd")

## The clip names `baby_life_clips.gd` authors. Named here as Strings rather than
## imported, because this file must stay free of anything that loads a model.
const LIFE_IDLE: String = "idle"
const LIFE_FUSS: String = "fuss"
const LIFE_EAT: String = "eat"
const LIFE_DRINK: String = "drink"
const LIFE_HAPPY: String = "celebrate"
const LIFE_SLEEP: String = "sleep"
const LIFE_WALK: String = "walk"
## Held in the caregiver's arms: legs tucked up, hands resting, head looking
## about. A posture, like sleep, so it beats the needs -- a hungry child being
## carried is still hungry (the bubble says so) but he is not standing and
## fussing in mid-air.
const LIFE_CARRIED: String = "carried"
## The little foot stamp -- one-shot, 0.9 s -- for a need that has gone
## unanswered a while. The body's "hmph", to go with the face's. Never a
## loop: he stamps once, then goes back to fussing and asking.
const LIFE_STAMP: String = "stamp"

const LIFE_CLIPS: Array[String] = [
	LIFE_IDLE, LIFE_FUSS, LIFE_EAT, LIFE_DRINK, LIFE_HAPPY, LIFE_SLEEP, LIFE_WALK,
	LIFE_CARRIED, LIFE_STAMP,
]

## -- The face --------------------------------------------------------------------
##
## The rigged model has NO facial bones -- the rig ends at `headfront` and the
## eyes, brows and mouth are painted into the albedo -- so the face cannot be
## animated. It can be REPAINTED, which is a different and much cheaper thing:
## `baby_face_moods.gd` redraws the eye and mouth islands of the atlas and the
## wrapper swaps the texture. Four variants, no per-frame work, nothing to
## interpolate.
##
## Named here as plain Strings, like the clips, because this file must stay free
## of anything that loads a model or an `Image`.
const FACE_CONTENT: String = "content"
const FACE_UNHAPPY: String = "unhappy"
const FACE_DELIGHTED: String = "delighted"
const FACE_ASLEEP: String = "asleep"
## Added 2026-09-20 so urgency is readable on the face as well as the bubble:
## a pout with pleading brows for hunger and thirst, half-lidded eyes for a
## child who is sleepy but not yet in bed, and the "hmph" -- brows in, puffed
## cheeks -- for a need that has been ignored.
const FACE_HUNGRY: String = "hungry"
const FACE_SLEEPY: String = "sleepy"
const FACE_HMPH: String = "hmph"

const FACE_MOODS: Array[String] = [
	FACE_CONTENT, FACE_UNHAPPY, FACE_DELIGHTED, FACE_ASLEEP,
	FACE_HUNGRY, FACE_SLEEPY, FACE_HMPH,
]

## -- Being ignored --------------------------------------------------------------
##
## A need voiced this long without being answered escalates: the bubble says
## its louder line (`child_needs.gd::LINES_URGENT`), the face goes to `hmph`,
## and every `STAMP_EVERY_SEC` after that the body stamps a foot once. It is
## still a request -- nothing is lost, nothing counts down, and the moment the
## need is met it all goes with the need. The number is long enough that a
## player walking over from the next room never sees it.
const IGNORED_AFTER_SEC: float = 12.0
const STAMP_EVERY_SEC: float = 6.0

## The idle plays this much slower while Bunny is sleepy: heavier breathing,
## a slower look-around. Same clip, different pace -- the trick `fuss` uses.
const SLEEPY_IDLE_PACE: float = 0.72

## How long Bunny stays visibly pleased after being cared for. Long enough to be
## seen and short enough that he is not still celebrating a bottle two rooms
## later. Not a timer the player races: nothing is lost when it ends.
const HAPPY_SECONDS: float = 3.2

## The fuss clip's playback rate at `distress() == 0` and at `distress() == 1`.
## Under 1.0 at the bottom on purpose: the first sign of hunger should be slower
## and heavier than serene breathing, not busier.
const FUSS_PACE_CALM: float = 0.78
const FUSS_PACE_URGENT: float = 1.55

## Metres. Bunny notices Aliz inside `ATTEND_NEAR` and gives up on her outside
## `ATTEND_FAR`; the gap is the hysteresis that stops him pivoting on the spot
## while she shuffles at the edge.
const ATTEND_NEAR: float = 2.1
const ATTEND_FAR: float = 2.7

## Degrees per second. A small child turns its head and shoulders unhurriedly;
## anything quicker looks mechanical, and the turn is the whole cue.
const TURN_RATE_DEG: float = 115.0

## How far Bunny will turn to watch Aliz, in degrees.
##
## **Set by rendering it, twice.** The first value was 78 -- roughly how far a
## real toddler turns before stepping round -- and in the bedroom shot it put
## Bunny side-on to a camera that is fixed at +Z, so the player got the back of
## his ear and the mission's "I'm hungry!" came from a child with no face.
##
## 45 is a three-quarter view: unmistakably turned towards Aliz, still looking
## out of the screen. The camera does not move in this game, so how far a
## character may turn is a framing decision, not an anatomy one.
const ATTEND_LIMIT_DEG: float = 45.0


## **The clip Bunny should be playing.** One answer, from the same inputs the
## rest of the care model uses.
##
## Precedence, and every step of it is deliberate:
##   1. **walking wins over everything** -- a fussing child sliding across the
##      floor in a fuss pose is the worst thing on this list;
##   2. then the explicit activity, because a mission that has put Bunny down to
##      feed him or to sleep has said what is happening and must not be argued
##      with;
##   3. then the happy window, so being cared for is visible for its own sake;
##   4. then a real unmet need;
##   5. then idle.
static func clip_for(stats: Dictionary, activity: String, walking: bool,
		happy_left: float, detail: String = "", stamp: bool = false) -> String:
	if walking:
		return LIFE_WALK
	# Being carried is a whole-body posture; nothing else can play at the same
	# time, and it is the caregiver's act, so it wins over the child's own state.
	if activity == Present.ACTIVITY_CARRIED:
		return LIFE_CARRIED
	if activity == Present.ACTIVITY_FEEDING:
		return feeding_clip(stats, detail)
	# Bedtime beats the happy window as well as the need. Being tucked in IS the
	# care act, so a child who celebrates it by standing up again has undone the
	# thing the player just did.
	if activity == Present.ACTIVITY_BEDTIME:
		return LIFE_SLEEP
	if happy_left > 0.0:
		return LIFE_HAPPY
	if _is_uncomfortable(Needs.dominant(stats)):
		# `stamp` is the actor saying "the stamp is due now" (see
		# `stamp_due()`); it is a one-shot, so the next refresh is a fuss again.
		return LIFE_STAMP if stamp else LIFE_FUSS
	return LIFE_IDLE


## **The face that goes with the body.** One answer, derived from the clip that
## was already chosen, so the mouth can never disagree with the arms.
##
## Deliberately NOT a fifth reaction axis of its own: every route into a mood
## goes through `clip_for()` first, which is the function the whole care model
## already agrees on. A face that could be set independently is a face that would
## end up smiling through a fuss the first time somebody added a branch.
##
## `eat` and `drink` keep the resting face. A child mid-spoonful is neither
## delighted nor upset, and swapping the mouth for an open grin exactly when a
## bottle is covering it buys nothing.
##
## `need` and `ignored_for` refine the answer WITHIN the clip, never against it:
## a fuss for hunger or thirst wears the pout (`hungry`), a fuss that has gone
## on past `IGNORED_AFTER_SEC` wears the `hmph`, a fuss for anything else stays
## `unhappy`; an idle while the child is sleepy is half-lidded. Called with the
## clip alone, the mapping is the original one.
static func face_for(clip: String, need: String = "", ignored_for: float = 0.0) -> String:
	match clip:
		LIFE_FUSS:
			if is_ignored(ignored_for):
				return FACE_HMPH
			if need == Needs.HUNGRY or need == Needs.THIRSTY:
				return FACE_HUNGRY
			return FACE_UNHAPPY
		LIFE_STAMP:
			return FACE_HMPH
		LIFE_HAPPY:
			return FACE_DELIGHTED
		LIFE_SLEEP:
			return FACE_ASLEEP
		LIFE_CARRIED:
			# Picked up is the thing a small child wants most; he beams.
			return FACE_DELIGHTED
		LIFE_IDLE:
			return FACE_SLEEPY if need == Needs.SLEEPY else FACE_CONTENT
		_:
			return FACE_CONTENT


## Has a need waited long enough to escalate? Pure, so the actor, the face and
## the line all agree on the moment.
static func is_ignored(ignored_for: float) -> bool:
	return ignored_for >= IGNORED_AFTER_SEC


## Is a stamp due? One at the moment of escalation, then one every
## `STAMP_EVERY_SEC`; `last_stamp_at` is the `ignored_for` value the previous
## stamp was played at (negative for none).
static func stamp_due(ignored_for: float, last_stamp_at: float) -> bool:
	if not is_ignored(ignored_for):
		return false
	if last_stamp_at < 0.0:
		return true
	return ignored_for - last_stamp_at >= STAMP_EVERY_SEC


## Does this need count towards being ignored? Only the ones the body shows.
static func is_uncomfortable_need(need: String) -> bool:
	return _is_uncomfortable(need)


## **A bottle or a spoon?** They are different motions -- two hands and a head
## tipped back, against one hand to the mouth -- and getting it wrong is the kind
## of small wrongness a four-year-old notices and an adult does not.
##
## The caller's `detail` (a care kind, e.g. `giveBottle`) settles it when there is
## one. There usually is not, because `house_level_director.gd` passes only
## "feeding" today, so the fallback reads the child's own stats: whichever of
## thirst and hunger is further past the point at which it starts to matter. It
## is a heuristic and is not pretending otherwise -- but it is a heuristic over
## the REAL stats, so it is at least always consistent with the need the child is
## voicing at the time.
static func feeding_clip(stats: Dictionary, detail: String = "") -> String:
	match detail:
		"giveBottle", "drink":
			return LIFE_DRINK
		"giveSnack", "feed", "eat":
			return LIFE_EAT
	var thirst_over: float = float(stats.get("thirst", 0.0)) - Needs.THIRSTY_AT
	var hunger_over: float = float(stats.get("hunger", 0.0)) - Needs.HUNGRY_AT
	return LIFE_DRINK if thirst_over > hunger_over else LIFE_EAT


## The needs that show on the body. `sleepy` and `wantsToPlay` are real needs and
## are deliberately NOT here: they are answered by a pose and a line, and a child
## who fusses about everything teaches that fussing means nothing.
static func _is_uncomfortable(need: String) -> bool:
	return need in [Needs.CRYING, Needs.HUNGRY, Needs.THIRSTY, Needs.NEEDS_COMFORT]


## **How badly.** 0.0 at the moment Bunny starts asking, 1.0 where `child_needs`
## says asking nicely has stopped working. Continuous, and read off the same
## hunger/thirst values the need itself is derived from -- there is no second
## number anywhere that could drift out of step with the first.
static func distress(stats: Dictionary) -> float:
	var span: float = Needs.CRYING_SEVERITY - Needs.HUNGRY_AT
	if span <= 0.0:
		return 0.0
	var hunger: float = (float(stats.get("hunger", 0.0)) - Needs.HUNGRY_AT) / span
	var thirst: float = (float(stats.get("thirst", 0.0)) - Needs.THIRSTY_AT) / span
	# Unhappiness counts too, and counts DOWN -- `crying` is reachable through
	# happiness alone, and a Bunny crying about that should not stand serenely.
	var unhappy: float = (Needs.COMFORT_BELOW - float(stats.get("happiness", 100.0))) \
			/ Needs.COMFORT_BELOW
	return clampf(maxf(maxf(hunger, thirst), unhappy), 0.0, 1.0)


## The fuss clip's playback rate for that distress. The gradient a child can see.
static func fuss_pace(distress_level: float) -> float:
	return lerpf(FUSS_PACE_CALM, FUSS_PACE_URGENT, clampf(distress_level, 0.0, 1.0))


## Every clip except the fuss plays at its authored pace. Stated as a function so
## `child_actor.gd` has one thing to ask and no branch of its own.
static func pace_for(clip: String, distress_level: float, need: String = "") -> float:
	if clip == LIFE_FUSS:
		return fuss_pace(distress_level)
	if clip == LIFE_IDLE and need == Needs.SLEEPY:
		return SLEEPY_IDLE_PACE
	return 1.0


## Should Bunny be looking at Aliz? `attending` is the current answer, so the
## band can be applied -- see the class doc on why a bare radius reads as broken.
static func should_attend(distance: float, attending: bool) -> bool:
	if attending:
		return distance <= ATTEND_FAR
	return distance <= ATTEND_NEAR


## One step of the turn, in degrees. Takes the shortest way round and never
## overshoots, so a caller can drive it straight from `_process` without a tween.
##
## Returned rather than applied: the angle is a float and this file holds no
## node, which is what keeps the care model testable without a scene.
static func turn_towards(current_deg: float, target_deg: float, delta: float,
		rate_deg: float = TURN_RATE_DEG) -> float:
	var difference: float = shortest_turn(current_deg, target_deg)
	var step: float = rate_deg * maxf(delta, 0.0)
	if absf(difference) <= step:
		return wrapf(target_deg, -180.0, 180.0)
	return wrapf(current_deg + signf(difference) * step, -180.0, 180.0)


## The signed shortest angle from `from_deg` to `to_deg`, in (-180, 180].
static func shortest_turn(from_deg: float, to_deg: float) -> float:
	return wrapf(to_deg - from_deg, -180.0, 180.0)


## The yaw Bunny should hold: the direction of Aliz, clamped so he never twists
## further than a small child comfortably would. Past the limit he looks as far
## as he can and no further, rather than snapping to face backwards.
static func attend_yaw(wanted_deg: float) -> float:
	return clampf(wrapf(wanted_deg, -180.0, 180.0), -ATTEND_LIMIT_DEG, ATTEND_LIMIT_DEG)
