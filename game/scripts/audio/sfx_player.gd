class_name SfxPlayer
extends Node
## Small, self-contained sound-effect player for Little Buddy.
##
## Add it as a child of any scene that wants sound:
##
##     var sfx := SfxPlayer.new()
##     add_child(sfx)
##     sfx.play(SfxPlayer.SUCCESS_CHIME)
##
## Design notes:
##   * Streams are resolved lazily and cached; a missing file is a silent
##     no-op, never an engine error.
##   * A small pool of `AudioStreamPlayer` nodes lets short effects overlap
##     instead of cutting each other off.
##   * Obeys the `soundEnabled` profile setting, read defensively from
##     `/root/SaveService` (that autoload is absent in the headless test
##     runner, so its absence must never matter).
##   * Output is clamped so nothing can ever be played louder than the
##     already-conservative level baked into the WAV files.
##   * No network, no analytics, no microphone. Playback only.

signal sfx_played(sfx_name: String)

const SFX_DIR: String = "res://audio/sfx"

# -- Known effects. Use these constants rather than bare strings. -------------
const SUCCESS_CHIME: String = "success_chime"
const SOFT_POP: String = "soft_pop"
const PICKUP: String = "pickup"
## Object landed where it belongs (drag delivered, item placed).
const PLACE_SOFT: String = "place_soft"
## Object slid back home because it was dropped somewhere else. NOT a failure
## sound -- there is no failure sound in this game.
const DROP_RETURN: String = "drop_return"
## The character walked into another room.
const ROOM_CHANGE: String = "room_change"
const STICKER_UNLOCK: String = "sticker_unlock"
const STAR_EARNED: String = "star_earned"
const BEDTIME_CHIME: String = "bedtime_chime"
const GENTLE_TAP: String = "gentle_tap"

const KNOWN_SFX: Array[String] = [
	SUCCESS_CHIME,
	SOFT_POP,
	PICKUP,
	PLACE_SOFT,
	DROP_RETURN,
	ROOM_CHANGE,
	STICKER_UNLOCK,
	STAR_EARNED,
	BEDTIME_CHIME,
	GENTLE_TAP,
]

## Child-safety ceiling: the final mix level can never exceed this, no matter
## what a caller passes in. The WAVs themselves peak at -6 dBFS or lower.
const MAX_OUTPUT_DB: float = 0.0
const MIN_OUTPUT_DB: float = -40.0

## Profile setting consulted before every play.
const SOUND_ENABLED_SETTING: String = "soundEnabled"
const SAVE_SERVICE_PATH: String = "/root/SaveService"

const _WavLoader := preload("res://scripts/audio/wav_loader.gd")

## Number of pooled `AudioStreamPlayer` voices. Small on purpose.
@export var voice_count: int = 6
## Global trim applied on top of each call's `volume_db`.
@export var master_volume_db: float = 0.0
## Hard mute, independent of the saved `soundEnabled` setting.
@export var muted: bool = false

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _save_service: Node = null


func _ready() -> void:
	_ensure_voices()


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------


## Plays `sfx_name` (a bare name such as "pickup", no path, no extension).
## Unknown names, missing files and unavailable audio devices are all silent
## no-ops -- this function must never be a source of errors or crashes.
func play(sfx_name: String, volume_db: float = 0.0) -> void:
	if sfx_name.is_empty():
		return
	if muted or not is_sound_enabled():
		return

	var stream: AudioStream = _resolve_stream(sfx_name)
	if stream == null:
		return

	var voice: AudioStreamPlayer = _take_voice()
	if voice == null:
		return

	voice.stream = stream
	voice.volume_db = clampf(master_volume_db + volume_db, MIN_OUTPUT_DB, MAX_OUTPUT_DB)
	# `AudioStreamPlayer.play()` requires tree membership. When this player has
	# not been added to a scene yet (unit tests, a prefab under construction)
	# the request is accepted and simply produces no audio.
	if voice.is_inside_tree():
		voice.play()
	sfx_played.emit(sfx_name)


## True when a playable stream exists for `sfx_name`.
func has_sfx(sfx_name: String) -> bool:
	return _resolve_stream(sfx_name) != null


## Resolves and caches every known effect up front (e.g. on a loading screen)
## so the first tap never pays for disk I/O. Returns how many were found.
func warm_cache() -> int:
	var found: int = 0
	for sfx_name in KNOWN_SFX:
		if _resolve_stream(sfx_name) != null:
			found += 1
	return found


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		stop_all()


func is_muted() -> bool:
	return muted


func set_master_volume_db(value: float) -> void:
	master_volume_db = clampf(value, MIN_OUTPUT_DB, MAX_OUTPUT_DB)


func get_master_volume_db() -> float:
	return master_volume_db


## Reads `soundEnabled` from the SaveService autoload when it exists. Defaults
## to true whenever the autoload, the method or the key is unavailable.
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


func stop_all() -> void:
	for voice in _voices:
		if is_instance_valid(voice) and voice.playing:
			voice.stop()


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------


func _resolve_stream(sfx_name: String) -> AudioStream:
	if _streams.has(sfx_name):
		return _streams[sfx_name]

	var stream: AudioStream = null
	var path: String = "%s/%s.wav" % [SFX_DIR, sfx_name]

	# Preferred path in a source checkout and in the headless test runner: read
	# the RIFF bytes directly, so no editor import step is required.
	if FileAccess.file_exists(path):
		stream = _WavLoader.load_wav(path)

	# Exported builds ship the imported resource, not the source .wav.
	if stream == null and ResourceLoader.exists(path):
		var resource: Resource = ResourceLoader.load(path, "AudioStream")
		if resource is AudioStream:
			stream = resource

	_streams[sfx_name] = stream  # Cache misses too -- never retry every frame.
	return stream


func _ensure_voices() -> void:
	if not _voices.is_empty():
		return
	var count: int = maxi(voice_count, 1)
	for i in range(count):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.name = "SfxVoice%d" % i
		voice.bus = &"Master"
		add_child(voice)
		_voices.append(voice)


func _take_voice() -> AudioStreamPlayer:
	_ensure_voices()
	if _voices.is_empty():
		return null

	# Prefer an idle voice so overlapping effects never cut each other off.
	for i in range(_voices.size()):
		var index: int = (_next_voice + i) % _voices.size()
		var candidate: AudioStreamPlayer = _voices[index]
		if is_instance_valid(candidate) and not candidate.playing:
			_next_voice = (index + 1) % _voices.size()
			return candidate

	# Everything is busy: steal the oldest slot in round-robin order.
	var fallback: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return fallback if is_instance_valid(fallback) else null


func _get_save_service() -> Node:
	if is_instance_valid(_save_service):
		return _save_service
	if not is_inside_tree():
		return null
	_save_service = get_node_or_null(SAVE_SERVICE_PATH)
	return _save_service
