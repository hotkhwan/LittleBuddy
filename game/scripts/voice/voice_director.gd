extends Node
## `Voice` -- the recorded voice pack's player (autoload; see docs/VOICE_PACK_V1.md).
##
##     Voice.say("bunny_003_yummy")                 # Bunny reacts
##     Voice.say("aliz_014_milk_time", {"queue": true})   # narration, after whatever is playing
##     Voice.say("aliz_021_star", {"interrupt": true})    # now, cutting anything
##
## Two characters, one voice at a time. Every line id comes from
## `content/voice/voice_manifest.json` (the owner's 36 lines); an id the manifest
## does not know is refused (`say()` returns false) rather than guessed.
##
## ## What plays
##
## When the line's OGG is in the build, it plays on that character's own
## `AudioStreamPlayer` on the "Voice" bus. When it is NOT (today: all 36), the
## manifest text is spoken through `TtsService` -- the same queue rules apply,
## `line_started` still fires (the subtitle still shows), and `is_recorded()`
## answers false. Nothing is ever faked: there is no silent placeholder, no
## pretend duration, no "recorded" flag on a file that is not there.
##
## ## Never two voices at once
##
## A recording and the device voice must never overlap. Before a recording
## starts, `TtsService.stop()` is called if it is speaking; a fallback line is
## handed to `TtsService` as ONE utterance and this node waits for its
## `speech_finished`. While the device voice is busy with a prompt that is not
## ours (a mode handler's instruction), a non-interrupting line WAITS for it --
## cutting a prompt a pre-reader has not finished hearing is worse than a late
## reaction. `test_voice_director.gd` drives both cases.
##
## ## Queue rules
##
##   * default (`say(id)`):
##       - Aliz preempts a playing Bunny line and clears queued Bunny lines;
##         behind a playing Aliz line she queues (replacing queued Aliz lines).
##       - Bunny never interrupts anyone: he queues behind Aliz, or behind his
##         own current line, replacing his own queued lines.
##   * `{"queue": true}`: never cuts, never replaces; plain FIFO behind
##     whatever is playing or queued (sequences and follow-ups use this).
##   * `{"interrupt": true}`: cuts whatever is playing (recording or TTS, ours
##     or not) and clears the queue.
##   * `stop(character)`: cuts that character's current line and drops their
##     queued lines; `stop()` cuts everything.
##
## ## Volume
##
## Per character, 0..1, persisted in the profile settings as `alizVoiceVolume`
## and `bunnyVoiceVolume`. The old single `voiceVolume` is migrated into
## `alizVoiceVolume` once (Aliz IS the narration voice `TtsService` has been
## playing all along), and `TtsService.set_voice_volume()` is kept in step
## with Aliz's level so the device voice and her recordings sit at one level.

const VoiceManifestScript := preload("res://scripts/voice/voice_manifest.gd")
const VoiceCuesScript := preload("res://scripts/voice/voice_cues.gd")

signal line_started(line_id: String, character: String, text: String)
signal line_finished(line_id: String)
signal character_volume_changed(character: String, linear: float)

const CHARACTER_ALIZ: String = VoiceManifestScript.CHARACTER_ALIZ
const CHARACTER_BUNNY: String = VoiceManifestScript.CHARACTER_BUNNY
const CHARACTERS: Array[String] = [CHARACTER_ALIZ, CHARACTER_BUNNY]

const BUS_NAME: StringName = &"Voice"
const VOLUME_SETTING_KEYS: Dictionary = {
	CHARACTER_ALIZ: "alizVoiceVolume",
	CHARACTER_BUNNY: "bunnyVoiceVolume",
}
const LEGACY_VOLUME_SETTING: String = "voiceVolume"
const DEFAULT_VOLUME: float = 0.85
const MAX_QUEUED: int = 6

## A recording's safety timer, like `TtsService`'s: `finished` is expected, but
## a playback that never reports (a device that suspends audio mid-line) must
## still release the queue.
const RECORDING_TIMEOUT_FACTOR: float = 1.25
const RECORDING_TIMEOUT_PAD_SECONDS: float = 0.5
const MIN_RECORDING_SECONDS: float = 0.3
## Mirrors `TtsService.REACTION_PROTECT_SECONDS`: a recorded reaction younger
## than this is not cut by a device-voice prompt; the prompt follows it.
const REACTION_PROTECT_SECONDS: float = 2.5

