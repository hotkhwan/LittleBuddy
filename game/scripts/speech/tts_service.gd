## Autoload facade for text-to-speech.
##
## Every English prompt the child hears goes through here. It uses Godot's
## built-in `DisplayServer` TTS (AVSpeechSynthesizer on iOS/macOS) when a voice
## is available, and always guarantees `speech_finished` fires -- via a safety
## timer -- so gameplay sequencing can never deadlock, even on a build with no
## TTS support at all.
##
## ## Why there is a queue in here
##
## `DisplayServer.tts_speak()` takes an `interrupt` flag as its LAST argument:
##
##     tts_speak(text, voice, volume, pitch, rate, utterance_id, interrupt)
##
## This service owns utterance ordering itself rather than relying on any
## platform's native queue: exactly one utterance is ever in flight, and the next
## one starts only when the current one is reported finished (natively, or by the
## safety timer). `speak(text, false)` therefore genuinely QUEUES -- two prompts
## can never talk over each other, and a queued prompt can never truncate the one
## before it. For a pre-reader a prompt that is cut off is a prompt that was
## never spoken.
##
## ## Child-friendly delivery
##
## Default adult TTS is too fast for a four-year-old meeting a word for the first
## time, so the default rate is deliberately below 1.0 and the parent-facing
## `ttsSpeed = "slow"` setting slows it further. Pitch is nudged very slightly up
## -- warm, not cartoonish.
##
## ## Degrading
##
## No TTS feature, no English voice, no SceneTree: `speak()` still emits
## `speech_started` / `speech_finished` with sensible pacing, so the on-screen
## text still advances silently and nothing crashes.
##
## Local synthesis only. No network, and the child's microphone is never involved.
extends Node

## Multiplier applied to the platform's default speaking rate.
## Slower than an adult default: the child is learning these words, not
## reviewing them. 1.0 would be the platform default.
const NORMAL_SPEECH_RATE: float = 0.85
## Parent setting `ttsSpeed = "slow"`. Noticeably slower, still natural.
const SLOW_SPEECH_RATE: float = 0.70

## Slightly-lifted pitch reads as friendly without sounding like a chipmunk.
const SPEECH_PITCH: float = 1.05

## 0-100. Prompts must sit clearly above the sound effects (which peak at
## -6 dBFS or lower); the platform default of 50 is easy to miss in a room with
## a child in it. Confirm comfort on device -- see the device checklist.
const SPEECH_VOLUME: int = 85

const MIN_DURATION_SECONDS: float = 0.6
const MAX_DURATION_SECONDS: float = 12.0
## ~150 wpm at rate 1.0; the estimate is divided by the current rate below.
const WORDS_PER_SECOND: float = 2.5

## The safety timer is a deadlock guard, not the normal path: when a native voice
## really is speaking, the platform's "utterance ended" callback should resolve
## first. Give it generous headroom so the timer cannot cut a prompt short.
const NATIVE_TIMEOUT_FACTOR: float = 1.6
const NATIVE_TIMEOUT_PAD_SECONDS: float = 0.8
## If the platform still reports itself speaking when the safety timer fires,
## wait this much longer rather than starting the next prompt over the top of it.
const TIMER_EXTENSION_SECONDS: float = 0.5
## Bounded so a platform that never stops reporting "speaking" cannot stall the
## queue permanently (10 s of extensions, then the queue moves on regardless).
const MAX_TIMER_EXTENSIONS: int = 20

## Nothing queued is ever silently dropped, but an unbounded queue would mean a
## child mashing a button could stack up a minute of speech. Oldest wins.
const MAX_QUEUED: int = 8

signal speech_started(text: String)
signal speech_finished(text: String)

var _initialised: bool = false
var _tts_feature_supported: bool = false
var _current_text: String = ""
var _is_speaking: bool = false
var _utterance_id: int = 0
var _current_utterance_id: int = 0
var _queue: Array[String] = []
## Set when the current utterance was handed to a real voice; drives how much
## headroom the safety timer gets.
var _current_used_native: bool = false
## Optional `func(duration: float, callback: Callable) -> void` used instead of a
## `SceneTreeTimer`. The headless test runner has no frame loop, so this is how
## the tests drive the queue one utterance at a time; production leaves it unset.
var _timer_factory: Callable = Callable()


