extends "res://scripts/tutor/providers/speech_synthesis_provider.gd"

## The canonical synthesis provider: Aliz's voice pack first, the device voice
## under the pack's queue second, the bare TtsService third, and a pacing clock
## when this build has no voice at all. Never silent-and-stuck: `finished`
## always comes.
##
## Route per utterance (`voice_used()`):
##   recording   `Voice.say(spokenLineId)` / `Voice.say_text(text)` hit a bundled
##               OGG; lip sync reads the "Voice" bus (`lip_sync_player()` is
##               Aliz's player);
##   voice_tts   the pack had no file: `Voice` spoke the text through TtsService
##               (one queue, one voice at a time); `platform_speech_*` forwarded;
##   tts         no `Voice` autoload in this build: TtsService directly;
##   paced       nothing audible (headless, muted, no TTS): the subtitle still
##               shows for a reading-speed duration.
##
## The turn is spoken with `interrupt: true`: a tutor line cuts leftover
## narration or a Bunny reaction rather than queueing behind it, and the
## recognition provider is cancelled through `started` before any sound.

const VOICE_PATH: String = "Voice"
const TTS_PATH: String = "TtsService"

var _voice: Node = null
var _tts: Node = null
var _remaining: float = 0.0
var _waiting_voice_line: bool = false
var _voice_line_started: bool = false
var _voice_line_id: String = ""
var _using_tts: bool = false
var _voice_hooked: Node = null
var _tts_hooked: Node = null
## Work moved off a signal's stack to the next `advance()`: the utterance to
## finish (-1 = none) and the platform line still to start ("" = none). The
## frame loop calls `advance()` every frame; a headless test calls it once.
var _pending_finish: int = -1
var _pending_tts_line: String = ""


func provider_name() -> String:
	return "voice_pack"


func is_available() -> bool:
	return true


## Injection for tests (a director with captured timers, a TtsService with a
## captured timer factory). Defaults are the autoloads.
func set_voice(voice: Node) -> void:
	_voice = voice


func set_tts(tts: Node) -> void:
	_tts = tts


func lip_sync_player() -> AudioStreamPlayer:
	var voice: Node = _voice_node()
	if voice == null or _route != ROUTE_RECORDING or not voice.has_method("get_player"):
		return null
	var character: String = "aliz"
	if voice.has_method("current_character"):
		character = String(voice.call("current_character"))
	return voice.call("get_player", character) as AudioStreamPlayer


func speak(text: String, spoken_line_id: String = "") -> bool:
	cancel()
	var line: String = text.strip_edges()
	if line.is_empty():
		return false
	_utterance += 1
	_speaking = true
	_current_text = line
	_remaining = pace_for(line)
	_route = ROUTE_PACED
	# `started` BEFORE any sound: the recognition provider cancels its session on it.
	started.emit(line)
	if _muted:
		return true
	var voice: Node = _voice_node()
	if voice != null and voice.has_method("say_text"):
		_hook_voice(voice)
		_waiting_voice_line = true
		_voice_line_started = false
		var accepted: bool = false
		if not spoken_line_id.is_empty() and voice.has_method("say"):
			accepted = bool(voice.call("say", spoken_line_id, {"interrupt": true}))
		if not accepted:
			accepted = bool(voice.call("say_text", line, {"interrupt": true}))
		if accepted:
			if not _voice_line_started:
				_refresh_voice_route(voice)
			return true
		_waiting_voice_line = false
	var tts: Node = _tts_node()
	if tts != null and tts.has_method("speak") and tts.has_signal("speech_finished"):
		_using_tts = true
		_route = ROUTE_TTS
		_hook_tts(tts)
		# Next advance(), not now: this is often reached from inside the
		# service's own `speech_finished`; a re-entrant speak() there clobbers
		# its state.
		_pending_tts_line = line
	return true


## Cuts the current utterance. `finished` still fires for it.
func cancel() -> void:
	if not _speaking:
		return
	var text: String = _current_text
	var voice: Node = _voice_node()
	if _waiting_voice_line and voice != null and voice.has_method("stop"):
		_waiting_voice_line = false
		voice.call("stop", "aliz")
	if _using_tts and _tts_node() != null and _tts_node().has_method("stop"):
		_using_tts = false
		_tts_node().call("stop")
	_finish(text)


