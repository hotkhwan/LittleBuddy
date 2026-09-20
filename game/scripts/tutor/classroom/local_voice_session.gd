extends Node

## THE FALLBACK TutorVoiceSession -- hands-free turn-taking over the on-device
## `SpeechService`, with the contract's surface (`docs/ALIZ_TUTOR_CONTRACTS.md`
## addendum), so the classroom runs hands-free today and swaps to Agent E's
## `scripts/tutor/voice/tutor_voice_session.gd` (VAD, streaming, barge-in,
## real input levels) the moment that file exists. `tutor_scene.gd` binds
## whichever is present through `has_method()` guards.
##
## What this one does, honestly:
##
##   * `start()` opens the session; while it is active, unmuted, and Aliz is
##     not speaking, it keeps a recogniser session open: every time the
##     service ends one (a result, a cap, a failure) the next opens after a
##     short gap. The child never presses anything. Capture happens ONLY
##     between `start()` and `stop()` -- never on the title screen, in Free
##     Play, in the background, after Exit or after quota expiry -- which is
##     the microphone-scope rule the addendum makes test-enforced.
##   * The mic is CLOSED while Aliz speaks (`set_aliz_speaking(true)`), because
##     `SpeechService.start_listening()` hushes the voice and this session has
##     no echo estimate to gate a barge-in against. So `supports_barge_in()` is
##     false here; the DEV hook can still simulate one.
##   * `get_input_level()` is SYNTHETIC: the service exposes no amplitude, and
##     a real meter needs the microphone bus Agent E's session will own. The
##     level idles low while listening, jumps on each partial and decays, and
##     is 0 when muted or off -- so the indicator is truthful about the state
##     of the microphone, which is what the rule requires, and the meter
##     becomes live when the real session lands.
##   * No recogniser at all (permission denied, no plugin, headless):
##     `hands_free_available()` is false, nothing is captured, and the scene
##     offers the touch fallback.
##
## Test hook: `simulate_child_audio(kind)` -- "correct" | "wrong" | "cough" |
## "pause_then_finish" | "interrupt" -- drives the same signals a recognised
## utterance drives. It works only after `enable_simulation(true)`; the
## product never fakes a transcript.

signal state_changed(from: String, to: String)
signal child_speech_started()
signal child_speech_ended(transcript: String)
signal partial_transcript(text: String)
signal barge_in()
signal session_ended(reason: String)
signal availability_changed(available: bool)

const STATE_IDLE: String = "idle"
const STATE_WELCOMING: String = "welcoming"
const STATE_LISTENING: String = "listening"
const STATE_CHILD_SPEAKING: String = "child_speaking"
const STATE_THINKING: String = "thinking"
const STATE_ALIZ_SPEAKING: String = "aliz_speaking"
const STATE_INTERRUPTED: String = "interrupted"
const STATE_MUTED: String = "muted"
const STATE_UNAVAILABLE: String = "unavailable"
const STATE_CLOSING: String = "closing"
const STATE_ENDED: String = "ended"

const SPEECH_SERVICE_PATH: String = "/root/SpeechService"
## The breath between one recogniser session ending and the next opening.
const REOPEN_GAP_SECONDS: float = 0.35
## Synthetic level shape (see the class doc).
const LEVEL_IDLE: float = 0.14
const LEVEL_PARTIAL: float = 0.85
const LEVEL_DECAY_PER_SEC: float = 1.6

const SIM_CORRECT: String = "correct"
const SIM_WRONG: String = "wrong"
const SIM_COUGH: String = "cough"
const SIM_PAUSE_THEN_FINISH: String = "pause_then_finish"
const SIM_INTERRUPT: String = "interrupt"
const SIM_WRONG_TEXT: String = "a car"

var _state: String = STATE_IDLE
var _active: bool = false
var _muted: bool = false
var _aliz_speaking: bool = false
var _lesson_id: String = ""
var _expected_answer: String = ""
var _level: float = 0.0
var _reopen_in: float = 0.0
var _service_live: bool = false
var _had_partial: bool = false
var _sim_enabled: bool = false
var _sim_pending: Array = []
var _breath: float = 0.0
var _forced_unavailable: bool = false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


# ---------------------------------------------------------------------------
# Contract surface
# ---------------------------------------------------------------------------

