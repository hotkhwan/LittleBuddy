extends RefCounted

## Tests for the save migrations (v1 -> v3 and v2 -> v3) and the schema
## additions they introduce: currentChapter/currentLevel, starsByLevel,
## levelCompleted, and the unlockedChapters/unlockedLevels/unlockedRooms
## unlock sets.
##
## Two cruxes under test throughout:
##   1. "stars" (lifetime task total, feeds sticker thresholds) and
##      "starsByLevel" (per-level 0..3 rating) are different currencies and must
##      never be summed or otherwise contaminate one another.
##   2. "levelCompleted" (did the child reach the end?) and "starsByLevel" (how
##      well did it go?) are different facts. Unlocking reads the first; the
##      second stays honest and may be 0 for a completed level.
##
## Uses a temp user:// path (never the real profile.json) and the REAL
## committed device fixture (`device_profile_v1.json`: v1, 64 stars, 33
## completed activities, 11 unlocked stickers), not only synthetic data.
## Does not depend on autoloads -- `--script` does not load them.

const SaveServiceScript := preload("res://scripts/save/save_service.gd")

const DEVICE_FIXTURE_PATH := "res://tests/fixtures/device_profile_v1.json"
const REAL_MISSIONS_PATH := "res://content/missions/missions.json"
const REAL_CHAPTERS_PATH := "res://content/chapters/chapters.json"
const MISSIONS_FIXTURE_PATH := "res://tests/fixtures/missions_fixture_ch2.json"
const NONEXISTENT_MISSIONS_PATH := "res://tests/fixtures/does_not_exist_missions.json"
const NONEXISTENT_CHAPTERS_PATH := "res://tests/fixtures/does_not_exist_chapters.json"

const DEVICE_STARS := 64
const DEVICE_COMPLETED_COUNT := 33
const DEVICE_STICKER_COUNT := 11


func test_name() -> String:
	return "save_migration"


func run():
	var failures: Array = []
	var test_path := "user://test_migration_%d.json" % randi()

	_cleanup(test_path)
	failures.append_array(_test_real_device_profile_preserves_v1_fields(test_path))

	_cleanup(test_path)
	failures.append_array(_test_real_device_profile_seeds_starsByLevel(test_path))

	_cleanup(test_path)
	failures.append_array(_test_seeding_never_inflates_task_stars(test_path))

	_cleanup(test_path)
	failures.append_array(_test_real_content_seeds_starsByLevel_via_default_paths(test_path))

	_cleanup(test_path)
	failures.append_array(_test_missing_level_definitions_skips_seeding_safely(test_path))

	_cleanup(test_path)
	failures.append_array(_test_chapter2_and_first_level_always_unlocked(test_path))

	_cleanup(test_path)
	failures.append_array(_test_starsByLevel_persists_across_reload(test_path))

	_cleanup(test_path)
	failures.append_array(_test_set_level_stars_is_max_wins(test_path))

	_cleanup(test_path)
	failures.append_array(_test_stars_and_level_stars_do_not_contaminate(test_path))

	_cleanup(test_path)
	failures.append_array(_test_unknown_future_version_does_not_crash(test_path))

	_cleanup(test_path)
	failures.append_array(_test_v2_to_v3_marks_rated_levels_completed(test_path))

	_cleanup(test_path)
	failures.append_array(_test_v3_profile_round_trips_unchanged(test_path))

	_cleanup(test_path)
	failures.append_array(_test_migration_is_idempotent(test_path))

	_cleanup(test_path)
	failures.append_array(_test_v1_migration_is_idempotent(test_path))

	_cleanup(test_path)
	failures.append_array(_test_level_completed_api(test_path))

	_cleanup(test_path)
	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var tmp_path := path + ".tmp"
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)


## Copies the committed real-device fixture into a scratch user:// path so
## ProfileStore (which writes via a temp-file+rename, only possible on
## user://) can load AND round-trip it like it would the real save file.
func _install_device_fixture(path: String) -> void:
	var src := FileAccess.open(DEVICE_FIXTURE_PATH, FileAccess.READ)
	var text := src.get_as_text()
	src.close()
	var dst := FileAccess.open(path, FileAccess.WRITE)
	dst.store_string(text)
	dst.close()


