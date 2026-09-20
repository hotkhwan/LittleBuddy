extends RefCounted

## The TutorTurn validator -- the client half of the shared schema in
## `docs/ALIZ_TUTOR_CONTRACTS.md`.
##
## Every turn Aliz speaks passes through `coerce()` first, whether it came from
## the local scripted provider or (later, flag-gated) from the backend. A turn
## that breaks any rule is REPLACED by `fallback_turn()` -- "Let's try
## together!" -- rather than repaired, because a half-repaired turn from a
## model is exactly the kind of thing a child should never hear. The rules are
## the contract's, verbatim, and `content/tutor/turn_fixtures.json` is the
## truth table both this file and the server's `turn_validator.js` are tested
## against, so the two can never drift apart silently.
##
## Pure GDScript: no nodes, no 3D types, no I/O except the optional allowlist
## read. Written by Agent B as the first version; Agent E owns it after merge.

const FIXTURES_PATH: String = "res://content/tutor/turn_fixtures.json"
const ALLOWLIST_PATH: String = "res://content/tutor/assets_allowlist.json"

const EMOTIONS: Array[String] = ["neutral", "listening", "thinking", "happy", "encouraging", "smile"]
const GESTURES: Array[String] = ["none", "nod", "tilt", "point", "clap", "wave"]
const VISUAL_TYPES: Array[String] = ["none", "flashcard", "model"]
const LESSON_ACTIONS: Array[String] = ["next_question", "retry", "give_hint", "complete", "end_session"]

## The approved visual ids. `content/tutor/assets_allowlist.json` overrides
## this list when it is present; the constant is the contract's own list so the
## validator works in a build that ships without the file.
const DEFAULT_ASSET_IDS: Array[String] = [
	"apple_red", "banana_yellow", "cat", "dog", "number_1", "number_2", "number_3",
	"color_blue", "color_green", "color_red", "color_yellow", "orange_orange", "grapes_purple",
]

const MAX_SPEECH: int = 160
const MAX_SUBTITLE: int = 160
const MAX_NEXT_QUESTION: int = 120
const MAX_DIGIT_RUN: int = 20

## Typographic punctuation a sentence may reasonably carry beyond ASCII. Anything
## else outside 0x20..0x7E is rejected -- no emoji, no control characters.
const EXTRA_PUNCTUATION: String = "’‘“”…—–"

## The age filter's word list. Short on purpose: it catches the words that must
## never reach a four-year-old from a generated turn, plus the commercial ones
## (`CLAUDE.md`: no purchase prompts, no external links). Matched on whole
## words, case-insensitively.
const BANNED_WORDS: Array[String] = [
	"kill", "die", "dead", "death", "blood", "gun", "knife", "hate", "stupid", "idiot",
	"dumb", "ugly", "loser", "shut up", "damn", "hell", "wrong", "fail", "failed", "failure",
	"buy", "purchase", "subscribe", "download", "password", "address",
]
const URL_MARKERS: Array[String] = ["http://", "https://", "www.", ".com", ".net", ".org"]

static var _asset_cache: Array = []


## The safe turn, exactly as the contract writes it.
static func fallback_turn() -> Dictionary:
	return {
		"speech": "Let's try together!",
		"subtitle": "Let's try together!",
		"emotion": "encouraging",
		"gesture": "tilt",
		"visual": {"type": "none"},
		"lessonAction": "retry",
	}


