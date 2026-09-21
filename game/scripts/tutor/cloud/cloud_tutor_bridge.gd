extends RefCounted

## CloudTutorBridge -- the ONE place the classroom scene touches the cloud
## tutor. `tutor_scene.gd` loads this file only while
## `TutorFlags.cloud_enabled()` is true and calls `attach()` once from
## `build()`; with the flag off nothing under `scripts/tutor/cloud/` is ever
## loaded and the classroom is unchanged.
##
## `attach(scene, engine, scripted_provider, local_synth)` builds the REST
## client, the realtime transport, the audio player, the session, the
## `CloudTutorProvider` and the `CloudSynthesisProvider`, wires them to the
## scene's read-backs (face, HUD, board, quota, voice session) and returns
## `{provider, synth}` for the scene to bind in place of the scripted pair.
## Everything visual still goes through the scene's own `_speak_turn()`;
## the bridge only keeps the subtitle growing as words stream, shows a
## tool-called card at once, and ends the cloud session when the scene
## leaves, breaks, backgrounds or a grown-up stops the lesson.
##
## Credentials: there is no Parent Corner sign-in in the app yet, so the
## session performs the Worker's DEV_MODE sign-in (`POST /v1/parents
## {provider: "dev"}`) with the pseudonymous per-install id as the subject and
## `clientId`, then grants the `ai_tutor` consent for that synthetic family.
## The id is random, kept under the SaveService setting `tutorDeviceId`.
## Never a name, never a device serial; the tokens stay in memory.
##
## Tests: `set_api_factory_for_tests(Callable)` makes `attach()` take its REST
## client from the factory instead of building one (a scripted fake; the
## suite never dials anything). Cleared with an invalid Callable.

const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const ApiScript := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")
const SessionScript := preload("res://scripts/tutor/cloud/cloud_tutor_session.gd")
const TransportScript := preload("res://scripts/tutor/voice/transports/cloud_realtime_transport.gd")
const PlayerScript := preload("res://scripts/tutor/cloud/cloud_audio_player.gd")
const ProviderScript := preload("res://scripts/tutor/cloud/cloud_tutor_provider.gd")
const SynthScript := preload("res://scripts/tutor/cloud/cloud_synthesis_provider.gd")

const DEVICE_ID_SETTING: String = "tutorDeviceId"
const SAVE_SERVICE_NAME: String = "SaveService"

static var _api_factory: Callable = Callable()

var _scene: Node = null
var _api: RefCounted = null
var _transport: RefCounted = null
var _player: Node = null
var _session: RefCounted = null
var _provider: RefCounted = null
var _synth: Node = null


static func set_api_factory_for_tests(factory: Callable) -> void:
	_api_factory = factory


func attach(scene: Node, engine: Object, _scripted_provider: RefCounted, local_synth: Node) -> Dictionary:
	if not TutorFlags.cloud_enabled() or scene == null:
		return {}
	_scene = scene
	var device_id: String = _device_id()
	if _api_factory.is_valid():
		_api = _api_factory.call(device_id)
	if _api == null:
		_api = ApiScript.new()
		_api.configure(device_id)
	_transport = TransportScript.new()
	_player = PlayerScript.new()
	_player.name = "CloudAudio"
	_session = SessionScript.new()
	_session.set_api(_api)
	_session.set_transport(_transport)
	_session.set_audio_player(_player)
	if scene.has_method("aliz"):
		_session.set_face(scene.call("aliz"))
	if scene.has_method("quota"):
		_session.set_quota_source(Callable(scene, "quota"))
	_session.set_capture_source(_capture_allowed)

	_provider = ProviderScript.new()
	_provider.set_engine(engine)
	_provider.set_cloud_session(_session)

	_synth = SynthScript.new()
	_synth.set_inner(local_synth)
	_synth.set_cloud_session(_session)
	_synth.set_cloud_provider(_provider)
	_synth.set_audio_player(_player)

	_session.subtitle_changed.connect(_on_subtitle)
	_session.tool_applied.connect(_on_tool)
	_session.fell_back.connect(_on_fell_back)
	if scene.has_signal("state_changed"):
		scene.state_changed.connect(_on_scene_state)
	scene.tree_exiting.connect(_on_scene_exiting)
	return {"provider": _provider, "synth": _synth}


