class_name MusicManifest
extends RefCounted
## The music catalogue, and the licence gate in front of it.
##
## Loads `res://content/audio/manifest.json` and answers three questions about a
## track: *may* we play it (licence), *can* we play it (is the file here), and
## *how* should it sound (level, loop points).
##
## ## Why a manifest at all
##
## Music is the one asset class in this project that is not ours. Every SFX is
## synthesised by `tools/generate_sfx.gd`, so it carries no licence surface at
## all; music is generated in Suno by a human and arrives as a file with a
## provenance story attached. That story is worth nothing if it lives in someone's
## memory, so it lives here as data, per track:
##
##     trackId, source, createdAt, downloadedAt, licenseEvidence, commercialUse,
##     localPath, loopStart, loopEnd, volumeDb, usageScenes
##
## ## This module fails CLOSED
##
## A track is playable only when `commercialUse == "verified"` **and**
## `licenseEvidence` names something real. Anything else -- "pending", "denied",
## a typo, a bool `true`, an empty evidence string -- is refused, and
## `refusal_reason()` says which rule stopped it. A gate that has to be
## understood to be safe is not a gate; this one is safe by default and has to be
## deliberately opened.
##
## ## A missing file is normal, not an error
##
## The tracks below are listed before they exist. That is the intended state: the
## game ships silent-safe, and dropping a file in turns music on with no code
## change. `refusal_reason()` distinguishes `fileMissing` (expected, silent) from
## `commercialUseUnverified` (a real problem worth one warning), because the
## caller must treat those two very differently.
##
## Pure data and local file I/O. No `Node`, no 3D types, no network.

# -----------------------------------------------------------------------------
# Schema
# -----------------------------------------------------------------------------

const DEFAULT_MANIFEST_PATH: String = "res://content/audio/manifest.json"
const DEFAULT_MUSIC_DIR: String = "res://audio/music"

## Every one of these must be present on every entry. An entry that is missing
## any of them is rejected outright rather than half-loaded: a track with no
## `licenseEvidence` key is not a track with pending evidence, it is a track
## nobody has thought about yet.
const REQUIRED_FIELDS: Array[String] = [
	"trackId",
	"source",
	"createdAt",
	"downloadedAt",
	"licenseEvidence",
	"commercialUse",
	"localPath",
	"loopStart",
	"loopEnd",
	"volumeDb",
	"usageScenes",
]

## The only value that opens the gate.
const COMMERCIAL_USE_VERIFIED: String = "verified"
## Rights not yet established. The honest state of a track in flight.
const COMMERCIAL_USE_PENDING: String = "pending"
## Rights established and they do not permit commercial use. Never remove such a
## track's row -- a deleted row is indistinguishable from a track nobody checked.
const COMMERCIAL_USE_DENIED: String = "denied"

const ALLOWED_COMMERCIAL_USE: Array[String] = [
	COMMERCIAL_USE_VERIFIED,
	COMMERCIAL_USE_PENDING,
	COMMERCIAL_USE_DENIED,
]

## Placeholder written into `licenseEvidence` before the evidence exists. Treated
## exactly like an empty string: no evidence.
const EVIDENCE_PENDING: String = "PENDING"

## Accepted audio containers, in the order they are probed when the declared
## `localPath` is not on disk. Suno exports MP3 (and WAV on some plans); OGG is
## what we would convert to. Whichever of the three lands in `audio/music/` under
## the right basename plays, so a delivery cannot be defeated by an extension.
const ALLOWED_EXTENSIONS: Array[String] = ["ogg", "mp3", "wav"]

# -- Refusal reasons. Stable strings; tests and logs both use them. ------------

const REFUSAL_NONE: String = ""
const REFUSAL_UNKNOWN_TRACK: String = "unknownTrack"
const REFUSAL_COMMERCIAL_USE_UNVERIFIED: String = "commercialUseUnverified"
const REFUSAL_LICENCE_EVIDENCE_MISSING: String = "licenceEvidenceMissing"
const REFUSAL_LOCAL_PATH_MISSING: String = "localPathMissing"
const REFUSAL_FILE_MISSING: String = "fileMissing"

