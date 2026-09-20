extends RefCounted

## TutorVoiceSession -- the HANDS-FREE conversation state machine
## (`docs/ALIZ_TUTOR_CONTRACTS.md`, addendum 2026-09-20 evening).
##
##   idle -> welcoming -> listening -> child_speaking -> thinking -> aliz_speaking
##                            ^                                          |
##                            +------------- (interrupted) <-------------+  barge-in
##                        ... -> closing -> ended
##
## The child never presses a microphone button. Entering Learn with Aliz
## (after the parental gate: `opts.gatePassed` is REQUIRED) starts the session;
## Aliz welcomes; the VAD (`vad.gd`) hears speech start and end; the on-device
## recogniser turns it into text; the conversation provider (or a realtime
## transport) answers; Aliz speaks; the child may interrupt.
##
## ## Microphone scope (hard rules, `test_tutor_voice_session.gd`)
##
##   * `is_capturing()` is true ONLY while the session is active, not muted,
##     not suspended, and in a state that listens (listening, child_speaking,
##     aliz_speaking for barge-in, interrupted). Idle, thinking, closing, ended:
##     never. Level polling and the recogniser both stop with it.
##   * `on_app_background()` stops capture and streaming and ENDS the session
##     (reason `background`); `on_app_foreground()` reopens nothing -- the
##     child re-enters Tutor Mode. `stop()`, quota expiry and `mute(true)` stop
##     capture at once.
##   * The recogniser is only ever opened through `OnDeviceRecognitionProvider`
##     (-> `SpeechService`); this file has no audio primitive.
##
## ## Level sources (what the VAD listens to)
##
##   1. `set_level_source(Callable)` -- a 0..1 input level per frame (the native
##      plugin's input meter via the patched `SpeechService`, or a transport's
##      server events). Full hands-free with barge-in.
##   2. No level source (this Mac today): RECOGNISER-DRIVEN mode -- the
##      recogniser is re-armed after every turn while Aliz is silent, its
##      partials mark `child_speaking`, its final ends the turn, its timeout is
##      the long pause. Honest limitation: no barge-in, because the mic cannot
##      be open while Aliz speaks without a level to gate the echo.
##   3. `simulate_child_audio(frames, transcript)` -- the dev "simulated child
##      audio" panel and the tests: synthetic level frames through the SAME
##      VAD path, the transcript delivered through the recogniser's simulated
##      path (refused on a mobile build).
##
## ## Barge-in
##
## `speech_started` while Aliz speaks (echo-gated: level above the playback
## estimate + margin for 200 ms) -> `synth.cancel()` (Voice.stop), transport
## `cancel()`, `set_speaking(false)`, `set_expression("listening")` + `tilt`,
## queued turns flushed, then the new utterance is captured and submitted as
## `PHASE_INTERJECTION` (the engine's `handle_interjection`). Timings are
## measured in `last_barge_in_timing()` (ms to Voice.stop, ms to mouth 0).
## Cancelled audio is never replayed: the synth utterance is finished, the
## transport's remaining deltas dropped.
##
## Everything spoken passed through `tutor_turn.gd`; the LessonEngine alone
## owns progression (`advance` / `switch_lesson` are called here, at a turn
## boundary, from the validated turn's `lessonAction`).

signal state_changed(from_state: String, to_state: String)
signal child_speech_started()
signal child_speech_ended(transcript: String)
signal partial_transcript(text: String)
signal aliz_started(turn: Dictionary)
signal aliz_finished(turn: Dictionary)
signal barge_in()
signal session_ended(reason: String)
signal capture_changed(capturing: bool)
signal turn_applied(turn: Dictionary, action: String)
signal reprompted(count: int)
## Capture-only: the child stayed quiet for a long while; the owner of the lesson loop decides.
signal long_pause()

const VadScript := preload("res://scripts/tutor/voice/vad.gd")
const ConversationProviderScript := preload("res://scripts/tutor/providers/conversation_provider.gd")
const ScriptedProviderScript := preload("res://scripts/tutor/providers/scripted_conversation_provider.gd")
const RecognitionScript := preload("res://scripts/tutor/providers/on_device_recognition_provider.gd")
const SynthScript := preload("res://scripts/tutor/providers/voice_pack_synthesis_provider.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")

