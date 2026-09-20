extends RefCounted
## One-line access to the voice pack from a call site, with the null guard
## built in.
##
##     VoiceBridge.cue(self, VoiceCues.EVENT_FOOD_BITE)
##     if not VoiceBridge.say_text(self, line, {"queue": true}):
##         _speak_through_tts(line)        # no Voice in this build: as before
##
## `Voice` is an autoload the lead registers (docs/patches/agentV_project_godot.diff).
## Until it exists every helper here returns false and the caller keeps doing
## exactly what it did before, so the game is complete with or without it.
## Nothing here is cached: a scene that outlives a hot reload asks again.

const VoiceCuesScript := preload("res://scripts/voice/voice_cues.gd")

const VOICE_PATH: String = "/root/Voice"


## The `Voice` autoload, or null.
static func voice(from: Node = null) -> Node:
	if from != null and from.is_inside_tree():
		return from.get_node_or_null(VOICE_PATH)
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		return (loop as SceneTree).root.get_node_or_null(NodePath("Voice"))
	return null


## Plays the cue table's lines for `event`. False when there is no Voice or the
## table has nothing for that moment (a call site may then speak its own text).
static func cue(from: Node, event: String, detail: String = "", opts: Dictionary = {}) -> bool:
	var director: Node = voice(from)
	if director == null or not director.has_method("say_all"):
		return false
	var ids: Array = VoiceCuesScript.for_event(event, detail)
	if ids.is_empty():
		return false
	return int(director.call("say_all", ids, opts)) > 0


## Says the given line ids (already resolved) in order.
static func say_lines(from: Node, line_ids: Array, opts: Dictionary = {}) -> bool:
	if line_ids.is_empty():
		return false
	var director: Node = voice(from)
	if director == null or not director.has_method("say_all"):
		return false
	return int(director.call("say_all", line_ids, opts)) > 0


## Routes spoken English through the voice pack (a recorded line when the text
## is one, the device voice under the pack's queue otherwise). False when there
## is no Voice: the caller must then speak through TtsService itself.
static func say_text(from: Node, text: String, opts: Dictionary = {}) -> bool:
	var director: Node = voice(from)
	if director == null or not director.has_method("say_text"):
		return false
	return bool(director.call("say_text", text, opts))


## Bunny's face for a cue, "" when it does not move the face.
static func face_for(event: String) -> String:
	return VoiceCuesScript.face_for(event)


static func is_available(from: Node = null) -> bool:
	return voice(from) != null
