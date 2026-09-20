extends RefCounted
## The recorded voice pack's table of contents.
##
## Reads `res://content/voice/voice_manifest.json` (the owner's 36 lines, two
## characters) and answers three questions the game needs: what is this line's
## text, who says it, and is its recording actually on disk.
##
## Engine-agnostic on purpose: no nodes, no audio. `VoiceDirector` is the only
## thing that loads a stream; everything else (cues, tests, docs checks) reads
## this table. Missing files are a REPORTED fact, never a hidden one --
## `missing_line_ids()` is what the validator test prints on every run, and
## `is_recorded()` never says yes to a file that is not there.

const DEFAULT_PATH: String = "res://content/voice/voice_manifest.json"
const CHARACTER_ALIZ: String = "aliz"
const CHARACTER_BUNNY: String = "bunny"
const CHARACTERS: Array[String] = [CHARACTER_ALIZ, CHARACTER_BUNNY]
const EXPECTED_LINE_COUNT: int = 36

var path: String = DEFAULT_PATH
var _lines: Array = []
var _by_id: Dictionary = {}
var _by_text: Dictionary = {}
var _characters: Dictionary = {}
var _load_error: String = ""
var _version: int = 0


## No `class_name`: this is preloaded by path everywhere so a fresh checkout
## works before the editor has rebuilt its global class cache.
const SELF_PATH: String = "res://scripts/voice/voice_manifest.gd"


static func load_default() -> RefCounted:
	var manifest: RefCounted = (load(SELF_PATH) as GDScript).new()
	manifest.call("load_from", DEFAULT_PATH)
	return manifest


## Parses `json_path`. Returns false (and remembers why) on any problem; the
## manifest is then simply empty, which every caller already tolerates.
func load_from(json_path: String) -> bool:
	path = json_path
	_lines = []
	_by_id = {}
	_by_text = {}
	_characters = {}
	_load_error = ""
	if not FileAccess.file_exists(json_path):
		_load_error = "missing: %s" % json_path
		return false
	var text: String = FileAccess.get_file_as_string(json_path)
	return load_from_text(text)


