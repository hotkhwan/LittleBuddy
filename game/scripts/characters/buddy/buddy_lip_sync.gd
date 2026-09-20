extends Node

## ============================================================================
## LIP SYNC SOURCE -- reads the loudness of what is actually playing and drives
## Aliz's mouth with it. Never a fixed timer.
## ============================================================================
##
## Three inputs, one output (`set_mouth_open(amount)` on the target, which is
## `pink_girl_buddy.gd` and, through it, `buddy_mouth.gd`'s smoothing):
##
## 1. **A bus, captured.** `attach(player)` / `attach_bus(name)` put an
##    `AudioEffectCapture` on that bus. Every frame the frames captured since
##    the last one are read, their RMS taken, and that RMS normalised by a slow
##    automatic gain: the running peak decays at `AGC_DECAY_PER_SEC`, so a
##    quiet voice after a loud one still opens the mouth fully within a second
##    or two, and a floor stops room noise from becoming speech. Above the gate
##    the normalised level is the mouth amount. When the attached player is
##    not playing the amount is forced to 0 at once -- the mouth's own release
##    (90 ms) then shuts it, well inside the 120 ms the contract allows.
##
## 2. **A synthetic envelope.** `drive_from_envelope(samples, sample_rate)`
##    pushes a mono buffer through exactly the same RMS -> AGC -> gate ->
##    amount pipeline in 1/60 s chunks, stepping the target's mouth each chunk,
##    and returns the amounts. That is how the headless test proves the
##    pipeline without an audio device.
##
## 3. **The platform voice.** When speech comes from `TtsService`'s native
##    synthesiser there is no stream in the engine to capture. `attach_tts()`
##    listens to `speech_started(text)` / `speech_finished(text)` and, between
##    them, plays a SYLLABLE-RATE PSEUDO-ENVELOPE derived from the text: one
##    raised-cosine bump per vowel group at the service's words-per-second, a
##    gap at each space and a longer one at punctuation, bump heights varied
##    deterministically by the letters so it never looks like a metronome.
##    **This is the honest fallback**: it is timed from the text, not measured
##    from the sound, and it says so here. It still stops with the audio --
##    `speech_finished` or `is_speaking()` going false zeroes it -- and when
##    the service is playing a RECORDED line through its own player on the
##    Voice bus, the captured bus wins over the pseudo-envelope.
##
## Nothing here persists or uploads audio; the capture buffer is read, reduced
## to one number, and discarded.
##
## Public: `set_target(node)`, `attach(player) -> bool`, `attach_bus(name) -> bool`,
## `attach_tts(tts = /root/TtsService) -> bool`, `detach()`,
## `drive_from_envelope(samples, sample_rate) -> PackedFloat32Array`,
## `amount_for_rms(rms, seconds) -> float`, `pseudo_envelope_for(text, rate) -> PackedFloat32Array`,
## `level()`, `is_capturing()`, `describe() -> Dictionary`.

const ENVELOPE_STEP_SEC: float = 1.0 / 60.0
## After a stream stops, the amount is 0 no later than this (contract: 120 ms).
const STOP_GRACE_SEC: float = 0.12
## RMS below this (full scale 1.0) is silence, whatever the gain says.
const NOISE_FLOOR: float = 0.004
## The AGC peak never falls below this, so silence cannot pump the gain up to
## the point where the floor itself reads as speech.
const AGC_MIN_PEAK: float = 0.03
## The peak keeps this fraction of itself per second: slow, so a sentence's
## quiet syllables read against its loud ones, not against themselves.
const AGC_DECAY_PER_SEC: float = 0.45
## Normalised level below this is a closed mouth.
const GATE: float = 0.10
## Shapes the level -> amount curve; < 1 lifts the quiet middle of speech.
const CURVE: float = 0.7
## The pseudo-envelope: syllables per second at rate 1.0 (TtsService's 2.5
## words per second, ~1.5 syllables a word), and the gaps.
const SYLLABLES_PER_SEC: float = 3.75
const WORD_GAP_SEC: float = 0.06
const PUNCTUATION_GAP_SEC: float = 0.22
const PSEUDO_SAMPLE_RATE: float = 60.0

var _target: Node = null
var _bus_index: int = -1
var _capture: AudioEffectCapture = null
var _player: AudioStreamPlayer = null
var _agc_peak: float = AGC_MIN_PEAK
var _level: float = 0.0
var _amount: float = 0.0
var _tts: Node = null
var _pseudo: PackedFloat32Array = PackedFloat32Array()
var _pseudo_time: float = 0.0
var _pseudo_active: bool = false


func _ready() -> void:
	if _target == null:
		var parent: Node = get_parent()
		if parent != null and parent.has_method("set_mouth_open"):
			_target = parent
	set_process(_capture != null or _pseudo_active)


## Whoever has `set_mouth_open(amount)` (and, ideally, `step_mouth(seconds)`
## for envelope replay). Defaults to the parent.
func set_target(node: Node) -> void:
	_target = node


