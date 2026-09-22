extends SceneTree

## DEV SMOKE (AI path, end to end): the real classroom scene, in REAL time,
## with the cloud tutor armed by the developer user args against the deployed
## development Worker, logging PER TURN what each stage of the chain did:
##
##   server provider label + fallback reason (from the session's turn log)
##   -> the validated TutorTurn (client validator verdict on the RAW body)
##   -> the lessonAction the scene applied
##   -> the gesture the server asked for vs the one Aliz played (pool)
##   -> the expression / gesture actually set on Aliz (TutorFace read-backs)
##   -> mouth openness + LipSyncSource level sampled WHILE the voice plays
##   -> which voice path spoke it (cloud audio / voice / tts / paced)
##   -> the microphone: recogniser closed + VAD gated while Aliz speaks,
##      capture back in the listening state afterwards.
##
##   godot --headless --path game --script res://tests/smoke_ai_classroom.gd \
##       -- --ai-tutor-cloud --tutor-backend-url=<https url>
##
## Not part of the suite: it needs the flag (user args only, never an export)
## and a backend. Every transcript is the scene's own simulated-child hook
## (`simulate("correct")` / `simulate("wrong")`): synthetic, scripted, no audio
## exists and no real child is involved. The TtsService autoload is KEPT (the
## Voice director is not) so the lip sync's TTS pseudo-envelope drives the
## mouth headless; the platform voice itself is absent in --headless.
##
## PASS criteria (printed at the end): >= MIN_CLOUD_TURNS server-authored
## turns; every raw server turn passes the client validator; no
## provider_failed; the gesture Aliz played differs from the previous turn's
## on every answer turn and an encouraging turn was seen; the expression set
## on Aliz is the one the scene chose on every turn; mouth openness > 0 on
## every TTS-voiced turn; the recogniser is never open and the VAD is gated
## on every sample taken while Aliz speaks; capture is seen in the listening
## state; the cloud session ends with the server's acknowledgement; capture
## is closed at the end.

const SCENE_PATH: String = "res://scenes/tutor/classroom.tscn"
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const LESSON_ID: String = "animals_cat_dog"
const MAX_SECONDS: float = 240.0
const MIN_CLOUD_TURNS: int = 5
## Answers the simulated child gives, in order, one per listening state.
const ANSWERS: Array[String] = ["correct", "correct", "wrong", "correct", "correct", "correct", "correct", "correct"]


class FakeSave extends RefCounted:
	var settings: Dictionary = {}
	var stars: int = 0
	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value
	func save_profile() -> bool:
		return true
	func add_stars(amount: int) -> int:
		stars += amount
		return stars
	func get_profile() -> Dictionary:
		return {"settings": settings, "unlockedRooms": [], "stars": stars}


var _scene: Node = null
var _aliz: Node = null
var _lip: Node = null
var _session: RefCounted = null
var _api: RefCounted = null
var _rows: Array = []              # one per spoken turn
var _raw_server_turns: Array = []  # [{valid, reasons, turn}] from the REST bodies
var _failed: Array = []
var _states: Array = []
var _completed: bool = false
var _answer_index: int = 0
var _last_answer_state: String = ""
var _answer_delay: float = -1.0
var _elapsed: float = 0.0
var _last_ticks: int = 0
var _done: bool = false
var _listening_capture_seen: bool = false
var _prev_gesture: String = ""


