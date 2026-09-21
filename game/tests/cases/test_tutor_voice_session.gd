extends RefCounted

## Hands-free Aliz (addendum 2026-09-20 evening): VAD, session states, mic
## scope, barge-in, transports, the owner's acceptance dialogue.
##
##   * VAD truth table on synthetic level sequences: a 600 ms answer starts
##     and ends; an 80 ms cough never starts (burst ignored); a mid-sentence
##     pause of 700 ms does not cut the utterance; a short utterance waits the
##     extended 1600 ms; a trailing "um" extends; 3 s of silence is a long
##     pause; the echo gate refuses Aliz's own level and admits a louder,
##     longer child; the noise floor adapts.
##   * Mic scope: capture only while active + not muted + a listening state;
##     never before start, never without the gate, never while thinking,
##     never after stop/background/quota; foreground reopens nothing; mute
##     stops it at once.
##   * Barge-in: child speech during aliz_speaking -> synth cancelled (Voice
##     stopped), transport cancelled, mouth 0 within 120 ms, listening face +
##     tilt, queued turns flushed, the new utterance captured as an
##     interjection; no overlapping replies; dropped deltas never replayed.
##   * Transports: the mock streams deltas + envelope deterministically and
##     cancels cleanly; the cloud transport refuses with the flag off and holds
##     no address of its own; `build_turn` validates and keeps the engine's
##     lesson action.
##   * The owner's dialogue, hands-free, with state-sequence prints.

