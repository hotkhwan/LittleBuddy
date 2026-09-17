extends SceneTree
## Procedural sound-effect generator for Little Buddy.
##
## Every sample is synthesised here, in this file, from sine partials. Nothing
## is downloaded, sampled or derived from third-party material, and the script
## makes no network calls of any kind.
##
## Usage (writes into the project's `res://audio/sfx`):
##   godot --headless --path game --script res://../tools/generate_sfx.gd
##
## Usage (scratch project, explicit absolute output directory):
##   godot --headless --path /tmp/scratch --script res://generate_sfx.gd -- \
##       --out /abs/path/to/game/audio/sfx
##
## Design rules (these are child-safety rules, not preferences):
##   * 22050 Hz, mono, 16-bit PCM -- small files, plenty for soft chimes.
##   * Only sine partials arranged into consonant (major third / fifth /
##     octave) intervals. No noise, no dissonance, no square/saw edges.
##   * Every voice has a smooth attack (>= 6 ms) and an exponential decay that
##     is force-tapered to exactly zero before the voice ends.
##   * Every rendered buffer additionally gets a linear fade-in/fade-out at the
##     buffer boundary, so the first and last samples are always exactly 0 --
##     no click, no DC step.
##   * Peak-normalised well below full scale (-6 dBFS for reward sounds, lower
##     for incidental UI sounds). Never 0 dBFS, never clipped.

const SAMPLE_RATE: int = 22050
const BITS_PER_SAMPLE: int = 16
const CHANNELS: int = 1

## Linear fade applied at both ends of every finished buffer (seconds).
const EDGE_FADE_SEC: float = 0.008

## Fraction of a voice's length reserved for forcing its tail to silence.
const VOICE_TAIL_FRACTION: float = 0.18

## Minimum time a file may take to reach half of its own peak. A sound that is
## already loud in its first millisecond is a snap, and a snap 30 cm from a
## small child's face is startling however quiet the file's average level is.
## (This is why the CC0 packs were rejected: one measured its first sample at
## 0.86 of full scale.)
const MIN_ATTACK_SEC: float = 0.005

const DEFAULT_OUT_DIR: String = "res://audio/sfx"

# -- Note table (equal temperament, A4 = 440 Hz). -----------------------------
const C4: float = 261.626
const E4: float = 329.628
const G4: float = 391.995
const C5: float = 523.251
const E5: float = 659.255
const G5: float = 783.991
const A5: float = 880.000
const C6: float = 1046.502
const E6: float = 1318.510
const G6: float = 1567.982
const C7: float = 2093.005

## Soft, triangle-flavoured partial stack (odd harmonics, 1/n^2 falloff).
const TRIANGLE: Array = [[1.0, 1.0], [3.0, 0.111], [5.0, 0.04]]
## Gentle bell: fundamental plus a fifth and an octave -- consonant, no beating.
const BELL: Array = [[1.0, 1.0], [1.5, 0.38], [2.0, 0.18]]
## Almost-pure sine with a whisper of second harmonic for warmth.
const WARM: Array = [[1.0, 1.0], [2.0, 0.14]]
## Very soft low chime.
const SOFT_LOW: Array = [[1.0, 1.0], [2.0, 0.12], [3.0, 0.05]]


func _initialize() -> void:
	var out_dir: String = _resolve_out_dir()
	print("generate_sfx: writing to %s" % out_dir)

	if not _ensure_dir(out_dir):
		printerr("generate_sfx: could not create output directory %s" % out_dir)
		quit(1)
		return

	var failures: Array[String] = []
	var total_bytes: int = 0

	for spec in _specs():
		var name: String = spec["name"]
		var samples: PackedFloat32Array = _render(spec)
		var path: String = out_dir.path_join("%s.wav" % name)
		if not _write_wav(path, samples):
			failures.append("%s: write failed" % name)
			continue

		var report: Dictionary = _verify(path, samples)
		total_bytes += int(report.get("bytes", 0))
		if report.has("error"):
			failures.append("%s: %s" % [name, report["error"]])
			continue

		print(
			(
				"  %-18s %6.3f s  %6d B  peak %6.2f dBFS  attack %5.1f ms"
				+ "  edges %d/%d  max-step %.4f  dc %+.5f"
			)
			% [
				name,
				report["duration"],
				report["bytes"],
				report["peak_db"],
				report["attack"] * 1000.0,
				report["first_sample"],
				report["last_sample"],
				report["max_step"],
				report["dc_offset"],
			]
		)

	print("")
	print("generate_sfx: %d file(s), %d bytes total" % [_specs().size(), total_bytes])
	if failures.is_empty():
		print("generate_sfx: OK")
		quit(0)
	else:
		for failure in failures:
			printerr("generate_sfx: %s" % failure)
		quit(1)


