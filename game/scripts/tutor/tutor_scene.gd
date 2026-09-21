extends Node3D

## ALIZ TUTOR MODE -- the classroom scene's orchestrator, HANDS-FREE.
##
##   TutorVoiceSession (mic, turn-taking) --> transcript
##       LessonEngine -> ConversationProvider -> TutorTurn (validated)
##           -> SpeechSynthesisProvider (Voice / TTS) -> Aliz's face + hands
##
## The child presses nothing per turn. Entering the classroom starts the voice
## session, Aliz welcomes the child ("Hi! What would you like to learn
## today?"), the child names a subject (or Aliz picks one after a gentle
## repeat), and the lesson runs as a conversation: Aliz asks, the microphone
## is live, the child answers, Aliz answers back. The child may interrupt
## when the session supports barge-in: Aliz stops, turns, and listens.
##
## Everything the child hears passed through `tutor_turn.gd` first. The
## engine owns progression (`advance()` is called here, at a boundary, never
## by a provider). The quota (`TutorQuota`) counts active seconds and may end
## the lesson only at a boundary -- with Aliz's own friendly closing, never a
## cut. Home and End lesson always work, from every state.
##
## ## Microphone scope (addendum, test-enforced)
##
## Capture only between `session.start()` and `session.stop()`: after Home,
## after End, after the closing, and the moment the app goes to the
## background -- where the session is stopped and NOT reopened on return; a
## "Welcome back -- tap to continue" card asks the child first.
##
## ## Honest fallbacks
##
## No recogniser (permission denied, no plugin, the headless suite): the
## indicator says "Mic off", the answer cards appear for every question and
## the big Tap-to-talk button says the word together with the child. The
## parent's `handsFreeMode` off: Tap-to-talk opens one push-to-talk turn.
## A provider failure: "Let's try together!" and the scripted path. Nothing
## here ever fakes a transcript; the DEV simulation goes through the voice
## session's test hook and is refused unless explicitly enabled.
##
## ## Seams
##
## `advance(delta)` is the frame; `_process()` calls it and tests call it.
## The engine, the voice session and the quota are the real classes when
## their files exist (`ResourceLoader.exists()`), stubs from `classroom/`
## otherwise, so Agents A, E and F land without a change here.

const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const ScriptedProviderScript := preload("res://scripts/tutor/providers/scripted_conversation_provider.gd")
const SynthesisScript := preload("res://scripts/tutor/providers/local_synthesis_provider.gd")
const ClassroomScript := preload("res://scripts/tutor/classroom/classroom_builder.gd")
const SeatPoseScript := preload("res://scripts/tutor/classroom/tutor_seat_pose.gd")
const EngineStubScript := preload("res://scripts/tutor/classroom/lesson_engine_stub.gd")
const LocalSessionScript := preload("res://scripts/tutor/classroom/local_voice_session.gd")
const FlashcardArt := preload("res://scripts/tutor/classroom/flashcard_art.gd")
const HudScript := preload("res://scripts/tutor/ui/tutor_hud.gd")
const IndicatorScript := preload("res://scripts/tutor/ui/tutor_mic_indicator.gd")
const BreakCardScript := preload("res://scripts/tutor/ui/tutor_break_card.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const LESSON_ENGINE_PATH: String = "res://scripts/tutor/lesson/lesson_engine.gd"
const TUTOR_QUOTA_PATH: String = "res://scripts/tutor/quota/tutor_quota.gd"
const VOICE_SESSION_PATH: String = "res://scripts/tutor/voice/tutor_voice_session.gd"
const SUBJECTS_PATH: String = "res://content/tutor/subjects.json"
const ALIZ_SCENE_PATH: String = "res://scenes/characters/buddy/PinkGirlBuddy.tscn"
const MAIN_SCRIPT_PATH: String = "res://scenes/main/main.gd"
const HOME_SCENE_PATH: String = "res://scenes/main/main.tscn"
const DEFAULT_LESSON_ID: String = "english_colors_fruits"
const SIM_USER_ARG: String = "--tutor-sim"
const SAVE_SERVICE_PATH: String = "/root/SaveService"
const SPEECH_SERVICE_PATH: String = "/root/SpeechService"
const AUDIO_PATH: String = "/root/Audio"
const VOICE_PATH: String = "/root/Voice"
const TTS_PATH: String = "/root/TtsService"
const HANDS_FREE_SETTING: String = "handsFreeMode"

## The shot: across the table from Aliz, a child's eye height, looking a
## little down so the table top and the board are both in frame.
const CAMERA_POSITION: Vector3 = Vector3(0.0, 1.5, 3.1)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 1.0, -0.8)
const CAMERA_FOV: float = 36.0
## The sun: front-left, high, no shadows.
const LIGHT_FROM: Vector3 = Vector3(-2.0, 4.0, 3.5)
const LIGHT_AT: Vector3 = Vector3(0.0, 0.8, -0.6)

## Silence handling while the mic is live: after this long with no speech
## Aliz asks the question again, once; after the full window it counts as an
## unanswered turn ("Let's try together!" + the hint), never a fail.
const NO_SPEECH_PROMPT_SECONDS: float = 3.0
const LISTEN_SECONDS: float = 8.0
## The "thinking" beat: long enough to read as a nod, too short to feel slow.
const THINK_SECONDS: float = 0.45
## How long "Great job!" stays up after a correct answer's speech.
const CELEBRATE_SECONDS: float = 1.1
## Push-to-talk / say-together: without recognition the tap waits; after
## this long Aliz repeats the question once, and after as long again says it
## with the child.
const NUDGE_SECONDS: float = 10.0

const WELCOME_TEXT: String = "Hi! What would you like to learn today?"
const WELCOME_AGAIN_TEXT: String = "We can learn fruits, numbers, colors or animals. What would you like?"
const CLOSING_TEXT: String = "Great job today! Come back tomorrow for more Little Days! Let's keep playing with Bunny!"