const SessionScript := preload("res://scripts/tutor/voice/tutor_voice_session.gd")
const VadScript := preload("res://scripts/tutor/voice/vad.gd")
const MockTransportScript := preload("res://scripts/tutor/voice/transports/mock_realtime_transport.gd")
const CloudTransportScript := preload("res://scripts/tutor/voice/transports/cloud_realtime_transport.gd")
const TransportBase := preload("res://scripts/tutor/voice/transports/realtime_transport.gd")
const RecognitionScript := preload("res://scripts/tutor/providers/on_device_recognition_provider.gd")
const ScriptedScript := preload("res://scripts/tutor/providers/scripted_conversation_provider.gd")
const SynthScript := preload("res://scripts/tutor/providers/voice_pack_synthesis_provider.gd")
const LessonEngineScript := preload("res://scripts/tutor/lesson/lesson_engine.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const FRAME_MS: float = 20.0


## A face that records calls and stamps when the mouth closed.
class FakeFace:
	extends RefCounted
	var calls: Array = []
	var speaking: bool = false
	var mouth_closed_usec: int = -1
	func set_expression(name: String) -> bool:
		calls.append("expression:%s" % name)
		return true
	func play_gesture(name: String) -> float:
		calls.append("gesture:%s" % name)
		return 0.4
	func set_speaking(active: bool) -> void:
		calls.append("speaking:%s" % str(active))
		speaking = active
		if not active:
			mouth_closed_usec = Time.get_ticks_usec()
	func set_listening_pose(active: bool) -> void:
		calls.append("pose:%s" % str(active))


## A voice that records stop() calls (stands in for /root/Voice).
class FakeVoice:
	extends Node
	signal line_started(line_id: String, character: String, text: String)
	signal line_finished(line_id: String)
	var stops: int = 0
	var spoken: Array = []
	var current: String = ""
	var serial: int = 0
	func say(_id: String, _opts: Dictionary = {}) -> bool:
		return false
	func say_text(text: String, _opts: Dictionary = {}) -> bool:
		serial += 1
		current = text
		spoken.append(text)
		line_started.emit("", "aliz", text)
		return true
	func stop(_character: String = "") -> void:
		stops += 1
		if not current.is_empty():
			var t: String = current
			current = ""
			line_finished.emit("")
	func finish() -> void:
		if not current.is_empty():
			current = ""
			line_finished.emit("")
	func is_speaking() -> bool:
		return not current.is_empty()
	func is_playing_recording() -> bool:
		return false
	func get_player(_c: String) -> AudioStreamPlayer:
		return null
	func current_character() -> String:
		return "aliz"


class Log:
	extends RefCounted
	var states: Array = []
	var events: Array = []
	var ended: Array = []
	var turns: Array = []
	var captures: Array = []
	func attach(session: RefCounted) -> void:
		session.state_changed.connect(func(_f: String, t: String) -> void: states.append(t))
		session.child_speech_started.connect(func() -> void: events.append("child_speech_started"))
		session.child_speech_ended.connect(func(t: String) -> void: events.append("child_speech_ended:%s" % t))
		session.barge_in.connect(func() -> void: events.append("barge_in"))
		session.aliz_started.connect(func(turn: Dictionary) -> void: turns.append(turn); events.append("aliz:%s" % turn.get("speech", "")))
		session.session_ended.connect(func(r: String) -> void: ended.append(r))
		session.capture_changed.connect(func(c: bool) -> void: captures.append(c))


func test_name() -> String:
	return "tutor_voice_session"


func run():
	var failures: Array = []
	failures.append_array(_test_vad_truth_table())
	failures.append_array(_test_vad_echo_gate_and_floor())
	failures.append_array(_test_mic_scope())
	failures.append_array(_test_hands_free_turn_and_reprompt())
	failures.append_array(_test_barge_in())
	failures.append_array(_test_mock_transport())
	failures.append_array(_test_cloud_transport_gated())
	failures.append_array(_test_owner_dialogue())
	failures.append_array(_test_recognizer_driven_mode())
	failures.append_array(_test_profile_and_guards())
	return failures


# ---------------------------------------------------------------------------
# VAD
# ---------------------------------------------------------------------------

## Feeds [[level, ms], ...] at FRAME_MS and returns the event log with times.
func _run_vad(vad: RefCounted, clip: Array, partial_at_ms: float = -1.0, partial_text: String = "") -> Array:
	var events: Array = []
	var t: float = 0.0
	for frame: Array in clip:
		var left: float = float(frame[1])
		while left > 0.0:
			var dt: float = minf(FRAME_MS, left)
			if partial_at_ms >= 0.0 and t >= partial_at_ms and not partial_text.is_empty():
				vad.set_last_partial(partial_text)
				partial_text = ""
			for event: Variant in vad.feed(float(frame[0]), dt):
				events.append([String(event), t + dt])
			t += dt
			left -= dt
	return events


static func _names(events: Array) -> Array:
	var out: Array = []
	for e: Array in events:
		out.append(e[0])
	return out


func _test_vad_truth_table():
	var failures: Array = []
	var rows: Array = []
	# name, clip, expected event names, note
	rows.append(["answer 600 ms", SessionScript.preset_clip("answer"), ["speech_started", "speech_ended"]])
	rows.append(["cough 80 ms", SessionScript.preset_clip("cough"), ["burst_ignored"]])
	rows.append(["single spike frame", [[0.02, 200], [0.9, 20], [0.02, 1500]], ["burst_ignored"]])
	rows.append(["100 ms burst (below 120)", [[0.02, 200], [0.5, 100], [0.02, 1500]], ["burst_ignored"]])
	rows.append(["pause 700 ms mid-sentence", SessionScript.preset_clip("pause_then_finish"), ["speech_started", "speech_ended"]])
	rows.append(["silence 3.5 s", SessionScript.preset_clip("silence"), ["long_pause"]])
	rows.append(["two answers", [[0.02, 100], [0.35, 700], [0.02, 1200], [0.35, 700], [0.02, 1200]],
		["speech_started", "speech_ended", "speech_started", "speech_ended"]])
	print("    VAD truth table (child profile):")
	for row: Array in rows:
		var vad: RefCounted = VadScript.new()
		var events: Array = _run_vad(vad, row[1])
		var names: Array = _names(events)
		var ok: bool = names == row[2]
		print("      %-28s -> %s %s" % [row[0], str(events), "" if ok else "  EXPECTED " + str(row[2])])
		if not ok:
			failures.append("VAD '%s': events %s, expected %s" % [row[0], str(names), str(row[2])])
	# Timing details.
	var vad: RefCounted = VadScript.new()
	var answer: Array = _run_vad(vad, SessionScript.preset_clip("answer"))
	if answer.size() == 2:
		var start_t: float = float(answer[0][1])
		var end_t: float = float(answer[1][1])
		if absf(start_t - 320.0) > FRAME_MS:
			failures.append("speech starts 120 ms into the utterance (t=%.0f, expected ~320)" % start_t)
		if absf(end_t - (200.0 + 700.0 + 900.0)) > FRAME_MS:
			failures.append("a 700 ms utterance ends 900 ms after it goes quiet (t=%.0f, expected ~1800)" % end_t)
	# A SHORT utterance (< 600 ms) waits the extended 1600 ms.
	vad = VadScript.new()
	var short_clip: Array = [[0.02, 100], [0.35, 300], [0.02, 1300], [0.02, 600]]
	var short_events: Array = _run_vad(vad, short_clip)
	if short_events.size() != 2:
		failures.append("short utterance: %s" % str(short_events))
	else:
		var end_t: float = float(short_events[1][1])
		if end_t < 100.0 + 300.0 + 1600.0 - FRAME_MS:
			failures.append("a 300 ms utterance must wait 1600 ms of silence, ended at %.0f" % end_t)
	# A pause of 1200 ms after a short utterance resumes rather than ends.
	vad = VadScript.new()
	var resumed: Array = _run_vad(vad, [[0.02, 100], [0.35, 300], [0.02, 1200], [0.35, 700], [0.02, 1200]])
	if _names(resumed) != ["speech_started", "speech_ended"]:
		failures.append("a hesitant child (300 ms + 1.2 s pause + more words) is one utterance: %s" % str(resumed))
	# A trailing hesitation ("um") extends the window for a long utterance.
	vad = VadScript.new()
	var hesitant: Array = _run_vad(vad, [[0.02, 100], [0.35, 900], [0.02, 1300], [0.35, 700], [0.02, 1800]], 500.0, "it is um")
	if _names(hesitant) != ["speech_started", "speech_ended"]:
		failures.append("'...um' + 1.3 s pause + more words stays one utterance: %s" % str(hesitant))
	vad = VadScript.new()
	var plain: Array = _run_vad(vad, [[0.02, 100], [0.35, 900], [0.02, 1300], [0.35, 700], [0.02, 1800]], 500.0, "it is an apple")
	if _names(plain) != ["speech_started", "speech_ended", "speech_started", "speech_ended"]:
		failures.append("a finished sentence + 1.3 s pause is two utterances: %s" % str(plain))
	# Long pause repeats only after speech resets it, not every frame.
	vad = VadScript.new()
	var long_events: Array = _run_vad(vad, [[0.02, 7000]])
	if _names(long_events) != ["long_pause"]:
		failures.append("one long_pause per silence, got %s" % str(long_events))
	return failures


func _test_vad_echo_gate_and_floor():
	var failures: Array = []
	var vad: RefCounted = VadScript.new()
	# The maths.
	if VadScript.echo_gate_passes(0.5, 0.5, 0.08, 300.0, 200.0):
		failures.append("a level equal to the playback estimate is echo")
	if not VadScript.echo_gate_passes(0.7, 0.5, 0.08, 200.0, 200.0):
		failures.append("estimate + margin, held 200 ms, is the child")
	if VadScript.echo_gate_passes(0.7, 0.5, 0.08, 120.0, 200.0):
		failures.append("120 ms is not long enough under the gate")
	# Aliz speaking at ~0.5: her own echo (0.45..0.55) never starts speech.
	# The session primes the estimate the moment playback starts (before the
	# first echo reaches the mic), as `_speak()` does.
	vad.set_gated(true)
	vad.prime_playback_level(0.5)
	var echo_only: Array = []
	for i: int in range(150):  # 3 s
		vad.update_playback_level(0.5, FRAME_MS)
		var mic: float = 0.45 + 0.1 * float(i % 2)
		for event: Variant in vad.feed(mic, FRAME_MS):
			echo_only.append(String(event))
	if echo_only.has("speech_started"):
		failures.append("Aliz's own playback level must not read as the child under the echo gate: %s" % str(echo_only))
	if absf(vad.echo_estimate() - 0.5) > 0.05:
		failures.append("the playback estimate tracks the loudspeaker: %.2f" % vad.echo_estimate())
	if absf(vad.barge_in_threshold() - 0.58) > 0.06:
		failures.append("barge-in threshold = estimate + 0.08: %.2f" % vad.barge_in_threshold())
	# A louder child (0.9) for 900 ms is a barge-in, and only after 200 ms.
	var start_t: float = -1.0
	for i: int in range(45):
		vad.update_playback_level(0.5, FRAME_MS)
		for event: Variant in vad.feed(0.9, FRAME_MS):
			if String(event) == "speech_started" and start_t < 0.0:
				start_t = float(i + 1) * FRAME_MS
	if start_t < 0.0:
		failures.append("a child at 0.9 over playback at 0.5 must barge in")
	elif start_t < 200.0 - FRAME_MS:
		failures.append("barge-in needs 200 ms above the gate, fired at %.0f ms" % start_t)
	# Ungated, a 0.35 answer starts after 120 ms.
	var quiet: RefCounted = VadScript.new()
	var t: float = -1.0
	for i: int in range(30):
		for event: Variant in quiet.feed(0.35, FRAME_MS):
			if String(event) == "speech_started" and t < 0.0:
				t = float(i + 1) * FRAME_MS
	if absf(t - 120.0) > FRAME_MS:
		failures.append("ungated start after 120 ms, got %.0f" % t)
	# Noise floor adapts: a room at 0.1 (a fan) after a few seconds no longer
	# trips at 0.12, but a 0.3 voice still does.
	# (A fan starting causes at most one false start, which ends by itself.)
	var noisy: RefCounted = VadScript.new()
	var fan_events: Array = []
	for i: int in range(600):  # 12 s
		for event: Variant in noisy.feed(0.1, FRAME_MS):
			fan_events.append(String(event))
	if noisy.noise_floor() < 0.09:
		failures.append("the floor should rise towards a steady 0.1 room, got %.3f" % noisy.noise_floor())
	if fan_events.count("speech_started") > 1 or noisy.is_speech():
		failures.append("a fan is at most one short false start, then the floor: %s" % str(fan_events))
	var trips: Array = _names(_run_vad(noisy, [[0.12, 600], [0.1, 1500]]))
	if trips.has("speech_started"):
		failures.append("0.12 over a 0.1 floor is the room, not speech: %s" % str(trips))
	var voice: Array = _names(_run_vad(noisy, [[0.3, 600], [0.1, 1500]]))
	if voice != ["speech_started", "speech_ended"]:
		failures.append("0.3 over a 0.1 floor is speech: %s" % str(voice))
	return failures


# ---------------------------------------------------------------------------
# Session harness
# ---------------------------------------------------------------------------

func _make(lesson_id: String = "animals_cat_dog", with_transport: bool = false) -> Dictionary:
	var engine: RefCounted = LessonEngineScript.new()
	engine.load_lesson(lesson_id)
	var voice := FakeVoice.new()
	var synth: Node = SynthScript.new()
	synth.set_voice(voice)
	var blank := Node.new()
	synth.set_tts(blank)
	var recognition: RefCounted = RecognitionScript.new()
	recognition.set_simulation_enabled(true)
	var face := FakeFace.new()
	var provider: RefCounted = ScriptedScript.new()
	provider.set_engine(engine)
	var session: RefCounted = SessionScript.new()
	session.set_engine(engine)
	session.set_conversation_provider(provider)
	session.set_recognition_provider(recognition)
	session.set_synthesis_provider(synth)
	session.set_face(face)
	var transport: RefCounted = null
	if with_transport:
		transport = MockTransportScript.new()
		transport.set_engine(engine)
		session.set_transport(transport)
	var log := Log.new()
	log.attach(session)
	return {"engine": engine, "voice": voice, "synth": synth, "blank": blank, "recognition": recognition,
		"face": face, "provider": provider, "session": session, "log": log, "transport": transport}


func _free(h: Dictionary) -> void:
	(h["synth"] as Node).free()
	(h["voice"] as Node).free()
	(h["blank"] as Node).free()


## Runs `seconds` of session time in FRAME_MS steps; finishes Aliz's fake
## voice line after `voice_after` seconds of her speaking (the recorded line
## "ends").
func _run(h: Dictionary, seconds: float, voice_after: float = 0.4) -> void:
	var session: RefCounted = h["session"]
	var voice: FakeVoice = h["voice"]
	var left: float = seconds
	var speaking_for: float = 0.0
	while left > 0.0:
		var dt: float = minf(FRAME_MS / 1000.0, left)
		if voice.is_speaking():
			speaking_for += dt
			if speaking_for >= voice_after:
				speaking_for = 0.0
				voice.finish()
		else:
			speaking_for = 0.0
		session.advance(dt)
		left -= dt


func _test_mic_scope():
	var failures: Array = []
	var h: Dictionary = _make()
	var session: RefCounted = h["session"]
	var log: Log = h["log"]
	if session.is_capturing() or session.is_active() or session.get_state() != "idle":
		failures.append("a new session captures nothing")
	# No gate: refused, nothing opens.
	if session.start("animals_cat_dog", {}):
		failures.append("start without gatePassed must be refused")
	if log.ended != ["gate_required"] or session.is_capturing():
		failures.append("the gate refusal is reported and captures nothing: %s" % str(log.ended))
	# With the gate: welcoming speaks first; capture starts only when listening.
	session.set_level_source(func() -> float: return 0.02)
	if not session.start("animals_cat_dog", {"gatePassed": true}):
		failures.append("start with the gate")
	if session.get_state() != "welcoming":
		failures.append("after start Aliz welcomes, got %s" % session.get_state())
	if session.is_capturing():
		failures.append("no capture while welcoming (Aliz is speaking, the child has not been asked)")
	_run(h, 1.5)  # the welcome line ends; the teach step advances; the question is asked
	if session.get_state() != "listening":
		failures.append("after the question the session listens, got %s (history %s)" % [session.get_state(), str(log.states)])
	if not session.is_capturing():
		failures.append("listening captures")
	# Mute stops capture at once; unmute resumes.
	session.mute(true)
	if session.is_capturing() or session.get_input_level() != 0.0:
		failures.append("mute stops capture and zeroes the indicator")
	session.mute(false)
	if not session.is_capturing():
		failures.append("unmute resumes listening capture")
	# Thinking does not capture.
	session.simulate_child_audio(SessionScript.preset_clip("answer"), "cat")
	var saw_thinking_capture: bool = false
	var saw_thinking: bool = false
	for i: int in range(120):
		session.advance(FRAME_MS / 1000.0)
		if session.get_state() == "thinking":
			saw_thinking = true
			if session.is_capturing():
				saw_thinking_capture = true
	if saw_thinking_capture:
		failures.append("thinking must not capture")
	# Background ends everything; foreground reopens nothing.
	session.on_app_background()
	if session.is_active() or session.is_capturing() or session.get_state() != "ended" or log.ended.back() != "background":
		failures.append("background stops capture and ends the session: %s / %s" % [session.get_state(), str(log.ended)])
	session.on_app_foreground()
	session.advance(0.5)
	if session.is_active() or session.is_capturing():
		failures.append("foreground must never reopen the microphone")
	if (h["recognition"] as RefCounted).has_active_session():
		failures.append("no recogniser session survives the end")
	# Quota expiry and stop() end it too.
	var h2: Dictionary = _make()
	var s2: RefCounted = h2["session"]
	s2.set_level_source(func() -> float: return 0.02)
	s2.start("animals_cat_dog", {"gatePassed": true})
	_run(h2, 1.5)
	s2.on_quota_expired()
	if s2.is_capturing() or (h2["log"] as Log).ended != ["quota_expired"]:
		failures.append("quota expiry stops capture: %s" % str((h2["log"] as Log).ended))
	s2.stop()
	if (h2["log"] as Log).ended.size() != 1:
		failures.append("stop after end is a no-op")
	# Capture flips are reported.
	if not log.captures.has(true) or log.captures.back() != false:
		failures.append("capture_changed reports on and finally off: %s" % str(log.captures))
	_free(h)
	_free(h2)
	return failures


func _test_hands_free_turn_and_reprompt():
	var failures: Array = []
	var h: Dictionary = _make()
	var session: RefCounted = h["session"]
	var log: Log = h["log"]
	var voice: FakeVoice = h["voice"]
	session.set_level_source(func() -> float: return 0.02)
	session.start("animals_cat_dog", {"gatePassed": true})
	_run(h, 1.5)
	if voice.spoken.size() < 2 or voice.spoken[0] != "Yay! Let's learn about animals!" or voice.spoken[1] != "What animal is this?":
		failures.append("welcome then the first question through the voice: %s" % str(voice.spoken))
	# A full hands-free turn: levels -> child_speaking -> transcript -> thinking -> aliz_speaking.
	session.simulate_child_audio(SessionScript.preset_clip("answer"), "a cat")
	_run(h, 3.0)
	var expected: Array = ["welcoming", "listening", "child_speaking", "thinking", "aliz_speaking"]
	if log.states.slice(0, 5) != expected:
		failures.append("hands-free turn states %s, expected prefix %s" % [str(log.states), str(expected)])
	if not log.events.has("child_speech_ended:a cat"):
		failures.append("the transcript arrives through child_speech_ended: %s" % str(log.events))
	if voice.spoken.size() < 3 or not String(voice.spoken[2]).contains("It's a cat!"):
		failures.append("Aliz praises the cat: %s" % str(voice.spoken))
	# After her answer the next question opens and she listens again.
	if session.get_state() != "listening" or not String(voice.spoken.back()).contains("cat sound"):
		failures.append("after the praise the sound question is asked and she listens: %s / %s" % [session.get_state(), str(voice.spoken)])
	# A cough produces nothing.
	var before: int = voice.spoken.size()
	session.simulate_child_audio(SessionScript.preset_clip("cough"), "meow")
	_run(h, 2.0)
	if voice.spoken.size() != before or session.get_state() != "listening" or log.events.has("child_speech_ended:meow"):
		failures.append("a cough must not produce a turn: spoken %d->%d state %s" % [before, voice.spoken.size(), session.get_state()])
	if int((h["engine"] as RefCounted).attempts()) != 0:
		failures.append("a cough is not an attempt")
	# A long pause re-prompts (the same question, locally), never a reply.
	var provider_turns_before: int = log.turns.size()
	_run(h, 3.5)
	if session.reprompt_count() != 1:
		failures.append("3 s of silence re-prompts once, got %d" % session.reprompt_count())
	if String(voice.spoken.back()) != "Can you make a cat sound?":
		failures.append("the re-prompt is the question again: %s" % voice.spoken.back())
	if int((h["engine"] as RefCounted).attempts()) != 0:
		failures.append("a re-prompt is not an attempt")
	if session.get_state() != "listening":
		failures.append("after the re-prompt she listens again: %s" % session.get_state())
	# Heard speech, no words decoded -> gentle "Let's try together!" (an unclear attempt).
	session.simulate_child_audio(SessionScript.preset_clip("answer"), "")
	_run(h, 3.0)
	if not String(voice.spoken.back()).begins_with("Let's try together"):
		failures.append("speech with nothing decoded is a gentle retry: %s" % voice.spoken.back())
	if int((h["engine"] as RefCounted).attempts()) != 1:
		failures.append("undecoded speech counts one unclear attempt, got %d" % int((h["engine"] as RefCounted).attempts()))
	print("    hands-free turn states: %s" % " -> ".join(PackedStringArray(log.states)))
	_free(h)
	return failures


func _test_barge_in():
	var failures: Array = []
	var h: Dictionary = _make("animals_cat_dog", true)
	var session: RefCounted = h["session"]
	var log: Log = h["log"]
	var voice: FakeVoice = h["voice"]
	var face: FakeFace = h["face"]
	var transport: RefCounted = h["transport"]
	session.set_level_source(func() -> float: return 0.02)
	session.start("animals_cat_dog", {"gatePassed": true})
	_run(h, 1.5)  # listening at "What animal is this?"
	# Answer through the transport: the reply streams; interrupt it mid-stream.
	session.simulate_child_audio(SessionScript.preset_clip("answer"), "a cat")
	_run(h, 2.3, 99.0)  # the reply is STREAMING over the transport (first delta ~2.0 s)
	if session.get_state() != "aliz_speaking" or not transport.is_responding():
		failures.append("Aliz should be speaking her streamed praise, got %s responding=%s (%s)" % [session.get_state(), str(transport.is_responding()), str(log.states)])
	if transport.sent_texts() != ["a cat"]:
		failures.append("the transcript went to the transport: %s" % str(transport.sent_texts()))
	var stops_before: int = voice.stops
	face.calls.clear()
	var t0: int = Time.get_ticks_usec()
	session.simulate_child_audio(SessionScript.preset_clip("interrupt"), "Wait! I want a dog!")
	# Feed until the barge-in fires (the echo gate needs 200 ms above the estimate).
	var fired_at_ms: float = -1.0
	var elapsed: float = 0.0
	while elapsed < 1.0 and fired_at_ms < 0.0:
		session.advance(FRAME_MS / 1000.0)
		elapsed += FRAME_MS / 1000.0
		if log.events.has("barge_in"):
			fired_at_ms = elapsed * 1000.0
	if fired_at_ms < 0.0:
		failures.append("a loud child over Aliz must barge in; events %s" % str(log.events))
		_free(h)
		return failures
	if fired_at_ms < 200.0 - FRAME_MS:
		failures.append("barge-in must wait for 200 ms above the echo gate, fired at %.0f ms" % fired_at_ms)
	var timing: Dictionary = session.last_barge_in_timing()
	if voice.spoken.size() != 2:
		failures.append("a reply cancelled mid-stream is never voiced: %s" % str(voice.spoken))
	if float(timing.get("toMouthZeroMs", 999.0)) > 120.0 or float(timing.get("toVoiceStopMs", 999.0)) > 120.0:
		failures.append("mouth 0 and Voice.stop within 120 ms: %s" % str(timing))
	if face.speaking:
		failures.append("set_speaking(false) on barge-in")
	if not face.calls.has("expression:listening") or not face.calls.has("gesture:tilt"):
		failures.append("barge-in turns Aliz to listen with a tilt: %s" % str(face.calls))
	if transport.cancel_count() != 1:
		failures.append("the transport response is cancelled once, got %d" % transport.cancel_count())
	var streamed_at_cancel: String = transport.streamed_text()
	if session.get_state() != "child_speaking":
		failures.append("after the interruption the child is being captured: %s" % session.get_state())
	print("    barge-in timing: fired %.0f ms after the child started; Voice.stop after %.3f ms; mouth 0 after %.3f ms"
			% [fired_at_ms, float(timing.get("toVoiceStopMs", -1.0)), float(timing.get("toMouthZeroMs", -1.0))])
	# The interjection is honoured: jump to the dog; no overlap, no replay.
	_run(h, 3.0)
	if not log.events.has("child_speech_ended:Wait! I want a dog!"):
		failures.append("the interrupting words are captured: %s" % str(log.events))
	var dog_turn: Dictionary = {}
	for turn: Dictionary in log.turns:
		if String(turn.get("lessonAction", "")) == "jump_step":
			dog_turn = turn
	if dog_turn.is_empty() or String(dog_turn.get("nextStepId", "")) != "s04_dog":
		failures.append("'Wait! I want a dog!' becomes a jump to the dog: %s" % str(log.turns))
	if transport.streamed_text() != streamed_at_cancel and transport.is_responding():
		failures.append("cancelled deltas must never resume")
	if transport.dropped_words() <= 0:
		failures.append("the unplayed part of the cancelled reply is dropped, not replayed")
	var overlaps: int = 0
	var speaking_depth: int = 0
	for event: Variant in log.events:
		if String(event).begins_with("aliz:"):
			speaking_depth += 1
	if voice.spoken.size() != log.turns.size():
		failures.append("every Aliz turn is exactly one voice line (no overlapping replies): %d lines for %d turns" % [voice.spoken.size(), log.turns.size()])
	# A second barge-in, this time on a VOICED line: Voice.stop() is called.
	_run(h, 2.0)
	session.simulate_child_audio(SessionScript.preset_clip("answer"), "a dog")
	_run(h, 3.6, 99.0)
	var stops_before_voice: int = voice.stops
	session.simulate_child_audio(SessionScript.preset_clip("interrupt"), "stop")
	_run(h, 1.0, 99.0)
	if voice.stops != stops_before_voice + 1:
		failures.append("a barge-in on a voiced line stops the voice exactly once: %d -> %d" % [stops_before_voice, voice.stops])
	var idx: int = log.states.find("interrupted")
	if idx < 0 or log.states[idx - 1] != "aliz_speaking" or log.states[idx + 1] != "child_speaking":
		failures.append("state path around the interruption is aliz_speaking -> interrupted -> child_speaking: %s" % str(log.states))
	print("    barge-in states: %s" % " -> ".join(PackedStringArray(log.states)))
	# Mute during Aliz speaking disables barge-in (no capture).
	_free(h)
	return failures


# ---------------------------------------------------------------------------
# Transports
# ---------------------------------------------------------------------------

func _test_mock_transport():
	var failures: Array = []
	var engine: RefCounted = LessonEngineScript.new()
	engine.load_lesson("english_colors_fruits")
	engine.advance()
	var transport: RefCounted = MockTransportScript.new()
	transport.set_engine(engine)
	var deltas: Array = []
	var levels: Array = []
	var done: Array = []
	var cancelled: Array = []
	transport.response_text_delta.connect(func(t: String) -> void: deltas.append(t))
	transport.response_audio_delta.connect(func(l: float, _b: int) -> void: levels.append(l))
	transport.response_done.connect(func(turn: Dictionary) -> void: done.append(turn))
	transport.response_cancelled.connect(func() -> void: cancelled.append(true))
	if transport.send_text("apple"):
		failures.append("send_text before connect is refused")
	transport.connect_session({"lessonId": "english_colors_fruits"})
	transport.advance(0.1)
	if not transport.is_connected_session():
		failures.append("the mock connects after its short delay")
	if not transport.send_text("apple", {"phase": "answer"}):
		failures.append("send_text on an open mock succeeds")
	transport.advance(0.19)
	if deltas.size() != 1:
		failures.append("one word per 180 ms: %s" % str(deltas))
	transport.advance(5.0)
	if done.size() != 1 or not TurnValidator.is_valid(done[0]):
		failures.append("response_done with a valid turn: %s" % str(done))
	var expected_text: String = String(done[0].get("speech", "")) if not done.is_empty() else ""
	if " ".join(PackedStringArray(deltas)) != expected_text:
		failures.append("the deltas spell the turn: '%s' vs '%s'" % [" ".join(PackedStringArray(deltas)), expected_text])
	var distinct: Dictionary = {}
	for l: float in levels:
		distinct[snappedf(l, 0.01)] = true
	if distinct.size() < 2:
		failures.append("the envelope varies across words (not a metronome): %s" % str(levels))
	for l: float in levels:
		if l < 0.4 or l > 0.9:
			failures.append("envelope levels are 0.45..0.85: %f" % l)
	# Determinism: same input, same stream.
	var again: RefCounted = MockTransportScript.new()
	var e2: RefCounted = LessonEngineScript.new()
	e2.load_lesson("english_colors_fruits")
	e2.advance()
	again.set_engine(e2)
	var deltas2: Array = []
	again.response_text_delta.connect(func(t: String) -> void: deltas2.append(t))
	again.connect_session({"lessonId": "english_colors_fruits"})
	again.advance(0.1)
	again.send_text("apple", {"phase": "answer"})
	again.advance(5.0)
	if deltas2 != deltas:
		failures.append("the mock transport is deterministic")
	# Cancel drops the rest, once.
	engine.advance()
	transport.send_text("red", {"phase": "answer"})
	transport.advance(0.19)
	transport.cancel()
	transport.cancel()
	if cancelled.size() != 1 or transport.is_responding():
		failures.append("cancel stops the response once: %s" % str(cancelled))
	var words_before: int = deltas.size()
	transport.advance(5.0)
	if deltas.size() != words_before or done.size() != 1:
		failures.append("no deltas and no done after a cancel (never replayed)")
	if transport.dropped_words() <= 0:
		failures.append("dropped words are counted")
	transport.close()
	if transport.is_connected_session():
		failures.append("close closes")
	return failures


func _test_cloud_transport_gated():
	var failures: Array = []
	if TutorFlags.cloud_enabled():
		return ["this suite must run with the cloud flag OFF"]
	var transport: RefCounted = CloudTransportScript.new()
	var errors: Array = []
	transport.error.connect(func(code: String, _m: String) -> void: errors.append(code))
	if transport.is_available():
		failures.append("the cloud transport is unavailable while the flag is off")
	var token: Dictionary = {"clientSecret": {"value": "ek_test", "expiresAt": 0}, "wsUrl": "wss://example.invalid/v1/realtime",
		"subprotocols": ["realtime"], "sessionUpdate": {"type": "session.update", "session": {"type": "realtime"}}}
	if transport.connect_session(token):
		failures.append("connect_session must refuse with the flag off")
	if errors != ["cloud_disabled"]:
		failures.append("the refusal reason is cloud_disabled: %s" % str(errors))
	if transport.send_text("hello") or transport.is_connected_session():
		failures.append("nothing is sent while closed")
	# The contract's token shape is refused the same way (the flag is read first).
	if transport.connect_session({"token": "mock-rt-x", "url": "wss://example.invalid/v1/realtime", "expiresAt": "2026-09-21T00:00:00Z"}):
		failures.append("connect_session (contract token) must refuse with the flag off")
	if errors != ["cloud_disabled", "cloud_disabled"]:
		failures.append("both refusals are cloud_disabled: %s" % str(errors))
	if transport.send_audio(PackedByteArray([0, 0])) or not transport.sent_events().is_empty():
		failures.append("no event may leave a transport that never opened")
	transport.advance(1.0)
	# build_turn keeps the engine's action and validates the words.
	var turn: Dictionary = CloudTransportScript.build_turn("Great! It's a cat!", {"outcome": "correct", "lessonAction": "next_question", "visualAssetId": "cat"})
	if String(turn.get("lessonAction", "")) != "next_question" or turn.get("visual", {}) != {"type": "flashcard", "assetId": "cat"} or String(turn["emotion"]) != "happy":
		failures.append("build_turn: %s" % str(turn))
	var bad: Dictionary = CloudTransportScript.build_turn("Visit https://example.com", {"outcome": "correct", "lessonAction": "next_question"})
	if bad != TurnValidator.fallback_turn():
		failures.append("a model reply with a URL becomes the fallback: %s" % str(bad))
	# RMS envelope maths.
	var silence: PackedByteArray = PackedByteArray()
	silence.resize(480)
	if CloudTransportScript.pcm16_rms(silence) != 0.0:
		failures.append("silent PCM has RMS 0")
	var loud: PackedByteArray = PackedByteArray()
	loud.resize(4)
	loud.encode_s16(0, 16384)
	loud.encode_s16(2, -16384)
	if absf(CloudTransportScript.pcm16_rms(loud) - 0.5) > 0.01:
		failures.append("RMS of +-0.5 is 0.5, got %f" % CloudTransportScript.pcm16_rms(loud))
	# Source-order + address hygiene (the privacy guard's rule, restated here).
	var code: String = _strip_comments((CloudTransportScript as GDScript).source_code)
	var flag_at: int = code.find("cloud_enabled()")
	var sock_at: int = code.find("WebSocketPeer")
	if flag_at < 0 or sock_at < 0 or flag_at > sock_at:
		failures.append("cloud transport must read cloud_enabled() before WebSocketPeer (flag %d, socket %d)" % [flag_at, sock_at])
	for needle: String in ["wss://", "https://", "api_key", "Bearer ", "openai"]:
		if code.to_lower().contains(needle.to_lower()):
			failures.append("cloud transport carries '%s'; addresses, headers and vendor names come from the backend token" % needle)
	for needle: String in ["AudioStreamMicrophone", "AudioEffectRecord"]:
		for script: GDScript in [CloudTransportScript, MockTransportScript, SessionScript, VadScript]:
			if (script as GDScript).source_code.contains(needle):
				failures.append("%s in %s: the game never opens the microphone itself" % [needle, script.resource_path])
	return failures


# ---------------------------------------------------------------------------
# The owner's dialogue, hands-free
# ---------------------------------------------------------------------------

func _test_owner_dialogue():
	var failures: Array = []
	var entry: String = String(LessonEngineScript.entry_lesson_id())
	var h: Dictionary = _make(entry)
	var session: RefCounted = h["session"]
	var voice: FakeVoice = h["voice"]
	var log: Log = h["log"]
	var engine: RefCounted = h["engine"]
	session.set_level_source(func() -> float: return 0.02)
	session.start(entry, {"gatePassed": true})
	var script: Array = []
	var say: Callable = func(text: String, seconds: float = 3.0) -> void:
		var waited: float = 0.0
		while session.get_state() != "listening" and waited < 6.0:
			_run(h, 0.1)
			waited += 0.1
		session.simulate_child_audio(SessionScript.preset_clip("answer"), text)
		script.append("child: %s" % text)
		_run(h, seconds)
	say.call("I want to learn about animals!")
	say.call("It's a cat!")
	say.call("Meow!")
	# While Aliz speaks the dog question... she has just asked it; interrupt
	# the NEXT line instead: answer, then barge in on the praise.
	var lines: Array = voice.spoken.duplicate()
	var expected_lines: Array = [
		"Hi! What would you like to learn today?",
		"Yay! Animals!",
		"Yay! Let's learn about animals!",
		"What animal is this?",
		"Great! It's a cat!",
		"Can you make a cat sound?",
		"Meow! You're amazing!",
		"What animal is this?",
	]
	# Line 4 carries ONE praise opener: the rotation may replace the lesson's
	# "Great!" ("Wonderful! It's a cat!"), never stack on it ("Yes! Great! ...").
	for i: int in range(expected_lines.size()):
		var got: String = String(lines[i]) if i < lines.size() else "<none>"
		var want: String = expected_lines[i]
		if i == 4:
			want = "It's a cat!"
		if not got.ends_with(want):
			failures.append("owner dialogue line %d: got '%s', expected '%s'" % [i, got, expected_lines[i]])
		if TurnValidator.dedupe_adjacent_phrases(got) != got:
			failures.append("owner dialogue line %d carries a doubled phrase: '%s'" % [i, got])
		var openers: int = 0
		for sentence: String in TurnValidator.split_sentences(got):
			if TurnValidator.is_acknowledgement(TurnValidator.phrase_key(sentence)):
				openers += 1
		if openers > 1:
			failures.append("owner dialogue line %d has %d openers: '%s'" % [i, openers, got])
	if String(engine.lesson_id()) != "animals_cat_dog":
		failures.append("the choice switched into the animals lesson: %s" % engine.lesson_id())
	var meow_turn: Dictionary = {}
	for turn: Dictionary in log.turns:
		if String(turn.get("speech", "")) == "Meow! You're amazing!":
			meow_turn = turn
	if meow_turn.is_empty() or String(meow_turn.get("gesture", "")) != "clap" or String(meow_turn.get("wantsSfx", "")) != "laugh":
		failures.append("the meow reaction claps and wants the laugh sfx: %s" % str(meow_turn))
	# Barge-in on a long line: say "dog" then interrupt the dog praise with a request for the cat again.
	var waited: float = 0.0
	while session.get_state() != "listening" and waited < 6.0:
		_run(h, 0.1)
		waited += 0.1
	session.simulate_child_audio(SessionScript.preset_clip("answer"), "a dog")
	_run(h, 2.6, 99.0)
	if session.get_state() != "aliz_speaking":
		failures.append("Aliz is praising the dog: %s" % session.get_state())
	session.simulate_child_audio(SessionScript.preset_clip("interrupt"), "Wait! I want the cat!")
	_run(h, 3.5)
	if not log.events.has("barge_in"):
		failures.append("the child interrupted Aliz: %s" % str(log.events))
	var jumped: bool = false
	for turn: Dictionary in log.turns:
		if String(turn.get("lessonAction", "")) == "jump_step" and String(turn.get("nextStepId", "")).begins_with("s0") :
			jumped = true
	if not jumped:
		failures.append("'Wait! I want the cat!' during her speech jumps to the cat: %s" % str(log.turns))
	print("    owner dialogue, hands-free (Aliz lines in order):")
	for line: String in voice.spoken:
		print("      Aliz: %s" % line)
	print("    owner dialogue states: %s" % " -> ".join(PackedStringArray(log.states)))
	_free(h)
	return failures


func _test_recognizer_driven_mode():
	var failures: Array = []
	# No level source (this Mac): the recogniser is re-armed after each turn.
	var h: Dictionary = _make()
	var session: RefCounted = h["session"]
	var recognition: RefCounted = h["recognition"]
	var voice: FakeVoice = h["voice"]
	var opened: Array = []
	recognition.state_changed.connect(func(_f: String, t: String) -> void:
		if t == "start":
			opened.append(true))
	session.start("animals_cat_dog", {"gatePassed": true})
	if not session.is_recognizer_driven():
		failures.append("without a level source the session is recogniser-driven")
	_run(h, 1.5)
	if session.get_state() != "listening" or opened.size() != 1:
		failures.append("listening opens the recogniser once (no level source): %s / %d" % [session.get_state(), opened.size()])
	if recognition.begin_listening():
		failures.append("the recogniser session is already open")
	# The simulated transcript arrives as a real final would.
	recognition.simulated_transcript("a cat")
	_run(h, 2.0)
	if voice.spoken.size() < 3 or not String(voice.spoken[2]).contains("cat"):
		failures.append("recogniser-driven turn answered: %s" % str(voice.spoken))
	if session.get_state() != "listening" or opened.size() != 2:
		failures.append("after Aliz's answer and the next question the recogniser is re-armed: %s / %d" % [session.get_state(), opened.size()])
	# A recogniser timeout with nothing said is a re-prompt, not an attempt.
	recognition.simulated_silence()
	_run(h, 1.5)
	if session.reprompt_count() != 1 or int((h["engine"] as RefCounted).attempts()) != 0:
		failures.append("recogniser timeout -> re-prompt (%d), no attempt (%d)" % [session.reprompt_count(), int((h["engine"] as RefCounted).attempts())])
	if not recognition.has_active_session():
		failures.append("after the re-prompt the recogniser listens again")
	session.stop()
	if recognition.has_active_session():
		failures.append("stop closes the recogniser")
	print("    recogniser-driven states: %s" % " -> ".join(PackedStringArray((h["log"] as Log).states)))
	_free(h)
	return failures


func _test_profile_and_guards():
	var failures: Array = []
	var profile: Dictionary = VadScript.load_profile()
	if int(profile.get("speechStart", {}).get("minDurationMs", 0)) != 120:
		failures.append("vad_profile_child.json: speechStart.minDurationMs = 120")
	if int(profile.get("speechEnd", {}).get("silenceMs", 0)) != 900 or int(profile.get("speechEnd", {}).get("extendedSilenceMs", 0)) != 1600:
		failures.append("vad_profile_child.json: end silence 900 / 1600")
	if int(profile.get("longPauseMs", 0)) != 3000:
		failures.append("vad_profile_child.json: longPauseMs = 3000")
	if int(profile.get("echoGate", {}).get("holdMs", 0)) != 200:
		failures.append("vad_profile_child.json: echoGate.holdMs = 200")
	if profile == VadScript.DEFAULT_PROFILE:
		pass  # identical by design
	# The session itself never opens audio or a network.
	var code: String = _strip_comments((SessionScript as GDScript).source_code)
	for needle: String in ["HTTPClient", "HTTPRequest", "WebSocketPeer", "AudioStreamMicrophone", "start_listening("]:
		if code.contains(needle):
			failures.append("tutor_voice_session.gd must not contain %s (it goes through the providers)" % needle)
	return failures


static func _strip_comments(source: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at < 0 else line.left(hash_at))
	return "\n".join(out)
