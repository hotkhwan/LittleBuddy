extends RefCounted

## Vocabulary review -- `scripts/content/vocabulary_review.gd`.
##
## The feature's success criterion is a NEGATIVE one: "a parent watching cannot
## tell which objects were chosen for review and which for the story". Most of
## this file is therefore spent proving that nothing observable changed shape --
## the row is the same size, the target is always in it, every entry is a plain
## object id with no marker on it, and a review pick is no more likely to land in
## any particular slot.
##
## `vocabulary_review.gd` is reached through a runtime `load()`, never a
## `preload()`. A `preload` of a broken script makes THIS CASE fail to parse, at
## which point `run_tests.gd` drops it from the report and a deleted feature looks
## like "fewer tests, still green" -- the exact failure `test_content_scripts.gd`
## exists to prevent. Loading at runtime makes a parse error a loud failure here.

const REVIEW_PATH: String = "res://scripts/content/vocabulary_review.gd"
## The pre-review chooser, used as the reference implementation for the
## "additive only" promise. Also loaded at runtime -- it is a Node subclass whose
## `class_name` is unavailable in the headless `--script` runner.
const MODE_HANDLER_PATH: String = "res://scripts/gameplay/mode_handler.gd"
const CONTENT_LIBRARY_PATH: String = "res://scripts/content/content_library.gd"
const LEVEL_SYSTEM_PATH: String = "res://scripts/progression/level_system.gd"
const PROFILE_STORE_PATH: String = "res://scripts/save/profile_store.gd"

const IDENTITY_SEEDS: int = 250
const TRIALS: int = 4000


func test_name() -> String:
	return "vocab_review"


func run():
	var failures: Array = []

	var review: GDScript = load(REVIEW_PATH) as GDScript
	if review == null or not review.can_instantiate():
		return ["%s is missing or has parse errors; the review feature is gone" % REVIEW_PATH]

	failures.append_array(_test_additive_only(review))
	failures.append_array(_test_review_weight_zero_disables(review))
	failures.append_array(_test_recency_curve(review))
	failures.append_array(_test_struggling_is_mild(review))
	failures.append_array(_test_weight_floor(review))
	failures.append_array(_test_review_actually_resurfaces(review))
	failures.append_array(_test_review_is_invisible(review))
	failures.append_array(_test_determinism(review))
	failures.append_array(_test_progress_recording(review))
	failures.append_array(_test_progress_is_defensive(review))
	failures.append_array(_test_profile_round_trip(review))
	failures.append_array(_test_level_ordinals())
	failures.append_array(_test_no_review_screen_shipped())

	return failures


## -- The promise: a missing `vocabularyProgress` changes NOTHING ----------------

## Not "uniform in distribution" -- identical, id for id, draw for draw, against
## the real `ModeHandler.build_choice_ids()`. If this ever goes red, review has
## stopped being additive and every existing level's choice rows have moved.
func _test_additive_only(review: GDScript):
	var failures: Array = []
	var handler: GDScript = load(MODE_HANDLER_PATH) as GDScript
	if handler == null:
		return ["could not load %s; the additive-only promise cannot be checked" % MODE_HANDLER_PATH]

	var pool: Array = _pool(["apple", "banana", "spoon", "cup", "bowl", "milk", "water"])
	var mismatches: int = 0
	for seed_value: int in range(1, IDENTITY_SEEDS + 1):
		for count: int in [1, 2, 3]:
			var before: Array = handler.call(
					"build_choice_ids", "teddy", pool, count, _rng(seed_value))
			var after: Array = review.call(
					"build_choice_ids", "teddy", pool, count, _rng(seed_value), {})
			if before != after:
				mismatches += 1
	if mismatches > 0:
		failures.append(
			("a profile with no vocabularyProgress must select EXACTLY as before: %d of %d "
			+ "seed/size combinations disagreed with ModeHandler.build_choice_ids()")
			% [mismatches, IDENTITY_SEEDS * 3])

	# And the same when the block exists but is empty, or is corrupt.
	for empty_case: Variant in [{}, null, 7, "nope", []]:
		var biased: Array = review.call("build_choice_ids", "teddy", pool, 3, _rng(99),
				{"progress": empty_case, "levelOrdinal": 5})
		var plain: Array = handler.call("build_choice_ids", "teddy", pool, 3, _rng(99))
		if biased != plain:
			failures.append("progress of %s must degrade to the pre-review selection, got %s vs %s"
					% [str(empty_case), str(biased), str(plain)])
	return failures