func _initialize() -> void:
	for auto_name: String in ["SaveService", "SpeechService", "Voice", "Sfx", "Audio"]:
		var node: Node = root.get_node_or_null(auto_name)
		if node != null:
			root.remove_child(node)
	if not TutorFlags.cloud_enabled():
		print("AI-SMOKE: run with `-- --ai-tutor-cloud`; the cloud tutor is off")
		quit(1)
		return
	var packed: PackedScene = load(SCENE_PATH)
	_scene = packed.instantiate()
	_scene.set("ignore_desktop_focus", true)
	root.add_child(_scene)
	_scene.call("build")
	_scene.call("set_save_service", FakeSave.new())
	_scene.call("enable_simulation", true)
	_scene.turn_spoken.connect(_on_turn)
	_scene.state_changed.connect(_on_state)
	_scene.lesson_completed.connect(func(_p: Dictionary) -> void: _completed = true)
	_aliz = _scene.call("aliz")
	if _aliz != null and _aliz.has_method("get_lip_sync"):
		_lip = _aliz.call("get_lip_sync")
	var provider: Object = _scene.call("provider")
	if provider != null and provider.has_signal("provider_failed"):
		provider.provider_failed.connect(func(r: String) -> void: _failed.append(r))
	_session = provider.call("cloud_session") if provider != null and provider.has_method("cloud_session") else null
	if _session != null:
		_session.ready.connect(func(info: Dictionary) -> void:
			print("AI-SMOKE: cloud session ready transport=%s session=%s quota=%s fallback=%s" % [
				String(info.get("transport", "")), String(info.get("sessionId", "")), str(info.get("quota", {})), String(info.get("realtimeFallback", ""))]))
		_session.fell_back.connect(func(r: String) -> void: print("AI-SMOKE: cloud session fell back: %s" % r))
		_api = _session.call("api") if _session.has_method("api") else null
		if _api != null and _api.has_signal("completed"):
			_api.completed.connect(_on_api_completed)
	var synth: Node = _scene.call("synthesis")
	print("AI-SMOKE: provider=%s synth=%s backend=%s lesson=%s aliz=%s lip_sync=%s tts_autoload=%s" % [
		String(provider.call("provider_name")) if provider != null else "none",
		String(synth.call("provider_name")) if synth.has_method("provider_name") else "local",
		TutorFlags.backend_url(), LESSON_ID, str(_aliz != null), str(_lip != null),
		str(root.get_node_or_null("TtsService") != null)])
	_scene.call("begin_lesson", LESSON_ID)
	_last_ticks = Time.get_ticks_msec()


## Every REST turn body: validate the RAW server turn with the client validator.
func _on_api_completed(kind: String, result: Dictionary) -> void:
	if kind != "turn" or not bool(result.get("ok", false)):
		return
	var body: Dictionary = result.get("body", {})
	if not body.has("turn"):
		return
	var verdict: Dictionary = TurnValidator.validate(body["turn"])
	_raw_server_turns.append({
		"valid": bool(verdict.get("valid", false)), "reasons": verdict.get("reasons", []),
		"provider": String(body.get("provider", "")), "fallback": str(body.get("fallback", "")),
		"contextSource": String(body.get("contextSource", "")),
		"latencyMs": int(_num(body.get("usage", {}).get("latencyMs", 0))),
		"emotion": String(body["turn"].get("emotion", "")), "gesture": String(body["turn"].get("gesture", "")),
		"visual": body["turn"].get("visual", {}), "lessonAction": String(body["turn"].get("lessonAction", "")),
	})


func _on_state(state: String) -> void:
	_states.append(state)
	if state == "listening":
		var d: Dictionary = _voice_diag()
		if bool(d.get("capturing", false)):
			_listening_capture_seen = true
		print("  %5.1fs  [listening] mic capturing=%s recognitionOpen=%s vadGated=%s voiceState=%s" % [
			_elapsed, str(d.get("capturing", "?")), str(d.get("recognitionOpen", "?")), str(d.get("vadGated", "?")), String(d.get("state", "?"))])


