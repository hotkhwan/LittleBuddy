extends RefCounted

## The parent settings model: which toggle maps to which persisted key, what
## the defaults are, and that it never crashes without the SaveService autoload.

const ModelScript := preload("res://scripts/parent_settings/parent_settings_model.gd")


## Stand-in for the SaveService autoload with the same duck-typed API.
class FakeSaveService:
	extends RefCounted

	var settings: Dictionary = {}
	var stars: int = 0
	var reset_count: int = 0

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		if settings.has(key):
			return settings[key]
		return default_value

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value

	func get_stars() -> int:
		return stars

	func reset_profile() -> void:
		reset_count += 1
		settings.clear()
		stars = 0


func test_name() -> String:
	return "parent_settings_model"


func run():
	var failures: Array = []
	failures += _test_defaults()
	failures += _test_keys_written()
	failures += _test_tts_speed_validation()
	failures += _test_corrupt_values_fall_back()
	failures += _test_without_service()
	failures += _test_reset()
	return failures


func _test_defaults():
	var failures: Array = []
	var service := FakeSaveService.new()
	var model: Object = ModelScript.new(service)

	if model.get_thai_hints() != true:
		failures.append("thaiHints should default to true")
	if model.get_speech_enabled() != true:
		failures.append("speechEnabled should default to true")
	if model.get_tts_speed() != "normal":
		failures.append("ttsSpeed should default to \"normal\", got %s" % model.get_tts_speed())
	if not service.settings.is_empty():
		failures.append("reading defaults must not write anything to the profile")

	# The key names are part of the persisted contract.
	if ModelScript.KEY_THAI_HINTS != "thaiHints":
		failures.append("thai hints key must be \"thaiHints\"")
	if ModelScript.KEY_SPEECH_ENABLED != "speechEnabled":
		failures.append("voice practice key must be \"speechEnabled\"")
	if ModelScript.KEY_TTS_SPEED != "ttsSpeed":
		failures.append("tts speed key must be \"ttsSpeed\"")

	return failures


func _test_keys_written():
	var failures: Array = []
	var service := FakeSaveService.new()
	var model: Object = ModelScript.new(service)

	model.set_thai_hints(false)
	model.set_speech_enabled(false)
	model.set_tts_speed("slow")

	if service.settings.get("thaiHints", true) != false:
		failures.append("Thai hints toggle should write thaiHints=false, got %s" % service.settings)
	if service.settings.get("speechEnabled", true) != false:
		failures.append("voice toggle should write speechEnabled=false, got %s" % service.settings)
	if service.settings.get("ttsSpeed", "") != "slow":
		failures.append("speed control should write ttsSpeed=\"slow\", got %s" % service.settings)
	# Changed deliberately 2026-09-20: the Thai toggle is now the helper-language
	# selector underneath, so turning it off also records helperLanguage="off" and
	# teachingLanguage="en". Still nothing outside the parent settings' own keys.
	var allowed: Array = ["thaiHints", "speechEnabled", "ttsSpeed",
			"helperLanguage", "teachingLanguage", "musicVolume", "voiceVolume"]
	for key: Variant in service.settings.keys():
		if not allowed.has(String(key)):
			failures.append("the model wrote an unexpected key %s: %s" % [str(key), service.settings])
	if service.settings.get("helperLanguage", "") != "off":
		failures.append("thaiHints=false must also record helperLanguage=off, got %s" % service.settings)

	# Reading back reflects what was stored.
	if model.get_thai_hints() != false or model.get_speech_enabled() != false:
		failures.append("toggles should read back the persisted values")
	if not model.is_tts_slow():
		failures.append("is_tts_slow() should be true after selecting slow")

	model.set_thai_hints(true)
	if service.settings.get("thaiHints", false) != true:
		failures.append("toggling back should write thaiHints=true")

	return failures


func _test_tts_speed_validation():
	var failures: Array = []
	var service := FakeSaveService.new()
	var model: Object = ModelScript.new(service)

	model.set_tts_speed("hyperspeed")
	if service.settings.has("ttsSpeed"):
		failures.append("an unknown speed must not be persisted, got %s" % service.settings)
	if model.get_tts_speed() != "normal":
		failures.append("an unknown speed must leave the value at the default")

	model.set_tts_speed("normal")
	if service.settings.get("ttsSpeed", "") != "normal":
		failures.append("\"normal\" should be persisted verbatim")

	return failures


func _test_corrupt_values_fall_back():
	var failures: Array = []
	var service := FakeSaveService.new()
	service.settings = {"thaiHints": "yes", "speechEnabled": 3, "ttsSpeed": 7}
	var model: Object = ModelScript.new(service)

	if model.get_thai_hints() != true:
		failures.append("a non-bool thaiHints should fall back to the default")
	if model.get_speech_enabled() != true:
		failures.append("a non-bool speechEnabled should fall back to the default")
	if model.get_tts_speed() != "normal":
		failures.append("a non-string ttsSpeed should fall back to the default")

	return failures


func _test_without_service():
	var failures: Array = []
	# No SaveService autoload (scene preview / headless test): must not crash.
	var model: Object = ModelScript.new(null)

	if model.get_thai_hints() != true or model.get_speech_enabled() != true:
		failures.append("defaults should still apply with no save service")
	if model.get_tts_speed() != "normal":
		failures.append("ttsSpeed default should still apply with no save service")
	if model.get_stars() != 0:
		failures.append("get_stars() should report 0 with no save service")

	model.set_thai_hints(false)
	model.set_tts_speed("slow")
	if model.get_thai_hints() != false or model.get_tts_speed() != "slow":
		failures.append("the model should keep values in memory when unpersisted")
	if model.reset_progress() != false:
		failures.append("reset_progress() should report false with no save service")

	return failures


func _test_reset():
	var failures: Array = []
	var service := FakeSaveService.new()
	service.stars = 12
	var model: Object = ModelScript.new(service)

	if model.get_stars() != 12:
		failures.append("get_stars() should read through to the save service")

	if model.reset_progress() != true:
		failures.append("reset_progress() should report true when the service handled it")
	if service.reset_count != 1:
		failures.append("reset_progress() should call reset_profile() exactly once, got %d" % service.reset_count)
	if model.get_stars() != 0:
		failures.append("stars should read as 0 after a reset")

	return failures