## A future native microphone tap feeds PCM16 mono 24 kHz here; the session
## streams it only while the hands-free session is capturing and not gated.
func push_microphone_pcm(pcm: PackedByteArray) -> bool:
	return _session != null and bool(_session.call("push_audio", pcm))


func session() -> RefCounted:
	return _session


func provider() -> RefCounted:
	return _provider


func synthesis() -> Node:
	return _synth


func api() -> RefCounted:
	return _api


# -- scene glue ------------------------------------------------------------------------------

func _capture_allowed() -> bool:
	if _scene == null or not _scene.has_method("voice_session"):
		return false
	var voice: Object = _scene.call("voice_session")
	if voice == null or not voice.has_method("is_capturing") or not bool(voice.call("is_capturing")):
		return false
	if voice.has_method("vad"):
		var vad: Object = voice.call("vad")
		if vad != null and vad.has_method("is_gated") and bool(vad.call("is_gated")):
			return false
	return true


func _on_subtitle(text: String) -> void:
	var hud: Object = _scene.call("hud") if _scene != null and _scene.has_method("hud") else null
	if hud == null or not hud.has_method("set_subtitle"):
		return
	if _scene.has_method("state") and String(_scene.call("state")) != "speaking":
		return
	hud.call("set_subtitle", text)


func _on_tool(name: String, args: Dictionary) -> void:
	if name != "show_card" or _scene == null:
		return
	var asset: String = String(args.get("assetId", ""))
	var hud: Object = _scene.call("hud") if _scene.has_method("hud") else null
	if hud != null and hud.has_method("set_card"):
		hud.call("set_card", asset)
	if _scene.has_method("classroom"):
		var classroom: Object = _scene.call("classroom")
		if classroom != null and classroom.has_method("get_board"):
			var board: Object = classroom.call("get_board")
			if board != null and board.has_method("show_card"):
				board.call("show_card", asset)


func _on_fell_back(reason: String) -> void:
	push_warning("cloud tutor: falling back to the scripted tutor (%s)" % reason)


## The scene's exits, each ending the cloud session with the reason the
## Worker records: the break card after the day's minutes (`quota_expired`),
## after the lesson (`lesson_complete`) or after a grown-up's End lesson
## (`parent_stop`); leaving the scene (`scene`); the app backgrounding.
func _on_scene_state(state: String) -> void:
	if _session == null:
		return
	match state:
		"break":
			_session.call("end", _break_reason())
		"done":
			_session.call("end", SessionScript.REASON_SCENE)
		"background":
			_session.call("on_app_background")
		_:
			pass


func _break_reason() -> String:
	if _scene == null:
		return SessionScript.REASON_COMPLETE
	var meter: Object = _scene.call("quota") if _scene.has_method("quota") else null
	if meter != null and meter.has_method("is_exhausted") and bool(meter.call("is_exhausted")):
		return SessionScript.REASON_QUOTA
	if _scene.has_method("is_lesson_complete") and bool(_scene.call("is_lesson_complete")):
		return SessionScript.REASON_COMPLETE
	return SessionScript.REASON_PARENT_STOP


func _on_scene_exiting() -> void:
	if _session != null:
		_session.call("end", SessionScript.REASON_SCENE)


func _device_id() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var save: Node = tree.root.get_node_or_null(SAVE_SERVICE_NAME) if tree != null and tree.root != null else null
	if save != null and save.has_method("get_setting"):
		var existing: String = String(save.call("get_setting", DEVICE_ID_SETTING, ""))
		if not existing.is_empty():
			return existing
	var fresh: String = "ld-%08x%08x" % [randi(), randi()]
	if save != null and save.has_method("set_setting"):
		save.call("set_setting", DEVICE_ID_SETTING, fresh)
	return fresh
