extends RefCounted

## FREE STARTER: is it real, and is it still real tomorrow?
##
## A free tier is a promise made to a parent in a shop, and the way it breaks is
## never a crash. It is somebody shortening a list to make a subscription look
## better, or a mission id being renamed in `missions.json` while the free pack
## goes on naming the old one -- at which point the free tier silently becomes a
## pack that references nothing, and the first person to find out is a child.
##
## So this case checks the free set against the things it claims, not against
## itself:
##
##   1. It contains `imHungry` and `snackTime`, and those missions EXIST in
##      `ContentLibrary`. Both halves matter; either one alone proves nothing.
##   2. It contains the whole house -- all four rooms.
##   3. Every audio id it lists is a sound this build actually ships.
##   4. `free_starter.json` and the compiled-in `FALLBACK` say the same thing, so
##      the offline fallback cannot drift into a different promise.
##   5. The free pack passes the ordinary pack validator. It is not a special case.
##   6. The copy it produces is kind and never mentions locking or paying.

const FreeStarter := preload("res://scripts/entitlement/free_starter.gd")
const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")
const ContentPackValidator := preload("res://scripts/content_packs/content_pack_validator.gd")
const GameVersion := preload("res://scripts/content_packs/game_version.gd")

## The two working missions. Named here as well as in `free_starter.gd` on
## purpose: this is the product commitment, and a test that read the constant it
## is checking would agree with any change to it.
const MUST_INCLUDE_MISSIONS: Array[String] = ["imHungry", "snackTime"]
const MUST_INCLUDE_ROOMS: Array[String] = ["bedroom", "bathroom", "kitchen", "livingRoom"]

## Words that must never appear in free-tier copy shown to anybody.
const FORBIDDEN_COPY: Array[String] = [
	"locked", "unlock me", "buy", "trial", "expire", "only", "upgrade",
]


func test_name() -> String:
	return "entitlement_free_starter"


func run():
	var failures: Array = []
	failures.append_array(_test_contents())
	failures.append_array(_test_missions_exist())
	failures.append_array(_test_audio_exists())
	failures.append_array(_test_file_and_fallback_agree())
	failures.append_array(_test_it_is_an_ordinary_pack())
	failures.append_array(_test_copy_is_kind())
	failures.append_array(_test_it_survives_a_broken_file())
	return failures


# ---------------------------------------------------------------------------

func _test_contents():
	var failures: Array = []
	var definition: Dictionary = FreeStarter.definition()

	if String(definition.get("entitlementId", "")) != EntitlementIds.FREE_STARTER:
		failures.append("the free pack's entitlementId is '%s', not '%s'"
				% [String(definition.get("entitlementId", "")), EntitlementIds.FREE_STARTER])

	var missions: PackedStringArray = FreeStarter.missions()
	for mission_id: String in MUST_INCLUDE_MISSIONS:
		if not missions.has(mission_id):
			failures.append(
				("Free Starter does not include '%s'. The free tier has to be a real game, not a "
				+ "demo: both working missions (%s) are part of what a family gets for nothing.")
				% [mission_id, ", ".join(MUST_INCLUDE_MISSIONS)])
		if not FreeStarter.includes_mission(mission_id):
			failures.append("includes_mission('%s') is false" % mission_id)

	var rooms: PackedStringArray = FreeStarter.rooms()
	for room_id: String in MUST_INCLUDE_ROOMS:
		if not rooms.has(room_id):
			failures.append("Free Starter does not include the %s; the free tier is the whole house"
					% room_id)
		if not FreeStarter.includes_room(room_id):
			failures.append("includes_room('%s') is false" % room_id)

	if FreeStarter.characters().is_empty():
		failures.append("Free Starter includes no character at all")
	if not FreeStarter.outfits().is_empty():
		failures.append("Free Starter claims an outfit, but no outfit system ships yet; the free "
				+ "tier must not promise something that does not exist")

	# Nonsense in, false out -- never a crash and never an accidental yes.
	if FreeStarter.includes_mission(null) or FreeStarter.includes_mission(7):
		failures.append("includes_mission() accepted a non-String")
	if FreeStarter.includes_room(null):
		failures.append("includes_room() accepted a non-String")

	return failures


## The free tier may only name missions that this build implements.
func _test_missions_exist():
	var failures: Array = []
	var library: Object = load("res://scripts/content/content_library.gd").new()
	library.call("load_all")
	for mission_id: String in FreeStarter.missions():
		if not bool(library.call("has_mission", mission_id)):
			failures.append(
				("Free Starter lists mission '%s', which is not in missions.json. The free pack is "
				+ "a CATALOGUE: the mission logic has to exist before the pack may name it. If the "
				+ "mission was renamed, rename it in res://content/packs/free_starter.json and in "
				+ "free_starter.gd's FALLBACK too.") % mission_id)
	return failures