## Subject routing for the welcome question, keyed by subjectId.
const SUBJECT_KEYWORDS: Dictionary = {
	"english_basics": ["english", "fruit", "fruits", "apple", "banana", "words", "word"],
	"numbers": ["number", "numbers", "count", "counting", "one", "two", "three"],
	"colors": ["color", "colors", "colour", "colours", "red", "blue", "yellow", "green"],
	"animals": ["animal", "animals", "cat", "dog", "pets", "pet", "kitty", "puppy"],
	"everyday_life": ["cup", "spoon", "everyday", "things", "home"],
}
const SUBJECT_CARDS: Dictionary = {
	"english_basics": "apple_red", "numbers": "number_1", "colors": "color_blue", "animals": "cat",
}

const PHASE_WELCOME: String = "welcome"
const PHASE_CHOSEN: String = "chosen"
const PHASE_CLOSING: String = "closing"
const PHASE_CELEBRATE: String = "celebrate"

const STATE_IDLE: String = "idle"
const STATE_SPEAKING: String = "speaking"
const STATE_LISTENING: String = "listening"
const STATE_AWAIT_MIC: String = "awaitMic"
const STATE_THINKING: String = "thinking"
const STATE_CELEBRATE: String = "celebrate"
const STATE_BREAK: String = "break"
const STATE_PAUSED: String = "paused"
const STATE_BACKGROUND: String = "background"
const STATE_DONE: String = "done"

signal state_changed(state: String)
signal turn_spoken(turn: Dictionary)
signal lesson_completed(progress: Dictionary)
signal left_scene(target: String)

var _classroom: Node3D = null
var _aliz: Node3D = null
## The lesson an interjection asked to switch to, applied at the boundary.
var _switch_target: String = ""
var _board_asset: String = ""
## Set for the instant a barge-in cuts Aliz: the synthesis provider's cancel()
## emits `finished` synchronously, and that must NOT run the boundary logic.
var _interrupted: bool = false
## A correct answer whose praise was cut short is still a correct answer: its
## advance is applied when the interruption has been handled.
var _deferred_action: String = ""
var _seat: SkeletonModifier3D = null
var _hud: Control = null
var _break_card: Control = null
var _engine: Object = null
var _provider: Object = null
var _synth: Node = null
var _quota: Object = null
var _session: Object = null
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
var _child_talking: bool = false
var _push_to_talk_live: bool = false
var _choosing: bool = false
var _welcomed_twice: bool = false
var _sim_enabled: bool = false
var _muted: bool = false
var _built: bool = false
var _leaving: bool = false
var _last_departure: String = ""
var _outcome_was_correct: bool = false
## DEV: photographed from an unfocused desktop window, the scene must not
## treat focus loss as a mobile background (the harnesses set this).
var ignore_desktop_focus: bool = false
## Correct answers since the lesson began: the break card's stars (QA C3).
var _correct_this_session: int = 0
var _using_real_engine: bool = false
var _using_real_session: bool = false
var _turn_log: Array = []
var _lesson_complete: bool = false
var _closing: bool = false
var _resume_needed: bool = false
var _save_override: Object = null
var _last_failure_reason: String = ""
var _subjects: Array = []
var _lip_sync: Node = null
var _no_recogniser_forced: bool = false


func _ready() -> void:
	build()
	if OS.get_cmdline_user_args().has(SIM_USER_ARG):
		enable_simulation(true)
		_hud.call("set_dev_panel_visible", true)
	begin_lesson(_lesson_id)


func _process(delta: float) -> void:
	advance(delta)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN:
			# Desktop focus is not a mobile background. With simulated child
			# audio (dev harnesses, no real mic) an unfocused window must not
			# end the lesson; the background rule itself is still exercised
			# through go_background() and the PAUSED/RESUMED pair.
			if _sim_enabled or ignore_desktop_focus:
				return
			if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
				go_background()
			else:
				return_from_background()
		NOTIFICATION_APPLICATION_PAUSED:
			go_background()
		NOTIFICATION_APPLICATION_RESUMED:
			return_from_background()


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

	_session = _make_session()
	_subjects = _load_subjects()

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
	_hud.tap_to_talk_pressed.connect(_on_tap_to_talk)
	_hud.answer_card_tapped.connect(_on_answer_card)
	_hud.exit_requested.connect(_on_exit_requested)
	_hud.exit_kept.connect(_on_exit_kept)
	_hud.exit_confirmed.connect(_on_exit_confirmed)
	_hud.resume_pressed.connect(_on_resume_pressed)
	_hud.sim_requested.connect(simulate)

	_break_card = BreakCardScript.new()
	layer.add_child(_break_card)
	_break_card.call("build")
	_break_card.continue_playing_pressed.connect(leave_to_free_play)
	_break_card.home_pressed.connect(leave_to_home)
	_break_card.learn_again_pressed.connect(_on_learn_again)

	_bind_lip_sync()


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


## Aliz's mouth follows what is actually playing: the Voice bus when the
## director exists, the platform voice's envelope otherwise. All guarded.
func _bind_lip_sync() -> void:
	if _aliz == null or not _aliz.has_method("get_lip_sync"):
		return
	_lip_sync = _aliz.call("get_lip_sync") as Node
	if _lip_sync == null:
		return
	var voice: Node = _autoload(VOICE_PATH)
	if voice != null and voice.has_method("get_player") and _lip_sync.has_method("attach"):
		var player: AudioStreamPlayer = voice.call("get_player", "aliz") as AudioStreamPlayer
		if player != null:
			_lip_sync.call("attach", player)
	var tts: Node = _autoload(TTS_PATH)
	if tts != null and _lip_sync.has_method("attach_tts"):
		_lip_sync.call("attach_tts", tts)


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


