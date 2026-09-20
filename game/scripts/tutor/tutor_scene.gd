extends Node3D

## ALIZ TUTOR MODE -- the classroom scene's orchestrator.
##
##   LessonEngine -> ConversationProvider -> SpeechSynthesisProvider -> face
##                                        <- recognition (SpeechService / dev sim)
##
## One turn of the loop, as the child sees it:
##
##   Aliz asks ("What is this?", the card on the board)  ....... SPEAKING
##   the mic opens, the ring pulses, "Listening..."  ........... LISTENING
##   the child answers; a beat, a nod, "Thinking..."  .......... THINKING
##   Aliz answers: smile + clap and "Great job!", or an
##   encouraging hint, or "Let's try together!" on silence  .... SPEAKING
##   the lesson engine's `lessonAction` is applied at the end
##   of that speech -- next step, retry, or the break card  .... (boundary)
##
## Everything the child hears passed through `tutor_turn.gd` first. The engine
## owns progression (`advance()` is called here, at a boundary, never by a
## provider). The quota mirror counts active seconds and may only end the
## lesson at a boundary. Home and Stop always work, from every state.
##
## ## Recognition, honestly
##
## When `SpeechService` reports a live backend the mic is real. When it does
## not -- a Mac without permission, a build without the plugin, the headless
## suite -- the scene never pretends: the mic press becomes "Let's try
## together!", Aliz says the word with the child and the lesson moves on. The
## DEV simulation (`enable_simulation()`, the hidden panel, `-- --tutor-sim`)
## feeds a transcript into exactly the same path a recognised phrase takes, so
## the whole loop is testable; it is refused unless it was explicitly enabled.
##
## ## Seams
##
## `advance(delta)` is the frame; `_process()` calls it and tests call it. The
## engine, the provider and the quota are swapped for the real ones whenever
## their files exist (`ResourceLoader.exists()`), so Agents A, E and F land
## without a change here.

const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const ScriptedProviderScript := preload("res://scripts/tutor/providers/scripted_conversation_provider.gd")
const SynthesisScript := preload("res://scripts/tutor/providers/local_synthesis_provider.gd")
const ClassroomScript := preload("res://scripts/tutor/classroom/classroom_builder.gd")
const SeatPoseScript := preload("res://scripts/tutor/classroom/tutor_seat_pose.gd")
const LocalQuotaScript := preload("res://scripts/tutor/classroom/tutor_local_quota.gd")
const EngineStubScript := preload("res://scripts/tutor/classroom/lesson_engine_stub.gd")
const HudScript := preload("res://scripts/tutor/ui/tutor_hud.gd")
const BreakCardScript := preload("res://scripts/tutor/ui/tutor_break_card.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const LESSON_ENGINE_PATH: String = "res://scripts/tutor/lesson/lesson_engine.gd"
const TUTOR_QUOTA_PATH: String = "res://scripts/tutor/quota/tutor_quota.gd"
const ALIZ_SCENE_PATH: String = "res://scenes/characters/buddy/PinkGirlBuddy.tscn"
const MAIN_SCRIPT_PATH: String = "res://scenes/main/main.gd"
const HOME_SCENE_PATH: String = "res://scenes/main/main.tscn"
const DEFAULT_LESSON_ID: String = "fruits_01"
const SIM_USER_ARG: String = "--tutor-sim"
const SAVE_SERVICE_PATH: String = "/root/SaveService"
const SPEECH_SERVICE_PATH: String = "/root/SpeechService"
const AUDIO_PATH: String = "/root/Audio"

## How long a listening turn may run before it counts as silence. The speech
## service caps its own session sooner (4 s without a partial).
const LISTEN_SECONDS: float = 8.0
## The "thinking" beat: long enough to read as a nod, too short to feel slow.
const THINK_SECONDS: float = 0.45
## How long "Great job!" stays up after a correct answer's speech.
const CELEBRATE_SECONDS: float = 1.1
## Without recognition the mic waits for a tap; after this long Aliz repeats
## the question once, and after as long again she says it with the child.
const NUDGE_SECONDS: float = 10.0

## The shot: across the table from Aliz, a child's eye height, looking a
## little down so the table top and the board are both in frame.
const CAMERA_POSITION: Vector3 = Vector3(0.0, 1.5, 3.1)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 1.0, -0.8)
const CAMERA_FOV: float = 36.0
## The sun: front-left, high, no shadows.
const LIGHT_FROM: Vector3 = Vector3(-2.0, 4.0, 3.5)
const LIGHT_AT: Vector3 = Vector3(0.0, 0.8, -0.6)

