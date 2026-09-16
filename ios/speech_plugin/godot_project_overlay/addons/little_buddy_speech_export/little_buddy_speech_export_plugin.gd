@tool
extends EditorExportPlugin
# Links the system frameworks LittleBuddySpeech's GDExtension code calls
# into (Speech.framework, AVFoundation.framework) into the generated iOS
# Xcode project.
#
# Why this file exists: Godot 4.7's iOS/"apple embedded" exporter does not
# parse a legacy .gdip file at all -- that mechanism does not exist in this
# engine version (confirmed by inspecting the shipped editor binary: the
# only "Invalid plugin config file" string in Godot 4.7.2 belongs to the
# ANDROID plugin loader, platform/android/export/export_plugin.cpp; there is
# no equivalent iOS/.gdip parser anywhere in the binary). System framework
# linking for a GDExtension-based iOS plugin instead goes through this
# EditorExportPlugin API (add_ios_framework), called from _export_begin.
# See ios/speech_plugin/README.md "Why not .gdip" for the full writeup.
#
# This plugin adds NOTHING else: no bundle files, no linker flags, no
# injected native code, no plist content (the project's own
# export_presets.cfg already declares NSMicrophoneUsageDescription and
# NSSpeechRecognitionUsageDescription). It only links two system frameworks
# that ship with every iOS SDK -- this does not add a network dependency or
# any third-party binary.

func _get_name() -> String:
	return "LittleBuddySpeechExport"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform.get_os_name() == "iOS"


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	if not features.has("ios"):
		return
	add_ios_framework("Speech.framework")
	add_ios_framework("AVFoundation.framework")
