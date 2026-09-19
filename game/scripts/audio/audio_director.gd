class_name AudioDirector
extends Node
## The game's one audio authority: background music, the mixer, and mute.
##
##     var audio := AudioDirector.new()
##     add_child(audio)
##     audio.bind_sfx_player(get_node_or_null("/root/Sfx"))
##     audio.set_state(AudioDirector.STATE_HOUSE)
##
## It is a plain `Node`, not a singleton. Instantiate it, compose it into a scene,
## or register it as an autoload -- all three work, and the tests use the first.
##
## ## The normal case today is that there is no music at all
##
## No track file exists in this repository yet. Every path through this class
## treats that as ordinary: `set_state()` succeeds, reports honestly that nothing
## is playing, emits `track_unavailable` once, and produces no engine error and no
## repeated warning. The game must be as complete and as pleasant silent as it is
## with a soundtrack, and it is this class's job to make "no music" a supported
## configuration rather than a degraded one.
##
## ## What it will not do
##
## Play a track the manifest has not cleared for commercial use. `MusicManifest`
## owns that gate (it fails closed); this class simply never assigns a stream it
## has not asked about. A licence refusal is warned about exactly once per track,
## because unlike a missing file it means something is wrong.
##
## ## Levels
##
## Three trims -- master, music, sfx -- in decibels, each able only to ATTENUATE
## (`MAX_TRIM_DB` is 0). The music total is additionally capped at
## `MusicManifest.MAX_VOLUME_DB`, so music can never reach the level of a spoken
## prompt however the trims are set. Mute is separate from the trims, so muting
## and unmuting restores the mix exactly.
##
## ## Fades run through `advance()`
##
## `_process()` only forwards to `advance(delta)`. That keeps the crossfade
## testable in the headless runner, where the tree never iterates and nothing can
## actually be mixed.
##
## No network. No microphone. Playback only.

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------

## The musical situation changed. `state` is one of the `STATE_*` constants.
signal music_state_changed(state: String)
## A track began fading in.
signal track_started(track_id: String)
## Music is fading out and nothing is replacing it.
signal music_stopped()
## A track the state wanted could not be played. `reason` is a
## `MusicManifest.REFUSAL_*` code -- `fileMissing` is the expected one today.
## Emitted once per track per director, so a caller can surface it in a
## diagnostics panel without it becoming a per-frame log.
signal track_unavailable(track_id: String, reason: String)
## The mix changed (trim or mute). Carries the effective values.
signal mix_changed(master_db: float, music_db: float, sfx_db: float, muted: bool)

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

const MusicCatalogue := preload("res://scripts/audio/music_manifest.gd")
const BgmMachine := preload("res://scripts/audio/bgm_state_machine.gd")

const STATE_SILENT: String = BgmMachine.STATE_SILENT
const STATE_MENU: String = BgmMachine.STATE_MENU
const STATE_HOUSE: String = BgmMachine.STATE_HOUSE
const STATE_MINI_GAME: String = BgmMachine.STATE_MINI_GAME
const STATE_REWARD: String = BgmMachine.STATE_REWARD

## Trims attenuate only. Nothing in this game gets louder than the level its
## asset was authored at.
const MAX_TRIM_DB: float = 0.0
const MIN_TRIM_DB: float = -60.0
## At or below this, a voice is treated as silent and stopped outright rather
## than left running at an inaudible level.
const SILENCE_DB: float = -59.0
## What a stopped voice's `volume_db` reads as.
const OFF_DB: float = -80.0

## Two voices is all a crossfade needs.
const VOICE_COUNT: int = 2

## Profile setting consulted before music plays, mirroring `SfxPlayer`'s use of
## `soundEnabled`. A parent turning sound off must silence music too.
const SOUND_ENABLED_SETTING: String = "soundEnabled"
const SAVE_SERVICE_PATH: String = "/root/SaveService"
## The existing `SfxPlayer` autoload, bound automatically when present.
const SFX_AUTOLOAD_PATH: String = "/root/Sfx"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