## Captures the bus `player` plays on, and forces 0 whenever it is not playing.
func attach(player: AudioStreamPlayer) -> bool:
	if player == null:
		return false
	if not attach_bus(String(player.bus)):
		return false
	_player = player
	if not player.finished.is_connected(_on_player_finished):
		player.finished.connect(_on_player_finished)
	return true


## Adds an `AudioEffectCapture` to `bus_name` (reusing one already there).
func attach_bus(bus_name: String) -> bool:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return false
	detach()
	_bus_index = index
	for slot: int in range(AudioServer.get_bus_effect_count(index)):
		var effect: AudioEffect = AudioServer.get_bus_effect(index, slot)
		if effect is AudioEffectCapture:
			_capture = effect as AudioEffectCapture
			break
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.1
		AudioServer.add_bus_effect(index, _capture)
	_agc_peak = AGC_MIN_PEAK
	set_process(true)
	return true


## Follows the platform voice through its start/finish signals.
func attach_tts(tts: Node = null) -> bool:
	var service: Node = tts
	if service == null and is_inside_tree():
		service = get_tree().root.get_node_or_null("TtsService")
	if service == null or not service.has_signal("speech_started") \
			or not service.has_signal("speech_finished"):
		return false
	if _tts != null and _tts != service:
		_disconnect_tts()
	_tts = service
	if not _tts.speech_started.is_connected(_on_speech_started):
		_tts.speech_started.connect(_on_speech_started)
	if not _tts.speech_finished.is_connected(_on_speech_finished):
		_tts.speech_finished.connect(_on_speech_finished)
	return true


## Removes the capture effect and stops following the player; the TTS
## connection stays (call `detach_tts()` for that). Zeroes the mouth.
func detach() -> void:
	if _bus_index >= 0 and _capture != null:
		for slot: int in range(AudioServer.get_bus_effect_count(_bus_index)):
			if AudioServer.get_bus_effect(_bus_index, slot) == _capture:
				AudioServer.remove_bus_effect(_bus_index, slot)
				break
	if _player != null and _player.finished.is_connected(_on_player_finished):
		_player.finished.disconnect(_on_player_finished)
	_capture = null
	_player = null
	_bus_index = -1
	_push(0.0)
	set_process(_pseudo_active)


func detach_tts() -> void:
	_disconnect_tts()
	_pseudo_active = false
	_pseudo = PackedFloat32Array()
	_push(0.0)


func is_capturing() -> bool:
	return _capture != null


## The last normalised level (0..1, before the gate) and amount pushed.
func level() -> float:
	return _level


func amount() -> float:
	return _amount


func describe() -> Dictionary:
	return {
		"capturing": _capture != null,
		"bus": AudioServer.get_bus_name(_bus_index) if _bus_index >= 0 else "",
		"player": _player != null,
		"tts": _tts != null,
		"pseudoActive": _pseudo_active,
		"agcPeak": _agc_peak,
		"level": _level,
		"amount": _amount,
	}


func _process(delta: float) -> void:
	var amount: float = 0.0
	var captured: bool = false
	if _capture != null:
		if _player != null and not _player.playing:
			_agc_settle(delta)
			amount = 0.0
			_capture.clear_buffer()
		else:
			var rms: float = _read_rms()
			amount = amount_for_rms(rms, delta)
			captured = rms > NOISE_FLOOR
	if _pseudo_active:
		var recording: bool = _tts != null and _tts.has_method("is_playing_recording") \
				and bool(_tts.call("is_playing_recording"))
		if _tts != null and _tts.has_method("is_speaking") and not bool(_tts.call("is_speaking")):
			_pseudo_active = false
		elif not (recording and _capture != null):
			amount = maxf(amount, _pseudo_at(delta))
		elif captured:
			# The recording is captured off the bus; keep the pseudo clock moving
			# so a later native line starts from the right place.
			_pseudo_time += delta
	_push(amount)
	if _capture == null and not _pseudo_active:
		set_process(false)


## One captured frame's worth of audio -> RMS (0..1, mono of the stereo pair).
func _read_rms() -> float:
	var frames: int = _capture.get_frames_available()
	if frames <= 0:
		return 0.0
	var buffer: PackedVector2Array = _capture.get_buffer(frames)
	var acc: float = 0.0
	for sample: Vector2 in buffer:
		var mono: float = 0.5 * (sample.x + sample.y)
		acc += mono * mono
	return sqrt(acc / maxf(float(buffer.size()), 1.0))


## RMS -> mouth amount through the slow AGC and the gate. `seconds` is how
## much time this measurement covers (the AGC decays by it). Pure apart from
## the AGC state, so a test can feed it numbers.
func amount_for_rms(rms: float, seconds: float) -> float:
	_agc_settle(seconds)
	if rms <= NOISE_FLOOR:
		_level = 0.0
		return 0.0
	_agc_peak = maxf(_agc_peak, rms)
	_level = clampf(rms / _agc_peak, 0.0, 1.0)
	if _level < GATE:
		return 0.0
	return pow((_level - GATE) / (1.0 - GATE), CURVE)


func _agc_settle(seconds: float) -> void:
	_agc_peak = maxf(AGC_MIN_PEAK, _agc_peak * pow(AGC_DECAY_PER_SEC, maxf(seconds, 0.0)))