## The pacing clock. A recording or TTS-backed utterance finishes on its own
## signal; the clock is the safety net there and the mechanism otherwise.
func advance(delta: float) -> void:
	if _pending_finish >= 0:
		var utterance: int = _pending_finish
		_pending_finish = -1
		_finish_utterance(utterance)
	if not _pending_tts_line.is_empty():
		var line: String = _pending_tts_line
		_pending_tts_line = ""
		_begin_tts(line, _utterance)
	if not _speaking or delta <= 0.0:
		return
	_remaining -= delta
	if _waiting_voice_line or _using_tts:
		if _remaining > -PACE_MAX_SECONDS * 2.0:
			return
	elif _remaining > 0.0:
		return
	_finish(_current_text)


# -- Voice pack ---------------------------------------------------------------------

func _voice_node() -> Node:
	if _voice != null and is_instance_valid(_voice):
		return _voice
	return _autoload(VOICE_PATH)


func _tts_node() -> Node:
	if _tts != null and is_instance_valid(_tts):
		return _tts
	return _autoload(TTS_PATH)


func _hook_voice(voice: Node) -> void:
	if _voice_hooked == voice:
		return
	_voice_hooked = voice
	if voice.has_signal("line_started") and not voice.is_connected("line_started", _on_voice_line_started):
		voice.connect("line_started", _on_voice_line_started)
	if voice.has_signal("line_finished") and not voice.is_connected("line_finished", _on_voice_line_finished):
		voice.connect("line_finished", _on_voice_line_finished)
	_hook_tts(_tts_node())


func _hook_tts(tts: Node) -> void:
	if tts == null or _tts_hooked == tts:
		return
	_tts_hooked = tts
	if tts.has_signal("speech_started") and not tts.is_connected("speech_started", _on_tts_started):
		tts.connect("speech_started", _on_tts_started)
	if tts.has_signal("speech_finished") and not tts.is_connected("speech_finished", _on_tts_finished):
		tts.connect("speech_finished", _on_tts_finished)


func _refresh_voice_route(voice: Node) -> void:
	if voice.has_method("is_playing_recording") and bool(voice.call("is_playing_recording")):
		_route = ROUTE_RECORDING
	else:
		_route = ROUTE_VOICE_TTS


func _on_voice_line_started(line_id: String, _character: String, text: String) -> void:
	if not _speaking or not _waiting_voice_line or _voice_line_started:
		return
	if text != _current_text:
		return
	_voice_line_started = true
	_voice_line_id = line_id
	var voice: Node = _voice_node()
	if voice != null:
		_refresh_voice_route(voice)


func _on_voice_line_finished(line_id: String) -> void:
	if not _speaking or not _waiting_voice_line or not _voice_line_started:
		return
	if line_id != _voice_line_id:
		return
	_waiting_voice_line = false
	# Off the director's stack before the scene reacts.
	_pending_finish = _utterance


# -- Platform voice --------------------------------------------------------------------

func _begin_tts(line: String, utterance: int) -> void:
	var tts: Node = _tts_node()
	if utterance != _utterance or not _speaking or tts == null:
		return
	tts.call("speak", line, true)


func _on_tts_started(text: String) -> void:
	if _speaking and text == _current_text:
		platform_speech_started.emit(text)


func _on_tts_finished(text: String) -> void:
	if _speaking and text == _current_text:
		platform_speech_finished.emit(text)
		if _using_tts:
			_pending_finish = _utterance


func _finish_utterance(utterance: int) -> void:
	if utterance == _utterance and _speaking:
		_finish(_current_text)


func _finish(text: String) -> void:
	if not _speaking:
		return
	_speaking = false
	_waiting_voice_line = false
	_voice_line_started = false
	_using_tts = false
	_pending_finish = -1
	_pending_tts_line = ""
	_current_text = ""
	_remaining = 0.0
	finished.emit(text)