# -----------------------------------------------------------------------------
# Effect definitions
# -----------------------------------------------------------------------------
#
# A spec is { name, length (seconds), peak_db, voices: [ ... ] }.
# A voice is { start, dur, freq, freq_end (optional glide target), amp,
#              attack, partials }.


func _specs() -> Array:
	return [
		{
			# Warm ascending major arpeggio: C5 - E5 - G5.
			"name": "success_chime",
			"length": 0.62,
			"peak_db": -6.0,
			"voices":
			[
				_voice(0.00, 0.32, C5, 1.00, 0.014, TRIANGLE),
				_voice(0.10, 0.34, E5, 0.90, 0.014, TRIANGLE),
				_voice(0.20, 0.40, G5, 0.85, 0.014, TRIANGLE),
			],
		},
		{
			# Short soft pop: a quick upward bend, no transient edge.
			"name": "soft_pop",
			"length": 0.16,
			"peak_db": -10.0,
			"voices": [_glide(0.0, 0.15, 380.0, 700.0, 1.0, 0.010, WARM)],
		},
		{
			# Gentle pickup blip: A5 with a soft major-third-above shimmer.
			"name": "pickup",
			"length": 0.15,
			"peak_db": -10.0,
			"voices":
			[
				_voice(0.00, 0.14, A5, 1.00, 0.012, WARM),
				_voice(0.01, 0.12, E6, 0.32, 0.012, WARM),
			],
		},
		{
			# Return-to-origin: a soft descending fifth, G5 down to C5.
			"name": "drop_return",
			"length": 0.32,
			"peak_db": -10.0,
			"voices": [_glide(0.0, 0.30, G5, C5, 1.0, 0.016, TRIANGLE)],
		},
		{
			# Object settles where it belongs: a stable major third, C5 + E5.
			# Deliberately NOT the descending fifth of `drop_return` -- landing in
			# the right place and sliding back home must not sound alike.
			"name": "place_soft",
			"length": 0.30,
			"peak_db": -11.0,
			"voices":
			[
				_voice(0.00, 0.26, C5, 1.00, 0.016, WARM),
				_voice(0.05, 0.22, E5, 0.55, 0.016, WARM),
			],
		},
		{
			# Walking into another room: an open, unhurried rising fifth, C5 - G5.
			# Incidental, so quieter than any reward sound; it happens a lot.
			"name": "room_change",
			"length": 0.55,
			"peak_db": -13.0,
			"voices":
			[
				_voice(0.00, 0.34, C5, 1.00, 0.030, SOFT_LOW),
				_voice(0.16, 0.36, G5, 0.70, 0.030, SOFT_LOW),
			],
		},
		{
			# Sparkle: four quick rising partials, C6 - E6 - G6 - C7.
			"name": "sticker_unlock",
			"length": 0.78,
			"peak_db": -6.0,
			"voices":
			[
				_voice(0.00, 0.30, C6, 0.95, 0.008, WARM),
				_voice(0.06, 0.30, E6, 0.85, 0.008, WARM),
				_voice(0.12, 0.32, G6, 0.78, 0.008, WARM),
				_voice(0.18, 0.40, C7, 0.62, 0.008, WARM),
			],
		},
		{
			# Bright but short reward chime: E6 bell with a fifth above.
			"name": "star_earned",
			"length": 0.46,
			"peak_db": -6.0,
			"voices": [_voice(0.0, 0.44, E6, 1.0, 0.009, BELL)],
		},
		{
			# Calming bedtime chord: C4 - G4 - C5, slow swell, long tail.
			"name": "bedtime_chime",
			"length": 1.90,
			"peak_db": -9.0,
			"voices":
			[
				_voice(0.00, 1.88, C4, 1.00, 0.260, SOFT_LOW),
				_voice(0.22, 1.62, G4, 0.58, 0.300, SOFT_LOW),
				_voice(0.46, 1.38, C5, 0.42, 0.300, SOFT_LOW),
			],
		},
		{
			# Very soft UI tick: quiet, consonant, barely there.
			"name": "gentle_tap",
			"length": 0.08,
			"peak_db": -14.0,
			"voices":
			[
				_voice(0.00, 0.070, C6, 1.00, 0.006, WARM),
				_voice(0.00, 0.050, G6, 0.26, 0.006, WARM),
			],
		},
	]


func _voice(
	start: float, dur: float, freq: float, amp: float, attack: float, partials: Array
) -> Dictionary:
	return {
		"start": start,
		"dur": dur,
		"freq": freq,
		"freq_end": freq,
		"amp": amp,
		"attack": attack,
		"partials": partials,
	}