const STATE_IDLE: String = "idle"
const STATE_SPEAKING: String = "speaking"
const STATE_LISTENING: String = "listening"
const STATE_AWAIT_MIC: String = "awaitMic"
const STATE_THINKING: String = "thinking"
const STATE_CELEBRATE: String = "celebrate"
const STATE_BREAK: String = "break"
const STATE_PAUSED: String = "paused"
const STATE_DONE: String = "done"

signal state_changed(state: String)
signal turn_spoken(turn: Dictionary)
signal lesson_completed(progress: Dictionary)
signal left_scene(target: String)

var _classroom: Node3D = null
var _aliz: Node3D = null
var _seat: SkeletonModifier3D = null
var _hud: Control = null
var _break_card: Control = null
var _engine: Object = null
var _provider: Object = null
var _synth: Node = null
var _quota: Object = null
var _camera: Camera3D = null

var _state: String = STATE_IDLE
var _resume_state: String = STATE_IDLE
var _lesson_id: String = DEFAULT_LESSON_ID
var _current_turn: Dictionary = {}
var _current_step: Dictionary = {}
var _last_question: Dictionary = {}
var _pending_phase: String = ""
var _pending_transcript: String = ""
var _timer: float = 0.0
var _nudged: bool = false
var _listening_live: bool = false
var _sim_enabled: bool = false
var _muted: bool = false
var _built: bool = false
var _leaving: bool = false
var _last_departure: String = ""
var _outcome_was_correct: bool = false
var _using_real_engine: bool = false
var _turn_log: Array = []
var _end_requested: bool = false
var _lesson_complete: bool = false
var _save_override: Object = null
var _last_failure_reason: String = ""


func _ready() -> void:
	build()
	if OS.get_cmdline_user_args().has(SIM_USER_ARG):
		enable_simulation(true)
		_hud.call("set_dev_panel_visible", true)
	begin_lesson(_lesson_id)


func _process(delta: float) -> void:
	advance(delta)


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

## Idempotent, and callable before `_ready()` for the headless runner.
func build() -> void:
	if _built:
		return
	_built = true
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		add_child(_camera)
	_camera.fov = CAMERA_FOV
	_camera.near = 0.05
	_camera.far = 30.0
	# Basis.looking_at rather than look_at(): it works before the node is in
	# a tree, which is where the headless runner builds this scene.
	_camera.transform = Transform3D(Basis.looking_at(CAMERA_TARGET - CAMERA_POSITION, Vector3.UP), CAMERA_POSITION)
	var light: DirectionalLight3D = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light != null:
		light.transform = Transform3D(Basis.looking_at(LIGHT_AT - LIGHT_FROM, Vector3.UP), LIGHT_FROM)
		light.shadow_enabled = false

	_classroom = ClassroomScript.new()
	add_child(_classroom)
	_classroom.call("build")

	_build_aliz()

	_synth = SynthesisScript.new()
	_synth.name = "Synthesis"
	add_child(_synth)
	_synth.finished.connect(_on_speech_finished)

	_engine = _make_engine()
	_provider = ScriptedProviderScript.new()
	_provider.call("set_engine", _engine)
	_provider.turn_ready.connect(_on_turn_ready)
	_provider.provider_failed.connect(_on_provider_failed)

	_quota = _make_quota()
	if _quota.has_signal("expired"):
		_quota.connect("expired", _on_quota_expired)

	var layer: CanvasLayer = get_node_or_null("UI") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "UI"
		add_child(layer)
	_hud = HudScript.new()
	layer.add_child(_hud)
	_hud.call("build")
	_hud.home_pressed.connect(leave_to_home)
	_hud.mute_toggled.connect(set_muted)
	_hud.repeat_pressed.connect(repeat_prompt)
	_hud.mic_pressed.connect(_on_mic_pressed)
	_hud.exit_requested.connect(_on_exit_requested)
	_hud.exit_kept.connect(_on_exit_kept)
	_hud.exit_confirmed.connect(_on_exit_confirmed)
	_hud.sim_requested.connect(simulate)

	_break_card = BreakCardScript.new()
	layer.add_child(_break_card)
	_break_card.call("build")
	_break_card.continue_playing_pressed.connect(leave_to_free_play)
	_break_card.home_pressed.connect(leave_to_home)
	_break_card.learn_again_pressed.connect(_on_learn_again)

	_bind_speech_service()


