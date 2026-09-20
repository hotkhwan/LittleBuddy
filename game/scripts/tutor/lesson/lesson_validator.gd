class_name LessonValidator
extends RefCounted
## Static validation for Aliz Tutor lesson content.
##
## Same shape as `ContentValidator`: every function returns an `Array` of
## human-readable problem strings, an empty array means "no problems found",
## and nothing here throws or pushes an error, so it runs from a test case, a
## debug screen or a build step. Pure: no nodes, no 3D types, no network.
##
## Two layers:
## 1. **Structural** -- `validate_against_schema()` is a small JSON Schema
##    (draft-07 subset) evaluator driven by `res://content/tutor/lesson_schema.json`
##    itself: type, required, properties, additionalProperties, enum, const,
##    pattern, min/maxLength, minimum/maximum, min/maxItems, uniqueItems, items,
##    local `$ref`. The schema file is the single source of truth for shapes.
## 2. **Semantic** -- what a schema cannot say: step-kind rules from the
##    schema's `x-requiredByKind` / `x-forbiddenByKind`, the visual asset
##    allowlist, unique stepIds, teach-first / celebrate-last ordering, the
##    duration budget (`x-durationModel`), ASCII-printable speakable text, the
##    child-UX word ban (no "wrong", no "fail"), helper keys that derive from a
##    line the lesson actually speaks, sticker ids that exist, and the
##    subjects index resolving to real files with no dead ends.

const SCHEMA_PATH: String = "res://content/tutor/lesson_schema.json"
const ALLOWLIST_PATH: String = "res://content/tutor/assets_allowlist.json"
const SUBJECTS_PATH: String = "res://content/tutor/subjects.json"
const LESSONS_DIR: String = "res://content/tutor/lessons"
const STICKERS_PATH: String = "res://content/stickers/stickers.json"

const LocalizationScript := preload("res://scripts/localization/localization.gd")
## Preloaded by path (not by class_name) so this runs before the global class cache is warm.
const AnswerMatcherScript := preload("res://scripts/tutor/lesson/answer_matcher.gd")

const KIND_TEACH: String = "teach"
const KIND_ASK: String = "ask"
const KIND_SOUND: String = "sound"
const KIND_CELEBRATE: String = "celebrate"
const KIND_CHOOSE: String = "choose"
const MENU_SUBJECT_ID: String = "menu"

## Duration model defaults; the schema's `x-durationModel` overrides them.
const TEACH_SECONDS: int = 6
const ASK_SECONDS: int = 12
const ASK_RETRY_ALLOWANCE_SECONDS: int = 10
const SOUND_SECONDS: int = 8
const SOUND_RETRY_ALLOWANCE_SECONDS: int = 6
const CHOOSE_SECONDS: int = 15
const CELEBRATE_SECONDS: int = 10
const DURATION_TOLERANCE_RATIO: float = 0.2

## Lines a child hears. Checked for ASCII and for the word ban.
const SPOKEN_FIELDS: Array[String] = [
	"teachText", "questionText", "hint", "encouragement", "successLine", "answerLine", "defaultLine",
]

## Child UX (CLAUDE.md): no failure state, no red X. None of these may appear
## in anything Aliz says, in any step.
const BANNED_WORDS: Array[String] = [
	"wrong", "incorrect", "fail", "failed", "failure", "bad", "stupid", "dumb",
	"buy", "purchase", "subscribe", "http", "www",
]


# --- entry points ------------------------------------------------------------

