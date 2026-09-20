extends RefCounted

## The TutorTurn validator -- the CLIENT half of the shared schema in
## `docs/ALIZ_TUTOR_CONTRACTS.md`. Canonical version (Agent E; supersedes the
## first draft Agent B wrote for the classroom scene, same method names).
##
## Every turn Aliz speaks passes through `coerce()` first, whether it came from
## the local scripted provider or (flag-gated) from the backend. A turn that
## breaks any rule is REPLACED by `fallback_turn()` -- "Let's try together!" --
## never repaired: a half-repaired sentence from a model is exactly what a
## child must never hear.
##
## The rules are `backend/src/turn_validator.js`, rule for rule, with the same
## reason codes (`speech:too_long`, `visual.assetId:not_allowed`, ...), and
## `content/tutor/turn_fixtures.json` is the truth table BOTH suites run
## (`test_tutor_turn.gd` here, `validator.test.js` there), so the two cannot
## drift apart silently. Rules, in the server's words:
##
##   * `speech` required, <= 160; `subtitle` <= 160 (defaults to speech);
##     `nextQuestion` <= 120; each ASCII printable 0x20..0x7E ONLY (no
##     typographic quotes, no emoji, no tabs), no URL, no digit run over 20,
##     no banned word (whole-word, case-insensitive);
##   * `emotion`, `gesture`, `lessonAction` exact members of their enums;
##   * `visual` required: `{type}` in none|flashcard|model; `assetId` must be on
##     the allowlist whenever present, and is required unless type is none;
##   * every other key is DROPPED from the output (a tool call, a score, a
##     debug blob never reaches the scene);
##   * text fields are trimmed on the way out.
##
## Pure GDScript: no nodes, no 3D types, no I/O except the optional allowlist
## and fixture reads.

const FIXTURES_PATH: String = "res://content/tutor/turn_fixtures.json"
const ALLOWLIST_PATH: String = "res://content/tutor/assets_allowlist.json"

const EMOTIONS: Array[String] = ["neutral", "listening", "thinking", "happy", "encouraging", "smile"]
const GESTURES: Array[String] = ["none", "nod", "tilt", "point", "clap", "wave"]
const VISUAL_TYPES: Array[String] = ["none", "flashcard", "model"]
## `switch_lesson` and `jump_step` (addendum 2026-09-20 evening): the engine
## routed the child elsewhere (a choose step, a barge-in "I want a dog!").
const LESSON_ACTIONS: Array[String] = ["next_question", "retry", "give_hint", "complete", "end_session", "switch_lesson", "jump_step"]

const OUTPUT_KEYS: Array[String] = ["speech", "subtitle", "emotion", "gesture", "visual", "lessonAction", "nextQuestion",
	"nextLessonId", "nextStepId", "wantsSfx"]
## CLIENT-ONLY optional passthroughs (the server never emits them and drops
## them if sent): lesson routing targets for `switch_lesson` / `jump_step`
## and the reaction sound effect a step asks for. Each must be a short safe
## identifier or it is dropped -- never a reason to fall back.
const IDENTIFIER_KEYS: Array[String] = ["nextLessonId", "nextStepId", "wantsSfx"]
const MAX_IDENTIFIER: int = 48

## The contract's approved list; `assets_allowlist.json` overrides it when
## present so the validator still works in a build that ships without the file.
const DEFAULT_ASSET_IDS: Array[String] = [
	"apple_red", "banana_yellow", "cat", "dog", "number_1", "number_2", "number_3",
	"color_blue", "color_green", "color_red", "color_yellow", "orange_orange", "grapes_purple",
]

const MAX_SPEECH: int = 160
const MAX_SUBTITLE: int = 160
const MAX_NEXT_QUESTION: int = 120
const MAX_DIGIT_RUN: int = 20