## Refusals that mean "the paperwork is wrong". These deserve a developer's
## attention. `fileMissing` deliberately is not one of them.
const LICENCE_REFUSALS: Array[String] = [
	REFUSAL_COMMERCIAL_USE_UNVERIFIED,
	REFUSAL_LICENCE_EVIDENCE_MISSING,
]

# -----------------------------------------------------------------------------
# Level ceiling
# -----------------------------------------------------------------------------

## Music can never be as loud as a spoken prompt or a reward chime. The loudest
## SFX sits at 0 dB of trim over a -6 dBFS file; music is held 6 dB below that
## however generous a manifest entry is, because music plays *under* the English
## the child is meant to hear.
const MAX_VOLUME_DB: float = -6.0
const MIN_VOLUME_DB: float = -60.0
## Manifest default when `volumeDb` is unusable.
const FALLBACK_VOLUME_DB: float = -14.0

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

var _manifest_version: int = 1
var _music_dir: String = DEFAULT_MUSIC_DIR
var _tracks: Dictionary = {}
var _order: Array[String] = []
var _errors: Array[String] = []
var _source_path: String = ""


# -----------------------------------------------------------------------------
# Loading
# -----------------------------------------------------------------------------
#
# These are instance methods rather than static factories on purpose. A static
# `-> MusicManifest` return type needs the script's own `class_name` to be
# resolvable, and the global class cache is written by the EDITOR -- so a freshly
# added script with a self-referencing type fails to compile in the headless
# runner and on any machine that has not opened the project. Costs one line at
# each call site; buys a module that cannot break the test runner.
#
#     var catalogue := MusicManifest.new()
#     catalogue.load_file()


## Reads and parses `path`, replacing anything previously loaded. Returns false
## when nothing usable was read -- in which case this is an EMPTY manifest with
## the problem recorded in `errors()`, never a crash and never an engine error.
## An empty manifest simply means no music, which is a state the game is required
## to survive anyway.
func load_file(path: String = DEFAULT_MANIFEST_PATH) -> bool:
	_reset()
	_source_path = path
	if not FileAccess.file_exists(path):
		_errors.append("manifest not found at %s" % path)
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_errors.append("could not open %s" % path)
		return false
	var text: String = file.get_as_text()
	file.close()
	return ingest_json(text)


## Parses manifest JSON from a string. Used by tests and by anything that wants
## to validate a candidate manifest before it is written.
func ingest_json(text: String) -> bool:
	# `JSON.new().parse()` rather than the `JSON.parse_string()` helper: the helper
	# pushes an engine ERROR on malformed input, and a corrupt manifest must
	# degrade to "no music" quietly, exactly as a corrupt profile degrades to safe
	# defaults. The message is kept in `errors()` where a developer can find it.
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		_reset_keeping_source()
		_errors.append(
			"manifest is not valid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()]
		)
		return false
	var parsed: Variant = json.data
	if parsed == null or not (parsed is Dictionary):
		_reset_keeping_source()
		_errors.append("manifest is not a JSON object")
		return false
	return ingest_dictionary(parsed as Dictionary)


## Replaces this manifest's contents with an already-decoded dictionary.
func ingest_dictionary(data: Dictionary) -> bool:
	var source: String = _source_path
	_reset()
	_source_path = source
	_ingest(data)
	return not _order.is_empty()


func _reset() -> void:
	_manifest_version = 1
	_music_dir = DEFAULT_MUSIC_DIR
	_tracks = {}
	_order = []
	_errors = []
	_source_path = ""


func _reset_keeping_source() -> void:
	var source: String = _source_path
	_reset()
	_source_path = source


# -----------------------------------------------------------------------------
# Reading the catalogue
# -----------------------------------------------------------------------------


func manifest_version() -> int:
	return _manifest_version


func music_dir() -> String:
	return _music_dir


func source_path() -> String:
	return _source_path


## Schema problems found while loading. A non-empty result does not stop the game
## -- it means some tracks were dropped or refused. Tests assert on it; the
## runtime only logs it.
func errors() -> Array:
	return _errors.duplicate()


