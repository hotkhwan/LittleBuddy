extends RefCounted

## "A Day With Little Buddy" -- the Chapter 3 vertical slice, asserted as DATA.
##
## Everything here is a property of `content/**`. No scene, no navigation, no
## `Node3D`: if this case needs a 3D type to answer a question, the question was
## about the wrong layer.
##
## What it is defending, in order of how expensive each would be to discover on a
## child's iPad instead of here:
##
##   1. **A target id that no room provides.** `"bedroom.doorToLivingRoom"` looks
##      exactly as plausible as `"bedroom.doorToBathroom"` in a JSON file, and the
##      house ring does not have that door. The level would simply never advance.
##   2. **Speech creeping into a star.** The whole product rests on a child who
##      never speaks reaching 3/3. That is one `starRules` edit away from being
##      false, and nothing else in the suite would notice.
##   3. **Level order drifting from the chapter chain.** `levelNumber` and
##      `chapters.json` are two independent statements of the same fact.
##
## Scripts are loaded BY PATH. `--headless --script` does not build the global
## class cache, so `class_name` is unavailable here.

const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const ContentValidatorScript := preload("res://scripts/content/content_validator.gd")
const LevelSystemScript := preload("res://scripts/progression/level_system.gd")
const StarRulesScript := preload("res://scripts/progression/star_rules.gd")
const SemanticIdScript := preload("res://scripts/navigation/semantic_id.gd")

## Loaded at runtime rather than preloaded: `house_layout.gd` belongs to the
## world layer, and a parse error over there must not take this content case with
## it. When it is unavailable the contract list below still carries the test.
const HOUSE_LAYOUT_PATH: String = "res://scripts/house/house_layout.gd"

const CHAPTER_ID: String = "ch3"

## The slice, exactly as `docs/SLICE_CONTRACT.md` §1 locks it:
## `[levelId, missionId, title, levelNumber, taskCount]`.
const SLICE: Array = [
	["goodMorning", "goodMorningRoutine", "Good Morning", 11, 7],
	["gettingDressed", "morningRoutine", "Getting Dressed", 12, 7],
	["breakfast", "breakfastTime", "Breakfast", 13, 8],
	["playTime", "toddlerPlayTime", "Play Time", 14, 8],
	["tidyAndBed", "tidyAndBedtime", "Clean Up and Good Night", 15, 8],
]

## Contract §2: every activity target the four greybox rooms provide. Furniture
## plus doors. Hard-coded on purpose -- this is the *contract*, and cross-checked
## against `house_layout.gd` below so the two can never silently diverge.
##
## The house is a RING (bedroom -> bathroom -> livingRoom -> kitchen -> bedroom),
## which is why `livingRoom` has no door to `bedroom`: the walk home at the end
## of the day goes through the kitchen.
const CONTRACT_TARGET_IDS: Array[String] = [
	"bedroom.bed",
	"bedroom.wardrobe",
	"bedroom.toy",
	"bedroom.doorToBathroom",
	"bedroom.doorToKitchen",
	"bathroom.sink",
	"bathroom.bath",
	"bathroom.towel",
	"bathroom.doorToBedroom",
	"bathroom.doorToLivingRoom",
	"kitchen.fridge",
	"kitchen.counter",
	"kitchen.table",
	"kitchen.doorToLivingRoom",
	"kitchen.doorToBedroom",
	"livingRoom.sofa",
	"livingRoom.toyBox",
	"livingRoom.book",
	"livingRoom.doorToBathroom",
	"livingRoom.doorToKitchen",
]

## The keys whose VALUE is a semantic target id. Declared in `content/index.json`
## as `semanticTargetKeys` too, so a validator can find them generically.
const SEMANTIC_TARGET_KEYS: Array[String] = ["targetId", "requiresWalkTo"]