func _glide(
	start: float,
	dur: float,
	freq_from: float,
	freq_to: float,
	amp: float,
	attack: float,
	partials: Array
) -> Dictionary:
	return {
		"start": start,
		"dur": dur,
		"freq": freq_from,
		"freq_end": freq_to,
		"amp": amp,
		"attack": attack,
		"partials": partials,
	}


# -----------------------------------------------------------------------------
# Synthesis
# -----------------------------------------------------------------------------


func _render(spec: Dictionary) -> PackedFloat32Array:
	var length: float = float(spec["length"])
	var frame_count: int = int(round(length * SAMPLE_RATE))
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(frame_count)

	for voice in spec["voices"]:
		_mix_voice(buffer, voice)

	_remove_dc(buffer)
	# Fade first, normalise second: the fade can only ever reduce a sample, so
	# normalising afterwards guarantees the final peak is exactly `peak_db`
	# while the (already zeroed) boundary samples stay at exactly zero.
	_apply_edge_fade(buffer)
	_normalise(buffer, float(spec["peak_db"]))
	return buffer


## Additive sine synthesis with a per-partial running phase, a smooth
## (smoothstep) attack and an exponential decay that is force-tapered to zero.
func _mix_voice(buffer: PackedFloat32Array, voice: Dictionary) -> void:
	var frame_count: int = buffer.size()
	var start_frame: int = int(round(float(voice["start"]) * SAMPLE_RATE))
	var voice_frames: int = int(round(float(voice["dur"]) * SAMPLE_RATE))
	if voice_frames <= 1:
		return

	var partials: Array = voice["partials"]
	var phases: PackedFloat64Array = PackedFloat64Array()
	phases.resize(partials.size())

	var f_from: float = float(voice["freq"])
	var f_to: float = float(voice["freq_end"])
	var amp: float = float(voice["amp"])
	var attack: float = maxf(float(voice["attack"]), 0.004)
	var dur: float = float(voice["dur"])
	attack = minf(attack, dur * 0.5)

	# Decay constant so the exponential reaches ~0.1% by the end of the voice.
	var decay_span: float = maxf(dur - attack, 0.001)
	var decay_rate: float = 6.9 / decay_span
	var tail: float = maxf(dur * VOICE_TAIL_FRACTION, 0.004)

	for i in range(voice_frames):
		var frame: int = start_frame + i
		if frame < 0:
			continue
		if frame >= frame_count:
			break

		var t: float = float(i) / SAMPLE_RATE
		var progress: float = float(i) / float(voice_frames - 1)

		# Envelope.
		var env: float
		if t < attack:
			env = smoothstep(0.0, 1.0, t / attack)
		else:
			env = exp(-decay_rate * (t - attack))
		# Force the tail to exactly zero so no voice ends on a discontinuity.
		var remaining: float = dur - t
		if remaining < tail:
			env *= smoothstep(0.0, 1.0, maxf(remaining, 0.0) / tail)

		# Frequency glide (linear in log space -- musically even).
		var freq: float = f_from
		if not is_equal_approx(f_from, f_to):
			freq = f_from * pow(f_to / f_from, progress)

		var value: float = 0.0
		for p in range(partials.size()):
			var partial: Array = partials[p]
			var mult: float = float(partial[0])
			var level: float = float(partial[1])
			phases[p] += TAU * float(freq * mult) / float(SAMPLE_RATE)
			if phases[p] > TAU:
				phases[p] -= TAU
			value += sin(phases[p]) * level

		buffer[frame] += value * env * amp


func _remove_dc(buffer: PackedFloat32Array) -> void:
	if buffer.is_empty():
		return
	var sum: float = 0.0
	for v in buffer:
		sum += v
	var mean: float = sum / float(buffer.size())
	if absf(mean) < 1e-7:
		return
	for i in range(buffer.size()):
		buffer[i] -= mean


## Peak-normalise to `peak_db` dBFS. Never reaches full scale.
func _normalise(buffer: PackedFloat32Array, peak_db: float) -> void:
	var peak: float = 0.0
	for v in buffer:
		peak = maxf(peak, absf(v))
	if peak <= 0.0:
		return
	var target: float = db_to_linear(peak_db)
	var gain: float = target / peak
	for i in range(buffer.size()):
		buffer[i] *= gain


## Linear fade at both boundaries so sample[0] and sample[n-1] are exactly 0.
func _apply_edge_fade(buffer: PackedFloat32Array) -> void:
	var n: int = buffer.size()
	if n < 4:
		return
	var fade: int = mini(int(EDGE_FADE_SEC * SAMPLE_RATE), n / 4)
	fade = maxi(fade, 2)
	for i in range(fade):
		var k: float = float(i) / float(fade)
		buffer[i] *= k
		buffer[n - 1 - i] *= k
	buffer[0] = 0.0
	buffer[n - 1] = 0.0