## Parses manifest JSON already in memory (tests hand fixtures in this way).
func load_from_text(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_error = "manifest is not a JSON object"
		return false
	var data: Dictionary = parsed
	_version = int(data.get("manifestVersion", 0))
	var characters: Variant = data.get("characters", {})
	if typeof(characters) == TYPE_DICTIONARY:
		_characters = (characters as Dictionary).duplicate(true)
	var lines: Variant = data.get("lines", [])
	if typeof(lines) != TYPE_ARRAY:
		_load_error = "manifest `lines` is not an array"
		return false
	for entry: Variant in lines:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var line: Dictionary = (entry as Dictionary).duplicate(true)
		var line_id: String = String(line.get("lineId", "")).strip_edges()
		if line_id.is_empty():
			continue
		_lines.append(line)
		_by_id[line_id] = line
		var english: String = normalise_text(String(line.get("text", "")))
		if not english.is_empty() and not _by_text.has(english):
			_by_text[english] = line_id
	return true


func load_error() -> String:
	return _load_error


func manifest_version() -> int:
	return _version


# -----------------------------------------------------------------------------
# Lookups
# -----------------------------------------------------------------------------


func has_line(line_id: String) -> bool:
	return _by_id.has(line_id)


## The whole row for `line_id`, or `{}`.
func line(line_id: String) -> Dictionary:
	return (_by_id.get(line_id, {}) as Dictionary).duplicate()


func text_for(line_id: String) -> String:
	return String((_by_id.get(line_id, {}) as Dictionary).get("text", ""))


func character_for(line_id: String) -> String:
	return String((_by_id.get(line_id, {}) as Dictionary).get("character", ""))


func emotion_for(line_id: String) -> String:
	return String((_by_id.get(line_id, {}) as Dictionary).get("emotion", ""))


func file_for(line_id: String) -> String:
	return String((_by_id.get(line_id, {}) as Dictionary).get("file", ""))


## The line whose English text is exactly `text` (case- and space-insensitive),
## or "". This is how a caller that only has a prompt string finds its recording.
func line_id_for_text(text: String) -> String:
	return String(_by_text.get(normalise_text(text), ""))


func line_ids() -> Array:
	var ids: Array = []
	for entry: Dictionary in _lines:
		ids.append(String(entry["lineId"]))
	return ids


func line_ids_for(character: String) -> Array:
	var ids: Array = []
	for entry: Dictionary in _lines:
		if String(entry.get("character", "")) == character:
			ids.append(String(entry["lineId"]))
	return ids


func lines() -> Array:
	return _lines.duplicate(true)


func line_count() -> int:
	return _lines.size()


func characters() -> Dictionary:
	return _characters.duplicate(true)


func has_character(character: String) -> bool:
	return CHARACTERS.has(character)


# -----------------------------------------------------------------------------
# What is actually on disk
# -----------------------------------------------------------------------------


## True only when the manifest names a file for `line_id` AND that file exists
## in the build. Never inferred, never cached across a run.
func is_recorded(line_id: String) -> bool:
	var file: String = file_for(line_id)
	if file.is_empty():
		return false
	return ResourceLoader.exists(file) or FileAccess.file_exists(file)


func recorded_line_ids() -> Array:
	var ids: Array = []
	for line_id: String in line_ids():
		if is_recorded(line_id):
			ids.append(line_id)
	return ids


func missing_line_ids() -> Array:
	var ids: Array = []
	for line_id: String in line_ids():
		if not is_recorded(line_id):
			ids.append(line_id)
	return ids


## One honest sentence for logs, docs and the validator test:
## "0 of 36 recordings present".
func presence_summary() -> String:
	return "%d of %d recordings present" % [recorded_line_ids().size(), line_count()]


# -----------------------------------------------------------------------------
# Validation (used by the test and by the convert tool's documentation)
# -----------------------------------------------------------------------------


## Structural problems, as strings. Empty means the table is sound. Presence of
## the audio files is deliberately NOT a problem here: see `missing_line_ids()`.
func validate() -> Array:
	var problems: Array = []
	if not _load_error.is_empty():
		problems.append(_load_error)
		return problems
	if _version < 1:
		problems.append("manifestVersion must be >= 1")
	var seen: Dictionary = {}
	for entry: Dictionary in _lines:
		var line_id: String = String(entry.get("lineId", ""))
		if seen.has(line_id):
			problems.append("duplicate lineId %s" % line_id)
		seen[line_id] = true
		var character: String = String(entry.get("character", ""))
		if not CHARACTERS.has(character):
			problems.append("%s: character must be aliz|bunny, got '%s'" % [line_id, character])
		if not line_id.begins_with(character + "_"):
			problems.append("%s: lineId must start with its character's name" % line_id)
		if String(entry.get("text", "")).strip_edges().is_empty():
			problems.append("%s: empty text" % line_id)
		if String(entry.get("emotion", "")).strip_edges().is_empty():
			problems.append("%s: empty emotion" % line_id)
		var file: String = String(entry.get("file", ""))
		var expected: String = "res://assets/audio/voice/%s/%s.ogg" % [character, line_id]
		if file != expected:
			problems.append("%s: file must be %s, got '%s'" % [line_id, expected, file])
	for character: String in CHARACTERS:
		if not _characters.has(character):
			problems.append("characters table lacks '%s'" % character)
	return problems


## Lower-cased, single-spaced, trimmed -- so "Great job!" and "great job! "
## are the same line. Punctuation is kept: "Milk, please!" is not "milk".
static func normalise_text(text: String) -> String:
	var parts: PackedStringArray = text.strip_edges().to_lower().split(" ", false)
	return " ".join(parts)
