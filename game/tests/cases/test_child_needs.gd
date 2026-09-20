extends RefCounted

## What Little Buddy needs, and how it shows.
##
## The brief's wording is the specification: the nine child states must be
## "coherent gameplay state, not unrelated visual flags". So the things pinned
## here are the ones that would be violated by nine independent booleans:
##
##   1. **Every state is derived.** Nothing is stored, so nothing can drift out
##      of step with `ChildStats`.
##   2. **The child signals ONE thing.** `dominant()` is total and ordered, so
##      the presentation always has exactly one answer and the caregiver always
##      has one obvious next action.
##   3. **Urgency beats preference.** A child who is hungry AND wants to play
##      gets fed. A game that announced "wantsToPlay" there would teach the wrong
##      thing about looking after someone.
##   4. **Crying is a summary, not a tenth need.** It appears when several needs
##      go unmet at once, or one goes far past asking nicely -- never on its own.
##   5. **Never three babies at once.** A pose is chosen by ACTIVITY, and an
##      explicit activity always wins, so a drifting stat cannot flip the mesh
##      mid-step.
##   6. **Nothing accuses the child.** These lines are spoken by an infant.

const Needs := preload("res://scripts/care/child_needs.gd")
const Present := preload("res://scripts/care/child_presentation.gd")
const StatsScript := preload("res://scripts/care/child_stats.gd")
const Life := preload("res://scripts/care/child_life.gd")
const LifeClips := preload("res://scripts/characters/little_buddy/baby_life_clips.gd")

## Words an infant must never be made to say about itself.
const BANNED: Array[String] = ["bad", "naughty", "wrong", "fail", "stupid", "dirty child"]


func test_name() -> String:
	return "child_needs"


func run():
	var failures: Array = []
	failures.append_array(_test_every_named_state_exists())
	failures.append_array(_test_a_content_child_needs_nothing())
	failures.append_array(_test_one_need_at_a_time())
	failures.append_array(_test_urgency_beats_preference())
	failures.append_array(_test_crying_is_a_summary())
	failures.append_array(_test_dirty_and_bath_are_one_axis())
	failures.append_array(_test_poses_follow_activity_not_need())
	failures.append_array(_test_every_need_has_an_answer_and_a_line())
	failures.append_array(_test_it_derives_from_child_stats())
	return failures


## A content child: nothing wrong on any axis.
func _content() -> Dictionary:
	return {
		"hunger": 10.0, "thirst": 10.0, "happiness": 90.0,
		"energy": 90.0, "cleanliness": 90.0, "freshness": 90.0,
	}


func _test_every_named_state_exists():
	var failures: Array = []
	# The nine the brief names, verbatim.
	for required: String in ["hungry", "thirsty", "sleepy", "dirty", "wantsToPlay",
			"crying", "needsComfort", "needsBath", "needsChanging"]:
		if not Needs.PRIORITY.has(required):
			failures.append("the brief names '%s' but it is not a state" % required)
	if Needs.PRIORITY.size() != 9:
		failures.append("expected the brief's nine states, found %d" % Needs.PRIORITY.size())
	return failures


func _test_a_content_child_needs_nothing():
	var failures: Array = []
	if not Needs.is_content(_content()):
		failures.append("a child with every stat healthy still reports '%s'"
				% Needs.dominant(_content()))
	if Needs.dominant(_content()) != Needs.NONE:
		failures.append("a content child must report NONE, not a need")
	return failures


func _test_one_need_at_a_time():
	var failures: Array = []
	# Every combination of two broken axes must still yield exactly one answer.
	var breakers: Dictionary = {
		"hunger": 95.0, "thirst": 95.0, "energy": 5.0,
		"cleanliness": 5.0, "freshness": 5.0, "happiness": 5.0,
	}
	for a: String in breakers.keys():
		for b: String in breakers.keys():
			if a == b:
				continue
			var stats: Dictionary = _content()
			stats[a] = breakers[a]
			stats[b] = breakers[b]
			var got: String = Needs.dominant(stats)
			if got == Needs.NONE:
				failures.append("two broken stats (%s, %s) produced NO need" % [a, b])
			elif not Needs.PRIORITY.has(got):
				failures.append("dominant() returned '%s', which is not a known state" % got)
	return failures


