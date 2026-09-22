extends RefCounted
## The voice pack's table of contents is exactly the owner's list -- and the
## test REPORTS which recordings are present rather than pretending.
##
## Asserted:
##   * the manifest parses, and `validate()` finds nothing wrong;
##   * exactly the 36 owner ids, each unique, each `aliz` or `bunny`;
##   * the exact English text the owner wrote for each id (pinned here, so a
##     stray edit to the JSON cannot silently change what the child hears);
##   * every file path is `res://assets/audio/voice/<character>/<lineId>.ogg`;
##   * the drop-in folders exist with a README, WAV masters are git-ignored;
##   * `docs/VOICE_ASSET_REQUEST.md` lists every id;
##   * the convert tool exists.
##
## REPORTED (printed, never failed): "N of 36 recordings present" and the ids
## that are missing. Today that is all 36.

const VoiceManifestScript := preload("res://scripts/voice/voice_manifest.gd")

const REQUEST_DOC: String = "res://../docs/VOICE_ASSET_REQUEST.md"
const PACK_DOC: String = "res://../docs/VOICE_PACK_V1.md"
const GITIGNORE: String = "res://../.gitignore"
const CONVERT_TOOL: String = "res://../tools/voice_convert.sh"

## The owner's list, 2026-09-20. AUTHORITATIVE.
const OWNER_LINES: Array = [
	["aliz_001_welcome", "aliz", "Welcome to Little Days!"],
	["aliz_002_lets_play", "aliz", "Let's play together!"],
	["aliz_003_come_on", "aliz", "Come on, Baby!"],
	["aliz_004_lets_go_home", "aliz", "Let's go home!"],
	["aliz_005_what_shall_we_do", "aliz", "What shall we do today?"],
	["aliz_006_good_job", "aliz", "Great job!"],
	["aliz_007_well_done", "aliz", "You did it!"],
	["aliz_008_try_again", "aliz", "Let's try again!"],
	["aliz_009_its_okay", "aliz", "It's okay. We can do it!"],
	["aliz_010_follow_me", "aliz", "Follow me!"],
	["bunny_001_hungry", "bunny", "I'm hungry, Aliz!"],
	["bunny_002_milk", "bunny", "Milk, please!"],
	["bunny_003_yummy", "bunny", "Yummy!"],
	["bunny_004_more", "bunny", "More, please!"],
	["bunny_005_thank_you", "bunny", "Thank you, Aliz!"],
	["bunny_006_sleepy", "bunny", "I'm sleepy."],
	["bunny_007_good_night", "bunny", "Good night!"],
	["bunny_008_bath", "bunny", "Bath time!"],
	["bunny_009_play", "bunny", "Play with me!"],
	["bunny_010_hug", "bunny", "Hug me, please!"],
	["bunny_011_happy", "bunny", "Yay!"],
	["bunny_012_upset", "bunny", "Hmph!"],
	["aliz_011_apple", "aliz", "Let's give Baby the apple!"],
	["aliz_012_banana", "aliz", "Let's peel the banana!"],
	["aliz_013_drink", "aliz", "Time for a drink!"],
	["aliz_014_milk_time", "aliz", "Let's make some milk!"],
	["aliz_015_bath_time", "aliz", "Let's take a bath!"],
	["aliz_016_brush_teeth", "aliz", "Let's brush our teeth!"],
	["aliz_017_bedtime", "aliz", "Time for bed!"],
	["aliz_018_clean_up", "aliz", "Let's put the toys away!"],
	["aliz_019_cooking", "aliz", "Let's cook something yummy!"],
	["aliz_020_all_done", "aliz", "All done!"],
	["aliz_021_star", "aliz", "You earned a star!"],
	["aliz_022_sticker", "aliz", "A new sticker for you!"],
	["aliz_023_break", "aliz", "Let's take a little break!"],
	["aliz_024_come_back", "aliz", "Come back soon for more Little Days!"],
]

## Sounds that are SFX, not lines. None of these words may be a lineId.
const NOT_LINES: Array[String] = ["laugh", "chew", "drink_sfx", "sigh", "snore", "giggle"]


func test_name() -> String:
	return "voice_manifest"


func run():
	var failures: Array = []
	var manifest: RefCounted = VoiceManifestScript.load_default()
	failures.append_array(_test_structure(manifest))
	failures.append_array(_test_owner_list(manifest))
	failures.append_array(_test_folders_and_ignores())
	failures.append_array(_test_docs(manifest))
	_report_presence(manifest)
	return failures


func _test_structure(manifest: RefCounted):
	var failures: Array = []
	if not manifest.load_error().is_empty():
		return ["manifest failed to load: %s" % manifest.load_error()]
	for problem: Variant in manifest.validate():
		failures.append("manifest: %s" % String(problem))
	if manifest.line_count() != VoiceManifestScript.EXPECTED_LINE_COUNT:
		failures.append("manifest lists %d lines; the owner's list has %d"
				% [manifest.line_count(), VoiceManifestScript.EXPECTED_LINE_COUNT])
	var ids: Array = manifest.line_ids()
	var unique: Dictionary = {}
	for line_id: String in ids:
		if unique.has(line_id):
			failures.append("duplicate lineId %s" % line_id)
		unique[line_id] = true
		var character: String = manifest.character_for(line_id)
		if character != "aliz" and character != "bunny":
			failures.append("%s: character '%s' is not aliz|bunny" % [line_id, character])
		if manifest.file_for(line_id) != "res://assets/audio/voice/%s/%s.ogg" % [character, line_id]:
			failures.append("%s: file path %s" % [line_id, manifest.file_for(line_id)])
	if manifest.line_ids_for("aliz").size() != 24:
		failures.append("Aliz should have 24 lines, found %d" % manifest.line_ids_for("aliz").size())
	if manifest.line_ids_for("bunny").size() != 12:
		failures.append("Bunny should have 12 lines, found %d" % manifest.line_ids_for("bunny").size())
	var characters: Dictionary = manifest.characters()
	for character: String in ["aliz", "bunny"]:
		var entry: Dictionary = characters.get(character, {})
		if String(entry.get("voice", "")).is_empty():
			failures.append("characters.%s needs a `voice` direction" % character)
	for word: String in NOT_LINES:
		for line_id: String in ids:
			if line_id.ends_with("_" + word):
				failures.append("%s: laughs/chewing/sighs are SFX, not voice lines" % line_id)
	return failures