func _ready() -> void:
	_ensure_initialised()


## Callable from anywhere: this service is an autoload in the game but is also
## constructed bare in the headless test runner, where `_ready()` never fires.
func _ensure_initialised() -> void:
	if _initialised:
		return
	_initialised = true
	_tts_feature_supported = _has_tts_feature()
	if _tts_feature_supported:
		DisplayServer.tts_set_utterance_callback(
			DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_ended
		)
		DisplayServer.tts_set_utterance_callback(
			DisplayServer.TTS_UTTERANCE_CANCELED, _on_utterance_canceled
		)


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------


## Speaks `text`.
##
## `interrupt = true` (default) replaces anything currently speaking AND anything
## queued behind it -- use it when a new prompt supersedes the old one.
## `interrupt = false` queues `text` to be spoken after the current utterance, so
## two prompts never overlap and neither is truncated.
func speak(text: String, interrupt: bool = true) -> void:
	_ensure_initialised()
	var line: String = text.strip_edges()
	if line.is_empty():
		return

	if interrupt:
		stop()
		_begin(line)
		return

	if _is_speaking:
		if _queue.size() >= MAX_QUEUED:
			return
		_queue.append(line)
		return

	_begin(line)


## Explicit alias for the queueing path, so call sites read as what they mean.
func enqueue(text: String) -> void:
	speak(text, false)


## Stops the current utterance and drops everything queued behind it.
## `speech_finished` still fires for the interrupted line so anything awaiting it
## is released rather than left hanging.
func stop() -> void:
	_ensure_initialised()
	_queue.clear()
	if _tts_feature_supported:
		DisplayServer.tts_stop()
	if _is_speaking:
		var text: String = _current_text
		_is_speaking = false
		_current_utterance_id = 0  # voids any in-flight safety timer
		_current_text = ""
		speech_finished.emit(text)


func is_available() -> bool:
	if not _has_tts_feature():
		return false
	return not _english_voices().is_empty()


func is_speaking() -> bool:
	return _is_speaking


func get_current_text() -> String:
	return _current_text


## Number of utterances waiting behind the current one.
func get_pending_count() -> int:
	return _queue.size()


func get_pending_texts() -> Array[String]:
	return _queue.duplicate()


## Advances the queue as if the platform had reported `utterance_id` finished.
##
## Called by the native utterance callbacks and by the safety timer. Public so
## the headless tests can drive the queue deterministically -- in `--script` runs
## there is no frame loop, so a `SceneTreeTimer` would never fire.
func notify_utterance_finished(utterance_id: int) -> void:
	_complete_utterance(utterance_id)


## The rate handed to the platform, for tests and diagnostics.
func get_speech_rate() -> float:
	return _speech_rate()


## Replaces the `SceneTreeTimer` used for the "utterance finished" safety net
## with `factory.call(duration: float, callback: Callable)`. A seam for the
## headless tests (no frame loop there, so a real timer would never fire).
func set_timer_factory(factory: Callable) -> void:
	_timer_factory = factory


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------


func _begin(text: String) -> void:
	_utterance_id += 1
	var utterance_id: int = _utterance_id
	_current_utterance_id = utterance_id
	_current_text = text
	_is_speaking = true
	_current_used_native = false

	speech_started.emit(text)

	if _tts_feature_supported:
		_current_used_native = _try_speak_native(text, utterance_id)

	# A started utterance is never left unresolved: either the platform reports
	# it, or this timer does.
	_schedule_fallback(utterance_id, _timeout_for(text, _current_used_native))


func _try_speak_native(text: String, utterance_id: int) -> bool:
	var voices: PackedStringArray = _english_voices()
	if voices.is_empty():
		return false

	# Argument order is (text, voice, volume, PITCH, RATE, utterance_id,
	# interrupt). Getting pitch and rate the wrong way round silently produces a
	# deeper adult voice at unchanged speed instead of a slower one -- which is
	# exactly the opposite of what a child learning the word needs.
	DisplayServer.tts_speak(
		text,
		voices[0],
		SPEECH_VOLUME,
		SPEECH_PITCH,
		_speech_rate(),
		utterance_id,
		true,  # ordering is owned here; only ever one utterance in flight
	)
	return true