## Contract §3. Content may ask for these and nothing else -- never an animation
## file name, never an `AnimationTree` state.
const SEMANTIC_ACTIONS: Array[String] = [
	"idle",
	"walk",
	"wave",
	"point",
	"clap",
	"pickUp",
	"hold",
	"give",
	"eat",
	"drink",
	"brushTeeth",
	"sit",
	"stand",
	"hug",
	"sleep",
	"wake",
	"celebrate",
]

## Modes that are English listening/recognition. Star 2, never star 1.
const LISTENING_MODES: Array[String] = ["findIt", "sayIt"]

## Bible 4-10 minutes per level, 20-30 minutes for the slice.
const MIN_LEVEL_MINUTES: int = 4
const MAX_LEVEL_MINUTES: int = 10
const MIN_SLICE_MINUTES: int = 20
const MAX_SLICE_MINUTES: int = 30

## Child UX (CLAUDE.md): no failure language anywhere a child can hear it.
const BANNED_CHILD_FACING: Array[String] = [
	"wrong",
	"incorrect",
	"fail",
	"score",
	"%",
	"percent",
	"bad",
	"stupid",
	"hurry",
	"time's up",
	"you lose",
]

const CHILD_FACING_KEYS: Array[String] = ["prompt", "instruction", "repeatPrompt"]

var _library: Object = null
var _system: Object = null


func test_name() -> String:
	return "chapter3_slice"


func run():
	var failures: Array = []

	_library = ContentLibraryScript.new()
	if _library == null:
		return ["content_library.gd could not be instantiated"]
	_library.load_all()

	for warning: Variant in _library.get_load_warnings():
		failures.append("content failed to load cleanly: %s" % str(warning))

	_system = LevelSystemScript.new()
	if _system == null:
		return ["level_system.gd could not be instantiated"]
	_system.load_all(_library)

	# The whole bundled set, slice included, must still validate clean. Run here
	# as well as in `test_level_progression` so a content-only regression fails
	# in the content case that owns it.
	for problem: Variant in ContentValidatorScript.validate_all(_library):
		failures.append("content validation: %s" % str(problem))

	failures.append_array(_test_five_levels_exist_and_are_ordered())
	failures.append_array(_test_every_target_id_is_real())
	failures.append_array(_test_every_action_is_semantic())
	failures.append_array(_test_targets_stay_inside_the_level_rooms())
	failures.append_array(_test_touch_alone_reaches_three_stars())
	failures.append_array(_test_star_one_needs_no_listening_task())
	failures.append_array(_test_star_rules_are_structurally_sound())
	failures.append_array(_test_no_duplicate_task_ids())
	failures.append_array(_test_vocabulary_behind_every_target_word())
	failures.append_array(_test_pacing())
	failures.append_array(_test_child_facing_language())
	failures.append_array(_test_named_prompts_are_present())

	return failures


# ---------------------------------------------------------------------------
# 1. The five levels, in order
# ---------------------------------------------------------------------------