func _build_aliz() -> void:
	if not ResourceLoader.exists(ALIZ_SCENE_PATH):
		return
	var packed: Resource = load(ALIZ_SCENE_PATH)
	if not (packed is PackedScene):
		return
	_aliz = (packed as PackedScene).instantiate() as Node3D
	if _aliz == null:
		return
	_aliz.name = "Aliz"
	_aliz.position = ClassroomScript.ALIZ_SEAT
	_aliz.rotation.y = ClassroomScript.ALIZ_YAW
	add_child(_aliz)
	if _aliz.has_method("build"):
		_aliz.call("build")
	if _aliz.has_method("set_locomotion"):
		_aliz.call("set_locomotion", 0.0)
	var skeleton: Skeleton3D = null
	if _aliz.has_method("get_skeleton"):
		skeleton = _aliz.call("get_skeleton") as Skeleton3D
	_seat = SeatPoseScript.mount(skeleton)
	if _seat != null:
		_seat.call("set_seated", true)
		_seat.call("settle")
	_face("neutral")


func _make_engine() -> Object:
	if ResourceLoader.exists(LESSON_ENGINE_PATH):
		var script: Resource = load(LESSON_ENGINE_PATH)
		if script is GDScript and (script as GDScript).can_instantiate():
			var engine: Object = (script as GDScript).new()
			if engine != null and engine.has_method("load_lesson") and engine.has_method("evaluate"):
				_using_real_engine = true
				return engine
	_using_real_engine = false
	return EngineStubScript.new()


func _make_quota() -> Object:
	var save: Object = _save_service()
	if ResourceLoader.exists(TUTOR_QUOTA_PATH):
		var script: Resource = load(TUTOR_QUOTA_PATH)
		if script is GDScript and (script as GDScript).can_instantiate():
			var quota: Object = (script as GDScript).new()
			if quota != null and quota.has_method("state") and quota.has_method("request_end_at_boundary"):
				if quota.has_method("set_save_service"):
					quota.call("set_save_service", save)
				if quota is Node:
					add_child(quota)
				return quota
	return LocalQuotaScript.new(save)


func _bind_speech_service() -> void:
	var speech: Node = _speech_service()
	if speech == null:
		return
	if speech.has_signal("recognized") and not speech.recognized.is_connected(_on_recognized):
		speech.recognized.connect(_on_recognized)
	if speech.has_signal("session_ended") and not speech.session_ended.is_connected(_on_session_ended):
		speech.session_ended.connect(_on_session_ended)
	if speech.has_signal("recognition_failed") and not speech.recognition_failed.is_connected(_on_recognition_failed):
		speech.recognition_failed.connect(_on_recognition_failed)


# ---------------------------------------------------------------------------
# Lesson flow
# ---------------------------------------------------------------------------

func begin_lesson(lesson_id: String = DEFAULT_LESSON_ID) -> void:
	build()
	_lesson_id = lesson_id if not lesson_id.is_empty() else DEFAULT_LESSON_ID
	_lesson_complete = false
	_end_requested = false
	_turn_log.clear()
	if not bool(_engine.call("load_lesson", _lesson_id)):
		_engine = EngineStubScript.new()
		_engine.call("load_lesson", DEFAULT_LESSON_ID)
		_provider.call("set_engine", _engine)
	if _engine.has_method("load_progress"):
		_engine.call("load_progress", _save_service())
	if _quota.has_method("begin_session"):
		_quota.call("begin_session")
	_set_music(true)
	_provider.call("begin_session", _lesson_id)
	_open_step()


## Asks the provider to present the current step.
func _open_step() -> void:
	_current_step = _engine.call("current_step")
	if _current_step.is_empty() or bool(_engine.call("is_complete")):
		_complete_lesson()
		return
	var asset: String = String(_current_step.get("visualAssetId", ""))
	_show_card(asset)
	_request_turn("", ScriptedProviderScript.PHASE_OPEN)