const STATE_IDLE: String = "idle"
const STATE_WELCOMING: String = "welcoming"
const STATE_LISTENING: String = "listening"
const STATE_CHILD_SPEAKING: String = "child_speaking"
const STATE_THINKING: String = "thinking"
const STATE_ALIZ_SPEAKING: String = "aliz_speaking"
const STATE_INTERRUPTED: String = "interrupted"
const STATE_CLOSING: String = "closing"
const STATE_ENDED: String = "ended"
const CAPTURING_STATES: Array[String] = [STATE_LISTENING, STATE_CHILD_SPEAKING, STATE_ALIZ_SPEAKING, STATE_INTERRUPTED]

const REASON_GATE: String = "gate_required"
const REASON_BACKGROUND: String = "background"
const REASON_QUOTA: String = "quota_expired"
const REASON_COMPLETE: String = "lesson_complete"
const REASON_CHILD: String = "child_asked"
const REASON_UNAVAILABLE: String = "recognition_unavailable"
const REASON_STOPPED: String = "stopped"

## "stop" / "I'm done" / "bye" said as a plain answer ends the session politely
## (the engine's own list when it has one; this is the fallback).
const STOP_PHRASES_FALLBACK: Array[String] = ["stop", "i'm done", "im done", "i am done", "all done", "bye", "bye bye", "goodbye", "finished", "no more"]
const GOODBYE_LINE: String = "Okay! Great job today! Bye bye!"

## Aliz's loudspeaker level assumed while she speaks and nothing measures it
## (device TTS with no bus to read): conservative, so the echo gate is strict.
const PLAYBACK_ASSUMED_LEVEL: float = 0.5
## A provider that has not answered by then gets the scripted fallback.
const THINKING_TIMEOUT_SECONDS: float = 9.0
## Re-prompts on a long pause before Aliz says the word with the child.
const MAX_REPROMPTS_PER_STEP: int = 2

var _engine: Object = null
var _provider: RefCounted = null
var _recognition: RefCounted = null
var _synth: Node = null
var _transport: RefCounted = null
var _face: Object = null
var _save: Object = null
var _vad: RefCounted = null
var _level_source: Callable = Callable()

var _state: String = STATE_IDLE
var _active: bool = false
var _muted: bool = false
var _lesson_id: String = ""
var _locale: String = "en-US"
var _hands_free: bool = true
var _current_turn: Dictionary = {}
var _current_phase: String = ""
var _pending_phase: String = ""
var _queued_turns: Array = []
var _interrupting: bool = false
var _thinking_seconds: float = 0.0
var _reprompts: int = 0
var _level: float = 0.0
var _playback_level: float = 0.0
var _history: Array = []
var _barge_timing: Dictionary = {}
var _barge_count: int = 0
var _sim_frames: Array = []
var _sim_transcript: String = ""
var _sim_active: bool = false
var _last_capturing: bool = false
var _reprompt_total: int = 0
var _transport_ready: bool = false
var _streaming: bool = false
var _wired: bool = false
## CAPTURE-ONLY mode: the classroom scene owns the lesson loop (engine,
## provider, synthesis, HUD, quota) and uses this session for what it is best
## at -- the microphone, VAD, the echo gate and barge-in. In this mode the
## session never speaks and never evaluates: it emits child_speech_started /
## partial_transcript / child_speech_ended(transcript) / barge_in, and the scene
## tells it when Aliz is speaking with `set_aliz_speaking()`. Started with
## `start(id, {captureOnly: true, gatePassed: true})`.
var _capture_only: bool = false
var _forced_unavailable: bool = false


# -- Wiring ---------------------------------------------------------------------

func set_engine(engine: Object) -> void:
	_engine = engine


func set_conversation_provider(provider: RefCounted) -> void:
	_provider = provider


func set_recognition_provider(provider: RefCounted) -> void:
	_recognition = provider


func set_synthesis_provider(synth: Node) -> void:
	_synth = synth


func set_transport(transport: RefCounted) -> void:
	_transport = transport


func set_face(face: Object) -> void:
	_face = face


func set_save_service(save: Object) -> void:
	_save = save


func set_level_source(source: Callable) -> void:
	_level_source = source


## -- The classroom scene's session contract (capture-only mode) --------------------------