func _test_review_weight_zero_disables(review: GDScript):
	var failures: Array = []
	var handler: GDScript = load(MODE_HANDLER_PATH) as GDScript
	if handler == null:
		return failures
	var pool: Array = _pool(["apple", "banana", "spoon", "cup", "bowl", "milk"])
	var progress: Dictionary = _progress({"apple": 2, "spoon": 2, "cup": 3})

	for seed_value: int in range(1, 60):
		var off: Array = review.call("build_choice_ids", "teddy", pool, 3, _rng(seed_value),
				{"progress": progress, "levelOrdinal": 6, "reviewWeight": 0.0})
		var plain: Array = handler.call("build_choice_ids", "teddy", pool, 3, _rng(seed_value))
		if off != plain:
			failures.append("reviewWeight 0.0 must disable review entirely (seed %d): %s vs %s"
					% [seed_value, str(off), str(plain)])
			break

	# The settings reader agrees with the switch.
	if float(review.call("read_review_weight", {"settings": {"reviewWeight": 0.0}})) != 0.0:
		failures.append("read_review_weight() must read a 0.0 as a real 0.0")
	if float(review.call("read_review_weight", {})) != float(review.get("DEFAULT_REVIEW_WEIGHT")):
		failures.append("a profile with no reviewWeight must get the default, not 0")
	if float(review.call("read_review_weight", {"settings": {"reviewWeight": "loud"}})) \
			!= float(review.get("DEFAULT_REVIEW_WEIGHT")):
		failures.append("a malformed reviewWeight must fall back to the default, not delete review")
	if float(review.call("read_review_weight", {"settings": {"reviewWeight": 99.0}})) \
			> float(review.get("MAX_REVIEW_WEIGHT")):
		failures.append("reviewWeight must be clamped so a hand-edited file cannot drill one word")
	return failures


## -- Scheduling ------------------------------------------------------------------

func _test_recency_curve(review: GDScript):
	var failures: Array = []
	var cooldown: int = int(review.get("COOLDOWN_LEVELS"))

	for gap: int in range(0, cooldown):
		if float(review.call("recency_factor", gap)) != 0.0:
			failures.append(("recencyFactor(%d) must be ZERO inside the cooldown window: an "
					+ "immediately repeated word is nagging, not teaching") % gap)
	for gap: int in [2, 3, 4, 5]:
		if float(review.call("recency_factor", gap)) < 1.0:
			failures.append("recencyFactor(%d) should be at its peak over 2-5 levels" % gap)
	if float(review.call("recency_factor", 8)) >= float(review.call("recency_factor", 5)):
		failures.append("recencyFactor must decay after the peak")
	# The long tail: a word never seen again must not fall silently to zero.
	for gap: int in [20, 100, 5000]:
		var tail: float = float(review.call("recency_factor", gap))
		if tail <= 0.0:
			failures.append(("recencyFactor(%d) fell to zero; a word met once and never again is "
					+ "exactly the word review exists for") % gap)
		if tail < float(review.get("TAIL_FLOOR")) - 0.0001:
			failures.append("recencyFactor(%d) dropped below the documented tail floor" % gap)
	return failures


