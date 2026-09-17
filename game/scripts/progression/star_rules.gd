class_name StarRules
extends RefCounted

## Pure, node-free evaluation of a level's 0-3 star rating.
##
## ## The product rule this file exists to enforce
##
##   | Star | Condition                                                        |
##   |------|------------------------------------------------------------------|
##   | 1    | core level completion -- ALWAYS achievable by touch alone         |
##   | 2    | the level's English listening/recognition tasks (findIt / sayIt)  |
##   | 3    | an optional exploration / help / cleanup / free-play challenge    |
##
## **Speech is never required for any star.** A `sayIt` task completed by touch
## still earns star 2. Nothing in this file reads a transcript, a recognition
## result, a confidence score or a microphone permission -- the only input is
## "which task ids were completed", and `ModeHandler.complete_by_touch()`
## guarantees every task id is reachable without a microphone.
## `tests/cases/test_star_rules.gd` asserts both the behaviour and the absence
## of any speech identifier in this source file, so a future edit that makes a
## star depend on speech turns the suite red.
##
## Stars are never subtracted: `merge()` is max-wins, and `evaluate()` is a pure
## function of the session, so replaying badly cannot lower a stored rating.
##
## Everything here is `static` and takes plain dictionaries. No nodes, no
## autoloads, no `SceneTree` -- so it is trivially testable.

const MAX_STARS: int = 3
const MIN_STARS: int = 0

## Modes that count towards star 2. Both are completable by touch.
const LISTENING_MODES: Array[String] = ["findIt", "sayIt"]

## Canonical rule keys. Authored in `missions.json` under `starRules`.
const KEY_CORE: String = "coreTaskIds"
const KEY_LISTENING: String = "listeningTaskIds"
const KEY_OPTIONAL: String = "optionalTaskIds"
const KEY_OPTIONAL_OBJECTIVES: String = "optionalObjectiveIds"

## Canonical session keys.
const KEY_COMPLETED: String = "completedTaskIds"


# ---------------------------------------------------------------------------
# Shaping
# ---------------------------------------------------------------------------

## Coerces an authored (or missing, or malformed) `starRules` value into the
## canonical four-list shape. Never raises; unknown keys are dropped.
static func normalize(rules: Variant) -> Dictionary:
	var source: Dictionary = {}
	if typeof(rules) == TYPE_DICTIONARY:
		source = rules
	return {
		KEY_CORE: _string_list(source.get(KEY_CORE, [])),
		KEY_LISTENING: _string_list(source.get(KEY_LISTENING, [])),
		KEY_OPTIONAL: _string_list(source.get(KEY_OPTIONAL, [])),
		KEY_OPTIONAL_OBJECTIVES: _string_list(source.get(KEY_OPTIONAL_OBJECTIVES, [])),
	}


## Coerces a session record into the canonical shape.
##
## A session describes *what happened in one play of one level* and nothing
## else. Any extra keys a caller passes are ignored outright, which is why a
## caller cannot accidentally make a star depend on speech.
static func normalize_session(session: Variant) -> Dictionary:
	var source: Dictionary = {}
	if typeof(session) == TYPE_DICTIONARY:
		source = session
	return {
		KEY_COMPLETED: _string_list(source.get(KEY_COMPLETED, [])),
		KEY_OPTIONAL_OBJECTIVES: _string_list(source.get(KEY_OPTIONAL_OBJECTIVES, [])),
	}


## Convenience builder for callers (and tests) that just have two id lists.
static func session(completed_task_ids: Variant, optional_objective_ids: Variant = []) -> Dictionary:
	return {
		KEY_COMPLETED: _string_list(completed_task_ids),
		KEY_OPTIONAL_OBJECTIVES: _string_list(optional_objective_ids),
	}