func _test_urgency_beats_preference():
	var failures: Array = []
	var stats: Dictionary = _content()
	stats["hunger"] = 70.0        # hungry
	stats["happiness"] = 50.0     # and would like to play
	var got: String = Needs.dominant(stats)
	if got != Needs.HUNGRY:
		failures.append(("a child who is hungry AND wants to play must be fed first; "
				+ "dominant() said '%s'") % got)

	# ...and comfort beats play, for the same reason.
	var sad: Dictionary = _content()
	sad["happiness"] = 20.0
	if Needs.dominant(sad) != Needs.NEEDS_COMFORT:
		failures.append("an unhappy child should need comfort, got '%s'" % Needs.dominant(sad))
	return failures


func _test_crying_is_a_summary():
	var failures: Array = []
	# One mild need must NOT be crying.
	var mild: Dictionary = _content()
	mild["hunger"] = 50.0
	if Needs.dominant(mild) == Needs.CRYING:
		failures.append("a single mild need should not make the child cry")

	# Three unmet needs must be.
	var many: Dictionary = _content()
	many["hunger"] = 60.0
	many["energy"] = 10.0
	many["freshness"] = 10.0
	if Needs.dominant(many) != Needs.CRYING:
		failures.append(("three unmet needs should read as crying, got '%s'. Crying is the "
				+ "summary of the others.") % Needs.dominant(many))

	# One need far past asking nicely must be too.
	var severe: Dictionary = _content()
	severe["hunger"] = 95.0
	if Needs.dominant(severe) != Needs.CRYING:
		failures.append("a starving child should read as crying, got '%s'"
				% Needs.dominant(severe))
	return failures


func _test_dirty_and_bath_are_one_axis():
	var failures: Array = []
	var filthy: Dictionary = _content()
	filthy["cleanliness"] = 10.0
	var active: Array = Needs.active_states(filthy)
	if active.has(Needs.DIRTY) and active.has(Needs.NEEDS_BATH):
		failures.append(("a child reported BOTH 'dirty' and 'needsBath'. They are the same axis "
				+ "at two depths; reporting both double-counts towards crying."))
	if not active.has(Needs.NEEDS_BATH):
		failures.append("a very dirty child should need a bath")
	return failures


