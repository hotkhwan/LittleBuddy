extends Node

## SpeechSynthesisProvider -- how a TutorTurn is voiced.
##
## Surface every implementation keeps (Agent B's `local_synthesis_provider.gd`
## draft had the same names, so the scene binds unchanged):
##
##   speak_turn(turn, spoken_line_id = "")   speak(text, spoken_line_id = "")
##   cancel()   advance(delta)   is_speaking()   current_text()   voice_used()
##   set_muted(bool) / is_muted()   is_available()
##   lip_sync_bus() -> StringName   lip_sync_player() -> AudioStreamPlayer
##   signal started(text)   signal finished(text)      -- exactly once per utterance
##   signal platform_speech_started(text) / platform_speech_finished(text)
##       -- forwarded from TtsService when the PLATFORM voice speaks, so a
##          text-based mouth envelope (Agent C's fallback) can run when there
##          is no audio bus to read.
##
## Implementations:
##   * `VoicePackSynthesisProvider` (canonical, always available): the recorded
##     line through `/root/Voice` when the step names a `spokenLineId` or the
##     text is one of the pack's lines, else the device voice under the same
##     queue (`Voice.say_text`), else `TtsService`, else a reading-speed pacing
##     clock so the subtitle still shows and `finished` still fires. Music
##     ducks through `Voice`/`TtsService` as it already does.
##   * `BackendSynthesisProvider` (stub, flag-gated): documents the future
##     cloud TTS route; today it answers `unavailable` and is never used.
##
## `finished` fires exactly once per utterance, including when `cancel()` cuts it.

signal started(text: String)
signal finished(text: String)
signal platform_speech_started(text: String)
signal platform_speech_finished(text: String)

const ROUTE_RECORDING: String = "recording"
const ROUTE_VOICE_TTS: String = "voice_tts"
const ROUTE_TTS: String = "tts"
const ROUTE_PACED: String = "paced"
const ROUTE_NONE: String = ""

## Reading-speed pacing when nothing audible is playing: a short lead-in plus
## per-character time. "Can you say banana?" is about 1.4 s; a hint about 2.5 s.
const PACE_LEAD_SECONDS: float = 0.35
const PACE_PER_CHAR_SECONDS: float = 0.055
const PACE_MIN_SECONDS: float = 0.8
const PACE_MAX_SECONDS: float = 6.0

var _speaking: bool = false
var _current_text: String = ""
var _muted: bool = false
var _route: String = ROUTE_NONE
var _utterance: int = 0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


func provider_name() -> String:
	return "base"


func is_available() -> bool:
	return false


func is_speaking() -> bool:
	return _speaking


func current_text() -> String:
	return _current_text


## Which route the current (or last) utterance took: recording / voice_tts /
## tts / paced.
func voice_used() -> String:
	return _route


func set_muted(muted: bool) -> void:
	_muted = muted


func is_muted() -> bool:
	return _muted


## The audio bus a `LipSyncSource` should read (`attach_bus`).
func lip_sync_bus() -> StringName:
	return &"Voice"


## The player carrying the current recording, when there is one (else null:
## the platform voice has no player; use the text envelope).
func lip_sync_player() -> AudioStreamPlayer:
	return null


## Speaks a validated turn. `spoken_line_id` is the step's recorded line, when
## the lesson names one. Returns false when nothing was said (empty text).
func speak_turn(turn: Dictionary, spoken_line_id: String = "") -> bool:
	return speak(String(turn.get("speech", "")), spoken_line_id)


func speak(_text: String, _spoken_line_id: String = "") -> bool:
	return false


func cancel() -> void:
	pass


func advance(_delta: float) -> void:
	pass


static func pace_for(text: String) -> float:
	return clampf(PACE_LEAD_SECONDS + PACE_PER_CHAR_SECONDS * float(text.length()), PACE_MIN_SECONDS, PACE_MAX_SECONDS)


## Through the main loop, so it answers before this node is in the active tree.
func _autoload(node_name: String) -> Node:
	var tree: SceneTree = get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(node_name))