func is_empty() -> bool:
	return _order.is_empty()


func track_count() -> int:
	return _order.size()


## Declared ids, in manifest order.
func track_ids() -> Array:
	return _order.duplicate()


func has_track(track_id: String) -> bool:
	return _tracks.has(track_id)


## A copy, so a caller cannot mutate the catalogue by holding one row.
func get_track(track_id: String) -> Dictionary:
	if not _tracks.has(track_id):
		return {}
	return (_tracks[track_id] as Dictionary).duplicate(true)


## Every track that declares `scene` in `usageScenes`, in manifest order,
## whatever its licence state. Callers that want to *play* something must still
## go through `is_playable()`; this exists so a refusal can name the track it
## refused.
func tracks_for_scene(scene: String) -> Array:
	var found: Array = []
	if scene.is_empty():
		return found
	for track_id: String in _order:
		var scenes: Array = (_tracks[track_id] as Dictionary).get("usageScenes", [])
		if scenes.has(scene):
			found.append(track_id)
	return found


## The first track for `scene` that is cleared and present, or "" when the scene
## has no music today. "" is a normal answer.
func playable_track_for_scene(scene: String) -> String:
	for track_id: String in tracks_for_scene(scene):
		if is_playable(track_id):
			return track_id
	return ""


# -----------------------------------------------------------------------------
# The gate
# -----------------------------------------------------------------------------


## True when the licence paperwork permits playback. Says nothing about whether
## the file exists.
func licence_cleared(track_id: String) -> bool:
	if not _tracks.has(track_id):
		return false
	var track: Dictionary = _tracks[track_id]
	if String(track.get("commercialUse", "")) != COMMERCIAL_USE_VERIFIED:
		return false
	return _has_evidence(String(track.get("licenseEvidence", "")))


## True when the row says, in so many words, that commercial use is NOT permitted.
##
## Different in kind from every other refusal, and the difference matters: a
## `"pending"` row means nobody has checked yet, a missing field means nobody has
## thought about it, and `"denied"` means somebody checked and the answer was no.
## `refusal_reason()` cannot tell them apart -- all three answer
## `commercialUseUnverified`, because all three must be refused -- so anything that
## releases a refusal (see `AudioDirector.may_play()`) has to ask this as well.
func is_denied(track_id: String) -> bool:
	if not _tracks.has(track_id):
		return false
	return String((_tracks[track_id] as Dictionary).get("commercialUse", "")) == COMMERCIAL_USE_DENIED


## True when the track may be played AND there is a file to play. This is the
## only question the audio manager is allowed to ask before assigning a stream.
func is_playable(track_id: String) -> bool:
	return refusal_reason(track_id) == REFUSAL_NONE


## "" when the track is playable, otherwise the first rule that stopped it.
## Order matters: the licence is checked BEFORE the disk, so a track with no
## rights reports its licence problem rather than hiding behind a missing file
## and quietly becoming playable the day someone drops the file in.
func refusal_reason(track_id: String) -> String:
	if not _tracks.has(track_id):
		return REFUSAL_UNKNOWN_TRACK
	var track: Dictionary = _tracks[track_id]

	if String(track.get("commercialUse", "")) != COMMERCIAL_USE_VERIFIED:
		return REFUSAL_COMMERCIAL_USE_UNVERIFIED
	if not _has_evidence(String(track.get("licenseEvidence", ""))):
		return REFUSAL_LICENCE_EVIDENCE_MISSING
	if String(track.get("localPath", "")).is_empty():
		return REFUSAL_LOCAL_PATH_MISSING
	if resolved_path(track_id).is_empty():
		return REFUSAL_FILE_MISSING
	return REFUSAL_NONE


## True when this refusal is a paperwork problem rather than "the file is not
## here yet". Only these are worth warning a developer about.
static func is_licence_refusal(reason: String) -> bool:
	return LICENCE_REFUSALS.has(reason)


## Ids whose file is absent. The expected state before a delivery; used by the
## runbook and by diagnostics, never to fail anything.
func missing_track_ids() -> Array:
	var missing: Array = []
	for track_id: String in _order:
		if resolved_path(track_id).is_empty():
			missing.append(track_id)
	return missing