func _request_turn(transcript: String, phase: String) -> void:
	_pending_phase = phase
	_pending_transcript = transcript
	_provider.call("submit_turn", transcript, {
		"phase": phase, "lessonId": _lesson_id, "step": _current_step,
		"progress": _engine.call("progress"),
	})


func _on_turn_ready(raw_turn: Dictionary) -> void:
	var turn: Dictionary = TurnValidator.coerce(raw_turn)
	_speak_turn(turn)


func _on_provider_failed(reason: String) -> void:
	# The contract's rule: a failing provider shows "Let's try together!" and
	# offers the local scripted path -- which is also what this scene runs, so
	# recovering means rebuilding the scripted provider and re-opening the step.
	push_warning("tutor provider failed: %s" % reason)
	_hud.call("set_banner", HudScript.BANNER_TOGETHER)
	_provider = ScriptedProviderScript.new()
	_provider.call("set_engine", _engine)
	_provider.turn_ready.connect(_on_turn_ready)
	_provider.provider_failed.connect(_on_provider_failed)
	_provider.call("begin_session", _lesson_id)
	_speak_turn(TurnValidator.fallback_turn())


func _speak_turn(turn: Dictionary) -> void:
	_current_turn = turn
	_turn_log.append(turn)
	var phase: String = _pending_phase
	if phase == ScriptedProviderScript.PHASE_OPEN and String(_current_step.get("kind", "")) == "ask":
		_last_question = turn
	_outcome_was_correct = phase == ScriptedProviderScript.PHASE_ANSWER \
			and String(turn.get("emotion", "")) == "happy" \
			and String(turn.get("lessonAction", "")) == "next_question"
	var visual: Dictionary = turn.get("visual", {})
	if String(visual.get("type", "none")) != "none":
		_show_card(String(visual.get("assetId", "")))
	_set_state(STATE_SPEAKING)
	_hud.call("set_banner", HudScript.BANNER_NONE)
	if phase == ScriptedProviderScript.PHASE_TIMEOUT or phase == ScriptedProviderScript.PHASE_TOGETHER \
			or String(turn.get("speech", "")).begins_with("Let's try together"):
		_hud.call("set_banner", HudScript.BANNER_TOGETHER)
	_hud.call("set_subtitle", String(turn.get("subtitle", turn.get("speech", ""))))
	_hud.call("set_mic_enabled", false)
	_face(String(turn.get("emotion", "neutral")))
	_gesture(String(turn.get("gesture", "none")))
	_set_speaking(true)
	var line_id: String = ""
	if phase == ScriptedProviderScript.PHASE_OPEN:
		line_id = String(_current_step.get("spokenLineId", ""))
	_synth.call("speak_turn", turn, line_id)
	turn_spoken.emit(turn)


func _on_speech_finished(_text: String) -> void:
	_set_speaking(false)
	if _state != STATE_SPEAKING:
		return
	_hud.call("set_subtitle", "")
	_after_turn()


## The boundary: the turn has been heard; apply its lessonAction.
func _after_turn() -> void:
	var action: String = String(_current_turn.get("lessonAction", "retry"))
	if _quota_exhausted():
		_end_requested = true
		if _quota.has_method("request_end_at_boundary"):
			_quota.call("request_end_at_boundary")
		if _state == STATE_BREAK:
			return
	match action:
		"complete", "end_session":
			_complete_lesson()
		"next_question":
			if _outcome_was_correct:
				_outcome_was_correct = false
				_hud.call("set_banner", HudScript.BANNER_SUCCESS)
				_face("happy")
				_set_state(STATE_CELEBRATE)
				_timer = CELEBRATE_SECONDS
				return
			_advance_step()
		_:
			_start_listening()


func _advance_step() -> void:
	_engine.call("advance")
	if _engine.has_method("save_progress"):
		_engine.call("save_progress", _save_service())
	_open_step()


func _complete_lesson() -> void:
	_lesson_complete = true
	# The celebrate step is the last one; step past it so the engine's own
	# progress says completed, which is what `tutorProgress` persists.
	if not bool(_engine.call("is_complete")):
		_engine.call("advance")
	if _engine.has_method("save_progress"):
		_engine.call("save_progress", _save_service())
	_hud.call("set_banner", HudScript.BANNER_SUCCESS)
	_face("happy")
	lesson_completed.emit(_engine.call("progress"))
	_show_break(not _quota_exhausted())