## Aliz is speaking (true) or has stopped (false). While she speaks the VAD is
## gated against her own playback and the recogniser is closed; when she stops
## the session listens again. In lesson-driven mode the session already knows.
func set_aliz_speaking(active: bool) -> void:
	if not _active or not _capture_only:
		return
	if active:
		_interrupting = false
		if _recognition != null:
			_recognition.cancel("playback_started")
		vad().set_gated(true)
		vad().prime_playback_level(PLAYBACK_ASSUMED_LEVEL)
		vad().set_last_partial("")
		_set_state(STATE_ALIZ_SPEAKING)
		_update_capture()
	else:
		vad().set_gated(false)
		if _state == STATE_ALIZ_SPEAKING or _state == STATE_INTERRUPTED:
			_listen()


## Barge-in is real only when the session drives the microphone hands-free.
func supports_barge_in() -> bool:
	return _hands_free and not _forced_unavailable


func hands_free_available() -> bool:
	if _forced_unavailable:
		return false
	return _recognizer_usable()


## Real on-device recognition, or the simulated path where a desktop allows it.
func _recognizer_usable() -> bool:
	if _recognition == null:
		return false
	if bool(_recognition.call("is_available")):
		return true
	return _recognition.has_method("is_simulation_enabled") and bool(_recognition.call("is_simulation_enabled"))


## A test/dev seam: pretend the recogniser is gone (permission denied). Ends a
## live session honestly so the scene falls back to tap-to-talk and cards.
func force_unavailable(forced: bool) -> void:
	_forced_unavailable = forced
	if forced and _active:
		stop(REASON_UNAVAILABLE)


func enable_simulation(enabled: bool) -> void:
	if _recognition != null and _recognition.has_method("set_simulation_enabled"):
		_recognition.call("set_simulation_enabled", enabled and RecognitionScript.simulation_allowed())


## Kept for the scene's contract; the capture-only session does not evaluate.
func set_expected_answer(_answer: String) -> void:
	pass


func is_capture_only() -> bool:
	return _capture_only


## True while a simulated child-audio clip is still being fed to the VAD (tests
## and the dev panel wait for it before feeding the next one).
func is_simulating() -> bool:
	return _sim_active


func vad() -> RefCounted:
	if _vad == null:
		_vad = VadScript.new()
	return _vad


func engine() -> Object:
	return _engine


func recognition() -> RefCounted:
	return _recognition


func provider() -> RefCounted:
	return _provider


# -- Queries ----------------------------------------------------------------------

func get_state() -> String:
	return _state


func is_active() -> bool:
	return _active


func is_muted() -> bool:
	return _muted


func is_capturing() -> bool:
	return _active and not _muted and CAPTURING_STATES.has(_state)


## 0..1 for the mic indicator; 0 whenever nothing is captured.
func get_input_level() -> float:
	return _level if is_capturing() else 0.0


func current_turn() -> Dictionary:
	return _current_turn.duplicate(true)


func state_history() -> Array:
	return _history.duplicate()


func last_barge_in_timing() -> Dictionary:
	return _barge_timing.duplicate()


func barge_in_count() -> int:
	return _barge_count


func reprompt_count() -> int:
	return _reprompt_total


func has_level_source() -> bool:
	return _level_source.is_valid() or _sim_active


func is_recognizer_driven() -> bool:
	return not has_level_source()


# -- Lifecycle ----------------------------------------------------------------------

## `opts`: gatePassed (REQUIRED true), handsFree (default true), locale,
## simulation (enable the recogniser's simulated path; desktop only), welcome
## (default true: speak the current step at once).
func start(lesson_id: String, opts: Dictionary = {}) -> bool:
	if _active:
		return false
	if not bool(opts.get("gatePassed", false)):
		session_ended.emit(REASON_GATE)
		return false
	_ensure_components()
	_capture_only = bool(opts.get("captureOnly", false))
	if _capture_only:
		# Simulation first: on a desktop with no recogniser the simulated child
		# audio IS the recogniser (tests, the dev panel); on a device it is
		# refused by the provider and real availability decides.
		if bool(opts.get("simulation", false)) and _recognition.has_method("set_simulation_enabled"):
			_recognition.call("set_simulation_enabled", true)
		if _forced_unavailable or _recognition == null or not _recognizer_usable():
			session_ended.emit(REASON_UNAVAILABLE)
			return false
		_lesson_id = lesson_id
		_locale = String(opts.get("locale", "en-US"))
		_hands_free = bool(opts.get("handsFree", true))
		_history.clear()
		_queued_turns.clear()
		_barge_count = 0
		_interrupting = false
		_muted = false
		_active = true
		if bool(opts.get("simulation", false)) and _recognition.has_method("set_simulation_enabled"):
			_recognition.call("set_simulation_enabled", true)
		_wire()
		_listen()
		return true
	if _engine == null or not _engine.has_method("current_step"):
		session_ended.emit("no_lesson_engine")
		return false
	if not bool(_engine.call("has_lesson")) or String(_engine.call("lesson_id")) != lesson_id:
		if not bool(_engine.call("load_lesson", lesson_id)):
			session_ended.emit("lesson_missing")
			return false
	_lesson_id = lesson_id
	_locale = String(opts.get("locale", "en-US"))
	_hands_free = bool(opts.get("handsFree", true))
	_history.clear()
	_queued_turns.clear()
	_reprompts = 0
	_reprompt_total = 0
	_barge_count = 0
	_interrupting = false
	_muted = false
	_active = true
	if bool(opts.get("simulation", false)) and _recognition.has_method("set_simulation_enabled"):
		_recognition.call("set_simulation_enabled", true)
	_wire()
	_provider.begin_session(lesson_id)
	if _transport != null:
		_transport_ready = false
		_transport.connect_session({"lessonId": lesson_id})
	_set_state(STATE_WELCOMING)
	if bool(opts.get("welcome", true)):
		_open_step()
	return true