func start(lesson_id: String, _opts: Dictionary = {}) -> bool:
	_lesson_id = lesson_id
	_active = true
	_had_partial = false
	_bind_service()
	if not hands_free_available():
		_set_state(STATE_UNAVAILABLE)
		return false
	_set_state(STATE_MUTED if _muted else STATE_LISTENING)
	_reopen_in = 0.0
	return true


func stop(reason: String = "") -> void:
	if not _active:
		return
	_active = false
	_close_service_session()
	_level = 0.0
	_set_state(STATE_ENDED)
	session_ended.emit(reason)


func mute(muted: bool) -> void:
	_muted = muted
	if muted:
		_close_service_session()
		_level = 0.0
		if _active and _state != STATE_ALIZ_SPEAKING:
			_set_state(STATE_MUTED)
	elif _active and _state == STATE_MUTED:
		_set_state(STATE_LISTENING)


func is_muted() -> bool:
	return _muted


func is_active() -> bool:
	return _active


## True only while a recogniser session is genuinely open.
func is_capturing() -> bool:
	return _service_live


func get_state() -> String:
	return _state


func get_input_level() -> float:
	return _level


func supports_barge_in() -> bool:
	return false


## DEV/test seam: pretend the recogniser is denied or missing.
func force_unavailable(forced: bool) -> void:
	_forced_unavailable = forced
	if forced:
		_close_service_session()
		if _active:
			_set_state(STATE_UNAVAILABLE)


## Whether hands-free can run on this device right now.
func hands_free_available() -> bool:
	if _forced_unavailable:
		return false
	var speech: Node = _speech_service()
	return speech != null and speech.has_method("is_available") and bool(speech.call("is_available"))


## The scene tells the session when Aliz speaks; the mic stays shut meanwhile.
func set_aliz_speaking(speaking: bool) -> void:
	_aliz_speaking = speaking
	if not _active:
		return
	if speaking:
		_close_service_session()
		_set_state(STATE_ALIZ_SPEAKING)
	elif _muted:
		_set_state(STATE_MUTED)
	elif hands_free_available() or _sim_enabled:
		_set_state(STATE_LISTENING)
		_reopen_in = REOPEN_GAP_SECONDS


## The canonical answer for the step being asked, for the DEV hook only.
func set_expected_answer(answer: String) -> void:
	_expected_answer = answer


func enable_simulation(enabled: bool) -> void:
	_sim_enabled = enabled


func is_simulation_enabled() -> bool:
	return _sim_enabled


## True while a simulated utterance is still being delivered.
func is_simulating() -> bool:
	return not _sim_pending.is_empty()


## DEV: simulated child audio. Refused unless simulation is enabled.
func simulate_child_audio(kind: String) -> void:
	if not _sim_enabled or not _active:
		push_warning("tutor voice: simulated audio refused (simulation %s, active %s)" % [_sim_enabled, _active])
		return
	if _muted:
		return
	match kind:
		SIM_CORRECT:
			_sim_pending = [[0.0, "start"], [0.3, "partial", _expected_answer.left(2)], [0.7, "final", _expected_answer]]
		SIM_WRONG:
			_sim_pending = [[0.0, "start"], [0.3, "partial", "a"], [0.7, "final", SIM_WRONG_TEXT]]
		SIM_COUGH:
			_sim_pending = [[0.0, "start"], [0.25, "final", ""]]
		SIM_PAUSE_THEN_FINISH:
			_sim_pending = [[0.0, "start"], [0.3, "partial", _expected_answer.left(2)], [1.6, "final", _expected_answer]]
		SIM_INTERRUPT:
			if _aliz_speaking:
				_sim_pending = [[0.0, "barge"], [0.4, "partial", _expected_answer.left(2)], [0.9, "final", _expected_answer]]
			else:
				_sim_pending = [[0.0, "start"], [0.6, "final", _expected_answer]]
		_:
			_sim_pending = [[0.0, "start"], [0.6, "final", ""]]