func _english_voices() -> PackedStringArray:
	return DisplayServer.tts_get_voices_for_language("en")


## Reads the parent-facing "ttsSpeed" setting. Read defensively: SaveService may
## be absent (tests, a scene run on its own).
func _speech_rate() -> float:
	var save_service: Node = null
	if is_inside_tree():
		save_service = get_node_or_null("/root/SaveService")
	if save_service == null or not save_service.has_method("get_setting"):
		return NORMAL_SPEECH_RATE
	if str(save_service.call("get_setting", "ttsSpeed", "normal")) == "slow":
		return SLOW_SPEECH_RATE
	return NORMAL_SPEECH_RATE


func _schedule_fallback(
	utterance_id: int, duration: float, extensions_left: int = MAX_TIMER_EXTENSIONS
) -> void:
	var resolve: Callable = func() -> void: _on_safety_timeout(utterance_id, extensions_left)

	if _timer_factory.is_valid():
		_timer_factory.call(duration, resolve)
		return

	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree and is_inside_tree():
		var timer: SceneTreeTimer = (main_loop as SceneTree).create_timer(duration)
		timer.timeout.connect(resolve)
		return
	# No frame loop to run a timer in (headless `--script` runs, or a service
	# built outside the tree). Resolve immediately so a queue can still drain and
	# nothing awaiting `speech_finished` hangs forever.
	_complete_utterance(utterance_id)


## The safety timer fired. If a real voice is demonstrably still talking, wait a
## little longer rather than starting the next prompt over the top of it: the
## timer is only an estimate, and talking over the child's prompt is worse than
## a slightly longer pause. Bounded, so a platform that never stops reporting
## "speaking" cannot stall the queue forever.
func _on_safety_timeout(utterance_id: int, extensions_left: int) -> void:
	if utterance_id != _current_utterance_id or not _is_speaking:
		return
	if extensions_left > 0 and _current_used_native and _platform_is_speaking():
		_schedule_fallback(utterance_id, TIMER_EXTENSION_SECONDS, extensions_left - 1)
		return
	_complete_utterance(utterance_id)


func _platform_is_speaking() -> bool:
	if not _tts_feature_supported:
		return false
	return DisplayServer.tts_is_speaking()


func _complete_utterance(utterance_id: int) -> void:
	if utterance_id != _current_utterance_id:
		return  # a newer speak()/stop() already resolved this utterance
	if not _is_speaking:
		return
	var text: String = _current_text
	_is_speaking = false
	_current_utterance_id = 0
	_current_text = ""
	speech_finished.emit(text)
	_pump()


## Starts the next queued utterance, if any.
func _pump() -> void:
	if _is_speaking or _queue.is_empty():
		return
	_begin(_queue.pop_front())


func _on_utterance_ended(utterance_id: int) -> void:
	_complete_utterance(utterance_id)


func _on_utterance_canceled(utterance_id: int) -> void:
	_complete_utterance(utterance_id)


## How long to wait before assuming the platform will never report this
## utterance. When no voice spoke, this doubles as the pacing of silent text.
func _timeout_for(text: String, used_native: bool) -> float:
	var estimate: float = _estimate_duration(text)
	if not used_native:
		return estimate
	return estimate * NATIVE_TIMEOUT_FACTOR + NATIVE_TIMEOUT_PAD_SECONDS


## Spoken length estimate, scaled by the current rate: slower speech takes
## longer, and a timeout computed at rate 1.0 would truncate slow speech.
func _estimate_duration(text: String) -> float:
	var words: PackedStringArray = text.split(" ", false)
	var word_count: int = maxi(words.size(), 1)
	var rate: float = maxf(_speech_rate(), 0.1)
	var duration: float = float(word_count) / (WORDS_PER_SECOND * rate)
	return clampf(duration, MIN_DURATION_SECONDS, MAX_DURATION_SECONDS)


func _has_tts_feature() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