func _test_struggling_is_mild(review: GDScript):
	var failures: Array = []
	var bonus: float = float(review.get("STRUGGLE_BONUS"))
	if bonus > 0.5:
		failures.append(("STRUGGLE_BONUS is %.2f. Aggressively drilling a word a child struggles "
				+ "with is exactly how a game starts to feel like a test; the spec says MILD.")
				% bonus)

	var perfect: float = float(review.call("struggling_factor",
			{"exposureCount": 8, "successCount": 8}))
	var awful: float = float(review.call("struggling_factor",
			{"exposureCount": 8, "successCount": 0}))
	if perfect != 1.0:
		failures.append("a word the child always gets right must have a neutral struggling factor")
	if awful <= perfect:
		failures.append("a word the child gets wrong must resurface somewhat more often")
	if awful > perfect * (1.0 + bonus) + 0.0001:
		failures.append("the struggling factor exceeded its own documented ceiling")
	if float(review.call("struggling_factor", {})) != 1.0:
		failures.append("a word with no exposures has no success rate; it must stay neutral")
	return failures


func _test_weight_floor(review: GDScript):
	var failures: Array = []
	var floor_weight: float = float(review.get("NEUTRAL_WEIGHT"))

	# Inside the cooldown a word is DAMPENED, never banned: an object that cannot
	# appear for two levels is a visible, systematic hole.
	var just_seen: float = float(review.call(
			"weight_for", {"lastSeenLevel": 6, "exposureCount": 3, "successCount": 1}, 6, 1.0))
	if just_seen != floor_weight:
		failures.append("a just-seen word must sit at the neutral floor, got %.3f" % just_seen)
	if just_seen <= 0.0:
		failures.append("no word may ever be weighted out of existence")

	var never_placed: float = float(review.call(
			"weight_for", {"exposureCount": 3, "successCount": 1}, 6, 1.0))
	if never_placed != floor_weight:
		failures.append("a word with no lastSeenLevel must fall back to the neutral weight")

	# A save written by a future build (lastSeenLevel ahead of the current level)
	# must not produce a negative gap and a nonsense weight.
	var future: float = float(review.call(
			"weight_for", {"lastSeenLevel": 40, "exposureCount": 2, "successCount": 0}, 6, 1.0))
	if future < floor_weight:
		failures.append("a lastSeenLevel from the future must not drop below the floor")
	return failures


## -- It actually works --------------------------------------------------------------

## The positive half: with review on, words last seen 2-5 levels ago really do
## come back more often than the rest. Compared against the measured uniform rate
## from the SAME pool rather than a hard-coded number, so the assertion cannot
## pass by accident if the pool changes.
func _test_review_actually_resurfaces(review: GDScript):
	var failures: Array = []
	var ids: Array = ["apple", "banana", "spoon", "cup", "bowl", "milk", "water", "toothbrush"]
	var pool: Array = _pool(ids)
	var due: Array = ["spoon", "cup"]
	var progress: Dictionary = _progress({"spoon": 3, "cup": 4})
	var options: Dictionary = {"progress": progress, "levelOrdinal": 7, "reviewWeight": 1.0}

	var review_rate: float = _appearance_rate(review, "teddy", pool, 3, due, options)
	var plain_rate: float = _appearance_rate(review, "teddy", pool, 3, due, {})
	if review_rate <= plain_rate + 0.02:
		failures.append(("review did not resurface anything: due words appeared %.1f%% of rows "
				+ "with review on vs %.1f%% with it off") % [review_rate * 100.0, plain_rate * 100.0])

	# ...and a word still inside its cooldown is NOT the one being resurfaced.
	var fresh_options: Dictionary = {
		"progress": _progress({"spoon": 7, "cup": 7}), "levelOrdinal": 7, "reviewWeight": 1.0,
	}
	var fresh_rate: float = _appearance_rate(review, "teddy", pool, 3, due, fresh_options)
	if fresh_rate > plain_rate + 0.05:
		failures.append(("a word seen in the current level was resurfaced anyway (%.1f%% vs a "
				+ "%.1f%% baseline); the cooldown is not holding")
				% [fresh_rate * 100.0, plain_rate * 100.0])
	return failures