func stop(reason: String = REASON_STOPPED) -> void:
	if not _active:
		return
	_set_state(STATE_CLOSING)
	_active = false
	_streaming = false
	_sim_active = false
	_sim_frames.clear()
	if _recognition != null:
		_recognition.set_continuous(false)
		_recognition.cancel()
	if _synth != null and is_instance_valid(_synth):
		_synth.cancel()
	if _transport != null:
		_transport.close()
	if _provider != null:
		_provider.end_session()
	if _engine != null and _save != null and _engine.has_method("save_progress"):
		_engine.call("save_progress", _save)
	_face_speaking(false)
	_face_call("set_listening_pose", false)
	vad().set_gated(false)
	_level = 0.0
	_set_state(STATE_ENDED)
	_update_capture()
	session_ended.emit(reason)


## Silences the microphone path entirely; Aliz may still finish speaking.
func mute(muted: bool) -> void:
	if muted == _muted:
		return
	_muted = muted
	if muted:
		if _recognition != null:
			_recognition.cancel()
		_sim_active = false
		_sim_frames.clear()
		vad().reset()
		_level = 0.0
		if _state == STATE_CHILD_SPEAKING:
			_set_state(STATE_LISTENING)
	elif _state == STATE_LISTENING:
		_arm_recognizer_if_driven()
	_update_capture()


func on_app_background() -> void:
	if _active:
		stop(REASON_BACKGROUND)


## Deliberately nothing: capture never resumes on its own.
func on_app_foreground() -> void:
	pass


func on_quota_expired() -> void:
	if _active:
		stop(REASON_QUOTA)


# -- Simulation (dev panel + tests) ------------------------------------------------------

## Feeds `frames` ([[level, ms], ...]) through the VAD as if the mic heard
## them; when the VAD ends the utterance the `transcript` (if any) arrives
## through the recogniser's simulated path. Refused unless the recogniser's
## simulation is allowed (never on a mobile build).
func simulate_child_audio(frames: Array, transcript: String = "") -> bool:
	if not _active or _recognition == null or not RecognitionScript.simulation_allowed():
		return false
	if not bool(_recognition.call("set_simulation_enabled", true)):
		return false
	_sim_frames = frames.duplicate(true)
	_sim_transcript = transcript
	_sim_active = true
	return true


## Ready-made clips for the panel: answer, cough, pause_then_finish, silence,
## interrupt (a louder, longer utterance that beats the echo gate).
static func preset_clip(name: String) -> Array:
	match name:
		"answer":
			return [[0.02, 200], [0.35, 700], [0.02, 1200]]
		"cough":
			return [[0.02, 200], [0.6, 80], [0.02, 1200]]
		"pause_then_finish":
			return [[0.02, 100], [0.35, 450], [0.02, 700], [0.35, 500], [0.02, 1200]]
		"silence":
			return [[0.02, 3500]]
		"interrupt":
			return [[0.9, 900], [0.02, 1200]]
	return []


