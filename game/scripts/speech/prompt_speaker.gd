## Speaks prompts that would otherwise only be drawn on screen.
##
## ## Why this exists
##
## `MissionRunner` emits `prompt_changed` for a mission's `introPhrase` and
## `outroPhrase` ("Good morning!", "Great job! All done.") but nothing speaks
## them -- the scenes only push them into a `Label`. The player is four and
## cannot read, so those lines currently do not exist for them. Mode handlers do
## speak their own task prompts, so this must not make those stutter.
##
## ## Use
##
## ```gdscript
## PromptSpeaker.attach(mission_runner, get_node("/root/TtsService"))
## ```
##
## One line, and every `prompt_changed` line becomes audible. The speaker parents
## itself to `source`, so it lives and dies with the runner.
##
## ## How double-speaking is avoided
##
## A mode handler emits `prompt_changed` and *then* speaks the same line in the
## same call stack. So this defers: at the end of the frame it asks `TtsService`
## what it is already speaking or has queued, and stays quiet if the line is
## already covered. What is left is exactly the lines nobody else spoke.
##
## Lines are always QUEUED (`interrupt = false`), never interrupting -- an intro
## phrase must not chop off the first task prompt, and vice versa.
extends Node

const DEFAULT_SIGNAL: String = "prompt_changed"

var _tts: Object = null
var _pending: Array[String] = []
var _flush_scheduled: bool = false


## Connects `source`'s `signal_name` to this speaker and returns it.
## Returns null when the source has no such signal or `tts` cannot speak --
## never an error, because audio is an enhancement and must never break a scene.
static func attach(source: Object, tts: Object, signal_name: String = DEFAULT_SIGNAL) -> Node:
	if source == null or tts == null or not tts.has_method("speak"):
		return null
	if not source.has_signal(signal_name):
		return null

	var speaker: Node = (load("res://scripts/speech/prompt_speaker.gd") as GDScript).new()
	speaker.name = "PromptSpeaker"
	speaker.set_tts(tts)
	source.connect(signal_name, speaker.on_prompt)
	if source is Node:
		(source as Node).add_child(speaker)
	return speaker


func set_tts(tts: Object) -> void:
	_tts = tts


## Signal target. The second argument is the Thai hint: written for the adult
## reading over the child's shoulder, and never handed to an English voice.
func on_prompt(text: String, _thai_hint: String = "") -> void:
	var line: String = text.strip_edges()
	if line.is_empty():
		return
	if not _pending.has(line):
		_pending.append(line)
	if not _flush_scheduled:
		_flush_scheduled = true
		call_deferred("flush")


## Speaks whatever nobody else picked up. Called automatically at the end of the
## frame; called directly by the headless tests, which have no frame loop.
func flush() -> void:
	_flush_scheduled = false
	var lines: Array[String] = _pending.duplicate()
	_pending.clear()
	if _tts == null or not _tts.has_method("speak"):
		return

	for line in lines:
		if _already_covered(line):
			continue
		_tts.call("speak", line, false)


## True when the voice is already saying this line, or is about to.
func _already_covered(line: String) -> bool:
	if _tts.has_method("get_current_text") and String(_tts.call("get_current_text")) == line:
		return true
	if _tts.has_method("get_pending_texts"):
		var queued: Variant = _tts.call("get_pending_texts")
		if queued is Array and (queued as Array).has(line):
			return true
	return false