## Validates everything under res://content/tutor: schema, allowlist, subjects
## index, every lesson file, and the cross-references between them.
static func validate_shipped() -> Array:
	var problems: Array = []
	var schema: Dictionary = load_schema()
	if schema.is_empty():
		problems.append("%s: missing or not a JSON object" % SCHEMA_PATH)
		return problems
	var allowlist: Array = load_allowlist()
	if allowlist.is_empty():
		problems.append("%s: missing or empty assetIds" % ALLOWLIST_PATH)
	var sticker_ids: Array = load_sticker_ids()

	var lessons: Dictionary = load_shipped_lessons()
	if lessons.is_empty():
		problems.append("%s: no lesson files found" % LESSONS_DIR)
	var subjects: Variant = load_json(SUBJECTS_PATH)
	var subjects_doc: Dictionary = subjects if typeof(subjects) == TYPE_DICTIONARY else {}
	for lesson_id: String in lessons.keys():
		var lesson: Variant = lessons[lesson_id]
		if typeof(lesson) != TYPE_DICTIONARY:
			problems.append("%s/%s.json: not a JSON object" % [LESSONS_DIR, lesson_id])
			continue
		var lesson_problems: Array = validate_lesson(lesson, schema, allowlist, sticker_ids, {"lessons": lessons, "subjects": subjects_doc})
		for problem: Variant in lesson_problems:
			problems.append("%s: %s" % [lesson_id, str(problem)])
		if String((lesson as Dictionary).get("lessonId", "")) != lesson_id:
			problems.append("%s: lessonId '%s' does not match the file name" % [lesson_id, str((lesson as Dictionary).get("lessonId", ""))])

	if subjects_doc.is_empty():
		problems.append("%s: missing or not a JSON object" % SUBJECTS_PATH)
	else:
		problems.append_array(validate_subjects(subjects_doc, lessons))
	return problems


## Validates one lesson dictionary. `allowlist` is the array of approved
## visualAssetIds; `sticker_ids` (optional) the known sticker ids; `context`
## (optional) `{lessons: {lessonId: Dictionary}, subjects: Dictionary}` lets
## choose routes be resolved.
static func validate_lesson(lesson: Dictionary, schema: Dictionary, allowlist: Array, sticker_ids: Array = [], context: Dictionary = {}) -> Array:
	var problems: Array = []
	problems.append_array(validate_against_schema(lesson, schema, schema, "$"))
	problems.append_array(_check_camel_case(lesson, "$"))
	if not problems.is_empty():
		# Semantic rules assume the shape is right; report shape first.
		return problems
	problems.append_array(_check_steps(lesson, schema, allowlist, context))
	if not is_menu_lesson(lesson):
		problems.append_array(_check_duration(lesson, schema))
	problems.append_array(_check_helper_keys(lesson))
	var completion: Dictionary = lesson.get("completion", {})
	var stars: int = int(completion.get("stars", 0))
	var sticker_id: String = String(completion.get("stickerId", ""))
	if stars > 0 and sticker_id.is_empty():
		problems.append("completion.stickerId is required when stars > 0")
	if stars == 0 and not is_menu_lesson(lesson):
		problems.append("completion.stars must be at least 1 for a teaching lesson")
	if not sticker_ids.is_empty() and not sticker_id.is_empty() and not sticker_ids.has(sticker_id):
		problems.append("completion.stickerId '%s' is not in %s" % [sticker_id, STICKERS_PATH])
	return problems


## A menu lesson is a single choose step (the entry "What would you like to
## learn today?"). It has no greeting, no celebrate and no duration budget.
static func is_menu_lesson(lesson: Dictionary) -> bool:
	var steps: Variant = lesson.get("steps", [])
	if typeof(steps) != TYPE_ARRAY or (steps as Array).is_empty():
		return false
	var first: Variant = (steps as Array)[0]
	return typeof(first) == TYPE_DICTIONARY and String((first as Dictionary).get("kind", "")) == KIND_CHOOSE