func _show_break(time_left: bool) -> void:
	_stop_listening()
	_synth.call("cancel")
	_hud.call("set_subtitle", "")
	_hud.call("set_mic_enabled", false)
	if _quota.has_method("end_session"):
		_quota.call("end_session")
	_set_state(STATE_BREAK)
	_hud.visible = false
	_break_card.call("open", time_left)


func _on_quota_expired() -> void:
	if _state == STATE_BREAK or _leaving:
		return
	_show_break(false)


func _on_learn_again() -> void:
	_break_card.call("close")
	_hud.visible = true
	begin_lesson(_lesson_id)


# ---------------------------------------------------------------------------
# Listening
# ---------------------------------------------------------------------------

func _start_listening() -> void:
	_nudged = false
	_timer = 0.0
	_last_failure_reason = ""
	_face("listening")
	var speech: Node = _speech_service()
	if speech != null and speech.has_method("is_available") and bool(speech.call("is_available")):
		_listening_live = true
		_set_state(STATE_LISTENING)
		_hud.call("set_banner", HudScript.BANNER_LISTENING)
		_hud.call("set_listening", true)
		speech.call("start_listening", _locale())
		return
	if _sim_enabled:
		_listening_live = false
		_set_state(STATE_LISTENING)
		_hud.call("set_banner", HudScript.BANNER_LISTENING)
		_hud.call("set_listening", true)
		return
	# No recognition on this device: the mic is a "say it with me" button.
	_listening_live = false
	_set_state(STATE_AWAIT_MIC)
	_hud.call("set_banner", HudScript.BANNER_NONE)
	_hud.call("set_listening", false)
	_hud.call("set_mic_enabled", true)


func _stop_listening() -> void:
	if _listening_live:
		var speech: Node = _speech_service()
		if speech != null and speech.has_method("stop_listening"):
			speech.call("stop_listening")
	_listening_live = false
	_hud.call("set_listening", false)


func _on_recognized(text: String) -> void:
	if _state != STATE_LISTENING or not _listening_live:
		return
	_listening_live = false
	_hud.call("set_listening", false)
	_think(text, ScriptedProviderScript.PHASE_ANSWER)


func _on_recognition_failed(reason: String) -> void:
	_last_failure_reason = reason


func _on_session_ended(outcome: String) -> void:
	if _state != STATE_LISTENING or not _listening_live:
		return
	if outcome == "recognized":
		return  # `_on_recognized` handled it
	_listening_live = false
	_hud.call("set_listening", false)
	if _last_failure_reason == "timeout":
		_think("", ScriptedProviderScript.PHASE_TIMEOUT)
		return
	# Anything else -- no permission, no plugin, an audio-session error -- is
	# the device's failure, not the child's silence, and is never counted as a
	# miss. The dev simulation keeps listening; the product falls back to the
	# tap-to-say-together mic.
	if _sim_enabled:
		_timer = 0.0
		return
	_set_state(STATE_AWAIT_MIC)
	_timer = 0.0
	_hud.call("set_banner", HudScript.BANNER_NONE)
	_hud.call("set_mic_enabled", true)


func _on_mic_pressed() -> void:
	match _state:
		STATE_AWAIT_MIC:
			_hud.call("set_mic_enabled", false)
			if _sim_enabled:
				_start_listening()
			else:
				_request_turn("", ScriptedProviderScript.PHASE_TOGETHER)
		STATE_LISTENING:
			pass
		_:
			pass


## A short "Thinking..." beat with a nod, then the transcript goes to the provider.
func _think(transcript: String, phase: String) -> void:
	_stop_listening()
	_pending_transcript = transcript
	_pending_phase = phase
	_set_state(STATE_THINKING)
	_hud.call("set_banner", HudScript.BANNER_THINKING)
	_face("thinking")
	_gesture("nod")
	_timer = THINK_SECONDS


# ---------------------------------------------------------------------------
# The frame
# ---------------------------------------------------------------------------

