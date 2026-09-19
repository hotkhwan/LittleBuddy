extends RefCounted

## THE PACK GATE. What gets in, what gets refused, and why.
##
## The two refusals the brief asks for are the first two tests here, and they are
## the two that protect a child rather than a developer:
##
##   * **a pack that needs a newer build** -- rejected whole. Half-loading a pack
##     authored against logic this build does not have is how a four-year-old ends
##     up in a mission with no ending.
##   * **a pack naming a mission that does not exist** -- rejected. A pack is a
##     CATALOGUE; the mission logic ships in the build and is tested there. This is
##     the assertion that keeps the weekly content drop from being able to invent
##     behaviour, which is the entire reason the catalogue and the logic are
##     separate things.
##
## The rest is the same instinct: no pack may name a URL, a `res://` path or a
## file, so "packs are local data, never remote and never executable" is a
## property the FORMAT has rather than a promise a document makes.
##
## `GameVersion.BUILD` is also checked against the `VERSION` file at the
## repository root, the same way `test_version.gd` checks `export_presets.cfg` and
## `CHANGELOG.md`. A pack gate that compares against a version the repository no
## longer has is a gate that lets the wrong packs through, silently.

const ContentPack := preload("res://scripts/content_packs/content_pack.gd")
const Validator := preload("res://scripts/content_packs/content_pack_validator.gd")
const GameVersion := preload("res://scripts/content_packs/game_version.gd")
const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

## The missions this build implements, for the tests that do not need the real
## library. Both are real ids (see `content/missions/missions.json`).
const KNOWN_MISSIONS: Array[String] = ["imHungry", "snackTime"]


func test_name() -> String:
	return "content_pack_validator"


func run():
	var failures: Array = []
	failures.append_array(_test_build_version_is_the_version_of_record())
	failures.append_array(_test_semver())
	failures.append_array(_test_a_good_pack_is_accepted())
	failures.append_array(_test_a_pack_from_the_future_is_rejected())
	failures.append_array(_test_a_missing_mission_is_rejected())
	failures.append_array(_test_an_unknown_entitlement_is_rejected())
	failures.append_array(_test_a_pack_can_never_name_a_file_or_a_url())
	failures.append_array(_test_the_shape_rules())
	failures.append_array(_test_normalising())
	failures.append_array(_test_unknown_fields_are_a_warning())
	failures.append_array(_test_the_metadata_fields_are_exactly_the_nine())
	return failures


# ---------------------------------------------------------------------------

## The compiled-in build version must be the repository's version of record.
func _test_build_version_is_the_version_of_record():
	var failures: Array = []
	var recorded: String = _read_root("VERSION").strip_edges()
	if recorded.is_empty():
		failures.append("could not read VERSION at the repository root (looked in %s); the pack "
				% _root_path("VERSION") + "gate has nothing to be measured against")
		return failures
	if GameVersion.BUILD != recorded:
		failures.append(
			("game_version.gd says BUILD = '%s' but VERSION says '%s'. Content packs are gated on "
			+ "BUILD, so a stale value here means packs are accepted or refused against a version "
			+ "this repository does not have. Bump both.") % [GameVersion.BUILD, recorded])
	if not GameVersion.is_valid(GameVersion.BUILD):
		failures.append("BUILD '%s' is not MAJOR.MINOR.PATCH" % GameVersion.BUILD)
	return failures


func _test_semver():
	var failures: Array = []

	if GameVersion.parse("1.2.3") != [1, 2, 3]:
		failures.append("parse('1.2.3') = %s" % str(GameVersion.parse("1.2.3")))
	for bad: Variant in ["", "1", "1.2", "1.2.3.4", "v1.2.3", "1.2.x", "0.2.0-beta1",
			null, 1.2, [], {}, "  ", "-1.0.0"]:
		if GameVersion.is_valid(bad):
			failures.append("is_valid(%s) should be false" % str(bad))

	var ordered: Array = [
		["0.1.0", "0.1.0", 0],
		["0.1.0", "0.1.1", -1],
		["0.1.1", "0.1.0", 1],
		["0.1.9", "0.2.0", -1],
		["0.9.9", "1.0.0", -1],
		["1.0.0", "0.9.9", 1],
		["0.10.0", "0.9.0", 1],   # not a string comparison
		["10.0.0", "9.0.0", 1],
	]
	for row: Variant in ordered:
		var pair: Array = row
		var got: int = GameVersion.compare(String(pair[0]), String(pair[1]))
		if got != int(pair[2]):
			failures.append("compare('%s', '%s') = %d, expected %d"
					% [String(pair[0]), String(pair[1]), got, int(pair[2])])

	if GameVersion.is_newer_than("0.1.0", "0.1.0"):
		failures.append("a pack requiring exactly this build must be accepted, not rejected")
	if not GameVersion.is_newer_than("0.2.0", "0.1.0"):
		failures.append("0.2.0 must be newer than 0.1.0")
	if GameVersion.is_newer_than("0.0.9", "0.1.0"):
		failures.append("an older requirement must never count as newer")
	return failures