func _test_five_levels_exist_and_are_ordered():
	var failures: Array = []

	var chain: PackedStringArray = _system.get_chapter_chain(CHAPTER_ID)
	if chain.size() != SLICE.size():
		failures.append("chapter 3 should chain %d levels, got %d: %s"
				% [SLICE.size(), chain.size(), str(chain)])

	# `levelNumber` and the chapter chain are two independent statements of the
	# same ordering. Walk the CHAIN (not the expected order) and assert the
	# numbers rise, so a reshuffled `chapters.json` cannot look plausible.
	var previous_number: int = 0
	for chained_id: String in chain:
		var chained: RefCounted = _system.get_level(chained_id)
		if chained == null:
			continue
		var chained_number: int = int(chained.call("get_level_number"))
		if chained_number <= previous_number:
			failures.append(
				"chapter 3 runs '%s' (level %d) after level %d; the chain and levelNumber disagree"
				% [chained_id, chained_number, previous_number])
		previous_number = chained_number

	for i: int in range(SLICE.size()):
		var row: Array = SLICE[i]
		var level_id: String = String(row[0])

		if i < chain.size() and chain[i] != level_id:
			failures.append("chapter 3 position %d should be '%s', got '%s'"
					% [i, level_id, chain[i]])

		var level: RefCounted = _system.get_level(level_id)
		if level == null:
			failures.append("level '%s' does not exist" % level_id)
			continue

		if String(level.call("get_mission_id")) != String(row[1]):
			failures.append("level '%s' should run mission '%s', got '%s'"
					% [level_id, String(row[1]), String(level.call("get_mission_id"))])
		if String(level.call("get_title")) != String(row[2]):
			failures.append("level '%s' should be titled '%s', got '%s'"
					% [level_id, String(row[2]), String(level.call("get_title"))])
		if int(level.call("get_level_number")) != int(row[3]):
			failures.append("level '%s' should be level %d, got %d"
					% [level_id, int(row[3]), int(level.call("get_level_number"))])
		if String(level.call("get_chapter_id")) != CHAPTER_ID:
			failures.append("level '%s' should belong to %s" % [level_id, CHAPTER_ID])
		if not bool(level.call("is_authored_level")):
			failures.append("level '%s' must be an authored level (levelId + chapterId)" % level_id)
		if String(level.call("get_story_beat")).strip_edges().is_empty():
			failures.append("level '%s' has no storyBeat" % level_id)
		if not bool(level.call("has_known_template")):
			failures.append("level '%s' uses an unknown template '%s'"
					% [level_id, String(level.call("get_template"))])

		var task_ids: PackedStringArray = _system.get_level_task_ids(level_id)
		if task_ids.size() != int(row[4]):
			failures.append("level '%s' should have %d tasks, got %d"
					% [level_id, int(row[4]), task_ids.size()])
		for task_id: String in task_ids:
			if not _library.has_task(task_id):
				failures.append("level '%s' points at unknown task '%s'" % [level_id, task_id])

	# The bonus level rides along with the chapter and never gates it.
	if _system.get_chapter_chain(CHAPTER_ID).has("sayItChallenge"):
		failures.append("'sayItChallenge' must stay a BONUS level, not a chain gate")

	return failures


# ---------------------------------------------------------------------------
# 2. Semantic ids -- the hard rule
# ---------------------------------------------------------------------------

func _test_every_target_id_is_real():
	var failures: Array = []

	var known: Dictionary = {}
	for target_id: String in CONTRACT_TARGET_IDS:
		known[target_id] = true

	# Cross-check the contract list against the room data itself, so adding a
	# prop in `house_layout.gd` without telling content (or vice versa) surfaces
	# here rather than as a level that will not advance.
	var layout: GDScript = load(HOUSE_LAYOUT_PATH) as GDScript
	if layout != null:
		var from_layout: Dictionary = {}
		for room_id: Variant in layout.room_ids():
			for target_id: Variant in layout.target_ids(String(room_id)):
				from_layout[layout.semantic_id(String(room_id), String(target_id))] = true
		for target_id: String in known.keys():
			if not from_layout.has(target_id):
				failures.append(
					"contract target '%s' is not provided by house_layout.gd any more" % target_id)
		for target_id: Variant in from_layout.keys():
			if not known.has(String(target_id)):
				failures.append(
					"house_layout.gd provides '%s', which the slice contract does not list"
					% String(target_id))

	for task: Variant in _slice_tasks():
		var task_dict: Dictionary = task
		var task_id: String = String(task_dict.get("taskId", ""))

		var has_any: bool = false
		for key: String in SEMANTIC_TARGET_KEYS:
			if not task_dict.has(key):
				continue
			has_any = true
			var value: Variant = task_dict[key]
			if typeof(value) != TYPE_STRING:
				failures.append("task '%s': '%s' must be a string, got %s"
						% [task_id, key, type_string(typeof(value))])
				continue
			var target_id: String = String(value)

			for problem: Variant in SemanticIdScript.problems(target_id):
				failures.append("task '%s'.%s: %s" % [task_id, key, str(problem)])

			if not SemanticIdScript.is_qualified(target_id):
				failures.append(
					"task '%s'.%s = '%s' is not '<roomId>.<targetId>'; an unqualified id cannot name a room"
					% [task_id, key, target_id])
				continue
			if not SemanticIdScript.is_known_room(SemanticIdScript.room_of(target_id)):
				failures.append("task '%s'.%s = '%s' names a room that does not exist"
						% [task_id, key, target_id])
			if not known.has(target_id):
				failures.append(
					"task '%s'.%s = '%s' is a target NO ROOM PROVIDES; the level would never advance"
					% [task_id, key, target_id])

		if not has_any:
			failures.append(
				"task '%s' is a Chapter 3 slice task with no semantic target; it cannot place the child anywhere"
				% task_id)

	return failures


