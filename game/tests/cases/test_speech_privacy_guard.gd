extends RefCounted
## Structural privacy guard for the speech stack.
##
## The promise this project makes to a parent is absolute: **no child audio is
## ever written to disk or leaves the device, and no transcript is ever
## persisted.** That promise was verified once on a physical device
## (`docs/SPEECH_DEVICE_VALIDATION.md`); this test is what stops it being
## undone later by an edit that nobody re-validates on hardware.
##
## It reads source only -- the GDScript speech layer and, read-only, the frozen
## native iOS plugin -- and fails loudly if any of the following appears:
##
##   * networking of any kind in the speech path,
##   * `requiresOnDeviceRecognition` relaxed to allow a server fallback,
##   * audio buffers written to a file,
##   * a recognized transcript stored in the diagnostics snapshot.
##
## The native plugin is FROZEN. Nothing here modifies it; the checks exist so a
## future change has to trip a red test rather than a child's privacy.

const GDSCRIPT_DIR: String = "res://scripts/speech"
const NATIVE_SOURCES: Array[String] = [
	"../ios/speech_plugin/src/little_buddy_speech.mm",
	"../ios/speech_plugin/src/little_buddy_speech.h",
]

## Networking primitives. None of these belong anywhere near the microphone.
const FORBIDDEN_GDSCRIPT: Array[String] = [
	"HTTPRequest",
	"HTTPClient",
	"WebSocketPeer",
	"StreamPeerTCP",
	"PacketPeerUDP",
	"ENetConnection",
	"MultiplayerAPI",
	"http://",
	"https://",
]

## Objective-C networking + on-disk audio.
const FORBIDDEN_NATIVE: Array[String] = [
	"NSURLSession",
	"NSURLRequest",
	"NSURLConnection",
	"CFNetwork",
	"dataTaskWithURL",
	"AVAudioFile",
	"writeToFile",
	"ExtAudioFile",
]

## Keys the on-device diagnostics snapshot is allowed to contain. It exists
## because a device has no console; it must stay capability flags and counts.
const ALLOWED_DIAG_KEYS: Array[String] = [
	"platform",
	"modelName",
	"backend",
	"nativeSingletonPresent",
	"isAvailable",
	"hasPermission",
	"speechEnabledSetting",
	"ttsAvailable",
	# Audio-session metadata used to correlate a native crash. The native JSON
	# is restricted to route/configuration/permission flags and contains no
	# transcript or audio samples.
	"audioDriver",
	"audioMixRate",
	"nativeAudioSession",
	"listenCount",
	"recognizedCount",
	"failedCount",
	"lastFailureReason",
	"launchCount",
	"writtenAt",
]


func test_name() -> String:
	return "speech_privacy_guard"


func run():
	var failures: Array = []
	failures.append_array(_test_gdscript_layer_has_no_network())
	failures.append_array(_test_diagnostics_never_hold_a_transcript())
	failures.append_array(_test_native_plugin_is_on_device_only())
	failures.append_array(_test_mock_is_never_used_on_a_device())
	return failures


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _speech_scripts() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(GDSCRIPT_DIR)
	if dir == null:
		return paths
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			paths.append("%s/%s" % [GDSCRIPT_DIR, file_name])
	return paths


func _test_gdscript_layer_has_no_network():
	var failures: Array = []
	var scripts: PackedStringArray = _speech_scripts()
	if scripts.is_empty():
		failures.append("no speech scripts found in %s" % GDSCRIPT_DIR)
	for path in scripts:
		var source: String = _read(path)
		if source.is_empty():
			failures.append("could not read %s" % path)
			continue
		for needle in FORBIDDEN_GDSCRIPT:
			if source.contains(needle):
				failures.append("%s references '%s' -- the speech path must never network" % [path, needle])
		if source.contains("AudioEffectRecord"):
			failures.append("%s records audio; child audio is never captured to disk" % path)
	return failures