func advance(delta: float) -> void:
	if not _built or delta <= 0.0 or _leaving:
		return
	_synth.call("advance", delta)
	_hud.call("advance", delta)
	if _quota.has_method("tick") and _is_active_state():
		_quota.call("tick", delta)
	match _state:
		STATE_THINKING:
			_timer -= delta
			if _timer <= 0.0:
				_request_turn(_pending_transcript, _pending_phase)
		STATE_CELEBRATE:
			_timer -= delta
			if _timer <= 0.0:
				_hud.call("set_banner", HudScript.BANNER_NONE)
				_advance_step()
		STATE_LISTENING:
			if not _listening_live:
				_timer += delta
				if _timer >= LISTEN_SECONDS:
					_think("", ScriptedProviderScript.PHASE_TIMEOUT)
		STATE_AWAIT_MIC:
			_timer += delta
			if not _nudged and _timer >= NUDGE_SECONDS:
				_nudged = true
				_timer = 0.0
				repeat_prompt()
			elif _nudged and _timer >= NUDGE_SECONDS:
				_hud.call("set_mic_enabled", false)
				_request_turn("", ScriptedProviderScript.PHASE_TOGETHER)


func _is_active_state() -> bool:
	return _state in [STATE_SPEAKING, STATE_LISTENING, STATE_AWAIT_MIC, STATE_THINKING, STATE_CELEBRATE]


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

## Aliz says the current prompt again. Listening is closed first and reopened
## after the repeat, so the mic is never open while she speaks.
func repeat_prompt() -> void:
	if _state in [STATE_BREAK, STATE_PAUSED, STATE_DONE, STATE_IDLE]:
		return
	var turn: Dictionary = _last_question if not _last_question.is_empty() else _current_turn
	if turn.is_empty():
		return
	_stop_listening()
	_synth.call("cancel")
	_pending_phase = ScriptedProviderScript.PHASE_OPEN
	_speak_turn(turn)


func set_muted(muted: bool) -> void:
	_muted = muted
	_synth.call("set_muted", muted)
	if _hud != null and bool(_hud.call("is_muted")) != muted:
		_hud.call("set_muted", muted)
	var audio: Node = _autoload(AUDIO_PATH)
	if audio != null and audio.has_method("set_muted"):
		audio.call("set_muted", muted)


func is_muted() -> bool:
	return _muted


func _on_exit_requested() -> void:
	if _state == STATE_PAUSED:
		return
	_resume_state = _state
	_stop_listening()
	_synth.call("cancel")
	_hud.call("set_subtitle", "")
	_hud.call("set_banner", HudScript.BANNER_NONE)
	_set_state(STATE_PAUSED)


func _on_exit_kept() -> void:
	if _state != STATE_PAUSED:
		return
	if _resume_state == STATE_BREAK:
		_set_state(STATE_BREAK)
		return
	# Pick the lesson up by asking the current step again.
	_set_state(STATE_IDLE)
	_open_step()


func _on_exit_confirmed() -> void:
	_show_break(not _quota_exhausted())


## Home: always works, from every state.
func leave_to_home() -> bool:
	return _depart(HOME_SCENE_PATH, "home")


## Continue Playing: the house's Free Play, configured the way the title screen
## configures it. Falls back to Home when the house is not in this build.
func leave_to_free_play() -> bool:
	var main_script: Resource = load(MAIN_SCRIPT_PATH) if ResourceLoader.exists(MAIN_SCRIPT_PATH) else null
	if main_script is GDScript and (main_script as GDScript).has_method("free_play_scene_path"):
		var path: String = String((main_script as GDScript).call("free_play_scene_path"))
		if not path.is_empty() and ResourceLoader.exists(path):
			return _depart(path, "freePlay", main_script)
	return leave_to_home()


func _depart(path: String, target: String, main_script: Resource = null) -> bool:
	if _leaving:
		return false
	_leaving = true
	_last_departure = target
	_stop_listening()
	_synth.call("cancel")
	if _quota.has_method("end_session"):
		_quota.call("end_session")
	var save: Object = _save_service()
	if save != null and save.has_method("save_profile"):
		save.call("save_profile")
	_set_music(false)
	_set_state(STATE_DONE)
	left_scene.emit(target)
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	if tree == null:
		return true
	if main_script is GDScript and target == "freePlay":
		# The same hand-off `main.gd::_enter_scene()` performs, so Free Play
		# opens in FREE_PLAY mode with the saved room, not as a bare scene.
		var instance: Node = (main_script as GDScript).call("build_scene", path, 1, _unlocked_rooms(), _profile())
		if instance != null:
			tree.root.call_deferred("add_child", instance)
			tree.call_deferred("set_current_scene", instance)
			call_deferred("queue_free")
			return true
	tree.call_deferred("change_scene_to_file", path)
	return true


