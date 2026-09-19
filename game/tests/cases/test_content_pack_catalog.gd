extends RefCounted

## THE PACK SHELF: local files, checked on the way in, and nothing else.
##
## This case asserts three things about the shipped shelf and one thing about the
## code that reads it.
##
##   1. **What ships is exactly one pack** -- Free Starter -- and it is accepted
##      cleanly by the real mission catalogue, with no rejections and no warnings.
##      A rejection in the shipped build would mean the free tier was not loading.
##   2. **A rejected pack is reported, not vanished.** A build one release behind
##      the content drop must be able to say WHY it refused a pack; on a device
##      with no console, a silent disappearance is undiagnosable.
##   3. **Entitlement decides which packs a family may use**, and the answer for
##      the shipped shelf is "the free one", from a service that cannot buy
##      anything.
##
## And the structural one: **the pack loader cannot fetch or execute.** Its source
## is scanned for `load()`, `ResourceLoader`, `HTTPRequest` and URLs, because that
## is the guarantee "content packs are local data" actually rests on. A pack read
## with `FileAccess` + `JSON.parse_string()` can only ever be a list of ids; a pack
## read with `load()` could be a scene with a script attached.

const Catalog := preload("res://scripts/content_packs/content_pack_catalog.gd")
const EntitlementService := preload("res://scripts/entitlement/entitlement_service.gd")
const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")
const FreeStarter := preload("res://scripts/entitlement/free_starter.gd")

## Scanned for the no-fetch, no-execute guarantee.
const PACK_SOURCES: Array[String] = [
	"res://scripts/content_packs/content_pack.gd",
	"res://scripts/content_packs/content_pack_validator.gd",
	"res://scripts/content_packs/content_pack_catalog.gd",
	"res://scripts/content_packs/game_version.gd",
]

## None of these belongs anywhere near content that arrives as a file.
const FORBIDDEN_IN_PACK_LAYER: Array[String] = [
	"HTTPRequest", "HTTPClient", "WebSocketPeer", "StreamPeerTCP", "PacketPeerUDP",
	"ResourceLoader", "PackedScene", "GDScript", "OS.execute", "OS.shell_open",
	"http://", "https://",
]


## An entitlement service that grants nothing at all -- not even Free Starter -- to
## prove that the catalogue really does ask, rather than assuming.
class GrantsNothing extends RefCounted:
	func is_active(_entitlement_id: String) -> bool:
		return false


func test_name() -> String:
	return "content_pack_catalog"


func run():
	var failures: Array = []
	failures.append_array(_test_the_shipped_shelf())
	failures.append_array(_test_rejections_are_kept())
	failures.append_array(_test_entitlement_decides())
	failures.append_array(_test_the_loader_cannot_fetch_or_execute())
	failures.append_array(_test_the_index_is_the_only_door())
	return failures


# ---------------------------------------------------------------------------

func _test_the_shipped_shelf():
	var failures: Array = []
	var catalog: Object = Catalog.new()
	catalog.load_all(_library())

	var rejections: Array = catalog.get_rejections()
	for rejection: Dictionary in rejections:
		failures.append(
			("the shipped build REJECTED its own content pack %s: %s. The free tier would be "
			+ "running on free_starter.gd's fallback, which is a safety net and not a plan.")
			% [String(rejection.get("path", "?")),
					" | ".join(PackedStringArray(rejection.get("reasons", [])))])
	for warning: Variant in catalog.get_warnings():
		failures.append("loading the shipped packs warned: %s" % str(warning))

	if catalog.get_pack_count() != 1:
		failures.append("the shipped shelf holds %d pack(s); exactly one (Free Starter) is expected"
				% catalog.get_pack_count())
	if not catalog.has_pack("freeStarter"):
		failures.append("the shipped shelf has no 'freeStarter' pack")

	var pack: Dictionary = catalog.get_pack("freeStarter")
	if pack.is_empty():
		return failures
	if String(pack.get("entitlementId", "")) != EntitlementIds.FREE_STARTER:
		failures.append("the free pack is gated behind '%s'" % String(pack.get("entitlementId", "")))
	if String(pack.get("sourcePath", "")) != FreeStarter.PACK_PATH:
		failures.append("the loaded pack's sourcePath is '%s', expected %s"
				% [String(pack.get("sourcePath", "")), FreeStarter.PACK_PATH])
	for mission_id: String in FreeStarter.missions():
		if not (pack["missions"] as Array).has(mission_id):
			failures.append("the loaded free pack is missing mission '%s'" % mission_id)

	# The accessors must not hand out the internal arrays.
	var copy: Dictionary = catalog.get_pack("freeStarter")
	(copy["missions"] as Array).clear()
	if (catalog.get_pack("freeStarter")["missions"] as Array).is_empty():
		failures.append("get_pack() returns a live reference; a caller can empty the catalogue")
	if not catalog.get_pack("nothingLikeThis").is_empty():
		failures.append("get_pack() invented a pack that does not exist")
	return failures