@export var manifest_path: String = MusicCatalogue.DEFAULT_MANIFEST_PATH
## Overall trim on everything.
@export var master_volume_db: float = 0.0
## Music trim, on top of each track's own `volumeDb`.
@export var music_volume_db: float = 0.0
## Sound-effect trim, forwarded to a bound `SfxPlayer`.
@export var sfx_volume_db: float = 0.0
@export var muted: bool = false
## Turn off to cut straight to the new track's target level. Off by default it is
## not: see `bgm_state_machine.gd` on why hard cuts are banned here.
@export var crossfade_enabled: bool = true
## Emit one engine warning when a track is refused for a licence reason *and* its
## file is present. See `should_warn_about()`. Tests turn it off so the suite
## output stays clean while still asserting the decision.
@export var warn_on_licence_refusal: bool = true

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

var _manifest: MusicCatalogue = null
var _machine: BgmMachine = BgmMachine.new()
var _voices: Array[AudioStreamPlayer] = []
## Per voice: trackId ("" when free), current level 0..1, fade plan.
var _voice_track: Array[String] = []
var _voice_level: Array[float] = []
var _voice_fade: Array[Dictionary] = []
var _active_voice: int = -1
var _desired_track: String = ""
var _reported: Dictionary = {}
var _streams: Dictionary = {}
var _sfx_player: Node = null
var _save_service: Node = null


func _ready() -> void:
	_ensure_voices()
	_ensure_manifest()
	# One mixer should own every level. Binding the SFX autoload here means an
	# autoload registration needs no configuration at all, and a composed instance
	# picks it up too. `bind_sfx_player()` overrides it; a missing `Sfx` is fine.
	if sfx_player() == null:
		bind_sfx_player(get_node_or_null(SFX_AUTOLOAD_PATH))


func _process(delta: float) -> void:
	advance(delta)


# -----------------------------------------------------------------------------
# Manifest
# -----------------------------------------------------------------------------


## The catalogue, loaded on first use. Never null.
func manifest() -> MusicCatalogue:
	_ensure_manifest()
	return _manifest


## Replaces the catalogue. Used by tests and by anything that wants to validate a
## manifest before adopting it. Re-resolves the current state against the new
## catalogue, so swapping a manifest in cannot leave a refused track playing.
func set_manifest(value: MusicCatalogue) -> void:
	_manifest = value if value != null else MusicCatalogue.new()
	_streams.clear()
	_reported.clear()
	_resolve_desired_track()
	_sync()


## Track ids listed in the manifest whose audio file is absent. Expected to be
## every track until a delivery lands; surfaced for the runbook, never fatal.
func missing_track_ids() -> Array:
	return manifest().missing_track_ids()


## Track ids the licence gate refuses. Must be empty in a shipping build.
func licence_refused_track_ids() -> Array:
	return manifest().licence_refused_track_ids()


## True when the build currently has no playable music at all -- the state this
## repository is in today, and a state that must not change how anything behaves.
func is_silent_build() -> bool:
	var catalogue: MusicCatalogue = manifest()
	for track_id: String in catalogue.track_ids():
		if catalogue.is_playable(track_id):
			return false
	return true


# -----------------------------------------------------------------------------
# Music state
# -----------------------------------------------------------------------------


## Moves the music to `state` (one of the `STATE_*` constants).
##
## Returns true when a track is now playing or fading in. False is a perfectly
## normal answer: it means this state has no cleared, present track -- so the
## game is silent here, which is exactly the build's current condition.
##
## An unknown state name changes nothing and returns the current playing status.
func set_state(state: String) -> bool:
	var result: Dictionary = _machine.request(state)
	var outcome: String = String(result["outcome"])
	if outcome == BgmMachine.OUTCOME_UNKNOWN_STATE:
		return is_playing_music()
	if outcome == BgmMachine.OUTCOME_SAME_STATE:
		return is_playing_music()

	_resolve_desired_track()
	_sync(float(result["fadeSeconds"]))
	music_state_changed.emit(_machine.state())
	return is_playing_music()


## Back to whatever was playing before the current state. For "the celebration is
## over, return to the room".
func return_to_previous_state() -> bool:
	return set_state(_machine.previous_state())


func current_state() -> String:
	return _machine.state()


## The track id actually assigned to a voice, or "" when nothing is playing.
func current_track_id() -> String:
	if _active_voice < 0 or _active_voice >= _voice_track.size():
		return ""
	return _voice_track[_active_voice]


