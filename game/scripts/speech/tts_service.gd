## Autoload facade for text-to-speech.
##
## Every English prompt the child hears goes through here. It uses Godot's
## built-in `DisplayServer` TTS (AVSpeechSynthesizer on iOS/macOS) when a voice
## is available, and always guarantees `speech_finished` fires -- via a safety
## timer -- so gameplay sequencing can never deadlock, even on a build with no
## TTS support at all.
##
## ## Why there is a queue in here
##
## `DisplayServer.tts_speak()` takes an `interrupt` flag as its LAST argument:
##
##     tts_speak(text, voice, volume, pitch, rate, utterance_id, interrupt)
##
## This service owns utterance ordering itself rather than relying on any
## platform's native queue: exactly one utterance is ever in flight, and the next
## one starts only when the current one is reported finished (natively, or by the
## safety timer). `speak(text, false)` therefore genuinely QUEUES -- two prompts
## can never talk over each other, and a queued prompt can never truncate the one
## before it. For a pre-reader a prompt that is cut off is a prompt that was
## never spoken.
##
## ## Child-friendly delivery
##
## Default adult TTS is too fast for a four-year-old meeting a word for the first
## time, so the default rate is deliberately below 1.0 and the parent-facing
## `ttsSpeed = "slow"` setting slows it further. Pitch is lifted a little --
## bright, not cartoonish.
##
## ## Which voice speaks (2026-09-20 voice pass)
##
## This used to hand the platform `tts_get_voices_for_language("en")[0]`, which
## on every Apple device is `com.apple.voice.compact.en-US.Samantha` -- the
## lowest-quality tier Apple ships, and exactly the "robot" the owner heard.
##
## `choose_voice()` now walks a documented preference chain (see
## `PREFERRED_VOICE_IDS`): the brightest, youngest-sounding female en-US voices
## Apple offers, best quality tier first, then any natural-tier en-US voice
## (female names first), then any natural-tier English voice, then anything
## English at all. The novelty (`com.apple.speech.synthesis.voice.*`) and
## Eloquence (`com.apple.eloquence.*`) engines are last resort only: "Junior"
## and "Superstar" are child-*named*, not child-*sounding*.
##
## Plainly: no Apple device ships a true child voice, and this service does not
## pretend otherwise. The premium/enhanced voices in the chain are a one-time
## download in Settings > Accessibility > Spoken Content > Voices; once present
## they are picked up automatically, fully on-device. The real path to a small,
## cheerful girl voice is recorded lines from a voice actor bundled as OGG -- see
## `docs/VOICE_HONESTY_PASS.md`.
##
## ## Reactions
##
## `react("Great!")` is for the short answers to something the child just did.
## A reaction starts at once (it may cut a prompt: the child has acted), and for
## `REACTION_PROTECT_SECONDS` a following `speak(text, true)` QUEUES behind it
## instead of truncating it -- so "Great!" is heard in full before the next
## prompt, and "Try again!" is heard before the repeated ask.
##
## ## Degrading
##
## No TTS feature, no English voice, no SceneTree: `speak()` still emits
## `speech_started` / `speech_finished` with sensible pacing, so the on-screen
## text still advances silently and nothing crashes.
##
## Local synthesis only. No network, and the child's microphone is never involved.
extends Node

## Multiplier applied to the platform's default speaking rate.
## Slower than an adult default: the child is learning these words, not
## reviewing them. 1.0 would be the platform default. Raised from 0.85 in the
## voice pass: the prompts are two to five words, and at 0.85 the loop felt
## sluggish rather than careful.
const NORMAL_SPEECH_RATE: float = 0.92
## Parent setting `ttsSpeed = "slow"`. Noticeably slower, still natural.
const SLOW_SPEECH_RATE: float = 0.78

## Lifted pitch reads as bright and young without turning into a chipmunk.
## 1.05 was inaudible as a change on the compact voice; 1.15 is clearly
## lighter. The test band is 0.9-1.2.
const SPEECH_PITCH: float = 1.15

## Voice preference chain, best first. Identifiers are Apple's stable voice
## ids (the same on macOS and iOS). Only voices the device actually has are
## ever chosen; a missing one is simply skipped. Zoe and Nicky are the
## youngest, brightest en-US female voices Apple ships; Ava and Allison are
## warm; Samantha is the always-present default (enhanced beats compact).
const PREFERRED_VOICE_IDS: Array[String] = [
	"com.apple.voice.premium.en-US.Zoe",
	"com.apple.voice.enhanced.en-US.Zoe",
	"com.apple.voice.premium.en-US.Nicky",
	"com.apple.voice.enhanced.en-US.Nicky",
	"com.apple.voice.premium.en-US.Ava",
	"com.apple.voice.enhanced.en-US.Ava",
	"com.apple.voice.enhanced.en-US.Allison",
	"com.apple.voice.premium.en-US.Samantha",
	"com.apple.voice.enhanced.en-US.Samantha",
	"com.apple.voice.enhanced.en-US.Joelle",
	"com.apple.voice.enhanced.en-US.Susan",
	"com.apple.voice.compact.en-US.Samantha",
]

