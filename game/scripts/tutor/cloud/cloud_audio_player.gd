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
## queued frame has played. Nothing is persisted; the queue is memory only.

signal level_changed(level: float)
signal drained()

const SAMPLE_RATE: int = 24000
const BUS_VOICE: String = "Voice"
const GENERATOR_BUFFER_SECONDS: float = 0.5

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


func _ready() -> void:
	_ensure_player()


func _process(delta: float) -> void:
	advance(delta)


## Tests: keep the virtual clock, skip the audio device entirely.
func set_device_enabled(enabled: bool) -> void:
	_device_enabled = enabled


func push_pcm16(bytes: PackedByteArray) -> void:
	if bytes.size() < 2:
		return
	_queue.append_array(pcm16_to_frames(bytes))
	_complete = false
	_drained_emitted = false
	_ensure_player()
	if _player != null and not _player.playing:
		_player.play()
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func mark_complete() -> void:
	_complete = true


func truncate() -> void:
	_queue = PackedFloat32Array()
	_cursor = 0
	_pushed_frames = 0
	_level = 0.0
	_complete = true
	_drained_emitted = true
	if _player != null and _player.playing:
		_player.stop()
	_playback = null
	level_changed.emit(0.0)


## Resets the played position for a new reply (the queue must be empty).
func begin_reply() -> void:
	truncate()
	_played_frames = 0
	_complete = false


func played_ms() -> float:
	return float(_played_frames) * 1000.0 / float(SAMPLE_RATE)


func queued_ms() -> float:
	return float(maxi(_queue.size() - _cursor, 0)) * 1000.0 / float(SAMPLE_RATE)


func level() -> float:
	return _level


func is_playing_audio() -> bool:
	return _cursor < _queue.size()


func has_audio() -> bool:
	return not _queue.is_empty()


## The virtual clock: consume this frame's worth, measure it, push it out.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var remaining: int = _queue.size() - _cursor
	if remaining <= 0:
		if _level != 0.0:
			_level = 0.0
			level_changed.emit(0.0)
		if _complete and not _drained_emitted:
			_drained_emitted = true
			if _player != null and _player.playing and (_playback == null or _playback.get_frames_available() >= int(float(SAMPLE_RATE) * GENERATOR_BUFFER_SECONDS) - 8):
				_player.stop()
			drained.emit()
		return
	var count: int = mini(int(round(delta * float(SAMPLE_RATE))), remaining)
	if count <= 0:
		return
	var sum: float = 0.0
	for i: int in range(count):
		var sample: float = _queue[_cursor + i]
		sum += sample * sample
	_level = clampf(sqrt(sum / float(count)), 0.0, 1.0)
	if _playback != null and _device_enabled:
		var room: int = _playback.get_frames_available()
		var to_push: int = mini(count, room)
		for i: int in range(to_push):
			var sample: float = _queue[_cursor + i]
			_playback.push_frame(Vector2(sample, sample))
		_pushed_frames += to_push
	_cursor += count
	_played_frames += count
	level_changed.emit(_level)
	if _cursor >= _queue.size() and _complete and not _drained_emitted:
		# The last sample played this frame: say so now, not a frame late.
		_drained_emitted = true
		_level = 0.0
		level_changed.emit(0.0)
		if _player != null and _player.playing:
			_player.stop()
		drained.emit()


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