# -- The frame ----------------------------------------------------------------------------

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	if _synth != null and is_instance_valid(_synth) and not _synth.is_inside_tree():
		_synth.advance(delta)
	if _recognition != null:
		_recognition.advance(delta)
	if _transport != null:
		_transport.advance(delta)
	if _provider != null and _provider.has_method("advance"):
		_provider.call("advance", delta)
	if not _active:
		return
	var ms: float = delta * 1000.0
	if _state == STATE_THINKING and not _capture_only:
		_thinking_seconds += delta
		if _thinking_seconds >= THINKING_TIMEOUT_SECONDS:
			_thinking_seconds = 0.0
			_speak(TurnValidator.fallback_turn(), _current_phase)
	if is_capturing() and has_level_source():
		var level_now: float = _next_level(ms)
		_level = level_now
		if _state == STATE_ALIZ_SPEAKING:
			vad().update_playback_level(_playback_level_now(), ms)
		for event: Variant in vad().feed(level_now, ms):
			_on_vad_event(String(event))
	elif not is_capturing():
		_level = 0.0
	_update_capture()


func _next_level(ms: float) -> float:
	if _sim_active:
		if _sim_frames.is_empty():
			if vad().is_speech():
				return 0.0  # the clip's tail is silence until the VAD closes the utterance
			# The clip is over. A transcript nobody spoke is dropped with it.
			_sim_active = false
			_sim_transcript = ""
			return 0.0
		var frame: Array = _sim_frames[0]
		var level_value: float = float(frame[0])
		frame[1] = float(frame[1]) - ms
		if float(frame[1]) <= 0.0:
			_sim_frames.pop_front()
		return level_value
	if _level_source.is_valid():
		return clampf(float(_level_source.call()), 0.0, 1.0)
	return 0.0


func _playback_level_now() -> float:
	if _playback_level > 0.0:
		var value: float = _playback_level
		_playback_level *= 0.7
		return value
	if _face != null and _face.has_method("get_lip_sync"):
		var lip: Variant = _face.call("get_lip_sync")
		if lip != null and (lip as Object).has_method("level"):
			return clampf(float((lip as Object).call("level")), 0.0, 1.0)
	if _synth != null and is_instance_valid(_synth) and _synth.is_speaking():
		return PLAYBACK_ASSUMED_LEVEL
	return 0.0


# -- VAD ------------------------------------------------------------------------------------

func _on_vad_event(event: String) -> void:
	match event:
		VadScript.EVENT_SPEECH_STARTED:
			if _state == STATE_LISTENING:
				_set_state(STATE_CHILD_SPEAKING)
				child_speech_started.emit()
				_recognition.begin_listening(_locale)
			elif _state == STATE_ALIZ_SPEAKING and _hands_free:
				_do_barge_in()
		VadScript.EVENT_SPEECH_ENDED:
			if _state == STATE_CHILD_SPEAKING:
				if _sim_active or not _sim_transcript.is_empty():
					var text: String = _sim_transcript
					_sim_transcript = ""
					if not text.is_empty():
						_recognition.call("simulated_transcript", text)
						return
					if _recognition.has_method("simulated_silence"):
						_recognition.call("simulated_silence")
						return
				_recognition.stop_listening()
		VadScript.EVENT_LONG_PAUSE:
			if _state == STATE_LISTENING:
				_reprompt()


## The child said nothing for a long while: ask again (local, never a reply
## from a model); after `MAX_REPROMPTS_PER_STEP`, say it together and move on.
func _reprompt() -> void:
	_reprompts += 1
	_reprompt_total += 1
	reprompted.emit(_reprompts)
	if _capture_only or _engine == null:
		# No lesson here: the scene re-asks (or moves on) and the mic stays open.
		long_pause.emit()
		return
	if _reprompts > MAX_REPROMPTS_PER_STEP:
		_request_turn("", ConversationProviderScript.PHASE_TOGETHER)
		return
	_request_turn("", ConversationProviderScript.PHASE_OPEN)


# -- Recognition ----------------------------------------------------------------------------

func _on_partial(text: String) -> void:
	vad().set_last_partial(text)
	partial_transcript.emit(text)
	if _state == STATE_LISTENING and is_recognizer_driven():
		_set_state(STATE_CHILD_SPEAKING)
		child_speech_started.emit()


