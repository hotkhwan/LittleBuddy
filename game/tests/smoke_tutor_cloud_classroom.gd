extends SceneTree

## DEV SMOKE: the real classroom scene, in REAL time, with the cloud tutor
## armed by the developer user args, against the mock server or the deployed
## development Worker.
##
##   /usr/local/bin/node tools/tutor_mock_server/server.mjs
##   godot --headless --path game --script res://tests/smoke_tutor_cloud_classroom.gd -- --ai-tutor-cloud
##   godot --headless --path game --script res://tests/smoke_tutor_cloud_classroom.gd -- --ai-tutor-cloud --tutor-backend-url=<https url>
##
## Nothing here is part of the suite: it needs the flag (user args only, never
## an export) and a backend. It instantiates `classroom.tscn`, lets Aliz
## welcome, answers every question through the scene's own simulated-child
## hook, and prints what was spoken, by which voice ("cloud" = a streamed
## realtime reply, anything else = the local voice) and whose WORDS they were
## ("cloud" = the server's validated TutorTurn, streamed or over the turns
## path; "local" = the scripted tutor), the provider's fallback log, the
## session's turn log with the server's quota numbers, how the cloud session
## ended, and whether the microphone is closed afterwards.
## Pass criteria printed at the end: at least one cloud-authored turn, no
## provider_failed, the lesson reached its end, the cloud session ended and
## the server acknowledged it, the capture is closed.

const SCENE_PATH: String = "res://scenes/tutor/classroom.tscn"
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const LESSON_ID: String = "animals_cat_dog"
const MAX_SECONDS: float = 150.0


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
var _spoken: Array = []
var _states: Array = []
var _failed: Array = []
var _completed: bool = false
var _ready_info: Dictionary = {}
var _last_answer_state: String = ""
var _answer_delay: float = -1.0
var _elapsed: float = 0.0
var _last_ticks: int = 0
var _done: bool = false


func _initialize() -> void:
	for auto_name: String in ["SaveService", "SpeechService", "TtsService", "Voice", "Sfx", "Audio"]:
		var node: Node = root.get_node_or_null(auto_name)
		if node != null:
			root.remove_child(node)
	if not TutorFlags.cloud_enabled():
		print("SMOKE: run with `-- --ai-tutor-cloud`; the cloud tutor is off")
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
	_scene.state_changed.connect(func(s: String) -> void: _states.append(s))
	_scene.lesson_completed.connect(func(_p: Dictionary) -> void: _completed = true)
	var provider: Object = _scene.call("provider")
	if provider != null and provider.has_signal("provider_failed"):
		provider.provider_failed.connect(func(r: String) -> void: _failed.append(r))
	var session: Object = provider.call("cloud_session") if provider != null and provider.has_method("cloud_session") else null
	if session != null:
		session.ready.connect(func(info: Dictionary) -> void:
			_ready_info = info
			print("SMOKE: cloud session ready transport=%s session=%s quota=%s fallback=%s" % [
				String(info.get("transport", "")), String(info.get("sessionId", "")), str(info.get("quota", {})), String(info.get("realtimeFallback", ""))]))
		session.fell_back.connect(func(r: String) -> void: print("SMOKE: cloud session fell back: %s" % r))
	print("SMOKE: provider=%s synth=%s backend=%s lesson=%s" % [
		String(provider.call("provider_name")) if provider != null else "none",
		String((_scene.call("synthesis") as Node).call("provider_name")) if (_scene.call("synthesis") as Node).has_method("provider_name") else "local",
		TutorFlags.backend_url(), LESSON_ID])
	_scene.call("begin_lesson", LESSON_ID)
	_last_ticks = Time.get_ticks_msec()


