class_name TutorExpressionDirector
extends Node

## Provider-neutral presentation policy for Aliz. Consumers translate the emitted
## semantic frame into the existing rig's public face/gesture methods; this class
## never sees skeletons, bones, or animation tracks.

signal presentation_changed(frame: Dictionary)
signal gesture_requested(gesture: String, intensity: float, duration: float)
signal look_requested(target: String, blend_seconds: float)

const EMOTIONS: Array[String] = [
	"neutral", "happy", "proud", "excited", "encouraging",
	"thinking", "listening", "surprised", "gentle", "confused",
]
const GESTURES: Array[String] = [
	"wave", "nod", "clap", "thumbs_up", "celebrate", "encourage",
	"thinking", "listening",
]
const LOOK_TARGETS: Array[String] = ["child", "board", "flashcard", "table", "bookshelf", "prop"]

const DEFAULT_BLEND_SECONDS: float = 0.24
const MIN_BLEND_SECONDS: float = 0.12
const MAX_BLEND_SECONDS: float = 0.8
const GESTURE_COOLDOWN_SECONDS: float = 1.25
const MAX_GESTURES_PER_WINDOW: int = 3
const GESTURE_WINDOW_SECONDS: float = 10.0

const EMOTION_MAP: Dictionary = {
	"neutral": {"face": "neutral", "eyes": "child", "brows": 0.0, "mouth": "neutral", "head": "still"},
	"happy": {"face": "happy", "eyes": "child", "brows": 0.18, "mouth": "smile", "head": "soft_bob"},
	"proud": {"face": "happy", "eyes": "child", "brows": 0.25, "mouth": "smile", "head": "small_nod"},
	"excited": {"face": "happy", "eyes": "child", "brows": 0.55, "mouth": "bright_smile", "head": "bright_bob"},
	"encouraging": {"face": "encouraging", "eyes": "child", "brows": 0.22, "mouth": "soft_smile", "head": "small_nod"},
	"thinking": {"face": "thinking", "eyes": "up_left", "brows": 0.12, "mouth": "thinking", "head": "soft_tilt"},
	"listening": {"face": "listening", "eyes": "child", "brows": 0.25, "mouth": "neutral", "head": "attentive"},
	"surprised": {"face": "surprised", "eyes": "child", "brows": 0.7, "mouth": "surprised", "head": "small_recoil"},
	"gentle": {"face": "encouraging", "eyes": "child", "brows": 0.08, "mouth": "soft_smile", "head": "soft_tilt"},
	"confused": {"face": "thinking", "eyes": "child", "brows": -0.12, "mouth": "uncertain", "head": "soft_tilt"},
}

var _emotion: String = "neutral"
var _intensity: float = 0.0
var _target_intensity: float = 0.0
var _blend_seconds: float = DEFAULT_BLEND_SECONDS
var _clock: float = 0.0
var _last_gesture_at: float = -1000.0
var _gesture_times: Array[float] = []
var _rotation_indices: Dictionary = {}


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	var safe_delta: float = maxf(delta, 0.0)
	_clock += safe_delta
	var weight: float = 1.0 if _blend_seconds <= 0.0 else minf(safe_delta / _blend_seconds, 1.0)
	var previous: float = _intensity
	_intensity = lerpf(_intensity, _target_intensity, weight)
	if not is_equal_approx(previous, _intensity):
		presentation_changed.emit(current_frame())


func set_emotion(emotion: String, intensity: float = 1.0, blend_seconds: float = DEFAULT_BLEND_SECONDS) -> bool:
	if not EMOTIONS.has(emotion) or not is_finite(intensity) or not is_finite(blend_seconds):
		return false
	_emotion = emotion
	_target_intensity = clampf(intensity, 0.0, 1.0)
	_blend_seconds = clampf(blend_seconds, MIN_BLEND_SECONDS, MAX_BLEND_SECONDS)
	presentation_changed.emit(current_frame())
	return true


func play_gesture(gesture: String, intensity: float = 1.0) -> bool:
	if not GESTURES.has(gesture) or not is_finite(intensity):
		return false
	_prune_gesture_times()
	if _clock - _last_gesture_at < GESTURE_COOLDOWN_SECONDS:
		return false
	if _gesture_times.size() >= MAX_GESTURES_PER_WINDOW:
		return false
	var safe_intensity: float = clampf(intensity, 0.15, 1.0)
	_last_gesture_at = _clock
	_gesture_times.append(_clock)
	gesture_requested.emit(gesture, safe_intensity, _gesture_duration(gesture))
	return true


func look_at(target: String) -> bool:
	if not LOOK_TARGETS.has(target):
		return false
	look_requested.emit(target, DEFAULT_BLEND_SECONDS)
	return true


## Stable per-session rotation prevents identical praise/gestures every turn.
func rotate(pool_id: String, values: Array) -> Variant:
	if pool_id.is_empty() or values.is_empty():
		return null
	var index: int = int(_rotation_indices.get(pool_id, 0))
	_rotation_indices[pool_id] = index + 1
	return values[index % values.size()]


func current_frame() -> Dictionary:
	var mapping: Dictionary = (EMOTION_MAP[_emotion] as Dictionary).duplicate(true)
	mapping["emotion"] = _emotion
	mapping["intensity"] = _intensity
	mapping["targetIntensity"] = _target_intensity
	mapping["blendSeconds"] = _blend_seconds
	return mapping


func reset() -> void:
	_emotion = "neutral"
	_intensity = 0.0
	_target_intensity = 0.0
	_clock = 0.0
	_last_gesture_at = -1000.0
	_gesture_times.clear()
	_rotation_indices.clear()
	presentation_changed.emit(current_frame())


func _prune_gesture_times() -> void:
	while not _gesture_times.is_empty() and _clock - _gesture_times[0] >= GESTURE_WINDOW_SECONDS:
		_gesture_times.pop_front()


func _gesture_duration(gesture: String) -> float:
	return 1.5 if gesture in ["clap", "celebrate"] else 0.9
