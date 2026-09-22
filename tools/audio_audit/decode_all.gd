extends SceneTree
## Full-decode audit harness for the Little Days iOS audio crash investigation.
##
## For every audio stream that ships, this pulls EVERY frame through the real
## engine decoder (libvorbis for .ogg, the WAV sampler for .wav) via
## `AudioStreamPlayback.mix_audio()` and reports frame counts, peak sample,
## NaN/Inf counts and whether the stream reached its natural end.
##
## It exercises the three ways the game actually obtains a stream:
##   imported   - ResourceLoader.load() of the .import-ed resource (what the
##                exported iOS build uses)
##   raw        - AudioStreamOggVorbis.load_from_file() of the source .ogg
##                (audio_director.gd `_decode_source_file` fallback)
##   duplicated - imported.duplicate(true) with loop/loop_offset applied,
##                exactly as audio_director.gd `_apply_loop` does before play
##
## Plus a loop-wrap pass (decodes past the end so the loop seek is exercised)
## and a seek sweep (seeks are the classic trigger for a mid-stream libvorbis
## fault such as res2_inverse / vorbis_book_decodevv_add).
##
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##       --script /abs/path/tools/audio_audit/decode_all.gd
##
## Read-only: loads resources and decodes in memory. Writes nothing.

const CHUNK: int = 2048
const OGG_PATHS: Array[String] = [
	"res://audio/music/little_days_theme.ogg",
	"res://audio/music/hungry_bunny.ogg",
]
const SFX_DIR: String = "res://audio/sfx"

var _fail: int = 0


func _init() -> void:
	print("### GODOT ", Engine.get_version_info()["string"])
	print("### AudioServer mix_rate=", AudioServer.get_mix_rate(),
		" driver=", AudioServer.get_driver_name(),
		" speaker_mode=", AudioServer.get_speaker_mode())
	print("")

	for p in OGG_PATHS:
		_audit_ogg(p)

	_audit_sfx()

	print("")
	print("### FAILURES: ", _fail)
	quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------------------


func _audit_ogg(path: String) -> void:
	print("==========================================================")
	print("OGG ", path)
	if not FileAccess.file_exists(path):
		_bad("source file missing: " + path)
		return
	print("  sourceBytes=", FileAccess.get_file_as_bytes(path).size())

	# --- variant 1: the imported resource (this is what ships) -------------
	var imported: AudioStream = null
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path, "AudioStream")
		if res is AudioStream:
			imported = res
	if imported == null:
		_bad("ResourceLoader could not load " + path)
	else:
		_describe("imported", imported)
		_decode_to_end("imported", imported)
		_loop_wrap("imported", imported)
		_seek_sweep("imported", imported)
		_concurrent("imported", imported)

	# --- variant 2: raw .ogg parsed at runtime -----------------------------
	var raw: AudioStream = AudioStreamOggVorbis.load_from_file(path)
	if raw == null:
		_bad("AudioStreamOggVorbis.load_from_file returned null for " + path)
	else:
		_describe("raw", raw)
		_decode_to_end("raw", raw)

	# --- variant 3: deep duplicate + loop, as audio_director does ----------
	if imported != null:
		var dup: Resource = imported.duplicate(true)
		if dup is AudioStream:
			var d: AudioStream = dup as AudioStream
			if "loop" in d:
				d.set("loop", true)
			if "loop_offset" in d:
				d.set("loop_offset", 0.0)
			_describe("duplicated", d)
			_decode_to_end("duplicated", d)
		else:
			_bad("duplicate(true) did not return an AudioStream")

	# --- imported vs raw packet-sequence equivalence ------------------------
	if imported is AudioStreamOggVorbis and raw is AudioStreamOggVorbis:
		var a: OggPacketSequence = (imported as AudioStreamOggVorbis).get_packet_sequence()
		var b: OggPacketSequence = (raw as AudioStreamOggVorbis).get_packet_sequence()
		var same_pages: bool = a.packet_data.size() == b.packet_data.size()
		var pa: int = _count_packets(a)
		var pb: int = _count_packets(b)
		print("  packetSequence imported: pages=", a.packet_data.size(), " packets=", pa,
			" rate=", a.sampling_rate, " finalGranule=",
			(a.granule_positions[a.granule_positions.size() - 1] if a.granule_positions.size() > 0 else -1))
		print("  packetSequence raw     : pages=", b.packet_data.size(), " packets=", pb,
			" rate=", b.sampling_rate)
		if not same_pages or pa != pb:
			_bad("imported and raw packet sequences differ (pages %d/%d packets %d/%d)"
				% [a.packet_data.size(), b.packet_data.size(), pa, pb])
		else:
			print("  packetSequence: imported == raw  OK")
	print("")


func _count_packets(seq: OggPacketSequence) -> int:
	var n: int = 0
	for page in seq.packet_data:
		n += (page as Array).size()
	return n