## Female English voice names Apple ships, for the "any female en-US voice"
## rung of the chain on a device whose list holds none of the ids above.
const FEMALE_VOICE_NAMES: Array[String] = [
	"zoe", "nicky", "ava", "allison", "samantha", "joelle", "susan", "kathy",
	"karen", "catherine", "moira", "tessa", "kate", "serena", "martha", "stephanie",
	"fiona", "veena", "flo", "sandy", "shelley", "grandma",
]

## Engines that are last resort only: they sound mechanical or are novelties.
const LAST_RESORT_ID_PREFIXES: Array[String] = [
	"com.apple.eloquence.",
	"com.apple.speech.synthesis.voice.",
]

## How long a reaction is protected from being cut by the next prompt. Long
## enough for "Well done!" on the slow setting, short enough that a stuck
## utterance can never hold a prompt hostage.
const REACTION_PROTECT_SECONDS: float = 2.5

## 0-100. Prompts must sit clearly above the sound effects (which peak at
## -6 dBFS or lower); the platform default of 50 is easy to miss in a room with
## a child in it. Confirm comfort on device -- see the device checklist.
const SPEECH_VOLUME: int = 85

const MIN_DURATION_SECONDS: float = 0.6
const MAX_DURATION_SECONDS: float = 12.0
## ~150 wpm at rate 1.0; the estimate is divided by the current rate below.
const WORDS_PER_SECOND: float = 2.5

## The safety timer is a deadlock guard, not the normal path: when a native voice
## really is speaking, the platform's "utterance ended" callback should resolve
## first. Give it generous headroom so the timer cannot cut a prompt short.
const NATIVE_TIMEOUT_FACTOR: float = 1.6
const NATIVE_TIMEOUT_PAD_SECONDS: float = 0.8
## If the platform still reports itself speaking when the safety timer fires,
## wait this much longer rather than starting the next prompt over the top of it.
const TIMER_EXTENSION_SECONDS: float = 0.5
## Bounded so a platform that never stops reporting "speaking" cannot stall the
## queue permanently (10 s of extensions, then the queue moves on regardless).
const MAX_TIMER_EXTENSIONS: int = 20

## Nothing queued is ever silently dropped, but an unbounded queue would mean a
## child mashing a button could stack up a minute of speech. Oldest wins.
const MAX_QUEUED: int = 8

signal speech_started(text: String)
signal speech_finished(text: String)

var _initialised: bool = false
var _tts_feature_supported: bool = false
var _current_text: String = ""
var _is_speaking: bool = false
var _utterance_id: int = 0
var _current_utterance_id: int = 0
var _queue: Array[String] = []
## Set when the current utterance was handed to a real voice; drives how much
## headroom the safety timer gets.
var _current_used_native: bool = false
## Optional `func(duration: float, callback: Callable) -> void` used instead of a
## `SceneTreeTimer`. The headless test runner has no frame loop, so this is how
## the tests drive the queue one utterance at a time; production leaves it unset.
var _timer_factory: Callable = Callable()
## True while the current utterance is a protected reaction (see `react()`).
var _current_is_reaction: bool = false
## Engine ticks (msec) at which the current reaction's protection lapses.
var _reaction_protected_until_msec: int = 0
## The voice id handed to the platform for the last utterance, for diagnostics.
var _last_voice_id: String = ""


func _ready() -> void:
	_ensure_initialised()


## Callable from anywhere: this service is an autoload in the game but is also
## constructed bare in the headless test runner, where `_ready()` never fires.
func _ensure_initialised() -> void:
	if _initialised:
		return
	_initialised = true
	_tts_feature_supported = _has_tts_feature()
	if _tts_feature_supported:
		DisplayServer.tts_set_utterance_callback(
			DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_ended
		)
		DisplayServer.tts_set_utterance_callback(
			DisplayServer.TTS_UTTERANCE_CANCELED, _on_utterance_canceled
		)


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------