const MODE_RECORDING: String = "recording"
const MODE_TTS: String = "tts"

const TTS_SERVICE_PATH: String = "/root/TtsService"
const SAVE_SERVICE_PATH: String = "/root/SaveService"

var _initialised: bool = false
var _manifest: RefCounted = null
var _players: Dictionary = {}
var _volumes: Dictionary = {}
var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _serial: int = 0
var _tts: Node = null
var _save: Node = null
var _tts_hooked: bool = false
var _suppress_tts_events: int = 0
var _timer_factory: Callable = Callable()
var _stream_resolver: Callable = Callable()
var _tts_volume_is_bunny: bool = false


func _ready() -> void:
	build()


## Idempotent; callable before `_ready()` (the headless runner never fires it
## for a node added to the root during `_initialize()`).
func build() -> void:
	_ensure_initialised()


func _ensure_initialised() -> void:
	if _initialised:
		return
	_initialised = true
	if _manifest == null:
		_manifest = VoiceManifestScript.load_default()
	_ensure_bus()
	for character: String in CHARACTERS:
		_ensure_player(character)
	_load_volumes()
	_hook_tts()


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------


## Plays (or queues) `line_id`. Returns false only for an id the manifest does
## not know; true means the line is playing or queued under the rules above.
## `opts`: {"interrupt": bool, "queue": bool, "reaction": bool}.
## Every Bunny line is a reaction; an Aliz line is one only when asked
## (`reaction: true` -- praise). A reaction that is a RECORDING is protected
## for `REACTION_PROTECT_SECONDS` from a device-voice prompt arriving on top:
## the prompt is held and said right after it instead (see `_on_tts_started`).
func say(line_id: String, opts: Dictionary = {}) -> bool:
	_ensure_initialised()
	if not _manifest.has_line(line_id):
		return false
	var character: String = _manifest.character_for(line_id)
	if not CHARACTERS.has(character):
		return false
	return _submit({
		"lineId": line_id,
		"character": character,
		"text": _manifest.text_for(line_id),
	}, opts)


## Speaks free English text under the same queue rules. When `text` is one of
## the 36 lines (or a documented alias -- `VoiceCues.for_text`), the recorded
## line is used; otherwise the text goes to the device voice as an ad-hoc Aliz
## line with an empty `lineId`. Subtitles show it either way. This is how
## `prompt_speaker.gd` and the `_speak()` call sites hand everything they say to
## one queue instead of two.
## `opts` as for `say()`, plus `"character"` ("aliz" default) for an ad-hoc line.
func say_text(text: String, opts: Dictionary = {}) -> bool:
	_ensure_initialised()
	var line: String = text.strip_edges()
	if line.is_empty():
		return false
	var line_id: String = VoiceCuesScript.for_text(line)
	if not line_id.is_empty() and _manifest.has_line(line_id):
		return say(line_id, opts)
	var character: String = String(opts.get("character", CHARACTER_ALIZ))
	if not CHARACTERS.has(character):
		character = CHARACTER_ALIZ
	return _submit({"lineId": "", "character": character, "text": line}, opts)


func _submit(entry: Dictionary, opts: Dictionary) -> bool:
	var character: String = String(entry["character"])
	entry["cut"] = false
	entry["reaction"] = bool(opts.get("reaction", false)) or character == CHARACTER_BUNNY
	var interrupt: bool = bool(opts.get("interrupt", false))
	var queue_only: bool = bool(opts.get("queue", false))

	if interrupt:
		_queue.clear()
		_cut_current()
		_stop_foreign_tts()
		entry["cut"] = true
		_begin(entry)
		return true

	if queue_only:
		_enqueue(entry)
		_pump()
		return true

	# Default policy.
	if character == CHARACTER_ALIZ:
		_drop_queued(CHARACTER_BUNNY)
		if _current_character() == CHARACTER_BUNNY:
			_cut_current()
			entry["cut"] = true
			_begin(entry)
			return true
		_drop_queued(CHARACTER_ALIZ)
		_enqueue(entry)
		_pump()
		return true

	# Bunny never interrupts.
	_drop_queued(CHARACTER_BUNNY)
	_enqueue(entry)
	_pump()
	return true


