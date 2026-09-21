extends Node

## CloudAudioPlayer -- plays the PCM16 mono 24 kHz chunks a realtime reply
## streams, with truncation for barge-in and a per-frame level for the mouth.
##
## The deltas arrive faster than real time, so playback runs on a VIRTUAL
## CLOCK: `advance(delta)` consumes `delta * 24000` frames from the queue,
## measures their RMS (`level()`, `level_changed`), pushes them to an
## `AudioStreamGenerator` on the Voice bus when an audio device exists, and
## keeps `played_ms()` -- the position `conversation.item.truncate` reports.
## Headless the device is absent and the clock still runs, so the tests and
## the lip sync behave the same with or without a speaker.
##
## `truncate()` drops everything not yet played and stops the stream at once
## (the barge-in rule: cancelled audio is never replayed). `mark_complete()`
## says the reply has no more chunks; `drained` fires once when the last
## queued frame has been HEARD. Nothing is persisted; the queue is memory only.
##
## ## Chunk boundaries (2026-09-21, "cut or broken" replies)
##
## Three things in the first version could cut a reply, all with a device:
##   * frames the generator had no room for were skipped but still counted
##     as played (a frame hitch dropped audio) -- now the clock consumes at
##     most what the device can take and waits otherwise;
##   * the player was stopped the instant the virtual clock reached the end,
##     while up to `GENERATOR_BUFFER_SECONDS` of the tail still sat in the
##     device buffer -- `drained` now waits for that buffer to empty;
##   * playback began on the first delta, so any gap between deltas starved
##     the device (an audible hole mid-word) -- playback now starts, and
##     resumes after a starve, only with `MIN_LEAD_SECONDS` queued or the
##     reply complete. 120 ms covers one late chunk of network jitter and is
##     below the 200 ms echo-gate hold, so it adds no perceptible latency.
## Counters (`diagnostics()`): chunks and frames received, frames played and
## pushed, underruns, truncations, drains, time spent waiting for a lead.
## Without a device (headless, the suite) the clock is unchanged: the lead
## exists to protect the device buffer, and `force_lead_for_tests()` turns it
## on for the one case that pins it.

signal level_changed(level: float)
signal drained()

const SAMPLE_RATE: int = 24000
const BUS_VOICE: String = "Voice"
const GENERATOR_BUFFER_SECONDS: float = 0.5
const MIN_LEAD_SECONDS: float = 0.12
## The generator's ring buffer keeps one slot in reserve; a few more frames of
## slack (about 10 ms) so "empty" is read the same on every mix step.
const DRAIN_SLACK_FRAMES: int = 256

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _queue: PackedFloat32Array = PackedFloat32Array()
var _cursor: int = 0
var _played_frames: int = 0
var _pushed_frames: int = 0
var _level: float = 0.0
var _complete: bool = false
var _drained_emitted: bool = true
var _device_enabled: bool = true
var _force_lead: bool = false
## The clock is running for this reply (a lead was reached once).
var _started: bool = false
## The clock ran out of frames mid-reply and waits for a new lead.
var _starved: bool = false
var _diag: Dictionary = {"chunksReceived": 0, "framesReceived": 0, "framesPlayed": 0, "framesPushed": 0,
	"underruns": 0, "truncations": 0, "drains": 0, "waitedForLeadMs": 0.0, "lastLeadMs": 0.0, "replies": 0}


func _ready() -> void:
	_ensure_player()


func _process(delta: float) -> void:
	advance(delta)


## Tests: keep the virtual clock, skip the audio device entirely.
func set_device_enabled(enabled: bool) -> void:
	_device_enabled = enabled


## Tests: apply the start/resume lead without a device.
func force_lead_for_tests(forced: bool) -> void:
	_force_lead = forced


func push_pcm16(bytes: PackedByteArray) -> void:
	if bytes.size() < 2:
		return
	var frames: PackedFloat32Array = pcm16_to_frames(bytes)
	_queue.append_array(frames)
	_complete = false
	_drained_emitted = false
	_diag["chunksReceived"] = int(_diag["chunksReceived"]) + 1
	_diag["framesReceived"] = int(_diag["framesReceived"]) + frames.size()
	_ensure_player()
	# The device starts in advance(), once a lead is queued -- never here.


func mark_complete() -> void:
	_complete = true


func truncate() -> void:
	if _cursor < _queue.size() or (_started and not _drained_emitted):
		_diag["truncations"] = int(_diag["truncations"]) + 1
	_queue = PackedFloat32Array()
	_cursor = 0
	_pushed_frames = 0
	_level = 0.0
	_complete = true
	_drained_emitted = true
	_started = false
	_starved = false
	if _player != null and _player.playing:
		_player.stop()
	_playback = null
	level_changed.emit(0.0)


## Resets the played position for a new reply (the queue must be empty).
func begin_reply() -> void:
	truncate()
	_played_frames = 0
	_complete = false
	_diag["replies"] = int(_diag["replies"]) + 1