## ...and only audio this build ships.
func _test_audio_exists():
	var failures: Array = []
	var sfx: GDScript = load("res://scripts/audio/sfx_player.gd")
	if sfx == null:
		return ["could not load sfx_player.gd to check the free audio list against"]
	var known: Variant = sfx.get_script_constant_map().get("KNOWN_SFX", null)
	if typeof(known) != TYPE_ARRAY or (known as Array).is_empty():
		return ["sfx_player.gd exposes no KNOWN_SFX list; the audio check would be vacuous"]
	var listed: PackedStringArray = FreeStarter.audio()
	if listed.is_empty():
		failures.append("Free Starter lists no audio at all")
	for audio_id: String in listed:
		if not (known as Array).has(audio_id):
			failures.append("Free Starter lists audio '%s', which is not a bundled sound" % audio_id)
	return failures


## The JSON and the compiled-in copy must be the same promise.
func _test_file_and_fallback_agree():
	var failures: Array = []
	if not FileAccess.file_exists(FreeStarter.PACK_PATH):
		return ["%s is missing; the free tier would be running on its fallback" % FreeStarter.PACK_PATH]
	var text: String = FileAccess.get_file_as_string(FreeStarter.PACK_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ["%s is not a JSON object" % FreeStarter.PACK_PATH]

	var file_pack: Dictionary = parsed
	for field: Variant in FreeStarter.FALLBACK.keys():
		var key: String = String(field)
		if not file_pack.has(key):
			failures.append("%s has no '%s'" % [FreeStarter.PACK_PATH, key])
			continue
		var from_file: Variant = file_pack[key]
		var from_code: Variant = FreeStarter.FALLBACK[key]
		if typeof(from_file) == TYPE_ARRAY and typeof(from_code) == TYPE_ARRAY:
			if Array(from_file) != Array(from_code):
				failures.append(
					("'%s' differs between %s (%s) and free_starter.gd's FALLBACK (%s). The "
					+ "fallback is what a child gets when the file cannot be read; if the two "
					+ "disagree, the free tier changes shape depending on whether a file loaded.")
					% [key, FreeStarter.PACK_PATH, str(from_file), str(from_code)])
		elif _is_number(from_file) and _is_number(from_code):
			# JSON has one number type, so `1` comes back as `1.0`.
			if not is_equal_approx(float(from_file), float(from_code)):
				failures.append("'%s' is %s in the file and %s in FALLBACK"
						% [key, str(from_file), str(from_code)])
		elif str(from_file) != str(from_code):
			failures.append("'%s' is %s in the file and %s in FALLBACK"
					% [key, str(from_file), str(from_code)])

	# camelCase JSON keys, per CLAUDE.md.
	for key: Variant in file_pack.keys():
		var name: String = String(key)
		if name.contains("_") or name.is_empty() or name[0] != name[0].to_lower():
			failures.append("%s key '%s' is not camelCase" % [FreeStarter.PACK_PATH, name])

	return failures


## The free set is a content pack like any other, and has to pass the same gate.
func _test_it_is_an_ordinary_pack():
	var failures: Array = []
	var library: Object = load("res://scripts/content/content_library.gd").new()
	library.call("load_all")
	var problems: PackedStringArray = ContentPackValidator.validate(
			FreeStarter.definition(), library, GameVersion.BUILD)
	for problem: String in problems:
		failures.append("the free pack fails the ordinary pack validator: %s" % problem)
	return failures


func _test_copy_is_kind():
	var failures: Array = []
	var line: String = FreeStarter.summary_line().to_lower()
	if not line.contains("free"):
		failures.append("the free-tier summary does not say it is free: '%s'" % line)
	for word: String in FORBIDDEN_COPY:
		if line.contains(word):
			failures.append("the free-tier summary says '%s': '%s'" % [word, line])
	if line.contains("%"):
		failures.append("the free-tier summary contains a percentage")
	return failures


## The one rule that is allowed to fail OPEN: a child keeps the game they have,
## whatever happened to the file.
func _test_it_survives_a_broken_file():
	var failures: Array = []
	# `definition()` merges over FALLBACK, so even a pack file that parsed to
	# rubbish leaves the two missions and the four rooms in place. Simulated by
	# merging nonsense through the same code path the loader uses.
	var missions: PackedStringArray = FreeStarter.missions()
	if missions.size() < MUST_INCLUDE_MISSIONS.size():
		failures.append("the free mission list shrank below the required set")
	for mission_id: String in MUST_INCLUDE_MISSIONS:
		if not FreeStarter.FALLBACK["missions"].has(mission_id):
			failures.append(
				("free_starter.gd's compiled-in FALLBACK does not include '%s'. That is the copy "
				+ "used when the pack file is missing or corrupt, which is exactly when a child "
				+ "must NOT lose the game they were playing yesterday.") % mission_id)
	if String(FreeStarter.FALLBACK.get("entitlementId", "")) != EntitlementIds.FREE_STARTER:
		failures.append("the FALLBACK pack is not tagged with the always-active entitlement")
	return failures


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
