extends "res://scripts/tutor/providers/speech_synthesis_provider.gd"

## BackendSynthesisProvider -- a STUB, on purpose.
##
## The future cloud voice route: the game would POST the validated turn's text
## to the backend (`TutorFlags.backend_url()` + `/api/v1/tutor/tts`, an
## endpoint Agent D has not built), the backend would call its configured TTS
## model with a configured `voiceId` (settings key `aiVoiceId`, Agent F) and
## stream audio bytes back; the bytes would play on an `AudioStreamPlayer` on
## the "Voice" bus so `LipSyncSource` reads them like a recording, with music
## ducking through the same bus.
##
## Today: `is_available()` is false, `speak()` refuses (returns false, emits
## nothing), and `VoicePackSynthesisProvider` speaks every turn. No network
## primitive exists in this file, and none may be added until
## `TutorFlags.cloud_enabled()` is read first (the privacy guard checks the
## source order) and the endpoint exists. No cloud TTS is called from the
## game while the flag is off.

const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const REASON_UNAVAILABLE: String = "unavailable"

var _voice_id: String = ""


func provider_name() -> String:
	return "backend_tts"


## False until the route exists AND the flag is on. The flag alone is not enough.
func is_available() -> bool:
	return false


## The configured cloud voice preset name (never a provider voice id literal in
## the client; the backend maps it).
func set_voice_id(voice_id: String) -> void:
	_voice_id = voice_id.strip_edges()


func voice_id() -> String:
	return _voice_id


## Why a caller got nothing: the route is not built (and, in public builds,
## the flag is off).
func unavailable_reason() -> String:
	if not TutorFlags.cloud_enabled():
		return "cloud_disabled"
	return REASON_UNAVAILABLE


func speak(_text: String, _spoken_line_id: String = "") -> bool:
	return false