func played_ms() -> float:
	return float(_played_frames) * 1000.0 / float(SAMPLE_RATE)


func queued_ms() -> float:
	return float(maxi(_queue.size() - _cursor, 0)) * 1000.0 / float(SAMPLE_RATE)


func level() -> float:
	return _level


## True until the reply has been HEARD: frames still queued, or pushed frames
## the device has not finished sounding.
func is_playing_audio() -> bool:
	if _cursor < _queue.size():
		return true
	return _started and not _drained_emitted


func has_audio() -> bool:
	return not _queue.is_empty()


## Counters only: no audio, no text.
func diagnostics() -> Dictionary:
	var out: Dictionary = _diag.duplicate()
	out["queuedMs"] = snappedf(queued_ms(), 0.1)
	out["playedMs"] = snappedf(played_ms(), 0.1)
	out["started"] = _started
	out["starved"] = _starved
	return out


## The virtual clock: consume this frame's worth, measure it, push it out.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var remaining: int = _queue.size() - _cursor
	if remaining <= 0:
		if _started and not _complete and not _starved:
			# Mid-reply and nothing left to play: the network is behind.
			_starved = true
			_diag["underruns"] = int(_diag["underruns"]) + 1
		if _level != 0.0:
			_level = 0.0
			level_changed.emit(0.0)
		if _complete and not _drained_emitted:
			_try_drain()
		return
	if (not _started or _starved) and _lead_required():
		if queued_ms() < MIN_LEAD_SECONDS * 1000.0 and not _complete:
			_diag["waitedForLeadMs"] = float(_diag["waitedForLeadMs"]) + delta * 1000.0
			return
	if not _started or _starved:
		_diag["lastLeadMs"] = snappedf(queued_ms(), 0.1)
	_started = true
	_starved = false
	if _player != null and _device_enabled and not _player.playing:
		_player.play()
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	var count: int = mini(int(round(delta * float(SAMPLE_RATE))), remaining)
	if _playback != null and _device_enabled:
		# Never skip what the device cannot take: the clock waits instead.
		count = mini(count, _playback.get_frames_available())
	if count <= 0:
		return
	var sum: float = 0.0
	for i: int in range(count):
		var sample: float = _queue[_cursor + i]
		sum += sample * sample
	_level = clampf(sqrt(sum / float(count)), 0.0, 1.0)
	if _playback != null and _device_enabled:
		for i: int in range(count):
			var sample: float = _queue[_cursor + i]
			_playback.push_frame(Vector2(sample, sample))
		_pushed_frames += count
		_diag["framesPushed"] = int(_diag["framesPushed"]) + count
	_cursor += count
	_played_frames += count
	_diag["framesPlayed"] = int(_diag["framesPlayed"]) + count
	level_changed.emit(_level)
	if _cursor >= _queue.size():
		if _complete and not _drained_emitted:
			_try_drain()
		elif not _complete and not _starved:
			# Consumed the last queued frame mid-reply: the next chunk is late.
			# Noted now, not a frame later, so the resume waits for a lead.
			_starved = true
			_diag["underruns"] = int(_diag["underruns"]) + 1


## `drained` only once the DEVICE has sounded the tail: stopping the player
## while its buffer still holds frames discards the last words of the reply.
## Without a device the last virtual frame is the end.
func _try_drain() -> void:
	if _player != null and _device_enabled and _player.playing and _playback != null:
		var capacity: int = int(float(SAMPLE_RATE) * GENERATOR_BUFFER_SECONDS)
		if _playback.get_frames_available() < capacity - DRAIN_SLACK_FRAMES:
			return  # still sounding; asked again next frame
	_drained_emitted = true
	_started = false
	_starved = false
	if _level != 0.0:
		_level = 0.0
		level_changed.emit(0.0)
	if _player != null and _player.playing:
		_player.stop()
	_playback = null
	_diag["drains"] = int(_diag["drains"]) + 1
	drained.emit()


func _lead_required() -> bool:
	return _force_lead or (_device_enabled and _player != null)


static func pcm16_to_frames(bytes: PackedByteArray) -> PackedFloat32Array:
	var count: int = bytes.size() / 2
	var frames: PackedFloat32Array = PackedFloat32Array()
	frames.resize(count)
	for i: int in range(count):
		frames[i] = float(bytes.decode_s16(i * 2)) / 32768.0
	return frames


func _ensure_player() -> void:
	if _player != null or not _device_enabled:
		return
	if not is_inside_tree():
		return
	_player = AudioStreamPlayer.new()
	_player.name = "CloudVoice"
	var generator: AudioStreamGenerator = AudioStreamGenerator.new()
	generator.mix_rate = float(SAMPLE_RATE)
	generator.buffer_length = GENERATOR_BUFFER_SECONDS
	_player.stream = generator
	if AudioServer.get_bus_index(BUS_VOICE) >= 0:
		_player.bus = BUS_VOICE
	add_child(_player)