## Identical to `BANNED_WORDS` in `backend/src/turn_validator.js`. Small and
## conservative: violence, scary/adult themes, insults, personal-data prompts.
const BANNED_WORDS: Array[String] = [
	"kill", "die", "dead", "death", "murder", "blood", "gun", "knife", "shoot", "stab", "bomb",
	"hate", "stupid", "idiot", "dumb", "ugly", "loser", "shut up",
	"damn", "hell", "crap", "sex", "sexy", "naked", "drug", "drugs", "beer", "wine", "drunk",
	"password", "credit card", "phone number", "home address", "where do you live", "last name",
]

## Same expression as the server's `URL_PATTERN`.
const URL_PATTERN: String = "(?i)(https?://|www\\.|[a-z0-9-]+\\.(com|net|org|io|app|co|me|tv|xyz|info)\\b)"

static var _asset_cache: Array = []
static var _url_regex: RegEx = null
static var _banned_regexes: Array = []


## The safe turn, exactly as the contract writes it (subtitle mirrors speech,
## as the server's `fallbackTurn()` does).
static func fallback_turn() -> Dictionary:
	return {
		"speech": "Let's try together!",
		"subtitle": "Let's try together!",
		"emotion": "encouraging",
		"gesture": "tilt",
		"visual": {"type": "none"},
		"lessonAction": "retry",
	}


## The ids a `visual.assetId` may take. Accepts the shapes the server's loader
## does: a bare array, or `{assetIds|assets|allowlist|ids: [id | {id}]}`.
static func allowed_asset_ids() -> Array:
	if not _asset_cache.is_empty():
		return _asset_cache
	var ids: Array = []
	if FileAccess.file_exists(ALLOWLIST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ALLOWLIST_PATH))
		var raw: Variant = null
		if typeof(parsed) == TYPE_ARRAY:
			raw = parsed
		elif typeof(parsed) == TYPE_DICTIONARY:
			var dict: Dictionary = parsed
			for key: String in ["assets", "allowlist", "ids", "assetIds"]:
				if dict.has(key):
					raw = dict[key]
					break
		if typeof(raw) == TYPE_ARRAY:
			for entry: Variant in raw:
				if typeof(entry) == TYPE_STRING and not String(entry).is_empty():
					ids.append(String(entry))
				elif typeof(entry) == TYPE_DICTIONARY:
					var id: String = String((entry as Dictionary).get("id", (entry as Dictionary).get("assetId", "")))
					if not id.is_empty():
						ids.append(id)
	if ids.is_empty():
		ids = DEFAULT_ASSET_IDS.duplicate()
	_asset_cache = ids
	return ids