func _on_final(text: String) -> void:
	if not _active or not (_state == STATE_CHILD_SPEAKING or _state == STATE_LISTENING or _state == STATE_INTERRUPTED):
		return
	child_speech_ended.emit(text)
	if _capture_only:
		_pending_phase = ""
		if _state == STATE_CHILD_SPEAKING or _state == STATE_INTERRUPTED:
			_listen()
		return
	var phase: String = _pending_phase if not _pending_phase.is_empty() else ConversationProviderScript.PHASE_ANSWER
	_pending_phase = ""
	if phase == ConversationProviderScript.PHASE_ANSWER and is_stop_phrase(text):
		_current_phase = phase
		_speak(TurnValidator.make(_goodbye_line(), "happy", "wave", "end_session"), phase)
		return
	_request_turn(text, phase)


func _on_recognition_ended(terminal: String) -> void:
	if not _active:
		return
	match terminal:
		"final":
			return
		"unavailable":
			if _state == STATE_CHILD_SPEAKING or _state == STATE_LISTENING:
				stop(REASON_UNAVAILABLE)
		_:
			if _capture_only:
				if _state == STATE_CHILD_SPEAKING:
					child_speech_ended.emit("")
					_listen()
				return
			if _state == STATE_CHILD_SPEAKING:
				# Heard something, decoded nothing: an unclear attempt, gently.
				_pending_phase = ""
				_request_turn("", ConversationProviderScript.PHASE_TIMEOUT)
			elif _state == STATE_LISTENING and is_recognizer_driven():
				_reprompt()


func _arm_recognizer_if_driven() -> void:
	if is_recognizer_driven() and _state == STATE_LISTENING and not _muted and _active:
		_recognition.begin_listening(_locale)


# -- Turns ------------------------------------------------------------------------------------

func _open_step() -> void:
	var step: Dictionary = _engine.call("current_step")
	if step.is_empty() or bool(_engine.call("is_complete")):
		stop(REASON_COMPLETE)
		return
	_reprompts = 0
	_request_turn("", ConversationProviderScript.PHASE_OPEN)


func _request_turn(transcript: String, phase: String) -> void:
	_current_phase = phase
	if phase != ConversationProviderScript.PHASE_OPEN and phase != ConversationProviderScript.PHASE_TOGETHER:
		_set_state(STATE_THINKING)
		_thinking_seconds = 0.0
		_face_call("set_expression", "thinking")
		_face_call("play_gesture", "nod")
	var use_transport: bool = _transport != null and _transport_ready and _transport.is_connected_session() \
			and (phase == ConversationProviderScript.PHASE_ANSWER or phase == ConversationProviderScript.PHASE_INTERJECTION)
	if use_transport:
		var context: Dictionary = {"phase": phase}
		if _transport.has_method("needs_lesson_context") and bool(_transport.call("needs_lesson_context")):
			var step: Dictionary = _engine.call("current_step")
			var verdict: Dictionary = _engine.call("evaluate", transcript)
			context = ConversationProviderScript.lesson_context_for(step, verdict)
			context["phase"] = phase
		if _transport.send_text(transcript, context):
			return
	_provider.submit_turn(transcript, {"phase": phase, "lessonId": _lesson_id, "step": _engine.call("current_step")})


func _on_turn_ready(raw_turn: Dictionary) -> void:
	if not _active:
		return
	var turn: Dictionary = TurnValidator.coerce(raw_turn)
	if _synth.is_speaking():
		_queued_turns.append(turn)  # spoken after the current line, or flushed by a barge-in
		return
	_speak(turn, _current_phase)


func _on_provider_failed(reason: String) -> void:
	if not _active:
		return
	push_warning("tutor voice session: provider failed (%s); scripted fallback" % reason)
	if _provider.provider_name() != "scripted":
		var scripted: RefCounted = ScriptedProviderScript.new()
		scripted.set_engine(_engine)
		_swap_provider(scripted)
		_provider.begin_session(_lesson_id)
	if _state == STATE_THINKING:
		_speak(TurnValidator.fallback_turn(), _current_phase)


func _speak(turn: Dictionary, phase: String) -> void:
	_current_turn = turn
	_current_phase = phase
	_interrupting = false
	var step: Dictionary = _engine.call("current_step")
	if _recognition != null:
		_recognition.cancel("playback_started")
	_face_call("set_expression", String(turn.get("emotion", "neutral")))
	if String(turn.get("gesture", "none")) != "none":
		_face_call("play_gesture", String(turn["gesture"]))
	_face_call("set_listening_pose", false)
	_face_speaking(true)
	vad().set_gated(true)
	vad().prime_playback_level(PLAYBACK_ASSUMED_LEVEL)
	vad().set_last_partial("")
	if _state != STATE_WELCOMING:
		_set_state(STATE_ALIZ_SPEAKING)
	_update_capture()
	aliz_started.emit(turn)
	var line_id: String = String(step.get("spokenLineId", "")) if phase == ConversationProviderScript.PHASE_OPEN else ""
	if not _synth.speak_turn(turn, line_id):
		_on_synth_finished("")


