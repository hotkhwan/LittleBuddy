extends RefCounted

## AI PATH, END TO END -- the two offline/local legs of the chain, on the REAL
## classroom scene, headless, no backend, no network (AI E2E verification,
## 2026-09-22; see docs/AI_E2E_VERIFICATION.md).
##
##   A. Cloud flag OFF (the suite's default, the value project.godot ships):
##      the classroom runs the SCRIPTED tutor. The provider is
##      `scripted_conversation_provider.gd`, the synthesis is the local shim,
##      no `CloudSynthesis`/`CloudAudio` node exists under the scene and no
##      script under `res://scripts/tutor/cloud/` is instanced anywhere in the
##      scene tree (privacy guard: with the flag off nothing that can reach a
##      network is loaded by the classroom). Three answers are judged locally.
##
##   B. Cloud flag ON (set IN MEMORY for this case only and restored in every
##      path) with the backend pointed at a CLOSED loopback port: the cloud
##      session fails its sign-in (`provider_unavailable`), the cloud provider
##      answers every turn with the scripted tutor's own words
##      (`fallback: cloud_not_ready`), the lesson keeps moving (speaking ->
##      listening -> speaking ...) and nothing reaches `provider_failed`. The
##      classroom never dies: three more answers are judged after the failure.
##      Then the loud path: a `provider_failed` on the bound provider makes the
##      scene say "Let's try together!" with the TOGETHER banner, rebuild the
##      scripted provider and carry on to the microphone again.
##
## Everything here is synthetic (the scene's simulated-child hook); no audio,
## no transcript of a real child. `run()` and the helpers are untyped (contract §8).

const SCENE_PATH: String = "res://scenes/tutor/classroom.tscn"
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const BridgeScript := preload("res://scripts/tutor/cloud/cloud_tutor_bridge.gd")
const ApiScript := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const HudScript := preload("res://scripts/tutor/ui/tutor_hud.gd")

const STEP: float = 0.1
const CLOUD_DIR: String = "res://scripts/tutor/cloud/"
const SCRIPTED_PROVIDER: String = "res://scripts/tutor/providers/scripted_conversation_provider.gd"
const TOGETHER_LINE: String = "Let's try together!"


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


func test_name() -> String:
	return "ai_e2e_offline_fallback"


func run():
	var failures: Array = []
	if TutorFlags.cloud_enabled():
		return ["this case must run with the cloud flag OFF (it arms the flag itself, in memory, for leg B)"]
	failures.append_array(_leg_a_flag_off())
	failures.append_array(_leg_b_backend_unreachable())
	return failures


# -- A: flag off -> scripted tutor, nothing from cloud/ in the tree ---------------------------

func _leg_a_flag_off():
	var failures: Array = []
	var scene: Node = _make()
	var spoken: Array = []
	scene.turn_spoken.connect(func(t: Dictionary) -> void: spoken.append(t))
	var provider: Object = scene.provider()
	var provider_path: String = _script_path(provider)
	var synth: Node = scene.synthesis()
	print("    A flag off: provider=%s (%s) synth=%s cloud nodes=%s" % [
		String(provider.call("provider_name")), provider_path, _script_path(synth), str(_cloud_scripts_in(scene))])
	if provider_path != SCRIPTED_PROVIDER or String(provider.call("provider_name")) != "scripted":
		failures.append("A: with the flag off the classroom must bind the scripted provider, got %s" % provider_path)
	if _script_path(synth).begins_with(CLOUD_DIR) or scene.get_node_or_null("CloudSynthesis") != null or scene.get_node_or_null("CloudAudio") != null:
		failures.append("A: with the flag off no cloud synthesis/audio node may exist under the scene")
	var cloud_nodes: Array = _cloud_scripts_in(scene)
	if not cloud_nodes.is_empty():
		failures.append("A: scripts under %s instanced with the flag off: %s" % [CLOUD_DIR, str(cloud_nodes)])
	# Three answers, all judged by the scripted tutor.
	var judged: int = 0
	for i: int in range(3):
		if _until(scene, func() -> bool: return scene.state() == "listening", 600) < 0:
			failures.append("A: answer %d: the classroom never reached listening (state %s)" % [i + 1, scene.state()])
			break
		var before: int = spoken.size()
		scene.simulate("correct")
		if _until(scene, func() -> bool: return spoken.size() > before, 600) < 0:
			failures.append("A: answer %d: no turn was spoken after the simulated answer" % (i + 1))
			break
		judged += 1
	print("    A flag off: %d answers judged locally, %d turns spoken, states=%s" % [judged, spoken.size(), str(_recent(scene))])
	for t: Dictionary in spoken:
		if TurnValidator.coerce(t) != t:
			failures.append("A: a scripted turn failed the validator: %s" % str(t))
			break
	if judged != 3:
		failures.append("A: expected 3 locally judged answers, got %d" % judged)
	_free(scene)
	return failures