## Says the first line for a `VoiceCues` event result; convenience for call sites
## that already hold an Array of ids (`say_all`).
func say_all(line_ids: Array, opts: Dictionary = {}) -> int:
	var accepted: int = 0
	var first: bool = true
	for line_id: Variant in line_ids:
		var per_line: Dictionary = opts.duplicate()
		if not first:
			# Only the first line of a sequence carries the interruption; the
			# rest follow it in order.
			per_line.erase("interrupt")
			per_line["queue"] = true
		if say(String(line_id), per_line):
			accepted += 1
		first = false
	return accepted


## Cuts `character`'s current line and drops their queued lines. `""` = everyone.
func stop(character: String = "") -> void:
	_ensure_initialised()
	if character.is_empty():
		_queue.clear()
		_cut_current()
		_stop_foreign_tts()
		return
	_drop_queued(character)
	if _current_character() == character:
		_cut_current()
		_pump()


func is_speaking() -> bool:
	return not _current.is_empty()


func current_line() -> String:
	return String(_current.get("lineId", ""))


func current_character() -> String:
	return _current_character()


func current_text() -> String:
	return String(_current.get("text", ""))


## True while the CURRENT line is an actual recording (never for the fallback).
func is_playing_recording() -> bool:
	return String(_current.get("mode", "")) == MODE_RECORDING


func pending_line_ids() -> Array:
	var ids: Array = []
	for entry: Dictionary in _queue:
		ids.append(String(entry["lineId"]))
	return ids


func pending_texts() -> Array:
	var texts: Array = []
	for entry: Dictionary in _queue:
		texts.append(String(entry["text"]))
	return texts


## Whether `line_id`'s recording is in the build. Manifest truth only.
func is_recorded(line_id: String) -> bool:
	_ensure_initialised()
	if _stream_resolver.is_valid():
		return _stream_resolver.call(line_id) != null
	return _manifest.is_recorded(line_id)


func manifest() -> RefCounted:
	_ensure_initialised()
	return _manifest


func text_for(line_id: String) -> String:
	_ensure_initialised()
	return _manifest.text_for(line_id)


## "0 of 36 recordings present" -- for the runbook and the settings screen.
func presence_summary() -> String:
	_ensure_initialised()
	return _manifest.presence_summary()


# -- Volume ---------------------------------------------------------------------


## 0..1 per character. Persists to the profile and applies at once.
func set_character_volume(character: String, linear: float) -> void:
	_ensure_initialised()
	if not CHARACTERS.has(character):
		return
	var level: float = clampf(linear, 0.0, 1.0) if is_finite(linear) else DEFAULT_VOLUME
	_volumes[character] = level
	_apply_player_volume(character)
	var save: Node = _save_service()
	if save != null and save.has_method("set_setting"):
		save.call("set_setting", String(VOLUME_SETTING_KEYS[character]), level)
	_sync_tts_volume()
	character_volume_changed.emit(character, level)


func get_character_volume(character: String) -> float:
	_ensure_initialised()
	return float(_volumes.get(character, DEFAULT_VOLUME))


## The setting key a character's level lives under (for the settings screen).
static func volume_setting_key(character: String) -> String:
	return String(VOLUME_SETTING_KEYS.get(character, ""))


# -- Test / composition hooks -----------------------------------------------------


func set_tts(tts: Node) -> void:
	_unhook_tts()
	_tts = tts
	_hook_tts()


func set_save_service(save: Node) -> void:
	_save = save
	if _initialised:
		_load_volumes()


func set_manifest(value: RefCounted) -> void:
	_manifest = value


## `factory(seconds, callback)` replaces the SceneTree timer for recordings.
func set_timer_factory(factory: Callable) -> void:
	_timer_factory = factory