func _test_a_good_pack_is_accepted():
	var failures: Array = []
	var problems: PackedStringArray = Validator.validate(_good_pack(), KNOWN_MISSIONS, "0.1.0")
	for problem: String in problems:
		failures.append("a valid pack was rejected: %s" % problem)
	if not Validator.is_valid(_good_pack(), KNOWN_MISSIONS, "0.1.0"):
		failures.append("is_valid() disagrees with validate() on a valid pack")

	# The real library is a valid catalogue too, not just an array.
	var library: Object = load("res://scripts/content/content_library.gd").new()
	library.call("load_all")
	if not Validator.is_valid(_good_pack(), library, "0.1.0"):
		failures.append("a valid pack was rejected when the catalogue was ContentLibrary; the "
				+ "duck-typed catalogue argument is broken")

	# A pack with no missions at all is fine -- a rooms-only or audio-only pack is a
	# legitimate drop, and it needs no catalogue to check.
	var no_missions: Dictionary = _good_pack()
	no_missions["missions"] = []
	if not Validator.is_valid(no_missions, null, "0.1.0"):
		failures.append("a pack with no missions was rejected: %s"
				% str(Validator.validate(no_missions, null, "0.1.0")))
	return failures


## Rejection 1.
func _test_a_pack_from_the_future_is_rejected():
	var failures: Array = []
	for required: String in ["0.1.1", "0.2.0", "1.0.0", "99.0.0"]:
		var pack: Dictionary = _good_pack()
		pack["requiredGameVersion"] = required
		var problems: PackedStringArray = Validator.validate(pack, KNOWN_MISSIONS, "0.1.0")
		if problems.is_empty():
			failures.append(
				("a pack requiring game version %s was ACCEPTED by a 0.1.0 build. It was authored "
				+ "against logic this build does not have; accepting it is how a child reaches a "
				+ "mission that cannot finish.") % required)
			continue
		if not _mentions(problems, required):
			failures.append("the rejection for requiredGameVersion %s does not name the version: %s"
					% [required, str(problems)])

	# Exactly the build version is fine. Older is fine.
	for required: String in ["0.1.0", "0.0.1"]:
		var pack: Dictionary = _good_pack()
		pack["requiredGameVersion"] = required
		if not Validator.is_valid(pack, KNOWN_MISSIONS, "0.1.0"):
			failures.append("a pack requiring %s was rejected by a 0.1.0 build: %s"
					% [required, str(Validator.validate(pack, KNOWN_MISSIONS, "0.1.0"))])

	# Unparseable is a rejection, never "treat as zero and carry on".
	for required: Variant in ["", "soon", "1.0", null, 2, "0.2", "v0.1.0"]:
		var pack: Dictionary = _good_pack()
		pack["requiredGameVersion"] = required
		if Validator.is_valid(pack, KNOWN_MISSIONS, "0.1.0"):
			failures.append("a pack with requiredGameVersion %s was accepted" % str(required))
	return failures


## Rejection 2.
func _test_a_missing_mission_is_rejected():
	var failures: Array = []

	var pack: Dictionary = _good_pack()
	pack["missions"] = ["feedTheDucks"]
	var problems: PackedStringArray = Validator.validate(pack, KNOWN_MISSIONS, "0.1.0")
	if problems.is_empty():
		failures.append(
			"a pack naming the mission 'feedTheDucks', which this build does not implement, was "
			+ "ACCEPTED. A content pack is a CATALOGUE: mission and mini-game logic ships in the "
			+ "build and is tested there, and a pack may only list ids that already exist. This is "
			+ "the separation the whole content-pack design is for.")
	elif not _mentions(problems, "feedTheDucks"):
		failures.append("the rejection does not name the missing mission: %s" % str(problems))

	# One good id does not excuse one bad id.
	var mixed: Dictionary = _good_pack()
	mixed["missions"] = ["imHungry", "feedTheDucks"]
	if Validator.is_valid(mixed, KNOWN_MISSIONS, "0.1.0"):
		failures.append("a pack with one real and one imaginary mission was accepted whole")

	# The real content library gives the same answer.
	var library: Object = load("res://scripts/content/content_library.gd").new()
	library.call("load_all")
	if Validator.is_valid(pack, library, "0.1.0"):
		failures.append("ContentLibrary accepted a mission it does not have")
	if not Validator.is_valid(_good_pack(), library, "0.1.0"):
		failures.append("ContentLibrary rejected missions it does have")

	# No catalogue at all cannot verify anything, so a pack with missions is
	# rejected rather than trusted.
	if Validator.is_valid(_good_pack(), null, "0.1.0"):
		failures.append("a pack's mission list was accepted with no catalogue to check it against; "
				+ "unverifiable must mean rejected")
	# ...and a catalogue that is junk is not a catalogue.
	for catalog: Variant in [42, "imHungry", {}, EntitlementIds.new()]:
		if Validator.is_valid(_good_pack(), catalog, "0.1.0"):
			failures.append("a non-catalogue (%s) was treated as able to confirm a mission"
					% str(catalog))
	return failures