## **Rewritten 2026-09-19, and the rule it checks is stricter than before.**
##
## This used to assert that feeding SEATS the child, because when it was written
## the seated export was the only way the game could say "this is feeding". That
## turned out to be the single biggest cause of the "Bunny is a rigid statue"
## complaint: `sitting` is an unrigged 398,404-triangle mesh with no skeleton, and
## because `hungry` implies `feeding`, it was what stood in the bedroom for the
## whole opening of the game -- unable to breathe, fuss or react.
##
## The rule then became: **a pose-locked export may only be chosen where it says
## something the rigged model cannot.** There was exactly one such thing, lying
## down, so `bedtime` was the only activity allowed to leave the rig.
##
## **Tightened again 2026-09-20, and the exception is now gone.**
## `baby_life_clips.gd::_sleep()` lies the rigged child down with a root-bone
## rotation and a measured hip drop, so "the rigged model cannot show this" is no
## longer true of anything. The assertion below is therefore the strongest form
## of the same rule -- **no activity leaves the rig, at all** -- and it is paired
## with a check that the `sleep` clip really exists, because dropping the
## exception without the clip would swap a wrong-looking child for a rigid one.
##
## Why it is worth this much: the three exports are three separate generations of
## a baby, not three poses of one. `docs/shots/bunny_sleepy_near_before.png` is
## the `sleeping` one in the shipping bedroom, and it has different hair, a
## different nappy and different proportions. Going to bed did not pose Bunny; it
## replaced him.
##
## The old invariant this all replaced -- that an explicit activity beats a
## drifting stat -- is still asserted, on the same fixture, below.
func _test_poses_follow_activity_not_need():
	var failures: Array = []

	# An explicit activity still beats a drifting stat: a child put down to feed
	# is NOT laid out asleep because some other axis went low.
	var sleepy: Dictionary = _content()
	sleepy["energy"] = 5.0
	var feeding: Dictionary = Present.describe(sleepy, Present.ACTIVITY_FEEDING)
	if String(feeding["activity"]) != Present.ACTIVITY_FEEDING:
		failures.append("an explicit activity must win over the need; got '%s'"
				% String(feeding["activity"]))
	if String(feeding["pose"]) == Present.POSE_SLEEPING:
		failures.append("a sleepy child put down to FEED was laid out asleep; an explicit "
				+ "activity must win over a drifting stat")
	if String(feeding["pose"]) != Present.POSE_RIGGED:
		failures.append(("feeding selected the '%s' pose. Only `rigged` has a skeleton, and "
				+ "feeding is the one moment the whole mission is about -- cutting to a mesh "
				+ "that cannot move there is what made Bunny a statue.") % String(feeding["pose"]))

	# Bedtime lies him down ON THE RIG. This is the assertion that keeps a future
	# "the sleeping export looks nicer here" from silently swapping the character
	# for a different child again.
	if String(Present.describe(_content(), Present.ACTIVITY_BEDTIME)["pose"]) != Present.POSE_RIGGED:
		failures.append(("bedtime selected the '%s' pose. The rigged model has a `sleep` clip now, "
				+ "and the pose-locked exports are visibly a DIFFERENT baby -- cutting to one is "
				+ "not posing the child, it is replacing him.")
				% String(Present.describe(_content(), Present.ACTIVITY_BEDTIME)["pose"]))

	# ...and NO activity is allowed off the rigged model.
	for activity: String in Present.ACTIVITIES:
		var pose: String = Present.pose_for_activity(activity)
		if pose != Present.POSE_RIGGED:
			failures.append(("activity '%s' selects the '%s' pose. Every pose-locked export is a "
					+ "mesh with no skeleton and no clips, so choosing one here freezes the child "
					+ "for the whole activity -- and they are three separate generations, so it "
					+ "also changes which child it is.") % [activity, pose])

	# Dropping the bedtime exception is only honest while the rig can actually
	# lie down. Asserted here rather than only in `test_bunny_life.gd`, because
	# THIS is the file that stopped selecting the supine export.
	if not LifeClips.CLIP_NAMES.has(Life.LIFE_SLEEP):
		failures.append(("no '%s' clip is authored, but bedtime no longer leaves the rigged model. "
				+ "That combination is a child standing to attention at bedtime.") % Life.LIFE_SLEEP)
	if Life.clip_for(_content(), Present.ACTIVITY_BEDTIME, false, 0.0) != Life.LIFE_SLEEP:
		failures.append("bedtime plays '%s' rather than the sleep clip"
				% Life.clip_for(_content(), Present.ACTIVITY_BEDTIME, false, 0.0))

	# And every activity still resolves to a pose that exists.
	var known: Array = [Present.POSE_STANDING, Present.POSE_SITTING,
			Present.POSE_SLEEPING, Present.POSE_RIGGED]
	for activity: String in Present.ACTIVITIES:
		var pose: String = Present.pose_for_activity(activity)
		if not known.has(pose):
			failures.append("activity '%s' maps to unknown pose '%s'" % [activity, pose])
	return failures


func _test_every_need_has_an_answer_and_a_line():
	var failures: Array = []
	for state: String in Needs.PRIORITY:
		if Needs.answering_action(state).is_empty():
			failures.append(("need '%s' has no caregiver action that answers it. A need the "
					+ "player cannot act on is a dead end.") % state)
		var line: String = Needs.line_for(state)
		if line.strip_edges().is_empty():
			failures.append("need '%s' has nothing to say" % state)
		for banned: String in BANNED:
			if line.to_lower().contains(banned):
				failures.append("need '%s' says '%s' in \"%s\"; the child never accuses itself"
						% [state, banned, line])
	return failures


func _test_it_derives_from_child_stats():
	var failures: Array = []
	var state = StatsScript.new()
	if not state.has_method("describe"):
		failures.append("ChildStats cannot describe itself, so needs cannot derive from it")
		return failures
	var stats: Dictionary = state.call("describe")
	for key: String in ["hunger", "thirst", "happiness", "energy", "cleanliness", "freshness"]:
		if not stats.has(key):
			failures.append("ChildStats.describe() is missing '%s'" % key)
	# A fresh day starts with something to do, and the needs model must agree with
	# the stats rather than carry its own opinion of them.
	if not Needs.active_states(stats).has(Needs.HUNGRY):
		failures.append(("ChildStats starts at hunger %.0f, which is past the threshold, but the "
				+ "needs model does not report hungry -- the two have drifted apart.")
				% float(stats.get("hunger", 0.0)))
	return failures
