extends RefCounted
## `LevelSystem` -- chapters, the Chapter 2 mapping, and unlock progression.
##
## The rule that matters most here: **progression gates on COMPLETION, never on
## a star count** -- and completion is a separate fact from the rating. A child
## who skipped every task still reaches the end, still unlocks the next level,
## and still honestly scores 0. `bathTime` carries the legacy `unlockAtStars:
## 10`, so "finish `milkTime` with ZERO stars and `bathTime` opens" is precisely
## the assertion that fails if anyone reinstates star gating for chapter levels.
##
## The seven pre-existing missions must also keep loading, keep validating and
## keep their old `unlockAtStars` semantics wherever something still uses them.

const LevelSystemScript := preload("res://scripts/progression/level_system.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const ContentValidatorScript := preload("res://scripts/content/content_validator.gd")
const StarRulesScript := preload("res://scripts/progression/star_rules.gd")

## The Chapter 2 mapping from `docs/PHASE1_CONTRACT.md`, frozen.
## [levelId, missionId, title, levelNumber]
const CHAPTER_2: Array = [
	["milkTime", "feedingTime", "Milk Time", 6],
	["bathTime", "bathTime", "Bath Time", 7],
	["bedtime", "bedtimeRoutine", "Bedtime", 8],
	["toysAndSmiles", "playTime", "Toys & Smiles", 9],
	["firstWords", "colorsAndShapes", "First Words", 10],
]

## The missions that shipped before the level layer. None may disappear.
const SHIPPED_MISSION_IDS: Array[String] = [
	"morningRoutine",
	"feedingTime",
	"playTime",
	"bathTime",
	"bedtimeRoutine",
	"colorsAndShapes",
	"sayItChallenge",
]

## Their `unlockAtStars` values, which the level layer must not have touched.
const LEGACY_UNLOCK_AT_STARS: Dictionary = {
	"morningRoutine": 0,
	"feedingTime": 0,
	"playTime": 4,
	"bathTime": 10,
	"bedtimeRoutine": 16,
	"colorsAndShapes": 24,
	"sayItChallenge": 32,
}


## Records what a SaveService would have been asked to do, without needing one.
class StubSaveService extends RefCounted:
	var stars_by_level: Dictionary = {}
	var level_completed: Dictionary = {}
	var set_calls: Array = []
	var completion_calls: Array = []
	var unlocked_levels: Array = []
	var unlocked_chapters: Array = []
	var current_level: String = ""

	func get_stars_by_level() -> Dictionary:
		return stars_by_level.duplicate(true)

	func get_level_completed() -> Dictionary:
		return level_completed.duplicate(true)

	func mark_level_completed(level_id: String) -> void:
		completion_calls.append(level_id)
		level_completed[level_id] = true

	func set_level_stars(level_id: String, stars: int) -> void:
		set_calls.append([level_id, stars])
		stars_by_level[level_id] = maxi(int(stars_by_level.get(level_id, 0)), stars)

	func unlock_level(level_id: String) -> void:
		unlocked_levels.append(level_id)

	func unlock_chapter(chapter_id: String) -> void:
		unlocked_chapters.append(chapter_id)

	func set_current_level(level_id: String) -> void:
		current_level = level_id


## A library that still speaks the pre-level-layer dialect.
class LegacyLibrary extends RefCounted:
	func get_missions() -> Array:
		return [{
			"missionId": "plainOldMission",
			"title": "Plain Old Mission",
			"unlockAtStars": 20,
			"taskIds": ["feedMilk", "findBowl"],
		}]

	func get_mission_tasks(_mission_id: String) -> Array:
		return [
			{"taskId": "feedMilk", "mode": "followInstruction"},
			{"taskId": "findBowl", "mode": "findIt"},
		]


var _library: RefCounted = null
var _system: RefCounted = null


func test_name() -> String:
	return "level_progression"


func run():
	var failures: Array = []

	_library = ContentLibraryScript.create()
	if _library == null:
		return ["could not load the content library"]
	_system = LevelSystemScript.create(_library)
	if _system == null:
		return ["could not build the level system"]

	failures.append_array(_test_existing_content_still_valid())
	failures.append_array(_test_chapter_2_mapping())
	failures.append_array(_test_chapter_2_star_rules())
	failures.append_array(_test_unlock_is_ordered())
	failures.append_array(_test_completion_is_separate_from_stars())
	failures.append_array(_test_completing_a_chapter_unlocks_the_next())
	failures.append_array(_test_speech_free_player_reaches_three_stars())
	failures.append_array(_test_replay_never_lowers())
	failures.append_array(_test_no_duplicate_awards())
	failures.append_array(_test_seeding())
	failures.append_array(_test_legacy_unlock_at_stars_still_works())
	failures.append_array(_test_degrades_without_a_save_service())

	return failures


# ---------------------------------------------------------------------------
# Nothing was broken on the way in
# ---------------------------------------------------------------------------

func _test_existing_content_still_valid():
	var failures: Array = []

	var problems: Array = ContentValidatorScript.validate_all(_library)
	for problem: Variant in problems:
		failures.append("content validation regressed: %s" % str(problem))

	for warning: Variant in _system.get_load_warnings():
		failures.append("level system warning: %s" % str(warning))

	var mission_ids: PackedStringArray = _library.get_mission_ids()
	# The invariant is "none of the shipped missions may DISAPPEAR", not "the
	# count is frozen". Chapter 3 legitimately adds missions; an equality check
	# here would make authoring new content fail a test about not losing old
	# content. Each shipped id is still checked individually in the loop below.
	if mission_ids.size() < SHIPPED_MISSION_IDS.size():
		failures.append(
			"expected at least %d missions, got %d -- a shipped mission was lost"
			% [SHIPPED_MISSION_IDS.size(), mission_ids.size()]
		)
	for mission_id: String in SHIPPED_MISSION_IDS:
		if not _library.has_mission(mission_id):
			failures.append("mission '%s' disappeared" % mission_id)
			continue
		var mission: Dictionary = _library.get_mission(mission_id)
		for key: String in ["missionId", "title", "thaiTitle", "category", "introPhrase", "outroPhrase", "unlockAtStars", "taskIds"]:
			if not mission.has(key):
				failures.append("mission '%s' lost pre-existing key '%s'" % [mission_id, key])
		var expected_threshold: int = int(LEGACY_UNLOCK_AT_STARS[mission_id])
		if int(mission.get("unlockAtStars", -1)) != expected_threshold:
			failures.append(
				"mission '%s' unlockAtStars changed from %d to %s -- the level layer must be additive"
				% [mission_id, expected_threshold, str(mission.get("unlockAtStars"))]
			)

	# The legacy star-threshold listing still behaves exactly as it did for the
	# missions that predate the level layer. Assert membership, not count: the
	# Chapter 3 missions are completion-gated, so they correctly carry
	# `unlockAtStars: 0` and now also appear in the 0-star listing. Counting
	# would turn "the legacy gate still works" into "no content may be added".
	var zero_star: Array = []
	for entry: Variant in _library.get_unlocked_missions(0):
		if typeof(entry) == TYPE_DICTIONARY:
			zero_star.append(String((entry as Dictionary).get("missionId", "")))
	for legacy_id: String in ["morningRoutine", "feedingTime"]:
		if not zero_star.has(legacy_id):
			failures.append(
				"get_unlocked_missions(0) no longer lists '%s'; the legacy star gate regressed"
				% legacy_id
			)
	if _library.get_unlocked_missions(32).size() < SHIPPED_MISSION_IDS.size():
		failures.append("get_unlocked_missions(32) should still list every shipped mission")

	return failures


# ---------------------------------------------------------------------------
# Chapter 2
# ---------------------------------------------------------------------------

func _test_chapter_2_mapping():
	var failures: Array = []

	var chain: PackedStringArray = _system.get_chapter_chain("ch2")
	if chain.size() != CHAPTER_2.size():
		failures.append("chapter 2 should chain %d levels, got %d" % [CHAPTER_2.size(), chain.size()])

	for i: int in range(CHAPTER_2.size()):
		var row: Array = CHAPTER_2[i]
		var level_id: String = String(row[0])

		if i < chain.size() and chain[i] != level_id:
			failures.append("chapter 2 position %d should be '%s', got '%s'" % [i, level_id, chain[i]])

		var level: RefCounted = _system.get_level(level_id)
		if level == null:
			failures.append("level '%s' does not exist" % level_id)
			continue

		if String(level.call("get_mission_id")) != String(row[1]):
			failures.append(
				"level '%s' should run mission '%s', got '%s'"
				% [level_id, String(row[1]), String(level.call("get_mission_id"))]
			)
		if String(level.call("get_title")) != String(row[2]):
			failures.append(
				"level '%s' should be titled '%s', got '%s'"
				% [level_id, String(row[2]), String(level.call("get_title"))]
			)
		if int(level.call("get_level_number")) != int(row[3]):
			failures.append("level '%s' should be level %d" % [level_id, int(row[3])])
		if String(level.call("get_chapter_id")) != "ch2":
			failures.append("level '%s' should belong to ch2" % level_id)
		if String(level.call("get_story_beat")).is_empty():
			failures.append("level '%s' has no storyBeat" % level_id)

		# Every level must resolve to real, existing, playable tasks.
		var task_ids: PackedStringArray = _system.get_level_task_ids(level_id)
		if task_ids.is_empty():
			failures.append("level '%s' resolves to no tasks" % level_id)
		for task_id: String in task_ids:
			if not _library.has_task(task_id):
				failures.append("level '%s' points at unknown task '%s'" % [level_id, task_id])

	# The two Chapter 3 missions stay loadable and are not in Chapter 2.
	for level_id: String in ["gettingDressed", "sayItChallenge"]:
		var level: RefCounted = _system.get_level(level_id)
		if level == null:
			failures.append("chapter 3 level '%s' must stay loadable" % level_id)
			continue
		if String(level.call("get_chapter_id")) != "ch3":
			failures.append("level '%s' should belong to ch3" % level_id)
		if chain.has(level_id):
			failures.append("level '%s' must not be part of the chapter 2 chain" % level_id)

	# `sayItChallenge` is a bonus level: unlocked with its chapter, never a gate.
	if _system.get_chapter_chain("ch3").has("sayItChallenge"):
		failures.append("'sayItChallenge' should be a chapter 3 BONUS level, not a chain gate")
	if not _system.get_levels_in_chapter("ch3").has("sayItChallenge"):
		failures.append("'sayItChallenge' should still be listed inside chapter 3")

	return failures


func _test_chapter_2_star_rules():
	var failures: Array = []

	for row: Array in CHAPTER_2:
		var level_id: String = String(row[0])
		var task_ids: PackedStringArray = _system.get_level_task_ids(level_id)
		var rules: Dictionary = _system.get_star_rules(level_id)

		for problem: Variant in StarRulesScript.validate(rules, task_ids, "level '%s' starRules" % level_id):
			failures.append(str(problem))

		if (rules.get("listeningTaskIds", []) as Array).is_empty():
			failures.append("level '%s' has no listening task, so star 2 would be free" % level_id)
		if (rules.get("optionalTaskIds", []) as Array).is_empty() \
				and (rules.get("optionalObjectiveIds", []) as Array).is_empty():
			failures.append("level '%s' has no optional challenge, so star 3 is unreachable" % level_id)

		# Star 1 must be reachable from the core tasks alone.
		var core_only: int = _system.rate_session(level_id, StarRulesScript.session(rules.get("coreTaskIds", [])))
		if core_only != 1:
			failures.append("level '%s': the core tasks alone should rate 1, got %d" % [level_id, core_only])

	return failures


# ---------------------------------------------------------------------------
# Unlocking
# ---------------------------------------------------------------------------

func _test_unlock_is_ordered():
	var failures: Array = []

	# A brand-new profile: chapter 2 and only its first level.
	var fresh: Dictionary = {}
	if _system.get_first_level_id() != "milkTime":
		failures.append("the journey should start at 'milkTime', got '%s'" % _system.get_first_level_id())
	if not _system.is_level_unlocked("milkTime", fresh):
		failures.append("the first level must always be unlocked")
	for level_id: String in ["bathTime", "bedtime", "toysAndSmiles", "firstWords"]:
		if _system.is_level_unlocked(level_id, fresh):
			failures.append("'%s' must be locked on a fresh profile" % level_id)
	if not _system.is_chapter_unlocked("ch2", fresh):
		failures.append("chapter 2 must be unlocked on a fresh profile")
	if _system.is_chapter_unlocked("ch3", fresh):
		failures.append("chapter 3 must be locked on a fresh profile")

	# THE rule: completion, not a star count. `bathTime` carries the legacy
	# `unlockAtStars: 10`, and finishing `milkTime` must open it.
	var finished: Dictionary = {"milkTime": true}
	if not _system.is_level_unlocked("bathTime", finished):
		failures.append(
			"finishing 'milkTime' must unlock 'bathTime' -- progression gates on "
			+ "completion, never on a star count"
		)
	if _system.is_level_unlocked("bedtime", finished):
		failures.append("'bedtime' must stay locked until 'bathTime' is completed")

	# Not finishing is not completion.
	if _system.is_level_unlocked("bathTime", {"milkTime": false}):
		failures.append("an unfinished 'milkTime' must not unlock 'bathTime'")
	if _system.is_level_unlocked("bathTime", {}):
		failures.append("an empty completion map must not unlock the second level")

	# A v2-era star map is still read correctly, so a profile that somehow
	# arrives un-migrated never locks a child out of progress they already have.
	if not _system.is_level_unlocked("bathTime", {"milkTime": 1}):
		failures.append("a legacy star map (milkTime: 1) should still read as completion")

	# Out-of-order progress cannot leapfrog the chain.
	if _system.is_level_unlocked("firstWords", {"toysAndSmiles": true}):
		failures.append("finishing a later level must not unlock the level after it")

	# Walking the chapter one level at a time opens exactly one more each time.
	var progress: Dictionary = {}
	for i: int in range(CHAPTER_2.size()):
		var level_id: String = String(CHAPTER_2[i][0])
		if not _system.is_level_unlocked(level_id, progress):
			failures.append("'%s' should be unlocked by the time it is reached" % level_id)
		progress[level_id] = true
		if i + 1 < CHAPTER_2.size():
			var next_id: String = String(CHAPTER_2[i + 1][0])
			if _system.get_next_level_id(level_id) != next_id:
				failures.append(
					"after '%s' the next level should be '%s', got '%s'"
					% [level_id, next_id, _system.get_next_level_id(level_id)]
				)
			if not _system.is_level_unlocked(next_id, progress):
				failures.append("completing '%s' should unlock '%s'" % [level_id, next_id])

	return failures


# ---------------------------------------------------------------------------
# Completion vs stars: the skip-everything playthrough
# ---------------------------------------------------------------------------

## A child who used the Next button on every single task reached the end of the
## level. That must:
##   - complete the level and unlock the next one (the escape hatch is never a
##     trap), and
##   - score 0, not 1 (a skipped objective is not an achievement).
func _test_completion_is_separate_from_stars():
	var failures: Array = []

	var skipped_everything: Dictionary = _system.resolve_completion("milkTime", 0, {}, {})

	if int(skipped_everything.get("stars", -1)) != 0:
		failures.append(
			"a level finished by skipping every task must rate 0, got %s -- skipped tasks are not achievements"
			% str(skipped_everything.get("stars"))
		)
	if not bool(skipped_everything.get("completed", false)):
		failures.append("reaching the end of a level must complete it even with 0 stars")
	if not bool((skipped_everything["levelCompleted"] as Dictionary).get("milkTime", false)):
		failures.append("the returned completion map must record the level")
	if not (skipped_everything["newlyUnlockedLevels"] as PackedStringArray).has("bathTime"):
		failures.append(
			"a 0-star completion must still unlock the next level -- the skip button is the "
			+ "room's no-dead-end escape hatch and must never become a lock"
		)
	if bool(skipped_everything.get("bonusSticker", true)):
		failures.append("a 0-star completion must not hand out the 3-star bonus sticker")

	# A whole chapter can be completed at 0 stars, and it opens the next one.
	var zero_star_run: Dictionary = {}
	var no_stars: Dictionary = {}
	for row: Array in CHAPTER_2:
		zero_star_run[String(row[0])] = true
		no_stars[String(row[0])] = 0
	if not _system.is_chapter_complete("ch2", zero_star_run):
		failures.append("a chapter finished with 0 stars everywhere must still count as complete")
	if not _system.is_chapter_unlocked("ch3", zero_star_run):
		failures.append("a child may unlock the next chapter with 0 stars")
	if _system.is_level_unlocked("bathTime", no_stars):
		failures.append(
			"the star map must NOT be mistaken for a completion map: 0 stars is not completion"
		)

	# Persistence: completion is written, a 0 rating writes no star.
	var save: StubSaveService = StubSaveService.new()
	var system: RefCounted = LevelSystemScript.create(_library)
	system.set_save_service(save)

	system.apply_completion("milkTime", 0)
	if save.completion_calls != ["milkTime"]:
		failures.append("apply_completion must mark the level completed, got %s" % str(save.completion_calls))
	if int(save.stars_by_level.get("milkTime", 0)) != 0:
		failures.append("a 0-star run must not be stored as a star, got %s" % str(save.stars_by_level))
	if not save.unlocked_levels.has("bathTime"):
		failures.append("a 0-star completion must persist the next level's unlock, got %s" % str(save.unlocked_levels))

	# Replaying it properly later raises the rating without re-issuing anything.
	system.apply_completion("milkTime", 2)
	if int(save.stars_by_level.get("milkTime", 0)) != 2:
		failures.append("a later, better run must raise the rating to 2, got %s" % str(save.stars_by_level))
	if save.completion_calls.size() != 2:
		failures.append("apply_completion should mark completion every time; SaveService de-duplicates")
	if save.unlocked_levels.count("bathTime") != 1:
		failures.append("a replay must not re-issue an unlock, got %s" % str(save.unlocked_levels))

	return failures


func _test_completing_a_chapter_unlocks_the_next():
	var failures: Array = []

	var almost: Dictionary = {}
	for i: int in range(CHAPTER_2.size() - 1):
		almost[String(CHAPTER_2[i][0])] = true
	if _system.is_chapter_complete("ch2", almost):
		failures.append("chapter 2 must not be complete with a level outstanding")
	if _system.is_chapter_unlocked("ch3", almost):
		failures.append("chapter 3 must stay locked while chapter 2 is unfinished")
	if _system.is_level_unlocked("gettingDressed", almost):
		failures.append("a chapter 3 level must stay locked while chapter 2 is unfinished")

	var done: Dictionary = almost.duplicate()
	done[String(CHAPTER_2[CHAPTER_2.size() - 1][0])] = true
	if not _system.is_chapter_complete("ch2", done):
		failures.append("finishing every level must complete chapter 2")
	if not _system.is_chapter_unlocked("ch3", done):
		failures.append("completing chapter 2 must unlock chapter 3")
	# `goodMorning` is L11, the first level of chapter 3. `gettingDressed` was the
	# first only while chapter 3 held a single promoted level.
	if not _system.is_level_unlocked("goodMorning", done):
		failures.append("completing chapter 2 must unlock the first chapter 3 level")
	if not _system.is_level_unlocked("sayItChallenge", done):
		failures.append("a bonus level must unlock with its chapter")
	if _system.get_next_level_id("firstWords") != "goodMorning":
		failures.append(
			"the level after the last of chapter 2 should be the first of chapter 3, got '%s'"
			% _system.get_next_level_id("firstWords")
		)

	var newly: PackedStringArray = _system.newly_unlocked_chapters(almost, done)
	if not newly.has("ch3"):
		failures.append("finishing chapter 2 should report ch3 as newly unlocked")

	return failures


# ---------------------------------------------------------------------------
# Speech is never required -- at the level level, not just in StarRules
# ---------------------------------------------------------------------------

## A child whose device has no working recognition completes every task by
## touch. That must still reach 3/3 on every Chapter 2 level, and must still
## carry them through the whole chapter.
func _test_speech_free_player_reaches_three_stars():
	var failures: Array = []

	var progress: Dictionary = {}
	for row: Array in CHAPTER_2:
		var level_id: String = String(row[0])
		var touch_only: Array = []
		for task_id: String in _system.get_level_task_ids(level_id):
			touch_only.append(task_id)

		var rating: int = _system.rate_session(level_id, {
			"completedTaskIds": touch_only,
			"speechAvailable": false,
			"speechEnabled": false,
			"transcripts": [],
		})
		if rating != 3:
			var detail: Dictionary = _system.describe_session(level_id, StarRulesScript.session(touch_only))
			failures.append(
				("level '%s': a player with speech unavailable must still reach 3/3 by touch; "
				+ "got %d (%s)") % [level_id, rating, str(detail)]
			)
		progress[level_id] = rating

	if not _system.is_chapter_complete("ch2", progress):
		failures.append("a touch-only player must be able to complete chapter 2")
	if not _system.is_chapter_unlocked("ch3", progress):
		failures.append("a touch-only player must be able to unlock chapter 3")

	return failures


# ---------------------------------------------------------------------------
# Replay safety
# ---------------------------------------------------------------------------

func _test_replay_never_lowers():
	var failures: Array = []

	var progress: Dictionary = {"milkTime": 3}
	var outcome: Dictionary = _system.resolve_completion("milkTime", 1, progress)

	if int(outcome.get("stars", 0)) != 3:
		failures.append("replaying worse must not lower a 3-star rating, got %s" % str(outcome.get("stars")))
	if bool(outcome.get("improved", true)):
		failures.append("a worse replay must not be reported as an improvement")
	if int((outcome["starsByLevel"] as Dictionary).get("milkTime", 0)) != 3:
		failures.append("the returned starsByLevel must keep the best-ever rating")
	if int(progress.get("milkTime", 0)) != 3:
		failures.append("resolve_completion must not mutate the map it was given")

	var better: Dictionary = _system.resolve_completion("milkTime", 3, {"milkTime": 1})
	if int(better.get("stars", 0)) != 3 or not bool(better.get("improved", false)):
		failures.append("a better replay must raise the rating and report the improvement")
	if not bool(better.get("bonusSticker", false)):
		failures.append("reaching 3/3 must flag the bonus sticker")

	var passing: Dictionary = _system.resolve_completion("milkTime", 2, {})
	if bool(passing.get("bonusSticker", true)):
		failures.append("2/3 passes but must not flag the bonus sticker")
	if not (passing["newlyUnlockedLevels"] as PackedStringArray).has("bathTime"):
		failures.append("a 2/3 pass must still unlock the next level")

	var negative: Dictionary = _system.resolve_completion("milkTime", -4, {"milkTime": 2})
	if int(negative.get("stars", 0)) != 2:
		failures.append("a negative award must never subtract from a stored rating")

	return failures


func _test_no_duplicate_awards():
	var failures: Array = []

	var save: StubSaveService = StubSaveService.new()
	var system: RefCounted = LevelSystemScript.create(_library)
	system.set_save_service(save)

	var first: Dictionary = system.apply_completion("milkTime", 3)
	if int(first.get("stars", 0)) != 3:
		failures.append("the first completion should store 3 stars")
	if not (first["newlyUnlockedLevels"] as PackedStringArray).has("bathTime"):
		failures.append("the first completion should unlock 'bathTime'")

	var unlocks_after_first: int = save.unlocked_levels.size()
	var second: Dictionary = system.apply_completion("milkTime", 3)

	if save.set_calls.size() != 1:
		failures.append(
			"set_level_stars should have been called once, not %d times -- a repeat "
			% save.set_calls.size() + "of the same result must not be re-awarded"
		)
	if save.unlocked_levels.size() != unlocks_after_first:
		failures.append("replaying a finished level must not re-issue unlocks")
	if bool(second.get("improved", true)):
		failures.append("an identical replay must not report an improvement")
	if int(second.get("stars", 0)) != 3:
		failures.append("an identical replay must keep the rating at 3")

	# A worse replay must not write at all.
	system.apply_completion("milkTime", 1)
	if save.set_calls.size() != 1:
		failures.append("a worse replay must not write a lower rating")
	if int(save.stars_by_level.get("milkTime", 0)) != 3:
		failures.append("the stored rating must stay at 3 after a worse replay")

	# The next level is suggested exactly once, when it first opens.
	if save.current_level != "bathTime":
		failures.append("completing 'milkTime' should point the player at 'bathTime'")

	return failures


# ---------------------------------------------------------------------------
# Migration support
# ---------------------------------------------------------------------------

func _test_seeding():
	var failures: Array = []

	# Every task of `milkTime` completed in a v1 profile -> exactly 1 star.
	var completed: Array = []
	for task_id: String in _system.get_level_task_ids("milkTime"):
		completed.append(task_id)

	var seeded: Dictionary = _system.seed_stars_from_completed_activities(completed)
	if int(seeded.get("milkTime", 0)) != 1:
		failures.append("a fully-completed level should seed exactly 1 star, got %s" % str(seeded.get("milkTime")))
	for level_id: Variant in seeded.keys():
		if int(seeded[level_id]) != 1:
			failures.append("seeding must never grant more than 1 star ('%s')" % str(level_id))

	# One task short: no star at all.
	var partial: Array = completed.duplicate()
	partial.pop_back()
	if _system.seed_stars_from_completed_activities(partial).has("milkTime"):
		failures.append("a partially-completed level must not be seeded")

	# The seeded star is enough to unlock the next level, so a returning player
	# is never sent backwards.
	if not _system.is_level_unlocked("bathTime", seeded):
		failures.append("a seeded star must unlock the following level")

	# Junk in, empty out.
	for junk: Variant in [null, 42, "activities"]:
		if not _system.seed_stars_from_completed_activities(junk).is_empty():
			failures.append("seeding from %s should yield nothing" % str(junk))

	return failures


# ---------------------------------------------------------------------------
# The old gate still works where it is still used
# ---------------------------------------------------------------------------

func _test_legacy_unlock_at_stars_still_works():
	var failures: Array = []

	var legacy_system: RefCounted = LevelSystemScript.create(LegacyLibrary.new())
	if legacy_system == null:
		return ["could not build a level system over a legacy library"]

	# An untagged mission keeps the task-star threshold it always had.
	if legacy_system.is_mission_available("plainOldMission", 19, {}):
		failures.append("an untagged mission must still respect unlockAtStars (19 < 20)")
	if not legacy_system.is_mission_available("plainOldMission", 20, {}):
		failures.append("an untagged mission must unlock at its unlockAtStars threshold")

	# ...and a promoted level ignores it in favour of completion gating.
	if _system.is_mission_available("bathTime", 0, {}):
		failures.append("a chapter level must not be available before the level before it")
	if not _system.is_mission_available("bathTime", 0, {"milkTime": 1}):
		failures.append("a chapter level must open on completion even with 0 task stars")

	# An untagged mission is still rateable rather than being skipped entirely.
	var rating: int = legacy_system.rate_session(
		"plainOldMission", StarRulesScript.session(["feedMilk", "findBowl"])
	)
	if rating != 2:
		failures.append("an untagged mission should still rate through derived rules, got %d" % rating)

	return failures


func _test_degrades_without_a_save_service():
	var failures: Array = []

	var system: RefCounted = LevelSystemScript.create(_library)
	# No SaveService injected and none in the tree: must compute, not crash.
	if not system.load_stars_by_level().is_empty():
		failures.append("without a SaveService the stored ratings should read as empty")

	var outcome: Dictionary = system.apply_completion("milkTime", 2)
	if int(outcome.get("stars", 0)) != 2:
		failures.append("apply_completion must still return a result without a SaveService")
	if not (outcome["newlyUnlockedLevels"] as PackedStringArray).has("bathTime"):
		failures.append("unlock computation must not depend on a SaveService")

	# A SaveService that implements none of the new API must also be survivable.
	system.set_save_service(RefCounted.new())
	var partial: Dictionary = system.apply_completion("milkTime", 3)
	if int(partial.get("stars", 0)) != 3:
		failures.append("a SaveService missing the level API must not break the level system")

	return failures