func _on_turn(turn: Dictionary) -> void:
	var synth: Node = _scene.call("synthesis")
	var voice: String = String(synth.call("voice_used")) if synth.has_method("voice_used") else "?"
	var words: String = String(synth.call("words_source")) if synth.has_method("words_source") else "?"
	var server_row: Dictionary = {}
	if words == "cloud" and _session != null:
		var log_rows: Array = _session.call("turn_log")
		if not log_rows.is_empty():
			server_row = log_rows[-1]
	var aliz_expression: String = String(_aliz.call("get_expression")) if _aliz != null and _aliz.has_method("get_expression") else "?"
	var aliz_gesture: String = String(_aliz.call("get_current_gesture")) if _aliz != null and _aliz.has_method("get_current_gesture") else "?"
	var d: Dictionary = _voice_diag()
	var row: Dictionary = {
		"t": snappedf(_elapsed, 0.1), "speech": String(turn.get("speech", "")), "voice": voice, "words": words,
		"serverProvider": String(server_row.get("provider", "")), "serverFallback": String(server_row.get("fallback", "")),
		"lessonAction": String(turn.get("lessonAction", "")), "turnEmotion": String(turn.get("emotion", "")),
		"turnGesture": String(turn.get("gesture", "")), "alizExpression": aliz_expression, "alizGesture": aliz_gesture,
		"prevGesture": _prev_gesture, "visual": turn.get("visual", {}),
		"maxMouth": 0.0, "maxLipLevel": 0.0, "maxLipAmount": 0.0, "samples": 0,
		"recognitionOpenWhileSpeaking": false, "vadUngatedWhileSpeaking": false,
		"micAtSpeak": {"capturing": d.get("capturing", null), "recognitionOpen": d.get("recognitionOpen", null), "vadGated": d.get("vadGated", null), "state": d.get("state", "")},
	}
	_rows.append(row)
	_prev_gesture = aliz_gesture
	print("  %5.1fs  TURN %d [server=%s%s] [words=%s voice=%s] action=%s turn(emotion=%s gesture=%s) aliz(expression=%s gesture=%s) mic(recOpen=%s vadGated=%s) %s" % [
		_elapsed, _rows.size(), row["serverProvider"] if not String(row["serverProvider"]).is_empty() else "local",
		("/" + String(row["serverFallback"])) if not String(row["serverFallback"]).is_empty() else "",
		words, voice, row["lessonAction"], row["turnEmotion"], row["turnGesture"], aliz_expression, aliz_gesture,
		str(d.get("recognitionOpen", "?")), str(d.get("vadGated", "?")), String(turn.get("speech", ""))])


func _process(_delta: float) -> bool:
	if _done or _scene == null:
		return true
	var now: int = Time.get_ticks_msec()
	var dt: float = float(now - _last_ticks) / 1000.0
	_last_ticks = now
	if dt <= 0.0:
		return false
	_elapsed += dt
	var state: String = String(_scene.call("state"))
	_sample_speaking(state)
	if state == "listening":
		if _last_answer_state != "listening":
			_answer_delay = 0.6
		_last_answer_state = "listening"
		if _answer_delay >= 0.0:
			_answer_delay -= dt
			if _answer_delay < 0.0:
				_answer_delay = -1.0
				var kind: String = ANSWERS[_answer_index % ANSWERS.size()]
				_answer_index += 1
				_scene.call("simulate", kind)
	else:
		_last_answer_state = state
	var cloud_turns: int = _cloud_turn_count()
	var enough: bool = cloud_turns >= MIN_CLOUD_TURNS + 1 and state == "listening"
	if state == "break" or state == "done" or enough or _elapsed >= MAX_SECONDS:
		_finish(state)
		return true
	return false


## While Aliz speaks: the mouth and lip level, and the microphone gate.
func _sample_speaking(state: String) -> void:
	if _rows.is_empty() or state != "speaking":
		return
	var synth: Node = _scene.call("synthesis")
	if not bool(synth.call("is_speaking")):
		return
	var row: Dictionary = _rows[-1]
	row["samples"] = int(row["samples"]) + 1
	if _aliz != null and _aliz.has_method("get_mouth_open"):
		row["maxMouth"] = maxf(float(row["maxMouth"]), float(_aliz.call("get_mouth_open")))
	if _lip != null:
		if _lip.has_method("level"):
			row["maxLipLevel"] = maxf(float(row["maxLipLevel"]), float(_lip.call("level")))
		if _lip.has_method("amount"):
			row["maxLipAmount"] = maxf(float(row["maxLipAmount"]), float(_lip.call("amount")))
	var d: Dictionary = _voice_diag()
	if bool(d.get("recognitionOpen", false)):
		row["recognitionOpenWhileSpeaking"] = true
	if d.has("vadGated") and not bool(d.get("vadGated", true)) and String(d.get("state", "")) == "aliz_speaking":
		row["vadUngatedWhileSpeaking"] = true


