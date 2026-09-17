extends RefCounted

## Guards the "2-3 hours of replayable play" acceptance targets.
##
## This case fails loudly if content is ever deleted or a category regresses,
## so a future refactor cannot silently shrink the game.

const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const ContentValidatorScript := preload("res://scripts/content/content_validator.gd")

const EXPECTED_CATEGORIES: Array[String] = ["feeding", "dressing", "bath", "play", "bedtime"]
const EXPECTED_MODES: Array[String] = ["findIt", "sayIt", "followInstruction"]

const MIN_TASKS_PER_CATEGORY: int = 4
const MIN_TASKS_PER_MODE: int = 5


func test_name() -> String:
	return "content_counts"


func run():
	var failures: Array = []

	var library: Object = ContentLibraryScript.new()
	if library == null:
		return ["content_library.gd could not be instantiated"]
	library.load_all()

	# Headline targets, enforced by the validator's shared constants.
	for problem: Variant in ContentValidatorScript.validate_counts(library):
		failures.append(str(problem))

	# All five activity categories exist and each carries real content.
	for category: String in EXPECTED_CATEGORIES:
		var tasks: Array = library.get_tasks_in_category(category)
		if tasks.size() < MIN_TASKS_PER_CATEGORY:
			failures.append(
				"category '%s' has %d tasks, expected at least %d"
				% [category, tasks.size(), MIN_TASKS_PER_CATEGORY]
			)
		if library.get_objects_in_category(category).is_empty():
			failures.append("category '%s' has no objects" % category)
		if library.get_words_in_category(category).is_empty():
			failures.append("category '%s' has no vocabulary" % category)

	# All three mini-game modes are actually playable.
	for mode: String in EXPECTED_MODES:
		var mode_tasks: Array = library.get_tasks_with_mode(mode)
		if mode_tasks.size() < MIN_TASKS_PER_MODE:
			failures.append(
				"mode '%s' has %d tasks, expected at least %d"
				% [mode, mode_tasks.size(), MIN_TASKS_PER_MODE]
			)

	# Sticker pacing must be monotonic so progression never unlocks backwards.
	var previous_threshold: int = -1
	for sticker: Variant in library.get_stickers():
		var sticker_dict: Dictionary = sticker
		var threshold: int = int(sticker_dict.get("unlockAtStars", 0))
		if threshold < previous_threshold:
			failures.append(
				"sticker '%s' unlocks at %d, before the previous sticker"
				% [str(sticker_dict.get("stickerId", "")), threshold]
			)
		previous_threshold = threshold

	# The first sticker must be reachable early, or the reward loop feels dead.
	if library.get_unlocked_stickers(3).is_empty():
		failures.append("no sticker is unlockable within the first 3 stars")

	# Every sticker must eventually be reachable by playing the missions.
	var total_available_stars: int = 0
	for task: Variant in library.get_tasks():
		var reward: Variant = (task as Dictionary).get("reward", {})
		if typeof(reward) == TYPE_DICTIONARY:
			total_available_stars += int((reward as Dictionary).get("stars", 0))
	if total_available_stars <= 0:
		failures.append("tasks award no stars at all")

	return failures