## The track this state WANTS, whether or not it can be played. "" when the state
## has no music at all.
func desired_track_id() -> String:
	return _desired_track


func is_playing_music() -> bool:
	return not current_track_id().is_empty()


## Fades music out and stays silent until the next `set_state()`.
func stop_music() -> void:
	set_state(STATE_SILENT)


# -----------------------------------------------------------------------------
# Mixer
# -----------------------------------------------------------------------------


func set_master_volume_db(value: float) -> void:
	master_volume_db = clampf(value, MIN_TRIM_DB, MAX_TRIM_DB)
	_apply_mix()


func get_master_volume_db() -> float:
	return master_volume_db


func set_music_volume_db(value: float) -> void:
	music_volume_db = clampf(value, MIN_TRIM_DB, MAX_TRIM_DB)
	_apply_mix()


func get_music_volume_db() -> float:
	return music_volume_db


func set_sfx_volume_db(value: float) -> void:
	sfx_volume_db = clampf(value, MIN_TRIM_DB, MAX_TRIM_DB)
	_apply_mix()


func get_sfx_volume_db() -> float:
	return sfx_volume_db


func set_muted(value: bool) -> void:
	if muted == value:
		return
	muted = value
	_apply_mix()


func is_muted() -> bool:
	return muted


func toggle_mute() -> bool:
	set_muted(not muted)
	return muted


## The level a track would actually be played at: master + music trim + the
## track's own level, capped by `MusicManifest.MAX_VOLUME_DB` so music always
## sits under speech. Returns `OFF_DB` when muted or when sound is switched off
## in the profile.
func effective_music_volume_db(track_id: String = "") -> float:
	if muted or not is_sound_enabled():
		return OFF_DB
	var id: String = track_id if not track_id.is_empty() else _desired_track
	var track_db: float = MusicCatalogue.FALLBACK_VOLUME_DB
	if not id.is_empty():
		track_db = manifest().volume_db_for(id)
	var total: float = master_volume_db + music_volume_db + track_db
	return clampf(total, MusicCatalogue.MIN_VOLUME_DB, MusicCatalogue.MAX_VOLUME_DB)


## The level effects play at. Returns `OFF_DB` when muted.
func effective_sfx_volume_db() -> float:
	if muted or not is_sound_enabled():
		return OFF_DB
	return clampf(master_volume_db + sfx_volume_db, MIN_TRIM_DB, MAX_TRIM_DB)


## Reads `soundEnabled` from the SaveService autoload when it exists. Defaults to
## true whenever the autoload, the method or the key is unavailable -- the
## headless runner and a standalone scene both hit that path.
func is_sound_enabled() -> bool:
	var service: Node = _get_save_service()
	if service == null:
		return true
	if not service.has_method("get_setting"):
		return true
	var value: Variant = service.call("get_setting", SOUND_ENABLED_SETTING, true)
	if value is bool:
		return value
	if value == null:
		return true
	return bool(value)


# -----------------------------------------------------------------------------
# Sound effects
# -----------------------------------------------------------------------------


## Hands this director an `SfxPlayer` (typically `/root/Sfx`) so one mixer owns
## every level. Duck-typed on purpose: anything with `set_master_volume_db` and
## `set_muted` works, and a null argument simply unbinds.
func bind_sfx_player(player: Node) -> void:
	_sfx_player = player
	_apply_sfx_mix()


func sfx_player() -> Node:
	return _sfx_player if is_instance_valid(_sfx_player) else null


## Convenience pass-through so a caller can hold one audio reference instead of
## two. A missing or unbound player is a silent no-op.
func play_sfx(sfx_name: String, volume_db: float = 0.0) -> void:
	var player: Node = sfx_player()
	if player == null or not player.has_method("play"):
		return
	player.call("play", sfx_name, volume_db)


# -----------------------------------------------------------------------------
# Fades
# -----------------------------------------------------------------------------