func _make_session() -> Object:
	var session: Object = null
	if ResourceLoader.exists(VOICE_SESSION_PATH):
		var script: Resource = load(VOICE_SESSION_PATH)
		if script is GDScript and (script as GDScript).can_instantiate():
			var candidate: Object = (script as GDScript).new()
			if candidate != null and candidate.has_method("start") and candidate.has_method("get_input_level"):
				session = candidate
				_using_real_session = true
	if session == null:
		session = LocalSessionScript.new()
		_using_real_session = false
	if session is Node:
		(session as Node).name = "VoiceSession"
		add_child(session)
	_connect_if(session, "child_speech_started", _on_child_speech_started)
	_connect_if(session, "child_speech_ended", _on_child_speech_ended)
	_connect_if(session, "partial_transcript", _on_partial_transcript)
	_connect_if(session, "barge_in", _on_barge_in)
	_connect_if(session, "long_pause", _on_long_pause)
	_connect_if(session, "session_ended", _on_session_ended)
	return session


func _make_quota() -> Object:
	var save: Object = _save_service()
	if ResourceLoader.exists(TUTOR_QUOTA_PATH):
		var script: Resource = load(TUTOR_QUOTA_PATH)
		if script is GDScript and (script as GDScript).can_instantiate():
			var quota: Object = (script as GDScript).new(save)
			if quota != null and quota.has_method("begin_session") and quota.has_method("boundary_reached"):
				_connect_if(quota, "expired", _on_quota_expired)
				return quota
	return null


static func _connect_if(object: Object, signal_name: String, target: Callable) -> void:
	if object != null and object.has_signal(signal_name) and not object.is_connected(signal_name, target):
		object.connect(signal_name, target)