## Replays a mono buffer through the pipeline in 1/60 s chunks, stepping the
## target's mouth for each, and returns the amount pushed per chunk. Silence
## at the end of the buffer (or a buffer that ends) leaves the amount at 0.
func drive_from_envelope(samples: PackedFloat32Array, sample_rate: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var chunk: int = maxi(1, int(round(sample_rate * ENVELOPE_STEP_SEC)))
	var at: int = 0
	_agc_peak = AGC_MIN_PEAK
	while at < samples.size():
		var end: int = mini(samples.size(), at + chunk)
		var acc: float = 0.0
		for k: int in range(at, end):
			acc += samples[k] * samples[k]
		var rms: float = sqrt(acc / float(end - at))
		var amount: float = amount_for_rms(rms, ENVELOPE_STEP_SEC)
		_push(amount)
		_step_target(ENVELOPE_STEP_SEC)
		out.append(amount)
		at = end
	_push(0.0)
	_step_target(ENVELOPE_STEP_SEC)
	return out


# ---------------------------------------------------------------------------
# the platform-voice fallback
# ---------------------------------------------------------------------------

func _on_speech_started(text: String) -> void:
	var rate: float = 1.0
	if _tts != null and _tts.has_method("get_speech_rate"):
		rate = maxf(0.25, float(_tts.call("get_speech_rate")))
	_pseudo = pseudo_envelope_for(text, rate)
	_pseudo_time = 0.0
	_pseudo_active = _pseudo.size() > 0
	set_process(true)


func _on_speech_finished(_text: String) -> void:
	_pseudo_active = false
	_pseudo = PackedFloat32Array()
	_push(0.0)


func _on_player_finished() -> void:
	_push(0.0)


## The amount of the pseudo-envelope at the current clock, advanced by
## `delta`. Past the end of the estimate (the platform spoke slower than
## guessed) it wraps at two-thirds height rather than stopping short; the
## finish signal is what stops it.
func _pseudo_at(delta: float) -> float:
	if _pseudo.is_empty():
		return 0.0
	var index: int = int(_pseudo_time * PSEUDO_SAMPLE_RATE)
	var value: float
	if index < _pseudo.size():
		value = _pseudo[index]
	else:
		value = 0.66 * _pseudo[index % _pseudo.size()]
	_pseudo_time += delta
	return value


## `text` -> a 60 Hz amplitude envelope: one raised-cosine bump per syllable,
## heights 0.55..1.0 chosen by the letters, gaps at spaces and punctuation.
static func pseudo_envelope_for(text: String, rate: float = 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var syllable_sec: float = 1.0 / (SYLLABLES_PER_SEC * maxf(rate, 0.25))
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return out
	var words: PackedStringArray = trimmed.split(" ", false)
	for word: String in words:
		var count: int = _syllables(word)
		for s: int in range(count):
			var seed: int = 0
			for c: int in range(word.length()):
				seed = (seed * 31 + word.unicode_at(c) + s * 7) % 1000003
			var height: float = 0.55 + 0.45 * float(seed % 100) / 99.0
			_append_bump(out, syllable_sec, height)
		var last: String = word.substr(word.length() - 1) if word.length() > 0 else ""
		var gap: float = PUNCTUATION_GAP_SEC if last in [".", ",", "!", "?", ";", ":"] \
				else WORD_GAP_SEC
		_append_silence(out, gap / maxf(rate, 0.25))
	return out


static func _syllables(word: String) -> int:
	var lower: String = word.to_lower()
	var count: int = 0
	var in_vowel: bool = false
	for c: int in range(lower.length()):
		var vowel: bool = lower.substr(c, 1) in ["a", "e", "i", "o", "u", "y"]
		if vowel and not in_vowel:
			count += 1
		in_vowel = vowel
	# A trailing silent "e" ("cake", "blue" has "ue") is still counted; close
	# enough for a mouth. Every word has at least one beat.
	return maxi(1, count)


static func _append_bump(out: PackedFloat32Array, seconds: float, height: float) -> void:
	var n: int = maxi(2, int(round(seconds * PSEUDO_SAMPLE_RATE)))
	for k: int in range(n):
		var phase: float = float(k) / float(n - 1)
		out.append(height * 0.5 * (1.0 - cos(TAU * phase)))


static func _append_silence(out: PackedFloat32Array, seconds: float) -> void:
	for _k: int in range(int(round(seconds * PSEUDO_SAMPLE_RATE))):
		out.append(0.0)


# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------

func _push(amount: float) -> void:
	_amount = clampf(amount, 0.0, 1.0)
	if _target != null and _target.has_method("set_mouth_open"):
		_target.call("set_mouth_open", _amount)


func _step_target(seconds: float) -> void:
	if _target != null and _target.has_method("step_mouth"):
		_target.call("step_mouth", seconds)


func _disconnect_tts() -> void:
	if _tts == null:
		return
	if _tts.speech_started.is_connected(_on_speech_started):
		_tts.speech_started.disconnect(_on_speech_started)
	if _tts.speech_finished.is_connected(_on_speech_finished):
		_tts.speech_finished.disconnect(_on_speech_finished)
	_tts = null
