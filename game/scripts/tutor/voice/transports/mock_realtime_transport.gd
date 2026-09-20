extends "res://scripts/tutor/voice/transports/realtime_transport.gd"

## MockRealtimeTransport -- deterministic, offline, synthetic.
##
## Answers every `send_text()` with the SCRIPTED provider's turn for that
## transcript, streamed the way a realtime backend streams: one text delta per
## word every `WORD_MS`, each with an audio-like envelope level (a raised
## cosine per word, height varied deterministically by the letters), then
## `response_done(turn)`. Time is whatever `advance(delta)` is fed, so a test
## controls it exactly. `cancel()` mid-stream stops at once, emits
## `response_cancelled`, and the words not yet streamed are dropped for good --
## the property the barge-in tests pin ("cancelled audio is never replayed").
## Nothing here touches a network, a microphone or a model.

const ScriptedProviderScript := preload("res://scripts/tutor/providers/scripted_conversation_provider.gd")

const WORD_MS: float = 180.0
const CONNECT_MS: float = 50.0

var _scripted: RefCounted = ScriptedProviderScript.new()
var _engine: Object = null
var _lesson_id: String = ""
var _connecting_ms: float = -1.0
var _pending_turn: Dictionary = {}
var _words: PackedStringArray = PackedStringArray()
var _word_index: int = 0
var _word_clock_ms: float = 0.0
var _streamed_text: String = ""
var _cancel_count: int = 0
var _dropped_words: int = 0
var _sent_texts: Array = []
var _audio_bytes_received: int = 0


func transport_name() -> String:
	return "mock"


func is_available() -> bool:
	return true


func set_engine(engine: Object) -> void:
	_engine = engine
	_scripted.set_engine(engine)


func scripted_provider() -> RefCounted:
	return _scripted


func sent_texts() -> Array:
	return _sent_texts.duplicate()


func cancel_count() -> int:
	return _cancel_count


func dropped_words() -> int:
	return _dropped_words


func streamed_text() -> String:
	return _streamed_text


func connect_session(token: Dictionary) -> bool:
	_lesson_id = String(token.get("lessonId", ""))
	if _engine == null:
		error.emit("no_engine", "mock transport needs a lesson engine")
		return false
	_scripted.begin_session(_lesson_id)
	_connecting_ms = 0.0
	return true


## Audio bytes are counted and discarded: the mock has no recogniser. The
## session uses the on-device transcript path with this transport.
func send_audio(pcm: PackedByteArray) -> bool:
	if not _open:
		return false
	_audio_bytes_received += pcm.size()
	return true


func send_text(text: String, lesson_context: Dictionary = {}) -> bool:
	if not _open or _responding:
		return false
	_sent_texts.append(text)
	var phase: String = String(lesson_context.get("phase", "answer"))
	var turn: Dictionary = TurnValidator.coerce(_scripted.build_turn(text, phase))
	_pending_turn = turn
	_words = String(turn.get("speech", "")).split(" ", false)
	_word_index = 0
	_word_clock_ms = 0.0
	_streamed_text = ""
	_responding = true
	return true


func cancel() -> void:
	if not _responding:
		return
	_dropped_words += _words.size() - _word_index
	_responding = false
	_pending_turn = {}
	_words = PackedStringArray()
	_cancel_count += 1
	response_cancelled.emit()


func close() -> void:
	cancel()
	_scripted.end_session()
	super.close()


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var ms: float = delta * 1000.0
	if _connecting_ms >= 0.0:
		_connecting_ms += ms
		if _connecting_ms >= CONNECT_MS:
			_connecting_ms = -1.0
			_open = true
			connected.emit({"transport": transport_name(), "lessonId": _lesson_id})
		return
	if not _responding:
		return
	_word_clock_ms += ms
	while _responding and _word_clock_ms >= WORD_MS:
		_word_clock_ms -= WORD_MS
		if _word_index >= _words.size():
			var done: Dictionary = _pending_turn
			_responding = false
			_pending_turn = {}
			response_done.emit(done)
			break
		var word: String = _words[_word_index]
		_word_index += 1
		_streamed_text = (_streamed_text + " " + word).strip_edges()
		response_text_delta.emit(word)
		response_audio_delta.emit(envelope_for_word(word), word.length() * 2 * 24)


## A raised-cosine peak per word, height 0.45..0.85 from the letters: an
## audio-like envelope that is never a flat metronome and always reproducible.
static func envelope_for_word(word: String) -> float:
	var sum: int = 0
	for i: int in range(word.length()):
		sum += word.unicode_at(i)
	return 0.45 + 0.4 * float(sum % 7) / 6.0
