extends Node

## CloudSynthesisProvider -- the SpeechSynthesisProvider surface over a cloud
## reply. The scene's `_speak_turn()` calls `speak_turn(turn)` exactly as it
## does for the local voice; here, when a realtime reply is streaming, the
## voice IS that reply (played by `CloudAudioPlayer`, mouth from its level)
## and `finished` fires when the reply has fully played. When no reply is
## streaming (the welcome, an open question, the closing, any local turn) the
## call is forwarded to the wrapped local provider, so recorded lines and the
## device voice keep working unchanged.
##
## Rules kept from the contract: `finished` fires exactly once per utterance,
## including when `cancel()` cuts it; `cancel()` on a cloud reply is the
## barge-in (response.cancel + truncate: what was not played is never played);
## a reply that streamed no audio is voiced by the local provider from its
## final words; a reply the session replaced for safety is voiced as the
## fallback line by the local provider before `finished`.

signal started(text: String)
signal finished(text: String)

const MODE_NONE: String = ""
const MODE_CLOUD: String = "cloud"
const MODE_INNER: String = "inner"

var _inner: Node = null
var _cloud: RefCounted = null
var _provider: RefCounted = null
var _player: Node = null
var _mode: String = MODE_NONE
var _speaking: bool = false
var _current_text: String = ""
var _muted: bool = false
var _wired: bool = false
var _finish_next_frame: bool = false
## Who authored the words of the last `speak_turn()`: "cloud" (a reply the
## session claimed, streamed or a REST turn voiced locally) or "local".
var _words_source: String = ""


func _ready() -> void:
	set_process(false)  # the scene pumps `advance()`, as it did the local provider


func set_inner(synth: Node) -> void:
	_inner = synth
	if _inner != null and not _inner.finished.is_connected(_on_inner_finished):
		_inner.finished.connect(_on_inner_finished)


func set_cloud_session(session: RefCounted) -> void:
	_cloud = session
	_wire()


## The conversation provider to pump each frame (the scene pumps only us).
func set_cloud_provider(provider: RefCounted) -> void:
	_provider = provider


func set_audio_player(player: Node) -> void:
	_player = player
	if _player != null and _player.get_parent() == null:
		add_child(_player)


func provider_name() -> String:
	return "cloud_synthesis"


func is_available() -> bool:
	return true


func is_speaking() -> bool:
	if _speaking:
		return true
	return _inner != null and bool(_inner.call("is_speaking"))


func current_text() -> String:
	if _mode == MODE_CLOUD:
		return _current_text
	return String(_inner.call("current_text")) if _inner != null else _current_text


func voice_used() -> String:
	if _mode == MODE_CLOUD:
		return "cloud"
	return String(_inner.call("voice_used")) if _inner != null and _inner.has_method("voice_used") else ""


func set_muted(muted: bool) -> void:
	_muted = muted
	if _inner != null:
		_inner.call("set_muted", muted)
	if _cloud != null:
		_cloud.call("mute", muted)


func is_muted() -> bool:
	return _muted


func lip_sync_bus() -> StringName:
	return &"Voice"


func lip_sync_player() -> AudioStreamPlayer:
	if _inner != null and _inner.has_method("lip_sync_player"):
		return _inner.call("lip_sync_player") as AudioStreamPlayer
	return null


func mode() -> String:
	return _mode


## Counters only (the scene's diagnostics() and the dev JSON): the cloud
## audio player's chunk/frame/underrun/truncation tallies, plus which mode
## the wrapper is in. No text, no audio.
func diagnostics() -> Dictionary:
	var out: Dictionary = {"mode": _mode, "wordsSource": _words_source}
	if _player != null and is_instance_valid(_player) and _player.has_method("diagnostics"):
		out.merge(_player.call("diagnostics"))
	return out


## "cloud" when the last turn's words came from the cloud session (whichever
## voice played them), "local" otherwise, "" before any turn.
func words_source() -> String:
	return _words_source


func speak_turn(turn: Dictionary, spoken_line_id: String = "") -> void:
	var text: String = String(turn.get("speech", "")).strip_edges()
	if _cloud != null and bool(_cloud.call("claim_reply_for_speech")):
		_words_source = "cloud"
		_begin_cloud(text)  # the provider's turn for the reply that is streaming
		return
	_words_source = "local"
	speak(text, spoken_line_id)


