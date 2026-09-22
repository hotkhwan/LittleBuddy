extends RefCounted

## Aliz Tutor Mode -- the speech pipeline providers (Agent E).
##
##   * recognition state machine over the REAL SpeechService with a scripted
##     backend: success, timeout with/without a partial (the caps), unavailable,
##     cancel drops a late final, echo prevention (playback `started` cancels a
##     live session; `begin_listening()` while speaking is refused), the
##     simulated path and its mobile guard, hands-free re-arm;
##   * scripted provider: every turn valid, reproducible across two engines,
##     varied across a lesson, one evaluate() per answer;
##   * backend provider: refuses with the flag off (no request ever built),
##     then -- against a LOCAL DEV_MODE server spawned from this test when node
##     is on this machine, else a printed skip -- session / correct turn /
##     incorrect turn / end, and each error mapping: not_approved,
##     quota_exhausted, rate_limited, session_ended, not_found,
##     provider_unavailable (closed port), timeout (a socket that never
##     answers), invalid turn from the server -> scripted fallback; exactly one
##     `turn_ready` per `submit_turn` in every case;
##   * synthesis provider: recording vs device voice vs paced, `started`
##     before sound, `finished` once, lip-sync player / TTS forwarding, cancel;
##   * the turn UX state machine drives a stub face through every state.
##
## Evidence prints (state sequences, the DEV_MODE round trip) go to stdout.