# ---------------------------------------------------------------------------
# Dev simulation
# ---------------------------------------------------------------------------

func enable_simulation(enabled: bool) -> void:
	_sim_enabled = enabled


func is_simulation_enabled() -> bool:
	return _sim_enabled


## Feeds a simulated transcript. Refused unless simulation is on, so nothing in
## normal play can fake a recognition result.
func simulate(kind: String) -> void:
	if not _sim_enabled:
		push_warning("tutor: simulated transcript refused; simulation is not enabled")
		return
	if _state == STATE_AWAIT_MIC:
		_start_listening()
	if _state != STATE_LISTENING:
		return
	match kind:
		HudScript.SIM_CORRECT:
			var answers: Array = _current_step.get("expectedAnswers", [])
			_think(String(answers[0]) if not answers.is_empty() else "yes", ScriptedProviderScript.PHASE_ANSWER)
		HudScript.SIM_WRONG:
			_think("a car", ScriptedProviderScript.PHASE_ANSWER)
		_:
			_think("", ScriptedProviderScript.PHASE_TIMEOUT)


# ---------------------------------------------------------------------------
# Face and card
# ---------------------------------------------------------------------------

func _face(expression: String) -> void:
	if _aliz == null:
		return
	if _aliz.has_method("set_expression"):
		_aliz.call("set_expression", expression)
	elif _aliz.has_method("set_face"):
		var mood: String = "content"
		if expression == "happy" or expression == "smile":
			mood = "happy"
		elif expression == "listening":
			mood = "surprised"
		_aliz.call("set_face", mood)


func _gesture(gesture: String) -> void:
	if _aliz == null or gesture == "none" or gesture.is_empty():
		return
	if _aliz.has_method("play_gesture"):
		_aliz.call("play_gesture", gesture)


func _set_speaking(active: bool) -> void:
	if _aliz != null and _aliz.has_method("set_speaking"):
		_aliz.call("set_speaking", active)


func _show_card(asset_id: String) -> void:
	_hud.call("set_card", asset_id)
	var board: Node = _classroom.call("get_board")
	if board != null:
		board.call("show_card", asset_id)


func _set_state(state: String) -> void:
	if _state == state:
		return
	_state = state
	state_changed.emit(state)


func _set_music(lesson: bool) -> void:
	var audio: Node = _autoload(AUDIO_PATH)
	if audio == null:
		return
	if lesson and audio.has_method("set_state"):
		audio.call("set_state", "miniGame")
	elif not lesson and audio.has_method("return_to_previous_state"):
		audio.call("return_to_previous_state")


# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------

## Through the main loop rather than `get_node("/root/...")`, which raises for
## a node that is not yet in the ACTIVE tree -- every node during the headless
## runner's `_initialize()`. `main.gd::_autoload()` makes the same choice.
func _autoload(path: String) -> Node:
	var tree: SceneTree = get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(path.trim_prefix("/root/"))


func _save_service() -> Object:
	if _save_override != null:
		return _save_override
	return _autoload(SAVE_SERVICE_PATH)


## A test seam: a dictionary-backed save service.
func set_save_service(save: Object) -> void:
	_save_override = save
	if _quota != null and _quota.has_method("set_save_service"):
		_quota.call("set_save_service", save)


func _speech_service() -> Node:
	return _autoload(SPEECH_SERVICE_PATH)


func _locale() -> String:
	var save: Object = _save_service()
	if save != null and save.has_method("get_setting"):
		return String(save.call("get_setting", "speechLocale", "en-US"))
	return "en-US"


func _quota_exhausted() -> bool:
	if _quota.has_method("is_exhausted"):
		return bool(_quota.call("is_exhausted"))
	var state: Dictionary = _quota.call("state")
	return float(state.get("remainingSeconds", 1.0)) <= 0.0


func _unlocked_rooms() -> Array:
	var profile: Variant = _profile()
	if typeof(profile) == TYPE_DICTIONARY and typeof((profile as Dictionary).get("unlockedRooms", null)) == TYPE_ARRAY:
		return ((profile as Dictionary)["unlockedRooms"] as Array).duplicate()
	return []


func _profile() -> Variant:
	var save: Object = _save_service()
	if save != null and save.has_method("get_profile"):
		return save.call("get_profile")
	return null


