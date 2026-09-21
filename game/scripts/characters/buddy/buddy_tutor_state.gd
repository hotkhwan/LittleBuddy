extends Node

## ============================================================================
## ALIZ'S TUTOR STATES -- one word from the conversation ("speaking",
## "interrupted", "celebrating"...) becomes a policy across her FOUR layers.
## ============================================================================
##
## The layers never talk to each other; this node talks to all of them through
## `pink_girl_buddy.gd`'s public surface:
##
##   face texture  -- `set_expression()`, plus OVERLAY layers (a brow raise, a
##                    glance) that ride over the expression without changing it
##   mouth frames  -- `set_speaking()`; the amounts come from the LipSyncSource
##   gesture layer -- `play_gesture(name, scale)`, `set_listening_pose()`, the
##                    look toward the attention target, the talk head motion
##   base          -- the idle / seated clip, untouched; it breathes underneath
##
## Blinking is never touched here: it runs in every state.
##
## ## The table
##
##   idle         neutral; not speaking; no gesture; straight ahead
##   listening    listening; lean-in (the held listening posture: spine lean,
##                head tilted 8 degrees); look at the child; hands still (a
##                running arm gesture fades out); not speaking
##   thinking     thinking; the `thinking` gesture on entry (hand under the
##                chin) with the `eyesUpLeft` overlay for its hold; not speaking
##   speaking     smile; speaking; talk head motion; every ~1.8 s a 250 ms brow
##                raise (the `browsUp` layer as an overlay); every ~4.5 s a 400 ms
##                glance (the `eyesUpLeft` overlay); every ~3 s a small hand beat
##                (beatRight / beatLeft / openHands at 0.6 scale)
##   interrupted  set_speaking(false) NOW (the mouth's 90 ms release shuts it,
##                inside the 120 ms the contract allows); the running gesture is
##                stopped (0.2 s fade); listening face at once; head to the
##                attention target; lean-in. Then behaves as `listening`.
##   happy        happy; a half nod on entry
##   encouraging  encouraging; the `encourage` gesture on entry (open palm,
##                small nod)
##   explaining   smile; speaking; `point` on entry, then a half nod every
##                ~2.5 s while `is_speaking()`; brow raises as in speaking
##   celebrating  happy; `celebrate` on entry (arms up, a small bounce); emits
##                `wants_sfx("laugh")` once
##
## The event-driven variety (thumbs up / clap / nod for a correct answer, and
## so on) is not a state: `tutor_gesture_pool.gd` picks a gesture per event
## and the scene plays it through `play_gesture()` over these states.
##
## Periods carry a little jitter (deterministic per entry) so two Alizes never
## nod in step and a child cannot count it. The schedule advances in
## `_process()` -- or by `step(seconds)` for a headless test -- and switches
## itself off in the states that have nothing periodic.

const GestureClips := preload("res://scripts/characters/buddy/buddy_gesture_clips.gd")

const STATE_IDLE: String = "idle"
const STATE_LISTENING: String = "listening"
const STATE_THINKING: String = "thinking"
const STATE_SPEAKING: String = "speaking"
const STATE_INTERRUPTED: String = "interrupted"
const STATE_HAPPY: String = "happy"
const STATE_ENCOURAGING: String = "encouraging"
const STATE_EXPLAINING: String = "explaining"
const STATE_CELEBRATING: String = "celebrating"
const STATES: Array[String] = [
	STATE_IDLE, STATE_LISTENING, STATE_THINKING, STATE_SPEAKING, STATE_INTERRUPTED,
	STATE_HAPPY, STATE_ENCOURAGING, STATE_EXPLAINING, STATE_CELEBRATING,
]

## Seconds.
const BROW_PERIOD: float = 1.8
const BROW_HOLD: float = 0.25
const GLANCE_PERIOD: float = 4.5
const GLANCE_HOLD: float = 0.4
const HAND_PERIOD: float = 3.0
const NOD_PERIOD: float = 2.5
const JITTER: float = 0.15
## Scales handed to `play_gesture()` for the small versions.
const HALF: float = 0.5
const BEAT_SCALE: float = 0.6