# -----------------------------------------------------------------------------
# RIFF/WAVE writing (hand-written header -- canonical 44-byte PCM form)
# -----------------------------------------------------------------------------


func _write_wav(path: String, samples: PackedFloat32Array) -> bool:
	var data_bytes: int = samples.size() * CHANNELS * (BITS_PER_SAMPLE / 8)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("generate_sfx: cannot open %s (%d)" % [path, FileAccess.get_open_error()])
		return false

	# RIFF chunk descriptor.
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_bytes)
	file.store_buffer("WAVE".to_ascii_buffer())

	# "fmt " sub-chunk (16 bytes, PCM).
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)  # audioFormat: 1 == PCM integer
	file.store_16(CHANNELS)
	file.store_32(SAMPLE_RATE)
	file.store_32(SAMPLE_RATE * CHANNELS * (BITS_PER_SAMPLE / 8))  # byteRate
	file.store_16(CHANNELS * (BITS_PER_SAMPLE / 8))  # blockAlign
	file.store_16(BITS_PER_SAMPLE)

	# "data" sub-chunk.
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_bytes)
	for v in samples:
		file.store_16(_to_pcm16(v) & 0xFFFF)

	file.close()
	return true


func _to_pcm16(value: float) -> int:
	var clamped: float = clampf(value, -1.0, 1.0)
	return clampi(int(round(clamped * 32767.0)), -32768, 32767)


# -----------------------------------------------------------------------------
# Verification (runs on the bytes that actually landed on disk)
# -----------------------------------------------------------------------------


func _verify(path: String, expected: PackedFloat32Array) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot re-open for verification"}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	if bytes.size() < 44:
		return {"error": "file too small (%d bytes)" % bytes.size()}
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {"error": "missing RIFF tag"}
	if bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {"error": "missing WAVE tag"}
	if bytes.decode_u16(20) != 1:
		return {"error": "not PCM"}
	if bytes.decode_u16(22) != CHANNELS:
		return {"error": "not mono"}
	if bytes.decode_u32(24) != SAMPLE_RATE:
		return {"error": "unexpected sample rate"}
	if bytes.decode_u16(34) != BITS_PER_SAMPLE:
		return {"error": "not 16-bit"}

	var declared: int = bytes.decode_u32(40)
	if declared != bytes.size() - 44:
		return {"error": "data chunk size %d != actual %d" % [declared, bytes.size() - 44]}
	if declared != expected.size() * 2:
		return {"error": "sample count mismatch"}

	var frame_count: int = declared / 2
	var peak: float = 0.0
	var max_step: float = 0.0
	var sum: float = 0.0
	var previous: float = 0.0
	var first: int = 0
	var last: int = 0
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(frame_count)

	for i in range(frame_count):
		var raw: int = bytes.decode_s16(44 + i * 2)
		if i == 0:
			first = raw
		if i == frame_count - 1:
			last = raw
		var v: float = float(raw) / 32768.0
		values[i] = v
		peak = maxf(peak, absf(v))
		sum += v
		if i > 0:
			max_step = maxf(max_step, absf(v - previous))
		previous = v

	if peak <= 0.0:
		return {"error": "silent file"}
	if peak > 0.72:  # > -2.8 dBFS would be far too hot for a child's ear
		return {"error": "peak too hot (%.3f)" % peak}
	if first != 0 or last != 0:
		return {"error": "boundary samples are not zero (%d/%d)" % [first, last]}

	# Attack: how long the file takes to reach half of its own peak.
	var attack_frames: int = frame_count
	var half: float = peak * 0.5
	for i in range(frame_count):
		if absf(values[i]) >= half:
			attack_frames = i
			break
	var attack: float = float(attack_frames) / float(SAMPLE_RATE)
	if attack < MIN_ATTACK_SEC:
		return {"error": "attack too sharp (%.4f s, minimum %.4f s)" % [attack, MIN_ATTACK_SEC]}

	return {
		"bytes": bytes.size(),
		"duration": float(frame_count) / float(SAMPLE_RATE),
		"peak_db": linear_to_db(peak),
		"attack": attack,
		"max_step": max_step,
		"dc_offset": sum / float(frame_count),
		"first_sample": first,
		"last_sample": last,
	}


# -----------------------------------------------------------------------------
# Plumbing
# -----------------------------------------------------------------------------


func _resolve_out_dir() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("--out="):
			return args[i].substr(6)
	return DEFAULT_OUT_DIR


func _ensure_dir(dir_path: String) -> bool:
	if DirAccess.dir_exists_absolute(dir_path):
		return true
	return DirAccess.make_dir_recursive_absolute(dir_path) == OK
