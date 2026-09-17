extends RefCounted
## Measures every procedurally generated sound effect in `res://audio/sfx`.
##
## Audio cannot be "looked at" like a render, but it can be measured, and these
## are child-safety numbers rather than preferences:
##
##   * **Peak** -- each file is normalised to an exact designed level. Reward
##     sounds sit at -6 dBFS; incidental ones lower. Nothing approaches full
##     scale.
##   * **First/last sample** -- exactly 0. A non-zero first sample IS the click.
##     (Third-party CC0 packs were rejected for this project after measuring
##     peaks at -1.4 dBFS with a first sample at 0.86 of full scale: an audible
##     snap to a child holding the device 30 cm from their face.)
##   * **Attack** -- time to reach half the file's own peak. A sound that is
##     already loud in its first millisecond is startling however quiet its
##     average level is.
##   * **Max sample step** -- bounds any discontinuity in the middle of a file,
##     which a peak check alone would not catch.
##   * **Duration** -- short, and exactly what the generator designed.
##
## Files come from `tools/generate_sfx.gd`. Every sample is synthesised from sine
## partials in that script: no third-party audio, and therefore no licence
## surface at all.

const SFX_DIR: String = "res://audio/sfx"
const PLAYER_SCRIPT: String = "res://scripts/audio/sfx_player.gd"

## name -> { duration (s), peak_db, min_attack_ms }
## Measured from the bytes the generator wrote; see `generate_sfx.gd` output.
const EXPECTED: Dictionary = {
	"success_chime": {"duration": 0.620, "peak_db": -6.0, "min_attack_ms": 6.0},
	"soft_pop": {"duration": 0.160, "peak_db": -10.0, "min_attack_ms": 5.0},
	"pickup": {"duration": 0.150, "peak_db": -10.0, "min_attack_ms": 5.0},
	"place_soft": {"duration": 0.300, "peak_db": -11.0, "min_attack_ms": 6.0},
	"drop_return": {"duration": 0.320, "peak_db": -10.0, "min_attack_ms": 6.0},
	"room_change": {"duration": 0.550, "peak_db": -13.0, "min_attack_ms": 10.0},
	"sticker_unlock": {"duration": 0.780, "peak_db": -6.0, "min_attack_ms": 5.0},
	"star_earned": {"duration": 0.460, "peak_db": -6.0, "min_attack_ms": 5.0},
	"bedtime_chime": {"duration": 1.900, "peak_db": -9.0, "min_attack_ms": 60.0},
	"gentle_tap": {"duration": 0.080, "peak_db": -14.0, "min_attack_ms": 5.0},
}

const MIN_DURATION: float = 0.0
const MAX_DURATION: float = 3.0
## -6 dBFS is the loudest effect; allow a hair of slack for 16-bit rounding.
const MAX_PEAK: float = 0.52
## Absolute floor on the onset, whatever an individual file's design says.
const ABSOLUTE_MIN_ATTACK_MS: float = 5.0
## Largest permitted jump between two consecutive samples. The hottest existing
## file measures 0.261; anything appreciably above that is a discontinuity.
const MAX_SAMPLE_STEP: float = 0.30
## Peak level tolerance, in dB, around the designed normalisation target.
const PEAK_DB_TOLERANCE: float = 0.20
const DURATION_TOLERANCE: float = 0.01
const MAX_DC_OFFSET: float = 0.001
const SAMPLE_RATE: int = 22050
const DATA_OFFSET: int = 44


func test_name() -> String:
	return "audio_assets"


func run():
	var failures: Array = []

	var loader_script: Resource = load("res://scripts/audio/wav_loader.gd")
	if loader_script == null or not (loader_script is GDScript):
		failures.append("could not load res://scripts/audio/wav_loader.gd")
		return failures

	for sfx_name: String in EXPECTED.keys():
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

		if bytes.size() <= DATA_OFFSET:
			failures.append(
				"%s: file is empty or header-only (%d bytes)" % [sfx_name, bytes.size()]
			)
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
			failures.append(
				"%s: duration must be < %f s, got %f" % [sfx_name, MAX_DURATION, duration]
			)

		failures.append_array(_check_waveform(sfx_name, bytes))

	failures.append_array(_check_catalogue_matches_player())
	failures.append_array(_check_import_settings())
	return failures


## Everything above is measured on the source `.wav`. An exported build plays
## the *imported* sample instead, so the import must be lossless -- otherwise the
## peak and attack numbers proved here are not the numbers a child hears.
## (Godot 4.4+ defaults new WAV imports to QOA, which is lossy.)
func _check_import_settings():
	var problems: Array = []
	for sfx_name: String in EXPECTED.keys():
		var path: String = "%s/%s.wav.import" % [SFX_DIR, sfx_name]
		if not FileAccess.file_exists(path):
			continue  # source checkout without an editor import pass
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			problems.append("%s: could not read import settings" % sfx_name)
			continue
		var text: String = file.get_as_text()
		file.close()

		if not text.contains("compress/mode=0"):
			problems.append(
				"%s: import is not lossless PCM (compress/mode=0); the measured peak "
				% sfx_name
				+ "and attack would not survive to the device"
			)
		if text.contains("edit/normalize=true"):
			problems.append(
				"%s: import normalisation would undo the deliberate quiet level" % sfx_name
			)
		if not text.contains("edit/loop_mode=0"):
			problems.append("%s: a looping effect would never stop" % sfx_name)
	return problems