# ---------------------------------------------------------------------------
# Read-backs for tests and the shot harness
# ---------------------------------------------------------------------------

func state() -> String:
	return _state


func hud() -> Control:
	return _hud


func break_card() -> Control:
	return _break_card


func classroom() -> Node3D:
	return _classroom


func aliz() -> Node3D:
	return _aliz


func lesson_engine() -> Object:
	return _engine


func provider() -> Object:
	return _provider


func quota() -> Object:
	return _quota


func synthesis() -> Node:
	return _synth


func current_turn() -> Dictionary:
	return _current_turn


func current_step() -> Dictionary:
	return _current_step


func turn_log() -> Array:
	return _turn_log


func is_lesson_complete() -> bool:
	return _lesson_complete


func using_real_engine() -> bool:
	return _using_real_engine


func last_departure() -> String:
	return _last_departure


func is_seated() -> bool:
	return _seat != null and bool(_seat.call("is_seated"))


func get_camera() -> Camera3D:
	return _camera


## Where the base of Aliz's head is, in scene space: the Head bone's rest,
## lowered by the seat pose's hip drop, through the skeleton's transform. Read
## off the REST rather than the live pose on purpose -- a `SkeletonModifier3D`'s
## result is applied for skinning and then unwound, so the live pose reads as
## standing even while she is drawn seated. Falls back to the classroom's
## constant without a rig.
func head_position() -> Vector3:
	if _aliz != null and _aliz.has_method("get_skeleton"):
		var skeleton: Skeleton3D = _aliz.call("get_skeleton") as Skeleton3D
		if skeleton != null:
			var head: int = skeleton.find_bone("Head")
			if head >= 0:
				var rest: Vector3 = skeleton.get_bone_global_rest(head).origin
				if is_seated():
					rest.y -= SeatPoseScript.HIP_DROP
				return _scene_transform_of(skeleton) * rest
	return ClassroomScript.ALIZ_SEATED_HEAD


## `node`'s transform relative to this scene root, composed by hand so it is
## right before the scene is in a tree (where `global_transform` is identity).
func _scene_transform_of(node: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != self:
		if cursor is Node3D:
			result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return transform * result


## Her face on screen, as a rect the HUD must keep clear of: from the base of
## the head 0.36 m up (the top of her hair) and 0.06 m down (the chin), 0.18 m
## either side, projected through the scene's camera. Projected by hand
## (`Projection.create_perspective` + the camera's transform) rather than with
## `Camera3D.unproject_position()`, so it answers for any `viewport_size`
## without a rendered viewport -- which is how the layout test asks at both
## shipped aspect ratios in one headless run.
func face_screen_rect(viewport_size: Vector2 = Vector2.ZERO) -> Rect2:
	if _camera == null:
		return Rect2()
	var size: Vector2 = viewport_size
	if size.x <= 0.0 or size.y <= 0.0:
		var viewport: Viewport = get_viewport() if is_inside_tree() else null
		if viewport == null:
			return Rect2()
		size = viewport.get_visible_rect().size
	var head: Vector3 = head_position()
	var right: Vector3 = _camera.transform.basis.x
	var up: Vector3 = Vector3.UP
	var points: Array = [
		head + right * 0.18 + up * 0.36, head - right * 0.18 + up * 0.36,
		head + right * 0.18 - up * 0.06, head - right * 0.18 - up * 0.06,
	]
	var rect: Rect2 = Rect2(project_point(points[0], size), Vector2.ZERO)
	for p: Vector3 in points:
		rect = rect.expand(project_point(p, size))
	return rect


## A scene-space point to viewport pixels through this scene's camera.
func project_point(point: Vector3, viewport_size: Vector2) -> Vector2:
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	var projection: Projection = Projection.create_perspective(_camera.fov, aspect, _camera.near, _camera.far, false)
	var view: Vector3 = _camera.transform.affine_inverse() * point
	var clip: Vector4 = projection * Vector4(view.x, view.y, view.z, 1.0)
	if is_zero_approx(clip.w):
		return Vector2.ZERO
	var ndc: Vector2 = Vector2(clip.x, clip.y) / clip.w
	return Vector2((ndc.x + 1.0) * 0.5 * viewport_size.x, (1.0 - ndc.y) * 0.5 * viewport_size.y)