## Speaks `text`.
##
## `interrupt = true` (default) replaces anything currently speaking AND anything
## queued behind it -- use it when a new prompt supersedes the old one.
## `interrupt = false` queues `text` to be spoken after the current utterance, so
## two prompts never overlap and neither is truncated.
func speak(text: String, interrupt: bool = true) -> void:
	_ensure_initialised()
	var line: String = text.strip_edges()
	if line.is_empty():
		return

	if interrupt:
		if _reaction_is_protected():
			# The new prompt supersedes everything queued, but not the reaction
			# the child is being answered with right now: it goes next instead.
			_queue.clear()
			_queue.append(line)
			return
		stop()
		_begin(line)
		return

	if _is_speaking:
		if _queue.size() >= MAX_QUEUED:
			return
		_queue.append(line)
		return

	_begin(line)


## Explicit alias for the queueing path, so call sites read as what they mean.
func enqueue(text: String) -> void:
	speak(text, false)


## A short answer to something the child just did: "Great!", "Try again!".
##
## Starts immediately -- cutting a prompt mid-word is right here, because the
## child has acted and is waiting to hear how it went -- and is then protected:
## a `speak(text, true)` arriving within `REACTION_PROTECT_SECONDS` queues behind
## it rather than truncating it. A second reaction arriving during a protected
## one does not cut it either; it is spoken next, ahead of any prompt, so
## "Try again!" then "You can tap it too!" arrive in that order.
func react(text: String) -> void:
	_ensure_initialised()
	var line: String = text.strip_edges()
	if line.is_empty():
		return
	if _reaction_is_protected():
		if _queue.size() >= MAX_QUEUED:
			return
		_queue.push_front(line)
		return
	stop()
	_begin(line, true)


## True while a reaction is being spoken and its protection has not lapsed.
func is_reaction_protected() -> bool:
	return _reaction_is_protected()


## Stops the current utterance and drops everything queued behind it.
## `speech_finished` still fires for the interrupted line so anything awaiting it
## is released rather than left hanging.
func stop() -> void:
	_ensure_initialised()
	_queue.clear()
	if _tts_feature_supported:
		DisplayServer.tts_stop()
	if _is_speaking:
		var text: String = _current_text
		_is_speaking = false
		_current_is_reaction = false
		_current_utterance_id = 0  # voids any in-flight safety timer
		_current_text = ""
		speech_finished.emit(text)


func is_available() -> bool:
	if not _has_tts_feature():
		return false
	return not _english_voices().is_empty()


func is_speaking() -> bool:
	return _is_speaking


func get_current_text() -> String:
	return _current_text


## Number of utterances waiting behind the current one.
func get_pending_count() -> int:
	return _queue.size()


func get_pending_texts() -> Array[String]:
	return _queue.duplicate()


## Advances the queue as if the platform had reported `utterance_id` finished.
##
## Called by the native utterance callbacks and by the safety timer. Public so
## the headless tests can drive the queue deterministically -- in `--script` runs
## there is no frame loop, so a `SceneTreeTimer` would never fire.
func notify_utterance_finished(utterance_id: int) -> void:
	_complete_utterance(utterance_id)


## The rate handed to the platform, for tests and diagnostics.
func get_speech_rate() -> float:
	return _speech_rate()


## The voice this service would speak with right now: `{id, name, language,
## tier}`, or an empty Dictionary when the platform has no English voice.
## `tier` is one of premium / enhanced / compact / super-compact / eloquence /
## novelty / other, read off Apple's id so a parent panel can say which.
func get_selected_voice() -> Dictionary:
	if not _has_tts_feature():
		return {}
	return choose_voice(DisplayServer.tts_get_voices())


## One line for the parent diagnostic: "Samantha (compact)" or "none".
func describe_voice() -> String:
	var voice: Dictionary = get_selected_voice()
	if voice.is_empty():
		return "none"
	return "%s (%s)" % [String(voice.get("name", "?")), String(voice.get("tier", "?"))]


## The voice id used for the most recent utterance ("" if none spoke natively).
func get_last_voice_id() -> String:
	return _last_voice_id


