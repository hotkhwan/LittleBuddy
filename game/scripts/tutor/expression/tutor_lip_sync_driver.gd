class_name TutorLipSyncDriver
extends RefCounted

## Audio/viseme-to-semantic mouth driver. An adapter blends this output with the
## rig's base mouth expression; it does not replace smile/surprise/thinking.

const ATTACK_SECONDS: float = 0.055
const RELEASE_SECONDS: float = 0.095
const NOISE_FLOOR: float = 0.012
const VISEMES: Array[String] = ["sil", "aa", "ee", "ih", "oh", "oo", "fv", "mbp", "th"]

var _openness: float = 0.0
var _viseme: String = "sil"
var _viseme_weight: float = 0.0


func update_amplitude(amplitude: float, delta: float) -> Dictionary:
	var safe_amplitude: float = clampf(amplitude, 0.0, 1.0) if is_finite(amplitude) else 0.0
	var target: float = 0.0
	if safe_amplitude > NOISE_FLOOR:
		target = clampf((safe_amplitude - NOISE_FLOOR) / (1.0 - NOISE_FLOOR), 0.0, 1.0)
		target = sqrt(target)
	var duration: float = ATTACK_SECONDS if target > _openness else RELEASE_SECONDS
	var weight: float = minf(maxf(delta, 0.0) / duration, 1.0)
	_openness = lerpf(_openness, target, weight)
	return frame()


func apply_viseme(viseme: String, weight: float = 1.0) -> bool:
	if not VISEMES.has(viseme) or not is_finite(weight):
		return false
	_viseme = viseme
	_viseme_weight = clampf(weight, 0.0, 1.0)
	if viseme == "sil":
		_viseme_weight = 0.0
	return true


func reset() -> Dictionary:
	_openness = 0.0
	_viseme = "sil"
	_viseme_weight = 0.0
	return frame()


func frame() -> Dictionary:
	return {
		"openness": _openness,
		"viseme": _viseme,
		"visemeWeight": _viseme_weight,
		"blendMode": "additive_expression_safe",
	}