const OVERLAY_BROWS: String = "browsUp"
const OVERLAY_GLANCE: String = "eyesUpLeft"
## `thinking`: the gaze goes up-left while the hand is under the chin -- from
## a little after entry (the hand is on its way up) to the end of the hold.
const THINKING_GAZE_FROM: float = 0.2
const THINKING_GAZE_UNTIL: float = 1.3

## Relayed by the wrapper as `wants_sfx(name)`: a hook for the scene's SFX.
signal wants_sfx(name: String)
signal state_changed(previous: String, current: String)

var _buddy: Node = null
var _state: String = STATE_IDLE
var _time: float = 0.0
var _next_brow: float = 0.0
var _next_glance: float = 0.0
var _next_hand: float = 0.0
var _next_nod: float = 0.0
var _brow_until: float = -1.0
var _glance_until: float = -1.0
var _beat_index: int = 0
var _entries: int = 0
## Counters a test reads: how many of each periodic thing fired in this state.
var _fired: Dictionary = {"brow": 0, "glance": 0, "hand": 0, "nod": 0}


func _ready() -> void:
	if _buddy == null:
		var parent: Node = get_parent()
		while parent != null and not parent.has_method("set_expression"):
			parent = parent.get_parent()
		_buddy = parent
	set_process(_is_periodic(_state))


func set_buddy(buddy: Node) -> void:
	_buddy = buddy


func state() -> String:
	return _state


func time_in_state() -> float:
	return _time


func fired() -> Dictionary:
	return _fired.duplicate()


static func is_state(name: String) -> bool:
	return STATES.has(name)


## Applies `name`'s policy now. Returns false for a name outside `STATES`.
func apply(name: String) -> bool:
	if not is_state(name) or _buddy == null:
		return false
	var previous: String = _state
	_state = name
	_time = 0.0
	_entries += 1
	_fired = {"brow": 0, "glance": 0, "hand": 0, "nod": 0}
	_brow_until = -1.0
	_glance_until = -1.0
	_set_overlays([])
	# Scheduling starts a little into the state so the entry gesture has room.
	var j: float = _jitter(_entries)
	_next_brow = 0.9 + j
	_next_glance = 2.0 + j
	_next_hand = 1.4 + j
	_next_nod = 1.6 + j
	match name:
		STATE_IDLE:
			_buddy.call("set_speaking", false)
			_buddy.call("stop_gesture")
			_buddy.call("set_listening_pose", false)
			_look(false)
			_talk(false)
			_buddy.call("set_expression", "neutral")
		STATE_LISTENING:
			_buddy.call("set_speaking", false)
			_talk(false)
			# Hands still: an arm gesture in flight fades out (the head is free).
			if GestureClips.ARM_GESTURES.has(String(_buddy.call("get_current_gesture"))):
				_buddy.call("stop_gesture")
			_buddy.call("set_expression", "listening")
			_buddy.call("set_listening_pose", true)
			_look(true)
		STATE_THINKING:
			_buddy.call("set_speaking", false)
			_talk(false)
			_buddy.call("set_listening_pose", false)
			_look(false)
			_buddy.call("set_expression", "thinking")
			_buddy.call("play_gesture", GestureClips.GESTURE_THINKING)
			_glance_until = THINKING_GAZE_UNTIL
		STATE_SPEAKING:
			_buddy.call("set_listening_pose", false)
			_look(false)
			_buddy.call("set_expression", "smile")
			_buddy.call("set_speaking", true)
			_talk(true)
		STATE_INTERRUPTED:
			# Order matters: the mouth and the gesture first (the timing
			# contract), then the face, then the turn toward the child.
			_buddy.call("set_speaking", false)
			_buddy.call("stop_gesture")
			_talk(false)
			_buddy.call("set_expression", "listening")
			_look(true)
			_buddy.call("set_listening_pose", true)
		STATE_HAPPY:
			_buddy.call("set_listening_pose", false)
			_look(false)
			_talk(false)
			_buddy.call("set_expression", "happy")
			_buddy.call("play_gesture", GestureClips.GESTURE_NOD, HALF)
		STATE_ENCOURAGING:
			_buddy.call("set_listening_pose", false)
			_look(false)
			_talk(false)
			_buddy.call("set_expression", "encouraging")
			_buddy.call("play_gesture", GestureClips.GESTURE_ENCOURAGE)
		STATE_EXPLAINING:
			_buddy.call("set_listening_pose", false)
			_look(false)
			_buddy.call("set_expression", "smile")
			_buddy.call("set_speaking", true)
			_talk(true)
			_buddy.call("play_gesture", GestureClips.GESTURE_POINT)
		STATE_CELEBRATING:
			_buddy.call("set_listening_pose", false)
			_look(false)
			_talk(false)
			_buddy.call("set_expression", "happy")
			_buddy.call("play_gesture", GestureClips.GESTURE_CELEBRATE)
			wants_sfx.emit("laugh")
	set_process(_is_periodic(_state))
	state_changed.emit(previous, _state)
	return true