## The injectable-path seam: a store reading a committed FIXTURE mission/chapter
## pair instead of the shipped content, so these assertions stay stable if the
## real chapter chain is re-authored later.
func _store_with_ch2_fixture(path: String) -> ProfileStore:
	return ProfileStore.new(path, MISSIONS_FIXTURE_PATH, REAL_CHAPTERS_PATH)


## No path arguments at all: exactly what the game constructs at runtime.
## taskIds/chapterId/levelId are authored directly onto missions.json (see
## LevelDefinition.is_authored_level()), and the chapter order lives in
## chapters.json. Seeding must work off those two files and nothing else --
## there is no levels.json and there never was.
func _store_with_real_content_defaults(path: String) -> ProfileStore:
	return ProfileStore.new(path)


## Neither missions.json nor chapters.json can be read. This is the fully-absent
## case the contract requires migration to survive: seeding is skipped, nothing
## crashes, nothing is lost.
func _store_with_no_level_data_at_all(path: String) -> ProfileStore:
	return ProfileStore.new(path, NONEXISTENT_MISSIONS_PATH, NONEXISTENT_CHAPTERS_PATH)


# ---------------------------------------------------------------------------
# Real device profile: v1 fields carry over untouched
# ---------------------------------------------------------------------------

func _test_real_device_profile_preserves_v1_fields(path: String) -> Array:
	var failures: Array = []
	_install_device_fixture(path)

	var store := _store_with_ch2_fixture(path)
	var migrated := store.load_profile()

	if migrated.get("profileVersion") != 3:
		failures.append("device profile: expected profileVersion 3 after migration, got %s"
				% str(migrated.get("profileVersion")))
	if int(migrated.get("stars", -1)) != DEVICE_STARS:
		failures.append("device profile: expected stars preserved as %d, got %s"
				% [DEVICE_STARS, str(migrated.get("stars"))])

	var completed: Array = migrated.get("completedActivities", [])
	if completed.size() != DEVICE_COMPLETED_COUNT:
		failures.append("device profile: expected %d completedActivities preserved, got %d"
				% [DEVICE_COMPLETED_COUNT, completed.size()])
	if not completed.has("feedMilk") or not completed.has("bedtimeBlanket"):
		failures.append("device profile: completedActivities lost specific entries after migration")

	var settings: Dictionary = migrated.get("settings", {})
	if settings.get("soundEnabled") != true:
		failures.append("device profile: settings.soundEnabled not preserved")
	if settings.get("ttsSpeed") != "normal":
		failures.append("device profile: settings.ttsSpeed not preserved")
	if settings.get("speechLocale") != "en-US":
		failures.append("device profile: settings.speechLocale not preserved")
	if settings.get("thaiHints") != true:
		failures.append("device profile: settings.thaiHints not preserved")

	var stickers: Array = settings.get("unlockedStickers", [])
	if stickers.size() != DEVICE_STICKER_COUNT:
		failures.append("device profile: expected %d unlockedStickers preserved, got %d"
				% [DEVICE_STICKER_COUNT, stickers.size()])
	if not stickers.has("milkSticker") or not stickers.has("toothbrushSticker"):
		failures.append("device profile: unlockedStickers lost specific entries after migration")

	return failures


# ---------------------------------------------------------------------------
# Real device profile: starsByLevel seeding, using the Chapter 2 mapping
# table from docs/PHASE1_CONTRACT.md against the real, already-shipped
# missions.json.
# ---------------------------------------------------------------------------

