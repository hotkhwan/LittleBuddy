extends RefCounted

## VAD -- pure energy voice-activity detection for the hands-free tutor.
##
## No audio device, no timers, no nodes: the owner feeds one linear level
## (0..1 amplitude envelope) per frame with the frame's duration in ms and
## reads back events. That is why a headless test can drive a whole
## conversation of synthetic levels through it, and why the same object runs
## on any level source (the native plugin's input meter, a transport's server
## events, the dev "simulated child audio" panel).
##
## Rules (constants in `content/tutor/vad_profile_child.json`):
##   * adaptive noise floor: a running minimum -- it falls quickly to any
##     quieter level (the fan stops) and rises slowly towards a sustained
##     louder one (`risePerSecond`, a quarter of that while speech is being
##     tracked so a long sentence cannot lift the floor under itself), never
##     above `max`. A fan that starts therefore causes at most one short false
##     start before it is the floor;
##   * speech START = level above floor + `speechStart.marginAboveFloor` for at
##     least `minDurationMs` (120 ms) -- a shorter burst (a cough, a tap, a
##     single spike frame) is ignored and counted in `bursts_ignored()`;
##   * speech END = level back within `speechEnd.marginAboveFloor` of the floor
##     for `silenceMs` (900 ms), EXTENDED to `extendedSilenceMs` (1600 ms) when
##     the utterance so far is shorter than `shortUtteranceMs` (600 ms) or the
##     last partial transcript ends in a hesitation ("um", "the", ...) -- so a
##     child pausing mid-sentence is not cut off;
##   * LONG PAUSE = `longPauseMs` (3000 ms) of silence with no speech -> the
##     `long_pause` event: the owner re-prompts; it is never sent anywhere as a
##     reply;
##   * ECHO GATE while Aliz speaks: `set_gated(true)` + `update_playback_level()`
##     keep a smoothed estimate of the loudspeaker's level; a start then needs
##     level > estimate + `echoGate.marginAboveEstimate` for `echoGate.holdMs`
##     (200 ms). The maths is `barge_in_threshold()` / `echo_gate_passes()`,
##     public so a test can pin it.
##
## `feed(level, dt_ms)` returns the events of that frame as an Array of
## Strings (EVENT_*) and also emits them as signals; state is `state()`.

signal speech_started()
signal speech_ended(utterance_ms: float)
signal long_pause()

const PROFILE_PATH: String = "res://content/tutor/vad_profile_child.json"

const STATE_SILENCE: String = "silence"
const STATE_CANDIDATE: String = "candidate"
const STATE_SPEECH: String = "speech"
const STATE_TRAILING: String = "trailing"

const EVENT_SPEECH_STARTED: String = "speech_started"
const EVENT_SPEECH_ENDED: String = "speech_ended"
const EVENT_LONG_PAUSE: String = "long_pause"
const EVENT_BURST_IGNORED: String = "burst_ignored"

## The shipped child profile, verbatim, as the fallback when the JSON is absent.
const DEFAULT_PROFILE: Dictionary = {
	"frameMs": 20,
	"noiseFloor": {"initial": 0.02, "min": 0.005, "max": 0.4, "risePerSecond": 0.03, "risePerSecondDuringSpeech": 0.0075,
		"fallSecondsToTrack": 0.5},
	"speechStart": {"marginAboveFloor": 0.06, "minDurationMs": 120, "minBurstMs": 120},
	"speechEnd": {"marginAboveFloor": 0.02, "silenceMs": 900, "extendedSilenceMs": 1600, "shortUtteranceMs": 600,
		"hesitationWords": ["um", "uh", "er", "erm", "hmm", "a", "the", "and", "it's", "its", "i", "so"]},
	"longPauseMs": 3000,
	"echoGate": {"marginAboveEstimate": 0.08, "holdMs": 200, "estimateSmoothingSeconds": 0.15},
}