# ---------------------------------------------------------------------------
# The frame
# ---------------------------------------------------------------------------

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	_breath += delta
	# Level: idle breathing while listening, decay after a partial, 0 otherwise.
	if _active and not _muted and (_state == STATE_LISTENING or _state == STATE_CHILD_SPEAKING):
		var floor_level: float = LEVEL_IDLE + 0.04 * sin(_breath * 2.4)
		_level = maxf(_level - LEVEL_DECAY_PER_SEC * delta, floor_level)
	else:
		_level = maxf(_level - LEVEL_DECAY_PER_SEC * delta, 0.0)
	# Simulated audio events.
	if not _sim_pending.is_empty():
		var head: Array = _sim_pending[0]
		head[0] = float(head[0]) - delta
		if float(head[0]) <= 0.0:
			_sim_pending.pop_front()
			_fire_sim(head)
	# Keep the recogniser open while hands-free is on and Aliz is quiet.
	if not _active or _muted or _aliz_speaking or _service_live:
		return
	if not hands_free_available():
		return
	_reopen_in -= delta
	if _reopen_in <= 0.0:
		_open_service_session()


func _fire_sim(event: Array) -> void:
	match String(event[1]):
		"start":
			_had_partial = true
			_set_state(STATE_CHILD_SPEAKING)
			child_speech_started.emit()
		"barge":
			_set_state(STATE_INTERRUPTED)
			barge_in.emit()
			child_speech_started.emit()
		"partial":
			_level = LEVEL_PARTIAL
			partial_transcript.emit(String(event[2]))
		"final":
			_level = LEVEL_PARTIAL * 0.6
			_had_partial = false
			if _active and not _muted:
				_set_state(STATE_LISTENING)
			child_speech_ended.emit(String(event[2]))


# ---------------------------------------------------------------------------
# SpeechService plumbing
# ---------------------------------------------------------------------------

func _bind_service() -> void:
	var speech: Node = _speech_service()
	if speech == null:
		return
	if speech.has_signal("partial_recognized") and not speech.partial_recognized.is_connected(_on_partial):
		speech.partial_recognized.connect(_on_partial)
	if speech.has_signal("recognized") and not speech.recognized.is_connected(_on_recognized):
		speech.recognized.connect(_on_recognized)
	if speech.has_signal("session_ended") and not speech.session_ended.is_connected(_on_service_session_ended):
		speech.session_ended.connect(_on_service_session_ended)
	if speech.has_signal("availability_changed") and not speech.availability_changed.is_connected(_on_availability):
		speech.availability_changed.connect(_on_availability)


func _open_service_session() -> void:
	var speech: Node = _speech_service()
	if speech == null or not speech.has_method("start_listening"):
		return
	_service_live = true
	_had_partial = false
	speech.call("start_listening", _locale())
	# A service that refused synchronously has already ended the session.


func _close_service_session() -> void:
	if not _service_live:
		return
	var speech: Node = _speech_service()
	_service_live = false
	if speech != null and speech.has_method("stop_listening"):
		speech.call("stop_listening")


func _on_partial(text: String) -> void:
	if not _active or not _service_live:
		return
	if not _had_partial:
		_had_partial = true
		_set_state(STATE_CHILD_SPEAKING)
		child_speech_started.emit()
	_level = LEVEL_PARTIAL
	partial_transcript.emit(text)


func _on_recognized(text: String) -> void:
	if not _active or not _service_live:
		return
	if not _had_partial:
		child_speech_started.emit()
	_had_partial = false
	_level = LEVEL_PARTIAL * 0.6
	child_speech_ended.emit(text)


func _on_service_session_ended(_outcome: String) -> void:
	if not _service_live:
		return
	_service_live = false
	_had_partial = false
	if _active and not _muted and not _aliz_speaking:
		_set_state(STATE_LISTENING)
	_reopen_in = REOPEN_GAP_SECONDS


func _on_availability(available: bool) -> void:
	availability_changed.emit(available)
	if _active and not available:
		_close_service_session()
		_set_state(STATE_UNAVAILABLE)


func _set_state(state: String) -> void:
	if _state == state:
		return
	var from: String = _state
	_state = state
	state_changed.emit(from, state)


func _speech_service() -> Node:
	var tree: SceneTree = get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(SPEECH_SERVICE_PATH.trim_prefix("/root/"))


func _locale() -> String:
	var tree: SceneTree = get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var save: Node = tree.root.get_node_or_null("SaveService")
		if save != null and save.has_method("get_setting"):
			return String(save.call("get_setting", "speechLocale", "en-US"))
	return "en-US"
