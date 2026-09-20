class_name ParentSettingsModel
extends RefCounted

## Pure mapping between the parent-facing toggles and the persisted settings
## keys, with safe defaults and type validation.
##
## The SaveService autoload is duck-typed and optional: the model keeps its own
## in-memory cache, so the settings screen still behaves correctly in a scene
## preview or a test run where no autoload exists. Nothing here touches the
## network, and no key outside the ones below is ever written.

const Localization := preload("res://scripts/localization/localization.gd")
const QuotaLedger := preload("res://scripts/tutor/quota/quota_ledger.gd")

const KEY_THAI_HINTS := "thaiHints"
const KEY_SPEECH_ENABLED := "speechEnabled"
const KEY_TTS_SPEED := "ttsSpeed"
## 0..1 linear slider values. 1.0 is the manifest / platform level.
const KEY_MUSIC_VOLUME := "musicVolume"
const KEY_VOICE_VOLUME := "voiceVolume"
## "th" / "zh" / "ar" / "hi" / "ja" / "off". Supersedes `thaiHints`, which is
## kept in step so every existing reader of the boolean keeps working.
const KEY_HELPER_LANGUAGE := "helperLanguage"
const KEY_TEACHING_LANGUAGE := "teachingLanguage"
## Per-character voice levels, 0..1, for the voice director (`/root/Voice`,
## `set_character_volume("aliz" | "bunny", v)`). `voiceVolume` above stays the
## single TTS level and keeps working beside them.
const KEY_ALIZ_VOICE_VOLUME := "alizVoiceVolume"
const KEY_BUNNY_VOICE_VOLUME := "bunnyVoiceVolume"
## The play-session reminder (`play_session.gd`): minutes of ACTIVE play before
## the break card, 0 = off. Only the offered values are ever stored.
const KEY_SESSION_REMINDER_MINUTES := "sessionReminderMinutes"
## "Learn with Aliz" (the local scripted tutor) on or off. The CLOUD tutor is
## gated separately by `TutorFlags.cloud_enabled()`, which no setting can turn on.
const KEY_AI_TUTOR_ENABLED := "aiTutorEnabled"
## The two tutor keys a grown-up's "Delete learning history" clears. Both are
## owned by the tutor layer (`lesson_engine.gd`, `quota_ledger.gd`); the model
## only knows their names so the delete touches exactly these and nothing else.
const KEY_TUTOR_PROGRESS := "tutorProgress"
const KEY_TUTOR_QUOTA := QuotaLedger.SETTING_KEY

const DEFAULT_THAI_HINTS := true
const DEFAULT_SPEECH_ENABLED := true
const DEFAULT_TTS_SPEED := "normal"
const DEFAULT_MUSIC_VOLUME := 1.0
## Matches `TtsService.SPEECH_VOLUME` (85 of 100) so an untouched slider changes
## nothing about how the game has sounded until now.
const DEFAULT_VOICE_VOLUME := 0.85
const DEFAULT_HELPER_LANGUAGE := "th"
const TEACHING_LANGUAGE := "en"
const DEFAULT_ALIZ_VOICE_VOLUME := 0.85
const DEFAULT_BUNNY_VOICE_VOLUME := 0.85
const DEFAULT_SESSION_REMINDER_MINUTES := 5
const SESSION_REMINDER_CHOICES: Array[int] = [0, 5, 10, 15]
const DEFAULT_AI_TUTOR_ENABLED := true

const TTS_SPEED_SLOW := "slow"
const TTS_SPEED_NORMAL := "normal"
const TTS_SPEEDS := [TTS_SPEED_SLOW, TTS_SPEED_NORMAL]

var _service: Object = null
var _cache: Dictionary = {}


func _init(service: Object = null) -> void:
	set_service(service)


## Accepts the SaveService autoload (or any object exposing get_setting /
## set_setting / reset_profile / get_stars). `null` is fine.
func set_service(service: Object) -> void:
	_service = service
	_cache.clear()


func get_thai_hints() -> bool:
	return _read_bool(KEY_THAI_HINTS, DEFAULT_THAI_HINTS)


## The legacy on/off. Off is `helperLanguage = "off"`; on restores Thai unless
## another language is already chosen.
func set_thai_hints(enabled: bool) -> void:
	if not enabled:
		set_helper_language(Localization.HELPER_OFF)
		return
	if get_helper_language() == Localization.HELPER_OFF:
		set_helper_language(DEFAULT_HELPER_LANGUAGE)
	else:
		_write(KEY_THAI_HINTS, true)


## -- helper language -----------------------------------------------------------

## "th" by default; "off" when a pre-`helperLanguage` profile has `thaiHints = false`.
func get_helper_language() -> String:
	var stored: Variant = _read(KEY_HELPER_LANGUAGE, null)
	if typeof(stored) == TYPE_STRING and not String(stored).is_empty():
		return Localization.normalise(stored)
	if not _read_bool(KEY_THAI_HINTS, DEFAULT_THAI_HINTS):
		return Localization.HELPER_OFF
	return DEFAULT_HELPER_LANGUAGE


## Persists the choice, keeps `thaiHints` in step, and applies it to
## `Localization` at once so the next prompt is already in the new language.
func set_helper_language(code: String) -> void:
	var value: String = Localization.normalise(code)
	_write(KEY_HELPER_LANGUAGE, value)
	_write(KEY_THAI_HINTS, value != Localization.HELPER_OFF)
	_write(KEY_TEACHING_LANGUAGE, TEACHING_LANGUAGE)
	Localization.set_helper_language(value)