## `resolver(line_id) -> AudioStream|null` replaces the on-disk lookup. Tests
## use it to prove the recording path without committing a single fake file.
func set_stream_resolver(resolver: Callable) -> void:
	_stream_resolver = resolver


func get_player(character: String) -> AudioStreamPlayer:
	_ensure_initialised()
	return _players.get(character, null)


## A recording finished (or the platform says so). Public so a test can drive
## it exactly like `AudioStreamPlayer.finished` would.
func notify_recording_finished(character: String) -> void:
	if _current_character() != character or String(_current.get("mode", "")) != MODE_RECORDING:
		return
	_complete(int(_current["serial"]))


# -----------------------------------------------------------------------------
# Queue internals
# -----------------------------------------------------------------------------


func _enqueue(entry: Dictionary) -> void:
	if _queue.size() >= MAX_QUEUED:
		_queue.pop_front()
	_queue.append(entry)


func _drop_queued(character: String) -> void:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _queue:
		if String(entry["character"]) != character:
			kept.append(entry)
	_queue = kept


func _pump() -> void:
	if not _current.is_empty() or _queue.is_empty():
		return
	if _foreign_tts_speaking():
		# Wait for the prompt to end (`_on_tts_finished` pumps again) -- unless
		# the prompt IS our next line said by someone else, which `_begin()`
		# adopts rather than repeats.
		var tts: Node = _tts_service()
		var front: Dictionary = _queue[0]
		if tts == null or not tts.has_method("get_current_text") \
				or String(tts.call("get_current_text")) != String(front["text"]):
			return
	var next: Dictionary = _queue.pop_front()
	_begin(next)


func _current_character() -> String:
	return String(_current.get("character", ""))


func _begin(entry: Dictionary) -> void:
	_serial += 1
	entry["serial"] = _serial
	entry["started"] = false
	entry["beganMsec"] = Time.get_ticks_msec()
	var character: String = String(entry["character"])
	var text: String = String(entry["text"])
	var line_id: String = String(entry["lineId"])

	var stream: AudioStream = _stream_for(line_id)
	if stream != null:
		entry["mode"] = MODE_RECORDING
		_current = entry
		# One voice at a time: the device voice yields to a recording.
		_stop_foreign_tts()
		var player: AudioStreamPlayer = _ensure_player(character)
		player.stop()
		player.stream = stream
		_apply_player_volume(character)
		if player.is_inside_tree():
			player.play()
		# Outside a live tree (the headless runner) the engine refuses to play;
		# the line is still tracked and its timer still releases it.
		_mark_started()
		var seconds: float = maxf(stream.get_length(), MIN_RECORDING_SECONDS)
		_schedule(_serial, seconds * RECORDING_TIMEOUT_FACTOR + RECORDING_TIMEOUT_PAD_SECONDS)
		return

	entry["mode"] = MODE_TTS
	_current = entry
	var tts: Node = _tts_service()
	if tts == null or not tts.has_method("speak"):
		# No device voice in this build: the subtitle still shows, and the queue
		# still moves. Silence is honest; a hang is not.
		_mark_started()
		_complete(_serial)
		return
	# Already being said by someone else (a mode handler's own `speak()` of the
	# same prompt)? Adopt it instead of saying it twice.
	if tts.has_method("get_current_text") and String(tts.call("get_current_text")) == text \
			and bool(tts.call("is_speaking")):
		_mark_started()
		return
	if tts.has_method("get_pending_texts"):
		var pending: Variant = tts.call("get_pending_texts")
		if pending is Array and (pending as Array).has(text):
			return  # `_on_tts_started(text)` marks it
	_speak_via_tts(tts, character, text, bool(entry.get("cut", false)))


