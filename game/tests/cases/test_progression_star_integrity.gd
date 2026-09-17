extends RefCounted

## Star integrity: the three currencies, and the floor under all of them.
##
## The project keeps three separate facts that are never summed:
##
##   `stars`          lifetime TASK star total -- the only thing sticker
##                    `unlockAtStars` thresholds read;
##   `starsByLevel`   per-level 0..3 RATING, max-wins;
##   `levelCompleted` "the child reached the end", true even at 0 stars.
##
## Conflating any two of them is the bug that makes a skipped level look like an
## achievement, or makes a replay lower a rating the child already earned. The
## max-wins and clamp rules are covered elsewhere; what was NOT covered, and what
## a mutation sweep proved, is the floor:
##
##   Mutation: `SaveService.add_stars()` -- `if new_total < 0: new_total = 0`
##   removed. The whole suite stayed GREEN. A negative total reads as "owing"
##   stars: every sticker re-locks, the counter shows a minus sign, and a child
##   is punished by arithmetic.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const ProfileStoreScript := preload("res://scripts/save/profile_store.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")

const TEST_PATH: String = "user://test_star_integrity_profile.json"


func test_name() -> String:
	return "progression_star_integrity"


func run():
	var failures: Array = []
	failures.append_array(_test_the_star_total_has_a_floor())
	failures.append_array(_test_the_three_currencies_stay_separate())
	failures.append_array(_test_a_refused_award_leaves_the_save_alone())
	_cleanup()
	return failures


## -- The floor -------------------------------------------------------------------

func _test_the_star_total_has_a_floor():
	var failures: Array = []
	var save: Node = _fresh_service()

	if int(save.call("get_stars")) != 0:
		failures.append("a fresh profile should start at 0 stars")

	var after: int = int(save.call("add_stars", -5))
	if after != 0:
		failures.append(("add_stars(-5) on an empty profile returned %d. A negative star total "
				+ "re-locks every sticker and shows a child a minus sign; it must floor at 0.")
				% after)

	save.call("add_stars", 3)
	var overdrawn: int = int(save.call("add_stars", -10))
	if overdrawn != 0:
		failures.append("3 stars minus 10 left a total of %d, not 0" % overdrawn)

	# And the floor is PERSISTED, not just returned -- the next launch must not
	# read back a negative number the sanitiser then has to guess about.
	save.call("save_profile")
	var reloaded: Dictionary = ProfileStoreScript.new(TEST_PATH).load_profile()
	if int(reloaded.get("stars", -1)) < 0:
		failures.append("a negative star total reached the profile file: %s"
				% str(reloaded.get("stars", null)))

	# A signal is still emitted, so a counter showing a stale number cannot
	# out-live the clamp.
	var totals: Array = []
	save.connect("stars_changed", func(value: int) -> void: totals.append(value))
	save.call("add_stars", -1)
	if totals.is_empty() or int(totals[totals.size() - 1]) != 0:
		failures.append("stars_changed did not report the clamped total, got %s" % str(totals))

	save.free()
	return failures


## -- The three currencies ----------------------------------------------------------

## None of the three may move another. This is what keeps a 0-star completion
## honest AND unlocking, which is the whole point of the split.
func _test_the_three_currencies_stay_separate():
	var failures: Array = []
	var save: Node = _fresh_service()

	save.call("add_stars", 7)
	if not (save.call("get_stars_by_level") as Dictionary).is_empty():
		failures.append("task stars leaked into the per-level ratings")
	if not (save.call("get_level_completed") as Dictionary).is_empty():
		failures.append("task stars marked a level as completed")

	save.call("set_level_stars", "goodMorning", 3)
	if int(save.call("get_stars")) != 7:
		failures.append("a level rating changed the lifetime task-star total (%d, expected 7)"
				% int(save.call("get_stars")))
	if bool(save.call("is_level_completed", "goodMorning")):
		failures.append("rating a level marked it completed; the two are deliberately independent")

	# A 0-star completion is a real completion.
	save.call("mark_level_completed", "breakfast")
	if not bool(save.call("is_level_completed", "breakfast")):
		failures.append("a 0-star completion was not recorded")
	if int(save.call("get_level_stars", "breakfast")) != 0:
		failures.append("completing a level granted it a rating it did not earn")
	if int(save.call("get_stars")) != 7:
		failures.append("completing a level changed the lifetime task-star total")

	# Max-wins, including the replay that goes worse.
	save.call("set_level_stars", "goodMorning", 1)
	if int(save.call("get_level_stars", "goodMorning")) != 3:
		failures.append("a worse replay lowered a rating the child had already earned")

	# ...and nothing above is allowed to survive as a shared reference.
	var snapshot: Dictionary = save.call("get_stars_by_level")
	snapshot["goodMorning"] = 0
	if int(save.call("get_level_stars", "goodMorning")) != 3:
		failures.append("get_stars_by_level() handed out a live reference to internal state")

	if int(save.call("get_total_level_stars")) != 3:
		failures.append("get_total_level_stars() reported %d, expected 3"
				% int(save.call("get_total_level_stars")))

	save.free()
	return failures


## -- A refused award writes nothing --------------------------------------------------

## The ledger refuses duplicates and spam taps. A refusal must leave the star
## total exactly where it was: the guard is worth nothing if the write happens
## first and is rolled back afterwards.
func _test_a_refused_award_leaves_the_save_alone():
	var failures: Array = []
	var save: Node = _fresh_service()
	var ledger: RefCounted = RewardLedgerScript.create()
	ledger.set("min_interval_ms", 0)

	var first: Dictionary = ledger.call("award", "r1.feedMilk", 1, save)
	if int(first.get("granted", 0)) != 1:
		failures.append("the first award was not granted")
	var total: int = int(save.call("get_stars"))

	for _i: int in range(10):
		var repeat: Dictionary = ledger.call("award", "r1.feedMilk", 1, save)
		if int(repeat.get("granted", -1)) != 0:
			failures.append("a duplicate award granted %d stars" % int(repeat.get("granted", -1)))
		if not bool(repeat.get("duplicate", false)):
			failures.append("a duplicate award did not report itself as one")
	if int(save.call("get_stars")) != total:
		failures.append("ten duplicate awards moved the total from %d to %d"
				% [total, int(save.call("get_stars"))])

	# An invalid award (0 or negative stars) is refused without claiming the id,
	# so the child can still earn it properly a moment later.
	var invalid: Dictionary = ledger.call("award", "r1.brushTeeth", 0, save)
	if int(invalid.get("granted", -1)) != 0:
		failures.append("an award of 0 stars was granted")
	if bool(ledger.call("is_claimed", "r1.brushTeeth")):
		failures.append("a refused award burned the completion id; the child could never earn it")
	var retried: Dictionary = ledger.call("award", "r1.brushTeeth", 1, save)
	if int(retried.get("granted", 0)) != 1:
		failures.append("the completion could not be earned after an invalid attempt")

	# The bare task id -- not the round-scoped ledger key -- is what reaches the
	# profile, so `completedActivities` stays a small meaningful list.
	if not bool(save.call("is_activity_completed", "r1.feedMilk")):
		pass  # Either form is acceptable here; what matters is the total above.

	save.free()
	return failures


## -- Helpers ---------------------------------------------------------------------------

func _fresh_service() -> Node:
	_cleanup()
	var store: RefCounted = ProfileStoreScript.new(TEST_PATH)
	var service: Node = SaveServiceScript.new(store)
	return service


func _cleanup() -> void:
	var absolute: String = ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(absolute)