## Advances every running fade by `delta` seconds. `_process()` calls this; tests
## call it directly, which is why the crossfade is verifiable with no tree and no
## audio device.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	for index in range(_voice_level.size()):
		var fade: Dictionary = _voice_fade[index]
		if not bool(fade.get("active", false)):
			continue
		var duration: float = float(fade.get("duration", 0.0))
		var elapsed: float = float(fade.get("elapsed", 0.0)) + delta
		var from: float = float(fade.get("from", 0.0))
		var to: float = float(fade.get("to", 0.0))
		var level: float = to
		if duration > 0.0 and elapsed < duration:
			level = lerpf(from, to, elapsed / duration)
		else:
			elapsed = duration
			fade["active"] = false
		fade["elapsed"] = elapsed
		_voice_fade[index] = fade
		_voice_level[index] = clampf(level, 0.0, 1.0)
		_apply_voice_level(index)
		if not bool(fade.get("active", false)) and is_zero_approx(_voice_level[index]):
			_release_voice(index)


## True while any crossfade or fade-out is still running.
func is_fading() -> bool:
	for fade: Dictionary in _voice_fade:
		if bool(fade.get("active", false)):
			return true
	return false


## Runs every pending fade to completion instantly. For a scene change, where a
## 1.2 s crossfade would outlive the thing it was fading.
func finish_fades() -> void:
	advance(BgmMachine.MAX_FADE_SECONDS * 2.0)


## Level 0..1 of a voice. Diagnostics and tests.
func voice_level(index: int) -> float:
	if index < 0 or index >= _voice_level.size():
		return 0.0
	return _voice_level[index]


func voice_track_id(index: int) -> String:
	if index < 0 or index >= _voice_track.size():
		return ""
	return _voice_track[index]


## The `AudioStreamPlayer` behind a voice. Exposed for diagnostics and tests
## rather than having them guess at child indices.
func voice_player(index: int) -> AudioStreamPlayer:
	_ensure_voices()
	if index < 0 or index >= _voices.size():
		return null
	return _voices[index]


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------


func _ensure_manifest() -> void:
	if _manifest != null:
		return
	var catalogue: MusicCatalogue = MusicCatalogue.new()
	catalogue.load_file(manifest_path)
	_manifest = catalogue


func _ensure_voices() -> void:
	if not _voices.is_empty():
		return
	for i in range(VOICE_COUNT):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.name = "MusicVoice%d" % i
		voice.bus = &"Master"
		voice.volume_db = OFF_DB
		add_child(voice)
		_voices.append(voice)
		_voice_track.append("")
		_voice_level.append(0.0)
		_voice_fade.append({"active": false, "from": 0.0, "to": 0.0, "elapsed": 0.0, "duration": 0.0})


## Works out which track the current state wants, and reports -- once -- when
## that track cannot be played.
func _resolve_desired_track() -> void:
	var catalogue: MusicCatalogue = manifest()
	var state: String = _machine.state()
	if state == STATE_SILENT:
		_desired_track = ""
		return

	var candidates: Array = catalogue.tracks_for_scene(state)
	_desired_track = ""
	for track_id: String in candidates:
		if catalogue.is_playable(track_id):
			_desired_track = track_id
			return

	# Nothing playable. Report the first candidate's reason once, so a diagnostics
	# panel can show it and a licence problem is not invisible -- but never per
	# frame, and never as an engine error.
	for track_id: String in candidates:
		_report_unavailable(track_id, catalogue.refusal_reason(track_id))


func _report_unavailable(track_id: String, reason: String) -> void:
	if track_id.is_empty() or reason.is_empty():
		return
	var key: String = "%s|%s" % [track_id, reason]
	if _reported.has(key):
		return
	_reported[key] = true
	if warn_on_licence_refusal and should_warn_about(track_id, reason):
		push_warning(
			("AudioDirector refused music track '%s' (%s), and there IS a file at %s. "
			+ "A track plays only when commercialUse is \"verified\" and licenseEvidence "
			+ "names real evidence. See docs/AUDIO_MANIFEST.md.")
			% [track_id, reason, manifest().resolved_path(track_id)]
		)
	track_unavailable.emit(track_id, reason)