func _test_real_device_profile_seeds_starsByLevel(path: String) -> Array:
	var failures: Array = []
	_install_device_fixture(path)

	var store := _store_with_ch2_fixture(path)
	var migrated := store.load_profile()

	var stars_by_level: Dictionary = migrated.get("starsByLevel", {})

	# bedtimeRoutine and colorsAndShapes are fully represented in the fixture's
	# completedActivities -> their levels earn the seeded core-completion star.
	if int(stars_by_level.get("bedtime", -1)) != 1:
		failures.append("device profile: expected level 'bedtime' seeded to 1 star, got %s"
				% str(stars_by_level.get("bedtime")))
	if int(stars_by_level.get("firstWords", -1)) != 1:
		failures.append("device profile: expected level 'firstWords' seeded to 1 star, got %s"
				% str(stars_by_level.get("firstWords")))

	# feedingTime is missing 'feedBanana' and bathTime is missing 'findTowel'
	# in the fixture -> under-crediting is safe, so those levels must NOT be
	# seeded a star just because most of their tasks are done.
	if stars_by_level.has("bathTime"):
		failures.append("device profile: level 'bathTime' was seeded a star despite an incomplete task set (over-crediting)")
	if int(stars_by_level.get("milkTime", 0)) != 0:
		failures.append("device profile: level 'milkTime' (feedingTime, incomplete) must not be seeded a star, got %s"
				% str(stars_by_level.get("milkTime")))

	# playTime has only 2 of 7 tasks done.
	if stars_by_level.has("toysAndSmiles"):
		failures.append("device profile: level 'toysAndSmiles' was seeded a star despite a mostly-incomplete task set")

	var unlocked_levels: Array = migrated.get("unlockedLevels", [])
	if not unlocked_levels.has("bedtime") or not unlocked_levels.has("firstWords"):
		failures.append("device profile: completed levels were not marked unlocked, got %s" % str(unlocked_levels))

	var unlocked_chapters: Array = migrated.get("unlockedChapters", [])
	if not unlocked_chapters.has("ch2"):
		failures.append("device profile: expected chapter 'ch2' unlocked, got %s" % str(unlocked_chapters))

	# v1 -> v3: exactly the levels that earned the seeded star are marked
	# completed. Never fewer (that would send this child backwards) and never
	# more (that would credit a level they never finished).
	var completed_levels: Dictionary = migrated.get("levelCompleted", {})
	for level_id: String in ["bedtime", "firstWords"]:
		if not bool(completed_levels.get(level_id, false)):
			failures.append("device profile: level '%s' was seeded a star but not marked completed, got %s"
					% [level_id, str(completed_levels)])
	for level_id: String in ["milkTime", "bathTime", "toysAndSmiles"]:
		if completed_levels.has(level_id):
			failures.append("device profile: incomplete level '%s' was marked completed, got %s"
					% [level_id, str(completed_levels)])
	if completed_levels.keys().size() != stars_by_level.keys().size():
		failures.append("device profile: levelCompleted and the seeded starsByLevel disagree: %s vs %s"
				% [str(completed_levels), str(stars_by_level)])

	return failures


func _test_seeding_never_inflates_task_stars(path: String) -> Array:
	var failures: Array = []
	_install_device_fixture(path)

	var store := _store_with_ch2_fixture(path)
	var migrated := store.load_profile()

	# Two levels are seeded a star each by the assertions above; "stars" (the
	# lifetime task total) must remain exactly what it was in the v1 file --
	# never summed with starsByLevel.
	if int(migrated.get("stars", -1)) != DEVICE_STARS:
		failures.append("device profile: 'stars' changed to %s after level seeding, expected untouched %d"
				% [str(migrated.get("stars")), DEVICE_STARS])

	var total_level_stars := 0
	var stars_by_level: Dictionary = migrated.get("starsByLevel", {})
	for level_id in stars_by_level.keys():
		total_level_stars += int(stars_by_level[level_id])
		# Seeding may never grant more than the single core-completion star: we
		# cannot know retroactively whether the listening or optional star was
		# earned, and over-crediting is not recoverable.
		if int(stars_by_level[level_id]) > 1:
			failures.append("device profile: level '%s' was seeded %s stars; seeding must never exceed 1"
					% [str(level_id), str(stars_by_level[level_id])])
	if total_level_stars == 0:
		failures.append("device profile: expected at least one seeded level star to make this assertion meaningful")

	return failures


# ---------------------------------------------------------------------------
# Real integration: default paths, no fixtures at all. Agent LEVEL authors
# chapterId/levelId/taskIds directly onto res://content/missions/missions.json
# (see LevelDefinition.is_authored_level()); this proves ProfileStore's
# defensive reader actually understands that shape today, not just a
# hypothetical one.
# ---------------------------------------------------------------------------