# -- B: flag on, backend on a closed port -> quiet scripted fallback, never dies --------------

func _leg_b_backend_unreachable():
	var failures: Array = []
	var port: int = _closed_port()
	if port <= 0:
		return ["B: could not reserve a closed loopback port"]
	var apis: Array = []
	# The bridge takes its REST client from this factory: armed for the suite
	# (loopback only, refused on mobile/release) and pointed at the closed port.
	BridgeScript.set_api_factory_for_tests(func(device_id: String) -> RefCounted:
		var api: RefCounted = ApiScript.new()
		api.configure(device_id)
		api.enable_for_tests()
		api.set_base_url("http://127.0.0.1:%d" % port)
		api.set_timeout_seconds(2.0)
		apis.append(api)
		return api)
	var had_setting: bool = ProjectSettings.has_setting(TutorFlags.SETTING_CLOUD)
	var previous: Variant = ProjectSettings.get_setting(TutorFlags.SETTING_CLOUD) if had_setting else false
	ProjectSettings.set_setting(TutorFlags.SETTING_CLOUD, true)
	var scene: Node = null
	if TutorFlags.cloud_enabled():
		scene = _make()
		failures.append_array(_run_leg_b(scene, apis, port))
	else:
		failures.append("B: TutorFlags.cloud_enabled() stayed false after the in-memory setting")
	# Restore FIRST, whatever happened above (test_tutor_flags asserts the flag is off).
	if had_setting:
		ProjectSettings.set_setting(TutorFlags.SETTING_CLOUD, previous)
	else:
		ProjectSettings.set_setting(TutorFlags.SETTING_CLOUD, false)
	BridgeScript.set_api_factory_for_tests(Callable())
	_free(scene)
	if TutorFlags.cloud_enabled():
		failures.append("B: the cloud flag must be OFF again after this case")
	return failures