const RecognitionScript := preload("res://scripts/tutor/providers/on_device_recognition_provider.gd")
const RecognitionBase := preload("res://scripts/tutor/providers/speech_recognition_provider.gd")
const ScriptedScript := preload("res://scripts/tutor/providers/scripted_conversation_provider.gd")
const BackendScript := preload("res://scripts/tutor/providers/backend_conversation_provider.gd")
const SynthScript := preload("res://scripts/tutor/providers/voice_pack_synthesis_provider.gd")
const BackendSynthScript := preload("res://scripts/tutor/providers/backend_synthesis_provider.gd")
const UxScript := preload("res://scripts/tutor/tutor_turn_ux.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const LessonEngineScript := preload("res://scripts/tutor/lesson/lesson_engine.gd")
const ServiceScript := preload("res://scripts/speech/speech_service.gd")
const DirectorScript := preload("res://scripts/voice/voice_director.gd")
const TtsServiceScript := preload("res://scripts/speech/tts_service.gd")

const LESSON_ID: String = "english_colors_fruits"
const NODE_CANDIDATES: Array[String] = ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"]
const SERVER_READY_SECONDS: float = 12.0
const ROUND_TRIP_SECONDS: float = 6.0


## A recogniser the test plays like a piano (same as test_speech_end_states).
class ScriptedBackend:
	extends SpeechBackend
	var available: bool = true
	var starts: int = 0
	var stops: int = 0
	var hypothesis_on_stop: String = ""
	var announces_stop: bool = true

	func is_available() -> bool:
		return available

	func has_permission() -> bool:
		return available

	func start_listening(_locale: String = "en-US") -> void:
		starts += 1
		listening_started.emit()

	func stop_listening() -> void:
		stops += 1
		if announces_stop:
			listening_stopped.emit()
		if not hypothesis_on_stop.is_empty():
			var text: String = hypothesis_on_stop
			hypothesis_on_stop = ""
			recognized.emit(text)

	func is_listening() -> bool:
		return true

	func get_backend_name() -> String:
		return "scripted"


## Something that speaks: `started` + `is_speaking()`.
class FakeSynth:
	extends RefCounted
	signal started(text: String)
	signal finished(text: String)
	var speaking: bool = false

	func speak(text: String) -> void:
		speaking = true
		started.emit(text)

	func stop() -> void:
		speaking = false
		finished.emit("")

	func is_speaking() -> bool:
		return speaking


## A stub of Agent C's face that records every call.
class FakeFace:
	extends RefCounted
	var calls: Array = []
	func set_expression(name: String) -> bool:
		calls.append("expression:%s" % name)
		return true
	func play_gesture(name: String) -> float:
		calls.append("gesture:%s" % name)
		return 0.5
	func set_speaking(active: bool) -> void:
		calls.append("speaking:%s" % str(active))
	func set_listening_pose(active: bool) -> void:
		calls.append("pose:%s" % str(active))


## Tallies a recognition provider's signals.
class RecTally:
	extends RefCounted
	var states: Array = []
	var partials: Array = []
	var finals: Array = []
	var failures: Array = []
	var ended: Array = []
	var refused: Array = []

	func attach(provider: RefCounted) -> void:
		provider.state_changed.connect(func(_from: String, to: String) -> void: states.append(to))
		provider.partial.connect(func(text: String) -> void: partials.append(text))
		provider.final.connect(func(text: String) -> void: finals.append(text))
		provider.failed.connect(func(reason: String) -> void: failures.append(reason))
		provider.session_ended.connect(func(terminal: String) -> void: ended.append(terminal))
		provider.refused.connect(func(reason: String) -> void: refused.append(reason))

	func terminals() -> int:
		return finals.size() + failures.size()


## Tallies a conversation provider's signals.
class ConvTally:
	extends RefCounted
	var sessions: Array = []
	var turns: Array = []
	var failures: Array = []
	var fallbacks: Array = []
	var metas: Array = []

	func attach(provider: RefCounted) -> void:
		provider.session_ready.connect(func(session: Dictionary) -> void: sessions.append(session))
		provider.turn_ready.connect(func(turn: Dictionary) -> void: turns.append(turn))
		provider.provider_failed.connect(func(reason: String) -> void: failures.append(reason))
		if provider.has_signal("fallback_used"):
			provider.fallback_used.connect(func(reason: String) -> void: fallbacks.append(reason))
		if provider.has_signal("turn_meta"):
			provider.turn_meta.connect(func(meta: Dictionary) -> void: metas.append(meta))


var _servers: Array = []
var _node_path: String = ""


func test_name() -> String:
	return "tutor_providers"


func run():
	var failures: Array = []
	failures.append_array(_test_recognition_success())
	failures.append_array(_test_recognition_timeout_paths())
	failures.append_array(_test_recognition_unavailable())
	failures.append_array(_test_recognition_cancel_drops_late_final())
	failures.append_array(_test_recognition_echo_prevention())
	failures.append_array(_test_recognition_simulation_and_guard())
	failures.append_array(_test_recognition_continuous_rearm())
	failures.append_array(_test_scripted_turns_valid_and_deterministic())
	failures.append_array(_test_scripted_variety())
	failures.append_array(_test_scripted_addendum_dialogue())
	failures.append_array(_test_backend_refuses_when_flag_off())
	failures.append_array(_test_backend_url_parsing_and_error_codes())
	failures.append_array(_test_backend_live_round_trip())
	failures.append_array(_test_backend_timeout_and_unreachable())
	failures.append_array(_test_synthesis_routes())
	failures.append_array(_test_synthesis_forwards_platform_voice())
	failures.append_array(_test_backend_synthesis_is_a_stub())
	failures.append_array(_test_turn_ux_states())
	_stop_servers()
	return failures


# ---------------------------------------------------------------------------
# Recognition
# ---------------------------------------------------------------------------

func _recognition(backend: SpeechBackend) -> Dictionary:
	var service: Node = ServiceScript.new()
	service.call("_set_backend", backend, "scripted")
	var provider: RefCounted = RecognitionScript.new()
	provider.set_speech_service(service)
	var tally := RecTally.new()
	tally.attach(provider)
	return {"service": service, "provider": provider, "tally": tally, "backend": backend}


func _free_recognition(h: Dictionary) -> void:
	(h["service"] as Node).free()


func _tick(h: Dictionary, seconds: float, step: float = 0.1) -> void:
	var left: float = seconds
	while left > 0.0:
		var d: float = minf(step, left)
		(h["service"] as Node).call("advance", d)
		(h["provider"] as RefCounted).call("advance", d)
		left -= d


func _check_one_ending(failures: Array, h: Dictionary, label: String, terminal: String) -> void:
	var tally: RecTally = h["tally"]
	if tally.terminals() != 1:
		failures.append("%s: %d terminal signal(s) (finals %s, failures %s); exactly one is the rule"
				% [label, tally.terminals(), str(tally.finals), str(tally.failures)])
	if tally.ended != [terminal]:
		failures.append("%s: session_ended %s, expected [%s]" % [label, str(tally.ended), terminal])
	var provider: RefCounted = h["provider"]
	if bool(provider.call("is_listening")) or bool(provider.call("has_active_session")):
		failures.append("%s: provider still listening after the ending" % label)
	# The service's own session may outlive ours by its cap (a manual stop with
	# nothing to hand over); run it out and prove nothing leaks back in.
	var finals_before: int = tally.finals.size()
	_tick(h, 8.0)  # past the service's 6 s after-partial cap + grace
	if bool((h["service"] as Node).call("is_listening")):
		failures.append("%s: SpeechService still listening after the ending" % label)
	if tally.finals.size() != finals_before or tally.terminals() != 1:
		failures.append("%s: a late service result leaked into a closed session" % label)
	print("    recognition[%s] states: %s" % [label, " -> ".join(PackedStringArray(provider.call("state_history")))])


func _test_recognition_success():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	var h: Dictionary = _recognition(backend)
	var provider: RefCounted = h["provider"]
	var tally: RecTally = h["tally"]
	if provider.state() != RecognitionBase.STATE_IDLE:
		failures.append("a new provider is idle, got %s" % provider.state())
	if backend.starts != 0:
		failures.append("the mic must not open on construction")
	if not provider.begin_listening():
		failures.append("begin_listening should open a session")
	if backend.starts != 1:
		failures.append("begin_listening must open the mic exactly once, got %d" % backend.starts)
	backend.partial_recognized.emit("app")
	backend.partial_recognized.emit("apple")
	_tick(h, 0.5)
	backend.recognized.emit("apple")
	_check_one_ending(failures, h, "success", RecognitionBase.STATE_FINAL)
	if tally.finals != ["apple"]:
		failures.append("final should carry the transcript, got %s" % str(tally.finals))
	if tally.partials != ["app", "apple"]:
		failures.append("partials pass through, got %s" % str(tally.partials))
	var expected: Array = ["start", "listening", "partial", "final"]
	if provider.state_history() != expected:
		failures.append("success path states %s, expected %s" % [str(provider.state_history()), str(expected)])
	# A second session starts clean.
	provider.begin_listening()
	if provider.state() != RecognitionBase.STATE_LISTENING or provider.state_history() != ["start", "listening"]:
		failures.append("a second session must start from a clean history: %s" % str(provider.state_history()))
	provider.cancel()
	_free_recognition(h)
	return failures


func _test_recognition_timeout_paths():
	var failures: Array = []
	# No partial at all: 4 s cap -> processing -> retry/timeout.
	var backend := ScriptedBackend.new()
	var h: Dictionary = _recognition(backend)
	var provider: RefCounted = h["provider"]
	provider.begin_listening()
	_tick(h, 3.9)
	if provider.state() != RecognitionBase.STATE_LISTENING:
		failures.append("before the cap the session is still listening, got %s" % provider.state())
	_tick(h, 2.0)
	_check_one_ending(failures, h, "timeout-no-partial", RecognitionBase.STATE_RETRY)
	if (h["tally"] as RecTally).failures != ["timeout"]:
		failures.append("silence ends as retry/timeout, got %s" % str((h["tally"] as RecTally).failures))
	if not provider.state_history().has("processing"):
		failures.append("the cap passes through processing (waiting for the hypothesis): %s" % str(provider.state_history()))
	if backend.stops < 1:
		failures.append("the cap must ask the backend to stop")
	_free_recognition(h)

	# A partial, then silence: 6 s cap; the backend hands its hypothesis over -> final.
	backend = ScriptedBackend.new()
	backend.hypothesis_on_stop = "banana"
	h = _recognition(backend)
	provider = h["provider"]
	provider.begin_listening()
	_tick(h, 1.0)
	backend.partial_recognized.emit("banana")
	_tick(h, 5.0)
	if provider.state() != RecognitionBase.STATE_PARTIAL:
		failures.append("5 s after a partial the session is still open, got %s" % provider.state())
	_tick(h, 1.5)
	_check_one_ending(failures, h, "timeout-after-partial", RecognitionBase.STATE_FINAL)
	if (h["tally"] as RecTally).finals != ["banana"]:
		failures.append("the hypothesis handed over at the cap is the final: %s" % str((h["tally"] as RecTally).finals))
	_free_recognition(h)

	# A partial, then silence, and a backend with nothing to hand over -> retry.
	backend = ScriptedBackend.new()
	h = _recognition(backend)
	provider = h["provider"]
	provider.begin_listening()
	backend.partial_recognized.emit("ba")
	_tick(h, 8.0)
	_check_one_ending(failures, h, "timeout-after-partial-empty", RecognitionBase.STATE_RETRY)
	_free_recognition(h)

	# The provider's OWN watchdog: a service that never ends its session.
	backend = ScriptedBackend.new()
	h = _recognition(backend)
	provider = h["provider"]
	provider.begin_listening()
	var service: Node = h["service"]
	var left: float = 7.0
	while left > 0.0:
		provider.advance(0.1)  # the service is NOT advanced: its cap never fires
		left -= 0.1
	if provider.has_active_session():
		failures.append("the provider's own watchdog must end a session the service forgot")
	if (h["tally"] as RecTally).ended != ["retry"]:
		failures.append("watchdog ending is retry, got %s" % str((h["tally"] as RecTally).ended))
	service.free()
	return failures


func _test_recognition_unavailable():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	backend.available = false
	var h: Dictionary = _recognition(backend)
	var provider: RefCounted = h["provider"]
	if provider.is_available():
		failures.append("is_available() must mirror the service")
	if not provider.begin_listening():
		failures.append("an unavailable recogniser still opens a session that ends at once")
	_check_one_ending(failures, h, "unavailable", RecognitionBase.STATE_UNAVAILABLE)
	if backend.starts != 0:
		failures.append("an unavailable backend must never be started")
	_free_recognition(h)

	# A permission failure reported by the backend mid-session.
	backend = ScriptedBackend.new()
	h = _recognition(backend)
	provider = h["provider"]
	provider.begin_listening()
	backend.recognition_failed.emit("permission_denied")
	_check_one_ending(failures, h, "permission-denied", RecognitionBase.STATE_UNAVAILABLE)
	_free_recognition(h)
	return failures


func _test_recognition_cancel_drops_late_final():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	backend.hypothesis_on_stop = "milk"  # the stop hands a hypothesis over synchronously
	var h: Dictionary = _recognition(backend)
	var provider: RefCounted = h["provider"]
	var tally: RecTally = h["tally"]
	provider.begin_listening()
	backend.partial_recognized.emit("milk")
	provider.cancel()
	backend.recognized.emit("milk")  # and a late one
	_check_one_ending(failures, h, "cancel", RecognitionBase.STATE_RETRY)
	if not tally.finals.is_empty():
		failures.append("a cancelled session must never produce a final: %s" % str(tally.finals))
	if tally.failures != ["cancelled"]:
		failures.append("cancel reason should be 'cancelled', got %s" % str(tally.failures))
	_free_recognition(h)
	return failures


func _test_recognition_echo_prevention():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	var h: Dictionary = _recognition(backend)
	var provider: RefCounted = h["provider"]
	var tally: RecTally = h["tally"]
	var synth := FakeSynth.new()
	provider.bind_synthesis(synth)

	# begin_listening() while speaking is refused: no session, no mic.
	synth.speak("What is this?")
	if provider.begin_listening():
		failures.append("begin_listening must be refused while synthesis speaks")
	if backend.starts != 0:
		failures.append("the mic opened during playback")
	if tally.refused != ["synthesis_speaking"] or not tally.ended.is_empty():
		failures.append("a refusal is not a session: refused %s, ended %s" % [str(tally.refused), str(tally.ended)])
	synth.stop()

	# A live session is cancelled the moment playback starts.
	if not provider.begin_listening():
		failures.append("begin_listening should work once playback stopped")
	backend.partial_recognized.emit("ap")
	synth.speak("Great job!")
	_check_one_ending(failures, h, "echo-cancel", RecognitionBase.STATE_RETRY)
	if tally.failures != ["playback_started"]:
		failures.append("playback cancels with reason playback_started, got %s" % str(tally.failures))
	if backend.stops < 1:
		failures.append("the mic must be stopped before playback")
	backend.recognized.emit("great job")  # what the mic heard of Aliz herself
	if not tally.finals.is_empty():
		failures.append("Aliz's own voice must never become the child's final")
	_free_recognition(h)
	return failures


func _test_recognition_simulation_and_guard():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	backend.available = false  # no real recogniser here
	var h: Dictionary = _recognition(backend)
	var provider: RefCounted = h["provider"]
	var tally: RecTally = h["tally"]
	if provider.simulated_transcript("apple"):
		failures.append("simulated_transcript must be refused while simulation is off")
	if not RecognitionScript.simulation_allowed():
		failures.append("simulation is allowed on a desktop test run")
	if not provider.set_simulation_enabled(true):
		failures.append("simulation can be enabled on a desktop test run")
	if provider.simulated_transcript("apple"):
		failures.append("simulated_transcript without an open session must be refused")
	provider.begin_listening()
	if backend.starts != 0:
		failures.append("a simulated session must never touch the microphone")
	if not provider.simulated_transcript("apple"):
		failures.append("simulated_transcript should feed the open simulated session")
	_check_one_ending(failures, h, "simulated", RecognitionBase.STATE_FINAL)
	if tally.finals != ["apple"] or tally.partials != ["apple"]:
		failures.append("the simulated transcript takes the partial -> final path: %s / %s" % [str(tally.partials), str(tally.finals)])
	provider.begin_listening()
	provider.simulated_silence()
	if tally.ended != ["final", "retry"]:
		failures.append("simulated silence ends as retry: %s" % str(tally.ended))
	# A simulated session still obeys the caps.
	provider.begin_listening()
	_tick(h, 6.0)
	if tally.ended != ["final", "retry", "retry"]:
		failures.append("a simulated session with no transcript must time out: %s" % str(tally.ended))
	# The guard is the mock's guard: source-level proof it keys on `mobile`.
	var source: String = (RecognitionScript as GDScript).source_code
	if not source.contains("OS.has_feature(\"mobile\")"):
		failures.append("simulation_allowed() must key on OS.has_feature(\"mobile\") like MockSpeechBackend's guard")
	var base_source: String = (RecognitionBase as GDScript).source_code
	for forbidden: String in ["next_transcript", "AudioStreamMicrophone", "HTTPClient", "HTTPRequest"]:
		if base_source.contains(forbidden) or source.replace("simulated_transcript", "").contains(forbidden):
			failures.append("recognition provider must not contain %s" % forbidden)
	_free_recognition(h)
	return failures


func _test_recognition_continuous_rearm():
	var failures: Array = []
	var backend := ScriptedBackend.new()
	var h: Dictionary = _recognition(backend)
	var provider: RefCounted = h["provider"]
	var synth := FakeSynth.new()
	provider.bind_synthesis(synth)
	provider.set_continuous(true, 0.2)
	provider.begin_listening()
	backend.recognized.emit("apple")
	if provider.has_active_session():
		failures.append("the final ends the session even in continuous mode")
	_tick(h, 0.1)
	if backend.starts != 1:
		failures.append("re-arm waits for the delay")
	synth.speak("Great job!")  # Aliz answers: no re-arm while she speaks
	_tick(h, 1.0)
	if backend.starts != 1:
		failures.append("continuous mode must not reopen the mic while Aliz speaks (starts=%d)" % backend.starts)
	synth.stop()
	provider.notify_playback_finished()
	_tick(h, 0.3)
	if backend.starts != 2:
		failures.append("continuous mode re-arms once playback ends (starts=%d)" % backend.starts)
	provider.set_continuous(false)
	provider.cancel()
	_tick(h, 1.0)
	if backend.starts != 2:
		failures.append("with continuous off nothing re-arms")
	_free_recognition(h)
	return failures


# ---------------------------------------------------------------------------
# Scripted provider
# ---------------------------------------------------------------------------

func _engine() -> RefCounted:
	var engine: RefCounted = LessonEngineScript.new()
	engine.load_lesson(LESSON_ID)
	return engine


## Plays the lesson with a fixed answer script; returns the spoken turns.
func _play_lesson(provider: RefCounted, engine: RefCounted, answers: Callable) -> Array:
	var tally := ConvTally.new()
	tally.attach(provider)
	provider.begin_session(LESSON_ID)
	var guard: int = 0
	while not bool(engine.is_complete()) and guard < 80:
		guard += 1
		var step: Dictionary = engine.current_step()
		provider.submit_turn("", {"phase": "open", "step": step})
		if String(step.get("kind", "")) != "ask":
			engine.advance()
			continue
		var attempt: int = 0
		while true:
			attempt += 1
			var said: String = answers.call(step, attempt)
			var before: int = tally.turns.size()
			provider.submit_turn(said, {"phase": "timeout" if said.is_empty() else "answer", "step": step})
			if tally.turns.size() != before + 1:
				return tally.turns  # the caller's assertion will fire
			var action: String = String(tally.turns.back().get("lessonAction", ""))
			if action == "next_question" or action == "complete":
				engine.advance()
				break
			if attempt > 5:
				break
	provider.end_session()
	return tally.turns


func _test_scripted_turns_valid_and_deterministic():
	var failures: Array = []
	var script: Callable = func(step: Dictionary, attempt: int) -> String:
		var answers: Array = step.get("expectedAnswers", [])
		var key: String = String(step.get("stepId", ""))
		if key.contains("banana_colour"):
			return "" if attempt == 1 else ("blue" if attempt == 2 else "")  # timeout, wrong, taught
		if key.contains("apple_colour"):
			return "green" if attempt == 1 else String(answers[0])
		return String(answers[0]) if not answers.is_empty() else "yes"
	var a_engine: RefCounted = _engine()
	var a: RefCounted = ScriptedScript.new()
	a.set_engine(a_engine)
	var turns_a: Array = _play_lesson(a, a_engine, script)
	var b_engine: RefCounted = _engine()
	var b: RefCounted = ScriptedScript.new()
	b.set_engine(b_engine)
	var turns_b: Array = _play_lesson(b, b_engine, script)
	if turns_a.is_empty() or turns_a.size() < 10:
		failures.append("the lesson should produce a run of turns, got %d" % turns_a.size())
	if turns_a != turns_b:
		failures.append("the scripted provider must be reproducible: two runs differ")
	for turn: Dictionary in turns_a:
		if not TurnValidator.is_valid(turn):
			failures.append("scripted turn is not valid: %s" % str(turn))
		if String(turn.get("speech", "")).contains("{"):
			failures.append("an unfilled template reached a turn: %s" % turn.get("speech", ""))
	# The outcomes read right.
	var joined: String = ""
	for turn: Dictionary in turns_a:
		joined += String(turn["speech"]) + " | "
	if not joined.contains("Let's try together!"):
		failures.append("a timeout is voiced as Let's try together!")
	if not (joined.contains("hint") or joined.contains("Let me help") or joined.contains("Listen.")):
		failures.append("a second miss gives a hint")
	if not (joined.contains("Great job") or joined.contains("Yes!")):
		failures.append("a correct answer is praised")
	# One evaluate() per answer: attempts count matches what we sent.
	var c_engine: RefCounted = _engine()
	var c: RefCounted = ScriptedScript.new()
	c.set_engine(c_engine)
	c.begin_session(LESSON_ID)
	c_engine.advance()  # past the hello step
	c.submit_turn("nope", {"phase": "answer"})
	if int(c_engine.attempts()) != 1:
		failures.append("one submit_turn is one evaluate(): attempts=%d" % int(c_engine.attempts()))
	# Together (no recogniser) never dead-ends.
	var together: Dictionary = c.build_turn("", "together")
	if String(together.get("lessonAction", "")) != "next_question" or not String(together["speech"]).to_lower().contains("apple"):
		failures.append("together turn should say the word and move on: %s" % str(together))
	# No session -> provider_failed, no turn.
	var d: RefCounted = ScriptedScript.new()
	d.set_engine(_engine())
	var d_tally := ConvTally.new()
	d_tally.attach(d)
	d.submit_turn("apple", {"phase": "answer"})
	if d_tally.failures != ["no_session"] or not d_tally.turns.is_empty():
		failures.append("submit_turn without a session fails cleanly: %s / %s" % [str(d_tally.failures), str(d_tally.turns)])
	print("    scripted lesson transcript (%d turns):" % turns_a.size())
	for turn: Dictionary in turns_a:
		print("      [%s/%s] %s" % [turn["emotion"], turn["lessonAction"], turn["speech"]])
	return failures


func _test_scripted_variety():
	var failures: Array = []
	var engine: RefCounted = _engine()
	var provider: RefCounted = ScriptedScript.new()
	provider.set_engine(engine)
	provider.begin_session(LESSON_ID)
	var indexes: Dictionary = {}
	var openers: Dictionary = {}
	var lesson: Dictionary = engine.lesson()
	for raw: Variant in lesson.get("steps", []):
		var step: Dictionary = raw
		if String(step.get("kind", "")) != "ask":
			continue
		var index: int = provider.variant_index(step, 1)
		indexes[index] = true
		var verdict: Dictionary = {"outcome": "correct", "lessonAction": "next_question", "attempt": 1,
			"line": "Great job!", "expected": String(step["expectedAnswers"][0])}
		var turn: Dictionary = provider.turn_for_verdict(step, verdict, "answer")
		openers[String(turn["speech"]).split(" ")[0]] = true
	if indexes.size() < 2:
		failures.append("across the lesson at least two variant indexes should be used, got %s" % str(indexes.keys()))
	if openers.size() < 2:
		failures.append("praise should vary across steps, got %s" % str(openers.keys()))
	# Seeded: pinning the seed pins the phrasing.
	provider.set_seed(1)
	var step_one: Dictionary = {"stepId": "x", "kind": "ask", "expectedAnswers": ["cat"], "visualAssetId": "cat"}
	var verdict_one: Dictionary = {"outcome": "correct", "lessonAction": "next_question", "attempt": 1, "line": "Meow!", "expected": "cat"}
	var first: Dictionary = provider.turn_for_verdict(step_one, verdict_one, "answer")
	var second: Dictionary = provider.turn_for_verdict(step_one, verdict_one, "answer")
	if first != second or not String(first["speech"]).begins_with("Wonderful!"):
		failures.append("seed 1 + attempt 1 picks variant 2 (Wonderful!) every time: %s" % first["speech"])
	if ScriptedScript.OPENERS_CORRECT.size() != 3 or ScriptedScript.OPENERS_HINT.size() != 3 or ScriptedScript.OPENERS_RETRY.size() != 3:
		failures.append("three variants per outcome")
	return failures


## The owner's acceptance dialogue at the provider level: choose -> animals,
## cat, the cat sound with its reaction, and a barge-in to the dog.
func _test_scripted_addendum_dialogue():
	var failures: Array = []
	var engine: RefCounted = LessonEngineScript.new()
	var entry: String = String(LessonEngineScript.entry_lesson_id())
	if not engine.load_lesson(entry):
		return ["entry lesson %s did not load" % entry]
	var provider: RefCounted = ScriptedScript.new()
	provider.set_engine(engine)
	var tally := ConvTally.new()
	tally.attach(provider)
	var routes: Array = []
	provider.lesson_routed.connect(func(action: String, target: String) -> void: routes.append([action, target]))
	provider.begin_session(entry)
	var log: Array = []
	var say: Callable = func(transcript: String, phase: String) -> Dictionary:
		provider.submit_turn(transcript, {"phase": phase})
		var turn: Dictionary = tally.turns.back()
		log.append("%s%s -> Aliz: %s" % ["child: " + transcript + " | " if not transcript.is_empty() else "", phase, turn["speech"]])
		return turn

	var ask: Dictionary = say.call("", "open")
	if not String(ask["speech"]).begins_with("Hi! What would you like to learn"):
		failures.append("the entry step asks what to learn: %s" % ask["speech"])
	var choice: Dictionary = say.call("I want to learn about animals!", "answer")
	if String(choice.get("lessonAction", "")) != "switch_lesson" or String(choice.get("nextLessonId", "")) != "animals_cat_dog":
		failures.append("'animals' routes with switch_lesson + nextLessonId: %s" % str(choice))
	if routes != [["switch_lesson", "animals_cat_dog"]]:
		failures.append("lesson_routed fires for the choice: %s" % str(routes))
	if not TurnValidator.is_valid(choice):
		failures.append("the routing turn must survive the validator: %s" % str(choice))
	engine.switch_lesson(String(choice["nextLessonId"]))
	var hello: Dictionary = say.call("", "open")
	if String(hello["speech"]) != "Yay! Let's learn about animals!" or hello["visual"] != {"type": "flashcard", "assetId": "cat"}:
		failures.append("the animals lesson opens with its teach line and the cat card: %s" % str(hello))
	engine.advance()
	var q1: Dictionary = say.call("", "open")
	if String(q1["speech"]) != "What animal is this?":
		failures.append("first question: %s" % q1["speech"])
	var a1: Dictionary = say.call("It's a cat!", "answer")
	if String(a1["emotion"]) != "happy" or not String(a1["speech"]).contains("It's a cat!"):
		failures.append("'It's a cat!' is praised with the lesson's success line: %s" % str(a1))
	engine.advance()
	var q2: Dictionary = say.call("", "open")
	if String(q2["speech"]) != "Can you make a cat sound?":
		failures.append("the sound step asks for the cat sound: %s" % q2["speech"])
	var a2: Dictionary = say.call("Meow!", "answer")
	if String(a2["speech"]) != "Meow! You're amazing!":
		failures.append("the reaction sound is not doubled and the line is kept: '%s'" % a2["speech"])
	if String(a2["gesture"]) != "clap" or String(a2.get("wantsSfx", "")) != "laugh" or String(a2["emotion"]) != "happy":
		failures.append("the sound step's reaction becomes clap + wantsSfx laugh: %s" % str(a2))
	if not TurnValidator.is_valid(a2) or not TurnValidator.coerce(a2).has("wantsSfx"):
		failures.append("wantsSfx survives the client validator: %s" % str(TurnValidator.coerce(a2)))
	# Barge-in while Aliz speaks: a topic change.
	var barge: Dictionary = say.call("Wait! I want a dog!", "interjection")
	if String(barge.get("lessonAction", "")) != "jump_step" or String(barge.get("nextStepId", "")) != "s04_dog":
		failures.append("'Wait! I want a dog!' jumps to the dog: %s" % str(barge))
	if barge["visual"] != {"type": "flashcard", "assetId": "dog"} or not String(barge["speech"]).to_lower().contains("dog"):
		failures.append("the jump shows the dog and says so: %s" % str(barge))
	if routes.size() != 2 or routes[1] != ["jump_step", "s04_dog"]:
		failures.append("lesson_routed fires for the jump: %s" % str(routes))
	var q3: Dictionary = say.call("", "open")
	if String(q3["speech"]) != "What animal is this?" or q3["visual"] != {"type": "flashcard", "assetId": "dog"}:
		failures.append("after the jump the dog question opens: %s" % str(q3))
	# Barge-in that is an answer: judged, not repeated.
	var answered: Dictionary = say.call("a dog", "interjection")
	if String(answered["emotion"]) != "happy" or int(engine.attempts()) != 1:
		failures.append("an interjection that answers is evaluated once: %s attempts=%d" % [str(answered), int(engine.attempts())])
	engine.advance()
	say.call("", "open")
	# Barge-in that is neither: the step is asked again, no attempt counted.
	var before: int = int(engine.attempts())
	var again: Dictionary = say.call("look a bird outside", "interjection")
	if String(again["lessonAction"]) != "retry" or not String(again["speech"]).contains("sound") or int(engine.attempts()) != before:
		failures.append("an unrelated interjection re-asks without counting an attempt: %s" % str(again))
	# "stop" ends the session.
	var stop: Dictionary = say.call("stop", "interjection")
	if String(stop.get("lessonAction", "")) != "end_session":
		failures.append("'stop' ends the session: %s" % str(stop))
	for turn: Dictionary in tally.turns:
		if not TurnValidator.is_valid(turn):
			failures.append("dialogue turn is invalid: %s" % str(turn))
	print("    owner dialogue through the scripted provider:")
	for line: String in log:
		print("      %s" % line)
	return failures


# ---------------------------------------------------------------------------
# Backend provider
# ---------------------------------------------------------------------------

func _test_backend_refuses_when_flag_off():
	var failures: Array = []
	if TutorFlags.cloud_enabled():
		return ["this suite must run with the cloud flag OFF"]
	var engine: RefCounted = _engine()
	var provider: RefCounted = BackendScript.new()
	provider.set_engine(engine)
	provider.use_dev_token()
	var tally := ConvTally.new()
	tally.attach(provider)
	if provider.is_available():
		failures.append("the backend provider is unavailable while the flag is off")
	provider.begin_session(LESSON_ID)
	if tally.failures != ["cloud_disabled"]:
		failures.append("begin_session with the flag off fails with cloud_disabled, got %s" % str(tally.failures))
	engine.advance()  # to the first ask
	provider.submit_turn("apple", {"phase": "answer"})
	if tally.turns.size() != 1:
		failures.append("submit_turn with the flag off still answers exactly once (scripted), got %d" % tally.turns.size())
	if tally.fallbacks != ["cloud_disabled"]:
		failures.append("the scripted fallback is announced as cloud_disabled, got %s" % str(tally.fallbacks))
	if not provider.request_log().is_empty():
		failures.append("NO request may be built while the flag is off: %s" % str(provider.request_log()))
	if provider.has_request_in_flight():
		failures.append("nothing may be in flight with the flag off")
	if String(tally.turns[0].get("emotion", "")) != "happy":
		failures.append("the fallback turn for a correct answer is the scripted praise: %s" % str(tally.turns[0]))
	# Source-order proof, the privacy guard's rule: the flag is read before the
	# first network primitive, and the file carries no URL literal.
	var source: String = (BackendScript as GDScript).source_code
	var code: String = _strip_comments(source)
	var flag_at: int = code.find("cloud_enabled()")
	var client_at: int = code.find("HTTPClient")
	if flag_at < 0 or client_at < 0 or flag_at > client_at:
		failures.append("backend provider must read TutorFlags.cloud_enabled() before its first HTTPClient (flag %d, client %d)" % [flag_at, client_at])
	if not code.contains("backend_url()"):
		failures.append("backend provider must take its address from TutorFlags.backend_url()")
	for scheme: String in ["http://", "https://"]:
		if code.contains(scheme):
			failures.append("backend provider carries a '%s' literal" % scheme)
	for forbidden: String in ["AudioStreamMicrophone", "audioBase64", "\"audio\""]:
		if code.contains(forbidden):
			failures.append("backend provider must never send audio (%s)" % forbidden)
	return failures


func _test_backend_url_parsing_and_error_codes():
	var failures: Array = []
	var cases: Dictionary = {
		"http://127.0.0.1:8787": {"host": "127.0.0.1", "port": 8787, "tls": false, "prefix": ""},
		"https://tutor.example/api/": {"host": "tutor.example", "port": 443, "tls": true, "prefix": "/api"},
		"http://localhost": {"host": "localhost", "port": 80, "tls": false, "prefix": ""},
		"ftp://x": {},
		"nonsense": {},
	}
	for url: String in cases.keys():
		var got: Dictionary = BackendScript.parse_url(url)
		if got != cases[url]:
			failures.append("parse_url(%s) = %s, expected %s" % [url, str(got), str(cases[url])])
	var codes: Array = [
		[{"error": {"code": "quota_exhausted"}}, 429, "quota_exhausted"],
		[{"error": {"code": "not_approved"}}, 403, "not_approved"],
		[{"error": {"code": "provider_unavailable"}}, 503, "provider_unavailable"],
		[{"error": {"code": "rate_limited"}}, 429, "rate_limited"],
		[{"error": {"code": "timeout"}}, 504, "timeout"],
		[{}, 503, "provider_unavailable"],
		[{}, 504, "timeout"],
		[{}, 500, "http_500"],
	]
	for row: Array in codes:
		var reason: String = BackendScript._error_code(row[0], row[1])
		if reason != row[2]:
			failures.append("error code for %s/%d = %s, expected %s" % [str(row[0]), row[1], reason, row[2]])
	return failures


## Spawns `node backend/src/server.js` in DEV_MODE on a free port. Returns the
## base URL or "" (with the reason printed).
func _spawn_server(extra_env: Array = []) -> String:
	if _node_path.is_empty():
		for candidate: String in NODE_CANDIDATES:
			if FileAccess.file_exists(candidate):
				_node_path = candidate
				break
	if _node_path.is_empty():
		print("    SKIP backend live test: node not found at %s" % str(NODE_CANDIDATES))
		return ""
	var repo_root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var server_js: String = repo_root.path_join("backend/src/server.js")
	if not FileAccess.file_exists(server_js):
		print("    SKIP backend live test: %s missing" % server_js)
		return ""
	var port: int = _free_port()
	if port <= 0:
		print("    SKIP backend live test: no free port")
		return ""
	var data_dir: String = OS.get_temp_dir().path_join("littledays-tutor-test-%d-%d" % [OS.get_process_id(), port])
	DirAccess.make_dir_recursive_absolute(data_dir)
	var args: PackedStringArray = PackedStringArray(["DEV_MODE=1", "PORT=%d" % port, "HOST=127.0.0.1", "DATA_DIR=%s" % data_dir])
	for entry: String in extra_env:
		args.append(entry)
	args.append(_node_path)
	args.append(server_js)
	var pid: int = OS.create_process("/usr/bin/env", args, false)
	if pid <= 0:
		print("    SKIP backend live test: could not spawn node")
		return ""
	_servers.append({"pid": pid, "dataDir": data_dir})
	var base: String = "http://127.0.0.1:%d" % port
	var deadline: int = Time.get_ticks_msec() + int(SERVER_READY_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _http_get_ok(port, "/healthz"):
			return base
		OS.delay_msec(100)
	print("    SKIP backend live test: server on %s did not answer /healthz in %.0f s" % [base, SERVER_READY_SECONDS])
	return ""


func _stop_servers() -> void:
	for server: Dictionary in _servers:
		OS.kill(int(server["pid"]))
	_servers.clear()


func _free_port() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _attempt: int in range(20):
		var port: int = rng.randi_range(20000, 40000)
		var probe := TCPServer.new()
		if probe.listen(port, "127.0.0.1") == OK:
			probe.stop()
			return port
	return -1


func _http_get_ok(port: int, path: String) -> bool:
	var client := HTTPClient.new()
	if client.connect_to_host("127.0.0.1", port) != OK:
		return false
	var deadline: int = Time.get_ticks_msec() + 1500
	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING] and Time.get_ticks_msec() < deadline:
		client.poll()
		OS.delay_msec(5)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return false
	client.request(HTTPClient.METHOD_GET, path, PackedStringArray())
	while client.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
		client.poll()
		OS.delay_msec(5)
	var ok: bool = client.has_response() and client.get_response_code() == 200
	client.close()
	return ok


## Pumps a provider until `predicate` holds or `seconds` of real time pass.
func _pump(provider: RefCounted, predicate: Callable, seconds: float = ROUND_TRIP_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var last: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline:
		var now_msec: int = Time.get_ticks_msec()
		provider.advance(float(now_msec - last) / 1000.0)
		last = now_msec
		if bool(predicate.call()):
			return true
		OS.delay_msec(5)
	provider.advance(0.001)
	return bool(predicate.call())


func _armed_provider(base_url: String, engine: RefCounted) -> Dictionary:
	var provider: RefCounted = BackendScript.new()
	provider.set_engine(engine)
	provider.use_dev_token()
	provider.set_base_url(base_url)
	if not provider.enable_for_tests():
		return {}
	var tally := ConvTally.new()
	tally.attach(provider)
	return {"provider": provider, "tally": tally}


func _test_backend_live_round_trip():
	var failures: Array = []
	var base: String = _spawn_server()
	if base.is_empty():
		return failures  # skipped, reason printed
	var engine: RefCounted = _engine()
	var h: Dictionary = _armed_provider(base, engine)
	if h.is_empty():
		return ["enable_for_tests() refused on a desktop run"]
	var provider: RefCounted = h["provider"]
	var tally: ConvTally = h["tally"]
	if not provider.is_available():
		failures.append("armed provider reports available")

	# Session.
	provider.begin_session(LESSON_ID)
	if not _pump(provider, func() -> bool: return not tally.sessions.is_empty() or not tally.failures.is_empty()):
		return ["live: no session answer within %.0f s" % ROUND_TRIP_SECONDS]
	if tally.sessions.size() != 1 or not tally.failures.is_empty():
		return ["live: session failed: %s" % str(tally.failures)]
	var session: Dictionary = tally.sessions[0]
	var session_id: String = String(session.get("sessionId", ""))
	if session_id.is_empty() or String(session.get("provider", "")) != "backend":
		failures.append("live: session_ready carries the server session id: %s" % str(session))
	print("    DEV_MODE round trip on %s" % base)
	print("      session %s entitlement=%s remaining=%s" % [session_id, session.get("entitlement", ""), str((session.get("quota", {}) as Dictionary).get("remainingSeconds", "?"))])

	# Open turn: local, no request.
	var requests_before: int = provider.request_log().size()
	provider.submit_turn("", {"phase": "open"})
	if tally.turns.size() != 1 or provider.request_log().size() != requests_before:
		failures.append("live: an open turn is built locally without a request")
	engine.advance()  # -> s02 apple

	# Correct turn.
	provider.submit_turn("apple", {"phase": "answer"})
	if not _pump(provider, func() -> bool: return tally.turns.size() >= 2):
		return ["live: no turn answer for 'apple' within %.0f s" % ROUND_TRIP_SECONDS]
	var correct: Dictionary = tally.turns[1]
	if not TurnValidator.is_valid(correct):
		failures.append("live: the server turn must be valid: %s" % str(correct))
	if not tally.fallbacks.is_empty():
		failures.append("live: a healthy server turn is not a fallback: %s" % str(tally.fallbacks))
	if tally.metas.is_empty() or String(tally.metas[0].get("provider", "")) != "mock":
		failures.append("live: turn_meta reports the server's mock provider: %s" % str(tally.metas))
	var sent: Dictionary = _last_request(provider, "turn")
	var body: Dictionary = sent.get("body", {})
	if String(body.get("transcript", "")) != "apple":
		failures.append("live: the transcript text is what was sent: %s" % str(body))
	var ctx: Dictionary = body.get("lessonContext", {})
	if String(ctx.get("outcome", "")) != "correct" or String(ctx.get("stepId", "")) != "s02_apple_name":
		failures.append("live: lessonContext carries the engine's verdict: %s" % str(ctx))
	for key: String in body.keys():
		if not ["transcript", "lessonContext"].has(String(key)):
			failures.append("live: request carries an unexpected field %s" % key)
	var idem: String = ""
	for header: String in sent.get("headers", []):
		if header.begins_with("Idempotency-Key: "):
			idem = header.trim_prefix("Idempotency-Key: ")
	if idem != "%s:s02_apple_name:1" % session_id:
		failures.append("live: Idempotency-Key = sessionId:stepId:attempt, got '%s'" % idem)
	print("      turn 1 transcript='apple' outcome=%s -> [%s/%s] %s" % [ctx.get("outcome", ""), correct["emotion"], correct["lessonAction"], correct["speech"]])
	engine.advance()  # -> s03 apple colour (expects red)

	# Incorrect turn.
	provider.submit_turn("banana", {"phase": "answer"})
	if not _pump(provider, func() -> bool: return tally.turns.size() >= 3):
		return ["live: no turn answer for 'banana' within %.0f s" % ROUND_TRIP_SECONDS]
	var incorrect: Dictionary = tally.turns[2]
	var ctx2: Dictionary = (_last_request(provider, "turn").get("body", {}) as Dictionary).get("lessonContext", {})
	if String(ctx2.get("outcome", "")) != "incorrect":
		failures.append("live: 'banana' for red is incorrect: %s" % str(ctx2))
	if String(incorrect.get("emotion", "")) == "happy":
		failures.append("live: an incorrect answer is not celebrated: %s" % str(incorrect))
	print("      turn 2 transcript='banana' outcome=%s -> [%s/%s] %s" % [ctx2.get("outcome", ""), incorrect["emotion"], incorrect["lessonAction"], incorrect["speech"]])

	# End.
	var ended: Array = []
	provider.session_ended.connect(func(summary: Dictionary) -> void: ended.append(summary))
	provider.end_session()
	if not _pump(provider, func() -> bool: return not ended.is_empty()):
		failures.append("live: end_session should get an answer")
	elif not String(ended[0].get("reason", "")).is_empty():
		failures.append("live: end failed: %s" % str(ended[0]))
	else:
		print("      end usage=%s" % str(ended[0].get("usage", {})))

	# After end: a turn falls back (no session), never hangs.
	provider.submit_turn("red", {"phase": "answer"})
	if tally.turns.size() != 4 or tally.fallbacks != ["no_session"]:
		failures.append("live: after end_session a turn falls back locally at once: turns=%d fallbacks=%s" % [tally.turns.size(), str(tally.fallbacks)])

	# not_approved: a bad token.
	var bad: RefCounted = BackendScript.new()
	bad.set_engine(_engine())
	bad.set_parent_approval_token("pa1.not.a.real.token")
	bad.set_base_url(base)
	bad.enable_for_tests()
	var bad_tally := ConvTally.new()
	bad_tally.attach(bad)
	bad.begin_session(LESSON_ID)
	_pump(bad, func() -> bool: return not bad_tally.failures.is_empty())
	if bad_tally.failures != ["not_approved"]:
		failures.append("live: a bad parent token maps to not_approved, got %s" % str(bad_tally.failures))

	# not_found: a session the server does not know (a restarted server).
	var lost: RefCounted = BackendScript.new()
	var lost_engine: RefCounted = _engine()
	lost_engine.advance()
	lost.set_engine(lost_engine)
	lost.use_dev_token()
	lost.set_base_url(base)
	lost.enable_for_tests()
	lost._session = {"sessionId": "00000000-0000-4000-8000-000000000000"}
	lost._active = true
	var lost_tally := ConvTally.new()
	lost_tally.attach(lost)
	lost.submit_turn("apple", {"phase": "answer"})
	_pump(lost, func() -> bool: return not lost_tally.turns.is_empty())
	if lost_tally.fallbacks != ["not_found"] or lost_tally.turns.size() != 1:
		failures.append("live: unknown session maps to not_found + scripted turn, got %s / %d" % [str(lost_tally.fallbacks), lost_tally.turns.size()])

	# session_ended: turns after the server closed it.
	var closed: RefCounted = BackendScript.new()
	var closed_engine: RefCounted = _engine()
	closed_engine.advance()
	closed.set_engine(closed_engine)
	closed.use_dev_token()
	closed.set_base_url(base)
	closed.enable_for_tests()
	var closed_tally := ConvTally.new()
	closed_tally.attach(closed)
	closed.begin_session(LESSON_ID)
	_pump(closed, func() -> bool: return not closed_tally.sessions.is_empty())
	var closed_session: Dictionary = closed._session.duplicate(true)
	closed.end_session()
	_pump(closed, func() -> bool: return not closed.has_request_in_flight())
	closed._session = closed_session
	closed._active = true
	closed.submit_turn("apple", {"phase": "answer"})
	_pump(closed, func() -> bool: return not closed_tally.turns.is_empty())
	if closed_tally.fallbacks != ["session_ended"]:
		failures.append("live: a turn on an ended session maps to session_ended, got %s" % str(closed_tally.fallbacks))

	# quota_exhausted (allowance 0) and rate_limited (IP limit 1) on a starved server.
	var starved: String = _spawn_server(["FREE_DAILY_SECONDS=0", "RATE_LIMIT_IP_PER_MINUTE=1"])
	if not starved.is_empty():
		var q: RefCounted = BackendScript.new()
		q.set_engine(_engine())
		q.use_dev_token()
		q.set_base_url(starved)
		q.enable_for_tests()
		var q_tally := ConvTally.new()
		q_tally.attach(q)
		q.begin_session(LESSON_ID)
		_pump(q, func() -> bool: return not q_tally.failures.is_empty())
		if q_tally.failures != ["quota_exhausted"]:
			failures.append("live: allowance 0 maps to quota_exhausted, got %s" % str(q_tally.failures))
		q.begin_session(LESSON_ID)
		_pump(q, func() -> bool: return q_tally.failures.size() >= 2)
		if q_tally.failures.size() < 2 or q_tally.failures[1] != "rate_limited":
			failures.append("live: the second request within the IP limit maps to rate_limited, got %s" % str(q_tally.failures))
		print("      error mappings: not_approved, not_found, session_ended, quota_exhausted, rate_limited all observed")
	return failures


func _last_request(provider: RefCounted, kind: String) -> Dictionary:
	var log: Array = provider.request_log()
	for i: int in range(log.size() - 1, -1, -1):
		var entry: Dictionary = log[i]
		if String(entry.get("kind", "")) == kind and entry.has("body"):
			return entry
	return {}


func _test_backend_timeout_and_unreachable():
	var failures: Array = []
	# A socket that accepts and never answers: the 8 s timeout (simulated
	# time) ends in a scripted fallback, never a hang.
	var port: int = _free_port()
	var sink := TCPServer.new()
	if port <= 0 or sink.listen(port, "127.0.0.1") != OK:
		return ["could not open a sink socket for the timeout test"]
	var engine: RefCounted = _engine()
	engine.advance()
	var provider: RefCounted = BackendScript.new()
	provider.set_engine(engine)
	provider.use_dev_token()
	provider.set_base_url("http://127.0.0.1:%d" % port)
	provider.enable_for_tests()
	var tally := ConvTally.new()
	tally.attach(provider)
	provider._session = {"sessionId": "sink"}
	provider._active = true
	provider.submit_turn("apple", {"phase": "answer"})
	var peers: Array = []
	var simulated: float = 0.0
	while simulated < 7.9:
		if sink.is_connection_available():
			peers.append(sink.take_connection())
		provider.advance(0.1)
		simulated += 0.1
		OS.delay_msec(1)
	if not tally.turns.is_empty():
		failures.append("before 8 s the request is still pending (no premature fallback)")
	provider.advance(0.2)
	if tally.fallbacks != ["timeout"] or tally.turns.size() != 1:
		failures.append("at 8 s the turn falls back with reason timeout: %s / %d turns" % [str(tally.fallbacks), tally.turns.size()])
	if provider.has_request_in_flight():
		failures.append("nothing stays in flight after the timeout")
	sink.stop()

	# Nothing listening at all: provider_unavailable, at once.
	var dead: RefCounted = BackendScript.new()
	var dead_engine: RefCounted = _engine()
	dead_engine.advance()
	dead.set_engine(dead_engine)
	dead.use_dev_token()
	dead.set_base_url("http://127.0.0.1:%d" % port)
	dead.enable_for_tests()
	var dead_tally := ConvTally.new()
	dead_tally.attach(dead)
	dead.begin_session(LESSON_ID)
	_pump(dead, func() -> bool: return not dead_tally.failures.is_empty(), 3.0)
	if dead_tally.failures != ["provider_unavailable"]:
		failures.append("a closed port maps to provider_unavailable, got %s" % str(dead_tally.failures))

	# The test override never reaches past loopback.
	var far: RefCounted = BackendScript.new()
	far.set_engine(_engine())
	far.use_dev_token()
	far.set_base_url("http://203.0.113.10:8787")
	far.enable_for_tests()
	var far_tally := ConvTally.new()
	far_tally.attach(far)
	far.begin_session(LESSON_ID)
	far.advance(0.1)
	if far_tally.failures != ["provider_unavailable"]:
		failures.append("the test override must refuse a non-loopback address, got %s" % str(far_tally.failures))
	var log: Array = far.request_log()
	for entry: Dictionary in log:
		if entry.has("body"):
			failures.append("no request may be SENT to a non-loopback address under the test override")
	# cancel() drops an in-flight request: no turn follows.
	var sink2 := TCPServer.new()
	sink2.listen(port, "127.0.0.1")
	var c: RefCounted = BackendScript.new()
	var ce: RefCounted = _engine()
	ce.advance()
	c.set_engine(ce)
	c.use_dev_token()
	c.set_base_url("http://127.0.0.1:%d" % port)
	c.enable_for_tests()
	var c_tally := ConvTally.new()
	c_tally.attach(c)
	c._session = {"sessionId": "sink"}
	c._active = true
	c.submit_turn("apple", {"phase": "answer"})
	c.advance(0.1)
	c.cancel()
	c.advance(9.0)
	if not c_tally.turns.is_empty() or c.has_request_in_flight():
		failures.append("cancel() drops the request; no turn follows")
	sink2.stop()
	return failures


# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------

func _voice_harness(recorded_ids: Array) -> Dictionary:
	var tts = TtsServiceScript.new()
	var tts_timers: Array = []
	tts.set_timer_factory(func(_d: float, cb: Callable) -> void: tts_timers.append(cb))
	var director = DirectorScript.new()
	var timers: Array = []
	director.set_timer_factory(func(_d: float, cb: Callable) -> void: timers.append(cb))
	director.set_tts(tts)
	var streams: Dictionary = {}
	for line_id: String in recorded_ids:
		streams[line_id] = _silent_stream(0.5)
	director.set_stream_resolver(func(line_id: String) -> AudioStream: return streams.get(line_id, null))
	var root: Node = _root()
	root.add_child(tts)
	root.add_child(director)
	director.build()
	var synth: Node = SynthScript.new()
	synth.set_voice(director)
	synth.set_tts(tts)
	root.add_child(synth)
	var started: Array = []
	var finished: Array = []
	var platform_started: Array = []
	var platform_finished: Array = []
	synth.started.connect(func(text: String) -> void: started.append(text))
	synth.finished.connect(func(text: String) -> void: finished.append(text))
	synth.platform_speech_started.connect(func(text: String) -> void: platform_started.append(text))
	synth.platform_speech_finished.connect(func(text: String) -> void: platform_finished.append(text))
	return {"tts": tts, "director": director, "synth": synth, "timers": timers, "tts_timers": tts_timers,
		"started": started, "finished": finished, "platformStarted": platform_started, "platformFinished": platform_finished}


func _free_voice_harness(h: Dictionary) -> void:
	for key: String in ["synth", "director", "tts"]:
		var node: Node = h[key]
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


## The provider moves signal-stack work to its next `advance()` (the frame).
func _flush_deferred(synth: Node = null) -> void:
	if synth != null:
		synth.advance(0.001)


func _test_synthesis_routes():
	var failures: Array = []
	var h: Dictionary = _voice_harness(["aliz_001_welcome", "aliz_006_good_job"])
	var synth: Node = h["synth"]
	var director = h["director"]
	var started: Array = h["started"]
	var finished: Array = h["finished"]

	# 1. A step with a spokenLineId that is recorded: the recording, lip sync on Aliz's player.
	var order: Array = []
	synth.started.connect(func(_t: String) -> void: order.append("started"))
	director.line_started.connect(func(_id: String, _c: String, _t: String) -> void: order.append("voice_line_started"))
	synth.speak_turn({"speech": "Welcome to Little Days!"}, "aliz_001_welcome")
	if synth.voice_used() != "recording":
		failures.append("a recorded spokenLineId plays the recording, got %s" % synth.voice_used())
	if order.slice(0, 2) != ["started", "voice_line_started"]:
		failures.append("`started` must fire BEFORE any sound (echo prevention), got %s" % str(order))
	if synth.lip_sync_player() == null or synth.lip_sync_player() != director.get_player("aliz"):
		failures.append("lip_sync_player() is Aliz's player while a recording plays")
	if String(synth.lip_sync_bus()) != "Voice":
		failures.append("lip_sync_bus() is the Voice bus")
	if not synth.is_speaking():
		failures.append("speaking while the recording plays")
	director.notify_recording_finished("aliz")
	_flush_deferred(synth)
	if finished != ["Welcome to Little Days!"] or synth.is_speaking():
		failures.append("finished fires once when the recording ends: %s" % str(finished))

	# 2. Text that IS a pack line (an alias): the recording through say_text.
	synth.speak("Nice!")
	if synth.voice_used() != "recording" or director.current_line() != "aliz_006_good_job":
		failures.append("text matching a pack line plays that recording, got %s / %s" % [synth.voice_used(), director.current_line()])
	synth.cancel()
	_flush_deferred(synth)
	if finished.size() != 2 or synth.is_speaking() or director.is_speaking():
		failures.append("cancel finishes the utterance once and stops the voice: %s" % str(finished))

	# 3. Free text: the device voice under the pack's queue.
	synth.speak("What is this?")
	if synth.voice_used() != "voice_tts":
		failures.append("free text goes to the device voice under Voice's queue, got %s" % synth.voice_used())
	if synth.lip_sync_player() != null:
		failures.append("no player for the platform voice (the text envelope runs instead)")
	_flush_deferred(synth)
	if h["platformStarted"] != ["What is this?"]:
		failures.append("platform speech_started is forwarded: %s" % str(h["platformStarted"]))
	var tts_timers: Array = h["tts_timers"]
	if tts_timers.is_empty():
		failures.append("expected a TtsService timer for the utterance")
	else:
		(tts_timers.pop_back() as Callable).call()
	_flush_deferred(synth)
	if finished.size() != 3 or h["platformFinished"] != ["What is this?"]:
		failures.append("finished + platform_speech_finished when the device voice ends: %s / %s" % [str(finished), str(h["platformFinished"])])

	# 4. Muted: paced, no sound, still finishes.
	synth.set_muted(true)
	synth.speak("Can you say banana?")
	if synth.voice_used() != "paced" or director.is_speaking():
		failures.append("muted speech is paced and silent, got %s" % synth.voice_used())
	synth.advance(0.5)
	if not synth.is_speaking():
		failures.append("paced speech lasts a reading-speed duration")
	synth.advance(3.0)
	if finished.size() != 4:
		failures.append("paced speech finishes on the clock: %s" % str(finished))
	synth.set_muted(false)

	# 5. Empty text: nothing.
	if synth.speak("   ") or started.size() != 4:
		failures.append("blank text is refused and emits nothing")
	_free_voice_harness(h)
	return failures


func _test_synthesis_forwards_platform_voice():
	var failures: Array = []
	# No Voice autoload at all: TtsService directly.
	var tts = TtsServiceScript.new()
	var tts_timers: Array = []
	tts.set_timer_factory(func(_d: float, cb: Callable) -> void: tts_timers.append(cb))
	var root: Node = _root()
	root.add_child(tts)
	var synth: Node = SynthScript.new()
	synth.set_tts(tts)
	root.add_child(synth)
	var blank := Node.new()
	synth.set_voice(blank)  # a node without say_text: not a voice
	var finished: Array = []
	var platform: Array = []
	synth.finished.connect(func(text: String) -> void: finished.append(text))
	synth.platform_speech_started.connect(func(text: String) -> void: platform.append(text))
	synth.speak("Great job!")
	if synth.voice_used() != "tts":
		failures.append("without Voice the platform voice is used directly, got %s" % synth.voice_used())
	_flush_deferred(synth)  # the pending _begin_tts
	if platform != ["Great job!"]:
		failures.append("platform_speech_started forwarded for the direct route: %s" % str(platform))
	if not tts_timers.is_empty():
		(tts_timers.pop_back() as Callable).call()
	_flush_deferred(synth)
	if finished != ["Great job!"]:
		failures.append("finished once when TtsService ends: %s" % str(finished))

	# No voice of any kind: paced, still finishes.
	var lonely: Node = SynthScript.new()
	lonely.set_voice(blank)
	lonely.set_tts(blank)
	var lonely_finished: Array = []
	lonely.finished.connect(func(text: String) -> void: lonely_finished.append(text))
	lonely.speak("Hello!")
	if lonely.voice_used() != "paced":
		failures.append("no voice at all -> paced, got %s" % lonely.voice_used())
	lonely.advance(10.0)
	if lonely_finished != ["Hello!"]:
		failures.append("paced speech with no voice still finishes")
	lonely.free()
	blank.free()
	for node: Node in [synth, tts]:
		root.remove_child(node)
		node.free()
	return failures


func _test_backend_synthesis_is_a_stub():
	var failures: Array = []
	var stub: Node = BackendSynthScript.new()
	if stub.is_available():
		failures.append("the backend synthesis provider is unavailable today")
	var emitted: Array = []
	stub.started.connect(func(t: String) -> void: emitted.append(t))
	if stub.speak("Hello") or not emitted.is_empty():
		failures.append("the stub refuses to speak and emits nothing")
	if stub.unavailable_reason() != "cloud_disabled":
		failures.append("with the flag off the reason is cloud_disabled, got %s" % stub.unavailable_reason())
	var code: String = _strip_comments((BackendSynthScript as GDScript).source_code)
	for primitive: String in ["HTTPClient", "HTTPRequest", "WebSocketPeer", "StreamPeerTCP"]:
		if code.contains(primitive):
			failures.append("the stub must contain no network primitive (%s)" % primitive)
	stub.free()
	return failures


# ---------------------------------------------------------------------------
# Turn UX
# ---------------------------------------------------------------------------

func _test_turn_ux_states():
	var failures: Array = []
	var ux: RefCounted = UxScript.new()
	var face := FakeFace.new()
	ux.set_face(face)
	var banners: Array = []
	var offers: Array = []
	ux.banner_changed.connect(func(text: String) -> void: banners.append(text))
	ux.offline_offered.connect(func(line: String, button: String) -> void: offers.append([line, button]))

	ux.enter("listening")
	if not face.calls.has("expression:listening") or not face.calls.has("pose:true"):
		failures.append("listening sets the listening expression and pose: %s" % str(face.calls))
	if ux.banner() != "Listening...":
		failures.append("listening banner")
	face.calls.clear()
	ux.enter("thinking")
	if not face.calls.has("expression:thinking") or not face.calls.has("gesture:nod") or not face.calls.has("pose:false"):
		failures.append("thinking nods and drops the pose: %s" % str(face.calls))
	face.calls.clear()
	var turn: Dictionary = {"speech": "Great job! It's an apple!", "subtitle": "Great job!", "emotion": "happy", "gesture": "clap", "lessonAction": "next_question"}
	ux.enter("speaking", {"turn": turn})
	if not face.calls.has("expression:happy") or not face.calls.has("gesture:clap") or not face.calls.has("speaking:true"):
		failures.append("speaking applies the turn's emotion/gesture and opens the mouth channel: %s" % str(face.calls))
	if ux.banner() != "Great job!":
		failures.append("speaking banner is the subtitle")
	face.calls.clear()
	ux.enter("success")
	if not face.calls.has("expression:smile") or not face.calls.has("gesture:clap") or ux.banner() != "Great!":
		failures.append("success = smile + clap + Great!: %s" % str(face.calls))
	face.calls.clear()
	ux.enter("incorrect", {"hint": "It's round and red."})
	if not face.calls.has("expression:encouraging") or ux.banner() != "It's round and red.":
		failures.append("incorrect = encouraging + hint: %s / %s" % [str(face.calls), ux.banner()])
	if face.calls.has("expression:sad") or ux.banner().contains("X") or ux.banner().contains("%"):
		failures.append("never a red X or a score")
	face.calls.clear()
	ux.enter("timeout")
	if not face.calls.has("gesture:tilt") or ux.banner() != "Let's try together!":
		failures.append("timeout = Let's try together! + tilt: %s" % str(face.calls))
	face.calls.clear()
	ux.enter("unavailable")
	if offers.size() != 1 or offers[0][0] != "Let's play with Baby instead!" or String(offers[0][1]).is_empty():
		failures.append("unavailable offers the offline path with a way home: %s" % str(offers))
	ux.enter("idle")
	if not face.calls.has("speaking:false"):
		failures.append("idle closes the mouth channel")
	if ux.history() != ["listening", "thinking", "speaking", "success", "incorrect", "timeout", "unavailable", "idle"]:
		failures.append("history records every state: %s" % str(ux.history()))
	# A face without any of the methods, or no face: no error, banners still move.
	var bare: RefCounted = UxScript.new()
	bare.set_face(RefCounted.new())
	for state: String in UxScript.STATES:
		bare.enter(state, {"turn": turn})
	var none: RefCounted = UxScript.new()
	none.enter("speaking", {"turn": turn})
	if none.banner() != "Great job!":
		failures.append("the UX works without a face at all")
	# After-turn mapping.
	if UxScript.after_turn_state(turn) != "success":
		failures.append("a happy next_question turn lands in success")
	if UxScript.after_turn_state({"emotion": "encouraging", "lessonAction": "give_hint"}) != "incorrect":
		failures.append("a hint turn lands in incorrect")
	if UxScript.after_turn_state({"emotion": "encouraging", "lessonAction": "retry"}, "timeout") != "timeout":
		failures.append("a timeout turn lands in timeout")
	if UxScript.after_turn_state({"emotion": "smile", "lessonAction": "retry"}, "open") != "listening":
		failures.append("an asked question lands in listening")
	if UxScript.state_for_recognition("unavailable") != "unavailable" or UxScript.state_for_recognition("final") != "thinking":
		failures.append("recognition terminals map to UX states")
	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _strip_comments(source: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at < 0 else line.left(hash_at))
	return "\n".join(out)


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
