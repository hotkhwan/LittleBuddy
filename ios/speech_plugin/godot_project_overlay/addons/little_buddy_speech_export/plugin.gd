@tool
extends EditorPlugin
# Registers little_buddy_speech_export_plugin.gd with the editor's export
# pipeline. This is the standard Godot 4 EditorPlugin/EditorExportPlugin
# pairing -- see ios/speech_plugin/README.md "Why not .gdip" for why this
# addon exists instead of a legacy .gdip file (that mechanism is not parsed
# by Godot 4.7's iOS exporter at all).
#
# This addon must be enabled in the project (Project Settings > Plugins, or
# by adding it to [editor_plugins] enabled= in project.godot) for
# _export_begin() in little_buddy_speech_export_plugin.gd to run during
# `--export-debug "iOS" ...` / `--export-release "iOS" ...`.

const LittleBuddySpeechExportPlugin = preload("little_buddy_speech_export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = LittleBuddySpeechExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
