extends RefCounted

## Provider-neutral classroom session contract. Provider names and credentials
## stay behind the Worker; the scene consumes only this child-safe metadata.

signal mode_changed(previous: String, current: String, reason: String)

const TIER_STANDARD := "standard"
const TIER_PREMIUM := "premium"
const TIERS: Array[String] = [TIER_STANDARD, TIER_PREMIUM]

const MODE_LESSON_LOCAL := "lesson_local"
const MODE_STANDARD_CHAT := "standard_chat"
const MODE_PREMIUM_LIVE := "premium_live"
const MODES: Array[String] = [MODE_LESSON_LOCAL, MODE_STANDARD_CHAT, MODE_PREMIUM_LIVE]

const AUDIO_DEVICE := "device"
const AUDIO_LIVE := "live"
const AUDIO_TEXT_TO_SPEECH := "text_to_speech"
const AUDIO_MODES: Array[String] = [AUDIO_DEVICE, AUDIO_LIVE, AUDIO_TEXT_TO_SPEECH]

var _metadata: Dictionary = defaults()


static func defaults() -> Dictionary:
	return {
		"tier": TIER_STANDARD,
		"mode": MODE_LESSON_LOCAL,
		"capabilities": ["localLesson", "touch", "deviceSpeech"],
		"quotaRemaining": -1.0,
		"audioMode": AUDIO_DEVICE,
	}


func configure(metadata: Dictionary) -> bool:
	var clean := sanitise(metadata)
	if clean.is_empty():
		return false
	_metadata = clean
	return true


func metadata() -> Dictionary:
	return _metadata.duplicate(true)


func tier() -> String:
	return String(_metadata.tier)


func mode() -> String:
	return String(_metadata.mode)


func child_label() -> String:
	match mode():
		MODE_STANDARD_CHAT: return "Ask Aliz anything"
		MODE_PREMIUM_LIVE: return "Talk live with Aliz"
		_: return "Lesson Mode"


func fallback(reason: String = "unavailable") -> bool:
	var previous := mode()
	match previous:
		MODE_PREMIUM_LIVE:
			_metadata.mode = MODE_STANDARD_CHAT
			_metadata.audioMode = AUDIO_TEXT_TO_SPEECH
		MODE_STANDARD_CHAT:
			_metadata.mode = MODE_LESSON_LOCAL
			_metadata.audioMode = AUDIO_DEVICE
		_:
			return false
	mode_changed.emit(previous, mode(), reason)
	return true


static func sanitise(source: Dictionary) -> Dictionary:
	var tier_value := String(source.get("tier", ""))
	var mode_value := String(source.get("mode", ""))
	var audio_value := String(source.get("audioMode", source.get("audio_mode", "")))
	if not TIERS.has(tier_value) or not MODES.has(mode_value) or not AUDIO_MODES.has(audio_value):
		return {}
	if mode_value == MODE_PREMIUM_LIVE and tier_value != TIER_PREMIUM:
		return {}
	var raw_capabilities: Variant = source.get("capabilities", [])
	if typeof(raw_capabilities) != TYPE_ARRAY:
		return {}
	var capabilities: Array[String] = []
	for item: Variant in raw_capabilities:
		if typeof(item) != TYPE_STRING:
			return {}
		var capability := String(item).strip_edges()
		if capability.is_empty() or capability.length() > 40:
			return {}
		if not capabilities.has(capability):
			capabilities.append(capability)
	var quota := float(source.get("quotaRemaining", source.get("quota_remaining", -1.0)))
	if not is_finite(quota) or quota < -1.0:
		return {}
	return {
		"tier": tier_value,
		"mode": mode_value,
		"capabilities": capabilities,
		"quotaRemaining": quota,
		"audioMode": audio_value,
	}