func _test_real_content_seeds_starsByLevel_via_default_paths(path: String) -> Array:
	var failures: Array = []
	_install_device_fixture(path)

	var store := _store_with_real_content_defaults(path)
	var migrated := store.load_profile()

	var stars_by_level: Dictionary = migrated.get("starsByLevel", {})
	if int(stars_by_level.get("bedtime", -1)) != 1:
		failures.append("real content: expected level 'bedtime' seeded to 1 star via missions.json, got %s"
				% str(stars_by_level.get("bedtime")))
	if int(stars_by_level.get("firstWords", -1)) != 1:
		failures.append("real content: expected level 'firstWords' seeded to 1 star via missions.json, got %s"
				% str(stars_by_level.get("firstWords")))
	if stars_by_level.has("milkTime"):
		failures.append("real content: level 'milkTime' (feedingTime, incomplete in the fixture) must not be seeded a star")

	if int(migrated.get("stars", -1)) != DEVICE_STARS:
		failures.append("real content: 'stars' changed after seeding via missions.json, expected untouched %d, got %s"
				% [DEVICE_STARS, str(migrated.get("stars"))])

	var unlocked_chapters: Array = migrated.get("unlockedChapters", [])
	if not unlocked_chapters.has("ch2"):
		failures.append("real content: expected chapter 'ch2' unlocked via missions.json, got %s" % str(unlocked_chapters))
	if String(migrated.get("currentLevel", "")) != "milkTime":
		failures.append("real content: expected currentLevel fallback 'milkTime' (chapters.json ch2's first level), got %s"
				% str(migrated.get("currentLevel")))

	var completed_levels: Dictionary = migrated.get("levelCompleted", {})
	for level_id: String in ["bedtime", "firstWords"]:
		if not bool(completed_levels.get(level_id, false)):
			failures.append("real content: expected level '%s' marked completed via missions.json, got %s"
					% [level_id, str(completed_levels)])
	if completed_levels.has("milkTime"):
		failures.append("real content: level 'milkTime' (incomplete in the fixture) must not be marked completed")

	return failures


# ---------------------------------------------------------------------------
# Absent level definitions: seeding must be skipped, never fail
# ---------------------------------------------------------------------------

func _test_missing_level_definitions_skips_seeding_safely(path: String) -> Array:
	var failures: Array = []
	_install_device_fixture(path)

	var store := _store_with_no_level_data_at_all(path)
	var migrated := store.load_profile()

	if int(migrated.get("stars", -1)) != DEVICE_STARS:
		failures.append("missing level defs: stars was not preserved, got %s" % str(migrated.get("stars")))
	var completed: Array = migrated.get("completedActivities", [])
	if completed.size() != DEVICE_COMPLETED_COUNT:
		failures.append("missing level defs: completedActivities was not preserved")

	var stars_by_level: Dictionary = migrated.get("starsByLevel", {})
	if not stars_by_level.is_empty():
		failures.append("missing level defs: expected no seeded starsByLevel, got %s" % str(stars_by_level))

	var completed_levels: Dictionary = migrated.get("levelCompleted", {})
	if not completed_levels.is_empty():
		failures.append("missing level defs: expected no seeded levelCompleted, got %s" % str(completed_levels))

	return failures


func _test_chapter2_and_first_level_always_unlocked(path: String) -> Array:
	var failures: Array = []
	_install_device_fixture(path)

	# Even with the level definitions entirely absent (no dedicated
	# levels.json AND no level-tagged missions.json), chapter 2 and a
	# concrete first level must be unlocked so no returning profile is
	# stranded.
	var store := _store_with_no_level_data_at_all(path)
	var migrated := store.load_profile()

	var unlocked_chapters: Array = migrated.get("unlockedChapters", [])
	if not unlocked_chapters.has("ch2"):
		failures.append("missing level defs: chapter 'ch2' must always be unlocked after migration, got %s" % str(unlocked_chapters))

	var unlocked_levels: Array = migrated.get("unlockedLevels", [])
	if unlocked_levels.is_empty():
		failures.append("missing level defs: expected a concrete first-level fallback to be unlocked, got none")

	if String(migrated.get("currentChapter", "")) != "ch2":
		failures.append("missing level defs: expected currentChapter 'ch2', got %s" % str(migrated.get("currentChapter")))
	if String(migrated.get("currentLevel", "")).is_empty():
		failures.append("missing level defs: expected a non-empty currentLevel fallback")

	return failures


# ---------------------------------------------------------------------------
# starsByLevel persistence
# ---------------------------------------------------------------------------

