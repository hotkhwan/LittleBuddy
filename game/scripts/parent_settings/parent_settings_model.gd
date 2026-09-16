class_name ParentSettingsModel
extends RefCounted

## Pure mapping between the parent-facing toggles and the persisted settings
## keys, with safe defaults and type validation.
##
## The SaveService autoload is duck-typed and optional: the model keeps its own
## in-memory cache, so the settings screen still behaves correctly in a scene
## preview or a test run where no autoload exists. Nothing here touches the
## network, and no key outside the ones below is ever written.

const KEY_THAI_HINTS := "thaiHints"
const KEY_SPEECH_ENABLED := "speechEnabled"
const KEY_TTS_SPEED := "ttsSpeed"

const DEFAULT_THAI_HINTS := true
const DEFAULT_SPEECH_ENABLED := true
const DEFAULT_TTS_SPEED := "normal"

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


func set_thai_hints(enabled: bool) -> void:
	_write(KEY_THAI_HINTS, enabled)


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


func _read_bool(key: String, default_value: bool) -> bool:
	var value: Variant = _read(key, default_value)
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	return default_value


func _write(key: String, value: Variant) -> void:
	_cache[key] = value
	if _service != null and _service.has_method("set_setting"):
		_service.call("set_setting", key, value)