## Picks the voice to speak with from a platform voice list (dictionaries with
## `id`, `name`, `language`, as `DisplayServer.tts_get_voices()` returns them).
##
## Static and pure so the chain can be tested against any list without a
## platform. The order is the documented fallback chain:
##   1. `PREFERRED_VOICE_IDS`, in order;
##   2. any natural-tier (`com.apple.voice.*`) en-US voice, female names first;
##   3. any natural-tier voice in any English locale, female names first;
##   4. any en-US voice, then any English voice, avoiding last-resort engines;
##   5. any English voice at all.
## Returns {} when the list holds no English voice.
static func choose_voice(voices: Array) -> Dictionary:
	var english: Array = []
	for entry in voices:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var voice: Dictionary = entry
		var language: String = String(voice.get("language", "")).replace("_", "-").to_lower()
		if language.begins_with("en"):
			english.append(voice)
	if english.is_empty():
		return {}

	for wanted: String in PREFERRED_VOICE_IDS:
		for voice: Dictionary in english:
			if String(voice.get("id", "")) == wanted:
				return _describe(voice)

	var natural_us: Array = english.filter(func(v: Dictionary) -> bool:
		return _is_natural_apple_id(String(v.get("id", ""))) and _is_en_us(v))
	var pick: Dictionary = _first_female_else_first(natural_us)
	if not pick.is_empty():
		return _describe(pick)

	var natural_any: Array = english.filter(func(v: Dictionary) -> bool:
		return _is_natural_apple_id(String(v.get("id", ""))))
	pick = _first_female_else_first(natural_any)
	if not pick.is_empty():
		return _describe(pick)

	var plain_us: Array = english.filter(func(v: Dictionary) -> bool:
		return _is_en_us(v) and not _is_last_resort_id(String(v.get("id", ""))))
	pick = _first_female_else_first(plain_us)
	if not pick.is_empty():
		return _describe(pick)

	var plain_any: Array = english.filter(func(v: Dictionary) -> bool:
		return not _is_last_resort_id(String(v.get("id", ""))))
	pick = _first_female_else_first(plain_any)
	if not pick.is_empty():
		return _describe(pick)

	return _describe(english[0])


## The quality tier encoded in an Apple voice id, for diagnostics.
static func voice_tier(voice_id: String) -> String:
	if voice_id.begins_with("com.apple.voice.premium."):
		return "premium"
	if voice_id.begins_with("com.apple.voice.enhanced."):
		return "enhanced"
	if voice_id.begins_with("com.apple.voice.super-compact."):
		return "super-compact"
	if voice_id.begins_with("com.apple.voice.compact."):
		return "compact"
	if voice_id.begins_with("com.apple.eloquence."):
		return "eloquence"
	if voice_id.begins_with("com.apple.speech.synthesis.voice."):
		return "novelty"
	return "other"


static func _describe(voice: Dictionary) -> Dictionary:
	var voice_id: String = String(voice.get("id", ""))
	return {
		"id": voice_id,
		"name": String(voice.get("name", voice_id)),
		"language": String(voice.get("language", "")),
		"tier": voice_tier(voice_id),
	}


static func _is_en_us(voice: Dictionary) -> bool:
	var language: String = String(voice.get("language", "")).replace("_", "-").to_lower()
	return language == "en-us"


static func _is_natural_apple_id(voice_id: String) -> bool:
	return voice_id.begins_with("com.apple.voice.")


static func _is_last_resort_id(voice_id: String) -> bool:
	for prefix: String in LAST_RESORT_ID_PREFIXES:
		if voice_id.begins_with(prefix):
			return true
	return false


static func _is_female_name(voice: Dictionary) -> bool:
	var name: String = String(voice.get("name", "")).to_lower()
	for female: String in FEMALE_VOICE_NAMES:
		if name == female or name.begins_with(female + " "):
			return true
	return false


static func _first_female_else_first(candidates: Array) -> Dictionary:
	if candidates.is_empty():
		return {}
	for voice: Dictionary in candidates:
		if _is_female_name(voice):
			return voice
	return candidates[0]


## Replaces the `SceneTreeTimer` used for the "utterance finished" safety net
## with `factory.call(duration: float, callback: Callable)`. A seam for the
## headless tests (no frame loop there, so a real timer would never fire).
func set_timer_factory(factory: Callable) -> void:
	_timer_factory = factory


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------


func _begin(text: String, is_reaction: bool = false) -> void:
	_utterance_id += 1
	var utterance_id: int = _utterance_id
	_current_utterance_id = utterance_id
	_current_text = text
	_is_speaking = true
	_current_used_native = false
	_current_is_reaction = is_reaction
	if is_reaction:
		_reaction_protected_until_msec = Time.get_ticks_msec() \
				+ int(REACTION_PROTECT_SECONDS * 1000.0)

	speech_started.emit(text)

	if _tts_feature_supported:
		_current_used_native = _try_speak_native(text, utterance_id)

	# A started utterance is never left unresolved: either the platform reports
	# it, or this timer does.
	_schedule_fallback(utterance_id, _timeout_for(text, _current_used_native))