func _test_an_unknown_entitlement_is_rejected():
	var failures: Array = []
	for id: Variant in ["", "premium", "family_club", "FamilyClub", null, 3, "freeStarterPlus"]:
		var pack: Dictionary = _good_pack()
		pack["entitlementId"] = id
		if Validator.is_valid(pack, KNOWN_MISSIONS, "0.1.0"):
			failures.append("a pack gated behind the unknown entitlement %s was accepted; it would "
					% str(id) + "be content nobody can ever be granted")
	for id: String in EntitlementIds.known_ids():
		var pack: Dictionary = _good_pack()
		pack["entitlementId"] = id
		if not Validator.is_valid(pack, KNOWN_MISSIONS, "0.1.0"):
			failures.append("a pack gated behind the known entitlement '%s' was rejected: %s"
					% [id, str(Validator.validate(pack, KNOWN_MISSIONS, "0.1.0"))])
	return failures


## The format itself cannot express a download or a script.
func _test_a_pack_can_never_name_a_file_or_a_url():
	var failures: Array = []
	var poison: Array = [
		"https://example.com/pack.zip",
		"http://example.com",
		"res://scripts/gameplay/mission_runner.gd",
		"user://profile.json",
		"../../etc/passwd",
		"evil.gd",
		"pack.zip",
		"libthing.dylib",
		"www.example.com",
	]
	for value: String in poison:
		# In a string field...
		var in_field: Dictionary = _good_pack()
		in_field["packId"] = value
		if Validator.is_valid(in_field, KNOWN_MISSIONS, "0.1.0"):
			failures.append("a pack whose packId was '%s' was accepted" % value)
		# ...and in a list field.
		var in_list: Dictionary = _good_pack()
		in_list["audio"] = [value]
		if Validator.is_valid(in_list, KNOWN_MISSIONS, "0.1.0"):
			failures.append(
				("a pack listing '%s' was accepted. A content pack may only ever be a list of ids: "
				+ "nothing fetchable, nothing runnable. Packs are packaged locally in the build.")
				% value)
	return failures


func _test_the_shape_rules():
	var failures: Array = []

	# Not a dictionary at all.
	for raw: Variant in [null, "", "pack", 7, [], [{}]]:
		if Validator.is_valid(raw, KNOWN_MISSIONS, "0.1.0"):
			failures.append("%s was accepted as a content pack" % str(raw))

	# packId
	for bad: Variant in ["", "Farm", "farm pack", "farm-pack", "farm_pack", "1farm", null, 5]:
		var pack: Dictionary = _good_pack()
		pack["packId"] = bad
		if Validator.is_valid(pack, KNOWN_MISSIONS, "0.1.0"):
			failures.append("packId %s was accepted" % str(bad))

	# version
	for bad: Variant in [0, -1, "one", null, {}]:
		var pack: Dictionary = _good_pack()
		pack["version"] = bad
		if Validator.is_valid(pack, KNOWN_MISSIONS, "0.1.0"):
			failures.append("version %s was accepted" % str(bad))

	# An empty pack gives the family nothing.
	var empty: Dictionary = _good_pack()
	for field: String in ContentPack.LIST_FIELDS:
		empty[field] = []
	if Validator.is_valid(empty, KNOWN_MISSIONS, "0.1.0"):
		failures.append("a pack listing nothing at all was accepted")

	# The audio ids this project actually uses are snake_case, so the payload rule
	# has to allow an underscore -- while packId still may not have one.
	var audio: Dictionary = _good_pack()
	audio["audio"] = ["success_chime", "star_earned"]
	if not Validator.is_valid(audio, KNOWN_MISSIONS, "0.1.0"):
		failures.append("snake_case audio ids were rejected: %s"
				% str(Validator.validate(audio, KNOWN_MISSIONS, "0.1.0")))
	return failures


