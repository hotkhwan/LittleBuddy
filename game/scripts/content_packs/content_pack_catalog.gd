extends RefCounted

## The local pack shelf: reads `res://content/packs/`, validates, sorts into
## accepted and rejected, and stops there.
##
##     var catalog := ContentPackCatalogScript.new()
##     catalog.load_all(library)              # library = ContentLibrary, for missions
##     catalog.get_packs()                    # the packs this build accepted
##     catalog.get_rejections()               # why the others were not accepted
##     catalog.entitled_missions(entitlements)  # what the family may actually play
##
## ## Local. Only ever local.
##
## Packs are files inside the build. The index names them explicitly (the same
## pattern `content/index.json` already uses for tasks and missions), every path
## is required to sit under `res://content/packs/`, and each one is read with
## `FileAccess` + `JSON.parse_string()` -- **never `load()` and never
## `ResourceLoader`**, so a pack file cannot be a scene, a script or a resource
## with a script attached. There is no downloader, no cache directory, no URL
## anywhere in this layer, and the validator refuses any pack whose values contain
## one.
##
## ## A rejected pack is not a missing pack
##
## Rejections are kept, with their reasons, rather than discarded. A pack that
## needs a newer build is a normal, expected state -- it is what a build one
## release behind should do with next release's content drop -- and a silent
## disappearance is the one behaviour that would make that state impossible to
## diagnose on a device with no console.
##
## ## What this deliberately does NOT do
##
## It does not gate anything on its own. `entitled_missions()` is a QUERY; no
## gameplay code calls it yet, and wiring it up is a Lead decision, not a
## catalogue's. It is also why there is no `is_mission_locked()` here: a mission
## that no pack mentions is not locked, it is simply not pack content, and a
## catalogue that answered "locked" for everything it had never heard of would
## close the shipped game the first time it loaded.
##
## And nothing here is child-facing. There is no "locked" badge, no teaser, no
## preview of a pack a family does not have. A child sees the game they have.

const ContentPack := preload("res://scripts/content_packs/content_pack.gd")
const ContentPackValidator := preload("res://scripts/content_packs/content_pack_validator.gd")
const GameVersion := preload("res://scripts/content_packs/game_version.gd")

const PACKS_DIR: String = "res://content/packs"
const INDEX_PATH: String = "res://content/packs/index.json"
const INDEX_FIELD: String = "packFiles"

## Accepted packs, as normalised records, in index order.
var _packs: Array = []
## `[{path, packId, reasons}]` for everything that did not get through.
var _rejections: Array = []
var _warnings: Array = []


## Reads the index and every pack it names.
##
## `mission_catalog` is duck-typed (`ContentLibrary`, or a list of mission ids).
## Passing nothing means no mission id can be verified, and the validator treats
## that as a rejection -- see its comment; it is the closed direction.
func load_all(mission_catalog: Variant = null, build_version: String = GameVersion.BUILD) -> void:
	_packs = []
	_rejections = []
	_warnings = []

	var index: Variant = _read_json(INDEX_PATH)
	if typeof(index) != TYPE_DICTIONARY:
		_warnings.append("%s is missing or is not a JSON object; no content packs were loaded"
				% INDEX_PATH)
		return

	var listed: Variant = (index as Dictionary).get(INDEX_FIELD, [])
	if typeof(listed) != TYPE_ARRAY:
		_warnings.append("%s has no '%s' array" % [INDEX_PATH, INDEX_FIELD])
		return

	for entry: Variant in (listed as Array):
		if typeof(entry) != TYPE_STRING:
			_warnings.append("%s: a packFiles entry is not a string; ignored" % INDEX_PATH)
			continue
		_load_one(String(entry), mission_catalog, build_version)


func _load_one(path: String, mission_catalog: Variant, build_version: String) -> void:
	# Every pack must live in the pack directory. Not a security boundary -- the
	# whole file tree is inside the build -- but it keeps the shelf a shelf, so
	# "where do packs come from" has exactly one answer.
	if not path.begins_with(PACKS_DIR + "/"):
		_reject(path, "", ["%s is outside %s/" % [path, PACKS_DIR]])
		return

	var raw: Variant = _read_json(path)
	if typeof(raw) != TYPE_DICTIONARY:
		_reject(path, "", ["%s is missing, unreadable or not a JSON object" % path])
		return

	var problems: PackedStringArray = ContentPackValidator.validate(
			raw, mission_catalog, build_version)
	for warning: String in ContentPackValidator.warnings(raw):
		_warnings.append("%s: %s" % [path, warning])

	var record: Dictionary = ContentPack.from_dict(raw)
	if not problems.is_empty():
		_reject(path, String(record["packId"]), problems)
		return

	# A duplicate packId would make `get_pack()` ambiguous and a later pack would
	# silently shadow an earlier one.
	for existing: Dictionary in _packs:
		if String(existing["packId"]) == String(record["packId"]):
			_reject(path, String(record["packId"]),
					["duplicate packId '%s'; already loaded" % String(record["packId"])])
			return

	record["sourcePath"] = path
	_packs.append(record)


# -- reading -------------------------------------------------------------------

func get_packs() -> Array:
	return _packs.duplicate(true)


func get_pack_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for record: Dictionary in _packs:
		out.append(String(record["packId"]))
	return out


func get_pack(pack_id: String) -> Dictionary:
	for record: Dictionary in _packs:
		if String(record["packId"]) == pack_id:
			return record.duplicate(true)
	return {}


func has_pack(pack_id: String) -> bool:
	return not get_pack(pack_id).is_empty()


func get_pack_count() -> int:
	return _packs.size()


## `[{path, packId, reasons}]`. Kept, not dropped -- see the class comment.
func get_rejections() -> Array:
	return _rejections.duplicate(true)


func get_warnings() -> Array:
	return _warnings.duplicate(true)


## Which packs the family may use, given an entitlement service (anything with
## `is_active`). Read-only; gates nothing by itself.
func entitled_packs(entitlements: Object) -> Array:
	var out: Array = []
	if entitlements == null or not entitlements.has_method("is_active"):
		return out
	for record: Dictionary in _packs:
		if bool(entitlements.call("is_active", String(record["entitlementId"]))):
			out.append(record.duplicate(true))
	return out


## The union of the mission ids in every entitled pack.
##
## NOT "the missions the child may play": a mission that appears in no pack at all
## is not in this list and is not restricted either. See the class comment.
func entitled_missions(entitlements: Object) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for record: Dictionary in entitled_packs(entitlements):
		for mission_id: Variant in (record["missions"] as Array):
			if not out.has(String(mission_id)):
				out.append(String(mission_id))
	return out


## Lines for a QA report or a build log. Never for a child's screen.
func describe() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for record: Dictionary in _packs:
		out.append("accepted: " + ContentPack.summary_line(record))
	for rejection: Dictionary in _rejections:
		out.append("rejected: %s -- %s" % [
			String(rejection.get("path", "?")),
			" | ".join(PackedStringArray(rejection.get("reasons", []))),
		])
	return out


# -- internals -----------------------------------------------------------------

func _reject(path: String, pack_id: String, reasons: Variant) -> void:
	var list: Array = []
	var kind: int = typeof(reasons)
	if kind == TYPE_ARRAY or kind == TYPE_PACKED_STRING_ARRAY:
		for reason: Variant in reasons:
			list.append(String(reason))
	_rejections.append({"path": path, "packId": pack_id, "reasons": list})


## Data only: `FileAccess` + `JSON`, never `load()`. A pack cannot be code.
static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text)