func _run_leg_b(scene: Node, apis: Array, port: int):
	var failures: Array = []
	var spoken: Array = []
	var provider_failed: Array = []
	var fell_back: Array = []
	var fallbacks: Array = []
	scene.turn_spoken.connect(func(t: Dictionary) -> void: spoken.append(t))
	var provider: Object = scene.provider()
	if provider == null or not _script_path(provider).begins_with(CLOUD_DIR):
		return ["B: with the flag on the classroom must bind the cloud provider, got %s" % _script_path(provider)]
	provider.provider_failed.connect(func(r: String) -> void: provider_failed.append(r))
	if provider.has_signal("fallback_used"):
		provider.fallback_used.connect(func(r: String) -> void: fallbacks.append(r))
	var session: RefCounted = provider.call("cloud_session")
	if session != null:
		session.fell_back.connect(func(r: String) -> void: fell_back.append(r))
	var synth: Node = scene.synthesis()
	print("    B closed port %d: provider=%s synth=%s api_clients=%d" % [port, String(provider.call("provider_name")), _script_path(synth), apis.size()])
	if apis.is_empty():
		failures.append("B: the bridge did not take its REST client from the test factory")
	# Three answers with the backend unreachable: every one answered by the scripted tutor.
	var judged: int = 0
	for i: int in range(3):
		if _until(scene, func() -> bool: return scene.state() == "listening", 800) < 0:
			failures.append("B: answer %d: the classroom never reached listening (state %s)" % [i + 1, scene.state()])
			break
		var before: int = spoken.size()
		scene.simulate("correct")
		if _until(scene, func() -> bool: return spoken.size() > before, 800) < 0:
			failures.append("B: answer %d: no turn was spoken after the simulated answer" % (i + 1))
			break
		judged += 1
	# Let the refused sign-in finish its round trip (2 s client timeout at most).
	_until(scene, func() -> bool: return not fell_back.is_empty(), 40)
	var words: String = String(synth.call("words_source")) if synth.has_method("words_source") else "?"
	var voice: String = String(synth.call("voice_used")) if synth.has_method("voice_used") else "?"
	var log_rows: Array = provider.call("turn_log") if provider.has_method("turn_log") else []
	var session_state: String = String(session.call("get_state")) if session != null else "none"
	var request_kinds: Array = []
	for api: RefCounted in apis:
		for entry: Dictionary in api.call("request_log"):
			request_kinds.append("%s:%s" % [String(entry.get("kind", "")), String(entry.get("code", entry.get("status", "")))])
	print("    B closed port: judged=%d spoken=%d words=%s voice=%s session=%s fell_back=%s fallbacks=%s provider_failed=%s requests=%s" % [
		judged, spoken.size(), words, voice, session_state, str(fell_back), str(fallbacks), str(provider_failed), str(request_kinds)])
	if judged != 3:
		failures.append("B: expected 3 answers judged during the outage, got %d" % judged)
	if words != "local":
		failures.append("B: the words must be the scripted tutor's (words_source=local), got %s" % words)
	if not provider_failed.is_empty():
		failures.append("B: an unreachable backend must not reach provider_failed: %s" % str(provider_failed))
	if fell_back.is_empty() or not fell_back.has(ApiScript.CODE_PROVIDER_UNAVAILABLE):
		failures.append("B: the cloud session must report fell_back(provider_unavailable) for the closed port: %s" % str(fell_back))
	var quiet_fallbacks: int = 0
	for row: Dictionary in log_rows:
		if String(row.get("kind", "")) == "fallback":
			quiet_fallbacks += 1
	if quiet_fallbacks < 1 or not fallbacks.has("cloud_not_ready"):
		failures.append("B: every answer during the outage must be a quiet scripted fallback (cloud_not_ready): log=%s used=%s" % [str(log_rows), str(fallbacks)])
	for t: Dictionary in spoken:
		if TurnValidator.coerce(t) != t:
			failures.append("B: a fallback turn failed the validator: %s" % str(t))
			break
	if String(scene.state()) in ["done", "break"]:
		failures.append("B: the classroom died during the outage (state %s)" % scene.state())
	# The loud path: a provider failure -> "Let's try together!" -> scripted provider -> mic again.
	if _until(scene, func() -> bool: return scene.state() == "listening", 800) < 0:
		failures.append("B: not listening before the provider_failed check (state %s)" % scene.state())
	var before_loud: int = spoken.size()
	scene.simulate("correct")
	_until(scene, func() -> bool: return scene.state() == "thinking" or spoken.size() > before_loud, 100)
	provider.provider_failed.emit("e2e_forced_failure")
	if _until(scene, func() -> bool: return spoken.size() > before_loud, 100) < 0:
		failures.append("B: provider_failed did not produce a spoken turn")
	else:
		var loud: Dictionary = spoken[-1]
		var banner: String = String(scene.hud().call("banner_kind"))
		var rebound: Object = scene.provider()
		print("    B provider_failed: spoke '%s' banner=%s provider now=%s" % [String(loud.get("speech", "")), banner, _script_path(rebound)])
		if String(loud.get("speech", "")) != TOGETHER_LINE or banner != HudScript.BANNER_TOGETHER:
			failures.append("B: provider_failed must say '%s' with the together banner, got '%s' / %s" % [TOGETHER_LINE, String(loud.get("speech", "")), banner])
		if _script_path(rebound) != SCRIPTED_PROVIDER:
			failures.append("B: after provider_failed the scene must run the scripted provider, got %s" % _script_path(rebound))
	if _until(scene, func() -> bool: return scene.state() == "listening", 800) < 0:
		failures.append("B: the classroom did not reopen the microphone after 'Let's try together!' (state %s)" % scene.state())
	else:
		var before_last: int = spoken.size()
		scene.simulate("correct")
		if _until(scene, func() -> bool: return spoken.size() > before_last, 800) < 0:
			failures.append("B: no scripted turn after the recovery")
	print("    B closed port: final state=%s spoken=%d recent states=%s" % [scene.state(), spoken.size(), str(_recent(scene))])
	scene.leave_to_home()
	scene.advance(STEP)
	var voice_session: Object = scene.voice_session()
	if voice_session != null and bool(voice_session.call("is_capturing")):
		failures.append("B: the microphone stayed open after leaving")
	return failures


# -- helpers ----------------------------------------------------------------------------------

func _make() -> Node:
	var packed: PackedScene = load(SCENE_PATH)
	var scene: Node = packed.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(scene)
	scene.build()
	scene.set_save_service(FakeSave.new())
	scene.enable_simulation(true)
	scene.begin_lesson()
	return scene


func _free(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		if scene.get_parent() != null:
			scene.get_parent().remove_child(scene)
		scene.free()


func _until(scene: Node, predicate: Callable, max_steps: int) -> int:
	for i: int in range(max_steps):
		if predicate.call():
			return i
		scene.advance(STEP)
	return -1


func _recent(scene: Node) -> Array:
	var log_rows: Array = scene.turn_log() if scene.has_method("turn_log") else []
	var out: Array = []
	for row: Dictionary in log_rows.slice(maxi(0, log_rows.size() - 4)):
		out.append(String(row.get("lessonAction", "")))
	return out


static func _script_path(object: Object) -> String:
	if object == null:
		return ""
	var script: Script = object.get_script() as Script
	return script.resource_path if script != null else ""


## Every node under `scene` whose script lives under `res://scripts/tutor/cloud/`.
func _cloud_scripts_in(scene: Node) -> Array:
	var out: Array = []
	var stack: Array = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var path: String = _script_path(node)
		if path.begins_with(CLOUD_DIR):
			out.append("%s (%s)" % [node.name, path])
		for child: Node in node.get_children():
			stack.append(child)
	return out


## Binds an ephemeral loopback port, then releases it: nothing listens there.
func _closed_port() -> int:
	var server := TCPServer.new()
	if server.listen(0, "127.0.0.1") != OK:
		return -1
	var port: int = server.get_local_port()
	server.stop()
	return port