## Subjects index rules: five-plus subjects, each with at least one lessonId
## that resolves to a shipped lesson whose subjectId points back; every shipped
## lesson listed exactly once.
static func validate_subjects(subjects_doc: Dictionary, lessons: Dictionary) -> Array:
	var problems: Array = []
	var subjects: Variant = subjects_doc.get("subjects", null)
	if typeof(subjects) != TYPE_ARRAY or (subjects as Array).is_empty():
		problems.append("subjects.json: 'subjects' must be a non-empty array")
		return problems
	var seen_lessons: Dictionary = {}
	var seen_subjects: Dictionary = {}
	var seen_keywords: Dictionary = {}
	var entry_id: String = String(subjects_doc.get("entryLessonId", ""))
	if entry_id.is_empty():
		problems.append("subjects.json: entryLessonId is required (the choose menu)")
	elif not lessons.has(entry_id):
		problems.append("subjects.json: entryLessonId '%s' is not a shipped lesson" % entry_id)
	elif typeof(lessons[entry_id]) == TYPE_DICTIONARY and not is_menu_lesson(lessons[entry_id]):
		problems.append("subjects.json: entryLessonId '%s' must be a menu lesson (first step choose)" % entry_id)
	var default_id: String = String(subjects_doc.get("defaultLessonId", ""))
	if default_id.is_empty():
		problems.append("subjects.json: defaultLessonId is required")
	elif not lessons.has(default_id) or (typeof(lessons[default_id]) == TYPE_DICTIONARY and is_menu_lesson(lessons[default_id])):
		problems.append("subjects.json: defaultLessonId '%s' must be a shipped teaching lesson" % default_id)
	for raw: Variant in subjects:
		if typeof(raw) != TYPE_DICTIONARY:
			problems.append("subjects.json: subject entry is not an object")
			continue
		var subject: Dictionary = raw
		var subject_id: String = String(subject.get("subjectId", ""))
		if subject_id.is_empty():
			problems.append("subjects.json: subject missing subjectId")
			continue
		if seen_subjects.has(subject_id):
			problems.append("subjects.json: duplicate subjectId '%s'" % subject_id)
		seen_subjects[subject_id] = true
		if String(subject.get("title", "")).strip_edges().is_empty():
			problems.append("subjects.json: subject '%s' has no title" % subject_id)
		var keywords: Variant = subject.get("keywords", null)
		if typeof(keywords) != TYPE_ARRAY or (keywords as Array).is_empty():
			problems.append("subjects.json: subject '%s' has no keywords (a child could not pick it)" % subject_id)
		else:
			for keyword_raw: Variant in keywords:
				var keyword: String = AnswerMatcherScript.normalize(String(keyword_raw))
				if keyword.is_empty() or not _is_ascii_printable(String(keyword_raw)):
					problems.append("subjects.json: subject '%s' keyword '%s' must be plain English" % [subject_id, str(keyword_raw)])
				elif seen_keywords.has(keyword) and String(seen_keywords[keyword]) != subject_id:
					problems.append("subjects.json: keyword '%s' belongs to both '%s' and '%s'" % [keyword, str(seen_keywords[keyword]), subject_id])
				seen_keywords[keyword] = subject_id
		var lesson_ids: Variant = subject.get("lessonIds", null)
		if typeof(lesson_ids) != TYPE_ARRAY or (lesson_ids as Array).is_empty():
			problems.append("subjects.json: subject '%s' has no lessonIds (selector dead end)" % subject_id)
			continue
		for lesson_id_raw: Variant in lesson_ids:
			var lesson_id: String = String(lesson_id_raw)
			if seen_lessons.has(lesson_id):
				problems.append("subjects.json: lesson '%s' listed under more than one subject" % lesson_id)
			seen_lessons[lesson_id] = subject_id
			if not lessons.has(lesson_id):
				problems.append("subjects.json: subject '%s' lists missing lesson '%s'" % [subject_id, lesson_id])
				continue
			var lesson: Variant = lessons[lesson_id]
			if typeof(lesson) == TYPE_DICTIONARY and String((lesson as Dictionary).get("subjectId", "")) != subject_id:
				problems.append("lesson '%s' has subjectId '%s' but is listed under '%s'"
						% [lesson_id, str((lesson as Dictionary).get("subjectId", "")), subject_id])
	for lesson_id: String in lessons.keys():
		if lesson_id == entry_id:
			continue
		if not seen_lessons.has(lesson_id):
			problems.append("lesson '%s' is shipped but no subject lists it" % lesson_id)
	return problems


## Estimated session length in seconds: teach 6 s, ask 12 s + 10 s retry
## allowance, celebrate 10 s (overridable from the schema's `x-durationModel`).
static func estimate_duration_seconds(lesson: Dictionary, schema: Dictionary = {}) -> int:
	var model: Dictionary = _duration_model(schema)
	var total: int = 0
	var steps: Variant = lesson.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return 0
	for raw: Variant in steps:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		match String((raw as Dictionary).get("kind", "")):
			KIND_TEACH:
				total += int(model["teachSeconds"])
			KIND_ASK:
				total += int(model["askSeconds"]) + int(model["askRetryAllowanceSeconds"])
			KIND_SOUND:
				total += int(model["soundSeconds"]) + int(model["soundRetryAllowanceSeconds"])
			KIND_CHOOSE:
				total += int(model["chooseSeconds"]) + int(model["askRetryAllowanceSeconds"])
			KIND_CELEBRATE:
				total += int(model["celebrateSeconds"])
	return total