## Every number that matters, measured off the bytes on disk.
func _check_waveform(sfx_name: String, bytes: PackedByteArray):
	var problems: Array = []
	var frame_count: int = (bytes.size() - DATA_OFFSET) / 2
	if frame_count < 2:
		problems.append("%s: not enough audio frames" % sfx_name)
		return problems

	var expected: Dictionary = EXPECTED[sfx_name]

	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(frame_count)
	var peak: float = 0.0
	var sum: float = 0.0
	var max_step: float = 0.0
	for i in range(frame_count):
		var value: float = float(bytes.decode_s16(DATA_OFFSET + i * 2)) / 32768.0
		values[i] = value
		peak = maxf(peak, absf(value))
		sum += value
		if i > 0:
			max_step = maxf(max_step, absf(value - values[i - 1]))

	# -- Peak -----------------------------------------------------------------
	if peak <= 0.0:
		problems.append("%s: file is silent" % sfx_name)
		return problems
	if peak > MAX_PEAK:
		problems.append(
			"%s: peak %.3f exceeds the -6 dBFS child-safety ceiling" % [sfx_name, peak]
		)
	var peak_db: float = linear_to_db(peak)
	var expected_db: float = float(expected["peak_db"])
	if absf(peak_db - expected_db) > PEAK_DB_TOLERANCE:
		problems.append(
			"%s: peak %.2f dBFS, expected %.2f dBFS (+/- %.2f)"
			% [sfx_name, peak_db, expected_db, PEAK_DB_TOLERANCE]
		)

	# -- Boundaries: a non-zero first sample IS the click. --------------------
	if values[0] != 0.0:
		problems.append(
			"%s: first sample is %.4f, expected exactly 0 (click at start)"
			% [sfx_name, values[0]]
		)
	if values[frame_count - 1] != 0.0:
		problems.append(
			"%s: last sample is %.4f, expected exactly 0 (click at end)"
			% [sfx_name, values[frame_count - 1]]
		)

	# -- Attack ---------------------------------------------------------------
	var attack_frames: int = frame_count
	for i in range(frame_count):
		if absf(values[i]) >= peak * 0.5:
			attack_frames = i
			break
	var attack_ms: float = float(attack_frames) * 1000.0 / float(SAMPLE_RATE)
	var min_attack_ms: float = maxf(float(expected["min_attack_ms"]), ABSOLUTE_MIN_ATTACK_MS)
	if attack_ms < min_attack_ms:
		problems.append(
			"%s: attack %.2f ms is sharper than the %.2f ms minimum -- startling"
			% [sfx_name, attack_ms, min_attack_ms]
		)

	# The very first millisecond must still be near silence, even if the file
	# reaches half-peak slowly overall.
	var first_ms_frames: int = mini(int(SAMPLE_RATE / 1000), frame_count)
	var first_ms_peak: float = 0.0
	for i in range(first_ms_frames):
		first_ms_peak = maxf(first_ms_peak, absf(values[i]))
	if first_ms_peak > peak * 0.10:
		problems.append(
			"%s: reaches %.1f%% of peak within 1 ms -- audible snap"
			% [sfx_name, first_ms_peak / peak * 100.0]
		)

	# -- Continuity and DC ----------------------------------------------------
	if max_step > MAX_SAMPLE_STEP:
		problems.append(
			"%s: max sample-to-sample step %.4f exceeds %.4f (discontinuity)"
			% [sfx_name, max_step, MAX_SAMPLE_STEP]
		)
	var dc: float = sum / float(frame_count)
	if absf(dc) > MAX_DC_OFFSET:
		problems.append("%s: DC offset %.5f is too large" % [sfx_name, dc])

	# -- Duration -------------------------------------------------------------
	var duration: float = float(frame_count) / float(SAMPLE_RATE)
	if absf(duration - float(expected["duration"])) > DURATION_TOLERANCE:
		problems.append(
			"%s: duration %.3f s, expected %.3f s" % [sfx_name, duration, expected["duration"]]
		)

	return problems


## The measured catalogue and the names `SfxPlayer` exposes must be the same set:
## a constant with no file plays silence, and a file no constant names is dead
## weight nobody can trigger.
func _check_catalogue_matches_player():
	var problems: Array = []
	var script: Resource = load(PLAYER_SCRIPT)
	if script == null or not (script is GDScript):
		problems.append("could not load %s" % PLAYER_SCRIPT)
		return problems

	var player: Node = (script as GDScript).new()
	var known: Array = []
	for name in player.KNOWN_SFX:
		known.append(String(name))
	player.free()

	for name in EXPECTED.keys():
		if not known.has(String(name)):
			problems.append("%s is measured here but SfxPlayer.KNOWN_SFX does not list it" % name)
	for name in known:
		if not EXPECTED.has(String(name)):
			problems.append("SfxPlayer lists %s but it is never measured" % name)
	return problems