func _test_every_action_is_semantic():
	var failures: Array = []
	for task: Variant in _slice_tasks():
		var task_dict: Dictionary = task
		var task_id: String = String(task_dict.get("taskId", ""))
		if not task_dict.has("characterAction"):
			failures.append("task '%s' asks for no character action" % task_id)
			continue
		var action: String = String(task_dict["characterAction"])
		if not SEMANTIC_ACTIONS.has(action):
			failures.append(
				"task '%s' asks for '%s', which is not a semantic action (contract §3)"
				% [task_id, action])
		# The failure this really guards: a file name or a path leaking in.
		for marker: String in ["res://", ".glb", ".anim", "/", "_v"]:
			if action.contains(marker):
				failures.append("task '%s': '%s' looks like an animation asset, not a semantic action"
						% [task_id, action])
	return failures


## A level's targets must lie in the rooms the level says it visits. A breakfast
## task pointing at `bathroom.sink` is well-formed, real, and still a bug.
func _test_targets_stay_inside_the_level_rooms():
	var failures: Array = []
	for row: Array in SLICE:
		var level_id: String = String(row[0])
		var mission: Dictionary = _library.get_mission(String(row[1]))
		if mission.is_empty():
			continue
		var rooms: Array = []
		var raw: Variant = mission.get("roomPath", [])
		if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
			failures.append("level '%s' declares no 'roomPath'" % level_id)
			continue
		for entry: Variant in (raw as Array):
			rooms.append(String(entry))

		for task_id: String in _system.get_level_task_ids(level_id):
			var task: Dictionary = _library.get_task(task_id)
			for key: String in SEMANTIC_TARGET_KEYS:
				if not task.has(key):
					continue
				var room: String = SemanticIdScript.room_of(String(task[key]))
				if room.is_empty() or rooms.has(room):
					continue
				failures.append(
					"level '%s' task '%s' points at '%s', but the level only visits %s"
					% [level_id, task_id, String(task[key]), str(rooms)])
	return failures


# ---------------------------------------------------------------------------
# 3. Speech is never required
# ---------------------------------------------------------------------------

## The product promise, as an assertion: a child who never turns the microphone
## on completes every task by touch and reaches 3/3 on every level.
##
## `ModeHandler.complete_by_touch()` makes every task id reachable without a
## microphone, so "completed every task id" IS the touch-only session.
func _test_touch_alone_reaches_three_stars():
	var failures: Array = []

	for row: Array in SLICE:
		var level_id: String = String(row[0])
		var touch_only: Array = []
		for task_id: String in _system.get_level_task_ids(level_id):
			touch_only.append(task_id)

		var rating: int = _system.rate_session(level_id, StarRulesScript.session(touch_only))
		if rating != 3:
			failures.append(
				"level '%s': a touch-only player rates %d/3; speech must never be needed for a star"
				% [level_id, rating])

		# And the same promise stated from the data side, so a future engine
		# change cannot make it true only by accident.
		for task_id: String in _system.get_level_task_ids(level_id):
			var task: Dictionary = _library.get_task(task_id)
			if bool(task.get("speechRequired", false)):
				failures.append("task '%s' declares speechRequired; no task may" % task_id)
			if bool(task.get("requiresSpeech", false)):
				failures.append("task '%s' declares requiresSpeech; no task may" % task_id)

	return failures