## Full report: `{valid, ok, reasons, errors, turn}`. `turn` is the normalised
## copy when valid (subtitle defaulted, trimmed, unknown keys dropped) and the
## fallback when not. `reasons` carries the server's reason codes; `errors` is
## the same array under the name the first draft used.
static func validate(candidate: Variant, allowlist: Array = []) -> Dictionary:
	var reasons: Array = []
	if typeof(candidate) != TYPE_DICTIONARY:
		return _report(false, ["turn:not_object"], fallback_turn())
	var t: Dictionary = candidate
	var allowed: Array = allowlist if not allowlist.is_empty() else allowed_asset_ids()

	reasons.append_array(check_text(t.get("speech", null), "speech", MAX_SPEECH, true))
	reasons.append_array(check_text(t.get("subtitle", null), "subtitle", MAX_SUBTITLE, false))
	reasons.append_array(check_text(t.get("nextQuestion", null), "nextQuestion", MAX_NEXT_QUESTION, false))

	if not _is_member(t.get("emotion", null), EMOTIONS):
		reasons.append("emotion:invalid")
	if not _is_member(t.get("gesture", null), GESTURES):
		reasons.append("gesture:invalid")
	if not _is_member(t.get("lessonAction", null), LESSON_ACTIONS):
		reasons.append("lessonAction:invalid")

	var visual: Variant = t.get("visual", null)
	var asset_id: String = ""
	var visual_type: String = ""
	if typeof(visual) != TYPE_DICTIONARY:
		reasons.append("visual:missing")
	else:
		var v: Dictionary = visual
		var raw_type: Variant = v.get("type", null)
		if not _is_member(raw_type, VISUAL_TYPES):
			reasons.append("visual.type:invalid")
		else:
			visual_type = String(raw_type)
		var raw_id: Variant = v.get("assetId", null)
		var id_present: bool = raw_id != null and not (typeof(raw_id) == TYPE_STRING and String(raw_id).is_empty())
		if id_present:
			if typeof(raw_id) != TYPE_STRING or not allowed.has(String(raw_id)):
				reasons.append("visual.assetId:not_allowed")
			else:
				asset_id = String(raw_id)
		if not visual_type.is_empty() and visual_type != "none" and asset_id.is_empty() \
				and not reasons.has("visual.assetId:not_allowed"):
			reasons.append("visual.assetId:required")

	if not reasons.is_empty():
		return _report(false, reasons, fallback_turn())

	var speech: String = String(t["speech"]).strip_edges()
	var subtitle: String = speech
	if typeof(t.get("subtitle", null)) == TYPE_STRING and not String(t["subtitle"]).strip_edges().is_empty():
		subtitle = String(t["subtitle"]).strip_edges()
	var turn: Dictionary = {
		"speech": speech,
		"subtitle": subtitle,
		"emotion": String(t["emotion"]),
		"gesture": String(t["gesture"]),
		"visual": {"type": "none"} if visual_type == "none" else {"type": visual_type, "assetId": asset_id},
		"lessonAction": String(t["lessonAction"]),
	}
	if typeof(t.get("nextQuestion", null)) == TYPE_STRING and not String(t["nextQuestion"]).strip_edges().is_empty():
		turn["nextQuestion"] = String(t["nextQuestion"]).strip_edges()
	for key: String in IDENTIFIER_KEYS:
		if typeof(t.get(key, null)) == TYPE_STRING and is_safe_identifier(String(t[key])):
			turn[key] = String(t[key])
	return _report(true, [], turn)


## The turn to act on: the normalised turn, or the fallback.
static func coerce(candidate: Variant) -> Dictionary:
	return validate(candidate)["turn"]


static func is_valid(candidate: Variant) -> bool:
	return bool(validate(candidate)["valid"])


## Mirror of the server's `checkText`: the reason codes for one text field.
static func check_text(value: Variant, field: String, max_length: int, required: bool) -> Array:
	var reasons: Array = []
	if value == null or (typeof(value) == TYPE_STRING and String(value).is_empty()):
		if required:
			reasons.append("%s:required" % field)
		return reasons
	if typeof(value) != TYPE_STRING:
		return ["%s:not_string" % field]
	var text: String = value
	if text.strip_edges().is_empty():
		return ["%s:required" % field] if required else []
	if text.length() > max_length:
		reasons.append("%s:too_long" % field)
	if not _is_ascii_printable(text):
		reasons.append("%s:non_ascii" % field)
	if _has_url(text):
		reasons.append("%s:url" % field)
	if _has_long_digit_run(text):
		reasons.append("%s:long_number" % field)
	if _has_banned_word(text):
		reasons.append("%s:banned_word" % field)
	return reasons