func _test_starsByLevel_persists_across_reload(path: String) -> Array:
	var failures: Array = []

	var store := ProfileStore.new(path)
	var profile := store.default_profile()
	profile["starsByLevel"] = {"milkTime": 2, "bathTime": 3}
	if not store.save_profile(profile):
		failures.append("starsByLevel round trip: save_profile returned false")
		return failures

	var reload_store := ProfileStore.new(path)
	var reloaded := reload_store.load_profile()
	var stars_by_level: Dictionary = reloaded.get("starsByLevel", {})

	if int(stars_by_level.get("milkTime", -1)) != 2:
		failures.append("starsByLevel round trip: expected milkTime=2, got %s" % str(stars_by_level.get("milkTime")))
	if int(stars_by_level.get("bathTime", -1)) != 3:
		failures.append("starsByLevel round trip: expected bathTime=3, got %s" % str(stars_by_level.get("bathTime")))

	return failures


# ---------------------------------------------------------------------------
# SaveService.set_level_stars: max-wins
# ---------------------------------------------------------------------------

func _test_set_level_stars_is_max_wins(path: String) -> Array:
	var failures: Array = []

	var store := ProfileStore.new(path)
	var save: Node = SaveServiceScript.new(store)

	save.set_level_stars("milkTime", 3)
	if save.get_level_stars("milkTime") != 3:
		failures.append("max-wins: expected 3 after first call, got %d" % save.get_level_stars("milkTime"))

	# A worse replay result must never lower the stored rating.
	save.set_level_stars("milkTime", 1)
	if save.get_level_stars("milkTime") != 3:
		failures.append("max-wins: a lower replay result (1) reduced the stored rating; expected it to stay 3, got %d"
				% save.get_level_stars("milkTime"))

	# A better result still raises it.
	save.set_level_stars("milkTime", 2)
	if save.get_level_stars("milkTime") != 3:
		failures.append("max-wins: 2 must not exceed the already-stored 3, got %d" % save.get_level_stars("milkTime"))

	# Out-of-range values are clamped, not rejected outright.
	save.set_level_stars("bathTime", 99)
	if save.get_level_stars("bathTime") != 3:
		failures.append("max-wins: expected out-of-range 99 clamped to 3, got %d" % save.get_level_stars("bathTime"))
	save.set_level_stars("bedtime", -5)
	if save.get_level_stars("bedtime") != 0:
		failures.append("max-wins: expected out-of-range -5 clamped to 0, got %d" % save.get_level_stars("bedtime"))

	# Persists across reload too.
	var reload_store := ProfileStore.new(path)
	var reloaded := reload_store.load_profile()
	var stars_by_level: Dictionary = reloaded.get("starsByLevel", {})
	if int(stars_by_level.get("milkTime", -1)) != 3:
		failures.append("max-wins: value did not persist across reload, got %s" % str(stars_by_level.get("milkTime")))

	(save as Node).free()
	return failures


# ---------------------------------------------------------------------------
# Two currencies never contaminate each other
# ---------------------------------------------------------------------------

func _test_stars_and_level_stars_do_not_contaminate(path: String) -> Array:
	var failures: Array = []

	var store := ProfileStore.new(path)
	var save: Node = SaveServiceScript.new(store)

	save.add_stars(5)
	save.set_level_stars("milkTime", 3)
	save.set_level_stars("bathTime", 1)

	if save.get_stars() != 5:
		failures.append("contamination: get_stars() expected 5 (untouched by level ratings), got %d" % save.get_stars())
	if save.get_total_level_stars() != 4:
		failures.append("contamination: get_total_level_stars() expected 3+1=4, got %d" % save.get_total_level_stars())

	# Raising a level rating further must not touch the task total.
	save.set_level_stars("milkTime", 3)
	save.mark_activity_completed("someTask")
	if save.get_stars() != 5:
		failures.append("contamination: marking an activity completed changed 'stars' without add_stars being called; expected 5, got %d"
				% save.get_stars())

	(save as Node).free()
	return failures


# ---------------------------------------------------------------------------
# Unknown/newer profileVersion
# ---------------------------------------------------------------------------