## Star 1 is core completion and must be reachable by a child who has understood
## nothing yet -- so no listening/recognition task may sit in `coreTaskIds`.
func _test_star_one_needs_no_listening_task():
	var failures: Array = []

	for row: Array in SLICE:
		var level_id: String = String(row[0])
		var rules: Dictionary = _system.get_star_rules(level_id)
		var core: Array = rules.get(StarRulesScript.KEY_CORE, [])

		if core.is_empty():
			failures.append("level '%s' has no core task, so star 1 is unreachable" % level_id)
			continue

		for entry: Variant in core:
			var task: Dictionary = _library.get_task(String(entry))
			var mode: String = String(task.get("mode", ""))
			if LISTENING_MODES.has(mode):
				failures.append(
					"level '%s': core task '%s' is a '%s' task; star 1 must not require listening"
					% [level_id, String(entry), mode])

		# The core tasks alone rate exactly 1 -- not 0 (unreachable) and not more
		# (which would mean star 2 was free).
		var core_only: int = _system.rate_session(level_id, StarRulesScript.session(core))
		if core_only != 1:
			failures.append("level '%s': the core tasks alone should rate 1, got %d"
					% [level_id, core_only])

	return failures


func _test_star_rules_are_structurally_sound():
	var failures: Array = []

	for row: Array in SLICE:
		var level_id: String = String(row[0])
		var task_ids: PackedStringArray = _system.get_level_task_ids(level_id)
		var rules: Dictionary = _system.get_star_rules(level_id)

		for problem: Variant in StarRulesScript.validate(
				rules, task_ids, "level '%s' starRules" % level_id):
			failures.append(str(problem))

		if (rules.get(StarRulesScript.KEY_LISTENING, []) as Array).is_empty():
			failures.append("level '%s' has no listening task, so star 2 would be free" % level_id)
		if (rules.get(StarRulesScript.KEY_OPTIONAL, []) as Array).is_empty() \
				and (rules.get(StarRulesScript.KEY_OPTIONAL_OBJECTIVES, []) as Array).is_empty():
			failures.append("level '%s' has no optional challenge, so star 3 is unreachable" % level_id)

		# Every listening task really is a listening mode, or star 2 is not
		# measuring English recognition at all.
		for entry: Variant in (rules.get(StarRulesScript.KEY_LISTENING, []) as Array):
			var mode: String = String(_library.get_task(String(entry)).get("mode", ""))
			if not LISTENING_MODES.has(mode):
				failures.append(
					"level '%s': listening task '%s' has mode '%s', expected findIt or sayIt"
					% [level_id, String(entry), mode])

		# Rules may only name tasks the level actually runs.
		for key: String in [StarRulesScript.KEY_CORE, StarRulesScript.KEY_LISTENING,
				StarRulesScript.KEY_OPTIONAL]:
			for entry: Variant in (rules.get(key, []) as Array):
				if not task_ids.has(String(entry)):
					failures.append("level '%s': %s names '%s', which the level does not run"
							% [level_id, key, String(entry)])

		# Nothing may be left out: a task the child is asked to do that counts
		# for no star is busywork.
		var claimed: Dictionary = {}
		for key: String in [StarRulesScript.KEY_CORE, StarRulesScript.KEY_LISTENING,
				StarRulesScript.KEY_OPTIONAL]:
			for entry: Variant in (rules.get(key, []) as Array):
				claimed[String(entry)] = true
		for task_id: String in task_ids:
			if not claimed.has(task_id):
				failures.append("level '%s': task '%s' counts towards no star" % [level_id, task_id])

	return failures


# ---------------------------------------------------------------------------
# 4. Ids and vocabulary
# ---------------------------------------------------------------------------