func _try_speak_native(text: String, utterance_id: int) -> bool:
	var voice: Dictionary = get_selected_voice()
	if voice.is_empty():
		return false
	_last_voice_id = String(voice["id"])

	# Argument order is (text, voice, volume, PITCH, RATE, utterance_id,
	# interrupt). Getting pitch and rate the wrong way round silently produces a
	# deeper adult voice at unchanged speed instead of a slower one -- which is
	# exactly the opposite of what a child learning the word needs.
	DisplayServer.tts_speak(
		text,
		_last_voice_id,
		SPEECH_VOLUME,
		SPEECH_PITCH,
		_speech_rate(),
		utterance_id,
		true,  # ordering is owned here; only ever one utterance in flight
	)
	return true


func _reaction_is_protected() -> bool:
	if not _is_speaking or not _current_is_reaction:
		return false
	return Time.get_ticks_msec() < _reaction_protected_until_msec


func _english_voices() -> PackedStringArray:
	return DisplayServer.tts_get_voices_for_language("en")


## Reads the parent-facing "ttsSpeed" setting. Read defensively: SaveService may
## be absent (tests, a scene run on its own).
func _speech_rate() -> float:
	var save_service: Node = null
	if is_inside_tree():
		save_service = get_node_or_null("/root/SaveService")
	if save_service == null or not save_service.has_method("get_setting"):
		return NORMAL_SPEECH_RATE
	if str(save_service.call("get_setting", "ttsSpeed", "normal")) == "slow":
		return SLOW_SPEECH_RATE
	return NORMAL_SPEECH_RATE


func _schedule_fallback(
	utterance_id: int, duration: float, extensions_left: int = MAX_TIMER_EXTENSIONS
) -> void:
	var resolve: Callable = func() -> void: _on_safety_timeout(utterance_id, extensions_left)

	if _timer_factory.is_valid():
		_timer_factory.call(duration, resolve)
		return

	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree and is_inside_tree():
		var timer: SceneTreeTimer = (main_loop as SceneTree).create_timer(duration)
		timer.timeout.connect(resolve)
		return
	# No frame loop to run a timer in (headless `--script` runs, or a service
	# built outside the tree). Resolve immediately so a queue can still drain and
	# nothing awaiting `speech_finished` hangs forever.
	_complete_utterance(utterance_id)


## The safety timer fired. If a real voice is demonstrably still talking, wait a
## little longer rather than starting the next prompt over the top of it: the
## timer is only an estimate, and talking over the child's prompt is worse than
## a slightly longer pause. Bounded, so a platform that never stops reporting
## "speaking" cannot stall the queue forever.
func _on_safety_timeout(utterance_id: int, extensions_left: int) -> void:
	if utterance_id != _current_utterance_id or not _is_speaking:
		return
	if extensions_left > 0 and _current_used_native and _platform_is_speaking():
		_schedule_fallback(utterance_id, TIMER_EXTENSION_SECONDS, extensions_left - 1)
		return
	_complete_utterance(utterance_id)


func _platform_is_speaking() -> bool:
	if not _tts_feature_supported:
		return false
	return DisplayServer.tts_is_speaking()


func _complete_utterance(utterance_id: int) -> void:
	if utterance_id != _current_utterance_id:
		return  # a newer speak()/stop() already resolved this utterance
	if not _is_speaking:
		return
	var text: String = _current_text
	_is_speaking = false
	_current_is_reaction = false
	_current_utterance_id = 0
	_current_text = ""
	speech_finished.emit(text)
	_pump()


## Starts the next queued utterance, if any.
func _pump() -> void:
	if _is_speaking or _queue.is_empty():
		return
	_begin(_queue.pop_front())


func _on_utterance_ended(utterance_id: int) -> void:
	_complete_utterance(utterance_id)


func _on_utterance_canceled(utterance_id: int) -> void:
	_complete_utterance(utterance_id)


## How long to wait before assuming the platform will never report this
## utterance. When no voice spoke, this doubles as the pacing of silent text.
func _timeout_for(text: String, used_native: bool) -> float:
	var estimate: float = _estimate_duration(text)
	if not used_native:
		return estimate
	return estimate * NATIVE_TIMEOUT_FACTOR + NATIVE_TIMEOUT_PAD_SECONDS


## Spoken length estimate, scaled by the current rate: slower speech takes
## longer, and a timeout computed at rate 1.0 would truncate slow speech.
func _estimate_duration(text: String) -> float:
	var words: PackedStringArray = text.split(" ", false)
	var word_count: int = maxi(words.size(), 1)
	var rate: float = maxf(_speech_rate(), 0.1)
	var duration: float = float(word_count) / (WORDS_PER_SECOND * rate)
	return clampf(duration, MIN_DURATION_SECONDS, MAX_DURATION_SECONDS)


func _has_tts_feature() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