## -- Invisibility -------------------------------------------------------------------

## If review is visible as review, the design has failed. Four ways it could
## become visible, all checked here.
func _test_review_is_invisible(review: GDScript):
	var failures: Array = []
	var handler: GDScript = load(MODE_HANDLER_PATH) as GDScript
	var ids: Array = ["apple", "banana", "spoon", "cup", "bowl", "milk", "water", "toothbrush"]
	var pool: Array = _pool(ids)
	var due: Array = ["spoon", "cup"]
	var options: Dictionary = {
		"progress": _progress({"spoon": 3, "cup": 4}), "levelOrdinal": 7, "reviewWeight": 1.0,
	}

	var slot_counts: Array = [0, 0, 0, 0]
	var rows_without_a_due_word: int = 0
	var non_due_appearances: int = 0

	for i: int in range(TRIALS):
		var row: Array = review.call("build_choice_ids", "teddy", pool, 3, _rng(1000 + i), options)

		# 1. Same shape as before. A shorter or longer row is itself a tell.
		if handler != null:
			var reference: Array = handler.call("build_choice_ids", "teddy", pool, 3, _rng(1000 + i))
			if row.size() != reference.size():
				failures.append("a review row has %d entries where the story row has %d"
						% [row.size(), reference.size()])
				break

		# 2. Plain object ids only -- no marker, no flag, no metadata.
		for entry: Variant in row:
			if typeof(entry) != TYPE_STRING:
				failures.append("a choice row entry is a %s, not a plain object id"
						% type_string(typeof(entry)))
				break

		# 3. The target is present exactly once and nothing repeats.
		var seen: Dictionary = {}
		for entry: Variant in row:
			seen[String(entry)] = true
		if seen.size() != row.size():
			failures.append("a review row contains the same object twice: %s" % str(row))
			break
		if not seen.has("teddy"):
			failures.append("the target went missing from a review row: %s" % str(row))
			break
		for entry: Variant in row:
			if String(entry) != "teddy" and not ids.has(String(entry)):
				failures.append("review introduced '%s', which is not in the story's pool"
						% String(entry))
				break

		# 4. Position is unbiased: a review pick must be no likelier to sit in any
		#    given slot than the target is.
		var has_due: bool = false
		for slot: int in range(row.size()):
			var object_id: String = String(row[slot])
			if due.has(object_id):
				has_due = true
				if slot < slot_counts.size():
					slot_counts[slot] += 1
			elif object_id != "teddy":
				non_due_appearances += 1
		if not has_due:
			rows_without_a_due_word += 1

	var placements: int = 0
	for count: Variant in slot_counts:
		placements += int(count)
	if placements > 0:
		for slot: int in range(slot_counts.size()):
			var share: float = float(slot_counts[slot]) / float(placements)
			if share < 0.18 or share > 0.32:
				failures.append(("review picks cluster in slot %d (%.1f%% of placements). A "
						+ "predictable position is a parent-visible tell.")
						% [slot, share * 100.0])

	# 5. Review is a BIAS, not a takeover: plenty of rows still show no due word at
	#    all, and non-due objects keep appearing. A row that is always the same
	#    three "revision" objects is a flashcard with extra steps.
	if rows_without_a_due_word < TRIALS / 10:
		failures.append(("only %d of %d rows contained no review word; resurfacing has become a "
				+ "fixed set, which reads as a quiz") % [rows_without_a_due_word, TRIALS])
	if non_due_appearances < TRIALS:
		failures.append("non-review objects almost stopped appearing; the row is no longer varied")
	return failures