## A pack this build cannot run is a reported rejection, never a silent gap.
func _test_rejections_are_kept():
	var failures: Array = []
	var catalog: Object = Catalog.new()
	# The shipped pack, judged by a build that is older than it needs.
	catalog.load_all(_library(), "0.0.1")

	if catalog.get_pack_count() != 0:
		failures.append("a build older than the pack's requiredGameVersion loaded it anyway")
	var rejections: Array = catalog.get_rejections()
	if rejections.size() != 1:
		failures.append("expected exactly one reported rejection, got %d" % rejections.size())
		return failures
	var reasons: PackedStringArray = PackedStringArray(rejections[0].get("reasons", []))
	if reasons.is_empty():
		failures.append(
			"a pack was refused with no reason recorded. On a device with no console, 'the pack is "
			+ "simply not there' is the one failure nobody can diagnose.")
	var joined: String = " ".join(reasons)
	if not joined.contains("0.1.0") or not joined.contains("0.0.1"):
		failures.append("the rejection reason names neither version: %s" % joined)
	if String(rejections[0].get("packId", "")) != "freeStarter":
		failures.append("the rejection does not say which pack it was: %s" % str(rejections[0]))
	if not " ".join(catalog.describe()).contains("rejected"):
		failures.append("describe() does not report the rejection")
	return failures


func _test_entitlement_decides():
	var failures: Array = []
	var catalog: Object = Catalog.new()
	catalog.load_all(_library())

	var entitlements: Object = EntitlementService.new()
	var entitled: Array = catalog.entitled_packs(entitlements)
	if entitled.size() != 1:
		failures.append("the default offline service entitles %d of the shipped packs, expected 1"
				% entitled.size())
	var missions: PackedStringArray = catalog.entitled_missions(entitlements)
	for mission_id: String in ["imHungry", "snackTime"]:
		if not missions.has(mission_id):
			failures.append("'%s' is not in the entitled mission list; it is free content"
					% mission_id)

	# A service that grants nothing entitles nothing -- so the catalogue really is
	# asking rather than assuming.
	var nothing: Object = GrantsNothing.new()
	if not catalog.entitled_packs(nothing).is_empty():
		failures.append("a service that grants nothing still entitled a pack")
	if not catalog.entitled_missions(nothing).is_empty():
		failures.append("a service that grants nothing still entitled missions")

	# No service at all: nothing, and no crash.
	if not catalog.entitled_packs(null).is_empty():
		failures.append("entitled_packs(null) returned packs")
	return failures