## Hands one line to `TtsService` and works out whether it started, was queued
## (reaction protection) or was resolved on the spot (headless: no timer loop).
func _speak_via_tts(tts: Node, character: String, text: String, cut: bool) -> void:
	var my_serial: int = int(_current.get("serial", -1))
	_set_tts_volume_for(character)
	if bool(_current.get("reaction", false)) and tts.has_method("react") \
			and not bool(tts.call("is_speaking")):
		# TtsService protects a reaction from the next prompt for 2.5 s: the
		# prompt queues behind it instead of truncating it.
		tts.call("react", text)
	else:
		tts.call("speak", text, cut)
	if _current.is_empty() or int(_current.get("serial", -1)) != my_serial:
		return  # resolved synchronously through the signals
	if tts.has_method("get_current_text") and String(tts.call("get_current_text")) == text \
			and bool(tts.call("is_speaking")):
		_mark_started()
		return
	var queued: bool = false
	if tts.has_method("get_pending_texts"):
		var pending: Variant = tts.call("get_pending_texts")
		queued = pending is Array and (pending as Array).has(text)
	if not queued:
		# Refused (empty text, full queue) or resolved without a signal: do not
		# leave the queue hanging on a line nobody is saying.
		_complete(my_serial)


func _mark_started() -> void:
	if _current.is_empty() or bool(_current.get("started", false)):
		return
	_current["started"] = true
	line_started.emit(String(_current["lineId"]), String(_current["character"]), String(_current["text"]))


func _complete(serial: int) -> void:
	if _current.is_empty() or int(_current.get("serial", -1)) != serial:
		return
	var finished: Dictionary = _current
	_current = {}
	if not bool(finished.get("started", false)):
		# Never a finish without a start: a subtitle listener pairs them.
		line_started.emit(String(finished["lineId"]), String(finished["character"]), String(finished["text"]))
	_restore_tts_volume()
	line_finished.emit(String(finished["lineId"]))
	_pump()


## Ends the current line now, whatever it is. Emits `line_finished`.
func _cut_current() -> void:
	if _current.is_empty():
		return
	var cut: Dictionary = _current
	_current = {}
	if String(cut.get("mode", "")) == MODE_RECORDING:
		var player: AudioStreamPlayer = _players.get(String(cut["character"]), null)
		if player != null and is_instance_valid(player):
			player.stop()
	else:
		var tts: Node = _tts_service()
		if tts != null and tts.has_method("stop"):
			_suppress_tts_events += 1
			tts.call("stop")
			_suppress_tts_events -= 1
	_restore_tts_volume()
	if not bool(cut.get("started", false)):
		line_started.emit(String(cut["lineId"]), String(cut["character"]), String(cut["text"]))
	line_finished.emit(String(cut["lineId"]))


## The device voice is saying something that is not one of our lines.
func _foreign_tts_speaking() -> bool:
	var tts: Node = _tts_service()
	if tts == null or not tts.has_method("is_speaking"):
		return false
	return bool(tts.call("is_speaking"))


func _stop_foreign_tts() -> void:
	var tts: Node = _tts_service()
	if tts == null or not tts.has_method("is_speaking") or not bool(tts.call("is_speaking")):
		return
	_suppress_tts_events += 1
	tts.call("stop")
	_suppress_tts_events -= 1


# -----------------------------------------------------------------------------
# TtsService coupling
# -----------------------------------------------------------------------------


func _tts_service() -> Node:
	if _tts != null and is_instance_valid(_tts):
		return _tts
	_tts = null
	_tts_hooked = false
	if is_inside_tree():
		_tts = get_node_or_null(TTS_SERVICE_PATH)
	else:
		var loop: MainLoop = Engine.get_main_loop()
		if loop is SceneTree and (loop as SceneTree).root != null:
			_tts = (loop as SceneTree).root.get_node_or_null(NodePath("TtsService"))
	_hook_tts()
	return _tts


func _hook_tts() -> void:
	if _tts_hooked or _tts == null or not is_instance_valid(_tts):
		return
	if _tts.has_signal("speech_started") and not _tts.speech_started.is_connected(_on_tts_started):
		_tts.speech_started.connect(_on_tts_started)
	if _tts.has_signal("speech_finished") and not _tts.speech_finished.is_connected(_on_tts_finished):
		_tts.speech_finished.connect(_on_tts_finished)
	_tts_hooked = true


func _unhook_tts() -> void:
	if _tts != null and is_instance_valid(_tts):
		if _tts.has_signal("speech_started") and _tts.speech_started.is_connected(_on_tts_started):
			_tts.speech_started.disconnect(_on_tts_started)
		if _tts.has_signal("speech_finished") and _tts.speech_finished.is_connected(_on_tts_finished):
			_tts.speech_finished.disconnect(_on_tts_finished)
	_tts_hooked = false