# --- loaders -------------------------------------------------------------------

static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return null
	return JSON.parse_string(text)


static func load_schema() -> Dictionary:
	var data: Variant = load_json(SCHEMA_PATH)
	return data if typeof(data) == TYPE_DICTIONARY else {}


static func load_allowlist() -> Array:
	var data: Variant = load_json(ALLOWLIST_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var ids: Variant = (data as Dictionary).get("assetIds", [])
	return ids if typeof(ids) == TYPE_ARRAY else []


static func load_sticker_ids() -> Array:
	var data: Variant = load_json(STICKERS_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var ids: Array = []
	for sticker: Variant in (data as Dictionary).get("stickers", []):
		if typeof(sticker) == TYPE_DICTIONARY:
			ids.append(String((sticker as Dictionary).get("stickerId", "")))
	return ids


## `{lessonId (from file name): parsed JSON or null}` for every lesson file.
static func load_shipped_lessons() -> Dictionary:
	var lessons: Dictionary = {}
	for lesson_id: String in shipped_lesson_ids():
		lessons[lesson_id] = load_json("%s/%s.json" % [LESSONS_DIR, lesson_id])
	return lessons


static func shipped_lesson_ids() -> Array:
	var ids: Array = []
	var dir: DirAccess = DirAccess.open(LESSONS_DIR)
	if dir == null:
		return ids
	for file_name: String in dir.get_files():
		if file_name.ends_with(".json"):
			ids.append(file_name.trim_suffix(".json"))
	ids.sort()
	return ids


# --- JSON Schema subset ---------------------------------------------------------

## Evaluates `value` against `schema` (draft-07 subset). `root` resolves local
## `$ref`s; `path` prefixes each problem.
static func validate_against_schema(value: Variant, schema: Dictionary, root: Dictionary, path: String) -> Array:
	var problems: Array = []
	if schema.has("$ref"):
		var resolved: Dictionary = _resolve_ref(String(schema["$ref"]), root)
		if resolved.is_empty():
			problems.append("%s: unresolvable $ref %s" % [path, str(schema["$ref"])])
			return problems
		return validate_against_schema(value, resolved, root, path)

	if schema.has("type"):
		var expected_type: String = String(schema["type"])
		if not _type_matches(value, expected_type):
			problems.append("%s: expected %s, got %s" % [path, expected_type, type_string(typeof(value))])
			return problems

	if schema.has("const") and not _json_equal(value, schema["const"]):
		problems.append("%s: must be %s" % [path, JSON.stringify(schema["const"])])
	if schema.has("enum"):
		var allowed: Array = schema["enum"]
		var found: bool = false
		for option: Variant in allowed:
			if _json_equal(value, option):
				found = true
				break
		if not found:
			problems.append("%s: '%s' is not one of %s" % [path, str(value), JSON.stringify(allowed)])

	match typeof(value):
		TYPE_STRING:
			var text: String = value
			if schema.has("minLength") and text.length() < int(schema["minLength"]):
				problems.append("%s: shorter than %d" % [path, int(schema["minLength"])])
			if schema.has("maxLength") and text.length() > int(schema["maxLength"]):
				problems.append("%s: longer than %d chars (%d)" % [path, int(schema["maxLength"]), text.length()])
			if schema.has("pattern"):
				var regex: RegEx = RegEx.new()
				if regex.compile(String(schema["pattern"])) == OK and regex.search(text) == null:
					problems.append("%s: '%s' does not match %s" % [path, text, str(schema["pattern"])])
		TYPE_INT, TYPE_FLOAT:
			var number: float = float(value)
			if schema.has("minimum") and number < float(schema["minimum"]):
				problems.append("%s: %s is below minimum %s" % [path, str(value), str(schema["minimum"])])
			if schema.has("maximum") and number > float(schema["maximum"]):
				problems.append("%s: %s is above maximum %s" % [path, str(value), str(schema["maximum"])])
		TYPE_ARRAY:
			var items: Array = value
			if schema.has("minItems") and items.size() < int(schema["minItems"]):
				problems.append("%s: needs at least %d items" % [path, int(schema["minItems"])])
			if schema.has("maxItems") and items.size() > int(schema["maxItems"]):
				problems.append("%s: more than %d items" % [path, int(schema["maxItems"])])
			if bool(schema.get("uniqueItems", false)):
				var seen: Array = []
				for item: Variant in items:
					var key: String = JSON.stringify(item)
					if seen.has(key):
						problems.append("%s: duplicate item %s" % [path, key])
					seen.append(key)
			if schema.has("items") and typeof(schema["items"]) == TYPE_DICTIONARY:
				for i: int in range(items.size()):
					problems.append_array(validate_against_schema(items[i], schema["items"], root, "%s[%d]" % [path, i]))
		TYPE_DICTIONARY:
			var object: Dictionary = value
			var properties: Dictionary = schema.get("properties", {})
			for required_key: Variant in schema.get("required", []):
				if not object.has(required_key):
					problems.append("%s: missing required '%s'" % [path, str(required_key)])
			for key: Variant in object.keys():
				var key_name: String = String(key)
				if properties.has(key_name):
					problems.append_array(validate_against_schema(object[key], properties[key_name], root, "%s.%s" % [path, key_name]))
				elif schema.has("additionalProperties") and schema["additionalProperties"] is bool and not bool(schema["additionalProperties"]):
					problems.append("%s: unknown key '%s'" % [path, key_name])
	return problems


static func _resolve_ref(ref: String, root: Dictionary) -> Dictionary:
	if not ref.begins_with("#/"):
		return {}
	var node: Variant = root
	for segment: String in ref.trim_prefix("#/").split("/", false):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(segment):
			return {}
		node = (node as Dictionary)[segment]
	return node if typeof(node) == TYPE_DICTIONARY else {}


static func _type_matches(value: Variant, expected: String) -> bool:
	match expected:
		"string":
			return typeof(value) == TYPE_STRING
		"integer":
			if typeof(value) == TYPE_INT:
				return true
			return typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), floor(float(value)))
		"number":
			return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
		"boolean":
			return typeof(value) == TYPE_BOOL
		"array":
			return typeof(value) == TYPE_ARRAY
		"object":
			return typeof(value) == TYPE_DICTIONARY
		"null":
			return value == null
	return true