func _test_determinism(review: GDScript):
	var failures: Array = []
	var pool: Array = _pool(["apple", "banana", "spoon", "cup", "bowl"])
	var options: Dictionary = {
		"progress": _progress({"spoon": 3}), "levelOrdinal": 7, "reviewWeight": 1.0,
	}
	var first: Array = []
	for i: int in range(20):
		first.append(review.call("build_choice_ids", "teddy", pool, 3, _rng(4242), options))
	var second: Array = []
	for i: int in range(20):
		second.append(review.call("build_choice_ids", "teddy", pool, 3, _rng(4242), options))
	if first != second:
		failures.append("weighted selection is not reproducible for a fixed seed")
	return failures


## -- The tracked data ------------------------------------------------------------------

func _test_progress_recording(review: GDScript):
	var failures: Array = []

	var progress: Dictionary = review.call("record_exposure", {}, "milk", 12, true)
	var entry: Dictionary = progress.get("milk", {})
	if int(entry.get("exposureCount", 0)) != 1 or int(entry.get("successCount", 0)) != 1 \
			or int(entry.get("lastSeenLevel", 0)) != 12:
		failures.append("record_exposure() did not record a first successful exposure: %s"
				% str(entry))

	progress = review.call("record_exposure", progress, "milk", 13, false)
	entry = progress.get("milk", {})
	if int(entry.get("exposureCount", 0)) != 2 or int(entry.get("successCount", 0)) != 1:
		failures.append("a miss must count as an exposure but not as a success: %s" % str(entry))
	if int(entry.get("lastSeenLevel", 0)) != 13:
		failures.append("lastSeenLevel must follow the newest level seen")

	# Replaying an earlier level must not rewrite history backwards.
	progress = review.call("record_exposure", progress, "milk", 4, true)
	if int((progress.get("milk", {}) as Dictionary).get("lastSeenLevel", 0)) != 13:
		failures.append("replaying an older level must not make a word look stale")

	# Only the three tracked keys, ever. No streaks, no scores, no accuracy.
	for key: Variant in (progress.get("milk", {}) as Dictionary).keys():
		if not ["lastSeenLevel", "exposureCount", "successCount"].has(String(key)):
			failures.append(("the progress entry grew a '%s' key. The spec tracks three numbers; "
					+ "anything more is the leech algorithm it explicitly rules out.") % String(key))

	# A whole row at once, with one winner.
	var row: Dictionary = review.call("record_row", {},
			["banana", "apple", "spoon", "banana"], 9, ["banana"])
	if row.size() != 3:
		failures.append("record_row() must count each distinct object once, got %d" % row.size())
	if int((row.get("banana", {}) as Dictionary).get("successCount", 0)) != 1:
		failures.append("record_row() did not credit the object the child chose")
	if int((row.get("apple", {}) as Dictionary).get("successCount", 0)) != 0:
		failures.append("record_row() credited a distractor with a success")
	if int((row.get("apple", {}) as Dictionary).get("exposureCount", 0)) != 1:
		failures.append("a distractor on screen IS an exposure; that is the whole mechanism")

	# Purity: the caller's dictionary is never mutated under it.
	var original: Dictionary = _progress({"milk": 3})
	var snapshot: Dictionary = original.duplicate(true)
	review.call("record_exposure", original, "milk", 20, true)
	if original != snapshot:
		failures.append("record_exposure() mutated its argument")
	return failures