func _test_unknown_future_version_does_not_crash(path: String) -> Array:
	var failures: Array = []

	var raw_text := JSON.stringify({
		"profileVersion": 99,
		"stars": 12,
		"completedActivities": ["feedMilk"],
		"currentChapter": "ch7",
		"currentLevel": "someFutureLevel",
		"starsByLevel": {"someFutureLevel": 3},
		"unlockedChapters": ["ch1", "ch2", "ch7"],
		"unlockedLevels": ["someFutureLevel"],
		"unlockedRooms": ["nursery"],
		"settings": {"speechLocale": "en-US", "speechEnabled": true, "thaiHints": true},
	})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(raw_text)
	file.close()

	var store := _store_with_ch2_fixture(path)
	var loaded := store.load_profile()

	if loaded.get("profileVersion") != 3:
		failures.append("unknown version: expected profileVersion normalized to 3, got %s" % str(loaded.get("profileVersion")))
	if int(loaded.get("stars", -1)) != 12:
		failures.append("unknown version: expected stars preserved as 12, got %s" % str(loaded.get("stars")))
	if String(loaded.get("currentChapter", "")) != "ch7":
		failures.append("unknown version: unknown-version fields should pass through field validation untouched, currentChapter got %s"
				% str(loaded.get("currentChapter")))
	var stars_by_level: Dictionary = loaded.get("starsByLevel", {})
	if int(stars_by_level.get("someFutureLevel", -1)) != 3:
		failures.append("unknown version: starsByLevel entry lost, got %s" % str(stars_by_level))

	return failures


# ---------------------------------------------------------------------------
# v3 round trip / idempotent migration
# ---------------------------------------------------------------------------

func _sample_v2_profile() -> Dictionary:
	return {
		"profileVersion": 2,
		"stars": 64,
		"completedActivities": ["feedMilk", "bedtimeBlanket"],
		"currentChapter": "ch2",
		"currentLevel": "bathTime",
		"starsByLevel": {"milkTime": 1, "bedtime": 3, "toysAndSmiles": 0},
		"unlockedChapters": ["ch1", "ch2"],
		"unlockedLevels": ["milkTime", "bathTime", "bedtime"],
		"unlockedRooms": ["nursery"],
		"settings": {
			"speechLocale": "en-US",
			"speechEnabled": true,
			"thaiHints": true,
			"soundEnabled": true,
			"ttsSpeed": "normal",
			"unlockedStickers": ["milkSticker"],
		},
	}


func _sample_v3_profile() -> Dictionary:
	var profile := _sample_v2_profile()
	profile["profileVersion"] = 3
	profile["levelCompleted"] = {"milkTime": true, "bedtime": true}
	return profile


## v2 -> v3: every level already rated >= 1 star was obviously finished, so it
## becomes a completion. NOTHING else may change -- this migration adds one
## derived field and touches no existing one.
func _test_v2_to_v3_marks_rated_levels_completed(path: String) -> Array:
	var failures: Array = []

	var original := _sample_v2_profile()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(original))
	file.close()

	var store := _store_with_ch2_fixture(path)
	var migrated := store.load_profile()

	if migrated.get("profileVersion") != 3:
		failures.append("v2->v3: expected profileVersion 3, got %s" % str(migrated.get("profileVersion")))

	var completed_levels: Dictionary = migrated.get("levelCompleted", {})
	for level_id: String in ["milkTime", "bedtime"]:
		if not bool(completed_levels.get(level_id, false)):
			failures.append("v2->v3: level '%s' had >= 1 star and must be marked completed, got %s"
					% [level_id, str(completed_levels)])
	# A 0-star v2 entry is not evidence of a finished level: under v2 every
	# finished level was force-rated to at least 1 star.
	if completed_levels.has("toysAndSmiles"):
		failures.append("v2->v3: a 0-star level must not be marked completed, got %s" % str(completed_levels))
	if completed_levels.has("bathTime"):
		failures.append("v2->v3: an unrated level must not be marked completed, got %s" % str(completed_levels))

	# Everything else carries over verbatim.
	for key: String in ["stars", "completedActivities", "currentChapter", "currentLevel",
			"starsByLevel", "unlockedChapters", "unlockedLevels", "unlockedRooms", "settings"]:
		if migrated.get(key) != original[key]:
			failures.append("v2->v3: key '%s' changed, expected %s, got %s"
					% [key, str(original[key]), str(migrated.get(key))])

	return failures


