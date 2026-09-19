extends RefCounted

## Replaying one mission WITHOUT wiping a child's save.
##
## The QA ask is "let me test Mission 01 again in under three minutes", and the
## obvious implementation -- `reset_profile()` -- is the wrong one. A parent
## tapping a QA button must not be able to delete their child's stars, their
## finished chapters or their settings. So this is a SURGICAL edit rather than a
## reset, and its scope is asserted rather than described:
##
##   CLEARED   `levelCompleted[<levelId>]`   -- so the level is replayable
##             `starsByLevel[<levelId>]`     -- so the replay is rated honestly
##             `currentLevel`                -- repointed AT the level
##
##   UNTOUCHED every other level's completion and rating, `stars` (the running
##             total the child sees), `completedActivities`, `settings`,
##             `unlockedLevels`, `unlockedChapters`, `unlockedRooms`, and every
##             key this file has never heard of.
##
## Leaving `stars` alone is the load-bearing decision, and it is deliberate that
## it does NOT subtract the replayed level's stars. Taking a child's stars away
## because a grown-up pressed a test button is exactly the kind of punishment
## `CLAUDE.md`'s child-UX rules exist to prevent. The consequence -- that
## replaying and re-earning can inflate the running total -- is the right way
## round for a tool behind a parental gate.
##
## Unlocks are left alone too. Re-locking the levels that Mission 01 opened would
## strand a child mid-journey, and `LevelSystem.compute_unlocks()` derives the
## unlocked set from completion anyway, so nothing here can go stale.
##
## PURE. Takes a profile dictionary and returns a new one. No autoload, no file,
## no node -- which is what lets `test_mission_replay.gd` assert the blast radius
## key by key instead of trusting this comment.

## Keys this may write. Anything outside this list is copied through untouched,
## and the test asserts that.
const KEY_COMPLETED: String = "levelCompleted"
const KEY_STARS_BY_LEVEL: String = "starsByLevel"
const KEY_CURRENT_LEVEL: String = "currentLevel"

## Keys that must survive a replay byte for byte. Named so the test can check
## them one at a time and name the one that broke.
const PROTECTED_KEYS: Array[String] = [
	"stars",
	"completedActivities",
	"settings",
	"unlockedLevels",
	"unlockedChapters",
	"unlockedRooms",
	"profileVersion",
]


## The profile as it should be after arming a replay of `level_id`.
##
## Returns a NEW dictionary; the input is never mutated, so a caller that decides
## not to save still holds the original.
static func armed(profile: Variant, level_id: String) -> Dictionary:
	var source: Dictionary = profile if typeof(profile) == TYPE_DICTIONARY else {}
	var out: Dictionary = source.duplicate(true)
	if level_id.strip_edges().is_empty():
		return out

	# Read as `Variant` and THEN coerce. A statically typed `Dictionary` local
	# throws before the guard below can run when a corrupt profile has a string
	# where a map belongs -- which is exactly the input this guard exists for.
	var raw_completed: Variant = out.get(KEY_COMPLETED, {})
	var completed: Dictionary = raw_completed if typeof(raw_completed) == TYPE_DICTIONARY else {}
	completed.erase(level_id)
	out[KEY_COMPLETED] = completed

	var raw_stars: Variant = out.get(KEY_STARS_BY_LEVEL, {})
	var stars: Dictionary = raw_stars if typeof(raw_stars) == TYPE_DICTIONARY else {}
	stars.erase(level_id)
	out[KEY_STARS_BY_LEVEL] = stars

	# Point the resume pointer AT the level, so the director opens it next rather
	# than picking up wherever the child had got to.
	out[KEY_CURRENT_LEVEL] = level_id
	return out


## What `armed()` would change, as plain text for the QA panel's status line.
## Computed by comparing, so it cannot claim a change that did not happen.
static func describe(profile: Variant, level_id: String) -> String:
	var before: Dictionary = profile if typeof(profile) == TYPE_DICTIONARY else {}
	var after: Dictionary = armed(before, level_id)
	var was_done: bool = bool((before.get(KEY_COMPLETED, {}) as Dictionary).get(level_id, false))
	var had_stars: int = int((before.get(KEY_STARS_BY_LEVEL, {}) as Dictionary).get(level_id, 0))
	var kept: int = int(after.get("stars", 0))
	if not was_done and had_stars == 0:
		return "'%s' was not finished yet -- it is ready to play. %d stars kept." % [level_id, kept]
	return "'%s' cleared (was %d/3). %d stars kept, nothing else changed." % [level_id, had_stars, kept]