func _test_progress_is_defensive(review: GDScript):
	var failures: Array = []
	var messy: Dictionary = {
		"milk": {"lastSeenLevel": 4, "exposureCount": 3, "successCount": 9},
		"water": {"lastSeenLevel": -2, "exposureCount": -5, "successCount": 1},
		"": {"lastSeenLevel": 1},
		"bad": 7,
		"alsoBad": [1, 2],
	}
	var clean: Dictionary = review.call("sanitize_progress", messy)
	if clean.has("") or clean.has("bad") or clean.has("alsoBad"):
		failures.append("sanitize_progress() kept an unusable entry: %s" % str(clean.keys()))
	if int((clean.get("milk", {}) as Dictionary).get("successCount", 0)) > 3:
		failures.append("successCount must be clamped to exposureCount, or the success rate "
				+ "can exceed 1 and the struggling factor goes negative")
	var water: Dictionary = clean.get("water", {})
	if int(water.get("lastSeenLevel", -1)) < 0 or int(water.get("exposureCount", -1)) < 0:
		failures.append("negative counters must be clamped, not carried through")
	for garbage: Variant in [null, 5, "text", [], true]:
		if not (review.call("sanitize_progress", garbage) as Dictionary).is_empty():
			failures.append("sanitize_progress(%s) must yield an empty block" % str(garbage))
	return failures


## -- Persistence ---------------------------------------------------------------------

## The block must survive a real `ProfileStore` round trip WITHOUT a schema bump:
## the save is at v4 and was migrated twice this week.
func _test_profile_round_trip(review: GDScript):
	var failures: Array = []
	var store_script: GDScript = load(PROFILE_STORE_PATH) as GDScript
	if store_script == null:
		return ["could not load %s" % PROFILE_STORE_PATH]

	var path: String = "user://test_vocab_review_profile.json"
	var store: RefCounted = store_script.new(path)
	var profile: Dictionary = store.call("default_profile")
	var settings: Dictionary = profile.get("settings", {})
	settings["reviewWeight"] = 1.5
	profile["settings"] = settings

	var progress: Dictionary = review.call("record_exposure", {}, "milk", 12, true)
	progress = review.call("record_exposure", progress, "banana", 9, false)
	profile = review.call("write_progress", profile, progress)

	var saved: bool = bool(store.call("save_profile", profile))
	if not saved:
		failures.append("could not write the test profile")
	var reloaded: Dictionary = store.call("load_profile")

	if int(reloaded.get("profileVersion", 0)) != int(store_script.get("CURRENT_VERSION")):
		failures.append("adding vocabularyProgress must not change the schema version")

	var restored: Dictionary = review.call("read_progress", reloaded)
	if restored != progress:
		failures.append(("vocabularyProgress did not survive a ProfileStore round trip.\n"
				+ "  wrote:    %s\n  read back: %s\n"
				+ "  (ProfileStore._sanitize() rebuilds the profile from default_profile() and "
				+ "copies only known TOP-LEVEL keys, so the settings mirror is what carries it "
				+ "today -- see read_progress().)") % [str(progress), str(restored)])

	if absf(float(review.call("read_review_weight", reloaded)) - 1.5) > 0.0001:
		failures.append("settings.reviewWeight did not survive a ProfileStore round trip")

	# Stars and completions are untouched by any of this.
	if int(reloaded.get("stars", -1)) != 0 or not (reloaded.get("levelCompleted", null) is Dictionary):
		failures.append("writing review data disturbed unrelated profile fields")

	# A profile that has never met review reads as "no history", never as an error.
	var virgin: Dictionary = store_script.new(path).call("default_profile")
	if not (review.call("read_progress", virgin) as Dictionary).is_empty():
		failures.append("a fresh profile must report an empty review history")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return failures


## -- Level ordinals -----------------------------------------------------------------