## Ids the licence gate refuses. Should be empty in a shipping build.
func licence_refused_track_ids() -> Array:
	var refused: Array = []
	for track_id: String in _order:
		if not licence_cleared(track_id):
			refused.append(track_id)
	return refused


# -----------------------------------------------------------------------------
# Playback parameters
# -----------------------------------------------------------------------------


## The file actually on disk for this track, or "" when there is none.
##
## Probes the declared `localPath` first, then the same basename with each
## accepted extension, so a delivery of `hungry_bunny.mp3` against a manifest
## that says `.ogg` still plays.
func resolved_path(track_id: String) -> String:
	if not _tracks.has(track_id):
		return ""
	var declared: String = String((_tracks[track_id] as Dictionary).get("localPath", ""))
	if declared.is_empty():
		return ""
	if _file_present(declared):
		return declared
	var base: String = declared.get_basename()
	for extension: String in ALLOWED_EXTENSIONS:
		var candidate: String = "%s.%s" % [base, extension]
		if candidate != declared and _file_present(candidate):
			return candidate
	return ""


## The track's own level, clamped into the child-safe window. Never louder than
## `MAX_VOLUME_DB`, whatever the manifest says.
func volume_db_for(track_id: String) -> float:
	if not _tracks.has(track_id):
		return FALLBACK_VOLUME_DB
	var raw: float = float((_tracks[track_id] as Dictionary).get("volumeDb", FALLBACK_VOLUME_DB))
	return clampf(raw, MIN_VOLUME_DB, MAX_VOLUME_DB)


## `{"loopStart": float, "loopEnd": float}` in seconds. `loopEnd == 0.0` means
## "to the end of the file"; both zero means "loop the whole thing", which is
## what a well-made loop wants.
func loop_points(track_id: String) -> Dictionary:
	if not _tracks.has(track_id):
		return {"loopStart": 0.0, "loopEnd": 0.0}
	var track: Dictionary = _tracks[track_id]
	var start: float = maxf(0.0, float(track.get("loopStart", 0.0)))
	var end: float = maxf(0.0, float(track.get("loopEnd", 0.0)))
	if end > 0.0 and end <= start:
		end = 0.0  # A loop that ends before it starts is no loop at all.
	return {"loopStart": start, "loopEnd": end}


# -----------------------------------------------------------------------------
# Round-tripping
# -----------------------------------------------------------------------------


## The manifest as a dictionary, in canonical field order. Feeding this back
## through `ingest_dictionary()` must produce an identical manifest -- the
## round-trip is a test, because a loader that quietly drops a field it does not
## understand is a loader that loses provenance.
func to_dictionary() -> Dictionary:
	var rows: Array = []
	for track_id: String in _order:
		rows.append((_tracks[track_id] as Dictionary).duplicate(true))
	return {
		"manifestVersion": _manifest_version,
		"musicDir": _music_dir,
		"tracks": rows,
	}


## `sort_keys` is FALSE deliberately. It defaults to true, which reorders every
## row alphabetically -- so `trackId` stopped being the first thing a human reads,
## and, worse, the JSON round-trip above stopped being an identity as soon as a row
## carried a field outside `REQUIRED_FIELDS`: `to_dictionary()` emits the canonical
## order and a sorted re-parse comes back in a different one. The provenance fields
## added with the 2026-09-19 delivery are exactly that case, and they found it.
func to_json_string() -> String:
	return JSON.stringify(to_dictionary(), "  ", false)


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------


func _ingest(data: Dictionary) -> void:
	_manifest_version = int(data.get("manifestVersion", 1))
	var declared_dir: String = String(data.get("musicDir", DEFAULT_MUSIC_DIR))
	_music_dir = declared_dir if not declared_dir.is_empty() else DEFAULT_MUSIC_DIR

	var rows: Variant = data.get("tracks", [])
	if not (rows is Array):
		_errors.append("`tracks` must be an array")
		return

	for row: Variant in rows as Array:
		if not (row is Dictionary):
			_errors.append("a `tracks` entry is not an object; dropped")
			continue
		_ingest_track(row as Dictionary)


