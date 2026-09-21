extends SceneTree

## DEV SMOKE (Agent E): the real classroom scene, in REAL time, with the cloud
## tutor armed by the developer user arg, against the mock server.
##
##   /usr/local/bin/node tools/tutor_mock_server/server.mjs
##   godot --headless --path game --script res://tests/smoke_tutor_cloud_classroom.gd -- --ai-tutor-cloud
##
## Nothing here is part of the suite: it needs the flag (user arg only, never
## an export) and the mock. It instantiates `classroom.tscn`, lets Aliz
## welcome, answers every question through the scene's own simulated-child
## hook, and prints what was spoken and by which voice ("cloud" = the
## streamed reply through CloudSynthesisProvider, anything else = the local
## voice), the provider's fallback log and how the cloud session ended.
## Pass criteria printed at the end: at least one cloud-voiced turn, no
## provider_failed, the lesson reached its end, the session ended cleanly.

const SCENE_PATH: String = "res://scenes/tutor/classroom.tscn"
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const MAX_SECONDS: float = 90.0


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
	print("SMOKE: provider=%s synth=%s backend=%s" % [
		String(provider.call("provider_name")) if provider != null else "none",
		String((_scene.call("synthesis") as Node).call("provider_name")) if (_scene.call("synthesis") as Node).has_method("provider_name") else "local",
		TutorFlags.backend_url()])
	_scene.call("begin_lesson", "animals_cat_dog")
	_last_ticks = Time.get_ticks_msec()


func _on_turn(turn: Dictionary) -> void:
	var synth: Node = _scene.call("synthesis")
	var voice: String = String(synth.call("voice_used")) if synth.has_method("voice_used") else "?"
	_spoken.append({"speech": String(turn.get("speech", "")), "voice": voice, "visual": turn.get("visual", {}), "t": snappedf(_elapsed, 0.1)})
	print("  %5.1fs  [%s] %s  %s" % [_elapsed, voice, String(turn.get("speech", "")), str(turn.get("visual", {}))])


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
	var cloud_turns: int = 0
	for entry: Dictionary in _spoken:
		if String(entry["voice"]) == "cloud":
			cloud_turns += 1
	var provider: Object = _scene.call("provider")
	var log_rows: Array = provider.call("turn_log") if provider != null and provider.has_method("turn_log") else []
	var session: Object = provider.call("cloud_session") if provider != null and provider.has_method("cloud_session") else null
	print("SMOKE: state=%s completed=%s turns=%d cloud_voiced=%d provider_failed=%s" % [state, str(_completed), _spoken.size(), cloud_turns, str(_failed)])
	print("SMOKE: provider log=%s" % str(log_rows))
	if session != null:
		print("SMOKE: cloud session state=%s history=%s reconnects=%d usage=%s summary=%s" % [
			String(session.call("get_state")), str(session.call("state_history")), int(session.call("reconnect_count")),
			str(session.call("usage")), str(session.call("last_summary"))])
	var ok: bool = cloud_turns >= 1 and _failed.is_empty() and (state == "break" or state == "done")
	print("SMOKE: %s" % ("PASS" if ok else "FAIL"))
	root.remove_child(_scene)
	_scene.free()
	quit(0 if ok else 1)
