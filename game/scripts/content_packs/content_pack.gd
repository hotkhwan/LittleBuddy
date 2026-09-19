extends RefCounted

## CONTENT PACK METADATA. Nine fields, one shape, reusable for every pack.
##
##     packId              "farmFriends"   -- camelCase, unique, stable forever
##     version             3               -- this pack's own revision, >= 1
##     requiredGameVersion "0.2.0"         -- oldest build that can run it
##     missions            ["feedTheDucks"] -- ids that must ALREADY exist in code
##     rooms               ["barn"]
##     characters          ["duck"]
##     outfits             ["raincoat"]
##     audio               ["quack"]
##     entitlementId       "familyClub"    -- which right unlocks it
##
## ## The separation this file exists to enforce
##
## **A pack is a CATALOGUE, not a program.** It lists ids. It cannot add a mission
## template, a rule, a state machine or a line of behaviour -- the logic for
## `feedTheDucks` has to be in `scripts/gameplay/` before any pack may name it,
## and `content_pack_validator.gd` rejects a pack that names a mission the build
## does not have. That is the entire discipline: **weekly content is a data drop
## against logic that already shipped and was already tested.**
##
## It is also what makes "a new pack every week" survivable. A pack cannot break
## the game because there is no mechanism by which it could: it has no code, it is
## read with `FileAccess` + `JSON` and never `load()`, and every id it names is
## checked against something that exists before it is accepted. Packs are
## packaged LOCALLY, in the build, under `res://content/packs/`. Nothing is
## downloaded, ever.
##
## ## Why the record is a Dictionary
##
## Because every other content type in this project is (`content_library.gd`
## returns Dictionaries throughout) and because a pack is JSON on both sides of
## the boundary. `from_dict()` normalises rather than validates: it returns all
## nine fields, with missing or wrong-typed ones as safe empties, so the validator
## downstream gets a predictable shape to complain about. Normalising and
## validating in one pass is how a half-valid pack ends up half-loaded.

## The nine fields, in the order the brief names them. Nothing else is read out of
## a pack file, and `ALLOWED_FIELDS` is what makes an unexpected key visible
## instead of silently ignored.
const FIELDS: Array[String] = [
	"packId", "version", "requiredGameVersion",
	"missions", "rooms", "characters", "outfits", "audio",
	"entitlementId",
]

## The five list fields, kept separately so the parser and the validator agree on
## which fields are arrays of ids without either one hard-coding the list twice.
const LIST_FIELDS: Array[String] = ["missions", "rooms", "characters", "outfits", "audio"]

const MAX_ID_LENGTH: int = 64


## A normalised record: all nine fields present, wrong types replaced by empties.
## Never fails, never throws; judging the result is the validator's job.
static func from_dict(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var out: Dictionary = {
		"packId": _string_of(source.get("packId", "")),
		"version": _int_of(source.get("version", 0)),
		"requiredGameVersion": _string_of(source.get("requiredGameVersion", "")),
		"entitlementId": _string_of(source.get("entitlementId", "")),
	}
	for field: String in LIST_FIELDS:
		out[field] = _ids_of(source.get(field, []))
	return out


## Keys in the file that this build does not know. Reported as a warning by the
## validator rather than an error: a pack authored for a later build may carry a
## field this one has no use for, and dropping it is correct -- silently dropping
## it is not.
static func unknown_fields(raw: Variant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key: Variant in (raw as Dictionary).keys():
		if typeof(key) != TYPE_STRING:
			continue
		if not FIELDS.has(String(key)):
			out.append(String(key))
	return out


## Every id a pack names, across all five list fields. Used by the offline-content
## checks: one loop instead of five.
static func all_ids(record: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for field: String in LIST_FIELDS:
		var value: Variant = record.get(field, [])
		if typeof(value) != TYPE_ARRAY:
			continue
		for entry: Variant in (value as Array):
			out.append(String(entry))
	return out


## How many ids the pack actually delivers. A pack that delivers nothing is a
## rejection, not a pack.
static func payload_size(record: Dictionary) -> int:
	return all_ids(record).size()


## One line for a changelog or a QA report. Never shown to a child.
static func summary_line(record: Dictionary) -> String:
	return "%s v%d (needs %s) -- %d missions, %d rooms, %d characters, %d outfits, %d audio [%s]" % [
		String(record.get("packId", "?")),
		int(record.get("version", 0)),
		String(record.get("requiredGameVersion", "?")),
		(record.get("missions", []) as Array).size(),
		(record.get("rooms", []) as Array).size(),
		(record.get("characters", []) as Array).size(),
		(record.get("outfits", []) as Array).size(),
		(record.get("audio", []) as Array).size(),
		String(record.get("entitlementId", "?")),
	]


# -- normalising ----------------------------------------------------------------

static func _string_of(value: Variant) -> String:
	return String(value).strip_edges() if typeof(value) == TYPE_STRING else ""


static func _int_of(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return 0


## Strings only, trimmed, de-duplicated, order preserved. A nested array, a
## number or a null inside the list is dropped individually -- the pack's other
## ids are still perfectly good data.
static func _ids_of(value: Variant) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry: Variant in (value as Array):
		if typeof(entry) != TYPE_STRING:
			continue
		var id: String = String(entry).strip_edges()
		if id.is_empty() or id.length() > MAX_ID_LENGTH:
			continue
		if not out.has(id):
			out.append(id)
	return out