## Builds a turn that is valid by construction, for the scripted provider. Text
## is trimmed to the limits; an unknown emotion/gesture/action falls to the
## neutral member; an asset not on the allowlist gives a visual of `none`.
static func make(speech: String, emotion: String, gesture: String, lesson_action: String,
		asset_id: String = "", next_question: String = "", subtitle: String = "",
		visual_type: String = "flashcard") -> Dictionary:
	var turn: Dictionary = {
		"speech": sanitize_text(speech, MAX_SPEECH),
		"subtitle": sanitize_text(subtitle if not subtitle.is_empty() else speech, MAX_SUBTITLE),
		"emotion": emotion if EMOTIONS.has(emotion) else "neutral",
		"gesture": gesture if GESTURES.has(gesture) else "none",
		"visual": {"type": "none"},
		"lessonAction": lesson_action if LESSON_ACTIONS.has(lesson_action) else "retry",
	}
	if not asset_id.is_empty() and allowed_asset_ids().has(asset_id):
		turn["visual"] = {
			"type": visual_type if (VISUAL_TYPES.has(visual_type) and visual_type != "none") else "flashcard",
			"assetId": asset_id,
		}
	if not next_question.is_empty():
		turn["nextQuestion"] = sanitize_text(next_question, MAX_NEXT_QUESTION)
	return turn


## `[a-z0-9_]{1,48}`, case-insensitive: a lesson id, a step id, an sfx name.
static func is_safe_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_IDENTIFIER:
		return false
	for i: int in range(value.length()):
		var code: int = value.unicode_at(i)
		var ok: bool = (code >= 0x30 and code <= 0x39) or (code >= 0x41 and code <= 0x5A) \
				or (code >= 0x61 and code <= 0x7A) or code == 0x5F
		if not ok:
			return false
	return true


## Lesson text on its way into `make()`: typographic punctuation becomes its
## ASCII form (the lesson JSON uses straight quotes today; this keeps a future
## edit from turning a whole turn into the fallback), anything else outside
## 0x20..0x7E is dropped, and the result is trimmed to `limit` on a word
## boundary where possible.
static func sanitize_text(text: String, limit: int) -> String:
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(text.length()):
		var code: int = text.unicode_at(i)
		if code >= 0x20 and code <= 0x7E:
			out.append(text[i])
			continue
		match code:
			0x2018, 0x2019: out.append("'")
			0x201C, 0x201D: out.append("\"")
			0x2013, 0x2014: out.append("-")
			0x2026: out.append("...")
			_: pass
	var line: String = "".join(out).strip_edges()
	if line.length() > limit:
		var cut: String = line.left(limit)
		var space: int = cut.rfind(" ")
		line = (cut.left(space) if space > limit / 2 else cut).strip_edges()
	return line


## Loads the shared fixture file: `[{name, input, expect, normalized?, reasonPrefix?}]`.
static func load_fixtures() -> Array:
	if not FileAccess.file_exists(FIXTURES_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES_PATH))
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var cases: Variant = (parsed as Dictionary).get("cases", [])
	return cases if typeof(cases) == TYPE_ARRAY else []


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _report(valid: bool, reasons: Array, turn: Dictionary) -> Dictionary:
	return {"valid": valid, "ok": valid, "reasons": reasons, "errors": reasons, "turn": turn}


static func _is_member(value: Variant, allowed: Array) -> bool:
	return typeof(value) == TYPE_STRING and allowed.has(String(value))


static func _is_ascii_printable(text: String) -> bool:
	for i: int in range(text.length()):
		var code: int = text.unicode_at(i)
		if code < 0x20 or code > 0x7E:
			return false
	return true


static func _has_url(text: String) -> bool:
	if _url_regex == null:
		_url_regex = RegEx.new()
		_url_regex.compile(URL_PATTERN)
	return _url_regex.search(text) != null


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


## Whole-word, case-insensitive, with the server's exact boundary rule
## `(^|[^a-z])word([^a-z]|$)` so "hello" never trips on "hell".
static func _has_banned_word(text: String) -> bool:
	if _banned_regexes.is_empty():
		for word: String in BANNED_WORDS:
			var regex: RegEx = RegEx.new()
			var pattern: String = "(?i)(^|[^a-z])%s([^a-z]|$)" % word.replace(" ", "\\s+")
			regex.compile(pattern)
			_banned_regexes.append(regex)
	for regex: RegEx in _banned_regexes:
		if regex.search(text) != null:
			return true
	return false