func speak(text: String, spoken_line_id: String = "") -> void:
	if _cloud != null and bool(_cloud.call("is_reply_open")):
		_cloud.call("barge_in")  # a new local line supersedes an open cloud reply
	_end_cloud_silently()
	_mode = MODE_INNER
	_current_text = text
	if _inner_can_speak():
		_inner.call("speak", text, spoken_line_id)
	else:
		# No voice at all: the subtitle still shows and `finished` still fires.
		_speaking = true
		started.emit(text)
		_finish_next_frame = true


func cancel() -> void:
	if _mode == MODE_CLOUD:
		if _cloud != null:
			_cloud.call("barge_in")
		_finish()
		return
	if _inner != null:
		_inner.call("cancel")  # its `finished` is forwarded
	elif _speaking:
		_finish()


func advance(delta: float) -> void:
	if _provider != null and _provider.has_method("advance"):
		_provider.call("advance", delta)
	elif _cloud != null:
		_cloud.call("advance", delta)
	if _inner != null:
		_inner.call("advance", delta)
	if _finish_next_frame:
		_finish_next_frame = false
		_finish()


# -- cloud reply ---------------------------------------------------------------------------------

func _begin_cloud(text: String) -> void:
	_mode = MODE_CLOUD
	_speaking = true
	_current_text = text
	started.emit(text)
	if bool(_cloud.call("is_reply_done")):
		# The reply finished before the scene asked: voice its words locally
		# when it had no audio, else it is already playing out.
		if not bool(_cloud.call("reply_had_audio")):
			_voice_final_locally()
		elif not bool(_cloud.call("is_speaking")):
			_finish_next_frame = true


func _on_cloud_speaking_changed(active: bool) -> void:
	if _mode != MODE_CLOUD or active:
		return
	if bool(_cloud.call("is_reply_open")):
		return  # a pause between chunks; the reply is still open
	if _cloud.has_method("is_replacing") and bool(_cloud.call("is_replacing")):
		return  # `reply_replaced` follows and voices the safe line
	_finish()


func _on_cloud_turn_ready(turn: Dictionary) -> void:
	if _mode != MODE_CLOUD:
		return
	_current_text = String(turn.get("speech", _current_text))
	if not bool(_cloud.call("reply_had_audio")):
		_voice_final_locally()


func _on_cloud_cancelled() -> void:
	if _mode == MODE_CLOUD:
		_finish()


func _on_cloud_replaced(turn: Dictionary) -> void:
	if _mode != MODE_CLOUD:
		return
	# Say the safe line through the local voice, then finish once.
	_mode = MODE_INNER
	_current_text = String(turn.get("speech", ""))
	if _inner_can_speak():
		_inner.call("speak", _current_text, "")
	else:
		_finish_next_frame = true


func _on_cloud_fell_back(_reason: String) -> void:
	if _mode == MODE_CLOUD:
		_finish()


func _voice_final_locally() -> void:
	_mode = MODE_INNER
	if _inner_can_speak() and not _current_text.is_empty():
		_inner.call("speak", _current_text, "")
	else:
		_finish_next_frame = true


## The wrapped provider exists and can speak; a missing voice degrades to
## silent text, never an error.
func _inner_can_speak() -> bool:
	return _inner != null and is_instance_valid(_inner) and _inner.has_method("speak")


func _on_inner_finished(text: String) -> void:
	if _mode == MODE_CLOUD:
		return
	_speaking = false
	_mode = MODE_NONE
	finished.emit(text)


func _end_cloud_silently() -> void:
	if _mode == MODE_CLOUD:
		_mode = MODE_NONE
		_speaking = false


func _finish() -> void:
	if not _speaking and _mode != MODE_CLOUD:
		return
	var text: String = _current_text
	_speaking = false
	_mode = MODE_NONE
	finished.emit(text)


func _wire() -> void:
	if _wired or _cloud == null:
		return
	_wired = true
	_cloud.speaking_changed.connect(_on_cloud_speaking_changed)
	_cloud.turn_ready.connect(_on_cloud_turn_ready)
	_cloud.cancelled.connect(_on_cloud_cancelled)
	_cloud.reply_replaced.connect(_on_cloud_replaced)
	_cloud.fell_back.connect(_on_cloud_fell_back)