func _on_turn(turn: Dictionary) -> void:
	var synth: Node = _scene.call("synthesis")
	var voice: String = String(synth.call("voice_used")) if synth.has_method("voice_used") else "?"
	var words: String = String(synth.call("words_source")) if synth.has_method("words_source") else "?"
	_spoken.append({"speech": String(turn.get("speech", "")), "voice": voice, "words": words, "visual": turn.get("visual", {}), "t": snappedf(_elapsed, 0.1)})
	print("  %5.1fs  [voice=%s words=%s] %s  %s %s" % [_elapsed, voice, words, String(turn.get("speech", "")), String(turn.get("gesture", "")), str(turn.get("visual", {}))])


func _process(_delta: float) -> bool:
	if _done:
		return true
	var now: int = Time.get_ticks_msec()
	var dt: float = float(now - _last_ticks) / 1000.0
	_last_ticks = now
	if dt <= 0.0:
		return false
	_elapsed += dt
	var state: String = String(_scene.call("state"))
	# Answer each question once, a beat after the mic opens.
	if state == "listening":
		if _last_answer_state != "listening":
			_answer_delay = 0.6
		_last_answer_state = "listening"
		if _answer_delay >= 0.0:
			_answer_delay -= dt
			if _answer_delay < 0.0:
				_answer_delay = -1.0
				_scene.call("simulate", "correct")
	else:
		_last_answer_state = state
	if state == "break" or state == "done" or _elapsed >= MAX_SECONDS:
		_finish(state)
		return true
	return false


func _finish(state: String) -> void:
	_done = true
	var cloud_voiced: int = 0
	var cloud_authored: int = 0
	for entry: Dictionary in _spoken:
		if String(entry["voice"]) == "cloud":
			cloud_voiced += 1
		if String(entry["words"]) == "cloud":
			cloud_authored += 1
	var provider: Object = _scene.call("provider")
	var log_rows: Array = provider.call("turn_log") if provider != null and provider.has_method("turn_log") else []
	var session: Object = provider.call("cloud_session") if provider != null and provider.has_method("cloud_session") else null
	print("SMOKE: state=%s completed=%s turns=%d cloud_authored=%d cloud_voiced=%d provider_failed=%s" % [state, str(_completed), _spoken.size(), cloud_authored, cloud_voiced, str(_failed)])
	print("SMOKE: provider log=%s" % str(log_rows))
	var session_ended: bool = false
	var server_ack: bool = false
	if session != null:
		# Let the end round trip finish (the scene stopped pumping at the break).
		var deadline: int = Time.get_ticks_msec() + 6000
		var last: int = Time.get_ticks_msec()
		while String(session.call("get_state")) != "ended" and Time.get_ticks_msec() < deadline:
			var now: int = Time.get_ticks_msec()
			session.call("advance", maxf(float(now - last) / 1000.0, 0.001))
			last = now
			OS.delay_msec(10)
		var summary: Dictionary = session.call("last_summary")
		session_ended = String(session.call("get_state")) == "ended"
		server_ack = bool(summary.get("serverAck", false))
		print("SMOKE: cloud session state=%s transport=%s history=%s reconnects=%d" % [
			String(session.call("get_state")), String(session.call("transport_mode")), str(session.call("state_history")), int(session.call("reconnect_count"))])
		print("SMOKE: cloud turn log=%s" % str(session.call("turn_log")))
		print("SMOKE: cloud session summary=%s" % str(summary))
		print("SMOKE: server quota=%s" % str(session.call("server_quota")))
	var voice: Object = _scene.call("voice_session")
	var capturing: bool = voice != null and voice.has_method("is_capturing") and bool(voice.call("is_capturing"))
	var active: bool = voice != null and voice.has_method("is_active") and bool(voice.call("is_active"))
	var streaming: bool = session != null and bool(session.call("is_streaming_allowed"))
	print("SMOKE: mic after %s: is_capturing=%s is_active=%s cloud_streaming_allowed=%s" % [state, str(capturing), str(active), str(streaming)])
	var ok: bool = cloud_authored >= 1 and _failed.is_empty() and (state == "break" or state == "done") \
			and session_ended and server_ack and not capturing and not streaming
	print("SMOKE: %s" % ("PASS" if ok else "FAIL"))
	root.remove_child(_scene)
	_scene.free()
	quit(0 if ok else 1)