func _describe(label: String, s: AudioStream) -> void:
	var extra: String = ""
	if s is AudioStreamOggVorbis:
		var o: AudioStreamOggVorbis = s as AudioStreamOggVorbis
		extra = " loop=%s loop_offset=%s bpm=%s beat_count=%s" % [
			o.has_loop(), o.get_loop_offset(), o.get_bpm(), o.get_beat_count()]
	elif s is AudioStreamWAV:
		var w: AudioStreamWAV = s as AudioStreamWAV
		extra = " mix_rate=%d stereo=%s format=%d loop_mode=%d loop_begin=%d loop_end=%d" % [
			w.mix_rate, w.stereo, w.format, w.loop_mode, w.loop_begin, w.loop_end]
	print("  [", label, "] class=", s.get_class(), " length=", s.get_length(), "s", extra)


## Decodes the whole stream to its natural end (loop forced off) and reports.
func _decode_to_end(label: String, stream: AudioStream) -> void:
	var s: AudioStream = stream
	# Force looping off on a private copy so the stream actually ends.
	var copy: Resource = s.duplicate(true)
	if copy is AudioStream:
		s = copy as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).set_loop(false)
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED

	var pb: AudioStreamPlayback = s.instantiate_playback()
	if pb == null:
		_bad(label + ": instantiate_playback() returned null")
		return

	var rate: float = AudioServer.get_mix_rate()
	var expected: int = int(round(s.get_length() * rate))
	var limit: int = expected + int(rate * 5.0) + CHUNK * 4

	pb.start(0.0)
	var frames: int = 0
	var peak: float = 0.0
	var nan_inf: int = 0
	var nonzero: int = 0
	var last_pos: float = -1.0
	var guard: int = 0
	while pb.is_playing() and frames < limit:
		var buf: PackedVector2Array = pb.mix_audio(1.0, CHUNK)
		if buf.size() == 0:
			guard += 1
			if guard > 4:
				break
			continue
		guard = 0
		for v in buf:
			var l: float = v.x
			var r: float = v.y
			if is_nan(l) or is_nan(r) or is_inf(l) or is_inf(r):
				nan_inf += 1
				continue
			var m: float = maxf(absf(l), absf(r))
			if m > peak:
				peak = m
			if m > 0.0000305:  # ~ 1 LSB of 16-bit
				nonzero += 1
		frames += buf.size()
		last_pos = pb.get_playback_position()

	var ended: bool = not pb.is_playing()
	var ratio: float = (float(frames) / float(expected)) if expected > 0 else 0.0
	print("  [", label, "] DECODE-TO-END frames=", frames, " expected~", expected,
		" ratio=", String.num(ratio, 4),
		" reachedEnd=", ended,
		" lastPos=", String.num(last_pos, 3), "s",
		" peak=", String.num(peak, 6),
		" nanInf=", nan_inf,
		" nonSilentFrames=", nonzero)

	if not ended:
		_bad(label + ": playback did not reach the end within " + str(limit) + " frames")
	if nan_inf > 0:
		_bad(label + ": " + str(nan_inf) + " NaN/Inf frames decoded")
	if peak <= 0.0:
		_bad(label + ": decoded silence (peak 0.0)")
	if peak > 1.5:
		_bad(label + ": peak " + str(peak) + " far outside [-1,1]")
	if expected > 0 and (ratio < 0.98 or ratio > 1.02):
		_bad(label + ": frame count " + str(frames) + " is " + String.num(ratio, 4)
			+ "x the expected " + str(expected))


## Decodes past the end so the loop wrap (a seek back into the stream) runs.
func _loop_wrap(label: String, stream: AudioStream) -> void:
	var s: AudioStream = stream
	var copy: Resource = s.duplicate(true)
	if copy is AudioStream:
		s = copy as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).set_loop(true)
		(s as AudioStreamOggVorbis).set_loop_offset(0.0)
	else:
		return

	var pb: AudioStreamPlayback = s.instantiate_playback()
	var rate: float = AudioServer.get_mix_rate()
	var target: int = int((s.get_length() + 6.0) * rate)  # 6 s past the end
	pb.start(0.0)
	var frames: int = 0
	var peak: float = 0.0
	var nan_inf: int = 0
	var stalls: int = 0
	while frames < target:
		if not pb.is_playing():
			_bad(label + ": looping stream stopped early at frame " + str(frames))
			break
		var buf: PackedVector2Array = pb.mix_audio(1.0, CHUNK)
		if buf.size() == 0:
			stalls += 1
			if stalls > 4:
				break
			continue
		stalls = 0
		for v in buf:
			if is_nan(v.x) or is_nan(v.y) or is_inf(v.x) or is_inf(v.y):
				nan_inf += 1
				continue
			peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
		frames += buf.size()
	print("  [", label, "] LOOP-WRAP  decoded=", frames, " frames (",
		String.num(float(frames) / rate, 2), "s over a ", String.num(s.get_length(), 2),
		"s stream) stillPlaying=", pb.is_playing(), " peak=", String.num(peak, 6),
		" nanInf=", nan_inf, " loopCount=", pb.get_loop_count())
	if nan_inf > 0:
		_bad(label + ": loop wrap produced " + str(nan_inf) + " NaN/Inf frames")
	if frames < target:
		_bad(label + ": loop wrap decoded only " + str(frames) + "/" + str(target) + " frames")