func _load_subjects() -> Array:
	if not FileAccess.file_exists(SUBJECTS_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SUBJECTS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var subjects: Variant = (parsed as Dictionary).get("subjects", [])
	return subjects if typeof(subjects) == TYPE_ARRAY else []


# ---------------------------------------------------------------------------
# Lesson flow
# ---------------------------------------------------------------------------

## Enters the classroom: opens the quota session, starts the voice session
## and has Aliz welcome the child. `lesson_id` is the lesson Aliz falls back
## to when the child does not name a subject.
func begin_lesson(lesson_id: String = DEFAULT_LESSON_ID) -> void:
	build()
	_lesson_id = lesson_id if not lesson_id.is_empty() else DEFAULT_LESSON_ID
	_lesson_complete = false
	_closing = false
	_choosing = true
	_correct_this_session = 0
	_welcomed_twice = false
	_turn_log.clear()
	_current_step = {}
	_last_question = {}
	if _quota == null:
		_quota = _make_quota()
	if _quota != null and _quota.has_method("set_lesson_id"):
		_quota.call("set_lesson_id", _lesson_id)
	if _quota != null and not bool(_quota.call("begin_session")):
		# Nothing left today: Aliz's closing, then the card. No mic is opened.
		_hud.visible = true
		_set_music(true)
		_speak_closing()
		return
	if _quota != null and _quota.has_method("request_end_at_boundary"):
		_quota.call("request_end_at_boundary")
	_set_music(true)
	_start_session()
	_provider.call("begin_session", _lesson_id)
	_show_card("")
	_pending_phase = PHASE_WELCOME
	_speak_turn(TurnValidator.make(WELCOME_TEXT, "smile", "wave", "retry"))


func _start_session() -> void:
	if _session == null:
		return
	if _session.has_method("enable_simulation"):
		_session.call("enable_simulation", _sim_enabled)
	if _session.has_method("mute"):
		_session.call("mute", _muted)
	# The real TutorVoiceSession runs CAPTURE-ONLY under this scene: it owns the
	# microphone, the VAD, the echo gate and barge-in; the scene keeps the
	# lesson loop. The classroom is entered after the grown-ups gate on the
	# title path, so the gate is recorded as passed here.
	if _session.has_method("set_face") and _aliz != null:
		_session.call("set_face", _aliz)
	if _session.has_method("set_level_source"):
		var speech: Node = _autoload(SPEECH_SERVICE_PATH)
		if speech != null and speech.has_method("get_input_level"):
			_session.call("set_level_source", Callable(speech, "get_input_level"))
	_session.call("start", _lesson_id, {
		"handsFree": _hands_free_setting(),
		"gatePassed": true,
		"captureOnly": true,
		"simulation": _sim_enabled,
	})
	_refresh_input_mode()


## Loads `lesson_id` into the engine (restarting a lesson the child already
## finished) and opens its first step.
func _load_and_open(lesson_id: String) -> void:
	_choosing = false
	_lesson_id = lesson_id
	if not bool(_engine.call("load_lesson", lesson_id)):
		if lesson_id != DEFAULT_LESSON_ID and bool(_engine.call("load_lesson", DEFAULT_LESSON_ID)):
			_lesson_id = DEFAULT_LESSON_ID
		else:
			_engine = EngineStubScript.new()
			_engine.call("load_lesson", lesson_id)
			_provider.call("set_engine", _engine)
	if _engine.has_method("load_progress"):
		_engine.call("load_progress", _save_service())
	if bool(_engine.call("is_complete")) and _engine.has_method("restart"):
		_engine.call("restart")
	if _quota != null and _quota.has_method("set_lesson_id"):
		_quota.call("set_lesson_id", _lesson_id)
	_open_step()


## Asks the provider to present the current step.
func _open_step() -> void:
	_current_step = _engine.call("current_step")
	if _current_step.is_empty() or bool(_engine.call("is_complete")):
		_complete_lesson()
		return
	var asset: String = String(_current_step.get("visualAssetId", ""))
	_show_card(asset)
	_tell_session_expected_answer()
	_request_turn("", ScriptedProviderScript.PHASE_OPEN)


func _request_turn(transcript: String, phase: String) -> void:
	_pending_phase = phase
	_pending_transcript = transcript
	_provider.call("submit_turn", transcript, {
		"phase": phase, "lessonId": _lesson_id, "step": _current_step,
		"progress": _engine.call("progress"),
	})


func _on_turn_ready(raw_turn: Dictionary) -> void:
	_speak_turn(TurnValidator.coerce(raw_turn))


func _on_provider_failed(reason: String) -> void:
	# The contract's rule: a failing provider shows "Let's try together!" and
	# offers the local scripted path -- which is also what this scene runs, so
	# recovering means rebuilding the scripted provider and carrying on.
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
	elif phase == PHASE_WELCOME:
		_last_question = turn
	_outcome_was_correct = phase == ScriptedProviderScript.PHASE_ANSWER \
			and String(turn.get("emotion", "")) == "happy" \
			and String(turn.get("lessonAction", "")) in ["next_question", "complete"]
	if _outcome_was_correct:
		_correct_this_session += 1
	var visual: Dictionary = turn.get("visual", {})
	if String(visual.get("type", "none")) != "none":
		_show_card(String(visual.get("assetId", "")))
	_child_talking = false
	_hud.call("hide_answer_cards")
	_set_state(STATE_SPEAKING)
	_hud.call("set_banner", HudScript.BANNER_NONE)
	if phase == ScriptedProviderScript.PHASE_TIMEOUT or phase == ScriptedProviderScript.PHASE_TOGETHER \
			or String(turn.get("speech", "")).begins_with("Let's try together"):
		_hud.call("set_banner", HudScript.BANNER_TOGETHER)
	_hud.call("set_subtitle", String(turn.get("subtitle", turn.get("speech", ""))))
	_hud.call("set_tap_to_talk_enabled", false)
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
	if _interrupted or _state != STATE_SPEAKING:
		return
	_hud.call("set_subtitle", "")
	_after_turn()


## The boundary: the turn has been heard; apply its lessonAction.
func _after_turn() -> void:
	var phase: String = _pending_phase
	if phase == PHASE_CLOSING:
		_finish_closing()
		return
	if _quota != null and _quota.has_method("boundary_reached") and bool(_quota.call("boundary_reached")):
		_speak_closing()
		return
	if phase == PHASE_WELCOME:
		_start_listening()
		return
	if phase == PHASE_CHOSEN:
		_load_and_open(_lesson_id)
		return
	if phase == PHASE_CELEBRATE:
		_finish_lesson()
		return
	var action: String = String(_current_turn.get("lessonAction", "retry"))
	match action:
		"jump_step":
			# handle_interjection() already moved the engine ("Okay! Let's see
			# the dog!"): open the step it is now on, card and all.
			_open_step()
		"switch_lesson":
			var target: String = String(_current_turn.get("nextLessonId", _switch_target))
			_switch_target = ""
			if not target.is_empty() and _engine.has_method("switch_lesson") \
					and bool(_engine.call("switch_lesson", target, _save_service())):
				_lesson_id = target
				if _quota != null and _quota.has_method("set_lesson_id"):
					_quota.call("set_lesson_id", target)
			_open_step()
		"complete", "end_session":
			if _outcome_was_correct:
				_outcome_was_correct = false
				_hud.call("set_banner", HudScript.BANNER_SUCCESS)
				_face("happy")
			_complete_lesson()
		"next_question":
			if _outcome_was_correct:
				_outcome_was_correct = false
				_hud.call("set_banner", HudScript.BANNER_SUCCESS)
				_face("happy")
				_set_state(STATE_CELEBRATE)
				_timer = CELEBRATE_SECONDS
				# Nothing heard in this beat is judged, so do not listen (QA C7):
				# the session stays gated until the next question opens the mic.
				if _session != null and _session.has_method("set_aliz_speaking"):
					_session.call("set_aliz_speaking", true)
				return
			_advance_step()
		_:
			_start_listening()


func _advance_step() -> void:
	_engine.call("advance")
	if _engine.has_method("save_progress"):
		_engine.call("save_progress", _save_service())
	_open_step()


## The lesson is done: Aliz says the lesson's own celebration line, then the
## card. The reward is granted by the engine's `save_progress()`.
func _complete_lesson() -> void:
	if _lesson_complete:
		_finish_lesson()
		return
	_lesson_complete = true
	# The engine says `complete` at the last question; step past whatever
	# trails it (a recap the celebration line replaces) so its own progress
	# reads completed and the reward is granted in the same save.
	var guard: int = 0
	while not bool(_engine.call("is_complete")) and guard < 64:
		guard += 1
		_engine.call("advance")
	if _engine.has_method("save_progress"):
		_engine.call("save_progress", _save_service())
	lesson_completed.emit(_engine.call("progress"))
	var line: String = "Great job today!"
	if _engine.has_method("completion_reward"):
		var reward: Dictionary = _engine.call("completion_reward")
		var celebration: String = String(reward.get("celebrationLine", "")).strip_edges()
		if not celebration.is_empty():
			line = celebration
	_pending_phase = PHASE_CELEBRATE
	_speak_turn(TurnValidator.make(line, "happy", "clap", "complete"))


func _finish_lesson() -> void:
	_hud.call("set_banner", HudScript.BANNER_SUCCESS)
	_face("happy")
	_show_break(not _quota_exhausted())


## The quota is used up (or the day started that way): Aliz's friendly
## closing, spoken, then the card. The session closes and the mic is released
## when the closing has been heard.
func _speak_closing() -> void:
	if _closing:
		return
	_closing = true
	_hud.call("hide_answer_cards")
	_pending_phase = PHASE_CLOSING
	_speak_turn(TurnValidator.make(CLOSING_TEXT, "happy", "wave", "end_session"))


func _finish_closing() -> void:
	_show_break(false)


func _show_break(time_left: bool) -> void:
	_stop_session("break")
	_synth.call("cancel")
	_hud.call("set_subtitle", "")
	_hud.call("hide_answer_cards")
	if _quota != null and _quota.has_method("end_session"):
		_quota.call("end_session", "lesson_complete" if time_left else "quota")
	_set_state(STATE_BREAK)
	_hud.visible = false
	_break_card.call("open", time_left, mini(3, _correct_this_session))


func _on_quota_expired() -> void:
	# The meter emits this from `boundary_reached()`, which `_after_turn()`
	# already answers with the closing; nothing else to do here.
	pass


func _on_learn_again() -> void:
	_break_card.call("close")
	_hud.visible = true
	_set_state(STATE_IDLE)
	begin_lesson(_lesson_id)


# ---------------------------------------------------------------------------
# Listening (hands-free) and its fallbacks
# ---------------------------------------------------------------------------

func _hands_free_setting() -> bool:
	var save: Object = _save_service()
	if save != null and save.has_method("get_setting"):
		return bool(save.call("get_setting", HANDS_FREE_SETTING, true))
	return true


## Whether the live session can capture on its own right now.
func _hands_free_live() -> bool:
	if _session == null or not _hands_free_setting() or _no_recogniser_forced:
		return false
	if _session.has_method("hands_free_available"):
		return bool(_session.call("hands_free_available"))
	return bool(_session.call("is_active"))


func _recogniser_available() -> bool:
	if _no_recogniser_forced:
		return false
	var speech: Node = _autoload(SPEECH_SERVICE_PATH)
	return speech != null and speech.has_method("is_available") and bool(speech.call("is_available"))


## DEV/test seam: behave as a device whose recogniser is denied or missing,
## so the touch fallback can be exercised on a Mac that has one.
func force_no_recogniser(forced: bool) -> void:
	_no_recogniser_forced = forced
	if _session != null and _session.has_method("force_unavailable"):
		_session.call("force_unavailable", forced)
	if _built:
		_refresh_input_mode()


## Sets the bottom-centre control to match the device: the indicator when
## hands-free runs (or the dev simulation stands in for it), Tap-to-talk
## otherwise.
func _refresh_input_mode() -> void:
	var live: bool = _hands_free_live() or _sim_enabled
	_hud.call("set_tap_to_talk_visible", not live)


func _start_listening() -> void:
	_nudged = false
	_timer = 0.0
	_child_talking = false
	_last_failure_reason = ""
	_face("listening")
	_tell_session_expected_answer()
	_refresh_input_mode()
	if _hands_free_live() or _sim_enabled:
		_set_state(STATE_LISTENING)
		_hud.call("set_banner", HudScript.BANNER_LISTENING)
		_hud.call("set_tap_to_talk_enabled", false)
		if not _hands_free_live():
			_offer_answer_cards()
		return
	# No hands-free: the tap is the way in, and the cards are the way out.
	_set_state(STATE_AWAIT_MIC)
	_hud.call("set_banner", HudScript.BANNER_NONE)
	_hud.call("set_tap_to_talk_enabled", true)
	if not _recogniser_available():
		_offer_answer_cards()


## Tap-to-talk: one push-to-talk turn when a recogniser exists, "say it
## together" when none does.
func _on_tap_to_talk() -> void:
	if _state != STATE_AWAIT_MIC:
		return
	_hud.call("set_tap_to_talk_enabled", false)
	if _recogniser_available():
		var speech: Node = _autoload(SPEECH_SERVICE_PATH)
		_connect_if(speech, "recognized", _on_push_to_talk_recognized)
		_connect_if(speech, "session_ended", _on_push_to_talk_ended)
		_connect_if(speech, "recognition_failed", _on_recognition_failed)
		_push_to_talk_live = true
		_set_state(STATE_LISTENING)
		_hud.call("set_banner", HudScript.BANNER_LISTENING)
		_hud.call("set_indicator", IndicatorScript.STATE_LISTENING, 0.3)
		speech.call("start_listening", _locale())
		return
	if _choosing:
		_choose_subject("")
		return
	_request_turn("", ScriptedProviderScript.PHASE_TOGETHER)


func _on_push_to_talk_recognized(text: String) -> void:
	if not _push_to_talk_live:
		return
	_push_to_talk_live = false
	_heard(text)


func _on_push_to_talk_ended(outcome: String) -> void:
	if not _push_to_talk_live or outcome == "recognized":
		return
	_push_to_talk_live = false
	if _last_failure_reason == "timeout":
		_heard("")
		return
	_set_state(STATE_AWAIT_MIC)
	_hud.call("set_banner", HudScript.BANNER_NONE)
	_hud.call("set_tap_to_talk_enabled", true)


func _on_recognition_failed(reason: String) -> void:
	_last_failure_reason = reason


## The touch fallback: on the choice, one card per subject that has a
## flashcard (Everyday Things has none yet); on a question, the right card
## and two others.
func _offer_answer_cards() -> void:
	if _choosing:
		var ids: Array = []
		for subject in _subjects:
			var card: String = String(SUBJECT_CARDS.get(String((subject as Dictionary).get("subjectId", "")), ""))
			if not card.is_empty() and ids.size() < HudScript.MAX_ANSWER_CARDS:
				ids.append(card)
		if ids.is_empty():
			ids = ["apple_red", "number_1", "color_blue", "cat"]
		_hud.call("show_answer_cards", ids)
		return
	if String(_current_step.get("kind", "")) != "ask":
		return
	var answer: String = String(_current_step.get("visualAssetId", ""))
	if answer.is_empty():
		return
	var pool: Array = TurnValidator.allowed_asset_ids().filter(func(id: String) -> bool: return id != answer)
	pool.sort()
	var seed: int = String(_current_step.get("stepId", "")).hash()
	var others: Array = []
	for i: int in range(2):
		if pool.is_empty():
			break
		others.append(pool.pop_at((seed + i * 7) % pool.size()))
	var cards: Array = [answer] + others
	# A stable, non-telling order: sort by id so the answer is not always first.
	cards.sort()
	_hud.call("show_answer_cards", cards)


func _on_answer_card(asset_id: String) -> void:
	if _state != STATE_LISTENING and _state != STATE_AWAIT_MIC:
		return
	if _choosing:
		for subject_id in SUBJECT_CARDS.keys():
			if String(SUBJECT_CARDS[subject_id]) == asset_id:
				_choose_subject(String(subject_id))
				return
		_choose_subject("")
		return
	_heard(FlashcardArt.word_for(asset_id))


# -- session signals --------------------------------------------------------

func _on_child_speech_started() -> void:
	if _state == STATE_LISTENING:
		_child_talking = true
		if _hud.call("banner_kind") != HudScript.BANNER_INTERRUPTED:
			_hud.call("set_banner", HudScript.BANNER_HEARING)
	elif _state == STATE_SPEAKING and _session != null and _session.has_method("supports_barge_in") \
			and bool(_session.call("supports_barge_in")):
		_on_barge_in()


func _on_partial_transcript(text: String) -> void:
	if _state == STATE_LISTENING:
		_child_talking = true
		# "I'm listening!" stays up through an interruption; partials show
		# softly on an ordinary turn.
		if _hud.call("banner_kind") != HudScript.BANNER_INTERRUPTED:
			_hud.call("show_partial", text)


func _on_child_speech_ended(transcript: String) -> void:
	if _state != STATE_LISTENING:
		return
	_heard(transcript)


## The child stayed quiet: Aliz asks the same thing again, kindly, and keeps listening.
func _on_long_pause() -> void:
	if _state != STATE_LISTENING or _closing:
		return
	repeat_prompt()


## The child interrupted Aliz: stop at once, turn, listen.
func _on_barge_in() -> void:
	if _state != STATE_SPEAKING or _closing:
		return
	# Remember what the cut turn owed the lesson: a correct answer's advance
	# must still happen once the interruption is dealt with.
	_deferred_action = ""
	if _outcome_was_correct:
		_deferred_action = String(_current_turn.get("lessonAction", "next_question"))
		_outcome_was_correct = false
	_interrupted = true
	_synth.call("cancel")
	_interrupted = false
	_set_speaking(false)
	_pending_phase = ScriptedProviderScript.PHASE_INTERJECTION
	_hud.call("set_subtitle", "")
	_face("listening")
	_gesture("tilt")
	_set_state(STATE_LISTENING)
	_child_talking = true
	_timer = 0.0
	_hud.call("set_banner", HudScript.BANNER_INTERRUPTED)


func _on_session_ended(reason: String) -> void:
	if reason == "background" or _leaving or _state in [STATE_BREAK, STATE_DONE, STATE_BACKGROUND]:
		return
	# The session dropped under us (device failure): fall back to the tap.
	if _state == STATE_LISTENING:
		_refresh_input_mode()


## A transcript arrived, from whichever path. Blank (a cough) keeps listening.
func _heard(transcript: String) -> void:
	var text: String = transcript.strip_edges()
	if text.is_empty():
		_child_talking = false
		_timer = 0.0
		if _state == STATE_LISTENING:
			_hud.call("set_banner", HudScript.BANNER_LISTENING)
		return
	if _choosing:
		_choose_subject(_route_subject(text))
		return
	# Interjections are what a BARGE-IN says. The engine's handle_interjection()
	# MOVES the lesson when it recognises a request, so it is consulted only for
	# a barge-in transcript; an ordinary answer is evaluated as an answer (a wrong
	# "banana" on the apple step is a miss, not a request to see the banana).
	var interjecting: bool = _pending_phase == ScriptedProviderScript.PHASE_INTERJECTION
	if interjecting and _engine.has_method("handle_interjection"):
		if not _sounds_like_a_request(text):
			# A bare word shouted over the question is an answer.
			_think(text, ScriptedProviderScript.PHASE_ANSWER)
			return
		var handled: Dictionary = _engine.call("handle_interjection", text)
		var action: String = String(handled.get("lessonAction", ""))
		if bool(handled.get("handled", false)):
			_switch_target = String(handled.get("nextLessonId", ""))
			_deferred_action = ""
			_pending_phase = ScriptedProviderScript.PHASE_ANSWER
			_speak_turn(TurnValidator.make(String(handled.get("line", "Okay!")), "happy", "nod",
				action if not action.is_empty() else "next_question", String(_current_step.get("visualAssetId", ""))))
			return
		if not bool(handled.get("isAnswer", false)):
			# An interruption that neither answers nor asks for anything else
			# ("look, a bird!") is never an attempt: finish what the cut turn
			# owed, then ask the question again.
			_resume_after_interjection()
			return
	elif _session != null and _session.has_method("is_stop_phrase") and bool(_session.call("is_stop_phrase", text)):
		# "I'm done" / "stop" from any turn ends the lesson kindly.
		_pending_phase = ScriptedProviderScript.PHASE_ANSWER
		_speak_turn(TurnValidator.make("Okay! Great job today! Bye bye!", "happy", "wave", "end_session",
				String(_current_step.get("visualAssetId", ""))))
		return
	_think(text, ScriptedProviderScript.PHASE_ANSWER)


const REQUEST_CUES: Array[String] = ["want", "show", "see", "let", "lets", "can", "no", "wait", "instead", "please", "again", "different", "other", "another"]


## True when an interruption reads as a request rather than a shouted answer.
static func _sounds_like_a_request(text: String) -> bool:
	var words: PackedStringArray = EngineStubScript.normalise(text).split(" ", false)
	if words.size() >= 3:
		return true
	for word: String in words:
		if REQUEST_CUES.has(word):
			return true
	return false


## After an interruption Aliz could not act on: apply the advance the cut
## praise owed (if any), then re-ask the current question. No attempt is spent.
func _resume_after_interjection() -> void:
	var owed: String = _deferred_action
	_deferred_action = ""
	_pending_phase = ScriptedProviderScript.PHASE_OPEN
	if owed == "next_question":
		_advance_step()
		return
	if owed == "complete" or owed == "end_session":
		_complete_lesson()
		return
	if not _last_question.is_empty():
		_speak_turn(_last_question)
	else:
		_open_step()


## A short "Thinking..." beat with a nod, then the transcript goes to the provider.
func _think(transcript: String, phase: String) -> void:
	_pending_transcript = transcript
	_pending_phase = phase
	_child_talking = false
	_hud.call("hide_answer_cards")
	_set_state(STATE_THINKING)
	_hud.call("set_banner", HudScript.BANNER_THINKING)
	_face("thinking")
	_gesture("nod")
	_timer = THINK_SECONDS


# -- the welcome and the subject choice -------------------------------------

func _route_subject(transcript: String) -> String:
	var said: String = " " + EngineStubScript.normalise(transcript) + " "
	for subject_id in SUBJECT_KEYWORDS.keys():
		for word in SUBJECT_KEYWORDS[subject_id]:
			if said.find(" " + String(word) + " ") >= 0:
				return String(subject_id)
	return ""


## Loads the chosen subject's first lesson; "" means the child did not name
## one -- Aliz asks once more, then picks the default herself.
func _choose_subject(subject_id: String) -> void:
	var lesson_id: String = ""
	var title: String = ""
	for subject in _subjects:
		var entry: Dictionary = subject
		if String(entry.get("subjectId", "")) == subject_id:
			var ids: Array = entry.get("lessonIds", [])
			if not ids.is_empty():
				lesson_id = String(ids[0])
				title = String(entry.get("title", ""))
	if lesson_id.is_empty():
		if not _welcomed_twice and not _subjects.is_empty():
			_welcomed_twice = true
			_pending_phase = PHASE_WELCOME
			_speak_turn(TurnValidator.make(WELCOME_AGAIN_TEXT, "encouraging", "tilt", "retry"))
			return
		lesson_id = _lesson_id
		title = ""
	_lesson_id = lesson_id
	_choosing = false
	_pending_phase = PHASE_CHOSEN
	var line: String = "Great! Let's learn %s!" % title if not title.is_empty() else "Great! Let's learn together!"
	_speak_turn(TurnValidator.make(line, "happy", "clap", "next_question"))


func _tell_session_expected_answer() -> void:
	if _session == null or not _session.has_method("set_expected_answer"):
		return
	var answer: String = "fruits"
	if not _choosing:
		var answers: Array = _current_step.get("expectedAnswers", [])
		answer = String(answers[0]) if not answers.is_empty() else "yes"
	_session.call("set_expected_answer", answer)


# ---------------------------------------------------------------------------
# The frame
# ---------------------------------------------------------------------------

func advance(delta: float) -> void:
	if not _built or delta <= 0.0 or _leaving:
		return
	_synth.call("advance", delta)
	_hud.call("advance", delta)
	if _session != null and _session.has_method("advance"):
		_session.call("advance", delta)
	_update_indicator()
	if _quota != null and _quota.has_method("tick") and _is_active_state():
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
			if _push_to_talk_live:
				return
			if _child_talking:
				return
			_timer += delta
			if not _nudged and _timer >= NO_SPEECH_PROMPT_SECONDS and _hands_free_live():
				_nudged = true
				repeat_prompt()
			elif _timer >= LISTEN_SECONDS:
				if _choosing:
					_choose_subject("")
				else:
					_think("", ScriptedProviderScript.PHASE_TIMEOUT)
		STATE_AWAIT_MIC:
			_timer += delta
			if not _nudged and _timer >= NUDGE_SECONDS:
				_nudged = true
				_timer = 0.0
				repeat_prompt()
			elif _nudged and _timer >= NUDGE_SECONDS:
				_hud.call("set_tap_to_talk_enabled", false)
				if _choosing:
					_choose_subject("")
				else:
					_request_turn("", ScriptedProviderScript.PHASE_TOGETHER)


func _update_indicator() -> void:
	var state: String = IndicatorScript.STATE_OFF
	var level: float = 0.0
	if _session != null and bool(_session.call("is_active")):
		level = float(_session.call("get_input_level"))
		if _muted:
			state = IndicatorScript.STATE_MUTED
		elif _state == STATE_SPEAKING:
			state = IndicatorScript.STATE_ALIZ
		elif _state == STATE_CELEBRATE:
			state = IndicatorScript.STATE_OFF
		elif _state == STATE_LISTENING and (_hands_free_live() or _sim_enabled or _push_to_talk_live):
			state = IndicatorScript.STATE_HEARING if _child_talking else IndicatorScript.STATE_LISTENING
		elif _hands_free_live():
			state = IndicatorScript.STATE_LISTENING
	elif _muted:
		state = IndicatorScript.STATE_MUTED
	_hud.call("set_indicator", state, level)


func _is_active_state() -> bool:
	return _state in [STATE_SPEAKING, STATE_LISTENING, STATE_AWAIT_MIC, STATE_THINKING, STATE_CELEBRATE]


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

## Aliz says the current prompt again; the mic reopens after it.
func repeat_prompt() -> void:
	if _state in [STATE_BREAK, STATE_PAUSED, STATE_BACKGROUND, STATE_DONE, STATE_IDLE] or _closing:
		return
	var turn: Dictionary = _last_question if not _last_question.is_empty() else _current_turn
	if turn.is_empty():
		return
	_synth.call("cancel")
	_pending_phase = PHASE_WELCOME if _choosing else ScriptedProviderScript.PHASE_OPEN
	_speak_turn(turn)


func set_muted(muted: bool) -> void:
	_muted = muted
	_synth.call("set_muted", muted)
	if _session != null and _session.has_method("mute"):
		_session.call("mute", muted)
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
	_synth.call("cancel")
	_set_speaking(false)
	_hud.call("set_subtitle", "")
	_hud.call("set_banner", HudScript.BANNER_NONE)
	_hud.call("hide_answer_cards")
	if _quota != null and _quota.has_method("pause_for"):
		_quota.call("pause_for", "confirm")
	_set_state(STATE_PAUSED)


func _on_exit_kept() -> void:
	if _state != STATE_PAUSED:
		return
	if _quota != null and _quota.has_method("resume_for"):
		_quota.call("resume_for", "confirm")
	if _resume_state == STATE_BREAK:
		_set_state(STATE_BREAK)
		return
	_set_state(STATE_IDLE)
	if _choosing:
		_pending_phase = PHASE_WELCOME
		_speak_turn(TurnValidator.make(WELCOME_TEXT, "smile", "wave", "retry"))
	else:
		_open_step()


func _on_exit_confirmed() -> void:
	if _quota != null and _quota.has_method("resume_for"):
		_quota.call("resume_for", "confirm")
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
	_stop_session("leave")
	_synth.call("cancel")
	_set_speaking(false)
	if _quota != null and _quota.has_method("end_session"):
		_quota.call("end_session", "leave")
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
# Mobile lifecycle
# ---------------------------------------------------------------------------

## The app went to the background: the mic closes now, the session stops,
## the meter stops counting. Public so a test can drive it.
func go_background() -> void:
	if not _built or _leaving or _state in [STATE_BREAK, STATE_DONE, STATE_BACKGROUND]:
		return
	_resume_state = _state
	_resume_needed = true
	_stop_session("background")
	_synth.call("cancel")
	_set_speaking(false)
	_hud.call("set_subtitle", "")
	_hud.call("set_banner", HudScript.BANNER_NONE)
	_hud.call("hide_answer_cards")
	if _quota != null and _quota.has_method("set_app_active"):
		_quota.call("set_app_active", false)
	_set_state(STATE_BACKGROUND)
	_update_indicator()


## Back in the foreground: the mic stays OFF until the child taps to continue.
func return_from_background() -> void:
	if not _resume_needed or _state != STATE_BACKGROUND:
		return
	_hud.call("show_resume_card", true)


func _on_resume_pressed() -> void:
	if _state != STATE_BACKGROUND:
		return
	_resume_needed = false
	if _quota != null and _quota.has_method("set_app_active"):
		_quota.call("set_app_active", true)
	_start_session()
	_set_state(STATE_IDLE)
	if _choosing:
		_pending_phase = PHASE_WELCOME
		_speak_turn(TurnValidator.make(WELCOME_TEXT, "smile", "wave", "retry"))
	else:
		_open_step()


func _stop_session(reason: String) -> void:
	_push_to_talk_live = false
	if _session != null and bool(_session.call("is_active")):
		_session.call("stop", reason)


# ---------------------------------------------------------------------------
# Dev simulation
# ---------------------------------------------------------------------------

func enable_simulation(enabled: bool) -> void:
	_sim_enabled = enabled
	if _session != null and _session.has_method("enable_simulation"):
		_session.call("enable_simulation", enabled)
	if _built:
		_refresh_input_mode()


func is_simulation_enabled() -> bool:
	return _sim_enabled


## DEV: simulated child audio, through the session's hook. Refused unless
## simulation is on, so nothing in normal play can fake a transcript.
func simulate(kind: String, transcript_override: String = "") -> void:
	if not _sim_enabled:
		push_warning("tutor: simulated audio refused; simulation is not enabled")
		return
	if _state == STATE_AWAIT_MIC:
		_start_listening()
	_tell_session_expected_answer()
	if _session != null and _session.has_method("simulate_child_audio"):
		# The hands-free session takes a level clip plus a transcript, so the
		# VAD and the barge-in gate run on the simulated audio too.
		var expected: Array = _current_step.get("expectedAnswers", [])
		var right: String = String(expected[0]) if not expected.is_empty() else "yes"
		if _choosing:
			right = "fruits"  # the simulated child picks English Basics, as documented
		var clip_name: String = "answer"
		var transcript: String = right
		match kind:
			"wrong":
				transcript = "banana" if right != "banana" else "apple"
			"cough":
				clip_name = "cough"
				transcript = ""
			"pause_then_finish", "pause":
				clip_name = "pause_then_finish"
			"interrupt":
				clip_name = "interrupt"
				transcript = "Wait! I want a dog!"
			"nothing", "silence":
				clip_name = "silence"
				transcript = ""
		if not transcript_override.is_empty():
			transcript = transcript_override
		var frames: Array = []
		var session_script: Script = _session.get_script()
		if session_script != null and session_script.has_method("preset_clip"):
			frames = session_script.call("preset_clip", clip_name)
		if frames.is_empty():
			frames = [[0.02, 200], [0.35, 700], [0.02, 1200]]
		_session.call("simulate_child_audio", frames, transcript)
		return
	# A session without hooks: emulate the signals it would have sent.
	if _state != STATE_LISTENING:
		return
	var answers: Array = _current_step.get("expectedAnswers", [])
	var answer: String = String(answers[0]) if not answers.is_empty() else "fruits"
	match kind:
		"correct", "pause_then_finish", "interrupt":
			_heard(answer)
		"wrong":
			_heard("a car")
		_:
			_heard("")


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
	if _session != null and _session.has_method("set_aliz_speaking"):
		_session.call("set_aliz_speaking", active)


func _show_card(asset_id: String) -> void:
	_board_asset = asset_id
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


## A test seam: a dictionary-backed save service. Rebuilds the quota on it.
func set_save_service(save: Object) -> void:
	_save_override = save
	_quota = _make_quota()


func _locale() -> String:
	var save: Object = _save_service()
	if save != null and save.has_method("get_setting"):
		return String(save.call("get_setting", "speechLocale", "en-US"))
	return "en-US"


func _quota_exhausted() -> bool:
	if _quota == null:
		return false
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


func voice_session() -> Object:
	return _session


func synthesis() -> Node:
	return _synth


func current_turn() -> Dictionary:
	return _current_turn


## The asset the board is showing right now, "" for none (tests).
func board_asset_id() -> String:
	return _board_asset


func current_step() -> Dictionary:
	return _current_step


func current_lesson_id() -> String:
	return _lesson_id


func is_choosing_subject() -> bool:
	return _choosing


func turn_log() -> Array:
	return _turn_log


func is_lesson_complete() -> bool:
	return _lesson_complete


func is_closing() -> bool:
	return _closing


func using_real_engine() -> bool:
	return _using_real_engine


func using_real_session() -> bool:
	return _using_real_session


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
