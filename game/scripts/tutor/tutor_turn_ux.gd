extends RefCounted

## TutorTurnUx -- the small state machine the classroom scene drives for one
## turn of the loop, and the only place that decides what Aliz's face, pose
## and banner do in each state. Pure GDScript; every face call is behind
## `has_method()` so it runs against a stub, Agent C's full face, or nothing.
##
##   state        face / pose                         banner (scene shows it)
##   listening    set_expression("listening"),         "Listening..."
##                set_listening_pose(true)
##   thinking     set_expression("thinking"), nod      "Thinking..."
##   speaking     set_expression(turn.emotion),        turn.subtitle
##                play_gesture(turn.gesture),
##                set_speaking(true)  (mouth from lip sync / text envelope)
##   success      smile + clap                          "Great!"
##   incorrect    encouraging + hint text               "Let's try together!"
##   timeout      "Let's try together!" line + tilt     "Let's try together!"
##   unavailable  offer the offline path                "Let's play with Bunny instead!"
##                (`offline_offered(line, button_text)`: the scene shows a
##                button back to the house)
##   idle         set_speaking(false), pose off
##
## Music ducks while Aliz speaks through `Voice`/`TtsService` already; this
## file adds nothing to audio. Never a red X, never a score: the incorrect and
## timeout states are encouragement plus the lesson's hint.

signal state_changed(from_state: String, to_state: String)
signal banner_changed(text: String)
## The offline path: `line` is what Aliz says, `button_text` the way home.
signal offline_offered(line: String, button_text: String)

const STATE_IDLE: String = "idle"
const STATE_LISTENING: String = "listening"
const STATE_THINKING: String = "thinking"
const STATE_SPEAKING: String = "speaking"
const STATE_SUCCESS: String = "success"
const STATE_INCORRECT: String = "incorrect"
const STATE_TIMEOUT: String = "timeout"
const STATE_UNAVAILABLE: String = "unavailable"
const STATES: Array[String] = [STATE_IDLE, STATE_LISTENING, STATE_THINKING, STATE_SPEAKING, STATE_SUCCESS,
	STATE_INCORRECT, STATE_TIMEOUT, STATE_UNAVAILABLE]

const BANNER_LISTENING: String = "Listening..."
const BANNER_THINKING: String = "Thinking..."
const BANNER_SUCCESS: String = "Great!"
const BANNER_TOGETHER: String = "Let's try together!"
const BANNER_OFFLINE: String = "Let's play with Bunny instead!"
const OFFLINE_LINE: String = "Let's play with Bunny instead!"
const OFFLINE_BUTTON: String = "Back to the house"
const TIMEOUT_LINE: String = "Let's try together!"

var _face: Object = null
var _state: String = STATE_IDLE
var _banner: String = ""
var _history: Array = []
var _last_gesture: String = ""
var _last_expression: String = ""


func set_face(face: Object) -> void:
	_face = face


func face() -> Object:
	return _face


func state() -> String:
	return _state


func banner() -> String:
	return _banner


## States entered so far, in order (evidence and tests).
func history() -> Array:
	return _history.duplicate()


func last_expression() -> String:
	return _last_expression


func last_gesture() -> String:
	return _last_gesture


## Enter a state. `payload` carries the turn for `speaking`, a `hint` for
## `incorrect`, a `line` override for `timeout`.
func enter(next_state: String, payload: Dictionary = {}) -> void:
	if not STATES.has(next_state):
		push_warning("TutorTurnUx: unknown state %s" % next_state)
		return
	var previous: String = _state
	_state = next_state
	_history.append(next_state)
	match next_state:
		STATE_LISTENING:
			_speaking(false)
			_expression("listening")
			_listening_pose(true)
			_set_banner(BANNER_LISTENING)
		STATE_THINKING:
			_listening_pose(false)
			_speaking(false)
			_expression("thinking")
			_gesture("nod")
			_set_banner(BANNER_THINKING)
		STATE_SPEAKING:
			_listening_pose(false)
			var turn: Dictionary = payload.get("turn", {})
			_expression(String(turn.get("emotion", "neutral")))
			_gesture(String(turn.get("gesture", "none")))
			_speaking(true)
			_set_banner(String(turn.get("subtitle", turn.get("speech", ""))))
		STATE_SUCCESS:
			_listening_pose(false)
			_expression("smile")
			_gesture("clap")
			_set_banner(BANNER_SUCCESS)
		STATE_INCORRECT:
			_listening_pose(false)
			_expression("encouraging")
			_gesture("tilt")
			var hint: String = String(payload.get("hint", ""))
			_set_banner(BANNER_TOGETHER if hint.is_empty() else hint)
		STATE_TIMEOUT:
			_listening_pose(false)
			_speaking(false)
			_expression("encouraging")
			_gesture("tilt")
			_set_banner(String(payload.get("line", TIMEOUT_LINE)))
		STATE_UNAVAILABLE:
			_listening_pose(false)
			_speaking(false)
			_expression("smile")
			_gesture("wave")
			_set_banner(BANNER_OFFLINE)
			offline_offered.emit(OFFLINE_LINE, OFFLINE_BUTTON)
		_:
			_listening_pose(false)
			_speaking(false)
			_expression("neutral")
			_set_banner("")
	state_changed.emit(previous, next_state)


## The state a spoken turn lands in once its speech has finished.
static func after_turn_state(turn: Dictionary, phase: String = "answer") -> String:
	var action: String = String(turn.get("lessonAction", "retry"))
	var emotion: String = String(turn.get("emotion", ""))
	if phase == "timeout":
		return STATE_TIMEOUT
	if phase == "open" or phase == "together":
		return STATE_LISTENING if action == "retry" else STATE_IDLE
	if emotion == "happy" and (action == "next_question" or action == "complete"):
		return STATE_SUCCESS
	if action == "retry" or action == "give_hint":
		return STATE_INCORRECT
	return STATE_IDLE


## Maps a recognition terminal to the UX state.
static func state_for_recognition(terminal_state: String) -> String:
	match terminal_state:
		"final": return STATE_THINKING
		"unavailable": return STATE_UNAVAILABLE
		_: return STATE_TIMEOUT


# -- Face calls, all guarded ------------------------------------------------------

func _expression(name: String) -> void:
	_last_expression = name
	if _face == null:
		return
	if _face.has_method("set_expression"):
		_face.call("set_expression", name)
	elif _face.has_method("set_face"):
		_face.call("set_face", name)


func _gesture(name: String) -> void:
	_last_gesture = name
	if _face != null and name != "none" and _face.has_method("play_gesture"):
		_face.call("play_gesture", name)


func _speaking(active: bool) -> void:
	if _face != null and _face.has_method("set_speaking"):
		_face.call("set_speaking", active)


func _listening_pose(active: bool) -> void:
	if _face != null and _face.has_method("set_listening_pose"):
		_face.call("set_listening_pose", active)


func _set_banner(text: String) -> void:
	_banner = text
	banner_changed.emit(text)
