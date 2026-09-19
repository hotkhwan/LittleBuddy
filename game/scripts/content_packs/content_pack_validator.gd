extends RefCounted

## THE GATE every content pack has to get through. Data in, reasons out.
##
##     var problems := ContentPackValidator.validate(raw, library, GameVersion.BUILD)
##     if problems.is_empty(): accept(ContentPack.from_dict(raw))
##
## Two rejections are the brief's, and they are the two that matter most:
##
##   1. **`requiredGameVersion` newer than this build.** A pack authored against
##      next release's logic cannot run here. Rejecting it whole is the only safe
##      answer -- loading the half of it this build understands is how a child ends
##      up in a mission that has no ending.
##   2. **A mission id the build does not have.** The pack is a catalogue; the
##      LOGIC must already exist. A pack that names `feedTheDucks` when no such
##      mission is implemented is a content mistake, and the place to find it is
##      here, on a developer's machine, in a test -- not in a room where a
##      four-year-old has just tapped something that does nothing.
##
## Everything else here is the same instinct applied wider: a pack must name a
## known entitlement (a pack gated behind an id that cannot be granted is dead
## content), must carry an actual payload, and must contain no URL, no `res://`
## path and no file extension anywhere -- because **a pack may only ever be a list
## of ids**. That last rule is what makes "no remote or executable content" a
## property of the format rather than a promise in a document: there is nothing in
## a valid pack that could name a thing to fetch or a thing to run.
##
## ## Reasons, not booleans
##
## `validate()` returns the list of what is wrong, in human words, because these
## strings are what a content author reads at 11pm on a Sunday. `is_valid()` is
## the boolean for callers that only need the verdict.
##
## PURE. No node, no 3D type, no network, no `load()`. The mission catalogue is
## duck-typed: pass `ContentLibrary`, or just an array of known mission ids.

const ContentPack := preload("res://scripts/content_packs/content_pack.gd")
const GameVersion := preload("res://scripts/content_packs/game_version.gd")
const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

## Substrings that must never appear in any field of a pack. A pack lists ids; an
## id containing any of these is trying to be a location or a file.
const FORBIDDEN_SUBSTRINGS: Array[String] = [
	"://", "http", "www.", "res:", "user:", "..",
	".gd", ".gdc", ".tscn", ".scn", ".pck", ".zip", ".so", ".dylib", ".dll",
]

## A pack has to actually give the family something.
const MIN_PAYLOAD_IDS: int = 1


## Everything wrong with `raw`, as sentences. Empty means the pack is acceptable.
static func validate(
		raw: Variant,
		mission_catalog: Variant = null,
		build_version: String = GameVersion.BUILD) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()

	if typeof(raw) != TYPE_DICTIONARY:
		problems.append("a content pack must be a JSON object; got %s"
				% type_string(typeof(raw)))
		return problems

	var record: Dictionary = ContentPack.from_dict(raw)
	var pack_id: String = String(record["packId"])

	# -- identity ---------------------------------------------------------------
	if pack_id.is_empty():
		problems.append("packId is missing or is not a string; a pack with no id cannot be "
				+ "referred to, enabled or replaced")
	elif not _is_camel_case_id(pack_id):
		problems.append("packId '%s' is not a plain camelCase id" % pack_id)

	var version: int = int(record["version"])
	if version < 1:
		problems.append("%s: version must be a whole number of 1 or more; got %s"
				% [_label(pack_id), str(raw.get("version", null))])

	# -- rejection 1: a pack from the future ------------------------------------
	var required: String = String(record["requiredGameVersion"])
	if not GameVersion.is_valid(required):
		problems.append("%s: requiredGameVersion '%s' is not MAJOR.MINOR.PATCH"
				% [_label(pack_id), required])
	elif GameVersion.is_newer_than(required, build_version):
		problems.append(
			("%s: requires game version %s but this build is %s. The pack is REJECTED whole "
			+ "rather than partly loaded: it was authored against logic this build does not "
			+ "have, and loading the half of it that parses is how a child reaches a mission "
			+ "with no ending. Ship the build first, then the pack.")
			% [_label(pack_id), required, build_version])

	# -- rejection 2: a mission that does not exist -----------------------------
	var missions: Array = record["missions"]
	if mission_catalog == null:
		if not missions.is_empty():
			problems.append(
				("%s: no mission catalogue was supplied, so its %d mission id(s) cannot be "
				+ "checked. A pack is a CATALOGUE -- the mission logic has to exist before the "
				+ "pack may name it -- so an unverifiable mission list is a rejection, not a "
				+ "warning.") % [_label(pack_id), missions.size()])
	else:
		for mission_id: Variant in missions:
			if not _catalog_has_mission(mission_catalog, String(mission_id)):
				problems.append(
					("%s: names mission '%s', which this build does not implement. Mission and "
					+ "mini-game LOGIC lives in code and ships with the build; a pack may only "
					+ "list ids that already exist. Add the mission first, then the pack entry.")
					% [_label(pack_id), String(mission_id)])

	# -- entitlement -----------------------------------------------------------
	var entitlement_id: String = String(record["entitlementId"])
	if entitlement_id.is_empty():
		problems.append("%s: entitlementId is missing; every pack has to say which right unlocks it"
				% _label(pack_id))
	elif not EntitlementIds.is_known(entitlement_id):
		problems.append(
			("%s: entitlementId '%s' is not one this build knows (%s). A pack gated behind an "
			+ "entitlement that can never be granted is content nobody will ever see, so it is "
			+ "rejected loudly instead of shipped dark.")
			% [_label(pack_id), entitlement_id, ", ".join(EntitlementIds.known_ids())])

	# -- payload ---------------------------------------------------------------
	if ContentPack.payload_size(record) < MIN_PAYLOAD_IDS:
		problems.append("%s: lists nothing at all -- no mission, room, character, outfit or audio"
				% _label(pack_id))

	# -- a pack is a list of ids, never a location or a file -------------------
	for value: String in _every_string(raw):
		var lowered: String = value.to_lower()
		for marker: String in FORBIDDEN_SUBSTRINGS:
			if lowered.contains(marker):
				problems.append(
					("%s: the value '%s' contains '%s'. A content pack may only ever be a list of "
					+ "ids -- no URL, no path, no file name, nothing fetchable and nothing "
					+ "runnable. Packs are packaged locally in the build; nothing is downloaded.")
					% [_label(pack_id), value, marker])
				break

	for id: String in ContentPack.all_ids(record):
		if not _is_plain_id(id):
			problems.append("%s: '%s' is not a plain id (letters, digits, underscore)"
					% [_label(pack_id), id])

	return problems