func _on_synth_finished(_text: String) -> void:
	if not _active:
		return
	_face_speaking(false)
	vad().set_gated(false)
	if _interrupting:
		return  # the barge-in already moved us on
	if _state != STATE_ALIZ_SPEAKING and _state != STATE_WELCOMING:
		return
	var spoken: Dictionary = _current_turn
	aliz_finished.emit(spoken)
	if not _queued_turns.is_empty():
		_speak(_queued_turns.pop_front(), _current_phase)
		return
	_after_turn(spoken)


func _after_turn(turn: Dictionary) -> void:
	var action: String = String(turn.get("lessonAction", "retry"))
	var step: Dictionary = _engine.call("current_step")
	var kind: String = String(step.get("kind", ""))
	turn_applied.emit(turn, action)
	if _current_phase == ConversationProviderScript.PHASE_OPEN:
		if ConversationProviderScript.QUESTION_KINDS.has(kind):
			_listen()
		else:
			_engine.call("advance")
			_open_step()
		return
	match action:
		"next_question", "complete":
			_engine.call("advance")
			_open_step()
		"switch_lesson":
			var target: String = String(turn.get("nextLessonId", ""))
			if not target.is_empty() and _engine.has_method("switch_lesson") and bool(_engine.call("switch_lesson", target, _save)):
				_lesson_id = target
				_provider.begin_session(target)
				_open_step()
			else:
				_listen()
		"jump_step":
			_open_step()
		"end_session":
			stop(REASON_CHILD)
		_:
			_listen()


func _listen() -> void:
	_set_state(STATE_LISTENING)
	_face_call("set_expression", "listening")
	_face_call("set_listening_pose", true)
	vad().set_gated(false)
	vad().reset_pause_clock()
	_update_capture()
	_arm_recognizer_if_driven()


## A realtime transport streams its reply while it is still being generated:
## Aliz is speaking from the first delta (mouth from the envelope, subtitle
## growing), and a barge-in now cancels the TRANSPORT. The validated turn at
## `response_done` is then voiced (the mock has no audio bytes; the on-device
## voice says the words). A reply cancelled mid-stream is never voiced.
func _on_transport_delta(_text: String) -> void:
	if not _active or _streaming or _state != STATE_THINKING:
		return
	_streaming = true
	_interrupting = false
	if _recognition != null:
		_recognition.cancel("playback_started")
	_face_call("set_expression", "happy")
	_face_call("set_listening_pose", false)
	_face_speaking(true)
	vad().set_gated(true)
	vad().prime_playback_level(PLAYBACK_ASSUMED_LEVEL)
	_set_state(STATE_ALIZ_SPEAKING)
	_update_capture()


func _on_transport_done(raw_turn: Dictionary) -> void:
	_streaming = false
	_on_turn_ready(raw_turn)


# -- Barge-in --------------------------------------------------------------------------------

func _do_barge_in() -> void:
	var t0: int = Time.get_ticks_usec()
	_interrupting = true
	_barge_count += 1
	_set_state(STATE_INTERRUPTED)
	_queued_turns.clear()
	_streaming = false
	if _transport != null:
		_transport.cancel()
	if _synth != null and is_instance_valid(_synth):
		_synth.cancel()  # -> Voice.stop() / TtsService.stop() inside the provider
	var t_voice: int = Time.get_ticks_usec()
	_face_speaking(false)
	var t_mouth: int = Time.get_ticks_usec()
	_face_call("set_expression", "listening")
	_face_call("play_gesture", "tilt")
	_face_call("set_listening_pose", true)
	vad().set_gated(false)
	_barge_timing = {
		"toVoiceStopMs": float(t_voice - t0) / 1000.0,
		"toMouthZeroMs": float(t_mouth - t0) / 1000.0,
	}
	barge_in.emit()
	_pending_phase = ConversationProviderScript.PHASE_INTERJECTION
	_set_state(STATE_CHILD_SPEAKING)
	child_speech_started.emit()
	_recognition.begin_listening(_locale)
	_update_capture()