func get_teaching_language() -> String:
	return TEACHING_LANGUAGE


## -- volumes -------------------------------------------------------------------

func get_music_volume() -> float:
	return _read_unit(KEY_MUSIC_VOLUME, DEFAULT_MUSIC_VOLUME)


func set_music_volume(value: float) -> void:
	_write(KEY_MUSIC_VOLUME, _unit(value))


func get_voice_volume() -> float:
	return _read_unit(KEY_VOICE_VOLUME, DEFAULT_VOICE_VOLUME)


func set_voice_volume(value: float) -> void:
	_write(KEY_VOICE_VOLUME, _unit(value))


func get_aliz_voice_volume() -> float:
	return _read_unit(KEY_ALIZ_VOICE_VOLUME, DEFAULT_ALIZ_VOICE_VOLUME)


func set_aliz_voice_volume(value: float) -> void:
	_write(KEY_ALIZ_VOICE_VOLUME, _unit(value))


func get_bunny_voice_volume() -> float:
	return _read_unit(KEY_BUNNY_VOICE_VOLUME, DEFAULT_BUNNY_VOICE_VOLUME)


func set_bunny_voice_volume(value: float) -> void:
	_write(KEY_BUNNY_VOICE_VOLUME, _unit(value))


## -- play session reminder -----------------------------------------------------

## 0 (off), 5, 10 or 15. Anything else stored reads as the default.
func get_session_reminder_minutes() -> int:
	var value: Variant = _read(KEY_SESSION_REMINDER_MINUTES, DEFAULT_SESSION_REMINDER_MINUTES)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var minutes: int = int(value)
		if float(value) == float(minutes) and SESSION_REMINDER_CHOICES.has(minutes):
			return minutes
	return DEFAULT_SESSION_REMINDER_MINUTES


## Only the offered values are persisted; anything else is ignored.
func set_session_reminder_minutes(minutes: int) -> void:
	if not SESSION_REMINDER_CHOICES.has(minutes):
		return
	_write(KEY_SESSION_REMINDER_MINUTES, minutes)


## -- Learn with Aliz -----------------------------------------------------------

func get_ai_tutor_enabled() -> bool:
	return _read_bool(KEY_AI_TUTOR_ENABLED, DEFAULT_AI_TUTOR_ENABLED)


func set_ai_tutor_enabled(enabled: bool) -> void:
	_write(KEY_AI_TUTOR_ENABLED, enabled)


## Clears the child's tutor lesson progress and today's local tutor-time usage.
## Touches exactly `tutorProgress` and `tutorQuota`: never stars, stickers,
## levels or any other setting. Returns true when a real service was written.
func delete_learning_history() -> bool:
	_write(KEY_TUTOR_PROGRESS, {})
	# The ledger keeps its day and its monotonic clock mark; only the count goes.
	var ledger: QuotaLedger = QuotaLedger.new(_service)
	ledger.clear_usage()
	_cache[KEY_TUTOR_QUOTA] = ledger.to_dict()
	return _service != null and _service.has_method("set_setting")


func get_speech_enabled() -> bool:
	return _read_bool(KEY_SPEECH_ENABLED, DEFAULT_SPEECH_ENABLED)


func set_speech_enabled(enabled: bool) -> void:
	_write(KEY_SPEECH_ENABLED, enabled)


func get_tts_speed() -> String:
	var value: Variant = _read(KEY_TTS_SPEED, DEFAULT_TTS_SPEED)
	if typeof(value) == TYPE_STRING and TTS_SPEEDS.has(value):
		return String(value)
	return DEFAULT_TTS_SPEED


## Unrecognised values are ignored rather than persisted, so the stored key can
## only ever be "slow" or "normal".
func set_tts_speed(speed: String) -> void:
	if not TTS_SPEEDS.has(speed):
		return
	_write(KEY_TTS_SPEED, speed)


func is_tts_slow() -> bool:
	return get_tts_speed() == TTS_SPEED_SLOW


func get_stars() -> int:
	if _service != null and _service.has_method("get_stars"):
		return int(_service.call("get_stars"))
	return 0


## Erases stars, stickers and completed activities via SaveService. Returns
## true if a real service handled it.
func reset_progress() -> bool:
	if _service != null and _service.has_method("reset_profile"):
		_service.call("reset_profile")
		return true
	return false


# -- internals ----------------------------------------------------------------

func _read(key: String, default_value: Variant) -> Variant:
	if _service != null and _service.has_method("get_setting"):
		return _service.call("get_setting", key, default_value)
	if _cache.has(key):
		return _cache[key]
	return default_value


## A 0..1 number, or the default for anything that is not a finite number.
func _read_unit(key: String, default_value: float) -> float:
	var value: Variant = _read(key, default_value)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		var number: float = float(value)
		if is_finite(number):
			return _unit(number)
	return default_value


static func _unit(value: float) -> float:
	if not is_finite(value):
		return 0.0
	return snappedf(clampf(value, 0.0, 1.0), 0.01)


func _read_bool(key: String, default_value: bool) -> bool:
	var value: Variant = _read(key, default_value)
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	return default_value


func _write(key: String, value: Variant) -> void:
	_cache[key] = value
	if _service != null and _service.has_method("set_setting"):
		_service.call("set_setting", key, value)