static func _json_equal(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return is_equal_approx(float(a), float(b))
	return JSON.stringify(a) == JSON.stringify(b)


# --- semantic rules ---------------------------------------------------------------

static func _check_camel_case(value: Variant, path: String) -> Array:
	var problems: Array = []
	match typeof(value):
		TYPE_DICTIONARY:
			for key: Variant in (value as Dictionary).keys():
				var key_name: String = String(key)
				if key_name.contains("_") or key_name.contains("-") or key_name.contains(" ") \
						or (not key_name.is_empty() and key_name[0] != key_name[0].to_lower()):
					problems.append("%s: key '%s' is not camelCase" % [path, key_name])
				problems.append_array(_check_camel_case((value as Dictionary)[key], "%s.%s" % [path, key_name]))
		TYPE_ARRAY:
			for i: int in range((value as Array).size()):
				problems.append_array(_check_camel_case((value as Array)[i], "%s[%d]" % [path, i]))
	return problems


static func _check_steps(lesson: Dictionary, schema: Dictionary, allowlist: Array, context: Dictionary = {}) -> Array:
	var problems: Array = []
	var steps: Array = lesson.get("steps", [])
	var required_by_kind: Dictionary = schema.get("x-requiredByKind", {})
	var forbidden_by_kind: Dictionary = schema.get("x-forbiddenByKind", {})
	var seen_ids: Dictionary = {}
	var ask_total: int = 0
	var celebrate_total: int = 0
	var choose_total: int = 0
	var is_full_lesson: bool = int(lesson.get("targetDurationSeconds", 0)) >= 240
	var menu: bool = is_menu_lesson(lesson)

	for i: int in range(steps.size()):
		var step: Dictionary = steps[i]
		var label: String = "steps[%d] (%s)" % [i, String(step.get("stepId", "?"))]
		var kind: String = String(step.get("kind", ""))
		var step_id: String = String(step.get("stepId", ""))
		if seen_ids.has(step_id):
			problems.append("%s: duplicate stepId" % label)
		seen_ids[step_id] = true

		for key: Variant in required_by_kind.get(kind, []):
			if not step.has(key) or (typeof(step[key]) == TYPE_STRING and String(step[key]).strip_edges().is_empty()):
				problems.append("%s: %s step needs '%s'" % [label, kind, str(key)])
		for key: Variant in forbidden_by_kind.get(kind, []):
			if step.has(key):
				problems.append("%s: %s step must not carry '%s'" % [label, kind, str(key)])

		if step.has("visualAssetId") and not allowlist.has(step["visualAssetId"]):
			problems.append("%s: visualAssetId '%s' is not in the allowlist" % [label, str(step["visualAssetId"])])

		match kind:
			KIND_ASK, KIND_SOUND:
				ask_total += 1
				if is_full_lesson and not step.has("visualAssetId"):
					problems.append("%s: ask steps in a full lesson need a visualAssetId" % label)
				problems.append_array(_check_expected_answers(step, label))
				if step.has("reaction"):
					var sound_back: String = String((step["reaction"] as Dictionary).get("alizSound", ""))
					if not _is_ascii_printable(sound_back):
						problems.append("%s: reaction.alizSound must be ASCII" % label)
					if kind == KIND_SOUND and not String(step.get("successLine", "")).to_lower().contains(AnswerMatcherScript.normalize(sound_back).split(" ", false)[0]):
						problems.append("%s: a sound step's successLine should echo the sound ('%s')" % [label, sound_back])
			KIND_CELEBRATE:
				celebrate_total += 1
			KIND_CHOOSE:
				choose_total += 1
				problems.append_array(_check_choose_step(step, label, context))

		for field: String in SPOKEN_FIELDS:
			if not step.has(field):
				continue
			var text: String = String(step[field])
			if not _is_ascii_printable(text):
				problems.append("%s: %s must be ASCII-printable English (TutorTurn speech rule)" % [label, field])
			var banned: String = _first_banned_word(text)
			if not banned.is_empty():
				problems.append("%s: %s contains banned word '%s' (child UX: no fail state, no purchase pressure)" % [label, field, banned])

	if steps.is_empty():
		return problems
	if menu:
		if steps.size() != 1:
			problems.append("a menu lesson is exactly one choose step, found %d steps" % steps.size())
		if String(lesson.get("subjectId", "")) != MENU_SUBJECT_ID:
			problems.append("a menu lesson's subjectId must be '%s'" % MENU_SUBJECT_ID)
		return problems
	if choose_total > 0:
		problems.append("a choose step may only open a menu lesson (steps[0])")
	if String((steps[0] as Dictionary).get("kind", "")) != KIND_TEACH:
		problems.append("steps[0] must be a teach step (the greeting)")
	if String((steps[steps.size() - 1] as Dictionary).get("kind", "")) != KIND_CELEBRATE:
		problems.append("the last step must be the celebrate step")
	if celebrate_total != 1:
		problems.append("exactly one celebrate step expected, found %d" % celebrate_total)
	if ask_total < 1:
		problems.append("a lesson needs at least one ask or sound step")
	if String(lesson.get("subjectId", "")) == MENU_SUBJECT_ID:
		problems.append("subjectId '%s' is reserved for the menu lesson" % MENU_SUBJECT_ID)
	var celebration_line: String = String((lesson.get("completion", {}) as Dictionary).get("celebrationLine", ""))
	if not celebration_line.is_empty():
		if not _is_ascii_printable(celebration_line):
			problems.append("completion.celebrationLine must be ASCII-printable")
		var banned_completion: String = _first_banned_word(celebration_line)
		if not banned_completion.is_empty():
			problems.append("completion.celebrationLine contains banned word '%s'" % banned_completion)
	return problems


## choose step: every route resolves (a lessonId that ships, or a subjectId
## that exists and has lessons), carries some answer words, and no answer
## routes two ways; defaultLessonId resolves too.
static func _check_choose_step(step: Dictionary, label: String, context: Dictionary) -> Array:
	var problems: Array = []
	var lessons: Dictionary = context.get("lessons", {})
	var subjects_doc: Dictionary = context.get("subjects", {})
	var subjects_by_id: Dictionary = {}
	for subject: Variant in subjects_doc.get("subjects", []):
		if typeof(subject) == TYPE_DICTIONARY:
			subjects_by_id[String((subject as Dictionary).get("subjectId", ""))] = subject
	var seen_answers: Dictionary = {}
	var choices: Array = step.get("choices", [])
	for i: int in range(choices.size()):
		var choice: Dictionary = choices[i]
		var choice_label: String = "%s choices[%d]" % [label, i]
		var lesson_id: String = String(choice.get("lessonId", ""))
		var subject_id: String = String(choice.get("subjectId", ""))
		if lesson_id.is_empty() and subject_id.is_empty():
			problems.append("%s: needs lessonId or subjectId" % choice_label)
			continue
		var answers: Array = []
		if not subject_id.is_empty():
			if subjects_by_id.is_empty():
				pass  # no context: cannot resolve, schema already checked the shape
			elif not subjects_by_id.has(subject_id):
				problems.append("%s: unknown subjectId '%s'" % [choice_label, subject_id])
			else:
				var subject: Dictionary = subjects_by_id[subject_id]
				answers.append_array(subject.get("keywords", []))
				if lesson_id.is_empty():
					var ids: Array = subject.get("lessonIds", [])
					if ids.is_empty():
						problems.append("%s: subject '%s' has no lessons to route to" % [choice_label, subject_id])
					else:
						lesson_id = String(ids[0])
		answers.append_array(choice.get("answers", []))
		if answers.is_empty() and not subjects_by_id.is_empty():
			problems.append("%s: no answers route to it" % choice_label)
		for answer: Variant in answers:
			var normalized: String = AnswerMatcherScript.normalize(String(answer))
			if seen_answers.has(normalized) and int(seen_answers[normalized]) != i:
				problems.append("%s: answer '%s' also routes choices[%d]" % [choice_label, str(answer), int(seen_answers[normalized])])
			seen_answers[normalized] = i
		if not lesson_id.is_empty() and not lessons.is_empty() and not lessons.has(lesson_id):
			problems.append("%s: routes to missing lesson '%s'" % [choice_label, lesson_id])
		if not lesson_id.is_empty() and lessons.has(lesson_id) and typeof(lessons[lesson_id]) == TYPE_DICTIONARY and is_menu_lesson(lessons[lesson_id]):
			problems.append("%s: routes to another menu" % choice_label)
	var default_id: String = String(step.get("defaultLessonId", ""))
	if not lessons.is_empty() and not lessons.has(default_id):
		problems.append("%s: defaultLessonId '%s' is not a shipped lesson" % [label, default_id])
	for answer: Variant in step.get("defaultAnswers", []):
		var normalized: String = AnswerMatcherScript.normalize(String(answer))
		if seen_answers.has(normalized):
			problems.append("%s: defaultAnswer '%s' also routes choices[%d]" % [label, str(answer), int(seen_answers[normalized])])
	return problems


static func _check_expected_answers(step: Dictionary, label: String) -> Array:
	var problems: Array = []
	var answers: Array = step.get("expectedAnswers", [])
	if answers.is_empty():
		return problems
	var seen: Dictionary = {}
	for raw: Variant in answers:
		var normalized: String = AnswerMatcherScript.normalize(String(raw))
		if normalized.is_empty():
			problems.append("%s: expectedAnswer '%s' is empty after normalisation" % [label, str(raw)])
			continue
		if seen.has(normalized):
			problems.append("%s: expectedAnswers '%s' and '%s' collapse to the same answer" % [label, str(seen[normalized]), str(raw)])
		seen[normalized] = raw
		if not _is_ascii_printable(String(raw)):
			problems.append("%s: expectedAnswer '%s' must be English (ASCII); no transliterations" % [label, str(raw)])
	var canonical: String = AnswerMatcherScript.strip_filler(AnswerMatcherScript.normalize(String(answers[0])))
	if canonical.split(" ", false).size() > 2:
		problems.append("%s: canonical answer '%s' should be one or two words (it is spoken back as the answer)" % [label, str(answers[0])])
	return problems


static func _check_duration(lesson: Dictionary, schema: Dictionary) -> Array:
	var problems: Array = []
	var target: int = int(lesson.get("targetDurationSeconds", 0))
	if target <= 0:
		return problems
	var estimate: int = estimate_duration_seconds(lesson, schema)
	var tolerance: float = float(_duration_model(schema)["toleranceRatio"])
	var low: int = int(floor(float(target) * (1.0 - tolerance)))
	var high: int = int(ceil(float(target) * (1.0 + tolerance)))
	if estimate < low or estimate > high:
		problems.append("estimated duration %d s is outside %d..%d s for targetDurationSeconds %d" % [estimate, low, high, target])
	return problems


## Every helperLanguageKey must be `Localization.key_for()` of a whole line or
## a sentence of a line this lesson speaks, so the Thai/Japanese/... helper
## table can be filled from real lines and never from a stale key.
static func _check_helper_keys(lesson: Dictionary) -> Array:
	var problems: Array = []
	var keys: Array = lesson.get("helperLanguageKeys", [])
	if keys.is_empty():
		return problems
	var spoken_keys: Dictionary = {}
	for raw: Variant in lesson.get("steps", []):
		var step: Dictionary = raw
		for field: String in SPOKEN_FIELDS:
			if not step.has(field):
				continue
			var line: String = String(step[field])
			spoken_keys[LocalizationScript.key_for(line)] = true
			for sentence: String in _sentences(line):
				spoken_keys[LocalizationScript.key_for(sentence)] = true
	var celebration_line: String = String((lesson.get("completion", {}) as Dictionary).get("celebrationLine", ""))
	if not celebration_line.is_empty():
		spoken_keys[LocalizationScript.key_for(celebration_line)] = true
		for sentence: String in _sentences(celebration_line):
			spoken_keys[LocalizationScript.key_for(sentence)] = true
	for key: Variant in keys:
		if not spoken_keys.has(String(key)):
			problems.append("helperLanguageKeys '%s' does not derive from any line in this lesson" % str(key))
	return problems


static func _sentences(line: String) -> Array:
	var out: Array = []
	var current: String = ""
	for character: String in line:
		if character == "." or character == "!" or character == "?":
			if not current.strip_edges().is_empty():
				out.append(current.strip_edges())
			current = ""
		else:
			current += character
	if not current.strip_edges().is_empty():
		out.append(current.strip_edges())
	return out


static func _duration_model(schema: Dictionary) -> Dictionary:
	var model: Dictionary = {
		"teachSeconds": TEACH_SECONDS,
		"askSeconds": ASK_SECONDS,
		"askRetryAllowanceSeconds": ASK_RETRY_ALLOWANCE_SECONDS,
		"soundSeconds": SOUND_SECONDS,
		"soundRetryAllowanceSeconds": SOUND_RETRY_ALLOWANCE_SECONDS,
		"chooseSeconds": CHOOSE_SECONDS,
		"celebrateSeconds": CELEBRATE_SECONDS,
		"toleranceRatio": DURATION_TOLERANCE_RATIO,
	}
	var override: Variant = schema.get("x-durationModel", null)
	if typeof(override) == TYPE_DICTIONARY:
		for key: Variant in (override as Dictionary).keys():
			if model.has(key):
				model[key] = (override as Dictionary)[key]
	return model


static func _is_ascii_printable(text: String) -> bool:
	for character: String in text:
		var code: int = character.unicode_at(0)
		if code < 32 or code > 126:
			return false
	return true


static func _first_banned_word(text: String) -> String:
	var words: PackedStringArray = AnswerMatcherScript.normalize(text).split(" ", false)
	for word: String in words:
		if BANNED_WORDS.has(word):
			return word
	return ""
