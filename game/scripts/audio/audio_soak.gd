extends Node
## DEVICE DIAGNOSTIC (debug builds only, `-- --audio-soak`).
##
## The iPad crash of 2026-09-22 died inside the Ogg Vorbis decoder
## (`res2_inverse` -> `vorbis_book_decodevv_add`), which in this build can only
## be the two music tracks: every SFX is WAV and the voice path is the
## platform's own synthesiser. A crash inside a decoder is a lifetime or
## memory problem, and the paths that can cause one are:
##
##   1. a state change that CROSS-FADES two Vorbis playbacks and then drops
##      one while the audio thread is still mixing it,
##   2. the loop wrap at the end of a track (a seek back to `loop_offset`),
##   3. `stop()` / `stream = null` while mixing,
##   4. the same again across a focus-out/focus-in, where Godot's Apple
##      embedded OS stops and starts the audio driver.
##
## This node hammers 1-3 with no touch input, so the device can reproduce in
## minutes what a person would need a long play session to hit. It changes
## nothing in a normal run: without the argument it is never instantiated, and
## it is compiled out of a release build by the same `OS.is_debug_build()`
## check the audio diagnostic uses.
const USER_ARG: String = "--audio-soak"
## `-- --audio-soak --audio-soak-speech` also drives the native speech session
## while the music plays. That is scenario F, and the one combination the
## engine cannot survive by construction: our plugin switches the SHARED
## AVAudioSession to PlayAndRecord/VoiceChat (and back) while Godot's RemoteIO
## output unit is running, and Godot's CoreAudio driver reads the hardware
## format once at init and never observes a route or session change
## (`drivers/coreaudio/audio_driver_coreaudio.mm`: `output_callback` writes
## `frames * ad->channels` samples using the channel count from init).
const USER_ARG_SPEECH: String = "--audio-soak-speech"
## Every step is one of these; the cycle repeats until the app is closed.
const CYCLE: Array[Dictionary] = [
	{"do": "state", "state": "menu", "wait": 1.2},
	{"do": "state", "state": "house", "wait": 0.6},
	{"do": "state", "state": "miniGame", "wait": 0.4},
	{"do": "state", "state": "house", "wait": 0.3},
	{"do": "state", "state": "reward", "wait": 0.3},
	{"do": "state", "state": "menu", "wait": 0.25},
	{"do": "state", "state": "miniGame", "wait": 0.25},
	{"do": "stop", "wait": 0.3},
	{"do": "state", "state": "house", "wait": 0.5},
	{"do": "duck", "on": true, "wait": 0.3},
	{"do": "duck", "on": false, "wait": 0.3},
	{"do": "sfx", "wait": 0.15},
	{"do": "sfx", "wait": 0.15},
	{"do": "sfx", "wait": 0.15},
]

## Added to the cycle by `--audio-soak-speech`.
const SPEECH_CYCLE: Array[Dictionary] = [
	{"do": "voiceProcessing", "on": true, "wait": 0.25},
	{"do": "listen", "wait": 1.0},
	{"do": "state", "state": "miniGame", "wait": 0.4},
	{"do": "stopListening", "wait": 0.4},
	{"do": "state", "state": "house", "wait": 0.4},
	{"do": "listen", "wait": 0.8},
	{"do": "stopListening", "wait": 0.2},
	{"do": "voiceProcessing", "on": false, "wait": 0.5},
	{"do": "state", "state": "menu", "wait": 0.6},
]

static func armed() -> bool:
	return OS.is_debug_build() and OS.get_cmdline_user_args().has(USER_ARG)


static func speech_armed() -> bool:
	return armed() and OS.get_cmdline_user_args().has(USER_ARG_SPEECH)


var _audio: Node = null
var _left: float = 0.0
var _step: int = 0
var _steps_done: int = 0
var _loops: int = 0


func bind(audio: Node) -> void:
	_audio = audio


func _process(delta: float) -> void:
	if _audio == null:
		return
	_left -= delta
	if _left > 0.0:
		return
	var steps: Array = _steps()
	if _step >= steps.size():
		_step = 0
	var row: Dictionary = steps[_step]
	match String(row.get("do", "")):
		"state":
			_audio.call("set_state", String(row["state"]))
		"stop":
			_audio.call("set_state", "silent")
		"duck":
			if _audio.has_method("set_ducked"):
				_audio.call("set_ducked", bool(row.get("on", false)))
		"sfx":
			var sfx: Node = get_node_or_null("/root/Sfx")
			if sfx != null and sfx.has_method("play"):
				sfx.call("play", "tap")
		"voiceProcessing":
			var speech: Node = get_node_or_null("/root/SpeechService")
			if speech != null and speech.has_method("set_voice_processing"):
				speech.call("set_voice_processing", bool(row.get("on", false)))
		"listen":
			var s1: Node = get_node_or_null("/root/SpeechService")
			if s1 != null and s1.has_method("start_listening"):
				s1.call("start_listening", "en-US")
		"stopListening":
			var s2: Node = get_node_or_null("/root/SpeechService")
			if s2 != null and s2.has_method("cancel_listening"):
				s2.call("cancel_listening")
			elif s2 != null and s2.has_method("stop_listening"):
				s2.call("stop_listening")
	_left = float(row.get("wait", 0.5))
	_steps_done += 1
	_step += 1
	if _step >= steps.size():
		_step = 0
		_loops += 1
		print("[audio_soak] loop %d done, %d steps, driver=%s playing=%s"
				% [_loops, _steps_done,
				AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "?",
				str(_audio.call("is_playing_music"))])


func _steps() -> Array:
	return (CYCLE + SPEECH_CYCLE) if speech_armed() else CYCLE


## Progress, so a device run can be read back without a console.
func soak_progress() -> Dictionary:
	return {"loops": _loops, "steps": _steps_done, "speech": speech_armed(),
			"driver": AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "?"}