## The ids a `visual.assetId` may take.
static func allowed_asset_ids() -> Array:
	if not _asset_cache.is_empty():
		return _asset_cache
	var ids: Array = []
	if FileAccess.file_exists(ALLOWLIST_PATH):
		var text: String = FileAccess.get_file_as_string(ALLOWLIST_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			var raw: Variant = (parsed as Dictionary).get("assetIds", (parsed as Dictionary).get("assets", []))
			if typeof(raw) == TYPE_ARRAY:
				for entry in raw:
					if typeof(entry) == TYPE_STRING:
						ids.append(String(entry))
					elif typeof(entry) == TYPE_DICTIONARY and (entry as Dictionary).has("id"):
						ids.append(String((entry as Dictionary)["id"]))
		elif typeof(parsed) == TYPE_ARRAY:
			for entry in parsed:
				if typeof(entry) == TYPE_STRING:
					ids.append(String(entry))
	if ids.is_empty():
		ids = DEFAULT_ASSET_IDS.duplicate()
	_asset_cache = ids
	return ids


## Full report: `{valid: bool, errors: Array[String], turn: Dictionary}`. `turn`
## is the normalised copy when valid (subtitle defaulted to the speech, visual
## defaulted to none, strings trimmed) and the fallback when not.
static func validate(candidate: Variant) -> Dictionary:
	var errors: Array = []
	if typeof(candidate) != TYPE_DICTIONARY:
		return {"valid": false, "errors": ["turn is not a dictionary"], "turn": fallback_turn()}
	var raw: Dictionary = candidate
	var turn: Dictionary = {}

	var speech: String = _text_field(raw, "speech", MAX_SPEECH, true, errors)
	turn["speech"] = speech
	var subtitle: String = _text_field(raw, "subtitle", MAX_SUBTITLE, false, errors)
	turn["subtitle"] = subtitle if not subtitle.is_empty() else speech

	var emotion: String = _enum_field(raw, "emotion", EMOTIONS, errors)
	turn["emotion"] = emotion
	var gesture: String = _enum_field(raw, "gesture", GESTURES, errors)
	turn["gesture"] = gesture
	var action: String = _enum_field(raw, "lessonAction", LESSON_ACTIONS, errors)
	turn["lessonAction"] = action

	var visual: Variant = raw.get("visual", {"type": "none"})
	if typeof(visual) != TYPE_DICTIONARY:
		errors.append("visual is not a dictionary")
		turn["visual"] = {"type": "none"}
	else:
		var v: Dictionary = visual
		var vtype: String = String(v.get("type", "")).strip_edges()
		if not VISUAL_TYPES.has(vtype):
			errors.append("visual.type '%s' is not one of %s" % [vtype, str(VISUAL_TYPES)])
			vtype = "none"
		var cleaned: Dictionary = {"type": vtype}
		if vtype != "none":
			var asset_id: String = String(v.get("assetId", "")).strip_edges()
			if asset_id.is_empty():
				errors.append("visual.assetId is required for a %s" % vtype)
			elif not allowed_asset_ids().has(asset_id):
				errors.append("visual.assetId '%s' is not on the allowlist" % asset_id)
			cleaned["assetId"] = asset_id
		elif v.has("assetId") and not String(v.get("assetId", "")).is_empty():
			errors.append("visual of type none must not carry an assetId")
		turn["visual"] = cleaned

	if raw.has("nextQuestion") and raw["nextQuestion"] != null:
		var next_question: String = _text_field(raw, "nextQuestion", MAX_NEXT_QUESTION, false, errors)
		if not next_question.is_empty():
			turn["nextQuestion"] = next_question

	for key in raw.keys():
		if not ["speech", "subtitle", "emotion", "gesture", "visual", "lessonAction", "nextQuestion"].has(String(key)):
			errors.append("unknown key '%s'" % String(key))

	if errors.is_empty():
		return {"valid": true, "errors": [], "turn": turn}
	return {"valid": false, "errors": errors, "turn": fallback_turn()}


## The turn to act on: the normalised turn, or the fallback.
static func coerce(candidate: Variant) -> Dictionary:
	return validate(candidate)["turn"]


static func is_valid(candidate: Variant) -> bool:
	return bool(validate(candidate)["valid"])


## Builds a turn that is valid by construction, for the scripted provider.
static func make(speech: String, emotion: String, gesture: String, lesson_action: String,
		asset_id: String = "", next_question: String = "", subtitle: String = "") -> Dictionary:
	var turn: Dictionary = {
		"speech": speech.strip_edges().left(MAX_SPEECH),
		"subtitle": (subtitle if not subtitle.is_empty() else speech).strip_edges().left(MAX_SUBTITLE),
		"emotion": emotion if EMOTIONS.has(emotion) else "neutral",
		"gesture": gesture if GESTURES.has(gesture) else "none",
		"visual": {"type": "none"},
		"lessonAction": lesson_action if LESSON_ACTIONS.has(lesson_action) else "retry",
	}
	if not asset_id.is_empty() and allowed_asset_ids().has(asset_id):
		turn["visual"] = {"type": "flashcard", "assetId": asset_id}
	if not next_question.is_empty():
		turn["nextQuestion"] = next_question.strip_edges().left(MAX_NEXT_QUESTION)
	return turn


## Loads the shared fixture file: `[{id, valid, turn, reason}]`.
static func load_fixtures() -> Array:
	if not FileAccess.file_exists(FIXTURES_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var cases: Variant = (parsed as Dictionary).get("cases", [])
	return cases if typeof(cases) == TYPE_ARRAY else []


# ---------------------------------------------------------------------------
# Field checks
# ---------------------------------------------------------------------------

static func _text_field(raw: Dictionary, key: String, limit: int, required: bool, errors: Array) -> String:
	if not raw.has(key) or raw[key] == null:
		if required:
			errors.append("%s is required" % key)
		return ""
	if typeof(raw[key]) != TYPE_STRING:
		errors.append("%s is not a string" % key)
		return ""
	var text: String = String(raw[key]).strip_edges()
	if required and text.is_empty():
		errors.append("%s is empty" % key)
	if text.length() > limit:
		errors.append("%s is %d characters; the limit is %d" % [key, text.length(), limit])
	var bad: String = _first_disallowed_char(text)
	if not bad.is_empty():
		errors.append("%s contains a disallowed character U+%04X" % [key, bad.unicode_at(0)])
	if _has_url(text):
		errors.append("%s contains a link" % key)
	if _has_long_digit_run(text):
		errors.append("%s contains a number longer than %d digits" % [key, MAX_DIGIT_RUN])
	var banned: String = _banned_word_in(text)
	if not banned.is_empty():
		errors.append("%s contains the word '%s'" % [key, banned])
	return text


static func _enum_field(raw: Dictionary, key: String, allowed: Array, errors: Array) -> String:
	if not raw.has(key) or typeof(raw[key]) != TYPE_STRING:
		errors.append("%s is required" % key)
		return String(allowed[0])
	var value: String = String(raw[key]).strip_edges()
	if not allowed.has(value):
		errors.append("%s '%s' is not one of %s" % [key, value, str(allowed)])
		return String(allowed[0])
	return value


static func _first_disallowed_char(text: String) -> String:
	for i: int in range(text.length()):
		var code: int = text.unicode_at(i)
		if code >= 0x20 and code <= 0x7E:
			continue
		if EXTRA_PUNCTUATION.find(text[i]) >= 0:
			continue
		return text[i]
	return ""


static func _has_url(text: String) -> bool:
	var lower: String = text.to_lower()
	for marker: String in URL_MARKERS:
		if lower.find(marker) >= 0:
			return true
	return false


static func _has_long_digit_run(text: String) -> bool:
	var run: int = 0
	for i: int in range(text.length()):
		var code: int = text.unicode_at(i)
		if code >= 0x30 and code <= 0x39:
			run += 1
			if run > MAX_DIGIT_RUN:
				return true
		else:
			run = 0
	return false


## Whole-word match: "hello" must not trip on "hell", but "shut up" must match.
static func _banned_word_in(text: String) -> String:
	var lower: String = " " + _letters_only(text.to_lower()) + " "
	for word: String in BANNED_WORDS:
		if lower.find(" " + word + " ") >= 0:
			return word
	return ""


static func _letters_only(text: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(text.length()):
		var code: int = text.unicode_at(i)
		var is_letter: bool = (code >= 0x61 and code <= 0x7A) or (code >= 0x30 and code <= 0x39)
		out.append(text[i] if is_letter else " ")
	return "".join(out)
