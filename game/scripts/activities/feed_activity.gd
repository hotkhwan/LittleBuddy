extends Node
class_name FeedActivity

## Owns the feedMilk activity state machine.
##
## Touch always completes the activity. Speech (via IntentMatcher/SpeechService)
## is a purely optional accelerant and never gates progress. TTS sequencing
## always races against a SceneTreeTimer safety timeout so the flow can never
## deadlock waiting on a TTS backend that fails to report completion.

enum State { IDLE, HUNGRY, AWAITING_INPUT, PROMPTING_SPEECH, DRINKING, CELEBRATING }

signal state_changed(state: int)
signal activity_completed(activity_id: String, stars: int)
## Emitted whenever a new line of dialogue should be shown in the speech bubble.
signal prompt_changed(text: String)

const SPEECH_WAIT_TIMEOUT_SEC: float = 4.0
const DRINK_DURATION_SEC: float = 1.2
const THANK_YOU_TEXT: String = "Thank you!"

var activity_data: Dictionary = {}
var baby_state: BabyState = null
## Optional; anything responding to set_view_state(String) is accepted (duck typed).
var baby_view: Node = null

var _state: int = State.IDLE
var _step_ready_generation: int = 0

signal _step_ready


func setup(p_baby_state: BabyState, p_baby_view: Node = null) -> void:
	baby_state = p_baby_state
	baby_view = p_baby_view


func get_state() -> int:
	return _state


func get_activity_data() -> Dictionary:
	return activity_data


## Begins (or restarts) the feedMilk activity. If no data is supplied it is
## loaded from bundled content (with a safe hardcoded fallback).
func start(p_activity_data: Dictionary = {}) -> void:
	activity_data = p_activity_data if not p_activity_data.is_empty() else ActivityLoader.load_activity()
	if baby_state == null:
		baby_state = BabyState.new()
	_run_sequence()


func _set_state(new_state: int) -> void:
	_state = new_state
	state_changed.emit(_state)


func _set_baby_view_state(view_state: String) -> void:
	if baby_view != null and baby_view.has_method("set_view_state"):
		baby_view.set_view_state(view_state)


func _is_accepting_state() -> bool:
	return _state == State.HUNGRY or _state == State.AWAITING_INPUT or _state == State.PROMPTING_SPEECH


func _run_sequence() -> void:
	_set_state(State.HUNGRY)
	_set_baby_view_state("hungry")
	await _speak_and_wait(String(activity_data.get("prompt", "I'm hungry.")))

	# The activity may already have been completed by touch/speech while we
	# were waiting for the first line to finish.
	if _state != State.HUNGRY:
		return

	_set_state(State.AWAITING_INPUT)
	await _speak_and_wait(String(activity_data.get("repeatPrompt", "Can you say milk?")))

	if _state != State.AWAITING_INPUT:
		return

	_set_state(State.PROMPTING_SPEECH)


## Races a TtsService.speech_finished signal against a safety timeout so the
## sequence never deadlocks if TTS is unavailable or misbehaves.
func _speak_and_wait(text: String, timeout_sec: float = SPEECH_WAIT_TIMEOUT_SEC) -> void:
	prompt_changed.emit(text)
	_step_ready_generation += 1
	var my_generation: int = _step_ready_generation

	var tts: Node = get_node_or_null("/root/TtsService")
	if tts != null and tts.has_signal("speech_finished") and tts.has_method("speak"):
		if not tts.speech_finished.is_connected(_on_tts_speech_finished):
			tts.speech_finished.connect(_on_tts_speech_finished)
		tts.speak(text)

	var timer: SceneTreeTimer = get_tree().create_timer(timeout_sec)
	timer.timeout.connect(_on_speech_wait_timeout.bind(my_generation), CONNECT_ONE_SHOT)

	await _step_ready


func _on_tts_speech_finished(_text: String) -> void:
	_step_ready.emit()


func _on_speech_wait_timeout(generation: int) -> void:
	if generation != _step_ready_generation:
		return
	_step_ready.emit()


## Called by the scene when the milk bottle is tapped onto the baby, or
## dragged and released over the baby. Always completes the activity while
## in an accepting state — touch must never be blocked by speech state.
func on_milk_delivered() -> void:
	if not _is_accepting_state():
		return
	_complete_feeding()


## Called by the scene with a recognized speech transcript. Purely optional;
## never required for progress.
func on_transcript(text: String) -> void:
	if not _is_accepting_state():
		return
	var accepted_commands: Array = activity_data.get("acceptedCommands", [])
	var target_words: Array = activity_data.get("targetWords", ["milk"])
	if IntentMatcher.matches(text, accepted_commands, target_words):
		_complete_feeding()


func _complete_feeding() -> void:
	if _state == State.DRINKING or _state == State.CELEBRATING:
		return

	_step_ready_generation += 1  # invalidate any pending speech-wait timers
	_set_state(State.DRINKING)
	_set_baby_view_state("drinking")

	if baby_state != null:
		var hunger_relief: float = float(activity_data.get("hungerRelief", 50.0))
		baby_state.feed(hunger_relief)

	var speech: Node = get_node_or_null("/root/SpeechService")
	if speech != null and speech.has_method("stop_listening"):
		speech.stop_listening()

	await get_tree().create_timer(DRINK_DURATION_SEC).timeout
	_celebrate()


func _celebrate() -> void:
	_set_state(State.CELEBRATING)
	_set_baby_view_state("happy")

	var activity_id: String = String(activity_data.get("activityId", "feedMilk"))
	var reward: Dictionary = activity_data.get("reward", {"stars": 1})
	var stars_to_award: int = int(reward.get("stars", 1))

	var thank_you_text: String = String(activity_data.get("thankYouPhrase", THANK_YOU_TEXT))
	_speak_and_wait(thank_you_text)
	activity_completed.emit(activity_id, stars_to_award)

	_set_state(State.IDLE)