func _process(delta: float) -> void:
	step(delta)


## Advances the state's schedule by `seconds`. Public for headless tests.
func step(seconds: float) -> void:
	_time += seconds
	if _buddy == null or not _is_periodic(_state):
		return
	var speaking: bool = bool(_buddy.call("is_speaking"))
	if _state == STATE_THINKING:
		# Only the gaze: up-left for the hold of the hand under the chin.
		_set_overlays([OVERLAY_GLANCE] if _time >= THINKING_GAZE_FROM and _time < _glance_until else [])
		return
	# Brows and glance: overlays over whatever the expression is.
	if _time >= _next_brow:
		_brow_until = _time + BROW_HOLD
		_next_brow = _time + BROW_PERIOD + _jitter(_fired["brow"] + 1)
		_fired["brow"] += 1
	if _state == STATE_SPEAKING and _time >= _next_glance:
		_glance_until = _time + GLANCE_HOLD
		_next_glance = _time + GLANCE_PERIOD + _jitter(_fired["glance"] + 3)
		_fired["glance"] += 1
	var overlays: Array = []
	if _time < _brow_until:
		overlays.append(OVERLAY_BROWS)
	if _time < _glance_until:
		overlays.append(OVERLAY_GLANCE)
	_set_overlays(overlays)
	# Hands: a small beat every ~3 s while speaking, never over a running gesture.
	if _state == STATE_SPEAKING and _time >= _next_hand:
		_next_hand = _time + HAND_PERIOD + _jitter(_fired["hand"] + 5)
		if speaking and String(_buddy.call("get_current_gesture")).is_empty():
			var beats: Array = [GestureClips.MICRO_BEAT_RIGHT, GestureClips.MICRO_OPEN_HANDS,
					GestureClips.MICRO_BEAT_LEFT]
			_buddy.call("play_gesture", beats[_beat_index % beats.size()], BEAT_SCALE)
			_beat_index += 1
			_fired["hand"] += 1
	# Explaining: a half nod every ~2.5 s while she is still speaking.
	if _state == STATE_EXPLAINING and _time >= _next_nod:
		_next_nod = _time + NOD_PERIOD + _jitter(_fired["nod"] + 7)
		if speaking and String(_buddy.call("get_current_gesture")) != GestureClips.GESTURE_POINT:
			_buddy.call("play_gesture", GestureClips.GESTURE_NOD, HALF)
			_fired["nod"] += 1


static func _is_periodic(name: String) -> bool:
	return name == STATE_SPEAKING or name == STATE_EXPLAINING or name == STATE_THINKING


## -JITTER..+JITTER, deterministic in `k`, never the same two in a row.
static func _jitter(k: int) -> float:
	return JITTER * sin(float(k) * 12.9898)


func _set_overlays(names: Array) -> void:
	if _buddy.has_method("_set_face_overlays"):
		_buddy.call("_set_face_overlays", names)


func _look(at_target: bool) -> void:
	if _buddy.has_method("_look_at_attention"):
		_buddy.call("_look_at_attention", at_target)


func _talk(active: bool) -> void:
	var layer: SkeletonModifier3D = _buddy.call("get_gesture_layer")
	if layer != null:
		layer.call("set_talk_motion", active)