## Letters-only, whole-phrase match against the engine's STOP_PHRASES (or the
## fallback list): "Stop!" and "I'm done." end the session; "stop sign" does not.
func is_stop_phrase(text: String) -> bool:
	var normalised: String = _letters_and_spaces(text)
	if normalised.is_empty():
		return false
	for phrase: Variant in _stop_phrases():
		if _letters_and_spaces(String(phrase)) == normalised:
			return true
	return false


func _stop_phrases() -> Array:
	if _engine != null:
		var script: Variant = _engine.get_script()
		if script is GDScript:
			var constants: Dictionary = (script as GDScript).get_script_constant_map()
			if constants.has("STOP_PHRASES") and typeof(constants["STOP_PHRASES"]) == TYPE_ARRAY:
				return constants["STOP_PHRASES"]
	return STOP_PHRASES_FALLBACK


func _goodbye_line() -> String:
	if _engine != null:
		var script: Variant = _engine.get_script()
		if script is GDScript:
			var constants: Dictionary = (script as GDScript).get_script_constant_map()
			if constants.has("END_SESSION_LINE"):
				return String(constants["END_SESSION_LINE"])
	return GOODBYE_LINE


static func _letters_and_spaces(text: String) -> String:
	var out: String = ""
	var lower: String = text.to_lower()
	for i: int in range(lower.length()):
		var code: int = lower.unicode_at(i)
		if (code >= 0x61 and code <= 0x7A) or code == 0x27:
			out += lower[i]
		elif code == 0x20 and not out.ends_with(" "):
			out += " "
	return out.strip_edges()


# -- Internals ---------------------------------------------------------------------------------

func _ensure_components() -> void:
	if _provider == null:
		_provider = ScriptedProviderScript.new()
	if _provider.has_method("set_engine") and _provider.engine() == null:
		_provider.set_engine(_engine)
	if _recognition == null:
		_recognition = RecognitionScript.new()
	if _synth == null:
		_synth = SynthScript.new()
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			tree.root.add_child(_synth)
	vad()


func _wire() -> void:
	if _wired:
		return
	_wired = true
	_provider.turn_ready.connect(_on_turn_ready)
	_provider.provider_failed.connect(_on_provider_failed)
	_recognition.partial.connect(_on_partial)
	_recognition.final.connect(_on_final)
	_recognition.session_ended.connect(_on_recognition_ended)
	_recognition.bind_synthesis(_synth)
	_synth.finished.connect(_on_synth_finished)
	if _transport != null:
		_transport.connected.connect(func(_info: Dictionary) -> void: _transport_ready = true)
		_transport.response_done.connect(_on_transport_done)
		_transport.response_text_delta.connect(_on_transport_delta)
		_transport.response_audio_delta.connect(func(level_value: float, _bytes: int) -> void: _playback_level = level_value)
		_transport.error.connect(func(code: String, _message: String) -> void:
			_transport_ready = false
			if _state == STATE_THINKING or _streaming:
				_streaming = false
				_on_provider_failed("transport:%s" % code))
		_transport.closed.connect(func(_reason: String) -> void: _transport_ready = false)


func _swap_provider(new_provider: RefCounted) -> void:
	if _provider != null:
		if _provider.turn_ready.is_connected(_on_turn_ready):
			_provider.turn_ready.disconnect(_on_turn_ready)
		if _provider.provider_failed.is_connected(_on_provider_failed):
			_provider.provider_failed.disconnect(_on_provider_failed)
	_provider = new_provider
	_provider.turn_ready.connect(_on_turn_ready)
	_provider.provider_failed.connect(_on_provider_failed)


func _set_state(next: String) -> void:
	if next == _state:
		return
	var previous: String = _state
	_state = next
	_history.append(next)
	state_changed.emit(previous, next)
	_update_capture()


func _update_capture() -> void:
	var now_capturing: bool = is_capturing()
	if now_capturing != _last_capturing:
		_last_capturing = now_capturing
		if not now_capturing and _recognition != null and _recognition.has_active_session() \
				and _state != STATE_THINKING:
			_recognition.cancel()
		capture_changed.emit(now_capturing)


func _face_call(method: String, arg: Variant) -> void:
	if _face != null and _face.has_method(method):
		_face.call(method, arg)


func _face_speaking(active: bool) -> void:
	_face_call("set_speaking", active)