func _ingest_track(row: Dictionary) -> void:
	var track_id: String = String(row.get("trackId", "")).strip_edges()
	var label: String = track_id if not track_id.is_empty() else "<no trackId>"

	var missing: Array = []
	for field: String in REQUIRED_FIELDS:
		if not row.has(field):
			missing.append(field)
	if not missing.is_empty():
		_errors.append(
			"track %s is missing required field(s) %s; dropped" % [label, ", ".join(missing)]
		)
		return
	if track_id.is_empty():
		_errors.append("a track has an empty trackId; dropped")
		return
	if _tracks.has(track_id):
		_errors.append("duplicate trackId %s; the later entry was dropped" % track_id)
		return

	# Normalise types but never values. An out-of-schema `commercialUse` is kept
	# verbatim and reported: silently rewriting it to "pending" would be tidier
	# and would also erase the evidence that someone typed something wrong.
	var commercial_use: String = _string_of(row["commercialUse"])
	if not ALLOWED_COMMERCIAL_USE.has(commercial_use):
		_errors.append(
			("track %s has commercialUse %s, which is not one of %s. It is refused: this gate "
			+ "fails closed, so a typo can never open it.")
			% [track_id, JSON.stringify(row["commercialUse"]), ", ".join(ALLOWED_COMMERCIAL_USE)]
		)

	var scenes: Array = []
	if row["usageScenes"] is Array:
		for scene: Variant in row["usageScenes"] as Array:
			var name: String = String(scene).strip_edges()
			if not name.is_empty():
				scenes.append(name)
	else:
		_errors.append("track %s has a non-array usageScenes; treated as empty" % track_id)

	var volume_db: float = FALLBACK_VOLUME_DB
	if _is_number(row["volumeDb"]):
		volume_db = clampf(float(row["volumeDb"]), MIN_VOLUME_DB, MAX_VOLUME_DB)
	else:
		_errors.append(
			"track %s has a non-numeric volumeDb; using %.1f dB" % [track_id, FALLBACK_VOLUME_DB]
		)

	var track: Dictionary = {
		"trackId": track_id,
		"source": String(row["source"]),
		"createdAt": String(row["createdAt"]),
		"downloadedAt": String(row["downloadedAt"]),
		"licenseEvidence": String(row["licenseEvidence"]),
		"commercialUse": commercial_use,
		"localPath": String(row["localPath"]).strip_edges(),
		"loopStart": _number_of(row["loopStart"]),
		"loopEnd": _number_of(row["loopEnd"]),
		"volumeDb": volume_db,
		"usageScenes": scenes,
	}

	# Anything the schema does not name is preserved rather than dropped, so a
	# field added by a later version survives a load/save cycle intact.
	for key: Variant in row.keys():
		var name: String = String(key)
		if not track.has(name):
			track[name] = row[key]

	_tracks[track_id] = track
	_order.append(track_id)


## Evidence has to point at something. "PENDING", "", "todo" and "n/a" do not.
static func _has_evidence(evidence: String) -> bool:
	var trimmed: String = evidence.strip_edges()
	if trimmed.is_empty():
		return false
	var lowered: String = trimmed.to_lower()
	return not [
		EVIDENCE_PENDING.to_lower(), "pending", "todo", "tbd", "none", "n/a", "unknown",
	].has(lowered)


## True when a playable file for `path` is reachable. `FileAccess` covers a
## source checkout and the headless runner; `ResourceLoader` covers an exported
## build, which ships the imported resource rather than the source file.
static func _file_present(path: String) -> bool:
	if path.is_empty():
		return false
	if FileAccess.file_exists(path):
		return true
	return ResourceLoader.exists(path)


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


static func _number_of(value: Variant) -> float:
	return float(value) if _is_number(value) else 0.0


## A `String()` cast of a bool gives "true", which is exactly what we want in an
## error message: it shows what was actually written.
static func _string_of(value: Variant) -> String:
	if value is String:
		return (value as String).strip_edges()
	return String(str(value))