func _on_tts_started(text: String) -> void:
	if _suppress_tts_events > 0:
		return
	var mode: String = String(_current.get("mode", ""))
	if mode == MODE_TTS:
		if String(_current.get("text", "")) == text:
			_mark_started()
		return
	if mode == MODE_RECORDING:
		# Someone handed the device voice a prompt while a recording plays. Never
		# two voices at once: the same words are already being said (stop the
		# duplicate); different words are a prompt the child must hear -- said
		# right after a young reaction, or right now in place of anything else.
		var tts: Node = _tts_service()
		if String(_current.get("text", "")) == text:
			if tts != null and tts.has_method("stop"):
				_suppress_tts_events += 1
				tts.call("stop")
				_suppress_tts_events -= 1
			return
		var age: float = float(Time.get_ticks_msec() - int(_current.get("beganMsec", 0))) / 1000.0
		if bool(_current.get("reaction", false)) and age < REACTION_PROTECT_SECONDS and tts != null:
			_hold_foreign_prompt(tts, text)
			return
		_cut_current()


func _on_tts_finished(text: String) -> void:
	if _suppress_tts_events > 0:
		return
	if String(_current.get("mode", "")) == MODE_TTS:
		if String(_current.get("text", "")) == text:
			_complete(int(_current["serial"]))
			return
		if not bool(_current.get("started", false)):
			# We were waiting on a pending utterance that TtsService dropped
			# (an interrupt cleared its queue). Say it ourselves rather than
			# hang -- a stuck `is_speaking()` would hold the music duck forever.
			var tts: Node = _tts_service()
			if tts != null and tts.has_method("speak") and not _tts_has_text(tts, text_of_current()):
				_speak_via_tts(tts, String(_current["character"]), text_of_current(), false)
		return
	# Someone else's prompt ended; a waiting line may go now.
	_pump()


## Takes the device voice's prompt (and anything queued behind it) off the
## platform and puts it at the FRONT of this queue, so it plays the moment the
## protected reaction ends. The child hears "Yummy!" whole, then the ask.
func _hold_foreign_prompt(tts: Node, text: String) -> void:
	var held: Array = [text]
	if tts.has_method("get_pending_texts"):
		var pending: Variant = tts.call("get_pending_texts")
		if pending is Array:
			for queued: Variant in pending:
				held.append(String(queued))
	if tts.has_method("stop"):
		_suppress_tts_events += 1
		tts.call("stop")
		_suppress_tts_events -= 1
	for index: int in range(held.size() - 1, -1, -1):
		var line: String = String(held[index]).strip_edges()
		if line.is_empty():
			continue
		_queue.push_front({"lineId": "", "character": CHARACTER_ALIZ, "text": line,
				"cut": false, "reaction": false, "held": true})
	while _queue.size() > MAX_QUEUED:
		_queue.pop_back()


func text_of_current() -> String:
	return String(_current.get("text", ""))


static func _tts_has_text(tts: Node, text: String) -> bool:
	if tts.has_method("get_current_text") and String(tts.call("get_current_text")) == text \
			and bool(tts.call("is_speaking")):
		return true
	if tts.has_method("get_pending_texts"):
		var pending: Variant = tts.call("get_pending_texts")
		return pending is Array and (pending as Array).has(text)
	return false


func _set_tts_volume_for(character: String) -> void:
	var tts: Node = _tts_service()
	if tts == null or not tts.has_method("set_voice_volume"):
		return
	tts.call("set_voice_volume", get_character_volume(character))
	_tts_volume_is_bunny = character == CHARACTER_BUNNY


func _restore_tts_volume() -> void:
	if not _tts_volume_is_bunny:
		return
	_tts_volume_is_bunny = false
	_sync_tts_volume()


## The device voice is Aliz's fallback and the narration voice: keep it at her level.
func _sync_tts_volume() -> void:
	var tts: Node = _tts_service()
	if tts == null or not tts.has_method("set_voice_volume"):
		return
	tts.call("set_voice_volume", get_character_volume(CHARACTER_ALIZ))