## "Levels since last seen" is only meaningful against the order the child meets
## the content in, so the ordinal has to come from the authored journey.
func _test_level_ordinals():
	var failures: Array = []
	var library_script: GDScript = load(CONTENT_LIBRARY_PATH) as GDScript
	var system_script: GDScript = load(LEVEL_SYSTEM_PATH) as GDScript
	if library_script == null or system_script == null:
		return ["could not load the content library or the level system"]

	var library: RefCounted = library_script.new()
	library.call("load_all")
	var system: RefCounted = system_script.new()
	system.call("load_all", library, "")

	var journey: PackedStringArray = system.call("get_journey_level_ids")
	if journey.size() < 5:
		failures.append("the authored journey resolved only %d levels; the ordinal is vacuous"
				% journey.size())
		return failures

	var previous: int = 0
	for level_id: String in journey:
		var ordinal: int = int(system.call("get_level_ordinal", level_id))
		if ordinal != previous + 1:
			failures.append("get_level_ordinal('%s') returned %d, expected %d"
					% [level_id, ordinal, previous + 1])
		previous = ordinal

	if int(system.call("get_level_ordinal", "notALevel")) != 0:
		failures.append("an unknown level must return 0, not a position")
	if int(system.call("get_level_ordinal", "")) != 0:
		failures.append("an empty level id must return 0")

	# The Chapter 3 day must stay in its authored order -- the ordinal is what the
	# cooldown is measured in, so a reordering silently reschedules every word.
	var chain: Array = ["goodMorning", "gettingDressed", "breakfast", "playTime", "tidyAndBed"]
	var last: int = 0
	for level_id: String in chain:
		var ordinal: int = int(system.call("get_level_ordinal", level_id))
		if ordinal <= 0:
			failures.append("Chapter 3 level '%s' has no journey position" % level_id)
		elif ordinal <= last:
			failures.append("'%s' is out of order in the journey (%d after %d)"
					% [level_id, ordinal, last])
		last = ordinal
	return failures


## -- What this feature must NOT be ---------------------------------------------------

## The spec's list of things review is explicitly not. A review screen would be a
## scene; a quiz mode would be a mode. Cheap to check, and the check is the thing
## that stops "one small parent-facing word list" from arriving by accident.
func _test_no_review_screen_shipped():
	var failures: Array = []
	for path: String in [
		"res://scenes/review", "res://scenes/progression/review_screen.tscn",
		"res://scenes/progression/flashcards.tscn", "res://scripts/gameplay/review_mode.gd",
		"res://scripts/gameplay/quiz_mode.gd",
	]:
		if ResourceLoader.exists(path) or DirAccess.dir_exists_absolute(path):
			failures.append(("%s exists. Review must happen inside activities the child already "
					+ "wants to do -- no flashcards, no study screen, no quiz mode, no popup.")
					% path)

	# The mode registry is the other door a "review mode" would come in through.
	var runner: GDScript = load("res://scripts/gameplay/mission_runner.gd") as GDScript
	if runner != null:
		var modes: Dictionary = runner.get("MODE_SCRIPTS")
		for key: Variant in modes.keys():
			var mode: String = String(key).to_lower()
			if mode.contains("review") or mode.contains("quiz") or mode.contains("flashcard"):
				failures.append("a '%s' mode was registered; review must not be a mode" % String(key))
	return failures


## -- Helpers ---------------------------------------------------------------------------

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _pool(ids: Array) -> Array:
	var pool: Array = []
	for object_id: Variant in ids:
		pool.append({"objectId": String(object_id), "category": "feeding"})
	return pool


## `{wordId: lastSeenLevel}` -> a full progress block with plausible counters.
func _progress(last_seen_by_word: Dictionary) -> Dictionary:
	var progress: Dictionary = {}
	for word_id: Variant in last_seen_by_word.keys():
		progress[String(word_id)] = {
			"lastSeenLevel": int(last_seen_by_word[word_id]),
			"exposureCount": 4,
			"successCount": 3,
		}
	return progress


## How often at least one of `wanted` appears in a choice row, over TRIALS rows.
func _appearance_rate(
	review: GDScript, target_id: String, pool: Array, count: int, wanted: Array, options: Dictionary
) -> float:
	var hits: int = 0
	for i: int in range(TRIALS):
		var row: Array = review.call("build_choice_ids", target_id, pool, count, _rng(7000 + i),
				options)
		for entry: Variant in row:
			if wanted.has(String(entry)):
				hits += 1
				break
	return float(hits) / float(TRIALS)
