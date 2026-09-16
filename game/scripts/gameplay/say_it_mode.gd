class_name SayItMode
extends "res://scripts/gameplay/mode_handler.gd"

## Mini-game B -- "Say It".
##
## TTS speaks the word, the object appears, and the Speak button becomes
## available. A transcript is matched with `IntentMatcher.matches()` against the
## task's `acceptedCommands` + `targetWords` -- tolerant phrase matching, and
## deliberately NO pronunciation score, percentage or star rating.
##
## ## The mic is never a gate
##
## Speech is strictly a bonus path. Tapping the object always completes the task
## with the same reward, and `complete_by_touch()` does the same from a button.
## So a child whose microphone is unavailable, denied, broken or simply too shy
## is never stuck and never penalised. `speak_button_enabled` is emitted `false`
## when no speech backend is available so the UI can hide a button that would do
## nothing.
##
## A failed recognition is *not* a failure state: it is answered with "Try
## again!" and the touch path stays live.

const MODE_NAME: String = "sayIt"
const INTENT_MATCHER_SCRIPT_PATH: String = "res://scripts/speech/intent_matcher.gd"

## Shown instead of a score when recognition does not match.
const TOUCH_HINT: String = "You can tap it too!"


func get_mode_name() -> String:
	return MODE_NAME


func _on_start() -> void:
	var target_id: String = get_target_object_id()
	if not target_id.is_empty():
		# Only the target: "Say It" is about the word, not about choosing.
		# Tapping it is the guaranteed touch completion.
		_spawn_choices([target_id])
	# The word on its own, queued after the instruction, so the child hears
	# exactly what to copy without the instruction being cut off.
	_speak(get_target_word(), false)
	speak_button_enabled.emit(_is_speech_available())


func get_target_word() -> String:
	var words: Variant = _task.get("targetWords", null)
	if typeof(words) == TYPE_ARRAY and not (words as Array).is_empty():
		return String((words as Array)[0])
	return ""


## Touch path: tapping the object counts as "I said it". Any other object is
## answered gently -- but in practice only the target is ever on screen.
func _handle_choice(object_id: String) -> void:
	if object_id == get_target_object_id() or object_id.is_empty():
		_succeed()
		return
	_gentle_retry(object_id)


## Speak button. If there is no usable backend we do not leave the child poking a
## dead button -- we point them at the touch path instead.
func request_listen() -> void:
	if not is_active():
		return
	var speech: Object = _speech_service()
	if speech == null or not speech.has_method("start_listening"):
		encouragement.emit(TOUCH_HINT)
		return
	if speech.has_method("is_available") and not bool(speech.call("is_available")):
		encouragement.emit(TOUCH_HINT)
		return
	speech.call("start_listening")


func on_transcript(text: String) -> void:
	if not is_active():
		return
	if matches_task(text, _task):
		_succeed()
		return
	# No score, no "wrong" -- just a kind nudge plus the reminder that touch works.
	_gentle_retry()
	encouragement.emit(TOUCH_HINT)


## Pure wrapper around `IntentMatcher`, loaded by path so this script never
## depends on Godot's global class cache.
static func matches_task(transcript: String, task: Dictionary) -> bool:
	var matcher: GDScript = load(INTENT_MATCHER_SCRIPT_PATH) as GDScript
	if matcher == null:
		return false
	var accepted: Array = []
	if typeof(task.get("acceptedCommands", null)) == TYPE_ARRAY:
		accepted = task.get("acceptedCommands")
	var targets: Array = []
	if typeof(task.get("targetWords", null)) == TYPE_ARRAY:
		targets = task.get("targetWords")
	return bool(matcher.matches(transcript, accepted, targets))
