extends Node

## The SpeechSynthesisProvider shim for the classroom: `speak(text)` /
## `speak_turn(turn)` and a `finished` signal, over whatever voice this build
## has, best first:
##
##   1. `/root/Voice`.say(line_id)  -- a bundled recorded line, when the step
##      names a `spokenLineId` and that autoload exists (Agent E's);
##   2. `/root/TtsService`.speak()  -- the on-device platform voice, which
##      already plays an owner recording when one matches the text;
##   3. its own pacing timer        -- headless, muted, or a build with no TTS:
##      the subtitle still shows for a reading-speed duration and `finished`
##      still fires, so the lesson can never hang on a voice that is not there.
##
## `advance(delta)` drives the pacing; `_process()` calls it every frame and a
## headless test calls it directly, the convention `SpeechService.advance()`
## and `AudioDirector.advance()` set. `finished` fires exactly once per
## utterance, including when `cancel()` cuts it. Agent E's full provider adds
## backend TTS bytes and the `LipSyncSource` amplitude; this shim exposes the
## same surface so the scene does not change when it lands.

signal started(text: String)
signal finished(text: String)

const VOICE_PATH: String = "/root/Voice"
const TTS_PATH: String = "/root/TtsService"

## Reading-speed pacing when nothing audible is playing: a short lead-in plus
## per-character time. "Can you say banana?" is about 1.4 s, a hint about 2.5 s.
const PACE_LEAD_SECONDS: float = 0.35
const PACE_PER_CHAR_SECONDS: float = 0.055
const PACE_MIN_SECONDS: float = 0.8
const PACE_MAX_SECONDS: float = 6.0

var _speaking: bool = false
var _current_text: String = ""
var _remaining: float = 0.0
var _muted: bool = false
var _using_tts: bool = false
var _tts: Node = null
var _voice_used: String = ""
## Increments per `speak()`, so a finish that arrives late (deferred, or from
## the service's own signal) is matched to the utterance it belongs to.
var _utterance: int = 0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## Silences the audible voice. The subtitle pacing keeps running so a muted
## lesson still moves at the same speed.
func set_muted(muted: bool) -> void:
	_muted = muted
	if muted and _using_tts and _tts != null and _tts.has_method("stop"):
		# `stop()` emits `speech_finished`, which finishes this utterance via
		# the TTS path; the subtitle then falls back to pacing for the rest.
		var text: String = _current_text
		_detach_tts()
		_using_tts = false
		_remaining = maxf(_remaining, _pace_for(text) * 0.5)


func is_muted() -> bool:
	return _muted


func is_speaking() -> bool:
	return _speaking


func current_text() -> String:
	return _current_text


## Which route the current (or last) utterance took: "voice", "tts" or "paced".
func voice_used() -> String:
	return _voice_used


## Speaks a validated turn. Prefers a recorded line when the turn (or the step
## it was built from) carries a `spokenLineId`.
func speak_turn(turn: Dictionary, spoken_line_id: String = "") -> void:
	speak(String(turn.get("speech", "")), spoken_line_id)


func speak(text: String, spoken_line_id: String = "") -> void:
	cancel()
	var line: String = text.strip_edges()
	if line.is_empty():
		return
	_utterance += 1
	_speaking = true
	_current_text = line
	_remaining = _pace_for(line)
	_voice_used = "paced"
	started.emit(line)
	if _muted:
		return
	var voice: Node = _autoload(VOICE_PATH)
	if voice != null and not spoken_line_id.is_empty() and voice.has_method("say"):
		var played: Variant = voice.call("say", spoken_line_id)
		if typeof(played) != TYPE_BOOL or bool(played):
			_voice_used = "voice"
			if voice.has_signal("finished") and not voice.is_connected("finished", _on_voice_finished):
				voice.connect("finished", _on_voice_finished, CONNECT_ONE_SHOT)
			return
	_tts = _autoload(TTS_PATH)
	if _tts != null and _tts.has_method("speak") and _tts.has_signal("speech_finished"):
		_using_tts = true
		_voice_used = "tts"
		# DEFERRED, and connected only once the call has gone out: this is
		# frequently reached from inside the service's own `speech_finished`
		# (the previous line ended, the scene asked for the next), and a
		# re-entrant `speak()` there clobbers the service's utterance state so
		# its finish for the new line never comes.
		call_deferred("_begin_tts", line, _utterance)


## Cuts the current utterance. `finished` still fires for it.
func cancel() -> void:
	if not _speaking:
		return
	var text: String = _current_text
	if _using_tts and _tts != null and _tts.has_method("stop"):
		_detach_tts()
		_tts.call("stop")
	_using_tts = false
	_speaking = false
	_current_text = ""
	_remaining = 0.0
	finished.emit(text)


## Runs the pacing clock. A TTS-backed utterance finishes on the service's own
## signal; the clock is a safety net there (the service's own timeout is
## longer) and the whole mechanism otherwise.
func advance(delta: float) -> void:
	if not _speaking or delta <= 0.0:
		return
	_remaining -= delta
	if _using_tts:
		# Give the platform voice generous room; the service guarantees its
		# own `speech_finished`, so this only catches a service that vanished.
		if _remaining > -PACE_MAX_SECONDS * 2.0:
			return
	elif _remaining > 0.0:
		return
	_finish()


func _finish() -> void:
	if not _speaking:
		return
	var text: String = _current_text
	_detach_tts()
	_using_tts = false
	_speaking = false
	_current_text = ""
	_remaining = 0.0
	finished.emit(text)


func _begin_tts(line: String, utterance: int) -> void:
	if utterance != _utterance or not _speaking or _tts == null or not is_instance_valid(_tts):
		return
	# Connected AFTER the call: `speak(interrupt = true)` stops whatever the
	# service was saying and emits `speech_finished` for that old line first.
	_tts.call("speak", line, true)
	if not _tts.speech_finished.is_connected(_on_tts_finished):
		_tts.speech_finished.connect(_on_tts_finished)


func _on_tts_finished(_text: String) -> void:
	if _using_tts:
		# Off the service's stack before the scene reacts (see `_begin_tts`).
		call_deferred("_finish_utterance", _utterance)


func _finish_utterance(utterance: int) -> void:
	if utterance == _utterance and _speaking:
		_finish()


func _on_voice_finished(_arg: Variant = null) -> void:
	if _speaking and _voice_used == "voice":
		_finish()


func _detach_tts() -> void:
	if _tts != null and is_instance_valid(_tts) and _tts.has_signal("speech_finished") \
			and _tts.speech_finished.is_connected(_on_tts_finished):
		_tts.speech_finished.disconnect(_on_tts_finished)


## Through the main loop, so it answers before this node is in the active tree.
func _autoload(path: String) -> Node:
	var tree: SceneTree = get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(path.trim_prefix("/root/"))


static func _pace_for(text: String) -> float:
	return clampf(PACE_LEAD_SECONDS + PACE_PER_CHAR_SECONDS * float(text.length()), PACE_MIN_SECONDS, PACE_MAX_SECONDS)
