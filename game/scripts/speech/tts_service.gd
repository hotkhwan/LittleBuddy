## Autoload facade for text-to-speech. Uses Godot's built-in DisplayServer TTS
## when a voice is available, and always guarantees `speech_finished` fires
## (via a timed fallback) so gameplay sequencing can never deadlock — even on
## platforms/builds with no TTS support at all.
extends Node

const NORMAL_SPEECH_RATE: float = 1.0
const SLOW_SPEECH_RATE: float = 0.75

signal speech_started(text: String)
signal speech_finished(text: String)

const MIN_DURATION_SECONDS := 0.6
const MAX_DURATION_SECONDS := 8.0
const WORDS_PER_SECOND := 2.5 # ~150 wpm, comfortable for a child listener

var _tts_feature_supported: bool = false
var _current_text: String = ""
var _is_speaking: bool = false
var _utterance_id: int = 0


func _ready() -> void:
	_tts_feature_supported = _has_tts_feature()
	if _tts_feature_supported:
		DisplayServer.tts_set_utterance_callback(
			DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_ended
		)
		DisplayServer.tts_set_utterance_callback(
			DisplayServer.TTS_UTTERANCE_CANCELED, _on_utterance_canceled
		)


func speak(text: String, interrupt: bool = true) -> void:
	if text == "":
		return
	if interrupt:
		stop()

	_utterance_id += 1
	var utterance_id := _utterance_id
	_current_text = text
	_is_speaking = true
	speech_started.emit(text)

	var used_native_voice := false
	if _tts_feature_supported:
		used_native_voice = _try_speak_native(text, utterance_id)

	# Always schedule a fallback completion. If the native callback fires
	# first it wins (guarded by utterance id); otherwise this guarantees
	# `speech_finished` still fires so gameplay never hangs.
	_schedule_fallback(utterance_id, _estimate_duration(text))

	if not used_native_voice:
		# No native voice spoke anything audible; nothing else to do besides
		# waiting for the fallback timer above.
		pass


func stop() -> void:
	if _tts_feature_supported:
		DisplayServer.tts_stop()
	if _is_speaking:
		var text := _current_text
		_is_speaking = false
		speech_finished.emit(text)


func is_available() -> bool:
	if not _has_tts_feature():
		return false
	var voices := DisplayServer.tts_get_voices_for_language("en")
	return not voices.is_empty()


func _try_speak_native(text: String, utterance_id: int) -> bool:
	# tts_get_voices_for_language returns a PackedStringArray of voice ids.
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		return false

	var voice_id: String = voices[0]
	DisplayServer.tts_speak(text, voice_id, 50, _speech_rate(), 1.0, utterance_id, true)
	return true


## Reads the parent-facing "ttsSpeed" setting. A slower rate helps a child who is
## still learning the words. Read defensively: SaveService may be absent (tests).
func _speech_rate() -> float:
	var save_service: Node = get_node_or_null("/root/SaveService")
	if save_service == null or not save_service.has_method("get_setting"):
		return NORMAL_SPEECH_RATE
	if str(save_service.get_setting("ttsSpeed", "normal")) == "slow":
		return SLOW_SPEECH_RATE
	return NORMAL_SPEECH_RATE


func _schedule_fallback(utterance_id: int, duration: float) -> void:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		var timer := (main_loop as SceneTree).create_timer(duration)
		timer.timeout.connect(func(): _complete_utterance(utterance_id))
	else:
		# No SceneTree (e.g. --script test runs) — resolve immediately.
		_complete_utterance(utterance_id)


func _complete_utterance(utterance_id: int) -> void:
	if utterance_id != _utterance_id:
		return # a newer speak()/stop() already resolved this utterance
	if not _is_speaking:
		return
	_is_speaking = false
	speech_finished.emit(_current_text)


func _on_utterance_ended(utterance_id: int) -> void:
	_complete_utterance(utterance_id)


func _on_utterance_canceled(utterance_id: int) -> void:
	_complete_utterance(utterance_id)


func _estimate_duration(text: String) -> float:
	var words := text.split(" ", false)
	var word_count: int = max(words.size(), 1)
	var duration := float(word_count) / WORDS_PER_SECOND
	return clamp(duration, MIN_DURATION_SECONDS, MAX_DURATION_SECONDS)


func _has_tts_feature() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
