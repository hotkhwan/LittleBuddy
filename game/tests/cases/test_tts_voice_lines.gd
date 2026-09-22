extends RefCounted

## The Voice volume slider reaches the platform voice, and the owner's
## recordings drop in by file name with TTS as the fallback.

const TtsServiceScript := preload("res://scripts/speech/tts_service.gd")
const VoiceLines := preload("res://scripts/speech/voice_lines.gd")
const L10n := preload("res://scripts/localization/localization.gd")

const REQUEST_DOC: String = "res://../docs/VOICE_ASSET_REQUEST.md"
const LEGACY_RENAMED_IDS: Array[String] = ["go_to_bunny", "take_it_to_bunny",
	"give_bunny_the_bottle", "bunny_wants_a_cuddle", "give_bunny_a_big_hug"]


class FakeSaveService:
	extends Node
	var settings: Dictionary = {}

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)


func test_name() -> String:
	return "tts_voice_lines"


func run():
	var failures: Array = []
	failures.append_array(_test_voice_volume())
	failures.append_array(_test_line_ids_and_paths())
	failures.append_array(_test_missing_recording_falls_back_to_tts())
	failures.append_array(_test_request_document_matches_the_code())
	return failures


func _test_voice_volume():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var service: Node = TtsServiceScript.new()
	# No profile, no override: today's level.
	if service.get_speech_volume_percent() != TtsServiceScript.SPEECH_VOLUME:
		failures.append("default voice volume should be %d, got %d"
				% [TtsServiceScript.SPEECH_VOLUME, service.get_speech_volume_percent()])
	# The profile's slider.
	var save := FakeSaveService.new()
	save.name = "SaveService"
	save.settings["voiceVolume"] = 0.4
	tree.root.add_child(save)
	if service.get_speech_volume_percent() != 40:
		failures.append("voiceVolume 0.4 in the profile should give 40, got %d" % service.get_speech_volume_percent())
	# The live override from the settings screen wins, clamped.
	service.set_voice_volume(1.7)
	if service.get_speech_volume_percent() != 100:
		failures.append("set_voice_volume(1.7) should clamp to 100, got %d" % service.get_speech_volume_percent())
	service.set_voice_volume(0.0)
	if service.get_speech_volume_percent() != 0:
		failures.append("set_voice_volume(0) should be 0, got %d" % service.get_speech_volume_percent())
	service.set_voice_volume(0.65)
	if absf(service.get_voice_volume() - 0.65) > 0.001:
		failures.append("get_voice_volume() should read back 0.65, got %.2f" % service.get_voice_volume())
	tree.root.remove_child(save)
	save.free()
	service.free()
	return failures


func _test_line_ids_and_paths():
	var failures: Array = []
	if VoiceLines.line_id_for("Time to drink!") != "time_to_drink":
		failures.append("line_id_for('Time to drink!') = %s" % VoiceLines.line_id_for("Time to drink!"))
	if VoiceLines.line_id_for("Time to drink!") != L10n.key_for("Time to drink!"):
		failures.append("voice line ids must be the localisation keys")
	if VoiceLines.stream_path("time_to_drink") != "res://audio/voice/time_to_drink.ogg":
		failures.append("drop-in path is %s" % VoiceLines.stream_path("time_to_drink"))
	if VoiceLines.LINES.size() < 24:
		failures.append("the request list holds only %d lines; ~24 were promised" % VoiceLines.LINES.size())
	for line_id: String in VoiceLines.line_ids():
		var row: Dictionary = VoiceLines.LINES[line_id]
		var text: String = String(row.get("text", ""))
		if text.is_empty() or String(row.get("emotion", "")).is_empty() or float(row.get("seconds", 0.0)) <= 0.0:
			failures.append("line %s lacks text, emotion or length" % line_id)
		if VoiceLines.line_id_for(text) != line_id and not LEGACY_RENAMED_IDS.has(line_id):
			failures.append("line %s's id does not derive from its text '%s' (%s)"
					% [line_id, text, VoiceLines.line_id_for(text)])
	for must: String in ["great", "try_again", "you_can_tap_it_too", "im_hungry_aliz", "time_to_drink", "milk", "thank_you"]:
		if not VoiceLines.LINES.has(must):
			failures.append("the request list has no '%s'" % must)
	return failures


func _test_missing_recording_falls_back_to_tts():
	var failures: Array = []
	# Nothing is bundled yet: the lookup says so, and speaking still resolves.
	if VoiceLines.has_recording("Time to drink!"):
		failures.append("a recording is reported for a line none is shipped for")
	if VoiceLines.stream_for("Time to drink!") != null:
		failures.append("stream_for() returned a stream with no file on disk")
	var service: Node = TtsServiceScript.new()
	var finished: Array = []
	service.speech_finished.connect(func(text: String) -> void: finished.append(text))
	service.speak("Time to drink!")
	# Outside a tree the safety path resolves at once.
	if service.is_playing_recording():
		failures.append("the service claims to be playing a recording that does not exist")
	if finished != ["Time to drink!"]:
		failures.append("speak() did not resolve through TTS/fallback: %s" % str(finished))
	service.free()
	return failures


## The owner's request document is now the VOICE PACK list (36 ids, two
## characters -- see `scripts/voice/voice_manifest.gd`); the text-keyed
## `VoiceLines` ids are the legacy drop-in and are no longer requested. The
## document must still name the legacy path so a file dropped there is not a
## mystery, and must list every manifest id (`test_voice_manifest.gd` checks the
## texts too).
func _test_request_document_matches_the_code():
	var failures: Array = []
	if not FileAccess.file_exists(REQUEST_DOC):
		return ["%s is missing" % REQUEST_DOC]
	var text: String = FileAccess.get_file_as_string(REQUEST_DOC)
	if not text.contains("res://audio/voice/<lineId>.ogg"):
		failures.append("the request document must still name the legacy drop-in path res://audio/voice/<lineId>.ogg")
	var manifest: RefCounted = (load("res://scripts/voice/voice_manifest.gd") as GDScript).call("load_default")
	for line_id: String in manifest.call("line_ids"):
		if not text.contains("`%s`" % line_id):
			failures.append("docs/VOICE_ASSET_REQUEST.md does not list `%s`" % line_id)
	return failures