func _test_diagnostics_never_hold_a_transcript():
	var failures: Array = []
	var path: String = "%s/speech_service.gd" % GDSCRIPT_DIR
	var source: String = _read(path)
	if source.is_empty():
		return ["could not read %s" % path]

	# Collect the dictionary keys written into the diagnostics file.
	var start: int = source.find("var diag: Dictionary = {")
	if start == -1:
		failures.append("could not find the diagnostics dictionary in speech_service.gd")
		return failures
	var finish: int = source.find("\n\t}", start)
	var body: String = source.substr(start, finish - start)

	for line in body.split("\n"):
		var trimmed: String = String(line).strip_edges()
		if not trimmed.begins_with("\""):
			continue
		var key_end: int = trimmed.find("\"", 1)
		if key_end <= 0:
			continue
		var key: String = trimmed.substr(1, key_end - 1)
		if not ALLOWED_DIAG_KEYS.has(key):
			failures.append(
				"speech diagnostics would persist an unapproved key '%s'; " % key
				+ "the snapshot must stay flags and counts, never words the child said"
			)

	# The recognized text must never be stored in a member variable either.
	if source.contains("_last_transcript") or source.contains("lastTranscript"):
		failures.append("speech_service.gd appears to retain a transcript")
	return failures


func _test_native_plugin_is_on_device_only():
	var failures: Array = []
	var project_root: String = ProjectSettings.globalize_path("res://")
	var checked: int = 0
	var found_on_device_flag: bool = false

	for relative in NATIVE_SOURCES:
		var path: String = project_root.path_join(relative).simplify_path()
		if not FileAccess.file_exists(path):
			failures.append("native speech source missing: %s" % path)
			continue
		var source: String = _read(path)
		if source.is_empty():
			failures.append("could not read %s" % path)
			continue
		checked += 1

		if source.contains("requiresOnDeviceRecognition = YES"):
			found_on_device_flag = true
		if source.contains("requiresOnDeviceRecognition = NO"):
			failures.append(
				"%s allows a server fallback; recognition must stay on-device" % path
			)
		for needle in FORBIDDEN_NATIVE:
			# Mentions inside comments are how this rule is documented in the
			# plugin, so only flag real code lines.
			for raw_line in source.split("\n"):
				var line: String = String(raw_line).strip_edges()
				if line.begins_with("//") or line.begins_with("*") or line.begins_with("/*"):
					continue
				if line.contains(needle):
					failures.append("%s: '%s' in %s" % [path, needle, line])

	if checked == 0:
		failures.append("no native speech source was checked")
	elif not found_on_device_flag:
		failures.append(
			"requiresOnDeviceRecognition = YES was not found; on-device-only is the "
			+ "single guarantee that makes uploading structurally impossible"
		)
	return failures


## The mock backend exists so the loop is playable on a desktop. It must never
## stand in for a real backend on a device -- faking a recognition for a child
## who actually spoke would be a lie, and faking one for a child who did not
## would be worse.
func _test_mock_is_never_used_on_a_device():
	var failures: Array = []
	var source: String = _read("%s/speech_service.gd" % GDSCRIPT_DIR)
	if source.is_empty():
		return ["could not read speech_service.gd"]

	# BROADENED 2026-09-19, and this is a tightening rather than a relaxation.
	#
	# This function is named `_test_mock_is_never_used_on_a_device` and its
	# docstring says "on a device" -- but the assertion below used to look for
	# the literal `OS.has_feature("ios")`. That gap between the stated intent and
	# the checked condition is not a detail: it is the exact shape of the bug the
	# Android audit found. The production code tested iOS alone, Android matched
	# neither branch, and a real Android device fell through to the MOCK -- which
	# reports itself available and emits a canned "milk". Every speaking task
	# would pass without the child speaking.
	#
	# So the guard now requires a check that covers EVERY mobile platform.
	# `OS.has_feature("mobile")` is true on iOS as well, so nothing that was
	# protected before is protected less.
	var device_branch: int = source.find("OS.has_feature(\"mobile\")")
	if device_branch == -1:
		failures.append("speech_service.gd has no `OS.has_feature(\"mobile\")` guard on "
				+ "backend selection. Naming a single platform lets the next mobile "
				+ "export fall through to the mock by omission.")
		return failures

	var tail: String = source.substr(device_branch)
	var mock_in_tail: int = tail.find("MockSpeechBackend")
	var unavailable_in_tail: int = tail.find("\"unavailable\"")
	if unavailable_in_tail == -1:
		failures.append("the device branch no longer reports 'unavailable' honestly")
	elif mock_in_tail != -1 and mock_in_tail < unavailable_in_tail:
		failures.append("the device branch falls back to the mock backend")
	return failures