func _test_v3_profile_round_trips_unchanged(path: String) -> Array:
	var failures: Array = []

	var store := _store_with_ch2_fixture(path)
	var original := _sample_v3_profile()
	if not store.save_profile(original):
		failures.append("v3 round trip: save_profile returned false")
		return failures

	var reload_store := _store_with_ch2_fixture(path)
	var reloaded := reload_store.load_profile()

	for key in original.keys():
		if not reloaded.has(key):
			failures.append("v3 round trip: key '%s' missing after reload" % key)
			continue
		if reloaded[key] != original[key]:
			failures.append("v3 round trip: key '%s' changed, expected %s, got %s"
					% [key, str(original[key]), str(reloaded[key])])

	return failures


func _test_migration_is_idempotent(path: String) -> Array:
	var failures: Array = []

	var store := _store_with_ch2_fixture(path)
	var original := _sample_v3_profile()
	store.save_profile(original)

	var first_load := store.load_profile()
	# Re-saving and reloading an already-v3 profile a second time must not
	# change anything further -- migration only ever runs for version <= 2.
	store.save_profile(first_load)
	var second_load := store.load_profile()

	for key in first_load.keys():
		if second_load.get(key) != first_load[key]:
			failures.append("idempotency: key '%s' changed on a second migration pass, %s -> %s"
					% [key, str(first_load[key]), str(second_load.get(key))])

	return failures


## The v1 path must be idempotent too: a migrated profile re-saved and reloaded
## is a v3 profile, so the v1 seeding must not run a second time and (for
## instance) re-credit a level whose tasks are still in completedActivities.
func _test_v1_migration_is_idempotent(path: String) -> Array:
	var failures: Array = []
	_install_device_fixture(path)

	var store := _store_with_ch2_fixture(path)
	var first_load := store.load_profile()
	store.save_profile(first_load)
	var second_load := store.load_profile()

	for key in first_load.keys():
		if second_load.get(key) != first_load[key]:
			failures.append("v1 idempotency: key '%s' changed on a second pass, %s -> %s"
					% [key, str(first_load[key]), str(second_load.get(key))])

	return failures


# ---------------------------------------------------------------------------
# SaveService: the levelCompleted API
# ---------------------------------------------------------------------------

func _test_level_completed_api(path: String) -> Array:
	var failures: Array = []

	var store := ProfileStore.new(path)
	var save: Node = SaveServiceScript.new(store)

	var seen: Array = []
	save.connect("level_completed_changed", func(level_id: String) -> void: seen.append(level_id))

	if save.is_level_completed("milkTime"):
		failures.append("levelCompleted API: a fresh profile must have no completed levels")

	save.mark_level_completed("milkTime")
	if not save.is_level_completed("milkTime"):
		failures.append("levelCompleted API: mark_level_completed did not stick")
	if seen != ["milkTime"]:
		failures.append("levelCompleted API: expected one level_completed_changed emission, got %s" % str(seen))

	# Idempotent: replaying a finished level must not re-emit or re-write.
	save.mark_level_completed("milkTime")
	if seen.size() != 1:
		failures.append("levelCompleted API: re-marking an already-completed level re-emitted, got %s" % str(seen))

	save.mark_level_completed("")
	if save.get_level_completed().has(""):
		failures.append("levelCompleted API: an empty level id was stored")

	# Completion is independent of the rating: this level is finished with 0 stars.
	if save.get_level_stars("milkTime") != 0:
		failures.append("levelCompleted API: marking a level completed granted it %d stars; completion and rating are separate"
				% save.get_level_stars("milkTime"))
	if save.get_stars() != 0:
		failures.append("levelCompleted API: marking a level completed changed the lifetime task-star total")

	# Deep copy: a caller cannot reach in and grant itself progress.
	var snapshot: Dictionary = save.get_level_completed()
	snapshot["bathTime"] = true
	if save.is_level_completed("bathTime"):
		failures.append("levelCompleted API: get_level_completed handed out a live reference")

	# ...and it survives a reload.
	var reloaded: Dictionary = ProfileStore.new(path).load_profile().get("levelCompleted", {})
	if not bool(reloaded.get("milkTime", false)):
		failures.append("levelCompleted API: completion did not persist across reload, got %s" % str(reloaded))
	if reloaded.has("bathTime"):
		failures.append("levelCompleted API: a mutated snapshot leaked into the saved profile")

	(save as Node).free()
	return failures