func _test_normalising():
	var failures: Array = []
	var record: Dictionary = ContentPack.from_dict({
		"packId": "  farmFriends  ",
		"version": 2.0,
		"missions": ["imHungry", "imHungry", 7, null, [], "  snackTime  ", ""],
		"rooms": "bedroom",
		"outfits": null,
	})
	if String(record["packId"]) != "farmFriends":
		failures.append("packId was not trimmed: '%s'" % String(record["packId"]))
	if int(record["version"]) != 2:
		failures.append("a JSON float version did not normalise to an int")
	if Array(record["missions"]) != ["imHungry", "snackTime"]:
		failures.append("mission list normalising dropped or kept the wrong entries: %s"
				% str(record["missions"]))
	if Array(record["rooms"]) != []:
		failures.append("a string where a list belongs should normalise to an empty list")
	if Array(record["outfits"]) != []:
		failures.append("null where a list belongs should normalise to an empty list")
	for field: String in ContentPack.FIELDS:
		if not record.has(field):
			failures.append("from_dict() did not produce the field '%s'" % field)

	# Nothing in, all nine fields out, nothing crashes.
	var blank: Dictionary = ContentPack.from_dict(null)
	if blank.size() != ContentPack.FIELDS.size():
		failures.append("from_dict(null) produced %d fields, expected %d"
				% [blank.size(), ContentPack.FIELDS.size()])
	if ContentPack.payload_size(blank) != 0:
		failures.append("an empty record reports a payload")
	if ContentPack.payload_size(ContentPack.from_dict(_good_pack())) < 3:
		failures.append("payload_size() undercounts a real pack")
	if not ContentPack.summary_line(ContentPack.from_dict(_good_pack())).contains("farmFriends"):
		failures.append("summary_line() does not name the pack")
	return failures


func _test_unknown_fields_are_a_warning():
	var failures: Array = []
	var pack: Dictionary = _good_pack()
	pack["weeklyTheme"] = "farm"
	if not Validator.is_valid(pack, KNOWN_MISSIONS, "0.1.0"):
		failures.append(
			"an unknown field turned into a rejection. A pack authored for a later build may carry "
			+ "a field this one does not read; dropping it is right, refusing the pack is not.")
	var warnings: PackedStringArray = Validator.warnings(pack)
	if not _mentions(warnings, "weeklyTheme"):
		failures.append("the ignored field was dropped silently: %s" % str(warnings))
	if not Validator.warnings(_good_pack()).is_empty():
		failures.append("a clean pack produced warnings: %s" % str(Validator.warnings(_good_pack())))
	return failures


## The nine fields are the contract. Adding or losing one is a schema change and
## has to be a deliberate, visible act.
func _test_the_metadata_fields_are_exactly_the_nine():
	var failures: Array = []
	var expected: Array = [
		"packId", "version", "requiredGameVersion",
		"missions", "rooms", "characters", "outfits", "audio",
		"entitlementId",
	]
	if Array(ContentPack.FIELDS) != expected:
		failures.append("ContentPack.FIELDS is %s; the agreed metadata is %s"
				% [str(ContentPack.FIELDS), str(expected)])
	for field: String in ContentPack.LIST_FIELDS:
		if not ContentPack.FIELDS.has(field):
			failures.append("LIST_FIELDS names '%s', which is not a pack field" % field)
	return failures


# -- helpers ---------------------------------------------------------------------

## A pack that must always be accepted, so every other test can change exactly one
## thing about it and see the gate react to that one thing.
func _good_pack() -> Dictionary:
	return {
		"packId": "farmFriends",
		"version": 1,
		"requiredGameVersion": "0.1.0",
		"missions": ["imHungry", "snackTime"],
		"rooms": ["bedroom"],
		"characters": ["buddy"],
		"outfits": [],
		"audio": ["success_chime"],
		"entitlementId": EntitlementIds.FREE_STARTER,
	}


func _mentions(lines: PackedStringArray, needle: String) -> bool:
	for line: String in lines:
		if line.contains(needle):
			return true
	return false


## The repository root is one level above `res://` (see `test_version.gd`).
func _root_path(file_name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(file_name).simplify_path()


func _read_root(file_name: String) -> String:
	var path: String = _root_path(file_name)
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
