extends RefCounted
## Contract tests for `VoiceDirector` (autoload `Voice`).
##
## Defended here:
##   * the queue/interruption rules (Aliz preempts Bunny and clears his queued
##     lines; Bunny never interrupts; same character replaces its queued lines;
##     `interrupt` cuts anything; `stop(character)`);
##   * a recording and the device voice NEVER play at the same time, in every
##     direction (recording waits for a foreign prompt, interrupt stops it, a
##     foreign prompt arriving mid-recording ends the recording, and the same
##     words are never said twice);
##   * the fallback: a missing file speaks the manifest text through TtsService,
##     `line_started` still fires, `is_recorded()` says false;
##   * per-character volume persists under `alizVoiceVolume`/`bunnyVoiceVolume`
##     and the old `voiceVolume` migrates into Aliz's once;
##   * the subtitle strip shows on `line_started` and hides on `line_finished`.
##
## Headless note: there is no frame loop, so both the director and the
## TtsService it falls back to get captured-timer factories; the test fires
## them by hand, and drives "the recording finished" through the public
## `notify_recording_finished()` exactly as `AudioStreamPlayer.finished` would.
## Recordings are in-memory `AudioStreamWAV`s handed in through the stream
## resolver: not one fake file is written anywhere.

const DirectorScript := preload("res://scripts/voice/voice_director.gd")
const TtsServiceScript := preload("res://scripts/speech/tts_service.gd")
const StripScript := preload("res://scripts/voice/subtitle_strip.gd")


## Stand-in for the SaveService autoload with the same duck-typed API.
class FakeSave:
	extends Node
	var settings: Dictionary = {}
	var writes: int = 0

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value
		writes += 1


func test_name() -> String:
	return "voice_director"


func run():
	var failures: Array = []
	failures.append_array(_test_unknown_ids_and_fallback())
	failures.append_array(_test_aliz_preempts_bunny())
	failures.append_array(_test_bunny_never_interrupts_aliz())
	failures.append_array(_test_same_character_replaces_queued())
	failures.append_array(_test_interrupt_and_stop())
	failures.append_array(_test_sequence_keeps_order())
	failures.append_array(_test_recording_waits_for_a_foreign_prompt())
	failures.append_array(_test_interrupt_stops_the_device_voice_before_a_recording())
	failures.append_array(_test_foreign_prompt_ends_a_recording())
	failures.append_array(_test_same_words_are_not_said_twice())
	failures.append_array(_test_volume_persistence_and_migration())
	failures.append_array(_test_no_tts_at_all_still_moves())
	failures.append_array(_test_subtitle_strip())
	failures.append_array(_test_autoload_shape())
	return failures


# -- Harness --------------------------------------------------------------------


## Director + real TtsService (captured timers) + fake save + optional in-memory
## recordings for `recorded_ids`.
func _make(recorded_ids: Array = [], settings: Dictionary = {}) -> Dictionary:
	var tts = TtsServiceScript.new()
	var tts_timers: Array = []
	tts.set_timer_factory(func(_d: float, cb: Callable) -> void: tts_timers.append(cb))

	var save := FakeSave.new()
	save.settings = settings.duplicate()

	var director = DirectorScript.new()
	var timers: Array = []
	var started: Array = []
	var finished: Array = []
	director.set_timer_factory(func(_d: float, cb: Callable) -> void: timers.append(cb))
	director.set_tts(tts)
	director.set_save_service(save)
	var streams: Dictionary = {}
	for line_id: String in recorded_ids:
		streams[line_id] = _silent_stream(0.5)
	director.set_stream_resolver(func(line_id: String) -> AudioStream: return streams.get(line_id, null))
	director.line_started.connect(func(line_id: String, character: String, text: String) -> void:
		started.append({"lineId": line_id, "character": character, "text": text}))
	director.line_finished.connect(func(line_id: String) -> void: finished.append(line_id))

	var root: Node = _root()
	if root != null:
		root.add_child(tts)
		root.add_child(save)
		root.add_child(director)
	director.build()  # `_ready()` does not fire in the headless runner
	return {
		"director": director, "tts": tts, "save": save,
		"timers": timers, "tts_timers": tts_timers,
		"started": started, "finished": finished, "streams": streams,
	}