## Default rules for a level that authored none, derived from its resolved task
## dictionaries:
##
##   - listening = every task whose `mode` is `findIt` or `sayIt`
##   - core      = everything else (or, when a level is all-listening, all tasks,
##                 so star 1 can never be awarded for doing nothing)
##   - optional  = none, because an optional challenge cannot be guessed
##
## This is what keeps the seven pre-existing missions working unchanged.
static func derive_from_tasks(tasks: Variant) -> Dictionary:
	var core: Array = []
	var listening: Array = []
	var all: Array = []
	if typeof(tasks) == TYPE_ARRAY:
		for entry: Variant in (tasks as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var task: Dictionary = entry
			var task_id: String = String(task.get("taskId", ""))
			if task_id.is_empty() or all.has(task_id):
				continue
			all.append(task_id)
			if LISTENING_MODES.has(String(task.get("mode", ""))):
				listening.append(task_id)
			else:
				core.append(task_id)
	if core.is_empty():
		core = all.duplicate()
	return {
		KEY_CORE: core,
		KEY_LISTENING: listening,
		KEY_OPTIONAL: [],
		KEY_OPTIONAL_OBJECTIVES: [],
	}


## Same fallback for a level we only know by task id (no modes available):
## every task is core, nothing is listening, nothing is optional.
static func derive_from_task_ids(task_ids: Variant) -> Dictionary:
	return {
		KEY_CORE: _string_list(task_ids),
		KEY_LISTENING: [],
		KEY_OPTIONAL: [],
		KEY_OPTIONAL_OBJECTIVES: [],
	}


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

## The whole point of this file: rules + session -> 0..3.
static func evaluate(rules: Variant, session_data: Variant) -> int:
	return int(describe(rules, session_data).get("stars", 0))


## `evaluate()` with its reasoning exposed, for the level-summary UI and for
## tests. Keys: `stars`, `star1`, `star2`, `star3`, `missingCore`,
## `missingListening`.
static func describe(rules: Variant, session_data: Variant) -> Dictionary:
	var shaped: Dictionary = normalize(rules)
	var play: Dictionary = normalize_session(session_data)

	var done: Dictionary = {}
	for task_id: Variant in (play[KEY_COMPLETED] as Array):
		done[String(task_id)] = true

	var objectives: Dictionary = {}
	for objective_id: Variant in (play[KEY_OPTIONAL_OBJECTIVES] as Array):
		objectives[String(objective_id)] = true

	var core: Array = shaped[KEY_CORE]
	var listening: Array = shaped[KEY_LISTENING]
	var optional: Array = shaped[KEY_OPTIONAL]
	var optional_objectives: Array = shaped[KEY_OPTIONAL_OBJECTIVES]

	var missing_core: Array = _missing(core, done)
	var missing_listening: Array = _missing(listening, done)

	# A level with no core tasks has nothing to complete, so it cannot be
	# "completed". Better to under-award than to hand out a star for nothing.
	var star1: bool = not core.is_empty() and missing_core.is_empty()
	# Ratings are cumulative, so star 2 implies star 1.
	var star2: bool = star1 and missing_listening.is_empty()
	# Star 3 is generous on purpose: ANY optional challenge is enough.
	var star3: bool = star2 and (_any(optional, done) or _any(optional_objectives, objectives))

	var stars: int = 0
	if star1:
		stars = 1
	if star2:
		stars = 2
	if star3:
		stars = 3

	return {
		"stars": stars,
		"star1": star1,
		"star2": star2,
		"star3": star3,
		"missingCore": missing_core,
		"missingListening": missing_listening,
	}


## Max-wins. Replaying a level worse must never reduce the stored rating, and a
## repeated award must never stack.
static func merge(previous_stars: int, awarded_stars: int) -> int:
	return maxi(clamp_stars(previous_stars), clamp_stars(awarded_stars))


static func clamp_stars(value: Variant) -> int:
	var number: int = 0
	match typeof(value):
		TYPE_INT:
			number = value
		TYPE_FLOAT:
			number = int(round(float(value)))
		TYPE_STRING, TYPE_STRING_NAME:
			number = String(value).to_int()
		_:
			number = 0
	return clampi(number, MIN_STARS, MAX_STARS)


## 3/3 grants a bonus sticker; 2/3 already passes the level.
static func grants_bonus_sticker(stars: int) -> bool:
	return clamp_stars(stars) >= MAX_STARS


static func is_passing(stars: int) -> bool:
	return clamp_stars(stars) >= 2


static func is_complete(stars: int) -> bool:
	return clamp_stars(stars) >= 1


## Structural checks on an authored rule set. Returns human-readable problems;
## empty means fine. `known_task_ids` is optional.
static func validate(rules: Variant, known_task_ids: Variant = null, label: String = "starRules") -> Array:
	var problems: Array = []
	if typeof(rules) != TYPE_DICTIONARY:
		problems.append("%s: must be an object" % label)
		return problems

	var shaped: Dictionary = normalize(rules)
	for key: Variant in (rules as Dictionary).keys():
		var key_text: String = String(key)
		if not [KEY_CORE, KEY_LISTENING, KEY_OPTIONAL, KEY_OPTIONAL_OBJECTIVES].has(key_text):
			problems.append("%s: unknown key '%s'" % [label, key_text])

	if (shaped[KEY_CORE] as Array).is_empty():
		problems.append("%s: '%s' must list at least one task" % [label, KEY_CORE])

	var seen: Dictionary = {}
	for key: String in [KEY_CORE, KEY_LISTENING, KEY_OPTIONAL]:
		for entry: Variant in (shaped[key] as Array):
			var task_id: String = String(entry)
			if seen.has(task_id):
				problems.append(
					"%s: task '%s' appears in both '%s' and '%s'"
					% [label, task_id, String(seen[task_id]), key]
				)
			seen[task_id] = key

	if typeof(known_task_ids) == TYPE_ARRAY or typeof(known_task_ids) == TYPE_PACKED_STRING_ARRAY:
		var known: Array = _string_list(known_task_ids)
		for key: String in [KEY_CORE, KEY_LISTENING, KEY_OPTIONAL]:
			for entry: Variant in (shaped[key] as Array):
				if not known.has(String(entry)):
					problems.append("%s: '%s' lists unknown task '%s'" % [label, key, String(entry)])

	return problems


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _missing(required: Array, done: Dictionary) -> Array:
	var missing: Array = []
	for entry: Variant in required:
		var task_id: String = String(entry)
		if not done.has(task_id):
			missing.append(task_id)
	return missing


static func _any(candidates: Array, done: Dictionary) -> bool:
	for entry: Variant in candidates:
		if done.has(String(entry)):
			return true
	return false


static func _string_list(source: Variant) -> Array:
	var result: Array = []
	var type: int = typeof(source)
	if type != TYPE_ARRAY and type != TYPE_PACKED_STRING_ARRAY:
		return result
	for entry: Variant in source:
		var text: String = String(entry).strip_edges()
		if text.is_empty() or result.has(text):
			continue
		result.append(text)
	return result
