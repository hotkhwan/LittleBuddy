extends SceneTree
## Offline hands-free demo, headless, on this Mac:
##   godot --headless --path game --script res://tests/demo_tutor_voice_session.gd            # simulated child audio (owner dialogue)
##   godot --headless --path game --script res://tests/demo_tutor_voice_session.gd -- --mock  # real SpeechService (desktop mock recogniser)
##   ... -- --voice   route lines through Voice/TtsService instead of the paced clock
##                    (headless has no platform voice and no frame loop, so those lines end at
##                    once and nothing can be interrupted; the default keeps reading-speed pacing)
##
## Runs the real autoloads (Voice -> TtsService: headless has no platform voice,
## so lines are paced), the scripted provider, the on-device recognition
## provider and the VAD. Prints every state change, every Aliz line and the
## barge-in timing. No network, no microphone.

const SessionScript := preload("res://scripts/tutor/voice/tutor_voice_session.gd")
const LessonEngineScript := preload("res://scripts/tutor/lesson/lesson_engine.gd")
const RecognitionScript := preload("res://scripts/tutor/providers/on_device_recognition_provider.gd")
const SynthScript := preload("res://scripts/tutor/providers/voice_pack_synthesis_provider.gd")

const STEP: float = 0.02
## Simulated-audio mode runs at this multiple of real time (its clocks are all
## simulated); the mock-recogniser mode runs in real time because the desktop
## mock answers on SceneTree timers.
const SIM_SPEED: float = 5.0

var _session: RefCounted = null
var _synth: Node = null
var _mock_recognizer: bool = false
var _clock: Array = [0.0]
var _script: Array = ["I want to learn about animals!", "It's a cat!", "Meow!", "a dog"]
var _interrupt_done: bool = false
var _next_line: int = 0
var _idle_for: float = 0.0


func _initialize() -> void:
	var mock_recognizer: bool = OS.get_cmdline_user_args().has("--mock")
	_mock_recognizer = mock_recognizer
	var voice: Node = root.get_node_or_null("Voice")
	if voice != null and voice.has_method("build"):
		voice.call("build")
	var speech: Node = root.get_node_or_null("SpeechService")
	if speech != null and String(speech.call("get_backend_name")) == "unavailable" and speech.has_method("_select_backend"):
		speech.call("_select_backend")  # autoload _ready() does not run under --script
	var engine: RefCounted = LessonEngineScript.new()
	var recognition: RefCounted = RecognitionScript.new()
	var synth: Node = SynthScript.new()
	# Not in the tree: the session advances it on its own (possibly scaled) clock.
	var session: RefCounted = SessionScript.new()
	session.set_engine(engine)
	session.set_recognition_provider(recognition)
	session.set_synthesis_provider(synth)
	if not OS.get_cmdline_user_args().has("--voice"):
		synth.set_muted(true)  # paced route: reading-speed durations, interruptible
	var clock: Array = _clock
	_session = session
	_synth = synth
	session.state_changed.connect(func(f: String, to: String) -> void: print("  %6.2fs  state %s -> %s" % [clock[0], f, to]))
	session.aliz_started.connect(func(turn: Dictionary) -> void: print("  %6.2fs  Aliz: %s   [%s/%s route=%s]" % [clock[0], turn.get("speech", ""), turn.get("emotion", ""), turn.get("lessonAction", ""), synth.voice_used()]))
	session.child_speech_started.connect(func() -> void: print("  %6.2fs  child speech started (level %.2f)" % [clock[0], session.get_input_level()]))
	session.child_speech_ended.connect(func(text: String) -> void: print("  %6.2fs  child said: \"%s\"" % [clock[0], text]))
	session.barge_in.connect(func() -> void: print("  %6.2fs  BARGE-IN %s" % [clock[0], str(session.last_barge_in_timing())]))
	session.capture_changed.connect(func(c: bool) -> void: print("  %6.2fs  capture %s" % [clock[0], "ON" if c else "off"]))
	session.session_ended.connect(func(r: String) -> void: print("  %6.2fs  session ended: %s" % [clock[0], r]))
	var entry: String = String(LessonEngineScript.entry_lesson_id())
	print("hands-free demo (%s) lesson=%s speech backend=%s voice=%s" % ["real SpeechService mock recogniser" if mock_recognizer else "simulated child audio", entry,
		str(root.get_node_or_null("SpeechService").call("get_backend_name")) if root.get_node_or_null("SpeechService") != null else "none",
		"Voice autoload" if voice != null else "none"])
	if not mock_recognizer:
		session.set_level_source(func() -> float: return 0.02)
	session.start(entry, {"gatePassed": true, "simulation": not mock_recognizer})
	var script: Array = ["I want to learn about animals!", "It's a cat!", "Meow!", "a dog"]
	var interrupt_done: bool = false
	var next_line: int = 0
	var idle_for: float = 0.0
	# Driven from _process(): SceneTree timers (the desktop mock recogniser,
	# TtsService fallbacks) only tick between frames.


func _process(delta: float) -> bool:
	var session: RefCounted = _session
	var t: float = _clock[0]
	if not session.is_active() or t > 60.0:
		if session.is_active():
			session.stop("demo_over")
		print("states: %s" % " -> ".join(PackedStringArray(session.state_history())))
		print("barge-ins: %d  reprompts: %d  vad bursts ignored: %d" % [session.barge_in_count(), session.reprompt_count(), session.vad().bursts_ignored()])
		return true
	var step: float = delta if _mock_recognizer else delta * SIM_SPEED
	session.advance(step)
	t += step
	_clock[0] = t
	if _mock_recognizer:
		if t > 20.0:
			session.stop("demo_over")
		return false
	if session.get_state() == "listening":
		_idle_for += step
		if _idle_for > 0.6 and _next_line < _script.size():
			_idle_for = 0.0
			var line: String = _script[_next_line]
			_next_line += 1
			print("  %6.2fs  [sim] child audio clip 'answer' + transcript \"%s\"" % [t, line])
			session.simulate_child_audio(SessionScript.preset_clip("answer"), line)
		elif _idle_for > 0.6 and _next_line == _script.size() and _interrupt_done:
			_idle_for = 0.0
			_next_line += 1
			print("  %6.2fs  [sim] child audio clip 'answer' + transcript \"stop\"" % t)
			session.simulate_child_audio(SessionScript.preset_clip("answer"), "stop")
	elif session.get_state() == "aliz_speaking" and _next_line == _script.size() and not _interrupt_done:
		_interrupt_done = true
		print("  %6.2fs  [sim] child audio clip 'interrupt' + transcript \"Wait! I want the cat!\" while Aliz speaks" % t)
		session.simulate_child_audio(SessionScript.preset_clip("interrupt"), "Wait! I want the cat!")
	else:
		_idle_for = 0.0
	return false
