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


func _test_poses_follow_activity_not_need():
	var failures: Array = []
	# Feeding seats the child, whatever the stats are doing.
	var sleepy: Dictionary = _content()
	sleepy["energy"] = 5.0
	var feeding: Dictionary = Present.describe(sleepy, Present.ACTIVITY_FEEDING)
	if String(feeding["pose"]) != Present.POSE_SITTING:
		failures.append(("an explicit feeding activity must seat the child even while another "
				+ "stat drifts; got pose '%s'") % String(feeding["pose"]))

	# Bedtime lies it down.
	if String(Present.describe(_content(), Present.ACTIVITY_BEDTIME)["pose"]) != Present.POSE_SLEEPING:
		failures.append("bedtime must use the sleeping pose")

	# And every activity resolves to exactly one known pose.
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