func _teardown(h: Dictionary) -> void:
	for key: String in ["director", "tts", "save"]:
		var node: Node = h[key]
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


## Fires TtsService's newest safety timer: "the platform finished the utterance".
func _finish_tts(h: Dictionary) -> bool:
	var timers: Array = h["tts_timers"]
	if timers.is_empty():
		return false
	var cb: Callable = timers.pop_back()
	cb.call()
	return true


func _started_ids(h: Dictionary) -> Array:
	var ids: Array = []
	for entry: Dictionary in h["started"]:
		ids.append(String(entry["lineId"]))
	return ids


static func _silent_stream(seconds: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(int(44100.0 * seconds) * 2)
	wav.data = bytes
	return wav


func _root() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


# -- Cases ----------------------------------------------------------------------


func _test_unknown_ids_and_fallback():
	var failures: Array = []
	var h: Dictionary = _make()
	var director = h["director"]
	var tts = h["tts"]

	if director.say("aliz_999_nope"):
		failures.append("an id the manifest does not know must be refused")
	if director.is_speaking():
		failures.append("a refused id must not leave the director speaking")

	if not director.say("bunny_003_yummy"):
		failures.append("a manifest id must be accepted")
	if director.is_recorded("bunny_003_yummy"):
		failures.append("no recording exists for bunny_003_yummy; is_recorded() must say so")
	if director.is_playing_recording():
		failures.append("the fallback must never claim to be a recording")
	if not director.is_speaking() or director.current_line() != "bunny_003_yummy":
		failures.append("the fallback line should be current: %s" % director.current_line())
	if String(tts.get_current_text()) != "Yummy!":
		failures.append("the fallback must hand TtsService the manifest text, got '%s'" % tts.get_current_text())
	if _started_ids(h) != ["bunny_003_yummy"]:
		failures.append("line_started must fire for a fallback line (the subtitle): %s" % str(_started_ids(h)))
	if String((h["started"][0] as Dictionary)["text"]) != "Yummy!" \
			or String((h["started"][0] as Dictionary)["character"]) != "bunny":
		failures.append("line_started carries the character and the English text")
	_finish_tts(h)
	if director.is_speaking():
		failures.append("finishing the TTS utterance must finish the line")
	if h["finished"] != ["bunny_003_yummy"]:
		failures.append("line_finished after the fallback: %s" % str(h["finished"]))
	_teardown(h)
	return failures


func _test_aliz_preempts_bunny():
	var failures: Array = []
	var h: Dictionary = _make()
	var director = h["director"]
	var tts = h["tts"]

	director.say("bunny_003_yummy")
	director.say("bunny_004_more")  # queued behind his own line
	if director.pending_line_ids() != ["bunny_004_more"]:
		failures.append("Bunny's second line should queue: %s" % str(director.pending_line_ids()))
	director.say("aliz_006_good_job")
	if director.current_line() != "aliz_006_good_job":
		failures.append("Aliz must preempt a Bunny reaction, current is %s" % director.current_line())
	if not director.pending_line_ids().is_empty():
		failures.append("Aliz must clear queued Bunny lines: %s" % str(director.pending_line_ids()))
	if h["finished"] != ["bunny_003_yummy"]:
		failures.append("the cut Bunny line must report finished: %s" % str(h["finished"]))
	if String(tts.get_current_text()) != "Great job!":
		failures.append("the device voice should now be on Aliz's line, got '%s'" % tts.get_current_text())
	# A second Aliz line behind a playing Aliz line queues, replacing queued Aliz.
	director.say("aliz_020_all_done")
	director.say("aliz_021_star")
	if director.current_line() != "aliz_006_good_job":
		failures.append("Aliz does not cut herself: %s" % director.current_line())
	if director.pending_line_ids() != ["aliz_021_star"]:
		failures.append("a new Aliz line replaces her queued line: %s" % str(director.pending_line_ids()))
	_teardown(h)
	return failures


func _test_bunny_never_interrupts_aliz():
	var failures: Array = []
	var h: Dictionary = _make()
	var director = h["director"]

	director.say("aliz_014_milk_time")
	director.say("bunny_003_yummy")
	if director.current_line() != "aliz_014_milk_time":
		failures.append("a Bunny reaction must not cut Aliz: %s" % director.current_line())
	if director.pending_line_ids() != ["bunny_003_yummy"]:
		failures.append("Bunny should wait behind Aliz: %s" % str(director.pending_line_ids()))
	_finish_tts(h)
	if director.current_line() != "bunny_003_yummy":
		failures.append("Bunny should follow once Aliz is done: %s" % director.current_line())
	if _started_ids(h) != ["aliz_014_milk_time", "bunny_003_yummy"]:
		failures.append("start order: %s" % str(_started_ids(h)))
	_teardown(h)
	return failures


func _test_same_character_replaces_queued():
	var failures: Array = []
	var h: Dictionary = _make()
	var director = h["director"]

	director.say("aliz_014_milk_time")
	director.say("bunny_003_yummy")
	director.say("bunny_004_more")
	director.say("bunny_005_thank_you")
	if director.pending_line_ids() != ["bunny_005_thank_you"]:
		failures.append("only Bunny's newest line should be queued: %s" % str(director.pending_line_ids()))
	# `queue: true` obeys the same rule, and never cuts.
	director.say("bunny_011_happy", {"queue": true})
	if director.pending_line_ids() != ["bunny_011_happy"] or director.current_line() != "aliz_014_milk_time":
		failures.append("queue:true replaces the same character's queued line and cuts nothing: %s / %s"
				% [str(director.pending_line_ids()), director.current_line()])
	_teardown(h)
	return failures


func _test_interrupt_and_stop():
	var failures: Array = []
	var h: Dictionary = _make()
	var director = h["director"]
	var tts = h["tts"]

	director.say("aliz_014_milk_time")
	director.say("bunny_003_yummy")
	director.say("bunny_012_upset", {"interrupt": true})
	if director.current_line() != "bunny_012_upset":
		failures.append("interrupt:true must cut anything, even Aliz: %s" % director.current_line())
	if not director.pending_line_ids().is_empty():
		failures.append("interrupt:true clears the queue: %s" % str(director.pending_line_ids()))
	if String(tts.get_current_text()) != "Hmph!":
		failures.append("the device voice should be on the interrupting line, got '%s'" % tts.get_current_text())

	director.say("aliz_006_good_job")  # preempts bunny
	director.say("bunny_003_yummy")
	director.say("aliz_020_all_done")
	# stop(bunny): drops his queued line, leaves Aliz alone.
	director.stop("bunny")
	if director.current_line() != "aliz_006_good_job" or director.pending_line_ids() != ["aliz_020_all_done"]:
		failures.append("stop(bunny) must only touch Bunny: %s / %s"
				% [director.current_line(), str(director.pending_line_ids())])
	director.stop("aliz")
	if director.is_speaking() or not director.pending_line_ids().is_empty():
		failures.append("stop(aliz) must cut her line and drop her queue")
	if tts.is_speaking():
		failures.append("stopping the fallback line must stop the device voice")
	director.say("bunny_003_yummy")
	director.stop()
	if director.is_speaking() or tts.is_speaking():
		failures.append("stop() must silence everything")
	_teardown(h)
	return failures


func _test_sequence_keeps_order():
	var failures: Array = []
	var h: Dictionary = _make()
	var director = h["director"]
	var accepted: int = director.say_all(["aliz_001_welcome", "aliz_002_lets_play"])
	if accepted != 2:
		failures.append("say_all should accept both lines, accepted %d" % accepted)
	if director.current_line() != "aliz_001_welcome" or director.pending_line_ids() != ["aliz_002_lets_play"]:
		failures.append("a two-line sequence plays in order: %s / %s"
				% [director.current_line(), str(director.pending_line_ids())])
	_finish_tts(h)
	if director.current_line() != "aliz_002_lets_play":
		failures.append("the second line of the sequence should follow: %s" % director.current_line())
	_teardown(h)
	return failures


## The device voice is busy with a prompt that is not ours: a recording waits.
func _test_recording_waits_for_a_foreign_prompt():
	var failures: Array = []
	var h: Dictionary = _make(["aliz_011_apple"])
	var director = h["director"]
	var tts = h["tts"]

	tts.speak("Walk to the kitchen.")
	if not tts.is_speaking():
		return ["harness: TtsService did not start the foreign prompt"]
	director.say("aliz_011_apple")
	if director.is_playing_recording():
		failures.append("a recording must not start over a prompt the child is still hearing")
	if not tts.is_speaking() or String(tts.get_current_text()) != "Walk to the kitchen.":
		failures.append("the foreign prompt must not be cut by a default-priority line")
	if director.pending_line_ids() != ["aliz_011_apple"]:
		failures.append("the recording should be waiting: %s" % str(director.pending_line_ids()))
	_finish_tts(h)
	if not director.is_playing_recording() or director.current_line() != "aliz_011_apple":
		failures.append("once the prompt ends the recording plays: %s" % director.current_line())
	if tts.is_speaking():
		failures.append("recording and device voice at the same time (after the wait)")
	if not director.is_recorded("aliz_011_apple"):
		failures.append("is_recorded() must be true when a stream resolves")
	var player: AudioStreamPlayer = director.get_player("aliz")
	if player == null or player.stream == null:
		failures.append("the recording should be on Aliz's own player")
	elif String(player.bus) != "Voice":
		failures.append("recordings play on the Voice bus, got %s" % String(player.bus))
	# Finishing the recording releases the queue.
	director.notify_recording_finished("aliz")
	if director.is_speaking():
		failures.append("notify_recording_finished must end the line")
	if h["finished"] != ["aliz_011_apple"]:
		failures.append("line_finished for the recording: %s" % str(h["finished"]))
	_teardown(h)
	return failures


func _test_interrupt_stops_the_device_voice_before_a_recording():
	var failures: Array = []
	var h: Dictionary = _make(["bunny_012_upset"])
	var director = h["director"]
	var tts = h["tts"]

	tts.speak("Give the baby some milk.")
	director.say("bunny_012_upset", {"interrupt": true})
	if tts.is_speaking():
		failures.append("interrupt:true must stop the device voice before the recording starts")
	if not director.is_playing_recording():
		failures.append("the recording should be playing now")
	# Bunny's fallback line while a recording is queued behind it: the safety
	# timer path also releases the line.
	var timers: Array = h["timers"]
	if timers.is_empty():
		failures.append("a recording must arm a safety timer")
	else:
		(timers.pop_back() as Callable).call()
		if director.is_speaking():
			failures.append("the safety timer must release a recording that never reported finished")
	_teardown(h)
	return failures


## Someone hands TtsService a different prompt while a recording plays: the
## recording yields, because the prompt is what the child must hear.
func _test_foreign_prompt_ends_a_recording():
	var failures: Array = []
	var h: Dictionary = _make(["bunny_003_yummy"])
	var director = h["director"]
	var tts = h["tts"]

	director.say("bunny_003_yummy")
	if not director.is_playing_recording():
		return ["harness: the recording did not start"]
	tts.speak("Find the baby bottle.")
	if director.is_speaking():
		failures.append("a recording must yield to a foreign prompt: never two voices at once")
	if not tts.is_speaking():
		failures.append("the foreign prompt must keep playing")
	if h["finished"] != ["bunny_003_yummy"]:
		failures.append("the yielded recording must report finished: %s" % str(h["finished"]))
	_teardown(h)
	return failures


## The same line reaches both paths (a mode handler's own `speak()` and the
## cue): it is said once.
func _test_same_words_are_not_said_twice():
	var failures: Array = []
	var h: Dictionary = _make()
	var director = h["director"]
	var tts = h["tts"]

	# Fallback: TtsService is already saying the exact text -> adopt it.
	tts.speak("Let's make some milk!")
	director.say("aliz_014_milk_time")
	if tts.get_pending_count() != 0:
		failures.append("the same text must not be queued a second time behind itself")
	if _started_ids(h) != ["aliz_014_milk_time"]:
		failures.append("an adopted utterance still raises line_started: %s" % str(_started_ids(h)))
	_finish_tts(h)
	if director.is_speaking() or h["finished"] != ["aliz_014_milk_time"]:
		failures.append("the adopted utterance's end must finish the line")
	_teardown(h)

	# Recording: the device voice starts the same words mid-recording -> the
	# duplicate is stopped and the recording carries on.
	var h2: Dictionary = _make(["aliz_014_milk_time"])
	var director2 = h2["director"]
	var tts2 = h2["tts"]
	director2.say("aliz_014_milk_time")
	tts2.speak("Let's make some milk!")
	if tts2.is_speaking():
		failures.append("the device voice must not repeat a line a recording is already saying")
	if not director2.is_playing_recording():
		failures.append("the recording carries on when the duplicate is stopped")
	_teardown(h2)
	return failures


func _test_volume_persistence_and_migration():
	var failures: Array = []
	var h: Dictionary = _make([], {"voiceVolume": 0.4})
	var director = h["director"]
	var save: FakeSave = h["save"]
	var tts = h["tts"]

	if not is_equal_approx(float(save.settings.get("alizVoiceVolume", -1.0)), 0.4):
		failures.append("the old voiceVolume must migrate into alizVoiceVolume: %s" % str(save.settings))
	if not is_equal_approx(director.get_character_volume("aliz"), 0.4):
		failures.append("Aliz's level should come from the migrated value, got %.2f" % director.get_character_volume("aliz"))
	if not is_equal_approx(director.get_character_volume("bunny"), DirectorScript.DEFAULT_VOLUME):
		failures.append("Bunny defaults when nothing is stored, got %.2f" % director.get_character_volume("bunny"))
	if not is_equal_approx(tts.get_voice_volume(), 0.4):
		failures.append("the device voice follows Aliz's level, got %.2f" % tts.get_voice_volume())

	director.set_character_volume("bunny", 0.3)
	if not is_equal_approx(float(save.settings.get("bunnyVoiceVolume", -1.0)), 0.3):
		failures.append("bunnyVoiceVolume must persist: %s" % str(save.settings))
	var player: AudioStreamPlayer = director.get_player("bunny")
	if player == null or not is_equal_approx(player.volume_db, linear_to_db(0.3)):
		failures.append("Bunny's player must take the level at once")
	director.set_character_volume("aliz", 1.7)
	if not is_equal_approx(director.get_character_volume("aliz"), 1.0):
		failures.append("levels clamp to 0..1")
	director.set_character_volume("aliz", 0.0)
	var aliz_player: AudioStreamPlayer = director.get_player("aliz")
	if aliz_player == null or aliz_player.volume_db > -79.0:
		failures.append("zero must be silent, not -inf dB")
	director.set_character_volume("nobody", 0.5)
	if save.settings.has("nobodyVoiceVolume"):
		failures.append("an unknown character must not be persisted")

	# A Bunny fallback line speaks at Bunny's level, then the device voice
	# returns to Aliz's.
	director.set_character_volume("aliz", 0.9)
	director.say("bunny_003_yummy")
	if not is_equal_approx(tts.get_voice_volume(), 0.3):
		failures.append("Bunny's fallback should speak at his level, got %.2f" % tts.get_voice_volume())
	_finish_tts(h)
	if not is_equal_approx(tts.get_voice_volume(), 0.9):
		failures.append("after Bunny the device voice returns to Aliz's level, got %.2f" % tts.get_voice_volume())

	if DirectorScript.volume_setting_key("aliz") != "alizVoiceVolume" \
			or DirectorScript.volume_setting_key("bunny") != "bunnyVoiceVolume":
		failures.append("the settings keys are part of the API for the settings screen")

	# A second boot with both keys stored does not migrate again.
	_teardown(h)
	var h2: Dictionary = _make([], {"voiceVolume": 0.1, "alizVoiceVolume": 0.6, "bunnyVoiceVolume": 0.2})
	var director2 = h2["director"]
	if not is_equal_approx(director2.get_character_volume("aliz"), 0.6):
		failures.append("an existing alizVoiceVolume must win over the legacy key, got %.2f" % director2.get_character_volume("aliz"))
	if (h2["save"] as FakeSave).writes != 0:
		failures.append("no migration write when the new key already exists")
	_teardown(h2)
	return failures


func _test_no_tts_at_all_still_moves():
	var failures: Array = []
	var director = DirectorScript.new()
	var started: Array = []
	var finished: Array = []
	director.line_started.connect(func(line_id: String, _c: String, _t: String) -> void: started.append(line_id))
	director.line_finished.connect(func(line_id: String) -> void: finished.append(line_id))
	director.set_tts(null)
	director.set_save_service(null)
	# Not in the tree, no TtsService anywhere: `say()` must resolve, not hang.
	director.say("aliz_021_star")
	if director.is_speaking():
		failures.append("with no device voice the line must resolve at once (silence, not a hang)")
	if started != ["aliz_021_star"] or finished != ["aliz_021_star"]:
		failures.append("started/finished still pair up with no voice: %s / %s" % [str(started), str(finished)])
	director.free()
	return failures


func _test_subtitle_strip():
	var failures: Array = []
	var h: Dictionary = _make()
	var director = h["director"]
	var strip: Control = StripScript.new()
	strip.call("build")
	strip.call("bind_voice", director)
	if bool(strip.call("is_showing")):
		failures.append("the strip must be hidden with nothing playing")
	director.say("bunny_001_hungry")
	if not bool(strip.call("is_showing")):
		failures.append("the strip shows on line_started")
	if String(strip.call("get_text")) != "I'm hungry, Aliz!":
		failures.append("the strip shows the line's English: '%s'" % strip.call("get_text"))
	director.say("aliz_014_milk_time")  # preempts
	if String(strip.call("get_text")) != "Let's make some milk!":
		failures.append("the strip follows the newest line: '%s'" % strip.call("get_text"))
	# The older line's finish (emitted by the preempt) must not hide the new one.
	if not bool(strip.call("is_showing")):
		failures.append("an older line finishing must not hide the current subtitle")
	_finish_tts(h)
	if bool(strip.call("is_showing")):
		failures.append("the strip hides on line_finished (no linger outside the tree)")
	# Layout: a static rect for keep-out tests, above the mount's button row.
	var rect: Rect2 = StripScript.rect_for(Vector2(1334.0, 750.0), 150.0)
	if rect.end.y > 750.0 - 150.0 + 0.01:
		failures.append("the pill must sit above the bottom margin: %s" % str(rect))
	if rect.size.x > StripScript.MAX_WIDTH + 0.01:
		failures.append("the pill is capped at MAX_WIDTH")
	if absf(rect.get_center().x - 667.0) > 0.5:
		failures.append("the pill is centred: %s" % str(rect))
	strip.call("set_bottom_margin", 200.0)
	if not is_equal_approx(float(strip.call("get_bottom_margin")), 200.0):
		failures.append("set_bottom_margin must stick")
	# Mounting while a line is already playing shows it at once.
	director.say("aliz_021_star")
	var late: Control = StripScript.new()
	late.call("build")
	late.call("bind_voice", director)
	if not bool(late.call("is_showing")) or String(late.call("get_text")) != "You earned a star!":
		failures.append("a strip mounted mid-line shows the current line")
	late.free()
	strip.free()
	_teardown(h)
	return failures


## The lead registers `Voice`; until then callers use `/root/Voice` with null
## guards. Pin the surface those callers and Agent S rely on.
func _test_autoload_shape():
	var failures: Array = []
	var director = DirectorScript.new()
	for method: String in ["say", "say_all", "stop", "is_speaking", "current_line", "is_recorded",
			"set_character_volume", "get_character_volume", "presence_summary"]:
		if not director.has_method(method):
			failures.append("VoiceDirector lacks %s()" % method)
	for signal_name: String in ["line_started", "line_finished", "character_volume_changed"]:
		if not director.has_signal(signal_name):
			failures.append("VoiceDirector lacks signal %s" % signal_name)
	if not (director is Node):
		failures.append("VoiceDirector must be a Node to be an autoload")
	director.free()
	var patch: String = "res://../docs/patches/agentV_project_godot.diff"
	if not FileAccess.file_exists(patch):
		failures.append("docs/patches/agentV_project_godot.diff (the Voice autoload line for the lead) is missing")
	elif not FileAccess.get_file_as_string(patch).contains('Voice="*res://scripts/voice/voice_director.gd"'):
		failures.append("the project.godot patch must register Voice at res://scripts/voice/voice_director.gd")
	return failures
