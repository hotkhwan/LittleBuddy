extends RefCounted
## Verifies the procedurally generated sound effects in `res://audio/sfx`.
##
## These files are produced by `tools/generate_sfx.gd`. The checks here are the
## child-safety contract for that generator: every effect must exist, be a
## valid 16-bit PCM mono WAVE, be short, start and end in silence (no click)
## and never approach full scale (nothing startling).

const SFX_DIR: String = "res://audio/sfx"

const EXPECTED_SFX: Array[String] = [
	"success_chime",
	"soft_pop",
	"pickup",
	"drop_return",
	"sticker_unlock",
	"star_earned",
	"bedtime_chime",
	"gentle_tap",
]

const MIN_DURATION: float = 0.0
const MAX_DURATION: float = 3.0
## -6 dBFS is the loudest effect; allow a hair of slack for 16-bit rounding.
const MAX_PEAK: float = 0.52


func test_name() -> String:
	return "audio_assets"


func run() -> Array:
	var failures: Array = []

	var loader_script: Resource = load("res://scripts/audio/wav_loader.gd")
	if loader_script == null or not (loader_script is GDScript):
		failures.append("could not load res://scripts/audio/wav_loader.gd")
		return failures

	for sfx_name in EXPECTED_SFX:
		var path: String = "%s/%s.wav" % [SFX_DIR, sfx_name]

		if not FileAccess.file_exists(path):
			failures.append("%s: missing (expected %s)" % [sfx_name, path])
			continue

		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			failures.append("%s: could not open %s" % [sfx_name, path])
			continue
		var bytes: PackedByteArray = file.get_buffer(file.get_length())
		file.close()

		if bytes.size() <= 44:
			failures.append("%s: file is empty or header-only (%d bytes)" % [sfx_name, bytes.size()])
			continue

		var stream: Variant = loader_script.parse(bytes)
		if stream == null:
			failures.append("%s: did not parse as a 16-bit PCM WAVE" % sfx_name)
			continue
		if not (stream is AudioStream):
			failures.append("%s: parsed value is not an AudioStream" % sfx_name)
			continue

		var wav: AudioStreamWAV = stream as AudioStreamWAV
		if wav.stereo:
			failures.append("%s: expected mono" % sfx_name)
		if wav.format != AudioStreamWAV.FORMAT_16_BITS:
			failures.append("%s: expected 16-bit format, got %d" % [sfx_name, wav.format])
		if wav.mix_rate != 22050 and wav.mix_rate != 44100:
			failures.append("%s: unexpected mix rate %d" % [sfx_name, wav.mix_rate])

		var duration: float = wav.get_length()
		if duration <= MIN_DURATION:
			failures.append("%s: duration must be > 0, got %f" % [sfx_name, duration])
		if duration >= MAX_DURATION:
			failures.append("%s: duration must be < %f s, got %f" % [sfx_name, MAX_DURATION, duration])

		failures.append_array(_check_waveform(sfx_name, bytes))

	return failures


## Peak / boundary checks straight off the bytes on disk.
func _check_waveform(sfx_name: String, bytes: PackedByteArray) -> Array:
	var problems: Array = []
	var data_offset: int = 44
	var frame_count: int = (bytes.size() - data_offset) / 2
	if frame_count < 2:
		problems.append("%s: not enough audio frames" % sfx_name)
		return problems

	var peak: float = 0.0
	for i in range(frame_count):
		var value: float = float(bytes.decode_s16(data_offset + i * 2)) / 32768.0
		peak = maxf(peak, absf(value))

	if peak <= 0.0:
		problems.append("%s: file is silent" % sfx_name)
	if peak > MAX_PEAK:
		problems.append(
			"%s: peak %.3f exceeds the -6 dBFS child-safety ceiling" % [sfx_name, peak]
		)

	var first: int = bytes.decode_s16(data_offset)
	var last: int = bytes.decode_s16(data_offset + (frame_count - 1) * 2)
	if first != 0:
		problems.append("%s: first sample is %d, expected 0 (click at start)" % [sfx_name, first])
	if last != 0:
		problems.append("%s: last sample is %d, expected 0 (click at end)" % [sfx_name, last])

	return problems