func _test_the_loader_cannot_fetch_or_execute():
	var failures: Array = []
	var scanned: int = 0
	for path: String in PACK_SOURCES:
		var code: String = _code_of(_read(path))
		if code.strip_edges().length() < 200:
			failures.append("%s stripped to almost nothing; this scan would pass vacuously" % path)
			continue
		scanned += 1
		for token: String in FORBIDDEN_IN_PACK_LAYER:
			if code.contains(token):
				failures.append(
					("%s references %s in executable code. Content packs arrive as FILES, and the "
					+ "only thing that makes them safe to ship weekly is that they are read as DATA "
					+ "-- FileAccess and JSON.parse_string, never load() and never over a network. "
					+ "A pack read with a resource loader could carry a script.")
					% [path, token])
		# `load(` is checked separately: `preload(` is fine and contains it.
		if code.replace("preload(", "").contains("load("):
			failures.append("%s calls load() at runtime; a pack file must never be loaded as a "
					% path + "resource")
	if scanned < PACK_SOURCES.size():
		failures.append("only %d of %d pack-layer files were scanned" % [scanned, PACK_SOURCES.size()])
	return failures


## Packs come from one directory, named by one index. Nothing else is a pack.
func _test_the_index_is_the_only_door():
	var failures: Array = []
	var catalog: Object = Catalog.new()
	catalog.load_all(_library())

	# A path outside the pack directory is refused even if it exists and parses.
	catalog.call("_load_one", "res://content/index.json", _library(), "0.1.0")
	var rejections: Array = catalog.get_rejections()
	if rejections.is_empty():
		failures.append("a pack path outside %s/ was accepted" % Catalog.PACKS_DIR)
	elif not " ".join(PackedStringArray(rejections[0].get("reasons", []))).contains("outside"):
		failures.append("the out-of-directory rejection does not say why: %s" % str(rejections[0]))

	# A missing file is a reported rejection, not a crash.
	var missing: Object = Catalog.new()
	missing.call("_load_one", "res://content/packs/does_not_exist.json", _library(), "0.1.0")
	if missing.get_rejections().is_empty():
		failures.append("a missing pack file was not reported")
	if missing.get_pack_count() != 0:
		failures.append("a missing pack file produced a pack")

	# The index itself is data, and it names its files.
	var index: Variant = JSON.parse_string(_read(Catalog.INDEX_PATH))
	if typeof(index) != TYPE_DICTIONARY:
		failures.append("%s is missing or is not a JSON object" % Catalog.INDEX_PATH)
		return failures
	var listed: Variant = (index as Dictionary).get(Catalog.INDEX_FIELD, null)
	if typeof(listed) != TYPE_ARRAY or (listed as Array).is_empty():
		failures.append("%s lists no pack files" % Catalog.INDEX_PATH)
		return failures
	for entry: Variant in (listed as Array):
		var path: String = String(entry)
		if not path.begins_with(Catalog.PACKS_DIR + "/"):
			failures.append("%s names '%s', which is outside the pack directory"
					% [Catalog.INDEX_PATH, path])
		if not FileAccess.file_exists(path):
			failures.append("%s names '%s', which does not exist" % [Catalog.INDEX_PATH, path])
	# Offline-first: no bundled content file may name a remote resource.
	var text: String = _read(Catalog.INDEX_PATH).to_lower() + _read(FreeStarter.PACK_PATH).to_lower()
	for marker: String in ["http://", "https://", "ftp://", "ws://"]:
		if text.contains(marker):
			failures.append("a shipped pack file contains a network URL (%s)" % marker)
	return failures


# -- helpers ---------------------------------------------------------------------

func _library() -> Object:
	var library: Object = load("res://scripts/content/content_library.gd").new()
	library.call("load_all")
	return library


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Executable code only: comments removed, string literals blanked. Same technique
## as `test_architecture_guard.gd`, and for the same reason -- a doc comment that
## correctly says "never HTTPRequest" must not fail the test for saying it.
static func _code_of(text: String) -> String:
	var code: String = ""
	for raw_line: String in text.split("\n"):
		code += _strip_line(raw_line) + "\n"
	return code


static func _strip_line(line: String) -> String:
	var out: String = ""
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if quote.is_empty():
			if character == "#":
				break
			if character == "\"" or character == "'":
				quote = character
			else:
				out += character
		else:
			if character == "\\":
				index += 1
			elif character == quote:
				quote = ""
		index += 1
	return out