func _test_owner_list(manifest: RefCounted):
	var failures: Array = []
	var expected_ids: Dictionary = {}
	for row: Array in OWNER_LINES:
		var line_id: String = String(row[0])
		expected_ids[line_id] = true
		if not manifest.has_line(line_id):
			failures.append("owner line %s is not in the manifest" % line_id)
			continue
		if manifest.character_for(line_id) != String(row[1]):
			failures.append("%s: character should be %s, got %s" % [line_id, row[1], manifest.character_for(line_id)])
		if manifest.text_for(line_id) != String(row[2]):
			failures.append("%s: text must be exactly \"%s\", got \"%s\"" % [line_id, row[2], manifest.text_for(line_id)])
		if manifest.emotion_for(line_id).strip_edges().is_empty():
			failures.append("%s: no emotion note" % line_id)
	for line_id: String in manifest.line_ids():
		if not expected_ids.has(line_id):
			failures.append("manifest has %s, which is not on the owner's list" % line_id)
	# Text lookup is exact and case-insensitive, and never invents a line.
	if manifest.line_id_for_text("great job!") != "aliz_006_good_job":
		failures.append("line_id_for_text should be case-insensitive")
	if not manifest.line_id_for_text("Great!").is_empty():
		failures.append("'Great!' is not a manifest text; the manifest must not guess (aliases live in VoiceCues)")
	return failures


func _test_folders_and_ignores():
	var failures: Array = []
	for character: String in ["aliz", "bunny"]:
		var readme: String = "res://assets/audio/voice/%s/README.md" % character
		if not FileAccess.file_exists(readme):
			failures.append("%s is missing" % readme)
		else:
			var text: String = FileAccess.get_file_as_string(readme)
			if not text.contains("44.1 kHz") or not text.contains("-3 dBFS"):
				failures.append("%s must state the delivery format (44.1 kHz, -3 dBFS)" % readme)
	if not FileAccess.file_exists(GITIGNORE):
		failures.append(".gitignore not found from res://")
	else:
		var ignore: String = FileAccess.get_file_as_string(GITIGNORE)
		if not ignore.contains("game/assets/audio/voice/**/*.wav"):
			failures.append(".gitignore must ignore game/assets/audio/voice/**/*.wav so a master never ships")
	if not FileAccess.file_exists(CONVERT_TOOL):
		failures.append("tools/voice_convert.sh is missing")
	else:
		var tool_text: String = FileAccess.get_file_as_string(CONVERT_TOOL)
		if not tool_text.contains("voice_pack_report.json"):
			failures.append("tools/voice_convert.sh must write voice_pack_report.json")
	# No stray master or placeholder in the drop-in folders.
	for character: String in ["aliz", "bunny"]:
		var dir: DirAccess = DirAccess.open("res://assets/audio/voice/%s" % character)
		if dir == null:
			failures.append("res://assets/audio/voice/%s does not exist" % character)
			continue
		for file_name: String in dir.get_files():
			if file_name.get_extension().to_lower() in ["wav", "aif", "aiff"]:
				failures.append("a WAV master is inside the repo: assets/audio/voice/%s/%s" % [character, file_name])
	return failures


func _test_docs(manifest: RefCounted):
	var failures: Array = []
	if not FileAccess.file_exists(REQUEST_DOC):
		return ["docs/VOICE_ASSET_REQUEST.md is missing"]
	var text: String = FileAccess.get_file_as_string(REQUEST_DOC)
	for line_id: String in manifest.line_ids():
		if not text.contains("`%s`" % line_id):
			failures.append("docs/VOICE_ASSET_REQUEST.md does not list `%s`" % line_id)
		if not text.contains(manifest.text_for(line_id)):
			failures.append("docs/VOICE_ASSET_REQUEST.md does not carry the text of %s" % line_id)
	if not text.contains("res://assets/audio/voice/<character>/<lineId>.ogg"):
		failures.append("the request document must name the drop-in path res://assets/audio/voice/<character>/<lineId>.ogg")
	if not text.contains("tools/voice_convert.sh"):
		failures.append("the request document must give the convert command")
	if not FileAccess.file_exists(PACK_DOC):
		failures.append("docs/VOICE_PACK_V1.md is missing")
	else:
		var pack: String = FileAccess.get_file_as_string(PACK_DOC)
		if not pack.contains("0 of 36") and manifest.recorded_line_ids().is_empty():
			failures.append("docs/VOICE_PACK_V1.md must say honestly that 0 of 36 recordings exist")
	return failures


## Printed, never failed: the honest state of the pack on this checkout.
func _report_presence(manifest: RefCounted) -> void:
	print("     voice pack: %s" % manifest.presence_summary())
	var missing: Array = manifest.missing_line_ids()
	if missing.is_empty():
		print("     every recording is in the build")
		return
	print("     missing (%d): %s" % [missing.size(), ", ".join(PackedStringArray(missing))])
	print("     these lines fall back to TtsService until their .ogg is dropped in")