var _profile: Dictionary = {}
var _state: String = STATE_SILENCE
var _floor: float = 0.02
var _level: float = 0.0
var _above_ms: float = 0.0
var _utterance_ms: float = 0.0
var _below_ms: float = 0.0
var _silence_ms: float = 0.0
var _bursts_ignored: int = 0
var _last_partial: String = ""
var _gated: bool = false
var _echo_estimate: float = 0.0
var _echo_held_ms: float = 0.0
var _long_pause_announced: bool = false


func _init(profile: Dictionary = {}) -> void:
	_profile = profile if not profile.is_empty() else load_profile()
	reset()


## Reads the child profile; the constant when the file is missing/invalid.
static func load_profile() -> Dictionary:
	if FileAccess.file_exists(PROFILE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
		if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("speechStart"):
			return parsed
	return DEFAULT_PROFILE.duplicate(true)


func profile() -> Dictionary:
	return _profile


func reset() -> void:
	_state = STATE_SILENCE
	_floor = float(_section("noiseFloor").get("initial", 0.02))
	_level = 0.0
	_above_ms = 0.0
	_utterance_ms = 0.0
	_below_ms = 0.0
	_silence_ms = 0.0
	_last_partial = ""
	_echo_held_ms = 0.0
	_long_pause_announced = false


func state() -> String:
	return _state


func is_speech() -> bool:
	return _state == STATE_SPEECH or _state == STATE_TRAILING


func level() -> float:
	return _level


func noise_floor() -> float:
	return _floor


func bursts_ignored() -> int:
	return _bursts_ignored


func utterance_ms() -> float:
	return _utterance_ms


## The recogniser's latest interim text: a trailing hesitation extends the
## end-of-speech window. Dropped at every speech end; never stored elsewhere.
func set_last_partial(text: String) -> void:
	_last_partial = text


## Echo gate on/off (on while Aliz speaks).
func set_gated(gated: bool) -> void:
	if gated != _gated:
		_echo_held_ms = 0.0
	_gated = gated
	if gated:
		_silence_ms = 0.0  # Aliz's speaking time is not the child's pause


## Starts the long-pause clock over (the owner just asked a question).
func reset_pause_clock() -> void:
	_silence_ms = 0.0
	_long_pause_announced = false


func is_gated() -> bool:
	return _gated


## Smoothed loudspeaker level (what the mic will hear of Aliz herself).
func update_playback_level(playback_level: float, dt_ms: float) -> void:
	var tau: float = maxf(float(_section("echoGate").get("estimateSmoothingSeconds", 0.15)), 0.001)
	var k: float = clampf((dt_ms / 1000.0) / tau, 0.0, 1.0)
	_echo_estimate += (clampf(playback_level, 0.0, 1.0) - _echo_estimate) * k


## Seeds the estimate the moment playback starts, before the first echo
## reaches the mic (the smoothing then tracks from there).
func prime_playback_level(playback_level: float) -> void:
	_echo_estimate = maxf(_echo_estimate, clampf(playback_level, 0.0, 1.0))
	_echo_held_ms = 0.0


func echo_estimate() -> float:
	return _echo_estimate


## The level a start must exceed right now.
func start_threshold() -> float:
	var threshold: float = _floor + float(_section("speechStart").get("marginAboveFloor", 0.06))
	if _gated:
		threshold = maxf(threshold, barge_in_threshold())
	return threshold


## Echo-gated start threshold: estimate + margin (the maths, exposed).
func barge_in_threshold() -> float:
	return _echo_estimate + float(_section("echoGate").get("marginAboveEstimate", 0.08))


## Pure: does a level held above the echo threshold for `held_ms` count as
## the child, not the loudspeaker?
static func echo_gate_passes(level_value: float, estimate: float, margin: float, held_ms: float, hold_ms: float) -> bool:
	return level_value > estimate + margin and held_ms >= hold_ms


func end_threshold() -> float:
	return _floor + float(_section("speechEnd").get("marginAboveFloor", 0.02))


## How long the level must stay low for the current utterance to end.
func required_end_silence_ms() -> float:
	var end: Dictionary = _section("speechEnd")
	var base: float = float(end.get("silenceMs", 900))
	var extended: float = float(end.get("extendedSilenceMs", 1600))
	var spoken_ms: float = _utterance_ms - _below_ms
	if spoken_ms < float(end.get("shortUtteranceMs", 600)):
		return extended
	if ends_in_hesitation(_last_partial):
		return extended
	return base


func ends_in_hesitation(text: String) -> bool:
	var words: PackedStringArray = text.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		return false
	var last: String = words[words.size() - 1]
	var trimmed: String = ""
	for i: int in range(last.length()):
		var c: String = last[i]
		if c.is_valid_identifier() or c == "'":
			trimmed += c
	if trimmed.is_empty():
		return false
	if last.ends_with("...") or last.ends_with("-"):
		return true
	var list: Array = _section("speechEnd").get("hesitationWords", [])
	return list.has(trimmed)


## One frame. Returns the events of this frame (also emitted as signals).
func feed(level_value: float, dt_ms: float) -> Array:
	var events: Array = []
	if dt_ms <= 0.0:
		return events
	_level = clampf(level_value, 0.0, 1.0)
	_track_floor(dt_ms)
	var start_gate: float = start_threshold()
	var start_min_ms: float = float(_section("speechStart").get("minDurationMs", 120))
	if _gated:
		start_min_ms = maxf(start_min_ms, float(_section("echoGate").get("holdMs", 200)))

	match _state:
		STATE_SILENCE:
			if not _gated:
				_silence_ms += dt_ms
			if _level > start_gate:
				_state = STATE_CANDIDATE
				_above_ms = dt_ms
			elif _silence_ms >= float(_profile.get("longPauseMs", 3000)) and not _long_pause_announced:
				_long_pause_announced = true
				events.append(EVENT_LONG_PAUSE)
				long_pause.emit()
		STATE_CANDIDATE:
			if _level > start_gate:
				_above_ms += dt_ms
				if _above_ms >= start_min_ms:
					_state = STATE_SPEECH
					_utterance_ms = _above_ms
					_below_ms = 0.0
					_silence_ms = 0.0
					_long_pause_announced = false
					events.append(EVENT_SPEECH_STARTED)
					speech_started.emit()
			else:
				# Too short to be a word: a cough, a tap, a spike. Back to quiet.
				_bursts_ignored += 1
				_state = STATE_SILENCE
				events.append(EVENT_BURST_IGNORED)
		STATE_SPEECH, STATE_TRAILING:
			_utterance_ms += dt_ms
			if _level <= end_threshold():
				_below_ms += dt_ms
				_state = STATE_TRAILING
				if _below_ms >= required_end_silence_ms():
					var spoken: float = _utterance_ms - _below_ms
					_state = STATE_SILENCE
					_silence_ms = 0.0
					_utterance_ms = 0.0
					_below_ms = 0.0
					_last_partial = ""
					_long_pause_announced = false
					events.append(EVENT_SPEECH_ENDED)
					speech_ended.emit(spoken)
			else:
				# The pause was a breath, not the end: keep the utterance going.
				_below_ms = 0.0
				_state = STATE_SPEECH
	return events


## A running minimum: quickly down to a quieter level, slowly up towards a
## sustained louder one (slower still while speech is being tracked).
func _track_floor(dt_ms: float) -> void:
	var nf: Dictionary = _section("noiseFloor")
	var dt: float = dt_ms / 1000.0
	if _level < _floor:
		var k: float = clampf(dt / maxf(float(nf.get("fallSecondsToTrack", 0.5)), 0.001), 0.0, 1.0)
		_floor += (_level - _floor) * k
	else:
		var rate: float = float(nf.get("risePerSecond", 0.03))
		if _state == STATE_SPEECH or _state == STATE_TRAILING:
			rate = float(nf.get("risePerSecondDuringSpeech", 0.0075))
		_floor = minf(_floor + rate * dt, _level)
	_floor = clampf(_floor, float(nf.get("min", 0.005)), float(nf.get("max", 0.4)))


func _section(key: String) -> Dictionary:
	var value: Variant = _profile.get(key, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}