# -----------------------------------------------------------------------------
# Players, bus, streams, timers
# -----------------------------------------------------------------------------


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(String(BUS_NAME)) >= 0:
		return
	# Created at runtime so no bus layout file has to be hand-written or
	# registered. It sends to Master like every other bus, so the parent's
	# master mute still covers it.
	var index: int = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, String(BUS_NAME))
	AudioServer.set_bus_send(index, &"Master")


func _ensure_player(character: String) -> AudioStreamPlayer:
	var existing: Variant = _players.get(character, null)
	if existing is AudioStreamPlayer and is_instance_valid(existing):
		return existing
	var player := AudioStreamPlayer.new()
	player.name = "%sVoice" % character.capitalize()
	player.bus = BUS_NAME if AudioServer.get_bus_index(String(BUS_NAME)) >= 0 else &"Master"
	player.finished.connect(func() -> void: notify_recording_finished(character))
	add_child(player)
	_players[character] = player
	_apply_player_volume(character)
	return player


func _apply_player_volume(character: String) -> void:
	var player: Variant = _players.get(character, null)
	if not (player is AudioStreamPlayer) or not is_instance_valid(player):
		return
	var linear: float = get_character_volume(character)
	(player as AudioStreamPlayer).volume_db = -80.0 if linear <= 0.0 else linear_to_db(linear)


func _stream_for(line_id: String) -> AudioStream:
	if _stream_resolver.is_valid():
		var resolved: Variant = _stream_resolver.call(line_id)
		return resolved if resolved is AudioStream else null
	if not _manifest.is_recorded(line_id):
		return null
	var resource: Resource = load(_manifest.file_for(line_id))
	return resource as AudioStream


func _schedule(serial: int, seconds: float) -> void:
	var resolve: Callable = func() -> void: _on_recording_timeout(serial)
	if _timer_factory.is_valid():
		_timer_factory.call(seconds, resolve)
		return
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree and is_inside_tree():
		(loop as SceneTree).create_timer(seconds).timeout.connect(resolve)
		return
	# No frame loop to wait in: resolve now so nothing hangs.
	_complete(serial)


func _on_recording_timeout(serial: int) -> void:
	if int(_current.get("serial", -1)) != serial:
		return
	if String(_current.get("mode", "")) != MODE_RECORDING:
		return
	_complete(serial)


# -----------------------------------------------------------------------------
# Persistence
# -----------------------------------------------------------------------------


func _save_service() -> Node:
	if _save != null and is_instance_valid(_save):
		return _save
	_save = null
	if is_inside_tree():
		_save = get_node_or_null(SAVE_SERVICE_PATH)
	else:
		var loop: MainLoop = Engine.get_main_loop()
		if loop is SceneTree and (loop as SceneTree).root != null:
			_save = (loop as SceneTree).root.get_node_or_null(NodePath("SaveService"))
	return _save


func _load_volumes() -> void:
	var save: Node = _save_service()
	for character: String in CHARACTERS:
		_volumes[character] = DEFAULT_VOLUME
	if save == null or not save.has_method("get_setting"):
		for character: String in CHARACTERS:
			_apply_player_volume(character)
		return
	# One-time migration: the old single slider becomes Aliz's level.
	var aliz_key: String = String(VOLUME_SETTING_KEYS[CHARACTER_ALIZ])
	if _read_level(save, aliz_key) < 0.0:
		var legacy: float = _read_level(save, LEGACY_VOLUME_SETTING)
		if legacy >= 0.0 and save.has_method("set_setting"):
			save.call("set_setting", aliz_key, legacy)
	for character: String in CHARACTERS:
		var stored: float = _read_level(save, String(VOLUME_SETTING_KEYS[character]))
		if stored >= 0.0:
			_volumes[character] = stored
		_apply_player_volume(character)
	_sync_tts_volume()


static func _read_level(save: Node, key: String) -> float:
	var value: Variant = save.call("get_setting", key, null)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		var level: float = float(value)
		if is_finite(level):
			return clampf(level, 0.0, 1.0)
	return -1.0