## Whether a refusal deserves a developer's attention.
##
## True only when the paperwork is wrong AND a file is actually sitting there --
## someone dropped a delivery in without recording its rights, which is the one
## audio mistake in this project that could reach a shipped build.
##
## A pending row with no file is the *designed* state of this repository: the
## tracks are listed before they exist so that dropping them in needs no code
## change. Warning about that on every boot would be noise, and noise is how a
## real warning gets ignored.
func should_warn_about(track_id: String, reason: String) -> bool:
	if not MusicCatalogue.is_licence_refusal(reason):
		return false
	return not manifest().resolved_path(track_id).is_empty()


## Brings the voices into line with `_desired_track` and the current mix.
func _sync(fade_seconds: float = -1.0) -> void:
	_ensure_voices()
	if _voices.is_empty():
		return

	var duration: float = fade_seconds
	if duration < 0.0:
		duration = BgmMachine.fade_seconds_to(_machine.state())
	if not crossfade_enabled:
		duration = 0.0

	var target_db: float = effective_music_volume_db(_desired_track)
	var silent: bool = _desired_track.is_empty() or target_db <= SILENCE_DB
	var target_level: float = 0.0 if silent else 1.0

	if silent:
		var was_playing: bool = is_playing_music()
		for index in range(_voices.size()):
			_fade_voice(index, 0.0, duration)
		_active_voice = -1
		if was_playing:
			music_stopped.emit()
		return

	# Already on the right track: just retarget its level, no crossfade.
	if _active_voice >= 0 and _voice_track[_active_voice] == _desired_track:
		_apply_voice_level(_active_voice)
		return

	var stream: AudioStream = _stream_for(_desired_track)
	if stream == null:
		# The manifest said the file was there and the loader disagreed. Nothing
		# to play; stay silent rather than error.
		_report_unavailable(_desired_track, MusicCatalogue.REFUSAL_FILE_MISSING)
		_desired_track = ""
		_sync(duration)
		return

	var incoming: int = _free_voice()
	for index in range(_voices.size()):
		if index != incoming:
			_fade_voice(index, 0.0, duration)

	_voice_track[incoming] = _desired_track
	_voice_level[incoming] = 0.0 if duration > 0.0 else target_level
	var voice: AudioStreamPlayer = _voices[incoming]
	voice.stream = stream
	_apply_voice_level(incoming)
	# `AudioStreamPlayer.play()` requires tree membership. Detached (a prefab
	# under construction, the headless runner) the request is accepted and simply
	# produces no audio -- the same contract as `SfxPlayer`.
	if voice.is_inside_tree():
		voice.play()
	_active_voice = incoming
	_fade_voice(incoming, target_level, duration)
	track_started.emit(_desired_track)


func _fade_voice(index: int, to_level: float, duration: float) -> void:
	if index < 0 or index >= _voice_level.size():
		return
	var from_level: float = _voice_level[index]
	if duration <= 0.0:
		_voice_level[index] = clampf(to_level, 0.0, 1.0)
		_voice_fade[index] = {
			"active": false, "from": from_level, "to": to_level,
			"elapsed": 0.0, "duration": 0.0,
		}
		_apply_voice_level(index)
		if is_zero_approx(_voice_level[index]):
			_release_voice(index)
		return
	if is_equal_approx(from_level, to_level):
		# Nothing to do, but a voice already at zero should not keep a stream.
		if is_zero_approx(to_level):
			_release_voice(index)
		return
	_voice_fade[index] = {
		"active": true, "from": from_level, "to": clampf(to_level, 0.0, 1.0),
		"elapsed": 0.0, "duration": duration,
	}


func _apply_voice_level(index: int) -> void:
	if index < 0 or index >= _voices.size():
		return
	var voice: AudioStreamPlayer = _voices[index]
	if not is_instance_valid(voice):
		return
	var level: float = _voice_level[index]
	if _voice_track[index].is_empty() or level <= 0.0:
		voice.volume_db = OFF_DB
		return
	var target_db: float = effective_music_volume_db(_voice_track[index])
	if target_db <= SILENCE_DB:
		voice.volume_db = OFF_DB
		return
	# Fade in LINEAR amplitude, then convert. A dB-linear fade sounds like it
	# happens all at once at the quiet end.
	var linear: float = db_to_linear(target_db) * level
	voice.volume_db = linear_to_db(maxf(linear, 0.00001))