## `ContentLibrary` DROPS a duplicate task id with only a load warning, so a
## copy-pasted task would silently shadow the original and the level would run
## the wrong record.
func _test_no_duplicate_task_ids():
	var failures: Array = []

	var seen: Dictionary = {}
	for path: String in _task_file_paths():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			failures.append("%s is not a JSON object" % path)
			continue
		var raw: Variant = (parsed as Dictionary).get("tasks", null)
		if typeof(raw) != TYPE_ARRAY:
			failures.append("%s has no 'tasks' array" % path)
			continue
		for entry: Variant in (raw as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var task_id: String = String((entry as Dictionary).get("taskId", ""))
			if task_id.is_empty():
				failures.append("%s contains a task with no taskId" % path)
				continue
			if seen.has(task_id):
				failures.append("duplicate taskId '%s' in %s (already in %s)"
						% [task_id, path, String(seen[task_id])])
				continue
			seen[task_id] = path

	# And no level may list the same task twice.
	for row: Array in SLICE:
		var mission: Dictionary = _library.get_mission(String(row[1]))
		var listed: Dictionary = {}
		for entry: Variant in (mission.get("taskIds", []) as Array):
			var task_id: String = String(entry)
			if listed.has(task_id):
				failures.append("level '%s' lists task '%s' twice" % [String(row[0]), task_id])
			listed[task_id] = true

	return failures


## Vocabulary roadmap gate G2: a word is only "taught" if a task needs it. Read
## backwards -- which is the direction a typo actually travels -- every target
## word a slice task teaches must exist in `vocabulary.json`, or the word has no
## Thai hint, no example sentence and nothing for the progress screen to show.
func _test_vocabulary_behind_every_target_word():
	var failures: Array = []

	var words: Dictionary = {}
	for word: Variant in _library.get_words():
		words[String((word as Dictionary).get("word", "")).to_lower().strip_edges()] = true

	for task: Variant in _slice_tasks():
		var task_dict: Dictionary = task
		var task_id: String = String(task_dict.get("taskId", ""))
		var raw: Variant = task_dict.get("targetWords", null)
		if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
			failures.append("task '%s' teaches no target word" % task_id)
			continue
		for entry: Variant in (raw as Array):
			var word: String = String(entry).to_lower().strip_edges()
			if not words.has(word):
				failures.append(
					"task '%s' teaches '%s', which is not in vocabulary.json (no Thai hint, no example)"
					% [task_id, word])

	return failures


# ---------------------------------------------------------------------------
# 5. Pacing and child UX
# ---------------------------------------------------------------------------

func _test_pacing():
	var failures: Array = []
	var total: int = 0

	for row: Array in SLICE:
		var level_id: String = String(row[0])
		var mission: Dictionary = _library.get_mission(String(row[1]))
		if mission.is_empty():
			continue

		var minutes: int = int(mission.get("estimatedMinutes", 0))
		if minutes < MIN_LEVEL_MINUTES or minutes > MAX_LEVEL_MINUTES:
			failures.append("level '%s' is estimated at %d minutes, expected %d-%d"
					% [level_id, minutes, MIN_LEVEL_MINUTES, MAX_LEVEL_MINUTES])
		total += minutes

		# `ContentValidator` bounds this too; repeated here because a level that
		# grows past 8 tasks stops being 4-10 minutes long for a toddler.
		var count: int = _system.get_level_task_ids(level_id).size()
		if count < 5 or count > 8:
			failures.append("level '%s' has %d tasks, expected 5-8" % [level_id, count])

		for key: String in ["introPhrase", "outroPhrase"]:
			if String(mission.get(key, "")).strip_edges().is_empty():
				failures.append("level '%s' has an empty '%s'" % [level_id, key])

	if total < MIN_SLICE_MINUTES or total > MAX_SLICE_MINUTES:
		failures.append("the slice is estimated at %d minutes, expected %d-%d"
				% [total, MIN_SLICE_MINUTES, MAX_SLICE_MINUTES])

	return failures


## No red X, no score, no percentage, no timer -- stated as language, because in
## a game with no HUD for any of those the only way they can appear is in a
## sentence a child hears.
func _test_child_facing_language():
	var failures: Array = []

	var lines: Array = []
	for task: Variant in _slice_tasks():
		var task_dict: Dictionary = task
		for key: String in CHILD_FACING_KEYS:
			lines.append([String(task_dict.get("taskId", "")), key, String(task_dict.get(key, ""))])
	for row: Array in SLICE:
		var mission: Dictionary = _library.get_mission(String(row[1]))
		for key: String in ["introPhrase", "outroPhrase", "title"]:
			lines.append([String(row[0]), key, String(mission.get(key, ""))])

	for line: Array in lines:
		var text: String = String(line[2]).to_lower()
		for banned: String in BANNED_CHILD_FACING:
			if text.contains(banned):
				failures.append("%s.%s says '%s', which contains the banned word '%s'"
						% [String(line[0]), String(line[1]), String(line[2]), banned])

	# Thai hints are support, never a crutch: every slice task carries one, and
	# none of them is empty (`settings.thaiHints` decides whether it is shown).
	for task: Variant in _slice_tasks():
		var task_dict: Dictionary = task
		if String(task_dict.get("thaiHint", "")).strip_edges().is_empty():
			failures.append("task '%s' has no Thai hint" % String(task_dict.get("taskId", "")))

	return failures


## The phrases the brief names by hand. They are the spine of the slice's
## English, so losing one to a rewrite should be loud.
func _test_named_prompts_are_present():
	var failures: Array = []

	# Every line the slice speaks, including the Chapter 2 records it reuses --
	# "Put on the shoes." is one of those, and the child hears it either way.
	var spoken: Dictionary = {}
	for row: Array in SLICE:
		for task_id: String in _system.get_level_task_ids(String(row[0])):
			var task: Dictionary = _library.get_task(task_id)
			for key: String in CHILD_FACING_KEYS:
				spoken[String(task.get(key, "")).to_lower().strip_edges()] = true
		var mission: Dictionary = _library.get_mission(String(row[1]))
		for key: String in ["introPhrase", "outroPhrase"]:
			spoken[String(mission.get(key, "")).to_lower().strip_edges()] = true

	for required: String in [
		"good morning!",
		"let's brush our teeth.",
		"can you find the milk?",
		"good night!",
	]:
		if not spoken.has(required):
			failures.append("the slice no longer says '%s' anywhere" % required)

	# "Put on your shoes." ships as "Put on the shoes." (the Chapter 2 record,
	# reused verbatim); assert the beat rather than the exact article.
	var has_shoes_instruction: bool = false
	for line: Variant in spoken.keys():
		var text: String = String(line)
		if text.begins_with("put on the shoes") or text.begins_with("put on your shoes"):
			has_shoes_instruction = true
	if not has_shoes_instruction:
		failures.append("the slice no longer tells the child to put on their shoes")

	# "Great job!" is the celebration the brief names.
	var has_praise: bool = false
	for line: Variant in spoken.keys():
		if String(line).contains("great job"):
			has_praise = true
	if not has_praise:
		failures.append("the slice never says 'Great job!'")

	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Every task record the slice runs that was authored FOR the slice -- i.e. that
## carries a semantic target. Reused Chapter 2 records (`wearPants`,
## `sayGoodNight`, ...) are deliberately excluded from the target/action checks:
## they are frozen by `test_content_chapter2_frozen.gd` and must not grow keys.
func _slice_tasks() -> Array:
	var seen: Dictionary = {}
	var tasks: Array = []
	for row: Array in SLICE:
		for task_id: String in _system.get_level_task_ids(String(row[0])):
			if seen.has(task_id):
				continue
			seen[task_id] = true
			var task: Dictionary = _library.get_task(task_id)
			if task.is_empty():
				continue
			if String(task.get("stage", "")) != "toddler":
				continue
			tasks.append(task)
	return tasks


func _task_file_paths() -> Array:
	var paths: Array = []
	for category: Variant in _library.get_categories():
		var path: String = String((category as Dictionary).get("tasksFile", ""))
		if not path.is_empty() and FileAccess.file_exists(path):
			paths.append(path)
	return paths