## The verdict on its own.
static func is_valid(
		raw: Variant,
		mission_catalog: Variant = null,
		build_version: String = GameVersion.BUILD) -> bool:
	return validate(raw, mission_catalog, build_version).is_empty()


## Things worth telling an author about that are not rejections. Kept apart from
## `validate()` so that a warning can never quietly become a reason to drop a pack.
static func warnings(raw: Variant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for field: String in ContentPack.unknown_fields(raw):
		out.append("unknown field '%s' was ignored; this build reads only: %s"
				% [field, ", ".join(ContentPack.FIELDS)])
	return out


# -- internals ------------------------------------------------------------------

static func _label(pack_id: String) -> String:
	return "pack '%s'" % pack_id if not pack_id.is_empty() else "pack <unnamed>"


## `ContentLibrary`-style object, or a plain list of ids. Anything else knows
## nothing, which means every mission id fails -- the closed direction.
static func _catalog_has_mission(catalog: Variant, mission_id: String) -> bool:
	if typeof(catalog) == TYPE_OBJECT:
		var object: Object = catalog
		if object.has_method("has_mission"):
			return bool(object.call("has_mission", mission_id))
		if object.has_method("get_mission_ids"):
			return PackedStringArray(object.call("get_mission_ids")).has(mission_id)
		return false
	if typeof(catalog) == TYPE_ARRAY:
		return (catalog as Array).has(mission_id)
	if typeof(catalog) == TYPE_PACKED_STRING_ARRAY:
		return (catalog as PackedStringArray).has(mission_id)
	return false


## camelCase: starts lower-case, letters and digits only. For `packId` and
## `entitlementId`, which are keys this project writes by hand.
static func _is_camel_case_id(id: String) -> bool:
	if id.is_empty():
		return false
	var first: String = id[0]
	if first < "a" or first > "z":
		return false
	for index: int in range(id.length()):
		if not _is_alphanumeric(id[index]):
			return false
	return true


## The looser rule for payload ids, which have to cover the bundled audio names
## (`success_chime`) as well as camelCase mission and room ids (`livingRoom`).
static func _is_plain_id(id: String) -> bool:
	if id.is_empty():
		return false
	var first: String = id[0]
	var starts_with_letter: bool = (first >= "a" and first <= "z") or (first >= "A" and first <= "Z")
	if not starts_with_letter:
		return false
	for index: int in range(id.length()):
		var character: String = id[index]
		if character == "_":
			continue
		if not _is_alphanumeric(character):
			return false
	return true


static func _is_alphanumeric(character: String) -> bool:
	if character >= "a" and character <= "z":
		return true
	if character >= "A" and character <= "Z":
		return true
	return character >= "0" and character <= "9"


## Every string anywhere in the raw pack -- values and nested list entries. Keys
## are covered by `unknown_fields()`; this is about what the values could name.
static func _every_string(raw: Variant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key: Variant in (raw as Dictionary).keys():
		var value: Variant = (raw as Dictionary)[key]
		if typeof(value) == TYPE_STRING:
			out.append(String(value))
		elif typeof(value) == TYPE_ARRAY:
			for entry: Variant in (value as Array):
				if typeof(entry) == TYPE_STRING:
					out.append(String(entry))
	return out