func _release_voice(index: int) -> void:
	if index < 0 or index >= _voices.size():
		return
	var voice: AudioStreamPlayer = _voices[index]
	if is_instance_valid(voice):
		if voice.playing:
			voice.stop()
		voice.stream = null
		voice.volume_db = OFF_DB
	_voice_track[index] = ""
	_voice_level[index] = 0.0
	if _active_voice == index:
		_active_voice = -1


func _free_voice() -> int:
	for index in range(_voices.size()):
		if index != _active_voice and _voice_track[index].is_empty():
			return index
	for index in range(_voices.size()):
		if index != _active_voice:
			return index
	return 0


## Re-applies trims and mute to every voice and to the bound effects player.
func _apply_mix() -> void:
	for index in range(_voice_level.size()):
		_apply_voice_level(index)
	# Muting must actually stop the music rather than leave it running at -80 dB,
	# and unmuting must bring back whatever the state asked for.
	if muted or not is_sound_enabled():
		for index in range(_voice_level.size()):
			_fade_voice(index, 0.0, 0.0)
		_active_voice = -1
	elif not _desired_track.is_empty() and not is_playing_music():
		# Unmuting fades back in over the current state's own duration rather than
		# snapping to level: the child asked for sound back, not for a jolt.
		_sync(-1.0)
	_apply_sfx_mix()
	mix_changed.emit(
		master_volume_db, music_volume_db, sfx_volume_db, muted
	)


func _apply_sfx_mix() -> void:
	var player: Node = sfx_player()
	if player == null:
		return
	if player.has_method("set_master_volume_db"):
		player.call("set_master_volume_db", clampf(master_volume_db + sfx_volume_db, MIN_TRIM_DB, MAX_TRIM_DB))
	if player.has_method("set_muted"):
		player.call("set_muted", muted)


## Resolves a track's file to a stream, cached. Misses are cached too, so a
## missing file is not re-probed every transition.
func _stream_for(track_id: String) -> AudioStream:
	if _streams.has(track_id):
		return _streams[track_id]
	var stream: AudioStream = null
	var path: String = manifest().resolved_path(track_id)
	if not path.is_empty():
		if ResourceLoader.exists(path):
			var resource: Resource = ResourceLoader.load(path, "AudioStream")
			if resource is AudioStream:
				stream = resource
		if stream == null and path.get_extension().to_lower() == "wav":
			# A source checkout has no imported sample for a raw .wav; read the
			# RIFF bytes directly, exactly as the SFX player does.
			var loader := load("res://scripts/audio/wav_loader.gd")
			if loader != null:
				var parsed: Variant = loader.load_wav(path)
				if parsed is AudioStream:
					stream = parsed
	if stream != null:
		stream = _apply_loop(stream, track_id)
	_streams[track_id] = stream
	return stream


## Applies the manifest's loop points. Duck-typed across stream types so an OGG,
## an MP3 and a WAV delivery all loop without this file knowing which arrived.
func _apply_loop(stream: AudioStream, track_id: String) -> AudioStream:
	var points: Dictionary = manifest().loop_points(track_id)
	var loop_start: float = float(points["loopStart"])
	var loop_end: float = float(points["loopEnd"])

	# Local copy: the imported resource is shared, and mutating it would leak
	# loop settings into anything else that loads the same file.
	var copy: AudioStream = stream
	if stream.resource_path != "":
		var duplicated: Resource = stream.duplicate(true)
		if duplicated is AudioStream:
			copy = duplicated

	if copy is AudioStreamWAV:
		var wav: AudioStreamWAV = copy as AudioStreamWAV
		var rate: int = maxi(wav.mix_rate, 1)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = int(loop_start * float(rate))
		if loop_end > 0.0:
			wav.loop_end = int(loop_end * float(rate))
		return wav

	# AudioStreamOggVorbis and AudioStreamMP3 both expose `loop`/`loop_offset`.
	if "loop" in copy:
		copy.set("loop", true)
	if "loop_offset" in copy:
		copy.set("loop_offset", loop_start)
	return copy


func _get_save_service() -> Node:
	if is_instance_valid(_save_service):
		return _save_service
	if not is_inside_tree():
		return null
	_save_service = get_node_or_null(SAVE_SERVICE_PATH)
	return _save_service
