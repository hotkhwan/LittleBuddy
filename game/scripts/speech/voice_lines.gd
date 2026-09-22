class_name VoiceLines
extends RefCounted
## Owner-recorded voice lines: a bundled OGG per line, played instead of TTS
## when present, silently skipped when not.
##
##     VoiceLines.line_id_for("Time to drink!")   # -> "time_to_drink"
##     VoiceLines.stream_path("time_to_drink")    # -> "res://audio/voice/time_to_drink.ogg"
##     VoiceLines.stream_for("Time to drink!")    # -> AudioStream, or null
##
## `TtsService._begin()` asks `stream_for(text)` first. A file at the drop-in
## path wins; anything else goes to the platform voice exactly as before, so a
## half-delivered set of recordings is fine -- the child hears a real voice for
## the lines that exist and Samantha for the rest, never silence.
##
## The line id is `Localization.key_for(<English text>)`, the same stable key
## the helper tables use, so one id names a line in every table this project
## keeps. The request list for the owner (id, text, emotion, length) is
## `docs/VOICE_ASSET_REQUEST.md`; `LINES` below is the same list in code so a
## test can hold the two together.
##
## Engine-agnostic apart from `ResourceLoader`/`FileAccess`: no Node, no 3D.

const Localization := preload("res://scripts/localization/localization.gd")

const VOICE_DIR: String = "res://audio/voice"
const EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]

## Every line the owner is asked to record: id -> {text, emotion, seconds}.
## Mission 01 (I'm Hungry!), the feeding vocabulary, and the UI encouragement.
const LINES: Dictionary = {
	# -- Mission 01: I'm Hungry! ---------------------------------------------
	"im_hungry_aliz": {"text": "I'm hungry, Aliz!", "emotion": "hungry, a little whiny, cute", "seconds": 1.6},
	"go_to_bunny": {"text": "Go to Baby.", "emotion": "warm, guiding", "seconds": 1.2},
	"lets_make_some_milk": {"text": "Let's make some milk!", "emotion": "bright, excited", "seconds": 1.6},
	"walk_to_the_kitchen": {"text": "Walk to the kitchen.", "emotion": "calm, clear", "seconds": 1.5},
	"where_is_the_bottle": {"text": "Where is the bottle?", "emotion": "curious, playful", "seconds": 1.5},
	"find_the_baby_bottle": {"text": "Find the baby bottle.", "emotion": "calm, clear", "seconds": 1.5},
	"pour_the_water_then_mix": {"text": "Pour the water, then mix.", "emotion": "calm, step by step", "seconds": 2.0},
	"take_it_to_bunny": {"text": "Take it to Baby!", "emotion": "encouraging", "seconds": 1.3},
	"time_to_drink": {"text": "Time to drink!", "emotion": "happy", "seconds": 1.2},
	"give_bunny_the_bottle": {"text": "Give Baby the bottle.", "emotion": "warm", "seconds": 1.5},
	"bunny_wants_a_cuddle": {"text": "Baby wants a cuddle.", "emotion": "soft, tender", "seconds": 1.6},
	"give_bunny_a_big_hug": {"text": "Give Baby a big hug.", "emotion": "warm, smiling", "seconds": 1.6},
	"thank_you_aliz": {"text": "Thank you, Aliz!", "emotion": "grateful, happy", "seconds": 1.3},
	# -- Feeding -------------------------------------------------------------
	"im_hungry": {"text": "I'm hungry.", "emotion": "hungry, cute", "seconds": 1.0},
	"im_thirsty": {"text": "I'm thirsty.", "emotion": "thirsty, cute", "seconds": 1.0},
	"give_the_baby_some_milk": {"text": "Give the baby some milk.", "emotion": "warm, guiding", "seconds": 1.8},
	"give_the_baby_the_apple": {"text": "Give the baby the apple.", "emotion": "warm, guiding", "seconds": 1.8},
	"give_the_baby_the_banana": {"text": "Give the baby the banana.", "emotion": "warm, guiding", "seconds": 1.8},
	"give_me_some_water": {"text": "Give me some water.", "emotion": "asking, cute", "seconds": 1.5},
	"can_you_say_milk": {"text": "Can you say milk?", "emotion": "inviting, patient", "seconds": 1.4},
	"milk": {"text": "milk", "emotion": "clear, slow, single word", "seconds": 0.8},
	"apple": {"text": "apple", "emotion": "clear, slow, single word", "seconds": 0.8},
	"banana": {"text": "banana", "emotion": "clear, slow, single word", "seconds": 0.9},
	"water": {"text": "water", "emotion": "clear, slow, single word", "seconds": 0.8},
	# -- Encouragement and UI -----------------------------------------------
	"great": {"text": "Great!", "emotion": "delighted", "seconds": 0.7},
	"nice": {"text": "Nice!", "emotion": "pleased", "seconds": 0.6},
	"well_done": {"text": "Well done!", "emotion": "proud, warm", "seconds": 0.9},
	"thank_you": {"text": "Thank you!", "emotion": "grateful, happy", "seconds": 0.9},
	"try_again": {"text": "Try again!", "emotion": "kind, no disappointment", "seconds": 0.9},
	"you_can_tap_it_too": {"text": "You can tap it too!", "emotion": "kind, helpful", "seconds": 1.4},
	"lets_go": {"text": "Let's go!", "emotion": "bright", "seconds": 0.8},
	"this_way": {"text": "This way!", "emotion": "guiding, cheerful", "seconds": 0.8},
	"here_we_are": {"text": "Here we are!", "emotion": "arriving, pleased", "seconds": 1.0},
	"im_listening": {"text": "I'm listening...", "emotion": "attentive, gentle", "seconds": 1.2},
	"voice_is_not_ready_tap_it_instead": {"text": "Voice is not ready. Tap it instead!", "emotion": "matter-of-fact, kind", "seconds": 2.0},
	"take_a_break": {"text": "Take a break?", "emotion": "gentle, caring", "seconds": 1.0},
}


## The id a spoken line is filed under.
static func line_id_for(text: String) -> String:
	return Localization.key_for(text)


## Where a recording for `line_id` is expected, with the preferred extension.
static func stream_path(line_id: String, extension: String = "ogg") -> String:
	return "%s/%s.%s" % [VOICE_DIR, line_id, extension]


## The first bundled recording for `line_id`, or "" when none is shipped.
static func find_recording(line_id: String) -> String:
	if line_id.is_empty():
		return ""
	for extension: String in EXTENSIONS:
		var path: String = stream_path(line_id, extension)
		if ResourceLoader.exists(path):
			return path
	return ""


static func has_recording(text: String) -> bool:
	return not find_recording(line_id_for(text)).is_empty()


## The stream for `text`'s recording, or null. Null is the normal answer today:
## no recordings are bundled yet, and TTS carries every line.
static func stream_for(text: String) -> AudioStream:
	var path: String = find_recording(line_id_for(text))
	if path.is_empty():
		return null
	var resource: Resource = load(path)
	return resource as AudioStream


## Ids in request order. Tests and the asset request document.
static func line_ids() -> Array:
	return LINES.keys()


static func english_for(line_id: String) -> String:
	return String((LINES.get(line_id, {}) as Dictionary).get("text", ""))