## Seeks all over the stream and decodes a short burst after each seek.
func _seek_sweep(label: String, stream: AudioStream) -> void:
	var s: AudioStream = stream
	var copy: Resource = s.duplicate(true)
	if copy is AudioStream:
		s = copy as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).set_loop(false)
	var length: float = s.get_length()
	var pb: AudioStreamPlayback = s.instantiate_playback()
	pb.start(0.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260922
	var positions: Array[float] = [
		0.0, 0.001, 0.5, length * 0.25, length * 0.5, length * 0.75,
		length - 1.0, length - 0.05, length - 0.001,
	]
	for i in range(40):
		positions.append(rng.randf() * length)

	var nan_inf: int = 0
	var peak: float = 0.0
	var decoded: int = 0
	var errors: int = 0
	for p in positions:
		var pos: float = clampf(p, 0.0, maxf(length - 0.0005, 0.0))
		pb.seek(pos)
		if not pb.is_playing():
			pb.start(pos)
		for _c in range(8):  # ~16k frames after each seek
			var buf: PackedVector2Array = pb.mix_audio(1.0, CHUNK)
			if buf.size() == 0:
				break
			for v in buf:
				if is_nan(v.x) or is_nan(v.y) or is_inf(v.x) or is_inf(v.y):
					nan_inf += 1
					continue
				peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
			decoded += buf.size()
	print("  [", label, "] SEEK-SWEEP ", positions.size(), " seeks, decoded=", decoded,
		" frames peak=", String.num(peak, 6), " nanInf=", nan_inf, " errors=", errors)
	if nan_inf > 0:
		_bad(label + ": seek sweep produced " + str(nan_inf) + " NaN/Inf frames")
	if decoded == 0:
		_bad(label + ": seek sweep decoded nothing")


## Four playbacks of the SAME AudioStreamOggVorbis (one shared, refcounted
## OggPacketSequence), started at different offsets and mixed round-robin.
## audio_director.gd crossfades with a 2-voice pool, so two AudioStreamPlayers
## can hold the same cached stream at once; this is that shape.
func _concurrent(label: String, stream: AudioStream) -> void:
	var length: float = stream.get_length()
	var playbacks: Array[AudioStreamPlayback] = []
	var offsets: Array[float] = [0.0, length * 0.33, length * 0.66, length - 2.0]
	for o in offsets:
		var pb: AudioStreamPlayback = stream.instantiate_playback()
		if pb == null:
			_bad(label + ": concurrent instantiate_playback() returned null")
			return
		pb.start(clampf(o, 0.0, maxf(length - 0.01, 0.0)))
		playbacks.append(pb)

	var nan_inf: int = 0
	var peak: float = 0.0
	var total: int = 0
	for _round in range(300):
		for pb in playbacks:
			if not pb.is_playing():
				pb.start(0.0)
			var buf: PackedVector2Array = pb.mix_audio(1.0, CHUNK)
			for v in buf:
				if is_nan(v.x) or is_nan(v.y) or is_inf(v.x) or is_inf(v.y):
					nan_inf += 1
					continue
				peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
			total += buf.size()
	print("  [", label, "] CONCURRENT ", playbacks.size(), " playbacks sharing one stream, decoded=",
		total, " frames peak=", String.num(peak, 6), " nanInf=", nan_inf)
	if nan_inf > 0:
		_bad(label + ": concurrent playback produced " + str(nan_inf) + " NaN/Inf frames")
	if total == 0:
		_bad(label + ": concurrent playback decoded nothing")


func _audit_sfx() -> void:
	print("==========================================================")
	print("SFX (WAV)")
	var dir: DirAccess = DirAccess.open(SFX_DIR)
	if dir == null:
		_bad("cannot open " + SFX_DIR)
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".wav"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()

	for n in names:
		var path: String = SFX_DIR + "/" + n
		var stream: AudioStream = null
		var how: String = ""
		if ResourceLoader.exists(path):
			var r: Resource = ResourceLoader.load(path, "AudioStream")
			if r is AudioStream:
				stream = r
				how = "imported"
		if stream == null:
			_bad(n + ": no importable stream")
			continue
		if stream is AudioStreamOggVorbis:
			_bad(n + ": WAV source imported as VORBIS -- unexpected, audit it")
		print("  ", n, " (", how, ")")
		_describe("  wav", stream)
		_decode_to_end("  " + n, stream)


func _bad(msg: String) -> void:
	_fail += 1
	print("  *** FINDING: ", msg)