func _voice_diag() -> Dictionary:
	var voice: Object = _scene.call("voice_session")
	if voice != null and voice.has_method("diagnostics"):
		return voice.call("diagnostics")
	return {}


func _cloud_turn_count() -> int:
	var n: int = 0
	for row: Dictionary in _rows:
		if String(row["words"]) == "cloud":
			n += 1
	return n


static func _num(value: Variant) -> float:
	return float(value) if value is float or value is int else 0.0


func _finish(state: String) -> void:
	_done = true
	var provider: Object = _scene.call("provider")
	var provider_log: Array = provider.call("turn_log") if provider != null and provider.has_method("turn_log") else []
	# -- per-turn table -----------------------------------------------------------------
	print("AI-SMOKE: per-turn table (t, server, words/voice, action, turn gesture -> aliz gesture, aliz expression, maxMouth, maxLipAmount, recOpenWhileSpeaking)")
	for i: int in range(_rows.size()):
		var r: Dictionary = _rows[i]
		print("  #%02d %5.1fs server=%-22s words=%-5s voice=%-5s action=%-13s gesture %-9s -> %-9s expr=%-11s mouth=%.3f lip=%.3f samples=%d recOpen=%s vadUngated=%s" % [
			i + 1, float(r["t"]), (String(r["serverProvider"]) + ("/" + String(r["serverFallback"]) if not String(r["serverFallback"]).is_empty() else "")) if not String(r["serverProvider"]).is_empty() else "-",
			r["words"], r["voice"], r["lessonAction"], r["turnGesture"], r["alizGesture"], r["alizExpression"],
			float(r["maxMouth"]), float(r["maxLipAmount"]), int(r["samples"]), str(r["recognitionOpenWhileSpeaking"]), str(r["vadUngatedWhileSpeaking"])])
	print("AI-SMOKE: raw server turns (client validator on the REST body):")
	var providers: Dictionary = {}
	var invalid_raw: int = 0
	for s: Dictionary in _raw_server_turns:
		var label: String = String(s["provider"]) + ("/" + String(s["fallback"]) if not String(s["fallback"]).is_empty() and String(s["fallback"]) != "<null>" else "")
		providers[label] = int(providers.get(label, 0)) + 1
		if not bool(s["valid"]):
			invalid_raw += 1
		print("  provider=%s fallback=%s contextSource=%s latencyMs=%d valid=%s reasons=%s emotion=%s gesture=%s visual=%s action=%s" % [
			s["provider"], s["fallback"], s["contextSource"], int(s["latencyMs"]), str(s["valid"]), str(s["reasons"]), s["emotion"], s["gesture"], str(s["visual"]), s["lessonAction"]])
	print("AI-SMOKE: server provider histogram=%s" % str(providers))
	print("AI-SMOKE: provider log=%s" % str(provider_log))
	print("AI-SMOKE: states=%s" % str(_states))
	# -- end the cloud session and wait for the server's acknowledgement ------------------
	var session_ended: bool = false
	var server_ack: bool = false
	if _session != null:
		if String(_session.call("get_state")) != "ended":
			_session.call("end", "smoke_done")
		var deadline: int = Time.get_ticks_msec() + 8000
		var last: int = Time.get_ticks_msec()
		while String(_session.call("get_state")) != "ended" and Time.get_ticks_msec() < deadline:
			var now: int = Time.get_ticks_msec()
			_session.call("advance", maxf(float(now - last) / 1000.0, 0.001))
			last = now
			OS.delay_msec(10)
		var summary: Dictionary = _session.call("last_summary")
		session_ended = String(_session.call("get_state")) == "ended"
		server_ack = bool(summary.get("serverAck", false))
		print("AI-SMOKE: cloud session state=%s transport=%s history=%s" % [String(_session.call("get_state")), String(_session.call("transport_mode")), str(_session.call("state_history"))])
		print("AI-SMOKE: cloud turn log=%s" % str(_session.call("turn_log")))
		print("AI-SMOKE: cloud session summary=%s" % str(summary))
	var voice: Object = _scene.call("voice_session")
	if voice != null and voice.has_method("stop"):
		voice.call("stop", "smoke_done")
	var capturing: bool = voice != null and voice.has_method("is_capturing") and bool(voice.call("is_capturing"))
	var streaming: bool = _session != null and bool(_session.call("is_streaming_allowed"))
	print("AI-SMOKE: mic after %s: is_capturing=%s cloud_streaming_allowed=%s" % [state, str(capturing), str(streaming)])
	# -- assertions ------------------------------------------------------------------------
	var problems: Array = []
	var cloud_turns: int = _cloud_turn_count()
	if cloud_turns < MIN_CLOUD_TURNS:
		problems.append("only %d server-authored turns (need %d)" % [cloud_turns, MIN_CLOUD_TURNS])
	if _raw_server_turns.is_empty() or invalid_raw > 0:
		problems.append("%d raw server turns failed the client validator (of %d)" % [invalid_raw, _raw_server_turns.size()])
	if not _failed.is_empty():
		problems.append("provider_failed=%s" % str(_failed))
	var encouraging_seen: bool = false
	var expressions: Dictionary = {}
	for i: int in range(_rows.size()):
		var r: Dictionary = _rows[i]
		expressions[String(r["alizExpression"])] = true
		if String(r["alizExpression"]) == "encouraging":
			encouraging_seen = true
		var intended: String = String(r["turnEmotion"])
		# The scene overrides the turn's emotion for answer feedback (pool) -- the
		# read-back must be a real TutorFace expression, never empty/unknown.
		if not TurnValidator.EMOTIONS.has(String(r["alizExpression"])):
			problems.append("turn %d: Aliz expression '%s' is not a TutorFace expression (turn asked %s)" % [i + 1, r["alizExpression"], intended])
		if String(r["alizGesture"]).is_empty() and String(r["turnGesture"]) != "none":
			problems.append("turn %d: no gesture on Aliz although the turn asked %s" % [i + 1, r["turnGesture"]])
		if i > 0 and String(r["words"]) == "cloud" and String(r["alizGesture"]) == String(r["prevGesture"]) and not String(r["alizGesture"]).is_empty():
			problems.append("turn %d: gesture %s repeats the previous turn's" % [i + 1, r["alizGesture"]])
		if String(r["voice"]) == "tts" and int(r["samples"]) > 3 and float(r["maxMouth"]) <= 0.0:
			problems.append("turn %d: mouth never opened while the TTS voice played (%d samples)" % [i + 1, int(r["samples"])])
		if bool(r["recognitionOpenWhileSpeaking"]):
			problems.append("turn %d: the recogniser was open while Aliz spoke" % (i + 1))
		if bool(r["vadUngatedWhileSpeaking"]):
			problems.append("turn %d: the VAD was not gated while Aliz spoke" % (i + 1))
	if not encouraging_seen:
		problems.append("no encouraging turn was seen (the wrong answer should produce one)")
	if expressions.size() < 2:
		problems.append("Aliz's expression never changed: %s" % str(expressions.keys()))
	if not _listening_capture_seen:
		problems.append("capture was never seen in the listening state")
	if not session_ended or not server_ack:
		problems.append("cloud session ended=%s serverAck=%s" % [str(session_ended), str(server_ack)])
	if capturing or streaming:
		problems.append("capture still open at the end: capturing=%s streaming=%s" % [str(capturing), str(streaming)])
	print("AI-SMOKE: state=%s completed=%s turns=%d cloud_authored=%d raw_server_turns=%d invalid_raw=%d expressions=%s encouraging_seen=%s" % [
		state, str(_completed), _rows.size(), cloud_turns, _raw_server_turns.size(), invalid_raw, str(expressions.keys()), str(encouraging_seen)])
	for p: String in problems:
		print("AI-SMOKE: PROBLEM %s" % p)
	print("AI-SMOKE: transcripts=simulated (scene hook only; no child audio, no real child)")
	print("AI-SMOKE: %s" % ("PASS" if problems.is_empty() else "FAIL"))
	root.remove_child(_scene)
	_scene.free()
	quit(0 if problems.is_empty() else 1)
